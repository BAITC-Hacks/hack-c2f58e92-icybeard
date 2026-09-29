using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Darumen.Modules.Access;
using Darumen.Modules.Analytics;
using Darumen.Modules.Queue;
using Darumen.Shared.Api;
using Darumen.Shared.Auth;

namespace Darumen.Tests.Access;

/// <summary>Изменение матрицы через PUT /admin/roles/{key}/permissions меняет доступ сразу (кэш сбрасывается), пишется в журнал.
/// Каждый тест — на своём экземпляре API: матрица общая для приложения.</summary>
public sealed class MatrixChangeTests
{
    [Fact]
    public async Task Granting_and_revoking_a_permission_changes_access_without_restart()
    {
        using var app = new TestApp();
        var admin = app.CreateClient(Roles.Admin, "admin1");
        var regulator = app.CreateClient(Roles.Regulator, "regulator1", "75");
        Assert.Equal(HttpStatusCode.Forbidden, (await regulator.GetAsync("/api/v1/journal/worklist")).StatusCode);

        var grant = await admin.PutAsJsonAsync("/api/v1/admin/roles/regulator/permissions",
            new RolePermissionsUpdateDto([new PermissionChangeDto(Permissions.WorklistView, PermissionScopes.All)], "пилот рабочего списка"));
        Assert.Equal(HttpStatusCode.OK, grant.StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await regulator.GetAsync("/api/v1/journal/worklist")).StatusCode);

        var me = await regulator.GetFromJsonAsync<MeDto>("/api/v1/me");
        Assert.Contains(me!.Permissions, p => p.Code == Permissions.WorklistView && p.Scope == PermissionScopes.All);

        await admin.PutAsJsonAsync("/api/v1/admin/roles/regulator/permissions",
            new RolePermissionsUpdateDto([new PermissionChangeDto(Permissions.WorklistView, null)], "пилот завершён"));
        Assert.Equal(HttpStatusCode.Forbidden, (await regulator.GetAsync("/api/v1/journal/worklist")).StatusCode);

