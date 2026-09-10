using Microsoft.EntityFrameworkCore;

namespace Darumen.Migrations;

/// <summary>Схема, которой владеет приложение: журнал решений и подтверждения сигналов.
/// Витрины gold и refdata создаёт публикация из lakehouse, они здесь не описаны.</summary>
public sealed class DarumenDbContext(DbContextOptions<DarumenDbContext> options) : DbContext(options)
{
    public const string Schema = "journal";

    public DbSet<Decision> Decisions => Set<Decision>();

    public DbSet<AnomalyAck> AnomalyAcks => Set<AnomalyAck>();

    public DbSet<IntakeBatch> IntakeBatches => Set<IntakeBatch>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.HasDefaultSchema(Schema);

        modelBuilder.Entity<Decision>(e =>
        {
            e.ToTable("decisions");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasColumnName("id");
            e.Property(x => x.Actor).HasColumnName("actor").HasMaxLength(200);
            e.Property(x => x.Role).HasColumnName("role").HasMaxLength(50);
            e.Property(x => x.Subject).HasColumnName("subject").HasMaxLength(100);
            e.Property(x => x.SubjectId).HasColumnName("subject_id").HasMaxLength(200);
            e.Property(x => x.Recommended).HasColumnName("recommended").HasColumnType("jsonb");
            e.Property(x => x.Chosen).HasColumnName("chosen").HasColumnType("jsonb");
            e.Property(x => x.Reason).HasColumnName("reason");
            e.Property(x => x.IdempotencyKey).HasColumnName("idempotency_key").HasMaxLength(200);
            e.Property(x => x.RecordedAt).HasColumnName("recorded_at").HasColumnType("timestamptz");
            e.HasIndex(x => x.IdempotencyKey).IsUnique();
            e.HasIndex(x => new { x.Actor, x.RecordedAt });
            e.HasIndex(x => new { x.Subject, x.SubjectId });
        });

        modelBuilder.Entity<AnomalyAck>(e =>
        {
            e.ToTable("anomaly_acks");
            e.HasKey(x => x.AnomalyId);
            e.Property(x => x.AnomalyId).HasColumnName("anomaly_id").HasMaxLength(64);
            e.Property(x => x.Status).HasColumnName("status").HasMaxLength(50);
            e.Property(x => x.Comment).HasColumnName("comment");
            e.Property(x => x.Actor).HasColumnName("actor").HasMaxLength(200);
            e.Property(x => x.AckedAt).HasColumnName("acked_at").HasColumnType("timestamptz");
        });

        modelBuilder.Entity<IntakeBatch>(e =>
        {
            e.ToTable("batches", "intake");
            e.HasKey(x => x.BatchId);
            e.Property(x => x.BatchId).HasColumnName("batch_id").HasMaxLength(200);
            e.Property(x => x.Dataset).HasColumnName("dataset").HasMaxLength(100);
            e.Property(x => x.Status).HasColumnName("status").HasMaxLength(50);
            e.Property(x => x.RowsLoaded).HasColumnName("rows_loaded");
            e.Property(x => x.RowsQuarantined).HasColumnName("rows_quarantined");
            e.Property(x => x.Partitions).HasColumnName("partitions");
            e.Property(x => x.EventId).HasColumnName("event_id").HasMaxLength(64);
            e.Property(x => x.OccurredAt).HasColumnName("occurred_at").HasColumnType("timestamptz");
            e.Property(x => x.ReceivedAt).HasColumnName("received_at").HasColumnType("timestamptz");
            e.HasIndex(x => new { x.Dataset, x.ReceivedAt });
        });
    }
}

public sealed class Decision
{
    public Guid Id { get; set; }

    public string Actor { get; set; } = string.Empty;

    public string Role { get; set; } = string.Empty;

    public string Subject { get; set; } = string.Empty;

    public string SubjectId { get; set; } = string.Empty;

    public string? Recommended { get; set; }

    public string? Chosen { get; set; }

    public string? Reason { get; set; }

    public string? IdempotencyKey { get; set; }

    public DateTime RecordedAt { get; set; }
}

public sealed class AnomalyAck
{
    public string AnomalyId { get; set; } = string.Empty;

    public string Status { get; set; } = string.Empty;

    public string? Comment { get; set; }

    public string Actor { get; set; } = string.Empty;

    public DateTime AckedAt { get; set; }
}

/// <summary>Партия загрузки из Data Intake Fabric, приходит событием intake.batch.loaded из Python.</summary>
public sealed class IntakeBatch
{
    public string BatchId { get; set; } = string.Empty;

    public string Dataset { get; set; } = string.Empty;

    public string Status { get; set; } = string.Empty;

    public long RowsLoaded { get; set; }

    public long RowsQuarantined { get; set; }

    public string Partitions { get; set; } = string.Empty;

    public string EventId { get; set; } = string.Empty;

    public DateTime? OccurredAt { get; set; }

    public DateTime ReceivedAt { get; set; }
}
