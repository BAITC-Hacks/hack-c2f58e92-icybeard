using System.Text.Json;
using Darumen.Shared.Api;
using Darumen.Shared.Auth;

namespace Darumen.Modules.Journal;

/// <summary>Кто какие решения пишет и читает (docs/rbac.md): запись — referral.confirm (сценарий симулятора — gov.simulator);
/// чтение — decisions.all (все, при own — решения своей организации) или decisions.own (только свои).</summary>
public static class DecisionAccess
{
    /// <summary>Предмет решения регулятора в симуляторе (веб: SimulatorView).</summary>
    public const string ScenarioSubject = DecisionSubjects.Scenario;

    public static readonly string[] WritePermissions = [Permissions.ReferralConfirm, Permissions.GovSimulator];
    public static readonly string[] ReadPermissions = [Permissions.DecisionsOwn, Permissions.DecisionsAll];

    private static readonly char[] SubjectSeparators = ['.', '-', ':'];

    /// <summary>Проверка записи: сценарий — gov.simulator; остальное — referral.confirm, при own — решение про свою организацию
    /// (организация в subjectId, recommended или chosen).</summary>
    public static async Task<IResult?> CheckWriteAsync(HttpContext http, DecisionRequestDto body)
    {
        if (body.Subject == ScenarioSubject)
        {
            return (await OrgAccess.ResolveAsync(http, null, Permissions.GovSimulator)).Problem;
        }

        var scope = await OrgAccess.ResolveAsync(http, null, Permissions.ReferralConfirm);
        if (scope.Problem is not null || !scope.IsOwn)
        {
            return scope.Problem;
        }

        return Concerns(body, scope.MoCode!) ? null : AccessProblems.Forbidden(AccessProblems.OtherOrganization);
    }

    /// <summary>Фильтр чтения: Actor — только решения этого актора; MoCode — решения своей организации; оба null — все.</summary>
    public static async Task<(string? Actor, string? MoCode, IResult? Problem)> ReadFilterAsync(HttpContext http, string? requestedActor)
    {
        var user = CurrentUser.From(http);
        var actor = requestedActor == "me" ? user.Actor : requestedActor;
        var permissions = http.RequestServices.GetRequiredService<IPermissionService>();
        var all = await permissions.ScopeForAsync(http.User, Permissions.DecisionsAll, http.RequestAborted);
        if (all == PermissionScope.All)
        {
            return (actor, null, null);
        }

        if (all == PermissionScope.Own)
        {
            // свои решения видны всегда; чужие — только решения своей организации
            return actor == user.Actor ? (actor, null, null) : (actor, user.MoCode, null);
        }

        if (await permissions.ScopeForAsync(http.User, Permissions.DecisionsOwn, http.RequestAborted) != PermissionScope.None)
        {
            return (user.Actor, null, null);
        }

        var ownWithoutOrganization = await permissions.RawScopeAsync(http.User, Permissions.DecisionsOwn, http.RequestAborted) == PermissionScope.Own
                                     || await permissions.RawScopeAsync(http.User, Permissions.DecisionsAll, http.RequestAborted) == PermissionScope.Own;
        return (null, null, AccessProblems.Forbidden(ownWithoutOrganization ? AccessProblems.NoOrganization : AccessProblems.PermissionRequired, ReadPermissions));
    }

    private static bool Concerns(DecisionRequestDto body, string moCode) =>
        body.SubjectId?.Split(SubjectSeparators).Contains(moCode, StringComparer.OrdinalIgnoreCase) == true
        || MoCodeOf(body.Recommended) == moCode || MoCodeOf(body.Chosen) == moCode;

    private static string? MoCodeOf(JsonElement? element) =>
        element is { ValueKind: JsonValueKind.Object } value && value.TryGetProperty("moCode", out var mo) && mo.ValueKind == JsonValueKind.String
            ? mo.GetString()
            : null;
}
