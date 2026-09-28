# Деплой стенда Darumen

## Цели деплоя

С 28.09.2026 у Darumen два стенда. Цель выбирается переменной `TARGET` (`make deploy TARGET=jurek`); её параметры — в `infra/deploy/targets/<цель>.env` (без секретов), секреты — в env-файле цели (git-ignored).

| Цель | Стенд | Хост и каталог | Порт веба | Env-файл | Кто выкатывает |
| --- | --- | --- | --- | --- | --- |
| `govtech` (по умолчанию) | https://icybeard.govtech-kz.com | `icybeard@82.115.43.223:/home/icybeard/darumen` — VPS хакатона, общий для всех команд | `8014` (Caddy организаторов → `127.0.0.1:8014`) | `infra/deploy/.env.govtech` | `make deploy`, CD по тегу |
| `jurek` | https://dc.jurek.kz | `deploy@195.201.7.56:/srv/darumen` — Hetzner, общая с POS | `5173` (хостовый Caddy) | `infra/deploy/.env.prod` | только `make deploy TARGET=jurek` |

На VPS хакатона Docker rootless: у каждой команды свой демон (`systemctl --user`, сокет `/run/user/1014/docker.sock`), поэтому контейнеры и их переменные другим командам не видны, а чистка образов и кэша сборки трогает только наши (`DEPLOY_PRUNE=1`, `DARUMEN_PRUNE_ALL=1`). Демон включён как пользовательский сервис, для пользователя включён linger — стек переживает выход из ssh и перезагрузку. Особенности rootless: на пользователя хоста отображается только root контейнера, поэтому бэкапы там пишет root контейнера (скрипты выбирают 0:0 сами); cgroup-драйвера нет, поэтому лимиты памяти из compose демон игнорирует; памяти мало (4 CPU, ~1,8 ГБ свободно на всех), поэтому `make deploy` собирает образы по одному (`DEPLOY_SEQUENTIAL_BUILD=1`). Логин и пароль команды на VPS — только в `docs/IcyBeard-secrets.pdf` (git-ignored), в репозиторий не попадают; для `make deploy` на VPS нужен вход по ключу (разово: `ssh-copy-id icybeard@82.115.43.223`, пароль из PDF).

## Стенд dc.jurek.kz

Прежний публичный стенд Darumen живёт на той же VM Hetzner, что и POS (`195.201.7.56`, 8 ГБ RAM без swap, nbg1), на месте прежнего демо GovTech Camp по природным рискам. TLS и домен `dc.jurek.kz` терминирует хостовый Caddy (`pos-server/deploy/caddy/Caddyfile.host`, блок `dc.jurek.kz → reverse_proxy 127.0.0.1:5173`) — стек публикует веб на `127.0.0.1:5173`. Этот блок ставит `X-Frame-Options: DENY` на все ответы, поэтому веб проверяет сессию Keycloak редиректом с `prompt=none`, а не тихим iframe (`silentCheckSsoRedirectUri`): с `DENY` браузер отказывает iframe того же origin, `init()` keycloak-js падает по таймауту ~10 с, и веб показывал «сервер входа не отвечает». Не включайте тихую проверку через iframe и `checkLoginIframe`, пока на Caddy стоит `DENY`.

Два пути выкатки:

- **CD по тегу** (основной, на VPS хакатона): `git tag v1.2.0 && git push origin v1.2.0` → `.github/workflows/release.yml` собирает образы в GHCR, выкатывает их на VM через `<стенд>/bin/release.sh` (`/home/icybeard/darumen` на VPS хакатона), проверяет и при сбое откатывает, собирает Android и публикует GitHub Release. CI выбирает только тег образов; форму инфраструктуры (compose, SQL, скрипты релиза) на VM ставит человек — `make vm-install-release`.
- **`make deploy`** (ручной, с ноутбука): rsync исходников и витрин, сборка образов на VM. Нужен для данных (`make deploy-data` — lakehouse есть только на машине разработчика) и как запасной путь без CI.

## Архитектура

```
человек: make vm-install-release ─► /srv/darumen/bin/template  (compose, db-init.sql, release.sh, restore.sh, template-hash.sh)
                                     /srv/darumen/bin/release.sh → template/…  (forced command ключа CI)

тег vX.Y.Z ─► release.yml ─► ci (тот же ci.yml) ─► images: 5 образов → ghcr.io/baitc-hacks/hack-c2f58e92-icybeard/*
                                   │                                  │
                                   └► android (AAB/APK)                └► deploy: ssh "release <тег> <actor> <sha256 шаблона тега>"
                                                                            stdin: только токен GHCR
                                                                              │
VM /srv/darumen/bin/release.sh ◄───────────────────────────────────────────────┘
  хэш шаблона на VM = хэш тега? (нет → отказ, стенд не тронут) → снимок шаблона в releases/<тег> → compose config
  с .env VM → pull → дамп БД → up -d → healthcheck + realm-sync → smoke → current → releases/<тег>
  (сбой → автооткат на прежний current)
                                   ▼
release.yml: smoke снаружи через Caddy (сбой → rollback) → GitHub Release (APK/AAB, заметки)
```

**Раскладка на VM** (`/srv/darumen`, владелец `deploy`):

