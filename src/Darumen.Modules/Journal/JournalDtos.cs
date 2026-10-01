using System.Text.Json;

namespace Darumen.Modules.Journal;

public sealed record DecisionRequestDto(string? Subject, string? SubjectId, JsonElement? Recommended, JsonElement? Chosen, string? Reason);

public sealed record DecisionDto(
    Guid DecisionId, string Actor, string Role, string Subject, string SubjectId, JsonElement? Recommended, JsonElement? Chosen,
    string? Reason, DateTimeOffset RecordedAt);

public sealed record DecisionCreatedDto(Guid DecisionId, DateTimeOffset RecordedAt);

public sealed record AuditEntryDto(
    long Id, DateTimeOffset At, string Actor, string Role, string Method, string Path, string? Query, int Status, int DurationMs, string TraceId,
    string? MoCode = null, string? Detail = null);

public sealed record NewDecision(
    string Actor, string Role, string Subject, string SubjectId, string? RecommendedJson, string? ChosenJson, string? Reason, string? IdempotencyKey,
    string? ActorMoCode = null);

/// <summary>Входящее направление (redirect) в организацию, ещё не подтверждённое ею (или подтверждённое, если
/// includeConfirmed=true в запросе): FromMoCode/FromMoName — организация-отправитель (из рефа маршрута), ProfileCode —
/// профиль очереди; PatientConsent — pending | accepted | declined (<see cref="RouteConsent"/>); подтвердить приём
/// можно только когда PatientConsent == accepted (<see cref="ReferralConfirmation"/>).
/// Status — состояние маршрута (<see cref="RouteStatuses"/>), PlannedAt — назначенная дата, Allowed — что принимающая
/// организация может сделать сейчас (подтвердить, отказать, перенести, госпитализация, неявка, выписка, снять с очереди).</summary>
public sealed record IncomingReferralDto(
    Guid DecisionId, string PatientRef, string FromMoCode, string FromMoName, string ProfileCode, string? Reason,
    DateTimeOffset RecordedAt, bool Severe, string PatientConsent, bool Confirmed, DateTimeOffset? ConfirmedAt,
    bool Discharged = false, DateTimeOffset? DischargedAt = null, string? Status = null, string? PlannedAt = null, bool Admitted = false,
    bool Overdue = false, IReadOnlyList<string>? Allowed = null, string? ClosedReason = null);

/// <summary>Колокольчик (задача 13 плана прозрачности, упрощена до внутрисистемных уведомлений вместо push):
/// направления, отправленные моей организацией, которые уже подтвердила принимающая сторона, с отметкой,
/// прочитал ли уже их текущий пользователь.</summary>
public sealed record SentReferralConfirmationDto(
    Guid DecisionId, string PatientRef, string ToMoCode, string ToMoName, DateTimeOffset ConfirmedAt, bool Read);

/// <summary>Сводка колокольчика для главной страницы: сколько входящих направлений ждут подтверждения (требует
/// действия) и какие из отправленных моей организацией уже подтверждены, но ещё не прочитаны мной.</summary>
public sealed record NotificationBellDto(
    int PendingIncomingCount, List<SentReferralConfirmationDto> UnreadConfirmations, List<DischargeReadyDto> UnreadDischarges,
    List<PatientEventDto>? PatientSignals = null);

/// <summary>Запрос на выписку/эпикриз (задача 11): decisionId в пути — id решения redirect, которое выписывается.</summary>
public sealed record DischargeRequestDto(string? PatientRef, string? Summary);

public sealed record DischargeDto(Guid DecisionId, string PatientRef, DateTimeOffset DischargedAt, string Summary);

/// <summary>Колокольчик: направления, которые моя организация отправляла и которые принимающая сторона выписала
/// (закрыла лечение), с эпикризом — с отметкой, прочитал ли уже эту выписку текущий пользователь.</summary>
public sealed record DischargeReadyDto(
    Guid DecisionId, string PatientRef, string FromMoCode, string FromMoName, string Summary, DateTimeOffset DischargedAt, bool Read);


/// <summary>PatientRef обязателен — тот же реф, что показан в <see cref="IncomingReferralDto"/> и на /route/{patientRef};
/// PlannedAt — назначенная дата госпитализации (ГГГГ-ММ-ДД, от сегодня до 30 дней вперёд), обязательна.</summary>
public sealed record ReferralConfirmRequestDto(string? PatientRef, string? Comment, string? PlannedAt = null);

/// <summary>Отказ в приёме (причина обязательна), отметка госпитализации или неявки (причина — по желанию).</summary>
public sealed record ReferralReasonRequestDto(string? PatientRef, string? Reason);

public sealed record ReferralRescheduleRequestDto(string? PatientRef, string? PlannedAt, string? Reason);
