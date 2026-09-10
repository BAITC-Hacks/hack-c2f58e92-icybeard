"""Access Index: monthly accessibility of planned hospital care per region and profile.

Two observed quantities per month (of registration), region and profile: the share of admitted patients who
waited more than 30 days and the 90th percentile of realised waits. Each is ranked across regions within the
month and profile; the index is 100 minus the mean rank percentile, so 100 is the most accessible region.
Rows with fewer than `min_count` admissions are suppressed (small-number rule). Day hospitals are already
excluded from features_wait.
"""
from __future__ import annotations

from pathlib import Path

import duckdb
import pandas as pd

from ..intake.pipeline import Lakehouse

VERSION = "1.0.0"
MIN_COUNT = 5
ALL_PROFILES = "all"
LONG_WAIT_DAYS = 30


def _observed(lake: Lakehouse) -> pd.DataFrame:
    con = duckdb.connect()
    try:
        f = f"read_parquet('{lake.root / 'gold' / 'features_wait.parquet'}')"
        return con.execute(f"""
            WITH base AS (
                SELECT date_trunc('month', registration_date)::DATE AS month, region_kato, profile_code, wait_days
                FROM {f} WHERE wait_days IS NOT NULL),
            per_profile AS (
                SELECT month, region_kato, profile_code, count(*) AS n,
                       avg((wait_days > {LONG_WAIT_DAYS})::int) AS share_over_30, quantile_cont(wait_days, 0.9) AS p90_days
                FROM base GROUP BY ALL),
            all_profiles AS (
                SELECT month, region_kato, '{ALL_PROFILES}' AS profile_code, count(*) AS n,
                       avg((wait_days > {LONG_WAIT_DAYS})::int) AS share_over_30, quantile_cont(wait_days, 0.9) AS p90_days
                FROM base GROUP BY ALL)
            SELECT * FROM per_profile UNION ALL SELECT * FROM all_profiles""").df()
    finally:
        con.close()


def score(observed: pd.DataFrame, min_count: int = MIN_COUNT) -> pd.DataFrame:
    """Rank regions within month and profile; higher index means more accessible."""
    df = observed[observed["n"] >= min_count]
    keys = ["month", "profile_code"]
    rank_share = df.groupby(keys)["share_over_30"].rank(pct=True, method="average")
    rank_p90 = df.groupby(keys)["p90_days"].rank(pct=True, method="average")
    index_value = (100 * (1 - 0.5 * rank_share - 0.5 * rank_p90)).round(1)
    scored = df.assign(rank_share=rank_share, rank_p90=rank_p90, index_value=index_value)
    rank = scored.groupby(keys)["index_value"].rank(ascending=False, method="min").astype(int)
    return (scored.assign(rank=rank, model=f"access_index@{VERSION}")
            .sort_values(["month", "profile_code", "rank"]).reset_index(drop=True))


def build_index(lake: Lakehouse, min_count: int = MIN_COUNT) -> pd.DataFrame:
    out = score(_observed(lake), min_count)
    gold = lake.root / "gold"
    gold.mkdir(parents=True, exist_ok=True)
    out.to_parquet(gold / "access_index.parquet", index=False)
    return out


def method_note(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "# Индекс доступности плановой госпитализации\n\n"
        "Считается ежемесячно по региону и профилю койки из фактических исходов направлений (только круглосуточные стационары).\n\n"
        f"1. Доля госпитализированных, ждавших дольше {LONG_WAIT_DAYS} дней, и 90-й перцентиль ожидания в днях.\n"
        "2. Обе величины ранжируются по регионам внутри месяца и профиля (перцентильный ранг).\n"
        "3. Индекс = 100 − среднее двух перцентильных рангов: 100 у самого доступного региона, 0 у наименее доступного.\n"
        f"4. Строки с числом госпитализаций меньше {MIN_COUNT} подавляются (правило малых чисел). Профиль `{ALL_PROFILES}` объединяет все профили.\n\n"
        "Ограничения: индекс относительный (сравнивает регионы между собой в один месяц), не абсолютный; на данных I квартала 2025 года "
        "он покрывает три месяца. При появлении истории за несколько лет добавится сравнение с тем же месяцем прошлого года.\n",
        encoding="utf-8",
    )
