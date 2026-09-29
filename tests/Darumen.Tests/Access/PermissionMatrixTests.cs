using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Darumen.Migrations.Migrations;
using Darumen.Shared.Auth;

namespace Darumen.Tests.Access;

/// <summary>docs/rbac.md: на каждое разрешение — разрешённая и запрещённая роль на реальном эндпоинте.</summary>
public sealed class PermissionMatrixTests(TestApp app) : IClassFixture<TestApp>
{
    private static readonly object ReferralDecision = new
    {
        subject = "referral", subjectId = "75.028B.381.2025-03-15",
        recommended = new { moCode = "22GN" }, chosen = new { moCode = "028B" }, reason = "ближе к дому",
    };

    /// <summary>permission, метод, путь, тело, разрешённая роль, запрещённая роль (роль без строк в матрице — visitor).</summary>
    public static TheoryData<string, string, string, object?, string, string> Matrix => new()
    {
        { Permissions.RouteOwn, "GET", "/api/v1/route/me", null, Roles.Citizen, Roles.Regulator },
        { Permissions.WaitPublic, "POST", "/api/v1/queue/alternatives", new { regionKato = "75", profileCode = "381" }, Roles.Steward, "visitor" },
        { Permissions.MedicinesCheck, "POST", "/api/v1/medicines/check", new { mnnId = "817", nosologyId = "109" }, Roles.Citizen, Roles.Regulator },
        // admin, не doctor: у врача worklist.view — own (задача 1.2), а этот клиент общей матрицы создаётся без
        // moCode (CreateClient(allowed, ..., "75")) — own-скоуп без организации даёт 403 no_organization, что сломало
        // бы эту строку; admin — тот же принцип, что уже использован для admin.users (Roles.Auditor вместо org_admin).
        { Permissions.WorklistView, "GET", "/api/v1/journal/worklist", null, Roles.Admin, Roles.Regulator },
        { Permissions.ReferralAssist, "POST", "/api/v1/queue/alternatives", new { regionKato = "75", profileCode = "381", referralPurpose = "Оперативное лечение" }, Roles.Doctor, Roles.Citizen },
        { Permissions.ReferralConfirm, "POST", "/api/v1/journal/decisions", ReferralDecision, Roles.Doctor, Roles.Citizen },
        { Permissions.ScribeUse, "GET", "/api/v1/scribe/health", null, Roles.Doctor, Roles.Regulator },
        { Permissions.DecisionsOwn, "GET", "/api/v1/journal/decisions?actor=me", null, Roles.Doctor, Roles.Citizen },
        { Permissions.DecisionsAll, "GET", "/api/v1/journal/decisions", null, Roles.Regulator, Roles.Steward },
        { Permissions.GovMap, "GET", "/api/v1/streams", null, Roles.Steward, Roles.Doctor },
        { Permissions.GovSimulator, "POST", "/api/v1/simulate", new { regionKato = "75", profileCode = "381" }, Roles.Regulator, Roles.Steward },
        { Permissions.InsightAsk, "GET", "/api/v1/insight/status", null, Roles.Steward, Roles.Doctor },
        { Permissions.OrgCabinet, "GET", "/api/v1/queue/organizations/028B?profileCode=381", null, Roles.Regulator, Roles.Doctor },
        { Permissions.AdminUsers, "GET", "/api/v1/admin/users", null, Roles.Auditor, Roles.Doctor },
        { Permissions.DataSteward, "GET", "/api/v1/intake/batches", null, Roles.Steward, Roles.Regulator },
        { Permissions.AdminOrgs, "GET", "/api/v1/admin/orgs", null, Roles.Regulator, Roles.Auditor },
        { Permissions.AdminRoles, "GET", "/api/v1/admin/roles", null, Roles.Admin, Roles.Regulator },
    };

