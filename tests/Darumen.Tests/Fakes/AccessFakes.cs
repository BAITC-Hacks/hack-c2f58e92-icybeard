using Darumen.Modules.Access.Data;
using Darumen.Modules.Access.Mail;
using Darumen.Modules.Journal;
using Darumen.Shared.Api;

namespace Darumen.Tests.Fakes;

/// <summary>Почта в памяти: Enabled = false — как без SMTP (emailSent: false).</summary>
public sealed class FakeEmailSender : IEmailSender
{
    public bool Enabled { get; set; } = true;

    public List<EmailMessage> Sent { get; } = [];

    public Task<bool> SendAsync(EmailMessage message, CancellationToken cancellationToken)
    {
        if (!Enabled)
        {
            return Task.FromResult(false);
        }

        lock (Sent)
        {
            Sent.Add(message);
        }

        return Task.FromResult(true);
    }

    public EmailMessage LastTo(string email)
    {
        lock (Sent)
        {
            return Sent.Last(m => m.To == email);
        }
    }
}

public sealed class InMemoryInvitationStore : IInvitationStore
{
    private readonly List<Invitation> _items = [];

    public Task AddAsync(Invitation invitation, CancellationToken cancellationToken)
    {
        lock (_items)
        {
            _items.Add(invitation);
        }

        return Task.CompletedTask;
    }

    public Task<Invitation?> ByTokenHashAsync(string tokenHash, CancellationToken cancellationToken)
    {
        lock (_items)
        {
            return Task.FromResult(_items.FirstOrDefault(i => i.TokenHash == tokenHash));
        }
    }

    public Task<IReadOnlyList<Invitation>> OpenForUsersAsync(IReadOnlyCollection<string> userIds, CancellationToken cancellationToken)
    {
        lock (_items)
        {
            return Task.FromResult<IReadOnlyList<Invitation>>(_items.Where(i => userIds.Contains(i.UserId) && i.IsOpen)
                .GroupBy(i => i.UserId).Select(g => g.OrderByDescending(i => i.InvitedAt).First()).ToList());
        }
    }

    public Task CloseAsync(Guid id, bool accepted, DateTimeOffset at, CancellationToken cancellationToken)
    {
        lock (_items)
        {
            var index = _items.FindIndex(i => i.Id == id && i.IsOpen);
            if (index >= 0)
            {
                _items[index] = accepted ? _items[index] with { AcceptedAt = at } : _items[index] with { DeclinedAt = at };
            }
        }

        return Task.CompletedTask;
    }

    public Task<bool> AnyByInviterAsync(string actor, CancellationToken cancellationToken)
    {
        lock (_items)
        {
            return Task.FromResult(_items.Any(i => i.InvitedBy == actor));
        }
    }
}

public sealed class InMemoryOrgApplicationStore : IOrgApplicationStore
{
    private readonly Dictionary<Guid, OrgApplication> _items = new();

    public Task<OrgApplication> AddAsync(OrgApplication application, CancellationToken cancellationToken)
    {
        lock (_items)
        {
            var numbered = application with { Number = $"ORG-{application.SubmittedAt:yyyy}-{_items.Count + 1:D5}" };
            _items[numbered.Id] = numbered;
            return Task.FromResult(numbered);
        }
    }

    public Task<OrgApplication?> GetAsync(Guid id, CancellationToken cancellationToken)
    {
        lock (_items)
        {
            return Task.FromResult(_items.GetValueOrDefault(id));
        }
    }

    public Task SaveAsync(OrgApplication application, CancellationToken cancellationToken)
    {
        lock (_items)
        {
            _items[application.Id] = application;
        }

        return Task.CompletedTask;
    }

    public Task<Paged<OrgApplication>> ListAsync(string? status, string? moCode, int page, int size, CancellationToken cancellationToken)
    {
        lock (_items)
        {
            var items = _items.Values.Where(a => (status is null || a.Status == status) && (moCode is null || a.MoCode == moCode))
                .OrderByDescending(a => a.SubmittedAt).ToList();
            return Task.FromResult(new Paged<OrgApplication>(items.Skip((page - 1) * size).Take(size).ToList(), page, size, items.Count));
        }
    }
}

public sealed class InMemoryAccountStore : IAccountStore
{
    private readonly Lock _gate = new();
    private readonly Dictionary<string, UserSettings> _settings = new();
    private readonly Dictionary<(string UserId, string Code), ConsentRecord> _consents = new();
    private readonly Dictionary<string, DoctorVerification> _verifications = new();

    public List<AccountRequest> Requests { get; } = [];

    public Task<UserSettings?> SettingsAsync(string userId, CancellationToken cancellationToken)
    {
        lock (_gate)
        {
            return Task.FromResult(_settings.GetValueOrDefault(userId));
        }
    }

    public Task SaveSettingsAsync(UserSettings settings, CancellationToken cancellationToken)
    {
        lock (_gate)
        {
            _settings[settings.UserId] = settings;
        }

        return Task.CompletedTask;
    }

    public Task<IReadOnlyList<ConsentRecord>> ConsentsAsync(string userId, CancellationToken cancellationToken)
    {
        lock (_gate)
        {
            return Task.FromResult<IReadOnlyList<ConsentRecord>>(_consents.Where(c => c.Key.UserId == userId).Select(c => c.Value).ToList());
        }
    }

