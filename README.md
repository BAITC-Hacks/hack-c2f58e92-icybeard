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
| [docs/data-intake.md](docs/data-intake.md) | Data Intake Fabric: слепая загрузка файлов, контракты наборов, парсеры и нормализаторы, правила качества, карантин, консоль стюарда |
| [docs/mobile-and-doctor.md](docs/mobile-and-doctor.md) | Мобильные приложения для гражданина, врача и руководителя; ведение маршрута пациента врачом вместо медкарты, границы и что для этого нужно |
| [docs/doctor-consult.md](docs/doctor-consult.md) | Сценарий приёма: AI‑скрайб с утверждением врачом, памятка пациенту, проверка рецепта на покрытие ОСМС и доступность в аптеках |
| [docs/implementation-plan.md](docs/implementation-plan.md) | Детальный план на четыре недели: вехи, задачи по дням с владельцами и условиями готовности, зависимости, линии отсечения, риски по неделям |
| [docs/tech-stack.md](docs/tech-stack.md) | Решения по стеку: .NET 10, Kafka, PostgreSQL, ClickHouse с Cube, Vue 3, Flutter, Python для данных и моделей; структура монорепо |
| [docs/gold-schemas.md](docs/gold-schemas.md) | Схемы silver, refdata и gold: колонки, типы, ключи, партиции, проверки качества |
| [docs/api.md](docs/api.md) | REST API v1: соглашения, эндпоинты по доменам с примерами запросов и ответов |
| [docs/data-requests.md](docs/data-requests.md) | Что из данных есть, чего не хватает, приоритетный запрос организаторам, открытые источники, черновик письма |
| [docs/tz.md](docs/tz.md) | Техническое задание программы (текст организаторов) |

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

## Запуск

```bash
make venv     # Python-окружение для ml/
make serve    # инфраструктура: Postgres, ClickHouse, Cube, Kafka, Schema Registry, Valkey, MinIO, Keycloak, MLflow
make build    # .NET и веб
make test     # тесты .NET, Python и веб
```

API: `dotnet run --project src/Darumen.Api`, документация на `/scalar`, здоровье на `/health`. Веб: `cd apps/web && npm run dev`. Мобильный клиент: `cd apps/mobile && flutter run`.

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
ml/.venv/bin/python -m darumen.models.train --only simulate,index   # одна часть
```

Карточки моделей в `docs/model-cards/` и `docs/access-index.md` генерируются командой `make train`, руками их не правят. Результаты лежат в `lakehouse/models/` и `lakehouse/gold/` (прогнозы, аномалии, индекс, перераспределение), метрики в MLflow.

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
