using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Authentication;

namespace Darumen.Shared.Auth;

/// <summary>Keycloak кладёт роли реалма в realm_access.roles; разворачиваем их в стандартные role-claims.</summary>
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
        if (document.RootElement.TryGetProperty("roles", out var roles))
        {
            foreach (var role in roles.EnumerateArray())
            {
                var name = role.GetString();
                if (name is not null && Roles.All.Contains(name))
                {
                    identity.AddClaim(new Claim(ClaimTypes.Role, name));
                }
            }
        }

        return Task.FromResult(principal);
    }
}
