using Darumen.Modules.RefData;
using Darumen.Shared.Api;
using Darumen.Shared.Auth;

namespace Darumen.Modules.Journal;

/// <summary>Колокольчик (задача 13 плана прозрачности): вместо push-инфраструктуры — внутрисистемные уведомления
/// для врача/главврача/менеджера по койкам своей организации. Три вещи, все — на лету из journal.decisions, кроме
/// отметок прочтения (единственное собственное хранилище, <see cref="INotificationReadRepository"/>, ключ
/// (actor, kind, decisionId) — kind различает разные события по одному и тому же decisionId направления, иначе
/// прочтение одного события ложно закрывало бы и другое): сколько входящих направлений ждут подтверждения (считается
/// на лету, своего хранения не требует); какие из отправленных моей организацией направлений уже подтверждены
/// принимающей стороной, но я их ещё не видел; какие из них уже выписаны с эпикризом (задача 11), но я их ещё не видел.</summary>
public static class NotificationBellEndpoints
{
    private const int RouteDecisionsPage = 500;
    private const int ReferralHistoryLimit = 20;

    public static void Map(IEndpointRouteBuilder api)
    {
        var group = api.MapGroup("/journal").WithTags("Journal");

        group.MapGet("/notifications/bell", async (string? moCode, HttpContext http, IDecisionRepository decisions,
                INotificationReadRepository reads, IRefDataRepository refData, CancellationToken ct) =>
            {
                var scope = await OrgAccess.ResolveAsync(http, moCode, Permissions.WorklistView);
                if (scope.Problem is not null)
                {
                    return scope.Problem;
                }

                if (scope.MoCode is null)
                {
                    // виджет для главной, а не листинг: без организации молча ничего не показываем, а не 422
                    return Results.Ok(new NotificationBellDto(0, [], []));
                }

                var forOrg = (await decisions.ListForOrganizationAsync(scope.MoCode, null, DecisionSubjects.Route, null, 1, RouteDecisionsPage, ct)).Items;

                var incoming = forOrg.Where(d => RouteSignals.MoCode(d.Chosen) == scope.MoCode && RouteSignals.Kind(d.Chosen) is null
                    && RouteConsent.Response(d.Chosen) is null && ReferralConfirmation.Confirms(d.Chosen) is null
                    && DischargeSummary.Discharges(d.Chosen) is null
                    && RoutePatientRef.TryParse(d.SubjectId, out var parsedIn) && parsedIn!.MoCode != scope.MoCode);

                var pendingIncoming = 0;
                foreach (var candidate in incoming)
                {
                    var related = (await decisions.ListAsync(null, DecisionSubjects.Route, candidate.SubjectId, 1, ReferralHistoryLimit, ct)).Items;
                    if (ReferralConfirmation.ConfirmedAt(candidate.DecisionId, related) is null)
                    {
                        pendingIncoming++;
                    }
                }

                // «отправленные моей организацией» определяются по рефу пациента (SYN-{регион}-{moCode}-{профиль}-{NN}),
                // а не по actor_mo_code/recommended.moCode/chosen.moCode — ListForOrganizationAsync фильтрует именно по
                // этим полям (годится для «входящих», где принимающая организация есть в chosen.moCode) и никогда не
                // вернёт запись, где организация-отправитель видна только в SubjectId. Поэтому здесь — отдельная,
                // не отфильтрованная по организации выборка с фильтром в памяти: тот же приём, что уже применяется в
                // /worklist для сигналов по региону (SubjectId.StartsWith), только по коду организации в рефе.
                var allRoute = (await decisions.ListAsync(null, DecisionSubjects.Route, null, 1, RouteDecisionsPage, ct)).Items;
                var sent = allRoute.Where(d => RouteSignals.MoCode(d.Chosen) != scope.MoCode && RouteSignals.Kind(d.Chosen) is null
                    && RouteConsent.Response(d.Chosen) is null && ReferralConfirmation.Confirms(d.Chosen) is null
                    && DischargeSummary.Discharges(d.Chosen) is null
                    && RoutePatientRef.TryParse(d.SubjectId, out var parsedOut) && parsedOut!.MoCode == scope.MoCode);

                var confirmedItems = new List<(Guid DecisionId, string PatientRef, string ToMoCode, DateTimeOffset ConfirmedAt)>();
                var dischargedItems = new List<(Guid DecisionId, string PatientRef, string FromMoCode, string Summary, DateTimeOffset DischargedAt)>();
                foreach (var candidate in sent)
                {
                    var related = (await decisions.ListAsync(null, DecisionSubjects.Route, candidate.SubjectId, 1, ReferralHistoryLimit, ct)).Items;
                    var confirmedAt = ReferralConfirmation.ConfirmedAt(candidate.DecisionId, related);
                    if (confirmedAt is not null)
                    {
                        confirmedItems.Add((candidate.DecisionId, candidate.SubjectId, RouteSignals.MoCode(candidate.Chosen)!, confirmedAt.Value));
                    }

                    if (DischargeSummary.RecordFor(candidate.DecisionId, related) is { } dischargeRecord)
                    {
                        dischargedItems.Add((candidate.DecisionId, candidate.SubjectId, RouteSignals.MoCode(candidate.Chosen)!,
                            DischargeSummary.Summary(dischargeRecord.Chosen) ?? "", dischargeRecord.RecordedAt));
                    }
                }

                var actor = CurrentUser.From(http).Actor;
                var readConfirmations = await reads.ReadDecisionIdsAsync(actor, NotificationKinds.ReferralConfirmed,
                    confirmedItems.Select(c => c.DecisionId).ToList(), ct);
                var readDischarges = await reads.ReadDecisionIdsAsync(actor, NotificationKinds.ReferralDischarged,
                    dischargedItems.Select(c => c.DecisionId).ToList(), ct);

                var pendingConfirmations = confirmedItems.Where(c => !readConfirmations.Contains(c.DecisionId)).ToList();
                var pendingDischarges = dischargedItems.Where(c => !readDischarges.Contains(c.DecisionId)).ToList();

                // Название организации — из справочника refdata.mo_registry по точному коду, без привязки к региону
                // (mo_code уникален глобально): региона второй стороны из рефа пациента-отправителя не узнать, а
                // показывать код вместо названия в колокольчике для конечного пользователя недопустимо.
                var names = new Dictionary<string, string>(StringComparer.Ordinal);
                foreach (var code in pendingConfirmations.Select(c => c.ToMoCode).Concat(pendingDischarges.Select(c => c.FromMoCode)).Distinct(StringComparer.Ordinal))
                {
                    var found = await refData.OrganizationsAsync(null, code, null, 1, ct);
                    if (found.FirstOrDefault(o => o.MoCode == code) is { } org)
                    {
                        names[code] = org.Name;
                    }
                }

                var unreadConfirmations = pendingConfirmations
                    .Select(c => new SentReferralConfirmationDto(c.DecisionId, c.PatientRef, c.ToMoCode, names.GetValueOrDefault(c.ToMoCode, c.ToMoCode), c.ConfirmedAt, false))
                    .OrderByDescending(c => c.ConfirmedAt)
                    .ToList();
                var unreadDischarges = pendingDischarges
                    .Select(c => new DischargeReadyDto(c.DecisionId, c.PatientRef, c.FromMoCode, names.GetValueOrDefault(c.FromMoCode, c.FromMoCode), c.Summary, c.DischargedAt, false))
                    .OrderByDescending(c => c.DischargedAt)
                    .ToList();

                return Results.Ok(new NotificationBellDto(pendingIncoming, unreadConfirmations, unreadDischarges));
            })
            .RequireAuthorization(Permissions.Policy(Permissions.WorklistView))
            .WithName("NotificationBell")
            .WithSummary("Колокольчик: сколько входящих направлений ждут подтверждения, какие отправленные моей "
                + "организацией направления подтверждены и какие выписаны (эпикриз) — из того, что я ещё не отмечал прочитанным")
            .Produces<NotificationBellDto>().ProducesProblem(StatusCodes.Status403Forbidden);

        group.MapPost("/notifications/bell/{kind}/{decisionId:guid}/read", async (string kind, Guid decisionId, HttpContext http,
                INotificationReadRepository reads, CancellationToken ct) =>
            {
                if (kind != NotificationKinds.ReferralConfirmed && kind != NotificationKinds.ReferralDischarged)
                {
                    return Results.Problem(statusCode: StatusCodes.Status400BadRequest, title: "Неизвестный вид уведомления",
                        detail: $"kind должен быть один из: {NotificationKinds.ReferralConfirmed}, {NotificationKinds.ReferralDischarged}");
                }

                if (await OrgAccess.CheckAsync(http, null, Permissions.WorklistView) is { } denied)
                {
                    return denied;
                }

                await reads.MarkReadAsync(CurrentUser.From(http).Actor, kind, decisionId, ct);
                return Results.NoContent();
            })
            .RequireAuthorization(Permissions.Policy(Permissions.WorklistView))
            .WithName("MarkNotificationRead")
            .WithSummary("Отмечает одно уведомление колокольчика прочитанным для текущего пользователя; произвольный "
                + "decisionId (в том числе несуществующий) — тоже 204, идемпотентно; kind — referral-confirmed или referral-discharged")
            .Produces(StatusCodes.Status204NoContent).ProducesProblem(StatusCodes.Status400BadRequest).ProducesProblem(StatusCodes.Status403Forbidden);
    }
}
