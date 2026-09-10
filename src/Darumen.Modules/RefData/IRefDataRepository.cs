namespace Darumen.Modules.RefData;

public interface IRefDataRepository
{
    Task<IReadOnlyList<RegionDto>> RegionsAsync(string lang, CancellationToken cancellationToken);

    Task<IReadOnlyList<OrganizationItemDto>> OrganizationsAsync(string? regionKato, string? query, int limit, CancellationToken cancellationToken);

    Task<IReadOnlyList<ProfileDto>> ProfilesAsync(CancellationToken cancellationToken);
}