| Путь | Что | Кто пишет |
| --- | --- | --- |
| `.env` | все секреты стенда (образец `infra/deploy/.env.prod.example`), `chmod 600` | человек (`make deploy` копирует `infra/deploy/.env.prod`); CD не трогает |
| `lakehouse/` | витрины gold, модели, refdata, манифесты (~60 МБ, не в git) | `make deploy` / `make deploy-data` |
| `backups/` | дампы Postgres: `last/`, `daily/`, `weekly/`, `monthly/`, `pre-restore/`; закрыты от других пользователей (каталоги 0700, файлы 0600) | сервис `backup`, `release.sh`, `restore.sh` |
| `bin/template/` | шаблон релиза — файлы из `infra/deploy/template-files.txt` | только человек (`make vm-install-release`) |
| `bin/release.sh`, `bin/restore.sh` | симлинки на копии в `bin/template/infra/deploy/`; `release.sh` — forced command ключа CI | то же |
| `releases/<тег>/` | снимок шаблона на момент релиза, `IMAGE_TAG`, `TEMPLATE_SHA256`, `STATUS`, `release.log` | `release.sh`, хранит 5 последних |
| `current`, `previous` | симлинки на релизы | `release.sh` |
| `infra/`, `src/`, … `MANUAL_DEPLOY` | исходники ручного деплоя и его отметка | `make deploy` |

**Сервисы** `infra/docker-compose.prod.yml` (проект `darumen`, самостоятельный файл, не оверлей):

| Сервис | Образ | Зачем | Проверка | Лимит памяти |
| --- | --- | --- | --- | --- |
| postgres | `imresamu/postgis:17-3.5@sha256:35fe7dce…` | журнал, intake, витрины gold/refdata, БД `keycloak` | `pg_isready` | 1 ГБ |
| db-init | тот же, одноразовый | идемпотентно: схемы darumen, роль и БД `keycloak` (`infra/postgres/db-init.sql`) — работает и на свежем томе, и на существующем `pgdata` | код выхода 0 | 128 МБ |
| keycloak | `…/keycloak` (`infra/keycloak/Dockerfile`) | вход; prod-режим на Postgres, темы внутри образа, realm импортируется только на пустую БД | bash `/dev/tcp` → `:9000/auth/health/ready` | 1 ГБ (heap 512 МБ) |
| realm-sync | `…/keycloak-config` (`infra/keycloak/config-cli.Dockerfile`) | одноразовый keycloak-config-cli: приводит realm к файлу, ничего не удаляя | код выхода 0 | 512 МБ |
| models | `…/models` (`infra/models.Dockerfile`, `SCRIBE_EXTRAS=1`) | gRPC Queue Intelligence / Load Forecasting | gRPC health | 1 ГБ |
| scribe | тот же образ | FastAPI-скрайб: faster-whisper + черновики DeepSeek | `/scribe/health` | 2 ГБ |
| intake | тот же образ | консоль загрузки данных; контракты зашиты в образ, одобренные на стенде — в томе `intakecontracts` | `/intake/health` | 1 ГБ |
| api | `…/api` (`infra/api.Dockerfile`, с curl) | .NET API: `Auth__Mode=keycloak`, `Messaging__Mode=local`, Insight через DeepSeek | `curl /health` | 768 МБ |
| web | `…/web` (`infra/web/Dockerfile`) | Vite-сборка за nginx; `/api`, `/openapi`, `/scalar`, `/health` → api, `/auth` → keycloak | `wget /` | 128 МБ |
| backup | `prodrigestivill/postgres-backup-local:17-debian-d257e5d@sha256:e803bd9e…` | ежедневные дампы darumen и keycloak | curl планировщика | 256 МБ |
| publish | `…/models`, профиль `tools` | публикация gold и refdata из lakehouse в Postgres | — | 1,5 ГБ |

`…` = `ghcr.io/baitc-hacks/hack-c2f58e92-icybeard` (`REGISTRY`), тег — `IMAGE_TAG`: `vX.Y.Z` у CD, `local` у `make deploy` (образы собираются на VM под тем же именем). Публичные образы закреплены по digest мультиархитектурного индекса (для postgis — тот же образ, что уже работает на VM); обновление — новый digest в compose и `make vm-install-release`. Лимиты — потолки против утечки одного сервиса на 8 ГБ VM, которую стенд делит с POS; в покое стенд занимает ~1,5 ГБ. Логи всех сервисов — `json-file` с ротацией 10 МБ × 3 (якорь `x-logging`). `depends_on` с условиями: keycloak ждёт db-init, realm-sync — healthy Keycloak, api — healthy Postgres и Keycloak, web — запущенных api и keycloak (nginx резолвит их при старте). Частые пробы healthcheck (`start_interval: 5s`) идут только в `start_period`, дальше — раз в 15–60 с.

ClickHouse, Cube, Kafka, Schema Registry, MinIO, MLflow и Valkey в проде не нужны: в C# ClickHouse не используется, шина хранит outbox в Postgres. Вход — Keycloak с демо-пользователями realm (`regulator1`, `chief1` — администратор организации 028B, `doctor1`, `steward1`, `auditor1`, `citizen1`, `admin1`, пароль `darumen`); персональных данных стенд не хранит, ИИН у `citizen1` синтетический.

## Граница доверия: шаблон релиза

Ключ CI на VM — forced command `release.sh`, и он может ровно три вещи: `release <тег> <пользователь GHCR> <sha256 шаблона>` (выкатить образы с этим тегом из нашего реестра), `rollback` и `status`. Никаких файлов от CI скрипт не принимает: в stdin — одна строка с токеном GHCR для `docker pull`, всё после неё не читается (stdin сразу отключается).

Форма инфраструктуры — **шаблон релиза**, список файлов в `infra/deploy/template-files.txt`:

```
infra/deploy/release.sh          forced command (VM запускает копию из шаблона через симлинк bin/release.sh)
infra/deploy/restore.sh          восстановление БД
infra/deploy/template-files.txt  сам список
infra/deploy/template-hash.sh    хэш шаблона — одна реализация для release.yml, vm-install и release.sh
infra/docker-compose.prod.yml    сервисы, образы, тома, порты, лимиты
infra/postgres/db-init.sql       файл, на который compose ссылается относительно себя
```

