#!/usr/bin/env python3
"""Оценка AI-скрайба на синтетических сценариях (ml/scribe_eval/scenarios.yaml).

Две независимые проверки:

1. Черновики (--drafts, нужен работающий стек: API + scribe + LLM):
   эталонная стенограмма отправляется в скрайб, черновик проверяется на ключевые факты
   (жалобы, диагноз, план). Доля сценариев, где все факты на месте, — прокси метрики
   «доля черновиков без правок».

2. WER распознавания (--audio-dir DIR, офлайн, нужен faster-whisper из ml/.venv):
   команда записывает аудио по текстам сценариев в DIR/<id>.wav, скрипт прогоняет их
   через ту же модель распознавания и считает пословный WER против эталона.

Примеры:
    python scripts/scribe_eval.py --drafts --api http://localhost:8000
    python scripts/scribe_eval.py --drafts --api http://localhost:8000 --keycloak http://localhost:8080
    ml/.venv/bin/python scripts/scribe_eval.py --audio-dir ml/scribe_eval/audio
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCENARIOS = ROOT / "ml" / "scribe_eval" / "scenarios.yaml"


def load_scenarios() -> list[dict]:
    import yaml

    return yaml.safe_load(SCENARIOS.read_text(encoding="utf-8"))["scenarios"]


def words(text: str) -> list[str]:
    return re.findall(r"\w+", text.lower(), flags=re.UNICODE)


def wer(reference: str, hypothesis: str) -> float:
    """Пословный WER: расстояние Левенштейна по словам, делённое на длину эталона."""
    ref, hyp = words(reference), words(hypothesis)
    if not ref:
        return 0.0
    prev = list(range(len(hyp) + 1))
    for i, r in enumerate(ref, 1):
        cur = [i]
        for j, h in enumerate(hyp, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (r != h)))
        prev = cur
    return prev[-1] / len(ref)


def keycloak_token(url: str, user: str, password: str, client_id: str = "darumen-web") -> str:
    data = urllib.parse.urlencode({"grant_type": "password", "client_id": client_id,
                                   "username": user, "password": password}).encode()
    req = urllib.request.Request(f"{url}/realms/darumen/protocol/openid-connect/token", data=data)
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)["access_token"]


def api_call(api: str, path: str, body: dict | None, token: str | None, method: str = "POST") -> dict:
    headers = {"Content-Type": "application/json"}
    headers.update({"Authorization": f"Bearer {token}"} if token else {"X-Actor": "doctor1", "X-Role": "doctor"})
    req = urllib.request.Request(f"{api}{path}", data=json.dumps(body).encode() if body is not None else None,
                                 headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=600) as resp:
        return json.load(resp)


def eval_drafts(scenarios: list[dict], api: str, token: str | None) -> dict:
    """Черновик по эталонной стенограмме: все ли ключевые факты попали в разделы."""
    results = []
    for sc in scenarios:
        started = time.monotonic()
        try:
            session = api_call(api, "/api/v1/scribe/sessions", {"consent": True, "language": sc["language"]}, token)
            sid = session["sessionId"]
            api_call(api, f"/api/v1/scribe/sessions/{sid}/transcript", {"text": sc["transcript"]}, token)
            draft = api_call(api, f"/api/v1/scribe/sessions/{sid}/draft", {}, token)
            text = " ".join(s.get("text", "") for s in draft.get("sections", [])).lower()
            # «а|б» — любая из форм факта засчитывается (словами или цифрами)
            missing = [kw for group in sc["expect"].values() for kw in group
                       if not any(alt.strip().lower() in text for alt in kw.split("|"))]
            model = str(draft.get("model", "?"))  # rules@… означает фолбэк без LLM — это не оценка модели
            results.append({"id": sc["id"], "language": sc["language"], "ok": not missing, "model": model,
                            "missing": missing, "seconds": round(time.monotonic() - started, 1)})
            print(f"draft {sc['id']} [{sc['language']}] {model} {'OK' if not missing else 'MISSING ' + ', '.join(missing)}")
        except Exception as exc:  # noqa: BLE001 — сценарии независимы, падение одного не прерывает прогон
            results.append({"id": sc["id"], "language": sc["language"], "ok": False, "error": str(exc)})
            print(f"draft {sc['id']} [{sc['language']}] ERROR {exc}")
    done = [r for r in results if "error" not in r]
    models: dict[str, int] = {}
    for r in done:
        models[r["model"]] = models.get(r["model"], 0) + 1
    summary = {"scenarios": len(results), "reached_model": len(done), "models": models,
               "clean_share": round(sum(r["ok"] for r in done) / len(done), 3) if done else None}
    if any(m.startswith("rules@") for m in models):
        summary["warning"] = "часть черновиков написана фолбэком правил (LLM не ответил) — это не оценка модели"
    return {"summary": summary, "results": results}


def eval_audio(scenarios: list[dict], audio_dir: Path, model_name: str) -> dict:
    """WER распознавания на записанных командой аудио: DIR/<id>.wav (или .m4a/.webm/.mp3)."""
    from faster_whisper import WhisperModel

    model = WhisperModel(model_name, compute_type="int8")
    results = []
    for sc in scenarios:
        audio = next((p for ext in ("wav", "m4a", "webm", "mp3") if (p := audio_dir / f"{sc['id']}.{ext}").exists()), None)
        if audio is None:
            continue
        segments, _ = model.transcribe(str(audio), language=sc["language"] if sc["language"] != "kk" else None)
        hypothesis = " ".join(s.text for s in segments)
        value = wer(sc["transcript"], hypothesis)
        results.append({"id": sc["id"], "language": sc["language"], "wer": round(value, 3)})
        print(f"wer   {sc['id']} [{sc['language']}] {value:.1%}")
    if not results:
        print(f"в {audio_dir} нет аудио по сценариям — запишите DIR/<id>.wav по текстам из {SCENARIOS}")
        return {"summary": {"recorded": 0}, "results": []}
    by_lang = {}
    for lang in ("ru", "kk"):
        vals = [r["wer"] for r in results if r["language"] == lang]
        if vals:
            by_lang[lang] = round(sum(vals) / len(vals), 3)
    return {"summary": {"recorded": len(results), "mean_wer": by_lang}, "results": results}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="scribe_eval")
    parser.add_argument("--drafts", action="store_true", help="прогнать черновики через работающий скрайб")
    parser.add_argument("--audio-dir", type=Path, default=None, help="каталог с записанными аудио для WER")
    parser.add_argument("--api", default="http://localhost:8000")
    parser.add_argument("--keycloak", default=None, help="адрес Keycloak: вход паролем демо-врача вместо заголовков")
    parser.add_argument("--password", default="darumen")
    parser.add_argument("--whisper-model", default="small")
    parser.add_argument("--out", type=Path, default=ROOT / "ml" / "scribe_eval" / "report.json")
    args = parser.parse_args(argv)

    scenarios = load_scenarios()
    report: dict = {"scenarios": len(scenarios)}
    if args.drafts:
        token = keycloak_token(args.keycloak, "doctor1", args.password) if args.keycloak else None
        report["drafts"] = eval_drafts(scenarios, args.api, token)
    if args.audio_dir:
        report["audio"] = eval_audio(scenarios, args.audio_dir, args.whisper_model)
    if not args.drafts and not args.audio_dir:
        parser.error("укажите --drafts и/или --audio-dir")

    args.out.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"отчёт: {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
