"""Срок обеспечения рецепта (fill_days) по МНН: LightGBM-квантиль p50 против baseline «медиана по МНН».
Зачем: сейчас MedicinesService.FillTimes отдаёт p50/p90 напрямую из фактических квантилей gold.rx_weekly —
честная агрегация, но не модель. Здесь — обучаемая оценка на контексте (МНН, категория, месяц), которую
C#-сервис показывает РЯДОМ с фактической медианой, а не вместо неё.

Выходы: models/rx_fill/{model.txt, report.json}, gold/rx_fill_by_mnn.parquet (drug_mnn_id: факт-медиана и p90
за последние 12 месяцев из gold.rx_weekly/rx_mnn и p50 модели).
"""
from __future__ import annotations

from pathlib import Path

import duckdb
import numpy as np
import pandas as pd

from ..intake.pipeline import Lakehouse
from .common import write_json
from .los import pinball50

VERSION = "1.0.0"
TRAIN_FROM = "2023-01-01"
TEST_FROM = "2025-10-01"    # как в los.py: последние ~7 месяцев — отложенная проверка по времени
FILL_DAYS_CAP = 60          # дольше — не срок обеспечения, а исключение (повторная выписка, ошибка данных)
TRAIN_SAMPLE = 2_000_000
FEATURES = ["drug_mnn_id", "category_id", "month"]
CATEGORICAL = ["drug_mnn_id", "category_id"]
MIN_CELL_N = 30


def _has_silver(lake: Lakehouse, dataset: str) -> bool:
    return lake.silver(dataset).exists() and any(lake.silver(dataset).rglob("*.parquet"))


def _dataset(lake: Lakehouse) -> pd.DataFrame:
    con = duckdb.connect()
    try:
        return con.execute(f"""
            SELECT coalesce(drug_mnn_id, 'unknown') AS drug_mnn_id,
                   coalesce(category_id, 'unknown') AS category_id,
                   month(recipe_date) AS month,
                   recipe_date::DATE AS day,
                   fill_days::DOUBLE AS fill_days
            FROM {lake.silver_sql('rx_fulfilled')}
            WHERE recipe_date >= DATE '{TRAIN_FROM}' AND fill_days BETWEEN 0 AND {FILL_DAYS_CAP}
        """).df()
    finally:
        con.close()


def train_rx_fill(lake: Lakehouse, out_dir: Path) -> dict:
    import lightgbm as lgb

    # как los/survival: без silver.rx_fulfilled (набор отдельный и не всегда загружен) молча пропускаем
    if not _has_silver(lake, "rx_fulfilled"):
        return {"skipped": "нет silver-данных rx_fulfilled (набор обеспеченных рецептов не загружен)"}

    df = _dataset(lake)
    if len(df) < MIN_CELL_N:
        return {"skipped": f"слишком мало строк rx_fulfilled ({len(df)}) для обучения"}

    for col in CATEGORICAL:
        df[col] = df[col].astype("category")
    test_mask = df["day"] >= pd.Timestamp(TEST_FROM)
    train, test = df[~test_mask], df[test_mask]
    if len(train) == 0 or len(test) == 0:
        return {"skipped": "нет данных по обе стороны временного разреза для теста"}
    if len(train) > TRAIN_SAMPLE:
        train = train.sample(TRAIN_SAMPLE, random_state=42)

    booster = lgb.train(
        {"objective": "quantile", "alpha": 0.5, "verbosity": -1, "num_leaves": 63, "learning_rate": 0.1},
        lgb.Dataset(train[FEATURES], train["fill_days"], categorical_feature=CATEGORICAL),
        num_boost_round=300)

    # baseline: медиана по МНН на обучении, с откатом на глобальную медиану — как в los.py
    by_mnn = train.groupby("drug_mnn_id", observed=True)["fill_days"].median()
    global_median = float(train["fill_days"].median())
    base = test["drug_mnn_id"].map(by_mnn).astype(float).fillna(global_median).to_numpy()

    pred = booster.predict(test[FEATURES])
    y = test["fill_days"].to_numpy()
    report = {
        "name": "rx_fill_p50", "version": VERSION,
        "train_rows": len(train), "test_rows": len(test),
        "train_window": f"{TRAIN_FROM}..{TEST_FROM}", "test_window": f"{TEST_FROM}..{df['day'].max()!s}",
        "pinball_p50": round(pinball50(y, pred), 4), "pinball_p50_baseline": round(pinball50(y, base), 4),
        "mae": round(float(np.mean(np.abs(y - pred))), 3), "mae_baseline": round(float(np.mean(np.abs(y - base))), 3),
        "median_fill_days": global_median,
    }

    out_dir.mkdir(parents=True, exist_ok=True)
    booster.save_model(str(out_dir / "model.txt"))
    write_json(out_dir / "report.json", report)

    # витрина для сервиса рецептов: факт-медиана/p90 за последние 12 месяцев (переиспользуем уже посчитанные
    # квантили gold.rx_weekly, не считаем их заново) + p50 модели по МНН
    recent = df[df["day"] >= pd.Timestamp(df["day"].max()) - pd.DateOffset(months=12)]
    n_by_mnn = recent.groupby("drug_mnn_id", observed=True).size().rename("n")
    sample = recent.sample(frac=1, random_state=42).groupby("drug_mnn_id", observed=True).head(500).copy()
    sample["pred"] = booster.predict(sample[FEATURES])
    model_p50 = sample.groupby("drug_mnn_id", observed=True)["pred"].median().rename("fill_days_p50_model")

    rx_weekly_path = lake.root / "gold" / "rx_weekly.parquet"
    if rx_weekly_path.exists():
        weekly = con_read_parquet(rx_weekly_path)
        fact = weekly.groupby("drug_mnn_id", observed=True).agg(
            fill_days_p50=("fill_days_p50", "median"), fill_days_p90=("fill_days_p90", "median")).reset_index()
    else:
        fact = pd.DataFrame({"drug_mnn_id": [], "fill_days_p50": [], "fill_days_p90": []})
    fact = fact.set_index("drug_mnn_id")
    cells = n_by_mnn.to_frame().join(fact, how="left").join(model_p50, how="left").reset_index()
    cells = cells.rename(columns={"fill_days_p50": "fill_days_p50_fact", "fill_days_p90": "fill_days_p90_fact"})
    cells = cells[cells["n"] >= MIN_CELL_N]

    gold = lake.root / "gold"
    gold.mkdir(parents=True, exist_ok=True)
    cells.to_parquet(gold / "rx_fill_by_mnn.parquet", index=False)
    report["cells"] = len(cells)
    write_json(out_dir / "report.json", report)
    return report


def con_read_parquet(path: Path) -> pd.DataFrame:
    con = duckdb.connect()
    try:
        return con.execute(f"SELECT * FROM read_parquet('{path}')").df()
    finally:
        con.close()
