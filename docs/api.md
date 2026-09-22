# REST API v1

Контракт для задач T2.1, T3.x и Flutter. Хост `Darumen.Api` за YARP, префикс `/api/v1`. Все ответы JSON в UTF‑8, даты `YYYY-MM-DD`, времена в ISO 8601 с часовым поясом. gRPC между .NET и Python описан в `proto/`; этот документ описывает только внешний REST.

## Общие соглашения

- **Аутентификация:** `Authorization: Bearer <JWT от Keycloak>` (реалм `darumen`, аудитория `darumen-api`, роли реалма в `realm_access.roles`, атрибут `region_kato`). Публичные эндпоинты помечены. Роли: `citizen`, `doctor`, `chief`, `regulator`, `steward`, `admin` (admin проходит все политики). В режиме `Auth:Mode=headers` (тесты, разработка без Keycloak) роль берётся из заголовков `X-Actor`, `X-Role`, `X-Region`. Без роли: 401, с чужой ролью: 403. Каждый запрос врача, главврача, регулятора и стюарда пишется в `journal.audit` (`GET /api/v1/journal/audit`, regulator).
- **Ошибки:** RFC 9457 `application/problem+json`: `{ "type", "title", "status", "detail", "instance", "errors": { "field": ["..."] } }`.
- **Локаль:** заголовок `Accept-Language: ru | kk`; объяснения и названия приходят на выбранном языке.
- **Версия модели:** каждый ответ с прогнозом содержит `model: { name, version, trainedThrough }`.
- **Объяснение:** `explanation: { summary, factors: [{ name, contribution, text }] }`, факторы отсортированы по `|contribution|`.
- **Пагинация:** `?page=1&size=50`, ответ `{ items, page, size, total }`.
- **Идемпотентность записи:** заголовок `Idempotency-Key` на POST журналов и решений.
- **Ограничение частоты:** `POST /insight/ask` и `/scribe/*` — не больше `RateLimits:ModelCallsPerMinute` запросов в минуту на пользователя (по умолчанию 20), сверх лимита 429.
- **Порог малых чисел:** публичные агрегаты со слишком малым числом наблюдений не публикуются, а не отдаются нулями/суррогатами. Порог свой у каждой витрины и указан рядом с ней: индекс доступности (`GET /index`) исключает ячейки региона и профиля с числом направлений с исходом < 20 ещё на этапе сборки `gold.access_index` (см. `ml/src/darumen/models/index.py`); длительность лечения (`GET /los`) — ячейки с числом случаев < 100 в `gold.los_by_profile`. Обе витрины уже не содержат таких строк к моменту, когда до них доходит REST API — подавленные значения просто отсутствуют в `items`, а не возвращаются как `null`.

## Queue: ожидание госпитализации

### `POST /api/v1/queue/predict` (роли: все, включая публичную)
Запрос:
```json
{
  "regionKato": "75",
  "moCode": "01YF",
  "profileCode": "381",
  "icd10": "H25.1",
  "referralPurpose": "Оперативное лечение",
  "territorialType": "Город",
  "financeSource": "Активы Фонда на ОСМС",
  "registrationDate": "2025-03-15"
}
```
Ответ 200:
```json
{
  "p50Days": 35, "p90Days": 126, "pWithin30Days": 0.44, "pRefusal": 0.09,
  "queue": { "len": 412, "ageP50": 21, "throughputPerDay": 6.1 },
  "explanation": { "summary": "…", "factors": [ { "name": "queue_len", "contribution": 11.2, "text": "В очереди 412 направлений, это на 60 % больше типичного" } ] },
  "model": { "name": "wait_quantile", "version": "1.3.0", "trainedThrough": "2025-02-28" }
}
```
Для гражданина `icd10` необязателен, `moCode` может быть пустым: тогда ответ по региону и профилю. 422 при неизвестных кодах.

### `POST /api/v1/queue/alternatives` (все)
Запрос: тело как выше плюс `limit` (по умолчанию 5), `maxDistanceKm` (0 = без ограничения). Ответ: `{ "items": [ { "mo": { "moCode", "name", "regionKato", "lat", "lon" }, "p50Days", "p90Days", "pRefusal", "distanceKm" } ], "model" }`, отсортировано по `p50Days`.

### `GET /api/v1/queue/organizations/{moCode}?profileCode=` (chief, regulator)
Ряд `queue_daily` и `throughput_4w` за 90 дней: `{ "days": [ { "day", "registered", "hospitalized", "refused", "queueLen", "queueAgeP50" } ], "throughput": {...} }`.

## Forecast: прогноз нагрузки

