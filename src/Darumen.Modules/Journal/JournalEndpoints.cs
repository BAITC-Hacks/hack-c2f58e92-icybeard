using Darumen.Shared.Api;
using Darumen.Shared.Auth;

namespace Darumen.Modules.Journal;

public static class JournalEndpoints
{
    /// <summary>Сколько решений по маршрутам читать для флагов сигналов в рабочем списке: журнал маршрутов на кэмпе
    /// исчисляется десятками записей, одной страницы хватает.</summary>
    private const int RouteDecisionsPage = 500;

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
                var region = regionKato ?? user.RegionKato ?? "75";
                var states = await ForOrganizationAsync(repository, region, scope.MoCode, ct);
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
