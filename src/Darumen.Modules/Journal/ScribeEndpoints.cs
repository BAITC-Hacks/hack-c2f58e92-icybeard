using Darumen.Modules.Queue;
using Darumen.Modules.RefData;
using Darumen.Shared.Api;
using Darumen.Shared.Auth;

namespace Darumen.Modules.Journal;

/// <summary>Согласие пациента на запись приёма AI-скрайбом. Врач запрашивает согласие у пациента своей больницы,
/// пациент отвечает в «Моём пути» (уведомление в колокольчике), и только с действующим согласием врач начинает
/// запись: одно согласие — один приём, в день запроса. Утверждённая памятка привязывается к пациенту и видна ему
/// в «Моём пути». Создание сессии и утверждение идут через API (здесь проверяется согласие), остальные шаги
/// скрайба — напрямую в сервис через прокси, как раньше.</summary>
public static class ScribeEndpoints
{
    private const int HistoryLimit = 500;
    private static readonly string[] Languages = ["ru", "kk"];

    public static void Map(IEndpointRouteBuilder api)
    {
        var consents = api.MapGroup("/scribe-consents").WithTags("Scribe");

        consents.MapGet("", async (string? patientRef, HttpContext http, IWorklistRepository worklist, IDecisionRepository decisions,
                IRefDataRepository refData, CancellationToken ct) =>
            {
                var (parsed, problem) = await DoctorPatientAsync(patientRef, http, worklist, decisions, ct);
                if (problem is not null)
                {
                    return problem;
                }

                var list = await LoadAsync(decisions, parsed!.Format(), http, ct);
                return Results.Ok(await DtosAsync(list, refData, ct));
            })
            .RequireAuthorization(Permissions.Policy(Permissions.ScribeUse))
            .WithName("ScribeConsents")
            .WithSummary("Запросы согласия на запись приёма по пациенту своей больницы, свежие первыми, со статусом (ждёт ответа, дано, отказ, "
                + "отозвано, истекло, идёт запись, памятка у пациента)")
            .Produces<List<ScribeConsentDto>>().ProducesProblem(StatusCodes.Status403Forbidden).ProducesProblem(StatusCodes.Status404NotFound);

        consents.MapPost("", async (ScribeConsentRequestDto body, HttpContext http, IWorklistRepository worklist, IDecisionRepository decisions,
                CancellationToken ct) =>
            {
                var (parsed, problem) = await DoctorPatientAsync(body.PatientRef, http, worklist, decisions, ct);
                if (problem is not null)
                {
                    return problem;
                }

                var reference = parsed!.Format();
                return await RouteJournal.SerializedAsync(Key(reference), async () =>
                {
                    if (await RouteJournal.ReplayAsync(http, decisions, ct) is { } replay)
                    {
                        return replay;
                    }

                    if (ScribeConsents.Active(await LoadAsync(decisions, reference, http, ct)) is { } active)
                    {
                        return Results.Problem(statusCode: StatusCodes.Status409Conflict, title: "Запрос уже отправлен",
                            detail: "у пациента уже есть действующий запрос согласия на сегодня",
                            extensions: new Dictionary<string, object?> { ["requestId"] = active.RequestId, ["status"] = active.Status });
                    }

                    var moCode = CurrentUser.From(http).MoCode ?? parsed.MoCode;
                    return await DecisionRecording.RecordAsync(http, decisions, DecisionSubjects.Scribe, reference, null,
                        ScribeConsents.RequestJson(moCode), RouteJournal.TrimOrNull(body.Comment), _ => $"/api/v1/scribe-consents?patientRef={reference}", ct);
                });
            })
            .RequireAuthorization(Permissions.Policy(Permissions.ScribeUse))
            .WithName("RequestScribeConsent")
            .WithSummary("Попросить у пациента согласие на запись приёма: пациент получает уведомление и отвечает в «Моём пути»; "
                + "один действующий запрос на пациента (409, если уже есть)")
            .Produces<DecisionCreatedDto>(StatusCodes.Status201Created).Produces<DecisionCreatedDto>()
            .ProducesProblem(StatusCodes.Status403Forbidden).ProducesProblem(StatusCodes.Status404NotFound).ProducesProblem(StatusCodes.Status409Conflict);

        consents.MapPost("/{requestId:guid}/cancel", async (Guid requestId, ScribeConsentRequestDto body, HttpContext http, IWorklistRepository worklist,
                IDecisionRepository decisions, CancellationToken ct) =>
            {
                var (parsed, problem) = await DoctorPatientAsync(body.PatientRef, http, worklist, decisions, ct);
                if (problem is not null)
                {
                    return problem;
                }

                var reference = parsed!.Format();
                return await RouteJournal.SerializedAsync(Key(reference), async () =>
                {
                    var consent = (await LoadAsync(decisions, reference, http, ct)).FirstOrDefault(c => c.RequestId == requestId);
                    if (consent is null)
                    {
                        return NotFound();
                    }

                    if (consent.Status is not (ScribeConsentStatuses.Pending or ScribeConsentStatuses.Granted))
                    {
                        return Conflict(consent, "запрос уже закрыт или запись начата — отменить нельзя");
                    }

                    return await DecisionRecording.RecordAsync(http, decisions, DecisionSubjects.Scribe, reference, null,
                        ScribeConsents.AnswerJson(ScribeConsentStatuses.Cancelled, requestId), RouteJournal.TrimOrNull(body.Comment),
                        _ => $"/api/v1/scribe-consents?patientRef={reference}", ct);
                });
            })
            .RequireAuthorization(Permissions.Policy(Permissions.ScribeUse))
            .WithName("CancelScribeConsent")
            .WithSummary("Отменить запрос согласия, пока запись не начата (тело — patientRef)")
            .Produces<DecisionCreatedDto>(StatusCodes.Status201Created).ProducesProblem(StatusCodes.Status404NotFound).ProducesProblem(StatusCodes.Status409Conflict);

        consents.MapPost("/{requestId:guid}/discard", async (Guid requestId, ScribeConsentRequestDto body, HttpContext http, IWorklistRepository worklist,
                IDecisionRepository decisions, IScribeService scribe, CancellationToken ct) =>
            {
                var (parsed, problem) = await DoctorPatientAsync(body.PatientRef, http, worklist, decisions, ct);
                if (problem is not null)
                {
                    return problem;
                }

                var reference = parsed!.Format();
                return await RouteJournal.SerializedAsync(Key(reference), async () =>
                {
                    var consent = (await LoadAsync(decisions, reference, http, ct)).FirstOrDefault(c => c.RequestId == requestId);
                    if (consent is null)
                    {
                        return NotFound();
                    }

                    if (consent.Status != ScribeConsentStatuses.Recording)
                    {
                        return Conflict(consent, "отменить можно только начатую и не утверждённую запись");
                    }

                    try
                    {
                        await scribe.DiscardAsync(consent.SessionId!, ct);
                    }
                    catch (Exception e) when (e is ScribeServiceException or HttpRequestException)
                    {
                        // сервис недоступен: в журнале запись всё равно отменяется, аудио удалится при очистке сервиса
                    }

                    return await DecisionRecording.RecordAsync(http, decisions, DecisionSubjects.Scribe, reference, null,
                        ScribeConsents.AnswerJson(ScribeConsentStatuses.Discarded, requestId), RouteJournal.TrimOrNull(body.Comment),
                        _ => $"/api/v1/scribe-consents?patientRef={reference}", ct);
                });
            })
            .RequireAuthorization(Permissions.Policy(Permissions.ScribeUse))
            .WithName("DiscardScribeRecording")
            .WithSummary("Отменить начатую и не утверждённую запись: аудио и черновик удаляются, для новой записи нужно новое согласие")
            .Produces<DecisionCreatedDto>(StatusCodes.Status201Created).ProducesProblem(StatusCodes.Status404NotFound).ProducesProblem(StatusCodes.Status409Conflict);

        // путь совпадает с прокси скрайба: этот обработчик точнее (литерал сильнее {**rest}), поэтому создать сессию
        // без согласия пациента в обход API нельзя
        api.MapPost("/scribe/sessions", async (ScribeSessionRequestDto body, HttpContext http, IDecisionRepository decisions, IScribeService scribe,
                CancellationToken ct) =>
            {
                var errors = new ValidationErrors();
                if (body.ConsentId is null)
                {
                    errors.Add("consentId", "нужно согласие пациента: сначала запросите его и дождитесь ответа");
                }

                var language = body.Language ?? "ru";
                if (!Languages.Contains(language))
                {
                    errors.Add("language", "ожидается ru или kk");
                }

                if (errors.Any)
                {
                    return errors.Problem();
                }

                var request = await FindRequestAsync(decisions, body.ConsentId!.Value, ct);
                if (request is null)
                {
                    return NotFound();
                }

                var reference = request.SubjectId;
                return await RouteJournal.SerializedAsync(Key(reference), async () =>
                {
                    var consent = (await LoadAsync(decisions, reference, http, ct)).First(c => c.RequestId == body.ConsentId);
                    if (consent.Status != ScribeConsentStatuses.Granted)
                    {
                        return Conflict(consent, consent.Status switch
                        {
                            ScribeConsentStatuses.Pending => "пациент ещё не ответил на запрос согласия",
                            ScribeConsentStatuses.Recording or ScribeConsentStatuses.Completed => "это согласие уже использовано: на новый приём нужно новое",
                            ScribeConsentStatuses.Expired => "согласие действовало только в день запроса — запросите новое",
                            _ => "пациент не дал согласия на запись",
                        });
                    }

                    var user = CurrentUser.From(http);
                    if (consent.MoCode is not null && user.MoCode is not null && !string.Equals(consent.MoCode, user.MoCode, StringComparison.OrdinalIgnoreCase))
                    {
                        return Results.Problem(statusCode: StatusCodes.Status403Forbidden, title: "Согласие дано другой больнице",
                            detail: "пациент дал согласие на запись врачу другой больницы");
                    }

                    string sessionId;
                    try
                    {
                        sessionId = await scribe.CreateSessionAsync(language, user.Actor, reference, ct);
                    }
                    catch (Exception e) when (e is ScribeServiceException or HttpRequestException)
                    {
                        return Unavailable();
                    }

                    await DecisionRecording.RecordAsync(http, decisions, DecisionSubjects.Scribe, reference, null,
                        ScribeConsents.SessionJson(sessionId, consent.RequestId), null, _ => "/api/v1/scribe/sessions", ct);
                    return Results.Created($"/api/v1/scribe/sessions/{sessionId}", new ScribeSessionCreatedDto(sessionId, consent.RequestId, reference));
                });
            })
            .RequireAuthorization(Permissions.Policy(Permissions.ScribeUse))
            .WithTags("Scribe")
            .WithName("CreateScribeSession")
            .WithSummary("Начать запись приёма по действующему согласию пациента (consentId): одно согласие — одна запись в день запроса")
            .Produces<ScribeSessionCreatedDto>(StatusCodes.Status201Created).ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status409Conflict).ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);

        api.MapPost("/scribe/sessions/{sessionId}/approve", async (string sessionId, ScribeApproveRequestDto body, HttpContext http,
                IDecisionRepository decisions, IScribeService scribe, CancellationToken ct) =>
            {
                var errors = new ValidationErrors();
                if (body.Sections is not { Count: > 0 })
                {
                    errors.Add("sections", "обязательное поле");
                }

                errors.Require("patientLeaflet", body.PatientLeaflet);
                if (errors.Any)
                {
                    return errors.Problem();
                }

                var session = await FindSessionAsync(decisions, sessionId, ct);
                if (session is null)
                {
                    return Results.Problem(statusCode: StatusCodes.Status404NotFound, title: "Запись не найдена",
                        detail: "нет записи приёма с таким sessionId, начатой по согласию пациента");
                }

                var (reference, requestId) = session.Value;
                return await RouteJournal.SerializedAsync(Key(reference), async () =>
                {
                    var consent = (await LoadAsync(decisions, reference, http, ct)).First(c => c.RequestId == requestId);
                    if (consent.Status != ScribeConsentStatuses.Recording)
                    {
                        return Conflict(consent, consent.Status == ScribeConsentStatuses.Completed
                            ? "эта запись уже утверждена"
                            : "запись отменена или истекла — для нового приёма нужно новое согласие");
                    }

                    string? token;
                    try
                    {
                        token = await scribe.ApproveAsync(sessionId, body, ct);
                    }
                    catch (ScribeServiceException e) when (e.Status is StatusCodes.Status409Conflict or StatusCodes.Status422UnprocessableEntity)
                    {
                        return Results.Problem(statusCode: e.Status, title: "Запись не утверждена", detail: e.Message);
                    }
                    catch (Exception e) when (e is ScribeServiceException or HttpRequestException)
                    {
                        return Unavailable();
                    }

                    if (token is null)
                    {
                        return Results.Problem(statusCode: StatusCodes.Status404NotFound, title: "Сессия не найдена",
                            detail: "сервис скрайба не знает эту сессию (например, был перезапущен) — начните запись заново");
                    }

                    await DecisionRecording.RecordAsync(http, decisions, DecisionSubjects.Scribe, reference, null,
                        ScribeConsents.LeafletJson(token, requestId, sessionId), null, _ => "/api/v1/scribe/sessions", ct);
                    return Results.Ok(new ScribeApprovedDto(token, true, requestId));
                });
            })
            .RequireAuthorization(Permissions.Policy(Permissions.ScribeUse))
            .WithTags("Scribe")
            .WithName("ApproveScribeSession")
            .WithSummary("Утвердить запись приёма: аудио удаляется, памятка привязывается к пациенту и появляется у него в «Моём пути»")
            .Produces<ScribeApprovedDto>().ProducesProblem(StatusCodes.Status404NotFound).ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity).ProducesProblem(StatusCodes.Status503ServiceUnavailable);

        var me = api.MapGroup("/route/me/scribe").WithTags("Route");

        me.MapGet("", async (string? regionKato, HttpContext http, IWorklistRepository worklist, IRefDataRepository refData,
                IDecisionRepository decisions, QueuePredictions predictions, CancellationToken ct) =>
            {
                var (parsed, _, problem) = await RouteEndpoints.ResolveCitizenAsync(regionKato, http, worklist, refData, predictions, ct);
                if (problem is not null)
                {
                    return Results.Ok(new List<ScribeConsentDto>());
                }

                return Results.Ok(await DtosAsync(await LoadAsync(decisions, parsed!.Format(), http, ct), refData, ct));
            })
            .RequireAuthorization(Permissions.Policy(Permissions.RouteOwn))
            .WithName("MyScribeConsents")
            .WithSummary("Мои запросы согласия на запись приёма и памятки врача (ссылка — leafletToken)")
            .Produces<List<ScribeConsentDto>>();

        me.MapPost("/{requestId:guid}/answer", async (Guid requestId, ScribeConsentAnswerDto body, string? regionKato, HttpContext http,
                IWorklistRepository worklist, IRefDataRepository refData, IDecisionRepository decisions, QueuePredictions predictions, CancellationToken ct) =>
            {
                var (parsed, _, problem) = await RouteEndpoints.ResolveCitizenAsync(regionKato, http, worklist, refData, predictions, ct);
                if (problem is not null)
                {
                    return problem;
                }

                var reference = parsed!.Format();
                return await RouteJournal.SerializedAsync(Key(reference), async () =>
                {
                    if (await RouteJournal.ReplayAsync(http, decisions, ct) is { } replay)
                    {
                        return replay;
                    }

                    var consent = (await LoadAsync(decisions, reference, http, ct)).FirstOrDefault(c => c.RequestId == requestId);
                    if (consent is null)
                    {
                        return NotFound();
                    }

                    // ответить можно на ожидающий запрос; отозвать — данное согласие, пока запись не начата
                    var answer = consent.Status switch
                    {
                        ScribeConsentStatuses.Pending => body.Granted ? ScribeConsentStatuses.Granted : ScribeConsentStatuses.Declined,
                        ScribeConsentStatuses.Granted when !body.Granted => ScribeConsentStatuses.Withdrawn,
                        _ => null,
                    };
                    if (answer is null)
                    {
                        return Conflict(consent, consent.Status switch
                        {
                            ScribeConsentStatuses.Granted => "вы уже дали согласие",
                            ScribeConsentStatuses.Recording or ScribeConsentStatuses.Completed => "запись уже начата — отозвать согласие нельзя",
                            ScribeConsentStatuses.Expired => "запрос истёк: согласие действует только в день приёма",
                            _ => "на этот запрос уже нельзя ответить",
                        });
                    }

                    return await DecisionRecording.RecordAsync(http, decisions, DecisionSubjects.Scribe, reference, null,
                        ScribeConsents.AnswerJson(answer, requestId), null, _ => "/api/v1/route/me/scribe", ct);
                });
            })
            .RequireAuthorization(Permissions.Policy(Permissions.RouteOwn))
            .WithName("AnswerScribeConsent")
            .WithSummary("Ответ на запрос согласия на запись приёма: granted = true — согласен, false — отказ; после согласия, "
                + "пока запись не начата, false отзывает его")
            .Produces<DecisionCreatedDto>(StatusCodes.Status201Created).Produces<DecisionCreatedDto>()
            .ProducesProblem(StatusCodes.Status404NotFound).ProducesProblem(StatusCodes.Status409Conflict);
    }

    /// <summary>Запросы согласия пациента (свёртка журнала) на сегодня по Казахстану.</summary>
    public static async Task<IReadOnlyList<ScribeConsent>> LoadAsync(IDecisionRepository decisions, string reference, HttpContext http, CancellationToken ct)
    {
        var page = await decisions.ListAsync(null, DecisionSubjects.Scribe, reference, 1, HistoryLimit, ct);
        return ScribeConsents.From(page.Items, RouteJournal.Today(http));
    }

    private static async Task<List<ScribeConsentDto>> DtosAsync(IReadOnlyList<ScribeConsent> list, IRefDataRepository refData, CancellationToken ct)
    {
        var names = await RouteJournal.OrganizationNamesAsync(refData, list.Where(c => c.MoCode is not null).Select(c => c.MoCode!), ct);
        return list.Select(c => ScribeConsents.Dto(c, names)).ToList();
    }

    /// <summary>Пациент, с которым работает врач: реф разбирается, пациент есть в очереди, врач из больницы пациента
    /// (или принимающей после подтверждённого перевода) и своего региона.</summary>
    private static async Task<(RoutePatientRef? Parsed, IResult? Problem)> DoctorPatientAsync(
        string? patientRef, HttpContext http, IWorklistRepository worklist, IDecisionRepository decisions, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(patientRef))
        {
            return (null, new ValidationErrors().Add("patientRef", "обязательное поле").Problem());
        }

        if (!RoutePatientRef.TryParse(patientRef, out var parsed))
        {
            return (null, NotFound());
        }

        var states = await worklist.QueueStatesAsync(parsed!.RegionKato, ct);
        if (!RouteEndpoints.Exists(parsed, states))
        {
            return (null, NotFound());
        }

        var scope = RegionAccess.RegionScope(CurrentUser.From(http));
        var (_, progress) = await RouteJournal.LoadAsync(decisions, parsed, ct);
        foreach (var org in RouteJournal.ReaderOrganizations(progress))
        {
            if (await OrgAccess.CheckAsync(http, org, Permissions.WorklistView) is null
                && (scope is null || scope == parsed.RegionKato || org != progress.OriginMoCode))
            {
                return (parsed, null);
            }
        }

        return (null, Results.Problem(statusCode: StatusCodes.Status403Forbidden, title: "Пациент другой больницы",
            detail: "запрашивать согласие и записывать приём может только больница пациента"));
    }

    private static async Task<DecisionDto?> FindRequestAsync(IDecisionRepository decisions, Guid requestId, CancellationToken ct)
    {
        var all = await decisions.ListAsync(null, DecisionSubjects.Scribe, null, 1, RouteJournal.AllRoutesLimit, ct);
        return all.Items.FirstOrDefault(d => d.DecisionId == requestId);
    }

    private static async Task<(string Reference, Guid RequestId)?> FindSessionAsync(IDecisionRepository decisions, string sessionId, CancellationToken ct)
    {
        var all = await decisions.ListAsync(null, DecisionSubjects.Scribe, null, 1, RouteJournal.AllRoutesLimit, ct);
        foreach (var d in all.Items)
        {
            if (d.Chosen is { ValueKind: System.Text.Json.JsonValueKind.Object } chosen
                && chosen.TryGetProperty("scribeSession", out var s) && s.GetString() == sessionId
                && chosen.TryGetProperty("requestId", out var r) && Guid.TryParse(r.GetString(), out var requestId))
            {
                return (d.SubjectId, requestId);
            }
        }

        return null;
    }

    private static string Key(string reference) => "scribe|" + reference;

    private static IResult NotFound() => Results.Problem(statusCode: StatusCodes.Status404NotFound, title: "Не найдено",
        detail: "нет такого пациента или запроса согласия");

    private static IResult Conflict(ScribeConsent consent, string detail) => Results.Problem(statusCode: StatusCodes.Status409Conflict,
        title: "Действие недоступно", detail: detail, extensions: new Dictionary<string, object?> { ["status"] = consent.Status });

    private static IResult Unavailable() => Results.Problem(statusCode: StatusCodes.Status503ServiceUnavailable, title: "Скрайб недоступен",
        detail: "сервис записи приёма не отвечает, попробуйте позже");
}
