namespace Darumen.Modules.Access.Identity;

/// <summary>Атрибуты пользователя в realm, которые читает и пишет приложение (мапперы токена — mo_code, region_kato, iin).</summary>
public static class IdentityAttributes
{
    public const string MoCode = "mo_code";
    public const string RegionKato = "region_kato";
    public const string Specialty = "specialty";
    public const string Position = "position";
    /// <summary>Способ входа: egov (после интеграции eGov) или password (по умолчанию).</summary>
    public const string Via = "via";
}

public sealed record IdentityUser(
    string Id, string Username, string? Email, bool EmailVerified, string? FirstName, string? LastName, bool Enabled,
    DateTimeOffset? CreatedAt, IReadOnlyDictionary<string, IReadOnlyList<string>> Attributes)
{
    public string? Attribute(string name) =>
        Attributes.TryGetValue(name, out var values) && values.Count > 0 && !string.IsNullOrWhiteSpace(values[0]) ? values[0] : null;

    public string DisplayName
    {
        get
        {
            var name = string.Join(' ', new[] { FirstName, LastName }.Where(p => !string.IsNullOrWhiteSpace(p)));
            return name.Length > 0 ? name : Username;
        }
    }
}

public sealed record NewIdentityUser(string Username, string Email, string? FirstName, string? LastName, IReadOnlyDictionary<string, string> Attributes);

/// <summary>Частичное обновление: null — поле не меняется; значение атрибута null — атрибут удаляется.</summary>
public sealed record IdentityUserUpdate(bool? Enabled = null, bool? EmailVerified = null, IReadOnlyDictionary<string, string?>? Attributes = null);

public sealed record IdentityCredential(string Type, DateTimeOffset? CreatedAt);

public sealed record IdentitySession(string Id, string? IpAddress, DateTimeOffset? Start, DateTimeOffset? LastAccess, IReadOnlyList<string> Clients);

public sealed record IdentityEvent(DateTimeOffset At, string Type, string? IpAddress, string? Error, string? AuthMethod, string? IdentityProvider);

/// <summary>Администрирование учётных записей Keycloak (Admin REST API). Недоступность — <see cref="IdentityUnavailableException"/>
/// (503 problem), нарушение политики паролей — <see cref="IdentityPolicyException"/> (422), занятый логин или почта —
/// <see cref="IdentityConflictException"/> (409).</summary>
public interface IIdentityAdmin
{
    Task<IReadOnlyList<IdentityUser>> UsersAsync(int max, CancellationToken cancellationToken);

    Task<IdentityUser?> UserAsync(string id, CancellationToken cancellationToken);

    Task<IdentityUser?> UserByEmailAsync(string email, CancellationToken cancellationToken);

    /// <summary>Идентификаторы пользователей с ролью реалма; роли нет в реалме — пусто.</summary>
    Task<IReadOnlyList<string>> RoleMembersAsync(string role, int max, CancellationToken cancellationToken);

    Task<IReadOnlyList<string>> UserRolesAsync(string id, CancellationToken cancellationToken);

    Task<string> CreateUserAsync(NewIdentityUser user, CancellationToken cancellationToken);

    Task UpdateUserAsync(string id, IdentityUserUpdate update, CancellationToken cancellationToken);

    Task DeleteUserAsync(string id, CancellationToken cancellationToken);

    Task SetRolesAsync(string id, IReadOnlyCollection<string> add, IReadOnlyCollection<string> remove, CancellationToken cancellationToken);

    /// <summary>Постоянный пароль по политике реалма.</summary>
    Task SetPasswordAsync(string id, string password, CancellationToken cancellationToken);

    Task<IReadOnlyList<IdentityCredential>> CredentialsAsync(string id, CancellationToken cancellationToken);

    Task<IReadOnlyList<IdentitySession>> SessionsAsync(string id, CancellationToken cancellationToken);

    Task DeleteSessionAsync(string sessionId, CancellationToken cancellationToken);

    /// <summary>Завершить все сессии пользователя.</summary>
    Task LogoutAsync(string id, CancellationToken cancellationToken);

    /// <summary>Последние события входа (LOGIN, LOGIN_ERROR), новые первыми.</summary>
    Task<IReadOnlyList<IdentityEvent>> LoginEventsAsync(string id, int max, CancellationToken cancellationToken);

    /// <summary>Роль реалма; уже существующая — не ошибка.</summary>
    Task CreateRoleAsync(string name, string? description, CancellationToken cancellationToken);

    /// <summary>Письмо Keycloak с действиями (UPDATE_PASSWORD) и возвратом на redirectUri клиента clientId.</summary>
    Task ExecuteActionsEmailAsync(string id, IReadOnlyList<string> actions, int lifespanSeconds, string clientId, string redirectUri, CancellationToken cancellationToken);
}

public sealed class IdentityUnavailableException(string message, Exception? inner = null) : Exception(message, inner);

public sealed class IdentityConflictException(string message) : Exception(message);

/// <summary>Учётной записи или сессии нет в Keycloak (удалена в консоли, пока шло приглашение) — 404 problem.</summary>
public sealed class IdentityNotFoundException(string message) : Exception(message);

/// <summary>Нарушение политики паролей реалма: Code — ключ сообщения Keycloak (invalidPasswordMinLengthMessage), Params — его параметры.</summary>
public sealed class IdentityPolicyException(string code, IReadOnlyList<string> parameters, string? description) : Exception(description ?? code)
{
    public string Code { get; } = code;

    public IReadOnlyList<string> Parameters { get; } = parameters;
}
