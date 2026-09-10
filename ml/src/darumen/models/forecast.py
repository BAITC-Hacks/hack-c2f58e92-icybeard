"""Load Forecasting for any registered stream: statsforecast models with a rolling-origin backtest
against the seasonal naive baseline, then final forecasts with 80 % intervals.

Outputs: gold/forecasts.parquet (all streams), models/forecast/<stream>/report.json.
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd

from ..intake.pipeline import Lakehouse
from .common import write_json
from .streams import Stream, load_series, load_streams, period_format

VERSION = "1.0.0"
LEVEL = 80


def _models(season: int):
    from statsforecast.models import AutoETS, SeasonalNaive

    return [SeasonalNaive(season_length=season), AutoETS(season_length=season)], "SeasonalNaive"


def smape(y: np.ndarray, f: np.ndarray) -> float:
    denom = np.abs(y) + np.abs(f)
    mask = denom > 0
    return float(np.mean(2 * np.abs(y[mask] - f[mask]) / denom[mask])) if mask.any() else 0.0


def mase(y: np.ndarray, f: np.ndarray, scale: float) -> float:
    return float(np.mean(np.abs(y - f)) / scale) if scale > 0 else float("nan")


def seasonal_scale(train: pd.DataFrame, season: int) -> pd.Series:
    """Per-series in-sample MAE of the seasonal naive forecast, the MASE denominator."""
    def _scale(part: pd.DataFrame) -> float:
        y = part.sort_values("ds")["y"].to_numpy()
        return float(np.mean(np.abs(y[season:] - y[:-season]))) if len(y) > season else float("nan")

    return train.groupby("unique_id").apply(_scale, include_groups=False)


def backtest(series: pd.DataFrame, stream: Stream) -> tuple[pd.DataFrame, dict]:
    from statsforecast import StatsForecast

    cfg = stream.forecast
    season = int(cfg.get("season", 1))
    h = int(max(cfg.get("horizons", [1])))
    models, baseline = _models(season)
    sf = StatsForecast(models=models, freq=stream.freq, n_jobs=-1)
    cv = sf.cross_validation(df=series[["unique_id", "ds", "y"]], h=h,
                             step_size=int(cfg.get("backtest_step", h)), n_windows=int(cfg.get("backtest_windows", 3)))
    cv = cv.reset_index() if "unique_id" not in cv.columns else cv
    cv["horizon"] = cv.groupby(["unique_id", "cutoff"]).cumcount() + 1
    scales = {cutoff: seasonal_scale(series[series["ds"] <= cutoff], season) for cutoff in cv["cutoff"].unique()}
    names = [m.__class__.__name__ for m in models]
    per_model = {}
    for name in names:
        rows = []
        for (uid, cutoff), part in cv.groupby(["unique_id", "cutoff"]):
            scale = scales[cutoff].get(uid, float("nan"))
            rows.append({"unique_id": uid, "smape": smape(part["y"].to_numpy(), part[name].to_numpy()),
                         "mase": mase(part["y"].to_numpy(), part[name].to_numpy(), scale)})
        frame = pd.DataFrame(rows)
        by_h = {int(hz): smape(g["y"].to_numpy(), g[name].to_numpy()) for hz, g in cv.groupby("horizon")}
        per_model[name] = {"smape": float(frame["smape"].mean()), "mase": float(np.nanmean(frame["mase"])),
                           "smape_by_horizon": by_h, "series_better_than_baseline": None}
    for name in names:
        if name == baseline:
            continue
        wins = total = 0
        for _, part in cv.groupby("unique_id"):
            total += 1
            wins += int(np.mean(np.abs(part["y"] - part[name])) < np.mean(np.abs(part["y"] - part[baseline])))
        per_model[name]["series_better_than_baseline"] = wins / total if total else None
    # базовая модель тоже кандидат: если сезонный наив точнее, в прогноз идёт он, а не худшая модель
    best = min(names, key=lambda n: per_model[n]["mase"])
    report = {"stream": stream.stream_id, "series": int(series["unique_id"].nunique()), "horizon": h, "season": season,
              "windows": int(cfg.get("backtest_windows", 3)), "baseline": baseline, "chosen": best, "models": per_model}
    return cv, report


def forecast_stream(lake: Lakehouse, stream: Stream, out_dir: Path) -> tuple[pd.DataFrame, dict]:
    from statsforecast import StatsForecast

    series = load_series(lake, stream)
    if series.empty:
        return pd.DataFrame(), {"stream": stream.stream_id, "series": 0, "skipped": "no gold table or too little history"}
    cv, report = backtest(series, stream)
    cfg = stream.forecast
    season = int(cfg.get("season", 1))
    h = int(max(cfg.get("horizons", [1])))
    models, _ = _models(season)
    sf = StatsForecast(models=models, freq=stream.freq, n_jobs=-1)
    fc = sf.forecast(df=series[["unique_id", "ds", "y"]], h=h, level=[LEVEL])
    fc = fc.reset_index() if "unique_id" not in fc.columns else fc
    chosen = report["chosen"]
    entities = series.drop_duplicates("unique_id").set_index("unique_id")[list(stream.entity)]
    fc = fc.join(entities, on="unique_id")
    fc["horizon"] = fc.groupby("unique_id").cumcount() + 1
    lo = fc[f"{chosen}-lo-{LEVEL}"] if f"{chosen}-lo-{LEVEL}" in fc else fc[chosen]
    hi = fc[f"{chosen}-hi-{LEVEL}"] if f"{chosen}-hi-{LEVEL}" in fc else fc[chosen]
    out = pd.DataFrame({
        "stream_id": stream.stream_id,
        "entity": fc[list(stream.entity)].apply(lambda r: json.dumps(dict(r), ensure_ascii=False), axis=1),
        "period": fc["ds"].dt.strftime(period_format(stream.grain)),
        "horizon": fc["horizon"].astype(int),
        "yhat": np.clip(fc[chosen].to_numpy(), 0, None),
        "lo": np.clip(np.minimum(lo.to_numpy(), fc[chosen].to_numpy()), 0, None),
        "hi": np.clip(np.maximum(hi.to_numpy(), fc[chosen].to_numpy()), 0, None),
        "model": f"{chosen}@{VERSION}",
    })
    for k in stream.entity:
        out[k] = fc[k].to_numpy()
    out_dir.mkdir(parents=True, exist_ok=True)
    write_json(out_dir / "report.json", report)
    cv.to_parquet(out_dir / "backtest.parquet", index=False)
    return out, report


def forecast_all(lake: Lakehouse, only: list[str] | None = None) -> dict[str, dict]:
    reports = {}
    frames = []
    for stream_id, stream in load_streams().items():
        if only and stream_id not in only:
            continue
        frame, report = forecast_stream(lake, stream, lake.root / "models" / "forecast" / stream_id)
        reports[stream_id] = report
        if len(frame):
            frames.append(frame)
    if frames:
        gold = lake.root / "gold"
        gold.mkdir(parents=True, exist_ok=True)
        pd.concat(frames, ignore_index=True).to_parquet(gold / "forecasts.parquet", index=False)
    return reports
