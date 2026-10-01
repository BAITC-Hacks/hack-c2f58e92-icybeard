using Darumen.Modules.RefData;
using Darumen.Shared.Api;
using Darumen.Shared.Auth;

namespace Darumen.Modules.Journal;

public static class JournalEndpoints
{
    public static void Map(IEndpointRouteBuilder api)
    {
        var group = api.MapGroup("/journal").WithTags("Journal");

        group.MapPost("/decisions", async (DecisionRequestDto body, HttpContext http, IDecisionRepository repository, CancellationToken ct) =>
            {
                var errors = new ValidationErrors().Require("subject", body.Subject).Require("subjectId", body.SubjectId);
                if (errors.Any)
                {
                    return errors.Problem();
                }

                if (await DecisionAccess.CheckWriteAsync(http, body) is { } denied)
                {
                    return denied;
                }

                return await DecisionRecording.RecordAsync(http, repository, body.Subject!, body.SubjectId!,
                    body.Recommended?.GetRawText(), body.Chosen?.GetRawText(), body.Reason,
                    decision => $"/api/v1/journal/decisions/{decision.DecisionId}", ct);
            })
            .RequireAuthorization(Permissions.Policy(DecisionAccess.WritePermissions))
            .WithName("RecordDecision").WithSummary("Записать решение человека (рекомендация и выбор): referral.confirm, сценарий симулятора — gov.simulator")
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .Produces<DecisionCreatedDto>(StatusCodes.Status201Created).Produces<DecisionCreatedDto>()
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity);

        group.MapGet("/decisions", async (string? actor, string? subject, string? subjectId, int? page, int? size, HttpContext http, IDecisionRepository repository, CancellationToken ct) =>
            {
                var (who, moCode, problem) = await DecisionAccess.ReadFilterAsync(http, actor);
                if (problem is not null)
                {
                    return problem;
                }

                var (p, s) = Paging.Normalize(page, size);
                return Results.Ok(moCode is null
                    ? await repository.ListAsync(who, subject, subjectId, p, s, ct)
                    : await repository.ListForOrganizationAsync(moCode, who, subject, subjectId, p, s, ct));
            })
            .RequireAuthorization(Permissions.Policy(DecisionAccess.ReadPermissions))
            .WithName("Decisions")
            .WithSummary("Журнал решений: decisions.all — все (при own — своей организации), decisions.own — только свои; subjectId — решения по одному предмету")
            .Produces<Paged<DecisionDto>>().ProducesProblem(StatusCodes.Status403Forbidden);

        group.MapGet("/worklist", async (string? regionKato, string? moCode, string? flag, HttpContext http, IWorklistRepository repository,
                QueuePredictions predictions, IDecisionRepository decisions, CancellationToken ct) =>
            {
                var scope = await OrgAccess.ResolveAsync(http, moCode, Permissions.WorklistView);
                if (scope.Problem is not null)
                {
                    return scope.Problem;
                }

                var user = CurrentUser.From(http);
                var regionScope = RegionAccess.RegionScope(user);
                if (regionScope is not null && regionKato is not null && regionKato != regionScope)
                {
                    return Results.Problem(statusCode: StatusCodes.Status403Forbidden, title: "Регион другого пользователя",
                        detail: "видны только очереди своего региона");
                }

                var region = regionScope ?? regionKato ?? user.RegionKato ?? "75";
                var regionStates = await repository.QueueStatesAsync(region, ct);
                var states = scope.MoCode is null
                    ? regionStates
                    : regionStates.Where(s => string.Equals(s.MoCode, scope.MoCode, StringComparison.OrdinalIgnoreCase)).ToList();
                // задача 10 плана прозрачности: врач, привязанный к отделению/профилю (клейм profile_code), видит
                // только свою очередь — без клейма (как и раньше) видны все профили организации.
                var profileScope = ProfileAccess.ProfileScope(user);
                if (profileScope is not null)
                {
                    states = states.Where(s => s.ProfileCode == profileScope).ToList();
                }

                var asOf = states.Count > 0 ? states[0].AsOf.ToString("yyyy-MM-dd") : string.Empty;
                var (byQueue, modelBacked) = await predictions.ForQueuesAsync(states, ct);
                var routes = await RouteJournal.AllAsync(decisions, ct);
                var names = regionStates.GroupBy(s => s.MoCode).ToDictionary(g => g.Key, g => g.First().MoName);
                var today = RouteJournal.Today(http);

                // состояние маршрута из журнала: завершённые и переведённые в другую больницу уходят из списка,
                // решения и переводы меняют следующий шаг и флаги
                WorklistItemDto? Adjust(WorklistItemDto item)
                {
                    if (!routes.TryGetValue(item.PatientRef, out var route))
                    {
                        return item;
                    }

                    var progress = route.Progress;
                    if (progress.IsClosed || (progress.TransferConfirmed && scope.MoCode is not null))
                    {
                        return null;
                    }

                    var side = scope.MoCode is null ? RouteSide.None : progress.SideOf(RouteAudience.Doctor, scope.MoCode);
                    return WorklistBuilder.Apply(item, progress, side, today, RouteJournal.OpenSignal(route.Decisions, progress, names));
                }

                var transferredIn = scope.MoCode is null ? [] : await TransferredInAsync(repository, routes, scope.MoCode, region, regionStates, names,
                    profileScope, today, ct);
                return Results.Ok(new WorklistResponseDto(WorklistBuilder.Build(states, byQueue, flag, null, Adjust, transferredIn), true, asOf, region,
                    modelBacked));
            })
            .RequireAuthorization(Permissions.Policy(Permissions.WorklistView))
            .WithName("Worklist")
            .WithSummary("Рабочий список: синтетические пациенты на реальных очередях региона с состоянием маршрута из журнала; moCode или "
                + "scope own — очереди организации плюс переведённые в неё пациенты; переведённые в другую больницу и завершённые уходят")
            .Produces<WorklistResponseDto>().ProducesProblem(StatusCodes.Status403Forbidden);

