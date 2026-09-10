using Dapper;
using Darumen.Shared.Api;
using Darumen.Shared.Data;

namespace Darumen.Modules.Intake;

public sealed class IntakeRepository(IDbConnectionFactory db) : IIntakeRepository
{
    public async Task<Paged<BatchDto>> BatchesAsync(string? status, string? dataset, int page, int size, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        const string where = "WHERE (@status IS NULL OR status = @status) AND (@dataset IS NULL OR dataset = @dataset)";
        var parameters = new { status, dataset, size, offset = (page - 1) * size };
        var total = await connection.ExecuteScalarAsync<long>(new CommandDefinition(
            $"SELECT count(*) FROM intake.batches {where}", parameters, cancellationToken: cancellationToken));
        var rows = await connection.QueryAsync<Row>(new CommandDefinition(
            $"""
            SELECT batch_id AS BatchId, dataset AS Dataset, status AS Status, rows_loaded AS RowsLoaded, rows_quarantined AS RowsQuarantined,
                   partitions AS Partitions, occurred_at AS OccurredAt, received_at AS ReceivedAt
            FROM intake.batches {where} ORDER BY received_at DESC LIMIT @size OFFSET @offset
            """,
            parameters, cancellationToken: cancellationToken));
        var items = rows.Select(r => new BatchDto(
            r.BatchId, r.Dataset, r.Status, r.RowsLoaded, r.RowsQuarantined,
            r.Partitions.Split(',', StringSplitOptions.RemoveEmptyEntries),
            r.OccurredAt is null ? null : new DateTimeOffset(DateTime.SpecifyKind(r.OccurredAt.Value, DateTimeKind.Utc)),
            new DateTimeOffset(DateTime.SpecifyKind(r.ReceivedAt, DateTimeKind.Utc)))).ToList();
        return new Paged<BatchDto>(items, page, size, total);
    }

    private sealed record Row(string BatchId, string Dataset, string Status, long RowsLoaded, long RowsQuarantined, string Partitions, DateTime? OccurredAt, DateTime ReceivedAt);
}
