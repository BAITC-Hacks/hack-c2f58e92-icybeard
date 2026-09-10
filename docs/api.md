# REST API v1

Контракт для задач T2.1, T3.x и Flutter. Хост `Darumen.Api` за YARP, префикс `/api/v1`. Все ответы JSON в UTF‑8, даты `YYYY-MM-DD`, времена в ISO 8601 с часовым поясом. gRPC между .NET и Python описан в `proto/`; этот документ описывает только внешний REST.

## Общие соглашения

- **Аутентификация:** `Authorization: Bearer <JWT от Keycloak>`. Публичные эндпоинты помечены. Роли: `citizen`, `doctor`, `chief`, `regulator`, `steward`, `admin`.
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
Элемент: `{ "id", "streamId", "entity", "period", "observed", "expected", "score", "severity", "status", "peerGroup", "explanation" }`.

### `POST /api/v1/anomalies/{id}/ack` (chief, regulator)
Тело `{ "comment" }`. Ответ 204. Пишет `decision.recorded`.

## Simulation

### `POST /api/v1/simulate` (regulator)
```json
{
  "regionKato": "75", "profileCode": "381",
  "scenario": { "capacityDeltaPct": 15, "redistributeSharePct": 20, "horizonDays": 90 }
}
```
Ответ: `{ "baseline": { "p50Days", "p90Days", "shareOver30" }, "scenario": { ... }, "deltaDays": -9.4, "ci": [-12.1, -6.7], "assumptions": ["…"], "model" }`.

### `POST /api/v1/redistribute` (regulator)
Тело `{ "regionKato", "profileCode", "constraints": { "maxDistanceKm", "maxShareMovedPct" } }`. Ответ: `{ "moves": [ { "fromMo", "toMo", "share", "expectedDeltaDays" } ], "totalDeltaDays", "model" }`.

## Access index

### `GET /api/v1/index?month=2025-03&profileCode=` (публичный)
`{ "items": [ { "regionKato", "name", "shareOver30", "p90Days", "indexValue", "rank" } ], "method": "…" }`.

## Medicines

### `POST /api/v1/medicines/check` (doctor, citizen)
Тело `{ "mnnId", "nosologyId", "regionKato" }`. Ответ:
```json
{
  "covered": true, "program": "ОСМС", "category": "…",
  "fillDaysP50": 3, "fillDaysP90": 12, "pFilled14d": 0.91,
  "shortage": { "flag": false, "score": 0.4 },
  "pharmacies": [ { "drugStoreId", "name", "lat", "lon", "fills30d" } ],
  "alternatives": [ { "specId", "name" } ],
  "model"
}
```
`pharmacies` пустой, пока нет справочника аптек (запрос 12).

## Journal: решения человека

### `POST /api/v1/journal/decisions` (doctor, regulator)
```json
{ "subject": "referral", "subjectId": "…", "recommended": { "moCode": "…" }, "chosen": { "moCode": "…" }, "reason": "…" }
```
Ответ 201 `{ "decisionId", "recordedAt" }`. Публикует `decision.recorded`.

### `GET /api/v1/journal/decisions?actor=me&page=` (doctor: свои; regulator: регион)

### `GET /api/v1/journal/worklist` (doctor)
Рабочий список пациентов на маршруте (на кэмпе синтетический): `{ "items": [ { "patientRef", "synthetic": true, "stage", "expectedDate", "riskFlags": ["stuck_over_30"], "priority", "nextAction", "explanation" } ] }`.

## Explain и Insight

### `GET /api/v1/explain/{predictionId}` (все авторизованные)
Полное объяснение прогноза с факторами и текстом на двух языках.

### `POST /api/v1/insight/ask` (chief, regulator)
Тело `{ "question": "Где в марте самая длинная очередь на офтальмологию?", "regionKato": null }`. Ответ: `{ "answer": "…", "value": 126, "unit": "дней", "chart": { "type": "bar", "x": [...], "series": [...] }, "toolsUsed": ["forecast", "index"], "sources": [...] }`. Никакого доступа к сырым данным: только инструменты доменов и Cube.

### `POST /api/v1/insight/reports` (chief, regulator)
Тело `{ "template": "region_monthly", "regionKato", "month", "format": "pdf | xlsx" }`. Ответ 202 `{ "reportId" }`, затем `GET /api/v1/insight/reports/{id}` → файл.

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
