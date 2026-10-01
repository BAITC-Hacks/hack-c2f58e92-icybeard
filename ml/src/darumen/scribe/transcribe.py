"""Transcribers: faster-whisper when installed, a fake for tests and machines without the model."""
from __future__ import annotations

import logging
import threading
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol


@dataclass(frozen=True)
class Segment:
    t0: float
    t1: float
    text: str


class Transcriber(Protocol):
    name: str

    def transcribe(self, audio: Path, language: str) -> list[Segment]: ...


log = logging.getLogger(__name__)



def decode_audio(audio: Path, rate: int = 16000):
    """Аудио любого формата, который читает ffmpeg, -> float32 моно 16 кГц. Свой декодер вместо
    faster_whisper.decode_audio: тот передаёт в av.open аргумент metadata_errors, которого нет в новых PyAV."""
    import av
    import numpy as np

    resampler = av.AudioResampler(format="s16", layout="mono", rate=rate)
    chunks = []
    with av.open(str(audio), mode="r") as container:
        stream = container.streams.audio[0]
        for frame in container.decode(stream):
            frame.pts = None
            for out in resampler.resample(frame):
                chunks.append(out.to_ndarray().reshape(-1))
        for out in resampler.resample(None):
            chunks.append(out.to_ndarray().reshape(-1))
    if not chunks:
        return np.zeros(0, dtype=np.float32)
    return np.concatenate(chunks).astype(np.float32) / 32768.0


class TranscriberUnavailable(RuntimeError):
    """Модель распознавания ещё загружается или не загрузилась — понятная причина для врача вместо 500."""


class WhisperTranscriber:
    """faster-whisper (CTranslate2). Модель скачивается один раз (кэш HF_HOME — в томе сервиса) и загружается
    в фоне при старте (warm_up), чтобы первый приём не ждал загрузки внутри запроса."""

    def __init__(self, model_size: str = "small", device: str = "auto", compute_type: str = "int8"):
        self.name = f"faster-whisper/{model_size}"
        self._model_size, self._device, self._compute_type = model_size, device, compute_type
        self._model = None
        self.vocabulary = None  # Vocabulary: подсказка модели (тема приёма и термины клиники)
        self._lock = threading.Lock()
        self.state = "idle"  # idle | loading | ready | error
        self.error: str | None = None

    def _load(self):
        with self._lock:
            if self._model is not None:
                return self._model
            self.state, self.error = "loading", None
            try:
                from faster_whisper import WhisperModel

                self._model = WhisperModel(self._model_size, device=self._device, compute_type=self._compute_type)
                self.state = "ready"
                return self._model
            except Exception as exc:  # noqa: BLE001 - нет сети для скачивания, нет места, битый кэш
                log.exception("whisper model failed to load")
                self.state, self.error = "error", f"{type(exc).__name__}: {exc}"[:300]
                raise TranscriberUnavailable(f"модель распознавания речи не загрузилась ({self.error})") from exc

    # примерный размер модели на диске (МБ) — для прогресса первой загрузки
    SIZES_MB = {"tiny": 75, "base": 145, "small": 485, "medium": 1530, "large-v3-turbo": 1620, "turbo": 1620, "large-v3": 3090}

    def progress(self) -> dict | None:
        """Сколько модели уже скачано (по файлам в кэше HF), пока она загружается; иначе None."""
        if self.state != "loading":
            return None
        import os

        hub = Path(os.environ.get("HF_HOME", Path.home() / ".cache" / "huggingface")) / "hub"
        key = self._model_size.lower()
        done = 0
        if hub.exists():
            for repo in hub.iterdir():
                if repo.name.startswith("models--") and "whisper" in repo.name.lower() and key in repo.name.lower():
                    done += sum(f.stat().st_size for f in repo.rglob("*") if f.is_file() and not f.is_symlink())
        total = self.SIZES_MB.get(self._model_size)
        return {"downloadedMb": round(done / 1_048_576), "totalMb": total}

    def warm_up(self) -> None:
        """Загрузить модель в фоне, не блокируя старт сервиса."""
        def run():
            try:
                self._load()
            except TranscriberUnavailable:
                pass

        threading.Thread(target=run, name="whisper-warm-up", daemon=True).start()

    def transcribe(self, audio: Path, language: str) -> list[Segment]:
        if self.state == "loading" and self._model is None:
            raise TranscriberUnavailable("модель распознавания речи ещё загружается (первый запуск, несколько минут) — "
                                         "попробуйте чуть позже или вставьте текст приёма")
        model = self._model or self._load()
        # сначала декодируем сами (PyAV, 16 кГц моно): запись браузера (webm/opus) и файлы читаются одинаково,
        # а ошибка формата отделяется от ошибки распознавания
        samples = decode_audio(audio)
        if len(samples) < 16000 // 2:
            raise ValueError("запись короче секунды")
        lang = "kk" if language == "kk" else "ru"
        try:
            result = self._run(model, samples, lang, vad=True)
        except Exception:  # noqa: BLE001 - VAD (onnxruntime) недоступен или упал: распознаём без него
            log.exception("transcription with VAD failed, retrying without VAD")
            result = []
        # VAD может отрезать тихую речь с микрофона ноутбука целиком — тогда пробуем без него
        return result or self._run(model, samples, lang, vad=False)

    def _run(self, model, samples, lang: str, vad: bool) -> list[Segment]:
        from .vocabulary import BASE_PROMPTS

        prompt = self.vocabulary.prompt(lang) if self.vocabulary is not None else BASE_PROMPTS.get(lang)
        segments, _ = model.transcribe(samples, language=lang, vad_filter=vad, beam_size=5,
                                       initial_prompt=prompt, condition_on_previous_text=False,
                                       vad_parameters={"min_silence_duration_ms": 700, "speech_pad_ms": 400})
        return [Segment(float(s.start), float(s.end), s.text.strip()) for s in segments if s.text.strip()]


class FakeTranscriber:
    """Returns a fixed transcript; used in tests and when faster-whisper is not installed."""

    name = "fake"
    state = "ready"
    error = None

    def __init__(self, text: str = "Пациент жалуется на боль в груди при нагрузке. Давление 150 на 95. Диагноз гипертоническая болезнь. Назначаю амлодипин 5 мг утром."):
        self._text = text

    def transcribe(self, audio: Path, language: str) -> list[Segment]:
        sentences = [s.strip() for s in self._text.replace("!", ".").split(".") if s.strip()]
        return [Segment(float(i * 4), float(i * 4 + 4), s + ".") for i, s in enumerate(sentences)]


def default_transcriber() -> Transcriber:
    try:
        import faster_whisper  # noqa: F401
    except ImportError:
        return FakeTranscriber()
    # в контейнере GPU нет: CPU и int8 явно, без автоопределения устройства; размер модели — DARUMEN_WHISPER_MODEL
    import os

    return WhisperTranscriber(os.environ.get("DARUMEN_WHISPER_MODEL", "large-v3-turbo"), os.environ.get("DARUMEN_WHISPER_DEVICE", "cpu"))
