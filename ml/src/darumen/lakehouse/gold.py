"""Gold tables (docs/gold-schemas.md), written as Parquet under <lakehouse>/gold.

    queue_daily          queue state per organisation, profile and day
    throughput_4w        28-day trailing throughput, refusal rate and realised waits (window strictly before the day)
    er_visits_daily      ER visits without admission per organisation and day
    admissions_monthly   discharges per region, profile and month (needs silver.ersb_cases)
    vac_monthly          vaccination doses per region, organisation, plan and month (needs silver.vac_facts)
    features_wait        training table for the waiting-time models, leak-free by construction
    rx_weekly            prescriptions issued and fulfilled per week and MNN, fill-time quantiles (needs silver.rx_*)
    rx_nosology_monthly  the same per month, nosology and category
    drug_programs        active drug specifications per nosology, category and programme (needs silver.drug_specs)
    staffing_by_region   sum of staffing position rates per region, snapshot (needs silver.staffing)
    rx_mnn               MNN per nosology with volumes of the last 12 months of data (needs silver.rx_*)

Every builder is a pure function of silver + refdata and overwrites its table, so rebuilding is idempotent.
"""
from __future__ import annotations

from collections.abc import Callable
from pathlib import Path

import duckdb

from ..intake.normalize import register_udfs
from ..intake.pipeline import Lakehouse

HORIZON_DAYS = 120          # how far past the last registration the queue is tracked
WINDOW_DAYS = 28
HOLDOUT_MO_BUCKETS = 10     # 1 of 10 organisations (by hash) is held out for test_mo
TEST_TIME_START = "2025-03-01"
# последние две недели февраля — только для ранней остановки обучения (early stopping), не в train и не в
# March-отчёте: раньше валидацию брали сэмплом из test_time самого отчёта, отчёт был не совсем честным
VALID_START = "2025-02-15"


def _sql_path(path: Path) -> str:
    return "'" + str(path).replace("'", "''") + "'"


def _has_silver(lake: Lakehouse, dataset: str) -> bool:
    return lake.silver(dataset).exists() and any(lake.silver(dataset).rglob("*.parquet"))


def _refdata(lake: Lakehouse, name: str) -> Path | None:
    path = lake.root / "refdata" / f"{name}.parquet"
    return path if path.exists() else None


def _write(con: duckdb.DuckDBPyConnection, out: Path, name: str, sql: str) -> int:
    out.mkdir(parents=True, exist_ok=True)
    con.execute(f"CREATE OR REPLACE TABLE {name} AS {sql}")
    con.execute(f"COPY {name} TO {_sql_path(out / f'{name}.parquet')} (FORMAT PARQUET)")
    return int(con.execute(f"SELECT count(*) FROM {name}").fetchone()[0])


def _prepare(con: duckdb.DuckDBPyConnection, lake: Lakehouse) -> None:
    register_udfs(con)
    con.execute(f"CREATE OR REPLACE VIEW referrals AS SELECT * FROM {lake.silver_sql('bg_referrals')}")
    registry = _refdata(lake, "mo_registry")
    if registry:
        con.execute(f"CREATE OR REPLACE VIEW mo_registry AS SELECT * FROM read_parquet({_sql_path(registry)})")
    else:
        con.execute("CREATE OR REPLACE VIEW mo_registry AS SELECT mo_code, mode(region_kato) AS region_kato, 'other' AS mo_type, 'M' AS size_bucket, NULL::VARCHAR AS peer_group_id FROM referrals GROUP BY mo_code")
    index = _refdata(lake, "mo_name_index")
    if index:
        con.execute(f"CREATE OR REPLACE VIEW mo_name_index AS SELECT * FROM read_parquet({_sql_path(index)})")
    else:
        con.execute("CREATE OR REPLACE VIEW mo_name_index AS SELECT NULL::VARCHAR AS region_kato, NULL::VARCHAR AS name_key, NULL::VARCHAR AS mo_code WHERE false")


