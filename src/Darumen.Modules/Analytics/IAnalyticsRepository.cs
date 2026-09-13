using Darumen.Shared.Api;

namespace Darumen.Modules.Analytics;

public interface IAnalyticsRepository
{
    Task<IReadOnlyList<StreamDto>> StreamsAsync(CancellationToken cancellationToken);

    Task<IReadOnlyList<HistoryPointDto>> HistoryAsync(string streamId, string entityJson, int periods, CancellationToken cancellationToken);

    Task<Paged<AnomalyDto>> AnomaliesAsync(AnomalyFilter filter, int page, int size, CancellationToken cancellationToken);

    /// <summary>Подтверждение и событие в одной транзакции (outbox); false, когда такого сигнала нет.</summary>
    Task<bool> AcknowledgeAsync(string anomalyId, string status, string? comment, string actor, Func<object> outboxEvent, CancellationToken cancellationToken);

    Task<IReadOnlyList<string>> IndexMonthsAsync(CancellationToken cancellationToken);

    Task<IReadOnlyList<IndexItemDto>> IndexAsync(string month, string profileCode, string lang, CancellationToken cancellationToken);

    /// <summary>Разметка сигналов людьми: сколько подтверждено/закрыто. Метки для будущей точности детектора.</summary>
    Task<IReadOnlyDictionary<string, int>> AnomalyAckStatsAsync(CancellationToken cancellationToken);
}
