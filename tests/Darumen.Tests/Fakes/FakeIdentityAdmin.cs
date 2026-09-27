using Darumen.Modules.Access.Identity;

namespace Darumen.Tests.Fakes;

/// <summary>Keycloak Admin API в памяти: демо-пользователи (id = логин, как в режиме заголовков), роли, сессии, события входа,
/// политика паролей реалма (12 символов, заглавная, строчная, цифра, не логин). Available = false — Keycloak недоступен.</summary>
public sealed class FakeIdentityAdmin : IIdentityAdmin
{
    private readonly Lock _gate = new();
    private readonly Dictionary<string, IdentityUser> _users = new();
    private readonly Dictionary<string, HashSet<string>> _roles = new();

    public FakeIdentityAdmin()
    {
        Seed("citizen1", "citizen", null, "75");
        Seed("doctor1", "doctor", "028B", "75", specialty: "офтальмолог");
        Seed("doctor-28", "doctor", "028B", "75", specialty: "хирург");
        Seed("doctor2", "doctor", "22GN", "75", specialty: "терапевт");
        Seed("chief1", "org_admin", "028B", "75");
        Seed("regulator1", "regulator", null, null);
        Seed("auditor1", "auditor", null, null);
        Seed("admin1", "admin", null, null);
        Seed("blocked1", "doctor", "028B", "75", enabled: false);
        Sessions["doctor1"] = [new("s-current", "10.0.0.1", DateTimeOffset.UtcNow.AddHours(-1), DateTimeOffset.UtcNow, ["darumen-web"]),
            new("s-mobile", "10.0.0.2", DateTimeOffset.UtcNow.AddDays(-1), DateTimeOffset.UtcNow.AddHours(-3), ["darumen-mobile"])];
        Events["doctor1"] = [new(DateTimeOffset.UtcNow.AddHours(-1), "LOGIN", "10.0.0.1", null, "openid-connect", null),
            new(DateTimeOffset.UtcNow.AddHours(-2), "LOGIN_ERROR", "10.0.0.9", "invalid_user_credentials", "openid-connect", null)];
        Credentials["doctor1"] = [new("password", DateTimeOffset.UtcNow.AddDays(-30)), new("otp", DateTimeOffset.UtcNow.AddDays(-10))];
    }

    public bool Available { get; set; } = true;

    public Dictionary<string, List<IdentitySession>> Sessions { get; } = new();

    public Dictionary<string, List<IdentityEvent>> Events { get; } = new();

    public Dictionary<string, List<IdentityCredential>> Credentials { get; } = new();

    public Dictionary<string, string> Passwords { get; } = new();

    public List<string> CreatedRoles { get; } = [];

    public List<(string UserId, IReadOnlyList<string> Actions, string ClientId, string RedirectUri)> ActionEmails { get; } = [];

    public IdentityUser? Find(string id)
    {
        lock (_gate)
        {
            return _users.GetValueOrDefault(id);
        }
    }

    public IReadOnlyList<string> RolesOf(string id)
    {
        lock (_gate)
        {
            return _roles.GetValueOrDefault(id)?.ToList() ?? [];
        }
    }

    public Task<IReadOnlyList<IdentityUser>> UsersAsync(int max, CancellationToken cancellationToken) =>
        Guarded<IReadOnlyList<IdentityUser>>(() => _users.Values.Take(max).ToList());

    public Task<IdentityUser?> UserAsync(string id, CancellationToken cancellationToken) => Guarded(() => _users.GetValueOrDefault(id));

    public Task<IdentityUser?> UserByEmailAsync(string email, CancellationToken cancellationToken) =>
        Guarded(() => _users.Values.FirstOrDefault(u => string.Equals(u.Email, email, StringComparison.OrdinalIgnoreCase)));

    public Task<IReadOnlyList<string>> RoleMembersAsync(string role, int max, CancellationToken cancellationToken) =>
        Guarded<IReadOnlyList<string>>(() => _roles.Where(r => r.Value.Contains(role)).Select(r => r.Key).Take(max).ToList());

    public Task<IReadOnlyList<string>> UserRolesAsync(string id, CancellationToken cancellationToken) =>
        Guarded<IReadOnlyList<string>>(() => _roles.GetValueOrDefault(id)?.ToList() ?? []);

    public Task<string> CreateUserAsync(NewIdentityUser user, CancellationToken cancellationToken) => Guarded(() =>
    {
        if (_users.Values.Any(u => u.Username == user.Username || u.Email == user.Email))
        {
            throw new IdentityConflictException("exists");
        }

        var id = Guid.NewGuid().ToString();
        _users[id] = new IdentityUser(id, user.Username, user.Email, false, user.FirstName, user.LastName, false, DateTimeOffset.UtcNow,
            user.Attributes.ToDictionary(a => a.Key, a => (IReadOnlyList<string>)[a.Value]));
        _roles[id] = [];
        return id;
    });

