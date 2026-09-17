import numpy as np
import pandas as pd

from darumen.intake.pipeline import Lakehouse
from darumen.models.index import ALL_PROFILES, build_index, score


def _rows(region: str, level: float, refused_share: float, n: int, rng: np.random.Generator) -> list[dict]:
    admitted = int(n * (1 - refused_share))
    rows = [{"registration_date": pd.Timestamp("2025-01-01") + pd.Timedelta(days=int(rng.integers(0, 28))),
             "region_kato": region, "profile_code": "381", "wait_days": float(max(0, level + rng.normal(0, 3))),
             "refused": False}
            for _ in range(admitted)]
    rows += [{"registration_date": pd.Timestamp("2025-01-01") + pd.Timedelta(days=int(rng.integers(0, 28))),
              "region_kato": region, "profile_code": "381", "wait_days": None, "refused": True}
             for _ in range(n - admitted)]
    return rows


def test_index_ranks_regions_within_month_and_profile(tmp_path):
    rng = np.random.default_rng(0)
    rows = []
    for region, level, refused_share in (("10", 2, 0.02), ("75", 40, 0.02), ("79", 20, 0.02)):
        rows += _rows(region, level, refused_share, 60, rng)
    rows += _rows("11", 5, 0.0, 5, rng)  # ниже порога малых чисел (20 направлений с исходом): подавляется
    gold = tmp_path / "lake" / "gold"
    gold.mkdir(parents=True)
    pd.DataFrame(rows).to_parquet(gold / "features_wait.parquet", index=False)
    index = build_index(Lakehouse(tmp_path / "lake"))
    per_profile = index[index["profile_code"] == "381"].set_index("region_kato")
    assert "11" not in per_profile.index
    assert per_profile.loc["10", "rank"] == 1 and per_profile.loc["75", "rank"] == 3
    assert per_profile.loc["10", "index_value"] > per_profile.loc["79", "index_value"] > per_profile.loc["75", "index_value"]
    assert set(index["profile_code"]) == {"381", ALL_PROFILES}
    assert (gold / "access_index.parquet").exists()


def test_higher_refusal_rate_alone_ranks_a_region_lower(tmp_path):
    """2.3: доля отказов — третья составляющая индекса, а не только ожидание и p90."""
    rng = np.random.default_rng(1)
    rows = []
    for region, refused_share in (("10", 0.01), ("75", 0.40)):  # одинаковое ожидание, разная доля отказов
        rows += _rows(region, level=15, refused_share=refused_share, n=60, rng=rng)
    gold = tmp_path / "lake" / "gold"
    gold.mkdir(parents=True)
    pd.DataFrame(rows).to_parquet(gold / "features_wait.parquet", index=False)
    index = build_index(Lakehouse(tmp_path / "lake")).set_index("region_kato")
    per_profile = index[index["profile_code"] == "381"]
    assert per_profile.loc["10", "index_value"] > per_profile.loc["75", "index_value"]
    assert per_profile.loc["10", "rank"] == 1


def test_all_profiles_index_is_volume_weighted_average_of_per_profile_index(tmp_path):
    """2.3: индекс `all` — средневзвешенное уже посчитанных индексов по профилям (вес — объём), а не
    независимый ранг по объединённым сырым цифрам."""
    observed = pd.DataFrame([
        # month, region, profile, n, доля>30, p90, доля отказов
        ("2025-01", "A", "p1", 25, 0.5, 50.0, 0.5),
        ("2025-01", "B", "p1", 25, 0.1, 10.0, 0.1),
        ("2025-01", "A", "p2", 75, 0.1, 10.0, 0.1),
        ("2025-01", "B", "p2", 75, 0.5, 50.0, 0.5),
        # пуловые сырые цифры по `all` — используются только для отображения (ShareOver30/P90Days/refusal_rate),
        # индекс всё равно пересчитывается ниже как средневзвешенное по уже посчитанным индексам профилей
        ("2025-01", "A", "all", 100, 0.2, 20.0, 0.2),
        ("2025-01", "B", "all", 100, 0.4, 40.0, 0.4),
    ], columns=["month", "region_kato", "profile_code", "n", "share_over_30", "p90_days", "refusal_rate"])

    result = score(observed, min_count=20).set_index(["region_kato", "profile_code"])
    assert result.loc[("A", "p1"), "index_value"] == 0.0
    assert result.loc[("B", "p1"), "index_value"] == 50.0
    assert result.loc[("A", "p2"), "index_value"] == 50.0
    assert result.loc[("B", "p2"), "index_value"] == 0.0

    # A: (25 * 0.0 + 75 * 50.0) / 100 = 37.5; B: (25 * 50.0 + 75 * 0.0) / 100 = 12.5
    all_rows = result.xs(ALL_PROFILES, level="profile_code")
    assert all_rows.loc["A", "index_value"] == 37.5
    assert all_rows.loc["B", "index_value"] == 12.5
    assert all_rows.loc["A", "rank"] == 1 and all_rows.loc["B", "rank"] == 2


def test_all_profiles_row_absent_when_no_profile_qualifies(tmp_path):
    """Регион без ни одного профиля, прошедшего порог малых чисел, не получает индекс `all` —
    его не из чего взвешивать."""
    observed = pd.DataFrame([
        ("2025-01", "A", "p1", 5, 0.5, 50.0, 0.5),  # ниже min_count
    ], columns=["month", "region_kato", "profile_code", "n", "share_over_30", "p90_days", "refusal_rate"])
    result = score(observed, min_count=20)
    assert result.empty
