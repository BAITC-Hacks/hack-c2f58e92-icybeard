#!/usr/bin/env python3
"""Тестовые маршруты пациентов для локального стенда: пять граждан в разных стадиях перевода.

Создаёт через Keycloak Admin API граждан citizen2…citizenN (у каждого свой ИИН → своя персона в очереди региона)
и, если нужно, врачей для больниц, которых нет среди демо-пользователей (doctor_<код МО>), а затем через обычный
API Darumen (те же эндпоинты, что нажимает интерфейс) доводит маршруты до стадий:

  1. сигнал гражданина «рассмотрите больницу быстрее» — ждёт ответа врача;
  2. врач предложил перевод — ждём согласия пациента;
  3. пациент согласился — ждём подтверждения принимающей больницы (помечен «тяжёлый случай»);
  4. принимающая подтвердила на сегодня — можно отметить госпитализацию и выписать;
  5. принимающая отказала — пациент остался в своей очереди.

Ничего не пишет в базу напрямую: все записи журнала появляются так же, как от живых пользователей, поэтому
аудит, уведомления и правила состояний отрабатывают по-настоящему. Повторный запуск пропускает маршруты, где
уже есть решения; чтобы начать с чистого листа — scripts/dev/reset-routes.sql.

Запуск (нужны поднятые контейнеры, Python 3.10+, без сторонних пакетов):
  python scripts/dev/seed_routes.py
  python scripts/dev/seed_routes.py --api http://localhost:8000 --keycloak http://localhost:8080 --kc-admin admin:admin
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid
from datetime import datetime, timedelta, timezone

REALM = "darumen"
WEB_CLIENT = "darumen-web"
PASSWORD = "darumen"
# политика паролей realm (12 символов, заглавная, строчная, цифра) не пропускает «darumen» через Admin API:
# демо-пользователи импортированы с готовым хэшем, а созданным скриптом нужен пароль по политике
TEST_PASSWORD = "Darumen-Test-1"
ALMATY = timezone(timedelta(hours=5))
# демо-врачи realm по больницам: для других больниц скрипт создаёт doctor_<код>
KNOWN_DOCTORS = {"028B": "doctor1", "22GN": "doctor2"}
STAGES = ("signal", "pending_consent", "pending_confirmation", "transferred_today", "rejected")
STAGE_TITLES = {
    "signal": "сигнал гражданина, ждёт ответа врача",
    "pending_consent": "врач предложил перевод, ждём согласия пациента",
    "pending_confirmation": "пациент согласился, ждём подтверждения принимающей (тяжёлый случай)",
    "transferred_today": "перевод подтверждён на сегодня — можно госпитализировать и выписать",
    "rejected": "принимающая больница отказала — пациент в своей очереди",
}


class Http:
    def __init__(self, api: str, keycloak: str) -> None:
        self.api = api.rstrip("/")
        self.keycloak = keycloak.rstrip("/")

    def call(self, method: str, url: str, token: str | None = None, body: dict | None = None, form: dict | None = None,
             idempotent: bool = False) -> tuple[int, dict | list | None]:
        data = None
        headers = {"Accept": "application/json"}
        if form is not None:
            data = urllib.parse.urlencode(form).encode()
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        elif body is not None:
            data = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
        if token:
            headers["Authorization"] = f"Bearer {token}"
        if idempotent:
            headers["Idempotency-Key"] = str(uuid.uuid4())
        request = urllib.request.Request(url, data=data, method=method, headers=headers)
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                raw = response.read()
                return response.status, (json.loads(raw) if raw else None)
        except urllib.error.HTTPError as error:
            raw = error.read()
            try:
                return error.code, json.loads(raw) if raw else None
            except json.JSONDecodeError:
                return error.code, {"detail": raw.decode(errors="replace")}
        except urllib.error.URLError as error:
            sys.exit(f"нет связи с {url}: {error.reason}. Контейнеры подняты? (docker compose … --profile app up -d)")

    # --- Keycloak ---
    def kc_admin_token(self, user: str, password: str) -> str:
        status, data = self.call("POST", f"{self.keycloak}/realms/master/protocol/openid-connect/token",
                                 form={"grant_type": "password", "client_id": "admin-cli", "username": user, "password": password})
        if status != 200 or not isinstance(data, dict):
            sys.exit(f"Keycloak admin не пустил ({status}): {data}. Проверьте --kc-admin (в dev-compose admin:admin)")
        return data["access_token"]

    def user_token(self, username: str) -> str:
        """Вход демо-паролем, а если он не подошёл — паролем пользователей, созданных этим скриптом."""
        status, data = 0, None
        for password in (PASSWORD, TEST_PASSWORD):
            status, data = self.call("POST", f"{self.keycloak}/realms/{REALM}/protocol/openid-connect/token",
                                     form={"grant_type": "password", "client_id": WEB_CLIENT, "scope": "openid", "username": username, "password": password})
            if status == 200 and isinstance(data, dict):
                return data["access_token"]
        sys.exit(f"не удалось войти как {username} ({status}): {data}")

    def kc_find_user(self, admin: str, username: str) -> str | None:
        status, data = self.call("GET", f"{self.keycloak}/admin/realms/{REALM}/users?username={urllib.parse.quote(username)}&exact=true", token=admin)
        if status == 200 and isinstance(data, list) and data:
            return data[0]["id"]
        return None

    def kc_ensure_user(self, admin: str, username: str, role: str, attributes: dict[str, str], first: str, last: str) -> tuple[str, bool]:
        """Возвращает (id, создан_сейчас). Существующего пользователя не трогает."""
        existing = self.kc_find_user(admin, username)
        if existing:
            return existing, False
        representation = {
            "username": username, "enabled": True, "emailVerified": True, "firstName": first, "lastName": last,
            "email": f"{username}@darumen.local",
            "attributes": {k: [v] for k, v in attributes.items()},
            "credentials": [{"type": "password", "value": TEST_PASSWORD, "temporary": False}],
        }
        status, data = self.call("POST", f"{self.keycloak}/admin/realms/{REALM}/users", token=admin, body=representation)
        if status not in (201, 409):
            sys.exit(f"не удалось создать пользователя {username} ({status}): {data}")
        user_id = self.kc_find_user(admin, username)
        if not user_id:
            sys.exit(f"пользователь {username} не найден после создания")
        status, role_rep = self.call("GET", f"{self.keycloak}/admin/realms/{REALM}/roles/{role}", token=admin)
        if status != 200:
            sys.exit(f"роль {role} не найдена в realm ({status})")
        status, data = self.call("POST", f"{self.keycloak}/admin/realms/{REALM}/users/{user_id}/role-mappings/realm", token=admin,
                                 body=[{"id": role_rep["id"], "name": role_rep["name"]}])
        if status not in (204, 200):
            sys.exit(f"не удалось выдать роль {role} пользователю {username} ({status}): {data}")
        return user_id, True

    def kc_delete_user(self, admin: str, user_id: str) -> None:
        self.call("DELETE", f"{self.keycloak}/admin/realms/{REALM}/users/{user_id}", token=admin)

    # --- Darumen API ---
    def darumen(self, method: str, path: str, token: str, body: dict | None = None, idempotent: bool = True) -> dict:
        status, data = self.call(method, f"{self.api}/api/v1{path}", token=token, body=body, idempotent=idempotent and method == "POST")
        if status >= 400:
            detail = data.get("detail") if isinstance(data, dict) else data
            title = data.get("title") if isinstance(data, dict) else ""
            raise RuntimeError(f"{method} {path} → {status} {title or ''}: {detail}")
        return data if isinstance(data, dict) else {}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--api", default="http://localhost:8000", help="адрес API Darumen (по умолчанию http://localhost:8000)")
    parser.add_argument("--keycloak", default="http://localhost:8080", help="адрес Keycloak (по умолчанию http://localhost:8080)")
    parser.add_argument("--kc-admin", default="admin:admin", help="логин:пароль администратора Keycloak (dev-compose: admin:admin)")
    parser.add_argument("--region", default="75", help="КАТО региона персон (по умолчанию 75 — Алматы)")
    parser.add_argument("--max-attempts", type=int, default=25, help="сколько ИИН перебрать в поисках пяти разных персон")
    args = parser.parse_args()

    http = Http(args.api, args.keycloak)
    kc_user, _, kc_password = args.kc_admin.partition(":")
    admin = http.kc_admin_token(kc_user, kc_password)

    # 1. Персоны: citizen1 из realm + новые граждане, пока не наберётся пять разных пациентов
    personas: list[dict] = []
    seen_refs: set[str] = set()
    created_citizens: list[str] = []
    n = 1
    while len(personas) < len(STAGES) and n <= args.max_attempts:
        username = "citizen1" if n == 1 else f"citizen{n}"
        if n > 1:
            user_id, created = http.kc_ensure_user(admin, username, "citizen", {"region_kato": args.region, "iin": f"{n:012d}", "via": "password"},
                                                   "Тест", f"Гражданин {n}")
        token = http.user_token(username)
        try:
            route = http.darumen("GET", f"/route/me?regionKato={args.region}", token)
        except RuntimeError as error:
            print(f"  {username}: маршрут недоступен — {error}")
            n += 1
            continue
        ref = route["patientRef"]
        if ref in seen_refs:
            # та же персона, что у другого гражданина (хэш ИИН попал в ту же из пяти строк) — удаляем и пробуем следующий ИИН
            if n > 1 and created:
                http.kc_delete_user(admin, user_id)
            n += 1
            continue
        seen_refs.add(ref)
        if n > 1 and created:
            created_citizens.append(username)
        alternatives = route.get("alternatives") or []
        personas.append({
            "username": username, "token": token, "ref": ref, "region": route["regionKato"],
            "origin": route["organization"]["moCode"], "originName": route["organization"].get("moName") or route["organization"]["moCode"],
            "target": alternatives[0]["mo"]["moCode"] if alternatives else None,
            "targetName": alternatives[0]["mo"]["name"] if alternatives else None,
            "status": (route.get("progress") or {}).get("status", "waiting"),
        })
        n += 1

    if not personas:
        sys.exit("ни одного маршрута не получилось: проверьте, что опубликованы витрины (конвейер pipeline) и запущен сервис моделей")

    # 2. Врачи для всех больниц, которые участвуют в маршрутах
    doctors: dict[str, str] = {}
    created_doctors: list[str] = []
    for mo in sorted({p["origin"] for p in personas} | {p["target"] for p in personas if p["target"]}):
        username = KNOWN_DOCTORS.get(mo, f"doctor_{mo.lower()}")
        if mo not in KNOWN_DOCTORS:
            _, created = http.kc_ensure_user(admin, username, "doctor", {"region_kato": args.region, "mo_code": mo}, "Тест", f"Врач {mo}")
            if created:
                created_doctors.append(username)
        doctors[mo] = username

    today = datetime.now(ALMATY).date().isoformat()
    report: list[tuple[str, str, str]] = []

    # 3. Стадии — по одной на персону, в порядке STAGES
    for persona, stage in zip(personas, STAGES):
        who = f"{persona['username']} · {persona['ref']} ({persona['originName']})"
        if persona["status"] != "waiting":
            report.append((who, f"пропущен: уже есть решения (статус {persona['status']}); сброс — scripts/dev/reset-routes.sql", stage))
            continue
        if not persona["target"]:
            report.append((who, "пропущен: модель не дала альтернатив (сервис models запущен?)", stage))
            continue
        origin_doctor = doctors[persona["origin"]]
        target_doctor = doctors[persona["target"]]
        try:
            if stage == "signal":
                http.darumen("POST", f"/route/me/signals?regionKato={args.region}", persona["token"],
                             {"kind": "request_redirect", "toMoCode": persona["target"], "comment": "Тест: прошу рассмотреть больницу, где примут быстрее"})
            else:
                severe = stage == "pending_confirmation"
                decision = http.darumen("POST", f"/route/{persona['ref']}/redirect", http.user_token(origin_doctor),
                                        {"toMoCode": persona["target"], "reason": "Тест: в этой больнице ожидание заметно короче", "severe": severe})
                decision_id = decision["decisionId"]
                if stage != "pending_consent":
                    http.darumen("POST", f"/route/me/consent?regionKato={args.region}", persona["token"], {"decisionId": decision_id, "accepted": True})
                if stage == "transferred_today":
                    http.darumen("POST", f"/journal/referrals/{decision_id}/confirm", http.user_token(target_doctor),
                                 {"patientRef": persona["ref"], "plannedAt": today, "comment": "Тест: место есть, ждём сегодня"})
                elif stage == "rejected":
                    http.darumen("POST", f"/journal/referrals/{decision_id}/reject", http.user_token(target_doctor),
                                 {"patientRef": persona["ref"], "reason": "Тест: нет мест по профилю на ближайший месяц"})
            report.append((who, f"{STAGE_TITLES[stage]} → {persona['targetName']} (врач принимающей: {target_doctor}; врач пациента: {origin_doctor})", stage))
        except RuntimeError as error:
            report.append((who, f"ошибка на стадии «{STAGE_TITLES[stage]}»: {error}", stage))

    # 4. Итог
    print(f"\nТестовые маршруты (пароль демо-пользователей: {PASSWORD}; созданных скриптом: {TEST_PASSWORD})\n")
    for who, outcome, _ in report:
        print(f"  • {who}\n      {outcome}")
    if created_citizens or created_doctors:
        print(f"\nСозданы пользователи Keycloak (пароль {TEST_PASSWORD}):", ", ".join(created_citizens + created_doctors))
    print("\nГде смотреть:")
    print("  гражданин  — войти его логином → «Мой путь» (/me/route)")
    print("  врач пациента — /doctor/worklist (строка с флагом сигнала / статусом перевода) → карточка пациента")
    print("  принимающая больница — /doctor/referrals/incoming (подтвердить, отказать, госпитализировать, выписать)")
    print("  главврач 028B (chief1) и регулятор (regulator1) — /doctor/decisions и /gov/audit: все записи журнала")


if __name__ == "__main__":
    main()
