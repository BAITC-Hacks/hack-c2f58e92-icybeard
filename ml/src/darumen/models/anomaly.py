"""Anomaly & Alerting for any registered stream: robust z-scores against the series' own trailing window,
with a peer adjustment that separates an organisation-specific spike from a region-wide wave.

Outputs: gold/anomalies.parquet, models/anomaly/<stream>/report.json (precision on injected spikes).
"""
from __future__ import annotations

import json

import numpy as np
import pandas as pd

from ..intake.pipeline import Lakehouse
from .common import write_json
from .streams import Stream, load_series, load_streams, merge_stream_table, period_format

VERSION = "1.0.0"
MAD_TO_SIGMA = 1.4826
EPS = 1e-9


def robust_z(series: pd.DataFrame, window: int, season: int = 1) -> pd.DataFrame:
    """Per row: expected level and z against the trailing MAD; the window excludes the current point.

    With a season (7 for daily series) and at least three seasonal lags in the window, the expected value
    is the median of the same weekday in the window, so weekends are not flagged against weekdays.
    """
    out = series.sort_values(["unique_id", "ds"]).reset_index(drop=True).copy()
    min_periods = max(5, window // 2)
    groups = out.groupby("unique_id")["y"]
    lags = window // season if season > 1 else 0
    if lags >= 3:
        stacked = pd.concat([groups.shift(season * k) for k in range(1, lags + 1)], axis=1)
        expected = stacked.median(axis=1, skipna=True)
        expected[stacked.notna().sum(axis=1) < 3] = np.nan
    else:
        shifted = groups.shift(1)
        expected = shifted.groupby(out["unique_id"]).transform(lambda s: s.rolling(window, min_periods=min_periods).median())
    shifted = groups.shift(1)
    if lags >= 3:
        # multiplicative trend: recent season versus the whole window, so growing series are not flagged every period
        recent = shifted.groupby(out["unique_id"]).transform(lambda s: s.rolling(season, min_periods=max(2, season // 2)).mean())
        longer = shifted.groupby(out["unique_id"]).transform(lambda s: s.rolling(window, min_periods=min_periods).mean())
        trend = (recent / longer).clip(0.5, 2.0).where(longer > EPS, 1.0)
        expected = expected * trend.fillna(1.0)
    residual = out["y"] - expected
    past_residual = residual.groupby(out["unique_id"]).shift(1)
    mad = past_residual.abs().groupby(out["unique_id"]).transform(lambda s: s.rolling(window, min_periods=min_periods).median())
    # counts are at least Poisson-noisy and drift: the scale never falls below sqrt(level), 15 % of level, or 1
    level = expected.fillna(0.0).abs()
    floor = np.maximum(np.maximum(np.sqrt(np.maximum(level, 1.0)), 0.15 * level), 1.0)
    scale = np.maximum(MAD_TO_SIGMA * mad.fillna(0.0), floor)
    # a series that was dormant for most of the window has no baseline to deviate from
    active = (shifted > 0).astype(float).groupby(out["unique_id"]).transform(lambda s: s.rolling(window, min_periods=min_periods).mean())
    out["expected"] = expected
    out["z"] = residual / scale
    out.loc[mad.isna() | active.isna() | (active < 0.5), "z"] = np.nan
    return out


def peer_adjust(scored: pd.DataFrame, peer_keys: tuple[str, ...]) -> pd.DataFrame:
    """z minus the median z of the peer group on the same period: what is specific to this entity."""
    keys = [k for k in peer_keys if k in scored.columns]
    if not keys:
        scored["peer_z"] = scored["z"]
        scored["peer_median_z"] = 0.0
        return scored
    peer_median = scored.groupby([*keys, "ds"])["z"].transform("median")
    scored["peer_z"] = scored["z"] - peer_median
    scored["peer_median_z"] = peer_median
    return scored


def detect(series: pd.DataFrame, stream: Stream) -> pd.DataFrame:
    cfg = stream.anomaly
    window = int(cfg.get("window", 28))
    threshold = float(cfg.get("threshold", 3.5))
    scored = peer_adjust(robust_z(series, window, int(stream.forecast.get("season", 1))), stream.peer_group)
    scored = scored[scored["z"].notna()]
    flagged = scored[scored["z"].abs() >= threshold].copy()
    flagged["severity"] = np.where(flagged["z"].abs() >= 1.5 * threshold, "critical", "warning")
    # shared = the peer group as a whole moved (a regional wave), entity = this organisation alone
    flagged["kind"] = np.where(flagged["peer_median_z"].abs() >= threshold / 2, "shared", "entity")
    return flagged


def evaluate_injection(series: pd.DataFrame, stream: Stream, n_spikes: int = 200, factor: float = 3.0, seed: int = 42) -> dict:
    """Inject multiplicative spikes into real series and measure how many land in the top-k scores."""
    rng = np.random.default_rng(seed)
    window = int(stream.anomaly.get("window", 28))
    threshold = float(stream.anomaly.get("threshold", 3.5))
    df = series.sort_values(["unique_id", "ds"]).reset_index(drop=True)
    eligible = (df.groupby("unique_id").cumcount() >= window) & (df["y"] > 0)
    candidates = df.index[eligible.to_numpy()]
    if len(candidates) == 0:
        return {"injected": 0}
    chosen = rng.choice(candidates, size=min(n_spikes, len(candidates)), replace=False)
    injected = df.copy()
    injected.loc[chosen, "y"] = injected.loc[chosen, "y"] * factor + 5
    scored = robust_z(injected, window, int(stream.forecast.get("season", 1)))
    scored["injected"] = False
    scored.loc[chosen, "injected"] = True
    k = len(chosen)
    valid = scored.dropna(subset=["z"])
    top = valid.nlargest(k, "z")
    flagged = valid[valid["z"].abs() >= threshold]
    ranks = valid["z"].rank(pct=True)
    return {"injected": int(k), "factor": factor, "precision_at_k": float(top["injected"].mean()),
            "recall_at_threshold": float(flagged["injected"].sum() / k),
            "injected_rank_percentile_median": float(ranks[valid["injected"]].median()) if valid["injected"].any() else float("nan"),
            "alerts_per_1000_points": float(1000 * len(flagged) / max(len(valid), 1))}


def detect_all(lake: Lakehouse, only: list[str] | None = None) -> dict[str, dict]:
    reports = {}
    frames = []
    for stream_id, stream in load_streams().items():
        if only and stream_id not in only:
            continue
        series = load_series(lake, stream)
        if series.empty:
            reports[stream_id] = {"stream": stream_id, "skipped": "no gold table or too little history"}
            continue
        flagged = detect(series, stream)
        report = {"stream": stream_id, "series": int(series["unique_id"].nunique()), "points": len(series),
                  "alerts": len(flagged), "critical": int((flagged["severity"] == "critical").sum()),
                  "entity_specific": int((flagged["kind"] == "entity").sum()), **evaluate_injection(series, stream)}
        out_dir = lake.root / "models" / "anomaly" / stream_id
        out_dir.mkdir(parents=True, exist_ok=True)
        write_json(out_dir / "report.json", report)
        reports[stream_id] = report
        if len(flagged):
            frames.append(pd.DataFrame({
                "stream_id": stream_id,
                "entity": flagged[list(stream.entity)].apply(lambda r: json.dumps(dict(r), ensure_ascii=False), axis=1),
                "period": flagged["ds"].dt.strftime(period_format(stream.grain)),
                "observed": flagged["y"].to_numpy(), "expected": flagged["expected"].to_numpy(),
                "score": flagged["z"].to_numpy(), "peer_score": flagged["peer_z"].to_numpy(),
                "severity": flagged["severity"].to_numpy(), "kind": flagged["kind"].to_numpy(), "status": "open",
                "model": f"robust_z@{VERSION}",
                **{k: flagged[k].to_numpy() for k in stream.entity},
            }))
    gold = lake.root / "gold"
    gold.mkdir(parents=True, exist_ok=True)
    merge_stream_table(gold / "anomalies.parquet", frames, list(reports))
    return reports
