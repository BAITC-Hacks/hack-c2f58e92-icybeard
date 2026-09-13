"""Оценки охвата вакцинацией ВОЗ/ЮНИСЕФ (WUENIC) по Казахстану из официального WHO GHO OData API
→ refdata/external_vaccination.yaml.

Запуск: ml/.venv/bin/python scripts/wuenic_fetch.py
Источник: https://ghoapi.azureedge.net/api/{indicator}?$filter=SpatialDim eq 'KAZ'
Индикаторы помечены (WUENIC) в самом GHO. Оценки WUENIC для Казахстана заметно ниже
административной отчётности (пересмотр после обследования MICS) — поэтому в продукте они
показываются только как внешний ориентир с источником, не как факт.
"""
from __future__ import annotations

import json
import urllib.request
from datetime import date
from pathlib import Path

import yaml

INDICATORS = {
    "VACCINECOVERAGE_DTP1": ("DTP1", "АКДС, первая доза"),
    "WHS4_100": ("DTP3", "АКДС, третья доза"),
    "WHS8_110": ("MCV1", "корь, первая доза"),
    "MCV2": ("MCV2", "корь, вторая доза"),
    "WHS4_117": ("HepB3", "гепатит B, третья доза"),
    "WHS4_543": ("BCG", "БЦЖ"),
    "WHS4_129": ("Hib3", "Hib, третья доза"),
    "PCV3": ("PCV3", "пневмококк, завершающая доза"),
}
YEAR_FROM = 2019
OUT = Path(__file__).resolve().parents[1] / "refdata" / "external_vaccination.yaml"


def fetch(indicator: str) -> dict[int, float]:
    url = f"https://ghoapi.azureedge.net/api/{indicator}?$filter=SpatialDim%20eq%20%27KAZ%27"
    with urllib.request.urlopen(url) as resp:
        rows = json.load(resp)["value"]
    return {int(r["TimeDim"]): float(r["NumericValue"]) for r in rows
            if r["TimeDim"] >= YEAR_FROM and r["NumericValue"] is not None}


def main() -> int:
    series = []
    for code, (vaccine, title_ru) in INDICATORS.items():
        values = fetch(code)
        series.append({
            "vaccine": vaccine,
            "title_ru": title_ru,
            "gho_indicator": code,
            "coverage_pct": {year: values[year] for year in sorted(values)},
        })
        print(f"{vaccine:6s} {dict(sorted(values.items()))}")
    payload = {
        "source": "WHO GHO OData API, индикаторы WUENIC (ВОЗ/ЮНИСЕФ), страна KAZ",
        "source_url": "https://ghoapi.azureedge.net/api/",
        "fetched": str(date.today()),
        "note": ("Оценки WUENIC ниже административной отчётности Казахстана (пересмотр после MICS); "
                 "в продукте — только внешний ориентир с подписью источника, не факт."),
        "series": series,
    }
    OUT.write_text(yaml.safe_dump(payload, allow_unicode=True, sort_keys=False), encoding="utf-8")
    print(f"written {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
