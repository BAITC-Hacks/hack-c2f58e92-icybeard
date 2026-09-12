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

    public async Task<IReadOnlyList<OrganizationItemDto>> OrganizationsAsync(string? regionKato, string? query, string? profileCode, int limit, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        var rows = await connection.QueryAsync<OrganizationItemDto>(new CommandDefinition(
            """
            SELECT r.mo_code AS MoCode, r.name_canonical AS Name, r.region_kato AS RegionKato, r.mo_type AS MoType, r.size_bucket AS SizeBucket, r.lat AS Lat, r.lon AS Lon
            FROM refdata.mo_registry r
            LEFT JOIN gold.queue_state s ON @profileCode IS NOT NULL AND s.mo_code = r.mo_code AND s.profile_code = @profileCode
            WHERE (@regionKato IS NULL OR r.region_kato = @regionKato)
              AND (@query IS NULL OR r.name_canonical ILIKE '%' || @query || '%' OR r.mo_code = @query)
              AND (@profileCode IS NULL OR s.mo_code IS NOT NULL)
            ORDER BY s.queue_len DESC NULLS LAST, r.referrals_in DESC NULLS LAST, r.mo_code
            LIMIT @limit
            """,
            new { regionKato, query, profileCode, limit }, cancellationToken: cancellationToken));
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

    public async Task<IReadOnlyList<SeasonalityDto>> SeasonalityAsync(CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        try
        {
            var rows = await connection.QueryAsync<SeasonalityDto>(new CommandDefinition(
                """
                SELECT series_id AS SeriesId, month AS Month, multiplier AS Multiplier, title AS Title,
                       source AS Source, source_year AS SourceYear, window_label AS WindowLabel
                FROM refdata.seasonality ORDER BY series_id, month
                """,
                cancellationToken: cancellationToken));
            return rows.ToList();
        }
        catch (Npgsql.PostgresException e) when (e.SqlState == "42P01")
        {
            return []; // таблица появится после make publish; до этого сезонного ориентира просто нет
        }
    }

    private sealed record RegionRow(string RegionKato, string NameRu, string? NameKz, string Capital, double? Lat, double? Lon, int? PopulationThousands);
}
