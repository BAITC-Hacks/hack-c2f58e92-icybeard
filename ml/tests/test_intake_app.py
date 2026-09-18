"""4.1/4.3/4.4/4.5/4.6/4.7: the intake HTTP console — upload a known schema (loads straight through to
gold), upload an unknown schema (contract draft), approve a draft (reprocesses the file that produced
it), and read back quarantine rows. Uses the two fixture files from ml/tests/fixtures/intake/."""
from pathlib import Path

from fastapi.testclient import TestClient

from darumen.intake.app import create_app
from darumen.intake.pipeline import Lakehouse

FIXTURES = Path(__file__).parent / "fixtures" / "intake"
CONTRACTS_DIR = Path(__file__).resolve().parents[2] / "contracts"


class _NullDrafter:
    """4.6 fallback path with no network at all — deterministic in CI, exercises the same code the real
    LlmContractDrafter falls back to when no provider key is configured."""

    name = "none"

    def available(self) -> bool:
        return False

    def enrich(self, draft: dict, samples: dict) -> dict:
        return draft


class _FakePublisher:
    def __init__(self):
        self.calls: list[tuple] = []

    def batch_loaded(self, dataset, batch_id, rows_loaded, rows_quarantined, partitions):
        self.calls.append((dataset, batch_id, rows_loaded, rows_quarantined, partitions))
        return "fake-event-id"


def _client(tmp_path, contracts_dir=CONTRACTS_DIR):
    lake = Lakehouse(tmp_path / "lake")
    publisher = _FakePublisher()
    app = create_app(lake, contracts_dir, drafter=_NullDrafter(), publisher=publisher)
    return TestClient(app), lake, publisher


def test_health_reports_the_drafter_and_llm_availability(tmp_path):
    client, _, _ = _client(tmp_path)
    body = client.get("/intake/health").json()
    assert body == {"status": "ok", "drafter": "none", "llmAvailable": False}


def test_upload_of_a_known_schema_loads_straight_to_silver_and_publishes(tmp_path):
    client, lake, publisher = _client(tmp_path)
    with (FIXTURES / "referrals_slice.csv").open("rb") as fh:
        response = client.post("/intake/files", files={"file": ("referrals_slice.csv", fh, "text/csv")})
    assert response.status_code == 201
    body = response.json()
    assert body["status"] == "loaded" and body["matchKind"] == "exact"
    assert body["batch"]["dataset"] == "bg_referrals"
    assert body["batch"]["rowsSilver"] == 3
    assert (lake.silver("bg_referrals")).exists()
    assert len(publisher.calls) == 1 and publisher.calls[0][0] == "bg_referrals"


def test_upload_of_an_unknown_schema_produces_a_reviewable_draft(tmp_path):
    client, _lake, publisher = _client(tmp_path)
    with (FIXTURES / "unknown_schema.csv").open("rb") as fh:
        response = client.post("/intake/files", files={"file": ("unknown_schema.csv", fh, "text/csv")})
    assert response.status_code == 201
    body = response.json()
    assert body["status"] == "unknown"
    dataset = body["dataset"]
    assert "device_id" in body["draft"]["columns"]
    assert not publisher.calls  # черновик не грузится в silver, событию неоткуда взяться

    listed = client.get("/intake/drafts").json()["items"]
    assert any(d["dataset"] == dataset for d in listed)
    fetched = client.get(f"/intake/drafts/{dataset}").json()
    assert fetched["dataset"] == dataset


def test_approving_a_draft_writes_the_contract_and_reprocesses_its_source_file(tmp_path):
    client, _lake, publisher = _client(tmp_path, contracts_dir=tmp_path / "contracts")
    with (FIXTURES / "unknown_schema.csv").open("rb") as fh:
        upload = client.post("/intake/files", files={"file": ("unknown_schema.csv", fh, "text/csv")}).json()
    dataset = upload["dataset"]

    approved = client.post(f"/intake/drafts/{dataset}/approve", json={"columnSemantics": {"region": "region_name"}}).json()
    assert Path(approved["contract"]).exists()
    assert approved["reprocessed"]["status"] == "loaded"
    assert approved["reprocessed"]["batch"]["dataset"] == dataset
    assert not (tmp_path / "lake" / "drafts" / f"{dataset}.yaml").exists()
    assert len(publisher.calls) == 1  # только после утверждения, не при первой (черновой) загрузке


def test_quarantine_lists_rows_that_failed_the_contracts_required_columns(tmp_path):
    import csv
    import io

    client, _lake, _ = _client(tmp_path)
    bad_csv = tmp_path / "referrals_bad.csv"
    good = (FIXTURES / "referrals_slice.csv").read_text(encoding="utf-8-sig")
    reader = list(csv.reader(io.StringIO(good)))
    header, rows = reader[0], reader[1:]
    # обнуляем обязательное поле icd10_ref_diag_code (не nullable в контракте) у одной строки — она должна уйти в карантин
    rows[0][header.index("icd10_ref_diag_code")] = ""
    with bad_csv.open("w", encoding="utf-8-sig", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(header)
        writer.writerows(rows)
    with bad_csv.open("rb") as fh:
        result = client.post("/intake/files", files={"file": ("referrals_bad.csv", fh, "text/csv")}).json()
    assert result["batch"]["rowsQuarantine"] == 1
    q = client.get("/intake/quarantine", params={"dataset": "bg_referrals"}).json()
    assert q["total"] == 1
    assert q["items"][0]["_quarantine_reason"] == "missing:icd10_ref_diag_code"