### `GET /api/v1/forecast/{streamId}?entity[regionKato]=75&entity[profileCode]=381&horizon=3` (chief, regulator)
`streamId` ∈ зарегистрированным потокам (`er_visits_daily`, `admissions_monthly`, `rx_weekly`, `lab_weekly`, `vac_monthly`). Ответ: `{ "points": [ { "period", "yhat", "lo", "hi" } ], "history": [ { "period", "y" } ], "backtest": { "smape", "mase", "baselineSmape" }, "model" }`.

### `GET /api/v1/streams` (все авторизованные)
Каталог потоков: `{ "items": [ { "streamId", "title", "grain", "entityKeys", "horizons" } ] }`.

## Anomalies

### `GET /api/v1/anomalies?regionKato=&streamId=&severity=&status=open&page=&size=` (chief, regulator)
Элемент: `{ "id", "streamId", "entity", "period", "observed", "expected", "score", "peerScore", "severity", "kind": "entity | shared", "status", "regionKato", "comment" }`. `id` детерминирован (md5 потока, сущности и периода), поэтому подтверждения переживают перепубликацию витрины.

### `POST /api/v1/anomalies/{id}/ack` (chief, regulator)
Тело `{ "comment", "status": "acknowledged | dismissed" }` (по умолчанию `acknowledged`; `dismissed` — ложный сигнал, отрицательная метка для дообучения детектора). В одной транзакции сохраняет подтверждение и запись в журнал решений (`subject: "anomaly"`, `subjectId` = id сигнала, `recommended: {"status": "open"}`, `chosen: {"status": …}`, `reason` = комментарий) и публикует `decision.recorded`. Ответ 204; 404 если сигнала нет; 403 если главврач закрывает сигнал не своего региона; 422 при другом статусе.

## Simulation

### `POST /api/v1/simulate` (regulator)
```json
{
  "regionKato": "75", "profileCode": "381",
  "scenario": { "capacityDeltaPct": 15, "redistributeSharePct": 20, "horizonDays": 90 }
}
```
Ответ: `{ "organisations": 12, "baseline": { "meanWaitDays": 31.2 }, "scenario": { "meanWaitDays": 21.8 }, "deltaDays": -9.4, "ci": [-12.1, -6.7], "assumptions": ["…"], "model": { "name": "fluid_queue", "version", "trainedThrough" } }`. Ожидание здесь среднее по жидкостной модели очереди (см. `docs/model-cards/simulate.md`), интервал по потоку направлений ±20 %.

### `POST /api/v1/redistribute` (regulator)
Тело `{ "regionKato", "profileCode", "constraints": { "maxDistanceKm", "maxShareMovedPct", "horizonDays" } }`. Ответ: `{ "moves": [ { "fromMo": { "moCode", "name", "regionKato" }, "toMo": {...}, "sharePct", "arrivalsPerDay", "waitFromBefore", "waitFromAfter", "waitToBefore", "waitToAfter" } ], "totalWaitDaysBefore", "totalWaitDaysAfter", "totalDeltaDays", "horizonDays", "model" }`. `maxDistanceKm` начнёт действовать, когда в реестре появятся координаты организаций.

## Access index

### `GET /api/v1/index?month=2025-03&profileCode=` (публичный)
`{ "month", "profileCode", "items": [ { "regionKato", "name", "shareOver30", "p90Days", "indexValue", "rank", "n" } ], "months": ["2025-01", …], "method": "…" }`. Без `month` берётся последний доступный; `profileCode` по умолчанию `all`; 422 при месяце вне доступных.

## Medicines

### `POST /api/v1/medicines/check` (публичный)
Тело `{ "mnnId", "nosologyId", "regionKato" }` (нужен хотя бы один из `mnnId`, `nosologyId`). Ответ:
```json
{
  "covered": true, "program": "Программа 90", "category": "63",
  "fillDaysP50": 3, "fillDaysP90": 12, "pFilled14d": 0.91,
  "shortage": { "flag": false, "score": 0.1, "basis": "обеспечено 92 % выписанных за 4 нед. против 95 % за предыдущие 12" },
  "pharmacies": [], "alternatives": [ { "mnnId", "name", "issued12m" } ],
  "basis": "по 1 240 обеспеченным рецептам МНН за 4 нед.",
  "model": { "name": "rx_fill", "version": "1.0.0", "trainedThrough": "2025-03-24" }
}
```
`covered` по активным спецификациям нозологии (справочник спецификаций), сроки по фактическим обеспеченным рецептам (МНН за последние недели, иначе нозология за месяцы), дефицит по падению доли обеспеченных к выписанным. Названий МНН и аптек в открытых данных нет (запросы 12, 13): `pharmacies` пустой, названия вида «МНН 817». `GET /api/v1/medicines/nosologies`, `GET /api/v1/medicines/mnn?nosologyId=` дают списки для выбора; в `/mnn` каждый МНН ровно один раз (объём суммируется по категориям нозологии, категория — самая массовая), иначе выпадающий список клиента получал дубликаты.

