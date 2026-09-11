# Состояние проекта Darumen Health

Обновлено 11 сентября 2026. Ветка `main`, репозиторий `icybeard/gov-tech-camp-case`. План работ: [implementation-plan.md](implementation-plan.md).

## Что работает сквозь стек

| Слой | Что сделано | Как проверить |
|---|---|---|
| Данные | 15 наборов МЗ РК скачаны и загружены через контракты (`contracts/*.yaml`) в bronze/silver/quarantine с манифестами; 3 набора по рецептам (~285 млн строк) и справочник спецификаций (41 млн) | `make data`, `make intake-status` |
| Справочники и витрины | регионы, профили коек, реестр 1 406 организаций; витрины `queue_daily`, `throughput_4w`, `features_wait`, `er_visits_daily`, `admissions_monthly`, `vac_monthly`, `rx_weekly`, `rx_nosology_monthly`, `rx_mnn`, `drug_programs`, `access_index` | `make refdata`, `make gold` |
| Модели | ожидание и отказ (LightGBM, квантили), прогнозы потоков (AutoETS против сезонного наива), аномалии (робастный z), симулятор очереди с перераспределением, индекс доступности; карточки в `docs/model-cards/` | `make train`, `make eval` |
| Сервисы моделей | gRPC (QueueIntelligence, LoadForecasting, Simulation) с health и reflection, контракты в `proto/` | `make models-serve`, `grpcurl -plaintext localhost:50051 list` |
| API | .NET 10 модульный монолит: Queue, Analytics, Simulation, Journal, RefData, Intake, Medicines, Insight; Keycloak или режим заголовков; аудит; Wolverine outbox/inbox и Kafka с Protobuf через Schema Registry; YARP к скрайбу | `dotnet run --project src/Darumen.Api`, `/scalar` |
| Публикация | Postgres (таблицы API) и ClickHouse (ряды) из Parquet; Cube над ClickHouse | `make publish`, `make serve` |
| Веб | Vue 3: карта регионов, регион, симулятор, вопросы к данным, ассистент направления, рабочий список, журнал решений, AI-скрайб, консоль стюарда, ожидание для граждан, проверка рецепта | `cd apps/web && npm run dev`, `npm run walk` |
| Мобильное | Flutter: гражданин (ожидание, рецепт), врач (рабочий список, ассистент направления), настройки, web-сборка | `cd apps/mobile && flutter run` |
| События | `decision.recorded` из API в Kafka, `intake.batch.loaded` из Python в API | `DARUMEN_KAFKA_TEST=1 dotnet test --filter KafkaIntegrationTests` |

## Цифры из `make eval` (11 сентября 2026)

| Метрика | Значение | Baseline |
|---|---|---|
| Ожидание, пинбол p50 на марте 2025 | 3.87 | 4.67 |
| Ожидание, пинбол p90 на марте 2025 | 2.22 | 2.63 |
| AUC отказа | 0.79 | 0.74 |
| Прогноз госпитализаций, MASE | 0.78 | 1.05 |
| Прогноз приёмного покоя, MASE | 0.88 | 0.99 |
| Перераспределение, экономия дней ожидания за 60 дней I квартала | 19 % (14–25 %) | — |
| Согласованность симулятора с фактом (Спирмен) | 0.61 | порог 0.5 |
| Индекс доступности, март 2025 | лучший регион 62 (95.0), худший 75 (2.5) | — |

## Что не сделано или ограничено

- Insight и черновики скрайба работают через DeepSeek (OpenAI-совместимый API, дешевле Claude) при `DEEPSEEK_API_KEY` в `.env`; провайдер заменяем (openai, anthropic). Эталонные 30 вопросов ([insight-questions.md](insight-questions.md)) не прогонялись, пока нет ключа.
- Отчёты PDF и Excel (`/insight/reports`) не реализованы.
- Полигоны регионов: открытый GeoJSON содержит 16 регионов до реформы 2022 года, поэтому карта показывает центры регионов; нужен ГИС-справочник (запрос данных).
- Координат организаций и аптек, названий МНН и поликлиник в открытых данных нет: расстояния равны нулю, лекарства показаны идентификаторами, регион рецептов `unknown` (запросы 12 и 13 в [data-requests.md](data-requests.md)).
- Направления и ожидающие покрывают только I квартал 2025 года: индекс доступности считается за три месяца.
- Недельный прогноз рецептов не лучше наива, поэтому в прогноз идёт сезонный наив (выбор модели по бэктесту).
- Вход через Keycloak проверен для API и настроен для веба (`VITE_AUTH_MODE=keycloak`); мобильное приложение работает в демо-режиме заголовков.
- Dagster: `make dagster` показывает линию активов silver → refdata → gold → models → published поверх тех же функций, что и цели `make`; расписания и сенсоры не настроены.
