namespace Darumen.Modules.RefData;

public interface IRefDataRepository
{
    Task<IReadOnlyList<RegionDto>> RegionsAsync(string lang, CancellationToken cancellationToken);

    /// <summary>С profileCode остаются только организации с очередью по этому профилю, сначала самые загруженные.</summary>
    Task<IReadOnlyList<OrganizationItemDto>> OrganizationsAsync(string? regionKato, string? query, string? profileCode, int limit, CancellationToken cancellationToken);

    Task<IReadOnlyList<ProfileDto>> ProfilesAsync(CancellationToken cancellationToken);

    Task<IReadOnlyList<SeasonalityDto>> SeasonalityAsync(CancellationToken cancellationToken);
}
