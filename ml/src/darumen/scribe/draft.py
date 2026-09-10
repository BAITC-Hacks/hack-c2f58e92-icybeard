"""Drafters turn a transcript into sections and a patient leaflet. RuleDrafter works offline; AnthropicDrafter
uses Claude when ANTHROPIC_API_KEY is set and falls back to the rules on any failure."""
from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass, field
from typing import Protocol

from .transcribe import Segment

SECTIONS = ["Жалобы", "Анамнез", "Осмотр", "Диагноз", "Назначения", "Прочее"]
KEYWORDS = {
    "Жалобы": ["жалоб", "беспоко", "болит", "боль", "тошнот", "слабост", "кашел", "температур"],
    "Анамнез": ["анамнез", "болеет", "принимает", "аллерг", "перенес", "хроничес", "наследств", "курит"],
    "Осмотр": ["осмотр", "давление", "пульс", "сатурац", "аускульт", "пальпац", "на осмотре", "температура тела"],
    "Диагноз": ["диагноз", "мкб", "предварительн", "ставим", "подтвержд"],
    "Назначения": ["назнач", "принимать", "таблет", "мг", "рецепт", "капли", "контроль", "явка", "направля", "анализ"],
}


@dataclass
class Section:
    name: str
    text: str
    spans: list[dict] = field(default_factory=list)


@dataclass
class Draft:
    sections: list[Section]
    leaflet: str
    model: str


class Drafter(Protocol):
    def draft(self, segments: list[Segment], language: str) -> Draft: ...


def _classify(sentence: str) -> str:
    lowered = sentence.lower()
    for name, words in KEYWORDS.items():
        if any(w in lowered for w in words):
            return name
    return "Прочее"


class RuleDrafter:
    """Keyword routing of sentences into sections; the leaflet repeats the prescriptions in plain words."""

    name = "rules@1.0.0"

    def draft(self, segments: list[Segment], language: str) -> Draft:
        buckets: dict[str, Section] = {name: Section(name, "") for name in SECTIONS}
        for segment in segments:
            for sentence in re.split(r"(?<=[.!?])\s+", segment.text.strip()):
                if not sentence:
                    continue
                section = buckets[_classify(sentence)]
                section.text = (section.text + " " + sentence).strip()
                section.spans.append({"t0": segment.t0, "t1": segment.t1})
        sections = [s for s in buckets.values() if s.text]
        prescriptions = buckets["Назначения"].text or "Назначения уточняйте у врача."
        leaflet = ("Что делать после приёма:\n- " + prescriptions.replace(". ", ".\n- ").rstrip("-").strip()
                   + "\n- При ухудшении самочувствия обратитесь к врачу или вызовите скорую помощь.")
        if language == "kk":
            leaflet += "\n(қазақ тіліндегі нұсқа дәрігердің растауынан кейін)"
        return Draft(sections, leaflet, self.name)


class AnthropicDrafter:
    """Claude structures the transcript; output is validated JSON, otherwise the rules take over."""

    PROMPT = (
        "Ты помощник врача. Из стенограммы приёма составь черновик записи по разделам "
        f"{', '.join(SECTIONS[:-1])} и короткую памятку пациенту простым языком. Ничего не выдумывай: "
        "если раздела нет в стенограмме, оставь пустую строку. Ответь только JSON вида "
        '{"sections": {"Жалобы": "...", "Анамнез": "...", "Осмотр": "...", "Диагноз": "...", "Назначения": "..."}, "leaflet": "..."}.'
    )

    def __init__(self, model: str | None = None, fallback: Drafter | None = None):
        self._model = model or os.environ.get("DARUMEN_SCRIBE_MODEL", "claude-sonnet-5")
        self._fallback = fallback or RuleDrafter()
        self.name = f"anthropic/{self._model}"

    def available(self) -> bool:
        return bool(os.environ.get("ANTHROPIC_API_KEY"))

    def draft(self, segments: list[Segment], language: str) -> Draft:
        if not self.available():
            return self._fallback.draft(segments, language)
        try:
            import anthropic

            transcript = "\n".join(f"[{s.t0:.0f}-{s.t1:.0f}] {s.text}" for s in segments)
            message = anthropic.Anthropic().messages.create(
                model=self._model, max_tokens=1200, system=self.PROMPT,
                messages=[{"role": "user", "content": f"Язык памятки: {language}. Стенограмма:\n{transcript}"}])
            payload = json.loads(re.search(r"\{.*\}", message.content[0].text, re.DOTALL).group(0))
            sections = [Section(name, str(payload["sections"].get(name, "")).strip()) for name in SECTIONS[:-1]]
            return Draft([s for s in sections if s.text], str(payload["leaflet"]).strip(), self.name)
        except Exception:  # noqa: BLE001 - демо: любая ошибка модели означает черновик по правилам
            return self._fallback.draft(segments, language)


def default_drafter() -> Drafter:
    return AnthropicDrafter()
