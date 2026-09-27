using Darumen.Shared.Api;

namespace Darumen.Modules.Access.Data;

/// <summary>Приглашения (auth.invitations): токен хранится только хешем.</summary>
public interface IInvitationStore
{
    Task AddAsync(Invitation invitation, CancellationToken cancellationToken);

    Task<Invitation?> ByTokenHashAsync(string tokenHash, CancellationToken cancellationToken);

    /// <summary>Незакрытые (не принятые и не отклонённые) приглашения пользователей, последнее на пользователя.</summary>
    Task<IReadOnlyList<Invitation>> OpenForUsersAsync(IReadOnlyCollection<string> userIds, CancellationToken cancellationToken);

    Task CloseAsync(Guid id, bool accepted, DateTimeOffset at, CancellationToken cancellationToken);

    Task<bool> AnyByInviterAsync(string actor, CancellationToken cancellationToken);
}

/// <summary>Заявки организаций (auth.org_applications); номер выдаёт последовательность auth.org_application_seq.</summary>
public interface IOrgApplicationStore
{
    Task<OrgApplication> AddAsync(OrgApplication application, CancellationToken cancellationToken);

    Task<OrgApplication?> GetAsync(Guid id, CancellationToken cancellationToken);

    Task SaveAsync(OrgApplication application, CancellationToken cancellationToken);

    Task<Paged<OrgApplication>> ListAsync(string? status, string? moCode, int page, int size, CancellationToken cancellationToken);
}

/// <summary>Аккаунт пользователя: настройки и уведомления, согласия, запросы (доступ, удаление), верификация врачей.</summary>
public interface IAccountStore
{
    Task<UserSettings?> SettingsAsync(string userId, CancellationToken cancellationToken);

    Task SaveSettingsAsync(UserSettings settings, CancellationToken cancellationToken);

    Task<IReadOnlyList<ConsentRecord>> ConsentsAsync(string userId, CancellationToken cancellationToken);

    Task SetConsentAsync(string userId, string code, bool granted, CancellationToken cancellationToken);

    Task AddRequestAsync(AccountRequest request, CancellationToken cancellationToken);

    Task<IReadOnlyDictionary<string, DoctorVerification>> VerificationsAsync(IReadOnlyCollection<string> userIds, CancellationToken cancellationToken);

    Task SetVerificationAsync(DoctorVerification verification, CancellationToken cancellationToken);
}

/// <summary>Чтение журналов для администрирования и аккаунта: последняя активность (journal.audit), направления и совпадение
/// с рекомендацией (journal.decisions), кто смотрел данные пользователя.</summary>
public interface IActivityReader
{
    Task<IReadOnlyDictionary<string, DateTimeOffset>> LastActivityAsync(IReadOnlyCollection<string> actors, CancellationToken cancellationToken);

    Task<IReadOnlyDictionary<string, ReferralStats>> ReferralStatsAsync(IReadOnlyCollection<string> actors, DateTimeOffset since, CancellationToken cancellationToken);

    /// <summary>Запросы других пользователей, в пути которых встречается одна из подстрок (идентификатор, логин, реф маршрута).</summary>
    Task<IReadOnlyList<AuditRow>> MentionsAsync(IReadOnlyCollection<string> needles, string exceptActor, int limit, CancellationToken cancellationToken);

    Task<IReadOnlyList<AuditRow>> ByActorAsync(string actor, int limit, CancellationToken cancellationToken);
}

/// <summary>Подключение организаций: есть ли данные очередей (gold.queue_state) и свежесть загрузок по наборам (intake.batches).</summary>
public interface IOrgDataStatus
{
    Task<IReadOnlySet<string>> ConnectedAsync(IReadOnlyCollection<string> moCodes, CancellationToken cancellationToken);

    Task<IReadOnlyList<DatasetFreshness>> FreshnessAsync(string? regionKato, CancellationToken cancellationToken);
}