Его ставит на VM только человек: `make vm-install-release` (`infra/deploy/vm-install.sh`) передаёт файлы по обычному ssh, атомарно подменяет `/srv/darumen/bin/template`, обновляет симлинки и сверяет хэш на VM с локальным. Хэш — `sh infra/deploy/template-hash.sh .`: sha256 от вывода `sha256sum` по файлам списка. `release.yml` считает его по чекауту тега и передаёт третьим аргументом; `release.sh` считает тот же хэш по `bin/template` и **до любых изменений** отказывает при расхождении: «шаблон на VM устарел — выполните make vm-install-release». Каждый релиз хранит снимок шаблона в `releases/<тег>/` — по нему же идёт откат.

**Правило выпуска.** Поменялся любой файл из списка (compose, SQL, `release.sh`, `restore.sh`, сам список) — сначала закоммитить, затем с чистого чекаута того же коммита `make vm-install-release`, затем тег. Незакоммиченные правки дадут другой хэш (`vm-install.sh` об этом предупреждает), и релиз тега будет отклонён. Если файлы шаблона не менялись, установленный шаблон подходит и следующим тегам. `make release-status` показывает хэш на VM, а локальный — `sh infra/deploy/template-hash.sh .`.

Что это даёт: утёкший ключ CI или изменённый workflow не может подменить compose (смонтировать `/srv/darumen` или `/`, вытащить `.env`, подключиться к сети POS, занять её порт) или переписать `release.sh` — всё это только через шаблон, который ставит человек. CI по-прежнему выбирает, какой код запускать: образы собираются из репозитория, и запись в репозиторий = выкатка кода на стенд (так устроен любой CD).

## Секреты и кто их задаёт

Секреты стенда живут в одном месте — `/srv/darumen/.env` на VM. CI получает только то, что нужно для выкатки и подписи; у нас в репозитории `BAITC-Hacks/hack-c2f58e92-icybeard` права write, поэтому секреты Actions добавляет **админ организации** (Settings → Secrets and variables → Actions → New repository secret). Без них workflow не падает: выкатка пропускается с notice, Android собирается демо-APK.

