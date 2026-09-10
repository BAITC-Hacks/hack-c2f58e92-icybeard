"""Dataset contracts: load YAML contracts and match a CSV header signature to one of them.

A contract describes one dataset (see docs/data-intake.md §3). Matching is the first step of
blind intake: exact signature match first, then a fuzzy match on the share of common columns.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

import yaml

EXACT = "exact"
FUZZY = "fuzzy"
FUZZY_THRESHOLD = 0.8
BOM = "﻿"


@dataclass(frozen=True)
class Contract:
    dataset: str
    title: str
    signature: tuple[str, ...]
    columns: dict[str, dict]
    keys: tuple[str, ...]
    format: dict = field(default_factory=dict)
    rules: tuple[dict, ...] = ()
    partition: tuple[str, ...] = ()
    privacy: dict = field(default_factory=dict)
    streams: tuple[dict, ...] = ()
    source: dict = field(default_factory=dict)

    @classmethod
    def from_yaml(cls, path: Path) -> Contract:
        raw = yaml.safe_load(path.read_text(encoding="utf-8"))
        return cls(
            dataset=raw["dataset"],
            title=raw.get("title", raw["dataset"]),
            signature=tuple(raw["signature"]),
            columns=raw.get("columns", {}),
            keys=tuple(raw.get("keys", ())),
            format=raw.get("format", {}),
            rules=tuple(raw.get("rules", ())),
            partition=tuple(raw.get("partition", ())),
            privacy=raw.get("privacy", {}),
            streams=tuple(raw.get("streams", ())),
            source=raw.get("source", {}),
        )


@dataclass(frozen=True)
class Match:
    contract: Contract
    kind: str
    score: float


def normalize_header(columns: list[str]) -> tuple[str, ...]:
    return tuple(c.strip().lstrip(BOM).lower() for c in columns)


def load_contracts(directory: Path) -> list[Contract]:
    return [Contract.from_yaml(p) for p in sorted(directory.glob("*.yaml"))]


def match_signature(header: list[str], contracts: list[Contract]) -> Match | None:
    """Return the best contract for a header, or None when the schema is unknown."""
    wanted = normalize_header(header)
    best: Match | None = None
    for contract in contracts:
        expected = normalize_header(list(contract.signature))
        if wanted == expected:
            return Match(contract, EXACT, 1.0)
        common = len(set(wanted) & set(expected))
        score = common / max(len(set(expected)), 1)
        if score >= FUZZY_THRESHOLD and (best is None or score > best.score):
            best = Match(contract, FUZZY, score)
    return best
