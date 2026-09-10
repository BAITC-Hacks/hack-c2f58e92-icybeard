using Darumen.Contracts.V1;
using Darumen.Shared.Api;
using Darumen.Shared.Auth;
using Darumen.Shared.Messaging;

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

                var user = CurrentUser.From(http);
                var key = http.Request.Headers.TryGetValue("Idempotency-Key", out var k) && !string.IsNullOrWhiteSpace(k) ? k.ToString() : null;
                var (decision, created) = await repository.RecordAsync(
                    new NewDecision(user.Actor, user.Role, body.Subject!, body.SubjectId!, body.Recommended?.GetRawText(), body.Chosen?.GetRawText(), body.Reason, key),
                    dto => new DecisionRecorded
                    {
                        Meta = Events.Meta(),
                        DecisionId = dto.DecisionId.ToString(),
                        ActorRole = user.Role,
                        Subject = body.Subject!,
                        Recommended = body.Recommended?.GetRawText() ?? string.Empty,
                        Chosen = body.Chosen?.GetRawText() ?? string.Empty,
                        Reason = body.Reason ?? string.Empty,
                    },
                    ct);

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

        group.MapGet("/audit", async (string? actor, int? page, int? size, IAuditRepository repository, CancellationToken ct) =>
            {
                var (p, s) = Paging.Normalize(page, size);
                return Results.Ok(await repository.ListAsync(actor, p, s, ct));
            })
            .RequireAuthorization(Policies.Regulator)
            .WithName("Audit").WithSummary("Журнал аудита запросов врачей и регуляторов").Produces<Paged<AuditEntryDto>>();
    }
}
