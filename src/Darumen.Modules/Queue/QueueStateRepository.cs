using Dapper;
using Darumen.Shared.Data;

namespace Darumen.Modules.Queue;

/// <summary>Состояние очереди из витрин gold в Postgres (публикует darumen.lakehouse publish).</summary>
public sealed class QueueStateRepository(IDbConnectionFactory db) : IQueueStateRepository
{
    private const string DateFormat = "yyyy-MM-dd";

    public async Task<QueueSnapshotDto?> SnapshotAsync(string moCode, string profileCode, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        var row = await connection.QuerySingleOrDefaultAsync<SnapshotRow>(new CommandDefinition(
            """
            SELECT queue_len AS QueueLen, queue_age_p50 AS QueueAgeP50, throughput_per_day AS ThroughputPerDay
            FROM gold.queue_state WHERE mo_code = @moCode AND profile_code = @profileCode
            """,
            new { moCode, profileCode }, cancellationToken: cancellationToken));
        return row is null ? null : new QueueSnapshotDto((int)row.QueueLen, row.QueueAgeP50, row.ThroughputPerDay);
    }

    public async Task<OrganizationSeriesDto?> SeriesAsync(string moCode, string profileCode, int days, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        var rows = (await connection.QueryAsync<DayRow>(new CommandDefinition(
            """
            SELECT day AS Day, registered AS Registered, hospitalized AS Hospitalized, refused AS Refused,
                   queue_len AS QueueLen, queue_age_p50 AS QueueAgeP50
            FROM gold.queue_daily
            WHERE mo_code = @moCode AND profile_code = @profileCode
              AND day > (SELECT max(day) FROM gold.queue_daily WHERE mo_code = @moCode AND profile_code = @profileCode) - @days
            ORDER BY day
            """,
            new { moCode, profileCode, days }, cancellationToken: cancellationToken))).ToList();
        if (rows.Count == 0)
        {
            return null;
        }

        var throughput = await connection.QuerySingleOrDefaultAsync<ThroughputRow>(new CommandDefinition(
            """
            SELECT day AS Day, throughput_per_day AS ThroughputPerDay, refusal_rate_4w AS RefusalRate4w,
                   wait_p50_4w AS WaitP50Days, wait_p90_4w AS WaitP90Days
            FROM gold.throughput_4w WHERE mo_code = @moCode AND profile_code = @profileCode ORDER BY day DESC LIMIT 1
            """,
            new { moCode, profileCode }, cancellationToken: cancellationToken));

        return new OrganizationSeriesDto(
            moCode, profileCode,
            rows.Select(r => new QueueDayDto(r.Day.ToString(DateFormat), (int)r.Registered, (int)r.Hospitalized, (int)r.Refused, (int)r.QueueLen, r.QueueAgeP50)).ToList(),
            throughput is null ? null : new ThroughputDto(throughput.Day.ToString(DateFormat), throughput.ThroughputPerDay, throughput.RefusalRate4w, throughput.WaitP50Days, throughput.WaitP90Days));
    }

    /// <summary>Нагрузка = поток направлений в день (registered_4w / 28) делить на пропускную способность
    /// (throughput_per_day). Больше 1 — очередь растёт; throughput_per_day = 0 при живом потоке направлений —
    /// организация вообще не госпитализирует по профилю, это тоже перегрузка (Load = null, показывать как «нет
    /// госпитализаций», а не как обычное число).</summary>
    public async Task<IReadOnlyList<OverloadedOrganizationDto>> OverloadedAsync(string? regionKato, string? profileCode, int limit, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        var rows = await connection.QueryAsync<OverloadedOrganizationDto>(new CommandDefinition(
            """
            SELECT s.mo_code AS MoCode, r.name_canonical AS Name, s.region_kato AS RegionKato, s.profile_code AS ProfileCode,
                   CASE WHEN s.throughput_per_day > 0 THEN (s.registered_4w / 28.0) / s.throughput_per_day END AS Load,
                   s.queue_len::int AS QueueLen, s.queue_age_p90 AS QueueAgeP90, s.refusal_rate_4w AS RefusalRate4w
            FROM gold.queue_state s
            JOIN refdata.mo_registry r ON r.mo_code = s.mo_code
            WHERE (@regionKato IS NULL OR s.region_kato = @regionKato)
              AND (@profileCode IS NULL OR s.profile_code = @profileCode)
              AND s.registered_4w > 0
              AND (s.throughput_per_day = 0 OR (s.registered_4w / 28.0) / s.throughput_per_day > 1.0)
            ORDER BY (s.throughput_per_day = 0) DESC, Load DESC
            LIMIT @limit
            """,
            new { regionKato, profileCode, limit }, cancellationToken: cancellationToken));
        return rows.ToList();
    }

    private sealed record SnapshotRow(long QueueLen, double? QueueAgeP50, double ThroughputPerDay);

    private sealed record DayRow(DateOnly Day, long Registered, long Hospitalized, long Refused, long QueueLen, double? QueueAgeP50);

    private sealed record ThroughputRow(DateOnly Day, double ThroughputPerDay, double? RefusalRate4w, double? WaitP50Days, double? WaitP90Days);
}
