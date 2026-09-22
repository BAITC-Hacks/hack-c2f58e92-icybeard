"""Справочник Стандарта стационарной помощи (refdata/route_standard.yaml) → четыре витрины refdata.route_*.
Чистая проверка без Postgres: состав стадий и чек-листа, положительная давность, подписи источника и даты
в каждой строке (интерфейс цитирует норматив), у ориентира МЗ РК — своя дата коллегии, а не дата приказа."""
from pathlib import Path

from darumen.lakehouse.publish import route_standard_frames

TABLES = {"refdata.route_stages", "refdata.route_refusal_reasons", "refdata.route_checklist", "refdata.route_benchmarks"}


def test_route_standard_frames_cover_stages_checklist_reasons_and_benchmarks_with_sources():
    frames = route_standard_frames()
    assert set(frames) == TABLES

    stages = frames["refdata.route_stages"]
    assert list(stages["code"]) == ["referral_issued", "examination", "waitlisted", "date_assigned", "hospitalized", "refused"]
    assert sorted(set(int(v) for v in stages["stage_order"])) == [1, 2, 3, 4, 5]
    by_code = stages.set_index("code")
    assert int(by_code.loc["date_assigned", "norm_working_days"]) == 2
    assert int(by_code.loc["refused", "no_show_days"]) == 2
    assert by_code.loc["referral_issued", "norm_working_days"] is not None  # nullable Int64, не object

    assert len(frames["refdata.route_refusal_reasons"]) == 4

    checklist = frames["refdata.route_checklist"]
    assert len(checklist) == 10
    assert (checklist["validity_days"] > 0).all()
    assert set(int(v) for v in checklist["validity_days"]) == {14, 30, 180, 365}

    benchmarks = frames["refdata.route_benchmarks"].set_index("code")
    assert benchmarks.loc["moh_avg_wait_days", "value"] == 30
    assert benchmarks.loc["moh_target_wait_days", "value"] == 20
    assert benchmarks.loc["moh_share_over_20_days", "value"] == 0.17
    assert benchmarks.loc["moh_target_wait_days", "source_date"] == "2026-02-19"
    assert "коллегия" in benchmarks.loc["moh_target_wait_days", "source"]

    for name, frame in frames.items():
        assert (frame["source"].str.len() > 0).all(), name
        assert (frame["source_date"].str.len() > 0).all(), name
        assert (frame["title_ru"].str.len() > 0).all() and (frame["title_kk"].str.len() > 0).all(), name
    assert (frames["refdata.route_stages"]["source_date"] == "2025-09-15").all()


def test_route_standard_frames_are_empty_when_seed_is_missing(tmp_path: Path):
    assert route_standard_frames(tmp_path) == {}
