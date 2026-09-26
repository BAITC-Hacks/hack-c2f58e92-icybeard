using Darumen.Modules.Public;

namespace Darumen.Tests.Fakes;

/// <summary>Погода и новости без сети: жара сегодня, дождь завтра; одна новость о больнице.</summary>
public sealed class FakeWeather : IWeatherSource
{
    public IReadOnlyList<WeatherDayDto>? Days { get; set; } =
    [
        new("2026-09-26", 18, 33, 5, 12, 7.2, "clear"),
        new("2026-09-27", 12, 22, 70, 20, 3.1, "rain"),
    ];

    public Task<IReadOnlyList<WeatherDayDto>?> ForecastAsync(double lat, double lon, CancellationToken cancellationToken) => Task.FromResult(Days);
}

public sealed class FakeNews : INewsSource
{
    public IReadOnlyList<NewsItemDto>? Items { get; set; } = [new("В Семее открыли новый корпус больницы", "https://example.kz/news/1", new DateTimeOffset(2026, 9, 26, 9, 0, 0, TimeSpan.FromHours(5)), "Тест")];

    public Task<IReadOnlyList<NewsItemDto>?> LatestAsync(CancellationToken cancellationToken) => Task.FromResult(Items);
}
