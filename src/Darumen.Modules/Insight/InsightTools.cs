using System.ComponentModel;
using System.Text.Json;
using Darumen.Contracts.V1;
using Darumen.Modules.Analytics;
using Darumen.Modules.Medicines;
using Darumen.Modules.Queue;
using Darumen.Modules.RefData;
using Darumen.Shared.Api;
using Darumen.Shared.Options;
using Microsoft.Extensions.AI;
using Microsoft.Extensions.Options;

namespace Darumen.Modules.Insight;

/// <summary>Инструменты модели: только сервисы доменов, никакого доступа к сырым данным. Каждый вызов оставляет
/// след для ответа (какие инструменты использованы, какой график показать).</summary>
public sealed class InsightTools(
    IAnalyticsRepository analytics,
    IRefDataRepository refData,
    IQueueStateRepository queueStates,
    QueueService queueService,
    Contracts.V1.Simulation.SimulationClient simulation,
    LoadForecasting.LoadForecastingClient forecasting,
    MedicinesService medicines,
    IOptions<ModelServicesOptions> modelServices)
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web) { WriteIndented = false };

    public List<string> Used { get; } = [];

    public ChartDto? Chart { get; private set; }

    public IReadOnlyList<AITool> All() =>
    [
        AIFunctionFactory.Create(AccessIndexAsync, "access_index", "Индекс доступности плановой госпитализации по регионам за месяц (YYYY-MM) и профилю койки (код или all). Возвращает рейтинг регионов."),
        AIFunctionFactory.Create(RegionsAsync, "regions", "Справочник регионов: код КАТО, название, столица."),
        AIFunctionFactory.Create(ProfilesAsync, "bed_profiles", "Справочник профилей коек: код и название."),
        AIFunctionFactory.Create(OrganizationsAsync, "organizations", "Организации региона с очередью по профилю, сначала самые загруженные."),
        AIFunctionFactory.Create(QueueStateAsync, "queue_state", "Текущее состояние очереди организации по профилю: длина, возраст, пропускная способность, факт ожидания."),
        AIFunctionFactory.Create(PredictWaitAsync, "predict_wait", "Прогноз ожидания (p50, p90 дней), вероятности госпитализации за 30 дней и отказа для региона и профиля, опционально организации."),
        AIFunctionFactory.Create(AnomaliesAsync, "anomalies", "Открытые сигналы аномалий по региону (код КАТО, опционально) и уровню (critical, warning)."),
        AIFunctionFactory.Create(ForecastAsync, "forecast", "Прогноз потока: admissions_monthly (госпитализации по региону и профилю), er_visits_daily (приёмный покой по региону и организации mo_key), vac_monthly (вакцинация по региону и плану)."),
        AIFunctionFactory.Create(SimulateAsync, "simulate", "Сценарий для региона и профиля: изменение мощности в процентах и доля перенаправленных направлений; возвращает ожидание до и после."),
        AIFunctionFactory.Create(MedicinesCheckAsync, "medicines_check", "Покрытие, сроки обеспечения и признаки дефицита по нозологии и МНН (идентификаторы)."),
    ];

    /// <summary>Ответ инструмента ограничен по размеру: локальные модели работают с контекстом 16k, куда должны
    /// поместиться десять схем инструментов, вопрос и несколько ответов подряд.</summary>
    public const int MaxToolResultChars = 6000;

    private string Track(string name, object payload)
    {
        Used.Add(name);
        var json = JsonSerializer.Serialize(payload, Json);
        return json.Length <= MaxToolResultChars ? json : json[..MaxToolResultChars] + "…(обрезано)";
    }

    private static string Short(string? text, int max = 70) => text is null ? string.Empty : text.Length <= max ? text : text[..max] + "…";

    [Description("Индекс доступности за месяц по профилю")]
    private async Task<string> AccessIndexAsync([Description("Месяц YYYY-MM; пусто = последний")] string? month, [Description("Код профиля койки или all")] string? profileCode, CancellationToken ct)
    {
        var months = await analytics.IndexMonthsAsync(ct);
        if (months.Count == 0)
        {
            return Track("access_index", new { error = "индекс не рассчитан" });
        }

        var chosen = string.IsNullOrWhiteSpace(month) || !months.Contains(month) ? months[^1] : month;
        var items = await analytics.IndexAsync(chosen, string.IsNullOrWhiteSpace(profileCode) ? AnalyticsEndpoints.AllProfiles : profileCode, Locale.Ru, ct);
        Chart = new ChartDto("bar", $"Индекс доступности, {chosen}", items.Select(i => i.Name).ToList(), [new ChartSeriesDto("индекс", items.Select(i => (double?)i.IndexValue).ToList())]);
        return Track("access_index", new { month = chosen, items = items.Select(i => new { i.RegionKato, i.Name, i.IndexValue, i.Rank, shareOver30 = Math.Round(i.ShareOver30, 3), i.P90Days, i.N }) });
    }

    private async Task<string> RegionsAsync(CancellationToken ct) =>
        Track("regions", (await refData.RegionsAsync(Locale.Ru, ct)).Select(r => new { r.RegionKato, r.Name, r.Capital }));

    private async Task<string> ProfilesAsync(CancellationToken ct) =>
        Track("bed_profiles", (await refData.ProfilesAsync(ct)).Take(60).Select(p => new { p.ProfileCode, p.Name, p.Referrals }));

    private async Task<string> OrganizationsAsync([Description("Код региона КАТО")] string regionKato, [Description("Код профиля койки")] string profileCode, CancellationToken ct) =>
        Track("organizations", (await refData.OrganizationsAsync(regionKato, null, profileCode, 10, ct)).Select(o => new { o.MoCode, name = Short(o.Name), o.MoType }));

    private async Task<string> QueueStateAsync([Description("Код организации")] string moCode, [Description("Код профиля койки")] string profileCode, CancellationToken ct)
    {
        var series = await queueStates.SeriesAsync(moCode, profileCode, 30, ct);
        if (series is null)
        {
            return Track("queue_state", new { error = "нет ряда очереди" });
        }

        Chart = new ChartDto("line", $"Очередь {moCode}, профиль {profileCode}", series.Days.Select(d => d.Day).ToList(), [new ChartSeriesDto("очередь", series.Days.Select(d => (double?)d.QueueLen).ToList())]);
        var last = series.Days[^1];
        return Track("queue_state", new { moCode, profileCode, last.Day, last.QueueLen, last.QueueAgeP50, series.Throughput });
    }

    private async Task<string> PredictWaitAsync([Description("Код региона КАТО")] string regionKato, [Description("Код профиля койки")] string profileCode, [Description("Код организации, пусто = по региону")] string? moCode, CancellationToken ct)
    {
        var response = await queueService.PredictAsync(new PredictRequestDto(regionKato, moCode, profileCode, null, null, null, null, null), Locale.Ru, ct);
        return Track("predict_wait", new { p50Days = Math.Round(response.P50Days, 1), p90Days = Math.Round(response.P90Days, 1), pWithin30Days = Math.Round(response.PWithin30Days, 3), pRefusal = Math.Round(response.PRefusal, 3), response.Queue, summary = Short(response.Explanation.Summary, 200) });
    }

    private async Task<string> AnomaliesAsync([Description("Код региона КАТО, пусто = все")] string? regionKato, [Description("critical или warning, пусто = все")] string? severity, CancellationToken ct)
    {
        var page = await analytics.AnomaliesAsync(new AnomalyFilter(string.IsNullOrWhiteSpace(regionKato) ? null : regionKato, null, string.IsNullOrWhiteSpace(severity) ? null : severity, "open"), 1, 8, ct);
        return Track("anomalies", new { page.Total, items = page.Items.Select(a => new { a.StreamId, entity = string.Join(" / ", a.Entity.Values.Select(v => Short(v, 40))), a.Period, observed = Math.Round(a.Observed), expected = Math.Round(a.Expected), score = Math.Round(a.Score, 1), a.Severity, a.Kind }) });
    }

    private async Task<string> ForecastAsync([Description("streamId: admissions_monthly, er_visits_daily или vac_monthly")] string streamId, [Description("Код региона КАТО")] string regionKato, [Description("Второй ключ сущности: profile_code, mo_key или vaccination_plan")] string? secondKey, CancellationToken ct)
    {
        var stream = (await analytics.StreamsAsync(ct)).FirstOrDefault(s => s.StreamId == streamId);
        if (stream is null)
        {
            return Track("forecast", new { error = "неизвестный поток" });
        }

        var entity = new Dictionary<string, string> { [stream.EntityKeys[0]] = regionKato };
        if (stream.EntityKeys.Count > 1)
        {
            entity[stream.EntityKeys[1]] = secondKey ?? string.Empty;
        }

        var request = new ForecastRequest { StreamId = streamId, Horizon = 0 };
        foreach (var (key, value) in entity)
        {
            request.Entity[key] = value;
        }

        try
        {
            var response = await forecasting.ForecastAsync(request, deadline: DateTime.UtcNow.AddSeconds(modelServices.Value.TimeoutSeconds), cancellationToken: ct);
            var history = await analytics.HistoryAsync(streamId, EntityJson.Canonical(stream.EntityKeys, entity), 12, ct);
            var x = history.Select(h => h.Period).Concat(response.Points.Select(p => p.Period)).ToList();
            Chart = new ChartDto("line", $"{stream.Title}: {regionKato} {secondKey}", x,
            [
                new ChartSeriesDto("факт", history.Select(h => (double?)h.Y).Concat(response.Points.Select(_ => (double?)null)).ToList()),
                new ChartSeriesDto("прогноз", history.Select(_ => (double?)null).Concat(response.Points.Select(p => (double?)p.Yhat)).ToList()),
            ]);
            return Track("forecast", new { streamId, entity, points = response.Points.Take(13).Select(p => new { p.Period, yhat = Math.Round(p.Yhat), lo = Math.Round(p.Lo), hi = Math.Round(p.Hi) }), history = history.TakeLast(6).Select(h => new { h.Period, y = Math.Round(h.Y) }), backtest = new { smape = Math.Round(response.Backtest.Smape, 3), mase = Math.Round(response.Backtest.Mase, 3) } });
        }
        catch (Grpc.Core.RpcException exception)
        {
            return Track("forecast", new { error = exception.Status.Detail });
        }
    }

    private async Task<string> SimulateAsync([Description("Код региона КАТО")] string regionKato, [Description("Код профиля койки")] string profileCode, [Description("Изменение мощности, %")] double capacityDeltaPct, [Description("Доля перенаправленных направлений, %")] double redirectSharePct, CancellationToken ct)
    {
        try
        {
            var response = await simulation.SimulateAsync(new SimulateRequest { Region = new RegionRef { Kato = regionKato }, ProfileCode = profileCode, CapacityDeltaPct = capacityDeltaPct, RedirectSharePct = redirectSharePct },
                deadline: DateTime.UtcNow.AddSeconds(modelServices.Value.TimeoutSeconds), cancellationToken: ct);
            return Track("simulate", new { response.Organisations, baseline = response.Baseline.MeanWaitDays, scenario = response.Scenario.MeanWaitDays, response.DeltaDays, ci = new[] { response.CiLow, response.CiHigh } });
        }
        catch (Grpc.Core.RpcException exception)
        {
            return Track("simulate", new { error = exception.Status.Detail });
        }
    }

    private async Task<string> MedicinesCheckAsync([Description("Идентификатор нозологии")] string? nosologyId, [Description("Идентификатор МНН")] string? mnnId, CancellationToken ct)
    {
        var response = await medicines.CheckAsync(new CheckRequestDto(mnnId, nosologyId, null), ct);
        return Track("medicines_check", new { response.Covered, response.Program, response.FillDaysP50, response.FillDaysP90, response.PFilled14d, response.Shortage, response.Basis });
    }
}
