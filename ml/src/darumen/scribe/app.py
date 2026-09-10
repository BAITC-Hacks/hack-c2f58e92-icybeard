"""FastAPI application of the scribe. Mounted behind the .NET API by YARP under /api/v1/scribe."""
from __future__ import annotations

import os
import shutil
from pathlib import Path
from typing import Annotated

from fastapi import FastAPI, File, Header, HTTPException, UploadFile
from pydantic import BaseModel, Field

from .draft import Drafter, default_drafter
from .store import SessionStore
from .transcribe import Segment, Transcriber, default_transcriber

MAX_AUDIO_BYTES = 50 * 1024 * 1024
LANGUAGES = ("ru", "kk")


class CreateSession(BaseModel):
    consent: bool
    language: str = "ru"


class TranscriptIn(BaseModel):
    text: str = Field(min_length=1, max_length=20_000)


class SectionIn(BaseModel):
    name: str
    text: str


class ApproveIn(BaseModel):
    sections: list[SectionIn]
    patient_leaflet: str = Field(alias="patientLeaflet")


def create_app(store: SessionStore, transcriber: Transcriber, drafter: Drafter) -> FastAPI:
    app = FastAPI(title="Darumen Scribe", version="0.1.0")

    def session_or_404(session_id: str):
        session = store.get(session_id)
        if session is None:
            raise HTTPException(404, "session not found")
        return session

    @app.get("/scribe/health")
    def health():
        return {"status": "ok", "transcriber": transcriber.name, "drafter": getattr(drafter, "name", "unknown")}

    @app.post("/scribe/sessions", status_code=201)
    def create_session(body: CreateSession, x_actor: str | None = Header(default=None)):
        if not body.consent:
            raise HTTPException(400, "consent is required before recording")
        if body.language not in LANGUAGES:
            raise HTTPException(422, f"language must be one of {LANGUAGES}")
        session = store.create(x_actor or "anonymous", body.language)
        return {"sessionId": session.session_id, "wsUrl": None, "uploadUrl": f"/scribe/sessions/{session.session_id}/audio"}

    @app.post("/scribe/sessions/{session_id}/audio")
    def upload_audio(session_id: str, file: Annotated[UploadFile, File()]):
        session = session_or_404(session_id)
        if session.approved:
            raise HTTPException(409, "session already approved, audio was deleted")
        suffix = Path(file.filename or "audio.webm").suffix or ".webm"
        target = store.audio_path(session, suffix)
        with target.open("wb") as out:
            shutil.copyfileobj(file.file, out, length=1024 * 1024)
        if target.stat().st_size > MAX_AUDIO_BYTES:
            target.unlink()
            raise HTTPException(413, "audio is larger than 50 MB")
        session.audio_path = str(target)
        segments = transcriber.transcribe(target, session.language)
        session.transcript = [{"t0": s.t0, "t1": s.t1, "text": s.text} for s in segments]
        return {"transcript": session.transcript, "text": " ".join(s.text for s in segments), "transcriber": transcriber.name}

    @app.post("/scribe/sessions/{session_id}/transcript")
    def set_transcript(session_id: str, body: TranscriptIn):
        """Typed or pasted transcript for demos without a microphone."""
        session = session_or_404(session_id)
        sentences = [s.strip() for s in body.text.replace("\n", " ").split(". ") if s.strip()]
        session.transcript = [{"t0": float(i * 4), "t1": float(i * 4 + 4), "text": s if s.endswith(".") else s + "."} for i, s in enumerate(sentences)]
        return {"transcript": session.transcript}

    @app.post("/scribe/sessions/{session_id}/draft")
    def make_draft(session_id: str):
        session = session_or_404(session_id)
        if not session.transcript:
            raise HTTPException(409, "no transcript yet")
        draft = drafter.draft([Segment(t["t0"], t["t1"], t["text"]) for t in session.transcript], session.language)
        session.draft = {"sections": [{"name": s.name, "text": s.text, "spans": s.spans} for s in draft.sections], "leaflet": draft.leaflet, "model": draft.model}
        return {**session.draft, "patientLeaflet": {"text": draft.leaflet}}

    @app.post("/scribe/sessions/{session_id}/approve", status_code=200)
    def approve(session_id: str, body: ApproveIn):
        session = session_or_404(session_id)
        if not body.sections or not body.patient_leaflet.strip():
            raise HTTPException(422, "sections and patientLeaflet are required")
        token = store.approve(session, [s.model_dump() for s in body.sections], body.patient_leaflet)
        return {"leafletToken": token, "leafletUrl": f"/scribe/leaflets/{token}", "audioDeleted": True}

    @app.delete("/scribe/sessions/{session_id}", status_code=204)
    def discard(session_id: str):
        session = session_or_404(session_id)
        store.delete_audio(session)
        session.transcript = []
        session.draft = None

    @app.get("/scribe/leaflets/{token}")
    def leaflet(token: str):
        found = store.leaflet(token)
        if found is None:
            raise HTTPException(404, "leaflet not found")
        return found

    return app


def build_default_app() -> FastAPI:
    root = Path(os.environ.get("DARUMEN_SCRIBE_DIR", "lakehouse/scribe"))
    return create_app(SessionStore(root), default_transcriber(), default_drafter())
