"""Profile the МЗ РК datasets in the local DataSets folder with DuckDB.

Usage:
    python scripts/profile_datasets.py [path/to/DataSets]

Prints coverage, cardinalities and wait-time distributions for the ИС БГ
referral, waiting and refusal datasets. Requires `duckdb` (pip install duckdb).
"""
from __future__ import annotations

import sys
from pathlib import Path

import duckdb

REFERRALS_DIR = "Направления на плановую госпитализацию в стационары"
WAITING_DIR = "Ожидающие плановую госпитализацию в стационары"
REFUSALS_DIR = "Отказы в плановой госпитализации (приёмный покой)"
DAY_HOSPITAL_PROFILE = "DH"


def csv_glob(base: Path, folder: str) -> str:
    return str(base / folder / "*.csv").replace("'", "''")


def register_views(con: duckdb.DuckDBPyConnection, base: Path) -> None:
    con.execute(
        f"""
        CREATE VIEW referrals AS
        SELECT *,
               split_part(hospitalization_code, '.', 1) AS region_code,
               split_part(hospitalization_code, '.', 2) AS mo_code,
               split_part(hospitalization_code, '.', 3) AS profile_code,
               date_diff('day', try_cast(registration_dt AS DATE),
                                try_cast(hospitalization_dt AS DATE)) AS wait_days
        FROM read_csv('{csv_glob(base, REFERRALS_DIR)}',
                      header=true, all_varchar=true, union_by_name=true)
        """
    )
    con.execute(
        f"""
        CREATE VIEW waiting AS
        SELECT *,
               region_origin_code || '.' || mo_destination_code || '.' ||
               profile_code || '.' || patient_seq_no AS hospitalization_code
        FROM read_csv('{csv_glob(base, WAITING_DIR)}', header=true, all_varchar=true)
        """
    )
    con.execute(
        f"""
        CREATE VIEW refusals AS
        SELECT * FROM read_csv('{csv_glob(base, REFUSALS_DIR)}',
                               header=true, all_varchar=true, union_by_name=true)
        """
    )


def section(title: str) -> None:
    print(f"\n=== {title} ===")


def show(con: duckdb.DuckDBPyConnection, label: str, sql: str) -> None:
    rows = con.execute(sql).fetchall()
    print(f"{label}:")
    for row in rows:
        print("   ", row)


def profile_referrals(con: duckdb.DuckDBPyConnection) -> None:
    section("Направления (ИС БГ)")
    show(con, "rows / registration range",
         "SELECT count(*), min(registration_dt), max(registration_dt) FROM referrals")
    show(con, "regions / MOs / profiles",
         "SELECT count(DISTINCT region_code), count(DISTINCT mo_code), count(DISTINCT profile_code) FROM referrals")
    show(con, "outcome shares (hospitalized, refused, none)",
         """SELECT round(avg((hospitalization_dt IS NOT NULL)::int), 3),
                   round(avg((refusal_dt IS NOT NULL)::int), 3),
                   round(avg((hospitalization_dt IS NULL AND refusal_dt IS NULL)::int), 3)
            FROM referrals""")
    show(con, "day-hospital share",
         f"SELECT round(avg((profile_code = '{DAY_HOSPITAL_PROFILE}')::int), 3) FROM referrals")
    show(con, "round-the-clock wait: n, share>7d, share>30d, p50, p90",
         f"""SELECT count(*), round(avg((wait_days > 7)::int), 3), round(avg((wait_days > 30)::int), 3),
                    quantile_cont(wait_days, 0.5), quantile_cont(wait_days, 0.9)
             FROM referrals WHERE wait_days IS NOT NULL AND profile_code <> '{DAY_HOSPITAL_PROFILE}'""")
    show(con, "wait by region (round-the-clock): region, n, refusal share, p50, p90",
         f"""SELECT region_code, count(*), round(avg((refusal_dt IS NOT NULL)::int), 3),
                    round(quantile_cont(CASE WHEN profile_code <> '{DAY_HOSPITAL_PROFILE}' THEN wait_days END, 0.5), 0),
                    round(quantile_cont(CASE WHEN profile_code <> '{DAY_HOSPITAL_PROFILE}' THEN wait_days END, 0.9), 0)
             FROM referrals GROUP BY 1 ORDER BY 1""")
    show(con, "wait by profile (top 12 by volume): code, name, n, p50, p90, mean",
         f"""SELECT profile_code, substr(any_value(bed_profile), 1, 38), count(*),
                    round(quantile_cont(wait_days, 0.5), 1), round(quantile_cont(wait_days, 0.9), 1),
                    round(avg(wait_days), 1)
             FROM referrals WHERE wait_days IS NOT NULL AND profile_code <> '{DAY_HOSPITAL_PROFILE}'
             GROUP BY 1 ORDER BY 3 DESC LIMIT 12""")


def profile_waiting(con: duckdb.DuckDBPyConnection) -> None:
    section("Ожидающие (ИС БГ)")
    show(con, "rows / registration range / planned range",
         """SELECT count(*), min(registration_dt), max(registration_dt),
                   min(CASE WHEN planned_dt > '2000' THEN planned_dt END), max(planned_dt)
            FROM waiting""")
    show(con, "join to referrals: match rate",
         """SELECT round(avg((r.hospitalization_code IS NOT NULL)::int), 3), count(*)
            FROM waiting w LEFT JOIN referrals r USING (hospitalization_code)""")
    show(con, "operation code filled share",
         "SELECT round(avg((operation_code IS NOT NULL AND operation_code <> '')::int), 3) FROM waiting")


def profile_refusals(con: duckdb.DuckDBPyConnection) -> None:
    section("Отказы в приёмном покое (ИС БГ)")
    show(con, "rows / date range", "SELECT count(*), min(refuse_dt), max(refuse_dt) FROM refusals")
    show(con, "regions / orgs", "SELECT count(DISTINCT region_in), count(DISTINCT org_in) FROM refusals")
    show(con, "by month", "SELECT substr(refuse_dt, 1, 7), count(*) FROM refusals GROUP BY 1 ORDER BY 1")
    show(con, "insured share", "SELECT insured, count(*) FROM refusals GROUP BY 1 ORDER BY 2 DESC")


def main() -> int:
    base = Path(sys.argv[1] if len(sys.argv) > 1 else "DataSets").expanduser().resolve()
    if not base.is_dir():
        print(f"DataSets folder not found: {base}", file=sys.stderr)
        return 1
    con = duckdb.connect()
    register_views(con, base)
    profile_referrals(con)
    profile_waiting(con)
    profile_refusals(con)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
