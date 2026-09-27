using Darumen.Modules.Access.Identity;
using Darumen.Modules.Access.Mail;
using Darumen.Modules.Access.Services;
using Darumen.Shared.Api;
using Darumen.Shared.Auth;

namespace Darumen.Modules.Access.Endpoints;

/// <summary>Пользователи (admin.users): список с фильтрами и сводкой, карточка, роль и организация, блокировка, приглашение.
/// При scope own — только своя организация и роли doctor/org_admin.</summary>
public static class AdminUserEndpoints
{
    public static void Map(IEndpointRouteBuilder api)
    {
        var users = api.MapGroup("/admin/users").WithTags("Admin").RequireAuthorization(Permissions.Policy(Permissions.AdminUsers));

        users.MapGet("", async (string? role, string? moCode, string? status, string? q, int? page, int? size, HttpContext http,
                UserDirectory directory, UserRows rows, CancellationToken ct) =>
            {
                var scope = await OrgAccess.ResolveAsync(http, moCode, Permissions.AdminUsers);
                if (scope.Problem is not null)
                {
                    return scope.Problem;
                }

                var inScope = (await directory.AllAsync(ct)).Where(u => UserRows.InOrganization(u, scope.MoCode)).ToList();
                var open = await rows.OpenInvitationsAsync(inScope, ct);
                var filtered = inScope
                    .Where(u => UserRows.HasRole(u, role) && UserRows.Matches(u, q) && (status is null || UserRows.Status(u, open) == status))
                    .OrderBy(u => u.Identity.DisplayName, StringComparer.CurrentCulture).ToList();
                var (p, s) = Paging.Normalize(page, size);
                var pageItems = await rows.RowsAsync(filtered.Skip((p - 1) * s).Take(s).ToList(), open, ct);
                return Results.Ok(new UsersPageDto(pageItems, filtered.Count, p, s, rows.Summary(inScope, open)));
            })
            .WithName("AdminUsers").WithSummary("Пользователи: role, moCode, status (active | invited | blocked), q; сводка active / invitedStale / blocked")
            .Produces<UsersPageDto>().ProducesProblem(StatusCodes.Status403Forbidden).ProducesProblem(StatusCodes.Status503ServiceUnavailable);

        users.MapGet("/{id}", async (string id, HttpContext http, UserDirectory directory, UserRows rows, CancellationToken ct) =>
            {
                var (target, scope, problem) = await TargetAsync(id, http, directory, ct);
                return problem ?? Results.Ok(await DetailAsync(target!, rows, ct));
            })
            .WithName("AdminUser").WithSummary("Карточка пользователя").Produces<UserDetailDto>()
            .ProducesProblem(StatusCodes.Status403Forbidden).ProducesProblem(StatusCodes.Status404NotFound);

        users.MapPut("/{id}", UpdateAsync)
            .WithName("AdminUpdateUser").WithSummary("Сменить роль и организацию; решение уходит в журнал")
            .Produces<UserDetailDto>().ProducesProblem(StatusCodes.Status403Forbidden).ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity);

        users.MapPost("/{id}/block", (string id, HttpContext http, UserDirectory directory, IIdentityAdmin identity, AdminActions actions, UserRows rows, CancellationToken ct) =>
                SetEnabledAsync(id, false, http, directory, identity, actions, rows, ct))
            .WithName("AdminBlockUser").WithSummary("Заблокировать: учётная запись выключается, сессии завершаются").Produces<UserDetailDto>();

        users.MapPost("/{id}/unblock", (string id, HttpContext http, UserDirectory directory, IIdentityAdmin identity, AdminActions actions, UserRows rows, CancellationToken ct) =>
                SetEnabledAsync(id, true, http, directory, identity, actions, rows, ct))
            .WithName("AdminUnblockUser").WithSummary("Разблокировать").Produces<UserDetailDto>();

