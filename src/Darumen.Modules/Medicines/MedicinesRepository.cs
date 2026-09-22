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
            SELECT nosology_id AS NosologyId, min(category_id) AS CategoryId, sum(issued_12m)::bigint AS Issued12m, sum(fulfilled_12m)::bigint AS Fulfilled12m, count(DISTINCT drug_mnn_id)::bigint AS MnnCount
            FROM gold.rx_mnn WHERE nosology_id <> 'unknown' GROUP BY nosology_id ORDER BY sum(issued_12m) DESC LIMIT @limit
            """,
            new { limit }, cancellationToken: cancellationToken));
        return rows.ToList();
    }

    public async Task<IReadOnlyList<MnnDto>> MnnAsync(string nosologyId, int limit, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        // gold.rx_mnn: одна строка на (drug_mnn_id, nosology_id, category_id) — внутри одной нозологии МНН встречается
        // в нескольких категориях (например, МНН 286 при нозологии 110 — категории 63, 64, 68). Список для выбора
        // должен содержать каждый МНН один раз: объём суммируем по категориям, категорию показываем самую массовую
        // (DISTINCT ON), как в TopMnnAsync. Иначе выпадающий список клиента получает дубликаты значений и падает.
        var rows = await connection.QueryAsync<MnnDto>(new CommandDefinition(
            """
            WITH totals AS (
                SELECT drug_mnn_id, sum(issued_12m)::bigint AS issued_12m, sum(fulfilled_12m)::bigint AS fulfilled_12m,
                       avg(fill_days_p50) AS fill_days_p50
                FROM gold.rx_mnn WHERE nosology_id = @nosologyId AND drug_mnn_id <> 'unknown' GROUP BY drug_mnn_id
            ),
            top_category AS (
                SELECT DISTINCT ON (drug_mnn_id) drug_mnn_id, category_id
                FROM gold.rx_mnn WHERE nosology_id = @nosologyId AND drug_mnn_id <> 'unknown' ORDER BY drug_mnn_id, issued_12m DESC
            )
            SELECT t.drug_mnn_id AS MnnId, @nosologyId AS NosologyId, c.category_id AS CategoryId,
                   t.issued_12m AS Issued12m, t.fulfilled_12m AS Fulfilled12m, t.fill_days_p50 AS FillDaysP50
            FROM totals t JOIN top_category c USING (drug_mnn_id)
            ORDER BY t.issued_12m DESC LIMIT @limit
            """,
            new { nosologyId, limit }, cancellationToken: cancellationToken));
        return rows.ToList();
    }

    public async Task<IReadOnlyList<MnnDto>> TopMnnAsync(int limit, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        // gold.rx_mnn: одна строка на (drug_mnn_id, nosology_id, category_id) — МНН выписывается при нескольких
        // нозологиях. Для национального топа сначала суммируем объём по МНН по всем нозологиям, а нозологию и
        // категорию для отображения берём ту, где у МНН больше всего рецептов (DISTINCT ON, как самая частая пара).
        var rows = await connection.QueryAsync<MnnDto>(new CommandDefinition(
            """
            WITH totals AS (
                SELECT drug_mnn_id, sum(issued_12m)::bigint AS issued_12m, sum(fulfilled_12m)::bigint AS fulfilled_12m,
                       avg(fill_days_p50) AS fill_days_p50
                FROM gold.rx_mnn WHERE drug_mnn_id <> 'unknown' GROUP BY drug_mnn_id
            ),
            top_nosology AS (
                SELECT DISTINCT ON (drug_mnn_id) drug_mnn_id, nosology_id, category_id
                FROM gold.rx_mnn WHERE drug_mnn_id <> 'unknown' ORDER BY drug_mnn_id, issued_12m DESC
            )
            SELECT t.drug_mnn_id AS MnnId, n.nosology_id AS NosologyId, n.category_id AS CategoryId,
                   t.issued_12m AS Issued12m, t.fulfilled_12m AS Fulfilled12m, t.fill_days_p50 AS FillDaysP50
            FROM totals t JOIN top_nosology n USING (drug_mnn_id)
            ORDER BY t.issued_12m DESC LIMIT @limit
            """,
            new { limit }, cancellationToken: cancellationToken));
        return rows.ToList();
    }

    public async Task<double?> FillDaysP50ModelAsync(string mnnId, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        try
        {
            return await connection.QuerySingleOrDefaultAsync<double?>(new CommandDefinition(
                "SELECT fill_days_p50_model FROM gold.rx_fill_by_mnn WHERE drug_mnn_id = @mnnId",
                new { mnnId }, cancellationToken: cancellationToken));
        }
        catch (Npgsql.PostgresException e) when (e.SqlState == "42P01")
        {
            // витрина gold.rx_fill_by_mnn ещё не опубликована (5.7 A) — проверка рецепта живёт без p50 модели
            return null;
        }
    }

    public async Task<PeerFulfillmentDto?> PeerFulfillmentAsync(string mnnId, string categoryId, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        var row = await connection.QuerySingleOrDefaultAsync<PeerFulfillmentDto>(new CommandDefinition(
            """
            SELECT coalesce(sum(fulfilled_12m)::float8 / nullif(sum(issued_12m), 0), 0) AS Ratio, count(*)::bigint AS PeerMnnCount,
                   coalesce(sum(issued_12m), 0)::bigint AS IssuedRecent, coalesce(sum(fulfilled_12m), 0)::bigint AS FulfilledRecent
            FROM gold.rx_mnn WHERE category_id = @categoryId AND drug_mnn_id <> @mnnId AND drug_mnn_id <> 'unknown'
            """,
            new { mnnId, categoryId }, cancellationToken: cancellationToken));
        return row is null || row.PeerMnnCount == 0 ? null : row;
    }
}
