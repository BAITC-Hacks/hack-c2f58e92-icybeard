using System.Security.Claims;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Tokens;

namespace Darumen.Shared.Auth;

public static class AuthSetup
{
    /// <summary>Аутентификация Keycloak (JWT) или заголовками, и политики по ролям; admin входит во все политики.</summary>
    public static IServiceCollection AddDarumenAuth(this IServiceCollection services, IConfiguration configuration)
    {
        var options = configuration.GetSection(AuthOptions.Section).Get<AuthOptions>() ?? new AuthOptions();
        var headers = string.Equals(options.Mode, AuthOptions.HeadersMode, StringComparison.OrdinalIgnoreCase);
        var authentication = services.AddAuthentication(headers ? HeaderAuthenticationHandler.Scheme : JwtBearerDefaults.AuthenticationScheme);
        if (headers)
        {
            authentication.AddScheme<AuthenticationSchemeOptions, HeaderAuthenticationHandler>(HeaderAuthenticationHandler.Scheme, null);
        }
        else
        {
            authentication.AddJwtBearer(jwt =>
            {
                jwt.Authority = options.Authority;
                jwt.Audience = options.Audience;
                jwt.RequireHttpsMetadata = options.RequireHttps;
                jwt.MapInboundClaims = false;
                jwt.TokenValidationParameters = new TokenValidationParameters
                {
                    NameClaimType = DarumenClaims.Name,
                    RoleClaimType = ClaimTypes.Role,
                    ValidateAudience = true,
                    ValidAudience = options.Audience,
                };
            });
            services.AddSingleton<IClaimsTransformation, KeycloakRolesTransformation>();
        }

        services.AddAuthorization(policies =>
        {
            policies.AddPolicy(Policies.Authenticated, p => p.RequireAuthenticatedUser());
            policies.AddPolicy(Policies.Citizen, p => p.RequireRole(Roles.Citizen, Roles.Admin));
            policies.AddPolicy(Policies.Doctor, p => p.RequireRole(Roles.Doctor, Roles.Admin));
            policies.AddPolicy(Policies.Regulator, p => p.RequireRole(Roles.Regulator, Roles.Admin));
            policies.AddPolicy(Policies.Steward, p => p.RequireRole(Roles.Steward, Roles.Admin));
            policies.AddPolicy(Policies.ChiefOrRegulator, p => p.RequireRole(Roles.Chief, Roles.Regulator, Roles.Admin));
            policies.AddPolicy(Policies.DoctorOrRegulator, p => p.RequireRole(Roles.Doctor, Roles.Regulator, Roles.Admin));
        });
        return services;
    }
}
