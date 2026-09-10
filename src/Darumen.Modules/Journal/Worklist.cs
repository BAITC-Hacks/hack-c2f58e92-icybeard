using Dapper;
using Darumen.Shared.Data;

namespace Darumen.Modules.Journal;

public sealed record WorklistItemDto(
    string PatientRef, bool Synthetic, string Stage, string? ExpectedDate, IReadOnlyList<string> RiskFlags, int Priority,
    string NextAction, string Explanation, string MoCode, string MoName, string ProfileCode, string RegionKato, int DaysWaiting);

public sealed record WorklistResponseDto(IReadOnlyList<WorklistItemDto> Items, bool Synthetic, string AsOf, string RegionKato);

/// <summary>Состояние очереди организации по профилю на дату среза (gold.queue_state + реестр).</summary>
public sealed record QueueStateRow(
    DateOnly AsOf, string MoCode, string MoName, string ProfileCode, string RegionKato, long QueueLen, double? QueueAgeP50, double? QueueAgeP90,
    double ThroughputPerDay, double? RefusalRate4w, double? WaitP50, double? WaitP90);

public interface IWorklistRepository
{
    Task<IReadOnlyList<QueueStateRow>> QueueStatesAsync(string regionKato, CancellationToken cancellationToken);
}

public sealed class WorklistRepository(IDbConnectionFactory db) : IWorklistRepository
{
    public async Task<IReadOnlyList<QueueStateRow>> QueueStatesAsync(string regionKato, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        var rows = await connection.QueryAsync<QueueStateRow>(new CommandDefinition(
            """
            SELECT q.as_of AS AsOf, q.mo_code AS MoCode, coalesce(m.name_canonical, q.mo_code) AS MoName, q.profile_code AS ProfileCode,
                   q.region_kato AS RegionKato, q.queue_len AS QueueLen, q.queue_age_p50 AS QueueAgeP50, q.queue_age_p90 AS QueueAgeP90,
                   q.throughput_per_day AS ThroughputPerDay, q.refusal_rate_4w AS RefusalRate4w, q.wait_p50_4w AS WaitP50, q.wait_p90_4w AS WaitP90
            FROM gold.queue_state q LEFT JOIN refdata.mo_registry m ON m.mo_code = q.mo_code
            WHERE q.region_kato = @regionKato AND q.queue_len > 0 AND q.profile_code <> 'DH'
            ORDER BY q.queue_len DESC
            """,
            new { regionKato }, cancellationToken: cancellationToken));
        return rows.ToList();
    }
}

/// <summary>Синтетический рабочий список врача: пациенты выдуманы, но их число, возраст ожидания и риски
/// взяты из реального состояния очередей региона. Детерминирован по организации и профилю.</summary>
public static class WorklistBuilder
{
    public const string StuckOver30 = "stuck_over_30";
    public const string RefusalRisk = "refusal_risk";
    public const string FasterAlternative = "faster_alternative";
    public const int MaxItems = 60;
    public const int MaxPerQueue = 6;
    public const double RefusalRiskThreshold = 0.2;
    public const double FasterByDays = 7;

    public static IReadOnlyList<WorklistItemDto> Build(IReadOnlyList<QueueStateRow> states, string? flag = null)
    {
        var total = states.Sum(s => s.QueueLen);
        if (total == 0)
        {
            return [];
        }

        var fastest = states.Where(s => s.WaitP50 is not null).GroupBy(s => s.ProfileCode)
            .ToDictionary(g => g.Key, g => g.Min(s => s.WaitP50!.Value));
        var items = new List<WorklistItemDto>();
        foreach (var state in states)
        {
            var count = (int)Math.Clamp(Math.Round(MaxItems * (double)state.QueueLen / total), 1, MaxPerQueue);
            for (var i = 0; i < count; i++)
            {
                items.Add(Item(state, i, fastest.GetValueOrDefault(state.ProfileCode, double.NaN)));
            }
        }

        var filtered = flag is null ? items : items.Where(i => i.RiskFlags.Contains(flag));
        return filtered.OrderByDescending(i => i.Priority).ThenByDescending(i => i.DaysWaiting).Take(MaxItems).ToList();
    }

    private static WorklistItemDto Item(QueueStateRow state, int index, double fastestP50)
    {
        var seed = Seed($"{state.MoCode}|{state.ProfileCode}|{index}");
        var p50 = state.QueueAgeP50 ?? 10;
        var p90 = Math.Max(state.QueueAgeP90 ?? p50 * 2, p50 + 1);
        // возраст ожидания: половина пациентов около медианы, хвост до p90 и дальше
        var quantile = (seed % 1000) / 1000.0;
        var daysWaiting = (int)Math.Round(quantile < 0.5 ? p50 * quantile * 2 : p50 + (p90 - p50) * (quantile - 0.5) * 2.4);
        var expectedWait = state.WaitP50 ?? p50;
        var flags = new List<string>();
        if (daysWaiting > 30)
        {
            flags.Add(StuckOver30);
        }

        if ((state.RefusalRate4w ?? 0) > RefusalRiskThreshold)
        {
            flags.Add(RefusalRisk);
        }

        if (!double.IsNaN(fastestP50) && state.WaitP50 is not null && state.WaitP50.Value - fastestP50 > FasterByDays)
        {
            flags.Add(FasterAlternative);
        }

        var remaining = Math.Max(0, expectedWait - daysWaiting);
        var stage = daysWaiting == 0 ? "зарегистрирован" : remaining <= 3 ? "вызов на госпитализацию" : "ожидает";
        var priority = (int)Math.Round(daysWaiting / 7.0) + flags.Count * 2;
        var nextAction = flags.Contains(FasterAlternative)
            ? "предложить перенаправление в организацию с меньшим ожиданием"
            : flags.Contains(RefusalRisk)
                ? "проверить показания и документы до вызова"
                : flags.Contains(StuckOver30)
                    ? "уточнить дату в организации"
                    : "ждать вызова";
        var explanation = $"очередь {state.QueueLen} направлений, медианное ожидание {expectedWait:0} дн., " +
                          $"отказы за 4 недели {(state.RefusalRate4w ?? 0):P0}";
        return new WorklistItemDto(
            $"SYN-{state.RegionKato}-{state.MoCode}-{index + 1:00}", true, stage,
            state.AsOf.AddDays((int)Math.Round(remaining)).ToString("yyyy-MM-dd"), flags, priority, nextAction, explanation,
            state.MoCode, state.MoName, state.ProfileCode, state.RegionKato, daysWaiting);
    }

    private static uint Seed(string key)
    {
        uint hash = 2166136261;
        foreach (var c in key)
        {
            hash = (hash ^ c) * 16777619;
        }

        return hash;
    }
}
