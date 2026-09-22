# Деплой на dc.jurek.kz

Публичный стенд Darumen живёт на той же VM Hetzner, что и POS (`195.201.7.56`, 8 ГБ RAM, nbg1), на месте прежнего демо GovTech Camp по природным рискам. TLS и домен `dc.jurek.kz` терминирует хостовый Caddy (`pos-server/deploy/caddy/Caddyfile.host`, блок `dc.jurek.kz → reverse_proxy 127.0.0.1:5173`) — новый стек публикует веб на том же `127.0.0.1:5173`. Этот блок ставит `X-Frame-Options: DENY` на все ответы, поэтому веб проверяет сессию Keycloak редиректом с `prompt=none`, а не тихим iframe (`silentCheckSsoRedirectUri`): с `DENY` браузер отказывает iframe того же origin, `init()` keycloak-js падает по таймауту ~10 с, и веб показывал «сервер входа не отвечает». Не включайте тихую проверку через iframe и `checkLoginIframe`, пока на Caddy стоит `DENY`.

## Что поднимается

`infra/docker-compose.prod.yml` — самостоятельный файл, не оверлей:

| Сервис | Образ | Зачем |
| --- | --- | --- |
| postgres | postgis 17 | журнал, intake, витрины gold/refdata из lakehouse |
| models | `infra/models.Dockerfile` | gRPC Queue Intelligence / Load Forecasting, читает `/lakehouse` (gold, models, refdata) |
| scribe | тот же образ, `SCRIBE_EXTRAS=1` | FastAPI-скрайб: faster-whisper (веса скачиваются при первом запросе) + черновики через DeepSeek |
| keycloak | `quay.io/keycloak/keycloak:26.0` | вход веба (PKCE) и мобильного приложения (password grant); realm `darumen` импортируется из `infra/keycloak` при старте; снаружи — только через nginx веба под `/auth` |
| api | `infra/api.Dockerfile` | .NET API: `Auth__Mode=keycloak` (issuer `https://dc.jurek.kz/auth/realms/darumen`, JWKS по внутреннему адресу `keycloak:8080`), `Messaging__Mode=local`, Insight через DeepSeek |
| web | `infra/web/Dockerfile` | Vite-сборка за nginx, `/api`, `/openapi`, `/scalar`, `/health` проксируются в api, `/auth` — в keycloak |

ClickHouse, Cube, Kafka, Schema Registry, MinIO, MLflow и Valkey в проде не нужны: в C# ClickHouse не используется, шина хранит outbox в Postgres, а Kafka заглушена. Вход — Keycloak с демо-пользователями realm (`regulator1`, `chief1`, `doctor1`, `steward1`, `citizen1`, `admin1`, пароль `darumen`); персональных данных стенд не хранит, ИИН у `citizen1` синтетический.

## Как задеплоить

1. Один раз: `cp infra/deploy/.env.prod.example infra/deploy/.env.prod`, заполнить `POSTGRES_PASSWORD`, `KEYCLOAK_ADMIN_PASSWORD` и `DEEPSEEK_API_KEY` (файл в `.gitignore`).
2. Локально должны быть собраны витрины: `make data && make train` (нужны `lakehouse/gold`, `lakehouse/models`, `lakehouse/refdata`).
3. Первый раз, с остановкой старого стека GovTech Camp в `/srv/govtech-camp`:
   ```bash
   make deploy ARGS=--replace-dc
   ```
   Дальше просто `make deploy` (или `make deploy ARGS=--no-publish`, если менялся только код).

Скрипт `scripts/deploy.sh` делает rsync кода (без данных, `node_modules`, `bin/obj`) и ~60 МБ витрин в `/srv/darumen`, кладёт `.env`, собирает образы на VM, поднимает стек, публикует gold и refdata в Postgres (`--profile tools run --rm publish`) и ждёт `https://dc.jurek.kz/health` и `https://dc.jurek.kz/auth/realms/darumen`.

Старый стек останавливается через `docker compose down` без `-v`: его тома (`govtech-camp_pgdata`, `govtech-camp_uploads`) остаются, при необходимости удалить руками `docker volume rm`.

## Проверка и отладка

```bash
ssh deploy@195.201.7.56 'cd /srv/darumen && docker compose -f infra/docker-compose.prod.yml --env-file .env ps'
ssh deploy@195.201.7.56 'cd /srv/darumen && docker compose -f infra/docker-compose.prod.yml --env-file .env logs --tail=100 api models scribe keycloak'
curl -s https://dc.jurek.kz/api/v1/            # {"name":"Darumen Health","version":...}
curl -s https://dc.jurek.kz/api/v1/insight/status
curl -s https://dc.jurek.kz/auth/realms/darumen | jq .realm   # "darumen" — Keycloak за nginx отвечает
```

Обновление данных: перегенерировать витрины локально (`make data`, `make train`) и снова `make deploy` — publish пересоздаст таблицы gold/refdata, journal и intake не трогаются.
