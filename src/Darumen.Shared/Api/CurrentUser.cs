using System.Security.Claims;
using Darumen.Shared.Auth;
using Microsoft.AspNetCore.Http;

namespace Darumen.Shared.Api;

/// <summary>Кто делает запрос: из claims (JWT Keycloak или схема заголовков). Iin — ИИН гражданина из клейма `iin`
/// (в демо-realm синтетический); нигде не логируется и не хранится, используется только как устойчивый сид маршрута.
/// MoCode — код организации из клейма `mo_code` (scope own разрешений). Role — первая встроенная роль из
/// <see cref="Auth.Roles.All"/> (для журнала), Roles — все роли приложения (для разрешений).</summary>
public sealed record CurrentUser(string Actor, string Role, string? RegionKato, string? Iin = null, string? MoCode = null)
{
    public const string Anonymous = "anonymous";
    public const string NoRole = "none";

    public IReadOnlyList<string> Roles { get; init; } = [];

    /// <summary>Идентификатор пользователя Keycloak (sub); в режиме заголовков — логин.</summary>
    public string UserId { get; init; } = Anonymous;

    /// <summary>Сессия Keycloak (sid) — «текущая» в списке сессий.</summary>
    public string? SessionId { get; init; }

    public bool IsAuthenticated => Actor != Anonymous;

    public static CurrentUser From(HttpContext context) => From(context.User);

    public static CurrentUser From(ClaimsPrincipal principal)
    {
        if (principal.Identity?.IsAuthenticated != true)
        {
            return new CurrentUser(Anonymous, NoRole, null);
        }

        var actor = principal.FindFirst(DarumenClaims.Name)?.Value ?? principal.Identity.Name ?? Anonymous;
        var roles = principal.FindAll(ClaimTypes.Role).Select(c => Auth.Roles.Normalize(c.Value)).Distinct().ToList();
        var role = Auth.Roles.All.FirstOrDefault(roles.Contains) ?? roles.FirstOrDefault() ?? NoRole;
        var moCode = principal.FindFirst(DarumenClaims.MoCode)?.Value;
        return new CurrentUser(actor, role, principal.FindFirst(DarumenClaims.Region)?.Value, principal.FindFirst(DarumenClaims.Iin)?.Value,
            string.IsNullOrWhiteSpace(moCode) ? null : moCode)
        {
            Roles = roles,
            UserId = principal.FindFirst(DarumenClaims.Subject)?.Value ?? actor,
            SessionId = principal.FindFirst(DarumenClaims.SessionId)?.Value,
        };
    }
}
