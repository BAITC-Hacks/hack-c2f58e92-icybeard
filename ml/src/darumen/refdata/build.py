"""Build reference tables under <lakehouse>/refdata from seeds and silver data.

    regions           seed refdata/regions.yaml
    region_neighbors  seed refdata/regions.yaml (neighbors) — join-таблица для «включить соседние регионы»
    bed_profiles      profile_code → name, from silver.bg_referrals
    mo_registry       mo_code → canonical name, name variants, region, type, size bucket, peer group
    mo_name_index     (region_kato, name_key) → mo_code, to resolve datasets that only carry names

The registry is assembled from what the data itself says: codes and names from referrals, code → region
from vaccination facts, name → region from ER visits and staffing, size from treated-case counts.
Coverage numbers are returned so the steward can see what is still unresolved.
"""
from __future__ import annotations

import json
from pathlib import Path

import duckdb
import yaml

from ..intake.normalize import register_udfs
from ..intake.pipeline import Lakehouse

SEED_DIR = Path(__file__).resolve().parents[4] / "refdata"

MO_TYPES = [
    ("polyclinic", ("поликлиник", "пмсп", "врачебн", "амбулатор", "семейн")),
    ("maternity", ("перинатальн", "родильн", "акушер")),
    ("dispensary", ("диспансер",)),
    ("republican", ("республиканск", "национальн", "научн", "нии ")),
    ("hospital", ("больниц", "госпиталь", "клиника", "медицинский центр", "стационар")),
    ("center", ("центр",)),
]


def classify_mo(name: str | None, nomenclature: str | None = None) -> str:
    text = f"{nomenclature or ''} {name or ''}".lower()
    for mo_type, needles in MO_TYPES:
        if any(needle in text for needle in needles):
            return mo_type
    return "other"


def _sql_path(path: Path) -> str:
    return "'" + str(path).replace("'", "''") + "'"


def _exists(lake: Lakehouse, dataset: str) -> bool:
    return lake.silver(dataset).exists() and any(lake.silver(dataset).rglob("*.parquet"))


def _classify_vectorized(names, nomenclatures):
    import pyarrow as pa

    if isinstance(names, pa.ChunkedArray):
        names = names.combine_chunks()
    if isinstance(nomenclatures, pa.ChunkedArray):
        nomenclatures = nomenclatures.combine_chunks()
    return pa.array([classify_mo(a, b) for a, b in zip(names.to_pylist(), nomenclatures.to_pylist(), strict=True)], type=pa.string())


