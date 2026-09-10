using System.Security.Claims;
using Darumen.Shared.Auth;
using Microsoft.AspNetCore.Http;

namespace Darumen.Shared.Api;

/// <summary>Кто делает запрос: из claims (JWT Keycloak или схема заголовков).</summary>
public sealed record CurrentUser(string Actor, string Role, string? RegionKato)
{
    public const string Anonymous = "anonymous";
    public const string NoRole = "none";

    public static CurrentUser From(HttpContext context) => From(context.User);

    public static CurrentUser From(ClaimsPrincipal principal)
    {
        if (principal.Identity?.IsAuthenticated != true)
        {
            return new CurrentUser(Anonymous, NoRole, null);
        }

        var actor = principal.FindFirst(DarumenClaims.Name)?.Value ?? principal.Identity.Name ?? Anonymous;
        var roles = principal.FindAll(ClaimTypes.Role).Select(c => c.Value).ToList();
        var role = Roles.All.FirstOrDefault(roles.Contains) ?? roles.FirstOrDefault() ?? NoRole;
        return new CurrentUser(actor, role, principal.FindFirst(DarumenClaims.Region)?.Value);
    }
}
