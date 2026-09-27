using Darumen.Modules.Access.Services;
using Darumen.Shared.Api;
using Darumen.Shared.Auth;

namespace Darumen.Modules.Access.Endpoints;

/// <summary>Кто кого администрирует: при scope own — только пользователей своей организации и только роли doctor/org_admin;
/// учётные записи и роль admin — только администратору системы.</summary>
public static class AdminGuards
{
    public const string RoleNotAssignable = "role_not_assignable";

    public static IResult? CheckTarget(HttpContext http, OrgScope scope, DirectoryUser target)
    {
        if (scope.IsOwn && !string.Equals(target.MoCode, scope.MoCode, StringComparison.OrdinalIgnoreCase))
        {
            return AccessProblems.Forbidden(AccessProblems.OtherOrganization);
        }

        return target.Has(Roles.Admin) && !IsSystemAdmin(http) ? AccessProblems.Forbidden(AccessProblems.PermissionRequired, Permissions.AdminRoles) : null;
    }

    public static IResult? CheckRole(HttpContext http, OrgScope scope, string role)
    {
        if (scope.IsOwn && !PermissionCatalog.OrgAssignableRoles.Contains(role))
        {
            return Results.Problem(statusCode: StatusCodes.Status403Forbidden, title: "Администратор организации назначает только врачей и администраторов организации",
                detail: RoleNotAssignable);
        }

        return role == Roles.Admin && !IsSystemAdmin(http)
            ? Results.Problem(statusCode: StatusCodes.Status403Forbidden, title: "Роль admin назначает только администратор системы", detail: RoleNotAssignable)
            : null;
    }

    /// <summary>Организация результата: при own — только своя (другая — 403), при all — из запроса.</summary>
    public static (string? MoCode, IResult? Problem) Organization(OrgScope scope, string? requested) =>
        !scope.IsOwn
            ? (string.IsNullOrWhiteSpace(requested) ? null : requested.Trim(), null)
            : string.IsNullOrWhiteSpace(requested) || string.Equals(requested.Trim(), scope.MoCode, StringComparison.OrdinalIgnoreCase)
                ? (scope.MoCode, null)
                : (null, AccessProblems.Forbidden(AccessProblems.OtherOrganization));

    private static bool IsSystemAdmin(HttpContext http) => CurrentUser.From(http).Roles.Contains(Roles.Admin);
}
