import duckdb

from darumen.lakehouse.gold import build_gold
from darumen.refdata.build import build_refdata


def _q(lake, table, sql):
    return duckdb.connect().execute(sql.format(t=f"read_parquet('{lake.root}/gold/{table}.parquet')")).fetchall()


def test_queue_daily_tracks_open_referrals(synthetic_lake):
    build_refdata(synthetic_lake)
    counts = build_gold(synthetic_lake)
    assert counts["queue_daily"] > 0 and counts["features_wait"] == 8 and counts["er_visits_daily"] == 3
    assert counts["admissions_monthly"] == 0 and counts["vac_monthly"] == 0  # no silver for them yet

    # hospital A, therapy: 5 Jan +1 registered; 7 Jan four open (5,6,7,7 registered, none resolved); 8 Jan one hospitalised
    rows = {r[0].isoformat(): r[1:] for r in _q(synthetic_lake, "queue_daily",
        "SELECT day, registered, hospitalized, refused, queue_len, queue_age_p50 FROM {t} WHERE mo_code='00AA' AND profile_code='021' AND day BETWEEN '2025-01-05' AND '2025-01-12' ORDER BY day")}
    assert rows["2025-01-05"][:4] == (1, 0, 0, 1)
    assert rows["2025-01-07"][:4] == (2, 0, 0, 4)
    assert rows["2025-01-08"][:4] == (0, 1, 0, 3)          # first one admitted on the 8th
    assert rows["2025-01-09"][:4] == (0, 0, 1, 2)          # refusal on the 9th
    assert rows["2025-01-11"][:4] == (0, 1, 0, 1)          # second admitted, only the open one remains
    assert rows["2025-01-12"][4] == 5                      # the open referral from the 7th is 5 days old

    region = _q(synthetic_lake, "queue_daily", "SELECT DISTINCT region_kato FROM {t}")
    assert region == [("10",)]


def test_throughput_window_has_no_look_ahead(synthetic_lake):
    build_refdata(synthetic_lake)
    build_gold(synthetic_lake)
    # on 20 Jan the window covers 23 Dec..19 Jan: two admissions (8th, 11th) with waits 3 and 5; the 21 Jan admission must not count
    row = _q(synthetic_lake, "throughput_4w",
             "SELECT hospitalized_4w, registered_4w, refused_4w, wait_p50_4w, wait_p90_4w, refusal_rate_4w FROM {t} WHERE mo_code='00AA' AND profile_code='021' AND day='2025-01-20'")[0]
    assert row[0] == 2 and row[1] == 4 and row[2] == 1
    assert row[3] == 4.0 and row[4] == 4.8
    assert abs(row[5] - 0.25) < 1e-9


def test_features_wait_is_leak_free_and_split(synthetic_lake):
    build_refdata(synthetic_lake)
    build_gold(synthetic_lake)
    rows = _q(synthetic_lake, "features_wait",
              "SELECT hospitalization_code, queue_len, throughput_per_day, wait_p50_4w, wait_days, refused, within_30, split, icd_chapter, same_mo FROM {t} ORDER BY hospitalization_code")
    by_code = {r[0]: r[1:] for r in rows}
    assert "10.00AA.DH.1" not in by_code                     # day hospital excluded
    first = by_code["10.00AA.021.1"]
    assert first[0] == 0 and first[1] == 0 and first[2] is None  # nothing before the first registration
    fifth = by_code["10.00AA.021.5"]                            # registered 20 Jan: queue on 19 Jan = 1 open, realised waits 3 and 5
    assert fifth[0] == 1 and fifth[2] == 4.0 and fifth[3] == 1 and fifth[5] is True
    assert by_code["10.00AA.021.3"][4] is True and by_code["10.00AA.021.3"][5] is False
    assert by_code["10.00BB.381.1"][7] == "VII" and by_code["10.00BB.381.1"][8] is False
    assert by_code["10.00AA.021.6"][6] in ("test_time", "test_mo") and by_code["10.00AA.021.1"][6] in ("train", "test_mo")