| Секрет Actions | Значение | Зачем |
| --- | --- | --- |
| `DEPLOY_SSH_KEY` | приватный ключ `darumen-ci` (ed25519, без пароля), целиком | вход на VM; на VM ключ ограничен forced command `release.sh` |
| `DEPLOY_HOST` | `icybeard@82.115.43.223` (VPS хакатона; для Hetzner было бы `deploy@195.201.7.56`) | куда выкатывать |
| `DEPLOY_KNOWN_HOSTS` | строка(и) `ssh-keyscan` VM, сверенные с отпечатком | защита от подмены хоста (`StrictHostKeyChecking=yes`) |
| `ANDROID_KEYSTORE_BASE64` | `base64 -i upload-keystore.jks` | ключ подписи релиза Android |
| `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | пароль хранилища, алиас, пароль ключа | то же |
| `GITHUB_TOKEN` | создаётся автоматически | push образов в GHCR (`packages: write`), на VM — только pull, живёт до конца джоба |

Ключ деплоя и декодированный keystore удаляются с раннера шагами `if: always()` в конце джоба.

| Переменная `.env` на VM | Кто задаёт | Замечание |
| --- | --- | --- |
| `POSTGRES_PASSWORD`, `KEYCLOAK_DB_PASSWORD` | лид | `KEYCLOAK_DB_PASSWORD` новая: без неё compose не стартует |
| `KEYCLOAK_ADMIN_PASSWORD` | лид | им же входит realm-sync; сменили пароль admin в консоли — поменяйте и в `.env` |
| `KEYCLOAK_ADMIN_CLIENT_SECRET` | лид | realm-sync применяет смену секрета к клиенту `darumen-admin`, api читает тот же |
| `SMTP_*`, `DEEPSEEK_API_KEY`, `LLM_PROVIDER`, `*_MODEL`, `PUBLIC_ORIGIN` | лид | как раньше |
| `BACKUP_*` | по умолчанию из compose | каталог, uid/gid, расписание, хранение |

Правка `.env` на VM без релиза: `ssh deploy@195.201.7.56`, отредактировать, затем `cd /srv/darumen && IMAGE_TAG=$(cat current/IMAGE_TAG) docker compose -p darumen -f current/infra/docker-compose.prod.yml --env-file .env up -d` (или выкатить тег заново).

## Разовая настройка VM

### VPS хакатона (цель govtech, стенд CD)

Выполняет человек команды с логином и паролем из `docs/IcyBeard-secrets.pdf`; CI этого сделать не может и не должен.

1. **Вход по ключу** (с ноутбука, пароль из PDF — один раз): `ssh-copy-id icybeard@82.115.43.223`, затем проверка `ssh icybeard@82.115.43.223 'id; docker version; docker compose version; free -m; df -h ~'`. Нужны Docker с плагином compose, доступные пользователю `icybeard`; если `docker ps` показывает контейнеры других команд, Docker общий — см. «Цели деплоя».
2. **Первый деплой с данными:** `make deploy` — кладёт код, витрины lakehouse и `infra/deploy/.env.govtech` в `/home/icybeard/darumen`, собирает образы на VPS и поднимает стек на `127.0.0.1:8014`. Проверка: https://icybeard.govtech-kz.com вместо заглушки «Приложение ещё не запущено».
3. **Шаблон релиза:** `make vm-install-release` (цель govtech по умолчанию) — `/home/icybeard/darumen/bin/template` и симлинки `bin/release.sh`, `bin/restore.sh`.
4. **Ключ CI** — как в шагах 4–8 ниже, но с путями VPS: в `~/.ssh/authorized_keys` пользователя `icybeard` строка `command="/home/icybeard/darumen/bin/release.sh",no-pty,no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-user-rc ssh-ed25519 AAAA… darumen-ci`; проверка `ssh -i ./darumen-ci icybeard@82.115.43.223 status`; known_hosts — `ssh-keyscan -t ed25519 82.115.43.223`, отпечаток сверить через `ssh icybeard@82.115.43.223 ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`.
5. **Секреты Actions** (админ организации): `DEPLOY_SSH_KEY` — приватный `darumen-ci`, `DEPLOY_HOST` — `icybeard@82.115.43.223`, `DEPLOY_KNOWN_HOSTS` — строка keyscan.

### Hetzner (цель jurek)

Выполняет человек с обычным ssh-доступом `deploy@195.201.7.56`; CI этого сделать не может и не должен.

1. **Секрет БД Keycloak.** `KEYCLOAK_DB_PASSWORD` уже добавлен в `infra/deploy/.env.prod`; на VM он попадёт в `/srv/darumen/.env` при ближайшем `make deploy` (или дописать руками).
2. **Права.** `.env` сейчас доступен на чтение другим пользователям VM: `ssh deploy@195.201.7.56 'chmod 600 /srv/darumen/.env; mkdir -p /srv/darumen/backups; chmod 750 /srv/darumen/backups'` (`make deploy` и `release.sh` дальше держат это сами, `release.sh status` предупреждает, если права ослабли).
3. **Шаблон релиза:** из чистого чекаута `make vm-install-release` — ставит `/srv/darumen/bin/template` и симлинки `bin/release.sh`, `bin/restore.sh`, печатает хэш. Повторять по правилу из «Граница доверия».
4. **Ключ CI** (на ноутбуке, во временном каталоге вне репозитория):
   ```bash
   ssh-keygen -t ed25519 -N '' -C darumen-ci -f ./darumen-ci
   ```
5. **Forced command.** Дописать открытый ключ в `~deploy/.ssh/authorized_keys` на VM одной строкой:
   ```
   command="/srv/darumen/bin/release.sh",no-pty,no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-user-rc ssh-ed25519 AAAA…(содержимое darumen-ci.pub) darumen-ci
   ```
   С этим ключом sshd всегда запускает `release.sh`, а запрошенную команду кладёт в `SSH_ORIGINAL_COMMAND`; скрипт принимает только `release`, `rollback`, `status`. Вместо перечня `no-*` можно написать `restrict,command="…"` (OpenSSH ≥ 7.2, на VM 9.6).
6. **Проверка ключа** (с ноутбука):
   ```bash
   ssh -i ./darumen-ci deploy@195.201.7.56 status      # хэш шаблона, current/previous, контейнеры, бэкапы
   ssh -i ./darumen-ci deploy@195.201.7.56 'ls /'      # usage и код 2 — shell ключу недоступен
   ```
7. **known_hosts:** `ssh-keyscan -t ed25519 195.201.7.56 > known_hosts.darumen` и сверить отпечаток с тем, что показывает сама VM: `ssh deploy@195.201.7.56 ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`.
8. **Передать админу организации** содержимое `darumen-ci` → `DEPLOY_SSH_KEY`, `deploy@195.201.7.56` → `DEPLOY_HOST`, `known_hosts.darumen` → `DEPLOY_KNOWN_HOSTS`; затем удалить `darumen-ci` с ноутбука. Отзыв ключа — удалить строку из `authorized_keys`.
9. **Android (по желанию):** создать upload-ключ (`keytool -genkeypair -keystore upload-keystore.jks -storetype PKCS12 -keyalg RSA -keysize 2048 -validity 10000 -alias upload`), хранить вне репозитория, передать админу `ANDROID_*`. Потеря ключа = новое приложение в Google Play, поэтому копия — в менеджере паролей. Локально ключ подключается через `apps/mobile/android/key.properties` (формат Flutter: `storeFile`, `storePassword`, `keyAlias`, `keyPassword`; файл и `*.jks` в `.gitignore`).
10. **Первый релиз с Keycloak на Postgres.** До него Keycloak работал в `start-dev` с БД внутри контейнера: пользователи, созданные на стенде, жили только до пересоздания контейнера. При переходе realm создаётся заново из файла (демо-пользователи с фиксированными `id`), поэтому перед первым релизом проверьте в консоли `https://dc.jurek.kz/auth/admin/` (realm darumen → Users), есть ли кто-то кроме демо, — таких нужно будет пригласить снова. Дальше пользователи, пароли, TOTP и сессии переживают любые релизы и пересоздания.
11. **GHCR.** Первый push создаёт пакеты `api`, `web`, `models`, `keycloak`, `keycloak-config` — приватные и привязанные к репозиторию через метку `org.opencontainers.image.source`, поэтому `GITHUB_TOKEN` репозитория их читает. Если push падает с `denied: installation not allowed to Create organization package`, админ организации разрешает создание пакетов из Actions (Organization settings → Packages).

На VM уже есть ключи `github-actions-pos-deploy*` — ключи POS без ограничений; ключ Darumen добавляется отдельной строкой и их не касается. Логин в GHCR `release.sh` делает во временном `DOCKER_CONFIG`, поэтому учётки POS в `~/.docker/config.json` не затираются.

## Выпуск релиза по тегу

```bash
# если с прошлого релиза менялись файлы из infra/deploy/template-files.txt:
make vm-install-release        # с чистого чекаута коммита, который будет помечен тегом
git tag -a v1.2.0 -m "Darumen 1.2.0"
git push origin v1.2.0         # origin = BAITC-Hacks/hack-c2f58e92-icybeard
```

Тег — `vX.Y.Z` или `vX.Y.Z-суффикс` (например `v1.2.0-rc.1`, релиз помечается как pre-release). Что происходит (Actions → release):

