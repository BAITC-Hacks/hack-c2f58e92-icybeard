using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Darumen.Modules.Queue;
using Darumen.Modules.RefData;
using Darumen.Shared.Api;
using Darumen.Shared.Auth;

namespace Darumen.Modules.Journal;

/// <summary>Маршрут пациента: /route/me — гражданин видит свой (синтетический) маршрут, отправляет запросы и отвечает на
/// перевод; /route/{patientRef} — врач видит маршрут пациента своей больницы (или переведённого к ним) и решает с причиной.
/// Что кому можно — только по <see cref="RouteProgress"/> (проекция журнала): всё прочее отклоняется 409 с объяснением.
/// Без output cache: ответ зависит от пользователя. Сервис моделей недоступен — маршрут строится по агрегатам витрины
/// (Forecast.FromModel = false), как рабочий список, а не падает 503 через UpstreamExceptionHandler.</summary>
public static class RouteEndpoints
{
    /// <summary>Регион гражданина без клейма region_kato и без параметра — г. Алматы, как у демо-пользователей.</summary>
    public const string DefaultRegion = "75";
    private const int AlternativesLimit = 3;

    public static void Map(IEndpointRouteBuilder api)
    {
        var group = api.MapGroup("/route").WithTags("Route");

        group.MapGet("/me", async (string? regionKato, HttpContext http, IWorklistRepository worklist, IRefDataRepository refData,
                IDecisionRepository decisions, QueueService queueService, QueuePredictions predictions, CancellationToken ct) =>
            {
                var (parsed, states, problem) = await ResolveCitizenAsync(regionKato, http, worklist, refData, predictions, ct);
                if (problem is not null)
                {
                    return problem;
                }

                var (log, progress) = await RouteJournal.LoadAsync(decisions, parsed!, ct);
                return Results.Ok(await BuildAsync(http, parsed!, states!, RouteAudience.Citizen, RouteSide.Citizen, log, progress, refData, queueService, ct));
            })
            .RequireAuthorization(Permissions.Policy(Permissions.RouteOwn))
            .WithName("MyRoute")
            .WithSummary("Мой маршрут: синтетический пациент на реальных очередях региона — стадии Стандарта, прогноз ожидания, чек-лист обследований, "
                + "где быстрее, состояние (перевод, дата от принимающей больницы) и доступные мне действия, хроника решений, история")
            .Produces<RouteDto>().ProducesProblem(StatusCodes.Status404NotFound).ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity);

