using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Authentication;

namespace Darumen.Shared.Auth;

/// <summary>Keycloak кладёт роли реалма в realm_access.roles; разворачиваем их в стандартные role-claims. Legacy-роль
/// chief трактуется как org_admin; роли, созданные в матрице (POST /admin/roles), проходят как есть; служебные роли
/// Keycloak (default-roles-*, offline_access, uma_authorization) отбрасываются.</summary>
public sealed class KeycloakRolesTransformation : IClaimsTransformation
{
    public Task<ClaimsPrincipal> TransformAsync(ClaimsPrincipal principal)
    {
        var identity = principal.Identity as ClaimsIdentity;
        var realmAccess = identity?.FindFirst(DarumenClaims.RealmAccess)?.Value;
        if (identity is null || realmAccess is null || identity.HasClaim(c => c.Type == ClaimTypes.Role))
        {
            return Task.FromResult(principal);
        }

        using var document = JsonDocument.Parse(realmAccess);
        if (document.RootElement.TryGetProperty("roles", out var roles) && roles.ValueKind == JsonValueKind.Array)
        {
            var names = roles.EnumerateArray().Select(r => r.GetString()).OfType<string>()
                .Where(Roles.IsApplicationRole).Select(Roles.Normalize).Distinct();
            foreach (var name in names)
            {
                identity.AddClaim(new Claim(ClaimTypes.Role, name));
            }
        }

        return Task.FromResult(principal);
    }
}
