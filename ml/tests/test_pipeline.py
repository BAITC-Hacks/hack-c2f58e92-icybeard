import json
from pathlib import Path

import duckdb

from darumen.intake.contracts import load_contracts
from darumen.intake.fingerprint import fingerprint
from darumen.intake.pipeline import (
    STATUS_BLOCKED,
    STATUS_LOADED,
    STATUS_SKIPPED,
    Lakehouse,
    draft_contract,
    plan_batches,
    run_batch,
)

CONTRACTS_DIR = Path(__file__).resolve().parents[2] / "contracts"
HEADER = ("hospitalization_code,referring_mo,hospital_mo,icd10_ref_diag_code,diagnosis_name,bed_profile,"
          "registration_dt,planned_dt,polyclinic_dt,hospitalization_dt,refusal_dt,territorial_type,"
          "referral_purpose,finance_source,sdu_load_date")
MO = '"КГП на ПХВ ""Центральная районная больница"" управления здравоохранения области Абай"'
LOAD = "2026-05-13 03:28:05.149000"


def row(code, reg, hosp="", refusal="", planned="2025-01-05 00:00:00"):
    return (f"{code},{MO},{MO},M54.4,Люмбаго с ишиасом,Терапевтические,{reg},{planned},2025-01-05 08:22:05.290000,"
            f"{hosp},{refusal},Город,Консервативное лечение,Активы Фонда на ОСМС,{LOAD}")


def write_csv(path: Path, rows: list[str]) -> Path:
    path.write_text("﻿" + HEADER + "\n" + "\n".join(rows) + "\n", encoding="utf-8")
    return path


def referrals_contract():
    return next(c for c in load_contracts(CONTRACTS_DIR) if c.dataset == "bg_referrals")


def test_batch_loads_typed_silver_and_quarantines_bad_rows(tmp_path):
    csv = write_csv(tmp_path / "referrals_part_001_of_001.csv", [
        row("10.00MY.021.1", "2025-01-05 08:22:02.517000", hosp="2025-01-08 08:00:00"),
        row("10.00MY.021.2", "2025-01-06 10:00:00", refusal="2025-01-20 10:00:00"),
        row("10.00MY.DH.3", "2025-02-01 09:00:00", planned="1970-01-01 00:00:00"),
        row("10.00MY.021.4", "2025-01-05 08:22:02.517000", hosp="2025-01-01 08:00:00"),  # hospitalised before registration
    ])
    lake = Lakehouse(tmp_path / "lake")
    result = run_batch([csv], referrals_contract(), lake)

    assert result.status == STATUS_LOADED, result.error
    assert result.rows_bronze == 4 and result.rows_silver == 3 and result.rows_quarantine == 1
    assert result.partitions == ["region_kato=10/p_month=2025-01", "region_kato=10/p_month=2025-02"]
    assert any(r.reason == "all_regions_present" and not r.passed for r in result.rules)

    con = duckdb.connect()
    silver = con.execute(
        f"SELECT hospitalization_code, region_kato, mo_code, profile_code, wait_days, outcome, is_day_hospital, planned_dt, "
        f"hospital_mo_key, icd10_ref_diag_code_canon FROM {lake.silver_sql('bg_referrals')} ORDER BY hospitalization_code"
    ).fetchall()
    assert [r[0] for r in silver] == ["10.00MY.021.1", "10.00MY.021.2", "10.00MY.DH.3"]
    first = silver[0]
    assert first[1] == "10" and first[2] == "00MY" and first[3] == "021" and first[4] == 3 and first[5] == "hospitalized"
    assert silver[1][5] == "refused" and silver[2][5] == "open" and silver[2][6] is True
    assert silver[2][7] is None  # 1970-01-01 treated as null
    assert first[8] == "центральная районная больница" and first[9] == "M54.4"

    quarantine = con.execute(f"SELECT hospitalization_code, _quarantine_reason FROM read_parquet('{lake.quarantine('bg_referrals')}/*.parquet')").fetchall()
    assert quarantine == [("10.00MY.021.4", "negative_wait")]

    manifest = json.loads(next(lake.manifests("bg_referrals").glob("*.json")).read_text(encoding="utf-8"))
    assert manifest["status"] == STATUS_LOADED and manifest["files"][0]["rows"] == 4 and manifest["files"][0]["md5"]

    again = run_batch([csv], referrals_contract(), lake)
    assert again.status == STATUS_SKIPPED and again.batch_id == result.batch_id


def test_block_rule_rejects_batch(tmp_path):
    csv = write_csv(tmp_path / "old.csv", [row("10.00MY.021.1", "2010-01-05 08:22:02", hosp="2010-01-08 08:00:00")])
    lake = Lakehouse(tmp_path / "lake")
    result = run_batch([csv], referrals_contract(), lake)
    assert result.status == STATUS_BLOCKED and "registration_out_of_range" in result.error
    assert not lake.silver("bg_referrals").exists()
    assert lake.bronze("bg_referrals").exists()


def test_unknown_schema_produces_draft(tmp_path):
    csv = tmp_path / "Новый набор_part_001_of_002.csv"
    csv.write_text("region_name,mkb10_code,visit_dt,amount\nАлматы г.а.,J03.9,2025-01-01 10:00:00,12.5\n", encoding="utf-8")
    lake = Lakehouse(tmp_path / "lake")
    plans = plan_batches(csv, CONTRACTS_DIR)
    assert len(plans) == 1 and plans[0].match is None
    draft = draft_contract(csv, fingerprint(csv), lake)
    text = draft.read_text(encoding="utf-8")
    assert "status: draft" in text and "semantic: region_name" in text and "semantic: icd10" in text
    assert "type: timestamp" in text and "type: decimal" in text


def test_folder_of_parts_is_one_batch(tmp_path):
    folder = tmp_path / "Направления"
    folder.mkdir()
    write_csv(folder / "x_part_001_of_002.csv", [row("10.00MY.021.1", "2025-01-05 08:00:00", hosp="2025-01-08 08:00:00")])
    write_csv(folder / "x_part_002_of_002.csv", [row("75.01YF.381.9", "2025-03-05 08:00:00", hosp="2025-04-20 08:00:00")])
    plans = plan_batches(folder, CONTRACTS_DIR)
    assert len(plans) == 1 and len(plans[0].files) == 2 and plans[0].match.contract.dataset == "bg_referrals"
    result = run_batch(plans[0].files, plans[0].match.contract, Lakehouse(tmp_path / "lake"))
    assert result.status == STATUS_LOADED and result.rows_silver == 2 and len(result.files) == 2
