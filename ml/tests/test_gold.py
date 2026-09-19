from pathlib import Path

import duckdb

from darumen.intake.contracts import load_contracts
from darumen.intake.pipeline import Lakehouse, run_batch
from darumen.lakehouse.gold import build_gold
from darumen.refdata.build import build_refdata

CONTRACTS_DIR = Path(__file__).resolve().parents[2] / "contracts"


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


STAFFING_HEADER = ("organization_name,locality_category,nomenclature,legal_address,position_category,position_rate,"
                    "position_type,post_id,region_id,region_name,region_kato,country_name,subordination_type,sdu_load_date")
LOAD = "2026-05-13 03:28:05.149000"


def staffing_row(post_id, region, rate, org="Городская больница №1"):
    # organization_name,locality_category,nomenclature,legal_address,position_category,position_rate,
    # position_type,post_id,region_id,region_name,region_kato,country_name,subordination_type,sdu_load_date
    return f"{org},,,,,{rate},,{post_id},,,{region},Казахстан,,{LOAD}"


def test_staffing_by_region_sums_rates_per_region(tmp_path, synthetic_lake):
    contracts = {c.dataset: c for c in load_contracts(CONTRACTS_DIR)}
    lake = synthetic_lake
    rows = [
        staffing_row("P1", "Область Абай", "1.0"),
        staffing_row("P2", "Область Абай", "0.5"),
        staffing_row("P3", "Акмолинская область", "0.75"),
        staffing_row("P4", "", "1.0"),  # region not resolvable: to_kato -> NULL, partitioned into region_kato="unknown"
    ]
    path = tmp_path / "staffing.csv"
    path.write_text("\ufeff" + STAFFING_HEADER + "\n" + "\n".join(rows) + "\n", encoding="utf-8")
    result = run_batch([path], contracts["staffing"], lake)
    assert result.status == "loaded"
    assert result.rows_quarantine == 0  # unresolved region lands in the "unknown" partition bucket, not quarantine

    counts = build_gold(lake)
    assert counts["staffing_by_region"] == 3  # "10", "11", "unknown"

    rows = duckdb.connect().execute(
        f"SELECT region_kato, total_rate, snapshot_date FROM read_parquet('{lake.root}/gold/staffing_by_region.parquet') ORDER BY region_kato").fetchall()
    by_region = {r[0]: r[1:] for r in rows}
    assert abs(by_region["10"][0] - 1.5) < 1e-9        # Область Абай: P1 + P2
    assert abs(by_region["11"][0] - 0.75) < 1e-9       # Акмолинская область: P3
    assert abs(by_region["unknown"][0] - 1.0) < 1e-9   # P4, unresolved region ("unknown" is not a real KATO code,
                                                        # so the API's join against refdata.regions drops it naturally)
    assert by_region["10"][1].isoformat() == "2026-05-13"


VAC_REFUSALS_HEADER = "id,reason,contraindication,vaccination_plan_code,sdu_load_date"


def vac_refusal_row(row_id, reason, contraindication=""):
    return f"{row_id},{reason},{contraindication},PLAN1,{LOAD}"


def test_vac_refusals_are_grouped_nationwide_by_reason_and_by_contraindication(tmp_path, synthetic_lake):
    # 5.8: у vac_refusals нет колонки региона и нет организации, из которой регион выводится — разбивка
    # только общенациональная, отдельно по причине и отдельно по противопоказанию.
    contracts = {c.dataset: c for c in load_contracts(CONTRACTS_DIR)}
    lake = synthetic_lake
    rows = [
        vac_refusal_row("R1", "родители отказались", ""),
        vac_refusal_row("R2", "родители отказались", ""),
        vac_refusal_row("R3", "медотвод", "аллергия"),
        vac_refusal_row("R4", "", ""),  # reason not filled: coalesced into "unknown" bucket
    ]
    path = tmp_path / "vac_refusals.csv"
    path.write_text("﻿" + VAC_REFUSALS_HEADER + "\n" + "\n".join(rows) + "\n", encoding="utf-8")
    result = run_batch([path], contracts["vac_refusals"], lake)
    assert result.status == "loaded"

    counts = build_gold(lake)
    assert counts["vac_refusals"] == 3  # by-reason table: "родители отказались", "медотвод", "unknown"

    by_reason = dict(_q(lake, "vac_refusals_by_reason", "SELECT reason, n FROM {t}"))
    assert by_reason["родители отказались"] == 2
    assert by_reason["медотвод"] == 1
    assert by_reason["unknown"] == 1

    by_contra = dict(_q(lake, "vac_refusals_by_contraindication", "SELECT contraindication, n FROM {t}"))
    assert by_contra["аллергия"] == 1
    assert by_contra["unknown"] == 3


ONCO_LATE_HEADER = ("localization_id,localization_name,icd_code,total_patients,advanced_stage_3_count,"
                     "advanced_stage_3_pct,advanced_stage_4_count,advanced_stage_4_pct,sdu_load_date")