        var history = await admin.GetFromJsonAsync<Paged<RoleChangeDto>>("/api/v1/admin/roles/history?role=regulator");
        Assert.Equal(2, history!.Total);
        Assert.Equal("пилот завершён", history.Items[0].Comment);
        Assert.Null(history.Items[0].NewScope);
        Assert.Equal(2, app.Decisions.Published.OfType<Darumen.Contracts.V1.DecisionRecorded>().Count(e => e.Subject == DecisionSubjects.RolePermissions));
    }

    [Fact]
    public async Task Map_granted_to_org_admin_stays_within_own_region()
    {
        // роль, привязанная к региону, прогнозирует и видит перегрузку только своего региона (клейм region_kato сильнее запроса)
        using var app = new TestApp();
        var chief = app.CreateClient(Roles.OrgAdmin, "chief-10", "10", "11XY");
        Assert.Equal(HttpStatusCode.Forbidden, (await chief.GetAsync("/api/v1/queue/overloaded?regionKato=75&profileCode=381")).StatusCode);

        await app.CreateClient(Roles.Admin, "admin1").PutAsJsonAsync("/api/v1/admin/roles/org_admin/permissions",
            new RolePermissionsUpdateDto([new PermissionChangeDto(Permissions.GovMap, PermissionScopes.All)], null));

        var forecast = await chief.GetFromJsonAsync<ForecastResponseDto>("/api/v1/forecast/admissions_monthly?entity[regionKato]=75&entity[profileCode]=381&horizon=3");
        Assert.Equal("10", forecast!.Entity["region_kato"]);
        Assert.Equal("10", app.Forecast.LastRequest!.Entity["region_kato"]);
        var overloaded = await chief.GetFromJsonAsync<JsonElement>("/api/v1/queue/overloaded?regionKato=75&profileCode=381");
        Assert.All(overloaded.GetProperty("items").EnumerateArray(), i => Assert.Equal("10", i.GetProperty("regionKato").GetString()));
    }

    [Fact]
    public async Task Matrix_rejects_admin_row_system_permissions_and_removing_public_waits()
    {
        using var app = new TestApp();
        var admin = app.CreateClient(Roles.Admin, "admin1");
        async Task<HttpStatusCode> Put(string role, string permission, string? scope) =>
            (await admin.PutAsJsonAsync($"/api/v1/admin/roles/{role}/permissions", new RolePermissionsUpdateDto([new PermissionChangeDto(permission, scope)], null))).StatusCode;

        Assert.Equal(HttpStatusCode.UnprocessableEntity, await Put(Roles.Admin, Permissions.GovMap, null));
        Assert.Equal(HttpStatusCode.UnprocessableEntity, await Put(Roles.Steward, Permissions.DataSteward, null));
        Assert.Equal(HttpStatusCode.UnprocessableEntity, await Put(Roles.Citizen, Permissions.WaitPublic, null));
        Assert.Equal(HttpStatusCode.UnprocessableEntity, await Put(Roles.Citizen, Permissions.GovMap, "everything"));
        Assert.Equal(HttpStatusCode.NotFound, await Put("ghost", Permissions.GovMap, PermissionScopes.All));
        Assert.Equal(HttpStatusCode.Forbidden, (await app.CreateClient(Roles.OrgAdmin, "chief1", "75", "028B")
            .PutAsJsonAsync("/api/v1/admin/roles/doctor/permissions", new RolePermissionsUpdateDto([new PermissionChangeDto(Permissions.GovMap, PermissionScopes.All)], null))).StatusCode);
    }

    [Fact]
    public async Task New_role_copies_permissions_and_is_created_in_keycloak()
    {
        using var app = new TestApp();
        var admin = app.CreateClient(Roles.Admin, "admin1");
        var created = await admin.PostAsJsonAsync("/api/v1/admin/roles", new RoleCreateDto("nurse", "Медсестра", "Мейірбике", "Помощь врачу", null, Roles.Doctor));
        Assert.Equal(HttpStatusCode.Created, created.StatusCode);
        Assert.Contains("nurse", app.Identity.CreatedRoles);

        // moCode обязателен: "nurse" копирует текущую матрицу doctor, а worklist.view у врача — own (задача 1.2
        // плана прозрачности), без организации был бы 403 no_organization вместо ожидаемого 200.
        var nurse = app.CreateClient("nurse", "nurse1", "75", "028B");
        Assert.Equal(HttpStatusCode.OK, (await nurse.GetAsync("/api/v1/journal/worklist")).StatusCode);
        var roles = await admin.GetFromJsonAsync<RolesResponseDto>("/api/v1/admin/roles");
        Assert.Contains(roles!.Roles, r => r.Key == "nurse" && !r.Builtin);
        Assert.Contains(roles.Matrix, m => m.Role == "nurse" && m.Permission == Permissions.ScribeUse);
        Assert.Contains(roles.Permissions, p => p.Code == Permissions.AdminRoles && p.System && !p.Editable);
        Assert.True(roles.IdentityAvailable);
        Assert.Equal(4, roles.UsersByRole[Roles.Doctor]); // doctor1, doctor-28, doctor2 и заблокированный blocked1

        Assert.Equal(HttpStatusCode.Conflict, (await admin.PostAsJsonAsync("/api/v1/admin/roles", new RoleCreateDto("nurse", "Дубль", "Дубль", null, null, null))).StatusCode);
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await admin.PostAsJsonAsync("/api/v1/admin/roles", new RoleCreateDto("Bad Key", "x", "x", null, null, null))).StatusCode);
    }

    /// <summary>Задача 8 плана прозрачности: «Менеджер по койкам» — урезанная версия org_admin (рабочий список и
    /// подтверждение направлений своей организации, без кабинета организации/пользователей), заводится тем же
    /// общим механизмом, что и «nurse» выше (POST /admin/roles), а не сидируется миграцией — см. doc-комментарии
    /// AuthRbac.Seed и Roles.BedManager. Существующих org_admin роль не трогает и никого не переносит: это отдельная,
    /// назначаемая по желанию роль.</summary>
    [Fact]
    public async Task Bed_manager_role_is_scoped_to_worklist_and_referral_confirm_of_its_own_organization()
    {
        using var app = new TestApp();
        var admin = app.CreateClient(Roles.Admin, "admin1");
        var created = await admin.PostAsJsonAsync("/api/v1/admin/roles",
            new RoleCreateDto(Roles.BedManager, "Менеджер по койкам", "Төсек-орын менеджері",
                "Рабочий список пациентов и подтверждение приёма направлений в своей организации", null, null));
        Assert.Equal(HttpStatusCode.Created, created.StatusCode);
        Assert.Contains(Roles.BedManager, app.Identity.CreatedRoles);

        var grant = await admin.PutAsJsonAsync($"/api/v1/admin/roles/{Roles.BedManager}/permissions",
            new RolePermissionsUpdateDto(
                [new PermissionChangeDto(Permissions.WorklistView, PermissionScopes.Own), new PermissionChangeDto(Permissions.ReferralConfirm, PermissionScopes.Own)],
                "задача 8 плана прозрачности"));
        Assert.Equal(HttpStatusCode.OK, grant.StatusCode);

        var bedManager = app.CreateClient(Roles.BedManager, "bm-028B", "75", "028B");
        var me = await bedManager.GetFromJsonAsync<MeDto>("/api/v1/me");
        Assert.Contains(me!.Permissions, p => p.Code == Permissions.WorklistView && p.Scope == PermissionScopes.Own);
        Assert.Contains(me.Permissions, p => p.Code == Permissions.ReferralConfirm && p.Scope == PermissionScopes.Own);

        // свой рабочий список — можно, чужая организация в own-скоупе — 403 (тот же принцип, что у org_admin/doctor)
        Assert.Equal(HttpStatusCode.OK, (await bedManager.GetAsync("/api/v1/journal/worklist")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await bedManager.GetAsync("/api/v1/journal/worklist?moCode=ZZZZ")).StatusCode);

        // ничего сверх выданного (в отличие от doctor/org_admin, урезанная роль не копирует более широкую матрицу)
        Assert.Equal(HttpStatusCode.Forbidden, (await bedManager.GetAsync("/api/v1/route/me")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await bedManager.GetAsync("/api/v1/streams")).StatusCode);

        // org_admin теперь может назначать эту роль в своей организации (AdminGuards.CheckRole проверяет ровно этот список)
        Assert.Contains(Roles.BedManager, PermissionCatalog.OrgAssignableRoles);
    }
}