def build_queue_daily(con: duckdb.DuckDBPyConnection, lake: Lakehouse, out: Path) -> int:
    return _write(con, out, "queue_daily", f"""
        WITH r AS (
            SELECT mo_code, profile_code, registration_dt::DATE AS reg_day,
                   hospitalization_dt::DATE AS hosp_day, refusal_dt::DATE AS ref_day,
                   coalesce(hospitalization_dt::DATE, refusal_dt::DATE) AS out_day
            FROM referrals),
        bounds AS (
            SELECT (min(reg_day) - INTERVAL 1 DAY)::DATE AS d0,  -- one day before the cohort starts, so "yesterday" exists
                   least(greatest(max(reg_day), max(out_day)), max(reg_day) + INTERVAL {HORIZON_DAYS} DAY)::DATE AS d1
            FROM r),
        cal AS (SELECT unnest(generate_series(d0, d1, INTERVAL 1 DAY))::DATE AS day FROM bounds),
        groups AS (SELECT DISTINCT mo_code, profile_code FROM r),
        spine AS (SELECT g.mo_code, g.profile_code, c.day FROM groups g CROSS JOIN cal c),
        reg AS (SELECT mo_code, profile_code, reg_day AS day, count(*) AS n FROM r GROUP BY ALL),
        hos AS (SELECT mo_code, profile_code, hosp_day AS day, count(*) AS n FROM r WHERE hosp_day IS NOT NULL GROUP BY ALL),
        ref AS (SELECT mo_code, profile_code, ref_day AS day, count(*) AS n FROM r WHERE ref_day IS NOT NULL GROUP BY ALL),
        open AS (
            SELECT s.mo_code, s.profile_code, s.day, count(*) AS queue_len,
                   quantile_cont(date_diff('day', r.reg_day, s.day), 0.5) AS queue_age_p50,
                   quantile_cont(date_diff('day', r.reg_day, s.day), 0.9) AS queue_age_p90
            FROM spine s
            JOIN r ON r.mo_code = s.mo_code AND r.profile_code = s.profile_code
                  AND r.reg_day <= s.day AND (r.out_day IS NULL OR r.out_day > s.day)
            GROUP BY ALL)
        SELECT s.day, coalesce(m.region_kato, 'unknown') AS region_kato, s.mo_code, s.profile_code,
               coalesce(reg.n, 0) AS registered, coalesce(hos.n, 0) AS hospitalized, coalesce(ref.n, 0) AS refused,
               coalesce(o.queue_len, 0) AS queue_len, o.queue_age_p50, o.queue_age_p90
        FROM spine s
        LEFT JOIN reg USING (mo_code, profile_code, day)
        LEFT JOIN hos USING (mo_code, profile_code, day)
        LEFT JOIN ref USING (mo_code, profile_code, day)
        LEFT JOIN open o USING (mo_code, profile_code, day)
        LEFT JOIN mo_registry m ON m.mo_code = s.mo_code
        ORDER BY s.mo_code, s.profile_code, s.day""")


def build_throughput_4w(con: duckdb.DuckDBPyConnection, lake: Lakehouse, out: Path) -> int:
    return _write(con, out, "throughput_4w", f"""
        WITH daily AS (
            SELECT day, mo_code, profile_code,
                   sum(hospitalized) OVER w AS hospitalized_4w,
                   sum(registered) OVER w AS registered_4w,
                   sum(refused) OVER w AS refused_4w
            FROM queue_daily
            WINDOW w AS (PARTITION BY mo_code, profile_code ORDER BY day
                         RANGE BETWEEN INTERVAL {WINDOW_DAYS} DAY PRECEDING AND INTERVAL 1 DAY PRECEDING)),
        realised AS (
            -- waits of referrals hospitalised inside the window: known by `day`, no look-ahead
            SELECT d.day, d.mo_code, d.profile_code,
                   quantile_cont(r.wait_days, 0.5) AS wait_p50_4w, quantile_cont(r.wait_days, 0.9) AS wait_p90_4w
            FROM daily d
            JOIN referrals r ON r.mo_code = d.mo_code AND r.profile_code = d.profile_code
                 AND r.hospitalization_dt::DATE BETWEEN d.day - INTERVAL {WINDOW_DAYS} DAY AND d.day - INTERVAL 1 DAY
            GROUP BY ALL)
        SELECT d.day, d.mo_code, d.profile_code,
               coalesce(d.hospitalized_4w, 0)::BIGINT AS hospitalized_4w,
               coalesce(d.registered_4w, 0)::BIGINT AS registered_4w,
               coalesce(d.refused_4w, 0)::BIGINT AS refused_4w,
               coalesce(d.hospitalized_4w, 0) / {WINDOW_DAYS}.0 AS throughput_per_day,
               coalesce(d.refused_4w, 0) / nullif(coalesce(d.registered_4w, 0), 0) AS refusal_rate_4w,
               w.wait_p50_4w, w.wait_p90_4w
        FROM daily d LEFT JOIN realised w USING (day, mo_code, profile_code)
        ORDER BY d.mo_code, d.profile_code, d.day""")


