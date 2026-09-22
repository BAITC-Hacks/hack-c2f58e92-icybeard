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
}
