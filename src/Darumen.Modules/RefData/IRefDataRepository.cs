namespace Darumen.Modules.RefData;

public interface IRefDataRepository
{
    Task<IReadOnlyList<RegionDto>> RegionsAsync(string lang, CancellationToken cancellationToken);

    /// <summary>С profileCode остаются только организации с очередью по этому профилю, сначала самые загруженные.</summary>
    Task<IReadOnlyList<OrganizationItemDto>> OrganizationsAsync(string? regionKato, string? query, string? profileCode, int limit, CancellationToken cancellationToken);

    Task<IReadOnlyList<ProfileDto>> ProfilesAsync(CancellationToken cancellationToken);

    Task<IReadOnlyList<SeasonalityDto>> SeasonalityAsync(CancellationToken cancellationToken);

    /// <summary>Оценки охвата WUENIC; пусто, пока витрина не опубликована.</summary>
    Task<IReadOnlyList<VaccinationBenchmarkDto>> VaccinationAsync(CancellationToken cancellationToken);

    /// <summary>Коды планов вакцинации, встречающиеся в данных (для переключателя потока на странице региона);
    /// пусто, пока витрина не опубликована.</summary>
    Task<IReadOnlyList<string>> VaccinationPlansAsync(string? regionKato, CancellationToken cancellationToken);
}
