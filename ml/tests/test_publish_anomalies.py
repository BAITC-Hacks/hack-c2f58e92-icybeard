"""gold.anomalies приобретает колонку mo_code при публикации — сопоставление (region_kato, mo_key)
с gold.er_visits_daily, где эта колонка уже подтягивается из mo_name_index (build_er_visits_daily)."""
import duckdb
import pandas as pd

from darumen.intake.pipeline import Lakehouse
from darumen.lakehouse.publish import anomalies_select


def _lake_with_anomalies(root, with_er_visits: bool = True) -> Lakehouse:
    lake = Lakehouse(root)
    gold = root / "gold"
    gold.mkdir()
    pd.DataFrame([
        # сигнал приёмного покоя: mo_key совпадает с организацией из er_visits_daily
        {"stream_id": "er_visits_daily", "entity": '{"region_kato": "10", "mo_key": "org a"}', "period": "2025-04-01",
         "observed": 12.0, "expected": 4.0, "score": 6.1, "peer_score": 5.0, "severity": "critical", "kind": "entity",
         "status": "open", "model": "robust_z@1.0.0", "region_kato": "10", "mo_key": "org a"},
        # региональный сигнал без организации (например, admissions_monthly) — mo_key отсутствует у этой строки
        {"stream_id": "admissions_monthly", "entity": '{"region_kato": "10", "profile_code": "381"}', "period": "2025-02",
         "observed": 50.0, "expected": 80.0, "score": -3.4, "peer_score": -1.0, "severity": "warning", "kind": "shared",
         "status": "open", "model": "robust_z@1.0.0", "region_kato": "10", "mo_key": None},
    ]).to_parquet(gold / "anomalies.parquet", index=False)
    if with_er_visits:
        pd.DataFrame([{"day": "2025-04-01", "region_kato": "10", "mo_key": "org a", "mo_code": "0003", "visits": 12}]
                     ).to_parquet(gold / "er_visits_daily.parquet", index=False)
    return lake


def test_anomalies_select_resolves_mo_code_by_region_and_mo_key(tmp_path):
    lake = _lake_with_anomalies(tmp_path)
    sql = anomalies_select(lake)
    rows = {r[0]: r[1] for r in duckdb.connect().execute(f"SELECT stream_id, mo_code FROM ({sql})").fetchall()}
    assert rows["er_visits_daily"] == "0003"
    assert rows["admissions_monthly"] is None


def test_anomalies_select_without_er_visits_table_leaves_mo_code_null(tmp_path):
    lake = _lake_with_anomalies(tmp_path, with_er_visits=False)
    sql = anomalies_select(lake)
    rows = duckdb.connect().execute(f"SELECT mo_code FROM ({sql})").fetchall()
    assert all(r[0] is None for r in rows)


def test_anomalies_select_without_anomalies_table_returns_none(tmp_path):
    lake = Lakehouse(tmp_path)
    assert anomalies_select(lake) is None
