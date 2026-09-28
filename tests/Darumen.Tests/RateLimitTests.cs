using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Darumen.Modules.Insight;
using Darumen.Shared.Api;
using Darumen.Shared.Auth;
using Microsoft.AspNetCore.Hosting;

namespace Darumen.Tests;

public sealed class RateLimitTests
{
    [Fact]
    public async Task Model_calls_are_limited_per_user()
    {
        using var app = new TestApp();
        using var limited = app.WithWebHostBuilder(builder => builder.UseSetting($"{RateLimitOptions.Section}:{nameof(RateLimitOptions.ModelCallsPerMinute)}", "2"));

        async Task<HttpStatusCode> Ask(string actor)
        {
            using var client = limited.CreateClient();
            client.DefaultRequestHeaders.Add(HeaderAuthenticationHandler.ActorHeader, actor);
            client.DefaultRequestHeaders.Add(HeaderAuthenticationHandler.RoleHeader, "regulator");
            return (await client.PostAsJsonAsync("/api/v1/insight/ask", new AskRequestDto("вопрос", null))).StatusCode;
        }

        Assert.Equal(HttpStatusCode.OK, await Ask("regulator-a"));
        Assert.Equal(HttpStatusCode.OK, await Ask("regulator-a"));
        Assert.Equal(HttpStatusCode.TooManyRequests, await Ask("regulator-a"));
        Assert.Equal(HttpStatusCode.OK, await Ask("regulator-b")); // лимит у каждого пользователя свой
    }

    [Fact]
    public async Task Api_is_limited_globally_with_a_problem_response_and_health_is_exempt()
    {
        using var app = new TestApp();
        using var limited = app.WithWebHostBuilder(builder => builder.UseSetting($"{GlobalRateLimitOptions.Section}:{nameof(GlobalRateLimitOptions.PermitLimit)}", "2"));
        using var client = limited.CreateClient();

        Assert.Equal(HttpStatusCode.OK, (await client.GetAsync("/api/v1/")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await client.GetAsync("/api/v1/")).StatusCode);
        using var rejected = await client.GetAsync("/api/v1/");
        Assert.Equal(HttpStatusCode.TooManyRequests, rejected.StatusCode);
        Assert.Equal("application/problem+json", rejected.Content.Headers.ContentType?.MediaType);
        Assert.NotNull(rejected.Headers.RetryAfter);
        using var problem = JsonDocument.Parse(await rejected.Content.ReadAsStringAsync());
        Assert.Equal(GlobalRateLimit.RejectedDetail, problem.RootElement.GetProperty("detail").GetString());
        Assert.Equal(429, problem.RootElement.GetProperty("status").GetInt32());

        for (var i = 0; i < 3; i++)
        {
            Assert.Equal(HttpStatusCode.OK, (await client.GetAsync("/health")).StatusCode); // /health не ограничивается
        }
    }

    [Fact]
    public async Task Global_limit_is_counted_per_user_and_per_forwarded_client_address()
    {
        using var app = new TestApp();
        using var limited = app.WithWebHostBuilder(builder => builder.UseSetting($"{GlobalRateLimitOptions.Section}:{nameof(GlobalRateLimitOptions.PermitLimit)}", "1"));

        async Task<HttpStatusCode> AsUser(string actor)
        {
            using var client = limited.CreateClient();
            client.DefaultRequestHeaders.Add(HeaderAuthenticationHandler.ActorHeader, actor);
            client.DefaultRequestHeaders.Add(HeaderAuthenticationHandler.RoleHeader, "regulator");
            return (await client.GetAsync("/api/v1/")).StatusCode;
        }

        // как на стенде: Caddy ставит адрес клиента, nginx дописывает шлюз docker-сети, через который пришёл Caddy
        async Task<HttpStatusCode> FromAddress(string address)
        {
            using var client = limited.CreateClient();
            client.DefaultRequestHeaders.Add("X-Forwarded-For", $"{address}, 172.18.0.1");
            return (await client.GetAsync("/api/v1/")).StatusCode;
        }

        Assert.Equal(HttpStatusCode.OK, await AsUser("regulator-a"));
        Assert.Equal(HttpStatusCode.TooManyRequests, await AsUser("regulator-a"));
        Assert.Equal(HttpStatusCode.OK, await AsUser("regulator-b"));

        Assert.Equal(HttpStatusCode.OK, await FromAddress("203.0.113.7"));
        Assert.Equal(HttpStatusCode.TooManyRequests, await FromAddress("203.0.113.7"));
        Assert.Equal(HttpStatusCode.OK, await FromAddress("198.51.100.9")); // другой клиент за тем же прокси — своё окно
    }
}