        group.MapGet("/referrals/incoming", async (string? moCode, bool? severe, bool? includeConfirmed, HttpContext http,
                IDecisionRepository decisions, IWorklistRepository worklist, IRefDataRepository refData, CancellationToken ct) =>
            {
                var scope = await OrgAccess.ResolveAsync(http, moCode, Permissions.WorklistView);
                if (scope.Problem is not null)
                {
                    return scope.Problem;
                }

                if (scope.MoCode is null)
                {
                    return Results.Problem(statusCode: StatusCodes.Status422UnprocessableEntity, title: "Нужна организация",
                        detail: "укажите moCode: без организации список входящих направлений не имеет смысла");
                }

                // перевод в эту организацию — по проекции маршрута: отменённые, отклонённые и отказы пациента сюда не попадают
                var routes = await RouteJournal.AllAsync(decisions, ct);
                var today = RouteJournal.Today(http);
                var loadedRegions = new HashSet<string>(StringComparer.Ordinal);
                var names = new Dictionary<string, string>(StringComparer.Ordinal);
                var rows = new List<IncomingReferralDto>();
                foreach (var (reference, route) in routes)
                {
                    var progress = route.Progress;
                    if (progress.Transfer is not { } transfer || !string.Equals(transfer.ToMoCode, scope.MoCode, StringComparison.OrdinalIgnoreCase)
                        || !(progress.TransferActive || progress.TransferConfirmed))
                    {
                        continue;
                    }

                    if (progress.TransferConfirmed && includeConfirmed != true)
                    {
                        continue;
                    }

                    if (severe == true && !transfer.Severe)
                    {
                        continue;
                    }

                    RoutePatientRef.TryParse(reference, out var parsed);
                    if (loadedRegions.Add(parsed!.RegionKato))
                    {
                        foreach (var state in await worklist.QueueStatesAsync(parsed.RegionKato, ct))
                        {
                            names.TryAdd(state.MoCode, state.MoName);
                        }
                    }

                    if (!names.ContainsKey(parsed.MoCode))
                    {
                        foreach (var (code, name) in await RouteJournal.OrganizationNamesAsync(refData, [parsed.MoCode], ct))
                        {
                            names[code] = name;
                        }
                    }

                    var consent = progress.Status == RouteStatuses.TransferPendingConsent ? RouteConsent.Pending
                        : transfer.ConsentAt is not null ? RouteConsent.Accepted : RouteConsent.Pending;
                    rows.Add(new IncomingReferralDto(
                        transfer.DecisionId, reference, parsed.MoCode, names.GetValueOrDefault(parsed.MoCode, parsed.MoCode), parsed.ProfileCode,
                        transfer.Reason, transfer.ProposedAt, transfer.Severe, consent, transfer.ConfirmedAt is not null, transfer.ConfirmedAt,
                        progress.ClosedReason == RouteCloseReasons.Discharged, progress.ClosedReason == RouteCloseReasons.Discharged ? progress.ClosedAt : null,
                        progress.Status, transfer.PlannedAt is { } planned ? RouteEvents.Format(planned) : null, transfer.AdmittedAt is not null,
                        progress.Overdue(today), progress.Allowed(RouteSide.Receiving, today).OrderBy(x => x, StringComparer.Ordinal).ToList(),
                        progress.ClosedReason));
                }

                return Results.Ok(rows.OrderByDescending(r => r.Severe).ThenByDescending(r => r.RecordedAt).ToList());
            })
            .RequireAuthorization(Permissions.Policy(Permissions.WorklistView))
            .WithName("IncomingReferrals")
            .WithSummary("Входящие направления в организацию (переводы от других организаций) с состоянием и доступными действиями: scope own — "
                + "только своя организация; severe=true — только тяжёлые; includeConfirmed=true — и подтверждённые (дата, госпитализация, выписка)")
            .Produces<List<IncomingReferralDto>>().ProducesProblem(StatusCodes.Status403Forbidden).ProducesProblem(StatusCodes.Status422UnprocessableEntity);

