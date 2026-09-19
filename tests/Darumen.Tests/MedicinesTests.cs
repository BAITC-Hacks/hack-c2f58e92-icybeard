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
    public void Shortage_surfaces_peer_ratio_alongside_own_history()
    {
        var peer = new PeerFulfillmentDto(0.85, 4, 5000, 4250);
        var withPeer = MedicinesService.Shortage(InMemoryMedicines.Weeks(88), peer);
        // 88/100 = 0.88 не хуже собственной базы (0.9) — own-сигнал спокоен, но ровесники обеспечены на 0.85,
        // а это МНН на уровне 0.88, так что peer-сравнение тоже не должно поднимать тревогу
        Assert.False(withPeer.Flag);
        Assert.Equal(0.85, withPeer.PeerRatio);
        Assert.Contains("похож", withPeer.PeerBasis, StringComparison.OrdinalIgnoreCase);

        // мало своей истории, но заметно хуже ровесников — сигнал всё равно должен сработать (5.7 B)
        var thin = new List<RxWeek> { new(new DateOnly(2025, 1, 6), 5, 1, 0, 3, 9) }; // ниже MinIssuedForSignal, ratio 0.2
        var peerOnly = MedicinesService.Shortage(thin, new PeerFulfillmentDto(0.95, 6, 6000, 5700));
        Assert.True(peerOnly.Flag);
        Assert.Equal("мало рецептов для сигнала по своей истории", peerOnly.Basis);
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
        // 5.7 A: p50 модели из gold.rx_fill_by_mnn показывается рядом с фактическим — не вместо него
        Assert.Equal(3.2, body.FillDaysP50Model);
        Assert.NotNull(body.FillDaysP50);
        // 5.7 B: сравнение с ровесниками той же категории видно отдельно от собственной истории
        Assert.Equal(0.85, body.Shortage.PeerRatio);
        Assert.NotNull(body.Shortage.PeerBasis);
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await client.PostAsJsonAsync("/api/v1/medicines/check", new CheckRequestDto(null, null, "7"))).StatusCode);
        var nosologies = await client.GetStringAsync("/api/v1/medicines/nosologies");
        Assert.Contains("\"109\"", nosologies);
    }

    [Fact]
    public async Task Check_endpoint_leaves_model_field_null_when_mnn_has_no_gold_cell()
    {
        var client = app.CreateClient("doctor");
        var body = await (await client.PostAsJsonAsync("/api/v1/medicines/check", new CheckRequestDto("900", "109", "75"))).Content.ReadFromJsonAsync<CheckResponseDto>();
        Assert.Null(body!.FillDaysP50Model);
    }

    [Fact]
    public async Task TopMnn_endpoint_returns_global_top_list_without_nosology_filter()
    {
        var client = app.CreateClient("doctor");
        var response = await client.GetStringAsync("/api/v1/medicines/mnn/top");
        Assert.Contains("\"817\"", response);
        Assert.Contains("\"900\"", response);
    }
}
