from pathlib import Path

from fastapi.testclient import TestClient

from darumen.scribe.app import create_app
from darumen.scribe.draft import RuleDrafter
from darumen.scribe.store import SessionStore
from darumen.scribe.transcribe import FakeTranscriber


def client(tmp_path: Path) -> tuple[TestClient, SessionStore]:
    store = SessionStore(tmp_path / "scribe")
    return TestClient(create_app(store, FakeTranscriber(), RuleDrafter())), store


def test_consent_is_required(tmp_path):
    api, _ = client(tmp_path)
    assert api.post("/scribe/sessions", json={"consent": False}).status_code == 400
    assert api.post("/scribe/sessions", json={"consent": True, "language": "de"}).status_code == 422


def test_full_flow_audio_draft_approve_leaflet_and_audio_deleted(tmp_path):
    api, store = client(tmp_path)
    created = api.post("/scribe/sessions", json={"consent": True, "language": "ru"}, headers={"X-Actor": "doctor1"})
    assert created.status_code == 201
    session_id = created.json()["sessionId"]

    uploaded = api.post(f"/scribe/sessions/{session_id}/audio", files={"file": ("consult.webm", b"\x1a\x45\xdf\xa3fake-audio", "audio/webm")})
    assert uploaded.status_code == 200
    assert "амлодипин" in uploaded.json()["text"]
    audio_files = list((store.root / "audio").iterdir())
    assert len(audio_files) == 1

    draft = api.post(f"/scribe/sessions/{session_id}/draft").json()
    names = [s["name"] for s in draft["sections"]]
    assert "Жалобы" in names and "Осмотр" in names and "Диагноз" in names and "Назначения" in names
    assert "амлодипин" in draft["patientLeaflet"]["text"] and draft["model"] == "rules@1.0.0"

    approved = api.post(f"/scribe/sessions/{session_id}/approve", json={"sections": draft["sections"], "patientLeaflet": draft["patientLeaflet"]["text"] + " Явка через 2 недели."})
    assert approved.status_code == 200
    token = approved.json()["leafletToken"]
    assert not list((store.root / "audio").iterdir())  # аудио удалено при утверждении
    assert api.post(f"/scribe/sessions/{session_id}/audio", files={"file": ("x.webm", b"1", "audio/webm")}).status_code == 409

    leaflet = api.get(f"/scribe/leaflets/{token}").json()
    assert "Явка через 2 недели" in leaflet["text"] and leaflet["language"] == "ru"
    assert api.get("/scribe/leaflets/nope").status_code == 404


def test_typed_transcript_without_microphone(tmp_path):
    api, _ = client(tmp_path)
    session_id = api.post("/scribe/sessions", json={"consent": True}).json()["sessionId"]
    assert api.post(f"/scribe/sessions/{session_id}/draft").status_code == 409
    api.post(f"/scribe/sessions/{session_id}/transcript", json={"text": "Жалобы на кашель неделю. Температура 37.5. Назначаю обильное питьё и контроль через три дня."})
    draft = api.post(f"/scribe/sessions/{session_id}/draft").json()
    assert any(s["name"] == "Назначения" and "контроль" in s["text"] for s in draft["sections"])
    assert api.get("/scribe/health").json()["transcriber"] == "fake"


def test_llm_drafter_without_key_uses_rules(monkeypatch):
    from darumen.scribe.draft import LlmDrafter
    from darumen.scribe.transcribe import Segment

    monkeypatch.delenv("DEEPSEEK_API_KEY", raising=False)
    drafter = LlmDrafter()
    assert drafter.name == "deepseek/deepseek-chat" and not drafter.available()
    draft = drafter.draft([Segment(0, 4, "Жалобы на кашель. Назначаю сироп.")], "ru")
    assert draft.model == "rules@1.0.0" and any(s.name == "Назначения" for s in draft.sections)
