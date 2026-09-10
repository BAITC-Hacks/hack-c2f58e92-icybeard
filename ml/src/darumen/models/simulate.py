"""Simulation & Optimization: a transparent fluid queue per organisation and profile, calibrated on
realised waits, with what-if scenarios (capacity, redirected arrivals) and greedy redistribution.

State per (organisation, profile): arrivals per day λ, admissions per day μ, open queue L.
Fluid dynamics: L[t+1] = max(0, L[t] + λ − μ); the wait of an arrival at day t ≈ k · L[t] / μ, where k is a
per-profile calibration factor fitted so that k · L / μ matches the realised median wait in the data.
Everything is inspectable: the scenario answer is a handful of numbers a regulator can recompute by hand.
"""
from __future__ import annotations

import json
from dataclasses import dataclass, replace

import duckdb
import numpy as np
import pandas as pd

from ..intake.pipeline import Lakehouse
from .common import write_json

VERSION = "1.0.0"
WINDOW_DAYS = 28
MAX_WAIT_DAYS = 365.0
DAY_HOSPITAL = "DH"
ARRIVAL_BAND = 0.2  # ±20 % on arrivals gives the scenario interval


@dataclass(frozen=True)
class QueueState:
    mo_code: str
    profile_code: str
    region_kato: str
    arrivals_per_day: float
    admissions_per_day: float
    queue_len: float
    calibration: float = 1.0


def fluid_wait(state: QueueState, horizon_days: int = 90, capacity_delta_pct: float = 0.0, arrivals_delta_pct: float = 0.0) -> dict:
    """Mean and end-of-horizon wait (days) under the fluid model for a scenario."""
    mu = max(state.admissions_per_day * (1 + capacity_delta_pct / 100), 1e-6)
    lam = max(state.arrivals_per_day * (1 + arrivals_delta_pct / 100), 0.0)
    queue = state.queue_len
    waits = []
    for _ in range(horizon_days):
        waits.append(min(state.calibration * queue / mu, MAX_WAIT_DAYS))
        queue = max(0.0, queue + lam - mu)
    return {"mean_wait_days": float(np.mean(waits)), "end_wait_days": float(waits[-1]),
            "end_queue": float(queue), "arrivals_per_day": lam, "admissions_per_day": mu}


def simulate(state: QueueState, capacity_delta_pct: float = 0.0, redirect_share_pct: float = 0.0, horizon_days: int = 90) -> dict:
    base = fluid_wait(state, horizon_days)
    scenario = fluid_wait(state, horizon_days, capacity_delta_pct, -redirect_share_pct)
    band = [fluid_wait(replace(state, arrivals_per_day=state.arrivals_per_day * f), horizon_days, capacity_delta_pct, -redirect_share_pct)
            for f in (1 - ARRIVAL_BAND, 1 + ARRIVAL_BAND)]
    delta = scenario["mean_wait_days"] - base["mean_wait_days"]
    return {
        "baseline": base, "scenario": scenario, "delta_days": float(delta),
        "ci": sorted(float(b["mean_wait_days"] - base["mean_wait_days"]) for b in band),
        "assumptions": [
            (f"поток направлений {state.arrivals_per_day:.2f} в день и пропускная способность {state.admissions_per_day:.2f} в день "
             f"взяты за последние {WINDOW_DAYS} дней"),
            f"калибровка профиля k = {state.calibration:.2f}: ожидание ≈ k × очередь / пропускная способность",
            f"интервал: поток направлений ±{ARRIVAL_BAND:.0%}",
        ],
        "model": f"fluid_queue@{VERSION}",
    }


# ---------- calibration and states from gold ------------------------------------------------------

def calibrate(features: pd.DataFrame) -> dict[str, float]:
    """k per profile: median of realised wait / (queue / throughput) over referrals with a defined load."""
    df = features[(features["throughput_per_day"] > 0) & features["wait_p50_4w"].notna() & (features["queue_len"] > 0)]
    ratio = df["wait_p50_4w"] / (df["queue_len"] / df["throughput_per_day"])
    df = df.assign(ratio=ratio)[np.isfinite(ratio)]
    by_profile = df.groupby("profile_code")["ratio"].median().clip(0.05, 5.0)
    overall = float(df["ratio"].median()) if len(df) else 1.0
    return {"__default__": min(max(overall, 0.05), 5.0), **{k: float(v) for k, v in by_profile.items()}}


def load_states(lake: Lakehouse, as_of: str | None = None, calibration: dict[str, float] | None = None) -> pd.DataFrame:
    """Latest queue state per organisation and profile from queue_daily and throughput_4w."""
    con = duckdb.connect()
    try:
        q = f"read_parquet('{lake.root / 'gold' / 'queue_daily.parquet'}')"
        t = f"read_parquet('{lake.root / 'gold' / 'throughput_4w.parquet'}')"
        day_filter = f"WHERE day <= DATE '{as_of}'" if as_of else ""
        states = con.execute(f"""
            WITH last AS (SELECT max(day) AS day FROM {q} {day_filter})
            SELECT q.mo_code, q.profile_code, q.region_kato, q.day AS as_of,
                   t.registered_4w / {WINDOW_DAYS}.0 AS arrivals_per_day,
                   t.throughput_per_day AS admissions_per_day,
                   q.queue_len::DOUBLE AS queue_len,
                   t.wait_p50_4w
            FROM {q} q JOIN last USING (day)
            JOIN {t} t USING (day, mo_code, profile_code)
            WHERE q.profile_code <> '{DAY_HOSPITAL}'""").df()
    finally:
        con.close()
    calibration = calibration or {"__default__": 1.0}
    default = calibration.get("__default__", 1.0)
    return states.assign(calibration=states["profile_code"].map(calibration).fillna(default))


