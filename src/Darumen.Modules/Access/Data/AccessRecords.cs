namespace Darumen.Modules.Access.Data;

public sealed record Invitation(
    Guid Id, string TokenHash, string UserId, string Email, string DisplayName, string Role, string? MoCode, string? RegionKato,
    string InvitedBy, DateTimeOffset InvitedAt, DateTimeOffset ExpiresAt, DateTimeOffset? AcceptedAt, DateTimeOffset? DeclinedAt, Guid? ApplicationId)
{
    public bool IsOpen => AcceptedAt is null && DeclinedAt is null;
}

public static class OrgApplicationStatuses
{
    public const string PendingEmail = "pending_email";
    public const string PendingReview = "pending_review";
    public const string Approved = "approved";
    public const string Rejected = "rejected";

    public static readonly string[] All = [PendingEmail, PendingReview, Approved, Rejected];
}

public sealed record OrgApplication(
    Guid Id, string Number, string OrgName, string Bin, string Type, string RegionKato, string? MoCode, string AdminName, string Email, string Phone,
    bool Consent, string Status, string StatusTokenHash, string? EmailCodeHash, DateTimeOffset? EmailCodeExpiresAt, DateTimeOffset? EmailCodeSentAt,
    int EmailCodeAttempts, DateTimeOffset SubmittedAt, DateTimeOffset? EmailVerifiedAt, DateTimeOffset? DecidedAt, string? DecidedBy,
    string? RejectReason, Guid? InvitationId);

public sealed record UserSettings(
    string UserId, string Actor, string? Phone, string Language, string TimeZone, string? NotificationsJson, DateTimeOffset? ProfileCheckedAt,
    DateTimeOffset UpdatedAt);

public sealed record ConsentRecord(string Code, bool Granted, DateTimeOffset UpdatedAt);

public static class AccountRequestKinds
{
    public const string Access = "access";
    public const string Deletion = "deletion";
}

public sealed record AccountRequest(
    DateTimeOffset At, string UserId, string Actor, string Role, string? MoCode, string Kind, string? Permission, string? Path, string? Comment);

public static class VerificationStatuses
{
    public const string Pending = "pending";
    public const string Verified = "verified";
    public const string Rejected = "rejected";

    public static readonly string[] All = [Pending, Verified, Rejected];
}

public sealed record DoctorVerification(string UserId, string Status, string? Comment, string DecidedBy, DateTimeOffset DecidedAt);

public sealed record ReferralStats(long Referrals, double? MatchRate);

public sealed record AuditRow(DateTimeOffset At, string Actor, string Role, string Method, string Path, int Status);

public sealed record DatasetFreshness(string Dataset, DateTimeOffset LastLoadedAt, string Status, long RowsLoaded);
