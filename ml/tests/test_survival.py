import numpy as np
import pandas as pd

from darumen.intake.pipeline import Lakehouse
from darumen.models.survival import train_survival

# Тот же синтетический features_wait.parquet, что и в test_models.synthetic_features (2.1):
# split уже размечен на train/valid/test_time/test_mo, ровно то, что читает survival._dataset.
from test_models import synthetic_features  # noqa: E402


def _lake_with_features_wait(tmp_path, df: pd.DataFrame) -> Lakehouse:
    lake = Lakehouse(tmp_path / "lake")
    gold = lake.root / "gold"
    gold.mkdir(parents=True)
    df.to_parquet(gold / "features_wait.parquet", index=False)
    return lake


def test_train_survival_beats_baseline_and_reports_expected_shape(tmp_path):
    df = synthetic_features(n=4000)
    lake = _lake_with_features_wait(tmp_path, df)
    report = train_survival(lake, tmp_path / "models" / "survival")

    assert report["name"] == "survival_aft"
    assert report["train_rows"] > 0
    assert 0 <= report["censored_share"] <= 1
    assert set(report["splits"]) == {"test_time", "test_mo"}

    for split, m in report["splits"].items():
        assert m["n"] > 0, split
        # AFT-модель не должна быть хуже baseline «медиана по организации и профилю» ни по C-index, ни по AUC@30
        assert m["c_index"] >= m["c_index_baseline"] - 0.03, split
        assert m["auc30"] >= m["auc30_baseline"] - 0.05, split
        assert set(m["p_admit_mean"]) == {"7", "30", "60", "90"}
        assert set(m["observed_share"]) == {"7", "30", "60", "90"}
        for horizon in ("7", "30", "60", "90"):
            assert 0 <= m["p_admit_mean"][horizon] <= 1, (split, horizon)
            assert 0 <= m["observed_share"][horizon] <= 1, (split, horizon)
        assert m["calibration30"]  # хотя бы один бин калибровки

    report_path = tmp_path / "models" / "survival" / "report.json"
    assert report_path.exists()


def test_unseen_category_and_missing_values_do_not_crash(tmp_path):
    df = synthetic_features(n=1500)
    lake = _lake_with_features_wait(tmp_path, df)
    train_survival(lake, tmp_path / "models" / "survival")

    # прогон _design на «грязных» данных (несуществующая категория, пропуск) не должен падать и не
    # должен рассинхронизировать колонки one-hot с теми, на которых обучалась модель
    from darumen.models.survival import _dataset, _design

    d = _dataset(lake)
    fit_columns = _design(d[d["split"] == "train"]).columns
    odd = d.head(5).copy()
    odd["profile_top"] = "UNSEEN_PROFILE"
    odd["mo_type"] = None
    x = _design(odd, columns=fit_columns)
    assert list(x.columns) == list(fit_columns)
    assert np.isfinite(x.to_numpy(dtype=float)).all()
