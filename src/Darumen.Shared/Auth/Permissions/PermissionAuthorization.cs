using Darumen.Shared.Api;
using Microsoft.AspNetCore.Authorization;
using Microsoft.Extensions.Options;

namespace Darumen.Shared.Auth;

/// <summary>Требование «любое из разрешений» (обычно одно).</summary>
public sealed class PermissionRequirement(IReadOnlyList<string> codes) : IAuthorizationRequirement
{
    public IReadOnlyList<string> Codes { get; } = codes;
}

/// <summary>Политики `perm:код` строятся на лету; остальные имена — у стандартного провайдера.</summary>
public sealed class PermissionPolicyProvider(IOptions<AuthorizationOptions> options) : IAuthorizationPolicyProvider
{
    private readonly DefaultAuthorizationPolicyProvider _fallback = new(options);

    public Task<AuthorizationPolicy?> GetPolicyAsync(string policyName)
    {
        if (!Permissions.TryParsePolicy(policyName, out var codes))
        {
            return _fallback.GetPolicyAsync(policyName);
        }

        var policy = new AuthorizationPolicyBuilder().RequireAuthenticatedUser().AddRequirements(new PermissionRequirement(codes)).Build();
        return Task.FromResult<AuthorizationPolicy?>(policy);
    }

    public Task<AuthorizationPolicy> GetDefaultPolicyAsync() => _fallback.GetDefaultPolicyAsync();

    public Task<AuthorizationPolicy?> GetFallbackPolicyAsync() => _fallback.GetFallbackPolicyAsync();
}

/// <summary>Роли пользователя → объединение разрешений из матрицы; own без mo_code — отказ с причиной no_organization.</summary>
public sealed class PermissionAuthorizationHandler(IPermissionService permissions) : AuthorizationHandler<PermissionRequirement>
{
    protected override async Task HandleRequirementAsync(AuthorizationHandlerContext context, PermissionRequirement requirement)
    {
        var ownWithoutOrganization = false;
        foreach (var code in requirement.Codes)
        {
            var raw = await permissions.RawScopeAsync(context.User, code);
            if (raw == PermissionScope.All || (raw == PermissionScope.Own && !string.IsNullOrWhiteSpace(CurrentUser.From(context.User).MoCode)))
            {
                context.Succeed(requirement);
                return;
            }

            ownWithoutOrganization |= raw == PermissionScope.Own;
        }

        context.Fail(new AuthorizationFailureReason(this, ownWithoutOrganization ? AccessProblems.NoOrganization : AccessProblems.PermissionRequired));
    }
}