def build_er_visits_daily(con: duckdb.DuckDBPyConnection, lake: Lakehouse, out: Path) -> int:
    if not _has_silver(lake, "bg_er_refusals"):
        return 0
    return _write(con, out, "er_visits_daily", f"""
        SELECT e.refuse_dt::DATE AS day, e.region_kato, e.org_in_key AS mo_key, i.mo_code,
               count(*) AS visits,
               avg((e.insured = 'Застрахован')::int) AS insured_share,
               mode(icd10_chapter(e.icd10_canon)) AS top_icd_chapter
        FROM {lake.silver_sql('bg_er_refusals')} e
        LEFT JOIN mo_name_index i ON i.region_kato = e.region_kato AND i.name_key = e.org_in_key
        GROUP BY ALL ORDER BY day, e.region_kato, mo_key""")


def build_admissions_monthly(con: duckdb.DuckDBPyConnection, lake: Lakehouse, out: Path) -> int:
    if not _has_silver(lake, "ersb_cases"):
        return 0
    profiles = _refdata(lake, "bed_profiles")
    profile_join = (f"LEFT JOIN read_parquet({_sql_path(profiles)}) p ON mo_name_key(p.name_ru) = mo_name_key(c.profile)"
                    if profiles else "LEFT JOIN (SELECT NULL::VARCHAR AS profile_code, NULL::VARCHAR AS name_ru WHERE false) p ON false")
    base = f"""
        SELECT date_trunc('month', c.p_outdate)::DATE AS month, c.region_kato,
               coalesce(p.profile_code, 'unknown') AS profile_code, c.medicine_organization_key AS mo_key,
               c.los_days, c.is_death
        FROM {lake.silver_sql('ersb_cases')} c {profile_join}"""
    rows = _write(con, out, "admissions_monthly", f"""
        SELECT month, region_kato, profile_code, count(*) AS cases, sum(coalesce(los_days, 0))::BIGINT AS bed_days,
               avg(los_days) AS los_mean, count(*) FILTER (WHERE is_death) AS deaths, count(DISTINCT mo_key) AS mo_count
        FROM ({base}) GROUP BY ALL ORDER BY month, region_kato, profile_code""")
    _write(con, out, "admissions_monthly_mo", f"""
        SELECT month, region_kato, mo_key, profile_code, count(*) AS cases, sum(coalesce(los_days, 0))::BIGINT AS bed_days,
               avg(los_days) AS los_mean, count(*) FILTER (WHERE is_death) AS deaths
        FROM ({base}) GROUP BY ALL ORDER BY month, region_kato, mo_key, profile_code""")
    return rows


def build_vac_monthly(con: duckdb.DuckDBPyConnection, lake: Lakehouse, out: Path) -> int:
    if not _has_silver(lake, "vac_facts"):
        return 0
    return _write(con, out, "vac_monthly", f"""
        SELECT date_trunc('month', vaccination_date)::DATE AS month, region_kato, mo_code, vaccination_plan,
               count(*) AS doses,
               count(*) FILTER (WHERE age_bucket = '0') AS age_0_1,
               count(*) FILTER (WHERE age_bucket = '1-6') AS age_1_6,
               count(*) FILTER (WHERE age_bucket = '7-17') AS age_7_17,
               count(*) FILTER (WHERE age_bucket = '18-59') AS age_18_59,
               count(*) FILTER (WHERE age_bucket = '60+') AS age_60_plus
        FROM {lake.silver_sql('vac_facts')} GROUP BY ALL ORDER BY month, region_kato, mo_code, vaccination_plan""")


