using System.Net;
using System.Net.Http.Json;
using Darumen.Modules.Public;
using Darumen.Shared.Api;
using Microsoft.AspNetCore.Hosting;

namespace Darumen.Tests.Access;

/// <summary>Анонимные эндпоинты: пример-карточки страницы входа, восстановление пароля, лимит частоты публичных форм.</summary>
public sealed class PublicAccessTests(TestApp app) : IClassFixture<TestApp>
{
    [Fact]
    public async Task Login_examples_are_anonymous()
    {
        var examples = await app.CreateClient().GetFromJsonAsync<LoginExamplesDto>("/api/v1/public/login-examples");
        Assert.NotNull(examples!.Wait);
        Assert.Equal("381", examples.Wait.ProfileCode); // «офтальмология»: первый профиль с «фтальм» в названии
        Assert.Equal("75", examples.Wait.RegionKato);
        Assert.True(examples.Wait.P90Days >= examples.Wait.P50Days);
        Assert.InRange(examples.Wait.Within30, 0, 1);
        Assert.NotNull(examples.Rx);
        Assert.Equal("817", examples.Rx.Mnn);
        Assert.True(examples.Rx.Covered);
    }

    [Fact]
    public async Task Password_reset_is_always_accepted_and_emails_only_known_enabled_users()
    {
        var anonymous = app.CreateClient();
        Assert.Equal(HttpStatusCode.Accepted, (await anonymous.PostAsJsonAsync("/api/v1/public/password-reset", new { email = "doctor1@darumen.local" })).StatusCode);
        var action = Assert.Single(app.Identity.ActionEmails, a => a.UserId == "doctor1");
        Assert.Equal(["UPDATE_PASSWORD"], action.Actions);
        Assert.Equal("darumen-web", action.ClientId);
        Assert.Equal("http://localhost:5173/", action.RedirectUri);

        Assert.Equal(HttpStatusCode.Accepted, (await anonymous.PostAsJsonAsync("/api/v1/public/password-reset", new { email = "nobody@nowhere.kz" })).StatusCode);
        Assert.Equal(HttpStatusCode.Accepted, (await anonymous.PostAsJsonAsync("/api/v1/public/password-reset", new { email = "blocked1@darumen.local" })).StatusCode);
        Assert.DoesNotContain(app.Identity.ActionEmails, a => a.UserId == "blocked1");
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await anonymous.PostAsJsonAsync("/api/v1/public/password-reset", new { email = "not-an-email" })).StatusCode);
    }

    [Fact]
    public async Task Password_reset_hides_keycloak_outage()
    {
        using var isolated = new TestApp();
        isolated.Identity.Available = false;
        Assert.Equal(HttpStatusCode.Accepted,
            (await isolated.CreateClient().PostAsJsonAsync("/api/v1/public/password-reset", new { email = "doctor1@darumen.local" })).StatusCode);
    }

    [Fact]
    public async Task Public_forms_are_rate_limited_per_address()
    {
        using var isolated = new TestApp();
        using var limited = isolated.WithWebHostBuilder(b => b.UseSetting($"{RateLimitOptions.Section}:{nameof(RateLimitOptions.PublicFormsPerMinute)}", "2"));
        using var client = limited.CreateClient();
        Assert.Equal(HttpStatusCode.Accepted, (await client.PostAsJsonAsync("/api/v1/public/password-reset", new { email = "a@b.kz" })).StatusCode);
        Assert.Equal(HttpStatusCode.Accepted, (await client.PostAsJsonAsync("/api/v1/public/password-reset", new { email = "a@b.kz" })).StatusCode);
        Assert.Equal(HttpStatusCode.TooManyRequests, (await client.PostAsJsonAsync("/api/v1/public/password-reset", new { email = "a@b.kz" })).StatusCode);
    }
}