        group.MapPost("/referrals/{decisionId:guid}/confirm", (Guid decisionId, ReferralConfirmRequestDto body, HttpContext http,
                IDecisionRepository decisions, CancellationToken ct) =>
                ReceivingActionAsync(http, decisions, decisionId, body.PatientRef, RouteActions.Confirm, (progress, moCode, today) =>
                {
                    var (date, problem) = RouteJournal.PlannedDate(body.PlannedAt, today);
                    return problem is not null ? (null, null, problem) : (RouteEvents.ConfirmJson(moCode, decisionId, date!.Value), RouteJournal.TrimOrNull(body.Comment), null);
                }, ct))
            .RequireAuthorization(Permissions.Policy(Permissions.ReferralConfirm))
            .WithName("ConfirmReferral")
            .WithSummary("Принимающая организация подтверждает приём и назначает дату госпитализации (plannedAt, от сегодня до 30 дней); "
                + "требует согласия пациента; после этого пациент закреплён за принимающей больницей, перевести дальше по этому направлению нельзя")
            .Produces<DecisionCreatedDto>(StatusCodes.Status201Created).Produces<DecisionCreatedDto>()
            .ProducesProblem(StatusCodes.Status403Forbidden).ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status409Conflict).ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity);

        group.MapPost("/referrals/{decisionId:guid}/reject", (Guid decisionId, ReferralReasonRequestDto body, HttpContext http,
                IDecisionRepository decisions, CancellationToken ct) =>
                ReceivingActionAsync(http, decisions, decisionId, body.PatientRef, RouteActions.Reject, (_, moCode, _) =>
                {
                    var errors = new ValidationErrors().Require("reason", body.Reason);
                    return errors.Any ? (null, null, errors.Problem()) : (RouteEvents.RejectJson(moCode, decisionId), body.Reason!.Trim(), null);
                }, ct))
            .RequireAuthorization(Permissions.Policy(Permissions.ReferralConfirm))
            .WithName("RejectReferral")
            .WithSummary("Принимающая организация отказывает в приёме с причиной (нет мест, другой профиль): пациент остаётся в своей очереди, "
                + "эту больницу по направлению больше не предлагают")
            .Produces<DecisionCreatedDto>(StatusCodes.Status201Created).Produces<DecisionCreatedDto>()
            .ProducesProblem(StatusCodes.Status404NotFound).ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity);

        group.MapPost("/referrals/{decisionId:guid}/reschedule", (Guid decisionId, ReferralRescheduleRequestDto body, HttpContext http,
                IDecisionRepository decisions, CancellationToken ct) =>
                ReceivingActionAsync(http, decisions, decisionId, body.PatientRef, RouteActions.Reschedule, (_, moCode, today) =>
                {
                    var errors = new ValidationErrors().Require("reason", body.Reason);
                    if (errors.Any)
                    {
                        return (null, null, errors.Problem());
                    }

                    var (date, problem) = RouteJournal.PlannedDate(body.PlannedAt, today);
                    return problem is not null ? (null, null, problem) : (RouteEvents.RescheduleJson(moCode, decisionId, date!.Value), body.Reason!.Trim(), null);
                }, ct))
            .RequireAuthorization(Permissions.Policy(Permissions.ReferralConfirm))
            .WithName("RescheduleReferral")
            .WithSummary("Принимающая организация переносит дату госпитализации с причиной (те же границы, что при подтверждении)")
            .Produces<DecisionCreatedDto>(StatusCodes.Status201Created).Produces<DecisionCreatedDto>()
            .ProducesProblem(StatusCodes.Status404NotFound).ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity);

        group.MapPost("/referrals/{decisionId:guid}/admit", (Guid decisionId, ReferralReasonRequestDto body, HttpContext http,
                IDecisionRepository decisions, CancellationToken ct) =>
                ReceivingActionAsync(http, decisions, decisionId, body.PatientRef, RouteActions.Admit,
                    (_, moCode, _) => (RouteEvents.AdmitJson(moCode, decisionId), RouteJournal.TrimOrNull(body.Reason), null), ct))
            .RequireAuthorization(Permissions.Policy(Permissions.ReferralConfirm))
            .WithName("AdmitReferral")
            .WithSummary("Принимающая организация отмечает госпитализацию — в назначенную дату или позже")
            .Produces<DecisionCreatedDto>(StatusCodes.Status201Created).Produces<DecisionCreatedDto>()
            .ProducesProblem(StatusCodes.Status404NotFound).ProducesProblem(StatusCodes.Status409Conflict);

        group.MapPost("/referrals/{decisionId:guid}/no-show", (Guid decisionId, ReferralReasonRequestDto body, HttpContext http,
                IDecisionRepository decisions, CancellationToken ct) =>
                ReceivingActionAsync(http, decisions, decisionId, body.PatientRef, RouteActions.NoShow,
                    (_, moCode, _) => (RouteEvents.NoShowJson(moCode, decisionId), RouteJournal.TrimOrNull(body.Reason), null), ct))
            .RequireAuthorization(Permissions.Policy(Permissions.ReferralConfirm))
            .WithName("NoShowReferral")
            .WithSummary("Пациент не явился в назначенную дату — маршрут завершается с этой пометкой (только после даты)")
            .Produces<DecisionCreatedDto>(StatusCodes.Status201Created).Produces<DecisionCreatedDto>()
            .ProducesProblem(StatusCodes.Status404NotFound).ProducesProblem(StatusCodes.Status409Conflict);

        group.MapPost("/referrals/{decisionId:guid}/discharge", (Guid decisionId, DischargeRequestDto body, HttpContext http,
                IDecisionRepository decisions, CancellationToken ct) =>
                ReceivingActionAsync(http, decisions, decisionId, body.PatientRef, RouteActions.Discharge, (_, moCode, _) =>
                {
                    var errors = new ValidationErrors().Require("summary", body.Summary);
                    return errors.Any ? (null, null, errors.Problem()) : (DischargeSummary.Json(moCode, decisionId, body.Summary!.Trim()), null, null);
                }, ct))
            .RequireAuthorization(Permissions.Policy(Permissions.ReferralConfirm))
            .WithName("DischargeReferral")
            .WithSummary("Принимающая организация закрывает лечение и отправляет эпикриз направившему врачу (задача 11); "
                + "только после подтверждения приёма и не раньше даты госпитализации; повторная выписка — 409")
            .Produces<DecisionCreatedDto>(StatusCodes.Status201Created).Produces<DecisionCreatedDto>()
            .ProducesProblem(StatusCodes.Status403Forbidden).ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status409Conflict).ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity);

        group.MapGet("/audit", async (string? actor, string? moCode, int? page, int? size, HttpContext http, IAuditRepository repository, CancellationToken ct) =>
            {
                var scope = await OrgAccess.ResolveAsync(http, moCode, Permissions.AdminUsers);
                if (scope.Problem is not null)
                {
                    return scope.Problem;
                }

                var (p, s) = Paging.Normalize(page, size);
                return Results.Ok(await repository.ListAsync(actor, scope.MoCode, p, s, ct));
            })
            .RequireAuthorization(Permissions.Policy(Permissions.AdminUsers))
            .WithName("Audit").WithSummary("Журнал аудита запросов персонала; scope own — только своей организации").Produces<Paged<AuditEntryDto>>();
    }

    /// <summary>Действие принимающей организации по переводу (подтвердить, отказать, перенести дату, госпитализация, неявка,
    /// выписка): организация из учётной записи, перевод — текущий по проекции маршрута и именно в эту организацию; можно ли
    /// действовать сейчас — по таблице <see cref="RouteProgress.Allowed"/>. Проверка и запись — последовательно по рефу.</summary>
    private static async Task<IResult> ReceivingActionAsync(
        HttpContext http, IDecisionRepository decisions, Guid decisionId, string? patientRef, string action,
        Func<RouteProgress, string, DateOnly, (string? Chosen, string? Reason, IResult? Problem)> build, CancellationToken ct)
    {
        if (await OrgAccess.CheckAsync(http, null, Permissions.ReferralConfirm) is { } denied)
        {
            return denied;
        }

        var moCode = CurrentUser.From(http).MoCode;
        if (string.IsNullOrWhiteSpace(moCode))
        {
            return AccessProblems.Forbidden(AccessProblems.NoOrganization);
        }

        var errors = new ValidationErrors().Require("patientRef", patientRef);
        if (errors.Any)
        {
            return errors.Problem();
        }

        if (!RoutePatientRef.TryParse(patientRef, out var parsed))
        {
            return NotFound();
        }

        var reference = parsed!.Format();
        return await RouteJournal.SerializedAsync(reference, async () =>
        {
            if (await RouteJournal.ReplayAsync(http, decisions, ct) is { } replay)
            {
                return replay;
            }

            var (_, progress) = await RouteJournal.LoadAsync(decisions, parsed, ct);
            if (progress.Transfer is not { } transfer || transfer.DecisionId != decisionId
                                                     || !string.Equals(transfer.ToMoCode, moCode, StringComparison.OrdinalIgnoreCase))
            {
                return NotFound();
            }

            var today = RouteJournal.Today(http);
            if (!progress.Allowed(progress.SideOf(RouteAudience.Doctor, moCode), today).Contains(action))
            {
                return RouteJournal.NotAllowed(action, progress, today);
            }

            var (chosen, reason, problem) = build(progress, moCode, today);
            if (problem is not null)
            {
                return problem;
            }

            return await DecisionRecording.RecordAsync(http, decisions, DecisionSubjects.Route, reference, null, chosen, reason,
                _ => "/api/v1/journal/referrals/incoming", ct);
        });

        static IResult NotFound() => Results.Problem(statusCode: StatusCodes.Status404NotFound, title: "Направление не найдено",
            detail: "нет действующего перевода этого пациента в вашу организацию с таким decisionId");
    }

    /// <summary>Пациенты, переведённые в эту организацию из других очередей (перевод подтверждён, маршрут не завершён):
    /// строка собирается из исходной очереди пациента (возраст ожидания не обнуляется переводом), но больница — принимающая,
    /// ожидаемая дата — назначенная ею.</summary>
    private static async Task<List<WorklistItemDto>> TransferredInAsync(
        IWorklistRepository repository, IReadOnlyDictionary<string, (IReadOnlyList<DecisionDto> Decisions, RouteProgress Progress)> routes,
        string moCode, string region, IReadOnlyList<QueueStateRow> regionStates, IReadOnlyDictionary<string, string> names, string? profileScope,
        DateOnly today, CancellationToken ct)
    {
        var byRegion = new Dictionary<string, IReadOnlyList<QueueStateRow>>(StringComparer.Ordinal) { [region] = regionStates };
        var result = new List<WorklistItemDto>();
        foreach (var (reference, route) in routes)
        {
            var progress = route.Progress;
            if (!progress.TransferConfirmed || progress.IsClosed || !string.Equals(progress.ResponsibleMoCode, moCode, StringComparison.OrdinalIgnoreCase)
                || !RoutePatientRef.TryParse(reference, out var parsed) || (profileScope is not null && parsed!.ProfileCode != profileScope))
            {
                continue;
            }

            if (!byRegion.TryGetValue(parsed!.RegionKato, out var states))
            {
                states = await repository.QueueStatesAsync(parsed.RegionKato, ct);
                byRegion[parsed.RegionKato] = states;
            }

            var origin = states.FirstOrDefault(s => s.MoCode == parsed.MoCode && s.ProfileCode == parsed.ProfileCode);
            if (origin is null)
            {
                continue;
            }

            var item = WorklistBuilder.BuildItem(origin, parsed.Index - 1, WorklistBuilder.Fallback(origin), WorklistBuilder.FastestP50(states, origin.ProfileCode));
            var receivingName = names.GetValueOrDefault(moCode, moCode);
            item = item with { MoCode = moCode, MoName = receivingName, RiskFlags = item.RiskFlags.Where(f => f != WorklistBuilder.FasterAlternative).ToList() };
            result.Add(WorklistBuilder.Apply(item, progress, RouteSide.Receiving, today, RouteJournal.OpenSignal(route.Decisions, progress, names)));
        }

        return result;
    }
}
