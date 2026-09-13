"""Publish gold and refdata to the serving stores: Postgres for the API tables, ClickHouse for the series
behind charts. Idempotent: every table is rebuilt from the Parquet files.

python -m darumen.lakehouse publish [--lakehouse lakehouse] [--only postgres|clickhouse]
"""
from __future__ import annotations

import json
import os
from pathlib import Path

import duckdb
import pandas as pd
import pyarrow as pa

from ..intake.pipeline import Lakehouse
from ..models.streams import Stream, load_streams, period_format

DEFAULT_PG_DSN = "host=localhost port=5432 dbname=darumen user=darumen password=darumen"
DEFAULT_CH_URL = "http://darumen:darumen@localhost:8123/darumen"
QUEUE_HISTORY_DAYS = 90
ANOMALY_ID = "md5(stream_id || '|' || entity || '|' || period)"
SERIES_COLUMNS = ["stream_id", "entity", "period", "y"]

# table -> (source parquet relative to the lakehouse, select list, optional filter, index columns)
PG_TABLES: dict[str, tuple[str, str, str, list[str]]] = {
    "refdata.regions": ("refdata/regions.parquet", "*", "", ["region_kato"]),
    "refdata.bed_profiles": ("refdata/bed_profiles.parquet", "*", "", ["profile_code"]),
    "refdata.mo_registry": ("refdata/mo_registry.parquet", "* EXCLUDE (name_variants)", "", ["mo_code"]),
    "gold.forecasts": ("gold/forecasts.parquet", "*", "", ["stream_id", "entity"]),
    "gold.anomalies": ("gold/anomalies.parquet", f"{ANOMALY_ID} AS id, *", "", ["stream_id", "region_kato", "severity"]),
    "gold.access_index": ("gold/access_index.parquet", "month::DATE AS month, * EXCLUDE (month)", "", ["month", "profile_code"]),
    "gold.redistribution_q1": ("gold/redistribution_q1.parquet", "*", "", ["region_kato", "profile_code"]),
    "gold.rx_weekly": ("gold/rx_weekly.parquet", "*", "", ["drug_mnn_id", "week"]),
    "gold.rx_nosology_monthly": ("gold/rx_nosology_monthly.parquet", "*", "", ["nosology_id", "month"]),
    "gold.drug_programs": ("gold/drug_programs.parquet", "*", "", ["nosology_id"]),
    "gold.rx_mnn": ("gold/rx_mnn.parquet", "*", "", ["nosology_id", "drug_mnn_id"]),
    "gold.los_by_profile": ("gold/los_by_profile.parquet", "*", "", ["region_kato", "profile_code"]),
}
CH_TABLES: dict[str, tuple[str, str, list[str]]] = {
    "queue_daily": ("gold/queue_daily.parquet", "*", ["region_kato", "mo_code", "profile_code", "day"]),
    "er_visits_daily": ("gold/er_visits_daily.parquet", "*", ["region_kato", "mo_key", "day"]),
    "admissions_monthly": ("gold/admissions_monthly.parquet", "month::DATE AS month, * EXCLUDE (month)", ["region_kato", "profile_code", "month"]),
    "admissions_monthly_mo": ("gold/admissions_monthly_mo.parquet", "month::DATE AS month, * EXCLUDE (month)", ["region_kato", "mo_key", "profile_code", "month"]),
    "vac_monthly": ("gold/vac_monthly.parquet", "month::DATE AS month, * EXCLUDE (month)", ["region_kato", "vaccination_plan", "month"]),
    "forecasts": ("gold/forecasts.parquet", "*", ["stream_id", "entity", "horizon"]),
    "anomalies": ("gold/anomalies.parquet", f"{ANOMALY_ID} AS id, *", ["stream_id", "entity", "period"]),
    "access_index": ("gold/access_index.parquet", "month::DATE AS month, * EXCLUDE (month)", ["month", "profile_code", "region_kato"]),
    "rx_weekly": ("gold/rx_weekly.parquet", "*", ["region_kato", "drug_mnn_id", "week"]),
    "rx_nosology_monthly": ("gold/rx_nosology_monthly.parquet", "*", ["nosology_id", "category_id", "month"]),
}


