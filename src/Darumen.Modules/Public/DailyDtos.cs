namespace Darumen.Modules.Public;

/// <summary>Один день прогноза: код погоды приведён к шести словам, чтобы клиенты рисовали иконку без таблицы WMO.</summary>
public sealed record WeatherDayDto(string Date, double TMin, double TMax, int PrecipitationProbability, double WindMax, double UvIndex, string Code);

public sealed record WeatherDto(bool Available, string Source, IReadOnlyList<WeatherDayDto> Days);

/// <summary>Совет по погоде: бытовое предупреждение (жара, мороз, ветер, осадки, УФ), не медицинская рекомендация.
/// <see cref="Day"/> — 0 сегодня, 1 завтра.</summary>
public sealed record WeatherTipDto(string Code, int Day, string Text);

public sealed record NewsItemDto(string Title, string Url, DateTimeOffset? PublishedAt, string Source);

public sealed record NewsDto(bool Available, string Source, IReadOnlyList<NewsItemDto> Items);

public sealed record DailyDto(string RegionKato, string RegionName, string Capital, DateTimeOffset AsOf, WeatherDto Weather, IReadOnlyList<WeatherTipDto> Tips, NewsDto News);
