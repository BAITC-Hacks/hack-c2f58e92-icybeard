using Microsoft.EntityFrameworkCore;

namespace Darumen.Migrations;

/// <summary>Схема auth: роли, матрица разрешений и её журнал, приглашения, заявки организаций, верификация врачей,
/// настройки и согласия пользователей, запросы доступа (docs/rbac.md).</summary>
internal static class AuthModel
{
    public const string Schema = "auth";
    public const string ApplicationNumberSequence = "org_application_seq";

    private const int KeyLength = 64;
    private const int ActorLength = 200;
    private const int HashLength = 64;

    public static void Configure(ModelBuilder modelBuilder)
    {
        modelBuilder.HasSequence<long>(ApplicationNumberSequence, Schema);
        ConfigureRoles(modelBuilder);
        ConfigureInvitations(modelBuilder);
        ConfigureApplications(modelBuilder);
        ConfigureAccount(modelBuilder);
    }

    private static void ConfigureRoles(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<AuthRole>(e =>
        {
            e.ToTable("roles", Schema);
            e.HasKey(x => x.Key);
            e.Property(x => x.Key).HasColumnName("key").HasMaxLength(KeyLength);
            e.Property(x => x.TitleRu).HasColumnName("title_ru").HasMaxLength(200);
            e.Property(x => x.TitleKk).HasColumnName("title_kk").HasMaxLength(200);
            e.Property(x => x.DescriptionRu).HasColumnName("description_ru");
            e.Property(x => x.DescriptionKk).HasColumnName("description_kk");
            e.Property(x => x.Builtin).HasColumnName("builtin");
            e.Property(x => x.CreatedAt).HasColumnName("created_at").HasColumnType("timestamptz");
        });

        modelBuilder.Entity<AuthRolePermission>(e =>
        {
            e.ToTable("role_permissions", Schema, t => t.HasCheckConstraint("ck_role_permissions_scope", "scope IN ('all', 'own')"));
            e.HasKey(x => new { x.Role, x.Permission });
            e.Property(x => x.Role).HasColumnName("role").HasMaxLength(KeyLength);
            e.Property(x => x.Permission).HasColumnName("permission").HasMaxLength(KeyLength);
            e.Property(x => x.Scope).HasColumnName("scope").HasMaxLength(8);
            e.HasOne<AuthRole>().WithMany().HasForeignKey(x => x.Role).OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<AuthRolePermissionChange>(e =>
        {
            e.ToTable("role_permission_changes", Schema);
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasColumnName("id").UseIdentityAlwaysColumn();
            e.Property(x => x.At).HasColumnName("at").HasColumnType("timestamptz");
            e.Property(x => x.Actor).HasColumnName("actor").HasMaxLength(ActorLength);
            e.Property(x => x.Role).HasColumnName("role").HasMaxLength(KeyLength);
            e.Property(x => x.Permission).HasColumnName("permission").HasMaxLength(KeyLength);
            e.Property(x => x.OldScope).HasColumnName("old_scope").HasMaxLength(8);
            e.Property(x => x.NewScope).HasColumnName("new_scope").HasMaxLength(8);
            e.Property(x => x.Comment).HasColumnName("comment");
            e.HasIndex(x => new { x.Role, x.At });
            e.HasIndex(x => x.At);
        });
    }

    private static void ConfigureInvitations(ModelBuilder modelBuilder) =>
        modelBuilder.Entity<AuthInvitation>(e =>
        {
            e.ToTable("invitations", Schema);
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasColumnName("id");
            e.Property(x => x.TokenHash).HasColumnName("token_hash").HasMaxLength(HashLength);
            e.Property(x => x.UserId).HasColumnName("user_id").HasMaxLength(KeyLength);
            e.Property(x => x.Email).HasColumnName("email").HasMaxLength(320);
            e.Property(x => x.DisplayName).HasColumnName("display_name").HasMaxLength(200);
            e.Property(x => x.Role).HasColumnName("role").HasMaxLength(KeyLength);
            e.Property(x => x.MoCode).HasColumnName("mo_code").HasMaxLength(20);
            e.Property(x => x.RegionKato).HasColumnName("region_kato").HasMaxLength(2);
            e.Property(x => x.InvitedBy).HasColumnName("invited_by").HasMaxLength(ActorLength);
            e.Property(x => x.InvitedAt).HasColumnName("invited_at").HasColumnType("timestamptz");
            e.Property(x => x.ExpiresAt).HasColumnName("expires_at").HasColumnType("timestamptz");
            e.Property(x => x.AcceptedAt).HasColumnName("accepted_at").HasColumnType("timestamptz");
            e.Property(x => x.DeclinedAt).HasColumnName("declined_at").HasColumnType("timestamptz");
            e.Property(x => x.ApplicationId).HasColumnName("application_id");
            e.HasIndex(x => x.TokenHash).IsUnique();
            e.HasIndex(x => new { x.UserId, x.InvitedAt });
            e.HasIndex(x => x.InvitedBy);
        });

    private static void ConfigureApplications(ModelBuilder modelBuilder) =>
        modelBuilder.Entity<AuthOrgApplication>(e =>
        {
            e.ToTable("org_applications", Schema);
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasColumnName("id");
            e.Property(x => x.Number).HasColumnName("number").HasMaxLength(32);
            e.Property(x => x.OrgName).HasColumnName("org_name").HasMaxLength(300);
            e.Property(x => x.Bin).HasColumnName("bin").HasMaxLength(12);
            e.Property(x => x.Type).HasColumnName("type").HasMaxLength(50);
            e.Property(x => x.RegionKato).HasColumnName("region_kato").HasMaxLength(2);
            e.Property(x => x.MoCode).HasColumnName("mo_code").HasMaxLength(20);
            e.Property(x => x.AdminName).HasColumnName("admin_name").HasMaxLength(200);
            e.Property(x => x.Email).HasColumnName("email").HasMaxLength(320);
            e.Property(x => x.Phone).HasColumnName("phone").HasMaxLength(32);
            e.Property(x => x.Consent).HasColumnName("consent");
            e.Property(x => x.Status).HasColumnName("status").HasMaxLength(20);
            e.Property(x => x.StatusTokenHash).HasColumnName("status_token_hash").HasMaxLength(HashLength);
            e.Property(x => x.EmailCodeHash).HasColumnName("email_code_hash").HasMaxLength(HashLength);
            e.Property(x => x.EmailCodeExpiresAt).HasColumnName("email_code_expires_at").HasColumnType("timestamptz");
            e.Property(x => x.EmailCodeSentAt).HasColumnName("email_code_sent_at").HasColumnType("timestamptz");
            e.Property(x => x.EmailCodeAttempts).HasColumnName("email_code_attempts");
            e.Property(x => x.SubmittedAt).HasColumnName("submitted_at").HasColumnType("timestamptz");
            e.Property(x => x.EmailVerifiedAt).HasColumnName("email_verified_at").HasColumnType("timestamptz");
            e.Property(x => x.DecidedAt).HasColumnName("decided_at").HasColumnType("timestamptz");
            e.Property(x => x.DecidedBy).HasColumnName("decided_by").HasMaxLength(ActorLength);
            e.Property(x => x.RejectReason).HasColumnName("reject_reason");
            e.Property(x => x.InvitationId).HasColumnName("invitation_id");
            e.HasIndex(x => x.Number).IsUnique();
            e.HasIndex(x => new { x.Status, x.SubmittedAt });
            e.HasIndex(x => x.MoCode);
        });

    private static void ConfigureAccount(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<AuthDoctorVerification>(e =>
        {
            e.ToTable("doctor_verifications", Schema);
            e.HasKey(x => x.UserId);
            e.Property(x => x.UserId).HasColumnName("user_id").HasMaxLength(KeyLength);
            e.Property(x => x.Status).HasColumnName("status").HasMaxLength(20);
            e.Property(x => x.Comment).HasColumnName("comment");
            e.Property(x => x.DecidedBy).HasColumnName("decided_by").HasMaxLength(ActorLength);
            e.Property(x => x.DecidedAt).HasColumnName("decided_at").HasColumnType("timestamptz");
        });

        modelBuilder.Entity<AuthUserSettings>(e =>
        {
            e.ToTable("user_settings", Schema);
            e.HasKey(x => x.UserId);
            e.Property(x => x.UserId).HasColumnName("user_id").HasMaxLength(KeyLength);
            e.Property(x => x.Actor).HasColumnName("actor").HasMaxLength(ActorLength);
            e.Property(x => x.Phone).HasColumnName("phone").HasMaxLength(32);
            e.Property(x => x.Language).HasColumnName("language").HasMaxLength(8);
            e.Property(x => x.TimeZone).HasColumnName("time_zone").HasMaxLength(64);
            e.Property(x => x.Notifications).HasColumnName("notifications").HasColumnType("jsonb");
            e.Property(x => x.ProfileCheckedAt).HasColumnName("profile_checked_at").HasColumnType("timestamptz");
            e.Property(x => x.UpdatedAt).HasColumnName("updated_at").HasColumnType("timestamptz");
        });

        modelBuilder.Entity<AuthUserConsent>(e =>
        {
            e.ToTable("user_consents", Schema);
            e.HasKey(x => new { x.UserId, x.Code });
            e.Property(x => x.UserId).HasColumnName("user_id").HasMaxLength(KeyLength);
            e.Property(x => x.Code).HasColumnName("code").HasMaxLength(KeyLength);
            e.Property(x => x.Granted).HasColumnName("granted");
            e.Property(x => x.UpdatedAt).HasColumnName("updated_at").HasColumnType("timestamptz");
        });

        modelBuilder.Entity<AuthAccountRequest>(e =>
        {
            e.ToTable("account_requests", Schema);
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasColumnName("id").UseIdentityAlwaysColumn();
            e.Property(x => x.At).HasColumnName("at").HasColumnType("timestamptz");
            e.Property(x => x.UserId).HasColumnName("user_id").HasMaxLength(KeyLength);
            e.Property(x => x.Actor).HasColumnName("actor").HasMaxLength(ActorLength);
            e.Property(x => x.Role).HasColumnName("role").HasMaxLength(KeyLength);
            e.Property(x => x.MoCode).HasColumnName("mo_code").HasMaxLength(20);
            e.Property(x => x.Kind).HasColumnName("kind").HasMaxLength(20);
            e.Property(x => x.Permission).HasColumnName("permission").HasMaxLength(KeyLength);
            e.Property(x => x.Path).HasColumnName("path").HasMaxLength(500);
            e.Property(x => x.Comment).HasColumnName("comment");
            e.Property(x => x.Status).HasColumnName("status").HasMaxLength(20);
            e.HasIndex(x => new { x.MoCode, x.At });
            e.HasIndex(x => new { x.UserId, x.At });
        });
    }
}
