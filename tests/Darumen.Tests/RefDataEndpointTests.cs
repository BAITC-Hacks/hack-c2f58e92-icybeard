using System.Net.Http.Json;
using Darumen.Modules.RefData;

namespace Darumen.Tests;

public sealed class RefDataEndpointTests(TestApp app) : IClassFixture<TestApp>
{
    [Fact]
    public async Task Organizations_carry_mo_key_for_the_er_visits_stream_switcher()
    {
        var client = app.CreateClient("doctor");
        var body = await client.GetFromJsonAsync<ItemsDto<OrganizationItemDto>>("/api/v1/refdata/organizations?regionKato=75");
        Assert.NotEmpty(body!.Items);
        Assert.All(body.Items, o => Assert.False(string.IsNullOrWhiteSpace(o.MoKey)));
    }

    [Fact]
    public async Task Vaccination_plans_are_scoped_by_region()
    {
        var client = app.CreateClient("doctor");
        var withRegion = await client.GetFromJsonAsync<ItemsDto<string>>("/api/v1/refdata/vaccination-plans?regionKato=75");
        Assert.NotEmpty(withRegion!.Items);

        var elsewhere = await client.GetFromJsonAsync<ItemsDto<string>>("/api/v1/refdata/vaccination-plans?regionKato=ZZ");
        Assert.Empty(elsewhere!.Items);
    }

    private sealed record ItemsDto<T>(IReadOnlyList<T> Items);
}
