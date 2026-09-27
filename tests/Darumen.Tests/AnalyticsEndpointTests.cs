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
        using var doc = JsonDocument.Parse(await app.CreateClient("regulator").GetStringAsync("/api/v1/streams"));
        Assert.Equal(2, doc.RootElement.GetProperty("items").GetArrayLength());
    }

    [Fact]
    public async Task Forecast_accepts_camel_case_entity_keys_and_adds_history()
    {
        var body = await app.CreateClient("regulator").GetFromJsonAsync<ForecastResponseDto>("/api/v1/forecast/admissions_monthly?entity[regionKato]=75&entity[profileCode]=381&horizon=3");
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
        // кабинет организации (org.cabinet, scope own): только сигналы своей организации
        var client = app.CreateClient("org_admin", "chief-75", "75", "028B");
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
        Assert.Contains(app.Analytics.Commands, c => c.AnomalyId == "a1" && c.Actor == "chief-75" && c.Role == "org_admin" && c.RegionScope == "75" && c.MoScope == "028B");

        Assert.Equal(HttpStatusCode.NotFound, (await client.PostAsJsonAsync("/api/v1/anomalies/zzz/ack", new AckRequestDto(null, null))).StatusCode);
    }

    [Fact]
    public async Task Anomalies_filter_by_mo_code_for_the_organisation_cabinet()
    {
        var client = app.CreateClient("org_admin", "chief-75", "75", "028B");
        var byOrg = await client.GetFromJsonAsync<Paged<AnomalyDto>>("/api/v1/anomalies?regionKato=75&moCode=028B");
        Assert.Single(byOrg!.Items);
        Assert.Equal("a1", byOrg.Items[0].Id);

        // чужая организация для scope own — 403 other_organization; регулятор (scope all) видит пустой список
        var foreign = await client.GetAsync("/api/v1/anomalies?regionKato=75&moCode=ZZZZ");
        Assert.Equal(HttpStatusCode.Forbidden, foreign.StatusCode);
        Assert.Contains("other_organization", await foreign.Content.ReadAsStringAsync());
        var unknownOrg = await app.CreateClient("regulator").GetFromJsonAsync<Paged<AnomalyDto>>("/api/v1/anomalies?regionKato=75&moCode=ZZZZ");
        Assert.Empty(unknownOrg!.Items);
    }

    [Fact]
    public async Task Anomalies_carry_the_affected_count_for_a_collapsed_regional_wave()
    {
        // 3.3: волна очереди по региону — одна строка в ленте (не по строке на организацию), с числом затронутых организаций
        var client = app.CreateClient("regulator");
        var body = await client.GetFromJsonAsync<Paged<AnomalyDto>>("/api/v1/anomalies?regionKato=10&streamId=queue_daily");
        Assert.Single(body!.Items);
        Assert.Equal("a3", body.Items[0].Id);
        Assert.Equal(6, body.Items[0].Affected);
        Assert.False(body.Items[0].Entity.ContainsKey("mo_code")); // различающий ключ пуст — сигнал не про одну организацию
    }

    [Fact]
    public async Task Org_admin_cannot_close_signals_of_another_organization()
    {
        var chief = app.CreateClient("org_admin", "chief-75", "75", "028B");
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
        var body = await app.CreateClient("regulator").GetFromJsonAsync<LosResponseDto>("/api/v1/los?regionKato=75&profileCode=031");
        Assert.NotNull(body);
        Assert.Equal(2, body.Items.Count);
        Assert.Equal("Кардиологические для взрослых", body.Items[0].ProfileName);
        Assert.Equal(7.0, body.Items[0].LosMedianFact);
        Assert.Contains("1/LOS", body.Method);
    }

    [Fact]
    public async Task Staffing_by_region_is_sorted_ascending_by_rate_per_10k_population()
    {
        var body = await app.CreateClient("regulator").GetFromJsonAsync<StaffingResponseDto>("/api/v1/staffing");
        Assert.NotNull(body);
        Assert.Equal(2, body.Items.Count);
        Assert.Equal("10", body.Items[0].RegionKato);
        Assert.Equal(12.5, body.Items[0].RatePer10kPopulation);
        Assert.Equal(3.1, body.Items[0].RatePer1000Admissions);
        Assert.Null(body.Items[1].RatePer1000Admissions);
        Assert.Contains("10 тыс.", body.Method);
    }

    [Fact]
    public async Task Vaccination_refusals_are_grouped_nationwide_by_reason_and_contraindication()
    {
        // 5.8: vac_refusals не содержит региона — обе разбивки общенациональные
        var body = await app.CreateClient("regulator").GetFromJsonAsync<VaccinationRefusalsResponseDto>("/api/v1/vaccination-refusals");
        Assert.NotNull(body);
        Assert.Equal(2, body.ByReason.Count);
        Assert.Equal("родители отказались", body.ByReason[0].Reason);
        Assert.Equal(120, body.ByReason[0].N);
        Assert.Equal(2, body.ByContraindication.Count);
        Assert.Contains(body.ByContraindication, c => c.Contraindication == "unknown");
        Assert.Contains("общенациональная", body.Method);
    }

    [Fact]
    public async Task Oncology_late_stage_share_is_reported_per_localization_nationwide()
    {
        // 5.8: onco_late уже общенациональный агрегат по локализации — региона в ответе нет
        var body = await app.CreateClient("regulator").GetFromJsonAsync<OncologyLateStageResponseDto>("/api/v1/oncology-late-stage");
        Assert.NotNull(body);
        Assert.Equal(2, body.Items.Count);
        var c50 = body.Items.Single(i => i.LocalizationId == "C50");
        Assert.Equal(400, c50.AdvancedTotalCount);
        Assert.Equal(0.4, c50.AdvancedShare);
        Assert.Contains("общенациональный", body.Method);
    }

    [Fact]
    public async Task Equipment_by_region_is_sorted_descending_by_units()
    {
        var body = await app.CreateClient("regulator").GetFromJsonAsync<EquipmentResponseDto>("/api/v1/equipment");
        Assert.NotNull(body);
        Assert.Equal(2, body.Items.Count);
        Assert.Equal("75", body.Items[0].RegionKato);
        Assert.Equal(340, body.Items[0].Units);
        Assert.Equal("10", body.Items[1].RegionKato);
        Assert.Contains("медицинской техники", body.Method);
    }

    [Fact]
    public async Task Equipment_for_organization_returns_units_or_zero()
    {
        var chief = app.CreateClient("org_admin", "chief1", "75", "028B");
        var known = await chief.GetFromJsonAsync<EquipmentOrganizationDto>("/api/v1/equipment/organizations/028B");
        Assert.NotNull(known);
        Assert.Equal(42, known.Units);
        Assert.Equal(HttpStatusCode.Forbidden, (await chief.GetAsync("/api/v1/equipment/organizations/00ZZ")).StatusCode);

        var unknown = await app.CreateClient("regulator").GetFromJsonAsync<EquipmentOrganizationDto>("/api/v1/equipment/organizations/00ZZ");
        Assert.NotNull(unknown);
        Assert.Equal(0, unknown.Units);
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
