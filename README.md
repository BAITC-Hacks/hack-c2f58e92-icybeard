# Darumen Health · GovTech Camp 2026, Кейс 1

Экосистема прогноза нагрузки на стационары и маршрутизации пациентов на данных МЗ РК. Одно ML‑ядро (прогноз рядов, аномалии, скоринг ожидания и риска, объяснимость), несколько потоков данных (плановая госпитализация, приёмные покои, стационары, лаборатории, вакцинация, онкология), три интерфейса (гражданин, врач ПМСП, регулятор).

Статус: данные загружены в локальный lakehouse, модели ядра обучены и проходят оценку против baseline (`make eval`), идёт API и интерфейсы. См. [бриф для команды](docs/team-brief.md).

## Линейки продукта

- **Darumen Gov**: ситуационный центр регулятора и главврача, ядро Кейса 1.
- **Darumen Care**: врачи и клиники, ожидание госпитализации и маршрутизация; режим врача с ведением маршрута пациента. Мобильные клиенты на Flutter.
- **Darumen Lab**: доступ к диагностике и нагрузка лабораторий.
- **Darumen Med**: доступность бесплатных лекарств, проверка рецепта на покрытие ОСМС и где получить, дефицит по регионам.
- **Darumen Family**: вакцинация, скрининги, профосмотры, новорождённые.
- **Darumen AI**: ассистент навигации поверх всех линеек и AI‑скрайб приёма с утверждением врачом, без диагнозов.

Подробное соответствие линеек доменам и данным: [docs/architecture.md](docs/architecture.md).

## Документы

| Файл | Что внутри |
|---|---|
| [docs/team-brief.md](docs/team-brief.md) | Контекст, идея, красные линии ТЗ, факты по данным, решения по моделям, план, открытые вопросы |
| [docs/data-catalog.md](docs/data-catalog.md) | Все наборы данных: идентификаторы на портале, колонки, покрытие, ключи соединения, ловушки, проверка целостности |
| [docs/architecture.md](docs/architecture.md) | Целевая архитектура платформы: принципы, роли, домены, потоки как декларации, слои lakehouse и ML, безопасность, масштабирование, путь от кэмпа к национальному масштабу |
| [docs/system-structure.md](docs/system-structure.md) | Структура системы: кому что показывать по ролям, где ML и где AI, оценка правильности и точности обучения по каждой модели, аккредитованные источники других стран для пробелов в данных, план изменений |
| [docs/data-intake.md](docs/data-intake.md) | Data Intake Fabric: слепая загрузка файлов, контракты наборов, парсеры и нормализаторы, правила качества, карантин, консоль стюарда |
| [docs/mobile-and-doctor.md](docs/mobile-and-doctor.md) | Мобильные приложения для гражданина, врача и руководителя; ведение маршрута пациента врачом вместо медкарты, границы и что для этого нужно |
| [docs/doctor-consult.md](docs/doctor-consult.md) | Сценарий приёма: AI‑скрайб с утверждением врачом, памятка пациенту, проверка рецепта на покрытие ОСМС и доступность в аптеках |
| [docs/implementation-plan.md](docs/implementation-plan.md) | Детальный план на четыре недели: вехи, задачи по дням с владельцами и условиями готовности, зависимости, линии отсечения, риски по неделям |
| [docs/tech-stack.md](docs/tech-stack.md) | Решения по стеку: .NET 10, Kafka, PostgreSQL, ClickHouse с Cube, Vue 3, Flutter, Python для данных и моделей; структура монорепо |
| [docs/gold-schemas.md](docs/gold-schemas.md) | Схемы silver, refdata и gold: колонки, типы, ключи, партиции, проверки качества |
| [docs/api.md](docs/api.md) | REST API v1: соглашения, эндпоинты по доменам с примерами запросов и ответов |
| [docs/data-requests.md](docs/data-requests.md) | Что из данных есть, чего не хватает, приоритетный запрос организаторам, открытые источники, черновик письма |
| [docs/tz.md](docs/tz.md) | Техническое задание программы (текст организаторов) |
| [docs/demo-pages.md](docs/demo-pages.md) | Что есть на каждой странице стенда и что показывать |
| [docs/criteria-map.md](docs/criteria-map.md) | Соответствие страниц и моделей критериям ТЗ и жюри, что закрыть до защиты |
| [docs/rbac.md](docs/rbac.md) | Роли, 14 разрешений, scope «своя организация», эндпоинты администрирования и аккаунта |
| [docs/deploy.md](docs/deploy.md) | Публичный стенд dc.jurek.kz: CD по тегу (GHCR, forced-command SSH, откат), продовый compose, Keycloak на Postgres, бэкапы и восстановление, секреты, минуты Actions |

