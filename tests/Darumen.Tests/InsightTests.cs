using System.Net;
using System.Net.Http.Json;
using Darumen.Modules.Insight;

namespace Darumen.Tests;

public sealed class InsightTests(TestApp app) : IClassFixture<TestApp>
{
    [Fact]
    public async Task Ask_runs_the_tool_loop_and_reports_tools_and_chart()
    {
        var client = app.CreateClient("regulator");
        var response = await client.PostAsJsonAsync("/api/v1/insight/ask", new AskRequestDto("Где лучший индекс по офтальмологии?", null));
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<AskResponseDto>();
        Assert.Contains("95.2", body!.Answer);
        Assert.Equal(95.2, body.Value);
        Assert.Equal(["access_index"], body.ToolsUsed);
        Assert.NotNull(body.Chart);
        Assert.Equal("bar", body.Chart!.Type);
        Assert.Equal(2, body.Chart.X.Count);
        Assert.True(app.Insight.Client.Calls >= 2);
    }

    [Fact]
    public async Task Ask_is_503_without_a_key_and_403_for_doctors()
    {
        app.Insight.Enabled = false;
        try
        {
            var response = await app.CreateClient("regulator").PostAsJsonAsync("/api/v1/insight/ask", new AskRequestDto("вопрос", null));
            Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        }
        finally
        {
            app.Insight.Enabled = true;
        }

        Assert.Equal(HttpStatusCode.Forbidden, (await app.CreateClient("doctor").PostAsJsonAsync("/api/v1/insight/ask", new AskRequestDto("вопрос", null))).StatusCode);
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await app.CreateClient("regulator").PostAsJsonAsync("/api/v1/insight/ask", new AskRequestDto("", null))).StatusCode);
    }

    [Fact]
    public void Extract_value_reads_the_first_number()
    {
        Assert.Equal(126, InsightService.ExtractValue("Самая длинная очередь 126 дней."));
        Assert.Equal(-9.4, InsightService.ExtractValue("Изменение −9,4 дня".Replace("−", "-")));
        Assert.Null(InsightService.ExtractValue("Данных нет"));
    }
}
