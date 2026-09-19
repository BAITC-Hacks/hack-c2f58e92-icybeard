using Darumen.Shared.Api;

namespace Darumen.Modules.Analytics;

public sealed record StreamDto(string StreamId, string Title, string Grain, IReadOnlyList<string> EntityKeys, IReadOnlyList<int> Horizons);

public sealed record ForecastPointDto(string Period, double Yhat, double Lo, double Hi);

public sealed record HistoryPointDto(string Period, double Y);

public sealed record BacktestDto(double Smape, double Mase, double BaselineSmape);

public sealed record ForecastResponseDto(
    string StreamId, IReadOnlyDictionary<string, string> Entity, IReadOnlyList<ForecastPointDto> Points,
    IReadOnlyList<HistoryPointDto> History, BacktestDto Backtest, ModelInfoDto Model, bool Flat);

public sealed record AnomalyDto(
    string Id, string StreamId, IReadOnlyDictionary<string, string> Entity, string Period, double Observed, double Expected,
    double Score, double PeerScore, string Severity, string Kind, string Status, string? RegionKato, string? Comment,
    string? MoCode = null, int? Affected = null);

/// <summary>MoCode — необязательно: не у всех потоков сигнал привязан к организации (see gold.anomalies.mo_code).</summary>
public sealed record AnomalyFilter(string? RegionKato, string? StreamId, string? Severity, string? Status, string? MoCode = null);

public sealed record AckRequestDto(string? Comment, string? Status);

/// <summary>Статусы сигнала. Закрывающие статусы ставит человек; они же метки для дообучения детектора (models/anomaly_labels.py).</summary>
public static class AnomalyStatuses
{
    public const string Open = "open";
    public const string Acknowledged = "acknowledged";
    public const string Dismissed = "dismissed";

    public static readonly IReadOnlyList<string> Closing = [Acknowledged, Dismissed];
}

/// <summary>Решение человека по сигналу. RegionScope — регион, которым ограничен пользователь (главврач), иначе null.</summary>
public sealed record AnomalyAckCommand(string AnomalyId, string Status, string? Comment, string Actor, string Role, string? RegionScope);

public enum AckOutcome
{
    Acknowledged,
    NotFound,
    OutOfScope,
}

public sealed record IndexItemDto(string RegionKato, string Name, double ShareOver30, double P90Days, double IndexValue, int Rank, long N);

public sealed record LosItemDto(string RegionKato, string ProfileName, string? ProfileCode, long N, double LosMedianFact, double? LosP50Model);

public sealed record LosResponseDto(IReadOnlyList<LosItemDto> Items, string Method);

public sealed record IndexResponseDto(string Month, string ProfileCode, IReadOnlyList<IndexItemDto> Items, IReadOnlyList<string> Months, string Method);

/// <summary>5.2: ставки на 10 тыс. населения и на 1 000 госпитализаций (12 мес.) из gold.staffing_by_region,
/// refdata.regions и gold.admissions_monthly. RatePer1000Admissions — null, если за 12 месяцев госпитализаций нет.</summary>
public sealed record StaffingRegionDto(
    string RegionKato, string RegionName, double RatePer10kPopulation, double? RatePer1000Admissions, DateOnly SnapshotDate);

public sealed record StaffingResponseDto(IReadOnlyList<StaffingRegionDto> Items, string Method);

/// <summary>5.8: разбивка отказов от вакцинации. В `vac_refusals` нет колонки региона и нет организации,
/// из которой регион выводился бы (contracts/vac_refusals.yaml) — разбивка только общенациональная,
/// отдельно по причине отказа и отдельно по противопоказанию.</summary>
public sealed record VacRefusalReasonDto(string Reason, long N);

public sealed record VacRefusalContraindicationDto(string Contraindication, long N);

public sealed record VacRefusalsDto(IReadOnlyList<VacRefusalReasonDto> ByReason, IReadOnlyList<VacRefusalContraindicationDto> ByContraindication);

public sealed record VaccinationRefusalsResponseDto(
    IReadOnlyList<VacRefusalReasonDto> ByReason, IReadOnlyList<VacRefusalContraindicationDto> ByContraindication, string Method);

/// <summary>5.8: доля запущенных случаев (стадии III/IV) по локализациям из `gold.onco_late` — этот датасет
/// уже общенациональный агрегат по локализации (grain), региона в нём нет и быть не может.
/// AdvancedShare — null, если TotalPatients равен 0.</summary>
public sealed record OncoLateItemDto(
    string LocalizationId, string LocalizationName, string? IcdCode, long TotalPatients,
    long AdvancedStage3Count, double? AdvancedStage3Pct, long AdvancedStage4Count, double? AdvancedStage4Pct,
    long AdvancedTotalCount, double? AdvancedShare, DateOnly SnapshotDate);

public sealed record OncologyLateStageResponseDto(IReadOnlyList<OncoLateItemDto> Items, string Method);
