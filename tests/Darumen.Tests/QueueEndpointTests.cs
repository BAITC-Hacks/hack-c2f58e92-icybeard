using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Darumen.Modules.Queue;
using Grpc.Core;

namespace Darumen.Tests;

public sealed class QueueEndpointTests(TestApp app) : IClassFixture<TestApp>
{
    private static readonly PredictRequestDto Request = new("75", "028B", "381", "H25.1", "Оперативное лечение", "Город", "Активы Фонда на ОСМС", "2025-04-01");

    [Fact]
    public async Task Predict_returns_quantiles_queue_and_explanation()
    {
        var response = await app.CreateClient().PostAsJsonAsync("/api/v1/queue/predict", Request);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<PredictResponseDto>();
        Assert.NotNull(body);
        Assert.Equal(12, body.P50Days);
        Assert.Equal(0.08, body.PRefusal);
        Assert.Equal(1784, body.Queue!.Len);
        Assert.Equal("Базовое ожидание 10 дн.", body.Explanation.Summary);
        Assert.Equal("wait_quantile", body.Model.Name);
    }

    [Fact]
    public async Task Predict_honours_accept_language_kk()
    {
        var client = app.CreateClient();
        client.DefaultRequestHeaders.Add("Accept-Language", "kk");
        var body = await (await client.PostAsJsonAsync("/api/v1/queue/predict", Request)).Content.ReadFromJsonAsync<PredictResponseDto>();
        Assert.Equal("Базалық күту 10 күн", body!.Explanation.Summary);
        Assert.Equal("кезек: 40", body.Explanation.Factors[0].Text);
    }

    [Fact]
    public async Task Predict_without_profile_or_region_is_422_problem()
    {
        var response = await app.CreateClient().PostAsJsonAsync("/api/v1/queue/predict", new PredictRequestDto(null, null, null, null, null, null, null, "2025-13-01"));
        Assert.Equal(HttpStatusCode.UnprocessableEntity, response.StatusCode);
        Assert.Equal("application/problem+json", response.Content.Headers.ContentType!.MediaType);
        using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var errors = doc.RootElement.GetProperty("errors");
        Assert.True(errors.TryGetProperty("profileCode", out _));
        Assert.True(errors.TryGetProperty("regionKato", out _));
        Assert.True(errors.TryGetProperty("registrationDate", out _));
    }

    [Fact]
    public async Task Model_service_outage_is_503_problem()
    {
        var previous = app.Queue.OnPredictWait;
        app.Queue.OnPredictWait = _ => throw new RpcException(new Status(StatusCode.Unavailable, "down"));
        try
        {
            var response = await app.CreateClient().PostAsJsonAsync("/api/v1/queue/predict", Request);
            Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
            Assert.Equal("application/problem+json", response.Content.Headers.ContentType!.MediaType);
        }
        finally
        {
            app.Queue.OnPredictWait = previous;
        }
    }

    [Fact]
    public async Task Unknown_organisation_from_model_is_404()
    {
        var previous = app.Queue.OnPredictWait;
        app.Queue.OnPredictWait = _ => throw new RpcException(new Status(StatusCode.NotFound, "unknown mo_code"));
        try
        {
            var response = await app.CreateClient().PostAsJsonAsync("/api/v1/queue/predict", Request);
            Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        }
        finally
        {
            app.Queue.OnPredictWait = previous;
        }
    }

    [Fact]
    public async Task Alternatives_are_sorted_by_p50()
    {
        var response = await app.CreateClient().PostAsJsonAsync("/api/v1/queue/alternatives", new AlternativesRequestDto("75", "028B", "381", null, null, null, null, null, 3, null));
        var body = await response.Content.ReadFromJsonAsync<AlternativesResponseDto>();
        Assert.Equal(2, body!.Items.Count);
        Assert.Equal("22GN", body.Items[0].Mo.MoCode);
        Assert.True(body.Items[0].P50Days <= body.Items[1].P50Days);
    }

    [Fact]
    public async Task Organisation_series_is_served_or_404()
    {
        var client = app.CreateClient("chief");
        var ok = await client.GetFromJsonAsync<OrganizationSeriesDto>("/api/v1/queue/organizations/028B?profileCode=381");
        Assert.Single(ok!.Days);
        Assert.Equal(6.1, ok.Throughput!.ThroughputPerDay);
        var missing = await client.GetAsync("/api/v1/queue/organizations/ZZZZ?profileCode=381");
        Assert.Equal(HttpStatusCode.NotFound, missing.StatusCode);
    }

    [Fact]
    public async Task Protected_routes_need_a_role()
    {
        Assert.Equal(HttpStatusCode.Unauthorized, (await app.CreateClient().GetAsync("/api/v1/queue/organizations/028B?profileCode=381")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await app.CreateClient("citizen").GetAsync("/api/v1/queue/organizations/028B?profileCode=381")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await app.CreateClient("chief").PostAsJsonAsync("/api/v1/simulate", new { regionKato = "75", profileCode = "381" })).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await app.CreateClient("admin").GetAsync("/api/v1/queue/organizations/028B?profileCode=381")).StatusCode);
    }
}