def _state(row) -> QueueState:
    return QueueState(row.mo_code, row.profile_code, row.region_kato, float(row.arrivals_per_day),
                      float(row.admissions_per_day), float(row.queue_len), float(row.calibration))


# ---------- redistribution ------------------------------------------------------------------------------

def _total_wait_days(base_states: dict[str, QueueState], arrivals: dict[str, float], horizon_days: int) -> float:
    return sum(fluid_wait(replace(st, arrivals_per_day=arrivals[mo]), horizon_days)["mean_wait_days"] * arrivals[mo] * horizon_days
               for mo, st in base_states.items())


def _waits(base_states: dict[str, QueueState], arrivals: dict[str, float], horizon_days: int) -> dict[str, float]:
    return {mo: fluid_wait(replace(st, arrivals_per_day=arrivals[mo]), horizon_days)["mean_wait_days"] for mo, st in base_states.items()}


def redistribute(states: pd.DataFrame, region_kato: str, profile_code: str, max_share_moved_pct: float = 20.0,
                 step_pct: float = 5.0, horizon_days: int = 90, min_admissions_per_day: float = 0.2, min_gain_days: float = 0.5) -> dict:
    """Greedy: move arrival share from the organisation with the longest expected wait to the one with the
    shortest, in steps, while the total expected waiting days over the horizon keep falling."""
    group = states[(states["region_kato"] == region_kato) & (states["profile_code"] == profile_code)
                   & (states["admissions_per_day"] >= min_admissions_per_day)]
    if len(group) < 2:
        return {"moves": [], "total_delta_days": 0.0, "reason": "fewer than two organisations with capacity"}
    base_states = {r.mo_code: _state(r) for r in group.itertuples()}
    original = {mo: st.arrivals_per_day for mo, st in base_states.items()}
    arrivals = dict(original)
    moved_out = dict.fromkeys(original, 0.0)
    cap = {mo: original[mo] * max_share_moved_pct / 100 for mo in original}
    before = _total_wait_days(base_states, arrivals, horizon_days)
    merged: dict[tuple[str, str], float] = {}
    for _ in range(200):
        w = _waits(base_states, arrivals, horizon_days)
        donors = [mo for mo in arrivals if moved_out[mo] < cap[mo] and arrivals[mo] > 0]
        if not donors:
            break
        source = max(donors, key=lambda m: w[m])
        target = min(arrivals, key=lambda m: w[m])
        if source == target or w[source] - w[target] < min_gain_days:
            break
        amount = min(original[source] * step_pct / 100, cap[source] - moved_out[source])
        trial = {**arrivals, source: arrivals[source] - amount, target: arrivals[target] + amount}
        if _total_wait_days(base_states, trial, horizon_days) >= _total_wait_days(base_states, arrivals, horizon_days):
            break
        arrivals = trial
        moved_out = {**moved_out, source: moved_out[source] + amount}
        merged = {**merged, (source, target): merged.get((source, target), 0.0) + amount}
    after = _total_wait_days(base_states, arrivals, horizon_days)
    w_before, w_after = _waits(base_states, original, horizon_days), _waits(base_states, arrivals, horizon_days)
    return {
        "moves": [{"from_mo": a, "to_mo": b, "share_of_source_pct": float(100 * v / original[a]) if original[a] else 0.0,
                   "arrivals_per_day": float(v), "wait_from_before": w_before[a], "wait_from_after": w_after[a],
                   "wait_to_before": w_before[b], "wait_to_after": w_after[b]} for (a, b), v in merged.items()],
        "total_wait_days_before": float(before), "total_wait_days_after": float(after),
        "total_delta_days": float(after - before), "horizon_days": horizon_days, "model": f"fluid_queue@{VERSION}",
    }


def _redistribution_table(states: pd.DataFrame, arrival_factor: float, max_share_moved_pct: float, horizon_days: int) -> pd.DataFrame:
    scaled = states.assign(arrivals_per_day=states["arrivals_per_day"] * arrival_factor)
    rows = []
    for (region, profile), _ in scaled.groupby(["region_kato", "profile_code"]):
        result = redistribute(scaled, region, profile, max_share_moved_pct=max_share_moved_pct, horizon_days=horizon_days)
        if result["moves"]:
            rows.append({"region_kato": region, "profile_code": profile, "moves": len(result["moves"]),
                         "wait_days_before": result["total_wait_days_before"], "wait_days_after": result["total_wait_days_after"],
                         "saved_days": -result["total_delta_days"],
                         "moves_detail": json.dumps(result["moves"], ensure_ascii=False)})
    return pd.DataFrame(rows, columns=["region_kato", "profile_code", "moves", "wait_days_before", "wait_days_after", "saved_days", "moves_detail"])


