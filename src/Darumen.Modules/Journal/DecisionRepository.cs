using System.Text.Json;
using Dapper;
using Darumen.Migrations;
using Darumen.Shared.Api;
using Darumen.Shared.Data;
using Microsoft.EntityFrameworkCore;
using Wolverine.EntityFrameworkCore;

namespace Darumen.Modules.Journal;

/// <summary>Запись через EF Core и outbox Wolverine (одна транзакция для строки и события), чтение через Dapper.</summary>
public sealed class DecisionRepository(IDbContextOutbox<DarumenDbContext> outbox, IDbConnectionFactory db) : IDecisionRepository
{
    private const string Columns = """
        id AS DecisionId, actor AS Actor, role AS Role, subject AS Subject, subject_id AS SubjectId,
        recommended::text AS RecommendedJson, chosen::text AS ChosenJson, reason AS Reason, recorded_at AS RecordedAt
        """;

    public async Task<(DecisionDto Decision, bool Created)> RecordAsync(NewDecision decision, Func<DecisionDto, object> outboxEvent, CancellationToken cancellationToken)
    {
        var context = outbox.DbContext;
        if (decision.IdempotencyKey is not null)
        {
            var existing = await context.Decisions.AsNoTracking().FirstOrDefaultAsync(d => d.IdempotencyKey == decision.IdempotencyKey, cancellationToken);
            if (existing is not null)
            {
                return (ToDto(existing), false);
            }
        }

        var entity = new Decision
        {
            Id = Guid.NewGuid(),
            Actor = decision.Actor,
            Role = decision.Role,
            Subject = decision.Subject,
            SubjectId = decision.SubjectId,
            Recommended = decision.RecommendedJson,
            Chosen = decision.ChosenJson,
            Reason = decision.Reason,
            IdempotencyKey = decision.IdempotencyKey,
            RecordedAt = DateTime.UtcNow,
        };
        context.Decisions.Add(entity);
        var dto = ToDto(entity);
        await outbox.PublishAsync(outboxEvent(dto));
        try
        {
            await outbox.SaveChangesAndFlushMessagesAsync(cancellationToken);
        }
        catch (DbUpdateException) when (decision.IdempotencyKey is not null)
        {
            // гонка двух запросов с одним ключом: уникальный индекс отклонил вторую строку
            context.Entry(entity).State = EntityState.Detached;
            var winner = await context.Decisions.AsNoTracking().FirstAsync(d => d.IdempotencyKey == decision.IdempotencyKey, cancellationToken);
            return (ToDto(winner), false);
        }

        return (dto, true);
    }

    public async Task<Paged<DecisionDto>> ListAsync(string? actor, string? subject, string? subjectId, int page, int size, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        const string where = "WHERE (@actor IS NULL OR actor = @actor) AND (@subject IS NULL OR subject = @subject) AND (@subjectId IS NULL OR subject_id = @subjectId)";
        var parameters = new { actor, subject, subjectId, size, offset = (page - 1) * size };
        var total = await connection.ExecuteScalarAsync<long>(new CommandDefinition(
            $"SELECT count(*) FROM journal.decisions {where}", parameters, cancellationToken: cancellationToken));
        var rows = await connection.QueryAsync<Row>(new CommandDefinition(
            $"SELECT {Columns} FROM journal.decisions {where} ORDER BY recorded_at DESC LIMIT @size OFFSET @offset",
            parameters, cancellationToken: cancellationToken));
        return new Paged<DecisionDto>(rows.Select(ToDto).ToList(), page, size, total);
    }

    private static DecisionDto ToDto(Decision d) => new(
        d.Id, d.Actor, d.Role, d.Subject, d.SubjectId, ParseJson(d.Recommended), ParseJson(d.Chosen), d.Reason,
        new DateTimeOffset(DateTime.SpecifyKind(d.RecordedAt, DateTimeKind.Utc)));

    private static DecisionDto ToDto(Row r) => new(
        r.DecisionId, r.Actor, r.Role, r.Subject, r.SubjectId, ParseJson(r.RecommendedJson), ParseJson(r.ChosenJson), r.Reason,
        new DateTimeOffset(DateTime.SpecifyKind(r.RecordedAt, DateTimeKind.Utc)));

    private static JsonElement? ParseJson(string? json) => json is null ? null : JsonSerializer.Deserialize<JsonElement>(json);

    private sealed record Row(
        Guid DecisionId, string Actor, string Role, string Subject, string SubjectId, string? RecommendedJson, string? ChosenJson,
        string? Reason, DateTime RecordedAt);
}
