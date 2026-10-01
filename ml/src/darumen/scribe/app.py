"""FastAPI application of the scribe. Mounted behind the .NET API by YARP under /api/v1/scribe."""
from __future__ import annotations

import logging
import os
import re
import shutil
from pathlib import Path
from typing import Annotated

from fastapi import FastAPI, File, Header, HTTPException, Request, UploadFile
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from .draft import CorrectionUnavailable, Drafter, default_drafter
from .store import SessionStore
from .transcribe import Segment, Transcriber, TranscriberUnavailable, default_transcriber
from .vocabulary import MAX_CUSTOM, Vocabulary

log = logging.getLogger(__name__)
SENTENCE_END = re.compile(r"(?<=[.!?…])\s+")

MAX_AUDIO_BYTES = 50 * 1024 * 1024
LANGUAGES = ("ru", "kk")


class CreateSession(BaseModel):
    consent: bool
    language: str = "ru"
    # реф пациента: API создаёт сессию только по его согласию и передаёт реф, чтобы запись была привязана к пациенту
    patient_ref: str | None = Field(default=None, alias="patientRef", max_length=64)


class TranscriptIn(BaseModel):
    text: str = Field(min_length=1, max_length=20_000)


class SegmentIn(BaseModel):
    text: str = Field(min_length=1, max_length=4_000)


class VocabularyIn(BaseModel):
    words: list[str] = Field(max_length=MAX_CUSTOM)


class SectionIn(BaseModel):
    name: str
    text: str


class ApproveIn(BaseModel):
    sections: list[SectionIn]
    patient_leaflet: str = Field(alias="patientLeaflet")


