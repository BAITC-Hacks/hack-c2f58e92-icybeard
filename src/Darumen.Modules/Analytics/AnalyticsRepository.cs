using Dapper;
using Darumen.Migrations;
using Darumen.Shared.Api;
using Darumen.Shared.Data;
using Wolverine.EntityFrameworkCore;

namespace Darumen.Modules.Analytics;

public sealed class AnalyticsRepository(IDbConnectionFactory db, IDbContextOutbox<DarumenDbContext> outbox) : IAnalyticsRepository
{
    public async Task<IReadOnlyList<StreamDto>> StreamsAsync(CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        var rows = await connection.QueryAsync<StreamRow>(new CommandDefinition(
            "SELECT stream_id AS StreamId, title AS Title, grain AS Grain, entity_keys AS EntityKeys, horizons AS Horizons FROM gold.streams ORDER BY stream_id",
            cancellationToken: cancellationToken));
        return rows.Select(r => new StreamDto(
            r.StreamId, r.Title, r.Grain,
            r.EntityKeys.Split(',', StringSplitOptions.RemoveEmptyEntries),
            r.Horizons.Split(',', StringSplitOptions.RemoveEmptyEntries).Select(int.Parse).ToList())).ToList();
    }

    public async Task<IReadOnlyList<HistoryPointDto>> HistoryAsync(string streamId, string entityJson, int periods, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        var rows = await connection.QueryAsync<HistoryPointDto>(new CommandDefinition(
            """
            SELECT period AS Period, y AS Y FROM (
                SELECT period, y FROM gold.series WHERE stream_id = @streamId AND entity = @entityJson ORDER BY period DESC LIMIT @periods
            ) t ORDER BY period
            """,
            new { streamId, entityJson, periods }, cancellationToken: cancellationToken));
        return rows.ToList();
    }

    public async Task<Paged<AnomalyDto>> AnomaliesAsync(AnomalyFilter filter, int page, int size, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        const string where = """
            WHERE (@regionKato IS NULL OR a.region_kato = @regionKato)
              AND (@streamId IS NULL OR a.stream_id = @streamId)
              AND (@severity IS NULL OR a.severity = @severity)
              AND (@status IS NULL OR coalesce(k.status, a.status) = @status)
            """;
        var parameters = new
        {
            regionKato = filter.RegionKato,
            streamId = filter.StreamId,
            severity = filter.Severity,
            status = filter.Status,
            size,
            offset = (page - 1) * size,
        };
        var total = await connection.ExecuteScalarAsync<long>(new CommandDefinition(
            $"SELECT count(*) FROM gold.anomalies a LEFT JOIN journal.anomaly_acks k ON k.anomaly_id = a.id {where}",
            parameters, cancellationToken: cancellationToken));
        var rows = await connection.QueryAsync<AnomalyRow>(new CommandDefinition(
            $"""
            SELECT a.id AS Id, a.stream_id AS StreamId, a.entity AS Entity, a.period AS Period, a.observed AS Observed,
                   a.expected AS Expected, a.score AS Score, a.peer_score AS PeerScore, a.severity AS Severity, a.kind AS Kind,
                   coalesce(k.status, a.status) AS Status, a.region_kato AS RegionKato, k.comment AS Comment
            FROM gold.anomalies a LEFT JOIN journal.anomaly_acks k ON k.anomaly_id = a.id
            {where}
            ORDER BY a.period DESC, abs(a.score) DESC
            LIMIT @size OFFSET @offset
            """,
            parameters, cancellationToken: cancellationToken));
        var items = rows.Select(r => new AnomalyDto(
            r.Id, r.StreamId, EntityJson.Parse(r.Entity), r.Period, r.Observed, r.Expected, r.Score, r.PeerScore,
            r.Severity, r.Kind, r.Status, r.RegionKato, r.Comment)).ToList();
        return new Paged<AnomalyDto>(items, page, size, total);
    }

