using Microsoft.AspNetCore.Http;

namespace Darumen.Shared.Api;

/// <summary>Кто делает запрос: из JWT после подключения Keycloak, до этого из заголовков X-Actor и X-Role.</summary>
public sealed record CurrentUser(string Actor, string Role, string? RegionKato)
{
    public const string Anonymous = "anonymous";

    public static CurrentUser From(HttpContext context)
    {
        var principal = context.User;
        if (principal.Identity?.IsAuthenticated == true)
        {
            var actor = principal.FindFirst("preferred_username")?.Value ?? principal.Identity.Name ?? Anonymous;
            var role = principal.FindFirst("role")?.Value ?? principal.FindFirst(System.Security.Claims.ClaimTypes.Role)?.Value ?? "unknown";
            return new CurrentUser(actor, role, principal.FindFirst("region_kato")?.Value);
        }

        var headers = context.Request.Headers;
        return new CurrentUser(
            headers.TryGetValue("X-Actor", out var a) && !string.IsNullOrWhiteSpace(a) ? a.ToString() : Anonymous,
            headers.TryGetValue("X-Role", out var r) && !string.IsNullOrWhiteSpace(r) ? r.ToString() : "unknown",
            headers.TryGetValue("X-Region", out var g) && !string.IsNullOrWhiteSpace(g) ? g.ToString() : null);
    }
}
