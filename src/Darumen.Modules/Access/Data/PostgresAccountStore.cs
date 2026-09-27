using Dapper;
using Darumen.Shared.Data;

namespace Darumen.Modules.Access.Data;

public sealed class PostgresAccountStore(IDbConnectionFactory db) : IAccountStore
{
    public async Task<UserSettings?> SettingsAsync(string userId, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        var row = await connection.QueryFirstOrDefaultAsync<SettingsRow>(new CommandDefinition(
            """
            SELECT user_id AS UserId, actor AS Actor, phone AS Phone, language AS Language, time_zone AS TimeZone, notifications::text AS NotificationsJson,
                   profile_checked_at AS ProfileCheckedAt, updated_at AS UpdatedAt
            FROM auth.user_settings WHERE user_id = @userId
            """,
            new { userId }, cancellationToken: cancellationToken));
        return row is null
            ? null
            : new UserSettings(row.UserId, row.Actor, row.Phone, row.Language, row.TimeZone, row.NotificationsJson, Db.Utc(row.ProfileCheckedAt), Db.Utc(row.UpdatedAt));
    }

    public async Task SaveSettingsAsync(UserSettings settings, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        await connection.ExecuteAsync(new CommandDefinition(
            """
            INSERT INTO auth.user_settings (user_id, actor, phone, language, time_zone, notifications, profile_checked_at, updated_at)
            VALUES (@UserId, @Actor, @Phone, @Language, @TimeZone, CAST(@NotificationsJson AS jsonb), @ProfileCheckedAt, @UpdatedAt)
            ON CONFLICT (user_id) DO UPDATE SET actor = excluded.actor, phone = excluded.phone, language = excluded.language,
                time_zone = excluded.time_zone, notifications = excluded.notifications, profile_checked_at = excluded.profile_checked_at,
                updated_at = excluded.updated_at
            """,
            new
            {
                settings.UserId, settings.Actor, settings.Phone, settings.Language, settings.TimeZone, settings.NotificationsJson,
                ProfileCheckedAt = Db.Raw(settings.ProfileCheckedAt), UpdatedAt = settings.UpdatedAt.UtcDateTime,
            },
            cancellationToken: cancellationToken));
    }

    public async Task<IReadOnlyList<ConsentRecord>> ConsentsAsync(string userId, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        var rows = await connection.QueryAsync<ConsentRow>(new CommandDefinition(
            "SELECT code AS Code, granted AS Granted, updated_at AS UpdatedAt FROM auth.user_consents WHERE user_id = @userId",
            new { userId }, cancellationToken: cancellationToken));
        return rows.Select(r => new ConsentRecord(r.Code, r.Granted, Db.Utc(r.UpdatedAt))).ToList();
    }

    public async Task SetConsentAsync(string userId, string code, bool granted, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        await connection.ExecuteAsync(new CommandDefinition(
            """
            INSERT INTO auth.user_consents (user_id, code, granted, updated_at) VALUES (@userId, @code, @granted, now())
            ON CONFLICT (user_id, code) DO UPDATE SET granted = excluded.granted, updated_at = excluded.updated_at
            """,
            new { userId, code, granted }, cancellationToken: cancellationToken));
    }

    public async Task AddRequestAsync(AccountRequest request, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        await connection.ExecuteAsync(new CommandDefinition(
            """
            INSERT INTO auth.account_requests (at, user_id, actor, role, mo_code, kind, permission, path, comment, status)
            VALUES (@At, @UserId, @Actor, @Role, @MoCode, @Kind, @Permission, @Path, @Comment, 'open')
            """,
            new
            {
                At = request.At.UtcDateTime, request.UserId, request.Actor, request.Role, request.MoCode, request.Kind, request.Permission, request.Path,
                request.Comment,
            },
            cancellationToken: cancellationToken));
    }

    public async Task<IReadOnlyDictionary<string, DoctorVerification>> VerificationsAsync(IReadOnlyCollection<string> userIds, CancellationToken cancellationToken)
    {
        if (userIds.Count == 0)
        {
            return new Dictionary<string, DoctorVerification>();
        }

        await using var connection = await db.OpenAsync(cancellationToken);
        var rows = await connection.QueryAsync<VerificationRow>(new CommandDefinition(
            """
            SELECT user_id AS UserId, status AS Status, comment AS Comment, decided_by AS DecidedBy, decided_at AS DecidedAt
            FROM auth.doctor_verifications WHERE user_id = ANY(@ids)
            """,
            new { ids = userIds.ToArray() }, cancellationToken: cancellationToken));
        return rows.ToDictionary(r => r.UserId, r => new DoctorVerification(r.UserId, r.Status, r.Comment, r.DecidedBy, Db.Utc(r.DecidedAt)));
    }

    public async Task SetVerificationAsync(DoctorVerification verification, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        await connection.ExecuteAsync(new CommandDefinition(
            """
            INSERT INTO auth.doctor_verifications (user_id, status, comment, decided_by, decided_at)
            VALUES (@UserId, @Status, @Comment, @DecidedBy, @DecidedAt)
            ON CONFLICT (user_id) DO UPDATE SET status = excluded.status, comment = excluded.comment, decided_by = excluded.decided_by,
                decided_at = excluded.decided_at
            """,
            new { verification.UserId, verification.Status, verification.Comment, verification.DecidedBy, DecidedAt = verification.DecidedAt.UtcDateTime },
            cancellationToken: cancellationToken));
    }

    private sealed record SettingsRow(
        string UserId, string Actor, string? Phone, string Language, string TimeZone, string? NotificationsJson, DateTime? ProfileCheckedAt, DateTime UpdatedAt);

    private sealed record ConsentRow(string Code, bool Granted, DateTime UpdatedAt);

    private sealed record VerificationRow(string UserId, string Status, string? Comment, string DecidedBy, DateTime DecidedAt);
}
