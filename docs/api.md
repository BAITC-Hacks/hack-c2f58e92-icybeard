# REST API v1

Контракт для задач T2.1, T3.x и Flutter. Хост `Darumen.Api` за YARP, префикс `/api/v1`. Все ответы JSON в UTF‑8, даты `YYYY-MM-DD`, времена в ISO 8601 с часовым поясом. gRPC между .NET и Python описан в `proto/`; этот документ описывает только внешний REST.

## Общие соглашения

- **Аутентификация и доступ:** `Authorization: Bearer <JWT от Keycloak>` (реалм `darumen`, аудитория `darumen-api`, роли реалма в `realm_access.roles`, атрибуты `region_kato`, `iin` у гражданина и `mo_code` — код организации для scope `own`). Роли: `citizen`, `doctor`, `org_admin` (прежняя `chief` в токене трактуется как `org_admin`), `regulator`, `steward`, `auditor`, `admin`. Доступ проверяется **разрешениями**, а не ролями: матрица «роль → разрешение → scope (`all` | `own`)» хранится в `auth.role_permissions` и меняется через `PUT /admin/roles/{key}/permissions` без перезапуска (кэш 30 с, сбрасывается при изменении); `admin` проходит все проверки. Контракт, матрица и сопоставление эндпоинтов — [rbac.md](rbac.md); у каждого эндпоинта ниже указано разрешение. Клиенты получают свои разрешения из `GET /api/v1/me`. В режиме `Auth:Mode=headers` (тесты, разработка без Keycloak) пользователь берётся из заголовков `X-Actor`, `X-Role` (через запятую), `X-Region`, `X-MoCode` (клейм `mo_code`), `X-Session-Id` (клейм `sid`). Без входа — 401; без разрешения — 403 `application/problem+json` с машинной причиной в `detail`: `permission_required` (и `permissions: [...]` — какие коды нужны), `no_organization` (scope `own`, а у пользователя нет `mo_code`), `other_organization` (scope `own`, запрошена чужая организация). Каждый запрос вошедшего пользователя, кроме гражданина, пишется в `journal.audit` вместе с его `mo_code` (`GET /api/v1/journal/audit`, `admin.users`).
- **Ошибки:** RFC 9457 `application/problem+json`: `{ "type", "title", "status", "detail", "instance", "errors": { "field": ["..."] } }`.
- **Локаль:** заголовок `Accept-Language: ru | kk`; объяснения и названия приходят на выбранном языке.
- **Версия модели:** каждый ответ с прогнозом содержит `model: { name, version, trainedThrough }`.
- **Объяснение:** `explanation: { summary, factors: [{ name, contribution, text }] }`, факторы отсортированы по `|contribution|`.
- **Пагинация:** `?page=1&size=50`, ответ `{ items, page, size, total }`.
- **Идемпотентность записи:** заголовок `Idempotency-Key` на POST журналов и решений.
- **Ограничение частоты:** общий лимит на все `/api/*` — `RateLimiting:PermitLimit` запросов за `RateLimiting:WindowSeconds` (по умолчанию 600 за 60 с; `RateLimiting:Enabled=false` выключает) на пользователя (`sub` из токена), без входа — на адрес клиента; `/health`, OpenAPI и Scalar не ограничиваются. Поверх него `POST /insight/ask` и `/scribe/*` — не больше `RateLimits:ModelCallsPerMinute` запросов в минуту на пользователя (по умолчанию 20), публичные формы — `RateLimits:PublicFormsPerMinute` с адреса. Сверх любого лимита — 429 `application/problem+json` с `detail: "rate_limited"` и заголовком `Retry-After` (секунды). Адрес клиента за хостовым Caddy и nginx контейнера web API берёт из `X-Forwarded-For` (`UseForwardedHeaders`): доверяются loopback и частные сети docker (`ForwardedHeaders:KnownNetworks`, по умолчанию `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `fc00::/7`), не больше `ForwardedHeaders:ForwardLimit` звеньев (по умолчанию 2: nginx и шлюз docker, через который приходит Caddy).
- **Порог малых чисел:** публичные агрегаты со слишком малым числом наблюдений не публикуются, а не отдаются нулями/суррогатами. Порог свой у каждой витрины и указан рядом с ней: индекс доступности (`GET /index`) исключает ячейки региона и профиля с числом направлений с исходом < 20 ещё на этапе сборки `gold.access_index` (см. `ml/src/darumen/models/index.py`); длительность лечения (`GET /los`) — ячейки с числом случаев < 100 в `gold.los_by_profile`. Обе витрины уже не содержат таких строк к моменту, когда до них доходит REST API — подавленные значения просто отсутствуют в `items`, а не возвращаются как `null`.

## Queue: ожидание госпитализации

### `POST /api/v1/queue/predict` (публичный)
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

### `POST /api/v1/queue/alternatives` (`wait.public`; с полями направления — `referral.assist`)
Вошедший пользователь (сроки ожидания видят все роли). Запрос с признаками конкретного направления (`icd10`, `referralPurpose`, `territorialType`, `financeSource`, `referringMoCode`) — это ассистент врача, ему нужен `referral.assist`, иначе 403. Запрос: тело как выше плюс `limit` (по умолчанию 5), `maxDistanceKm` (0 = без ограничения). Ответ: `{ "items": [ { "mo": { "moCode", "name", "regionKato", "lat", "lon" }, "p50Days", "p90Days", "pRefusal", "distanceKm" } ], "model" }`, отсортировано по `p50Days`.

### `GET /api/v1/queue/organizations/{moCode}?profileCode=` (`org.cabinet`; при `own` — только своя организация)
Ряд `queue_daily` и `throughput_4w` за 90 дней: `{ "days": [ { "day", "registered", "hospitalized", "refused", "queueLen", "queueAgeP50" } ], "throughput": {...} }`.

## Forecast: прогноз нагрузки

### `GET /api/v1/forecast/{streamId}?entity[regionKato]=75&entity[profileCode]=381&horizon=3` (`gov.map`)
`streamId` ∈ зарегистрированным потокам (`er_visits_daily`, `admissions_monthly`, `rx_weekly`, `lab_weekly`, `vac_monthly`). Ответ: `{ "points": [ { "period", "yhat", "lo", "hi" } ], "history": [ { "period", "y" } ], "backtest": { "smape", "mase", "baselineSmape" }, "model" }`.

### `GET /api/v1/streams` (`gov.map`)
Каталог потоков: `{ "items": [ { "streamId", "title", "grain", "entityKeys", "horizons" } ] }`.

## Anomalies

### `GET /api/v1/anomalies?regionKato=&streamId=&severity=&status=open&page=&size=` (`gov.map` — все; `org.cabinet` при `own` — только сигналы своей организации)
Элемент: `{ "id", "streamId", "entity", "period", "observed", "expected", "score", "peerScore", "severity", "kind": "entity | shared", "status", "regionKato", "comment" }`. `id` детерминирован (md5 потока, сущности и периода), поэтому подтверждения переживают перепубликацию витрины.

### `POST /api/v1/anomalies/{id}/ack` (`gov.map` или `org.cabinet`)
Тело `{ "comment", "status": "acknowledged | dismissed" }` (по умолчанию `acknowledged`; `dismissed` — ложный сигнал, отрицательная метка для дообучения детектора). В одной транзакции сохраняет подтверждение и запись в журнал решений (`subject: "anomaly"`, `subjectId` = id сигнала, `recommended: {"status": "open"}`, `chosen: {"status": …}`, `reason` = комментарий) и публикует `decision.recorded`. Ответ 204; 404 если сигнала нет; 403 `other_organization`, если сигнал вне организации (scope `own`) или региона пользователя; 422 при другом статусе.

## Simulation

### `POST /api/v1/simulate` (`gov.simulator`)
```json
{
  "regionKato": "75", "profileCode": "381",
  "scenario": { "capacityDeltaPct": 15, "redistributeSharePct": 20, "horizonDays": 90 }
}
```
Ответ: `{ "organisations": 12, "baseline": { "meanWaitDays": 31.2 }, "scenario": { "meanWaitDays": 21.8 }, "deltaDays": -9.4, "ci": [-12.1, -6.7], "assumptions": ["…"], "model": { "name": "fluid_queue", "version", "trainedThrough" } }`. Ожидание здесь среднее по жидкостной модели очереди (см. `docs/model-cards/simulate.md`), интервал по потоку направлений ±20 %.

### `POST /api/v1/redistribute` (`gov.simulator`)
Тело `{ "regionKato", "profileCode", "constraints": { "maxDistanceKm", "maxShareMovedPct", "horizonDays" } }`. Ответ: `{ "moves": [ { "fromMo": { "moCode", "name", "regionKato" }, "toMo": {...}, "sharePct", "arrivalsPerDay", "waitFromBefore", "waitFromAfter", "waitToBefore", "waitToAfter" } ], "totalWaitDaysBefore", "totalWaitDaysAfter", "totalDeltaDays", "horizonDays", "model" }`. `maxDistanceKm` начнёт действовать, когда в реестре появятся координаты организаций.

## Access index

### `GET /api/v1/index?month=2025-03&profileCode=` (публичный)
`{ "month", "profileCode", "items": [ { "regionKato", "name", "shareOver30", "p90Days", "indexValue", "rank", "n" } ], "months": ["2025-01", …], "method": "…" }`. Без `month` берётся последний доступный; `profileCode` по умолчанию `all`; 422 при месяце вне доступных.

## Medicines

### `POST /api/v1/medicines/check` (`medicines.check`; списки `/medicines/*` — тоже)
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

### `POST /api/v1/journal/decisions` (`referral.confirm`; `subject: "scenario"` симулятора — `gov.simulator`)
```json
{ "subject": "referral", "subjectId": "…", "recommended": { "moCode": "…" }, "chosen": { "moCode": "…" }, "reason": "…" }
```
Ответ 201 `{ "decisionId", "recordedAt" }`. Публикует `decision.recorded`. `subject`: `referral` (направление), `anomaly` (сигнал, пишется через `/anomalies/{id}/ack`), `route` (маршрут пациента, `subjectId` — реф `SYN-…`, пишется через `/route/{patientRef}/redirect`).

### `GET /api/v1/journal/decisions?actor=me&subject=&subjectId=&page=&size=` (`decisions.all` — все, при `own` — решения своей организации; `decisions.own` — только свои)
Ответ `{ items: [ { decisionId, actor, role, subject, subjectId, recommended, chosen, reason, recordedAt } ], page, size, total }`. `subjectId` — решения по одному предмету (например, по рефу пациента). До подключения Keycloak актор берётся из заголовков `X-Actor` и `X-Role`.

### `GET /api/v1/journal/worklist?regionKato=&moCode=&flag=` (`worklist.view`; `moCode` или scope `own` — только очереди организации)
Рабочий список пациентов на маршруте (на кэмпе синтетический): `{ "items": [ { "patientRef": "SYN-75-028B-381-01", "synthetic": true, "stage", "stageCode": "registered | waiting | called", "expectedDate", "riskFlags": ["stuck_over_30"], "priority", "nextAction", "nextActionCode": "redirect_faster | review_before_call | clarify_date | wait_for_call", "explanation", "moCode", "moName", "profileCode", "regionKato", "daysWaiting" } ], "synthetic": true, "asOf", "regionKato", "modelBacked" }`. Реф включает профиль (у организации бывают очереди по нескольким профилям) и открывает маршрут пациента — `GET /api/v1/route/{patientRef}`; `stage` и `nextAction` — русские подписи для старых клиентов, `stageCode` и `nextActionCode` — машинные коды, которые клиенты локализуют сами (RU/KK). Строка с открытым сигналом гражданина (см. `POST /route/me/signals`) несёт `"patientSignal": { "kind", "toMoCode", "toMoName", "comment", "recordedAt" }`, флаг `patient_signal` в `riskFlags` и приоритет на 3 выше; фильтр `flag=patient_signal`. Сигнал закрывается решением врача (`/route/{ref}/redirect` или `/route/{ref}/keep`). Прогнозы по очередям региона (в Алматы их 373) модель отдаёт одним пакетным вызовом `PredictQueues`, API кэширует их на срез витрины (1 ч): состав и порядок списка стабильны между запросами, повторный запрос к модели не обращается; `modelBacked: false` — сервис моделей был недоступен, приоритеты и флаги посчитаны по агрегатам витрины.

## Route: маршрут пациента

Один контракт для гражданина и врача — только логистика плановой госпитализации: стадии Стандарта стационарной помощи (приказ МЗ РК ҚР-ДСМ-27), даты, прогноз ожидания той же модели, чек-лист обследований со сроками давности, альтернативы, решения врача и история прошлых направлений. Пациент синтетический (`synthetic: true`): выдуман, но сроки, очередь и исходы взяты из реального состояния очередей региона на `asOf`; это написано в `basis`. Ответы не кэшируются. Сервис моделей недоступен — маршрут строится по агрегатам витрины (`forecast.fromModel = false`, `pWithin30Days = null`), а не отдаёт 503.

### `GET /api/v1/route/me?regionKato=` (`route.own`)
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

### `GET /api/v1/route/{patientRef}` (`worklist.view`; при `own` — пациенты своей организации)
Тот же ответ с `audience: "doctor"` и панелью `doctor: { priority, riskFlags, nextAction, nextActionCode, explanation, pRefusal, refusalOrgInTraining, shap }`. 403 — пациент другого региона (клейм `region_kato` врача сильнее рефа), 404 — реф не разбирается или в очереди нет пациента с таким номером на дату среза.

### `POST /api/v1/route/{patientRef}/redirect` (`referral.confirm`)
Тело `{ "toMoCode": "22GN", "reason": "…" }`, заголовок `Idempotency-Key`. Записывает решение `subject: route` (рекомендация системы — самая быстрая альтернатива по модели, выбор — `toMoCode`) и публикует `decision.recorded`; ответ 201 `{ "decisionId", "recordedAt" }`, при повторе ключа 200 с той же записью. 422 без `toMoCode` или `reason` и если организация совпадает с текущей. Гражданин видит решение в `decisions` своего маршрута («врач предложил другую организацию»).

### `POST /api/v1/route/{patientRef}/keep` (`referral.confirm`)

Тело `{ "reason" }`, `Idempotency-Key` как у `/redirect`. Решение «оставить в текущей организации» с причиной: в журнале `chosen` = текущая организация, на маршруте `Kind = keep`; закрывает открытый сигнал гражданина. 422 без причины.

### `POST /api/v1/route/me/signals` (`route.own`)

Двусторонний маршрут: тело `{ "kind": "still_waiting | treated_elsewhere | withdraw | request_redirect", "toMoCode"?, "comment"? }`, `Idempotency-Key`. Первые три — цифровая валидация листа ожидания («Вы ещё ждёте?», как DrDoctor/NECU в NHS), четвёртый — просьба рассмотреть организацию быстрее (`toMoCode` обязателен и не равен текущей → иначе 422). Запись идёт в те же `journal.decisions` (subject `route`, роль `citizen`, `chosen = {"signal", "moCode"?}`, `reason` = комментарий); в аудит не попадает. Ответ 201 `{ "decisionId", "recordedAt" }`.

В `GET /route/me` и `GET /route/{ref}` добавлены `"signals": [ { "decisionId", "recordedAt", "kind", "toMoCode", "toMoName", "comment", "open" } ]` (свежие первыми, `open` — врач ещё не ответил решением после сигнала) и `"validationDue"` (нет подтверждения ожидания за 30 дней). Сигналы не входят в `decisions`.

## Insight

### `POST /api/v1/insight/ask` (`insight.ask`)
Тело `{ "question": "Где в марте самая длинная очередь на офтальмологию?", "regionKato": null }`. Ответ: `{ "answer": "…\nИсточник: access_index", "value": 126, "unit": null, "chart": { "type": "bar | line", "title", "x": [...], "series": [ { "name", "data": [...] } ] } | null, "toolsUsed": ["access_index"], "sources": ["tool:access_index"], "model": "ollama/darumen-qwen3.8:27b" }`. Модель видит только инструменты доменов (`access_index`, `regions`, `bed_profiles`, `organizations`, `queue_state`, `predict_wait`, `anomalies`, `forecast`, `simulate`, `medicines_check`), не сырые данные. Провайдер задаётся в `Insight:Provider`: ollama по умолчанию (локальная модель через OpenAI-совместимый адрес `http://localhost:11434/v1`, ключ не нужен, для Qwen3 в промпт добавляется `/no_think`, теги `<think>` вырезаются), deepseek, openai или anthropic с ключом из `.env`. Сбой модели отдаётся как 503 «Модель недоступна». `GET /api/v1/insight/status` показывает готовность, провайдера и модель. Эталонные вопросы: [insight-questions.md](insight-questions.md), прогон `scripts/insight_eval.py`.

### `GET /api/v1/insight/reports?month=&profileCode=&format=pdf|xlsx` (`insight.ask`)
Отчёт «Индекс доступности за месяц»: PDF (QuestPDF, встроенный шрифт с кириллицей) или Excel (ClosedXML) из тех же витрин, что карта регионов. Ответ — файл с Content-Disposition; 404, если индекс не рассчитан. Кнопки скачивания есть на карте регионов.

### `GET /api/v1/quality` (`gov.map` или `referral.assist`)
Качество моделей одним JSON — отчёты `make train`/`make eval` из lakehouse (read-only mount): `{ "wait": { "test_time", "test_mo", "by_region": [...], "by_profile": [...], "trainedThrough" }, "forecasts": { "<stream>": { "chosen", "models", "per_series_choice", "flat_share" } }, "anomalies", "simulate", "los", "survival", "anomalyLabelsModel", "anomalyLabels" }`. Этот же источник цитируют страница /quality и строка метрик в ассистенте направления.

### `GET /api/v1/los?regionKato=&profileCode=` (`gov.map`; как `/staffing`, `/vaccination-refusals`, `/oncology-late-stage`, `/equipment`)
Длительность лечения по ячейкам регион×профиль из `gold.los_by_profile`: `{ "items": [ { "regionKato", "profileName", "profileCode", "n", "losMedianFact", "losP50Model" } ], "method" }`. Медиана факта за последние 12 месяцев (ячейки ≥ 100 случаев) и p50 LightGBM-модели; симулятор показывает «одна койка ≈ 1/LOS госпитализаций в день». Пустой список, пока витрина не опубликована.

### `GET /api/v1/refdata/seasonality` (публичный, как остальной refdata)
Внешние сезонные формы NHS 2017–2019: `{ "items": [ { "seriesId": "rtt_waiting_list | rtt_admitted_per_day | ae_attendances_per_day", "month": 1–12, "multiplier", "title", "source", "sourceYear", "windowLabel" } ] }`. Множители при среднегодовом = 1; в интерфейсе всегда подписаны «внешний ориентир».

### `GET /api/v1/refdata/vaccination` (публичный, как остальной refdata)
Оценки охвата вакцинацией WUENIC (ВОЗ/ЮНИСЕФ, WHO GHO API, страна KAZ): `{ "items": [ { "vaccine": "DTP3", "titleRu", "year", "coveragePct", "source", "note" } ] }`. Оценки заметно ниже административной отчётности (пересмотр после MICS) — показываются только как внешний ориентир. Обновление: `scripts/wuenic_fetch.py` → `make publish`.

## Public (страница входа)

### `GET /api/v1/public/daily?regionKato=` (публичный)
Витрина «сегодня и завтра» (страница входа веба и главная гражданина в мобилке): `weather` — прогноз Open-Meteo на сегодня и завтра по координатам столицы региона (`refdata/regions.yaml`), коды погоды сведены к шести словам `clear · cloudy · fog · rain · snow · thunder`; `tips` — бытовые предупреждения по порогам (жара ≥ 30 °C, мороз ≤ −15 °C, ветер ≥ 50 км/ч, осадки ≥ 60 %, УФ ≥ 6, снег, гроза, туман), на языке `Accept-Language`, `day` 0 — сегодня, 1 — завтра; `news` — материалы о здравоохранении из RSS (по умолчанию Tengrinews, фильтр по заголовку словарём `Public:NewsKeywords`, ленты МЗ РК на gov.kz отвечают 500). Источники кэшируются `Public:CacheMinutes` (30) и деградируют по отдельности: `available: false` без ошибки. Никаких диагнозов и медицинских рекомендаций (ТЗ §11); неизвестный регион → регион по умолчанию `75`.

### `GET /api/v1/public/login-examples` (публичный, кэш 1 ч)
Пример-карточки страницы входа одним запросом (раньше веб вызывал `/queue/predict` и `/medicines/*` без входа): `{ "wait": { "regionKato": "75", "regionName", "profileCode", "profileName", "p50Days", "p90Days", "within30" }, "rx": { "mnn", "covered", "fillP50", "fillP90" } }`. Регион и профиль — `Public:LoginExamples` (г. Алматы, первый профиль с «фтальм» в названии), МНН — первое по объёму рецептов. Часть без данных (модель или витрина недоступна) — `null` и кэш на минуту.

### `GET /api/v1/public/service-status` (публичный, кэш 30 с)
Какие внешние каналы сейчас работают — веб и мобилка показывают недоступное честно, ничего не скрывая (баннер «Почтовый сервер недоступен», выключенные колонки почты, SMS и push в настройках уведомлений, пояснение у кнопки eGov mobile):

```json
{
  "checkedAt": "2026-09-28T10:15:00Z",
  "email": { "available": false, "reason": "smtp_not_configured" },
  "push":  { "available": false, "reason": "not_ready" },
  "sms":   { "available": false, "reason": "not_ready" },
  "egov":  { "available": false, "reason": "endpoint_not_provided" }
}
```

`checkedAt` — UTC до секунды; у доступного канала `available: true, reason: null` (поле `reason` есть всегда). Причины: `email` — `smtp_not_configured` (пуст `Mail:Smtp:Host`) или `smtp_unreachable` (TCP-подключение к `Mail:Smtp:Host:Port` не удалось за 3 с; результат пробы кэшируется на 60 с, одновременные запросы ждут одну пробу, учётные данные SMTP не используются и не логируются, Warning в журнал — только при смене состояния); `push` и `sms` — `not_ready`, пока не выставлены `Services:Push:Ready` / `Services:Sms:Ready` (`true`, по умолчанию `false`); `egov` — `endpoint_not_provided`, пока пуст `Services:Egov:Endpoint` (адрес сервиса eGov mobile / Smart Bridge). Проба никогда не превращается в 5xx: сбой — это `smtp_unreachable`. Клиент, не получивший ответ, почту считает неизвестной (баннер не показывает), а push, SMS и eGov — недоступными.

## Intake

Все `/intake/*` — `data.steward`.

- `POST /api/v1/intake/files`: multipart, ответ 202 `{ "batchId" }`.
- `GET /api/v1/intake/batches?status=` → `{ items: [ { batchId, dataset, status, rowsLoaded, rowsQuarantined, receivedAt } ] }`.
- `GET /api/v1/intake/contracts`, `GET /api/v1/intake/contracts/{id}` (черновик с автопрофилем), `POST /api/v1/intake/contracts/{id}/approve`.
- `GET /api/v1/intake/quarantine?batchId=` → строки с причиной; `POST /api/v1/intake/batches/{id}/reprocess`.

## Refdata

- `GET /api/v1/refdata/regions`, `/organizations?regionKato=&q=&profileCode=`, `/profiles`, `/seasonality`, `/vaccination`, `/vaccination-plans?regionKato=`, `/route-standard`. Публичные, кэш 1 час, `Vary: Accept-Language`. Справочников МКБ-10 и МНН по имени нет (запрос 12).
- `GET /api/v1/refdata/route-standard` — Стандарт стационарной помощи (приказ МЗ РК ҚР-ДСМ-27, ред. 15.09.2025): `{ "meta": { "source", "sourceUrl", "sourceDate" }, "available", "stages": [ { "code", "order", "title", "norm", "normWorkingDays", "rescheduleMaxDays", "noShowDays" } ], "refusalReasons": [ { "code", "title" } ], "checklist": [ { "code", "title", "validityDays", "validityLabel" } ], "benchmarks": [ { "code", "value", "unit", "title", "source", "sourceDate" } ] }`. Подписи по `Accept-Language`; источник — `refdata/route_standard.yaml` → `make publish` → `refdata.route_*`; `available: false`, пока витрины не опубликованы. Только логистика: сроки давности обследований — норматив приложения 5, а не медицинская рекомендация; ориентир МЗ РК (20 дней) — из коллегии 19.02.2026.

## Scribe (демо)

Все `/scribe/*`, кроме памятки по токену, — `scribe.use`.

- `POST /api/v1/scribe/sessions`: `{ "consent": true, "language": "ru|kk" }` → `{ sessionId, wsUrl }`.
- WebSocket `wsUrl`: клиент шлёт аудио‑чанки, сервер шлёт `{ "type": "partial|final", "text", "t0", "t1" }`.
- `POST /api/v1/scribe/sessions/{id}/draft` → черновик записи `{ sections: [ { name, text, spans: [ { t0, t1 } ] } ] }`.
- `POST /api/v1/scribe/sessions/{id}/approve` `{ sections, patientLeaflet: { text } }` → 204, аудио удалено.
- `GET /api/v1/scribe/leaflets/{token}` (публичный по QR) → памятка.

## Доступ и администрирование

Контракт — [rbac.md](rbac.md): роли, матрица разрешений, scope `own`, сопоставление эндпоинтов. Все пути под `/api/v1`, ошибки — `application/problem+json`, списки — `{ items, total, page, size }`. Решения администраторов (роль и организация пользователя, блокировка, верификация врача, решение по заявке, изменение матрицы) пишутся в журнал решений (`subject`: `user_access`, `doctor_verification`, `org_application`, `role_permissions`) и в `journal.audit`. Keycloak — через Admin REST API конфиденциального клиента `darumen-admin` (`Keycloak:Admin:*`, секрет — `Keycloak__Admin__ClientSecret`); недоступен — 503 problem «Сервис учётных записей недоступен», `GET /me` при этом отвечает (без проверки второго фактора).

**Я и мой аккаунт** (любой вошедший)
- `GET /me` → `{ actor, userId, displayName, email, emailVerified, roles, permissions: [{ code, scope }], moCode, moName, regionKato, iinMasked, onboarding: { emailVerified, otpConfigured, profileChecked, colleaguesInvited } }`. `permissions` — действующие: `own` без `mo_code` не попадает в список.
- `POST /me/access-requests` `{ permission, path, comment? }` → 202; запись в `auth.account_requests` и `journal.audit` (`detail`: `access_request: permission=… path=…`), видна в журнале аудита администратору организации и системы.
- `GET /me/profile`, `PUT /me/profile` `{ phone?, language: ru|kk, timeZone: IANA }`; ФИО, должность, специальность и организация — только чтение (`readOnlyFields`).
- `GET /me/notifications`, `PUT /me/notifications` `{ events: [{ code, inApp, email, sms, push }], quietFrom, quietTo, quietExceptRegulator, digest: off|daily|weekly }`; события: `security` (всегда включено), `route_updates`, `patient_signals`, `referral_decisions`, `anomalies`, `data_uploads`, `access_requests`, `org_applications`.
- `GET /me/consents`, `PUT /me/consents/{code}` `{ granted }`: `forecasts` (обязательное — отозвать нельзя, 422), `anonymized_stats`, `research_exports`.
- `GET /me/access-log` — записи аудита других пользователей, где встречается мой id, логин или (у гражданина) реф моего маршрута; `GET /me/export` — CSV своих данных (ИИН маской); `POST /me/deletion-request` → 202.
- `GET /me/security` → `{ passwordChangedAt, otpConfigured, smsAvailable: false, recoveryCodes: null, recentLogins: [{ at, method, success, ip }], sessions: [{ id, device, browser, ip, start, lastAccess, current }] }` (Keycloak: credentials, события LOGIN/LOGIN_ERROR, сессии; текущая — по `sid` токена; `device` — по клиенту Keycloak, User-Agent Admin API не отдаёт). `DELETE /me/sessions/{id}` → 204; `DELETE /me/sessions?keepCurrent=true` → `{ closed }` (`keepCurrent=false` — выход из всех сессий). Смена пароля и приложение-аутентификатор — редиректом в Keycloak (`kc_action=UPDATE_PASSWORD` / `CONFIGURE_TOTP`).

**Администрирование** (`admin.users`: пользователи и врачи; при `own` — только своя организация и роли `doctor`/`org_admin`; роль `admin` и учётные записи администраторов системы — только `admin`)
- `GET /admin/users?role&moCode&status&q&page&size` → `{ items: [{ id, username, displayName, email, roles, moCode, moName, regionKato, lastActivity, status: active|invited|blocked, via: egov|password }], total, page, size, summary: { active, invitedStale, blocked } }`; `lastActivity` — последняя запись актора в `journal.audit`; `invited` — учётная запись выключена и есть открытое приглашение.
- `GET /admin/users/{id}`; `PUT /admin/users/{id}` `{ role, moCode?, regionKato? }` (роли реалма заменяются, атрибуты `mo_code`/`region_kato` — в Keycloak); `POST /admin/users/{id}/block` (выключение и выход из всех сессий), `POST /admin/users/{id}/unblock`. Роль, которую нельзя назначить, — 403 `role_not_assignable`.
- `POST /admin/users/invite` `{ email, displayName, role, moCode?, regionKato? }` → 201 `{ userId, invitationId, expiresAt, emailSent, inviteUrl? }`: пользователь в Keycloak выключен до принятия, токен 7 дней (в базе — SHA-256), письмо «Вас пригласили» со ссылкой `{Web:PublicOrigin}/invite/{token}`; без SMTP — `emailSent: false` и `inviteUrl` для ручной передачи. Занятая почта — 409.
- `GET /admin/doctors?regionKato&moCode&specialty&verification&page&size` → `{ id, displayName, specialty, moCode, moName, regionKato, referrals, matchRate, verification: pending|verified|rejected }` (направления и доля совпадения выбора с рекомендацией — журнал решений `referral`/`route` за 90 дней); `POST /admin/doctors/{id}/verification` `{ status, comment? }`.
- `GET /admin/roles` (`admin.roles`) → `{ roles, permissions (каталог RU/KK, system, editable), matrix: [{ role, permission, scope }], usersByRole, identityAvailable }`; `PUT /admin/roles/{key}/permissions` `{ changes: [{ permission, scope: all|own|null }], comment? }` (строка `admin`, системные разрешения и снятие `wait.public` — 422); `POST /admin/roles` `{ key, titleRu, titleKk, descriptionRu?, descriptionKk?, copyFrom? }` → 201, создаёт realm role в Keycloak; `GET /admin/roles/history?role&page&size`.
- `GET /admin/orgs?regionKato&type&status&q&page&size`, `GET /admin/orgs/{moCode}` (`admin.orgs`) → `{ moCode, name, regionKato, type, users, status: connected|no_data, admins: [{ id, displayName, email, status }], freshness: [{ dataset, lastLoadedAt, status, rowsLoaded }] }` (+ `applications` в карточке): справочник `refdata.mo_registry`, пользователи — по атрибуту `mo_code`, «подключена» — есть строки в `gold.queue_state`, свежесть — последние партии `intake.batches` по наборам (региональные — по партиции `region_kato`).
- `GET /admin/org-applications?status&page&size`; `POST /admin/org-applications/{id}/approve` `{ moCode? }` (создаёт `org_admin` с приглашением, письмо «Заявка одобрена» со ссылкой; без кода организации — 422); `POST /admin/org-applications/{id}/reject` `{ reason }` (письмо с причиной). Рассматривается только заявка `pending_review`, иначе 409.

**Публичное** (анонимно; POST — лимит `RateLimits:PublicFormsPerMinute` с адреса, по умолчанию 10, сверх — 429)
- `POST /public/org-applications` `{ orgName, bin (12 цифр), type, regionKato, moCode?, adminName, email, phone, consent: true }` → 201 `{ id, number (ORG-2026-00001), statusToken, emailSent, resendAfterSeconds }` и письмо с 6-значным кодом (15 минут, 5 попыток).
- `POST /public/org-applications/{id}/verify-email` `{ code, statusToken }` → статус `pending_review`; `POST /public/org-applications/{id}/resend-code` `{ statusToken }` → 202 (не чаще раза в 60 с, иначе 429 с `retryAfterSeconds`); `GET /public/org-applications/{id}?statusToken=` → `{ number, orgName, email (маской), status: pending_email|pending_review|approved|rejected, submittedAt }`.
- `GET /public/invites/{token}` → `{ displayName, email, orgName, moCode, role, roleTitleRu, roleTitleKk, invitedBy, invitedAt, expiresAt }` (404 — нет такого; 410 `expired|accepted|declined`); `POST /public/invites/{token}/accept` `{ password, acceptedRules: true }` — пароль ставится через Admin API по политике реалма, нарушение — 422 с текстом на языке `Accept-Language` в `errors.password` и `passwordPolicy: { code, ru, kk }`; пользователь включается, почта подтверждается. `POST /public/invites/{token}/decline` — выключенная учётная запись удаляется.
- `POST /public/password-reset` `{ email }` → всегда 202 `{ accepted: true }` (не раскрывает, есть ли почта); если пользователь найден и включён — Keycloak шлёт письмо `UPDATE_PASSWORD` (`execute-actions-email`, срок 1 ч, `client_id=darumen-web`, возврат на `{Web:PublicOrigin}/`).
- `GET /public/login-examples` и `GET /public/service-status` (почта, push, SMS, eGov — доступны ли сейчас) — см. раздел Public.

Почта приложения: `Mail:Smtp:Host/Port/User/Password/From/EnableSsl` (в разработке — Mailpit `localhost:1025`, интерфейс `localhost:8025`; в compose — `mailpit:1025`); шаблоны «Письма системы» в Палитре C: приглашение, код подтверждения почты, решение по заявке. Смену пароля и «Забыли пароль» шлёт Keycloak своей темой писем.

## Тесты контракта
Для каждого эндпоинта: пример запроса и ответа в `src/Darumen.Tests/Contracts/`, проверка схемы через OpenAPI, тайминги p95 < 300 мс на витринах в Testcontainers.
