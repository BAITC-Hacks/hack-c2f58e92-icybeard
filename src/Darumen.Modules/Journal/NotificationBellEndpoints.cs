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
                    return Results.Ok(new NotificationBellDto(0, [], [], []));
                }

                // всё — из проекций маршрутов (RouteProgress): отменённые, отклонённые и отказы пациента не считаются
                var routes = await RouteJournal.AllAsync(decisions, ct);
                var pendingIncoming = routes.Values.Count(r => r.Progress.Status == RouteStatuses.TransferPendingConfirmation
                    && string.Equals(r.Progress.Transfer!.ToMoCode, scope.MoCode, StringComparison.OrdinalIgnoreCase));

                // «отправленные моей организацией» — по рефу пациента (SYN-{регион}-{moCode}-{профиль}-{NN}): больница, где он стоял в очереди
                var confirmedItems = new List<(Guid DecisionId, string PatientRef, string ToMoCode, DateTimeOffset ConfirmedAt)>();
                var dischargedItems = new List<(Guid DecisionId, string PatientRef, string FromMoCode, string Summary, DateTimeOffset DischargedAt)>();
                foreach (var (reference, route) in routes)
                {
                    var progress = route.Progress;
                    if (!string.Equals(progress.OriginMoCode, scope.MoCode, StringComparison.OrdinalIgnoreCase) || progress.Transfer is not { ConfirmedAt: not null } transfer)
                    {
                        continue;
                    }

                    confirmedItems.Add((transfer.DecisionId, reference, transfer.ToMoCode, transfer.ConfirmedAt.Value));
                    if (progress.ClosedReason == RouteCloseReasons.Discharged)
                    {
                        var summary = RouteEvents.Ordered(route.Decisions).LastOrDefault(e => e.Kind == RouteEventKind.Discharge)?.Value ?? "";
                        dischargedItems.Add((transfer.DecisionId, reference, transfer.ToMoCode, summary, progress.ClosedAt!.Value));
                    }
                }

                var actor = CurrentUser.From(http).Actor;

                // что сделали пациенты моей больницы за последние дни (кроме уже прочитанного)
                var scribe = (await decisions.ListAsync(null, DecisionSubjects.Scribe, null, 1, RouteJournal.AllRoutesLimit, ct)).Items;
                var signals = PatientSignals.From(routes, scribe, scope.MoCode, (http.RequestServices.GetService<TimeProvider>() ?? TimeProvider.System).GetUtcNow().AddDays(-PatientSignals.Days), RouteJournal.Today(http));
                var readSignals = await reads.ReadDecisionIdsAsync(actor, NotificationKinds.PatientSignal, signals.Select(s => s.Id).ToList(), ct);
                signals = signals.Where(s => !readSignals.Contains(s.Id)).ToList();

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
                foreach (var code in pendingConfirmations.Select(c => c.ToMoCode).Concat(pendingDischarges.Select(c => c.FromMoCode))
                             .Concat(signals.Select(s => s.MoCode).OfType<string>()).Distinct(StringComparer.Ordinal))
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

                var patientSignals = signals.Select(s => s.MoCode is { } mo ? s with { MoName = names.GetValueOrDefault(mo, mo) } : s).ToList();
                return Results.Ok(new NotificationBellDto(pendingIncoming, unreadConfirmations, unreadDischarges, patientSignals));
            })
            .RequireAuthorization(Permissions.Policy(Permissions.WorklistView))
            .WithName("NotificationBell")
            .WithSummary("Колокольчик: сколько входящих направлений ждут подтверждения, какие отправленные моей "
                + "организацией направления подтверждены и какие выписаны (эпикриз) — из того, что я ещё не отмечал прочитанным")
            .Produces<NotificationBellDto>().ProducesProblem(StatusCodes.Status403Forbidden);

        group.MapPost("/notifications/bell/{kind}/{decisionId:guid}/read", async (string kind, Guid decisionId, HttpContext http,
                INotificationReadRepository reads, CancellationToken ct) =>
            {
                if (kind != NotificationKinds.ReferralConfirmed && kind != NotificationKinds.ReferralDischarged && kind != NotificationKinds.PatientSignal)
                {
                    return Results.Problem(statusCode: StatusCodes.Status400BadRequest, title: "Неизвестный вид уведомления",
                        detail: $"kind должен быть один из: {NotificationKinds.ReferralConfirmed}, {NotificationKinds.ReferralDischarged}, {NotificationKinds.PatientSignal}");
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
