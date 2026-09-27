namespace Darumen.Migrations;

/// <summary>Роль приложения (realm role Keycloak с тем же ключом); builtin — встроенная, не удаляется.</summary>
public sealed class AuthRole
{
    public string Key { get; set; } = string.Empty;
    public string TitleRu { get; set; } = string.Empty;
    public string TitleKk { get; set; } = string.Empty;
    public string? DescriptionRu { get; set; }
    public string? DescriptionKk { get; set; }
    public bool Builtin { get; set; }
    public DateTime CreatedAt { get; set; }
}

/// <summary>Строка матрицы: разрешение роли с охватом all | own.</summary>
public sealed class AuthRolePermission
{
    public string Role { get; set; } = string.Empty;
    public string Permission { get; set; } = string.Empty;
    public string Scope { get; set; } = string.Empty;
}

/// <summary>Журнал изменений матрицы: old/new scope null — разрешения не было / сняли.</summary>
public sealed class AuthRolePermissionChange
{
    public long Id { get; set; }
    public DateTime At { get; set; }
    public string Actor { get; set; } = string.Empty;
    public string Role { get; set; } = string.Empty;
    public string Permission { get; set; } = string.Empty;
    public string? OldScope { get; set; }
    public string? NewScope { get; set; }
    public string? Comment { get; set; }
}

/// <summary>Приглашение: хранится только SHA-256 токена, сам токен уходит в письме или ответе администратору.</summary>
public sealed class AuthInvitation
{
    public Guid Id { get; set; }
    public string TokenHash { get; set; } = string.Empty;
    public string UserId { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public string DisplayName { get; set; } = string.Empty;
    public string Role { get; set; } = string.Empty;
    public string? MoCode { get; set; }
    public string? RegionKato { get; set; }
    public string InvitedBy { get; set; } = string.Empty;
    public DateTime InvitedAt { get; set; }
    public DateTime ExpiresAt { get; set; }
    public DateTime? AcceptedAt { get; set; }
    public DateTime? DeclinedAt { get; set; }
    public Guid? ApplicationId { get; set; }
}

/// <summary>Заявка организации на подключение: pending_email → pending_review → approved | rejected.</summary>
public sealed class AuthOrgApplication
{
    public Guid Id { get; set; }
    public string Number { get; set; } = string.Empty;
    public string OrgName { get; set; } = string.Empty;
    public string Bin { get; set; } = string.Empty;
    public string Type { get; set; } = string.Empty;
    public string RegionKato { get; set; } = string.Empty;
    public string? MoCode { get; set; }
    public string AdminName { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public string Phone { get; set; } = string.Empty;
    public bool Consent { get; set; }
    public string Status { get; set; } = string.Empty;
    public string StatusTokenHash { get; set; } = string.Empty;
    public string? EmailCodeHash { get; set; }
    public DateTime? EmailCodeExpiresAt { get; set; }
    public DateTime? EmailCodeSentAt { get; set; }
    public int EmailCodeAttempts { get; set; }
    public DateTime SubmittedAt { get; set; }
    public DateTime? EmailVerifiedAt { get; set; }
    public DateTime? DecidedAt { get; set; }
    public string? DecidedBy { get; set; }
    public string? RejectReason { get; set; }
    public Guid? InvitationId { get; set; }
}

public sealed class AuthDoctorVerification
{
    public string UserId { get; set; } = string.Empty;
    public string Status { get; set; } = string.Empty;
    public string? Comment { get; set; }
    public string DecidedBy { get; set; } = string.Empty;
    public DateTime DecidedAt { get; set; }
}

/// <summary>Настройки аккаунта: профиль (телефон, язык, часовой пояс) и уведомления (jsonb).</summary>
public sealed class AuthUserSettings
{
    public string UserId { get; set; } = string.Empty;
    public string Actor { get; set; } = string.Empty;
    public string? Phone { get; set; }
    public string Language { get; set; } = "ru";
    public string TimeZone { get; set; } = "Asia/Almaty";
    public string? Notifications { get; set; }
    public DateTime? ProfileCheckedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
}

public sealed class AuthUserConsent
{
    public string UserId { get; set; } = string.Empty;
    public string Code { get; set; } = string.Empty;
    public bool Granted { get; set; }
    public DateTime UpdatedAt { get; set; }
}

/// <summary>Запросы пользователя: доступ к разделу (kind = access) и удаление аккаунта (kind = deletion).</summary>
public sealed class AuthAccountRequest
{
    public long Id { get; set; }
    public DateTime At { get; set; }
    public string UserId { get; set; } = string.Empty;
    public string Actor { get; set; } = string.Empty;
    public string Role { get; set; } = string.Empty;
    public string? MoCode { get; set; }
    public string Kind { get; set; } = string.Empty;
    public string? Permission { get; set; }
    public string? Path { get; set; }
    public string? Comment { get; set; }
    public string Status { get; set; } = string.Empty;
}
