"""Дообучение детектора аномалий на человеческой разметке из журнала подтверждений.

Каждое действие человека над сигналом (подтвердил / отклонил) — метка. Пока меток меньше
порога или разметка односторонняя, обучение честно пропускается и отчёт объясняет почему;
как только стюарды накопят достаточно решений, логистический ре-ранкер начнёт оценивать
P(сигнал реальный) поверх робастного z и сравниваться с ранжированием по |score|.

Выход: models/anomaly_labels/report.json (CV-AUC против baseline |score| или причина пропуска).
"""
from __future__ import annotations

import hashlib
from pathlib import Path

import duckdb
import numpy as np
import pandas as pd

from ..intake.pipeline import Lakehouse
from ..lakehouse.publish import DEFAULT_PG_DSN
from .common import write_json

VERSION = "1.0.0"
MIN_LABELS = 50
POSITIVE = {"acknowledged", "confirmed"}
NEGATIVE = {"dismissed", "rejected", "false_positive"}
FEATURES = ["abs_score", "peer_score", "ratio", "is_entity"]


def _anomaly_id(row: pd.Series) -> str:
    return hashlib.md5(f"{row['stream_id']}|{row['entity']}|{row['period']}".encode()).hexdigest()


def _labels(dsn: str) -> pd.DataFrame:
    """Разметка из journal.anomaly_acks; пустой frame, если Postgres недоступен."""
    con = duckdb.connect()
    try:
        con.execute("INSTALL postgres; LOAD postgres;")
        con.execute(f"ATTACH '{dsn}' AS pg (TYPE postgres, READ_ONLY)")
        return con.execute("SELECT anomaly_id, status FROM pg.journal.anomaly_acks").df()
    except duckdb.Error:
        return pd.DataFrame(columns=["anomaly_id", "status"])
    finally:
        con.close()


def train_anomaly_labels(lake: Lakehouse, out_dir: Path, dsn: str = DEFAULT_PG_DSN) -> dict:
    anomalies = pd.read_parquet(lake.root / "gold" / "anomalies.parquet")
    anomalies["anomaly_id"] = anomalies.apply(_anomaly_id, axis=1)
    # в gold.anomalies есть свой столбец status (open) — метка человека переименована заранее
    labels = _labels(dsn).rename(columns={"status": "label"})
    labels = labels[labels["label"].isin(POSITIVE | NEGATIVE)]
    joined = anomalies.merge(labels, on="anomaly_id", how="inner")
    joined["y"] = joined["label"].isin(POSITIVE).astype(int)

    report: dict = {
        "name": "anomaly_labels", "version": VERSION,
        "labels": int(len(joined)),
        "positives": int(joined["y"].sum()), "negatives": int((1 - joined["y"]).sum()),
        "min_labels": MIN_LABELS,
    }
    out_dir.mkdir(parents=True, exist_ok=True)
    if len(joined) < MIN_LABELS:
        report["skipped"] = f"недостаточно разметки: {len(joined)} из {MIN_LABELS}"
        write_json(out_dir / "report.json", report)
        return report
    if joined["y"].nunique() < 2:
        report["skipped"] = "разметка односторонняя: нужны и подтверждённые, и отклонённые сигналы"
        write_json(out_dir / "report.json", report)
        return report

    from sklearn.linear_model import LogisticRegression
    from sklearn.metrics import roc_auc_score
    from sklearn.model_selection import cross_val_predict

    x = pd.DataFrame({
        "abs_score": joined["score"].abs(),
        "peer_score": joined["peer_score"].abs(),
        "ratio": (joined["observed"] / joined["expected"].replace(0, np.nan)).fillna(1.0).clip(0, 10),
        "is_entity": (joined["kind"] == "entity").astype(float),
    })
    folds = min(5, int(joined["y"].value_counts().min()))
    model = LogisticRegression(max_iter=1000)
    p = cross_val_predict(model, x, joined["y"], cv=folds, method="predict_proba")[:, 1]
    report["auc_cv"] = round(float(roc_auc_score(joined["y"], p)), 3)
    report["auc_baseline_abs_score"] = round(float(roc_auc_score(joined["y"], x["abs_score"])), 3)
    report["cv_folds"] = folds
    model.fit(x, joined["y"])
    report["coefficients"] = {name: round(float(c), 4) for name, c in zip(FEATURES, model.coef_[0])}
    write_json(out_dir / "report.json", report)
    return report
