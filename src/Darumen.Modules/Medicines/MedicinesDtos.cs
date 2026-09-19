using Darumen.Shared.Api;

namespace Darumen.Modules.Medicines;

public sealed record CheckRequestDto(string? MnnId, string? NosologyId, string? RegionKato);

/// <summary>Score/Flag — против собственной истории МНН (own baseline). PeerRatio/PeerBasis — то же самое, но
/// против МНН-«ровесников» той же категории за последние 12 месяцев (5.7 B); null, если ровесников с данными нет.</summary>
public sealed record ShortageDto(bool Flag, double Score, string Basis, double? PeerRatio, string? PeerBasis);

public sealed record PharmacyDto(string DrugStoreId, string Name, double? Lat, double? Lon, long Fills30d);

public sealed record AlternativeMnnDto(string MnnId, string Name, long Issued12m);

/// <summary>Обеспеченность МНН-«ровесников» той же категории за последние 12 месяцев, без самого МНН.</summary>
public sealed record PeerFulfillmentDto(double Ratio, long PeerMnnCount, long IssuedRecent, long FulfilledRecent);

public sealed record CheckResponseDto(
    bool Covered, string? Program, string? Category, double? FillDaysP50, double? FillDaysP90, double? FillDaysP50Model, double? PFilled14d,
    ShortageDto Shortage, IReadOnlyList<PharmacyDto> Pharmacies, IReadOnlyList<AlternativeMnnDto> Alternatives,
    string Basis, ModelInfoDto Model);

public sealed record NosologyDto(string NosologyId, string CategoryId, long Issued12m, long Fulfilled12m, long MnnCount);

public sealed record MnnDto(string MnnId, string NosologyId, string CategoryId, long Issued12m, long Fulfilled12m, double? FillDaysP50);

/// <summary>Неделя по МНН из gold.rx_weekly.</summary>
public sealed record RxWeek(DateOnly Week, long Issued, long Fulfilled, long Fulfilled14d, double? FillDaysP50, double? FillDaysP90);

/// <summary>Месяц по нозологии из gold.rx_nosology_monthly.</summary>
public sealed record RxMonth(DateOnly Month, string CategoryId, long Issued, long Fulfilled, long Fulfilled14d, double? FillDaysP50, double? FillDaysP90);

public sealed record DrugProgram(string ProgramId, string CategoryId, long ActiveSpecs, long Products, double? UnitPriceP50);