        group.MapPost("/me/signals", async (RouteSignalRequestDto body, string? regionKato, HttpContext http, IWorklistRepository worklist,
                IRefDataRepository refData, IDecisionRepository decisions, QueuePredictions predictions, CancellationToken ct) =>
            {
                var (parsed, _, problem) = await ResolveCitizenAsync(regionKato, http, worklist, refData, predictions, ct);
                if (problem is not null)
                {
                    return problem;
                }

                var errors = new ValidationErrors().Require("kind", body.Kind);
                if (!errors.Any && !RouteSignals.Kinds.Contains(body.Kind!))
                {
                    errors.Add("kind", $"ожидается один из: {string.Join(", ", RouteSignals.Kinds)}");
                }

                var request = !errors.Any && body.Kind == RouteSignals.RequestRedirect;
                if (request)
                {
                    errors.Require("toMoCode", body.ToMoCode);
                    if (!errors.Any && body.ToMoCode == parsed!.MoCode)
                    {
                        errors.Add("toMoCode", "организация совпадает с текущей");
                    }
                }

                if (errors.Any)
                {
                    return errors.Problem();
                }

                var reference = parsed!.Format();
                return await RouteJournal.SerializedAsync(reference, async () =>
                {
                    if (await RouteJournal.ReplayAsync(http, decisions, ct) is { } replay)
                    {
                        return replay;
                    }

                    var (_, progress) = await RouteJournal.LoadAsync(decisions, parsed, ct);
                    var today = RouteJournal.Today(http);
                    var action = body.Kind switch
                    {
                        RouteSignals.RequestRedirect => RouteActions.RequestTransfer,
                        RouteSignals.PreferCurrent => RouteActions.PreferCurrent,
                        RouteSignals.StillWaiting => RouteActions.StillWaiting,
                        _ => RouteActions.Withdraw,
                    };
                    if (!progress.Allowed(RouteSide.Citizen, today).Contains(action))
                    {
                        return RouteJournal.NotAllowed(action, progress, today);
                    }

                    if (request && progress.RejectedMoCodes.Contains(body.ToMoCode!))
                    {
                        return RouteJournal.Conflict("Больница уже отказала", "эта больница уже отказала в приёме по вашему направлению — выберите другую", progress);
                    }

                    // сигнал — та же запись журнала, что решение врача: recommended = текущая организация, chosen = {"signal", "moCode"?};
                    // комментарий гражданина — в reason, без обработки текста
                    return await DecisionRecording.RecordAsync(http, decisions, DecisionSubjects.Route, reference,
                        MoJson(parsed.MoCode), RouteSignals.Json(body.Kind!, request ? body.ToMoCode : null), RouteJournal.TrimOrNull(body.Comment),
                        _ => "/api/v1/route/me", ct);
                });
            })
            .RequireAuthorization(Permissions.Policy(Permissions.RouteOwn))
            .WithName("MyRouteSignal")
            .WithSummary("Сигнал гражданина по своему маршруту: «ещё жду», «хочу остаться здесь», «уже лечился в другом месте», «больше не нужно» или "
                + "просьба рассмотреть организацию быстрее (toMoCode); во время перевода и после него просить перевод нельзя (409)")
            .Produces<DecisionCreatedDto>(StatusCodes.Status201Created).Produces<DecisionCreatedDto>()
            .ProducesProblem(StatusCodes.Status404NotFound).ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity);

        group.MapPost("/me/consent", async (RouteConsentRequestDto body, string? regionKato, HttpContext http, IWorklistRepository worklist,
                IRefDataRepository refData, IDecisionRepository decisions, QueuePredictions predictions, CancellationToken ct) =>
            {
                var (parsed, _, problem) = await ResolveCitizenAsync(regionKato, http, worklist, refData, predictions, ct);
                if (problem is not null)
                {
                    return problem;
                }

                if (body.DecisionId is null)
                {
                    return new ValidationErrors().Add("decisionId", "обязательное поле").Problem();
                }

                var reference = parsed!.Format();
                return await RouteJournal.SerializedAsync(reference, async () =>
                {
                    if (await RouteJournal.ReplayAsync(http, decisions, ct) is { } replay)
                    {
                        return replay;
                    }

                    // согласие относится к текущему переводу на этом маршруте; ответ на старый или чужой перевод — 404
                    var (_, progress) = await RouteJournal.LoadAsync(decisions, parsed, ct);
                    if (progress.Transfer?.DecisionId != body.DecisionId || progress.TransferConfirmed)
                    {
                        return Results.Problem(statusCode: StatusCodes.Status404NotFound, title: "Решение не найдено",
                            detail: "нет перевода на этом маршруте, ожидающего вашего ответа, с таким decisionId");
                    }

                    var today = RouteJournal.Today(http);
                    var action = body.Accepted ? RouteActions.AcceptTransfer : RouteActions.DeclineTransfer;
                    if (!progress.Allowed(RouteSide.Citizen, today).Contains(action))
                    {
                        return RouteJournal.NotAllowed(action, progress, today);
                    }

                    return await DecisionRecording.RecordAsync(http, decisions, DecisionSubjects.Route, reference,
                        null, RouteConsent.Json(body.Accepted, body.DecisionId!.Value), RouteJournal.TrimOrNull(body.Reason), _ => "/api/v1/route/me", ct);
                });
            })
            .RequireAuthorization(Permissions.Policy(Permissions.RouteOwn))
            .WithName("MyRouteConsent")
            .WithSummary("Согласие или отказ гражданина на перевод; до подтверждения больницей согласие можно отозвать (accepted = false)")
            .Produces<DecisionCreatedDto>(StatusCodes.Status201Created).Produces<DecisionCreatedDto>()
            .ProducesProblem(StatusCodes.Status404NotFound).ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity);

        group.MapGet("/me/notifications", async (string? regionKato, HttpContext http, IWorklistRepository worklist, IRefDataRepository refData,
                IDecisionRepository decisions, QueueService queueService, QueuePredictions predictions, INotificationReadRepository reads,
                CancellationToken ct) =>
            {
                var (parsed, states, problem) = await ResolveCitizenAsync(regionKato, http, worklist, refData, predictions, ct);
                if (problem is not null)
                {
                    // виджет, а не листинг: без маршрута — пустой колокольчик, а не ошибка
                    return Results.Ok(new CitizenNotificationsDto(0, []));
                }

                var (log, progress) = await RouteJournal.LoadAsync(decisions, parsed!, ct);
                var route = await BuildAsync(http, parsed!, states!, RouteAudience.Citizen, RouteSide.Citizen, log, progress, refData, queueService, ct);
                var preferences = http.RequestServices.GetService<IRouteNotificationPreferences>();
                var user = CurrentUser.From(http);
                var routeUpdates = preferences is null || await preferences.RouteUpdatesEnabledAsync(user.UserId, ct);
                var scribe = await ScribeEndpoints.LoadAsync(decisions, parsed!.Format(), http, ct);
                var scribeNames = await RouteJournal.OrganizationNamesAsync(refData, scribe.Where(c => c.MoCode is not null).Select(c => c.MoCode!), ct);
                var items = CitizenNotifications.From(route, progress, routeUpdates, scribe, scribeNames);
                var read = await reads.ReadDecisionIdsAsync(user.Actor, NotificationKinds.Route, items.Select(i => i.Id).ToList(), ct);
                var marked = items.Select(i => i with { Read = read.Contains(i.Id) }).ToList();
                return Results.Ok(new CitizenNotificationsDto(marked.Count(i => !i.Read), marked));
            })
            .RequireAuthorization(Permissions.Policy(Permissions.RouteOwn))
            .WithName("MyRouteNotifications")
            .WithSummary("Колокольчик гражданина: что по его маршруту сделали другие (предложили перевод, оставили, подтвердили дату, отказали, "
                + "перенесли, сняли, выписали) и истекающие до госпитализации анализы; «нужен ваш ответ» показывается всегда, остальное — по настройке route_updates")
            .Produces<CitizenNotificationsDto>();

        group.MapPost("/me/notifications/{id:guid}/read", async (Guid id, HttpContext http, INotificationReadRepository reads, CancellationToken ct) =>
            {
                await reads.MarkReadAsync(CurrentUser.From(http).Actor, NotificationKinds.Route, id, ct);
                return Results.NoContent();
            })
            .RequireAuthorization(Permissions.Policy(Permissions.RouteOwn))
            .WithName("MarkMyRouteNotificationRead")
            .WithSummary("Отметить уведомление гражданина прочитанным; повтор и неизвестный id — тоже 204")
            .Produces(StatusCodes.Status204NoContent);

        group.MapGet("/{patientRef}", async (string patientRef, HttpContext http, IWorklistRepository worklist, IRefDataRepository refData,
                IDecisionRepository decisions, QueueService queueService, CancellationToken ct) =>
            {
                var resolved = await ResolveAsync(patientRef, http, worklist, decisions, Permissions.WorklistView, ct);
                if (resolved.Problem is not null)
                {
                    return resolved.Problem;
                }

                var side = await DoctorSideAsync(http, resolved.Progress!);
                return Results.Ok(await BuildAsync(http, resolved.Parsed!, resolved.States!, RouteAudience.Doctor, side, resolved.Decisions!, resolved.Progress!,
                    refData, queueService, ct));
            })
            .RequireAuthorization(Permissions.Policy(Permissions.WorklistView))
            .WithName("PatientRoute")
            .WithSummary("Маршрут пациента (реф SYN-регион-организация-профиль-NN) с панелью врача: больница пациента, а после подтверждённого "
                + "перевода — и принимающая; состояние и доступные этому врачу действия")
            .Produces<RouteDto>().ProducesProblem(StatusCodes.Status403Forbidden).ProducesProblem(StatusCodes.Status404NotFound);

        group.MapPost("/{patientRef}/redirect", (string patientRef, RouteRedirectRequestDto body, HttpContext http, IWorklistRepository worklist,
                IDecisionRepository decisions, QueueService queueService, CancellationToken ct) =>
                DoctorActionAsync(patientRef, http, worklist, decisions, RouteActions.Redirect, RedirectErrors(patientRef, body), async (resolved, progress) =>
                {
                    if (!progress.CanRedirectTo(body.ToMoCode!))
                    {
                        return (null, null, null, RouteJournal.Conflict("Эту больницу предлагать нельзя",
                            progress.RejectedMoCodes.Contains(body.ToMoCode!)
                                ? "эта больница уже отказала в приёме по этому направлению"
                                : "пациент уже отказался от перевода в эту больницу; предложить её снова можно, если он сам попросит", progress));
                    }

                    var recommended = await RecommendedAsync(resolved.Parsed!, resolved.States!, queueService, ct);
                    return (MoJson(recommended), MoJson(body.ToMoCode!, body.Severe), body.Reason!.Trim(), null);
                }, ct))
            .RequireAuthorization(Permissions.Policy(Permissions.ReferralConfirm))
            .WithName("RedirectRoute")
            .WithSummary("Предложить перевод в другую организацию с причиной: решение (рекомендация системы и выбор врача) уходит в журнал, "
                + "дальше — согласие пациента и подтверждение принимающей больницы; решать может только больница, где пациент стоит в очереди")
            .Produces<DecisionCreatedDto>(StatusCodes.Status201Created).Produces<DecisionCreatedDto>()
            .ProducesProblem(StatusCodes.Status403Forbidden).ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status409Conflict).ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity);

        group.MapPost("/{patientRef}/keep", (string patientRef, RouteKeepRequestDto body, HttpContext http, IWorklistRepository worklist,
                IDecisionRepository decisions, QueueService queueService, CancellationToken ct) =>
                DoctorActionAsync(patientRef, http, worklist, decisions, RouteActions.Keep, ReasonErrors(body.Reason), async (resolved, _) =>
                {
                    // «оставить» — тоже решение с причиной: закрывает запрос гражданина и попадает в журнал как Kind = keep
                    var recommended = await RecommendedAsync(resolved.Parsed!, resolved.States!, queueService, ct);
                    return (MoJson(recommended), MoJson(resolved.Parsed!.MoCode), body.Reason!.Trim(), null);
                }, ct))
            .RequireAuthorization(Permissions.Policy(Permissions.ReferralConfirm))
            .WithName("KeepRoute")
            .WithSummary("Оставить пациента в текущей организации с причиной; решение уходит в журнал (Kind = keep), пациент видит ответ")
            .Produces<DecisionCreatedDto>(StatusCodes.Status201Created).Produces<DecisionCreatedDto>()
            .ProducesProblem(StatusCodes.Status403Forbidden).ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status409Conflict).ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity);

        group.MapPost("/{patientRef}/cancel-transfer", (string patientRef, RouteReasonRequestDto body, HttpContext http, IWorklistRepository worklist,
                IDecisionRepository decisions, CancellationToken ct) =>
                DoctorActionAsync(patientRef, http, worklist, decisions, RouteActions.CancelTransfer, ReasonErrors(body.Reason), (_, progress) =>
                    Task.FromResult<(string?, string?, string?, IResult?)>(
                        (null, RouteEvents.CancelJson(progress.Transfer!.DecisionId), body.Reason!.Trim(), null)), ct))
            .RequireAuthorization(Permissions.Policy(Permissions.ReferralConfirm))
            .WithName("CancelRouteTransfer")
            .WithSummary("Отменить ещё не подтверждённый перевод с причиной: пациент остаётся в своей очереди, принимающая больница перестаёт его видеть")
            .Produces<DecisionCreatedDto>(StatusCodes.Status201Created).Produces<DecisionCreatedDto>()
            .ProducesProblem(StatusCodes.Status403Forbidden).ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity);

        group.MapPost("/{patientRef}/close", (string patientRef, RouteReasonRequestDto body, HttpContext http, IWorklistRepository worklist,
                IDecisionRepository decisions, CancellationToken ct) =>
                DoctorActionAsync(patientRef, http, worklist, decisions, RouteActions.Close, ReasonErrors(body.Reason), (resolved, progress) =>
                {
                    // снимаем по той причине, которую назвал пациент: «уже лечился в другом месте» или «больше не нужно»
                    var signal = resolved.Decisions!.FirstOrDefault(d => d.DecisionId == progress.OpenSignalId);
                    var closes = signal is not null && RouteEvents.Parse(signal).Value == RouteSignals.TreatedElsewhere
                        ? RouteEvents.ClosedTreatedElsewhere
                        : RouteEvents.ClosedWithdrawn;
                    return Task.FromResult<(string?, string?, string?, IResult?)>((null, RouteEvents.CloseJson(closes), body.Reason!.Trim(), null));
                }, ct))
            .RequireAuthorization(Permissions.Policy(Permissions.ReferralConfirm))
            .WithName("CloseRoute")
            .WithSummary("Подтвердить снятие пациента с листа ожидания по его просьбе (до перевода — больница пациента, после — принимающая)")
            .Produces<DecisionCreatedDto>(StatusCodes.Status201Created).Produces<DecisionCreatedDto>()
            .ProducesProblem(StatusCodes.Status403Forbidden).ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity);
    }

    private static IResult? ReasonErrors(string? reason)
    {
        var errors = new ValidationErrors().Require("reason", reason);
        return errors.Any ? errors.Problem() : null;
    }

    private static IResult? RedirectErrors(string patientRef, RouteRedirectRequestDto body)
    {
        var errors = new ValidationErrors().Require("toMoCode", body.ToMoCode).Require("reason", body.Reason);
        if (!errors.Any && RoutePatientRef.TryParse(patientRef, out var parsed)
                        && string.Equals(body.ToMoCode, parsed!.MoCode, StringComparison.OrdinalIgnoreCase))
        {
            errors.Add("toMoCode", "организация совпадает с текущей");
        }

        return errors.Any ? errors.Problem() : null;
    }

    /// <summary>Реф синтетического пациента гражданина — тот же, что на /route/me (для журнала «кто смотрел мой маршрут»);
    /// null — в регионе нет очередей.</summary>
    public static async Task<string?> CitizenPatientRefAsync(HttpContext http, IWorklistRepository worklist, IRefDataRepository refData,
        QueuePredictions predictions, CancellationToken ct)
    {
        var (parsed, _, _) = await ResolveCitizenAsync(null, http, worklist, refData, predictions, ct);
        return parsed?.Format();
    }

    /// <summary>Решение врача по маршруту (оставить, перевести, отменить перевод, снять с очереди): доступ к маршруту, сторона —
    /// больница пациента (или принимающая для снятия после перевода), разрешено ли действие сейчас; проверка и запись —
    /// последовательно по рефу. build возвращает recommended, chosen, reason или ошибку ввода.</summary>
    private static async Task<IResult> DoctorActionAsync(
        string patientRef, HttpContext http, IWorklistRepository worklist, IDecisionRepository decisions, string action, IResult? invalid,
        Func<Resolved, RouteProgress, Task<(string? Recommended, string? Chosen, string? Reason, IResult? Problem)>> build, CancellationToken ct)
    {
        if (!RoutePatientRef.TryParse(patientRef, out var parsed))
        {
            return NotFound();
        }

        return await RouteJournal.SerializedAsync(parsed!.Format(), async () =>
        {
            var resolved = await ResolveAsync(patientRef, http, worklist, decisions, Permissions.ReferralConfirm, ct);
            if (resolved.Problem is not null)
            {
                return resolved.Problem;
            }

            // ошибки ввода — раньше повтора и состояния: 422 «заполните причину» понятнее, чем 409 о состоянии
            if (invalid is not null)
            {
                return invalid;
            }

            if (await RouteJournal.ReplayAsync(http, decisions, ct) is { } replay)
            {
                return replay;
            }

            var progress = resolved.Progress!;
            var side = await DoctorSideAsync(http, progress);
            if (side is not (RouteSide.Origin or RouteSide.Receiving))
            {
                return Results.Problem(statusCode: StatusCodes.Status403Forbidden, title: "Решает больница пациента",
                    detail: "решение по маршруту принимает больница, где пациент стоит в очереди, а после перевода — принимающая больница");
            }

            var today = RouteJournal.Today(http);
            if (!progress.Allowed(side, today).Contains(action))
            {
                return RouteJournal.NotAllowed(action, progress, today);
            }

            var (recommended, chosen, reason, problem) = await build(resolved, progress);
            if (problem is not null)
            {
                return problem;
            }

            var reference = resolved.Parsed!.Format();
            return await DecisionRecording.RecordAsync(http, decisions, DecisionSubjects.Route, reference, recommended, chosen, reason,
                _ => $"/api/v1/route/{reference}", ct);
        });
    }

    /// <summary>Сторона врача на маршруте: по своей организации (больница пациента или принимающая); без совпадения —
    /// по охвату разрешения referral.confirm (матрица ролей может дать «все организации»): до подтверждённого перевода
    /// такой врач решает за больницу пациента, после — за принимающую. Без referral.confirm — только просмотр.</summary>
    private static async Task<RouteSide> DoctorSideAsync(HttpContext http, RouteProgress progress)
    {
        var user = CurrentUser.From(http);
        var side = progress.SideOf(RouteAudience.Doctor, user.MoCode);
        if (side != RouteSide.None)
        {
            return await OrgAccess.CheckAsync(http, null, Permissions.ReferralConfirm) is null ? side : RouteSide.None;
        }

        if (!string.IsNullOrWhiteSpace(user.MoCode))
        {
            // сотрудник другой больницы — не сторона этого маршрута, даже если его разрешение referral.confirm без ограничений
            return RouteSide.None;
        }

        // без своей организации (администратор системы) — действует за ответственную больницу
        var responsible = progress.TransferConfirmed ? progress.ResponsibleMoCode : progress.OriginMoCode;
        if (await OrgAccess.CheckAsync(http, responsible, Permissions.ReferralConfirm) is not null)
        {
            return RouteSide.None;
        }

        return progress.TransferConfirmed ? RouteSide.Receiving : RouteSide.Origin;
    }

    /// <summary>Рекомендация системы для журнала — самая быстрая альтернатива по модели; без модели рекомендацией
    /// остаётся текущая организация.</summary>
    private static async Task<string> RecommendedAsync(RoutePatientRef parsed, IReadOnlyList<QueueStateRow> states, QueueService queueService, CancellationToken ct)
    {
        var state = states.First(s => s.MoCode == parsed.MoCode && s.ProfileCode == parsed.ProfileCode);
        var alternatives = await TryAsync(() => queueService.AlternativesAsync(AlternativesRequest(state, 1), ct));
        return alternatives is { Items.Count: > 0 } ? alternatives.Items[0].Mo.MoCode : parsed.MoCode;
    }

    /// <summary>Персона гражданина: та же популяция и те же кэшированные прогнозы, что в рабочем списке врача
    /// (QueuePredictions) — гражданин один из пациентов списка. Сид — ИИН из клейма (не сохраняется, только хешируется),
    /// иначе учётная запись: реф не меняется при смене логина того же человека. Если гражданин уже действовал по маршруту
    /// (есть записи в журнале), он закреплён за этим маршрутом: перевод, другой прогноз или отключённая модель не должны
    /// «подменить» ему пациента.</summary>
    internal static async Task<(RoutePatientRef? Parsed, IReadOnlyList<QueueStateRow>? States, IResult? Problem)> ResolveCitizenAsync(
        string? regionKato, HttpContext http, IWorklistRepository worklist, IRefDataRepository refData, QueuePredictions predictions, CancellationToken ct)
    {
        var user = CurrentUser.From(http);
        var region = user.RegionKato ?? regionKato ?? DefaultRegion;
        var errors = new ValidationErrors().Kato("regionKato", region);
        if (errors.Any)
        {
            return (null, null, errors.Problem());
        }

        var states = await worklist.QueueStatesAsync(region, ct);
        // закрепление только по собственным действиям гражданина (роль citizen): решения врача по чужим пациентам
        // не должны делать «Моим путём» чужой маршрут
        if (http.RequestServices.GetService<IDecisionRepository>() is { } decisions
            && (await decisions.ListAsync(user.Actor, DecisionSubjects.Route, null, 1, 5, ct)).Items
                .FirstOrDefault(d => string.Equals(d.Role, RouteAudience.Citizen, StringComparison.OrdinalIgnoreCase)) is { } last
            && RoutePatientRef.TryParse(last.SubjectId, out var pinned) && pinned!.RegionKato == region && Exists(pinned, states))
        {
            return (pinned, states, null);
        }

        var (byQueue, _) = await predictions.ForQueuesAsync(states, ct);
        var population = WorklistBuilder.Build(states, byQueue);
        if (population.Count == 0)
        {
            return (null, null, Results.Problem(statusCode: StatusCodes.Status404NotFound, title: "Нет очередей в регионе",
                detail: $"в регионе {region} нет активных очередей на дату среза витрины"));
        }

        var excludedProfiles = RouteBuilder.ExcludedProfiles(await refData.ProfilesAsync(ct));
        RoutePatientRef.TryParse(RouteBuilder.PickPatientRef(population, user.Iin ?? user.Actor, excludedProfiles), out var parsed);
        return (parsed, states, null);
    }

    internal static bool Exists(RoutePatientRef parsed, IReadOnlyList<QueueStateRow> states)
    {
        var state = states.FirstOrDefault(s => s.MoCode == parsed.MoCode && s.ProfileCode == parsed.ProfileCode);
        return state is not null && parsed.Index <= WorklistBuilder.CountFor(state, states.Sum(s => s.QueueLen));
    }

    private sealed record Resolved(
        RoutePatientRef? Parsed, IReadOnlyList<QueueStateRow>? States, IReadOnlyList<DecisionDto>? Decisions, RouteProgress? Progress, IResult? Problem);

    /// <summary>Разбор рефа, существование пациента в очереди и доступ: больница из рефа (scope own) в своём регионе — или,
    /// после подтверждённого перевода, принимающая больница (она теперь отвечает за пациента, в том числе из соседнего региона).</summary>
    private static async Task<Resolved> ResolveAsync(
        string patientRef, HttpContext http, IWorklistRepository worklist, IDecisionRepository decisions, string permission, CancellationToken ct)
    {
        if (!RoutePatientRef.TryParse(patientRef, out var parsed))
        {
            return new Resolved(null, null, null, null, NotFound());
        }

        var states = await worklist.QueueStatesAsync(parsed!.RegionKato, ct);
        if (!Exists(parsed, states))
        {
            return new Resolved(null, null, null, null, Results.Problem(statusCode: StatusCodes.Status404NotFound, title: "Пациент не найден",
                detail: "в этой очереди нет пациента с таким номером на дату среза витрины"));
        }

        var (log, progress) = await RouteJournal.LoadAsync(decisions, parsed, ct);
        var originDenied = await OrgAccess.CheckAsync(http, parsed.MoCode, permission);
        var scope = RegionAccess.RegionScope(CurrentUser.From(http));
        if (originDenied is null && (scope is null || scope == parsed.RegionKato))
        {
            return new Resolved(parsed, states, log, progress, null);
        }

        // принимающая больница после подтверждённого перевода — без привязки к региону рефа
        if (progress.TransferConfirmed && await OrgAccess.CheckAsync(http, progress.ResponsibleMoCode, permission) is null)
        {
            return new Resolved(parsed, states, log, progress, null);
        }

        if (originDenied is not null)
        {
            return new Resolved(null, null, null, null, originDenied);
        }

        return new Resolved(null, null, null, null, Results.Problem(statusCode: StatusCodes.Status403Forbidden, title: "Пациент другого региона",
            detail: "врач видит маршруты пациентов только своего региона"));
    }

    private static IResult NotFound() => Results.Problem(statusCode: StatusCodes.Status404NotFound, title: "Пациент не найден",
        detail: "ожидается реф вида SYN-регион-организация-профиль-NN");

    private static async Task<RouteDto> BuildAsync(
        HttpContext http, RoutePatientRef parsed, IReadOnlyList<QueueStateRow> states, string audience, RouteSide side,
        IReadOnlyList<DecisionDto> log, RouteProgress progress, IRefDataRepository refData, QueueService queueService, CancellationToken ct)
    {
        var lang = Locale.From(http.Request);
        var state = states.First(s => s.MoCode == parsed.MoCode && s.ProfileCode == parsed.ProfileCode);
        var predictTask = TryAsync(() => queueService.PredictAsync(PredictRequest(state), lang, ct));
        var alternativesTask = TryAsync(() => queueService.AlternativesAsync(AlternativesRequest(state, AlternativesLimit), ct));
        var standardTask = refData.RouteStandardAsync(lang, ct);
        var profilesTask = refData.ProfilesAsync(ct);
        await Task.WhenAll(predictTask, alternativesTask, standardTask, profilesTask);

        var prediction = predictTask.Result;
        var queuePrediction = prediction is null
            ? WorklistBuilder.Fallback(state)
            : new QueuePrediction(prediction.P50Days, prediction.P90Days, prediction.PRefusal, true);
        var item = WorklistBuilder.BuildItem(state, parsed.Index - 1, queuePrediction, WorklistBuilder.FastestP50(states, state.ProfileCode));
        var profileNames = profilesTask.Result.GroupBy(p => p.ProfileCode).ToDictionary(g => g.Key, g => g.First().Name);

        // названия второй стороны перевода, которой может не быть ни в очередях региона, ни в альтернативах
        var known = states.Select(s => s.MoCode).Concat(alternativesTask.Result?.Items.Select(a => a.Mo.MoCode) ?? []).ToHashSet(StringComparer.Ordinal);
        var wanted = new[] { progress.Transfer?.ToMoCode, progress.LastAttempt?.ToMoCode, progress.ResponsibleMoCode }
            .Concat(log.Select(d => RouteEvents.Parse(d).MoCode))
            .Where(code => code is not null && !known.Contains(code)).Select(code => code!);
        var extraNames = await RouteJournal.OrganizationNamesAsync(refData, wanted, ct);

        return RouteBuilder.Build(new RouteBuilder.Inputs(
            item, state, states, standardTask.Result, prediction, alternativesTask.Result, log, profileNames, audience, lang,
            DateTimeOffset.UtcNow, progress, side, RouteJournal.Today(http), extraNames));
    }

    /// <summary>Категориальные признаки запроса неизвестны для синтетического пациента — не выдумываем диагноз (Icd10 = null),
    /// дата регистрации — срез витрины, как в рабочем списке.</summary>
    private static PredictRequestDto PredictRequest(QueueStateRow state) =>
        new(state.RegionKato, state.MoCode, state.ProfileCode, null, null, null, null, state.AsOf.ToString("yyyy-MM-dd"), null);

    private static AlternativesRequestDto AlternativesRequest(QueueStateRow state, int limit) =>
        new(state.RegionKato, state.MoCode, state.ProfileCode, null, null, null, null, state.AsOf.ToString("yyyy-MM-dd"), limit, null);

    /// <summary>Сервис моделей недоступен или организация не распознана — как в JournalEndpoints.PredictForQueuesAsync:
    /// маршрут строится по агрегатам витрины, а не отдаёт 503.</summary>
    private static async Task<T?> TryAsync<T>(Func<Task<T>> call) where T : class
    {
        try
        {
            return await call();
        }
        catch (Exception e) when (e is not OperationCanceledException)
        {
            return null;
        }
    }

    private static string MoJson(string moCode) => JsonSerializer.Serialize(new { moCode });

    /// <summary>chosen решения redirect: moCode всегда, severe — только когда врач пометил случай тяжёлым (клинический флаг,
    /// не путать с очередными RiskFlags в WorklistBuilder).</summary>
    private static string MoJson(string moCode, bool severe) =>
        severe ? JsonSerializer.Serialize(new { moCode, severe = true }) : MoJson(moCode);
}

