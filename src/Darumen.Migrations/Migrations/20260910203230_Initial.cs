using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Darumen.Migrations.Migrations
{
    /// <inheritdoc />
    public partial class Initial : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.EnsureSchema(
                name: "journal");

            migrationBuilder.CreateTable(
                name: "anomaly_acks",
                schema: "journal",
                columns: table => new
                {
                    anomaly_id = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    status = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                    comment = table.Column<string>(type: "text", nullable: true),
                    actor = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    acked_at = table.Column<DateTime>(type: "timestamptz", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_anomaly_acks", x => x.anomaly_id);
                });

            migrationBuilder.CreateTable(
                name: "decisions",
                schema: "journal",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    actor = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    role = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                    subject = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    subject_id = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    recommended = table.Column<string>(type: "jsonb", nullable: true),
                    chosen = table.Column<string>(type: "jsonb", nullable: true),
                    reason = table.Column<string>(type: "text", nullable: true),
                    idempotency_key = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    recorded_at = table.Column<DateTime>(type: "timestamptz", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_decisions", x => x.id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_decisions_actor_recorded_at",
                schema: "journal",
                table: "decisions",
                columns: new[] { "actor", "recorded_at" });

            migrationBuilder.CreateIndex(
                name: "IX_decisions_idempotency_key",
                schema: "journal",
                table: "decisions",
                column: "idempotency_key",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_decisions_subject_subject_id",
                schema: "journal",
                table: "decisions",
                columns: new[] { "subject", "subject_id" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "anomaly_acks",
                schema: "journal");

            migrationBuilder.DropTable(
                name: "decisions",
                schema: "journal");
        }
    }
}
