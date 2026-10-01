"""Drafters turn a transcript into sections and a patient leaflet. RuleDrafter works offline; LlmDrafter
uses DeepSeek (or another OpenAI-compatible API) when its key is set and falls back to the rules on any failure."""
from __future__ import annotations

import difflib
import json
import os
import re
from dataclasses import dataclass, field
from typing import ClassVar, Protocol

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


class CorrectionUnavailable(RuntimeError):
    """Исправить стенограмму через ИИ сейчас нельзя: модель не настроена или не ответила."""


def plausible_fix(old: str, new: str) -> bool:
    """Правка похожа на исправление терминов, а не на пересказ: длина почти та же, текст в основном совпадает."""
    if not new or not (0.6 <= len(new) / max(len(old), 1) <= 1.6):
        return False
    return difflib.SequenceMatcher(None, old.lower(), new.lower()).ratio() >= 0.55


class LlmDrafter:
    """A chat model structures the transcript through an OpenAI-compatible API (DeepSeek by default);
    output is validated JSON, otherwise the rules take over. Nothing is sent without an API key."""

    PROMPT = (
        "Ты помощник врача. Стенограмма дана построчно, каждая строка начинается с индекса фрагмента в "
        "квадратных скобках, например [0], [1]. Из стенограммы составь черновик записи по разделам "
        f"{', '.join(SECTIONS[:-1])} и короткую памятку пациенту простым языком. Ничего не выдумывай: "
        "если раздела нет в стенограмме, оставь пустую строку и пустой список segments. Для каждого раздела "
        "укажи индексы фрагментов стенограммы (segments), из которых взят текст раздела. Ответь только JSON вида "
        '{"sections": {"Жалобы": {"text": "...", "segments": [0]}, "Анамнез": {"text": "...", "segments": []}, '
        '"Осмотр": {"text": "...", "segments": []}, "Диагноз": {"text": "...", "segments": []}, '
        '"Назначения": {"text": "...", "segments": []}}, "leaflet": "..."}.'
    )
    DEFAULTS: ClassVar[dict[str, tuple[str, str, str]]] = {
        "ollama": ("http://localhost:11434/v1", "darumen-qwen3.8:27b", "OLLAMA_API_KEY"),
        "deepseek": ("https://api.deepseek.com", "deepseek-chat", "DEEPSEEK_API_KEY"),
        "openai": ("https://api.openai.com/v1", "gpt-4.1-mini", "OPENAI_API_KEY"),
    }
    THINK = re.compile(r"<think>.*?</think>", re.DOTALL)

    def __init__(self, provider: str | None = None, model: str | None = None, base_url: str | None = None,
                 api_key: str | None = None, fallback: Drafter | None = None):
        self._provider = provider or os.environ.get("DARUMEN_LLM_PROVIDER", "ollama")
        default_url, default_model, key_var = self.DEFAULTS.get(self._provider, self.DEFAULTS["ollama"])
        self._base_url = base_url or os.environ.get("DARUMEN_LLM_BASE_URL", default_url)
        self._model = model or os.environ.get("DARUMEN_SCRIBE_MODEL", default_model)
        # Ollama ключ не проверяет: локальная модель доступна без переменной окружения
        self._api_key = api_key or os.environ.get(key_var) or ("ollama" if self._provider == "ollama" else None)
        self._fallback = fallback or RuleDrafter()
        self.name = f"{self._provider}/{self._model}"

    def available(self) -> bool:
        return bool(self._api_key)

    @staticmethod
    def _section(name: str, raw: object, segments: list[Segment]) -> Section:
        """Строка (старый/сломанный формат ответа модели) -> раздел без ссылок; словарь {text, segments} ->
        раздел со spans, индексы вне диапазона и не-числа отбрасываются, а не роняют весь черновик."""
        if isinstance(raw, dict):
            text = str(raw.get("text", "")).strip()
            spans = []
            for idx in raw.get("segments") or []:
                if isinstance(idx, bool) or not isinstance(idx, int) or not (0 <= idx < len(segments)):
                    continue
                seg = segments[idx]
                spans.append({"t0": seg.t0, "t1": seg.t1})
            return Section(name, text, spans)
        return Section(name, str(raw).strip())

    def _chat(self, system: str, user: str, max_tokens: int) -> dict:
        """Один запрос к модели с ответом-JSON; исключение — если модель недоступна или ответ не JSON."""
        from openai import OpenAI

        client = OpenAI(api_key=self._api_key, base_url=self._base_url, timeout=float(os.environ.get("DARUMEN_LLM_TIMEOUT", "180")), max_retries=0)
        effort = os.environ.get("DARUMEN_LLM_REASONING", "none" if self._provider == "ollama" else "")
        completion = client.chat.completions.create(
            model=self._model, temperature=0, max_tokens=max_tokens, response_format={"type": "json_object"},
            messages=[{"role": "system", "content": system + ("\n/no_think" if self._provider == "ollama" else "")},
                      {"role": "user", "content": user}],
            **({"extra_body": {"reasoning_effort": effort}} if effort else {}))
        content = self.THINK.sub("", completion.choices[0].message.content or "")
        return json.loads(re.search(r"\{.*\}", content, re.DOTALL).group(0))

    CORRECT_PROMPT = (
        "Ты проверяешь стенограмму приёма врача, распознанную из речи. Исправь только слова, которые распознавание "
        "исказило: названия лекарств, болезней, анализов, анатомии, медицинские термины — и явные опечатки рядом с ними. "
        "Если подходит, бери написание из списка терминов. Не меняй смысл, не пересказывай, не добавляй и не удаляй "
        "фразы, не трогай фрагменты без ошибок. Стенограмма дана построчно с индексом фрагмента в квадратных скобках. "
        'Ответь только JSON вида {"segments": [{"i": 0, "text": "исправленный фрагмент целиком"}]} — только '
        'изменённые фрагменты; если ошибок нет, {"segments": []}.'
    )

    def correct(self, texts: list[str], terms: list[str], language: str) -> dict[int, str]:
        """Исправленные фрагменты {индекс: текст}; только правдоподобные правки (см. plausible_fix)."""
        if not self.available():
            raise CorrectionUnavailable("исправление через ИИ не настроено: нет доступа к языковой модели")
        transcript = "\n".join(f"[{i}] {t}" for i, t in enumerate(texts))
        user = (f"Язык: {language}.\nТермины: {', '.join(terms) if terms else '—'}\nСтенограмма:\n{transcript}")
        try:
            payload = self._chat(self.CORRECT_PROMPT, user, max_tokens=200 + 2 * sum(len(t) for t in texts))
        except Exception as exc:  # модель не запущена, таймаут, не JSON
            raise CorrectionUnavailable(f"языковая модель не ответила ({type(exc).__name__}) — исправьте фразы вручную") from exc
        fixes: dict[int, str] = {}
        for item in payload.get("segments") or []:
            if not isinstance(item, dict):
                continue
            i, text = item.get("i"), str(item.get("text", "")).strip()
            if isinstance(i, int) and not isinstance(i, bool) and 0 <= i < len(texts) and text != texts[i] and plausible_fix(texts[i], text):
                fixes[i] = text
        return fixes

    def draft(self, segments: list[Segment], language: str) -> Draft:
        if not self.available():
            return self._fallback.draft(segments, language)
        try:
            transcript = "\n".join(f"[{i}] [{s.t0:.0f}-{s.t1:.0f}] {s.text}" for i, s in enumerate(segments))
            payload = self._chat(self.PROMPT, f"Язык памятки: {language}. Стенограмма:\n{transcript}", max_tokens=1200)
            sections = [self._section(name, payload["sections"].get(name, ""), segments) for name in SECTIONS[:-1]]
            return Draft([s for s in sections if s.text], str(payload["leaflet"]).strip(), self.name)
        except Exception:  # noqa: BLE001 - демо: любая ошибка модели означает черновик по правилам
            return self._fallback.draft(segments, language)


def default_drafter() -> Drafter:
    return LlmDrafter()
