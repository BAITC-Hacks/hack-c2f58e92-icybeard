"""In-memory state for the model services: the wait model, the queue state per organisation and profile at
the data's as-of date, the organisation registry and the precomputed forecasts. Loaded once, never mutated."""
from __future__ import annotations

import json
import math
from dataclasses import dataclass

import duckdb
import numpy as np
import pandas as pd

from ..intake.normalize import icd10_canon, icd10_chapter
from ..intake.pipeline import Lakehouse
from ..models.common import FEATURES
from ..models.simulate import load_calibration, load_states
from ..models.streams import Stream, load_streams
from ..models.wait import WaitModel

EARTH_RADIUS_KM = 6371.0
FORECAST_COLUMNS = ["stream_id", "entity", "period", "horizon", "yhat", "lo", "hi", "model"]
REGISTRY_COLUMNS = ["mo_code", "name_canonical", "region_kato", "mo_type", "size_bucket", "lat", "lon"]


def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Great-circle distance; 0 when any coordinate is missing (the registry has no coordinates yet)."""
    if any(v is None or (isinstance(v, float) and math.isnan(v)) for v in (lat1, lon1, lat2, lon2)):
        return 0.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi, dlambda = math.radians(lat2 - lat1), math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlambda / 2) ** 2
    return 2 * EARTH_RADIUS_KM * math.asin(math.sqrt(a))


def _as_of(lake: Lakehouse) -> pd.Timestamp:
    """The last registration date: the queue calendar itself runs on until the last outcome."""
    features = lake.root / "gold" / "features_wait.parquet"
    queue = lake.root / "gold" / "queue_daily.parquet"
    con = duckdb.connect()
    try:
        if features.exists():
            value = con.execute(f"SELECT max(registration_date) FROM read_parquet('{features}')").fetchone()[0]
        else:
            value = con.execute(f"SELECT max(day) FROM read_parquet('{queue}')").fetchone()[0]
    finally:
        con.close()
    return pd.Timestamp(value)


def _queue_state(lake: Lakehouse, as_of: pd.Timestamp) -> pd.DataFrame:
    queue = lake.root / "gold" / "queue_daily.parquet"
    throughput = lake.root / "gold" / "throughput_4w.parquet"
    day = as_of.strftime("%Y-%m-%d")
    con = duckdb.connect()
    try:
        con.execute(f"CREATE VIEW q AS SELECT * FROM read_parquet('{queue}') WHERE day = DATE '{day}'")
        if throughput.exists():
            con.execute(f"CREATE VIEW t AS SELECT * FROM read_parquet('{throughput}') WHERE day = DATE '{day}'")
        else:
            con.execute("CREATE VIEW t AS SELECT mo_code, profile_code, NULL::DOUBLE AS throughput_per_day, NULL::DOUBLE AS refusal_rate_4w, "
                        "NULL::DOUBLE AS wait_p50_4w, NULL::DOUBLE AS wait_p90_4w, NULL::BIGINT AS registered_4w FROM q WHERE false")
        return con.execute("""
            SELECT q.mo_code, q.profile_code, q.region_kato, q.queue_len::BIGINT AS queue_len, q.queue_age_p50, q.queue_age_p90,
                   coalesce(t.throughput_per_day, 0.0) AS throughput_per_day, t.refusal_rate_4w, t.wait_p50_4w, t.wait_p90_4w,
                   coalesce(t.registered_4w, 0)::BIGINT AS registered_4w
            FROM q LEFT JOIN t USING (mo_code, profile_code)""").df()
    finally:
        con.close()


def _registry(lake: Lakehouse, queue: pd.DataFrame) -> pd.DataFrame:
    path = lake.root / "refdata" / "mo_registry.parquet"
    if path.exists():
        return pd.read_parquet(path, columns=REGISTRY_COLUMNS).drop_duplicates("mo_code")
    fallback = queue.groupby("mo_code", as_index=False)["region_kato"].agg(lambda s: s.mode().iloc[0])
    return fallback.assign(name_canonical=fallback["mo_code"], mo_type=None, size_bucket=None, lat=np.nan, lon=np.nan)[REGISTRY_COLUMNS]


@dataclass(frozen=True)
class ModelState:
    wait: WaitModel
    as_of: pd.Timestamp
    queue: pd.DataFrame
    registry: pd.DataFrame
    registry_by_code: dict[str, dict]
    forecasts: pd.DataFrame
    sim_states: pd.DataFrame
    streams: dict[str, Stream]
    reports: dict[str, dict]
    backtests: dict[str, pd.DataFrame]

    @classmethod
    def load(cls, lake: Lakehouse, streams: dict[str, Stream] | None = None) -> ModelState:
        wait = WaitModel.load(lake.root / "models" / "wait")
        as_of = _as_of(lake)
        queue = _queue_state(lake, as_of)
        registry = _registry(lake, queue)
        forecasts_path = lake.root / "gold" / "forecasts.parquet"
        forecasts = pd.read_parquet(forecasts_path) if forecasts_path.exists() else pd.DataFrame(columns=FORECAST_COLUMNS)
        streams = load_streams() if streams is None else streams
        reports, backtests = {}, {}
        for stream_id in streams:
            directory = lake.root / "models" / "forecast" / stream_id
            if (directory / "report.json").exists():
                reports[stream_id] = json.loads((directory / "report.json").read_text(encoding="utf-8"))
            if (directory / "backtest.parquet").exists():
                backtests[stream_id] = pd.read_parquet(directory / "backtest.parquet")
        by_code = {row["mo_code"]: row for row in registry.to_dict("records")}
        throughput = lake.root / "gold" / "throughput_4w.parquet"
        sim_states = (load_states(lake, as_of=as_of.strftime("%Y-%m-%d"), calibration=load_calibration(lake)) if throughput.exists()
                      else pd.DataFrame(columns=["mo_code", "profile_code", "region_kato", "arrivals_per_day", "admissions_per_day", "queue_len", "wait_p50_4w", "calibration"]))
        return cls(wait, as_of, queue, registry, by_code, forecasts, sim_states, streams, reports, backtests)

    # ---------- lookups ----------
    @property
    def model_info(self) -> dict[str, str]:
        meta = self.wait.metadata
        return {"name": str(meta.get("name", "wait_quantile")), "version": str(meta.get("version", "")),
                "trained_through": str(meta.get("trained_through", ""))[:10]}

    @property
    def known_regions(self) -> set[str]:
        return set(self.queue["region_kato"].dropna()) | set(self.registry["region_kato"].dropna())

    @property
    def known_profiles(self) -> set[str]:
        return set(self.queue["profile_code"].dropna()) | set(self.wait.categories.get("profile_code", []))

    @property
    def known_organisations(self) -> set[str]:
        return set(self.registry_by_code) | set(self.queue["mo_code"])

    def region_of(self, mo_code: str) -> str:
        row = self.registry_by_code.get(mo_code)
        if row is not None and isinstance(row.get("region_kato"), str):
            return row["region_kato"]
        rows = self.queue[self.queue["mo_code"] == mo_code]
        return str(rows["region_kato"].iloc[0]) if len(rows) else ""

    def organisations(self, region_kato: str, profile_code: str) -> pd.DataFrame:
        """Organisations of a region with a queue state for the profile at as_of."""
        return self.queue[(self.queue["region_kato"] == region_kato) & (self.queue["profile_code"] == profile_code)]

    # ---------- features for inference ----------
    def feature_rows(self, mo_codes: list[str], profile_code: str, icd10: str = "", referral_purpose: str = "",
                     finance_source: str = "", territorial_type: str = "", registration_date: str = "",
                     referring_mo_code: str = "") -> pd.DataFrame:
        """One feature row per organisation, in the layout of gold.features_wait. The registration date defaults
        to the day after as_of. same_mo is True when the caller names the referring organisation and it matches
        the hospital being scored; unknown (not passed) behaves exactly as before — same_mo is False."""
        when = pd.Timestamp(registration_date) if registration_date else self.as_of + pd.Timedelta(days=1)
        canon = icd10_canon(icd10) if icd10 else None
        state = self.queue[self.queue["profile_code"] == profile_code].set_index("mo_code")
        rows = []
        for mo in mo_codes:
            st = state.loc[mo] if mo in state.index else None
            rg = self.registry_by_code.get(mo)
            rows.append({
                "region_kato": (rg or {}).get("region_kato") or (st["region_kato"] if st is not None else None),
                "mo_code": mo, "profile_code": profile_code,
                "icd_chapter": icd10_chapter(canon) if canon else None, "icd_block": canon[:3] if canon else None,
                "referral_purpose": referral_purpose or None, "finance_source": finance_source or None,
                "territorial_type": territorial_type or None,
                "mo_size_bucket": (rg or {}).get("size_bucket"), "mo_type": (rg or {}).get("mo_type"),
                "queue_len": int(st["queue_len"]) if st is not None else 0,
                "queue_age_p50": st["queue_age_p50"] if st is not None else np.nan,
                "queue_age_p90": st["queue_age_p90"] if st is not None else np.nan,
                "throughput_per_day": float(st["throughput_per_day"]) if st is not None else 0.0,
                "refusal_rate_4w": st["refusal_rate_4w"] if st is not None else np.nan,
                "wait_p50_4w": st["wait_p50_4w"] if st is not None else np.nan,
                "wait_p90_4w": st["wait_p90_4w"] if st is not None else np.nan,
                # gold uses DuckDB's dayofweek (0 = Sunday) and ISO week
                "dow": (when.dayofweek + 1) % 7, "week_of_year": int(when.isocalendar().week),
                "same_mo": bool(referring_mo_code) and referring_mo_code == mo,
            })
        return pd.DataFrame(rows, columns=FEATURES)
