"""4.6: enrich a heuristic contract draft (`pipeline.draft_contract`) with an LLM's read of column
semantics — a better title and, for columns the heuristics left as plain `string`/`decimal` with no
`semantic`, a best-guess tag and a short human description. Same OpenAI-compatible provider pattern as
`scribe.draft.LlmDrafter` (env-driven, no key configured → skipped entirely) and the same rule: any
failure at all — no key, network, bad JSON — falls back to the untouched heuristic draft, never raises."""
from __future__ import annotations

import json
import os
import re
from typing import ClassVar

ALLOWED_SEMANTICS = ("icd10", "region_name", "mo_name")
PROMPT = (
    "Ты помогаешь стюарду данных описать неизвестный CSV перед подключением к системе здравоохранения "
    "Казахстана. Тебе дан список колонок с примерами значений и типом, который угадала эвристика. "
    "Придумай короткое человеческое название набора данных (title) и, только для колонок, где это "
    "уместно, предложи semantic — один из: icd10, region_name, mo_name (код диагноза МКБ-10, название "
    "региона, название медицинской организации). Не выдумывай semantic для колонок, которые явно не про "
    "это. Ответь только JSON вида {\"title\": \"...\", \"columns\": {\"<имя колонки>\": \"icd10\", ...}} "
    "— в columns перечисли только те колонки, для которых предлагаешь semantic."
)


class LlmContractDrafter:
    DEFAULTS: ClassVar[dict[str, tuple[str, str, str]]] = {
        "ollama": ("http://localhost:11434/v1", "darumen-qwen3.8:27b", "OLLAMA_API_KEY"),
        "deepseek": ("https://api.deepseek.com", "deepseek-chat", "DEEPSEEK_API_KEY"),
        "openai": ("https://api.openai.com/v1", "gpt-4.1-mini", "OPENAI_API_KEY"),
    }
    THINK = re.compile(r"<think>.*?</think>", re.DOTALL)

    def __init__(self, provider: str | None = None, model: str | None = None, base_url: str | None = None, api_key: str | None = None):
        self._provider = provider or os.environ.get("DARUMEN_LLM_PROVIDER", "ollama")
        default_url, default_model, key_var = self.DEFAULTS.get(self._provider, self.DEFAULTS["ollama"])
        self._base_url = base_url or os.environ.get("DARUMEN_LLM_BASE_URL", default_url)
        self._model = model or os.environ.get("DARUMEN_INTAKE_MODEL", default_model)
        self._api_key = api_key or os.environ.get(key_var) or ("ollama" if self._provider == "ollama" else None)
        self.name = f"{self._provider}/{self._model}"

    def available(self) -> bool:
        return bool(self._api_key)

    def enrich(self, draft: dict, samples: dict[str, list[str]]) -> dict:
        """Returns a copy of `draft` with `title` and column `semantic` improved where the model is
        confident; on any failure (no key, network, bad JSON, unknown column names) returns `draft` unchanged."""
        if not self.available():
            return draft
        try:
            from openai import OpenAI

            columns_desc = "\n".join(
                f"- {name} (тип: {spec.get('type', 'string')}): примеры {samples.get(name, [])[:5]}"
                for name, spec in draft["columns"].items()
            )
            client = OpenAI(api_key=self._api_key, base_url=self._base_url, timeout=float(os.environ.get("DARUMEN_LLM_TIMEOUT", "60")), max_retries=0)
            system = PROMPT + ("\n/no_think" if self._provider == "ollama" else "")
            completion = client.chat.completions.create(
                model=self._model, temperature=0, max_tokens=800, response_format={"type": "json_object"},
                messages=[{"role": "system", "content": system},
                          {"role": "user", "content": f"Файл: {draft.get('title', draft['dataset'])}\nКолонки:\n{columns_desc}"}])
            content = self.THINK.sub("", completion.choices[0].message.content or "")
            payload = json.loads(re.search(r"\{.*\}", content, re.DOTALL).group(0))
            enriched = dict(draft)
            title = str(payload.get("title") or "").strip()
            if title:
                enriched["title"] = title
            columns = dict(draft["columns"])
            for name, semantic in (payload.get("columns") or {}).items():
                if name in columns and semantic in ALLOWED_SEMANTICS:
                    columns[name] = {**columns[name], "semantic": semantic}
            enriched["columns"] = columns
            enriched["draft_model"] = self.name
            return enriched
        except Exception:  # noqa: BLE001 - черновик и так уже готов по правилам, LLM только его улучшает
            return draft


def default_contract_drafter() -> LlmContractDrafter:
    return LlmContractDrafter()