    public Task UpdateUserAsync(string id, IdentityUserUpdate update, CancellationToken cancellationToken) => Guarded(() =>
    {
        var user = _users.GetValueOrDefault(id) ?? throw new IdentityNotFoundException(id);
        var attributes = user.Attributes.ToDictionary(a => a.Key, a => a.Value);
        foreach (var (key, value) in update.Attributes ?? new Dictionary<string, string?>())
        {
            if (string.IsNullOrWhiteSpace(value))
            {
                attributes.Remove(key);
            }
            else
            {
                attributes[key] = [value];
            }
        }

        _users[id] = user with { Enabled = update.Enabled ?? user.Enabled, EmailVerified = update.EmailVerified ?? user.EmailVerified, Attributes = attributes };
        return true;
    });

    public Task DeleteUserAsync(string id, CancellationToken cancellationToken) => Guarded(() => _users.Remove(id) | _roles.Remove(id));

    public Task SetRolesAsync(string id, IReadOnlyCollection<string> add, IReadOnlyCollection<string> remove, CancellationToken cancellationToken) => Guarded(() =>
    {
        var roles = _roles.GetValueOrDefault(id) ?? [];
        roles.ExceptWith(remove.Where(r => !add.Contains(r)));
        roles.UnionWith(add);
        _roles[id] = roles;
        return true;
    });

    public Task SetPasswordAsync(string id, string password, CancellationToken cancellationToken) => Guarded(() =>
    {
        var user = _users.GetValueOrDefault(id) ?? throw new IdentityNotFoundException(id);
        if (password.Length < 12)
        {
            throw new IdentityPolicyException("invalidPasswordMinLengthMessage", ["12"], "Invalid password: minimum length 12.");
        }

        if (!password.Any(char.IsUpper) || !password.Any(char.IsLower) || !password.Any(char.IsDigit))
        {
            throw new IdentityPolicyException(!password.Any(char.IsDigit) ? "invalidPasswordMinDigitsMessage" : "invalidPasswordMinUpperCaseCharsMessage", ["1"], null);
        }

        if (string.Equals(password, user.Username, StringComparison.OrdinalIgnoreCase))
        {
            throw new IdentityPolicyException("invalidPasswordNotUsernameMessage", [], null);
        }

        Passwords[id] = password;
        return true;
    });

    public Task<IReadOnlyList<IdentityCredential>> CredentialsAsync(string id, CancellationToken cancellationToken) =>
        Guarded<IReadOnlyList<IdentityCredential>>(() => Credentials.GetValueOrDefault(id)?.ToList() ?? []);

    public Task<IReadOnlyList<IdentitySession>> SessionsAsync(string id, CancellationToken cancellationToken) =>
        Guarded<IReadOnlyList<IdentitySession>>(() => Sessions.GetValueOrDefault(id)?.ToList() ?? []);

    public Task DeleteSessionAsync(string sessionId, CancellationToken cancellationToken) => Guarded(() =>
    {
        foreach (var list in Sessions.Values)
        {
            list.RemoveAll(s => s.Id == sessionId);
        }

        return true;
    });

    public Task LogoutAsync(string id, CancellationToken cancellationToken) => Guarded(() => Sessions.Remove(id));

    public Task<IReadOnlyList<IdentityEvent>> LoginEventsAsync(string id, int max, CancellationToken cancellationToken) =>
        Guarded<IReadOnlyList<IdentityEvent>>(() => Events.GetValueOrDefault(id)?.Take(max).ToList() ?? []);

    public Task CreateRoleAsync(string name, string? description, CancellationToken cancellationToken) => Guarded(() =>
    {
        CreatedRoles.Add(name);
        return true;
    });

    public Task ExecuteActionsEmailAsync(string id, IReadOnlyList<string> actions, int lifespanSeconds, string clientId, string redirectUri,
        CancellationToken cancellationToken) => Guarded(() =>
    {
        ActionEmails.Add((id, actions, clientId, redirectUri));
        return true;
    });

    private void Seed(string username, string role, string? moCode, string? region, string? specialty = null, bool enabled = true)
    {
        var attributes = new Dictionary<string, IReadOnlyList<string>>();
        if (moCode is not null)
        {
            attributes["mo_code"] = [moCode];
        }

        if (region is not null)
        {
            attributes["region_kato"] = [region];
        }

        if (specialty is not null)
        {
            attributes["specialty"] = [specialty];
        }

        _users[username] = new IdentityUser(username, username, $"{username}@darumen.local", true, username, "Demo", enabled, DateTimeOffset.UtcNow.AddDays(-60), attributes);
        _roles[username] = [role];
    }

    private Task<T> Guarded<T>(Func<T> action)
    {
        if (!Available)
        {
            throw new IdentityUnavailableException("Keycloak недоступен (тест)");
        }

        lock (_gate)
        {
            return Task.FromResult(action());
        }
    }
}
