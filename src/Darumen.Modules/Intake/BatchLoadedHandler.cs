using Darumen.Contracts.V1;
using Darumen.Migrations;

namespace Darumen.Modules.Intake;

/// <summary>Обработчик Wolverine для intake.batch.loaded из Python: upsert по batch_id, поэтому повторная доставка безвредна.</summary>
public static class BatchLoadedHandler
{
    public const string LoadedStatus = "loaded";

    public static async Task Handle(BatchLoaded @event, DarumenDbContext db, CancellationToken cancellationToken)
    {
        var batch = await db.IntakeBatches.FindAsync([@event.BatchId], cancellationToken);
        if (batch is null)
        {
            batch = new IntakeBatch { BatchId = @event.BatchId };
            db.IntakeBatches.Add(batch);
        }

        batch.Dataset = @event.Dataset;
        batch.Status = LoadedStatus;
        batch.RowsLoaded = @event.RowsLoaded;
        batch.RowsQuarantined = @event.RowsQuarantined;
        batch.Partitions = string.Join(',', @event.Partitions);
        batch.EventId = @event.Meta?.EventId ?? string.Empty;
        batch.OccurredAt = @event.Meta?.OccurredAt?.ToDateTime();
        batch.ReceivedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(cancellationToken);
    }
}