    public async Task<bool> AcknowledgeAsync(string anomalyId, string status, string? comment, string actor, Func<object> outboxEvent, CancellationToken cancellationToken)
    {
        await using (var connection = await db.OpenAsync(cancellationToken))
        {
            var exists = await connection.ExecuteScalarAsync<bool>(new CommandDefinition(
                "SELECT EXISTS (SELECT 1 FROM gold.anomalies WHERE id = @anomalyId)", new { anomalyId }, cancellationToken: cancellationToken));
            if (!exists)
            {
                return false;
            }
        }

        var context = outbox.DbContext;
        var ack = await context.AnomalyAcks.FindAsync([anomalyId], cancellationToken);
        if (ack is null)
        {
            ack = new AnomalyAck { AnomalyId = anomalyId };
            context.AnomalyAcks.Add(ack);
        }

        ack.Status = status;
        ack.Comment = comment;
        ack.Actor = actor;
        ack.AckedAt = DateTime.UtcNow;
        await outbox.PublishAsync(outboxEvent());
        await outbox.SaveChangesAndFlushMessagesAsync(cancellationToken);
        return true;
    }

    public async Task<IReadOnlyList<string>> IndexMonthsAsync(CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        // месяц форматируется в SQL: Dapper читает date-скаляры ненадёжно
        var months = await connection.QueryAsync<string>(new CommandDefinition(
            "SELECT to_char(month, 'YYYY-MM') AS month FROM gold.access_index GROUP BY month ORDER BY month", cancellationToken: cancellationToken));
        return months.ToList();
    }

    public async Task<IReadOnlyList<IndexItemDto>> IndexAsync(string month, string profileCode, string lang, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        var monthStart = month + "-01"; // Dapper не передаёт DateOnly параметром, приводим в SQL
        var rows = await connection.QueryAsync<IndexRow>(new CommandDefinition(
            """
            SELECT i.region_kato AS RegionKato, coalesce(r.name_ru, i.region_kato) AS NameRu, coalesce(r.name_kz, r.name_ru, i.region_kato) AS NameKz,
                   i.share_over_30 AS ShareOver30, i.p90_days AS P90Days, i.index_value AS IndexValue, i.rank AS Rank, i.n AS N
            FROM gold.access_index i LEFT JOIN refdata.regions r ON r.region_kato = i.region_kato
            WHERE i.month = @monthStart::date AND i.profile_code = @profileCode
            ORDER BY i.rank
            """,
            new { monthStart, profileCode }, cancellationToken: cancellationToken));
        return rows.Select(r => new IndexItemDto(r.RegionKato, lang == Locale.Kk ? r.NameKz : r.NameRu, r.ShareOver30, r.P90Days, r.IndexValue, (int)r.Rank, r.N)).ToList();
    }

    public async Task<IReadOnlyDictionary<string, int>> AnomalyAckStatsAsync(CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        var rows = await connection.QueryAsync<(string Status, int N)>(new CommandDefinition(
            "SELECT status AS Status, count(*)::int AS N FROM journal.anomaly_acks GROUP BY status",
            cancellationToken: cancellationToken));
        return rows.ToDictionary(r => r.Status, r => r.N);
    }

    public async Task<IReadOnlyList<LosItemDto>> LosAsync(string? regionKato, string? profileCode, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        try
        {
            // приведения типов в SQL: DuckDB пишет BIGINT/DOUBLE, Dapper подбирает конструктор по точным типам
            var rows = await connection.QueryAsync<LosItemDto>(new CommandDefinition(
                """
                SELECT region_kato AS RegionKato, profile_name AS ProfileName, profile_code::text AS ProfileCode,
                       n::bigint AS N, los_median_fact::float8 AS LosMedianFact, los_p50_model::float8 AS LosP50Model
                FROM gold.los_by_profile
                WHERE (@regionKato IS NULL OR region_kato = @regionKato)
                  AND (@profileCode IS NULL OR profile_code = @profileCode)
                ORDER BY n DESC
                """,
                new { regionKato, profileCode }, cancellationToken: cancellationToken));
            return rows.ToList();
        }
        catch (Npgsql.PostgresException e) when (e.SqlState == "42P01")
        {
            // витрина ещё не опубликована — страница живёт без блока LOS
            return [];
        }
    }

    private sealed record StreamRow(string StreamId, string Title, string Grain, string EntityKeys, string Horizons);

    private sealed record AnomalyRow(
        string Id, string StreamId, string Entity, string Period, double Observed, double Expected, double Score, double PeerScore,
        string Severity, string Kind, string Status, string? RegionKato, string? Comment);

    private sealed record IndexRow(string RegionKato, string NameRu, string NameKz, double ShareOver30, double P90Days, double IndexValue, long Rank, long N);
}
