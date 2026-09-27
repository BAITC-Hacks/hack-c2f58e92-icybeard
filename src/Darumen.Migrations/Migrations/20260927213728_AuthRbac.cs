using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace Darumen.Migrations.Migrations
{
    /// <inheritdoc />
    public partial class AuthRbac : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.EnsureSchema(
                name: "auth");

            migrationBuilder.CreateSequence(
                name: "org_application_seq",
                schema: "auth");

            migrationBuilder.AddColumn<string>(
                name: "actor_mo_code",
                schema: "journal",
                table: "decisions",
                type: "character varying(20)",
                maxLength: 20,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "detail",
                schema: "journal",
                table: "audit",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "mo_code",
                schema: "journal",
                table: "audit",
                type: "character varying(20)",
                maxLength: 20,
                nullable: true);

            migrationBuilder.CreateTable(
                name: "account_requests",
                schema: "auth",
                columns: table => new
                {
                    id = table.Column<long>(type: "bigint", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityAlwaysColumn),
                    at = table.Column<DateTime>(type: "timestamptz", nullable: false),
                    user_id = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    actor = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    role = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    mo_code = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: true),
                    kind = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    permission = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                    path = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    comment = table.Column<string>(type: "text", nullable: true),
                    status = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_account_requests", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "doctor_verifications",
                schema: "auth",
                columns: table => new
                {
                    user_id = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    status = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    comment = table.Column<string>(type: "text", nullable: true),
                    decided_by = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    decided_at = table.Column<DateTime>(type: "timestamptz", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_doctor_verifications", x => x.user_id);
                });

            migrationBuilder.CreateTable(
                name: "invitations",
                schema: "auth",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    token_hash = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    user_id = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    email = table.Column<string>(type: "character varying(320)", maxLength: 320, nullable: false),
                    display_name = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    role = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    mo_code = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: true),
                    region_kato = table.Column<string>(type: "character varying(2)", maxLength: 2, nullable: true),
                    invited_by = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    invited_at = table.Column<DateTime>(type: "timestamptz", nullable: false),
                    expires_at = table.Column<DateTime>(type: "timestamptz", nullable: false),
                    accepted_at = table.Column<DateTime>(type: "timestamptz", nullable: true),
                    declined_at = table.Column<DateTime>(type: "timestamptz", nullable: true),
                    application_id = table.Column<Guid>(type: "uuid", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_invitations", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "org_applications",
                schema: "auth",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    number = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    org_name = table.Column<string>(type: "character varying(300)", maxLength: 300, nullable: false),
                    bin = table.Column<string>(type: "character varying(12)", maxLength: 12, nullable: false),
                    type = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                    region_kato = table.Column<string>(type: "character varying(2)", maxLength: 2, nullable: false),
                    mo_code = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: true),
                    admin_name = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    email = table.Column<string>(type: "character varying(320)", maxLength: 320, nullable: false),
                    phone = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    consent = table.Column<bool>(type: "boolean", nullable: false),
                    status = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    status_token_hash = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    email_code_hash = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                    email_code_expires_at = table.Column<DateTime>(type: "timestamptz", nullable: true),
                    email_code_sent_at = table.Column<DateTime>(type: "timestamptz", nullable: true),
                    email_code_attempts = table.Column<int>(type: "integer", nullable: false),
                    submitted_at = table.Column<DateTime>(type: "timestamptz", nullable: false),
                    email_verified_at = table.Column<DateTime>(type: "timestamptz", nullable: true),
                    decided_at = table.Column<DateTime>(type: "timestamptz", nullable: true),
                    decided_by = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    reject_reason = table.Column<string>(type: "text", nullable: true),
                    invitation_id = table.Column<Guid>(type: "uuid", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_org_applications", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "role_permission_changes",
                schema: "auth",
                columns: table => new
                {
                    id = table.Column<long>(type: "bigint", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityAlwaysColumn),
                    at = table.Column<DateTime>(type: "timestamptz", nullable: false),
                    actor = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    role = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    permission = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    old_scope = table.Column<string>(type: "character varying(8)", maxLength: 8, nullable: true),
                    new_scope = table.Column<string>(type: "character varying(8)", maxLength: 8, nullable: true),
                    comment = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_role_permission_changes", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "roles",
                schema: "auth",
                columns: table => new
                {
                    key = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    title_ru = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    title_kk = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    description_ru = table.Column<string>(type: "text", nullable: true),
                    description_kk = table.Column<string>(type: "text", nullable: true),
                    builtin = table.Column<bool>(type: "boolean", nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamptz", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_roles", x => x.key);
                });

            migrationBuilder.CreateTable(
                name: "user_consents",
                schema: "auth",
                columns: table => new
                {
                    user_id = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    code = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    granted = table.Column<bool>(type: "boolean", nullable: false),
                    updated_at = table.Column<DateTime>(type: "timestamptz", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_user_consents", x => new { x.user_id, x.code });
                });

            migrationBuilder.CreateTable(
                name: "user_settings",
                schema: "auth",
                columns: table => new
                {
                    user_id = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    actor = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    phone = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: true),
                    language = table.Column<string>(type: "character varying(8)", maxLength: 8, nullable: false),
                    time_zone = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    notifications = table.Column<string>(type: "jsonb", nullable: true),
                    profile_checked_at = table.Column<DateTime>(type: "timestamptz", nullable: true),
                    updated_at = table.Column<DateTime>(type: "timestamptz", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_user_settings", x => x.user_id);
                });

            migrationBuilder.CreateTable(
                name: "role_permissions",
                schema: "auth",
                columns: table => new
                {
                    role = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    permission = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    scope = table.Column<string>(type: "character varying(8)", maxLength: 8, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_role_permissions", x => new { x.role, x.permission });
                    table.CheckConstraint("ck_role_permissions_scope", "scope IN ('all', 'own')");
                    table.ForeignKey(
                        name: "FK_role_permissions_roles_role",
                        column: x => x.role,
                        principalSchema: "auth",
                        principalTable: "roles",
                        principalColumn: "key",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_decisions_actor_mo_code_recorded_at",
                schema: "journal",
                table: "decisions",
                columns: new[] { "actor_mo_code", "recorded_at" });

            migrationBuilder.CreateIndex(
                name: "IX_audit_mo_code_at",
                schema: "journal",
                table: "audit",
                columns: new[] { "mo_code", "at" });

            migrationBuilder.CreateIndex(
                name: "IX_account_requests_mo_code_at",
                schema: "auth",
                table: "account_requests",
                columns: new[] { "mo_code", "at" });

            migrationBuilder.CreateIndex(
                name: "IX_account_requests_user_id_at",
                schema: "auth",
                table: "account_requests",
                columns: new[] { "user_id", "at" });

            migrationBuilder.CreateIndex(
                name: "IX_invitations_invited_by",
                schema: "auth",
                table: "invitations",
                column: "invited_by");

            migrationBuilder.CreateIndex(
                name: "IX_invitations_token_hash",
                schema: "auth",
                table: "invitations",
                column: "token_hash",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_invitations_user_id_invited_at",
                schema: "auth",
                table: "invitations",
                columns: new[] { "user_id", "invited_at" });

            migrationBuilder.CreateIndex(
                name: "IX_org_applications_mo_code",
                schema: "auth",
                table: "org_applications",
                column: "mo_code");

            migrationBuilder.CreateIndex(
                name: "IX_org_applications_number",
                schema: "auth",
                table: "org_applications",
                column: "number",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_org_applications_status_submitted_at",
                schema: "auth",
                table: "org_applications",
                columns: new[] { "status", "submitted_at" });

            migrationBuilder.CreateIndex(
                name: "IX_role_permission_changes_at",
                schema: "auth",
                table: "role_permission_changes",
                column: "at");

            migrationBuilder.CreateIndex(
                name: "IX_role_permission_changes_role_at",
                schema: "auth",
                table: "role_permission_changes",
                columns: new[] { "role", "at" });

            Seed(migrationBuilder);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "account_requests",
                schema: "auth");

            migrationBuilder.DropTable(
                name: "doctor_verifications",
                schema: "auth");

            migrationBuilder.DropTable(
                name: "invitations",
                schema: "auth");

            migrationBuilder.DropTable(
                name: "org_applications",
                schema: "auth");

            migrationBuilder.DropTable(
                name: "role_permission_changes",
                schema: "auth");

            migrationBuilder.DropTable(
                name: "role_permissions",
                schema: "auth");

            migrationBuilder.DropTable(
                name: "user_consents",
                schema: "auth");

            migrationBuilder.DropTable(
                name: "user_settings",
                schema: "auth");

            migrationBuilder.DropTable(
                name: "roles",
                schema: "auth");

            migrationBuilder.DropIndex(
                name: "IX_decisions_actor_mo_code_recorded_at",
                schema: "journal",
                table: "decisions");

            migrationBuilder.DropIndex(
                name: "IX_audit_mo_code_at",
                schema: "journal",
                table: "audit");

            migrationBuilder.DropColumn(
                name: "actor_mo_code",
                schema: "journal",
                table: "decisions");

            migrationBuilder.DropColumn(
                name: "detail",
                schema: "journal",
                table: "audit");

            migrationBuilder.DropColumn(
                name: "mo_code",
                schema: "journal",
                table: "audit");

            migrationBuilder.DropSequence(
                name: "org_application_seq",
                schema: "auth");
        }
    }
}
