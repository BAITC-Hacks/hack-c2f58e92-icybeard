using System.Security.Claims;
using System.Text.Encodings.Web;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace Darumen.Shared.Auth;

/// <summary>Схема для тестов и разработки без Keycloak: X-Actor, X-Role (через запятую; chief → org_admin), X-Region,
/// X-MoCode (клейм mo_code для scope own) и X-Session-Id (клейм sid).</summary>
public sealed class HeaderAuthenticationHandler(IOptionsMonitor<AuthenticationSchemeOptions> options, ILoggerFactory logger, UrlEncoder encoder)
    : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    public new const string Scheme = "Headers";
    public const string ActorHeader = "X-Actor";
    public const string RoleHeader = "X-Role";
    public const string RegionHeader = "X-Region";
    public const string MoCodeHeader = "X-MoCode";
    public const string SessionHeader = "X-Session-Id";

    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        var actor = Request.Headers[ActorHeader].ToString();
        if (string.IsNullOrWhiteSpace(actor))
        {
            return Task.FromResult(AuthenticateResult.NoResult());
        }

        var claims = new List<Claim> { new(DarumenClaims.Name, actor) };
        claims.AddRange(Request.Headers[RoleHeader].ToString().Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(Roles.Normalize).Distinct().Select(role => new Claim(ClaimTypes.Role, role)));
        AddOptional(claims, RegionHeader, DarumenClaims.Region);
        AddOptional(claims, MoCodeHeader, DarumenClaims.MoCode);
        AddOptional(claims, SessionHeader, DarumenClaims.SessionId);

        var identity = new ClaimsIdentity(claims, Scheme, DarumenClaims.Name, ClaimTypes.Role);
        return Task.FromResult(AuthenticateResult.Success(new AuthenticationTicket(new ClaimsPrincipal(identity), Scheme)));
    }

    private void AddOptional(List<Claim> claims, string header, string claimType)
    {
        var value = Request.Headers[header].ToString();
        if (!string.IsNullOrWhiteSpace(value))
        {
            claims.Add(new Claim(claimType, value.Trim()));
        }
    }
}