/// <summary>Настройка гражданина «Изменения моего маршрута» (событие route_updates на странице «Уведомления»): реализует
/// модуль Access, где хранятся настройки; без реализации уведомления включены.</summary>
public interface IRouteNotificationPreferences
{
    Task<bool> RouteUpdatesEnabledAsync(string userId, CancellationToken cancellationToken);
}

/// <summary>Уведомление гражданина: Kind — <see cref="CitizenNotifications"/>; NeedsAction — нужен его ответ (предложен перевод);
/// Count — для истекающих анализов.</summary>
public sealed record CitizenNotificationDto(
    Guid Id, string Kind, DateTimeOffset At, string? MoName, string? PlannedAt, string? Reason, bool NeedsAction, bool Read, int? Count = null);

public sealed record CitizenNotificationsDto(int Unread, IReadOnlyList<CitizenNotificationDto> Items);

/// <summary>Что попадает в колокольчик гражданина: только действия других людей по его маршруту (свои запросы и ответы — нет)
/// и анализы, которые истекут до госпитализации. «Нужен ваш ответ» на перевод нельзя выключить настройкой — иначе он
/// пропустит решение о своей госпитализации.</summary>
public static class CitizenNotifications
{
    public const string TestsExpiring = "tests_expiring";

    /// <summary>Врач просит согласие на запись приёма — нужен ответ, выключить нельзя.</summary>
    public const string ScribeConsent = "scribe_consent";