def build_features_wait(con: duckdb.DuckDBPyConnection, lake: Lakehouse, out: Path) -> int:
    return _write(con, out, "features_wait", f"""
        SELECT r.hospitalization_code,
               r.registration_dt::DATE AS registration_date,
               r.region_kato AS origin_region_kato,
               coalesce(m.region_kato, r.region_kato) AS region_kato,
               r.mo_code, r.profile_code, r.referring_mo_key,
               icd10_chapter(r.icd10_ref_diag_code_canon) AS icd_chapter,
               substr(r.icd10_ref_diag_code_canon, 1, 3) AS icd_block,
               r.referral_purpose, r.finance_source, r.territorial_type,
               (r.referring_mo_key = r.hospital_mo_key) AS same_mo,
               coalesce(q.queue_len, 0) AS queue_len, q.queue_age_p50, q.queue_age_p90,
               coalesce(t.throughput_per_day, 0) AS throughput_per_day, t.refusal_rate_4w, t.wait_p50_4w, t.wait_p90_4w,
               m.size_bucket AS mo_size_bucket, m.mo_type,
               dayofweek(r.registration_dt) AS dow, weekofyear(r.registration_dt) AS week_of_year,
               r.wait_days,
               (r.outcome = 'refused') AS refused,
               (r.wait_days IS NOT NULL AND r.wait_days <= 30) AS within_30,
               CASE WHEN hash(r.mo_code) % {HOLDOUT_MO_BUCKETS} = 0 THEN 'test_mo'
                    WHEN r.registration_dt::DATE < DATE '{VALID_START}' THEN 'train'
                    WHEN r.registration_dt::DATE < DATE '{TEST_TIME_START}' THEN 'valid'
                    ELSE 'test_time' END AS split
        FROM referrals r
        LEFT JOIN queue_daily q ON q.mo_code = r.mo_code AND q.profile_code = r.profile_code
                                AND q.day = r.registration_dt::DATE - INTERVAL 1 DAY
        LEFT JOIN throughput_4w t ON t.mo_code = r.mo_code AND t.profile_code = r.profile_code
                                  AND t.day = r.registration_dt::DATE
        LEFT JOIN mo_registry m ON m.mo_code = r.mo_code
        WHERE NOT r.is_day_hospital
        ORDER BY r.registration_dt""")


UNKNOWN = "unknown"
FILL_WITHIN_DAYS = 14


def _rx_available(lake: Lakehouse) -> bool:
    return _has_silver(lake, "rx_issued") and _has_silver(lake, "rx_fulfilled")


def build_rx_weekly(con: duckdb.DuckDBPyConnection, lake: Lakehouse, out: Path) -> int:
    """Issued and fulfilled counts per week and MNN with fill-time quantiles. Fill time comes from the
    fulfilled rows themselves (recipe_date is repeated there), so no join across the two large tables."""
    if not _rx_available(lake):
        return 0
    return _write(con, out, "rx_weekly", f"""
        WITH issued AS (
            SELECT date_trunc('week', recipe_date)::DATE AS week, coalesce(drug_mnn_id, '{UNKNOWN}') AS drug_mnn_id, count(*) AS issued
            FROM {lake.silver_sql('rx_issued')} GROUP BY ALL),
        fulfilled AS (
            SELECT date_trunc('week', recipe_date)::DATE AS week, coalesce(drug_mnn_id, '{UNKNOWN}') AS drug_mnn_id, count(*) AS fulfilled,
                   sum((fill_days <= {FILL_WITHIN_DAYS})::int) AS fulfilled_14d,
                   quantile_cont(fill_days, 0.5) AS fill_days_p50, quantile_cont(fill_days, 0.9) AS fill_days_p90
            FROM {lake.silver_sql('rx_fulfilled')} WHERE fill_days IS NULL OR fill_days >= 0 GROUP BY ALL)
        SELECT coalesce(i.week, f.week) AS week, '{UNKNOWN}' AS region_kato, coalesce(i.drug_mnn_id, f.drug_mnn_id) AS drug_mnn_id,
               coalesce(i.issued, 0)::BIGINT AS issued, coalesce(f.fulfilled, 0)::BIGINT AS fulfilled, coalesce(f.fulfilled_14d, 0)::BIGINT AS fulfilled_14d,
               f.fill_days_p50, f.fill_days_p90, (coalesce(i.issued, 0) - coalesce(f.fulfilled, 0))::BIGINT AS gap
        FROM issued i FULL OUTER JOIN fulfilled f ON i.week = f.week AND i.drug_mnn_id = f.drug_mnn_id
        ORDER BY 1, 3""")


