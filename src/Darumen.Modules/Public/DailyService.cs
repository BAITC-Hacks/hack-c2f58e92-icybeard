using Darumen.Modules.RefData;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace Darumen.Modules.Public;

/// <summary>Витрина гостя «сегодня и завтра»: погода по столице региона, советы по правилам и новости о здравоохранении.
/// Внешние источники кэшируются и деградируют по отдельности: без погоды остаются новости и наоборот.</summary>
public sealed class DailyService(IRefDataRepository refData, IWeatherSource weather, INewsSource news, IMemoryCache cache, IOptions<PublicOptions> options, ILogger<DailyService> logger, TimeProvider time)
{
    public const string DefaultRegion = "75";

    public async Task<DailyDto?> GetAsync(string? regionKato, string lang, CancellationToken cancellationToken)
    {
        var regions = await refData.RegionsAsync(lang, cancellationToken);
        var region = regions.FirstOrDefault(r => r.RegionKato == (regionKato ?? DefaultRegion)) ?? regions.FirstOrDefault(r => r.RegionKato == DefaultRegion) ?? regions.FirstOrDefault();
        if (region is null)
        {
            return null;
        }

        var ttl = TimeSpan.FromMinutes(Math.Max(1, options.Value.CacheMinutes));
        var days = await cache.GetOrCreateAsync($"public.weather.{region.RegionKato}", async entry =>
        {
            entry.AbsoluteExpirationRelativeToNow = ttl;
            return await SafeAsync(() => region.Lat is { } lat && region.Lon is { } lon ? weather.ForecastAsync(lat, lon, cancellationToken) : Task.FromResult<IReadOnlyList<WeatherDayDto>?>(null), "weather");
        }) ?? [];
        var items = await cache.GetOrCreateAsync("public.news", async entry =>
        {
            entry.AbsoluteExpirationRelativeToNow = ttl;
            return await SafeAsync(() => news.LatestAsync(cancellationToken), "news");
        });

        return new DailyDto(
            region.RegionKato,
            region.Name,
            region.Capital,
            time.GetUtcNow(),
            new WeatherDto(days.Count > 0, "Open-Meteo", days),
            WeatherTips.For(days, lang),
            new NewsDto(items is not null, options.Value.NewsSource, items ?? []));
    }

    private async Task<T?> SafeAsync<T>(Func<Task<T?>> call, string what) where T : class
    {
        try
        {
            return await call();
        }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException or TimeoutException)
        {
            logger.LogWarning(e, "Публичный источник {What} недоступен", what);
            return null;
        }
    }
}
