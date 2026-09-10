import json

import grpc
import pandas as pd
import pytest
from grpc_health.v1 import health_pb2, health_pb2_grpc
from test_models import synthetic_features

from darumen.intake.pipeline import Lakehouse
from darumen.models.streams import Stream
from darumen.models.wait import train_wait
from darumen.services.server import build_server
from darumen.services.state import ModelState, haversine_km
from darumen.v1 import (
    common_pb2,
    forecast_pb2,
    forecast_pb2_grpc,
    queue_pb2,
    queue_pb2_grpc,
    simulation_pb2,
    simulation_pb2_grpc,
)

STREAM = Stream("er_visits_daily", "t", "er_visits_daily", "day", "visits", ("region_kato", "mo_key"), "day",
                ("region_kato",), {"season": 7, "horizons": [7]}, {"window": 28, "threshold": 3.5})
PROFILES = ("021", "381")


def _write_lake(root) -> Lakehouse:
    df = synthetic_features(n=2500)
    train_wait(df, root / "models" / "wait", trained_through="2025-02-28")
    gold = root / "gold"
    gold.mkdir()
    df.to_parquet(gold / "features_wait.parquet", index=False)
    as_of = pd.Timestamp(df["registration_date"].max()).date()
    mos = sorted(df["mo_code"].unique())
    pd.DataFrame([{"day": as_of, "region_kato": "10", "mo_code": m, "profile_code": p, "registered": 3, "hospitalized": 2, "refused": 0,
                   "queue_len": 10 * (i + 1), "queue_age_p50": 5.0, "queue_age_p90": 12.0}
                  for i, m in enumerate(mos) for p in PROFILES]).to_parquet(gold / "queue_daily.parquet", index=False)
    pd.DataFrame([{"day": as_of, "mo_code": m, "profile_code": p, "hospitalized_4w": 56, "registered_4w": 60 + i, "refused_4w": 2,
                   "throughput_per_day": 2.0, "refusal_rate_4w": 0.03, "wait_p50_4w": 4.0 + i, "wait_p90_4w": 9.0 + i}
                  for i, m in enumerate(mos) for p in PROFILES]).to_parquet(gold / "throughput_4w.parquet", index=False)
    (root / "refdata").mkdir()
    pd.DataFrame([{"mo_code": m, "name_canonical": f"Больница {m}", "region_kato": "10", "mo_type": "hospital", "size_bucket": "M",
                   "lat": 49.0 + i * 0.1, "lon": 80.0} for i, m in enumerate(mos)]).to_parquet(root / "refdata" / "mo_registry.parquet", index=False)
    pd.DataFrame([{"stream_id": "er_visits_daily", "entity": json.dumps({"region_kato": "10", "mo_key": "org a"}), "period": f"2025-04-{d:02d}",
                   "horizon": d, "yhat": 20.0 + d, "lo": 15.0, "hi": 25.0 + d, "model": "AutoETS@1.0.0", "region_kato": "10", "mo_key": "org a"}
                  for d in range(1, 8)]).to_parquet(gold / "forecasts.parquet", index=False)
    fdir = root / "models" / "forecast" / "er_visits_daily"
    fdir.mkdir(parents=True)
    (fdir / "report.json").write_text(json.dumps({"stream": "er_visits_daily", "chosen": "AutoETS", "baseline": "SeasonalNaive",
                                                  "models": {"AutoETS": {"mase": 0.8}, "SeasonalNaive": {"mase": 1.0}}}), encoding="utf-8")
    pd.DataFrame({"unique_id": ["10|org a"] * 3, "ds": pd.date_range("2025-03-01", periods=3), "cutoff": pd.Timestamp("2025-02-28"),
                  "y": [20.0, 22.0, 24.0], "SeasonalNaive": [18.0, 18.0, 18.0], "AutoETS": [21.0, 22.0, 23.0], "horizon": [1, 2, 3]}
                 ).to_parquet(fdir / "backtest.parquet", index=False)
    return Lakehouse(root)


@pytest.fixture(scope="module")
def served(tmp_path_factory):
    lake = _write_lake(tmp_path_factory.mktemp("lake"))
    state = ModelState.load(lake, streams={"er_visits_daily": STREAM})
    server, port = build_server(state, "localhost:0")
    server.start()
    channel = grpc.insecure_channel(f"localhost:{port}")
    yield state, queue_pb2_grpc.QueueIntelligenceStub(channel), forecast_pb2_grpc.LoadForecastingStub(channel), channel
    channel.close()
    server.stop(0)


def _request(mo_code="0003", region="10", profile_code="381"):
    return queue_pb2.PredictWaitRequest(region=common_pb2.RegionRef(kato=region), mo_code=mo_code, profile_code=profile_code,
                                        icd10="H25.1", referral_purpose="Оперативное лечение", territorial_type="Город",
                                        finance_source="Активы Фонда на ОСМС", registration_date="2025-04-01")


def test_state_as_of_and_feature_layout(served):
    state = served[0]
    assert str(state.as_of.date()) == "2025-03-31" and len(state.queue) == 24
    row = state.feature_rows(["0003"], "381", icd10=" h25.1", registration_date="2025-04-01").iloc[0]
    assert row["queue_len"] == 40 and row["icd_block"] == "H25" and row["icd_chapter"] == "VII"
    assert row["dow"] == 2 and row["week_of_year"] == 14  # Tuesday in DuckDB numbering (0 = Sunday)
    assert row["mo_size_bucket"] == "M" and row["region_kato"] == "10"


