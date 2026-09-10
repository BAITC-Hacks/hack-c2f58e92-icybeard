namespace Darumen.Modules.Queue;

public interface IQueueStateRepository
{
    Task<QueueSnapshotDto?> SnapshotAsync(string moCode, string profileCode, CancellationToken cancellationToken);

    Task<OrganizationSeriesDto?> SeriesAsync(string moCode, string profileCode, int days, CancellationToken cancellationToken);
}
