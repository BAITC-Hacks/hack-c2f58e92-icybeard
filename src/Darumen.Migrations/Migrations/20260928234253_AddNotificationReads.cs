using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Darumen.Migrations.Migrations
{
    /// <inheritdoc />
    public partial class AddNotificationReads : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "notification_reads",
                schema: "journal",
                columns: table => new
                {
                    actor = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    decision_id = table.Column<Guid>(type: "uuid", nullable: false),
                    kind = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                    read_at = table.Column<DateTime>(type: "timestamptz", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_notification_reads", x => new { x.actor, x.decision_id, x.kind });
                });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "notification_reads",
                schema: "journal");
        }
    }
}
