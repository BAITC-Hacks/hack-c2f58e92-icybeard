"""Shared fixtures: a tiny synthetic lakehouse built through the real intake pipeline."""
from pathlib import Path

import pytest

from darumen.intake.contracts import load_contracts
from darumen.intake.pipeline import Lakehouse, run_batch

CONTRACTS_DIR = Path(__file__).resolve().parents[2] / "contracts"

REFERRALS_HEADER = ("hospitalization_code,referring_mo,hospital_mo,icd10_ref_diag_code,diagnosis_name,bed_profile,"
                    "registration_dt,planned_dt,polyclinic_dt,hospitalization_dt,refusal_dt,territorial_type,"
                    "referral_purpose,finance_source,sdu_load_date")
ER_HEADER = "region_in,org_in,resident,insured,benefit_cat,refuse_dt,attach_region,attach_org,icd10,icd_name,amount,finance_src,sdu_load_date"
LOAD = "2026-05-13 03:28:05.149000"
HOSPITAL_A = '"КГП на ПХВ ""Городская больница №1"" управления здравоохранения области Абай"'
HOSPITAL_B = '"КГП на ПХВ ""Областная клиническая больница"" управления здравоохранения области Абай"'
POLYCLINIC = '"КГП на ПХВ ""Городская поликлиника №3"" управления здравоохранения области Абай"'


def referral(code, reg, hosp="", refusal="", hospital=HOSPITAL_A, profile_name="Терапевтические", icd="M54.4"):
    return (f"{code},{POLYCLINIC},{hospital},{icd},Диагноз,{profile_name},{reg},2025-01-05 00:00:00,{reg},"
            f"{hosp},{refusal},Город,Консервативное лечение,Активы Фонда на ОСМС,{LOAD}")


def er_visit(day, org=HOSPITAL_A, icd="J03.9", region="Область Абай"):
    return f"{region},{org},Город,Застрахован,Нет льгот,{day} 10:00:00,{region},{org},{icd},Диагноз,,Активы Фонда на ОСМС,{LOAD}"


REFERRAL_ROWS = [
    # hospital A, therapy 021: registrations Jan 5..7, waits 3 / 5 / refused / open, plus Jan 20 with wait 1
    referral("10.00AA.021.1", "2025-01-05 08:00:00", hosp="2025-01-08 08:00:00"),
    referral("10.00AA.021.2", "2025-01-06 09:00:00", hosp="2025-01-11 08:00:00"),
    referral("10.00AA.021.3", "2025-01-07 09:00:00", refusal="2025-01-09 12:00:00"),
    referral("10.00AA.021.4", "2025-01-07 10:00:00"),
    referral("10.00AA.021.5", "2025-01-20 10:00:00", hosp="2025-01-21 08:00:00"),
    referral("10.00AA.021.6", "2025-03-10 10:00:00", hosp="2025-03-14 08:00:00"),
    # hospital B, ophthalmology 381, long wait
    referral("10.00BB.381.1", "2025-01-10 08:00:00", hosp="2025-02-20 08:00:00", hospital=HOSPITAL_B, profile_name="Офтальмологические для взрослых", icd="H25.1"),
    referral("10.00BB.381.2", "2025-02-01 08:00:00", hosp="2025-03-15 08:00:00", hospital=HOSPITAL_B, profile_name="Офтальмологические для взрослых", icd="H25.1"),
    # day hospital, zero wait, excluded from features
    referral("10.00AA.DH.1", "2025-01-05 08:00:00", hosp="2025-01-05 08:00:00", profile_name=""),
]
ER_ROWS = [er_visit("2025-01-05"), er_visit("2025-01-05"), er_visit("2025-01-06", icd="I10"), er_visit("2025-01-06", org=HOSPITAL_B)]


def write_csv(path: Path, header: str, rows: list[str]) -> Path:
    path.write_text("﻿" + header + "\n" + "\n".join(rows) + "\n", encoding="utf-8")
    return path


@pytest.fixture
def synthetic_lake(tmp_path) -> Lakehouse:
    contracts = {c.dataset: c for c in load_contracts(CONTRACTS_DIR)}
    lake = Lakehouse(tmp_path / "lake")
    referrals = write_csv(tmp_path / "referrals.csv", REFERRALS_HEADER, REFERRAL_ROWS)
    er = write_csv(tmp_path / "er.csv", ER_HEADER, ER_ROWS)
    assert run_batch([referrals], contracts["bg_referrals"], lake).status == "loaded"
    assert run_batch([er], contracts["bg_er_refusals"], lake).status == "loaded"
    return lake
