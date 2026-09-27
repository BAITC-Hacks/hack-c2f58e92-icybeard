using Dapper;
using Darumen.Shared.Api;
using Darumen.Shared.Data;

namespace Darumen.Modules.Access.Data;

public sealed class PostgresOrgApplicationStore(IDbConnectionFactory db) : IOrgApplicationStore
{
    private const string Columns = """
        id AS Id, number AS Number, org_name AS OrgName, bin AS Bin, type AS Type, region_kato AS RegionKato, mo_code AS MoCode,
        admin_name AS AdminName, email AS Email, phone AS Phone, consent AS Consent, status AS Status, status_token_hash AS StatusTokenHash,
        email_code_hash AS EmailCodeHash, email_code_expires_at AS EmailCodeExpiresAt, email_code_sent_at AS EmailCodeSentAt,
        email_code_attempts AS EmailCodeAttempts, submitted_at AS SubmittedAt, email_verified_at AS EmailVerifiedAt, decided_at AS DecidedAt,
        decided_by AS DecidedBy, reject_reason AS RejectReason, invitation_id AS InvitationId
        """;

    public async Task<OrgApplication> AddAsync(OrgApplication application, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        var sequence = await connection.ExecuteScalarAsync<long>(new CommandDefinition(
            "SELECT nextval('auth.org_application_seq')", cancellationToken: cancellationToken));
        var numbered = application with { Number = $"ORG-{application.SubmittedAt.UtcDateTime:yyyy}-{sequence:D5}" };
        await connection.ExecuteAsync(new CommandDefinition(
            """
            INSERT INTO auth.org_applications (id, number, org_name, bin, type, region_kato, mo_code, admin_name, email, phone, consent, status,
                status_token_hash, email_code_hash, email_code_expires_at, email_code_sent_at, email_code_attempts, submitted_at)
            VALUES (@Id, @Number, @OrgName, @Bin, @Type, @RegionKato, @MoCode, @AdminName, @Email, @Phone, @Consent, @Status,
                @StatusTokenHash, @EmailCodeHash, @EmailCodeExpiresAt, @EmailCodeSentAt, @EmailCodeAttempts, @SubmittedAt)
            """,
            Parameters(numbered), cancellationToken: cancellationToken));
        return numbered;
    }

    public async Task<OrgApplication?> GetAsync(Guid id, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        var row = await connection.QueryFirstOrDefaultAsync<Row>(new CommandDefinition(
            $"SELECT {Columns} FROM auth.org_applications WHERE id = @id", new { id }, cancellationToken: cancellationToken));
        return row?.ToRecord();
    }

    public async Task SaveAsync(OrgApplication application, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        await connection.ExecuteAsync(new CommandDefinition(
            """
            UPDATE auth.org_applications SET status = @Status, mo_code = @MoCode, email_code_hash = @EmailCodeHash,
                email_code_expires_at = @EmailCodeExpiresAt, email_code_sent_at = @EmailCodeSentAt, email_code_attempts = @EmailCodeAttempts,
                email_verified_at = @EmailVerifiedAt, decided_at = @DecidedAt, decided_by = @DecidedBy, reject_reason = @RejectReason,
                invitation_id = @InvitationId
            WHERE id = @Id
            """,
            Parameters(application), cancellationToken: cancellationToken));
    }

    public async Task<Paged<OrgApplication>> ListAsync(string? status, string? moCode, int page, int size, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        const string where = "WHERE (@status IS NULL OR status = @status) AND (@moCode IS NULL OR mo_code = @moCode)";
        var parameters = new { status, moCode, size, offset = (page - 1) * size };
        var total = await connection.ExecuteScalarAsync<long>(new CommandDefinition(
            $"SELECT count(*) FROM auth.org_applications {where}", parameters, cancellationToken: cancellationToken));
        var rows = await connection.QueryAsync<Row>(new CommandDefinition(
            $"SELECT {Columns} FROM auth.org_applications {where} ORDER BY submitted_at DESC LIMIT @size OFFSET @offset",
            parameters, cancellationToken: cancellationToken));
        return new Paged<OrgApplication>(rows.Select(r => r.ToRecord()).ToList(), page, size, total);
    }

    private static object Parameters(OrgApplication a) => new
    {
        a.Id, a.Number, a.OrgName, a.Bin, a.Type, a.RegionKato, a.MoCode, a.AdminName, a.Email, a.Phone, a.Consent, a.Status, a.StatusTokenHash,
        a.EmailCodeHash, EmailCodeExpiresAt = Db.Raw(a.EmailCodeExpiresAt), EmailCodeSentAt = Db.Raw(a.EmailCodeSentAt), a.EmailCodeAttempts,
        SubmittedAt = a.SubmittedAt.UtcDateTime, EmailVerifiedAt = Db.Raw(a.EmailVerifiedAt), DecidedAt = Db.Raw(a.DecidedAt), a.DecidedBy,
        a.RejectReason, a.InvitationId,
    };

    private sealed record Row(
        Guid Id, string Number, string OrgName, string Bin, string Type, string RegionKato, string? MoCode, string AdminName, string Email, string Phone,
        bool Consent, string Status, string StatusTokenHash, string? EmailCodeHash, DateTime? EmailCodeExpiresAt, DateTime? EmailCodeSentAt,
        int EmailCodeAttempts, DateTime SubmittedAt, DateTime? EmailVerifiedAt, DateTime? DecidedAt, string? DecidedBy, string? RejectReason,
        Guid? InvitationId)
    {
        public OrgApplication ToRecord() => new(
            Id, Number, OrgName, Bin, Type, RegionKato, MoCode, AdminName, Email, Phone, Consent, Status, StatusTokenHash, EmailCodeHash,
            Db.Utc(EmailCodeExpiresAt), Db.Utc(EmailCodeSentAt), EmailCodeAttempts, Db.Utc(SubmittedAt), Db.Utc(EmailVerifiedAt), Db.Utc(DecidedAt),
            DecidedBy, RejectReason, InvitationId);
    }
}