def test_predict_wait_for_organisation(served):
    _, queue, _, _ = served
    res = queue.PredictWait(_request())
    assert res.p90_days >= res.p50_days >= 0 and 0 <= res.p_within_30_days <= 1
    assert res.explanation.factors and res.explanation.factors[0].text_kz and "дн." in res.explanation.factors[0].text_ru
    assert res.model.name == "wait_quantile" and res.model.trained_through == "2025-02-28"


def test_predict_wait_for_region_without_organisation(served):
    _, queue, _, _ = served
    res = queue.PredictWait(_request(mo_code=""))
    assert res.p50_days > 0 and res.explanation.summary_ru


def test_refusal_explained_as_risk(served):
    _, queue, _, _ = served
    res = queue.PredictRefusal(_request())
    assert 0 <= res.p_refusal <= 1 and "риск" in res.explanation.summary_ru and "дн." not in res.explanation.factors[0].text_ru


@pytest.mark.parametrize("request_, code", [
    (_request(profile_code="999"), grpc.StatusCode.INVALID_ARGUMENT),
    (_request(mo_code="ZZZZ"), grpc.StatusCode.NOT_FOUND),
    (_request(mo_code="", region="99"), grpc.StatusCode.INVALID_ARGUMENT),
])
def test_bad_requests_map_to_status_codes(served, request_, code):
    _, queue, _, _ = served
    with pytest.raises(grpc.RpcError) as err:
        queue.PredictWait(request_)
    assert err.value.code() == code


def test_alternatives_sorted_excluding_base_and_within_distance(served):
    _, queue, _, _ = served
    res = queue.Alternatives(queue_pb2.AlternativesRequest(base=_request(), limit=3))
    assert len(res.alternatives) == 3 and all(a.organization.mo_code != "0003" for a in res.alternatives)
    assert [a.p50_days for a in res.alternatives] == sorted(a.p50_days for a in res.alternatives)
    assert all(a.distance_km > 0 and a.organization.name.startswith("Больница") for a in res.alternatives)
    near = queue.Alternatives(queue_pb2.AlternativesRequest(base=_request(), max_distance_km=15))
    assert {a.organization.mo_code for a in near.alternatives} == {"0002", "0004"}


def test_forecast_points_and_backtest(served):
    _, _, forecast, _ = served
    res = forecast.Forecast(forecast_pb2.ForecastRequest(stream_id="er_visits_daily", entity={"region_kato": "10", "mo_key": "org a"}, horizon=3))
    assert [p.period for p in res.points] == ["2025-04-01", "2025-04-02", "2025-04-03"]
    assert res.points[0].lo <= res.points[0].yhat <= res.points[0].hi
    assert res.backtest.mase == 0.8 and 0 < res.backtest.smape < res.backtest.baseline_smape
    assert res.model.name == "AutoETS" and res.model.version == "1.0.0"


@pytest.mark.parametrize("request_, code", [
    (forecast_pb2.ForecastRequest(stream_id="nope"), grpc.StatusCode.INVALID_ARGUMENT),
    (forecast_pb2.ForecastRequest(stream_id="er_visits_daily", entity={"region_kato": "10"}), grpc.StatusCode.INVALID_ARGUMENT),
    (forecast_pb2.ForecastRequest(stream_id="er_visits_daily", entity={"region_kato": "10", "mo_key": "unknown"}), grpc.StatusCode.NOT_FOUND),
])
def test_forecast_bad_requests(served, request_, code):
    _, _, forecast, _ = served
    with pytest.raises(grpc.RpcError) as err:
        forecast.Forecast(request_)
    assert err.value.code() == code


def test_health_and_distance(served):
    channel = served[3]
    status = health_pb2_grpc.HealthStub(channel).Check(health_pb2.HealthCheckRequest(service="darumen.v1.QueueIntelligence"))
    assert status.status == health_pb2.HealthCheckResponse.SERVING
    assert abs(haversine_km(51.1694, 71.4491, 43.2389, 76.8897) - 970) < 30  # Astana to Almaty
    assert haversine_km(None, 1.0, 2.0, 3.0) == 0.0


def test_simulation_scenarios_and_redistribution(served):
    state, _, _, channel = served
    sim = simulation_pb2_grpc.SimulationStub(channel)
    assert len(state.sim_states) == 24
    res = sim.Simulate(simulation_pb2.SimulateRequest(region=common_pb2.RegionRef(kato="10"), profile_code="381", capacity_delta_pct=25))
    assert res.organisations == 12 and res.delta_days < 0 and res.ci_low <= res.delta_days <= res.ci_high and res.assumptions
    assert res.model.name == "fluid_queue" and res.model.trained_through == "2025-03-31"
    moves = sim.Redistribute(simulation_pb2.RedistributeRequest(region=common_pb2.RegionRef(kato="10"), profile_code="381"))
    assert moves.moves and moves.total_delta_days < 0 and moves.moves[0].to.name.startswith("Больница")
    assert moves.moves[0].share_of_source_pct <= 20.0 + 1e-9
    with pytest.raises(grpc.RpcError) as err:
        sim.Simulate(simulation_pb2.SimulateRequest(region=common_pb2.RegionRef(kato="99"), profile_code="381"))
    assert err.value.code() == grpc.StatusCode.INVALID_ARGUMENT