    [Theory]
    [MemberData(nameof(Matrix))]
    public async Task Permission_is_granted_and_denied_by_the_matrix(string permission, string method, string path, object? body, string allowed, string denied)
    {
        var granted = await SendAsync(app.CreateClient(allowed, $"{allowed}-matrix", "75"), method, path, body);
        Assert.True(granted.StatusCode is not (HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden),
            $"{permission}: {allowed} получил {(int)granted.StatusCode} на {method} {path}");

        var refused = await SendAsync(app.CreateClient(denied, $"{denied}-matrix", "75"), method, path, body);
        Assert.Equal(HttpStatusCode.Forbidden, refused.StatusCode);
        using var problem = JsonDocument.Parse(await refused.Content.ReadAsStringAsync());
        Assert.Equal(AccessProblems.PermissionRequired, problem.RootElement.GetProperty("detail").GetString());
        Assert.Contains(permission, problem.RootElement.GetProperty("permissions").EnumerateArray().Select(e => e.GetString()));
    }

    [Fact]
    public void Matrix_covers_every_permission_of_the_catalog()
    {
        var covered = Matrix.Select(row => (string)row[0]).ToHashSet();
        Assert.All(PermissionCatalog.All, p => Assert.Contains(p.Code, covered));
    }

    [Fact]
    public async Task Admin_passes_every_policy_and_anonymous_gets_401()
    {
        foreach (var path in new[] { "/api/v1/admin/roles", "/api/v1/streams", "/api/v1/journal/worklist", "/api/v1/intake/batches" })
        {
            Assert.Equal(HttpStatusCode.OK, (await app.CreateClient(Roles.Admin, "admin1").GetAsync(path)).StatusCode);
            Assert.Equal(HttpStatusCode.Unauthorized, (await app.CreateClient().GetAsync(path)).StatusCode);
        }
    }

    [Fact]
    public async Task Legacy_chief_role_is_treated_as_org_admin()
    {
        var chief = app.CreateClient(Roles.LegacyChief, "chief1", "75", "028B");
        Assert.Equal(HttpStatusCode.OK, (await chief.GetAsync("/api/v1/queue/organizations/028B?profileCode=381")).StatusCode);
        var me = await chief.GetFromJsonAsync<JsonElement>("/api/v1/me");
        Assert.Contains(Roles.OrgAdmin, me.GetProperty("roles").EnumerateArray().Select(r => r.GetString()));
    }

    [Fact]
    public void Migration_seed_matches_the_catalog_matrix()
    {
        var seeded = AuthRbac.SeedRolePermissions.Select(r => (r.Role, r.Permission, r.Scope)).OrderBy(r => r).ToList();
        var catalog = PermissionCatalog.DefaultMatrix.Select(r => (r.Role, r.Permission, r.Scope)).OrderBy(r => r).ToList();
        Assert.Equal(catalog, seeded);
        Assert.Equal(PermissionCatalog.BuiltinRoles.Select(r => r.Key).Order(), AuthRbac.SeedRoles.Select(r => r.Key).Order());
    }

    [Fact]
    public async Task Permission_matrix_is_cached_between_requests()
    {
        using var isolated = new TestApp();
        var doctor = isolated.CreateClient(Roles.Doctor, "doctor1", "75");
        await doctor.GetAsync("/api/v1/journal/worklist");
        var reads = isolated.Permissions.MatrixReads;
        await doctor.GetAsync("/api/v1/journal/worklist");
        await doctor.GetAsync("/api/v1/me");
        Assert.Equal(reads, isolated.Permissions.MatrixReads); // 30 с кэша: повторные запросы не читают матрицу заново
    }

    internal static Task<HttpResponseMessage> SendAsync(HttpClient client, string method, string path, object? body) => method switch
    {
        "POST" => client.PostAsJsonAsync(path, body),
        "PUT" => client.PutAsJsonAsync(path, body),
        "DELETE" => client.DeleteAsync(path),
        _ => client.GetAsync(path),
    };
}