def build_rx_nosology_monthly(con: duckdb.DuckDBPyConnection, lake: Lakehouse, out: Path) -> int:
    if not _rx_available(lake):
        return 0
    return _write(con, out, "rx_nosology_monthly", f"""
        WITH issued AS (
            SELECT date_trunc('month', recipe_date)::DATE AS month, coalesce(nosology_id, '{UNKNOWN}') AS nosology_id,
                   coalesce(category_id, '{UNKNOWN}') AS category_id, count(*) AS issued, count(DISTINCT drug_mnn_id) AS mnn_count
            FROM {lake.silver_sql('rx_issued')} GROUP BY ALL),
        fulfilled AS (
            SELECT date_trunc('month', recipe_date)::DATE AS month, coalesce(nosology_id, '{UNKNOWN}') AS nosology_id,
                   coalesce(category_id, '{UNKNOWN}') AS category_id, count(*) AS fulfilled,
                   sum((fill_days <= {FILL_WITHIN_DAYS})::int) AS fulfilled_14d,
                   quantile_cont(fill_days, 0.5) AS fill_days_p50, quantile_cont(fill_days, 0.9) AS fill_days_p90
            FROM {lake.silver_sql('rx_fulfilled')} WHERE fill_days IS NULL OR fill_days >= 0 GROUP BY ALL)
        SELECT coalesce(i.month, f.month) AS month, coalesce(i.nosology_id, f.nosology_id) AS nosology_id,
               coalesce(i.category_id, f.category_id) AS category_id,
               coalesce(i.issued, 0)::BIGINT AS issued, coalesce(i.mnn_count, 0)::BIGINT AS mnn_count,
               coalesce(f.fulfilled, 0)::BIGINT AS fulfilled, coalesce(f.fulfilled_14d, 0)::BIGINT AS fulfilled_14d,
               f.fill_days_p50, f.fill_days_p90
        FROM issued i FULL OUTER JOIN fulfilled f ON i.month = f.month AND i.nosology_id = f.nosology_id AND i.category_id = f.category_id
        ORDER BY 1, 2, 3""")


def build_rx_mnn(con: duckdb.DuckDBPyConnection, lake: Lakehouse, out: Path) -> int:
    """Which MNN are prescribed for which nosology: volumes over the last twelve months of data."""
    if not _rx_available(lake):
        return 0
    return _write(con, out, "rx_mnn", f"""
        WITH span AS (SELECT max(recipe_date)::DATE - INTERVAL 365 DAY AS since FROM {lake.silver_sql('rx_issued')}),
        issued AS (
            SELECT coalesce(drug_mnn_id, '{UNKNOWN}') AS drug_mnn_id, coalesce(nosology_id, '{UNKNOWN}') AS nosology_id,
                   coalesce(category_id, '{UNKNOWN}') AS category_id, count(*) AS issued_12m
            FROM {lake.silver_sql('rx_issued')}, span WHERE recipe_date >= span.since GROUP BY ALL),
        fulfilled AS (
            SELECT coalesce(drug_mnn_id, '{UNKNOWN}') AS drug_mnn_id, coalesce(nosology_id, '{UNKNOWN}') AS nosology_id,
                   coalesce(category_id, '{UNKNOWN}') AS category_id, count(*) AS fulfilled_12m,
                   quantile_cont(fill_days, 0.5) AS fill_days_p50
            FROM {lake.silver_sql('rx_fulfilled')}, span WHERE recipe_date >= span.since AND (fill_days IS NULL OR fill_days >= 0) GROUP BY ALL)
        SELECT coalesce(i.drug_mnn_id, f.drug_mnn_id) AS drug_mnn_id, coalesce(i.nosology_id, f.nosology_id) AS nosology_id,
               coalesce(i.category_id, f.category_id) AS category_id, coalesce(i.issued_12m, 0)::BIGINT AS issued_12m,
               coalesce(f.fulfilled_12m, 0)::BIGINT AS fulfilled_12m, f.fill_days_p50
        FROM issued i FULL OUTER JOIN fulfilled f ON i.drug_mnn_id = f.drug_mnn_id AND i.nosology_id = f.nosology_id AND i.category_id = f.category_id
        ORDER BY 2, 4 DESC""")


