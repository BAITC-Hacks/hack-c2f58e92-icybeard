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
- **Порог малых чисел:** публичные агрегаты с числом наблюдений меньше 5 возвращаются как `null` с `suppressed: true`.

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
Тело `{ "comment", "status": "acknowledged | closed" }` (по умолчанию `acknowledged`). Ответ 204, 404 если сигнала нет. Публикует `anomaly.acknowledged`.

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
`covered` по активным спецификациям нозологии (справочник спецификаций), сроки по фактическим обеспеченным рецептам (МНН за последние недели, иначе нозология за месяцы), дефицит по падению доли обеспеченных к выписанным. Названий МНН и аптек в открытых данных нет (запросы 12, 13): `pharmacies` пустой, названия вида «МНН 817». `GET /api/v1/medicines/nosologies`, `GET /api/v1/medicines/mnn?nosologyId=` дают списки для выбора.

## Journal: решения человека

### `POST /api/v1/journal/decisions` (doctor, regulator)
```json
{ "subject": "referral", "subjectId": "…", "recommended": { "moCode": "…" }, "chosen": { "moCode": "…" }, "reason": "…" }
```
Ответ 201 `{ "decisionId", "recordedAt" }`. Публикует `decision.recorded`.

### `GET /api/v1/journal/decisions?actor=me&subject=&page=&size=` (doctor: свои; regulator: регион)
Ответ `{ items: [ { decisionId, actor, role, subject, subjectId, recommended, chosen, reason, recordedAt } ], page, size, total }`. До подключения Keycloak актор берётся из заголовков `X-Actor` и `X-Role`.

### `GET /api/v1/journal/worklist` (doctor)
Рабочий список пациентов на маршруте (на кэмпе синтетический): `{ "items": [ { "patientRef", "synthetic": true, "stage", "expectedDate", "riskFlags": ["stuck_over_30"], "priority", "nextAction", "explanation" } ] }`.

## Explain и Insight

### `GET /api/v1/explain/{predictionId}` (все авторизованные)
Полное объяснение прогноза с факторами и текстом на двух языках.

### `POST /api/v1/insight/ask` (chief, regulator)
Тело `{ "question": "Где в марте самая длинная очередь на офтальмологию?", "regionKato": null }`. Ответ: `{ "answer": "…\nИсточник: access_index", "value": 126, "unit": null, "chart": { "type": "bar | line", "title", "x": [...], "series": [ { "name", "data": [...] } ] } | null, "toolsUsed": ["access_index"], "sources": ["tool:access_index"], "model": "deepseek/deepseek-chat" }`. Модель видит только инструменты доменов (`access_index`, `regions`, `bed_profiles`, `organizations`, `queue_state`, `predict_wait`, `anomalies`, `forecast`, `simulate`, `medicines_check`), не сырые данные. Провайдер задаётся в `Insight:Provider` (deepseek по умолчанию через OpenAI-совместимый клиент, openai, anthropic), ключ в `DEEPSEEK_API_KEY` в `.env` или `Insight:ApiKey`; без ключа ответ 503, `GET /api/v1/insight/status` показывает готовность, провайдера и модель. Эталонные вопросы: [insight-questions.md](insight-questions.md), прогон `scripts/insight_eval.py`.

### `POST /api/v1/insight/reports` (chief, regulator)
Тело `{ "template": "region_monthly", "regionKato", "month", "format": "pdf | xlsx" }`. Ответ 202 `{ "reportId" }`, затем `GET /api/v1/insight/reports/{id}` → файл. Пока не реализовано: выгрузка таблиц индекса и сигналов делается из интерфейса.

## Intake

- `POST /api/v1/intake/files` (steward): multipart, ответ 202 `{ "batchId" }`.
- `GET /api/v1/intake/batches?status=` → `{ items: [ { batchId, dataset, status, rowsLoaded, rowsQuarantined, receivedAt } ] }`.
- `GET /api/v1/intake/contracts`, `GET /api/v1/intake/contracts/{id}` (черновик с автопрофилем), `POST /api/v1/intake/contracts/{id}/approve`.
- `GET /api/v1/intake/quarantine?batchId=` → строки с причиной; `POST /api/v1/intake/batches/{id}/reprocess`.

## Refdata

- `GET /api/v1/refdata/regions`, `/organizations?regionKato=&q=`, `/profiles`, `/icd10?q=`, `/mnn?q=`. Публичные, кэш 1 час.

## Scribe (демо)

- `POST /api/v1/scribe/sessions` (doctor): `{ "consent": true, "language": "ru|kk" }` → `{ sessionId, wsUrl }`.
- WebSocket `wsUrl`: клиент шлёт аудио‑чанки, сервер шлёт `{ "type": "partial|final", "text", "t0", "t1" }`.
- `POST /api/v1/scribe/sessions/{id}/draft` → черновик записи `{ sections: [ { name, text, spans: [ { t0, t1 } ] } ] }`.
- `POST /api/v1/scribe/sessions/{id}/approve` `{ sections, patientLeaflet: { text } }` → 204, аудио удалено.
- `GET /api/v1/scribe/leaflets/{token}` (публичный по QR) → памятка.

## Тесты контракта
Для каждого эндпоинта: пример запроса и ответа в `src/Darumen.Tests/Contracts/`, проверка схемы через OpenAPI, тайминги p95 < 300 мс на витринах в Testcontainers.
