using Dapper;
using Darumen.Modules.Queue;
using Darumen.Shared.Data;

namespace Darumen.Modules.Journal;

/// <summary>3.6: прогноз ожидания и риска отказа от модели (QueueIntelligence) для одной очереди
/// (организация × профиль), с которым строится приоритет рабочего списка. Категориальные признаки запроса
/// (МКБ-10, цель, город/село, источник финансирования) не известны для синтетических пациентов рабочего
/// списка — берутся типичные значения (см. WorklistPrediction.TypicalRequest), это не выдаётся за прогноз
/// по конкретному диагнозу пациента, только за оценку по организации и профилю.</summary>
public sealed record QueuePrediction(double P50Days, double P90Days, double PRefusal, bool FromModel);

/// <summary>Stage — подпись стадии по-русски для текущих клиентов; StageCode — машинный код той же стадии
/// (<see cref="WorklistBuilder.StageRegistered"/>, <see cref="WorklistBuilder.StageWaiting"/>, <see cref="WorklistBuilder.StageCalled"/>),
/// который клиенты локализуют сами (RU/KK); та же пара для следующего шага — NextAction (по-русски) и NextActionCode
/// (<see cref="WorklistBuilder.ActionRedirectFaster"/> и другие Action*). PatientRef — см. <see cref="RoutePatientRef"/>.</summary>
public sealed record WorklistItemDto(
    string PatientRef, bool Synthetic, string Stage, string StageCode, string? ExpectedDate, IReadOnlyList<string> RiskFlags, int Priority,
    string NextAction, string NextActionCode, string Explanation, string MoCode, string MoName, string ProfileCode, string RegionKato, int DaysWaiting);

