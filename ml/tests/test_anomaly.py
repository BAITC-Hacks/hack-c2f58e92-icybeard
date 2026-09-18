import numpy as np
import pandas as pd

from darumen.models.anomaly import detect, evaluate_injection, robust_z
from darumen.models.streams import Stream

STREAM = Stream("er_visits_daily", "t", "er_visits_daily", "day", "visits", ("region_kato", "mo_key"), "day",
                ("region_kato",), {"season": 7, "min_history": 60}, {"window": 28, "threshold": 3.5})


def _daily(n_series=6, days=120, seed=3):
    rng = np.random.default_rng(seed)
    rows = []
    for i in range(n_series):
        base = 20 + 5 * i
        for d in range(days):
            ds = pd.Timestamp("2025-01-01") + pd.Timedelta(days=d)
            rows.append({"unique_id": f"10|org{i}", "region_kato": "10", "mo_key": f"org{i}", "ds": ds,
                         "y": float(rng.poisson(base * (1.2 if ds.dayofweek < 5 else 0.8)))})
    return pd.DataFrame(rows)


def test_spike_is_detected_and_quiet_series_is_not():
    df = _daily()
    df.loc[(df["unique_id"] == "10|org0") & (df["ds"] == "2025-03-15"), "y"] = 200.0
    flagged = detect(df, STREAM)
    hits = flagged[(flagged["unique_id"] == "10|org0") & (flagged["ds"] == "2025-03-15")]
    assert len(hits) == 1 and hits["severity"].iloc[0] == "critical" and hits["kind"].iloc[0] == "entity"
    assert len(flagged) <= 8  # no more than a handful of false alarms on Poisson noise


def test_shared_wave_collapses_into_one_signal_per_region_and_period():
    """3.3: a region-wide wave used to flag every organisation separately, flooding the feed with one row per
    organisation for what is really one event. It now collapses to a single row per (peer group, period) —
    here peer_group is (region_kato,), so one row for the whole region, not six for the six organisations."""
    df = _daily()
    df.loc[df["ds"] == "2025-03-20", "y"] *= 4  # every organisation in the region spikes the same day
    flagged = detect(df, STREAM)
    wave = flagged[flagged["ds"] == "2025-03-20"]
    assert len(wave) == 1
    row = wave.iloc[0]
    assert row["kind"] == "shared" and row["affected"] == 6
    assert row["region_kato"] == "10" and pd.isna(row["mo_key"])  # различающий ключ пуст — сигнал не про одну организацию


def test_entity_specific_spike_is_not_collapsed():
    """Обычный сигнал по одной организации (kind == entity) не трогается: affected остаётся NaN, mo_key на месте."""
    df = _daily()
    df.loc[(df["unique_id"] == "10|org0") & (df["ds"] == "2025-03-15"), "y"] = 200.0
    flagged = detect(df, STREAM)
    hit = flagged[(flagged["unique_id"] == "10|org0") & (flagged["ds"] == "2025-03-15")].iloc[0]
    assert hit["kind"] == "entity" and pd.isna(hit["affected"]) and hit["mo_key"] == "org0"


def test_robust_z_excludes_current_point():
    df = _daily(n_series=1)
    scored = robust_z(df, 28)
    assert scored["z"].isna().sum() >= 5  # warm-up
    assert scored["expected"].iloc[-1] == df["y"].iloc[-29:-1].median()
    weekly = robust_z(df, 28, season=7)
    same_weekday = [df["y"].iloc[-1 - 7 * k] for k in range(1, 5)]
    assert abs(weekly["expected"].iloc[-1] - np.median(same_weekday)) <= 0.15 * np.median(same_weekday)  # stationary: trend ≈ 1


def test_injection_evaluation_has_high_precision():
    report = evaluate_injection(_daily(n_series=10, days=150), STREAM, n_spikes=40, factor=3.0)
    assert report["injected"] == 40 and report["precision_at_k"] >= 0.8 and report["recall_at_threshold"] >= 0.8
