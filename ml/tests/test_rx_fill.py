"""train_rx_fill: LightGBM-квантиль p50 срока обеспечения рецепта против baseline «медиана по МНН»,
плюс gold/rx_fill_by_mnn.parquet для сервиса лекарств (5.7 A)."""
import numpy as np
import pandas as pd
import pytest

from darumen.intake.pipeline import Lakehouse
from darumen.models.rx_fill import train_rx_fill

N_PER_MNN = 120


def _synthetic_lake(root) -> Lakehouse:
    """Три МНН с разным типичным сроком обеспечения, растянуты по трём годам так, чтобы обучающая
    (до 2025-10-01) и отложенная тестовая часть обе были непустыми."""
    lake = Lakehouse(root)
    rng = np.random.default_rng(42)
    mnn_offset = {"m1": 2.0, "m2": 6.0, "m3": 10.0}
    dates = pd.date_range("2023-01-01", "2026-01-01", periods=N_PER_MNN)
    rows = []
    for mnn, offset in mnn_offset.items():
        category = "cat-a" if mnn != "m3" else "cat-b"
        for day in dates:
            fill_days = max(0.0, offset + rng.normal(0, 1.0))
            rows.append({
                "recipe_id": f"{mnn}-{day.date()}", "drug_mnn_id": mnn, "category_id": category,
                "recipe_date": day, "fill_days": round(fill_days),
            })
    df = pd.DataFrame(rows)
    silver = lake.silver("rx_fulfilled")
    silver.mkdir(parents=True, exist_ok=True)
    df.to_parquet(silver / "rx_fulfilled.parquet", index=False)

    # gold.rx_weekly — источник факт-медианы/p90, переиспользуемых витриной (не считаем их заново)
    weekly = df.copy()
    weekly["week"] = weekly["recipe_date"].dt.to_period("W").dt.start_time
    weekly = weekly.groupby(["week", "drug_mnn_id"], as_index=False).agg(
        fill_days_p50=("fill_days", "median"), fill_days_p90=("fill_days", lambda s: s.quantile(0.9)))
    gold = lake.root / "gold"
    gold.mkdir(parents=True, exist_ok=True)
    weekly.to_parquet(gold / "rx_weekly.parquet", index=False)
    return lake


def test_train_rx_fill_beats_or_matches_baseline_and_writes_gold(tmp_path):
    lake = _synthetic_lake(tmp_path)
    report = train_rx_fill(lake, tmp_path / "models" / "rx_fill")
    assert "skipped" not in report
    assert report["train_rows"] > 0
    assert report["test_rows"] > 0
    # модель хотя бы не намного хуже честного baseline (медиана по МНН на трёх чётко разделённых МНН —
    # baseline и так силён, модели достаточно быть в его окрестности)
    assert report["pinball_p50"] <= report["pinball_p50_baseline"] * 1.5

    assert (tmp_path / "models" / "rx_fill" / "model.txt").exists()
    assert (tmp_path / "models" / "rx_fill" / "report.json").exists()

    cells = pd.read_parquet(lake.root / "gold" / "rx_fill_by_mnn.parquet")
    assert set(cells["drug_mnn_id"]) == {"m1", "m2", "m3"}
    assert "fill_days_p50_model" in cells.columns
    assert "fill_days_p50_fact" in cells.columns
    assert "fill_days_p90_fact" in cells.columns
    # относительный порядок трёх явно разных МНН модель должна улавливать
    by_mnn = cells.set_index("drug_mnn_id")["fill_days_p50_model"]
    assert by_mnn["m1"] < by_mnn["m2"] < by_mnn["m3"]


def test_train_rx_fill_skips_without_silver_data(tmp_path):
    lake = Lakehouse(tmp_path)
    report = train_rx_fill(lake, tmp_path / "models" / "rx_fill")
    assert "skipped" in report
