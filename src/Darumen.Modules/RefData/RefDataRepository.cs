using Dapper;
using Darumen.Shared.Api;
using Darumen.Shared.Data;

namespace Darumen.Modules.RefData;

public sealed class RefDataRepository(IDbConnectionFactory db) : IRefDataRepository
{
    public async Task<IReadOnlyList<RegionDto>> RegionsAsync(string lang, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        var rows = await connection.QueryAsync<RegionRow>(new CommandDefinition(
            "SELECT region_kato AS RegionKato, name_ru AS NameRu, name_kz AS NameKz, capital AS Capital, lat AS Lat, lon AS Lon, population_thousands AS PopulationThousands FROM refdata.regions ORDER BY region_kato",
            cancellationToken: cancellationToken));
        return rows.Select(r => new RegionDto(r.RegionKato, lang == Locale.Kk ? r.NameKz ?? r.NameRu : r.NameRu, r.Capital, r.Lat, r.Lon, r.PopulationThousands)).ToList();
    }

    public async Task<IReadOnlyList<OrganizationItemDto>> OrganizationsAsync(string? regionKato, string? query, int limit, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        var rows = await connection.QueryAsync<OrganizationItemDto>(new CommandDefinition(
            """
            SELECT mo_code AS MoCode, name_canonical AS Name, region_kato AS RegionKato, mo_type AS MoType, size_bucket AS SizeBucket, lat AS Lat, lon AS Lon
            FROM refdata.mo_registry
            WHERE (@regionKato IS NULL OR region_kato = @regionKato)
              AND (@query IS NULL OR name_canonical ILIKE '%' || @query || '%' OR mo_code = @query)
            ORDER BY referrals_in DESC NULLS LAST, mo_code
            LIMIT @limit
            """,
            new { regionKato, query, limit }, cancellationToken: cancellationToken));
        return rows.ToList();
    }

    public async Task<IReadOnlyList<ProfileDto>> ProfilesAsync(CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        var rows = await connection.QueryAsync<ProfileDto>(new CommandDefinition(
            "SELECT profile_code AS ProfileCode, name_ru AS Name, is_day_hospital AS IsDayHospital, referrals AS Referrals FROM refdata.bed_profiles ORDER BY referrals DESC",
            cancellationToken: cancellationToken));
        return rows.ToList();
    }

    private sealed record RegionRow(string RegionKato, string NameRu, string? NameKz, string Capital, double? Lat, double? Lon, int? PopulationThousands);
}
