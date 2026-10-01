"""Session store: audio and transcript live only until approval; approved notes and leaflets persist as JSON."""
from __future__ import annotations

import json
import secrets
import shutil
from dataclasses import asdict, dataclass, field
from datetime import UTC, datetime
from pathlib import Path


@dataclass
class ScribeSession:
    session_id: str
    actor: str
    language: str
    created_at: str
    audio_path: str | None = None
    transcript: list[dict] = field(default_factory=list)
    draft: dict | None = None
    approved: bool = False
    leaflet_token: str | None = None
    patient_ref: str | None = None


class SessionStore:
    """Сессии хранятся на диске (sessions/<id>.json): перезапуск или пересборка сервиса не теряет начатую запись,
    врач продолжает её с того же места."""

    def __init__(self, root: Path):
        self.root = root
        for folder in ("audio", "notes", "leaflets", "sessions"):
            (self.root / folder).mkdir(parents=True, exist_ok=True)
        self._sessions: dict[str, ScribeSession] = {}
        for path in (self.root / "sessions").glob("*.json"):
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
                self._sessions[data["session_id"]] = ScribeSession(**data)
            except (ValueError, KeyError, TypeError):
                continue  # повреждённый файл не мешает остальным сессиям

    def create(self, actor: str, language: str, patient_ref: str | None = None) -> ScribeSession:
        session = ScribeSession(secrets.token_hex(8), actor, language, datetime.now(UTC).isoformat(), patient_ref=patient_ref)
        self._sessions[session.session_id] = session
        self.save(session)
        return session

    def save(self, session: ScribeSession) -> None:
        """Записать состояние сессии на диск после каждого изменения."""
        path = self.root / "sessions" / f"{session.session_id}.json"
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps(asdict(session), ensure_ascii=False), encoding="utf-8")
        tmp.replace(path)

    def get(self, session_id: str) -> ScribeSession | None:
        return self._sessions.get(session_id)

    def audio_path(self, session: ScribeSession, suffix: str) -> Path:
        return self.root / "audio" / f"{session.session_id}{suffix}"

    def delete_audio(self, session: ScribeSession) -> None:
        if session.audio_path and Path(session.audio_path).exists():
            Path(session.audio_path).unlink()
        session.audio_path = None

    def approve(self, session: ScribeSession, sections: list[dict], leaflet: str) -> str:
        """Persist the approved note and leaflet, drop audio and transcript, return the public leaflet token."""
        token = secrets.token_urlsafe(16)
        approved_at = datetime.now(UTC).isoformat()
        (self.root / "notes" / f"{session.session_id}.json").write_text(json.dumps(
            {"sessionId": session.session_id, "actor": session.actor, "patientRef": session.patient_ref, "language": session.language, "approvedAt": approved_at,
             "sections": sections, "leafletToken": token}, ensure_ascii=False, indent=1), encoding="utf-8")
        (self.root / "leaflets" / f"{token}.json").write_text(json.dumps(
            {"text": leaflet, "language": session.language, "approvedAt": approved_at}, ensure_ascii=False, indent=1), encoding="utf-8")
        self.delete_audio(session)
        session.transcript = []
        session.draft = None
        session.approved = True
        session.leaflet_token = token
        self.save(session)
        return token

    def leaflet(self, token: str) -> dict | None:
        path = self.root / "leaflets" / f"{token}.json"
        return json.loads(path.read_text(encoding="utf-8")) if path.exists() and token.replace("-", "").replace("_", "").isalnum() else None

    def wipe(self) -> None:
        shutil.rmtree(self.root / "audio", ignore_errors=True)
        (self.root / "audio").mkdir(parents=True, exist_ok=True)

    def snapshot(self, session: ScribeSession) -> dict:
        data = asdict(session)
        data.pop("audio_path", None)
        return data
