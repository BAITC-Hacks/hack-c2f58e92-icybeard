import numpy as np
import pandas as pd

from darumen.models.common import coverage, pinball
from darumen.models.wait import WaitModel, model_card, train_wait


def synthetic_features(n: int = 3000, seed: int = 7) -> pd.DataFrame:
    rng = np.random.default_rng(seed)
    mo = rng.choice([f"{i:04d}" for i in range(12)], n)
    profile = rng.choice(["021", "031", "381"], n)
    queue = rng.integers(0, 200, n)
    throughput = rng.uniform(0.5, 10, n)
    base = {"021": 2, "031": 10, "381": 35}
    wait = np.array([base[p] for p in profile]) + queue / (throughput + 1) + rng.normal(0, 3, n)
    wait = np.clip(np.round(wait), 0, None)
    refused = rng.random(n) < (0.03 + queue / 500)  # refusal risk grows with the queue
    reg = pd.to_datetime("2025-01-01") + pd.to_timedelta(rng.integers(0, 90, n), unit="D")
    df = pd.DataFrame({
        "hospitalization_code": [f"10.{m}.{p}.{i}" for i, (m, p) in enumerate(zip(mo, profile, strict=True))],
        "registration_date": reg.date, "region_kato": "10", "mo_code": mo, "profile_code": profile,
        "icd_chapter": rng.choice(["IX", "VII", "XIII"], n), "icd_block": rng.choice(["I10", "H25", "M54"], n),
        "referral_purpose": rng.choice(["Консервативное лечение", "Оперативное лечение"], n),
        "finance_source": "Активы Фонда на ОСМС", "territorial_type": rng.choice(["Город", "Село"], n),
        "mo_size_bucket": rng.choice(["S", "M", "L"], n), "mo_type": "hospital",
        "queue_len": queue, "queue_age_p50": queue / 3, "queue_age_p90": queue / 2, "throughput_per_day": throughput,
        "refusal_rate_4w": rng.uniform(0, 0.3, n), "wait_p50_4w": wait + rng.normal(0, 2, n), "wait_p90_4w": wait * 1.5,
        "dow": reg.dayofweek, "week_of_year": reg.isocalendar().week.to_numpy(), "same_mo": rng.random(n) < 0.6,
    })
    df["wait_days"] = np.where(refused, np.nan, wait)
    df["refused"] = refused
    df["within_30"] = (~refused) & (wait <= 30)
    holdout = pd.Series(mo).isin(["0000", "0001"]).to_numpy()
    df["split"] = np.where(holdout, "test_mo", np.where(reg < pd.Timestamp("2025-03-01"), "train", "test_time"))
    return df


def test_pinball_and_coverage():
    y = np.array([1.0, 2.0, 3.0])
    assert pinball(y, y, 0.5) == 0.0
    assert pinball(y, y + 1, 0.9) < pinball(y, y - 1, 0.9)  # over-prediction is cheap at the 90th percentile
    assert coverage(y, np.array([1.0, 1.0, 5.0])) == 2 / 3


def test_train_beats_baseline_and_roundtrips(tmp_path):
    df = synthetic_features()
    model, report = train_wait(df, tmp_path / "wait", trained_through="2025-02-28")
    for split in ("test_time", "test_mo"):
        m = report[split]
        assert m["pinball_p50"] < m["pinball_p50_baseline"], split
        assert 0.8 <= m["coverage_p90"] <= 0.97, split
        assert m["auc_refusal"] > 0.6
    loaded = WaitModel.load(tmp_path / "wait")
    sample = df[df["split"] == "test_time"].head(5)
    pred = loaded.predict(sample)
    assert (pred["p90_days"] >= pred["p50_days"]).all() and pred["p_refusal"].between(0, 1).all()
    explanation = loaded.explain(sample.head(1))[0]
    assert explanation["factors"] and "дн." in explanation["factors"][0]["text"]
    assert "Базовое ожидание" in explanation["summary"]
    kz = loaded.explain(sample.head(1), lang="kz")[0]
    assert "күн" in kz["factors"][0]["text"]
    card = model_card(model, report)
    assert "Карточка модели" in card and "Март 2025" in card


def test_unseen_category_and_missing_values_do_not_crash(tmp_path):
    df = synthetic_features(n=1500)
    model, _ = train_wait(df, tmp_path / "wait")
    odd = df.head(3).copy()
    odd["mo_code"] = "ZZZZ"
    odd["queue_len"] = np.nan
    odd["icd_chapter"] = None
    pred = model.predict(odd)
    base = model.baseline_predict(odd)
    assert pred["p50_days"].notna().all() and base["base_p50"].notna().all()
