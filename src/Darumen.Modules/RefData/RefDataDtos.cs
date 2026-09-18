namespace Darumen.Modules.RefData;

public sealed record RegionDto(string RegionKato, string Name, string Capital, double? Lat, double? Lon, int? PopulationThousands);

public sealed record OrganizationItemDto(string MoCode, string Name, string RegionKato, string? MoType, string? SizeBucket, double? Lat, double? Lon, string? MoKey = null);

public sealed record ProfileDto(string ProfileCode, string Name, bool IsDayHospital, long Referrals);

/// <summary>Внешняя сезонная форма (NHS): множитель месяца при среднем за год = 1.</summary>
public sealed record SeasonalityDto(string SeriesId, int Month, double Multiplier, string Title, string Source, int SourceYear, string WindowLabel);

/// <summary>Оценка охвата вакцинацией WUENIC (ВОЗ/ЮНИСЕФ) по Казахстану — внешний ориентир, не факт.</summary>
public sealed record VaccinationBenchmarkDto(string Vaccine, string TitleRu, int Year, double CoveragePct, string Source, string Note);
