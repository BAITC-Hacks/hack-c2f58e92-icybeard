using Darumen.Modules.Access.Data;
using Darumen.Modules.Access.Identity;
using Darumen.Modules.Access.Services;
using Darumen.Shared.Api;
using Darumen.Shared.Auth;

namespace Darumen.Modules.Access.Endpoints;

/// <summary>Приглашение по ссылке /invite/{token}: просмотр, принятие (пароль по политике реалма, пользователь включается,
/// почта подтверждается) и отказ (выключенная учётная запись удаляется).</summary>
public static class PublicInviteEndpoints
{
    public static void Map(IEndpointRouteBuilder api)
    {
        var invites = api.MapGroup("/public/invites").WithTags("Public").AllowAnonymous();

        invites.MapGet("/{token}", async (string token, IInvitationStore store, OrgDirectory orgs, IPermissionStore roles, TimeProvider time, CancellationToken ct) =>
            {
                var (invitation, problem) = await OpenAsync(token, store, time, ct);
                if (problem is not null)
                {
                    return problem;
                }

                var role = PermissionCatalog.BuiltinRoles.FirstOrDefault(r => r.Key == invitation!.Role);
                var titleRu = role?.TitleRu ?? await AdminInvite.RoleTitleAsync(roles, invitation!.Role, ct);
                return Results.Ok(new InviteInfoDto(invitation!.DisplayName, invitation.Email, await orgs.NameAsync(invitation.MoCode, ct), invitation.MoCode,
                    invitation.Role, titleRu, role?.TitleKk ?? titleRu, invitation.InvitedBy, invitation.InvitedAt, invitation.ExpiresAt));
            })
            .WithName("Invite").WithSummary("Приглашение: кто, куда и с какой ролью приглашён; 404 — нет такого, 410 — истекло, принято или отклонено")
            .Produces<InviteInfoDto>().ProducesProblem(StatusCodes.Status404NotFound).ProducesProblem(StatusCodes.Status410Gone);

        invites.MapPost("/{token}/accept", async (string token, InviteAcceptDto body, IInvitationStore store, IIdentityAdmin identity, TimeProvider time,
                CancellationToken ct) =>
            {
                var errors = new ValidationErrors().Require("password", body.Password);
                if (!body.AcceptedRules)
                {
                    errors.Add("acceptedRules", "нужно принять правила работы с данными");
                }

                if (errors.Any)
                {
                    return errors.Problem();
                }

                var (invitation, problem) = await OpenAsync(token, store, time, ct);
                if (problem is not null)
                {
                    return problem;
                }

                // политика паролей реалма проверяется в Keycloak; нарушение — 422 с текстом RU/KK (IdentityExceptionHandler)
                await identity.SetPasswordAsync(invitation!.UserId, body.Password!, ct);
                await identity.UpdateUserAsync(invitation.UserId, new IdentityUserUpdate(Enabled: true, EmailVerified: true), ct);
                await store.CloseAsync(invitation.Id, accepted: true, time.GetUtcNow(), ct);
                return Results.Ok(new InviteAcceptedDto(invitation.Email, true));
            })
            .RequireRateLimiting(RateLimits.PublicForms)
            .WithName("AcceptInvite").WithSummary("Принять приглашение: пароль по политике реалма и согласие с правилами")
            .Produces<InviteAcceptedDto>().ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status410Gone).Produces(StatusCodes.Status429TooManyRequests);

        invites.MapPost("/{token}/decline", async (string token, IInvitationStore store, IIdentityAdmin identity, TimeProvider time, CancellationToken ct) =>
            {
                var (invitation, problem) = await OpenAsync(token, store, time, ct);
                if (problem is not null)
                {
                    return problem;
                }

                await store.CloseAsync(invitation!.Id, accepted: false, time.GetUtcNow(), ct);
                await identity.DeleteUserAsync(invitation.UserId, ct); // учётная запись не включалась — удаляем
                return Results.Ok(new { declined = true });
            })
            .RequireRateLimiting(RateLimits.PublicForms)
            .WithName("DeclineInvite").WithSummary("Отказаться от приглашения")
            .ProducesProblem(StatusCodes.Status410Gone);
    }

    private static async Task<(Invitation? Invitation, IResult? Problem)> OpenAsync(string token, IInvitationStore store, TimeProvider time, CancellationToken ct)
    {
        var invitation = await store.ByTokenHashAsync(Tokens.Hash(token), ct);
        if (invitation is null)
        {
            return (null, Results.Problem(statusCode: StatusCodes.Status404NotFound, title: "Приглашение не найдено", detail: "not_found"));
        }

        var state = invitation.AcceptedAt is not null ? "accepted" : invitation.DeclinedAt is not null ? "declined"
            : invitation.ExpiresAt <= time.GetUtcNow() ? "expired" : null;
        return state is null
            ? (invitation, null)
            : (null, Results.Problem(statusCode: StatusCodes.Status410Gone, title: "Ссылка больше не действует", detail: state));
    }
}
