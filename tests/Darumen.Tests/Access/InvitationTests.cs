using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.RegularExpressions;
using Darumen.Modules.Access;
using Darumen.Shared.Auth;

namespace Darumen.Tests.Access;

/// <summary>Приглашение → письмо со ссылкой → просмотр → принятие с паролем по политике реалма → пользователь включён.</summary>
public sealed partial class InvitationTests(TestApp app) : IClassFixture<TestApp>
{
    private HttpClient Admin => app.CreateClient(Roles.Admin, "admin1");

    [Fact]
    public async Task Invite_then_accept_enables_the_user()
    {
        var response = await Admin.PostAsJsonAsync("/api/v1/admin/users/invite", new InviteRequestDto("Aigerim@Clinic.kz", "Айгерим Сапарова", Roles.Doctor, "028B", "75"));
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var created = await response.Content.ReadFromJsonAsync<InviteResultDto>();
        Assert.True(created!.EmailSent);
        Assert.Null(created.InviteUrl); // письмо ушло — ссылка только в письме
        Assert.False(app.Identity.Find(created.UserId)!.Enabled);
        Assert.Equal([Roles.Doctor], app.Identity.RolesOf(created.UserId));

        var mail = app.Mail.LastTo("aigerim@clinic.kz");
        Assert.Contains("#5B5BD6", mail.Html);
        Assert.Contains("Принять приглашение", mail.Html);
        var token = TokenPattern().Match(mail.Text).Groups[1].Value;

        var users = await Admin.GetFromJsonAsync<UsersPageDto>("/api/v1/admin/users?status=invited");
        Assert.Contains(users!.Items, u => u.Id == created.UserId);

        var info = await app.CreateClient().GetFromJsonAsync<InviteInfoDto>($"/api/v1/public/invites/{token}");
        Assert.Equal("Айгерим Сапарова", info!.DisplayName);
        Assert.Equal("Казахский ордена институт глазных болезней", info.OrgName);
        Assert.Equal("Врач ПМСП", info.RoleTitleRu);
        Assert.Equal("admin1", info.InvitedBy);

        var weak = await app.CreateClient().PostAsJsonAsync($"/api/v1/public/invites/{token}/accept", new InviteAcceptDto("short", true));
        Assert.Equal(HttpStatusCode.UnprocessableEntity, weak.StatusCode);
        using (var problem = JsonDocument.Parse(await weak.Content.ReadAsStringAsync()))
        {
            Assert.Contains("не короче 12", problem.RootElement.GetProperty("errors").GetProperty("password")[0].GetString());
            Assert.Contains("кемінде 12", problem.RootElement.GetProperty("passwordPolicy").GetProperty("kk").GetString());
        }

        Assert.Equal(HttpStatusCode.UnprocessableEntity,
            (await app.CreateClient().PostAsJsonAsync($"/api/v1/public/invites/{token}/accept", new InviteAcceptDto("Strong-Passw0rd", false))).StatusCode);
        var accepted = await app.CreateClient().PostAsJsonAsync($"/api/v1/public/invites/{token}/accept", new InviteAcceptDto("Strong-Passw0rd", true));
        Assert.Equal(HttpStatusCode.OK, accepted.StatusCode);
        var user = app.Identity.Find(created.UserId)!;
        Assert.True(user.Enabled);
        Assert.True(user.EmailVerified);
        Assert.Equal("Strong-Passw0rd", app.Identity.Passwords[created.UserId]);

        Assert.Equal(HttpStatusCode.Gone, (await app.CreateClient().GetAsync($"/api/v1/public/invites/{token}")).StatusCode);
        var detail = await Admin.GetFromJsonAsync<UserDetailDto>($"/api/v1/admin/users/{created.UserId}");
        Assert.Equal("active", detail!.User.Status);
    }

