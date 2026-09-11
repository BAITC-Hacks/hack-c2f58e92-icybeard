"""Прогон эталонных вопросов Insight: python scripts/insight_eval.py [--api http://localhost:8000] [--role regulator] [--timeout 600]

Требует запущенный API с настроенной моделью (локальная Ollama по умолчанию). Печатает ответ и использованные
инструменты по каждому вопросу и итог; таймаут и сетевые ошибки считаются промахом, а не останавливают прогон.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
import urllib.error
import urllib.parse
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


def keycloak_token(url: str, user: str, password: str, client_id: str = "darumen-web") -> str:
    """Пароль демо-пользователя реалма darumen обменивается на токен (для API в режиме keycloak, например в Docker)."""
    data = urllib.parse.urlencode({"grant_type": "password", "client_id": client_id, "username": user, "password": password}).encode()
    with urllib.request.urlopen(urllib.request.Request(f"{url}/realms/darumen/protocol/openid-connect/token", data=data), timeout=30) as r:
        return json.load(r)["access_token"]


def ask(api: str, role: str, question: str, timeout: float, token: str | None = None) -> dict:
    headers = {"Content-Type": "application/json"}
    headers.update({"Authorization": f"Bearer {token}"} if token else {"X-Actor": f"{role}1", "X-Role": role})
    req = urllib.request.Request(f"{api}/api/v1/insight/ask", data=json.dumps({"question": question}).encode(), headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        return {"error": e.code, "answer": e.read().decode()[:300], "toolsUsed": []}
    except Exception as e:  # noqa: BLE001 - таймаут или сеть: промах, но прогон продолжается
        return {"error": type(e).__name__, "answer": str(e)[:200], "toolsUsed": []}


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
    parser.add_argument("--timeout", type=float, default=600.0, help="секунд на вопрос; локальные модели отвечают минуты")
    parser.add_argument("--keycloak", default=None, help="адрес Keycloak, например http://localhost:8080: вход паролем демо-пользователя вместо заголовков")
    parser.add_argument("--password", default="darumen")
    args = parser.parse_args()
    token = keycloak_token(args.keycloak, f"{args.role}1", args.password) if args.keycloak else None
    ok = 0
    rows = questions()
    for number, question, expectation in rows:
        started = time.time()
        answer = ask(args.api, args.role, question, args.timeout, token)
        good = passed(answer, expectation)
        ok += good
        print(f"{'OK  ' if good else 'FAIL'} {number:2d} [{time.time() - started:.0f}s] {question}\n     -> {answer.get('answer', '')[:160].replace(chr(10), ' ')} | tools {answer.get('toolsUsed')}", flush=True)
    print(f"\n{ok}/{len(rows)} passed (criterion 25/30)")
    return 0 if ok >= 25 else 1


if __name__ == "__main__":
    sys.exit(main())
