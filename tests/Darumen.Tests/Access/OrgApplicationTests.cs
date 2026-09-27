using System.Net;
using System.Net.Http.Json;
using System.Text.RegularExpressions;
using Darumen.Modules.Access;
using Darumen.Shared.Api;
using Darumen.Shared.Auth;

namespace Darumen.Tests.Access;

/// <summary>Заявка организации → код на почту → подтверждение → одобрение регулятором → администратор организации с приглашением.</summary>
public sealed partial class OrgApplicationTests(TestApp app) : IClassFixture<TestApp>
{
    private static OrgApplicationRequestDto Request(string email) =>
        new("Городская поликлиника №5", "123456789012", "polyclinic", "75", "22GN", "Жанар Ахметова", email, "+7 701 555 44 33", true);

    [Fact]
    public async Task Application_is_verified_by_code_and_approved_with_an_invitation()
    {
        var anonymous = app.CreateClient();
        var submitted = await anonymous.PostAsJsonAsync("/api/v1/public/org-applications", Request("zhanar@poly5.kz"));
        Assert.Equal(HttpStatusCode.Created, submitted.StatusCode);
        var created = await submitted.Content.ReadFromJsonAsync<OrgApplicationCreatedDto>();
        Assert.True(created!.EmailSent);
        Assert.StartsWith("ORG-", created.Number);
        var code = CodePattern().Match(app.Mail.LastTo("zhanar@poly5.kz").Text).Groups[1].Value;
        Assert.Equal(6, code.Length);

        var status = await anonymous.GetFromJsonAsync<OrgApplicationStatusDto>($"/api/v1/public/org-applications/{created.Id}?statusToken={created.StatusToken}");
        Assert.Equal("pending_email", status!.Status);
        Assert.Equal("z***@poly5.kz", status.Email);
        Assert.Equal(HttpStatusCode.NotFound, (await anonymous.GetAsync($"/api/v1/public/org-applications/{created.Id}?statusToken=wrong")).StatusCode);

        var resendTooSoon = await anonymous.PostAsJsonAsync($"/api/v1/public/org-applications/{created.Id}/resend-code", new StatusTokenDto(created.StatusToken));
        Assert.Equal(HttpStatusCode.TooManyRequests, resendTooSoon.StatusCode);

        var wrong = await anonymous.PostAsJsonAsync($"/api/v1/public/org-applications/{created.Id}/verify-email", new VerifyEmailDto(code == "000000" ? "111111" : "000000", created.StatusToken));
        Assert.Equal(HttpStatusCode.UnprocessableEntity, wrong.StatusCode);
        var verified = await anonymous.PostAsJsonAsync($"/api/v1/public/org-applications/{created.Id}/verify-email", new VerifyEmailDto(code, created.StatusToken));
        Assert.Equal("pending_review", (await verified.Content.ReadFromJsonAsync<OrgApplicationStatusDto>())!.Status);

        var regulator = app.CreateClient(Roles.Regulator, "regulator1");
        var queue = await regulator.GetFromJsonAsync<Paged<OrgApplicationDto>>("/api/v1/admin/org-applications?status=pending_review");
        Assert.Contains(queue!.Items, a => a.Id == created.Id);
        Assert.Equal(HttpStatusCode.Forbidden, (await app.CreateClient(Roles.Doctor, "doctor1").GetAsync("/api/v1/admin/org-applications")).StatusCode);

        var approved = await regulator.PostAsJsonAsync($"/api/v1/admin/org-applications/{created.Id}/approve", new ApproveRequestDto(null));
        Assert.Equal(HttpStatusCode.OK, approved.StatusCode);
        var decision = await approved.Content.ReadFromJsonAsync<ApplicationDecisionDto>();
        Assert.Equal("approved", decision!.Status);
        Assert.True(decision.EmailSent);

        var letter = app.Mail.LastTo("zhanar@poly5.kz");
        Assert.Contains("Заявка одобрена", letter.Html);
        var admin = app.Identity.Find((await app.CreateClient(Roles.Admin, "admin1").GetFromJsonAsync<UsersPageDto>("/api/v1/admin/users?q=zhanar"))!.Items.Single().Id)!;
        Assert.Equal("22GN", admin.Attribute("mo_code"));
        Assert.Equal([Roles.OrgAdmin], app.Identity.RolesOf(admin.Id));
        Assert.Contains(app.Decisions.Published.OfType<Darumen.Contracts.V1.DecisionRecorded>(), e => e.Subject == DecisionSubjects.OrgApplication);
        Assert.Equal(HttpStatusCode.Conflict, (await regulator.PostAsJsonAsync($"/api/v1/admin/org-applications/{created.Id}/approve", new ApproveRequestDto(null))).StatusCode);
    }

