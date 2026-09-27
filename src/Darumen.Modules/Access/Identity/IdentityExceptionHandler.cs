using Darumen.Shared.Api;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.Extensions.Logging;

namespace Darumen.Modules.Access.Identity;

/// <summary>Ошибки Keycloak — понятный problem+json, а не 500: недоступен → 503, нет записи → 404, занято → 409, политика паролей → 422
/// с текстом на языке запроса (и обоими языками в passwordPolicy).</summary>
public sealed class IdentityExceptionHandler(IProblemDetailsService problems, ILogger<IdentityExceptionHandler> logger) : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(HttpContext httpContext, Exception exception, CancellationToken cancellationToken)
    {
        var problem = exception switch
        {
            IdentityUnavailableException unavailable => Unavailable(unavailable),
            IdentityConflictException conflict => new Microsoft.AspNetCore.Mvc.ProblemDetails
            {
                Status = StatusCodes.Status409Conflict, Title = "Учётная запись уже существует", Detail = conflict.Message,
            },
            IdentityPolicyException policy => Policy(policy, Locale.From(httpContext.Request)),
            IdentityNotFoundException notFound => new Microsoft.AspNetCore.Mvc.ProblemDetails
            {
                Status = StatusCodes.Status404NotFound, Title = "Учётная запись не найдена", Detail = notFound.Message,
            },
            _ => null,
        };
        if (problem is null)
        {
            return false;
        }

        httpContext.Response.StatusCode = problem.Status!.Value;
        return await problems.TryWriteAsync(new ProblemDetailsContext { HttpContext = httpContext, ProblemDetails = problem });
    }

    private Microsoft.AspNetCore.Mvc.ProblemDetails Unavailable(IdentityUnavailableException exception)
    {
        logger.LogWarning(exception, "Keycloak admin API is unavailable");
        return new Microsoft.AspNetCore.Mvc.ProblemDetails
        {
            Status = StatusCodes.Status503ServiceUnavailable,
            Title = "Сервис учётных записей недоступен",
            Detail = $"{exception.Message}. Повторите позже.",
        };
    }

    private static Microsoft.AspNetCore.Mvc.ProblemDetails Policy(IdentityPolicyException exception, string lang)
    {
        var (ru, kk) = PasswordPolicyMessages.For(exception.Code, exception.Parameters);
        var text = lang == Locale.Kk ? kk : ru;
        var problem = new HttpValidationProblemDetails(new Dictionary<string, string[]> { ["password"] = [text] })
        {
            Status = StatusCodes.Status422UnprocessableEntity,
            Title = "Пароль не соответствует политике",
            Detail = text,
        };
        problem.Extensions["passwordPolicy"] = new { code = exception.Code, ru, kk };
        return problem;
    }
}
