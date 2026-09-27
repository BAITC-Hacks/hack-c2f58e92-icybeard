using Darumen.Modules.Access.Data;
using Darumen.Modules.Access.Identity;
using Darumen.Modules.Access.Services;
using Darumen.Shared.Api;
using Darumen.Shared.Auth;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace Darumen.Modules.Access.Endpoints;

/// <summary>Анонимно, с лимитом частоты на адрес: заявка организации и код почты, приглашение, восстановление пароля.</summary>
public static class PublicAccessEndpoints
{
    private const int PasswordResetLifespanSeconds = 3600;

    public static void Map(IEndpointRouteBuilder api)
    {
        var applications = api.MapGroup("/public/org-applications").WithTags("Public").AllowAnonymous();

        applications.MapPost("", async (OrgApplicationRequestDto body, OrgApplicationService service, CancellationToken ct) =>
            {
                var errors = OrgApplicationService.Validate(body);
                if (errors.Any)
                {
                    return errors.Problem();
                }

                var (application, statusToken, sent) = await service.SubmitAsync(body, ct);
                return Results.Created($"/api/v1/public/org-applications/{application.Id}",
                    new OrgApplicationCreatedDto(application.Id, application.Number, statusToken, sent, (int)OrgApplicationService.ResendAfter.TotalSeconds));
            })
            .RequireRateLimiting(RateLimits.PublicForms)
            .WithName("SubmitOrgApplication").WithSummary("Заявка на подключение организации; на почту уходит 6-значный код (15 минут)")
            .Produces<OrgApplicationCreatedDto>(StatusCodes.Status201Created).ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .Produces(StatusCodes.Status429TooManyRequests);

        applications.MapPost("/{id:guid}/verify-email", async (Guid id, VerifyEmailDto body, OrgApplicationService service, CancellationToken ct) =>
            {
                var outcome = await service.VerifyAsync(id, body, ct);
                return outcome.Problem ?? Results.Ok(Status(outcome.Application!));
            })
            .RequireRateLimiting(RateLimits.PublicForms)
            .WithName("VerifyOrgApplicationEmail").WithSummary("Подтвердить почту кодом: заявка переходит на рассмотрение (pending_review)")
            .Produces<OrgApplicationStatusDto>().ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity).ProducesProblem(StatusCodes.Status404NotFound);

        applications.MapPost("/{id:guid}/resend-code", async (Guid id, StatusTokenDto body, OrgApplicationService service, CancellationToken ct) =>
            {
                var outcome = await service.ResendAsync(id, body.StatusToken, ct);
                return outcome.Problem ?? Results.Accepted(value: new CodeResentDto(outcome.EmailSent, (int)OrgApplicationService.ResendAfter.TotalSeconds));
            })
            .RequireRateLimiting(RateLimits.PublicForms)
            .WithName("ResendOrgApplicationCode").WithSummary("Новый код не чаще раза в 60 с (иначе 429 с retryAfterSeconds)")
            .Produces<CodeResentDto>(StatusCodes.Status202Accepted).Produces(StatusCodes.Status429TooManyRequests);

        applications.MapGet("/{id:guid}", async (Guid id, string? statusToken, OrgApplicationService service, CancellationToken ct) =>
            {
                var (application, problem) = await service.AuthorizeAsync(id, statusToken, ct);
                return problem ?? Results.Ok(Status(application!));
            })
            .WithName("OrgApplicationStatus").WithSummary("Статус заявки по statusToken: pending_email | pending_review | approved | rejected")
            .Produces<OrgApplicationStatusDto>().ProducesProblem(StatusCodes.Status404NotFound);

        PublicInviteEndpoints.Map(api);

        api.MapPost("/public/password-reset", PasswordResetAsync)
            .AllowAnonymous().RequireRateLimiting(RateLimits.PublicForms).WithTags("Public")
            .WithName("PasswordReset").WithSummary("Восстановление пароля: всегда 202; если почта есть и учётная запись включена — Keycloak шлёт письмо UPDATE_PASSWORD")
            .Produces(StatusCodes.Status202Accepted).ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity);
    }

    private static async Task<IResult> PasswordResetAsync(PasswordResetDto body, IIdentityAdmin identity, IOptions<KeycloakAdminOptions> keycloak,
        IOptions<WebOptions> web, ILoggerFactory loggers, CancellationToken ct)
    {
        var errors = AccountValidation.Email(new ValidationErrors(), "email", body.Email);
        if (errors.Any)
        {
            return errors.Problem();
        }

        try
        {
            var user = await identity.UserByEmailAsync(body.Email!.Trim(), ct);
            if (user is { Enabled: true })
            {
                await identity.ExecuteActionsEmailAsync(user.Id, ["UPDATE_PASSWORD"], PasswordResetLifespanSeconds, keycloak.Value.WebClientId,
                    $"{web.Value.Origin}/", ct);
            }
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            // ответ не раскрывает, есть ли такая почта и дошло ли письмо; адрес в журнал не пишется
            loggers.CreateLogger(typeof(PublicAccessEndpoints)).LogWarning(exception, "Password reset email was not requested");
        }

        return Results.Accepted(value: new { accepted = true });
    }

    private static OrgApplicationStatusDto Status(OrgApplication application) =>
        new(application.Number, application.OrgName, OrgApplicationService.MaskEmail(application.Email), application.Status, application.SubmittedAt);
}
