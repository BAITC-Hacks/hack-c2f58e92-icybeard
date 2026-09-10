"""Shared pieces for the tabular models: feature lists, loading, encoding and metrics."""
from __future__ import annotations

import json
import os
from pathlib import Path

import duckdb
import numpy as np
import pandas as pd

from ..intake.pipeline import Lakehouse

CATEGORICAL = ["region_kato", "mo_code", "profile_code", "icd_chapter", "icd_block", "referral_purpose",
               "finance_source", "territorial_type", "mo_size_bucket", "mo_type"]
NUMERIC = ["queue_len", "queue_age_p50", "queue_age_p90", "throughput_per_day", "refusal_rate_4w",
           "wait_p50_4w", "wait_p90_4w", "dow", "week_of_year", "same_mo"]
FEATURES = CATEGORICAL + NUMERIC
UNKNOWN = "__na__"
DEFAULT_TRACKING_URI = "sqlite:///lakehouse/mlflow.db"

LABELS_RU = {
    "queue_len": "очередь в организации по профилю", "queue_age_p50": "медианный возраст очереди",
    "queue_age_p90": "возраст самых старых направлений", "throughput_per_day": "пропускная способность за 4 недели",
    "refusal_rate_4w": "доля отказов за 4 недели", "wait_p50_4w": "фактическое ожидание за 4 недели",
    "wait_p90_4w": "долгие ожидания за 4 недели", "dow": "день недели", "week_of_year": "неделя года",
    "same_mo": "направление внутри своей организации", "region_kato": "регион", "mo_code": "организация",
    "profile_code": "профиль койки", "icd_chapter": "класс диагноза", "icd_block": "группа диагноза",
    "referral_purpose": "цель направления", "finance_source": "источник финансирования",
    "territorial_type": "город или село", "mo_size_bucket": "размер организации", "mo_type": "тип организации",
}
LABELS_KZ = {
    "queue_len": "ұйымдағы кезек", "queue_age_p50": "кезектің медианалық жасы", "queue_age_p90": "ең ескі жолдамалар",
    "throughput_per_day": "4 аптадағы өткізу қабілеті", "refusal_rate_4w": "4 аптадағы бас тарту үлесі",
    "wait_p50_4w": "4 аптадағы нақты күту", "wait_p90_4w": "4 аптадағы ұзақ күту", "dow": "апта күні",
    "week_of_year": "жыл аптасы", "same_mo": "өз ұйымына жолдама", "region_kato": "өңір", "mo_code": "ұйым",
    "profile_code": "төсек бейіні", "icd_chapter": "диагноз класы", "icd_block": "диагноз тобы",
    "referral_purpose": "жолдама мақсаты", "finance_source": "қаржыландыру көзі", "territorial_type": "қала немесе ауыл",
    "mo_size_bucket": "ұйым көлемі", "mo_type": "ұйым түрі",
}


def load_features(lake: Lakehouse) -> pd.DataFrame:
    path = lake.root / "gold" / "features_wait.parquet"
    con = duckdb.connect()
    try:
        return con.execute(f"SELECT * FROM read_parquet('{path}')").df()
    finally:
        con.close()


def encode(df: pd.DataFrame, categories: dict[str, list[str]] | None = None) -> tuple[pd.DataFrame, dict[str, list[str]]]:
    """Return the feature frame with pandas categoricals; learn category lists when none are given."""
    out = pd.DataFrame(index=df.index)
    learned: dict[str, list[str]] = {}
    for col in CATEGORICAL:
        values = df[col].astype("string").fillna(UNKNOWN)
        cats = list(categories[col]) if categories else sorted(set(values.unique().tolist()) | {UNKNOWN})
        learned[col] = cats
        values = values.where(values.isin(cats), UNKNOWN)  # unseen categories at inference → unknown bucket
        out[col] = pd.Categorical(values, categories=cats)
    for col in NUMERIC:
        out[col] = pd.to_numeric(df[col], errors="coerce").astype("float64")
    return out, learned


def pinball(y: np.ndarray, q: np.ndarray, alpha: float) -> float:
    diff = y - q
    return float(np.mean(np.maximum(alpha * diff, (alpha - 1) * diff)))


def coverage(y: np.ndarray, q: np.ndarray) -> float:
    return float(np.mean(y <= q))


def mae(y: np.ndarray, p: np.ndarray) -> float:
    return float(np.mean(np.abs(y - p)))


def auc(y: np.ndarray, p: np.ndarray) -> float:
    from sklearn.metrics import roc_auc_score

    return float(roc_auc_score(y, p)) if len(np.unique(y)) > 1 else float("nan")


def brier(y: np.ndarray, p: np.ndarray) -> float:
    return float(np.mean((y - p) ** 2))


def calibration_table(y: np.ndarray, p: np.ndarray, bins: int = 10) -> list[dict]:
    edges = np.linspace(0, 1, bins + 1)
    rows = []
    for lo, hi in zip(edges[:-1], edges[1:], strict=True):
        mask = (p >= lo) & (p < hi if hi < 1 else p <= hi)
        if mask.sum():
            rows.append({"bin": f"{lo:.1f}-{hi:.1f}", "n": int(mask.sum()), "predicted": float(p[mask].mean()), "observed": float(y[mask].mean())})
    return rows


def models_dir(lake: Lakehouse) -> Path:
    return lake.root / "models"


def mlflow_log(run_name: str, params: dict, metrics: dict, artifacts: list[Path]) -> str | None:
    """Log to MLflow when it is reachable; never fail training because of tracking."""
    try:
        import mlflow

        mlflow.set_tracking_uri(os.environ.get("MLFLOW_TRACKING_URI", DEFAULT_TRACKING_URI))
        mlflow.set_experiment("darumen")
        with mlflow.start_run(run_name=run_name) as run:
            mlflow.log_params({k: str(v)[:250] for k, v in params.items()})
            mlflow.log_metrics({k: float(v) for k, v in metrics.items() if isinstance(v, (int, float)) and not np.isnan(v)})
            for artifact in artifacts:
                mlflow.log_artifact(str(artifact))
            return run.info.run_id
    except Exception as exc:  # noqa: BLE001 - tracking is optional
        print(f"mlflow: пропущено ({type(exc).__name__}: {exc})")
        return None


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=1, default=float), encoding="utf-8")
