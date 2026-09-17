"""Access Index: monthly accessibility of planned hospital care per region and profile.

Three observed quantities per month (of registration), region and profile, over referrals with a resolved
outcome (hospitalized or refused — an `open` referral has no outcome yet and is excluded): the share of
admitted patients who waited more than 30 days, the 90th percentile of realised waits among admitted
patients, and the refusal rate (refused / (hospitalized + refused)). Each is ranked across regions within
the month and profile; the index is 100 minus the mean rank percentile, so 100 is the most accessible
region. Rows with fewer than `min_count` resolved referrals are suppressed (small-number rule). The `all`
profile row combines every profile for display (pooled share/p90/refusal-rate, for the same reason a single
profile's row would be shown), but its index is the volume-weighted average of that region's own
already-ranked per-profile indices, not an independent ranking of the pooled numbers — a profile with an
unusually good or bad pooled figure should move `all` in proportion to its share of referrals, not by
however that pooled figure happens to rank against other regions on its own. Day hospitals are already
excluded from features_wait.
"""
from __future__ import annotations

from pathlib import Path

import duckdb
import numpy as np
import pandas as pd

from ..intake.pipeline import Lakehouse

VERSION = "2.0.0"
MIN_COUNT = 20
ALL_PROFILES = "all"
LONG_WAIT_DAYS = 30
UNKNOWN_REGION = "unknown"  # организации без сопоставленного региона не участвуют в рейтинге


def _observed(lake: Lakehouse) -> pd.DataFrame:
    con = duckdb.connect()
    try:
        f = f"read_parquet('{lake.root / 'gold' / 'features_wait.parquet'}')"
        return con.execute(f"""
            WITH base AS (
                SELECT date_trunc('month', registration_date)::DATE AS month, region_kato, profile_code, wait_days, refused
                FROM {f}
                WHERE (wait_days IS NOT NULL OR refused) AND region_kato <> '{UNKNOWN_REGION}'),
            per_profile AS (
                SELECT month, region_kato, profile_code, count(*) AS n,
                       avg((wait_days > {LONG_WAIT_DAYS})::int) AS share_over_30, quantile_cont(wait_days, 0.9) AS p90_days,
                       avg(refused::int) AS refusal_rate
                FROM base GROUP BY ALL),
            all_profiles AS (
                SELECT month, region_kato, '{ALL_PROFILES}' AS profile_code, count(*) AS n,
                       avg((wait_days > {LONG_WAIT_DAYS})::int) AS share_over_30, quantile_cont(wait_days, 0.9) AS p90_days,
                       avg(refused::int) AS refusal_rate
                FROM base GROUP BY ALL)
            SELECT * FROM per_profile UNION ALL SELECT * FROM all_profiles""").df()
    finally:
        con.close()


def _rank_profiles(df: pd.DataFrame) -> pd.DataFrame:
    """Rank real (non-`all`) profile rows within month and profile: higher index means more accessible."""
    keys = ["month", "profile_code"]
    rank_share = df.groupby(keys)["share_over_30"].rank(pct=True, method="average")
    rank_p90 = df.groupby(keys)["p90_days"].rank(pct=True, method="average")
    rank_refusal = df.groupby(keys)["refusal_rate"].rank(pct=True, method="average")
    index_value = (100 * (1 - (rank_share + rank_p90 + rank_refusal) / 3)).round(1)
    return df.assign(rank_share=rank_share, rank_p90=rank_p90, rank_refusal=rank_refusal, index_value=index_value)


def _weighted_all_index(scored_profiles: pd.DataFrame) -> pd.DataFrame:
    """Volume-weighted average of a region's own scored per-profile indices, one row per (month, region_kato)
    that has at least one qualifying profile — a region with nothing scored has no `all` index either."""
    def combine(group: pd.DataFrame) -> pd.Series:
        return pd.Series({"index_value": round(float(np.average(group["index_value"], weights=group["n"])), 1)})

    return (scored_profiles.groupby(["month", "region_kato"], group_keys=True)
            .apply(combine, include_groups=False).reset_index())


def score(observed: pd.DataFrame, min_count: int = MIN_COUNT) -> pd.DataFrame:
    """Rank regions within month and profile; higher index means more accessible."""
    df = observed[observed["n"] >= min_count].copy()
    profiles = _rank_profiles(df[df["profile_code"] != ALL_PROFILES])
    pooled_all = df[df["profile_code"] == ALL_PROFILES].drop(columns=["profile_code"])
    weighted = _weighted_all_index(profiles)
    all_rows = pooled_all.merge(weighted, on=["month", "region_kato"], how="inner")
    all_rows = all_rows.assign(profile_code=ALL_PROFILES, rank_share=np.nan, rank_p90=np.nan, rank_refusal=np.nan)

    scored = pd.concat([profiles, all_rows], ignore_index=True, sort=False)
    rank = scored.groupby(["month", "profile_code"])["index_value"].rank(ascending=False, method="min").astype(int)
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
        "Считается ежемесячно по региону и профилю койки из фактических исходов направлений (только круглосуточные стационары, "
        "только направления с исходом — госпитализация или отказ; ещё не рассмотренные не учитываются).\n\n"
        f"1. Три составляющие: доля госпитализированных, ждавших дольше {LONG_WAIT_DAYS} дней; 90-й перцентиль ожидания среди "
        "госпитализированных, в днях; доля отказов среди всех направлений с исходом.\n"
        "2. Все три величины ранжируются по регионам внутри месяца и профиля (перцентильный ранг).\n"
        "3. Индекс = 100 − среднее трёх перцентильных рангов: 100 у самого доступного региона, 0 у наименее доступного.\n"
        f"4. Строки с числом направлений с исходом меньше {MIN_COUNT} подавляются (правило малых чисел).\n"
        f"5. Профиль `{ALL_PROFILES}` объединяет все профили: сами доля/перцентиль/отказы считаются по объединённым данным региона "
        "(для отображения), а вот индекс — это средневзвешенное уже посчитанных индексов по профилям того же региона и месяца "
        "(вес — число направлений с исходом по профилю), а не независимый ранг по объединённым цифрам.\n\n"
        "Ограничения: индекс относительный (сравнивает регионы между собой в один месяц), не абсолютный; на данных I квартала 2025 года "
        "он покрывает три месяца. При появлении истории за несколько лет добавится сравнение с тем же месяцем прошлого года.\n",
        encoding="utf-8",
    )