    public Task SetConsentAsync(string userId, string code, bool granted, CancellationToken cancellationToken)
    {
        lock (_gate)
        {
            _consents[(userId, code)] = new ConsentRecord(code, granted, DateTimeOffset.UtcNow);
        }

        return Task.CompletedTask;
    }

    public Task AddRequestAsync(AccountRequest request, CancellationToken cancellationToken)
    {
        lock (_gate)
        {
            Requests.Add(request);
        }

        return Task.CompletedTask;
    }

    public Task<IReadOnlyDictionary<string, DoctorVerification>> VerificationsAsync(IReadOnlyCollection<string> userIds, CancellationToken cancellationToken)
    {
        lock (_gate)
        {
            return Task.FromResult<IReadOnlyDictionary<string, DoctorVerification>>(
                _verifications.Where(v => userIds.Contains(v.Key)).ToDictionary(v => v.Key, v => v.Value));
        }
    }

    public Task SetVerificationAsync(DoctorVerification verification, CancellationToken cancellationToken)
    {
        lock (_gate)
        {
            _verifications[verification.UserId] = verification;
        }

        return Task.CompletedTask;
    }
}

/// <summary>Журналы и витрины для администрирования: активность и направления doctor1, очереди у 028B, одна партия загрузки.</summary>
public sealed class InMemoryActivity : IActivityReader, IOrgDataStatus
{
    public List<AuditRow> Audit { get; } =
    [
        new(DateTimeOffset.UtcNow.AddMinutes(-5), "doctor1", "doctor", "GET", "/api/v1/journal/worklist", 200),
        new(DateTimeOffset.UtcNow.AddMinutes(-3), "chief1", "org_admin", "GET", "/api/v1/admin/users/doctor1", 200),
    ];

    public Task<IReadOnlyDictionary<string, DateTimeOffset>> LastActivityAsync(IReadOnlyCollection<string> actors, CancellationToken cancellationToken) =>
        Task.FromResult<IReadOnlyDictionary<string, DateTimeOffset>>(Audit.Where(a => actors.Contains(a.Actor))
            .GroupBy(a => a.Actor).ToDictionary(g => g.Key, g => g.Max(a => a.At)));

    public Task<IReadOnlyDictionary<string, ReferralStats>> ReferralStatsAsync(IReadOnlyCollection<string> actors, DateTimeOffset since, CancellationToken cancellationToken) =>
        Task.FromResult<IReadOnlyDictionary<string, ReferralStats>>(actors.Contains("doctor1")
            ? new Dictionary<string, ReferralStats> { ["doctor1"] = new(12, 0.75) }
            : new Dictionary<string, ReferralStats>());

    public Task<IReadOnlyList<AuditRow>> MentionsAsync(IReadOnlyCollection<string> needles, string exceptActor, int limit, CancellationToken cancellationToken) =>
        Task.FromResult<IReadOnlyList<AuditRow>>(Audit.Where(a => a.Actor != exceptActor && needles.Any(n => a.Path.Contains(n))).Take(limit).ToList());

    public Task<IReadOnlyList<AuditRow>> ByActorAsync(string actor, int limit, CancellationToken cancellationToken) =>
        Task.FromResult<IReadOnlyList<AuditRow>>(Audit.Where(a => a.Actor == actor).Take(limit).ToList());

    public Task<IReadOnlySet<string>> ConnectedAsync(IReadOnlyCollection<string> moCodes, CancellationToken cancellationToken) =>
        Task.FromResult<IReadOnlySet<string>>(moCodes.Where(m => m == "028B").ToHashSet());

    public Task<IReadOnlyList<DatasetFreshness>> FreshnessAsync(string? regionKato, CancellationToken cancellationToken) =>
        Task.FromResult<IReadOnlyList<DatasetFreshness>>([new("bg_referrals", DateTimeOffset.UtcNow.AddHours(-2), "loaded", 767084)]);
}

/// <summary>journal.audit в памяти: записи двух организаций для проверки scope own.</summary>
public sealed class InMemoryAudit : IAuditRepository
{
    private readonly List<AuditEntryDto> _items =
    [
        new(1, DateTimeOffset.UtcNow.AddMinutes(-10), "doctor1", "doctor", "GET", "/api/v1/journal/worklist", null, 200, 12, "t1", "028B"),
        new(2, DateTimeOffset.UtcNow.AddMinutes(-9), "doctor2", "doctor", "GET", "/api/v1/journal/worklist", null, 200, 15, "t2", "22GN"),
        new(3, DateTimeOffset.UtcNow.AddMinutes(-8), "regulator1", "regulator", "GET", "/api/v1/index", null, 200, 9, "t3"),
    ];

    public Task<Paged<AuditEntryDto>> ListAsync(string? actor, string? moCode, int page, int size, CancellationToken cancellationToken)
    {
        var items = _items.Where(a => (actor is null || a.Actor == actor) && (moCode is null || a.MoCode == moCode)).ToList();
        return Task.FromResult(new Paged<AuditEntryDto>(items.Skip((page - 1) * size).Take(size).ToList(), page, size, items.Count));
    }
}
