using System.Security.Claims;
using Darumen.Modules.Access.Data;
using Darumen.Modules.Access.Identity;
using Darumen.Modules.Access.Services;
using Darumen.Shared.Api;
using Darumen.Shared.Auth;

namespace Darumen.Modules.Access.Endpoints;

/// <summary>GET /me — кто я и что мне можно (источник меню и маршрутов клиентов), запрос доступа, удаление аккаунта.</summary>
public static class MeEndpoints
{
    private const int MaxPathLength = 500;
    private const int MaxCommentLength = 1000;
    /// <summary>Проверка второго фактора в /me необязательна и не должна задерживать старт клиента.</summary>
    private static readonly TimeSpan OptionalCallTimeout = TimeSpan.FromSeconds(2);

    public static void Map(IEndpointRouteBuilder api)
    {
        var me = api.MapGroup("/me").WithTags("Account").RequireAuthorization(Policies.Authenticated);

        me.MapGet("", GetMeAsync)
            .WithName("Me").WithSummary("Кто я: роли, действующие разрешения (code, scope), организация, ИИН маской, шаги онбординга")
            .Produces<MeDto>();

        me.MapPost("/access-requests", async (AccessRequestDto body, HttpContext http, IAccountStore account, AdminActions actions, CancellationToken ct) =>
            {
                var errors = new ValidationErrors().Require("permission", body.Permission).Require("path", body.Path);
                if (!errors.Any && PermissionCatalog.Find(body.Permission!) is null)
                {
                    errors.Add("permission", "неизвестное разрешение");
                }

                if (body.Path?.Length > MaxPathLength || body.Comment?.Length > MaxCommentLength)
                {
                    errors.Add("comment", $"путь до {MaxPathLength} символов, комментарий до {MaxCommentLength}");
                }

                if (errors.Any)
                {
                    return errors.Problem();
                }

                var user = CurrentUser.From(http);
                await account.AddRequestAsync(new AccountRequest(DateTimeOffset.UtcNow, user.UserId, user.Actor, user.Role, user.MoCode,
                    AccountRequestKinds.Access, body.Permission, body.Path, body.Comment?.Trim()), ct);
                actions.Audit(http, "access_request", $"permission={body.Permission} path={body.Path}");
                return Results.Accepted(value: new { accepted = true });
            })
            .WithName("RequestAccess").WithSummary("Запросить доступ к разделу: запись в аудит, видна администратору организации и системы")
            .Produces(StatusCodes.Status202Accepted).ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity);

        me.MapPost("/deletion-request", async (DeletionRequestDto? body, HttpContext http, IAccountStore account, AdminActions actions, CancellationToken ct) =>
            {
                if (body?.Comment?.Length > MaxCommentLength)
                {
                    return new ValidationErrors().Add("comment", $"до {MaxCommentLength} символов").Problem();
                }

                var user = CurrentUser.From(http);
                await account.AddRequestAsync(new AccountRequest(DateTimeOffset.UtcNow, user.UserId, user.Actor, user.Role, user.MoCode,
                    AccountRequestKinds.Deletion, null, null, body?.Comment?.Trim()), ct);
                actions.Audit(http, "deletion_request", "запрос на удаление аккаунта");
                return Results.Accepted(value: new { accepted = true });
            })
            .WithName("RequestDeletion").WithSummary("Запрос на удаление аккаунта: рассматривает администратор системы")
            .Produces(StatusCodes.Status202Accepted);

        MeDataEndpoints.Map(me);
    }

    private static async Task<IResult> GetMeAsync(HttpContext http, IPermissionService permissions, OrgDirectory orgs, IAccountStore account,
        IInvitationStore invitations, IIdentityAdmin identity, CancellationToken ct)
    {
        var user = CurrentUser.From(http);
        var principal = http.User;
        var grants = await permissions.EffectiveAsync(principal, ct);
        var emailVerified = string.Equals(principal.FindFirst(DarumenClaims.EmailVerified)?.Value, "true", StringComparison.OrdinalIgnoreCase);
        var settings = await SafeAsync(() => account.SettingsAsync(user.UserId, ct), null);
        var invited = await SafeAsync(() => invitations.AnyByInviterAsync(user.Actor, ct), false);
        var otp = await SafeAsync(async () =>
        {
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
            timeout.CancelAfter(OptionalCallTimeout);
            return (await identity.CredentialsAsync(user.UserId, timeout.Token)).Any(c => c.Type == "otp");
        }, false);

        return Results.Ok(new MeDto(
            user.Actor, user.UserId, DisplayName(principal, user.Actor), principal.FindFirst(DarumenClaims.Email)?.Value, emailVerified, user.Roles,
            grants.Select(g => new PermissionGrantDto(g.Code, PermissionScopes.Format(g.Scope)!)).ToList(),
            user.MoCode, await orgs.NameAsync(user.MoCode, ct), user.RegionKato, IinMask.Mask(user.Iin),
            new OnboardingDto(emailVerified, otp, settings?.ProfileCheckedAt is not null, invited)));
    }

    public static string DisplayName(ClaimsPrincipal principal, string fallback)
    {
        var full = principal.FindFirst(DarumenClaims.FullName)?.Value;
        if (!string.IsNullOrWhiteSpace(full))
        {
            return full;
        }

        var parts = new[] { principal.FindFirst(DarumenClaims.GivenName)?.Value, principal.FindFirst(DarumenClaims.FamilyName)?.Value }
            .Where(p => !string.IsNullOrWhiteSpace(p)).ToList();
        return parts.Count > 0 ? string.Join(' ', parts) : fallback;
    }

    /// <summary>Необязательные части /me (онбординг) не должны ронять ответ, если Postgres или Keycloak недоступны.</summary>
    internal static async Task<T> SafeAsync<T>(Func<Task<T>> call, T fallback)
    {
        try
        {
            return await call();
        }
        catch (Exception)
        {
            return fallback; // в том числе таймаут необязательного вызова Keycloak
        }
    }
}
