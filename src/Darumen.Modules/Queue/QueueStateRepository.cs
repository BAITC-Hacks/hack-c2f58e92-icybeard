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

    private sealed record SnapshotRow(long QueueLen, double? QueueAgeP50, double ThroughputPerDay);

    private sealed record DayRow(DateOnly Day, long Registered, long Hospitalized, long Refused, long QueueLen, double? QueueAgeP50);

    private sealed record ThroughputRow(DateOnly Day, double ThroughputPerDay, double? RefusalRate4w, double? WaitP50Days, double? WaitP90Days);
}