    [Fact]
    public async Task Without_smtp_the_invite_url_is_returned()
    {
        using var isolated = new TestApp();
        isolated.Mail.Enabled = false;
        var response = await isolated.CreateClient(Roles.Admin, "admin1")
            .PostAsJsonAsync("/api/v1/admin/users/invite", new InviteRequestDto("nosmtp@clinic.kz", "Без Почты", Roles.Regulator, null, null));
        var created = await response.Content.ReadFromJsonAsync<InviteResultDto>();
        Assert.False(created!.EmailSent);
        Assert.StartsWith("http://localhost:5173/invite/", created.InviteUrl);
        Assert.True(created.ExpiresAt > DateTimeOffset.UtcNow.AddDays(6));
    }

    [Fact]
    public async Task Declining_removes_the_disabled_account_and_duplicates_are_rejected()
    {
        await Admin.PostAsJsonAsync("/api/v1/admin/users/invite", new InviteRequestDto("decline@clinic.kz", "Откажусь", Roles.Doctor, "028B", null));
        var token = TokenPattern().Match(app.Mail.LastTo("decline@clinic.kz").Text).Groups[1].Value;
        var info = await app.CreateClient().GetFromJsonAsync<InviteInfoDto>($"/api/v1/public/invites/{token}");
        Assert.Equal(HttpStatusCode.OK, (await app.CreateClient().PostAsync($"/api/v1/public/invites/{token}/decline", null)).StatusCode);
        Assert.Equal(HttpStatusCode.Gone, (await app.CreateClient().GetAsync($"/api/v1/public/invites/{token}")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await app.CreateClient().GetAsync("/api/v1/public/invites/unknown-token")).StatusCode);
        Assert.NotNull(info);

        Assert.Equal(HttpStatusCode.Conflict,
            (await Admin.PostAsJsonAsync("/api/v1/admin/users/invite", new InviteRequestDto("doctor1@darumen.local", "Дубль", Roles.Doctor, "028B", null))).StatusCode);
        Assert.Equal(HttpStatusCode.UnprocessableEntity,
            (await Admin.PostAsJsonAsync("/api/v1/admin/users/invite", new InviteRequestDto("chief@clinic.kz", "Без Кода", Roles.OrgAdmin, null, null))).StatusCode);
    }

    [Fact]
    public async Task Admin_blocks_and_unblocks_a_user()
    {
        var blocked = await Admin.PostAsync("/api/v1/admin/users/doctor2/block", null);
        Assert.Equal("blocked", (await blocked.Content.ReadFromJsonAsync<UserDetailDto>())!.User.Status);
        Assert.False(app.Identity.Find("doctor2")!.Enabled);
        var unblocked = await Admin.PostAsync("/api/v1/admin/users/doctor2/unblock", null);
        Assert.Equal("active", (await unblocked.Content.ReadFromJsonAsync<UserDetailDto>())!.User.Status);
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await Admin.PostAsync("/api/v1/admin/users/admin1/block", null)).StatusCode);

        // аудитор (admin.users all) не трогает администратора системы и не назначает роль admin
        var auditor = app.CreateClient(Roles.Auditor, "auditor1");
        Assert.Equal(HttpStatusCode.Forbidden, (await auditor.PostAsync("/api/v1/admin/users/admin1/block", null)).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await auditor.PutAsJsonAsync("/api/v1/admin/users/doctor2", new UserUpdateDto(Roles.Admin, null, null))).StatusCode);
    }

    [Fact]
    public async Task Accepting_an_invitation_of_a_user_deleted_in_keycloak_is_404_not_500()
    {
        await Admin.PostAsJsonAsync("/api/v1/admin/users/invite", new InviteRequestDto("gone@clinic.kz", "Удалённый Пользователь", Roles.Doctor, "028B", null));
        var token = TokenPattern().Match(app.Mail.LastTo("gone@clinic.kz").Text).Groups[1].Value;
        var user = (await app.Identity.UserByEmailAsync("gone@clinic.kz", CancellationToken.None))!;
        await app.Identity.DeleteUserAsync(user.Id, CancellationToken.None);
        var accepted = await app.CreateClient().PostAsJsonAsync($"/api/v1/public/invites/{token}/accept", new InviteAcceptDto("Strong-Passw0rd", true));
        Assert.Equal(HttpStatusCode.NotFound, accepted.StatusCode);
    }

    [GeneratedRegex(@"/invite/([A-Za-z0-9_\-]+)")]
    private static partial Regex TokenPattern();
}
