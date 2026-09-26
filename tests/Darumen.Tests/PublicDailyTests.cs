using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Darumen.Modules.Public;
using Darumen.Shared.Api;

namespace Darumen.Tests;

public sealed class PublicDailyTests(TestApp app) : IClassFixture<TestApp>
{
    /// <summary>Гость без входа получает погоду на два дня, советы по правилам и новости; казахские советы — по Accept-Language.</summary>
    [Fact]
    public async Task Daily_is_public_and_carries_weather_tips_and_news()
    {
        var daily = await app.CreateClient().GetFromJsonAsync<DailyDto>("/api/v1/public/daily?regionKato=10");
        Assert.NotNull(daily);
        Assert.Equal("10", daily!.RegionKato);
        Assert.Equal("Семей", daily.Capital);
        Assert.True(daily.Weather.Available);
        Assert.Equal(2, daily.Weather.Days.Count);
        Assert.Contains(daily.Tips, t => t.Code == "heat" && t.Day == 0);
        Assert.Contains(daily.Tips, t => t.Code == "rain" && t.Day == 1);
        Assert.Contains(daily.Tips, t => t.Code == "uv" && t.Day == 0);
        Assert.True(daily.News.Available);
        Assert.Single(daily.News.Items);

        var client = app.CreateClient();
        client.DefaultRequestHeaders.AcceptLanguage.ParseAdd("kk");
        var kk = await client.GetFromJsonAsync<DailyDto>("/api/v1/public/daily?regionKato=10");
        Assert.Contains(kk!.Tips, t => t.Text.Contains("Ыстық"));
    }

    [Fact]
    public async Task Unknown_region_falls_back_to_the_first_known_one()
    {
        var response = await app.CreateClient().GetAsync("/api/v1/public/daily?regionKato=ZZ");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public void Tips_follow_thresholds_and_never_mention_treatment()
    {
        var calm = WeatherTips.For([new("2026-09-26", 10, 20, 10, 10, 2, "cloudy")], Locale.Ru);
        Assert.Single(calm);
        Assert.Equal("fine", calm[0].Code);

        var harsh = WeatherTips.For([new("2026-01-10", -22, -12, 80, 60, 1, "snow")], Locale.Ru);
        Assert.Equal(["frost", "wind", "snow"], harsh.Select(t => t.Code));
        Assert.All(harsh, t => Assert.DoesNotContain("леч", t.Text, StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public void Open_meteo_response_is_parsed_into_days_with_code_words()
    {
        const string json = """
            {"daily":{"time":["2026-09-26","2026-09-27"],"temperature_2m_max":[23.5,23.3],"temperature_2m_min":[11.6,12.3],
            "precipitation_probability_max":[41,8],"wind_speed_10m_max":[8.3,5.9],"uv_index_max":[5.25,5.30],"weather_code":[51,2]}}
            """;
        using var doc = JsonDocument.Parse(json);
        var days = OpenMeteoClient.Parse(doc.RootElement);
        Assert.Equal(2, days.Count);
        Assert.Equal("rain", days[0].Code);
        Assert.Equal("cloudy", days[1].Code);
        Assert.Equal(41, days[0].PrecipitationProbability);
    }

    [Fact]
    public void Rss_is_filtered_by_health_keywords_and_limited()
    {
        const string rss = """
            <?xml version="1.0"?><rss version="2.0"><channel>
            <item><title>Курс доллара вырос</title><link>https://x.kz/1</link><pubDate>Fri, 25 Sep 2026 12:00:00 +0500</pubDate></item>
            <item><title>Врачи Алматы получили новое оборудование</title><link>https://x.kz/2</link><pubDate>Fri, 25 Sep 2026 13:00:00 +0500</pubDate></item>
            <item><title>Открылась поликлиника в Астане</title><link>https://x.kz/3</link></item>
            </channel></rss>
            """;
        var items = RssNewsClient.Parse(rss, "врач|поликлиник", "Тест", 1);
        Assert.Single(items);
        Assert.Equal("https://x.kz/2", items[0].Url);
        Assert.Equal(13, items[0].PublishedAt!.Value.Hour);
        Assert.Empty(RssNewsClient.Parse("not xml", "врач", "Тест", 5));
    }
}
