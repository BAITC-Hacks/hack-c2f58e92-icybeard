namespace Darumen.Shared.Auth;

public sealed class AuthOptions
{
    public const string Section = "Auth";
    public const string KeycloakMode = "keycloak";
    public const string HeadersMode = "headers";

    /// <summary>keycloak: JWT от Keycloak (OIDC); headers: роли из заголовков X-Actor/X-Role/X-Region для тестов и разработки.</summary>
    public string Mode { get; set; } = KeycloakMode;

    public string Authority { get; set; } = "http://localhost:8080/realms/darumen";

    public string Audience { get; set; } = "darumen-api";

    public bool RequireHttps { get; set; }
}

public static class Roles
{
    public const string Citizen = "citizen";
    public const string Doctor = "doctor";
    /// <summary>Администратор организации (обязателен клейм mo_code); заменил роль chief (главврач).</summary>
    public const string OrgAdmin = "org_admin";
    public const string Regulator = "regulator";
    public const string Steward = "steward";
    /// <summary>Аудитор: журналы решений и аудита.</summary>
    public const string Auditor = "auditor";
    public const string Admin = "admin";

    /// <summary>Прежняя роль главврача: в токене трактуется как <see cref="OrgAdmin"/> (legacy-алиас).</summary>
    public const string LegacyChief = "chief";

    public static readonly string[] All = [Citizen, Doctor, OrgAdmin, Regulator, Steward, Auditor, Admin];

    /// <summary>Встроенные роли, чьи запросы попадают в журнал аудита: все, кроме гражданина. Созданные в матрице роли
    /// тоже аудируются (<see cref="IsAudited"/>).</summary>
    public static readonly string[] Audited = [Doctor, OrgAdmin, Regulator, Steward, Auditor, Admin];

    /// <summary>Роли самого Keycloak, которые не относятся к приложению.</summary>
    private static readonly string[] KeycloakBuiltins = ["offline_access", "uma_authorization"];

    /// <summary>chief → org_admin; остальные роли как есть.</summary>
    public static string Normalize(string role) => role == LegacyChief ? OrgAdmin : role;

    /// <summary>Роль приложения, а не служебная роль Keycloak (default-roles-*, offline_access, uma_authorization).</summary>
    public static bool IsApplicationRole(string role) =>
        !string.IsNullOrWhiteSpace(role) && !KeycloakBuiltins.Contains(role) && !role.StartsWith("default-roles-", StringComparison.Ordinal);

    public static bool IsAudited(string role) => role != Citizen && role != "none" && !string.IsNullOrWhiteSpace(role);
}

public static class Policies
{
    /// <summary>Любой вошедший пользователь (например, /me). Доступ к данным — только политиками разрешений
    /// <see cref="Permissions.Policy"/>.</summary>
    public const string Authenticated = "authenticated";
}

public static class DarumenClaims
{
    public const string Name = "preferred_username";
    public const string Region = "region_kato";
    /// <summary>ИИН гражданина (маппер `iin` на клиентах darumen-web и darumen-mobile); в демо-realm значения синтетические.</summary>
    public const string Iin = "iin";

    /// <summary>Код организации (атрибут пользователя `mo_code` в realm): scope `own` разрешений ограничен этой организацией.</summary>
    public const string MoCode = "mo_code";
    public const string RealmAccess = "realm_access";
    public const string Subject = "sub";
    /// <summary>Идентификатор сессии Keycloak: текущая сессия в «Безопасности» аккаунта.</summary>
    public const string SessionId = "sid";
    public const string FullName = "name";
    public const string GivenName = "given_name";
    public const string FamilyName = "family_name";
    public const string Email = "email";
    public const string EmailVerified = "email_verified";
}
