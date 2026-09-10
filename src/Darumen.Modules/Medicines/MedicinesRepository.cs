using Dapper;
using Darumen.Shared.Data;

namespace Darumen.Modules.Medicines;

public sealed class MedicinesRepository(IDbConnectionFactory db) : IMedicinesRepository
{
    public async Task<IReadOnlyList<RxWeek>> WeeksAsync(string mnnId, int weeks, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        var rows = await connection.QueryAsync<RxWeek>(new CommandDefinition(
            """
            SELECT week AS Week, issued AS Issued, fulfilled AS Fulfilled, fulfilled_14d AS Fulfilled14d, fill_days_p50 AS FillDaysP50, fill_days_p90 AS FillDaysP90
            FROM gold.rx_weekly WHERE drug_mnn_id = @mnnId ORDER BY week DESC LIMIT @weeks
            """,
            new { mnnId, weeks }, cancellationToken: cancellationToken));
        return rows.OrderBy(r => r.Week).ToList();
    }

    public async Task<IReadOnlyList<RxMonth>> MonthsAsync(string nosologyId, int months, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        var rows = await connection.QueryAsync<RxMonth>(new CommandDefinition(
            """
            SELECT month AS Month, category_id AS CategoryId, issued AS Issued, fulfilled AS Fulfilled, fulfilled_14d AS Fulfilled14d,
                   fill_days_p50 AS FillDaysP50, fill_days_p90 AS FillDaysP90
            FROM gold.rx_nosology_monthly WHERE nosology_id = @nosologyId ORDER BY month DESC LIMIT @months
            """,
            new { nosologyId, months }, cancellationToken: cancellationToken));
        return rows.OrderBy(r => r.Month).ToList();
    }

    public async Task<IReadOnlyList<DrugProgram>> ProgramsAsync(string nosologyId, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        var rows = await connection.QueryAsync<DrugProgram>(new CommandDefinition(
            """
            SELECT program_id AS ProgramId, category_id AS CategoryId, active_specs AS ActiveSpecs, products AS Products, unit_price_p50 AS UnitPriceP50
            FROM gold.drug_programs WHERE nosology_id = @nosologyId ORDER BY active_specs DESC
            """,
            new { nosologyId }, cancellationToken: cancellationToken));
        return rows.ToList();
    }

    public async Task<IReadOnlyList<NosologyDto>> NosologiesAsync(int limit, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        var rows = await connection.QueryAsync<NosologyDto>(new CommandDefinition(
            """
            SELECT nosology_id AS NosologyId, min(category_id) AS CategoryId, sum(issued_12m) AS Issued12m, sum(fulfilled_12m) AS Fulfilled12m, count(DISTINCT drug_mnn_id) AS MnnCount
            FROM gold.rx_mnn WHERE nosology_id <> 'unknown' GROUP BY nosology_id ORDER BY sum(issued_12m) DESC LIMIT @limit
            """,
            new { limit }, cancellationToken: cancellationToken));
        return rows.ToList();
    }

    public async Task<IReadOnlyList<MnnDto>> MnnAsync(string nosologyId, int limit, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        var rows = await connection.QueryAsync<MnnDto>(new CommandDefinition(
            """
            SELECT drug_mnn_id AS MnnId, nosology_id AS NosologyId, category_id AS CategoryId, issued_12m AS Issued12m, fulfilled_12m AS Fulfilled12m, fill_days_p50 AS FillDaysP50
            FROM gold.rx_mnn WHERE nosology_id = @nosologyId AND drug_mnn_id <> 'unknown' ORDER BY issued_12m DESC LIMIT @limit
            """,
            new { nosologyId, limit }, cancellationToken: cancellationToken));
        return rows.ToList();
    }
}
