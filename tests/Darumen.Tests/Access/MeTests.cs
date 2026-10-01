using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Darumen.Modules.Access;
using Darumen.Modules.Access.Data;
using Darumen.Shared.Api;
using Darumen.Shared.Auth;

namespace Darumen.Tests.Access;

/// <summary>GET /me и аккаунт: разрешения, профиль, уведомления, согласия, безопасность и сессии.</summary>
public sealed class MeTests(TestApp app) : IClassFixture<TestApp>
{
    private HttpClient Doctor => app.CreateClient(Roles.Doctor, "doctor1", "75", "028B", session: "s-current");

    [Fact]
    public async Task Me_returns_roles_permissions_and_organization()
    {
        var me = await Doctor.GetFromJsonAsync<MeDto>("/api/v1/me");
        Assert.Equal("doctor1", me!.Actor);
        Assert.Equal([Roles.Doctor], me.Roles);
        Assert.Contains(me.Permissions, p => p.Code == Permissions.WorklistView && p.Scope == PermissionScopes.Own);
        Assert.DoesNotContain(me.Permissions, p => p.Code == Permissions.GovMap);
        Assert.Equal("028B", me.MoCode);
        Assert.Equal("Казахский ордена институт глазных болезней", me.MoName);
        Assert.True(me.Onboarding.OtpConfigured);
        Assert.Null(me.IinMasked);

        Assert.Equal(HttpStatusCode.Unauthorized, (await app.CreateClient().GetAsync("/api/v1/me")).StatusCode);
    }

    [Fact]
    public async Task Own_permissions_are_empty_without_mo_code()
    {
        var withOrg = await app.CreateClient(Roles.OrgAdmin, "chief1", "75", "028B").GetFromJsonAsync<MeDto>("/api/v1/me");
        Assert.Contains(withOrg!.Permissions, p => p.Code == Permissions.OrgCabinet && p.Scope == PermissionScopes.Own);
        var withoutOrg = await app.CreateClient(Roles.OrgAdmin, "chief-x", "75").GetFromJsonAsync<MeDto>("/api/v1/me");
        Assert.DoesNotContain(withoutOrg!.Permissions, p => p.Scope == PermissionScopes.Own);
        Assert.Contains(withoutOrg.Permissions, p => p.Code == Permissions.WaitPublic);
    }

    [Fact]
    public void Iin_is_masked()
    {
        Assert.Equal("00••••••••01", IinMask.Mask("000000000001"));
        Assert.Null(IinMask.Mask(null));
    }

    [Fact]
    public async Task Access_request_is_recorded()
    {
        var citizen = app.CreateClient(Roles.Citizen, "citizen1", "75");
        var response = await citizen.PostAsJsonAsync("/api/v1/me/access-requests", new AccessRequestDto(Permissions.GovMap, "/gov", "нужно для работы"));
        Assert.Equal(HttpStatusCode.Accepted, response.StatusCode);
        Assert.Contains(app.Accounts.Requests, r => r.Actor == "citizen1" && r.Permission == Permissions.GovMap && r.Kind == AccountRequestKinds.Access);
        Assert.Equal(HttpStatusCode.UnprocessableEntity,
            (await citizen.PostAsJsonAsync("/api/v1/me/access-requests", new AccessRequestDto("no.such", "/x", null))).StatusCode);
    }

