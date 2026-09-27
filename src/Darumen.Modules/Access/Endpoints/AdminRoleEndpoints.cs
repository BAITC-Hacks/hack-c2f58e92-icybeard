using System.Text.RegularExpressions;
using Darumen.Modules.Access.Identity;
using Darumen.Modules.Access.Services;
using Darumen.Shared.Api;
using Darumen.Shared.Auth;

namespace Darumen.Modules.Access.Endpoints;

/// <summary>Матрица ролей (admin.roles): чтение, изменение с журналом, создание и дублирование роли (realm role в Keycloak), история.</summary>
public static partial class AdminRoleEndpoints
{
    public static void Map(IEndpointRouteBuilder api)
    {
        var roles = api.MapGroup("/admin/roles").WithTags("Admin").RequireAuthorization(Permissions.Policy(Permissions.AdminRoles));

        roles.MapGet("", async (IPermissionStore store, IPermissionService permissions, UserDirectory directory, CancellationToken ct) =>
            {
                var records = await RolesAsync(store, ct);
                var (usersByRole, available) = await UsersByRoleAsync(directory, ct);
                var matrix = (await permissions.MatrixAsync(ct)).Select(m => new MatrixCellDto(m.Role, m.Permission, m.Scope)).ToList();
                return Results.Ok(new RolesResponseDto(
                    records.Select(r => new RoleDto(r.Key, r.TitleRu, r.TitleKk, r.DescriptionRu, r.DescriptionKk, r.Builtin, r.Key != Roles.Admin)).ToList(),
                    PermissionCatalog.All.Select(p => new PermissionDto(p.Code, p.TitleRu, p.TitleKk, p.System, PermissionCatalog.IsEditable(p.Code))).ToList(),
                    matrix, usersByRole, available));
            })
            .WithName("AdminRoles").WithSummary("Роли, каталог разрешений RU/KK, матрица и число пользователей по ролям").Produces<RolesResponseDto>();

        roles.MapPut("/{key}/permissions", UpdateAsync)
            .WithName("AdminUpdateRolePermissions")
            .WithSummary("Изменить разрешения роли: changes [{ permission, scope: all | own | null }]; изменения — в журнал, кэш разрешений сбрасывается")
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity).ProducesProblem(StatusCodes.Status404NotFound);

