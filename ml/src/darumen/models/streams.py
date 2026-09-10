"""Stream declarations (streams/*.yaml) and loading of their series from gold.

A stream is a declared time series family: which gold table, which entity keys, which measure and
grain. Forecasting and anomaly detection work on any registered stream without stream-specific code.
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import duckdb
import pandas as pd
import yaml

from ..intake.pipeline import Lakehouse

STREAMS_DIR = Path(__file__).resolve().parents[4] / "streams"
FREQ = {"day": "D", "month": "MS"}
INCOMPLETE_TAIL_RATIO = 0.6  # trailing periods below this share of the trailing-year median are still being loaded


@dataclass(frozen=True)
class Stream:
    stream_id: str
    title: str
    table: str
    time_col: str
    y_col: str
    entity: tuple[str, ...]
    grain: str
    peer_group: tuple[str, ...]
    forecast: dict
    anomaly: dict

    @property
    def freq(self) -> str:
        return FREQ[self.grain]

    @classmethod
    def from_yaml(cls, path: Path) -> Stream:
        raw = yaml.safe_load(path.read_text(encoding="utf-8"))
        gold = raw["gold"]
        return cls(raw["stream"], raw.get("title", raw["stream"]), gold["table"], gold["time"], gold["y"],
                   tuple(raw["entity"]), raw["time"]["grain"], tuple(raw.get("peer_group", ())),
                   raw.get("forecast", {}), raw.get("anomaly", {}))


def load_streams(directory: Path = STREAMS_DIR) -> dict[str, Stream]:
    return {s.stream_id: s for s in (Stream.from_yaml(p) for p in sorted(directory.glob("*.yaml")))}


def load_series(lake: Lakehouse, stream: Stream) -> pd.DataFrame:
    """Series in statsforecast layout: unique_id, ds, y, plus the entity columns. Gaps are filled with 0,
    the incomplete trailing periods (still being loaded at the source) are dropped."""
    empty = pd.DataFrame(columns=["unique_id", "ds", "y", *stream.entity])
    path = lake.root / "gold" / f"{stream.table}.parquet"
    if not path.exists():
        return empty
    keys = ", ".join(f'"{k}"' for k in stream.entity)
    con = duckdb.connect()
    try:
        df = con.execute(
            f"SELECT {keys}, \"{stream.time_col}\"::DATE AS ds, sum(\"{stream.y_col}\")::DOUBLE AS y "
            f"FROM read_parquet('{path}') GROUP BY ALL ORDER BY ALL"
        ).df()
    finally:
        con.close()
    if df.empty:
        return empty
    df["ds"] = pd.to_datetime(df["ds"])
    df["unique_id"] = df[list(stream.entity)].astype(str).agg("|".join, axis=1)
    df = _drop_incomplete_tail(df, stream)
    filled = []
    for uid, part in df.groupby("unique_id", sort=False):
        idx = pd.date_range(part["ds"].min(), df["ds"].max(), freq=stream.freq)
        series = part.set_index("ds")["y"].reindex(idx, fill_value=0.0)
        block = pd.DataFrame({"unique_id": uid, "ds": idx, "y": series.to_numpy()})
        for k in stream.entity:
            block[k] = part[k].iloc[0]
        filled.append(block)
    out = pd.concat(filled, ignore_index=True)
    min_history = int(stream.forecast.get("min_history", 0))
    lengths = out.groupby("unique_id")["ds"].transform("size")
    return out[lengths >= min_history].reset_index(drop=True)


def _drop_incomplete_tail(df: pd.DataFrame, stream: Stream) -> pd.DataFrame:
    """The source keeps loading recent periods; the last months of the treated-cases list are visibly partial."""
    totals = df.groupby("ds")["y"].sum().sort_index()
    season = int(stream.forecast.get("season", 1))
    if len(totals) <= season + 1:
        return df
    reference = totals.iloc[-(season + 1):-1].median()
    last_complete = totals.index[-1]
    for ds, value in totals[::-1].items():
        if value >= INCOMPLETE_TAIL_RATIO * reference:
            last_complete = ds
            break
    return df[df["ds"] <= last_complete]