    [Fact]
    public async Task Application_can_be_rejected_with_a_reason_and_is_validated()
    {
        var anonymous = app.CreateClient();
        var created = await (await anonymous.PostAsJsonAsync("/api/v1/public/org-applications", Request("reject@poly.kz") with { MoCode = null }))
            .Content.ReadFromJsonAsync<OrgApplicationCreatedDto>();
        var regulator = app.CreateClient(Roles.Regulator, "regulator1");
        Assert.Equal(HttpStatusCode.Conflict, (await regulator.PostAsJsonAsync($"/api/v1/admin/org-applications/{created!.Id}/reject", new RejectRequestDto("нет"))).StatusCode);

        var code = CodePattern().Match(app.Mail.LastTo("reject@poly.kz").Text).Groups[1].Value;
        await anonymous.PostAsJsonAsync($"/api/v1/public/org-applications/{created.Id}/verify-email", new VerifyEmailDto(code, created.StatusToken));
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await regulator.PostAsJsonAsync($"/api/v1/admin/org-applications/{created.Id}/approve", new ApproveRequestDto(null))).StatusCode);
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await regulator.PostAsJsonAsync($"/api/v1/admin/org-applications/{created.Id}/reject", new RejectRequestDto(" "))).StatusCode);
        var rejected = await regulator.PostAsJsonAsync($"/api/v1/admin/org-applications/{created.Id}/reject", new RejectRequestDto("БИН не найден в реестре"));
        Assert.Equal("rejected", (await rejected.Content.ReadFromJsonAsync<ApplicationDecisionDto>())!.Status);
        Assert.Contains("БИН не найден в реестре", app.Mail.LastTo("reject@poly.kz").Html);

        var injected = await anonymous.PostAsJsonAsync("/api/v1/public/org-applications", Request("inject@poly.kz") with { OrgName = "Клиника\r\nBcc: all@x.kz" });
        Assert.Equal(HttpStatusCode.UnprocessableEntity, injected.StatusCode);

        var invalid = await anonymous.PostAsJsonAsync("/api/v1/public/org-applications", Request("bad") with { Bin = "12", Consent = false });
        Assert.Equal(HttpStatusCode.UnprocessableEntity, invalid.StatusCode);
        var body = await invalid.Content.ReadAsStringAsync();
        Assert.Contains("bin", body);
        Assert.Contains("consent", body);
        Assert.Contains("email", body);
    }

    [Fact]
    public async Task Organizations_show_users_connection_and_freshness()
    {
        var regulator = app.CreateClient(Roles.Regulator, "regulator1");
        var orgs = await regulator.GetFromJsonAsync<Paged<OrgRowDto>>("/api/v1/admin/orgs?regionKato=75");
        var eye = Assert.Single(orgs!.Items, o => o.MoCode == "028B");
        Assert.Equal("connected", eye.Status);
        Assert.True(eye.Users >= 4);
        Assert.Contains(eye.Admins, a => a.Id == "chief1");
        Assert.Contains(eye.Freshness, f => f.Dataset == "bg_referrals");
        Assert.Equal("no_data", Assert.Single(orgs.Items, o => o.MoCode == "22GN").Status);

        var connectedOnly = await regulator.GetFromJsonAsync<Paged<OrgRowDto>>("/api/v1/admin/orgs?status=connected");
        Assert.All(connectedOnly!.Items, o => Assert.Equal("connected", o.Status));
        var detail = await regulator.GetFromJsonAsync<OrgDetailDto>("/api/v1/admin/orgs/028B");
        Assert.Equal("028B", detail!.Organization.MoCode);
        Assert.Equal(HttpStatusCode.NotFound, (await regulator.GetAsync("/api/v1/admin/orgs/NOPE")).StatusCode);
    }

    [GeneratedRegex(@"Код: (\d{6})")]
    private static partial Regex CodePattern();
}
