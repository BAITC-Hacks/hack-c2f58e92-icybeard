"""Survival-модель ожидания: лог-логистическое AFT (lifelines) по направлениям с честным
цензурированием. Распределение выбрано по AIC на обучении (лог-логистическое 367k против
396k у Вейбулла и 372k у лог-нормального).

Отличие от квантильной wait-модели: открытые направления и отказы не выбрасываются, а
цензурируются датой последнего наблюдаемого исхода, поэтому модель отвечает на продуктовый
вопрос «какова вероятность госпитализации к дате X» безусловно — с учётом риска не попасть вовсе.
Отказ трактуется как цензурирование (пациент не госпитализирован за всё окно наблюдения);
конкурирующие риски не моделируются — это ограничение записано в отчёте.

Выходы: models/survival/report.json (C-index и AUC@30 против baseline, калибровка по децилям).
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd

from ..intake.pipeline import Lakehouse
from .common import write_json

VERSION = "1.0.0"
TRAIN_SAMPLE = 120_000
TOP_PROFILES = 30
HORIZONS = [7, 30, 60, 90]
NUMERIC = ["queue_len_log", "queue_age_p50", "throughput_per_day", "refusal_rate_4w", "wait_p50_4w", "wait_p90_4w",
           "org_share30"]
CATEGORICAL = ["region_kato", "profile_top", "referral_purpose", "territorial_type", "mo_size_bucket", "mo_type"]


def _dataset(lake: Lakehouse) -> pd.DataFrame:
    df = pd.read_parquet(lake.root / "gold" / "features_wait.parquet")
    reg = pd.to_datetime(df["registration_date"])
    censor_date = (reg + pd.to_timedelta(df["wait_days"], unit="D")).max()
    event = df["wait_days"].notna()
    duration = df["wait_days"].where(event, (censor_date - reg).dt.days.astype(float))
    df = df.assign(
        event=event,
        duration=duration.clip(lower=0.5),  # AFT требует строго положительную длительность
        queue_len_log=np.log1p(df["queue_len"]),
        profile_top=df["profile_code"].where(
            df["profile_code"].isin(df["profile_code"].value_counts().head(TOP_PROFILES).index), "OTH"),
    )
    # «эффект организации»: доля госпитализированных за 30 дней по ячейке mo×profile на обучении.
    # Это одновременно и признак модели, и baseline для AUC@30: превышение baseline означает,
    # что остальная структура (очередь, регион, цель направления) добавляет информацию.
    train_mask = df["split"] == "train"
    within = df.loc[train_mask, "event"] & (df.loc[train_mask, "duration"] <= 30)
    cell = within.groupby([df.loc[train_mask, "mo_code"], df.loc[train_mask, "profile_code"]]).mean()
    by_profile = within.groupby(df.loc[train_mask, "profile_code"]).mean()
    share = pd.Series(df.set_index(["mo_code", "profile_code"]).index.map(cell), index=df.index, dtype=float)
    df["org_share30"] = share.fillna(df["profile_code"].map(by_profile).astype(float)).fillna(float(within.mean()))
    for col in NUMERIC:
        df[col] = df[col].fillna(df.loc[df["split"] == "train", col].median())
    df.attrs["censor_date"] = str(censor_date.date())
    return df


def _design(df: pd.DataFrame, columns: pd.Index | None = None) -> pd.DataFrame:
    x = pd.get_dummies(df[NUMERIC + CATEGORICAL], columns=CATEGORICAL, drop_first=True, dtype=float)
    if columns is not None:
        x = x.reindex(columns=columns, fill_value=0.0)
    return x


def _calibration(p: np.ndarray, y: np.ndarray, bins: int = 10) -> list[dict]:
    frame = pd.DataFrame({"p": p, "y": y})
    frame["bin"] = pd.qcut(frame["p"], bins, duplicates="drop")
    return [
        {"n": int(g["y"].size), "predicted": round(float(g["p"].mean()), 3), "observed": round(float(g["y"].mean()), 3)}
        for _, g in frame.groupby("bin", observed=True)
    ]


def train_survival(lake: Lakehouse, out_dir: Path) -> dict:
    from lifelines import LogLogisticAFTFitter
    from lifelines.utils import concordance_index
    from sklearn.metrics import roc_auc_score

    df = _dataset(lake)
    train = df[df["split"] == "train"]
    fit_frame = train.sample(min(len(train), TRAIN_SAMPLE), random_state=42)
    design = _design(fit_frame)
    fit_data = design.assign(duration=fit_frame["duration"].to_numpy(), event=fit_frame["event"].to_numpy(dtype=float))
    model = LogLogisticAFTFitter(penalizer=0.01)
    model.fit(fit_data, duration_col="duration", event_col="event")

    report: dict = {
        "name": "survival_aft", "version": VERSION, "censor_date": df.attrs["censor_date"],
        "train_rows": int(len(fit_frame)), "censored_share": round(float(1 - train["event"].mean()), 4),
        "note": "отказ цензурируется, а не моделируется отдельным риском; вероятности безусловные",
        "splits": {},
    }
    admitted = train[train["event"]]
    cell_median = admitted.groupby(["mo_code", "profile_code"])["duration"].median()
    profile_median = admitted.groupby("profile_code")["duration"].median()
    for split in ["test_time", "test_mo"]:
        test = df[df["split"] == split]
        x = _design(test, columns=design.columns)
        median_pred = model.predict_median(x).to_numpy()
        c_model = concordance_index(test["duration"], median_pred, test["event"])
        # baseline для C-index: медиана ожидания по организации и профилю на обучении
        base_median = pd.Series(test.set_index(["mo_code", "profile_code"]).index.map(cell_median),
                                index=test.index, dtype=float)
        base_median = base_median.fillna(test["profile_code"].map(profile_median).astype(float))
        base_median = base_median.fillna(float(admitted["duration"].median()))
        c_base = concordance_index(test["duration"], base_median.to_numpy(), test["event"])

        y30 = (test["event"] & (test["duration"] <= 30)).to_numpy()
        p_by_t = {t: 1.0 - model.predict_survival_function(x, times=[t]).iloc[0].to_numpy() for t in HORIZONS}
        auc30 = float(roc_auc_score(y30, p_by_t[30]))
        auc30_base = float(roc_auc_score(y30, test["org_share30"].to_numpy()))
        report["splits"][split] = {
            "n": int(len(test)),
            "c_index": round(float(c_model), 3), "c_index_baseline": round(float(c_base), 3),
            "auc30": round(auc30, 3), "auc30_baseline": round(auc30_base, 3),
            "p_admit_mean": {str(t): round(float(p_by_t[t].mean()), 3) for t in HORIZONS},
            "observed_share": {str(t): round(float((test["event"] & (test["duration"] <= t)).mean()), 3)
                               for t in HORIZONS},
            "calibration30": _calibration(p_by_t[30], y30.astype(float)),
        }

    out_dir.mkdir(parents=True, exist_ok=True)
    write_json(out_dir / "report.json", report)
    return report
