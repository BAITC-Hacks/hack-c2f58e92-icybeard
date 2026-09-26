using System.Globalization;
using System.Text.Json;
using Microsoft.Extensions.Options;

namespace Darumen.Modules.Public;

public interface IWeatherSource
{
    /// <summary>Прогноз на сегодня и завтра по координатам; null, если источник недоступен или выключен.</summary>
    Task<IReadOnlyList<WeatherDayDto>?> ForecastAsync(double lat, double lon, CancellationToken cancellationToken);
}

/// <summary>Open-Meteo: бесплатный прогноз без ключа, два дня, часовой пояс Казахстана.</summary>
public sealed class OpenMeteoClient(HttpClient http, IOptions<PublicOptions> options) : IWeatherSource
{
    private const string TimeZone = "Asia/Almaty";

    public async Task<IReadOnlyList<WeatherDayDto>?> ForecastAsync(double lat, double lon, CancellationToken cancellationToken)
    {
        var baseUrl = options.Value.WeatherBaseUrl;
        if (string.IsNullOrWhiteSpace(baseUrl))
        {
            return null;
        }

        var url = $"{baseUrl}?latitude={lat.ToString(CultureInfo.InvariantCulture)}&longitude={lon.ToString(CultureInfo.InvariantCulture)}" +
                  $"&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max,wind_speed_10m_max,uv_index_max,weather_code&timezone={Uri.EscapeDataString(TimeZone)}&forecast_days=2";
        using var response = await http.GetAsync(url, cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            return null;
        }

        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync(cancellationToken));
        return Parse(json.RootElement);
    }

    /// <summary>Разбор ответа Open-Meteo: массивы по дням одинаковой длины, отсутствующее значение (null) — как 0.</summary>
    public static IReadOnlyList<WeatherDayDto> Parse(JsonElement root)
    {
        if (!root.TryGetProperty("daily", out var daily) || !daily.TryGetProperty("time", out var time))
        {
            return [];
        }

        var days = new List<WeatherDayDto>();
        for (var i = 0; i < time.GetArrayLength(); i++)
        {
            days.Add(new(
                time[i].GetString() ?? "",
                Num(daily, "temperature_2m_min", i),
                Num(daily, "temperature_2m_max", i),
                (int)Math.Round(Num(daily, "precipitation_probability_max", i)),
                Num(daily, "wind_speed_10m_max", i),
                Num(daily, "uv_index_max", i),
                WeatherTips.CodeWord((int)Num(daily, "weather_code", i))));
        }

        return days;
    }

    private static double Num(JsonElement daily, string name, int i) =>
        daily.TryGetProperty(name, out var arr) && i < arr.GetArrayLength() && arr[i].ValueKind == JsonValueKind.Number ? arr[i].GetDouble() : 0;
}