/// <summary>ModelBacked — прогноз модели получен хотя бы для одной очереди (иначе показывать в UI
/// как формулу/агрегаты, а не как «ML-модель», см. WorklistView.vue).</summary>
public sealed record WorklistResponseDto(IReadOnlyList<WorklistItemDto> Items, bool Synthetic, string AsOf, string RegionKato, bool ModelBacked);

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

    /// <summary>Коды следующего шага (NextActionCode) по флагам, от сильного к слабому; подписи RU/KK — на клиентах.</summary>
    public const string ActionRedirectFaster = "redirect_faster";
    public const string ActionReviewBeforeCall = "review_before_call";
    public const string ActionClarifyDate = "clarify_date";
    public const string ActionWaitForCall = "wait_for_call";
    public const int MaxItems = 60;
    public const int MaxPerQueue = 6;
    public const double RefusalRiskThreshold = 0.2;
    public const double FasterByDays = 7;
    public const string StageRegistered = "registered";
    public const string StageWaiting = "waiting";
    public const string StageCalled = "called";

    /// <summary>predictions — прогноз модели по одной очереди (mo_code, profile_code), см. <see cref="QueuePrediction"/>.
    /// Приоритет и флаг риска отказа считаются по нему, а не по формуле на сырых полях витрины (3.6): при
    /// отсутствии прогноза для очереди (сервис моделей недоступен) используется тот же расчёт с агрегатами
    /// витрины вместо прогноза, помеченный FromModel = false — так метка «ML-модель» на экране остаётся честной
    /// (см. WorklistResponseDto.ModelBacked).</summary>
    public static IReadOnlyList<WorklistItemDto> Build(
        IReadOnlyList<QueueStateRow> states, IReadOnlyDictionary<(string MoCode, string ProfileCode), QueuePrediction> predictions, string? flag = null)
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
            var prediction = predictions.GetValueOrDefault((state.MoCode, state.ProfileCode)) ?? Fallback(state);
            var count = CountFor(state, total);
            for (var i = 0; i < count; i++)
            {
                items.Add(BuildItem(state, i, prediction, fastest.GetValueOrDefault(state.ProfileCode, double.NaN)));
            }
        }

        var filtered = flag is null ? items : items.Where(i => i.RiskFlags.Contains(flag));
        return filtered.OrderByDescending(i => i.Priority).ThenByDescending(i => i.DaysWaiting).Take(MaxItems).ToList();
    }

    /// <summary>Сколько синтетических пациентов приходится на очередь: пропорционально её доле в регионе, от 1 до
    /// MaxPerQueue. Публично, чтобы маршрут (/route/{patientRef}) проверял, существует ли номер пациента в очереди.</summary>
    public static int CountFor(QueueStateRow state, long total) =>
        total <= 0 ? 0 : (int)Math.Clamp(Math.Round(MaxItems * (double)state.QueueLen / total), 1, MaxPerQueue);

    /// <summary>Минимальное медианное ожидание по профилю среди организаций региона (флаг «есть быстрее»); NaN без данных.</summary>
    public static double FastestP50(IReadOnlyList<QueueStateRow> states, string profileCode)
    {
        var known = states.Where(s => s.ProfileCode == profileCode && s.WaitP50 is not null).Select(s => s.WaitP50!.Value).ToList();
        return known.Count == 0 ? double.NaN : known.Min();
    }

    /// <summary>Прогноз недоступен (сервис моделей упал или организация вне обучения) — тот же расчёт,
    /// что был единственным до 3.6, на агрегатах витрины вместо модели; FromModel = false.</summary>
    public static QueuePrediction Fallback(QueueStateRow state)
    {
        var p50 = state.QueueAgeP50 ?? 10;
        return new QueuePrediction(state.WaitP50 ?? p50, state.WaitP90 ?? p50 * 2, state.RefusalRate4w ?? 0, false);
    }

    /// <summary>Одна строка рабочего списка: index — номер пациента в очереди (0..CountFor−1), реф получает index+1.
    /// Публично, чтобы маршрут регенерировал ту же строку по рефу без пересборки всего списка.</summary>
    public static WorklistItemDto BuildItem(QueueStateRow state, int index, QueuePrediction prediction, double fastestP50)
    {
        var seed = Seed($"{state.MoCode}|{state.ProfileCode}|{index}");
        var p50 = state.QueueAgeP50 ?? 10;
        var p90 = Math.Max(state.QueueAgeP90 ?? p50 * 2, p50 + 1);
        // возраст ожидания: половина пациентов около медианы, хвост до p90 и дальше (из фактической витрины очереди,
        // не из прогноза — сколько пациент УЖЕ ждёт, это наблюдаемый факт, а не оценка модели)
        var quantile = (seed % 1000) / 1000.0;
        var daysWaiting = (int)Math.Round(quantile < 0.5 ? p50 * quantile * 2 : p50 + (p90 - p50) * (quantile - 0.5) * 2.4);
        var expectedWait = prediction.P50Days;
        var flags = new List<string>();
        if (daysWaiting > 30)
        {
            flags.Add(StuckOver30);
        }

        if (prediction.PRefusal > RefusalRiskThreshold)
        {
            flags.Add(RefusalRisk);
        }

        if (!double.IsNaN(fastestP50) && state.WaitP50 is not null && state.WaitP50.Value - fastestP50 > FasterByDays)
        {
            flags.Add(FasterAlternative);
        }

        var remaining = Math.Max(0, expectedWait - daysWaiting);
        var stageCode = daysWaiting == 0 ? StageRegistered : remaining <= 3 ? StageCalled : StageWaiting;
        var stage = stageCode switch
        {
            StageRegistered => "зарегистрирован",
            StageCalled => "вызов на госпитализацию",
            _ => "ожидает",
        };
        // 3.6: приоритет = насколько пациент уже пережидает прогноз модели (не абсолютные дни) + предсказанный
        // моделью риск отказа — оба слагаемых из прогноза, а не только число флагов, как было до 3.6
        var overdue = expectedWait > 0 ? daysWaiting / expectedWait : (daysWaiting > 0 ? 2.0 : 0.0);
        var priority = (int)Math.Round(overdue * 5) + (int)Math.Round(prediction.PRefusal * 10) + (flags.Contains(FasterAlternative) ? 2 : 0);
        var nextActionCode = flags.Contains(FasterAlternative) ? ActionRedirectFaster
            : flags.Contains(RefusalRisk) ? ActionReviewBeforeCall
            : flags.Contains(StuckOver30) ? ActionClarifyDate
            : ActionWaitForCall;
        var nextAction = nextActionCode switch
        {
            ActionRedirectFaster => "предложить перенаправление в организацию с меньшим ожиданием",
            ActionReviewBeforeCall => "проверить показания и документы до вызова",
            ActionClarifyDate => "уточнить дату в организации",
            _ => "ждать вызова",
        };
        var explanation = $"очередь {state.QueueLen} направлений, {(prediction.FromModel ? "прогноз ожидания" : "медианное ожидание")} {expectedWait:0} дн., " +
                          $"{(prediction.FromModel ? "прогноз риска отказа" : "отказы за 4 недели")} {prediction.PRefusal:P0}";
        return new WorklistItemDto(
            new RoutePatientRef(state.RegionKato, state.MoCode, state.ProfileCode, index + 1).Format(), true, stage, stageCode,
            state.AsOf.AddDays((int)Math.Round(remaining)).ToString("yyyy-MM-dd"), flags, priority, nextAction, nextActionCode, explanation,
            state.MoCode, state.MoName, state.ProfileCode, state.RegionKato, daysWaiting);
    }

    /// <summary>FNV-1a: детерминированный сид по строковому ключу (та же функция нужна маршруту для дат и истории).</summary>
    public static uint Seed(string key)
    {
        uint hash = 2166136261;
        foreach (var c in key)
        {
            hash = (hash ^ c) * 16777619;
        }

        return hash;
    }
}
