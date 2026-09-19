"""Длительность лечения (LOS) по пролеченным случаям ЭРСБ: LightGBM-квантиль p50 против
baseline «медиана по профилю и региону». Зачем: честная пропускная способность койки для
симулятора — «+N коек» переводится в госпитализации в день через среднюю длительность лечения.

Выходы: models/los/{model.txt, report.json}, gold/los_by_profile.parquet
(region_kato × profile: факт-медиана за последние 12 месяцев и p50 модели).
"""
from __future__ import annotations

from pathlib import Path

import duckdb
import numpy as np
import pandas as pd

from ..intake.pipeline import Lakehouse
from .common import write_json

VERSION = "1.0.0"
TRAIN_FROM = "2023-01-01"
TEST_FROM = "2025-10-01"     # последние ~7 месяцев — отложенная проверка по времени
LOS_CAP = 120                # дольше — реабилитация и хроника, не профиль планового потока
TRAIN_SAMPLE = 3_000_000
FEATURES = ["profile", "region_kato", "icd_block", "help_type", "has_operation", "month"]
CATEGORICAL = ["profile", "region_kato", "icd_block", "help_type"]


def _dataset(lake: Lakehouse) -> pd.DataFrame:
    con = duckdb.connect()
    try:
        return con.execute(f"""
            SELECT coalesce(profile, 'нет профиля') AS profile,
                   coalesce(region_kato, '00') AS region_kato,
                   coalesce(substr(icd10_canon, 1, 3), '???') AS icd_block,
                   coalesce(help_type, '?') AS help_type,
                   (operation IS NOT NULL)::int AS has_operation,
                   month(p_hospitaldate) AS month,
                   p_hospitaldate::DATE AS day,
                   los_days::DOUBLE AS los_days
            FROM {lake.silver_sql('ersb_cases')}
            WHERE p_hospitaldate >= DATE '{TRAIN_FROM}' AND los_days BETWEEN 0 AND {LOS_CAP}
        """).df()
    finally:
        con.close()


def pinball50(y: np.ndarray, pred: np.ndarray) -> float:
    diff = y - pred
    return float(np.mean(np.maximum(0.5 * diff, (0.5 - 1) * diff)))


def train_los(lake: Lakehouse, out_dir: Path) -> dict:
    import lightgbm as lgb

    # как forecast/anomaly/anomaly_labels: без набора ersb_cases (Список пролеченных случаев)
    # молча пропускаем, а не падаем — это отдельный тяжёлый набор (42 ГБ), не всегда загружен
    if not any(lake.silver("ersb_cases").glob("**/*.parquet")):
        return {"skipped": "нет silver-данных ersb_cases (набор treated_list не загружен)"}

    df = _dataset(lake)
    for col in CATEGORICAL:
        df[col] = df[col].astype("category")
    test_mask = df["day"] >= pd.Timestamp(TEST_FROM)
    train, test = df[~test_mask], df[test_mask]
    if len(train) > TRAIN_SAMPLE:
        train = train.sample(TRAIN_SAMPLE, random_state=42)

    booster = lgb.train(
        {"objective": "quantile", "alpha": 0.5, "verbosity": -1, "num_leaves": 63, "learning_rate": 0.1},
        lgb.Dataset(train[FEATURES], train["los_days"], categorical_feature=CATEGORICAL),
        num_boost_round=300)

    # baseline: медиана по профилю и региону на обучении, с откатом на профиль и на глобальную
    cell = train.groupby(["profile", "region_kato"], observed=True)["los_days"].median()
    by_profile = train.groupby("profile", observed=True)["los_days"].median()
    global_median = float(train["los_days"].median())
    base = test.set_index(["profile", "region_kato"]).index.map(cell)
    base = pd.Series(base, index=test.index, dtype=float)
    base = base.fillna(test["profile"].map(by_profile).astype(float)).fillna(global_median).to_numpy()

    pred = booster.predict(test[FEATURES])
    y = test["los_days"].to_numpy()
    report = {
        "name": "los_p50", "version": VERSION,
        "train_rows": len(train), "test_rows": len(test),
        "train_window": f"{TRAIN_FROM}..{TEST_FROM}", "test_window": f"{TEST_FROM}..{df['day'].max()!s}",
        "pinball_p50": round(pinball50(y, pred), 4), "pinball_p50_baseline": round(pinball50(y, base), 4),
        "mae": round(float(np.mean(np.abs(y - pred))), 3), "mae_baseline": round(float(np.mean(np.abs(y - base))), 3),
        "median_los_days": global_median,
    }

    out_dir.mkdir(parents=True, exist_ok=True)
    booster.save_model(str(out_dir / "model.txt"))
    write_json(out_dir / "report.json", report)

    # витрина для симулятора: медиана факта за последние 12 месяцев и p50 модели по ячейкам
    recent = df[df["day"] >= pd.Timestamp(df["day"].max()) - pd.DateOffset(months=12)]
    cells = recent.groupby(["region_kato", "profile"], observed=True).agg(
        n=("los_days", "size"), los_median_fact=("los_days", "median")).reset_index()
    cells = cells[cells["n"] >= 100]
    sample = recent.sample(frac=1, random_state=42).groupby(["region_kato", "profile"], observed=True).head(500)
    sample = sample.copy()
    sample["pred"] = booster.predict(sample[FEATURES])
    model_p50 = sample.groupby(["region_kato", "profile"], observed=True)["pred"].median().rename("los_p50_model")
    cells = cells.merge(model_p50, on=["region_kato", "profile"], how="left")

    profiles_path = lake.root / "refdata" / "bed_profiles.parquet"
    if profiles_path.exists():
        bed = pd.read_parquet(profiles_path)[["profile_code", "name_ru"]]
        cells = cells.merge(bed.rename(columns={"name_ru": "profile"}), on="profile", how="left")
    else:
        cells["profile_code"] = None
    cells = cells.rename(columns={"profile": "profile_name"})
    gold = lake.root / "gold"
    gold.mkdir(parents=True, exist_ok=True)
    cells.to_parquet(gold / "los_by_profile.parquet", index=False)
    report["cells"] = len(cells)
    write_json(out_dir / "report.json", report)
    return report
