using Darumen.Shared.Api;
using Darumen.Shared.Auth;

namespace Darumen.Modules.Journal;

public static class JournalEndpoints
{
    public static void Map(IEndpointRouteBuilder api)
    {
        var group = api.MapGroup("/journal").WithTags("Journal").RequireAuthorization(Policies.DoctorOrRegulator);

        group.MapPost("/decisions", async (DecisionRequestDto body, HttpContext http, IDecisionRepository repository, CancellationToken ct) =>
            {
                var errors = new ValidationErrors().Require("subject", body.Subject).Require("subjectId", body.SubjectId);
                if (errors.Any)
                {
                    return errors.Problem();
                }

                return await DecisionRecording.RecordAsync(http, repository, body.Subject!, body.SubjectId!,
                    body.Recommended?.GetRawText(), body.Chosen?.GetRawText(), body.Reason,
                    decision => $"/api/v1/journal/decisions/{decision.DecisionId}", ct);
            })
            .WithName("RecordDecision").WithSummary("Записать решение человека (рекомендация и выбор)")
            .Produces<DecisionCreatedDto>(StatusCodes.Status201Created).Produces<DecisionCreatedDto>()
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity);

        group.MapGet("/decisions", async (string? actor, string? subject, string? subjectId, int? page, int? size, HttpContext http, IDecisionRepository repository, CancellationToken ct) =>
            {
                var (p, s) = Paging.Normalize(page, size);
                var who = actor == "me" ? CurrentUser.From(http).Actor : actor;
                return Results.Ok(await repository.ListAsync(who, subject, subjectId, p, s, ct));
            })
            .WithName("Decisions").WithSummary("Журнал решений (subjectId — решения по одному предмету, например по рефу пациента)").Produces<Paged<DecisionDto>>();

        group.MapGet("/worklist", async (string? regionKato, string? flag, HttpContext http, IWorklistRepository repository, QueuePredictions predictions, CancellationToken ct) =>
            {
                var user = CurrentUser.From(http);
                var region = regionKato ?? user.RegionKato ?? "75";
                var states = await repository.QueueStatesAsync(region, ct);
                var asOf = states.Count > 0 ? states[0].AsOf.ToString("yyyy-MM-dd") : string.Empty;
                var (byQueue, modelBacked) = await predictions.ForQueuesAsync(states, ct);
                return Results.Ok(new WorklistResponseDto(WorklistBuilder.Build(states, byQueue, flag), true, asOf, region, modelBacked));
            })
            .RequireAuthorization(Policies.Doctor)
            .WithName("Worklist").WithSummary("Рабочий список врача: синтетические пациенты на реальных очередях региона").Produces<WorklistResponseDto>();

        group.MapGet("/audit", async (string? actor, int? page, int? size, IAuditRepository repository, CancellationToken ct) =>
            {
                var (p, s) = Paging.Normalize(page, size);
                return Results.Ok(await repository.ListAsync(actor, p, s, ct));
            })
            .RequireAuthorization(Policies.Regulator)
            .WithName("Audit").WithSummary("Журнал аудита запросов врачей и регуляторов").Produces<Paged<AuditEntryDto>>();
    }
}
