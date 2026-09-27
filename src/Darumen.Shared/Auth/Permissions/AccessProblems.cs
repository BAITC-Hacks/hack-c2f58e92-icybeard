using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Authorization.Policy;
using Microsoft.AspNetCore.Http;

namespace Darumen.Shared.Auth;

/// <summary>403 problem+json с машинно-читаемой причиной в detail: клиент показывает «Нет доступа» и предлагает запросить доступ.</summary>
public static class AccessProblems
{
    public const string PermissionRequired = "permission_required";
    public const string NoOrganization = "no_organization";
    public const string OtherOrganization = "other_organization";
    private const string PermissionsExtension = "permissions";

    public static IResult Forbidden(string detail, params string[] permissions) => Results.Problem(
        statusCode: StatusCodes.Status403Forbidden,
        title: Title(detail),
        detail: detail,
        extensions: permissions.Length == 0 ? null : new Dictionary<string, object?> { [PermissionsExtension] = permissions });

    public static string Title(string detail) => detail switch
    {
        NoOrganization => "Нет организации: разрешение действует только в своей организации",
        OtherOrganization => "Данные другой организации",
        _ => "Нет доступа к разделу",
    };

    internal static Dictionary<string, object?> Extensions(IEnumerable<string> permissions) => new() { [PermissionsExtension] = permissions.ToArray() };
}

/// <summary>Отказ политики разрешений — 403 problem+json с причиной (permission_required / no_organization) и кодами
/// разрешений; 401 и остальное — стандартной обработкой.</summary>
public sealed class ProblemAuthorizationResultHandler(IProblemDetailsService problems) : IAuthorizationMiddlewareResultHandler
{
    private readonly AuthorizationMiddlewareResultHandler _default = new();

    public async Task HandleAsync(RequestDelegate next, HttpContext context, AuthorizationPolicy policy, PolicyAuthorizationResult authorizeResult)
    {
        var codes = policy.Requirements.OfType<PermissionRequirement>().SelectMany(r => r.Codes).ToList();
        if (!authorizeResult.Forbidden || codes.Count == 0)
        {
            await _default.HandleAsync(next, context, policy, authorizeResult);
            return;
        }

        var detail = authorizeResult.AuthorizationFailure?.FailureReasons.Select(r => r.Message).FirstOrDefault() ?? AccessProblems.PermissionRequired;
        context.Response.StatusCode = StatusCodes.Status403Forbidden;
        var problem = new Microsoft.AspNetCore.Mvc.ProblemDetails { Status = StatusCodes.Status403Forbidden, Title = AccessProblems.Title(detail), Detail = detail };
        foreach (var (key, value) in AccessProblems.Extensions(codes))
        {
            problem.Extensions[key] = value;
        }

        await problems.WriteAsync(new ProblemDetailsContext { HttpContext = context, ProblemDetails = problem });
    }
}