1. **ci** — тот же `ci.yml` (.NET, Python, веб с `npm run lint`, Flutter, интеграция с Kafka).
2. **images** — 5 образов параллельно (buildx, кэш слоёв в GitHub Actions cache), теги `vX.Y.Z` и `sha-<7 символов>`, только `linux/amd64`.
3. **deploy** (если есть `DEPLOY_*`) — считает хэш шаблона по чекауту тега и вызывает `release <тег> <actor> <хэш>`, в stdin — только токен GHCR. На VM `release.sh`: сверяет хэш с установленным шаблоном (не совпал — отказ, стенд не тронут) → снимок шаблона в `releases/<тег>` → `docker compose config` с `.env` VM → pull образов → дамп darumen и keycloak в `backups/last` → `up -d` (db-init, keycloak, realm-sync, остальные) → ждёт healthcheck сервисов и успешного realm-sync (до 7 минут) → smoke `127.0.0.1:<WEB_PORT из .env>` (`/health`, `/auth/realms/darumen`, `/api/v1/public/service-status`) → `current → releases/<тег>`, `previous →` прошлый. Любой сбой после `up` — автоматический откат на прежний `current` и красный джоб.
4. **smoke** — те же три адреса снаружи, через Caddy и TLS; сбой → `rollback` по ssh.
5. **android** — `flutter build appbundle` + `apk` с `--dart-define` `API_BASE=https://icybeard.govtech-kz.com`, `KEYCLOAK_URL=https://icybeard.govtech-kz.com/auth`, `WEB_BASE=https://icybeard.govtech-kz.com` (адрес стенда CD — `PUBLIC_URL` в release.yml); версия из тега, номер сборки — номер запуска workflow. Без `ANDROID_*` — только `darumen-<тег>-demo-debug-signed.apk` (ставится на устройства, но не для Google Play и не обновляется поверх подписанной сборки).
6. **github-release** — только для тегов, если образы и Android собрались, а выкатка и smoke прошли или пропущены: заметки GitHub (по PR и коммитам) + файлы APK/AAB.

Ручной запуск (Actions → release → Run workflow) на любой ветке: `deploy` — выкатывать ли (тег образов `sha-<коммит>`; хэш шаблона этой ветки тоже должен совпасть с установленным), `ios` — собрать iOS без подписи на macOS (минута macOS = 10 минут квоты). GitHub Release при ручном запуске не создаётся, сборки — в артефактах запуска (Android — 14 дней, iOS — 7).

Лог выкатки — в джобе deploy и на VM: `<стенд>/releases/<тег>/release.log`; состояние — `make release-status`.

## Откат

- **Автоматически:** `release.sh` откатывает сам, если после `up` сервисы не стали healthy, realm-sync упал или не прошёл smoke; джоб smoke откатывает, если стенд не отвечает снаружи.
- **Руками:** `make rollback` (то есть `ssh deploy@195.201.7.56 /srv/darumen/bin/release.sh rollback`) — поднимает `previous` по его снимку шаблона и меняет местами `current` и `previous`. Образы 5 последних релизов лежат на VM, реестр для отката не нужен.
- **Конкретная старая версия:** Actions → release → запуск нужного тега → Re-run all jobs. Если с того тега менялись файлы шаблона, релиз откажет по хэшу: сначала `git checkout <тег> && make vm-install-release`, затем перезапуск (и потом снова `make vm-install-release` с актуального коммита).
- **Данные откат не возвращает.** Если новая версия успела изменить схему БД, после отката восстановите дамп, снятый перед релизом: `make restore DB=darumen DUMP=last/darumen-<время релиза>.sql.gz` (список дампов — `ssh deploy@195.201.7.56 /srv/darumen/bin/restore.sh --list`).
- **Если не поднялся и откат** — вложенного восстановления нет намеренно (третий `up` поверх двух неудачных чаще вредит): `release.sh` пишет «ОТКАТ НЕ УДАЛСЯ», джоб красный, стенд в том состоянии, в каком его оставил откат. Дальше руками на VM: `/srv/darumen/bin/release.sh status`; логи `docker logs --tail=100 darumen-<сервис>-1`; поднять заведомо рабочий релиз — `cd /srv/darumen/releases/<тег> && IMAGE_TAG=<тег> LAKEHOUSE_DIR=/srv/darumen/lakehouse BACKUP_DIR=/srv/darumen/backups docker compose -p darumen -f infra/docker-compose.prod.yml --env-file /srv/darumen/.env up -d`; при повреждённых данных — `restore.sh` из дампа перед релизом; в крайнем случае `make deploy` с ноутбука.

Если CD-релизов ещё не было, `release.sh` откатывается на ручной деплой (`/srv/darumen/infra`, образы `local`).

## Данные (lakehouse)

Витрины не хранятся в git и есть только на машине разработчика:

```bash
make data && make train     # собрать gold, refdata, модели
make deploy-data            # rsync lakehouse/{gold,models,refdata,manifests} на VM + publish в Postgres
ssh deploy@195.201.7.56 docker restart darumen-models-1   # сервис моделей перечитает модели
```

`deploy-data` не трогает код, образы и `.env`; publish пересоздаёт таблицы gold/refdata, journal и intake не трогаются. Он берёт compose-файл и тег текущего CD-релиза (`current`), если он есть, иначе — ручного деплоя.

## Ручной деплой без CI

```bash
cp infra/deploy/.env.prod.example infra/deploy/.env.prod   # один раз, заполнить (файл в .gitignore)
make deploy                  # код + витрины + .env → сборка образов на VM (тег local) → up → realm-sync → publish → проверки
make deploy ARGS=--no-publish
```

`scripts/deploy.sh` делает rsync исходников (без данных, `node_modules`, `bin/obj`, каталогов CD и бэкапов) в `/srv/darumen`, кладёт `.env` (`chmod 600`), закрывает `backups/` от других пользователей, собирает образы на VM (`docker compose build --pull`), поднимает стек, ждёт realm-sync, публикует gold и refdata и проверяет `/health`, `/auth/realms/darumen`, `/api/v1/public/service-status`. Сборка на VM занимает ~10 минут и ~3 ГБ кэша (чистится до 2 ГБ). Шаблон CD (`bin/template`) ручной деплой не трогает — это отдельный шаг `make vm-install-release`. Ручной деплой оставляет отметку `/srv/darumen/MANUAL_DEPLOY` (видна в `release-status`); следующий CD-релиз её снимает, а при сбое откатывается на последний CD-релиз, а не на ручную сборку.

