namespace Darumen.Modules.Journal;

/// <summary>Виды событий колокольчика, различающие отметки «прочитано» по одному и тому же decisionId направления.</summary>
public static class NotificationKinds
{
    public const string ReferralConfirmed = "referral-confirmed";
    public const string ReferralDischarged = "referral-discharged";
}

/// <summary>Отметки «прочитано» для завершённых уведомлений колокольчика (задача 13 плана прозрачности,
/// упрощена до внутрисистемных уведомлений вместо push): один пользователь может отметить одно событие
/// (kind + decisionId) прочитанным один раз; отсутствие отметки означает «не прочитано».</summary>
public interface INotificationReadRepository
{
    Task MarkReadAsync(string actor, string kind, Guid decisionId, CancellationToken cancellationToken);

    /// <summary>Из переданных decisionId одного вида события — какие уже отмечены этим пользователем как прочитанные.</summary>
    Task<HashSet<Guid>> ReadDecisionIdsAsync(string actor, string kind, IReadOnlyCollection<Guid> decisionIds, CancellationToken cancellationToken);
}
