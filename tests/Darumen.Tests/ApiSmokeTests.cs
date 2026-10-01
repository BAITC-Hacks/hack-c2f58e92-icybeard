using System.Net;
using System.Text.Json;

namespace Darumen.Tests;

public sealed class ApiSmokeTests(TestApp app) : IClassFixture<TestApp>
{
    private readonly HttpClient _client = app.CreateClient();

    [Fact]
    public async Task Health_returns_ok()
    {
        var response = await _client.GetAsync("/health");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task Health_reports_unavailable_when_the_database_is_down()
    {
        using var down = new TestApp();
        down.Database.Up = false;
        using var client = down.CreateClient();

        var response = await client.GetAsync("/health");

        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
    }

    [Fact]
    public async Task Root_returns_product_name()
    {
        var body = await _client.GetStringAsync("/api/v1/");
        Assert.Contains("Darumen Health", body);
    }

    [Fact]
    public async Task OpenApi_document_lists_module_routes()
    {
        var response = await _client.GetAsync("/openapi/v1.json");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var paths = doc.RootElement.GetProperty("paths").EnumerateObject().Select(p => p.Name).ToList();
        foreach (var expected in new[] { "/api/v1/queue/predict", "/api/v1/queue/alternatives", "/api/v1/forecast/{streamId}", "/api/v1/anomalies", "/api/v1/index", "/api/v1/simulate", "/api/v1/redistribute", "/api/v1/journal/decisions", "/api/v1/refdata/regions" })
        {
            Assert.Contains(expected, paths);
        }
    }
}