def _as_of(con: duckdb.DuckDBPyConnection, lake: Lakehouse) -> str:
    features = lake.root / "gold" / "features_wait.parquet"
    return str(con.execute(f"SELECT max(registration_date) FROM read_parquet('{features}')").fetchone()[0])


def series_frame(con: duckdb.DuckDBPyConnection, lake: Lakehouse, stream: Stream) -> pd.DataFrame:
    """History of every series of a stream in the canonical layout (entity JSON as Python json.dumps writes it)."""
    path = lake.root / "gold" / f"{stream.table}.parquet"
    if not path.exists():
        return pd.DataFrame(columns=SERIES_COLUMNS)
    keys = ", ".join(f'"{k}"' for k in stream.entity)
    fmt = period_format(stream.grain)
    df = con.execute(f"""SELECT {keys}, strftime("{stream.time_col}"::DATE, '{fmt}') AS period, sum("{stream.y_col}")::DOUBLE AS y
                         FROM read_parquet('{path}') GROUP BY ALL ORDER BY ALL""").df()
    entity = df[list(stream.entity)].astype(str).apply(lambda r: json.dumps(dict(r), ensure_ascii=False), axis=1)
    return pd.DataFrame({"stream_id": stream.stream_id, "entity": entity, "period": df["period"], "y": df["y"]})


def streams_frame(streams: dict[str, Stream]) -> pd.DataFrame:
    return pd.DataFrame([{"stream_id": s.stream_id, "title": s.title, "grain": s.grain, "gold_table": s.table,
                          "entity_keys": ",".join(s.entity), "horizons": ",".join(str(h) for h in s.forecast.get("horizons", []))}
                         for s in streams.values()])


def seasonality_frame() -> pd.DataFrame:
    """Внешние сезонные формы (NHS) из refdata/external_seasonality.yaml — витрина для подписи в интерфейсе."""
    import yaml

    path = Path("refdata") / "external_seasonality.yaml"
    if not path.exists():
        return pd.DataFrame()
    doc = yaml.safe_load(path.read_text(encoding="utf-8"))
    window = str(doc.get("meta", {}).get("window", ""))
    rows = []
    for series_id, series in doc.get("series", {}).items():
        for month, multiplier in series["multipliers"].items():
            rows.append({"series_id": series_id, "month": int(month), "multiplier": float(multiplier),
                         "title": series.get("title", series_id), "source": series.get("source", ""),
                         "source_year": int(series.get("year", 0)), "window_label": window})
    return pd.DataFrame(rows)


def vaccination_frame() -> pd.DataFrame:
    """Оценки охвата WUENIC (ВОЗ/ЮНИСЕФ) из refdata/external_vaccination.yaml — внешний ориентир."""
    import yaml

    path = Path("refdata") / "external_vaccination.yaml"
    if not path.exists():
        return pd.DataFrame()
    doc = yaml.safe_load(path.read_text(encoding="utf-8"))
    rows = []
    for series in doc.get("series", []):
        for year, coverage in series.get("coverage_pct", {}).items():
            rows.append({"vaccine": series["vaccine"], "title_ru": series.get("title_ru", series["vaccine"]),
                         "year": int(year), "coverage_pct": float(coverage),
                         "source": doc.get("source", ""), "note": doc.get("note", "")})
    return pd.DataFrame(rows)


