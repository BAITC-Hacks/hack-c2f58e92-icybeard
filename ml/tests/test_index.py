import numpy as np
import pandas as pd

from darumen.intake.pipeline import Lakehouse
from darumen.models.index import build_index


def test_index_ranks_regions_within_month_and_profile(tmp_path):
    rng = np.random.default_rng(0)
    rows = []
    for region, level in (("10", 2), ("75", 40), ("79", 20)):
        for _ in range(60):
            rows.append({"registration_date": pd.Timestamp("2025-01-01") + pd.Timedelta(days=int(rng.integers(0, 28))),
                         "region_kato": region, "profile_code": "381", "wait_days": float(max(0, level + rng.normal(0, 3)))})
    for _ in range(3):  # too few admissions: suppressed
        rows.append({"registration_date": pd.Timestamp("2025-01-05"), "region_kato": "11", "profile_code": "381", "wait_days": 1.0})
    gold = tmp_path / "lake" / "gold"
    gold.mkdir(parents=True)
    pd.DataFrame(rows).to_parquet(gold / "features_wait.parquet", index=False)
    index = build_index(Lakehouse(tmp_path / "lake"))
    per_profile = index[index["profile_code"] == "381"].set_index("region_kato")
    assert "11" not in per_profile.index
    assert per_profile.loc["10", "rank"] == 1 and per_profile.loc["75", "rank"] == 3
    assert per_profile.loc["10", "index_value"] > per_profile.loc["79", "index_value"] > per_profile.loc["75", "index_value"]
    assert set(index["profile_code"]) == {"381", "all"}
    assert (gold / "access_index.parquet").exists()
