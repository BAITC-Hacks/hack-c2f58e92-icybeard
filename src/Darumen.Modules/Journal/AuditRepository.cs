using Dapper;
using Darumen.Shared.Api;
using Darumen.Shared.Data;

namespace Darumen.Modules.Journal;

public sealed class AuditRepository(IDbConnectionFactory db) : IAuditRepository
{
    public async Task<Paged<AuditEntryDto>> ListAsync(string? actor, int page, int size, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        const string where = "WHERE (@actor IS NULL OR actor = @actor)";
        var parameters = new { actor, size, offset = (page - 1) * size };
        var total = await connection.ExecuteScalarAsync<long>(new CommandDefinition($"SELECT count(*) FROM journal.audit {where}", parameters, cancellationToken: cancellationToken));
        var rows = await connection.QueryAsync<Row>(new CommandDefinition(
            $"""
            SELECT id AS Id, at AS At, actor AS Actor, role AS Role, method AS Method, path AS Path, query AS Query, status AS Status,
                   duration_ms AS DurationMs, trace_id AS TraceId
            FROM journal.audit {where} ORDER BY at DESC LIMIT @size OFFSET @offset
            """,
            parameters, cancellationToken: cancellationToken));
        var items = rows.Select(r => new AuditEntryDto(r.Id, new DateTimeOffset(DateTime.SpecifyKind(r.At, DateTimeKind.Utc)), r.Actor, r.Role, r.Method, r.Path, r.Query, r.Status, r.DurationMs, r.TraceId)).ToList();
        return new Paged<AuditEntryDto>(items, page, size, total);
    }

    private sealed record Row(long Id, DateTime At, string Actor, string Role, string Method, string Path, string? Query, int Status, int DurationMs, string TraceId);
}
