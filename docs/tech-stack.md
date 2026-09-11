# Решения по технологическому стеку

Зафиксировано командой 10 сентября 2026. Принцип полиглота: **.NET владеет доменами, API, Kafka и Postgres; Python владеет загрузкой данных, витринами и моделями.** Граница между ними: контракты gRPC в `proto/`, события Kafka в Protobuf, витрины в ClickHouse и Postgres.

## Сервисы продукта (.NET 10)

| Решение | Выбор | Примечание |
|---|---|---|
| Форма кода | Модульный монолит, границы по доменам из архитектуры | Разнос по контейнерам на пилоте без переписывания |
| Внутренняя архитектура | Clean Architecture: Domain, Application, Infrastructure, Presentation в каждом модуле | Presentation отправляет команду в Wolverine, обработчик в Application выполняет use case, доменные события уходят в outbox в той же транзакции; модули общаются только через события и Application‑контракты |
| Медиатор и шина сообщений | Wolverine (JasperFx, MIT) | Один пакет закрывает медиатор, транзакционный outbox в Postgres, транспорт Kafka, локальные очереди и отложенные сообщения. MediatR отклонён из‑за коммерческой лицензии с 13‑й версии |
| Доступ к данным | Dapper | Чтение витрин и запись OLTP простым SQL |
| Миграции | EF Core Migrations | EF только для схемы, не для запросов |
| OpenAPI | Встроенный `Microsoft.AspNetCore.OpenApi` + Scalar UI | |
| Протоколы | REST для веб и мобильных клиентов, gRPC к модельным сервисам на Python | Контракты в `proto/` |
| Фоновые задания | Quartz.NET | Cron‑задачи: пересчёты, рассылки, отчёты. Публикацию outbox делает Wolverine |
| Шлюз и BFF | YARP | Один вход для Vue и Flutter, агрегация экранов |
| Локальная оркестрация | Docker Compose как источник истины для всех сервисов; .NET Aspire опционально для цикла разработки .NET | Python‑сервисы, ClickHouse, Cube, Kafka и Keycloak живут в Compose |

## События (Kafka)

| Решение | Выбор |
|---|---|
| Брокер | Apache Kafka |
| Сериализация | Protobuf + Confluent Schema Registry, субъекты `<topic>-value`. Готовой интеграции Schema Registry в Wolverine нет: пишем свой `IMessageSerializer` поверх сериализаторов Confluent, задача T0.11 |
| Клиент .NET | Транспорт Kafka в Wolverine поверх Confluent.Kafka |
| Надёжность | Durable outbox и inbox Wolverine в Postgres (сообщение сохраняется в той же транзакции, что и данные); dead‑letter топик на каждый основной; идемпотентные потребители по `event_id` |
| Топики | `intake.batch.loaded`, `stream.updated`, `model.deployed`, `anomaly.detected`, `decision.recorded`, `notification.requested` |

## Данные

| Решение | Выбор | Роль |
|---|---|---|
| PostgreSQL 17 | PostGIS, pg_trgm, pgvector, pg_partman | OLTP: журнал решений, пользователи, метаданные intake, справочники, outbox |
| ClickHouse | С семантическим слоем Cube | Витрины gold, ряды потоков, аналитика для Gov; Cube отдаёт метрики и графики Vue через единый API |
| Valkey | | Кэш ответов моделей и online‑признаки |
| MinIO | | Landing, Parquet, артефакты моделей, временное аудио |
| Parquet + DuckDB | На стороне Python | Подготовка данных, признаки, обучение |

## Веб (Vue)

| Решение | Выбор |
|---|---|
| Каркас | Vue 3 + Vite + TypeScript, SPA, без Nuxt |
| Состояние | Pinia |
| UI‑набор | PrimeVue 4 (MIT; версия 5 показывает плашку «Invalid PrimeUI License» и требует лицензию, поэтому закреплена ветка 4.x) |
| Графики и карта | vue‑echarts, MapLibre GL |
| Формы | VeeValidate + zod |
| i18n | vue‑i18n, казахский и русский |
| Тесты | Vitest, Playwright |

## Мобильные клиенты

Flutter, клиент API генерируется из OpenAPI, push через FCM и APNs, OIDC с PKCE. Подробно в [mobile-and-doctor.md](mobile-and-doctor.md).

## Python и ML

| Решение | Выбор |
|---|---|
| Оркестрация данных и обучения | Dagster |
| Загрузка данных | Intake Fabric на Python: DuckDB, pyarrow, контракты YAML |
| Модели | LightGBM, statsforecast, SHAP, OR‑Tools |
| Сервисы моделей | FastAPI + gRPC по контрактам из `proto/`; батч‑скоринг пишет в ClickHouse и Postgres |
| Реестр моделей | MLflow, карточки моделей; .NET читает метаданные через REST |
| Хранилище признаков | Витрины в ClickHouse и Postgres плюс Valkey, без Feast на кэмпе |
| Скрайб | faster‑whisper на CTranslate2, потоковая передача по WebSocket |
| LLM | DeepSeek по умолчанию через OpenAI-совместимый клиент (`Microsoft.Extensions.AI.OpenAI`), Anthropic SDK как альтернативный провайдер для C# через `Microsoft.Extensions.AI` в модуле Insight, Ollama как запасной вариант |

## Сквозные

| Решение | Выбор |
|---|---|
| Аутентификация | Keycloak, OIDC с PKCE; NCALayer для ЭЦП на пилоте; eGov для граждан на следующем этапе |
| Наблюдаемость | OpenTelemetry, Prometheus, Grafana, Loki; Serilog |
| Отчёты | QuestPDF, ClosedXML |
| Тесты .NET | xUnit, Testcontainers для Postgres и Kafka, k6 |
| Секреты и флаги | user‑secrets локально, Vault на пилоте; OpenFeature |
| CI/CD | GitHub Actions, контейнеры, Docker Compose на кэмпе, Kubernetes на пилоте |

## Структура репозитория

```
src/                        решение .NET 10, модульный монолит
  Darumen.Api/              хост, YARP, OpenAPI, подключение модулей
  Darumen.Modules/          Queue, Forecast, Anomaly, Simulation, Index, Insight,
                            Journal, Notifications, Intake, RefData, Medicines, Scribe;
                            в каждом Domain / Application / Infrastructure / Presentation
  Darumen.Shared/           Wolverine (outbox, Kafka), Dapper, аутентификация, наблюдаемость
  Darumen.Migrations/       миграции EF Core
  Darumen.Tests/            xUnit, Testcontainers
ml/                         Python: intake, lakehouse (Dagster), features, models,
                            model services (gRPC), scribe
apps/web/                   Vue 3
apps/mobile/                Flutter
proto/                      контракты gRPC и событий Kafka
contracts/                  контракты наборов данных (YAML)
streams/                    декларации потоков (YAML)
refdata/                    справочники и правила сопоставления
infra/                      docker-compose, clickhouse, cube, keycloak, k8s
docs/
```
