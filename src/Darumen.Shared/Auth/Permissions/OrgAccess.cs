using Darumen.Shared.Api;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;

namespace Darumen.Shared.Auth;

/// <summary>Охват запроса: Scope All — MoCode = запрошенная организация (или null — все); Own — организация актора;
/// Problem — 403 (нет разрешения, нет организации у актора, чужая организация).</summary>
public sealed record OrgScope(PermissionScope Scope, string? MoCode, IResult? Problem)
{
    public bool IsOwn => Scope == PermissionScope.Own;
}

/// <summary>Проверка scope own на эндпоинтах: рабочий список, журнал решений, кабинет организации, пользователи.</summary>
public static class OrgAccess
{
    /// <summary>codes — «любое из»: берётся наибольший охват.</summary>
    public static async Task<OrgScope> ResolveAsync(HttpContext http, string? requestedMoCode, params string[] codes)
    {
        var permissions = http.RequestServices.GetRequiredService<IPermissionService>();
        var best = PermissionScope.None;
        foreach (var code in codes)
        {
            var scope = await permissions.RawScopeAsync(http.User, code, http.RequestAborted);
            best = scope > best ? scope : best;
        }

        var requested = string.IsNullOrWhiteSpace(requestedMoCode) ? null : requestedMoCode.Trim();
        return best switch
        {
            PermissionScope.All => new OrgScope(PermissionScope.All, requested, null),
            PermissionScope.Own => Own(CurrentUser.From(http).MoCode, requested),
            _ => new OrgScope(PermissionScope.None, null, AccessProblems.Forbidden(AccessProblems.PermissionRequired, codes)),
        };
    }

    /// <summary>Доступна ли актору организация moCode (для проверок по конкретной записи, например по рефу пациента).</summary>
    public static async Task<IResult?> CheckAsync(HttpContext http, string? moCode, params string[] codes)
    {
        var scope = await ResolveAsync(http, moCode, codes);
        return scope.Problem;
    }

    private static OrgScope Own(string? actorMoCode, string? requested)
    {
        if (string.IsNullOrWhiteSpace(actorMoCode))
        {
            return new OrgScope(PermissionScope.Own, null, AccessProblems.Forbidden(AccessProblems.NoOrganization));
        }

        return requested is not null && !string.Equals(requested, actorMoCode, StringComparison.OrdinalIgnoreCase)
            ? new OrgScope(PermissionScope.Own, actorMoCode, AccessProblems.Forbidden(AccessProblems.OtherOrganization))
            : new OrgScope(PermissionScope.Own, actorMoCode, null);
    }
}
