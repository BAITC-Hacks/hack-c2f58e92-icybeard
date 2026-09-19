using Darumen.Shared.Api;

namespace Darumen.Modules.Analytics;

public interface IAnalyticsRepository
{
    Task<IReadOnlyList<StreamDto>> StreamsAsync(CancellationToken cancellationToken);

    Task<IReadOnlyList<HistoryPointDto>> HistoryAsync(string streamId, string entityJson, int periods, CancellationToken cancellationToken);

    Task<Paged<AnomalyDto>> AnomaliesAsync(AnomalyFilter filter, int page, int size, CancellationToken cancellationToken);

    /// <summary>Подтверждение, запись в журнал решений и событие в одной транзакции (outbox).
    /// NotFound — сигнала нет; OutOfScope — сигнал вне региона пользователя, ничего не записано.</summary>
    Task<AckOutcome> AcknowledgeAsync(AnomalyAckCommand command, Func<object> outboxEvent, CancellationToken cancellationToken);

    Task<IReadOnlyList<string>> IndexMonthsAsync(CancellationToken cancellationToken);

    Task<IReadOnlyList<IndexItemDto>> IndexAsync(string month, string profileCode, string lang, CancellationToken cancellationToken);

    /// <summary>Разметка сигналов людьми: сколько подтверждено/закрыто. Метки для будущей точности детектора.</summary>
    Task<IReadOnlyDictionary<string, int>> AnomalyAckStatsAsync(CancellationToken cancellationToken);

    /// <summary>Длительность лечения по ячейкам регион×профиль из gold.los_by_profile; пусто, пока витрина не опубликована.</summary>
    Task<IReadOnlyList<LosItemDto>> LosAsync(string? regionKato, string? profileCode, CancellationToken cancellationToken);

    /// <summary>5.2: ставки на 10 тыс. населения и на 1 000 госпитализаций по регионам, для сравнения на /gov;
    /// пусто, пока gold.staffing_by_region не опубликован.</summary>
    Task<IReadOnlyList<StaffingRegionDto>> StaffingByRegionAsync(CancellationToken cancellationToken);

    /// <summary>5.8: отказы от вакцинации по причине и по противопоказанию, общенационально (нет региона в источнике);
    /// пустые списки, пока gold.vac_refusals_by_reason/_by_contraindication не опубликованы.</summary>
    Task<VacRefusalsDto> VaccinationRefusalsAsync(CancellationToken cancellationToken);

    /// <summary>5.8: доля запущенных случаев (III/IV стадии) по локализациям, общенационально из gold.onco_late;
    /// пусто, пока витрина не опубликована.</summary>
    Task<IReadOnlyList<OncoLateItemDto>> OncologyLateStageAsync(CancellationToken cancellationToken);

    /// <summary>5.10: число единиц активной медтехники по регионам, для сравнения на /gov, из gold.equipment_by_region;
    /// пусто, пока витрина не опубликована.</summary>
    Task<IReadOnlyList<EquipmentRegionDto>> EquipmentByRegionAsync(CancellationToken cancellationToken);

    /// <summary>5.10: число единиц активной медтехники организации для кабинета организации, из gold.equipment_by_organization;
    /// 0, если у организации нет строк (или витрина ещё не опубликована).</summary>
    Task<long> EquipmentForOrganizationAsync(string moCode, CancellationToken cancellationToken);
}
