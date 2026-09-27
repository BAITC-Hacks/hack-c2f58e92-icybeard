# Деплой на dc.jurek.kz

Публичный стенд Darumen живёт на той же VM Hetzner, что и POS (`195.201.7.56`, 8 ГБ RAM, nbg1), на месте прежнего демо GovTech Camp по природным рискам. TLS и домен `dc.jurek.kz` терминирует хостовый Caddy (`pos-server/deploy/caddy/Caddyfile.host`, блок `dc.jurek.kz → reverse_proxy 127.0.0.1:5173`) — новый стек публикует веб на том же `127.0.0.1:5173`. Этот блок ставит `X-Frame-Options: DENY` на все ответы, поэтому веб проверяет сессию Keycloak редиректом с `prompt=none`, а не тихим iframe (`silentCheckSsoRedirectUri`): с `DENY` браузер отказывает iframe того же origin, `init()` keycloak-js падает по таймауту ~10 с, и веб показывал «сервер входа не отвечает». Не включайте тихую проверку через iframe и `checkLoginIframe`, пока на Caddy стоит `DENY`.

## Что поднимается

`infra/docker-compose.prod.yml` — самостоятельный файл, не оверлей:

| Сервис | Образ | Зачем |
| --- | --- | --- |
| postgres | postgis 17 | журнал, intake, витрины gold/refdata из lakehouse |
| models | `infra/models.Dockerfile` | gRPC Queue Intelligence / Load Forecasting, читает `/lakehouse` (gold, models, refdata) |
| scribe | тот же образ, `SCRIBE_EXTRAS=1` | FastAPI-скрайб: faster-whisper (веса скачиваются при первом запросе) + черновики через DeepSeek |
| keycloak | `quay.io/keycloak/keycloak:26.0` | вход веба (PKCE) и мобильного приложения (password grant); realm `darumen` импортируется из `infra/keycloak` при каждом создании контейнера (после правки realm нужен `up -d --force-recreate keycloak`); темы входа и писем (Палитра C, RU/KK) — `infra/keycloak/themes/darumen`, монтируются целиком в `/opt/keycloak/themes/darumen`; SMTP и секрет служебного клиента — из `.env` (см. «Keycloak» ниже); снаружи — только через nginx веба под `/auth` |
| api | `infra/api.Dockerfile` | .NET API: `Auth__Mode=keycloak` (issuer `https://dc.jurek.kz/auth/realms/darumen`, JWKS по внутреннему адресу `keycloak:8080`), `Messaging__Mode=local`, Insight через DeepSeek |
| web | `infra/web/Dockerfile` | Vite-сборка за nginx, `/api`, `/openapi`, `/scalar`, `/health` проксируются в api, `/auth` — в keycloak |

ClickHouse, Cube, Kafka, Schema Registry, MinIO, MLflow и Valkey в проде не нужны: в C# ClickHouse не используется, шина хранит outbox в Postgres, а Kafka заглушена. Вход — Keycloak с демо-пользователями realm (`regulator1`, `chief1` — администратор организации 028B, `doctor1`, `steward1`, `auditor1`, `citizen1`, `admin1`, пароль `darumen`); персональных данных стенд не хранит, ИИН у `citizen1` синтетический.

## Как задеплоить

1. Один раз: `cp infra/deploy/.env.prod.example infra/deploy/.env.prod`, заполнить `POSTGRES_PASSWORD`, `KEYCLOAK_ADMIN_PASSWORD`, `KEYCLOAK_ADMIN_CLIENT_SECRET`, `DEEPSEEK_API_KEY` и `SMTP_*` (файл в `.gitignore`). Без `KEYCLOAK_ADMIN_CLIENT_SECRET` compose не стартует; без `SMTP_HOST` стенд работает, но письма (сброс пароля, уведомления) не уходят.
2. Локально должны быть собраны витрины: `make data && make train` (нужны `lakehouse/gold`, `lakehouse/models`, `lakehouse/refdata`).
3. Первый раз, с остановкой старого стека GovTech Camp в `/srv/govtech-camp`:
   ```bash
   make deploy ARGS=--replace-dc
   ```
   Дальше просто `make deploy` (или `make deploy ARGS=--no-publish`, если менялся только код).

Скрипт `scripts/deploy.sh` делает rsync кода (без данных, `node_modules`, `bin/obj`) и ~60 МБ витрин в `/srv/darumen`, кладёт `.env`, собирает образы на VM, поднимает стек, публикует gold и refdata в Postgres (`--profile tools run --rm publish`) и ждёт `https://dc.jurek.kz/health` и `https://dc.jurek.kz/auth/realms/darumen`.

Старый стек останавливается через `docker compose down` без `-v`: его тома (`govtech-camp_pgdata`, `govtech-camp_uploads`) остаются, при необходимости удалить руками `docker volume rm`.

## Keycloak

**Realm.** `infra/keycloak/darumen-realm.json` импортируется при каждом создании контейнера (`start-dev --import-realm`, база dev-file внутри контейнера — пользователи, сессии и события, созданные на стенде, живут до пересоздания). После правки realm: `docker compose -f infra/docker-compose.prod.yml --env-file .env up -d --force-recreate keycloak` (локально — `docker compose -f infra/docker-compose.yml --env-file .env up -d --force-recreate keycloak mailpit`). Правка шаблонов темы подхватывается без перезапуска (в `start-dev` кэш тем выключен). В логах должно быть `Realm 'darumen' imported` и `Import finished successfully`.