## Journal: решения человека

### `POST /api/v1/journal/decisions` (doctor, regulator)
```json
{ "subject": "referral", "subjectId": "…", "recommended": { "moCode": "…" }, "chosen": { "moCode": "…" }, "reason": "…" }
```
Ответ 201 `{ "decisionId", "recordedAt" }`. Публикует `decision.recorded`. `subject`: `referral` (направление), `anomaly` (сигнал, пишется через `/anomalies/{id}/ack`), `route` (маршрут пациента, `subjectId` — реф `SYN-…`, пишется через `/route/{patientRef}/redirect`).

### `GET /api/v1/journal/decisions?actor=me&subject=&subjectId=&page=&size=` (doctor: свои; regulator: регион)
Ответ `{ items: [ { decisionId, actor, role, subject, subjectId, recommended, chosen, reason, recordedAt } ], page, size, total }`. `subjectId` — решения по одному предмету (например, по рефу пациента). До подключения Keycloak актор берётся из заголовков `X-Actor` и `X-Role`.

### `GET /api/v1/journal/worklist?regionKato=&flag=` (doctor)
Рабочий список пациентов на маршруте (на кэмпе синтетический): `{ "items": [ { "patientRef": "SYN-75-028B-381-01", "synthetic": true, "stage", "stageCode": "registered | waiting | called", "expectedDate", "riskFlags": ["stuck_over_30"], "priority", "nextAction", "nextActionCode": "redirect_faster | review_before_call | clarify_date | wait_for_call", "explanation", "moCode", "moName", "profileCode", "regionKato", "daysWaiting" } ], "synthetic": true, "asOf", "regionKato", "modelBacked" }`. Реф включает профиль (у организации бывают очереди по нескольким профилям) и открывает маршрут пациента — `GET /api/v1/route/{patientRef}`; `stage` и `nextAction` — русские подписи для старых клиентов, `stageCode` и `nextActionCode` — машинные коды, которые клиенты локализуют сами (RU/KK). Прогнозы по очередям региона (в Алматы их 373) модель отдаёт одним пакетным вызовом `PredictQueues`, API кэширует их на срез витрины (1 ч): состав и порядок списка стабильны между запросами, повторный запрос к модели не обращается; `modelBacked: false` — сервис моделей был недоступен, приоритеты и флаги посчитаны по агрегатам витрины.

## Route: маршрут пациента

Один контракт для гражданина и врача — только логистика плановой госпитализации: стадии Стандарта стационарной помощи (приказ МЗ РК ҚР-ДСМ-27), даты, прогноз ожидания той же модели, чек-лист обследований со сроками давности, альтернативы, решения врача и история прошлых направлений. Пациент синтетический (`synthetic: true`): выдуман, но сроки, очередь и исходы взяты из реального состояния очередей региона на `asOf`; это написано в `basis`. Ответы не кэшируются. Сервис моделей недоступен — маршрут строится по агрегатам витрины (`forecast.fromModel = false`, `pWithin30Days = null`), а не отдаёт 503.

