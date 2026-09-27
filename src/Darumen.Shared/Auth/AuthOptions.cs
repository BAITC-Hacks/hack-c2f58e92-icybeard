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
    public const string Chief = "chief";
    public const string Regulator = "regulator";
    public const string Steward = "steward";
    public const string Admin = "admin";

    public static readonly string[] All = [Citizen, Doctor, Chief, Regulator, Steward, Admin];

    /// <summary>Роли, чьи запросы попадают в журнал аудита.</summary>
    public static readonly string[] Audited = [Doctor, Chief, Regulator, Steward, Admin];
}

public static class Policies
{
    public const string Authenticated = "authenticated";
    /// <summary>Гражданин видит только свой маршрут (/route/me); публичные экраны ожидания и лекарств политики не требуют.</summary>
    public const string Citizen = "citizen";
    public const string Doctor = "doctor";
    public const string Regulator = "regulator";
    public const string Steward = "steward";
    public const string ChiefOrRegulator = "chief-or-regulator";
    public const string DoctorOrRegulator = "doctor-or-regulator";
}

public static class DarumenClaims
{
    public const string Name = "preferred_username";
    public const string Region = "region_kato";
    /// <summary>ИИН гражданина (маппер `iin` на клиентах darumen-web и darumen-mobile); в демо-realm значения синтетические.</summary>
    public const string Iin = "iin";

    /// <summary>Код организации главврача (атрибут пользователя `mo_code` в realm): портал «Больница» открывает свою организацию.</summary>
    public const string MoCode = "mo_code";
    public const string RealmAccess = "realm_access";
}
