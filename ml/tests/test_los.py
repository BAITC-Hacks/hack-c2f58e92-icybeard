import numpy as np
import pandas as pd

from darumen.intake.pipeline import Lakehouse
from darumen.models.los import FEATURES, train_los


def synthetic_ersb_cases(n: int = 6000, seed: int = 3) -> pd.DataFrame:
    """Tiny synthetic silver.ersb_cases: enough dates to straddle TRAIN_FROM/TEST_FROM and
    enough region×profile cells (>=100 rows each) to survive the gold/los_by_profile filter."""
    rng = np.random.default_rng(seed)
    profile = rng.choice(["021", "031", "381"], n)
    region = rng.choice(["10", "11"], n)
    icd_block = rng.choice(["I10", "H25", "M54"], n)
    help_type = rng.choice(["Стационарная", "Дневной стационар"], n)
    has_op = rng.integers(0, 2, n)
    base_los = {"021": 5, "031": 9, "381": 3}
    los = np.array([base_los[p] for p in profile]) + has_op * 3 + rng.normal(0, 1.5, n)
    los = np.clip(np.round(los), 0, 40)
    # ~4 года данных (2023-01-01 .. конец 2026), чтобы и train (до 2025-10-01), и test (после) были непустыми
    day = pd.to_datetime("2023-01-01") + pd.to_timedelta(rng.integers(0, 1460, n), unit="D")
    return pd.DataFrame({
        "profile": profile, "region_kato": region, "icd10_canon": [f"{b}.4" for b in icd_block],
        "help_type": help_type, "operation": np.where(has_op == 1, "op-code", None),
        "p_hospitaldate": day, "los_days": los,
    })


def _lake_with_ersb_cases(tmp_path, df: pd.DataFrame) -> Lakehouse:
    lake = Lakehouse(tmp_path / "lake")
    silver = lake.silver("ersb_cases")
    silver.mkdir(parents=True)
    df.to_parquet(silver / "part-0.parquet", index=False)
    return lake


def test_train_los_beats_baseline_and_writes_outputs(tmp_path):
    df = synthetic_ersb_cases()
    lake = _lake_with_ersb_cases(tmp_path, df)
    report = train_los(lake, tmp_path / "models" / "los")

    assert "skipped" not in report
    assert report["train_rows"] > 0 and report["test_rows"] > 0
    # квантильная модель p50 не должна быть хуже baseline «медиана по профилю и региону»
    assert report["pinball_p50"] <= report["pinball_p50_baseline"] * 1.05
    assert report["cells"] > 0

    model_path = tmp_path / "models" / "los" / "model.txt"
    report_path = tmp_path / "models" / "los" / "report.json"
    assert model_path.exists() and report_path.exists()

    gold_path = tmp_path / "lake" / "gold" / "los_by_profile.parquet"
    assert gold_path.exists()
    gold = pd.read_parquet(gold_path)
    for col in ("region_kato", "profile_name", "n", "los_median_fact", "los_p50_model", "profile_code"):
        assert col in gold.columns
    assert (gold["n"] >= 100).all()


def test_train_los_skips_without_ersb_cases(tmp_path):
    lake = Lakehouse(tmp_path / "lake")
    report = train_los(lake, tmp_path / "models" / "los")
    assert "skipped" in report


def test_unseen_category_and_missing_values_do_not_crash(tmp_path):
    df = synthetic_ersb_cases(n=3000)
    lake = _lake_with_ersb_cases(tmp_path, df)
    train_los(lake, tmp_path / "models" / "los")

    import lightgbm as lgb

    booster = lgb.Booster(model_file=str(tmp_path / "models" / "los" / "model.txt"))
    odd = pd.DataFrame({
        "profile": pd.Categorical(["ZZZ", None, "021"]),
        "region_kato": pd.Categorical(["99", None, "10"]),
        "icd_block": pd.Categorical(["???", None, "I10"]),
        "help_type": pd.Categorical([None, "Стационарная", None]),
        "has_operation": [0, 1, np.nan],
        "month": [1, np.nan, 6],
    })
    for col in FEATURES:
        assert col in odd.columns
    pred = booster.predict(odd[FEATURES])
    assert np.isfinite(pred).all()
