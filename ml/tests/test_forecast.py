import numpy as np
import pandas as pd

from darumen.intake.pipeline import Lakehouse
from darumen.models.forecast import forecast_stream, smape
from darumen.models.streams import Stream, load_series, load_streams


def _monthly_gold(tmp_path, months=60, seed=1):
    rng = np.random.default_rng(seed)
    rows = []
    for region in ("10", "11"):
        for profile in ("021", "381"):
            level = {"021": 400, "381": 90}[profile] * (1.2 if region == "11" else 1.0)
            for i in range(months):
                month = pd.Timestamp("2021-01-01") + pd.DateOffset(months=i)
                seasonal = 1 + 0.15 * np.sin(2 * np.pi * (i % 12) / 12)
                cases = int(level * seasonal + rng.normal(0, 8))
                los_mean = {"021": 9.0, "381": 4.0}[profile]  # разная длительность лечения по профилю, чтобы bed_days != cases
                rows.append({"month": month.date(), "region_kato": region, "profile_code": profile,
                             "cases": cases, "bed_days": int(cases * los_mean), "los_mean": los_mean, "deaths": 0, "mo_count": 3})
    gold = tmp_path / "lake" / "gold"
    gold.mkdir(parents=True)
    pd.DataFrame(rows).to_parquet(gold / "admissions_monthly.parquet", index=False)
    return tmp_path / "lake"


def test_streams_are_declared():
    streams = load_streams()
    assert {"er_visits_daily", "admissions_monthly", "vac_monthly"} <= set(streams)
    assert streams["admissions_monthly"].freq == "MS" and streams["er_visits_daily"].freq == "D"


def test_bed_days_stream_is_declared():
    # 5.1: поток строится на том же gold-срезе admissions_monthly, только y = bed_days (сумма, а не count)
    streams = load_streams()
    assert "bed_days_monthly" in streams
    stream = streams["bed_days_monthly"]
    assert stream.table == "admissions_monthly" and stream.y_col == "bed_days"
    assert stream.entity == ("region_kato", "profile_code") and stream.freq == "MS"


def test_bed_days_series_matches_gold_column(tmp_path):
    root = _monthly_gold(tmp_path)
    stream = load_streams()["bed_days_monthly"]
    series = load_series(Lakehouse(root), stream)
    gold = pd.read_parquet(root / "gold" / "admissions_monthly.parquet")
    # для каждой сущности сумма bed_days из ряда совпадает с суммой bed_days в gold (без хвоста, отброшенного как неполный)
    for uid, part in series.groupby("unique_id"):
        region, profile_code = uid.split("|")
        gold_part = gold[(gold["region_kato"] == region) & (gold["profile_code"] == profile_code)]
        gold_part = gold_part[pd.to_datetime(gold_part["month"]) <= part["ds"].max()]
        assert part["y"].sum() == gold_part["bed_days"].sum()
        assert part["y"].sum() > 0
    # bed_days не совпадает с cases для того же профиля — проверяет, что мы не сложили не ту колонку
    cases_series = load_series(Lakehouse(root), load_streams()["admissions_monthly"])
    assert cases_series["y"].sum() != series["y"].sum()


def test_incomplete_tail_is_dropped(tmp_path):
    root = _monthly_gold(tmp_path)
    df = pd.read_parquet(root / "gold" / "admissions_monthly.parquet")
    last = df["month"].max()
    df.loc[df["month"] == last, "cases"] = 3  # partial month still loading at the source
    df.to_parquet(root / "gold" / "admissions_monthly.parquet", index=False)
    series = load_series(Lakehouse(root), load_streams()["admissions_monthly"])
    assert series["ds"].max() < pd.Timestamp(last)
    assert series.groupby("unique_id").size().min() == 59


def test_forecast_backtests_against_baseline(tmp_path):
    root = _monthly_gold(tmp_path)
    stream = load_streams()["admissions_monthly"]
    frame, report = forecast_stream(Lakehouse(root), stream, root / "models" / "forecast" / "admissions_monthly")
    assert report["series"] == 4 and report["baseline"] == "SeasonalNaive"
    # выбор по потоку: лучший из кандидатов, включая ансамбль; сезонная синтетика не должна отдать победу наиву
    assert report["chosen"] in {"AutoETS", "Ensemble"}
    assert report["models"][report["chosen"]]["mase"] <= report["models"]["SeasonalNaive"]["mase"]
    # выбор по ряду: каждый ряд получил своего победителя, сумма совпадает с числом рядов
    assert sum(report["per_series_choice"].values()) == report["series"]
    assert set(frame["horizon"]) == {1, 2, 3} and len(frame) == 12
    assert (frame["lo"] <= frame["yhat"]).all() and (frame["yhat"] <= frame["hi"]).all()
    assert frame["period"].str.match(r"\d{4}-\d{2}$").all()
    # каждый ряд несёт имя своей модели и флаг плоского прогноза
    assert frame["model"].str.contains("@").all() and frame["flat"].dtype == bool
    assert "flat_share" in report
    assert (root / "models" / "forecast" / "admissions_monthly" / "report.json").exists()


def test_smape_handles_zeros():
    assert smape(np.array([0.0, 0.0]), np.array([0.0, 0.0])) == 0.0
    assert 0 < smape(np.array([10.0, 20.0]), np.array([12.0, 18.0])) < 0.2


def test_stream_dataclass_fields():
    s = Stream("x", "x", "t", "day", "y", ("a",), "day", ("a",), {"horizons": [7]}, {})
    assert s.freq == "D"


def test_period_format_by_grain():
    from darumen.models.streams import FREQ, period_format

    assert period_format("day") == "%Y-%m-%d" and period_format("week") == "%Y-%m-%d" and period_format("month") == "%Y-%m"
    assert FREQ["week"] == "W-MON"


def test_baseline_can_be_chosen_when_it_wins():
    import inspect

    from darumen.models import forecast

    source = inspect.getsource(forecast.backtest)
    assert 'best = min(names, key=lambda n: per_model[n]["mase"])' in source
