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

    /// <summary>Справочник Стандарта публичен (гость видит сроки давности анализов и ориентир МЗ РК на экране ожидания)
    /// и каждая часть подписана источником и датой; казахские подписи приходят по Accept-Language.</summary>
    [Fact]
    public async Task Route_standard_is_public_and_cites_source_and_date()
    {
        var standard = await app.CreateClient().GetFromJsonAsync<RouteStandardDto>("/api/v1/refdata/route-standard");
        Assert.True(standard!.Available);
        Assert.Contains("ҚР-ДСМ-27", standard.Meta.Source);
        Assert.Equal("2025-09-15", standard.Meta.SourceDate);
        Assert.Equal(["referral_issued", "examination", "waitlisted", "date_assigned", "hospitalized", "refused"], standard.Stages.Select(s => s.Code));
        Assert.Equal(2, standard.Stages.Single(s => s.Code == "date_assigned").NormWorkingDays);
        Assert.All(standard.Checklist, c => Assert.True(c.ValidityDays > 0));
        Assert.Equal(20, standard.Benchmarks.Single(b => b.Code == "moh_target_wait_days").Value);
        Assert.Equal("2026-02-19", standard.Benchmarks.Single(b => b.Code == "moh_target_wait_days").SourceDate);

        var kk = app.CreateClient();
        kk.DefaultRequestHeaders.Add("Accept-Language", "kk");
        var kazakh = await kk.GetFromJsonAsync<RouteStandardDto>("/api/v1/refdata/route-standard");
        Assert.Equal("Жолдама берілді", kazakh!.Stages[0].Title);
    }

    private sealed record ItemsDto<T>(IReadOnlyList<T> Items);
}
