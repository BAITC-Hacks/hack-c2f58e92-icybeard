namespace Darumen.Shared.Auth;

/// <summary>Коды разрешений (docs/rbac.md) и имена политик `perm:код` для RequireAuthorization.</summary>
public static class Permissions
{
    public const string RouteOwn = "route.own";
    public const string WaitPublic = "wait.public";
    public const string MedicinesCheck = "medicines.check";
    public const string WorklistView = "worklist.view";
    public const string ReferralAssist = "referral.assist";
    public const string ReferralConfirm = "referral.confirm";
    public const string ScribeUse = "scribe.use";
    public const string DecisionsOwn = "decisions.own";
    public const string DecisionsAll = "decisions.all";
    public const string GovMap = "gov.map";
    public const string GovSimulator = "gov.simulator";
    public const string InsightAsk = "insight.ask";
    public const string OrgCabinet = "org.cabinet";
    public const string AdminUsers = "admin.users";

    /// <summary>Системные: не показываются в матрице и не редактируются.</summary>
    public const string DataSteward = "data.steward";
    public const string AdminOrgs = "admin.orgs";
    public const string AdminRoles = "admin.roles";

    public const string PolicyPrefix = "perm:";
    private const char Separator = '|';

    /// <summary>Имя политики: `perm:gov.map`; несколько кодов — «любое из» (`perm:gov.map|org.cabinet`).</summary>
    public static string Policy(params string[] codes) => PolicyPrefix + string.Join(Separator, codes);

    public static bool TryParsePolicy(string policyName, out string[] codes)
    {
        codes = [];
        if (!policyName.StartsWith(PolicyPrefix, StringComparison.Ordinal))
        {
            return false;
        }

        codes = policyName[PolicyPrefix.Length..].Split(Separator, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        return codes.Length > 0;
    }
}

/// <summary>Охват разрешения: own — только своя организация (клейм mo_code), all — без ограничений.</summary>
public enum PermissionScope
{
    None = 0,
    Own = 1,
    All = 2,
}

public static class PermissionScopes
{
    public const string All = "all";
    public const string Own = "own";

    public static PermissionScope Parse(string? scope) => scope switch
    {
        All => PermissionScope.All,
        Own => PermissionScope.Own,
        _ => PermissionScope.None,
    };

    public static string? Format(PermissionScope scope) => scope switch
    {
        PermissionScope.All => All,
        PermissionScope.Own => Own,
        _ => null,
    };

    public static bool IsValid(string? scope) => scope is All or Own;
}