def batches_frame(lake: Lakehouse) -> pd.DataFrame:
    """Партии загрузки из манифестов lakehouse — консоль стюарда работает и без Kafka."""
    rows = []
    for path in sorted((lake.root / "manifests").glob("*/*.json")):
        try:
            m = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        finished = m.get("finished_at") or m.get("started_at")
        rows.append({
            "batch_id": m["batch_id"], "dataset": m["dataset"], "status": m.get("status", "loaded"),
            "rows_loaded": int(m.get("rows_silver") or 0), "rows_quarantined": int(m.get("rows_quarantine") or 0),
            "partitions": ",".join(str(p) for p in (m.get("partitions") or [])),
            "event_id": m["batch_id"][:64], "occurred_at": finished, "received_at": finished,
        })
    frame = pd.DataFrame(rows)
    if len(frame):
        for col in ("occurred_at", "received_at"):
            frame[col] = pd.to_datetime(frame[col], utc=True)
    return frame


def _replace_pg_table(con: duckdb.DuckDBPyConnection, name: str, select_sql: str, index: list[str]) -> int:
    con.execute(f"DROP TABLE IF EXISTS pg.{name}")
    con.execute(f"CREATE TABLE pg.{name} AS {select_sql}")
    if index:
        idx_name = name.replace(".", "_") + "_idx"
        con.execute(f"CALL postgres_execute('pg', 'CREATE INDEX IF NOT EXISTS {idx_name} ON {name} ({', '.join(index)})')")
    return int(con.execute(f"SELECT count(*) FROM pg.{name}").fetchone()[0])


def publish_postgres(lake: Lakehouse, dsn: str = DEFAULT_PG_DSN, streams: dict[str, Stream] | None = None) -> dict[str, int]:
    """Rebuild the API tables in Postgres through DuckDB's postgres extension (no extra drivers)."""
    con = duckdb.connect()
    counts: dict[str, int] = {}
    try:
        con.execute("INSTALL postgres; LOAD postgres;")
        con.execute(f"ATTACH '{dsn}' AS pg (TYPE postgres)")
        for schema in ("refdata", "gold"):
            con.execute(f"CREATE SCHEMA IF NOT EXISTS pg.{schema}")
        as_of = _as_of(con, lake)
        window = f"day BETWEEN DATE '{as_of}' - INTERVAL {QUEUE_HISTORY_DAYS} DAY AND DATE '{as_of}'"
        tables = {**PG_TABLES,
                  "gold.queue_daily": ("gold/queue_daily.parquet", "*", window, ["mo_code", "profile_code", "day"]),
                  "gold.throughput_4w": ("gold/throughput_4w.parquet", "*", window, ["mo_code", "profile_code", "day"])}
        for name, (source, select, where, index) in tables.items():
            path = lake.root / source
            if not path.exists():
                continue
            sql = f"SELECT {select} FROM read_parquet('{path}')" + (f" WHERE {where}" if where else "")
            counts[name] = _replace_pg_table(con, name, sql, index)
        counts["gold.queue_state"] = _replace_pg_table(con, "gold.queue_state", f"""
            SELECT q.day AS as_of, q.mo_code, q.profile_code, q.region_kato, q.queue_len, q.queue_age_p50, q.queue_age_p90,
                   coalesce(t.throughput_per_day, 0.0) AS throughput_per_day, t.refusal_rate_4w, t.wait_p50_4w, t.wait_p90_4w,
                   coalesce(t.registered_4w, 0) AS registered_4w
            FROM read_parquet('{lake.root / 'gold' / 'queue_daily.parquet'}') q
            LEFT JOIN read_parquet('{lake.root / 'gold' / 'throughput_4w.parquet'}') t USING (day, mo_code, profile_code)
            WHERE q.day = DATE '{as_of}'""", ["mo_code", "profile_code"])
        seasonality = seasonality_frame()
        if len(seasonality):
            con.register("seasonality_df", seasonality)
            counts["refdata.seasonality"] = _replace_pg_table(con, "refdata.seasonality", "SELECT * FROM seasonality_df", ["series_id", "month"])
        vaccination = vaccination_frame()
        if len(vaccination):
            con.register("vaccination_df", vaccination)
            counts["refdata.vaccination_wuenic"] = _replace_pg_table(con, "refdata.vaccination_wuenic", "SELECT * FROM vaccination_df", ["vaccine", "year"])
        streams = load_streams() if streams is None else streams
        con.register("streams_df", streams_frame(streams))
        counts["gold.streams"] = _replace_pg_table(con, "gold.streams", "SELECT * FROM streams_df", ["stream_id"])
        series = pd.concat([series_frame(con, lake, s) for s in streams.values()], ignore_index=True)
        con.register("series_df", series)
        counts["gold.series"] = _replace_pg_table(con, "gold.series", "SELECT * FROM series_df", ["stream_id", "entity", "period"])
        con.execute("CALL postgres_execute('pg', 'CREATE INDEX IF NOT EXISTS mo_registry_name_trgm ON refdata.mo_registry USING gin (name_canonical gin_trgm_ops)')")
        # партии из манифестов дозаписываются в intake.batches (таблица принадлежит миграциям API,
        # поэтому не пересоздаём её, а вставляем недостающие batch_id)
        batches = batches_frame(lake)
        if len(batches):
            try:
                con.register("batches_df", batches)
                con.execute("""
                    INSERT INTO pg.intake.batches
                    SELECT batch_id, dataset, status, rows_loaded, rows_quarantined, partitions, event_id, occurred_at, received_at
                    FROM batches_df WHERE batch_id NOT IN (SELECT batch_id FROM pg.intake.batches)
                """)
                counts["intake.batches"] = int(con.execute("SELECT count(*) FROM pg.intake.batches").fetchone()[0])
            except duckdb.Error as exc:
                print(f"intake.batches пропущены: {exc}")  # API ещё не применил миграции — не валим публикацию
    finally:
        con.close()
    return counts


