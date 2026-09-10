"""Normalizers used while building silver tables, registered as DuckDB scalar functions.

Each function is pure Python so it can be unit-tested, and is exposed to SQL through
`register_udfs` as a vectorised (Arrow) function.
"""
from __future__ import annotations

import contextlib
import re
from collections.abc import Callable

import duckdb

from .regions import to_kato

QUOTED = re.compile(r'["«“]([^"»”]+)["»”]')
ORG_FORMS = [
    "государственное коммунальное предприятие на праве хозяйственного ведения",
    "коммунальное государственное предприятие на праве хозяйственного ведения",
    "республиканское государственное предприятие на праве хозяйственного ведения",
    "коммунальное государственное предприятие",
    "государственное коммунальное предприятие",
    "республиканское государственное предприятие",
    "товарищество с ограниченной ответственностью",
    "некоммерческое акционерное общество",
    "акционерное общество",
    "негосударственное учреждение",
    "государственное учреждение",
    "на праве хозяйственного ведения",
    "кгп на пхв", "гкп на пхв", "ргп на пхв", "на пхв",
    "кгп", "гкп", "ргп", "тоо", "нао", "ао", "ну", "гу", "учреждение",
]
_ORG_FORM_RE = re.compile(r"\b(" + "|".join(re.escape(f) for f in ORG_FORMS) + r")\b")
_PUNCT = re.compile(r"[^\w\s-]", re.UNICODE)
_SPACES = re.compile(r"\s+")

CYRILLIC_TO_LATIN = str.maketrans(
    {"А": "A", "В": "B", "С": "C", "Е": "E", "Н": "H", "К": "K", "М": "M", "О": "O", "Р": "P", "Т": "T",
     "Х": "X", "І": "I", "Ј": "J", "Ү": "Y", "У": "Y"}
)
ICD10 = re.compile(r"^[A-Z][0-9]{2}(\.[0-9A-Z]{1,4})?$")


def mo_name_key(name: str | None) -> str | None:
    """Stable key for a medical organisation name: the quoted proper name if present, else the
    name without legal form, lower-cased, punctuation stripped, spaces collapsed."""
    if name is None:
        return None
    text = str(name).strip()
    if not text:
        return None
    quoted = QUOTED.search(text)
    core = quoted.group(1) if quoted else text
    core = core.lower()
    if not quoted:
        core = _ORG_FORM_RE.sub(" ", core)
    core = _PUNCT.sub(" ", core)
    core = _SPACES.sub(" ", core).strip()
    return core or None


def icd10_canon(code: str | None) -> str | None:
    """Canonical ICD-10 code (`J03.9`) or None when the value is not a code."""
    if code is None:
        return None
    text = str(code).strip().upper().replace(",", ".").replace(" ", "")
    text = text.translate(CYRILLIC_TO_LATIN)
    return text if ICD10.match(text) else None


def _vectorized(fn: Callable[[str | None], str | None]) -> Callable:
    def wrapper(values):  # pyarrow array in, pyarrow array out
        import pyarrow as pa

        if isinstance(values, pa.ChunkedArray):
            values = values.combine_chunks()
        return pa.array([fn(v) for v in values.to_pylist()], type=pa.string())

    return wrapper


UDFS: dict[str, Callable[[str | None], str | None]] = {
    "to_kato": to_kato,
    "mo_name_key": mo_name_key,
    "icd10_canon": icd10_canon,
}


def register_udfs(con) -> None:
    """Register the normalizers on a DuckDB connection (idempotent)."""
    try:
        from duckdb.sqltypes import VARCHAR
    except ImportError:  # older DuckDB
        from duckdb.typing import VARCHAR
    for name, fn in UDFS.items():
        with contextlib.suppress(duckdb.Error):  # not registered yet on a fresh connection
            con.remove_function(name)
        con.create_function(name, _vectorized(fn), [VARCHAR], VARCHAR, type="arrow", null_handling="special")
