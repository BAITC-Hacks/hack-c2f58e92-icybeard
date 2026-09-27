using Darumen.Contracts.V1;
using Darumen.Shared.Api;
using Darumen.Shared.Messaging;

namespace Darumen.Modules.Journal;

/// <summary>Общая запись решения человека для POST /journal/decisions и POST /route/{patientRef}/redirect:
/// Idempotency-Key из заголовка, событие DecisionRecorded через outbox в той же транзакции, 201 при новой записи
/// и 200 с той же записью при повторе ключа (двойной клик даёт одну запись).</summary>
public static class DecisionRecording
{
    public const string IdempotencyHeader = "Idempotency-Key";

    public static async Task<IResult> RecordAsync(
        HttpContext http, IDecisionRepository repository, string subject, string subjectId,
        string? recommendedJson, string? chosenJson, string? reason, Func<DecisionDto, string> location, CancellationToken cancellationToken)
    {
        var user = CurrentUser.From(http);
        var (decision, created) = await repository.RecordAsync(
            new NewDecision(user.Actor, user.Role, subject, subjectId, recommendedJson, chosenJson, reason, IdempotencyKey(http), user.MoCode),
            dto => new DecisionRecorded
            {
                Meta = Events.Meta(),
                DecisionId = dto.DecisionId.ToString(),
                ActorRole = user.Role,
                Subject = subject,
                Recommended = recommendedJson ?? string.Empty,
                Chosen = chosenJson ?? string.Empty,
                Reason = reason ?? string.Empty,
            },
            cancellationToken);

        var payload = new DecisionCreatedDto(decision.DecisionId, decision.RecordedAt);
        return created ? Results.Created(location(decision), payload) : Results.Ok(payload);
    }

    public static string? IdempotencyKey(HttpContext http) =>
        http.Request.Headers.TryGetValue(IdempotencyHeader, out var key) && !string.IsNullOrWhiteSpace(key) ? key.ToString() : null;
}
