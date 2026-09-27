using System.Text.Json;

namespace Darumen.Modules.Journal;

public sealed record DecisionRequestDto(string? Subject, string? SubjectId, JsonElement? Recommended, JsonElement? Chosen, string? Reason);

public sealed record DecisionDto(
    Guid DecisionId, string Actor, string Role, string Subject, string SubjectId, JsonElement? Recommended, JsonElement? Chosen,
    string? Reason, DateTimeOffset RecordedAt);

public sealed record DecisionCreatedDto(Guid DecisionId, DateTimeOffset RecordedAt);

public sealed record AuditEntryDto(
    long Id, DateTimeOffset At, string Actor, string Role, string Method, string Path, string? Query, int Status, int DurationMs, string TraceId,
    string? MoCode = null, string? Detail = null);

public sealed record NewDecision(
    string Actor, string Role, string Subject, string SubjectId, string? RecommendedJson, string? ChosenJson, string? Reason, string? IdempotencyKey,
    string? ActorMoCode = null);
