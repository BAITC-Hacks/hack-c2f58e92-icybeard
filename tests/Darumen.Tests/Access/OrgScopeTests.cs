using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Darumen.Modules.Access;
using Darumen.Modules.Journal;
using Darumen.Shared.Api;
using Darumen.Shared.Auth;

namespace Darumen.Tests.Access;

/// <summary>scope own у администратора организации (mo_code = 028B): своя организация — да, чужая — 403 other_organization,
/// без клейма mo_code — 403 no_organization.</summary>
public sealed class OrgScopeTests(TestApp app) : IClassFixture<TestApp>
{
    private HttpClient OrgAdmin => app.CreateClient(Roles.OrgAdmin, "chief1", "75", "028B");

    [Fact]
    public async Task Worklist_is_limited_to_own_organization()
    {
        var own = await OrgAdmin.GetFromJsonAsync<WorklistResponseDto>("/api/v1/journal/worklist");
        Assert.NotEmpty(own!.Items);
        Assert.All(own.Items, i => Assert.Equal("028B", i.MoCode));

        await AssertForbiddenAsync(await OrgAdmin.GetAsync("/api/v1/journal/worklist?moCode=22GN"), AccessProblems.OtherOrganization);

        // врач (scope all) видит весь регион, а с moCode — очереди одной организации
        var doctor = await app.CreateClient(Roles.Doctor, "doctor1", "75").GetFromJsonAsync<WorklistResponseDto>("/api/v1/journal/worklist");
        Assert.Contains(doctor!.Items, i => i.MoCode == "22GN");
    }

    [Fact]
    public async Task Org_admin_without_mo_code_gets_no_organization()
    {
        var noOrg = app.CreateClient(Roles.OrgAdmin, "chief-no-org", "75");
        await AssertForbiddenAsync(await noOrg.GetAsync("/api/v1/journal/worklist"), AccessProblems.NoOrganization);
        await AssertForbiddenAsync(await noOrg.GetAsync("/api/v1/admin/users"), AccessProblems.NoOrganization);
    }

    [Fact]
    public async Task Patient_route_is_open_only_for_own_organization()
    {
        Assert.Equal(HttpStatusCode.OK, (await OrgAdmin.GetAsync("/api/v1/route/SYN-75-028B-381-01")).StatusCode);
        await AssertForbiddenAsync(await OrgAdmin.GetAsync("/api/v1/route/SYN-75-22GN-381-01"), AccessProblems.OtherOrganization);
        await AssertForbiddenAsync(await OrgAdmin.PostAsJsonAsync("/api/v1/route/SYN-75-22GN-381-01/keep", new RouteKeepRequestDto("остаётся")),
            AccessProblems.OtherOrganization);
    }

    [Fact]
    public async Task All_decisions_for_org_admin_are_decisions_of_own_organization()
    {
        await RecordAsync(app.CreateClient(Roles.Doctor, "doctor-28", "75", "028B"), "75.028B.381.2025-03-15", "22GN", "028B");
        await RecordAsync(app.CreateClient(Roles.Doctor, "doctor2", "75", "22GN"), "75.22GN.381.2025-03-15", "22GN", "027O");

        var own = await OrgAdmin.GetFromJsonAsync<Paged<DecisionDto>>("/api/v1/journal/decisions");
        Assert.Contains(own!.Items, d => d.Actor == "doctor-28");
        Assert.DoesNotContain(own.Items, d => d.Actor == "doctor2");

        var all = await app.CreateClient(Roles.Regulator, "regulator1").GetFromJsonAsync<Paged<DecisionDto>>("/api/v1/journal/decisions");
        Assert.Contains(all!.Items, d => d.Actor == "doctor2");

        // decisions.own без decisions.all: врач видит только свои решения, даже если просит чужие
        var doctorView = await app.CreateClient(Roles.Doctor, "doctor2", "75", "22GN").GetFromJsonAsync<Paged<DecisionDto>>("/api/v1/journal/decisions?actor=doctor-28");
        Assert.All(doctorView!.Items, d => Assert.Equal("doctor2", d.Actor));

        // и записывать решения при scope own можно только про свою организацию
        await AssertForbiddenAsync(await OrgAdmin.PostAsJsonAsync("/api/v1/journal/decisions", Decision("75.22GN.381.2025-03-15", "22GN", "027O")),
            AccessProblems.OtherOrganization);
    }

    [Fact]
    public async Task Audit_journal_is_limited_to_own_organization()
    {
        var own = await OrgAdmin.GetFromJsonAsync<Paged<AuditEntryDto>>("/api/v1/journal/audit");
        Assert.All(own!.Items, a => Assert.Equal("028B", a.MoCode));
        var all = await app.CreateClient(Roles.Auditor, "auditor1").GetFromJsonAsync<Paged<AuditEntryDto>>("/api/v1/journal/audit");
        Assert.Equal(3, all!.Total);
        await AssertForbiddenAsync(await app.CreateClient(Roles.Doctor, "doctor1").GetAsync("/api/v1/journal/audit"), AccessProblems.PermissionRequired);
    }