def ch_type(field: pa.Field, key: bool) -> str:
    t = field.type
    if pa.types.is_boolean(t):
        base = "Bool"
    elif pa.types.is_integer(t):
        base = "Int64" if t.bit_width > 32 else "Int32"
    elif pa.types.is_floating(t):
        base = "Float64"
    elif pa.types.is_date(t):
        base = "Date32"
    elif pa.types.is_timestamp(t):
        base = "DateTime64(6)"
    else:
        base = "String"
    return base if key else f"Nullable({base})"


def publish_clickhouse(lake: Lakehouse, url: str = DEFAULT_CH_URL) -> dict[str, int]:
    """Rebuild the series tables in ClickHouse (MergeTree) with Arrow inserts."""
    import clickhouse_connect

    client = clickhouse_connect.get_client(dsn=url)
    con = duckdb.connect()
    counts: dict[str, int] = {}
    try:
        for name, (source, select, order) in CH_TABLES.items():
            path = lake.root / source
            if not path.exists():
                continue
            table = con.execute(f"SELECT {select} FROM read_parquet('{path}')").fetch_arrow_table()
            columns = ", ".join(f"`{f.name}` {ch_type(f, f.name in order)}" for f in table.schema)
            client.command(f"DROP TABLE IF EXISTS {name}")
            client.command(f"CREATE TABLE {name} ({columns}) ENGINE = MergeTree ORDER BY ({', '.join(order)})")
            for batch in table.to_batches(max_chunksize=500_000):
                client.insert_arrow(name, pa.Table.from_batches([batch]))
            counts[name] = int(client.command(f"SELECT count() FROM {name}"))
    finally:
        con.close()
        client.close()
    return counts


def publish(lake: Lakehouse, only: str | None = None, pg_dsn: str | None = None, ch_url: str | None = None) -> dict[str, dict[str, int]]:
    out: dict[str, dict[str, int]] = {}
    if only in (None, "postgres"):
        out["postgres"] = publish_postgres(lake, pg_dsn or os.environ.get("POSTGRES_DSN", DEFAULT_PG_DSN))
    if only in (None, "clickhouse"):
        out["clickhouse"] = publish_clickhouse(lake, ch_url or os.environ.get("CLICKHOUSE_URL", DEFAULT_CH_URL))
    return out