    [Fact]
    public async Task Profile_notifications_and_consents_round_trip()
    {
        var profile = await (await Doctor.PutAsJsonAsync("/api/v1/me/profile", new ProfileUpdateDto("+7 701 000 00 00", "kk", "Asia/Almaty")))
            .Content.ReadFromJsonAsync<ProfileDto>();
        Assert.Equal("kk", profile!.Language);
        Assert.Equal("офтальмолог", profile.Specialty);
        Assert.Contains("specialty", profile.ReadOnlyFields);
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await Doctor.PutAsJsonAsync("/api/v1/me/profile", new ProfileUpdateDto(null, "en", "Mars/Base"))).StatusCode);
        Assert.True((await Doctor.GetFromJsonAsync<MeDto>("/api/v1/me"))!.Onboarding.ProfileChecked);

        var update = new NotificationsUpdateDto([new NotificationEventUpdateDto("security", false, false, false, false), new NotificationEventUpdateDto("anomalies", true, true, false, true)],
            "22:00", "08:00", true, "daily");
        var notifications = await (await Doctor.PutAsJsonAsync("/api/v1/me/notifications", update)).Content.ReadFromJsonAsync<NotificationsDto>();
        var security = Assert.Single(notifications!.Events, e => e.Code == "security");
        Assert.True(security is { InApp: true, Email: true, Locked: true }); // событие security не выключается
        Assert.Contains(notifications.Events, e => e is { Code: "anomalies", Email: true, Push: true });
        Assert.Equal("daily", (await Doctor.GetFromJsonAsync<NotificationsDto>("/api/v1/me/notifications"))!.Digest);
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await Doctor.PutAsJsonAsync("/api/v1/me/notifications", update with { QuietTo = null })).StatusCode);

        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await Doctor.PutAsJsonAsync("/api/v1/me/consents/forecasts", new ConsentUpdateDto(false))).StatusCode);
        var consents = await (await Doctor.PutAsJsonAsync("/api/v1/me/consents/research_exports", new ConsentUpdateDto(true))).Content.ReadFromJsonAsync<JsonElement>();
        Assert.Contains(consents.GetProperty("items").EnumerateArray(), c => c.GetProperty("code").GetString() == "research_exports" && c.GetProperty("granted").GetBoolean());
        Assert.Equal(HttpStatusCode.NotFound, (await Doctor.PutAsJsonAsync("/api/v1/me/consents/unknown", new ConsentUpdateDto(true))).StatusCode);
    }

    [Fact]
    public async Task Security_lists_logins_and_sessions_and_closes_others()
    {
        var security = await Doctor.GetFromJsonAsync<SecurityDto>("/api/v1/me/security");
        Assert.True(security!.OtpConfigured);
        Assert.False(security.SmsAvailable);
        Assert.NotNull(security.PasswordChangedAt);
        Assert.Contains(security.RecentLogins, l => !l.Success && l.Ip == "10.0.0.9");
        Assert.Contains(security.Sessions, s => s is { Id: "s-current", Current: true, Device: "Веб-браузер" });
        Assert.Contains(security.Sessions, s => s is { Id: "s-mobile", Current: false, Device: "Мобильное приложение" });

        Assert.Equal(HttpStatusCode.NotFound, (await Doctor.DeleteAsync("/api/v1/me/sessions/someone-else")).StatusCode);
        var closed = await (await Doctor.DeleteAsync("/api/v1/me/sessions?keepCurrent=true")).Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(1, closed.GetProperty("closed").GetInt32());
        Assert.Equal(["s-current"], app.Identity.Sessions["doctor1"].Select(s => s.Id));
    }

    [Fact]
    public async Task Keycloak_outage_is_503_for_security_but_not_for_me()
    {
        using var isolated = new TestApp();
        isolated.Identity.Available = false;
        var doctor = isolated.CreateClient(Roles.Doctor, "doctor1", "75", "028B");
        var security = await doctor.GetAsync("/api/v1/me/security");
        Assert.Equal(HttpStatusCode.ServiceUnavailable, security.StatusCode);
        Assert.Contains("application/problem+json", security.Content.Headers.ContentType!.ToString());
        Assert.Equal(HttpStatusCode.OK, (await doctor.GetAsync("/api/v1/me")).StatusCode);
        Assert.Equal(HttpStatusCode.ServiceUnavailable, (await isolated.CreateClient(Roles.Admin, "admin1").GetAsync("/api/v1/admin/users")).StatusCode);
    }

    [Fact]
    public async Task Access_log_and_export_show_own_data()
    {
        var log = await Doctor.GetFromJsonAsync<JsonElement>("/api/v1/me/access-log");
        Assert.Contains(log.GetProperty("items").EnumerateArray(), i => i.GetProperty("actor").GetString() == "chief1");

        var export = await Doctor.GetAsync("/api/v1/me/export");
        Assert.Equal("text/csv", export.Content.Headers.ContentType!.MediaType);
        var csv = await export.Content.ReadAsStringAsync();
        Assert.Contains("Раздел;Поле;Значение", csv);
        Assert.Contains("Профиль;Логин;doctor1", csv);
        Assert.Contains("Согласие;Использование моих данных для прогноза сроков ожидания (обязательное);да", csv);

        Assert.Equal(HttpStatusCode.Accepted, (await Doctor.PostAsJsonAsync("/api/v1/me/deletion-request", new DeletionRequestDto("больше не работаю"))).StatusCode);
        Assert.Contains(app.Accounts.Requests, r => r.Kind == AccountRequestKinds.Deletion && r.Actor == "doctor1");
    }
}