def consistency_with_observed(states: pd.DataFrame, horizon_days: int = 1) -> dict:
    """How well the calibrated fluid wait at as_of matches the realised median wait of the last four weeks."""
    df = states[states["wait_p50_4w"].notna() & (states["admissions_per_day"] > 0)]
    if len(df) < 3:
        return {"n": len(df), "mae_days": float("nan"), "spearman": float("nan")}
    predicted = np.array([fluid_wait(_state(r), horizon_days)["mean_wait_days"] for r in df.itertuples()])
    observed = df["wait_p50_4w"].to_numpy(dtype=float)
    spearman = float(pd.Series(predicted).rank().corr(pd.Series(observed).rank()))
    return {"n": len(df), "mae_days": float(np.mean(np.abs(predicted - observed))), "spearman": spearman,
            "median_predicted_days": float(np.median(predicted)), "median_observed_days": float(np.median(observed))}


def counterfactual_q1(lake: Lakehouse, as_of: str = "2025-01-29", max_share_moved_pct: float = 20.0, horizon_days: int = 60) -> dict:
    """Headline number: waiting days the fluid model attributes to redistribution within region and profile,
    starting after four weeks of warm-up in Q1 2025. The band re-runs the optimisation with arrivals ±20 %."""
    features = pd.read_parquet(lake.root / "gold" / "features_wait.parquet")
    calibration = calibrate(features)
    states = load_states(lake, as_of=as_of, calibration=calibration)
    table = _redistribution_table(states, 1.0, max_share_moved_pct, horizon_days)
    band = [_redistribution_table(states, f, max_share_moved_pct, horizon_days) for f in (1 - ARRIVAL_BAND, 1 + ARRIVAL_BAND)]
    before = float(table["wait_days_before"].sum())
    saved = float(table["saved_days"].sum())
    saved_band = sorted(float(t["saved_days"].sum()) for t in band)
    summary = {
        "as_of": as_of, "horizon_days": horizon_days, "max_share_moved_pct": max_share_moved_pct,
        "groups_with_moves": len(table), "organisations": int(states["mo_code"].nunique()),
        "wait_days_before": before, "wait_days_after": before - saved, "saved_days": saved,
        "saved_days_band": saved_band, "saved_share": saved / before if before else 0.0,
        "saved_share_band": [v / before if before else 0.0 for v in saved_band],
        "consistency": consistency_with_observed(states),
        "calibration": calibration, "model": f"fluid_queue@{VERSION}",
    }
    out = lake.root / "gold"
    out.mkdir(parents=True, exist_ok=True)
    if len(table):
        table.to_parquet(out / "redistribution_q1.parquet", index=False)
    write_json(lake.root / "models" / "simulate" / "counterfactual_q1.json", summary)
    write_json(lake.root / "models" / "simulate" / "calibration.json", calibration)
    return summary


def load_calibration(lake: Lakehouse) -> dict[str, float]:
    path = lake.root / "models" / "simulate" / "calibration.json"
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {"__default__": 1.0}


def simulate_states(states: pd.DataFrame, region_kato: str, profile_code: str, capacity_delta_pct: float = 0.0,
                    redirect_share_pct: float = 0.0, horizon_days: int = 90) -> dict:
    """Scenario for all organisations of a region and profile, aggregated with arrival weights."""
    group = states[(states["region_kato"] == region_kato) & (states["profile_code"] == profile_code)]
    if group.empty:
        return {"error": "no organisations for this region and profile"}
    results = [simulate(_state(r), capacity_delta_pct, redirect_share_pct, horizon_days) for r in group.itertuples()]
    raw = group["arrivals_per_day"].to_numpy()
    weights = raw / raw.sum() if raw.sum() else np.full(len(group), 1.0 / len(group))

    def agg(values) -> float:
        return float(np.dot(np.asarray(list(values)), weights))

    baseline, scenario = agg(r["baseline"]["mean_wait_days"] for r in results), agg(r["scenario"]["mean_wait_days"] for r in results)
    return {"organisations": len(group), "baseline": {"mean_wait_days": baseline}, "scenario": {"mean_wait_days": scenario},
            "delta_days": scenario - baseline, "ci": [agg(r["ci"][0] for r in results), agg(r["ci"][1] for r in results)],
            "assumptions": results[0]["assumptions"], "model": f"fluid_queue@{VERSION}"}


def simulate_group(lake: Lakehouse, region_kato: str, profile_code: str, capacity_delta_pct: float = 0.0,
                   redirect_share_pct: float = 0.0, horizon_days: int = 90, as_of: str | None = None) -> dict:
    states = load_states(lake, as_of=as_of, calibration=load_calibration(lake))
    return simulate_states(states, region_kato, profile_code, capacity_delta_pct, redirect_share_pct, horizon_days)
