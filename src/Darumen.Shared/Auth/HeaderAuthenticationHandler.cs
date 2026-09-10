using System.Security.Claims;
using System.Text.Encodings.Web;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace Darumen.Shared.Auth;

/// <summary>Схема для тестов и разработки без Keycloak: X-Actor, X-Role (через запятую), X-Region.</summary>
public sealed class HeaderAuthenticationHandler(IOptionsMonitor<AuthenticationSchemeOptions> options, ILoggerFactory logger, UrlEncoder encoder)
    : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    public const string Scheme = "Headers";
    public const string ActorHeader = "X-Actor";
    public const string RoleHeader = "X-Role";
    public const string RegionHeader = "X-Region";

    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        var actor = Request.Headers[ActorHeader].ToString();
        if (string.IsNullOrWhiteSpace(actor))
        {
            return Task.FromResult(AuthenticateResult.NoResult());
        }

        var claims = new List<Claim> { new(DarumenClaims.Name, actor) };
        claims.AddRange(Request.Headers[RoleHeader].ToString().Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(role => new Claim(ClaimTypes.Role, role)));
        var region = Request.Headers[RegionHeader].ToString();
        if (!string.IsNullOrWhiteSpace(region))
        {
            claims.Add(new Claim(DarumenClaims.Region, region));
        }

        var identity = new ClaimsIdentity(claims, Scheme, DarumenClaims.Name, ClaimTypes.Role);
        return Task.FromResult(AuthenticateResult.Success(new AuthenticationTicket(new ClaimsPrincipal(identity), Scheme)));
    }
}