## Keycloak

**Прод.** Образ `infra/keycloak/Dockerfile`: Keycloak 26.0.8 (та же версия, что была на стенде), `kc.sh build` с `db=postgres`, health на management-порту 9000, `http-relative-path=/auth`, темы `darumen` внутри образа, запуск `start --optimized --import-realm`, кэш `local` (один узел). БД — `keycloak` в том же Postgres под своей ролью (`KEYCLOAK_DB_PASSWORD`, пул до 20 соединений). Прокси и имя хоста — как раньше: `KC_HOSTNAME=https://dc.jurek.kz/auth`, `KC_PROXY_HEADERS=xforwarded`, `KC_HTTP_ENABLED`, `KC_HOSTNAME_BACKCHANNEL_DYNAMIC` (api ходит за JWKS на `keycloak:8080`), heap до 512 МБ. Пользователи, пароли, TOTP, сессии и события хранятся в Postgres и переживают пересоздание контейнера; в дампы попадают вместе с darumen.

**Realm: первый старт и дальнейшие правки.** `--import-realm` импортирует `infra/keycloak/darumen-realm.json` только на пустую БД (существующий realm пропускается — «Realm 'darumen' already exists. Import skipped»). Дальнейшие правки realm применяет одноразовый **realm-sync** — [adorsys/keycloak-config-cli](https://github.com/adorsys/keycloak-config-cli) 6.5.1 (сборка под Keycloak 26.0.x) при каждом `up`, после healthy Keycloak:

- применяется: настройки realm (политики паролей, TOTP, сессии, SMTP), клиенты (в том числе смена секрета `darumen-admin`), роли, мапперы, профиль пользователя, демо-пользователи (атрибуты, добавление ролей); файл применяется каждый раз (`IMPORT_CACHE_ENABLED=false`), поэтому смена SMTP или секрета в `.env` доходит без правки файла;
- **никогда не удаляется** (`IMPORT_MANAGED_*=no-delete`, `IMPORT_USERS_MERGEROLES/MERGEGROUPS=true`, пользователей config-cli не удаляет вообще): пользователи вне файла, их пароли и TOTP, группы, роли и клиенты, созданные на стенде, роли, выданные демо-пользователям руками. Удалить что-то из realm можно только руками в консоли — удаление строки из файла на стенд не распространяется;
- **пароли демо-пользователей** в файле помечены `userLabel: "initial"`: задаются только при создании пользователя, поэтому смена пароля (например, `admin1`) на стенде не откатывается релизом. Вернуть демо-пароль — консоль → Users → Credentials → Reset password;
- **фиксированные `id`** у демо-пользователей и service account `darumen-admin` (UUIDv5 от имени): `sub` в токенах одинаков в dev и проде и после пересоздания realm, а на него завязаны данные API (`CurrentUser.UserId`). Если демо-пользователя удалить руками, realm-sync создаст его заново, но уже со случайным `id` (Admin API не принимает `id` при создании).

**realm-sync входит как администратор master-realm** (`admin` / `KEYCLOAK_ADMIN_PASSWORD`, созданный bootstrap при первом старте): это полный доступ ко всему Keycloak, и сменённый в консоли пароль без правки `.env` ломает релизы (config-cli ждёт 60 с и падает — и в релизе, и в откате). Следующий шаг — отдельный service account в realm darumen только с ролями `realm-management`, нужными для импорта; config-cli умеет входить им (`KEYCLOAK_GRANTTYPE=client_credentials`, `KEYCLOAK_CLIENTID`, `KEYCLOAK_CLIENTSECRET`, `KEYCLOAK_LOGINREALM=darumen`).

Проверено локально на копии прод-compose: пользователь, созданный через Admin API, смена пароля демо-пользователя и роль, созданная на стенде, пережили пересоздание контейнера Keycloak, повторный realm-sync, циклы релиз/откат и восстановление из дампа; вход демо-пользователя паролем через `darumen-mobile` работает; смена `KEYCLOAK_ADMIN_CLIENT_SECRET` и `SMTP_HOST` в `.env` применяется следующим realm-sync.

Логи: `docker logs darumen-realm-sync-1` (строка `keycloak-config-cli ran in …`, код выхода 0).

**Плейсхолдеры.** В realm-файле `${VAR:значение по умолчанию}` — синтаксис Keycloak: подставляется из переменных окружения при импорте (переменная окружения побеждает, без неё берётся значение после двоеточия; проверено на 26.0.8). У keycloak-config-cli синтаксис другой — `$(env:VAR:-по умолчанию)` (Apache Commons StringSubstitutor), поэтому при сборке образа realm-sync файл переводится скриптом `infra/keycloak/render-realm.sh` (только имена в верхнем регистре; ключи сообщений вроде `${username}` в профиле пользователя не трогаются; сборка падает, если плейсхолдер не перевёлся). Источник один — `darumen-realm.json`, генератора realm нет. Переменные подставляются одинаково в сервисы keycloak и realm-sync (якорь `x-realm-env` в compose). В теме `theme.properties` — `${env.VAR:по умолчанию}`.

| Переменная (keycloak, realm-sync) | Dev (`docker-compose.yml`) | Прод (`docker-compose.prod.yml`, из `.env`) |
| --- | --- | --- |
| `SMTP_HOST`, `SMTP_PORT` | `mailpit`, `1025` | обязательно задать хост; порт по умолчанию `587` |
| `SMTP_USER`, `SMTP_PASSWORD` | пусто | учётка SMTP |
| `SMTP_FROM` | `noreply@darumen.kz` | по умолчанию `noreply@darumen.kz` (имя отправителя «Darumen Health», Reply-To `help@darumen.kz`) |
| `SMTP_AUTH`, `SMTP_STARTTLS`, `SMTP_SSL` | `false` | по умолчанию `true`, `true`, `false`; `SMTP_SSL` для порта 587 не задавать (API читает его как `Mail__Smtp__EnableSsl`, по умолчанию `true`) |
| `KEYCLOAK_ADMIN_CLIENT_SECRET` | `darumen-admin-dev-secret` | обязательна, длинная случайная строка |
| `DARUMEN_WEB_URL` | `http://localhost:5173/` | `${PUBLIC_ORIGIN}/` — корень веба для ссылок «О системе» и «Зарегистрировать организацию» |

**Dev** не изменился: `quay.io/keycloak/keycloak:26.0`, `start-dev --import-realm`, realm и темы монтируются из `infra/keycloak` (правка шаблонов темы подхватывается без перезапуска, после правки realm — `docker compose -f infra/docker-compose.yml --env-file .env up -d --force-recreate keycloak mailpit`). В проде темы зашиты в образ и кэшируются: правка темы или realm выезжает новым тегом. Письма в dev ловит Mailpit: интерфейс http://localhost:8025, API `http://localhost:8025/api/v1/messages`.

Что в realm: роли `citizen`, `doctor`, `org_admin`, `regulator`, `steward`, `auditor`, `admin` (роли `chief` больше нет, `chief1` — `org_admin` с `mo_code=028B`); атрибуты `region_kato`, `mo_code`, `iin`, `specialty`, `position`, `via` объявлены в профиле пользователя: пишет и читает их только администратор через admin API (клиент `darumen-admin`), пользователь в личном кабинете видит только должность и специальность и изменить их не может; прочие атрибуты вне профиля — политика `ADMIN_EDIT` (без неё Keycloak 26 молча отбрасывает их при записи через admin API); политика паролей `length(12) and upperCase(1) and lowerCase(1) and digits(1) and notUsername and passwordHistory(5)`; защита от подбора — 5 попыток, блокировка 15 минут; TOTP 6 цифр / 30 с; сессия 30 минут без активности, «Запомнить на 30 дней» — 30 дней; офлайн-токены мобилки (`scope=offline_access`) — 30 дней; ссылка сброса пароля — 60 минут; события входа хранятся 30 дней. Демо-пароли `darumen` короче политики, поэтому в realm лежат их хэши (pbkdf2-sha512): политика проверяется только при смене пароля. Keycloak не выдаёт импортированным пользователям роли по умолчанию, поэтому у демо-пользователей явно указана `default-roles-darumen` (без неё офлайн-токены мобилки отклоняются с `not_allowed`).

**Служебный клиент `darumen-admin`** — confidential, только client credentials (service account), без входа пользователей; роли `realm-management`: `view-users`, `manage-users`, `query-users`, `view-events`, `view-realm`, `manage-realm`. Им пользуется только API (пользователи, роли, события входа). Проверка: `curl -s -d client_id=darumen-admin -d client_secret=$KEYCLOAK_ADMIN_CLIENT_SECRET -d grant_type=client_credentials $KC/realms/darumen/protocol/openid-connect/token`. API нужен тот же секрет (`Keycloak__Admin__ClientSecret` в сервисе api).

**Темы.** `login/` — страницы по доскам W-Auth-*: вход (eGov — пояснение «после интеграции», без имитации входа), «Забыли пароль» → «Проверьте почту», новый пароль со шкалой и правилами политики, «Пароль изменён», второй фактор (6 полей, вставка кода), настройка аутентификатора (QR и ключ), ошибки «Ссылка устарела», «Аккаунт заблокирован», «Сессия истекла», выход. `email/` — письма по доске W-Mail: смена пароля, действия администратора, подтверждение почты и уведомления безопасности (пароль или аутентификатор изменён, вход временно заблокирован). Уведомления шлёт слушатель событий `email`, список событий — `KC_SPI_EVENTS_LISTENER_EMAIL_INCLUDE_EVENTS` в compose (без `LOGIN_ERROR`, чтобы не писать на каждую опечатку). Время в письмах — по `TZ=Asia/Almaty`.

## Бэкапы и восстановление

Сервис `backup` ([prodrigestivill/postgres-backup-local](https://github.com/prodrigestivill/docker-postgres-backup-local), `17-debian-d257e5d`, закреплён по digest — pg_dump 17, как сервер) раз в сутки в полночь по Алматы делает `pg_dump` БД `darumen` и `keycloak` (все схемы, gzip) в `/srv/darumen/backups`:

- `last/<db>-YYYYMMDD-HHMMSS.sql.gz` — каждый дамп, хранится 7 дней (`BACKUP_KEEP_MINS`); сюда же `release.sh` кладёт дамп перед каждым релизом;
- `daily/` — 7 дней, `weekly/` — 4 недели, `monthly/` — 6 месяцев (жёсткие ссылки, место не удваивают);
- `<каталог>/<db>-latest.sql.gz` — ссылка на свежий.

**Права.** В дампах хэши паролей и секреты клиентов Keycloak, а VM общая, поэтому другие пользователи не имеют к ним доступа: контейнер пишет от `BACKUP_UID:BACKUP_GID` (`deploy`, 1000:1000) с `umask 0077` (обёртка `command` в compose; `docker exec` в `release.sh` и `make backup-now` задаёт тот же umask — exec его не наследует) — каталоги `0700`, файлы `0600`; `restore.sh` пишет `pre-restore/` с `umask 077` (`0700`/`0600`); `release.sh` перед каждым релизом и `make deploy` делают `chmod -R go-rwx backups`. Каталоги и файлы доступны только владельцу, как у `restore.sh`.

Дамп сейчас: `make backup-now`. Список: `ssh deploy@195.201.7.56 /srv/darumen/bin/restore.sh --list`.

Восстановление одной БД (`/srv/darumen/bin/restore.sh` — копия из шаблона):

```bash
make restore DB=keycloak                                   # из last/keycloak-latest.sql.gz
make restore DB=darumen DUMP=daily/darumen-20261001.sql.gz
```

Скрипт спрашивает подтверждение (ввести имя БД), снимает страховочный дамп текущей БД в `backups/pre-restore/`, останавливает только тех, кто пишет в эту БД (`keycloak` или `api` + `intake`), пересоздаёт БД (`DROP … WITH (FORCE)`, владелец `keycloak` или `darumen`), заливает дамп с `ON_ERROR_STOP` и запускает сервисы, дожидаясь healthcheck; при ошибке сервисы поднимаются обратно, а путь к страховочному дампу печатается. Проверено локально: круговой прогон darumen (с PostGIS, tiger, topology и схемами gold/journal) и keycloak — данные, появившиеся после дампа, исчезли, данные до дампа и вход пользователей вернулись.

**Копия вне VM — следующий шаг.** Сейчас дампы лежат на том же диске, что и база: гибель VM = потеря бэкапов. Кредов для внешнего хранилища нет, поэтому это не сделано. Рекомендация — Hetzner Storage Box (BX11, 1 ТБ, в том же ДЦ) и rclone по SFTP:

```bash
sudo apt install rclone                                      # на VM
rclone config create storagebox sftp host=uXXXXXX.your-storagebox.de port=23 user=uXXXXXX key_file=~/.ssh/storagebox
rclone sync /srv/darumen/backups storagebox:darumen-backups --create-empty-src-dirs   # проверить руками
( crontab -l; echo '30 1 * * * rclone sync /srv/darumen/backups storagebox:darumen-backups --log-file=/srv/darumen/backups/rclone.log' ) | crontab -
```

Для внешнего хранилища стоит включить шифрование (`rclone config` → remote типа `crypt` поверх `storagebox`). Раз в месяц — пробное восстановление из внешней копии на локальном стеке.

## Мониторинг

- **Healthcheck** у каждого долгоживущего сервиса (таблица выше); `release.sh` и `make release-status` показывают состояние, `docker ps` на VM — `(healthy)`/`(unhealthy)`. Автоперезапуск упавших — `restart: unless-stopped`.
- **uptime.yml** — раз в час (`17 * * * *`) и вручную: `/health`, `/auth/realms/darumen`, `/api/v1/public/service-status` снаружи, три попытки. Упавший прогон GitHub присылает письмом (подписка: Settings → Notifications → Actions → «Send notifications for failed workflows only»). Расписание работает только из ветки по умолчанию.
- **Стоимость:** каждый прогон — 1 оплачиваемая минута, ≈ 720 минут в месяц (36 % квоты). Если минут не хватает — `17 */3 * * *` (≈ 240 минут) или бесплатный внешний монитор (UptimeRobot, Better Stack: те же три адреса раз в 5 минут, почта/Telegram) и отключение `uptime.yml`.
- **Логи:** ротация 10 МБ × 3 на контейнер; `ssh deploy@195.201.7.56 'docker logs --tail=100 darumen-api-1'`.
- **Диск:** `release.sh` после релиза удаляет образы релизов старше 5 последних, висячие образы и кэш сборки сверх 2 ГБ; `make release-status` показывает `df -h`.

## Минуты GitHub Actions

Приватный репозиторий организации на бесплатном плане — ~2000 минут в месяц; Linux-минута = 1, macOS = 10, каждая джоба округляется вверх до минуты.

| Что | Минут за прогон | Замечание |
| --- | --- | --- |
| `ci.yml` (push в main, PR) | ≈ 10 | 5 параллельных джоб; правки только `docs/**` и `*.md` CI не запускают; новый push в PR отменяет старый прогон |
| `release.yml` по тегу | ≈ 35–45 | CI ≈ 10 + образы ≈ 12–15 (холодный кэш дольше) + Android ≈ 8–10 + выкатка, smoke, релиз ≈ 4 |
| `release.yml` с `ios=true` | + ≈ 100 | ~10 минут macOS × 10 |
| `uptime.yml` | ≈ 720 в месяц | см. «Мониторинг» |

Бюджет: 720 (uptime) + 10 релизов × 40 + ~80 прогонов CI × 10 ≈ 1900. Минуты кончаются — первым делом реже uptime. Хранилище: артефакты Android живут 14 дней (к GitHub Release файлы прикреплены отдельно), образы GHCR сейчас бесплатны («Container image storage and bandwidth for the Container registry is currently free», GitHub обещает предупредить за месяц); старые версии пакетов можно удалять в настройках пакета. Если CI станет обязательной проверкой PR (branch protection), `paths-ignore` придётся убрать: пропущенный по путям прогон не отчитывается. Сторонние действия `subosito/flutter-action` и `softprops/action-gh-release` закреплены по SHA коммита (версия — в комментарии).

## Проверка и отладка

```bash
make release-status
ssh deploy@195.201.7.56 'cd /srv/darumen && IMAGE_TAG=$(cat current/IMAGE_TAG) docker compose -p darumen -f current/infra/docker-compose.prod.yml --env-file .env ps'
ssh deploy@195.201.7.56 'docker logs --tail=100 darumen-keycloak-1; docker logs darumen-realm-sync-1 | tail -5'
curl -s https://dc.jurek.kz/api/v1/                        # {"name":"Darumen Health","version":...}
curl -s https://dc.jurek.kz/api/v1/public/service-status   # почта, push, SMS, eGov
curl -s https://dc.jurek.kz/auth/realms/darumen | jq .realm   # "darumen" — Keycloak за nginx отвечает
```

Старый стек GovTech Camp останавливался `make deploy ARGS=--replace-dc` через `docker compose down` без `-v`: его тома (`govtech-camp_pgdata`, `govtech-camp_uploads`) остаются, удалить руками `docker volume rm`.
