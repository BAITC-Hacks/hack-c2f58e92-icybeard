using Dapper;
using Darumen.Shared.Api;
using Darumen.Shared.Data;

namespace Darumen.Modules.Access.Data;

public sealed class PostgresActivityReader(IDbConnectionFactory db) : IActivityReader, IOrgDataStatus
{
    private const string UndefinedTable = "42P01";

    public async Task<IReadOnlyDictionary<string, DateTimeOffset>> LastActivityAsync(IReadOnlyCollection<string> actors, CancellationToken cancellationToken)
    {
        if (actors.Count == 0)
        {
            return new Dictionary<string, DateTimeOffset>();
        }

        await using var connection = await db.OpenAsync(cancellationToken);
        var rows = await connection.QueryAsync<(string Actor, DateTime At)>(new CommandDefinition(
            "SELECT actor, max(at) FROM journal.audit WHERE actor = ANY(@actors) GROUP BY actor",
            new { actors = actors.ToArray() }, cancellationToken: cancellationToken));
        return rows.ToDictionary(r => r.Actor, r => Db.Utc(r.At));
    }

    public async Task<IReadOnlyDictionary<string, ReferralStats>> ReferralStatsAsync(
        IReadOnlyCollection<string> actors, DateTimeOffset since, CancellationToken cancellationToken)
    {
        if (actors.Count == 0)
        {
            return new Dictionary<string, ReferralStats>();
        }

        await using var connection = await db.OpenAsync(cancellationToken);
        // совпадение с рекомендацией: выбор врача (chosen.moCode) равен рекомендации системы (recommended.moCode)
        var rows = await connection.QueryAsync<(string Actor, long Referrals, double? MatchRate)>(new CommandDefinition(
            """
            SELECT actor, count(*),
                   avg(CASE WHEN recommended->>'moCode' IS NULL OR chosen->>'moCode' IS NULL THEN NULL
                            WHEN recommended->>'moCode' = chosen->>'moCode' THEN 1.0 ELSE 0.0 END)
            FROM journal.decisions
            WHERE actor = ANY(@actors) AND subject IN (@referral, @route) AND recorded_at >= @since
            GROUP BY actor
            """,
            new { actors = actors.ToArray(), referral = DecisionSubjects.Referral, route = DecisionSubjects.Route, since = since.UtcDateTime },
            cancellationToken: cancellationToken));
        return rows.ToDictionary(r => r.Actor, r => new ReferralStats(r.Referrals, r.MatchRate));
    }

    public async Task<IReadOnlyList<AuditRow>> MentionsAsync(IReadOnlyCollection<string> needles, string exceptActor, int limit, CancellationToken cancellationToken)
    {
        var patterns = needles.Where(n => n.Length >= 3).Select(n => "%" + Escape(n) + "%").ToArray();
        if (patterns.Length == 0)
        {
            return [];
        }

        await using var connection = await db.OpenAsync(cancellationToken);
        var rows = await connection.QueryAsync<Row>(new CommandDefinition(
            """
            SELECT at AS At, actor AS Actor, role AS Role, method AS Method, path AS Path, status AS Status
            FROM journal.audit WHERE actor <> @exceptActor AND path LIKE ANY(@patterns)
            ORDER BY at DESC LIMIT @limit
            """,
            new { patterns, exceptActor, limit }, cancellationToken: cancellationToken));
        return rows.Select(r => r.ToRecord()).ToList();
    }

    public async Task<IReadOnlyList<AuditRow>> ByActorAsync(string actor, int limit, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        var rows = await connection.QueryAsync<Row>(new CommandDefinition(
            """
            SELECT at AS At, actor AS Actor, role AS Role, method AS Method, path AS Path, status AS Status
            FROM journal.audit WHERE actor = @actor ORDER BY at DESC LIMIT @limit
            """,
            new { actor, limit }, cancellationToken: cancellationToken));
        return rows.Select(r => r.ToRecord()).ToList();
    }

    public async Task<IReadOnlySet<string>> ConnectedAsync(IReadOnlyCollection<string> moCodes, CancellationToken cancellationToken)
    {
        if (moCodes.Count == 0)
        {
            return new HashSet<string>();
        }

        await using var connection = await db.OpenAsync(cancellationToken);
        try
        {
            var rows = await connection.QueryAsync<string>(new CommandDefinition(
                "SELECT DISTINCT mo_code FROM gold.queue_state WHERE mo_code = ANY(@codes)", new { codes = moCodes.ToArray() }, cancellationToken: cancellationToken));
            return rows.ToHashSet(StringComparer.OrdinalIgnoreCase);
        }
        catch (Npgsql.PostgresException e) when (e.SqlState == UndefinedTable)
        {
            return new HashSet<string>(); // витрина появится после make publish
        }
    }

    public async Task<IReadOnlyList<DatasetFreshness>> FreshnessAsync(string? regionKato, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        // партии без региона в партициях — общенациональные наборы; с регионом — только партии региона организации
        var rows = await connection.QueryAsync<(string Dataset, DateTime At, string Status, long RowsLoaded)>(new CommandDefinition(
            """
            SELECT DISTINCT ON (dataset) dataset, received_at, status, rows_loaded
            FROM intake.batches
            WHERE @region IS NULL OR partitions NOT LIKE '%region_kato=%' OR partitions LIKE '%region_kato=' || @region || '%'
            ORDER BY dataset, received_at DESC
            """,
            new { region = regionKato }, cancellationToken: cancellationToken));
        return rows.Select(r => new DatasetFreshness(r.Dataset, Db.Utc(r.At), r.Status, r.RowsLoaded)).ToList();
    }

    private static string Escape(string value) => value.Replace("\\", "\\\\").Replace("%", "\\%").Replace("_", "\\_");

    private sealed record Row(DateTime At, string Actor, string Role, string Method, string Path, int Status)
    {
        public AuditRow ToRecord() => new(Db.Utc(At), Actor, Role, Method, Path, Status);
    }
}
