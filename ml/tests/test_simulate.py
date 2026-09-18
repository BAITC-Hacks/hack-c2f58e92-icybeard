import pandas as pd

from darumen.models.simulate import QueueState, calibrate, fluid_wait, redistribute, simulate, simulate_states


def test_fluid_queue_drains_when_capacity_exceeds_arrivals():
    st = QueueState("A", "021", "10", arrivals_per_day=2.0, admissions_per_day=4.0, queue_len=40.0)
    res = fluid_wait(st, horizon_days=30)
    assert res["end_queue"] == 0.0 and res["mean_wait_days"] < 10.0


def test_capacity_scenario_reduces_wait_and_ci_brackets_delta():
    st = QueueState("A", "021", "10", arrivals_per_day=5.0, admissions_per_day=4.0, queue_len=100.0, calibration=1.0)
    out = simulate(st, capacity_delta_pct=25.0, horizon_days=60)
    assert out["delta_days"] < 0
    assert out["ci"][0] <= out["delta_days"] <= out["ci"][1]
    assert out["scenario"]["admissions_per_day"] == 5.0


def test_beds_delta_adds_admissions_capacity_via_fluid_wait():
    st = QueueState("A", "021", "10", arrivals_per_day=5.0, admissions_per_day=4.0, queue_len=100.0, calibration=1.0)
    out = simulate(st, horizon_days=60, admissions_delta=2.0)
    assert out["scenario"]["admissions_per_day"] == 6.0
    assert out["delta_days"] < 0
    assert any("коек" in a for a in out["assumptions"])


def test_simulate_states_distributes_beds_delta_by_arrival_share_and_reports_admissions():
    states = pd.DataFrame([
        {"mo_code": "BIG", "profile_code": "381", "region_kato": "75", "arrivals_per_day": 8.0, "admissions_per_day": 4.0, "queue_len": 100.0, "calibration": 1.0},
        {"mo_code": "SMALL", "profile_code": "381", "region_kato": "75", "arrivals_per_day": 2.0, "admissions_per_day": 4.0, "queue_len": 10.0, "calibration": 1.0},
    ])
    without = simulate_states(states, "75", "381", horizon_days=60)
    assert without["admissions_per_day"] == 8.0

    with_beds = simulate_states(states, "75", "381", horizon_days=60, beds_delta=10.0, los_days=5.0)
    assert with_beds["admissions_per_day"] == 10.0  # +10 коек / 5 дней LOS = +2 госпитализации/день суммарно
    assert with_beds["scenario"]["mean_wait_days"] < without["scenario"]["mean_wait_days"]


def test_simulate_states_ignores_beds_delta_without_los():
    states = pd.DataFrame([{"mo_code": "ONLY", "profile_code": "381", "region_kato": "75", "arrivals_per_day": 2.0,
                            "admissions_per_day": 4.0, "queue_len": 10.0, "calibration": 1.0}])
    result = simulate_states(states, "75", "381", horizon_days=60, beds_delta=10.0, los_days=None)
    assert result["admissions_per_day"] == 4.0


def test_redistribution_moves_from_slow_to_fast():
    states = pd.DataFrame([
        {"mo_code": "SLOW", "profile_code": "381", "region_kato": "75", "arrivals_per_day": 6.0, "admissions_per_day": 4.0, "queue_len": 300.0, "calibration": 1.0},
        {"mo_code": "FAST", "profile_code": "381", "region_kato": "75", "arrivals_per_day": 1.0, "admissions_per_day": 4.0, "queue_len": 5.0, "calibration": 1.0},
        {"mo_code": "OTHER", "profile_code": "021", "region_kato": "75", "arrivals_per_day": 1.0, "admissions_per_day": 4.0, "queue_len": 5.0, "calibration": 1.0},
    ])
    result = redistribute(states, "75", "381", max_share_moved_pct=20.0, horizon_days=60)
    assert result["moves"] and result["moves"][0]["from_mo"] == "SLOW" and result["moves"][0]["to_mo"] == "FAST"
    assert result["total_delta_days"] < 0
    assert result["moves"][0]["share_of_source_pct"] <= 20.0 + 1e-9
    assert result["moves"][0]["wait_from_after"] < result["moves"][0]["wait_from_before"]


def test_redistribution_needs_two_organisations():
    states = pd.DataFrame([{"mo_code": "ONLY", "profile_code": "381", "region_kato": "75", "arrivals_per_day": 6.0,
                            "admissions_per_day": 4.0, "queue_len": 300.0, "calibration": 1.0}])
    assert redistribute(states, "75", "381")["moves"] == []


def test_calibration_recovers_ratio():
    features = pd.DataFrame({"profile_code": ["021"] * 50 + ["381"] * 50,
                             "queue_len": [40.0] * 100, "throughput_per_day": [4.0] * 100,
                             "wait_p50_4w": [5.0] * 50 + [20.0] * 50})
    k = calibrate(features)
    assert abs(k["021"] - 0.5) < 1e-9 and abs(k["381"] - 2.0) < 1e-9 and 0.5 <= k["__default__"] <= 2.0


def test_consistency_reports_rank_agreement():
    from darumen.models.simulate import consistency_with_observed
    states = pd.DataFrame([
        {"mo_code": f"M{i}", "profile_code": "381", "region_kato": "75", "arrivals_per_day": 2.0, "admissions_per_day": 2.0,
         "queue_len": float(10 * (i + 1)), "calibration": 1.0, "wait_p50_4w": float(5 * (i + 1))} for i in range(6)])
    c = consistency_with_observed(states)
    assert c["n"] == 6 and c["spearman"] > 0.99 and abs(c["mae_days"]) < 1e-9
