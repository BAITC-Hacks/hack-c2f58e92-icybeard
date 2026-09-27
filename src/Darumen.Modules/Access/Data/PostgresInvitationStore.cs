using Dapper;
using Darumen.Shared.Data;

namespace Darumen.Modules.Access.Data;

public sealed class PostgresInvitationStore(IDbConnectionFactory db) : IInvitationStore
{
    private const string Columns = """
        id AS Id, token_hash AS TokenHash, user_id AS UserId, email AS Email, display_name AS DisplayName, role AS Role, mo_code AS MoCode,
        region_kato AS RegionKato, invited_by AS InvitedBy, invited_at AS InvitedAt, expires_at AS ExpiresAt, accepted_at AS AcceptedAt,
        declined_at AS DeclinedAt, application_id AS ApplicationId
        """;

    public async Task AddAsync(Invitation invitation, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        await connection.ExecuteAsync(new CommandDefinition(
            """
            INSERT INTO auth.invitations (id, token_hash, user_id, email, display_name, role, mo_code, region_kato, invited_by, invited_at, expires_at, application_id)
            VALUES (@Id, @TokenHash, @UserId, @Email, @DisplayName, @Role, @MoCode, @RegionKato, @InvitedBy, @InvitedAt, @ExpiresAt, @ApplicationId)
            """,
            new
            {
                invitation.Id, invitation.TokenHash, invitation.UserId, invitation.Email, invitation.DisplayName, invitation.Role, invitation.MoCode,
                invitation.RegionKato, invitation.InvitedBy, InvitedAt = invitation.InvitedAt.UtcDateTime, ExpiresAt = invitation.ExpiresAt.UtcDateTime,
                invitation.ApplicationId,
            },
            cancellationToken: cancellationToken));
    }

    public async Task<Invitation?> ByTokenHashAsync(string tokenHash, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        var row = await connection.QueryFirstOrDefaultAsync<Row>(new CommandDefinition(
            $"SELECT {Columns} FROM auth.invitations WHERE token_hash = @tokenHash", new { tokenHash }, cancellationToken: cancellationToken));
        return row?.ToRecord();
    }

    public async Task<IReadOnlyList<Invitation>> OpenForUsersAsync(IReadOnlyCollection<string> userIds, CancellationToken cancellationToken)
    {
        if (userIds.Count == 0)
        {
            return [];
        }

        await using var connection = await db.OpenAsync(cancellationToken);
        var rows = await connection.QueryAsync<Row>(new CommandDefinition(
            $"""
            SELECT DISTINCT ON (user_id) {Columns} FROM auth.invitations
            WHERE user_id = ANY(@ids) AND accepted_at IS NULL AND declined_at IS NULL
            ORDER BY user_id, invited_at DESC
            """,
            new { ids = userIds.ToArray() }, cancellationToken: cancellationToken));
        return rows.Select(r => r.ToRecord()).ToList();
    }

    public async Task CloseAsync(Guid id, bool accepted, DateTimeOffset at, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        var column = accepted ? "accepted_at" : "declined_at";
        await connection.ExecuteAsync(new CommandDefinition(
            $"UPDATE auth.invitations SET {column} = @at WHERE id = @id AND accepted_at IS NULL AND declined_at IS NULL",
            new { id, at = at.UtcDateTime }, cancellationToken: cancellationToken));
    }

    public async Task<bool> AnyByInviterAsync(string actor, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        return await connection.ExecuteScalarAsync<bool>(new CommandDefinition(
            "SELECT EXISTS (SELECT 1 FROM auth.invitations WHERE invited_by = @actor)", new { actor }, cancellationToken: cancellationToken));
    }

    private sealed record Row(
        Guid Id, string TokenHash, string UserId, string Email, string DisplayName, string Role, string? MoCode, string? RegionKato, string InvitedBy,
        DateTime InvitedAt, DateTime ExpiresAt, DateTime? AcceptedAt, DateTime? DeclinedAt, Guid? ApplicationId)
    {
        public Invitation ToRecord() => new(
            Id, TokenHash, UserId, Email, DisplayName, Role, MoCode, RegionKato, InvitedBy, Db.Utc(InvitedAt), Db.Utc(ExpiresAt),
            Db.Utc(AcceptedAt), Db.Utc(DeclinedAt), ApplicationId);
    }
}
