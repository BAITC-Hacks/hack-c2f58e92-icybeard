using System.Text.Json;
using Dapper;
using Darumen.Shared.Api;
using Darumen.Shared.Data;

namespace Darumen.Modules.Journal;

public sealed class DecisionRepository(IDbConnectionFactory db) : IDecisionRepository
{
    private const string Columns = """
        id AS DecisionId, actor AS Actor, role AS Role, subject AS Subject, subject_id AS SubjectId,
        recommended::text AS RecommendedJson, chosen::text AS ChosenJson, reason AS Reason, recorded_at AS RecordedAt
        """;

    public async Task<(DecisionDto Decision, bool Created)> RecordAsync(NewDecision decision, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        var inserted = await connection.QuerySingleOrDefaultAsync<Row>(new CommandDefinition(
            $"""
            INSERT INTO journal.decisions (id, actor, role, subject, subject_id, recommended, chosen, reason, idempotency_key, recorded_at)
            VALUES (@id, @actor, @role, @subject, @subjectId, @recommended::jsonb, @chosen::jsonb, @reason, @key, now())
            ON CONFLICT (idempotency_key) DO NOTHING
            RETURNING {Columns}
            """,
            new
            {
                id = Guid.NewGuid(),
                actor = decision.Actor,
                role = decision.Role,
                subject = decision.Subject,
                subjectId = decision.SubjectId,
                recommended = decision.RecommendedJson,
                chosen = decision.ChosenJson,
                reason = decision.Reason,
                key = decision.IdempotencyKey,
            },
            cancellationToken: cancellationToken));
        if (inserted is not null)
        {
            return (ToDto(inserted), true);
        }

        var existing = await connection.QuerySingleAsync<Row>(new CommandDefinition(
            $"SELECT {Columns} FROM journal.decisions WHERE idempotency_key = @key",
            new { key = decision.IdempotencyKey }, cancellationToken: cancellationToken));
        return (ToDto(existing), false);
    }

    public async Task<Paged<DecisionDto>> ListAsync(string? actor, string? subject, int page, int size, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        const string where = "WHERE (@actor IS NULL OR actor = @actor) AND (@subject IS NULL OR subject = @subject)";
        var parameters = new { actor, subject, size, offset = (page - 1) * size };
        var total = await connection.ExecuteScalarAsync<long>(new CommandDefinition(
            $"SELECT count(*) FROM journal.decisions {where}", parameters, cancellationToken: cancellationToken));
        var rows = await connection.QueryAsync<Row>(new CommandDefinition(
            $"SELECT {Columns} FROM journal.decisions {where} ORDER BY recorded_at DESC LIMIT @size OFFSET @offset",
            parameters, cancellationToken: cancellationToken));
        return new Paged<DecisionDto>(rows.Select(ToDto).ToList(), page, size, total);
    }

    private static DecisionDto ToDto(Row r) => new(
        r.DecisionId, r.Actor, r.Role, r.Subject, r.SubjectId,
        r.RecommendedJson is null ? null : JsonSerializer.Deserialize<JsonElement>(r.RecommendedJson),
        r.ChosenJson is null ? null : JsonSerializer.Deserialize<JsonElement>(r.ChosenJson),
        r.Reason, r.RecordedAt);

    private sealed record Row(
        Guid DecisionId, string Actor, string Role, string Subject, string SubjectId, string? RecommendedJson, string? ChosenJson,
        string? Reason, DateTime RecordedAt);
}