    /// <summary>Врач утвердил запись приёма — памятка у пациента.</summary>
    public const string ScribeLeaflet = "scribe_leaflet";

    private static readonly HashSet<string> FromOthers = new(StringComparer.Ordinal)
    {
        RouteJournalKinds.Redirect, RouteJournalKinds.Keep, RouteJournalKinds.Cancel, RouteJournalKinds.Confirm, RouteJournalKinds.Reject,
        RouteJournalKinds.Reschedule, RouteJournalKinds.Admit, RouteJournalKinds.NoShow, RouteJournalKinds.Discharge, RouteJournalKinds.Close,
    };

    public static IReadOnlyList<CitizenNotificationDto> From(
        RouteDto route, RouteProgress progress, bool routeUpdates, IReadOnlyList<ScribeConsent>? scribe = null,
        IReadOnlyDictionary<string, string>? names = null)
    {
        var items = new List<CitizenNotificationDto>();
        foreach (var consent in scribe ?? [])
        {
            var moName = consent.MoCode is null ? null : names?.GetValueOrDefault(consent.MoCode, consent.MoCode) ?? consent.MoCode;
            if (consent.Status == ScribeConsentStatuses.Pending)
            {
                items.Add(new CitizenNotificationDto(consent.RequestId, ScribeConsent, consent.RequestedAt, moName, null, consent.Comment, true, false));
            }
            else if (consent.Status == ScribeConsentStatuses.Completed && routeUpdates && consent.LeafletToken is { } token)
            {
                // отдельный id: отметка «прочитано» у запроса и у памятки своя
                var id = new Guid(MD5.HashData(Encoding.UTF8.GetBytes("scribe-leaflet|" + token)));
                items.Add(new CitizenNotificationDto(id, ScribeLeaflet, consent.ApprovedAt ?? consent.RequestedAt, moName, null, null, false, false));
            }
        }

        foreach (var entry in route.Journal ?? [])
        {
            if (!FromOthers.Contains(entry.Kind))
            {
                continue;
            }

            var needsAction = entry.Kind == RouteJournalKinds.Redirect && progress.Status == RouteStatuses.TransferPendingConsent
                              && progress.Transfer?.DecisionId == entry.Id;
            if (routeUpdates || needsAction)
            {
                items.Add(new CitizenNotificationDto(entry.Id, entry.Kind, entry.At, entry.MoName, entry.PlannedAt, entry.Reason, needsAction, false));
            }
        }

        // анализы, срок которых истечёт к дате госпитализации (или уже истёк), пока маршрут не завершён и пациент не в больнице
        var expiring = route.Checklist.Where(c => c.Status is RouteChecklistStatus.Expiring or RouteChecklistStatus.Expired).ToList();
        if (routeUpdates && expiring.Count > 0 && progress.Status is not (RouteStatuses.Admitted or RouteStatuses.Closed))
        {
            var key = $"{route.PatientRef}|tests|{string.Join(",", expiring.Select(c => c.Code + ":" + c.Status))}|{route.Dates.PlannedAt ?? route.Dates.ExpectedAt}";
            var id = new Guid(MD5.HashData(Encoding.UTF8.GetBytes(key)));
            items.Add(new CitizenNotificationDto(id, TestsExpiring, DateTimeOffset.UtcNow, null, route.Dates.PlannedAt ?? route.Dates.ExpectedAt, null, false,
                false, expiring.Count));
        }

        return items.OrderByDescending(i => i.NeedsAction).ThenByDescending(i => i.At).ToList();
    }
}
