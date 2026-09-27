namespace Darumen.Shared.Api;

/// <summary>Предметы решений в журнале (journal.decisions.subject); веб-клиент использует те же строки (lib/decision.ts).</summary>
public static class DecisionSubjects
{
    /// <summary>Направление пациента: recommended/chosen вида {"moCode": "…"}.</summary>
    public const string Referral = "referral";

    /// <summary>Сигнал аномалии: recommended/chosen вида {"status": "…"}, subject_id — id сигнала.</summary>
    public const string Anomaly = "anomaly";

    /// <summary>Маршрут пациента: перенаправление врачом, recommended/chosen вида {"moCode": "…"}, subject_id — реф
    /// синтетического пациента (SYN-регион-организация-профиль-NN); гражданин видит эти решения на своём маршруте.</summary>
    public const string Route = "route";

    /// <summary>Сценарий симулятора регулятора: recommended/chosen — параметры сценария.</summary>
    public const string Scenario = "scenario";

    /// <summary>Изменение матрицы ролей: subject_id — ключ роли, recommended — прежние охваты, chosen — новые.</summary>
    public const string RolePermissions = "role_permissions";

    /// <summary>Роль, организация или блокировка пользователя: subject_id — id пользователя Keycloak.</summary>
    public const string UserAccess = "user_access";

    /// <summary>Верификация врача: chosen {"status": "verified | rejected | pending"}.</summary>
    public const string DoctorVerification = "doctor_verification";

    /// <summary>Решение по заявке организации: chosen {"status": "approved | rejected"}.</summary>
    public const string OrgApplication = "org_application";
}
