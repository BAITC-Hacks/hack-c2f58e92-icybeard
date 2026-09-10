using System.Net;
using System.Net.Http.Json;
using Darumen.Modules.Medicines;
using Darumen.Tests.Fakes;

namespace Darumen.Tests;

public sealed class MedicinesTests(TestApp app) : IClassFixture<TestApp>
{
    [Fact]
    public void Shortage_flags_a_drop_in_fulfilled_share()
    {
        var drop = MedicinesService.Shortage(InMemoryMedicines.Weeks(40));
        Assert.True(drop.Flag);
        Assert.True(drop.Score >= 0.5);
        var steady = MedicinesService.Shortage(InMemoryMedicines.Weeks(88));
        Assert.False(steady.Flag);
        Assert.False(MedicinesService.Shortage([]).Flag);
    }

    [Fact]
    public void Fill_times_prefer_recent_weeks_of_the_mnn()
    {
        var (p50, p90, pFilled, basis) = MedicinesService.FillTimes(InMemoryMedicines.Weeks(88), []);
        Assert.Equal(3, p50);
        Assert.Equal(9, p90);
        Assert.Equal(0.5, pFilled);
        Assert.Contains("МНН", basis);
        var fallback = MedicinesService.FillTimes([], [new RxMonth(new DateOnly(2025, 3, 1), "63", 10, 8, 6, 4, 12)]);
        Assert.Equal(4, fallback.P50);
        Assert.Equal(0.75, fallback.PFilled14d);
    }

    [Fact]
    public async Task Check_endpoint_reports_coverage_program_and_alternatives()
    {
        var client = app.CreateClient("doctor");
        var body = await (await client.PostAsJsonAsync("/api/v1/medicines/check", new CheckRequestDto("817", "109", "75"))).Content.ReadFromJsonAsync<CheckResponseDto>();
        Assert.True(body!.Covered);
        Assert.Equal("Программа 90", body.Program);
        Assert.True(body.Shortage.Flag);
        Assert.Single(body.Alternatives);
        Assert.Equal("900", body.Alternatives[0].MnnId);
        Assert.Equal("rx_fill", body.Model.Name);
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await client.PostAsJsonAsync("/api/v1/medicines/check", new CheckRequestDto(null, null, "7"))).StatusCode);
        var nosologies = await client.GetStringAsync("/api/v1/medicines/nosologies");
        Assert.Contains("\"109\"", nosologies);
    }
}
