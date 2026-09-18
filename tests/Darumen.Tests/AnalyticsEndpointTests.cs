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
        Assert.Contains(app.Analytics.Commands, c => c.AnomalyId == "a1" && c.Actor == "chief-75" && c.Role == "chief" && c.RegionScope == "75");

        Assert.Equal(HttpStatusCode.NotFound, (await client.PostAsJsonAsync("/api/v1/anomalies/zzz/ack", new AckRequestDto(null, null))).StatusCode);
    }

    [Fact]
    public async Task Anomalies_filter_by_mo_code_for_the_organisation_cabinet()
    {
        var client = app.CreateClient("chief", "chief-75", "75");
        var byOrg = await client.GetFromJsonAsync<Paged<AnomalyDto>>("/api/v1/anomalies?regionKato=75&moCode=028B");
        Assert.Single(byOrg!.Items);
        Assert.Equal("a1", byOrg.Items[0].Id);

        var unknownOrg = await client.GetFromJsonAsync<Paged<AnomalyDto>>("/api/v1/anomalies?regionKato=75&moCode=ZZZZ");
        Assert.Empty(unknownOrg!.Items);
    }

    [Fact]
    public async Task Anomalies_carry_the_affected_count_for_a_collapsed_regional_wave()
    {
        // 3.3: волна очереди по региону — одна строка в ленте (не по строке на организацию), с числом затронутых организаций
        var client = app.CreateClient("chief", "chief-10", "10");
        var body = await client.GetFromJsonAsync<Paged<AnomalyDto>>("/api/v1/anomalies?regionKato=10&streamId=queue_daily");
        Assert.Single(body!.Items);
        Assert.Equal("a3", body.Items[0].Id);
        Assert.Equal(6, body.Items[0].Affected);
        Assert.False(body.Items[0].Entity.ContainsKey("mo_code")); // различающий ключ пуст — сигнал не про одну организацию
    }

    [Fact]
    public async Task Chief_cannot_close_signals_of_another_region()
    {
        var chief = app.CreateClient("chief", "chief-75", "75");
        var response = await chief.PostAsJsonAsync("/api/v1/anomalies/a2/ack", new AckRequestDto("не мой регион", "dismissed"));
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        Assert.DoesNotContain(app.Analytics.Commands, c => c.AnomalyId == "a2");
    }

    [Fact]
    public async Task Ack_accepts_only_closing_statuses()
    {
        var regulator = app.CreateClient("regulator");
        var response = await regulator.PostAsJsonAsync("/api/v1/anomalies/a2/ack", new AckRequestDto(null, "closed"));
        Assert.Equal(HttpStatusCode.UnprocessableEntity, response.StatusCode);
        Assert.DoesNotContain(app.Analytics.Commands, c => c.AnomalyId == "a2");
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