### `GET /api/v1/route/me?regionKato=` (citizen)
Регион — клейм `region_kato`, иначе параметр, иначе `75`. Гражданин — один из первых пяти «застрявших» (дольше 30 дней или с организацией быстрее) пациентов рабочего списка региона (те же кэшированные прогнозы, что у врача); профили, привязанные к полу и беременности (231, 241, 251), и детские (по названию в справочнике: «… для детей», «Педиатрические», «Патология новорожденных») синтетическому взрослому гражданину не назначаются; номер — детерминированно по ИИН из клейма (иначе по учётной записи), поэтому врач видит того же пациента на первом экране своего списка. Ответ:
```json
{ "patientRef": "SYN-75-028B-381-01", "synthetic": true, "audience": "citizen", "asOf": "2025-03-31", "regionKato": "75",
  "organization": { "moCode", "moName", "profileCode", "profileName" },
  "stage": "waitlisted", "stageTitle": "Внесено в лист ожидания",
  "timeline": [ { "code": "referral_issued | examination | waitlisted | date_assigned | hospitalized", "order", "title", "date", "status": "done | current | upcoming", "norm" } ],
  "dates": { "issuedAt", "registeredAt", "plannedAt", "expectedAt" }, "daysWaiting": 47,
  "forecast": { "p50Days", "p90Days", "pWithin30Days", "fromModel": true, "model": { "name", "version", "trainedThrough" } },
  "benchmarks": [ { "code": "moh_target_wait_days", "value": 20, "unit": "days", "title", "source", "sourceDate": "2026-02-19" } ],
  "checklist": [ { "code": "cbc", "title", "validityDays": 14, "validityLabel": "14 дней", "doneAt", "validUntil", "status": "valid | expiring | expired" } ],
  "alternatives": [ { "mo": { "moCode", "name", "regionKato" }, "p50Days", "p90Days", "pRefusal", "distanceKm", "isNeighborRegion" } ], "alternativesModel",
  "decisions": [ { "decisionId", "role", "recordedAt", "fromMoCode", "toMoCode", "toMoName", "reason", "kind": "redirect | keep" } ],
  "history": [ { "moCode", "moName", "profileCode", "profileName", "registeredAt", "outcome": "hospitalized | refused", "outcomeAt", "waitDays" } ],
  "doctor": null, "basis": "Синтетический маршрут: …", "standard": { "source", "sourceUrl", "sourceDate", "available" } }
```
Гражданину `doctor` всегда `null`: риск отказа, приоритет и флаги — служебная информация врача. Стадии и статусы чек-листа считаются только по датам (`issuedAt` — за 1–10 дней до регистрации, обследования сданы между ними, срок действия — по приложению 5); причины отказов пациенту не приписываются, в открытых данных их нет. 404, если в регионе нет очередей; 422 — неверный КАТО.

### `GET /api/v1/route/{patientRef}` (doctor)
Тот же ответ с `audience: "doctor"` и панелью `doctor: { priority, riskFlags, nextAction, nextActionCode, explanation, pRefusal, refusalOrgInTraining, shap }`. 403 — пациент другого региона (клейм `region_kato` врача сильнее рефа), 404 — реф не разбирается или в очереди нет пациента с таким номером на дату среза.

### `POST /api/v1/route/{patientRef}/redirect` (doctor)
Тело `{ "toMoCode": "22GN", "reason": "…" }`, заголовок `Idempotency-Key`. Записывает решение `subject: route` (рекомендация системы — самая быстрая альтернатива по модели, выбор — `toMoCode`) и публикует `decision.recorded`; ответ 201 `{ "decisionId", "recordedAt" }`, при повторе ключа 200 с той же записью. 422 без `toMoCode` или `reason` и если организация совпадает с текущей. Гражданин видит решение в `decisions` своего маршрута («врач предложил другую организацию»).

## Insight

### `POST /api/v1/insight/ask` (chief, regulator)
Тело `{ "question": "Где в марте самая длинная очередь на офтальмологию?", "regionKato": null }`. Ответ: `{ "answer": "…\nИсточник: access_index", "value": 126, "unit": null, "chart": { "type": "bar | line", "title", "x": [...], "series": [ { "name", "data": [...] } ] } | null, "toolsUsed": ["access_index"], "sources": ["tool:access_index"], "model": "ollama/darumen-qwen3.8:27b" }`. Модель видит только инструменты доменов (`access_index`, `regions`, `bed_profiles`, `organizations`, `queue_state`, `predict_wait`, `anomalies`, `forecast`, `simulate`, `medicines_check`), не сырые данные. Провайдер задаётся в `Insight:Provider`: ollama по умолчанию (локальная модель через OpenAI-совместимый адрес `http://localhost:11434/v1`, ключ не нужен, для Qwen3 в промпт добавляется `/no_think`, теги `<think>` вырезаются), deepseek, openai или anthropic с ключом из `.env`. Сбой модели отдаётся как 503 «Модель недоступна». `GET /api/v1/insight/status` показывает готовность, провайдера и модель. Эталонные вопросы: [insight-questions.md](insight-questions.md), прогон `scripts/insight_eval.py`.

### `GET /api/v1/insight/reports?month=&profileCode=&format=pdf|xlsx` (chief, regulator)
Отчёт «Индекс доступности за месяц»: PDF (QuestPDF, встроенный шрифт с кириллицей) или Excel (ClosedXML) из тех же витрин, что карта регионов. Ответ — файл с Content-Disposition; 404, если индекс не рассчитан. Кнопки скачивания есть на карте регионов.

### `GET /api/v1/quality` (все авторизованные)
Качество моделей одним JSON — отчёты `make train`/`make eval` из lakehouse (read-only mount): `{ "wait": { "test_time", "test_mo", "by_region": [...], "by_profile": [...], "trainedThrough" }, "forecasts": { "<stream>": { "chosen", "models", "per_series_choice", "flat_share" } }, "anomalies", "simulate", "los", "survival", "anomalyLabelsModel", "anomalyLabels" }`. Этот же источник цитируют страница /quality и строка метрик в ассистенте направления.

