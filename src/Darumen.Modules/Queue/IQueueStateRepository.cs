namespace Darumen.Modules.Queue;

public interface IQueueStateRepository
{
    Task<QueueSnapshotDto?> SnapshotAsync(string moCode, string profileCode, CancellationToken cancellationToken);

    Task<OrganizationSeriesDto?> SeriesAsync(string moCode, string profileCode, int days, CancellationToken cancellationToken);

    /// <summary>Организации с нагрузкой (поток / госпитализации) больше 1, самые загруженные — первыми.</summary>
    Task<IReadOnlyList<OverloadedOrganizationDto>> OverloadedAsync(string? regionKato, string? profileCode, int limit, CancellationToken cancellationToken);
}
