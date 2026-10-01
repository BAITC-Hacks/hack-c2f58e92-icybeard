using System.Security.Claims;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.IdentityModel.Tokens;

namespace Darumen.Shared.Auth;

public static class AuthSetup
{
    /// <summary>Аутентификация Keycloak (JWT) или заголовками и политики разрешений `perm:код` (docs/rbac.md): роли → матрица
    /// auth.role_permissions (кэш 30 с); admin проходит все политики.</summary>
    public static IServiceCollection AddDarumenAuth(this IServiceCollection services, IConfiguration configuration)
    {
        var options = configuration.GetSection(AuthOptions.Section).Get<AuthOptions>() ?? new AuthOptions();
        var headers = string.Equals(options.Mode, AuthOptions.HeadersMode, StringComparison.OrdinalIgnoreCase);
        if (headers && string.Equals(configuration["ASPNETCORE_ENVIRONMENT"] ?? configuration["DOTNET_ENVIRONMENT"], "Production", StringComparison.OrdinalIgnoreCase))
        {
            // в проде доверять заголовкам X-Actor/X-Role нельзя: любой клиент назвался бы администратором
            throw new InvalidOperationException("Auth:Mode=headers недопустим в Production — используйте keycloak");
        }

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

        services.AddAuthorization(policies => policies.AddPolicy(Policies.Authenticated, p => p.RequireAuthenticatedUser()));
        services.TryAddSingleton(TimeProvider.System);
        services.TryAddSingleton<IPermissionStore, PostgresPermissionStore>();
        services.AddSingleton<IPermissionService, PermissionService>();
        services.AddSingleton<IAuthorizationPolicyProvider, PermissionPolicyProvider>();
        services.AddSingleton<IAuthorizationHandler, PermissionAuthorizationHandler>();
        services.AddSingleton<IAuthorizationMiddlewareResultHandler, ProblemAuthorizationResultHandler>();
        return services;
    }
}
