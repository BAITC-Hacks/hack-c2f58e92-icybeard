"""Прогон эталонных вопросов Insight: python scripts/insight_eval.py [--api http://localhost:8000] [--role regulator]

Требует запущенный API с ANTHROPIC_API_KEY. Печатает ответ и использованные инструменты по каждому вопросу и итог.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

DOC = Path(__file__).resolve().parents[1] / "docs" / "insight-questions.md"
TOOL_NAMES = ["access_index", "predict_wait", "organizations", "queue_state", "simulate", "forecast", "anomalies", "medicines_check", "regions", "bed_profiles"]


def questions() -> list[tuple[int, str, str]]:
    rows = []
    for line in DOC.read_text(encoding="utf-8").splitlines():
        match = re.match(r"\|\s*(\d+)\s*\|\s*(.+?)\s*\|\s*(.+?)\s*\|$", line)
        if match:
            rows.append((int(match.group(1)), match.group(2), match.group(3)))
    return rows


def ask(api: str, role: str, question: str) -> dict:
    req = urllib.request.Request(f"{api}/api/v1/insight/ask", data=json.dumps({"question": question}).encode(),
                                 headers={"Content-Type": "application/json", "X-Actor": f"{role}1", "X-Role": role}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        return {"error": e.code, "answer": e.read().decode()[:300], "toolsUsed": []}


def passed(answer: dict, expectation: str) -> bool:
    text = (answer.get("answer") or "").lower()
    expected_tools = [t for t in TOOL_NAMES if t in expectation]
    tools_ok = not expected_tools or any(t in answer.get("toolsUsed", []) for t in expected_tools)
    has_number = bool(re.search(r"\d", text))
    return "error" not in answer and tools_ok and (has_number or "нет" in text or "инструмент" not in expectation)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--api", default="http://localhost:8000")
    parser.add_argument("--role", default="regulator")
    args = parser.parse_args()
    ok = 0
    rows = questions()
    for number, question, expectation in rows:
        answer = ask(args.api, args.role, question)
        good = passed(answer, expectation)
        ok += good
        print(f"{'OK  ' if good else 'FAIL'} {number:2d} {question}\n     -> {answer.get('answer', '')[:160].replace(chr(10), ' ')} | tools {answer.get('toolsUsed')}")
    print(f"\n{ok}/{len(rows)} passed (criterion 25/30)")
    return 0 if ok >= 25 else 1


if __name__ == "__main__":
    sys.exit(main())
