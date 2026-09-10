using System.Net.Http.Json;
using Darumen.Modules.Journal;
using Darumen.Tests.Fakes;

namespace Darumen.Tests;

public sealed class WorklistTests(TestApp app) : IClassFixture<TestApp>
{
    [Fact]
    public async Task Builder_is_deterministic_and_flags_real_risks()
    {
        var states = await new InMemoryWorklist().QueueStatesAsync("75", CancellationToken.None);
        var first = WorklistBuilder.Build(states);
        var second = WorklistBuilder.Build(states);
        Assert.Equal(first.Select(i => i.PatientRef), second.Select(i => i.PatientRef));
        Assert.All(first, i => Assert.True(i.Synthetic));
        var eye = first.Where(i => i.MoCode == "028B").ToList();
        Assert.True(eye.Count > 0 && eye.Count <= WorklistBuilder.MaxPerQueue);
        Assert.All(eye, i => Assert.Contains(WorklistBuilder.RefusalRisk, i.RiskFlags));
        Assert.All(eye, i => Assert.Contains(WorklistBuilder.FasterAlternative, i.RiskFlags));
        Assert.Contains(first, i => i.RiskFlags.Contains(WorklistBuilder.StuckOver30));
        Assert.True(first[0].Priority >= first[^1].Priority);
        Assert.Empty(WorklistBuilder.Build([]));
        Assert.All(WorklistBuilder.Build(states, WorklistBuilder.RefusalRisk), i => Assert.Contains(WorklistBuilder.RefusalRisk, i.RiskFlags));
    }

    [Fact]
    public async Task Worklist_endpoint_uses_the_doctor_region()
    {
        var body = await app.CreateClient("doctor", "doctor1", "75").GetFromJsonAsync<WorklistResponseDto>("/api/v1/journal/worklist");
        Assert.True(body!.Synthetic);
        Assert.Equal("75", body.RegionKato);
        Assert.Equal("2025-03-31", body.AsOf);
        Assert.NotEmpty(body.Items);
        var empty = await app.CreateClient("doctor", "doctor2", "10").GetFromJsonAsync<WorklistResponseDto>("/api/v1/journal/worklist");
        Assert.Empty(empty!.Items);
    }
}
