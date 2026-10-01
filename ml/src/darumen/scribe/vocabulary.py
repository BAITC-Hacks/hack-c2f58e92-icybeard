"""Словарь медицинских терминов скрайба: встроенные списки (terms/ru.txt, terms/kk.txt) и термины клиники,
которые врачи добавляют сами (хранятся в каталоге сервиса). Используется в двух местах: подсказка модели
распознавания речи (initial_prompt — ограничена по длине) и подбор кандидатов для исправления стенограммы."""
from __future__ import annotations

import difflib
import itertools
import json
import re
import threading
from pathlib import Path

TERMS_DIR = Path(__file__).with_name("terms")
MAX_CUSTOM = 500
MAX_TERM = 80
# Whisper берёт в подсказку ~224 токена: тема + термины клиники, без длинного списка (длинный список модель
# начинает «дописывать» на паузах)
PROMPT_CHARS = 600
WORD = re.compile(r"[\w-]+", re.UNICODE)

BASE_PROMPTS = {
    "ru": "Приём врача и пациента в поликлинике. Стенограмма разговора. Жалобы, анамнез, давление, пульс, температура, "
          "осмотр, диагноз, назначения, анализы, направление, гипертония, диабет, амлодипин, метформин.",
    "kk": "Емханадағы дәрігер мен пациенттің қабылдауы. Әңгіменің стенограммасы. Шағымдар, анамнез, қан қысымы, "
          "тамыр соғысы, температура, тексеру, диагноз, тағайындау, талдаулар, жолдама.",
}


def _read_groups(path: Path) -> list[tuple[str, list[str]]]:
    """Файл терминов: строка «# Название» начинает группу, остальные строки — термины."""
    groups: list[tuple[str, list[str]]] = []
    if not path.exists():
        return groups
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line.startswith("#"):
            groups.append((line.lstrip("# ").split(" (")[0].rstrip("."), []))
        elif line:
            if not groups:
                groups.append(("", []))
            groups[-1][1].append(line)
    return [(name, terms) for name, terms in groups if terms]


def _read_terms(path: Path) -> list[str]:
    return [t for _, terms in _read_groups(path) for t in terms]


def _common_prefix(a: str, b: str) -> int:
    n = 0
    for x, y in zip(a, b):
        if x != y:
            break
        n += 1
    return n


def clean_terms(words: list[str], limit: int | None = MAX_CUSTOM) -> list[str]:
    """Без пустых строк, повторов (без учёта регистра) и слишком длинных строк; порядок сохраняется."""
    seen, result = set(), []
    for w in words:
        term = " ".join(str(w).split())[:MAX_TERM]
        if term and term.lower() not in seen:
            seen.add(term.lower())
            result.append(term)
    return result[:limit] if limit else result


class Vocabulary:
    def __init__(self, root: Path | None = None):
        self._file = root / "vocabulary.json" if root else None
        self._lock = threading.Lock()
        self._builtin = {"ru": _read_terms(TERMS_DIR / "ru.txt"), "kk": _read_terms(TERMS_DIR / "kk.txt")}
        self._custom: list[str] = []
        if self._file and self._file.exists():
            try:
                self._custom = clean_terms(json.loads(self._file.read_text(encoding="utf-8")).get("words", []))
            except (ValueError, OSError):
                self._custom = []

    @property
    def custom(self) -> list[str]:
        return list(self._custom)

    def builtin_groups(self) -> list[dict]:
        return [{"name": name, "language": lang, "terms": terms}
                for lang in ("ru", "kk") for name, terms in _read_groups(TERMS_DIR / f"{lang}.txt")]

    def fix_by_dictionary(self, texts: list[str], language: str) -> dict[int, str]:
        """Исправление без языковой модели: слово, очень похожее на термин словаря (амоксицелин -> амоксициллин),
        заменяется термином. Слово, которое отличается от термина только окончанием (бронхита, гипертонической),
        — это падеж, а не ошибка, и не трогается."""
        vocab = {w for t in self.terms(language) for w in WORD.findall(t.lower()) if len(w) >= 6}
        fixes: dict[int, str] = {}
        for i, text in enumerate(texts):
            def replace(m: re.Match) -> str:
                word = m.group(0)
                low = word.lower()
                if len(low) < 6 or low in vocab:
                    return word
                match = difflib.get_close_matches(low, vocab, n=1, cutoff=0.82)
                if not match or _common_prefix(low, match[0]) >= min(len(low), len(match[0])) - 3:
                    return word
                fixed = match[0]
                return fixed[0].upper() + fixed[1:] if word[0].isupper() else fixed

            fixed_text = WORD.sub(replace, text)
            if fixed_text != text:
                fixes[i] = fixed_text
        return fixes

    def builtin_count(self) -> int:
        return len(self._builtin["ru"]) + len(self._builtin["kk"])

    def set_custom(self, words: list[str]) -> list[str]:
        with self._lock:
            self._custom = clean_terms(words)
            if self._file:
                self._file.parent.mkdir(parents=True, exist_ok=True)
                tmp = self._file.with_suffix(".tmp")
                tmp.write_text(json.dumps({"words": self._custom}, ensure_ascii=False, indent=1), encoding="utf-8")
                tmp.replace(self._file)
        return self.custom

    def terms(self, language: str) -> list[str]:
        """Все термины для языка: свои сначала; для казахского — ещё и русские (названия лекарств те же)."""
        own = self._builtin["kk"] + self._builtin["ru"] if language == "kk" else self._builtin["ru"]
        return clean_terms(self._custom + own, limit=None)

    def prompt(self, language: str) -> str:
        base = BASE_PROMPTS.get(language, BASE_PROMPTS["ru"])
        extra = ""
        for term in self._custom:
            if len(base) + len(extra) + len(term) + 2 > PROMPT_CHARS:
                break
            extra += (", " if extra else " ") + term
        return base + (extra + "." if extra else "")

    def candidates(self, texts: list[str], language: str, limit: int = 80) -> list[str]:
        """Термины словаря, похожие на слова стенограммы (по написанию): их модель исправления может подставить."""
        terms = self.terms(language)
        lowered = {t.lower(): t for t in terms}
        # для многословных терминов сравниваем и отдельные слова: «гипертоническая болезнь» найдётся по «гипертонической»
        by_word: dict[str, set[str]] = {}
        for t in terms:
            for w in WORD.findall(t.lower()):
                if len(w) >= 4:
                    by_word.setdefault(w, set()).add(t)
        found: list[str] = []
        words = [w for text in texts for w in WORD.findall(text.lower()) if len(w) >= 4]
        pairs = [f"{a} {b}" for a, b in itertools.pairwise(words)]
        for w in words + pairs:
            for match in difflib.get_close_matches(w, lowered.keys(), n=2, cutoff=0.6):
                found.append(lowered[match])
            for match in difflib.get_close_matches(w, by_word.keys(), n=2, cutoff=0.7):
                if len(by_word[match]) <= 4:  # частые слова («болезнь») не тянут за собой полсловаря
                    found.extend(sorted(by_word[match]))
            if len(set(found)) >= limit:
                break
        return clean_terms(found, limit=limit)