def build_refdata(lake: Lakehouse, out: Path | None = None, seed_dir: Path = SEED_DIR) -> dict:
    out = Path(out or lake.root / "refdata")
    out.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect()
    register_udfs(con)
    try:
        from duckdb.sqltypes import VARCHAR
    except ImportError:  # older DuckDB
        from duckdb.typing import VARCHAR
    con.create_function("classify_mo", _classify_vectorized, [VARCHAR, VARCHAR], VARCHAR, type="arrow", null_handling="special")
    report: dict = {"tables": {}, "coverage": {}, "warnings": []}

    regions = yaml.safe_load((seed_dir / "regions.yaml").read_text(encoding="utf-8"))["regions"]
    con.execute("CREATE OR REPLACE TABLE regions (region_kato VARCHAR, name_ru VARCHAR, name_kz VARCHAR, capital VARCHAR, lat DOUBLE, lon DOUBLE, population_thousands INTEGER)")
    con.executemany("INSERT INTO regions VALUES (?, ?, ?, ?, ?, ?, ?)",
                    [(r["region_kato"], r["name_ru"], r["name_kz"], r["capital"], r["lat"], r["lon"], r["population_thousands"]) for r in regions])
    con.execute(f"COPY regions TO {_sql_path(out / 'regions.parquet')} (FORMAT PARQUET)")
    report["tables"]["regions"] = len(regions)

    # 3.7: соседи региона (для «где быстрее» с флагом includeNeighbors) — список смежных КАТО из
    # regions.yaml, разложен в join-таблицу (region_kato, neighbor_kato), а не массив в колонке,
    # чтобы читался обычным SELECT/join без специфичных для DuckDB операций над списками.
    neighbor_pairs = [(r["region_kato"], n) for r in regions for n in r.get("neighbors", [])]
    con.execute("CREATE OR REPLACE TABLE region_neighbors (region_kato VARCHAR, neighbor_kato VARCHAR)")
    if neighbor_pairs:
        con.executemany("INSERT INTO region_neighbors VALUES (?, ?)", neighbor_pairs)
    con.execute(f"COPY region_neighbors TO {_sql_path(out / 'region_neighbors.parquet')} (FORMAT PARQUET)")
    report["tables"]["region_neighbors"] = len(neighbor_pairs)

    if not _exists(lake, "bg_referrals"):
        report["warnings"].append("silver.bg_referrals отсутствует: реестр организаций не построен")
        con.close()
        return report
    con.execute(f"CREATE OR REPLACE VIEW referrals AS SELECT * FROM {lake.silver_sql('bg_referrals')}")

    con.execute("""
        CREATE OR REPLACE TABLE bed_profiles AS
        SELECT profile_code,
               coalesce(mode(bed_profile) FILTER (WHERE bed_profile IS NOT NULL),
                        CASE WHEN profile_code = 'DH' THEN 'Дневной стационар' END) AS name_ru,
               profile_code = 'DH' AS is_day_hospital,
               count(*) AS referrals
        FROM referrals GROUP BY profile_code ORDER BY profile_code""")
    con.execute(f"COPY bed_profiles TO {_sql_path(out / 'bed_profiles.parquet')} (FORMAT PARQUET)")
    report["tables"]["bed_profiles"] = con.execute("SELECT count(*) FROM bed_profiles").fetchone()[0]

    # 1. codes and names from referrals; the code prefix is the region of origin, not of the hospital
    con.execute("""
        CREATE OR REPLACE TABLE code_names AS
        SELECT mo_code,
               mode(hospital_mo) AS name_canonical,
               mode(hospital_mo_key) AS name_key,
               list(DISTINCT hospital_mo) AS name_variants,
               mode(region_kato) AS origin_region_kato,
               count(*) AS referrals_in,
               count(*) FILTER (WHERE outcome = 'hospitalized') AS hospitalized_in
        FROM referrals GROUP BY mo_code""")

    # 2. code → region from vaccination facts (organisation code with its region)
    if _exists(lake, "vac_facts"):
        con.execute(f"""
            CREATE OR REPLACE TABLE code_region_vac AS
            SELECT mo_code, mode(region_kato) AS region_kato FROM {lake.silver_sql('vac_facts')}
            WHERE mo_code IS NOT NULL AND region_kato IS NOT NULL GROUP BY mo_code""")
    else:
        con.execute("CREATE OR REPLACE TABLE code_region_vac (mo_code VARCHAR, region_kato VARCHAR)")

    # 3. name key → region from ER visits and staffing
    sources = []
    if _exists(lake, "bg_er_refusals"):
        sources.append(f"SELECT org_in_key AS name_key, region_kato, count(*) AS n FROM {lake.silver_sql('bg_er_refusals')} WHERE org_in_key IS NOT NULL AND region_kato IS NOT NULL GROUP BY ALL")
    if _exists(lake, "staffing"):
        sources.append(f"SELECT organization_name_key AS name_key, region_kato, count(*) AS n FROM {lake.silver_sql('staffing')} WHERE organization_name_key IS NOT NULL AND region_kato IS NOT NULL GROUP BY ALL")
    if sources:
        con.execute("CREATE OR REPLACE TABLE key_region AS SELECT name_key, arg_max(region_kato, n) AS region_kato, count(DISTINCT region_kato) AS regions FROM (" + " UNION ALL ".join(sources) + ") GROUP BY name_key")
    else:
        con.execute("CREATE OR REPLACE TABLE key_region (name_key VARCHAR, region_kato VARCHAR, regions INTEGER)")

    # 4. nomenclature (type) from staffing, size from treated counts
    if _exists(lake, "staffing"):
        con.execute(f"CREATE OR REPLACE TABLE key_nomenclature AS SELECT organization_name_key AS name_key, mode(nomenclature) AS nomenclature FROM {lake.silver_sql('staffing')} GROUP BY 1")
    else:
        con.execute("CREATE OR REPLACE TABLE key_nomenclature (name_key VARCHAR, nomenclature VARCHAR)")
    if _exists(lake, "ersb_treated_count"):
        con.execute(f"CREATE OR REPLACE TABLE key_size AS SELECT medicine_organization_key AS name_key, sum(discharged_total) AS discharged_total, sum(bed_days) AS bed_days FROM {lake.silver_sql('ersb_treated_count')} GROUP BY 1")
    else:
        con.execute("CREATE OR REPLACE TABLE key_size (name_key VARCHAR, discharged_total BIGINT, bed_days BIGINT)")

    con.execute("""
        CREATE OR REPLACE TABLE mo_registry AS
        WITH base AS (
          SELECT c.mo_code, c.name_canonical, c.name_key, c.name_variants,
                 coalesce(v.region_kato, CASE WHEN kr.regions = 1 THEN kr.region_kato END, c.origin_region_kato) AS region_kato,
                 CASE WHEN v.region_kato IS NOT NULL THEN 'vaccination' WHEN kr.regions = 1 THEN 'name_match' ELSE 'origin_majority' END AS region_source,
                 classify_mo(c.name_canonical, kn.nomenclature) AS mo_type,
                 kn.nomenclature,
                 coalesce(ks.discharged_total, 0) AS discharged_total,
                 c.referrals_in, c.hospitalized_in
          FROM code_names c
          LEFT JOIN code_region_vac v USING (mo_code)
          LEFT JOIN key_region kr ON kr.name_key = c.name_key
          LEFT JOIN key_nomenclature kn ON kn.name_key = c.name_key
          LEFT JOIN key_size ks ON ks.name_key = c.name_key),
        sized AS (
          SELECT *, CASE WHEN discharged_total > 0 THEN discharged_total ELSE hospitalized_in * 4 END AS size_proxy FROM base),
        bucketed AS (
          SELECT *, CASE WHEN size_proxy >= quantile_cont(size_proxy, 0.75) OVER () THEN 'L'
                         WHEN size_proxy >= quantile_cont(size_proxy, 0.35) OVER () THEN 'M' ELSE 'S' END AS size_bucket
          FROM sized)
        SELECT mo_code, name_canonical, name_key, name_variants, region_kato, region_source, mo_type, nomenclature,
               discharged_total, referrals_in, hospitalized_in, size_bucket,
               region_kato || ':' || mo_type || ':' || size_bucket AS peer_group_id,
               NULL::DOUBLE AS lat, NULL::DOUBLE AS lon
        FROM bucketed ORDER BY mo_code""")
    con.execute(f"COPY mo_registry TO {_sql_path(out / 'mo_registry.parquet')} (FORMAT PARQUET)")
    con.execute("""
        CREATE OR REPLACE TABLE mo_name_index AS
        SELECT region_kato, name_key, arg_max(mo_code, referrals_in) AS mo_code, count(*) AS candidates
        FROM mo_registry WHERE name_key IS NOT NULL GROUP BY 1, 2""")
    con.execute(f"COPY mo_name_index TO {_sql_path(out / 'mo_name_index.parquet')} (FORMAT PARQUET)")

    report["tables"]["mo_registry"] = con.execute("SELECT count(*) FROM mo_registry").fetchone()[0]
    report["tables"]["mo_name_index"] = con.execute("SELECT count(*) FROM mo_name_index").fetchone()[0]
    report["coverage"]["region_source"] = dict(con.execute("SELECT region_source, count(*) FROM mo_registry GROUP BY 1").fetchall())
    report["coverage"]["mo_type"] = dict(con.execute("SELECT mo_type, count(*) FROM mo_registry GROUP BY 1").fetchall())
    report["coverage"]["size_bucket"] = dict(con.execute("SELECT size_bucket, count(*) FROM mo_registry GROUP BY 1").fetchall())
    report["coverage"]["with_size_from_treated"] = con.execute("SELECT count(*) FROM mo_registry WHERE discharged_total > 0").fetchone()[0]
    if _exists(lake, "bg_er_refusals"):
        matched = con.execute(f"""
            SELECT round(avg((i.mo_code IS NOT NULL)::int), 3)
            FROM (SELECT DISTINCT region_kato, org_in_key FROM {lake.silver_sql('bg_er_refusals')}) e
            LEFT JOIN mo_name_index i ON i.region_kato = e.region_kato AND i.name_key = e.org_in_key""").fetchone()[0]
        report["coverage"]["er_orgs_resolved_to_code"] = matched
    (out / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=1), encoding="utf-8")
    con.close()
    return report