def onco_late_row(loc_id, name, icd, total, stage3, stage4, load=LOAD):
    stage3_pct = round(stage3 / total, 4) if total else 0
    stage4_pct = round(stage4 / total, 4) if total else 0
    return f"{loc_id},{name},{icd},{total},{stage3},{stage3_pct},{stage4},{stage4_pct},{load}"


def test_onco_late_shares_are_nationwide_by_localization(tmp_path, synthetic_lake):
    # 5.8: onco_late уже общенациональный агрегат по локализации (grain), региона в нём нет и быть не может —
    # витрина считает долю запущенных случаев (III+IV стадии) и берёт последнюю дату загрузки.
    contracts = {c.dataset: c for c in load_contracts(CONTRACTS_DIR)}
    lake = synthetic_lake
    older = "2026-01-10 00:00:00.000000"
    rows = [
        onco_late_row("C50", "Молочная железа", "C50", 1000, 200, 100, load=older),  # older snapshot: must not survive
        onco_late_row("C50", "Молочная железа", "C50", 1000, 250, 150),
        onco_late_row("C16", "Желудок", "C16", 400, 100, 200),
    ]
    path = tmp_path / "onco_late.csv"
    path.write_text("﻿" + ONCO_LATE_HEADER + "\n" + "\n".join(rows) + "\n", encoding="utf-8")
    result = run_batch([path], contracts["onco_late"], lake)
    assert result.status == "loaded"

    counts = build_gold(lake)
    assert counts["onco_late"] == 2  # one row per localization, latest snapshot only

    rows = _q(lake, "onco_late", "SELECT localization_id, advanced_total_count, advanced_share, snapshot_date FROM {t} ORDER BY localization_id")
    by_loc = {r[0]: r[1:] for r in rows}
    assert by_loc["C50"][0] == 400 and abs(by_loc["C50"][1] - 0.4) < 1e-9   # only the newer snapshot counted
    assert by_loc["C16"][0] == 300 and abs(by_loc["C16"][1] - 0.75) < 1e-9
    assert by_loc["C50"][2].isoformat() == "2026-05-13"


EQUIPMENT_HEADER = ("identifier,mo_id,inventory_number,quantity,release_date,input_date,finance_source_id,"
                     "decommission_date,is_fixed_asset,ownership_id,condition_id,serial_number,finance_code,"
                     "finance_name_ru,finance_name_kz,finance_begin_date,finance_end_date,finance_is_active,"
                     "ownership_code,ownership_name_ru,ownership_name_kz,ownership_begin_date,ownership_end_date,"
                     "ownership_is_active,sdu_load_date")


def equipment_row(identifier, mo_id, quantity="", decommission_date="", is_fixed_asset="1", load=LOAD):
    fields = [identifier, mo_id, "", str(quantity), "", "", "", decommission_date, is_fixed_asset] + [""] * 15 + [load]
    assert len(fields) == 25
    return ",".join(fields)


def test_equipment_counts_active_units_by_region_and_organization(tmp_path, synthetic_lake):
    # 5.10: quantity может быть NULL - строка тогда стоит за одну единицу (coalesce(quantity, 1)); строка с
    # decommission_date в счёт активного оборудования не идёт (is_active из контракта: "decommission_date is null",
    # тот же приём, что и is_active у drug_specs); mo_code без записи в mo_registry попадает в бакет "unknown".
    contracts = {c.dataset: c for c in load_contracts(CONTRACTS_DIR)}
    lake = synthetic_lake
    rows = [
        equipment_row("E1", "00AA", quantity="2"),                                                  # active, quantity=2 -> 2 units
        equipment_row("E2", "00AA", quantity=""),                                                    # active, null quantity -> fallback to 1 unit
        equipment_row("E3", "00AA", quantity="5", decommission_date="2020-01-01 00:00:00.000000"),   # decommissioned -> excluded entirely
        equipment_row("E4", "00ZZ", quantity="3"),                                                   # active, mo_code unknown to mo_registry -> region "unknown"
    ]
    path = tmp_path / "equipment.csv"
    path.write_text("\ufeff" + EQUIPMENT_HEADER + "\n" + "\n".join(rows) + "\n", encoding="utf-8")
    result = run_batch([path], contracts["equipment"], lake)
    assert result.status == "loaded"
    assert result.rows_quarantine == 0

    counts = build_gold(lake)
    assert counts["equipment"] == 2  # equipment_by_region rows: region "10" and "unknown"

    by_region = dict(_q(lake, "equipment_by_region", "SELECT region_kato, units FROM {t}"))
    assert by_region["10"] == 3        # E1 (2 units) + E2 (1 unit, null-quantity fallback); E3 excluded (decommissioned)
    assert by_region["unknown"] == 3   # E4, mo_code not resolvable to a region

    by_org = dict(_q(lake, "equipment_by_organization", "SELECT mo_code, units FROM {t}"))
    assert by_org["00AA"] == 3
    assert by_org["00ZZ"] == 3
