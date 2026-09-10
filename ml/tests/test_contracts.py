from pathlib import Path

from darumen.intake.contracts import BOM, EXACT, FUZZY, load_contracts, match_signature

CONTRACTS_DIR = Path(__file__).resolve().parents[2] / "contracts"

REFERRALS_HEADER = [
    "hospitalization_code", "referring_mo", "hospital_mo", "icd10_ref_diag_code", "diagnosis_name",
    "bed_profile", "registration_dt", "planned_dt", "polyclinic_dt", "hospitalization_dt", "refusal_dt",
    "territorial_type", "referral_purpose", "finance_source", "sdu_load_date",
]


def test_contracts_load_and_have_keys():
    contracts = load_contracts(CONTRACTS_DIR)
    assert {c.dataset for c in contracts} >= {"bg_referrals", "bg_waiting", "bg_er_refusals", "ersb_treated_count"}
    for contract in contracts:
        assert contract.signature, contract.dataset
        assert contract.keys, contract.dataset


def test_exact_match_with_bom_and_case():
    contracts = load_contracts(CONTRACTS_DIR)
    header = [BOM + REFERRALS_HEADER[0].upper()] + REFERRALS_HEADER[1:]
    match = match_signature(header, contracts)
    assert match is not None and match.kind == EXACT and match.contract.dataset == "bg_referrals"


def test_fuzzy_match_when_one_column_is_missing():
    contracts = load_contracts(CONTRACTS_DIR)
    match = match_signature(REFERRALS_HEADER[:-1], contracts)
    assert match is not None and match.kind == FUZZY and match.contract.dataset == "bg_referrals"


def test_unknown_schema_returns_none():
    contracts = load_contracts(CONTRACTS_DIR)
    assert match_signature(["a", "b", "c"], contracts) is None
