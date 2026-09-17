using System.Net;
using System.Net.Http.Json;
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
}
