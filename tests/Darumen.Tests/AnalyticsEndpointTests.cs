using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Darumen.Modules.Analytics;
using Darumen.Shared.Api;

namespace Darumen.Tests;

public sealed class AnalyticsEndpointTests(TestApp app) : IClassFixture<TestApp>
{
    [Fact]
    public async Task Streams_catalog_is_listed()
    {
        using var doc = JsonDocument.Parse(await app.CreateClient("citizen").GetStringAsync("/api/v1/streams"));
        Assert.Equal(2, doc.RootElement.GetProperty("items").GetArrayLength());
    }

    [Fact]
    public async Task Forecast_accepts_camel_case_entity_keys_and_adds_history()
    {
        var body = await app.CreateClient("chief").GetFromJsonAsync<ForecastResponseDto>("/api/v1/forecast/admissions_monthly?entity[regionKato]=75&entity[profileCode]=381&horizon=3");
        Assert.NotNull(body);
        Assert.Equal(3, body.Points.Count);
        Assert.Equal(2, body.History.Count);
        Assert.Equal("75", body.Entity["region_kato"]);
        Assert.Equal("381", app.Forecast.LastRequest!.Entity["profile_code"]);
        Assert.Equal(0.8, body.Backtest.Mase);
        Assert.Equal("AutoETS", body.Model.Name);
    }

    [Fact]
    public async Task Forecast_unknown_stream_is_404_and_missing_key_is_422()
    {
        var client = app.CreateClient("regulator");
        Assert.Equal(HttpStatusCode.NotFound, (await client.GetAsync("/api/v1/forecast/nope?entity[regionKato]=75")).StatusCode);
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await client.GetAsync("/api/v1/forecast/admissions_monthly?entity[regionKato]=75")).StatusCode);
    }

    [Fact]
    public async Task Anomalies_default_to_open_and_ack_changes_status()
    {
        var client = app.CreateClient("chief", "chief-75", "75");
        var open = await client.GetFromJsonAsync<Paged<AnomalyDto>>("/api/v1/anomalies?regionKato=75");
        Assert.Single(open!.Items);
        Assert.Equal("a1", open.Items[0].Id);
        Assert.Equal("org a", open.Items[0].Entity["mo_key"]);

        var ack = await client.PostAsJsonAsync("/api/v1/anomalies/a1/ack", new AckRequestDto("проверено, вспышка ОРВИ", null));
        Assert.Equal(HttpStatusCode.NoContent, ack.StatusCode);
        var after = await client.GetFromJsonAsync<Paged<AnomalyDto>>("/api/v1/anomalies?regionKato=75&status=acknowledged");
        Assert.Single(after!.Items);
        Assert.Equal("проверено, вспышка ОРВИ", after.Items[0].Comment);
        Assert.Contains(app.Analytics.Published.OfType<Darumen.Contracts.V1.DecisionRecorded>(), e => e.Subject == "anomaly" && e.DecisionId == "a1" && e.Chosen == "acknowledged");

        Assert.Equal(HttpStatusCode.NotFound, (await client.PostAsJsonAsync("/api/v1/anomalies/zzz/ack", new AckRequestDto(null, null))).StatusCode);
    }

    [Fact]
    public async Task Los_returns_cells_and_method_note()
    {
        var body = await app.CreateClient("citizen").GetFromJsonAsync<LosResponseDto>("/api/v1/los?regionKato=75&profileCode=031");
        Assert.NotNull(body);
        Assert.Equal(2, body.Items.Count);
        Assert.Equal("Кардиологические для взрослых", body.Items[0].ProfileName);
        Assert.Equal(7.0, body.Items[0].LosMedianFact);
        Assert.Contains("1/LOS", body.Method);
    }

    [Fact]
    public async Task Index_defaults_to_latest_month_and_validates_month()
    {
        var client = app.CreateClient();
        var body = await client.GetFromJsonAsync<IndexResponseDto>("/api/v1/index");
        Assert.Equal("2025-03", body!.Month);
        Assert.Equal("all", body.ProfileCode);
        Assert.Equal("62", body.Items[0].RegionKato);
        Assert.Contains("Индекс", body.Method);
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await client.GetAsync("/api/v1/index?month=2024-01")).StatusCode);
    }
}