## Данные

Источник: портал открытых данных [ashyq.data.gov.kz](https://ashyq.data.gov.kz), публикация МЗ РК от 6 сентября 2026. Данные в репозиторий не входят (около 60 ГБ), они лежат локально в `DataSets/<название набора>/<оригинальное имя файла>.csv`.

```bash
# список наборов и их идентификаторов
python3 scripts/download_datasets.py --list

# скачать и проверить (один экземпляр на папку, битые части перекачиваются)
python3 scripts/download_datasets.py referrals waiting refusals treated_count --workers 4

# только проверить целостность уже скачанного
python3 scripts/download_datasets.py --verify-only referrals waiting refusals
```

Профилирование базовых наборов (нужен `duckdb`: `pip install duckdb`):

```bash
python3 scripts/profile_datasets.py DataSets
```

## Ключевые факты по данным

- Направления, ожидающие и отказы приёмного покоя покрывают только I квартал 2025 по всем 20 регионам. Многолетняя динамика есть в «Списке пролеченных случаев» (2011–2026, 42 ГБ).
- «Ожидающие» это та же когорта, что и направления, а не снимок живой очереди: составной ключ соединяется на 99,5 %.
- Ожидание считать по календарным дням: факт госпитализации часто проставлен как 08:00 того же дня.
- Дневной стационар (профиль `DH`) это 48 % направлений с нулевым ожиданием, его выделять отдельно.
- Никогда не запускать два загрузчика в одну папку одновременно.

## Запуск в Docker

Весь стек поднимается контейнерами, на хосте остаётся только Ollama (Docker Desktop на macOS не даёт контейнерам GPU; на Linux с NVIDIA есть профиль `ollama`).

```bash
cp .env.example .env               # адреса и режимы, значения по умолчанию подходят для ноутбука
ollama pull qwen3.8:27b && make ollama-model   # локальная модель с контекстом 16k (один раз)
make serve                         # инфраструктура: Postgres, ClickHouse, Cube, Kafka, Schema Registry, Valkey, MinIO, Keycloak, Mailpit, MLflow
make pipeline                      # данные в контейнере: intake → refdata → gold → train → publish (DataSets и lakehouse монтируются с хоста)
make up                            # API :8000, сервис моделей :50051, скрайб :8010, веб :3000
```

Веб на `http://localhost:3000`: кнопка «Войти» ведёт в Keycloak, демо-пользователи с паролем `darumen`: `regulator1`, `chief1` (администратор организации), `doctor1`, `steward1`, `auditor1`, `citizen1`, `admin1`; без входа открыта только страница входа (и памятка пациенту по QR). Письма Keycloak (сброс пароля, уведомления безопасности) в dev ловит Mailpit — http://localhost:8025; тема входа и писем, SMTP и служебный клиент `darumen-admin` — [docs/deploy.md](docs/deploy.md#keycloak). API без Keycloak (заголовки `X-Actor`/`X-Role`/`X-Region`, только для тестов и отладки через `/scalar`): `API_AUTH_MODE=headers` в `.env`, затем `make up`; веб и мобильное приложение входят только через Keycloak. API за nginx веба и напрямую на `:8000` (`/scalar`). Логи: `make logs`, остановка: `make down`. Образы: `infra/api.Dockerfile`, `infra/models.Dockerfile` (модели, скрайб, конвейер), `infra/web.Dockerfile`.

## Запуск для разработки (без Docker для приложения)

```bash
make venv     # Python-окружение для ml/
make serve    # инфраструктура: Postgres, ClickHouse, Cube, Kafka, Schema Registry, Valkey, MinIO, Keycloak, Mailpit, MLflow
make build    # .NET и веб
make test     # тесты .NET, Python и веб
```

На macOS с Apple Silicon сборке .NET нужны нативные `protoc` и `grpc_csharp_plugin` (`brew install protobuf grpc`): пакет Grpc.Tools везёт для macOS только x64-бинарник, который без Rosetta не запускается («Bad CPU type in executable»). `make build` и `make test` подставляют их сами; при прямом вызове `dotnet` экспортируйте `PROTOBUF_PROTOC=/opt/homebrew/bin/protoc GRPC_PROTOC_PLUGIN=/opt/homebrew/bin/grpc_csharp_plugin`.

API: `dotnet run --project src/Darumen.Api` (порт по умолчанию из launchSettings, в compose 8000), документация на `/scalar`, здоровье на `/health`. Перед первым запросом: `make serve`, `make publish` (витрины в Postgres и ClickHouse) и `make models-serve` (gRPC-сервисы моделей на :50051, адрес в `ModelServices:Address`). Миграции журнала применяются при старте API (`Database:MigrateOnStartup`), схему ведёт EF Core в `src/Darumen.Migrations` (`dotnet dotnet-ef migrations add <Name> --project src/Darumen.Migrations --startup-project src/Darumen.Migrations -o Migrations`). Без Postgres или сервиса моделей API отвечает problem+json 503, а не падает. Веб (`apps/web`, Vue 3 + Vite + PrimeVue 4): `npm run dev` на :5173 с прокси `/api` на :8000; вход через Keycloak (PKCE, `VITE_KEYCLOAK_*` в `apps/web/.env.example`), кнопка «Войти через eGov mobile» показывает, что вход через eGov недоступен — адрес сервиса Smart Bridge не предоставлен (статус из `GET /api/v1/public/service-status`, `docs/egov-auth.md`), публичные страницы открыты без входа. Экраны: карта регионов с индексом и сигналами, регион с очередью организации и прогнозом, симулятор, ассистент направления, рабочий список, журнал решений, консоль стюарда, публичная страница ожидания. `npm run walk` прогоняет все экраны в браузере и складывает скриншоты в `e2e/shots`. `npm run deep-link` проверяет прямую ссылку на защищённую страницу после входа через Keycloak (веб на :3000). Мобильный клиент (Flutter, `apps/mobile`, подробности в `apps/mobile/README.md`): `cd apps/mobile && flutter run --dart-define=API_BASE=http://10.0.2.2:8000 --dart-define=KEYCLOAK_URL=http://10.0.2.2:8080` (без define — адреса локального стека). Две роли по образцу NHS App: гражданин — Главная с карточкой «Моя госпитализация», Мой путь (стадии Стандарта, прогноз, чек-лист анализов, где быстрее, решения врача, история), Сколько ждут, Лекарства, Вакцинация, Уведомления, Профиль; врач — Пациенты → маршрут пациента с перенаправлением → ассистент направления, Скрайб (печатная стенограмма → черновик по разделам «AI‑черновик» → утверждение → памятка), Профиль. Вход — Keycloak (`citizen1`/`doctor1`, пароль `darumen`), кнопка «Войти через eGov mobile» видна, но вторична и подписана «сервис недоступен»: адрес сервиса eGov mobile (Smart Bridge) не предоставлен (`docs/egov-auth.md`). Гостевого режима нет: без входа открыт только экран входа. Переключатель RU/KK в профиле локализует интерфейс (`lib/l10n/strings.dart`), системные виджеты и заголовок `Accept-Language`. Тема светлая/тёмная из одних токенов (`lib/theme`), шрифт Onest. `flutter analyze && flutter test` — на машине с Flutter SDK.

Модули монолита (`src/Darumen.Modules/*`, каждый реализует `IDarumenModule`): Queue (ожидание, отказ, альтернативы, ряд организации), Analytics (потоки, прогноз с историей, аномалии с подтверждением, индекс доступности), Simulation (сценарии и перераспределение), Journal (решения человека с Idempotency-Key), RefData (регионы, организации, профили), Intake (партии загрузки из событий Kafka). Контракт: [docs/api.md](docs/api.md).

События: Wolverine с durable outbox и inbox в Postgres (схема `wolverine`) и транспортом Kafka; сообщения из `proto/darumen/v1/events.proto` идут в формате Confluent Schema Registry (субъект `<топик>-value`, совместимость BACKWARD), поэтому Python-клиенты читают и пишут те же байты. Решения и подтверждения сигналов пишутся вместе с событием `darumen.decision.recorded` в одной транзакции; Data Intake Fabric публикует `darumen.intake.batch.loaded` (`darumen.intake add` при заданных `KAFKA_BOOTSTRAP` и `SCHEMA_REGISTRY_URL`), API принимает его в `intake.batches`. Неудачные обработки уходят в `<топик>.dlq` после повторов. Режим `Messaging:Mode=stub` отключает внешние транспорты (тесты, разработка без compose). Сквозной тест: `DARUMEN_KAFKA_TEST=1 dotnet test --filter KafkaIntegrationTests` при запущенном `make serve`; посмотреть поток: `ml/.venv/bin/python -m darumen.intake.events tail --topic darumen.decision.recorded`.

Слепая загрузка данных (Data Intake Fabric, см. [docs/data-intake.md](docs/data-intake.md)):

```bash
make data                                                        # проверить скачанное и загрузить всю папку DataSets
ml/.venv/bin/python -m darumen.intake add "DataSets/<набор>"      # один набор или один файл
ml/.venv/bin/python -m darumen.intake inspect <file.csv>          # отпечаток файла и подбор контракта
make intake-status                                               # манифесты загрузок
```

Файл с известной схемой проходит в `lakehouse/bronze` и `lakehouse/silver` (Parquet, партиции по региону и месяцу) с манифестом и карантином; файл с неизвестной схемой получает черновик контракта в `lakehouse/drafts/` для стюарда.

Модели (см. [docs/model-cards/](docs/model-cards/) и [docs/access-index.md](docs/access-index.md)):

```bash
make train    # ожидание и отказ (LightGBM), прогнозы и аномалии по потокам streams/*.yaml, симулятор очереди, индекс доступности
make eval     # оценка против baseline на отложенных выборках; падает, если модель хуже baseline
make publish  # витрины gold и refdata в Postgres (таблицы API) и ClickHouse (ряды для графиков), идемпотентно
ml/.venv/bin/python -m darumen.models.train --only simulate,index   # одна часть
```

Сервисы моделей по gRPC (контракты в `proto/darumen/v1`, код генерируется в `ml/src/darumen/v1` командой `make proto`):

```bash
make models-serve                                    # QueueIntelligence и LoadForecasting на :50051, health и reflection включены
grpcurl -plaintext localhost:50051 list              # проверить
```

Карточки моделей в `docs/model-cards/` и `docs/access-index.md` генерируются командой `make train`, руками их не правят. Переобучить один поток: `ml/.venv/bin/python -m darumen.models.train --only forecast,anomaly --streams rx_weekly` (результат сливается в общие таблицы прогнозов и аномалий). Линия активов в Dagster: `make dagster` (silver → refdata → gold → models → published).

AI-скрайб (демо, [docs/doctor-consult.md](docs/doctor-consult.md)): `make scribe-serve` поднимает FastAPI на :8010, API проксирует его через YARP под `/api/v1/scribe/*` (политика doctor, памятки публичны по токену). Стенограмма: faster-whisper (`make venv-scribe`, модель скачивается при первом запросе) или напечатанный текст; черновик записи по разделам: локальная модель в Ollama (`ollama pull qwen3.8:27b`, затем `make ollama-model` создаёт `darumen-qwen3.8:27b` с контекстом 16k, иначе KV-кэш на 128k токенов не помещается в память ноутбука; 18 ГБ на GPU), провайдер меняется переменной `DARUMEN_LLM_PROVIDER` (ollama, deepseek, openai), иначе правила по ключевым словам. Аудио удаляется при утверждении записи врачом. Графики: Cube над ClickHouse (`infra/cube`, dev-режим на :4000, `GET /cubejs-api/v1/meta`). Результаты лежат в `lakehouse/models/` и `lakehouse/gold/` (прогнозы, аномалии, индекс, перераспределение), метрики в MLflow.

## Структура

```
src/        решение .NET 10: Darumen.Api, Darumen.Shared, Darumen.Contracts, Darumen.Modules/*, Darumen.Migrations
tests/      Darumen.Tests (xunit)
ml/         Python: intake, lakehouse, features, models, сервисы моделей (src/darumen), tests/
apps/web/   Vue 3 + Vite + PrimeVue
apps/mobile/ Flutter
proto/      контракты gRPC и событий Kafka
contracts/  контракты наборов данных (YAML)
streams/    декларации потоков (YAML)
infra/      docker-compose, Dockerfile API, init Postgres
scripts/    загрузка, проверка и профилирование данных
docs/       документация проекта
DataSets/   локальные данные (в .gitignore)
```

Целевая раскладка монорепо (`src/` .NET, `ml/` Python, `apps/web` Vue, `apps/mobile` Flutter) описана в [docs/tech-stack.md](docs/tech-stack.md).
