using Darumen.Shared.Api;
using Darumen.Shared.Auth;

namespace Darumen.Modules.Journal;

public static class JournalEndpoints
{
    /// <summary>Сколько решений по маршрутам читать для флагов сигналов в рабочем списке: журнал маршрутов на кэмпе
    /// исчисляется десятками записей, одной страницы хватает.</summary>
    private const int RouteDecisionsPage = 500;

    /// <summary>Сколько решений по одному маршруту читать для вычисления согласия пациента/подтверждения принимающей
    /// организации по конкретному направлению — как DecisionsLimit в RouteEndpoints (один маршрут — считаные записи).</summary>
    private const int ReferralHistoryLimit = 20;

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
                var states = await ForOrganizationAsync(repository, region, scope.MoCode, ct);
                // задача 10 плана прозрачности: врач, привязанный к отделению/профилю (клейм profile_code), видит
                // только свою очередь — без клейма (как и раньше) видны все профили организации.
                var profileScope = ProfileAccess.ProfileScope(user);
                if (profileScope is not null)
                {
                    states = states.Where(s => s.ProfileCode == profileScope).ToList();
                }

                var asOf = states.Count > 0 ? states[0].AsOf.ToString("yyyy-MM-dd") : string.Empty;
                var (byQueue, modelBacked) = await predictions.ForQueuesAsync(states, ct);
                // открытые сигналы граждан: решения по маршрутам немногочисленны (только по рефам региона), одна страница
                var routeDecisions = await decisions.ListAsync(null, DecisionSubjects.Route, null, 1, RouteDecisionsPage, ct);
                var names = states.GroupBy(s => s.MoCode).ToDictionary(g => g.Key, g => g.First().MoName);
                var regional = routeDecisions.Items.Where(d => d.SubjectId.StartsWith($"SYN-{region}-", StringComparison.Ordinal)).ToList();
                var signals = RouteSignals.Open(regional, names);
                return Results.Ok(new WorklistResponseDto(WorklistBuilder.Build(states, byQueue, flag, signals), true, asOf, region, modelBacked));
            })
            .RequireAuthorization(Permissions.Policy(Permissions.WorklistView))
            .WithName("Worklist")
            .WithSummary("Рабочий список: синтетические пациенты на реальных очередях региона; moCode или scope own — только очереди организации")
            .Produces<WorklistResponseDto>().ProducesProblem(StatusCodes.Status403Forbidden);

        group.MapGet("/referrals/incoming", async (string? moCode, bool? severe, bool? includeConfirmed, HttpContext http,
                IDecisionRepository decisions, IWorklistRepository worklist, CancellationToken ct) =>
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

                // redirect в эту организацию: chosen.moCode == своя организация, отправитель — другая (из рефа), это не
                // сигнал гражданина и не сама запись согласия/подтверждения (у них другая форма chosen)
                var candidates = (await decisions.ListForOrganizationAsync(scope.MoCode, null, DecisionSubjects.Route, null, 1, RouteDecisionsPage, ct)).Items
                    .Where(d => RouteSignals.MoCode(d.Chosen) == scope.MoCode && RouteSignals.Kind(d.Chosen) is null
                                && RouteConsent.Response(d.Chosen) is null && ReferralConfirmation.Confirms(d.Chosen) is null
                                && RoutePatientRef.TryParse(d.SubjectId, out var parsed) && parsed!.MoCode != scope.MoCode)
                    .ToList();

                var loadedRegions = new HashSet<string>(StringComparer.Ordinal);
                var names = new Dictionary<string, string>(StringComparer.Ordinal);
                var rows = new List<IncomingReferralDto>();
                foreach (var candidate in candidates)
                {
                    RoutePatientRef.TryParse(candidate.SubjectId, out var parsed);
                    if (loadedRegions.Add(parsed!.RegionKato))
                    {
                        foreach (var state in await worklist.QueueStatesAsync(parsed.RegionKato, ct))
                        {
                            names.TryAdd(state.MoCode, state.MoName);
                        }
                    }

                    var related = (await decisions.ListAsync(null, DecisionSubjects.Route, candidate.SubjectId, 1, ReferralHistoryLimit, ct)).Items;
                    var confirmedAt = ReferralConfirmation.ConfirmedAt(candidate.DecisionId, related);
                    if (confirmedAt is not null && includeConfirmed != true)
                    {
                        continue;
                    }

                    var isSevere = ReferralConfirmation.Severe(candidate.Chosen);
                    if (severe == true && !isSevere)
                    {
                        continue;
                    }

                    var dischargeRecord = DischargeSummary.RecordFor(candidate.DecisionId, related);
                    rows.Add(new IncomingReferralDto(
                        candidate.DecisionId, candidate.SubjectId, parsed!.MoCode, names.GetValueOrDefault(parsed.MoCode, parsed.MoCode),
                        parsed.ProfileCode, candidate.Reason, candidate.RecordedAt, isSevere,
                        RouteConsent.StatusFor(candidate.DecisionId, related), confirmedAt is not null, confirmedAt,
                        dischargeRecord is not null, dischargeRecord?.RecordedAt));
                }

                return Results.Ok(rows.OrderByDescending(r => r.Severe).ThenByDescending(r => r.RecordedAt).ToList());
            })
            .RequireAuthorization(Permissions.Policy(Permissions.WorklistView))
            .WithName("IncomingReferrals")
            .WithSummary("Входящие направления в организацию (redirect от других организаций): scope own — только своя организация, как в /journal/worklist; "
                + "severe=true — только тяжёлые случаи; includeConfirmed=true — показать и уже подтверждённые")
            .Produces<List<IncomingReferralDto>>().ProducesProblem(StatusCodes.Status403Forbidden).ProducesProblem(StatusCodes.Status422UnprocessableEntity);

        group.MapPost("/referrals/{decisionId:guid}/confirm", async (Guid decisionId, ReferralConfirmRequestDto body, HttpContext http,
                IDecisionRepository decisions, CancellationToken ct) =>
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

                var errors = new ValidationErrors().Require("patientRef", body.PatientRef);
                if (errors.Any)
                {
                    return errors.Problem();
                }

                var related = (await decisions.ListAsync(null, DecisionSubjects.Route, body.PatientRef, 1, ReferralHistoryLimit, ct)).Items;
                var target = related.FirstOrDefault(d =>
                    d.DecisionId == decisionId && RouteSignals.MoCode(d.Chosen) == moCode && RouteSignals.Kind(d.Chosen) is null
                    && RouteConsent.Response(d.Chosen) is null && ReferralConfirmation.Confirms(d.Chosen) is null);
                if (target is null)
                {
                    return Results.Problem(statusCode: StatusCodes.Status404NotFound, title: "Направление не найдено",
                        detail: "нет решения redirect на этот маршрут в вашу организацию с таким decisionId");
                }

                if (ReferralConfirmation.ConfirmedAt(decisionId, related) is not null)
                {
                    return Results.Problem(statusCode: StatusCodes.Status409Conflict, title: "Уже подтверждено",
                        detail: "это направление уже подтверждено вашей организацией");
                }

                if (RouteConsent.StatusFor(decisionId, related) != RouteConsent.Accepted)
                {
                    return Results.Problem(statusCode: StatusCodes.Status409Conflict, title: "Пациент ещё не согласился",
                        detail: "нельзя подтвердить приём, пока пациент не принял направление (patientConsent должен быть accepted)");
                }

                var comment = string.IsNullOrWhiteSpace(body.Comment) ? null : body.Comment.Trim();
                return await DecisionRecording.RecordAsync(http, decisions, DecisionSubjects.Route, body.PatientRef!,
                    null, ReferralConfirmation.Json(moCode, decisionId), comment, _ => "/api/v1/journal/referrals/incoming", ct);
            })
            .RequireAuthorization(Permissions.Policy(Permissions.ReferralConfirm))
            .WithName("ConfirmReferral")
            .WithSummary("Принимающая организация подтверждает приём направленного пациента; требует, чтобы пациент уже согласился (patientConsent == accepted); "
                + "повторное подтверждение и подтверждение без согласия пациента — 409")
            .Produces<DecisionCreatedDto>(StatusCodes.Status201Created).Produces<DecisionCreatedDto>()
            .ProducesProblem(StatusCodes.Status403Forbidden).ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status409Conflict).ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity);

        group.MapPost("/referrals/{decisionId:guid}/discharge", async (Guid decisionId, DischargeRequestDto body, HttpContext http,
                IDecisionRepository decisions, CancellationToken ct) =>
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

                var errors = new ValidationErrors().Require("patientRef", body.PatientRef).Require("summary", body.Summary);
                if (errors.Any)
                {
                    return errors.Problem();
                }

                var related = (await decisions.ListAsync(null, DecisionSubjects.Route, body.PatientRef, 1, ReferralHistoryLimit, ct)).Items;
                var target = related.FirstOrDefault(d =>
                    d.DecisionId == decisionId && RouteSignals.MoCode(d.Chosen) == moCode && RouteSignals.Kind(d.Chosen) is null
                    && RouteConsent.Response(d.Chosen) is null && ReferralConfirmation.Confirms(d.Chosen) is null);
                if (target is null)
                {
                    return Results.Problem(statusCode: StatusCodes.Status404NotFound, title: "Направление не найдено",
                        detail: "нет решения redirect на этот маршрут в вашу организацию с таким decisionId");
                }

                if (ReferralConfirmation.ConfirmedAt(decisionId, related) is null)
                {
                    return Results.Problem(statusCode: StatusCodes.Status409Conflict, title: "Приём ещё не подтверждён",
                        detail: "нельзя выписать пациента, пока принимающая организация не подтвердила приём направления");
                }

                if (DischargeSummary.RecordFor(decisionId, related) is not null)
                {
                    return Results.Problem(statusCode: StatusCodes.Status409Conflict, title: "Уже выписан",
                        detail: "по этому направлению уже есть эпикриз выписки");
                }

                var summary = body.Summary!.Trim();
                return await DecisionRecording.RecordAsync(http, decisions, DecisionSubjects.Route, body.PatientRef!,
                    null, DischargeSummary.Json(moCode, decisionId, summary), null, _ => "/api/v1/journal/referrals/incoming", ct);
            })
            .RequireAuthorization(Permissions.Policy(Permissions.ReferralConfirm))
            .WithName("DischargeReferral")
            .WithSummary("Принимающая организация закрывает лечение и отправляет эпикриз направившему врачу (задача 11); "
                + "требует, чтобы приём уже был подтверждён; выписка без подтверждения и повторная выписка — 409")
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

    /// <summary>Очереди региона; с организацией (параметр moCode или scope own) — только очереди этой организации.</summary>
    private static async Task<IReadOnlyList<QueueStateRow>> ForOrganizationAsync(IWorklistRepository repository, string region, string? moCode, CancellationToken ct)
    {
        var states = await repository.QueueStatesAsync(region, ct);
        return moCode is null ? states : states.Where(s => string.Equals(s.MoCode, moCode, StringComparison.OrdinalIgnoreCase)).ToList();
    }
}
