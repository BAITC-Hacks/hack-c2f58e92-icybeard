"""Transcribers: faster-whisper when installed, a fake for tests and machines without the model."""
from __future__ import annotations

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


class WhisperTranscriber:
    """faster-whisper (CTranslate2); the model is downloaded on first use."""

    def __init__(self, model_size: str = "small", device: str = "auto", compute_type: str = "int8"):
        self.name = f"faster-whisper/{model_size}"
        self._model_size, self._device, self._compute_type = model_size, device, compute_type
        self._model = None

    def transcribe(self, audio: Path, language: str) -> list[Segment]:
        if self._model is None:
            from faster_whisper import WhisperModel

            self._model = WhisperModel(self._model_size, device=self._device, compute_type=self._compute_type)
        segments, _ = self._model.transcribe(str(audio), language="kk" if language == "kk" else "ru", vad_filter=True)
        return [Segment(float(s.start), float(s.end), s.text.strip()) for s in segments if s.text.strip()]


class FakeTranscriber:
    """Returns a fixed transcript; used in tests and when faster-whisper is not installed."""

    name = "fake"

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
    return WhisperTranscriber()
