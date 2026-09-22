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
            SELECT r.mo_code AS MoCode, r.name_canonical AS Name, r.region_kato AS RegionKato, r.mo_type AS MoType, r.size_bucket AS SizeBucket, r.lat AS Lat, r.lon AS Lon, r.name_key AS MoKey
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
                SELECT series_id AS SeriesId, month::int AS Month, multiplier AS Multiplier, title AS Title,
                       source AS Source, source_year::int AS SourceYear, window_label AS WindowLabel
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

    public async Task<IReadOnlyList<VaccinationBenchmarkDto>> VaccinationAsync(CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        try
        {
            var rows = await connection.QueryAsync<VaccinationBenchmarkDto>(new CommandDefinition(
                """
                SELECT vaccine AS Vaccine, title_ru AS TitleRu, year::int AS Year, coverage_pct AS CoveragePct,
                       source AS Source, note AS Note
                FROM refdata.vaccination_wuenic ORDER BY vaccine, year
                """,
                cancellationToken: cancellationToken));
            return rows.ToList();
        }
        catch (Npgsql.PostgresException e) when (e.SqlState == "42P01")
        {
            return []; // витрина появится после make publish
        }
    }

    /// <summary>Коды планов вакцинации, встречающиеся в gold.vac_monthly — переключатель потока на странице региона
    /// использует их как второй ключ сущности (entity[vaccinationPlan]) для /api/v1/forecast/vac_monthly.</summary>
    public async Task<IReadOnlyList<string>> VaccinationPlansAsync(string? regionKato, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        try
        {
            var rows = await connection.QueryAsync<string>(new CommandDefinition(
                "SELECT DISTINCT vaccination_plan FROM gold.vac_monthly WHERE vaccination_plan IS NOT NULL AND (@regionKato IS NULL OR region_kato = @regionKato) ORDER BY 1",
                new { regionKato }, cancellationToken: cancellationToken));
            return rows.ToList();
        }
        catch (Npgsql.PostgresException e) when (e.SqlState == "42P01")
        {
            return []; // витрина появится после make publish
        }
    }

    public async Task<RouteStandardDto> RouteStandardAsync(string lang, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        var kk = lang == Locale.Kk;
        try
        {
            var stages = (await connection.QueryAsync<StageRow>(new CommandDefinition(
                """
                SELECT code AS Code, stage_order::int AS StageOrder, title_ru AS TitleRu, title_kk AS TitleKk, norm_ru AS NormRu, norm_kk AS NormKk,
                       norm_working_days::int AS NormWorkingDays, reschedule_max_days::int AS RescheduleMaxDays, no_show_days::int AS NoShowDays,
                       source AS Source, source_url AS SourceUrl, source_date AS SourceDate
                FROM refdata.route_stages ORDER BY stage_order, code
                """, cancellationToken: cancellationToken))).ToList();
            var reasons = (await connection.QueryAsync<TitledRow>(new CommandDefinition(
                "SELECT code AS Code, title_ru AS TitleRu, title_kk AS TitleKk FROM refdata.route_refusal_reasons ORDER BY code",
                cancellationToken: cancellationToken))).ToList();
            var checklist = (await connection.QueryAsync<ChecklistRow>(new CommandDefinition(
                """
                SELECT code AS Code, title_ru AS TitleRu, title_kk AS TitleKk, validity_days::int AS ValidityDays,
                       validity_label_ru AS ValidityLabelRu, validity_label_kk AS ValidityLabelKk
                FROM refdata.route_checklist ORDER BY validity_days, code
                """, cancellationToken: cancellationToken))).ToList();
            var benchmarks = (await connection.QueryAsync<BenchmarkRow>(new CommandDefinition(
                """
                SELECT code AS Code, value::float8 AS Value, unit AS Unit, title_ru AS TitleRu, title_kk AS TitleKk, source AS Source, source_date AS SourceDate
                FROM refdata.route_benchmarks ORDER BY code
                """, cancellationToken: cancellationToken))).ToList();
            if (stages.Count == 0)
            {
                return RouteStandardDto.Empty;
            }

            return new RouteStandardDto(
                new RouteStandardMetaDto(stages[0].Source, stages[0].SourceUrl, stages[0].SourceDate),
                true,
                stages.Select(s => new RouteStageDefDto(s.Code, s.StageOrder, Pick(kk, s.TitleRu, s.TitleKk), Pick(kk, s.NormRu, s.NormKk), s.NormWorkingDays, s.RescheduleMaxDays, s.NoShowDays)).ToList(),
                reasons.Select(r => new RouteRefusalReasonDto(r.Code, Pick(kk, r.TitleRu, r.TitleKk))).ToList(),
                checklist.Select(c => new RouteChecklistDefDto(c.Code, Pick(kk, c.TitleRu, c.TitleKk), c.ValidityDays, Pick(kk, c.ValidityLabelRu, c.ValidityLabelKk))).ToList(),
                benchmarks.Select(b => new RouteBenchmarkDto(b.Code, b.Value, b.Unit, Pick(kk, b.TitleRu, b.TitleKk), b.Source, b.SourceDate)).ToList());
        }
        catch (Npgsql.PostgresException e) when (e.SqlState == "42P01")
        {
            return RouteStandardDto.Empty; // витрины refdata.route_* появятся после make publish
        }
    }

    private static string Pick(bool kk, string ru, string? kkText) => kk && !string.IsNullOrWhiteSpace(kkText) ? kkText : ru;

    private sealed record RegionRow(string RegionKato, string NameRu, string? NameKz, string Capital, double? Lat, double? Lon, int? PopulationThousands);

    private sealed record StageRow(
        string Code, int StageOrder, string TitleRu, string? TitleKk, string NormRu, string? NormKk, int? NormWorkingDays, int? RescheduleMaxDays,
        int? NoShowDays, string Source, string SourceUrl, string SourceDate);

    private sealed record TitledRow(string Code, string TitleRu, string? TitleKk);

    private sealed record ChecklistRow(string Code, string TitleRu, string? TitleKk, int ValidityDays, string ValidityLabelRu, string? ValidityLabelKk);

    private sealed record BenchmarkRow(string Code, double Value, string Unit, string TitleRu, string? TitleKk, string Source, string SourceDate);
}
