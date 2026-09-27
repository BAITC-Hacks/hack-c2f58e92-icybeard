namespace Darumen.Modules.Access;

// Я и мой аккаунт
public sealed record PermissionGrantDto(string Code, string Scope);

public sealed record OnboardingDto(bool EmailVerified, bool OtpConfigured, bool ProfileChecked, bool ColleaguesInvited);

public sealed record MeDto(
    string Actor, string UserId, string DisplayName, string? Email, bool EmailVerified, IReadOnlyList<string> Roles,
    IReadOnlyList<PermissionGrantDto> Permissions, string? MoCode, string? MoName, string? RegionKato, string? IinMasked, OnboardingDto Onboarding);

public sealed record AccessRequestDto(string? Permission, string? Path, string? Comment);

public sealed record ProfileDto(
    string DisplayName, string? Position, string? Specialty, string? Email, string? Phone, string Language, string TimeZone,
    string? MoCode, string? MoName, string? RegionKato, string? IinMasked, IReadOnlyList<string> ReadOnlyFields);

public sealed record ProfileUpdateDto(string? Phone, string? Language, string? TimeZone);

public sealed record NotificationEventDto(string Code, string TitleRu, string TitleKk, bool InApp, bool Email, bool Sms, bool Push, bool Locked);

public sealed record NotificationsDto(IReadOnlyList<NotificationEventDto> Events, string? QuietFrom, string? QuietTo, bool QuietExceptRegulator, string Digest);

public sealed record NotificationEventUpdateDto(string? Code, bool InApp, bool Email, bool Sms, bool Push);

public sealed record NotificationsUpdateDto(
    IReadOnlyList<NotificationEventUpdateDto>? Events, string? QuietFrom, string? QuietTo, bool QuietExceptRegulator, string? Digest);

public sealed record ConsentDto(string Code, string TitleRu, string TitleKk, bool Required, bool Granted, DateTimeOffset? UpdatedAt);

public sealed record ConsentUpdateDto(bool? Granted);

public sealed record AccessLogItemDto(DateTimeOffset At, string Actor, string Role, string Method, string Path, int Status);

public sealed record DeletionRequestDto(string? Comment);

public sealed record LoginDto(DateTimeOffset At, string Method, bool Success, string? Ip);

public sealed record SessionDto(string Id, string Device, string? Browser, string? Ip, DateTimeOffset? Start, DateTimeOffset? LastAccess, bool Current);

public sealed record SecurityDto(
    DateTimeOffset? PasswordChangedAt, bool OtpConfigured, bool SmsAvailable, IReadOnlyList<string>? RecoveryCodes,
    IReadOnlyList<LoginDto> RecentLogins, IReadOnlyList<SessionDto> Sessions);

// Администрирование
public sealed record UserRowDto(
    string Id, string Username, string DisplayName, string? Email, IReadOnlyList<string> Roles, string? MoCode, string? MoName, string? RegionKato,
    DateTimeOffset? LastActivity, string Status, string Via);

public sealed record UsersSummaryDto(int Active, int InvitedStale, int Blocked);

public sealed record UsersPageDto(IReadOnlyList<UserRowDto> Items, long Total, int Page, int Size, UsersSummaryDto Summary);

public sealed record UserDetailDto(
    UserRowDto User, bool EmailVerified, DateTimeOffset? CreatedAt, string? Position, string? Specialty, DateTimeOffset? InvitedAt,
    DateTimeOffset? InviteExpiresAt);

public sealed record UserUpdateDto(string? Role, string? MoCode, string? RegionKato);

public sealed record InviteRequestDto(string? Email, string? DisplayName, string? Role, string? MoCode, string? RegionKato);

public sealed record InviteResultDto(string UserId, Guid InvitationId, DateTimeOffset ExpiresAt, bool EmailSent, string? InviteUrl);

public sealed record DoctorRowDto(
    string Id, string DisplayName, string? Specialty, string? MoCode, string? MoName, string? RegionKato, long Referrals, double? MatchRate,
    string Verification);

public sealed record VerificationRequestDto(string? Status, string? Comment);

public sealed record RoleDto(string Key, string TitleRu, string TitleKk, string? DescriptionRu, string? DescriptionKk, bool Builtin, bool Editable);

public sealed record PermissionDto(string Code, string TitleRu, string TitleKk, bool System, bool Editable);

public sealed record MatrixCellDto(string Role, string Permission, string Scope);

public sealed record RolesResponseDto(
    IReadOnlyList<RoleDto> Roles, IReadOnlyList<PermissionDto> Permissions, IReadOnlyList<MatrixCellDto> Matrix,
    IReadOnlyDictionary<string, int> UsersByRole, bool IdentityAvailable);

public sealed record PermissionChangeDto(string? Permission, string? Scope);

public sealed record RolePermissionsUpdateDto(IReadOnlyList<PermissionChangeDto>? Changes, string? Comment);

public sealed record RoleCreateDto(string? Key, string? TitleRu, string? TitleKk, string? DescriptionRu, string? DescriptionKk, string? CopyFrom);

public sealed record RoleChangeDto(long Id, DateTimeOffset At, string Actor, string Role, string Permission, string? OldScope, string? NewScope, string? Comment);

public sealed record OrgAdminDto(string Id, string DisplayName, string? Email, string Status);

public sealed record FreshnessDto(string Dataset, DateTimeOffset LastLoadedAt, string Status, long RowsLoaded);

public sealed record OrgRowDto(
    string MoCode, string Name, string RegionKato, string? Type, int? Users, string Status, IReadOnlyList<OrgAdminDto> Admins,
    IReadOnlyList<FreshnessDto> Freshness);

public sealed record OrgApplicationDto(
    Guid Id, string Number, string OrgName, string Bin, string Type, string RegionKato, string? MoCode, string AdminName, string Email, string Phone,
    string Status, DateTimeOffset SubmittedAt, DateTimeOffset? EmailVerifiedAt, DateTimeOffset? DecidedAt, string? DecidedBy, string? RejectReason);

public sealed record OrgDetailDto(OrgRowDto Organization, IReadOnlyList<OrgApplicationDto> Applications);

public sealed record ApproveRequestDto(string? MoCode);

public sealed record RejectRequestDto(string? Reason);

public sealed record ApplicationDecisionDto(string Status, bool EmailSent, string? InviteUrl, Guid? InvitationId);

// Публичное
public sealed record OrgApplicationRequestDto(
    string? OrgName, string? Bin, string? Type, string? RegionKato, string? MoCode, string? AdminName, string? Email, string? Phone, bool Consent);

public sealed record OrgApplicationCreatedDto(Guid Id, string Number, string StatusToken, bool EmailSent, int ResendAfterSeconds);

public sealed record VerifyEmailDto(string? Code, string? StatusToken);

public sealed record StatusTokenDto(string? StatusToken);

public sealed record CodeResentDto(bool EmailSent, int ResendAfterSeconds);

public sealed record OrgApplicationStatusDto(string Number, string OrgName, string Email, string Status, DateTimeOffset SubmittedAt);

public sealed record InviteInfoDto(
    string DisplayName, string Email, string? OrgName, string? MoCode, string Role, string RoleTitleRu, string RoleTitleKk, string InvitedBy,
    DateTimeOffset InvitedAt, DateTimeOffset ExpiresAt);

public sealed record InviteAcceptDto(string? Password, bool AcceptedRules);

public sealed record InviteAcceptedDto(string Username, bool Accepted);

public sealed record PasswordResetDto(string? Email);
