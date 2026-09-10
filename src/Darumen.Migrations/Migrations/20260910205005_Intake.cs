using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Darumen.Migrations.Migrations
{
    /// <inheritdoc />
    public partial class Intake : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.EnsureSchema(
                name: "intake");

            migrationBuilder.CreateTable(
                name: "batches",
                schema: "intake",
                columns: table => new
                {
                    batch_id = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    dataset = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    status = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                    rows_loaded = table.Column<long>(type: "bigint", nullable: false),
                    rows_quarantined = table.Column<long>(type: "bigint", nullable: false),
                    partitions = table.Column<string>(type: "text", nullable: false),
                    event_id = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    occurred_at = table.Column<DateTime>(type: "timestamptz", nullable: true),
                    received_at = table.Column<DateTime>(type: "timestamptz", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_batches", x => x.batch_id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_batches_dataset_received_at",
                schema: "intake",
                table: "batches",
                columns: new[] { "dataset", "received_at" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "batches",
                schema: "intake");
        }
    }
}