    [Fact]
    public async Task Users_and_doctors_are_limited_to_own_organization()
    {
        var users = await OrgAdmin.GetFromJsonAsync<UsersPageDto>("/api/v1/admin/users");
        Assert.NotEmpty(users!.Items);
        Assert.All(users.Items, u => Assert.Equal("028B", u.MoCode));
        Assert.Equal(1, users.Summary.Blocked);
        Assert.Contains(users.Items, u => u.Username == "doctor1" && u.LastActivity is not null && u.MoName == "Казахский ордена институт глазных болезней");

        await AssertForbiddenAsync(await OrgAdmin.GetAsync("/api/v1/admin/users?moCode=22GN"), AccessProblems.OtherOrganization);
        await AssertForbiddenAsync(await OrgAdmin.GetAsync("/api/v1/admin/users/doctor2"), AccessProblems.OtherOrganization);

        var doctors = await OrgAdmin.GetFromJsonAsync<Paged<DoctorRowDto>>("/api/v1/admin/doctors");
        Assert.All(doctors!.Items, d => Assert.Equal("028B", d.MoCode));
        var doctor1 = Assert.Single(doctors.Items, d => d.Id == "doctor1");
        Assert.Equal(12, doctor1.Referrals);
        Assert.Equal(0.75, doctor1.MatchRate);
        Assert.Equal("pending", doctor1.Verification);
    }

    [Fact]
    public async Task Org_admin_assigns_only_doctor_or_org_admin_in_own_organization()
    {
        var denied = await OrgAdmin.PutAsJsonAsync("/api/v1/admin/users/doctor-28", new UserUpdateDto(Roles.Regulator, null, null));
        Assert.Equal(HttpStatusCode.Forbidden, denied.StatusCode);
        Assert.Contains("role_not_assignable", await denied.Content.ReadAsStringAsync());
        await AssertForbiddenAsync(await OrgAdmin.PutAsJsonAsync("/api/v1/admin/users/doctor-28", new UserUpdateDto(Roles.Doctor, "22GN", null)),
            AccessProblems.OtherOrganization);

        var promoted = await OrgAdmin.PutAsJsonAsync("/api/v1/admin/users/doctor-28", new UserUpdateDto(Roles.OrgAdmin, null, null));
        Assert.Equal(HttpStatusCode.OK, promoted.StatusCode);
        Assert.Equal([Roles.OrgAdmin], app.Identity.RolesOf("doctor-28"));
        Assert.Contains(app.Decisions.Published.OfType<Darumen.Contracts.V1.DecisionRecorded>(), e => e.Subject == DecisionSubjects.UserAccess);

        var invite = await OrgAdmin.PostAsJsonAsync("/api/v1/admin/users/invite", new InviteRequestDto("new.doctor@clinic.kz", "Новый Врач", Roles.Doctor, null, "75"));
        Assert.Equal(HttpStatusCode.Created, invite.StatusCode);
        var created = await invite.Content.ReadFromJsonAsync<InviteResultDto>();
        Assert.Equal("028B", app.Identity.Find(created!.UserId)!.Attribute("mo_code")); // организация — своя, даже без moCode в запросе
    }

    [Fact]
    public async Task Doctor_verification_is_recorded_and_scoped()
    {
        var verified = await OrgAdmin.PostAsJsonAsync("/api/v1/admin/doctors/doctor1/verification", new VerificationRequestDto("verified", "диплом проверен"));
        Assert.Equal(HttpStatusCode.OK, verified.StatusCode);
        Assert.Equal("verified", (await verified.Content.ReadFromJsonAsync<DoctorRowDto>())!.Verification);
        Assert.Contains(app.Decisions.Published.OfType<Darumen.Contracts.V1.DecisionRecorded>(), e => e.Subject == DecisionSubjects.DoctorVerification);

        await AssertForbiddenAsync(await OrgAdmin.PostAsJsonAsync("/api/v1/admin/doctors/doctor2/verification", new VerificationRequestDto("verified", null)),
            AccessProblems.OtherOrganization);
        Assert.Equal(HttpStatusCode.UnprocessableEntity,
            (await OrgAdmin.PostAsJsonAsync("/api/v1/admin/doctors/doctor1/verification", new VerificationRequestDto("maybe", null))).StatusCode);
    }

    private static object Decision(string subjectId, string recommended, string chosen) =>
        new { subject = "referral", subjectId, recommended = new { moCode = recommended }, chosen = new { moCode = chosen }, reason = "тест" };

    private static async Task RecordAsync(HttpClient client, string subjectId, string recommended, string chosen) =>
        Assert.Equal(HttpStatusCode.Created, (await client.PostAsJsonAsync("/api/v1/journal/decisions", Decision(subjectId, recommended, chosen))).StatusCode);

    internal static async Task AssertForbiddenAsync(HttpResponseMessage response, string detail)
    {
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        using var problem = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(detail, problem.RootElement.GetProperty("detail").GetString());
    }
}
