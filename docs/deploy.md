# Деплой на dc.jurek.kz

Публичный стенд Darumen живёт на той же VM Hetzner, что и POS (`195.201.7.56`, 8 ГБ RAM, nbg1), на месте прежнего демо GovTech Camp по природным рискам. TLS и домен `dc.jurek.kz` терминирует хостовый Caddy (`pos-server/deploy/caddy/Caddyfile.host`, блок `dc.jurek.kz → reverse_proxy 127.0.0.1:5173`) — Caddy не трогаем, новый стек публикует веб на том же `127.0.0.1:5173`.

## Что поднимается

`infra/docker-compose.prod.yml` — самостоятельный файл, не оверлей:

| Сервис | Образ | Зачем |
| --- | --- | --- |
| postgres | postgis 17 | журнал, intake, витрины gold/refdata из lakehouse |
| models | `infra/models.Dockerfile` | gRPC Queue Intelligence / Load Forecasting, читает `/lakehouse` (gold, models, refdata) |
| scribe | тот же образ, `SCRIBE_EXTRAS=1` | FastAPI-скрайб: faster-whisper (веса скачиваются при первом запросе) + черновики через DeepSeek |
| api | `infra/api.Dockerfile` | .NET API: `Auth__Mode=headers`, `Messaging__Mode=stub`, Insight через DeepSeek |
| web | `infra/web/Dockerfile` | Vite-сборка за nginx, `/api`, `/openapi`, `/scalar`, `/health` проксируются в api |

ClickHouse, Cube, Kafka, Schema Registry, Keycloak, MinIO, MLflow и Valkey в проде не нужны: в C# ClickHouse не используется, шина работает в режиме заглушки, авторизация — заголовками `X-Actor`/`X-Role`/`X-Region` (демо-режим, роль выбирается в интерфейсе — как и на старом стенде, стенд не для персональных данных).

## Как задеплоить

1. Один раз: `cp infra/deploy/.env.prod.example infra/deploy/.env.prod`, заполнить `POSTGRES_PASSWORD` и `DEEPSEEK_API_KEY` (файл в `.gitignore`).
2. Локально должны быть собраны витрины: `make data && make train` (нужны `lakehouse/gold`, `lakehouse/models`, `lakehouse/refdata`).
3. Первый раз, с остановкой старого стека GovTech Camp в `/srv/govtech-camp`:
   ```bash
   make deploy ARGS=--replace-dc
   ```
   Дальше просто `make deploy` (или `make deploy ARGS=--no-publish`, если менялся только код).

Скрипт `scripts/deploy.sh` делает rsync кода (без данных, `node_modules`, `bin/obj`) и ~60 МБ витрин в `/srv/darumen`, кладёт `.env`, собирает образы на VM, поднимает стек, публикует gold и refdata в Postgres (`--profile tools run --rm publish`) и ждёт `https://dc.jurek.kz/health`.

Старый стек останавливается через `docker compose down` без `-v`: его тома (`govtech-camp_pgdata`, `govtech-camp_uploads`) остаются, при необходимости удалить руками `docker volume rm`.

## Проверка и отладка

```bash
ssh deploy@195.201.7.56 'cd /srv/darumen && docker compose -f infra/docker-compose.prod.yml --env-file .env ps'
ssh deploy@195.201.7.56 'cd /srv/darumen && docker compose -f infra/docker-compose.prod.yml --env-file .env logs --tail=100 api models scribe'
curl -s https://dc.jurek.kz/api/v1/            # {"name":"Darumen Health","version":...}
curl -s https://dc.jurek.kz/api/v1/insight/status
```

Обновление данных: перегенерировать витрины локально (`make data`, `make train`) и снова `make deploy` — publish пересоздаст таблицы gold/refdata, journal и intake не трогаются.