Что в realm: роли `citizen`, `doctor`, `org_admin`, `regulator`, `steward`, `auditor`, `admin` (роли `chief` больше нет, `chief1` — `org_admin` с `mo_code=028B`); атрибуты `region_kato`, `mo_code`, `iin`, `specialty`, `position`, `via` объявлены в профиле пользователя: пишет и читает их только администратор через admin API (клиент `darumen-admin`), пользователь в личном кабинете видит только должность и специальность и изменить их не может; прочие атрибуты вне профиля — политика `ADMIN_EDIT` (без неё Keycloak 26 молча отбрасывает их при записи через admin API); политика паролей `length(12) and upperCase(1) and lowerCase(1) and digits(1) and notUsername and passwordHistory(5)`; защита от подбора — 5 попыток, блокировка 15 минут; TOTP 6 цифр / 30 с; сессия 30 минут без активности, «Запомнить на 30 дней» — 30 дней; офлайн-токены мобилки (`scope=offline_access`) — 30 дней; ссылка сброса пароля — 60 минут; события входа хранятся 30 дней. Демо-пароли `darumen` короче политики, поэтому в realm лежат их хэши (pbkdf2-sha512): политика проверяется только при смене пароля. Keycloak не выдаёт импортированным пользователям роли по умолчанию, поэтому у демо-пользователей явно указана `default-roles-darumen` (без неё офлайн-токены мобилки отклоняются с `not_allowed`).

**Плейсхолдеры.** В realm-файле `${VAR:значение по умолчанию}` подставляется из переменных окружения контейнера при импорте (проверено на 26.0.8: переменная окружения побеждает, без неё берётся значение после двоеточия). В теме `theme.properties` — `${env.VAR:по умолчанию}`.

| Переменная (сервис keycloak) | Dev (`docker-compose.yml`) | Прод (`docker-compose.prod.yml`, из `.env`) |
| --- | --- | --- |
| `SMTP_HOST`, `SMTP_PORT` | `mailpit`, `1025` | обязательно задать хост; порт по умолчанию `587` |
| `SMTP_USER`, `SMTP_PASSWORD` | пусто | учётка SMTP |
| `SMTP_FROM` | `noreply@darumen.kz` | по умолчанию `noreply@darumen.kz` (имя отправителя «Darumen Health», Reply-To `help@darumen.kz`) |
| `SMTP_AUTH`, `SMTP_STARTTLS`, `SMTP_SSL` | `false` | по умолчанию `true`, `true`, `false`; `SMTP_SSL` для порта 587 не задавать (API читает его как `Mail__Smtp__EnableSsl`, по умолчанию `true`) |
| `KEYCLOAK_ADMIN_CLIENT_SECRET` | `darumen-admin-dev-secret` | обязательна, длинная случайная строка |
| `DARUMEN_WEB_URL` | `http://localhost:5173/` | `${PUBLIC_ORIGIN}/` — корень веба для ссылок «О системе» и «Зарегистрировать организацию» |

В dev письма ловит Mailpit: интерфейс http://localhost:8025, API `http://localhost:8025/api/v1/messages`.

**Служебный клиент `darumen-admin`** — confidential, только client credentials (service account), без входа пользователей; роли `realm-management`: `view-users`, `manage-users`, `query-users`, `view-events`, `view-realm`, `manage-realm`. Им пользуется только API (пользователи, роли, события входа). Проверка: `curl -s -d client_id=darumen-admin -d client_secret=$KEYCLOAK_ADMIN_CLIENT_SECRET -d grant_type=client_credentials $KC/realms/darumen/protocol/openid-connect/token`. API нужен тот же секрет (`Keycloak__Admin__ClientSecret` в сервисе api).

**Темы.** `login/` — страницы по доскам W-Auth-*: вход (eGov — пояснение «после интеграции», без имитации входа), «Забыли пароль» → «Проверьте почту», новый пароль со шкалой и правилами политики, «Пароль изменён», второй фактор (6 полей, вставка кода), настройка аутентификатора (QR и ключ), ошибки «Ссылка устарела», «Аккаунт заблокирован», «Сессия истекла», выход. `email/` — письма по доске W-Mail: смена пароля, действия администратора, подтверждение почты и уведомления безопасности (пароль или аутентификатор изменён, вход временно заблокирован). Уведомления шлёт слушатель событий `email`, список событий — `KC_SPI_EVENTS_LISTENER_EMAIL_INCLUDE_EVENTS` в compose (без `LOGIN_ERROR`, чтобы не писать на каждую опечатку). Время в письмах — по `TZ=Asia/Almaty`.

## Проверка и отладка

```bash
ssh deploy@195.201.7.56 'cd /srv/darumen && docker compose -f infra/docker-compose.prod.yml --env-file .env ps'
ssh deploy@195.201.7.56 'cd /srv/darumen && docker compose -f infra/docker-compose.prod.yml --env-file .env logs --tail=100 api models scribe keycloak'
curl -s https://dc.jurek.kz/api/v1/            # {"name":"Darumen Health","version":...}
curl -s https://dc.jurek.kz/api/v1/insight/status
curl -s https://dc.jurek.kz/auth/realms/darumen | jq .realm   # "darumen" — Keycloak за nginx отвечает
```

Обновление данных: перегенерировать витрины локально (`make data`, `make train`) и снова `make deploy` — publish пересоздаст таблицы gold/refdata, journal и intake не трогаются.