        users.MapPost("/invite", AdminInvite.InviteAsync)
            .WithName("AdminInviteUser").WithSummary("Пригласить: пользователь в Keycloak (выключен до принятия), ссылка /invite/{token} на 7 дней; без SMTP — inviteUrl и emailSent: false")
            .Produces<InviteResultDto>(StatusCodes.Status201Created).ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status409Conflict).ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity);
    }

    internal static async Task<(DirectoryUser? Target, OrgScope Scope, IResult? Problem)> TargetAsync(string id, HttpContext http, UserDirectory directory, CancellationToken ct)
    {
        var scope = await OrgAccess.ResolveAsync(http, null, Permissions.AdminUsers);
        if (scope.Problem is not null)
        {
            return (null, scope, scope.Problem);
        }

        var target = await directory.FindAsync(id, ct);
        if (target is null)
        {
            return (null, scope, Results.Problem(statusCode: StatusCodes.Status404NotFound, title: "Пользователь не найден"));
        }

        return (target, scope, AdminGuards.CheckTarget(http, scope, target));
    }

    internal static async Task<UserDetailDto> DetailAsync(DirectoryUser user, UserRows rows, CancellationToken ct)
    {
        var open = await rows.OpenInvitationsAsync([user], ct);
        var row = (await rows.RowsAsync([user], open, ct))[0];
        var invitation = open.GetValueOrDefault(user.Id);
        return new UserDetailDto(row, user.Identity.EmailVerified, user.Identity.CreatedAt, user.Position, user.Specialty, invitation?.InvitedAt, invitation?.ExpiresAt);
    }

    private static async Task<IResult> UpdateAsync(string id, UserUpdateDto body, HttpContext http, UserDirectory directory, IIdentityAdmin identity,
        AdminActions actions, UserRows rows, CancellationToken ct)
    {
        var (target, scope, problem) = await TargetAsync(id, http, directory, ct);
        if (problem is not null)
        {
            return problem;
        }

        var roleKeys = await directory.RoleKeysAsync(ct);
        var errors = new ValidationErrors().Require("role", body.Role).Kato("regionKato", body.RegionKato);
        if (body.Role is not null && (!roleKeys.Contains(body.Role) || body.Role == Roles.LegacyChief))
        {
            errors.Add("role", "неизвестная роль");
        }

        var (moCode, moProblem) = AdminGuards.Organization(scope, body.MoCode ?? target!.MoCode);
        if (!errors.Any && body.Role == Roles.OrgAdmin && string.IsNullOrWhiteSpace(moCode))
        {
            errors.Add("moCode", "администратору организации нужен код организации");
        }

        if (errors.Any)
        {
            return errors.Problem();
        }

        if ((moProblem ?? AdminGuards.CheckRole(http, scope, body.Role!)) is { } denied)
        {
            return denied;
        }

        await identity.SetRolesAsync(id, [body.Role!], roleKeys.Where(r => r != body.Role).ToList(), ct);
        await identity.UpdateUserAsync(id, new IdentityUserUpdate(Attributes: new Dictionary<string, string?>
        {
            [IdentityAttributes.MoCode] = moCode,
            [IdentityAttributes.RegionKato] = body.RegionKato ?? target!.RegionKato,
        }), ct);
        await actions.RecordAsync(http, DecisionSubjects.UserAccess, id, new { roles = target!.Roles, moCode = target.MoCode },
            new { role = body.Role, moCode, regionKato = body.RegionKato ?? target.RegionKato }, null, ct);
        return Results.Ok(await DetailAsync((await directory.FindAsync(id, ct))!, rows, ct));
    }

    private static async Task<IResult> SetEnabledAsync(string id, bool enabled, HttpContext http, UserDirectory directory, IIdentityAdmin identity,
        AdminActions actions, UserRows rows, CancellationToken ct)
    {
        var (target, _, problem) = await TargetAsync(id, http, directory, ct);
        if (problem is not null)
        {
            return problem;
        }

        if (!enabled && target!.Identity.Username == CurrentUser.From(http).Actor)
        {
            return new ValidationErrors().Add("id", "нельзя заблокировать самого себя").Problem();
        }

        await identity.UpdateUserAsync(id, new IdentityUserUpdate(Enabled: enabled), ct);
        if (!enabled)
        {
            await identity.LogoutAsync(id, ct);
        }

        await actions.RecordAsync(http, DecisionSubjects.UserAccess, id, new { status = target!.Identity.Enabled ? UserStatuses.Active : UserStatuses.Blocked },
            new { status = enabled ? UserStatuses.Active : UserStatuses.Blocked }, null, ct);
        return Results.Ok(await DetailAsync((await directory.FindAsync(id, ct))!, rows, ct));
    }
}

/// <summary>POST /admin/users/invite.</summary>
internal static class AdminInvite
{
    public static async Task<IResult> InviteAsync(InviteRequestDto body, HttpContext http, UserDirectory directory, InvitationService invitations,
        IEmailSender mail, OrgDirectory orgs, IPermissionStore roleStore, AdminActions actions, CancellationToken ct)
    {
        var scope = await OrgAccess.ResolveAsync(http, null, Permissions.AdminUsers);
        if (scope.Problem is not null)
        {
            return scope.Problem;
        }

        var roleKeys = await directory.RoleKeysAsync(ct);
        var errors = AccountValidation.Email(new ValidationErrors(), "email", body.Email).Require("displayName", body.DisplayName).Require("role", body.Role)
            .Kato("regionKato", body.RegionKato);
        AccountValidation.MaxLength(errors, "displayName", body.DisplayName);
        if (body.Role is not null && (!roleKeys.Contains(body.Role) || body.Role == Roles.LegacyChief))
        {
            errors.Add("role", "неизвестная роль");
        }

        var (moCode, moProblem) = AdminGuards.Organization(scope, body.MoCode);
        if (!errors.Any && body.Role == Roles.OrgAdmin && moCode is null)
        {
            errors.Add("moCode", "администратору организации нужен код организации");
        }

        if (errors.Any)
        {
            return errors.Problem();
        }

        if ((moProblem ?? AdminGuards.CheckRole(http, scope, body.Role!)) is { } denied)
        {
            return denied;
        }

        var user = CurrentUser.From(http);
        var created = await invitations.CreateAsync(new InviteCommand(body.Email!, body.DisplayName!, body.Role!, moCode, body.RegionKato), user.Actor, ct);
        var roleTitle = await RoleTitleAsync(roleStore, body.Role!, ct);
        var invitation = created.Invitation;
        var sent = await mail.SendAsync(EmailTemplates.Invitation(invitation.Email, invitation.DisplayName, roleTitle, await orgs.NameAsync(moCode, ct),
            MeEndpoints.DisplayName(http.User, user.Actor), created.Url, invitation.ExpiresAt), ct);
        actions.Audit(http, "invite", $"user={invitation.UserId} role={invitation.Role} mo={moCode} emailSent={sent}");
        return Results.Created($"/api/v1/admin/users/{invitation.UserId}",
            new InviteResultDto(invitation.UserId, invitation.Id, invitation.ExpiresAt, sent, sent ? null : created.Url));
    }

    public static async Task<string> RoleTitleAsync(IPermissionStore roleStore, string role, CancellationToken ct)
    {
        var builtin = PermissionCatalog.BuiltinRoles.FirstOrDefault(r => r.Key == role)?.TitleRu;
        if (builtin is not null)
        {
            return builtin;
        }

        return await MeEndpoints.SafeAsync(async () => (await roleStore.RolesAsync(ct)).FirstOrDefault(r => r.Key == role)?.TitleRu ?? role, role);
    }
}
