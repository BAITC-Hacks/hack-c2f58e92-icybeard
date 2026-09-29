using Dapper;
using Darumen.Shared.Data;

namespace Darumen.Modules.Journal;

public sealed class NotificationReadRepository(IDbConnectionFactory db) : INotificationReadRepository
{
    public async Task MarkReadAsync(string actor, string kind, Guid decisionId, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        await connection.ExecuteAsync(new CommandDefinition(
            """
            INSERT INTO journal.notification_reads (actor, decision_id, kind, read_at) VALUES (@actor, @decisionId, @kind, now())
            ON CONFLICT (actor, decision_id, kind) DO NOTHING
            """,
            new { actor, decisionId, kind }, cancellationToken: cancellationToken));
    }

    public async Task<HashSet<Guid>> ReadDecisionIdsAsync(string actor, string kind, IReadOnlyCollection<Guid> decisionIds, CancellationToken cancellationToken)
    {
        if (decisionIds.Count == 0)
        {
            return [];
        }

        await using var connection = await db.OpenAsync(cancellationToken);
        var rows = await connection.QueryAsync<Guid>(new CommandDefinition(
            "SELECT decision_id FROM journal.notification_reads WHERE actor = @actor AND kind = @kind AND decision_id = ANY(@decisionIds)",
            new { actor, kind, decisionIds = decisionIds.ToArray() }, cancellationToken: cancellationToken));
        return rows.ToHashSet();
    }
}