def create_app(store: SessionStore, transcriber: Transcriber, drafter: Drafter, vocabulary: Vocabulary | None = None) -> FastAPI:
    vocabulary = vocabulary or Vocabulary()
    app = FastAPI(title="Darumen Scribe", version="0.1.0")

    @app.exception_handler(HTTPException)
    async def problem(_: Request, exc: HTTPException):
        # ответ в виде problem details (title + detail), как у API: веб показывает понятный текст, а не «Internal Server Error»
        return JSONResponse({"title": "Скрайб", "detail": str(exc.detail), "status": exc.status_code}, status_code=exc.status_code)

    def session_or_404(session_id: str):
        session = store.get(session_id)
        if session is None:
            raise HTTPException(404, "сессия записи не найдена: сервис скрайба перезапускался — запросите у пациента новое согласие")
        return session

    def editable_session(session_id: str):
        """Сессия, в которую ещё можно писать: после утверждения аудио удалено, запись зафиксирована."""
        session = session_or_404(session_id)
        if session.approved:
            raise HTTPException(409, "session already approved, audio was deleted")
        return session

    @app.get("/scribe/health")
    def health():
        return {"status": "ok", "transcriber": transcriber.name, "drafter": getattr(drafter, "name", "unknown"),
                "transcriberState": getattr(transcriber, "state", "ready"), "transcriberError": getattr(transcriber, "error", None),
                "transcriberProgress": transcriber.progress() if hasattr(transcriber, "progress") else None}

    @app.post("/scribe/sessions", status_code=201)
    def create_session(body: CreateSession, x_actor: str | None = Header(default=None)):
        if not body.consent:
            raise HTTPException(400, "consent is required before recording")
        if body.language not in LANGUAGES:
            raise HTTPException(422, f"language must be one of {LANGUAGES}")
        session = store.create(x_actor or "anonymous", body.language, body.patient_ref)
        return {"sessionId": session.session_id, "wsUrl": None, "uploadUrl": f"/scribe/sessions/{session.session_id}/audio"}

    @app.post("/scribe/sessions/{session_id}/audio")
    def upload_audio(session_id: str, file: Annotated[UploadFile, File()]):
        session = editable_session(session_id)
        suffix = Path(file.filename or "audio.webm").suffix or ".webm"
        target = store.audio_path(session, suffix)
        with target.open("wb") as out:
            shutil.copyfileobj(file.file, out, length=1024 * 1024)
        if target.stat().st_size > MAX_AUDIO_BYTES:
            target.unlink()
            raise HTTPException(413, "audio is larger than 50 MB")
        session.audio_path = str(target)
        try:
            segments = transcriber.transcribe(target, session.language)
        except TranscriberUnavailable as exc:
            store.delete_audio(session)
            raise HTTPException(503, str(exc)) from exc
        except Exception as exc:  # битый или неподдерживаемый файл: понятный ответ вместо 500
            log.exception("transcription failed for %s (%d bytes)", target.name, target.stat().st_size if target.exists() else -1)
            store.delete_audio(session)
            reason = f"{type(exc).__name__}: {exc}".strip()[:160]
            raise HTTPException(422, f"не удалось распознать запись ({reason}). Проверьте, что это аудио (webm, ogg, mp3, wav, m4a) "
                                     "длиннее пары секунд") from exc
        if not segments:
            store.delete_audio(session)
            raise HTTPException(422, "речь не распознана: запись слишком короткая или тихая — запишите ещё раз или вставьте текст")
        session.transcript = [{"t0": s.t0, "t1": s.t1, "text": s.text} for s in segments]
        session.draft = None  # новая стенограмма — старый черновик больше не про неё
        store.save(session)
        return {"transcript": session.transcript, "text": " ".join(s.text for s in segments), "transcriber": transcriber.name}

    @app.post("/scribe/sessions/{session_id}/transcript")
    def set_transcript(session_id: str, body: TranscriptIn):
        """Typed or pasted transcript for demos without a microphone."""
        session = editable_session(session_id)
        sentences = [s.strip() for s in SENTENCE_END.split(body.text.replace("\n", " ")) if s.strip()]
        session.transcript = [{"t0": float(i * 4), "t1": float(i * 4 + 4), "text": s if s[-1] in ".!?…" else s + "."}
                              for i, s in enumerate(sentences)]
        session.draft = None
        store.save(session)
        return {"transcript": session.transcript}

    @app.post("/scribe/sessions/{session_id}/segments/{index}")
    def edit_segment(session_id: str, index: int, body: SegmentIn):
        """Врач исправил фразу стенограммы. Исходный текст распознавания сохраняется (original), чтобы правку было
        видно и её можно было вернуть; текст, равный исходному, — это возврат."""
        session = editable_session(session_id)
        if not 0 <= index < len(session.transcript):
            raise HTTPException(404, "фраза стенограммы не найдена")
        segment, text = session.transcript[index], " ".join(body.text.split())
        original = segment.get("original", segment["text"])
        if text == original:
            segment.pop("original", None)
            segment.pop("source", None)
        elif text != segment["text"]:
            segment["original"], segment["source"] = original, "doctor"
        segment["text"] = text
        store.save(session)
        return {"transcript": session.transcript}

    @app.post("/scribe/sessions/{session_id}/correct")
    def correct_terms(session_id: str):
        """По кнопке врача: языковая модель исправляет искажённые медицинские термины, сверяясь со словарём.
        Исправленные фразы помечаются (source=ai) и хранят исходный текст."""
        session = editable_session(session_id)
        if not session.transcript:
            raise HTTPException(409, "стенограммы ещё нет")
        texts = [t["text"] for t in session.transcript]
        # сначала словарь (работает всегда, без сети), затем языковая модель, если она доступна
        changes = {i: (text, "dictionary") for i, text in vocabulary.fix_by_dictionary(texts, session.language).items()}
        current = [changes[i][0] if i in changes else t for i, t in enumerate(texts)]
        ai_error = None
        if hasattr(drafter, "correct"):
            try:
                for i, text in drafter.correct(current, vocabulary.candidates(current, session.language), session.language).items():
                    changes[i] = (text, "ai")
            except CorrectionUnavailable as exc:
                ai_error = str(exc)
        else:
            ai_error = "языковая модель не настроена"
        for i, (text, source) in changes.items():
            segment = session.transcript[i]
            segment["original"] = segment.get("original", segment["text"])
            segment["text"], segment["source"] = text, source
        store.save(session)
        return {"transcript": session.transcript, "changed": len(changes), "aiError": ai_error}

    @app.get("/scribe/vocabulary")
    def get_vocabulary():
        return {"words": vocabulary.custom, "builtIn": vocabulary.builtin_count(), "groups": vocabulary.builtin_groups()}

    @app.post("/scribe/vocabulary")
    def set_vocabulary(body: VocabularyIn):
        """Термины клиники: подсказываются модели распознавания и используются при исправлении через ИИ."""
        return {"words": vocabulary.set_custom(body.words), "builtIn": vocabulary.builtin_count(), "groups": vocabulary.builtin_groups()}

    @app.post("/scribe/sessions/{session_id}/draft")
    def make_draft(session_id: str):
        session = editable_session(session_id)
        if not session.transcript:
            raise HTTPException(409, "no transcript yet")
        draft = drafter.draft([Segment(t["t0"], t["t1"], t["text"]) for t in session.transcript], session.language)
        session.draft = {"sections": [{"name": s.name, "text": s.text, "spans": s.spans} for s in draft.sections], "leaflet": draft.leaflet, "model": draft.model}
        store.save(session)
        return {**session.draft, "patientLeaflet": {"text": draft.leaflet}}

    @app.get("/scribe/sessions/{session_id}")
    def get_session(session_id: str):
        """Состояние начатой записи — чтобы врач продолжил с того же места (стенограмма, черновик)."""
        session = session_or_404(session_id)
        draft = {**session.draft, "patientLeaflet": {"text": session.draft["leaflet"]}} if session.draft else None
        return {"sessionId": session.session_id, "language": session.language, "approved": session.approved,
                "transcript": session.transcript, "draft": draft}

    @app.post("/scribe/sessions/{session_id}/approve", status_code=200)
    def approve(session_id: str, body: ApproveIn):
        session = editable_session(session_id)
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
        store.save(session)

    @app.get("/scribe/leaflets/{token}")
    def leaflet(token: str):
        found = store.leaflet(token)
        if found is None:
            raise HTTPException(404, "leaflet not found")
        return found

    return app


def build_default_app() -> FastAPI:
    root = Path(os.environ.get("DARUMEN_SCRIBE_DIR", "lakehouse/scribe"))
    transcriber = default_transcriber()
    if hasattr(transcriber, "warm_up"):
        transcriber.warm_up()  # модель грузится в фоне сразу при старте, а не на первом приёме
    vocabulary = Vocabulary(root)
    if hasattr(transcriber, "vocabulary"):
        transcriber.vocabulary = vocabulary
    return create_app(SessionStore(root), transcriber, default_drafter(), vocabulary)
