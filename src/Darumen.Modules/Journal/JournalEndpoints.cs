using System.Text.Json;
using Darumen.Shared.Api;
using Darumen.Shared.Messaging;

namespace Darumen.Modules.Journal;

public static class JournalEndpoints
{
    public static void Map(IEndpointRouteBuilder api)
    {
        var group = api.MapGroup("/journal").WithTags("Journal");

        group.MapPost("/decisions", async (DecisionRequestDto body, HttpContext http, IDecisionRepository repository, IEventPublisher events, CancellationToken ct) =>
            {
                var errors = new ValidationErrors().Require("subject", body.Subject).Require("subjectId", body.SubjectId);
                if (errors.Any)
                {
                    return errors.Problem();
                }

                var user = CurrentUser.From(http);
                var key = http.Request.Headers.TryGetValue("Idempotency-Key", out var k) && !string.IsNullOrWhiteSpace(k) ? k.ToString() : null;
                var (decision, created) = await repository.RecordAsync(new NewDecision(
                    user.Actor, user.Role, body.Subject!, body.SubjectId!,
                    body.Recommended?.GetRawText(), body.Chosen?.GetRawText(), body.Reason, key), ct);
                if (created)
                {
                    await events.PublishAsync(new DecisionRecorded(decision.DecisionId, decision.Actor, decision.Role, decision.Subject, decision.SubjectId, decision.RecordedAt), ct);
                }

                var payload = new DecisionCreatedDto(decision.DecisionId, decision.RecordedAt);
                return created ? Results.Created($"/api/v1/journal/decisions/{decision.DecisionId}", payload) : Results.Ok(payload);
            })
            .WithName("RecordDecision").WithSummary("Записать решение человека (рекомендация и выбор)")
            .Produces<DecisionCreatedDto>(StatusCodes.Status201Created).Produces<DecisionCreatedDto>()
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity);

        group.MapGet("/decisions", async (string? actor, string? subject, int? page, int? size, HttpContext http, IDecisionRepository repository, CancellationToken ct) =>
            {
                var (p, s) = Paging.Normalize(page, size);
                var who = actor == "me" ? CurrentUser.From(http).Actor : actor;
                return Results.Ok(await repository.ListAsync(who, subject, p, s, ct));
            })
            .WithName("Decisions").WithSummary("Журнал решений").Produces<Paged<DecisionDto>>();
    }
}
