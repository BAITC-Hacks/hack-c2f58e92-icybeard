using System.Text.Json;
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
              AND (@moCode IS NULL OR a.mo_code = @moCode)
            """;
        var parameters = new
        {
            regionKato = filter.RegionKato,
            streamId = filter.StreamId,
            severity = filter.Severity,
            status = filter.Status,
            moCode = filter.MoCode,
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
                   coalesce(k.status, a.status) AS Status, a.region_kato AS RegionKato, k.comment AS Comment, a.mo_code AS MoCode,
                   a.affected AS Affected
            FROM gold.anomalies a LEFT JOIN journal.anomaly_acks k ON k.anomaly_id = a.id
            {where}
            ORDER BY a.period DESC, abs(a.score) DESC
            LIMIT @size OFFSET @offset
            """,
            parameters, cancellationToken: cancellationToken));
        var items = rows.Select(r => new AnomalyDto(
            r.Id, r.StreamId, EntityJson.Parse(r.Entity), r.Period, r.Observed, r.Expected, r.Score, r.PeerScore,
            r.Severity, r.Kind, r.Status, r.RegionKato, r.Comment, r.MoCode, r.Affected)).ToList();
        return new Paged<AnomalyDto>(items, page, size, total);
    }

    public async Task<AckOutcome> AcknowledgeAsync(AnomalyAckCommand command, Func<object> outboxEvent, CancellationToken cancellationToken)
    {
        await using (var connection = await db.OpenAsync(cancellationToken))
        {
            var signal = await connection.QueryFirstOrDefaultAsync<SignalScopeRow>(new CommandDefinition(
                "SELECT region_kato AS RegionKato FROM gold.anomalies WHERE id = @anomalyId",
                new { anomalyId = command.AnomalyId }, cancellationToken: cancellationToken));
            if (signal is null)
            {
                return AckOutcome.NotFound;
            }

            if (command.RegionScope is not null && signal.RegionKato != command.RegionScope)
            {
                return AckOutcome.OutOfScope;
            }
        }

        var context = outbox.DbContext;
        var now = DateTime.UtcNow;
        var ack = await context.AnomalyAcks.FindAsync([command.AnomalyId], cancellationToken);
        if (ack is null)
        {
            ack = new AnomalyAck { AnomalyId = command.AnomalyId };
            context.AnomalyAcks.Add(ack);
        }

        ack.Status = command.Status;
        ack.Comment = command.Comment;
        ack.Actor = command.Actor;
        ack.AckedAt = now;

        // решение по сигналу видно в общем журнале рядом с решениями врачей: рекомендация системы — «открыт», выбор человека — статус
        context.Decisions.Add(new Decision
        {
            Id = Guid.NewGuid(),
            Actor = command.Actor,
            Role = command.Role,
            Subject = DecisionSubjects.Anomaly,
            SubjectId = command.AnomalyId,
            Recommended = StatusJson(AnomalyStatuses.Open),
            Chosen = StatusJson(command.Status),
            Reason = command.Comment,
            RecordedAt = now,
        });

        await outbox.PublishAsync(outboxEvent());
        await outbox.SaveChangesAndFlushMessagesAsync(cancellationToken);
        return AckOutcome.Acknowledged;
    }

    private static string StatusJson(string status) => JsonSerializer.Serialize(new { status });

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

    public async Task<IReadOnlyList<StaffingRegionDto>> StaffingByRegionAsync(CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        try
        {
            // total_rate — сумма занимаемых ставок на дату снапшота (gold.staffing_by_region, 5.2); знаменатели считаются
            // здесь: население региона из refdata.regions, госпитализации — сумма cases за последние 12 месяцев из
            // gold.admissions_monthly относительно последнего загруженного месяца (последний месяц может быть неполным,
            // но так же считается forecast/index, оставляем единообразно).
            var rows = await connection.QueryAsync<StaffingRegionDto>(new CommandDefinition(
                """
                WITH latest AS (SELECT max(month) AS last_month FROM gold.admissions_monthly),
                admissions_12m AS (
                    SELECT a.region_kato, sum(a.cases)::float8 AS admissions
                    FROM gold.admissions_monthly a, latest
                    WHERE a.month > latest.last_month - INTERVAL '12 months'
                    GROUP BY a.region_kato
                )
                SELECT s.region_kato AS RegionKato, r.name_ru AS RegionName,
                       (s.total_rate::float8 * 10.0) / r.population_thousands AS RatePer10kPopulation,
                       CASE WHEN a.admissions > 0 THEN (s.total_rate::float8 * 1000.0) / a.admissions END AS RatePer1000Admissions,
                       s.snapshot_date AS SnapshotDate
                FROM gold.staffing_by_region s
                JOIN refdata.regions r ON r.region_kato = s.region_kato
                LEFT JOIN admissions_12m a ON a.region_kato = s.region_kato
                ORDER BY RatePer10kPopulation ASC
                """,
                cancellationToken: cancellationToken));
            return rows.ToList();
        }
        catch (Npgsql.PostgresException e) when (e.SqlState == "42P01")
        {
            // витрина ещё не опубликована — страница /gov живёт без блока кадров
            return [];
        }
    }

    public async Task<VacRefusalsDto> VaccinationRefusalsAsync(CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        try
        {
            // общенациональные разбивки: у vac_refusals нет колонки региона и нет организации, из которой
            // регион можно было бы вывести — две отдельные таблицы (5.8), не джойн по строке
            var byReason = await connection.QueryAsync<VacRefusalReasonDto>(new CommandDefinition(
                "SELECT reason AS Reason, n::bigint AS N FROM gold.vac_refusals_by_reason ORDER BY n DESC",
                cancellationToken: cancellationToken));
            var byContraindication = await connection.QueryAsync<VacRefusalContraindicationDto>(new CommandDefinition(
                "SELECT contraindication AS Contraindication, n::bigint AS N FROM gold.vac_refusals_by_contraindication ORDER BY n DESC",
                cancellationToken: cancellationToken));
            return new VacRefusalsDto(byReason.ToList(), byContraindication.ToList());
        }
        catch (Npgsql.PostgresException e) when (e.SqlState == "42P01")
        {
            // витрина ещё не опубликована — страница /gov живёт без блока по вакцинации
            return new VacRefusalsDto([], []);
        }
    }

    public async Task<IReadOnlyList<OncoLateItemDto>> OncologyLateStageAsync(CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        try
        {
            // gold.onco_late уже общенациональный агрегат по локализации (grain контракта) — региона в источнике нет
            var rows = await connection.QueryAsync<OncoLateItemDto>(new CommandDefinition(
                """
                SELECT localization_id AS LocalizationId, localization_name AS LocalizationName, icd_code AS IcdCode,
                       total_patients::bigint AS TotalPatients,
                       advanced_stage_3_count::bigint AS AdvancedStage3Count, advanced_stage_3_pct::float8 AS AdvancedStage3Pct,
                       advanced_stage_4_count::bigint AS AdvancedStage4Count, advanced_stage_4_pct::float8 AS AdvancedStage4Pct,
                       advanced_total_count::bigint AS AdvancedTotalCount, advanced_share::float8 AS AdvancedShare,
                       snapshot_date AS SnapshotDate
                FROM gold.onco_late
                ORDER BY advanced_share DESC NULLS LAST
                """,
                cancellationToken: cancellationToken));
            return rows.ToList();
        }
        catch (Npgsql.PostgresException e) when (e.SqlState == "42P01")
        {
            // витрина ещё не опубликована — страница /gov живёт без блока по онкологии
            return [];
        }
    }

    private sealed record SignalScopeRow(string? RegionKato);

    private sealed record StreamRow(string StreamId, string Title, string Grain, string EntityKeys, string Horizons);

    private sealed record AnomalyRow(
        string Id, string StreamId, string Entity, string Period, double Observed, double Expected, double Score, double PeerScore,
        string Severity, string Kind, string Status, string? RegionKato, string? Comment, string? MoCode, int? Affected);

    private sealed record IndexRow(string RegionKato, string NameRu, string NameKz, double ShareOver30, double P90Days, double IndexValue, long Rank, long N);
}
