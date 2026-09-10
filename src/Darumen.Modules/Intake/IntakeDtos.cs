namespace Darumen.Modules.Intake;

public sealed record BatchDto(
    string BatchId, string Dataset, string Status, long RowsLoaded, long RowsQuarantined, IReadOnlyList<string> Partitions,
    DateTimeOffset? OccurredAt, DateTimeOffset ReceivedAt);
