"""File fingerprint: format, encoding, delimiter and header of an incoming file.

Only the first 64 KiB are read, so fingerprinting a 250 MB part costs nothing.
"""
from __future__ import annotations

import csv
import io
from dataclasses import dataclass
from pathlib import Path

SAMPLE_BYTES = 64 * 1024
DELIMITERS = (",", ";", "\t", "|")
BOM = b"\xef\xbb\xbf"
FORMATS = {".csv": "csv", ".txt": "csv", ".tsv": "csv", ".parquet": "parquet", ".xlsx": "xlsx", ".json": "json"}


@dataclass(frozen=True)
class Fingerprint:
    path: Path
    format: str
    encoding: str
    has_bom: bool
    delimiter: str
    quote: str
    header: tuple[str, ...]
    size_bytes: int

    @property
    def signature(self) -> tuple[str, ...]:
        return tuple(c.strip().lower() for c in self.header)


def _decode(sample: bytes) -> tuple[str, str, bool]:
    has_bom = sample.startswith(BOM)
    if has_bom:
        sample = sample[len(BOM):]
    cut = sample.rfind(b"\n")
    if cut > 0:
        sample = sample[:cut]
    try:
        return sample.decode("utf-8"), "utf-8", has_bom
    except UnicodeDecodeError:
        return sample.decode("cp1251", errors="replace"), "cp1251", has_bom


def _detect_delimiter(first_line: str) -> str:
    counts = {d: first_line.count(d) for d in DELIMITERS}
    best = max(counts, key=counts.get)
    return best if counts[best] > 0 else ","


def fingerprint(path: Path) -> Fingerprint:
    path = Path(path)
    fmt = FORMATS.get(path.suffix.lower(), "unknown")
    size = path.stat().st_size
    if fmt != "csv":
        return Fingerprint(path, fmt, "binary", False, "", "", (), size)
    with path.open("rb") as fh:
        sample = fh.read(SAMPLE_BYTES)
    text, encoding, has_bom = _decode(sample)
    first_line = text.split("\n", 1)[0].rstrip("\r")
    delimiter = _detect_delimiter(first_line)
    header = next(csv.reader(io.StringIO(first_line), delimiter=delimiter, quotechar='"'), [])
    return Fingerprint(path, fmt, encoding, has_bom, delimiter, '"', tuple(h.strip() for h in header), size)
