namespace Darumen.Modules.RefData;

public sealed record RegionDto(string RegionKato, string Name, string Capital, double? Lat, double? Lon, int? PopulationThousands);

public sealed record OrganizationItemDto(string MoCode, string Name, string RegionKato, string? MoType, string? SizeBucket, double? Lat, double? Lon, string? MoKey = null);

public sealed record ProfileDto(string ProfileCode, string Name, bool IsDayHospital, long Referrals);

/// <summary>Внешняя сезонная форма (NHS): множитель месяца при среднем за год = 1.</summary>
public sealed record SeasonalityDto(string SeriesId, int Month, double Multiplier, string Title, string Source, int SourceYear, string WindowLabel);

/// <summary>Оценка охвата вакцинацией WUENIC (ВОЗ/ЮНИСЕФ) по Казахстану — внешний ориентир, не факт.</summary>
public sealed record VaccinationBenchmarkDto(string Vaccine, string TitleRu, int Year, double CoveragePct, string Source, string Note);

/// <summary>Стандарт стационарной помощи (приказ МЗ РК ҚР-ДСМ-27): стадии маршрута плановой госпитализации, допустимые
/// причины отказа, общий чек-лист обследований приложения 5 со сроками давности и ориентир МЗ РК по ожиданию.
/// Только логистика — не медицинские рекомендации (ТЗ §10.2, §11). Available = false, пока витрины
/// refdata.route_* не опубликованы (make publish).</summary>
public sealed record RouteStandardDto(
    RouteStandardMetaDto Meta, bool Available, IReadOnlyList<RouteStageDefDto> Stages, IReadOnlyList<RouteRefusalReasonDto> RefusalReasons,
    IReadOnlyList<RouteChecklistDefDto> Checklist, IReadOnlyList<RouteBenchmarkDto> Benchmarks)
{
    public static readonly RouteStandardDto Empty = new(new RouteStandardMetaDto(string.Empty, string.Empty, string.Empty), false, [], [], [], []);
}

public sealed record RouteStandardMetaDto(string Source, string SourceUrl, string SourceDate);

/// <summary>Стадия маршрута; Norm — нормативный срок Стандарта словами, числовые нормы — отдельными полями.</summary>
public sealed record RouteStageDefDto(string Code, int Order, string Title, string Norm, int? NormWorkingDays, int? RescheduleMaxDays, int? NoShowDays);

public sealed record RouteRefusalReasonDto(string Code, string Title);

/// <summary>Пункт общего перечня обследований (приложение 5) и срок его действия в днях.</summary>
public sealed record RouteChecklistDefDto(string Code, string Title, int ValidityDays, string ValidityLabel);

/// <summary>Ориентир МЗ РК (коллегия 19.02.2026): средний срок ожидания, цель, доля ожидающих дольше цели.</summary>
public sealed record RouteBenchmarkDto(string Code, double Value, string Unit, string Title, string Source, string SourceDate);
