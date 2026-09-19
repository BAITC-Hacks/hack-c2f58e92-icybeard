import numpy as np
import pandas as pd

from darumen.intake.pipeline import Lakehouse
from darumen.models import anomaly_labels
from darumen.models.anomaly_labels import MIN_LABELS, _anomaly_id, train_anomaly_labels


def _lake_with_anomalies(tmp_path, n: int = 200, seed: int = 5) -> tuple[Lakehouse, pd.DataFrame]:
    rng = np.random.default_rng(seed)
    lake = Lakehouse(tmp_path / "lake")
    gold = lake.root / "gold"
    gold.mkdir(parents=True)
    score = rng.normal(0, 3, n)
    anomalies = pd.DataFrame({
        "stream_id": "er_visits_daily",
        "entity": [f'{{"region_kato": "10", "mo_key": "org {i % 20}"}}' for i in range(n)],
        # i // 28 и i % 28 вместе однозначно восстанавливают i, поэтому период уникален для
        # каждой строки даже при повторяющихся entity — иначе anomaly_id коллизирует и merge задваивает строки
        "period": [f"2025-{1 + (i // 28):02d}-{(i % 28) + 1:02d}" for i in range(n)],
        "observed": rng.uniform(1, 100, n), "expected": rng.uniform(1, 100, n),
        "score": score, "peer_score": score * 0.7 + rng.normal(0, 0.5, n),
        "severity": np.where(np.abs(score) > 2, "critical", "warning"),
        "kind": np.where(rng.random(n) < 0.5, "entity", "shared"),
        "status": "open", "model": "robust_z@1.0.0",
    })
    anomalies.to_parquet(gold / "anomalies.parquet", index=False)
    return lake, anomalies


def _fake_labels(anomalies: pd.DataFrame, seed: int = 1) -> pd.DataFrame:
    """Синтетическая человеческая разметка: сигналы с большим |score| подтверждаются чаще —
    так реранкер на признаке abs_score получает содержательный AUC, а не случайный шум."""
    rng = np.random.default_rng(seed)
    ids = anomalies.apply(_anomaly_id, axis=1)
    p_true = 1 / (1 + np.exp(-(anomalies["score"].abs() - 2)))
    is_true = rng.random(len(anomalies)) < p_true
    status = np.where(is_true, "confirmed", "dismissed")
    return pd.DataFrame({"anomaly_id": ids, "status": status})


def test_train_anomaly_labels_fits_and_beats_baseline_when_enough_labels(tmp_path, monkeypatch):
    lake, anomalies = _lake_with_anomalies(tmp_path)
    labels = _fake_labels(anomalies)
    monkeypatch.setattr(anomaly_labels, "_labels", lambda dsn: labels)

    report = train_anomaly_labels(lake, tmp_path / "models" / "anomaly_labels", dsn="unused")

    assert "skipped" not in report
    assert report["labels"] == len(anomalies)
    assert report["positives"] > 0 and report["negatives"] > 0
    assert report["cv_folds"] >= 2
    # реранкер использует |score| как один из признаков, так что не должен проигрывать голому baseline
    assert report["auc_cv"] >= report["auc_baseline_abs_score"] - 0.1
    assert set(report["coefficients"]) == {"abs_score", "peer_score", "ratio", "is_entity"}

    report_path = tmp_path / "models" / "anomaly_labels" / "report.json"
    assert report_path.exists()


def test_train_anomaly_labels_skips_when_too_few_labels(tmp_path, monkeypatch):
    lake, anomalies = _lake_with_anomalies(tmp_path, n=200)
    few = _fake_labels(anomalies).head(MIN_LABELS - 1)
    monkeypatch.setattr(anomaly_labels, "_labels", lambda dsn: few)

    report = train_anomaly_labels(lake, tmp_path / "models" / "anomaly_labels", dsn="unused")
    assert "skipped" in report
    assert report["labels"] == MIN_LABELS - 1


def test_train_anomaly_labels_skips_when_labels_are_one_sided(tmp_path, monkeypatch):
    lake, anomalies = _lake_with_anomalies(tmp_path, n=200)
    labels = _fake_labels(anomalies)
    labels["status"] = "confirmed"  # односторонняя разметка: только подтверждения
    monkeypatch.setattr(anomaly_labels, "_labels", lambda dsn: labels)

    report = train_anomaly_labels(lake, tmp_path / "models" / "anomaly_labels", dsn="unused")
    assert "skipped" in report
    assert "односторонняя" in report["skipped"]


def test_labels_returns_empty_frame_without_postgres():
    # без живого Postgres в песочнице _labels должна тихо вернуть пустой frame, а не упасть
    df = anomaly_labels._labels("host=localhost port=1 dbname=nope user=nope password=nope")
    assert list(df.columns) == ["anomaly_id", "status"]
    assert len(df) == 0