        roles.MapPost("", CreateAsync)
            .WithName("AdminCreateRole").WithSummary("Создать роль (или копию copyFrom): realm role в Keycloak и строка матрицы")
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity).ProducesProblem(StatusCodes.Status409Conflict);

        roles.MapGet("/history", async (string? role, int? page, int? size, IPermissionStore store, CancellationToken ct) =>
            {
                var (p, s) = Paging.Normalize(page, size);
                var history = await store.HistoryAsync(role, p, s, ct);
                return Results.Ok(new Paged<RoleChangeDto>(history.Items.Select(ToDto).ToList(), history.Page, history.Size, history.Total));
            })
            .WithName("AdminRolesHistory").WithSummary("Журнал изменений матрицы").Produces<Paged<RoleChangeDto>>();
    }

    private static async Task<IResult> UpdateAsync(string key, RolePermissionsUpdateDto body, HttpContext http, IPermissionStore store,
        IPermissionService permissions, AdminActions actions, CancellationToken ct)
    {
        if ((await RolesAsync(store, ct)).All(r => r.Key != key))
        {
            return Results.Problem(statusCode: StatusCodes.Status404NotFound, title: "Роль не найдена", detail: key);
        }

        var errors = ValidateChanges(key, body);
        if (errors.Any)
        {
            return errors.Problem();
        }

        var changes = body.Changes!.Select(c => new PermissionChange(c.Permission!, c.Scope)).ToList();
        var before = (await permissions.MatrixAsync(ct)).Where(m => m.Role == key).ToDictionary(m => m.Permission, m => m.Scope);
        var applied = await store.ApplyAsync(key, changes, CurrentUser.From(http).Actor, body.Comment?.Trim(), ct);
        permissions.Invalidate();
        if (applied.Count > 0)
        {
            await actions.RecordAsync(http, DecisionSubjects.RolePermissions, key,
                applied.ToDictionary(a => a.Permission, a => before.GetValueOrDefault(a.Permission)),
                applied.ToDictionary(a => a.Permission, a => a.NewScope), body.Comment?.Trim(), ct);
        }

        var matrix = (await permissions.MatrixAsync(ct)).Where(m => m.Role == key).Select(m => new MatrixCellDto(m.Role, m.Permission, m.Scope)).ToList();
        return Results.Ok(new { role = key, matrix, applied = applied.Select(ToDto).ToList() });
    }

    private static ValidationErrors ValidateChanges(string key, RolePermissionsUpdateDto body)
    {
        var errors = new ValidationErrors();
        if (key == Roles.Admin)
        {
            return errors.Add("role", "строка администратора системы не редактируется");
        }

        if (body.Changes is not { Count: > 0 })
        {
            return errors.Add("changes", "нужно хотя бы одно изменение");
        }

        foreach (var change in body.Changes)
        {
            if (change.Permission is null || !PermissionCatalog.IsEditable(change.Permission))
            {
                errors.Add("changes", $"{change.Permission}: разрешения нет в матрице или оно системное");
            }
            else if (change.Scope is not null && !PermissionScopes.IsValid(change.Scope))
            {
                errors.Add("changes", $"{change.Permission}: scope — all, own или null");
            }
            else if (change.Permission == Permissions.WaitPublic && change.Scope != PermissionScopes.All)
            {
                errors.Add("changes", "wait.public не снимается ни с одной роли и действует на всю страну");
            }
        }

        return errors;
    }

    private static async Task<IResult> CreateAsync(RoleCreateDto body, HttpContext http, IPermissionStore store, IPermissionService permissions,
        IIdentityAdmin identity, AdminActions actions, CancellationToken ct)
    {
        var existing = await RolesAsync(store, ct);
        var errors = new ValidationErrors().Require("key", body.Key).Require("titleRu", body.TitleRu).Require("titleKk", body.TitleKk);
        if (body.Key is not null && !KeyPattern().IsMatch(body.Key))
        {
            errors.Add("key", "латиница в нижнем регистре, цифры и _, 3–32 символа, с буквы");
        }

        if (body.CopyFrom is not null && (existing.All(r => r.Key != body.CopyFrom) || body.CopyFrom == Roles.Admin))
        {
            errors.Add("copyFrom", "роль-образец не найдена (admin копировать нельзя)");
        }

        if (errors.Any)
        {
            return errors.Problem();
        }

        if (existing.Any(r => r.Key == body.Key) || body.Key == Roles.LegacyChief)
        {
            return Results.Problem(statusCode: StatusCodes.Status409Conflict, title: "Роль уже есть", detail: body.Key);
        }

        // сначала роль реалма: без неё назначить новую роль пользователю нельзя; уже существующая в Keycloak — не ошибка
        await identity.CreateRoleAsync(body.Key!, body.DescriptionRu ?? body.TitleRu, ct);
        var record = new RoleRecord(body.Key!, body.TitleRu!.Trim(), body.TitleKk!.Trim(), body.DescriptionRu?.Trim(), body.DescriptionKk?.Trim(), false, DateTimeOffset.UtcNow);
        var applied = await store.CreateRoleAsync(record, body.CopyFrom, CurrentUser.From(http).Actor, ct);
        permissions.Invalidate();
        await actions.RecordAsync(http, DecisionSubjects.RolePermissions, record.Key, body.CopyFrom is null ? null : new { copyFrom = body.CopyFrom },
            applied.ToDictionary(a => a.Permission, a => a.NewScope), "роль создана", ct);
        return Results.Created($"/api/v1/admin/roles/{record.Key}",
            new RoleDto(record.Key, record.TitleRu, record.TitleKk, record.DescriptionRu, record.DescriptionKk, false, true));
    }

    private static async Task<IReadOnlyList<RoleRecord>> RolesAsync(IPermissionStore store, CancellationToken ct) =>
        await MeEndpoints.SafeAsync(() => store.RolesAsync(ct), PermissionCatalog.BuiltinRoles
            .Select(r => new RoleRecord(r.Key, r.TitleRu, r.TitleKk, r.DescriptionRu, r.DescriptionKk, true, DateTimeOffset.MinValue)).ToList());

    private static async Task<(IReadOnlyDictionary<string, int> Counts, bool Available)> UsersByRoleAsync(UserDirectory directory, CancellationToken ct)
    {
        try
        {
            var users = await directory.AllAsync(ct);
            return (users.SelectMany(u => u.Roles).GroupBy(r => r).ToDictionary(g => g.Key, g => g.Count()), true);
        }
        catch (IdentityUnavailableException)
        {
            return (new Dictionary<string, int>(), false); // матрица доступна и без Keycloak, числа пользователей — нет
        }
    }

    private static RoleChangeDto ToDto(PermissionChangeRecord r) => new(r.Id, r.At, r.Actor, r.Role, r.Permission, r.OldScope, r.NewScope, r.Comment);

    [GeneratedRegex("^[a-z][a-z0-9_]{2,31}$")]
    private static partial Regex KeyPattern();
}