def build_drug_programs(con: duckdb.DuckDBPyConnection, lake: Lakehouse, out: Path) -> int:
    if not _has_silver(lake, "drug_specs"):
        return 0
    return _write(con, out, "drug_programs", f"""
        SELECT coalesce(nosology_id, '{UNKNOWN}') AS nosology_id, coalesce(category_id, '{UNKNOWN}') AS category_id,
               coalesce(program_id, '{UNKNOWN}') AS program_id,
               count(*) AS specs, sum(is_active::int)::BIGINT AS active_specs, count(DISTINCT product_id) AS products,
               quantile_cont(spec_unit_price, 0.5) AS unit_price_p50, max(sdu_load_date)::DATE AS snapshot_date
        FROM {lake.silver_sql('drug_specs')} GROUP BY ALL ORDER BY 1, 2, 3""")


def build_staffing_by_region(con: duckdb.DuckDBPyConnection, lake: Lakehouse, out: Path) -> int:
    """Занимаемые ставки медперсонала по региону: сырая сумма ставок на дату снапшота (staffing —
    это не временной ряд, а точечный срез). Деление на численность населения и на объём госпитализаций
    (per 10k / per 1000) считается в SQL на стороне API (5.2), где уже доступны refdata.regions и
    gold.admissions_monthly — здесь только простая агрегация, без межвитринных джойнов."""
    if not _has_silver(lake, "staffing"):
        return 0
    return _write(con, out, "staffing_by_region", f"""
        SELECT region_kato, sum(position_rate) AS total_rate, max(sdu_load_date)::DATE AS snapshot_date
        FROM {lake.silver_sql('staffing')} GROUP BY ALL ORDER BY 1""")


def build_onco_monthly(con: duckdb.DuckDBPyConnection, lake: Lakehouse, out: Path) -> int:
    """Впервые выявленные ЗН по месяцам и локализациям из расширенного реестра ЭРОБ.
    Реестр накопительный: полная помесячная интенсивность только с сентября 2024, более ранние
    месяцы содержат лишь пациентов, оставшихся на учёте, поэтому ряд начинается с 2024-09."""
    if not _has_silver(lake, "onco_ext"):
        return 0
    top = "'C50','C34','C44','C16','C18','C53','C61','C64'"  # локализации с достаточным месячным объёмом
    base = f"""
        SELECT date_trunc('month', diagnosis_date)::DATE AS month,
               substr(diagnosis_code_canon, 1, 3) AS icd3
        FROM {lake.silver_sql('onco_ext')}
        WHERE diagnosis_date >= DATE '2024-09-01' AND diagnosis_code_canon LIKE 'C%'"""
    return _write(con, out, "onco_monthly", f"""
        WITH base AS ({base}),
        grouped AS (
            SELECT month, CASE WHEN icd3 IN ({top}) THEN icd3 ELSE 'OTH' END AS localization, count(*) AS new_cases
            FROM base GROUP BY ALL)
        SELECT month, localization, new_cases FROM grouped
        UNION ALL
        SELECT month, 'ALL' AS localization, sum(new_cases) AS new_cases FROM grouped GROUP BY month
        ORDER BY month, localization""")


BUILDERS: dict[str, Callable[[duckdb.DuckDBPyConnection, Lakehouse, Path], int]] = {
    "queue_daily": build_queue_daily,
    "throughput_4w": build_throughput_4w,
    "er_visits_daily": build_er_visits_daily,
    "admissions_monthly": build_admissions_monthly,
    "vac_monthly": build_vac_monthly,
    "onco_monthly": build_onco_monthly,
    "features_wait": build_features_wait,
    "rx_weekly": build_rx_weekly,
    "rx_nosology_monthly": build_rx_nosology_monthly,
    "drug_programs": build_drug_programs,
    "staffing_by_region": build_staffing_by_region,
    "rx_mnn": build_rx_mnn,
}


def build_gold(lake: Lakehouse, only: list[str] | None = None, out: Path | None = None) -> dict[str, int]:
    out = Path(out or lake.root / "gold")
    con = duckdb.connect()
    try:
        _prepare(con, lake)
        counts: dict[str, int] = {}
        for name, builder in BUILDERS.items():
            if only and name not in only:
                continue
            counts[name] = builder(con, lake, out)
        return counts
    finally:
        con.close()
