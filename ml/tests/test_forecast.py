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
                rows.append({"month": month.date(), "region_kato": region, "profile_code": profile,
                             "cases": int(level * seasonal + rng.normal(0, 8)), "bed_days": 0, "los_mean": 7.0, "deaths": 0, "mo_count": 3})
    gold = tmp_path / "lake" / "gold"
    gold.mkdir(parents=True)
    pd.DataFrame(rows).to_parquet(gold / "admissions_monthly.parquet", index=False)
    return tmp_path / "lake"


def test_streams_are_declared():
    streams = load_streams()
    assert {"er_visits_daily", "admissions_monthly", "vac_monthly"} <= set(streams)
    assert streams["admissions_monthly"].freq == "MS" and streams["er_visits_daily"].freq == "D"


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
    assert report["series"] == 4 and report["baseline"] == "SeasonalNaive" and report["chosen"] == "AutoETS"
    assert report["models"]["AutoETS"]["mase"] < report["models"]["SeasonalNaive"]["mase"] * 1.5
    assert set(frame["horizon"]) == {1, 2, 3} and len(frame) == 12
    assert (frame["lo"] <= frame["yhat"]).all() and (frame["yhat"] <= frame["hi"]).all()
    assert frame["period"].str.match(r"\d{4}-\d{2}$").all()
    assert (root / "models" / "forecast" / "admissions_monthly" / "report.json").exists()


def test_smape_handles_zeros():
    assert smape(np.array([0.0, 0.0]), np.array([0.0, 0.0])) == 0.0
    assert 0 < smape(np.array([10.0, 20.0]), np.array([12.0, 18.0])) < 0.2


def test_stream_dataclass_fields():
    s = Stream("x", "x", "t", "day", "y", ("a",), "day", ("a",), {"horizons": [7]}, {})
    assert s.freq == "D"
