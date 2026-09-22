using Darumen.Modules.Queue;
using Darumen.Modules.RefData;
using Darumen.Shared.Api;

namespace Darumen.Modules.Journal;

/// <summary>Маршрут пациента через плановую госпитализацию — один контракт для гражданина (/route/me) и врача
/// (/route/{patientRef}). Только логистика: стадии Стандарта, даты, прогноз модели ожидания, чек-лист обследований
/// со сроками давности, альтернативы, решения врача и история прошлых направлений. Пациент синтетический
/// (Synthetic = true): выдуман, но сроки и исходы взяты из реального состояния очередей региона на AsOf.
/// Doctor заполняется только для врача — гражданин не видит риск отказа и приоритет (docs/system-structure.md, правило 1).
/// Даты — ISO yyyy-MM-dd; коды стадий и статусов машинные, клиенты локализуют их сами (RU/KK).</summary>
public sealed record RouteDto(
    string PatientRef, bool Synthetic, string Audience, string AsOf, string RegionKato, RouteOrganizationDto Organization,
    string Stage, string StageTitle, IReadOnlyList<RouteStageDto> Timeline, RouteDatesDto Dates, int DaysWaiting,
    RouteForecastDto Forecast, IReadOnlyList<RouteBenchmarkDto> Benchmarks, IReadOnlyList<RouteChecklistItemDto> Checklist,
    IReadOnlyList<AlternativeDto> Alternatives, ModelInfoDto? AlternativesModel, IReadOnlyList<RouteDecisionDto> Decisions,
    IReadOnlyList<RouteHistoryDto> History, RouteDoctorPanelDto? Doctor, string Basis, RouteStandardRefDto Standard);

public sealed record RouteOrganizationDto(string MoCode, string MoName, string ProfileCode, string ProfileName);

/// <summary>Стадия на таймлайне: Date — когда пройдена или назначена (done/current), Norm — нормативный срок Стандарта.</summary>
public sealed record RouteStageDto(string Code, int Order, string Title, string? Date, string Status, string? Norm);

public sealed record RouteDatesDto(string IssuedAt, string RegisteredAt, string? PlannedAt, string ExpectedAt);

/// <summary>FromModel = false — сервис моделей недоступен: p50/p90 из агрегатов витрины, PWithin30Days тогда null.</summary>
public sealed record RouteForecastDto(double P50Days, double P90Days, double? PWithin30Days, bool FromModel, ModelInfoDto? Model);

/// <summary>Пункт чек-листа приложения 5: DoneAt и ValidUntil — даты, Status — valid | expiring | expired, только по датам.</summary>
public sealed record RouteChecklistItemDto(string Code, string Title, int ValidityDays, string ValidityLabel, string DoneAt, string ValidUntil, string Status);

/// <summary>Решение врача по маршруту из journal.decisions: Kind — redirect (другая организация) | keep.</summary>
public sealed record RouteDecisionDto(
    Guid DecisionId, string Role, DateTimeOffset RecordedAt, string? FromMoCode, string ToMoCode, string ToMoName, string? Reason, string Kind);

public sealed record RouteHistoryDto(
    string MoCode, string MoName, string ProfileCode, string ProfileName, string RegisteredAt, string Outcome, string OutcomeAt, int WaitDays);

/// <summary>Служебная панель врача: приоритет и флаги рабочего списка, следующий шаг (русская подпись и код, как в
/// <see cref="WorklistItemDto"/>), риск отказа и факторы модели.</summary>
public sealed record RouteDoctorPanelDto(
    int Priority, IReadOnlyList<string> RiskFlags, string NextAction, string NextActionCode, string Explanation, double PRefusal, bool RefusalOrgInTraining, ExplanationDto? Shap);

public sealed record RouteStandardRefDto(string Source, string SourceUrl, string SourceDate, bool Available);

public sealed record RouteRedirectRequestDto(string? ToMoCode, string? Reason);

public static class RouteAudience
{
    public const string Citizen = "citizen";
    public const string Doctor = "doctor";
}

/// <summary>Коды стадий — те же, что в refdata/route_standard.yaml.</summary>
public static class RouteStages
{
    public const string ReferralIssued = "referral_issued";
    public const string Examination = "examination";
    public const string Waitlisted = "waitlisted";
    public const string DateAssigned = "date_assigned";
    public const string Hospitalized = "hospitalized";
    public const string Refused = "refused";
}

public static class RouteTimelineStatus
{
    public const string Done = "done";
    public const string Current = "current";
    public const string Upcoming = "upcoming";
}

public static class RouteChecklistStatus
{
    public const string Valid = "valid";
    public const string Expiring = "expiring";
    public const string Expired = "expired";
}

public static class RouteOutcomes
{
    public const string Hospitalized = "hospitalized";
    public const string Refused = "refused";
}

public static class RouteDecisionKinds
{
    public const string Redirect = "redirect";
    public const string Keep = "keep";
}
