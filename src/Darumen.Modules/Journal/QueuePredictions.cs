using Darumen.Modules.Queue;
using Microsoft.Extensions.Caching.Memory;

namespace Darumen.Modules.Journal;

/// <summary>Прогнозы модели по очередям региона (mo_code, profile_code) для рабочего списка и выбора персоны гражданина.
/// Один прогноз на очередь, не на синтетического пациента (3.6): нескольким строкам списка одной очереди не нужен
/// отдельный вызов gRPC. Все очереди региона (в Алматы их 373) запрашиваются одним пакетным вызовом PredictQueues:
/// по два вызова на очередь упирались в дедлайн, весь список откатывался на агрегаты витрины, причём от запроса к запросу
/// по-разному. Успешные прогнозы кэшируются на срез витрины (<see cref="CacheFor"/>): состав и порядок списка стабильны
/// между запросами, а гражданин из /route/me — один из пациентов списка врача. Категориальные признаки запроса для
/// синтетических пациентов неизвестны — не выдумываем диагноз, дата регистрации — дата среза витрины, чтобы модель не
/// увидела признаки календаря за пределами обучения. Сервис моделей недоступен или не знает очередь — прогноза нет,
/// WorklistBuilder считает по агрегатам (<see cref="QueuePrediction.FromModel"/>), список не падает целиком.</summary>
public sealed class QueuePredictions(QueueService queueService, IMemoryCache cache)
{
    public static readonly TimeSpan CacheFor = TimeSpan.FromHours(1);
    /// <summary>Один пакетный вызов за раз: параллельные запросы ждут и берут результат первого из кэша.</summary>
    private static readonly SemaphoreSlim Gate = new(1, 1);

    public async Task<(IReadOnlyDictionary<(string MoCode, string ProfileCode), QueuePrediction> Predictions, bool ModelBacked)> ForQueuesAsync(
        IReadOnlyList<QueueStateRow> states, CancellationToken ct)
    {
        var predictions = new Dictionary<(string MoCode, string ProfileCode), QueuePrediction>();
        foreach (var batch in states.GroupBy(s => (s.RegionKato, s.AsOf)))
        {
            var queues = batch.Select(s => (s.MoCode, s.ProfileCode)).Distinct().ToList();
            var missing = queues.Where(q => !TryCached(batch.Key, q, predictions)).ToList();
            if (missing.Count == 0)
            {
                continue;
            }

            await Gate.WaitAsync(ct);
            try
            {
                // пока ждали очередь на вызов, параллельный запрос мог заполнить кэш
                missing = missing.Where(q => !TryCached(batch.Key, q, predictions)).ToList();
                if (missing.Count == 0)
                {
                    continue;
                }

                var forecasts = await queueService.PredictQueuesAsync(batch.Key.RegionKato, missing, batch.Key.AsOf.ToString("yyyy-MM-dd"), ct);
                foreach (var forecast in forecasts.Items)
                {
                    var prediction = new QueuePrediction(forecast.P50Days, forecast.P90Days, forecast.PRefusal, true);
                    // кэшируются только полученные прогнозы: недоступный сервис — не «нет прогноза на час», а повтор при следующем запросе
                    cache.Set(CacheKey(batch.Key, (forecast.MoCode, forecast.ProfileCode)), prediction, CacheFor);
                    predictions[(forecast.MoCode, forecast.ProfileCode)] = prediction;
                }
            }
            catch (Exception) when (!ct.IsCancellationRequested)
            {
                // сервис моделей недоступен — WorklistBuilder откатится на агрегаты витрины для очередей без прогноза
            }
            finally
            {
                Gate.Release();
            }
        }

        return (predictions, predictions.Count > 0);
    }

    private bool TryCached((string RegionKato, DateOnly AsOf) batch, (string MoCode, string ProfileCode) queue,
        Dictionary<(string MoCode, string ProfileCode), QueuePrediction> into)
    {
        if (!cache.TryGetValue(CacheKey(batch, queue), out QueuePrediction? cached) || cached is null)
        {
            return false;
        }

        into[queue] = cached;
        return true;
    }

    private static string CacheKey((string RegionKato, DateOnly AsOf) batch, (string MoCode, string ProfileCode) queue) =>
        $"queue-prediction|{batch.RegionKato}|{queue.MoCode}|{queue.ProfileCode}|{batch.AsOf:yyyy-MM-dd}";
}