### `GET /api/v1/los?regionKato=&profileCode=` (все авторизованные)
Длительность лечения по ячейкам регион×профиль из `gold.los_by_profile`: `{ "items": [ { "regionKato", "profileName", "profileCode", "n", "losMedianFact", "losP50Model" } ], "method" }`. Медиана факта за последние 12 месяцев (ячейки ≥ 100 случаев) и p50 LightGBM-модели; симулятор показывает «одна койка ≈ 1/LOS госпитализаций в день». Пустой список, пока витрина не опубликована.

### `GET /api/v1/refdata/seasonality` (публичный, как остальной refdata)
Внешние сезонные формы NHS 2017–2019: `{ "items": [ { "seriesId": "rtt_waiting_list | rtt_admitted_per_day | ae_attendances_per_day", "month": 1–12, "multiplier", "title", "source", "sourceYear", "windowLabel" } ] }`. Множители при среднегодовом = 1; в интерфейсе всегда подписаны «внешний ориентир».

### `GET /api/v1/refdata/vaccination` (публичный, как остальной refdata)
Оценки охвата вакцинацией WUENIC (ВОЗ/ЮНИСЕФ, WHO GHO API, страна KAZ): `{ "items": [ { "vaccine": "DTP3", "titleRu", "year", "coveragePct", "source", "note" } ] }`. Оценки заметно ниже административной отчётности (пересмотр после MICS) — показываются только как внешний ориентир. Обновление: `scripts/wuenic_fetch.py` → `make publish`.

## Intake

- `POST /api/v1/intake/files` (steward): multipart, ответ 202 `{ "batchId" }`.
- `GET /api/v1/intake/batches?status=` → `{ items: [ { batchId, dataset, status, rowsLoaded, rowsQuarantined, receivedAt } ] }`.
- `GET /api/v1/intake/contracts`, `GET /api/v1/intake/contracts/{id}` (черновик с автопрофилем), `POST /api/v1/intake/contracts/{id}/approve`.
- `GET /api/v1/intake/quarantine?batchId=` → строки с причиной; `POST /api/v1/intake/batches/{id}/reprocess`.

## Refdata

- `GET /api/v1/refdata/regions`, `/organizations?regionKato=&q=&profileCode=`, `/profiles`, `/seasonality`, `/vaccination`, `/vaccination-plans?regionKato=`, `/route-standard`. Публичные, кэш 1 час, `Vary: Accept-Language`. Справочников МКБ-10 и МНН по имени нет (запрос 12).
- `GET /api/v1/refdata/route-standard` — Стандарт стационарной помощи (приказ МЗ РК ҚР-ДСМ-27, ред. 15.09.2025): `{ "meta": { "source", "sourceUrl", "sourceDate" }, "available", "stages": [ { "code", "order", "title", "norm", "normWorkingDays", "rescheduleMaxDays", "noShowDays" } ], "refusalReasons": [ { "code", "title" } ], "checklist": [ { "code", "title", "validityDays", "validityLabel" } ], "benchmarks": [ { "code", "value", "unit", "title", "source", "sourceDate" } ] }`. Подписи по `Accept-Language`; источник — `refdata/route_standard.yaml` → `make publish` → `refdata.route_*`; `available: false`, пока витрины не опубликованы. Только логистика: сроки давности обследований — норматив приложения 5, а не медицинская рекомендация; ориентир МЗ РК (20 дней) — из коллегии 19.02.2026.

## Scribe (демо)

- `POST /api/v1/scribe/sessions` (doctor): `{ "consent": true, "language": "ru|kk" }` → `{ sessionId, wsUrl }`.
- WebSocket `wsUrl`: клиент шлёт аудио‑чанки, сервер шлёт `{ "type": "partial|final", "text", "t0", "t1" }`.
- `POST /api/v1/scribe/sessions/{id}/draft` → черновик записи `{ sections: [ { name, text, spans: [ { t0, t1 } ] } ] }`.
- `POST /api/v1/scribe/sessions/{id}/approve` `{ sections, patientLeaflet: { text } }` → 204, аудио удалено.
- `GET /api/v1/scribe/leaflets/{token}` (публичный по QR) → памятка.

## Тесты контракта
Для каждого эндпоинта: пример запроса и ответа в `src/Darumen.Tests/Contracts/`, проверка схемы через OpenAPI, тайминги p95 < 300 мс на витринах в Testcontainers.
