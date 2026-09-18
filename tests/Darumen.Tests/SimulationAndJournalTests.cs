using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Darumen.Modules.Journal;
using Darumen.Modules.Simulation;
using Darumen.Shared.Api;

namespace Darumen.Tests;

public sealed class SimulationAndJournalTests(TestApp app) : IClassFixture<TestApp>
{
    [Fact]
    public async Task Simulate_returns_delta_with_interval()
    {
        var response = await app.CreateClient("regulator").PostAsJsonAsync("/api/v1/simulate", new SimulateRequestDto("75", "381", new ScenarioDto(15, null, 90)));
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<SimulateResponseDto>();
        Assert.Equal(-3, body!.DeltaDays);
        Assert.True(body.Ci[0] <= body.DeltaDays && body.DeltaDays <= body.Ci[1]);
        Assert.Equal("fluid_queue", body.Model.Name);
    }

    [Fact]
    public async Task Simulate_forwards_beds_delta_and_returns_admissions_per_day()
    {
        var response = await app.CreateClient("regulator").PostAsJsonAsync("/api/v1/simulate", new SimulateRequestDto("75", "381", new ScenarioDto(null, null, 90, BedsDelta: 10)));
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<SimulateResponseDto>();
        Assert.Equal(22, body!.AdmissionsPerDay);
    }

    [Fact]
    public async Task Redistribute_lists_moves_and_validates_region()
    {
        var client = app.CreateClient("regulator");
        var body = await (await client.PostAsJsonAsync("/api/v1/redistribute", new RedistributeRequestDto("75", "381", null))).Content.ReadFromJsonAsync<RedistributeResponseDto>();
        Assert.Single(body!.Moves);
        Assert.Equal("SLOW", body.Moves[0].FromMo.MoCode);
        Assert.Equal(-200, body.TotalDeltaDays);
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await client.PostAsJsonAsync("/api/v1/redistribute", new RedistributeRequestDto("7", "381", null))).StatusCode);
    }

    [Fact]
    public async Task Decision_is_recorded_once_per_idempotency_key()
    {
        var client = app.CreateClient("doctor", "doctor-1");
        client.DefaultRequestHeaders.Add("Idempotency-Key", "k-1");
        var request = new DecisionRequestDto("referral", "75.028B.381.10", JsonDocument.Parse("{\"moCode\":\"22GN\"}").RootElement, JsonDocument.Parse("{\"moCode\":\"028B\"}").RootElement, "пациент выбрал ближайшую");
        var first = await client.PostAsJsonAsync("/api/v1/journal/decisions", request);
        Assert.Equal(HttpStatusCode.Created, first.StatusCode);
        var created = await first.Content.ReadFromJsonAsync<DecisionCreatedDto>();
        var second = await client.PostAsJsonAsync("/api/v1/journal/decisions", request);
        Assert.Equal(HttpStatusCode.OK, second.StatusCode);
        Assert.Equal(created!.DecisionId, (await second.Content.ReadFromJsonAsync<DecisionCreatedDto>())!.DecisionId);

        var mine = await client.GetFromJsonAsync<Paged<DecisionDto>>("/api/v1/journal/decisions?actor=me");
        Assert.Single(mine!.Items);
        Assert.Equal("doctor-1", mine.Items[0].Actor);

        var published = Assert.Single(app.Decisions.Published.OfType<Darumen.Contracts.V1.DecisionRecorded>());
        Assert.Equal(created.DecisionId.ToString(), published.DecisionId);
        Assert.Equal("doctor", published.ActorRole);
        Assert.False(string.IsNullOrEmpty(published.Meta.EventId));
    }

    [Fact]
    public async Task Intake_batches_are_listed()
    {
        var body = await app.CreateClient("steward").GetFromJsonAsync<Paged<Darumen.Modules.Intake.BatchDto>>("/api/v1/intake/batches?dataset=bg_referrals");
        Assert.Single(body!.Items);
        Assert.Equal(767084, body.Items[0].RowsLoaded);
    }

    [Fact]
    public async Task Decision_without_subject_is_422()
    {
        var response = await app.CreateClient("doctor").PostAsJsonAsync("/api/v1/journal/decisions", new DecisionRequestDto(null, null, null, null, null));
        Assert.Equal(HttpStatusCode.UnprocessableEntity, response.StatusCode);
    }

    [Fact]
    public async Task RefData_regions_organizations_profiles()
    {
        var client = app.CreateClient();
        using var regions = JsonDocument.Parse(await client.GetStringAsync("/api/v1/refdata/regions"));
        Assert.Equal("Область Абай", regions.RootElement.GetProperty("items")[0].GetProperty("name").GetString());
        using var orgs = JsonDocument.Parse(await client.GetStringAsync("/api/v1/refdata/organizations?regionKato=75&q=глазн"));
        Assert.Equal(1, orgs.RootElement.GetProperty("items").GetArrayLength());
        using var profiles = JsonDocument.Parse(await client.GetStringAsync("/api/v1/refdata/profiles"));
        Assert.Equal(2, profiles.RootElement.GetProperty("items").GetArrayLength());
    }
}
