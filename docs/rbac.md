# Роли, разрешения и администрирование

Источник — доски холста Claude Design «Админ · роли и доступ (матрица)», «Админ · пользователи / врачи / организации», flow входа и аккаунта (28.09.2026). Этот файл — контракт для бэкенда, Keycloak, веба и мобилки: проверка прав выполняется **и на бэкенде (источник истины), и на клиентах** (скрытие пунктов меню, защита маршрутов, состояние «нет доступа»). Клиенты не держат собственных списков «роль → экран»: они получают набор разрешений из `GET /api/v1/me`.

## Роли

| Ключ (realm role) | RU | KK | Особенности |
|---|---|---|---|
| `citizen` | Гражданин | Азамат | свой маршрут, клейм `iin` |
| `doctor` | Врач ПМСП | МСАК дәрігері | клеймы `region_kato`, `mo_code` (если задан), `profile_code` (задача 10 плана прозрачности, необязателен — привязка к отделению/профилю: с ним `/journal/worklist` сужен до одной очереди своей организации, без него — все профили организации, как раньше) |
| `org_admin` | Администратор организации | Ұйым әкімшісі | обязателен клейм `mo_code`; заменяет прежнюю роль `chief` (главврач). Роль `chief` в токене трактуется как `org_admin` (legacy-алиас в `KeycloakRolesTransformation`) |
| `regulator` | Регулятор (Минздрав) | Реттеуші (ДСМ) | вся страна по умолчанию; с клеймом `region_kato` — региональный регулятор (тот же охват, что у `org_admin`/`doctor`: `/journal/worklist`, `/anomalies`, закрытие аномалии вне своего региона — 403) |
| `steward` | Оператор данных | Деректер операторы | загрузки и качество данных (роль `steward` — прежнее название «Стюард данных»/«Деректер стюарды», переименовано в задаче 12 плана прозрачности; ключ роли и код разрешения `data.steward` не менялись) |
| `auditor` | Аудитор | Аудитор | новая роль: журналы и аудит |
| `admin` | Администратор системы | Жүйе әкімшісі | все разрешения, строка матрицы не редактируется |
| `bed_manager` | Менеджер по койкам | Төсек-орын менеджері | задача 8 плана прозрачности: урезанная версия `org_admin` — только `worklist.view` (own) и `referral.confirm` (own), без кабинета организации/пользователей. **Не сидируется миграцией** — заводится администратором через `POST /admin/roles` + `PUT /admin/roles/bed_manager/permissions` (тот же общий механизм создания ролей, что и любая произвольная роль); `org_admin` затем может назначать её в своей организации (`PermissionCatalog.OrgAssignableRoles`). Существующих `org_admin` роль не трогает — это дополнительная, а не заменяющая роль |

Демо-пользователи realm (пароль `darumen`): `citizen1`, `doctor1` (`mo_code=028B`), `doctor2` (`mo_code=22GN` — второй врач другой организации, нужен, чтобы вживую пройти весь цикл направления: `doctor1`/`doctor2` отправляет — принимающая сторона подтверждает и выписывает — колокольчик отправившей стороне; без второго врача цепочка не проходит целиком, потому что `confirm`/`discharge` требует mo_code именно принимающей организации), `chief1` (роль `org_admin`, `mo_code=028B`, имя пользователя сохранено для документации), `regulator1`, `steward1`, `auditor1`, `admin1`. `bed_manager` — не в этом списке: её нужно один раз создать через `admin.roles`, затем через `admin.users` пригласить/назначить нужного сотрудника.

## Разрешения

`scope`: `all` — без ограничений; `own` — только своя организация (клейм `mo_code`; без клейма разрешение пустое, API отвечает 403 с `detail: "no_organization"`); «—» — нет доступа.

| Код | Разрешение (RU) | citizen | doctor | org_admin | regulator | steward | auditor | admin |
|---|---|---|---|---|---|---|---|---|
| `route.own` | Просмотр своего маршрута | all | all | own | — | — | — | all |
| `wait.public` | Просмотр сроков ожидания (публично) | all | all | all | all | all | all | all |
| `medicines.check` | Проверка рецепта | all | all | — | — | — | — | all |
| `worklist.view` | Рабочий список пациентов | — | own | own | — | — | — | all |
| `referral.assist` | Ассистент направления | — | all | — | — | — | — | all |
| `referral.confirm` | Подтверждение направления | — | all | own | — | — | — | all |
| `scribe.use` | AI-скрайб | — | all | — | — | — | — | all |
| `decisions.own` | Журнал решений (свои) | — | all | own | — | — | all | all |
| `decisions.all` | Журнал решений (все) | — | — | own | all | — | all | all |
| `gov.map` | Карта регионов и прогнозы (+ регион, качество моделей) | — | — | — | all | all | all | all |
| `gov.simulator` | Симулятор «что если» | — | — | — | all | — | — | all |
| `insight.ask` | Вопросы к данным (AI) | — | — | — | all | all | — | all |
| `org.cabinet` | Кабинет организации (обзор, направления и отказы) | — | — | own | all | — | — | all |
| `admin.users` | Аудит и управление пользователями (пользователи, врачи, журнал аудита) | — | — | own | — | — | all | all |

`bed_manager` в этой таблице не показан — роль не сидируется миграцией и появляется в матрице только после того, как её создали через `admin.roles` (см. раздел «Роли» выше); тогда же в её строке появятся `worklist.view: own` и `referral.confirm: own`.

Системные разрешения — не показываются в матрице и не редактируются: `data.steward` (консоль оператора данных, загрузка партий: steward, admin), `admin.orgs` (организации и заявки на регистрацию: regulator, admin), `admin.roles` (матрица ролей, создание ролей: admin). `wait.public` не снимается ни с одной роли; анонимные агрегаты ожидания остаются анонимными.

Хранение: таблицы схемы `auth` (миграция EF): `roles(key, title_ru, title_kk, description_ru, description_kk, builtin, created_at)`, `role_permissions(role, permission, scope)`, `role_permission_changes(id, at, actor, role, permission, old_scope, new_scope, comment)`. Сид — матрица выше. Кэш разрешений в API — 30 с, сбрасывается при изменении. Каждое изменение пишется в `role_permission_changes` и в `journal.audit`.

## Проверка на бэкенде

- Политика на каждое разрешение: `RequireAuthorization(Permissions.Policy("gov.map"))` (имя политики `perm:gov.map`); обработчик `PermissionAuthorizationHandler` берёт роли пользователя (realm roles после трансформации) → объединение разрешений из `role_permissions` (максимальный scope). `admin` проходит всё.
- Для `own` эндпоинт получает scope через `IPermissionService.ScopeFor(user, code)` и фильтрует по `CurrentUser.MoCode` (рабочий список, журнал решений, кабинет организации, пользователи). Попытка открыть чужую организацию — 403 `detail: "other_organization"`.
- Без политики остаются только публичные агрегаты: `/queue/predict`, `/index`, `/refdata/*`, `/public/*`, памятка по QR. Проверка рецепта и списки МНН — под `medicines.check`. Пример-карточки страницы входа получают данные из `GET /public/login-examples` (анонимно, кэш 1 ч).
- Сопоставление существующих эндпоинтов: `/route/me` и сигналы гражданина → `route.own`; `/route/{ref}` → `worklist.view`; `/route/{ref}/redirect`, `POST /journal/decisions`, ответ на сигнал → `referral.confirm`; `/journal/worklist` → `worklist.view`; `GET /journal/decisions` → `decisions.own` (свои) или `decisions.all` (все; при `own` — по `mo_code` актора); `/journal/audit` → `admin.users`; ассистент (альтернативы, объяснение, прогноз по направлению) → `referral.assist`; `/scribe/*` (кроме памятки по токену) → `scribe.use`; карта, индекс-детализации, аномалии, `/quality` → `gov.map`; `/simulate`, `/redistribute` → `gov.simulator`; `/insight/*` → `insight.ask`; ряды и кабинет организации → `org.cabinet`; `/intake/*` → `data.steward`.
- Уточнения реализации (эндпоинты, которые нужны двум экранам): `POST /queue/alternatives` по региону и профилю — `wait.public` (экран «Сроки ожидания» гражданина), с полями направления (`icd10`, `referralPurpose`, `territorialType`, `financeSource`, `referringMoCode`) — `referral.assist`; `/quality` — `gov.map` или `referral.assist` (качество модели в ассистенте); `/anomalies` и подтверждение сигнала — `gov.map` или `org.cabinet` (при `own` — сигналы своей организации); `POST /journal/decisions` с `subject: "scenario"` (решение в симуляторе) — `gov.simulator`; ряды и медтехника организации (`/queue/organizations/{mo}`, `/equipment/organizations/{mo}`) — `org.cabinet`; `/queue/overloaded`, `/streams`, `/forecast/*`, `/los`, `/staffing`, `/equipment`, `/vaccination-refusals`, `/oncology-late-stage` — `gov.map`. Отказ — 403 problem с `detail` `permission_required` (+ `permissions: [...]`), `no_organization` или `other_organization`; назначение недоступной роли — 403 `role_not_assignable`.
- Тесты: на каждое разрешение — позитивный и негативный запрос по ролям из матрицы; `own` — своя и чужая организация; изменение матрицы через API меняет доступ без перезапуска.

## Новые эндпоинты (все под `/api/v1`)

Ошибки — существующий `application/problem+json`; списки — `{ items, total, page, size }`.

**Я и мой аккаунт** (любой вошедший)
- `GET /me` → `{ actor, userId, displayName, email, emailVerified, roles: string[], permissions: [{ code, scope }], moCode, moName, regionKato, iinMasked, onboarding: { emailVerified, otpConfigured, profileChecked, colleaguesInvited } }`.
- `POST /me/access-requests` `{ permission, path, comment? }` → 202; пишется в аудит, видно администратору организации/системы.
- `GET /me/profile`, `PUT /me/profile` `{ phone?, language, timeZone }` (ФИО, должность, специальность — только чтение, «меняет администратор»).
- `GET /me/security` → `{ passwordChangedAt, otpConfigured, smsAvailable: false, recoveryCodes: null, recentLogins: [{ at, method, success, ip }], sessions: [{ id, device, browser, ip, lastAccess, current }] }`; `DELETE /me/sessions/{id}`; `DELETE /me/sessions?keepCurrent=true`. Смена пароля и приложение-аутентификатор — редиректом в Keycloak (`kc_action=UPDATE_PASSWORD` / `CONFIGURE_TOTP`).
- `GET /me/notifications`, `PUT /me/notifications` `{ events: [{ code, inApp, email, sms, push }], quietFrom, quietTo, quietExceptRegulator, digest }` (событие `security` всегда включено).
- `GET /me/consents`, `PUT /me/consents/{code}` `{ granted }` (коды `forecasts` — обязательное, `anonymized_stats`, `research_exports`); `GET /me/access-log` — кто и что смотрел по мне (из аудита); `GET /me/export` — CSV; `POST /me/deletion-request`.

**Администрирование** (`admin.users` — пользователи, врачи; при `own` — только своя организация и назначение только `doctor`/`org_admin`/`bed_manager` в ней — `PermissionCatalog.OrgAssignableRoles`)
- `GET /admin/users?role&moCode&status&q&page&size` → строки `{ id, username, displayName, email, roles, moCode, moName, regionKato, lastActivity, status: active|invited|blocked, via: egov|password }` + сводка `{ active, invitedStale, blocked }`.
- `GET /admin/users/{id}`; `PUT /admin/users/{id}` `{ role, moCode?, regionKato? }`; `POST /admin/users/{id}/block`; `POST /admin/users/{id}/unblock`.
- `POST /admin/users/invite` `{ email, displayName, role, moCode?, regionKato? }` → пользователь в Keycloak (выключен до принятия), токен приглашения на 7 дней, письмо со ссылкой `/invite/{token}`; без SMTP ответ содержит `inviteUrl` для ручной передачи и `emailSent: false`.
- `GET /admin/doctors?regionKato&moCode&specialty&verification&page` → `{ id, displayName, specialty, moCode, moName, regionKato, referrals, matchRate, verification: pending|verified|rejected }` (направления и совпадение — из журнала решений за квартал); `POST /admin/doctors/{id}/verification` `{ status, comment? }`.
- `GET /admin/roles` → `{ roles, permissions (каталог RU/KK), matrix: [{ role, permission, scope }], usersByRole }` (`admin.roles`); `PUT /admin/roles/{key}/permissions` `{ changes: [{ permission, scope|null }], comment? }`; `POST /admin/roles` `{ key, titleRu, titleKk, descriptionRu?, copyFrom? }` (создаёт realm role в Keycloak); `GET /admin/roles/history?role`.
- `GET /admin/orgs?regionKato&type&status&page`, `GET /admin/orgs/{moCode}` (`admin.orgs`) → справочник организаций + число пользователей + статус подключения (есть данные очередей = «подключена», иначе «нет данных») + свежесть загрузок по наборам; администратор организации из Keycloak.
- `GET /admin/org-applications?status`, `POST /admin/org-applications/{id}/approve` (создаёт `org_admin` с приглашением), `POST /admin/org-applications/{id}/reject` `{ reason }` (`admin.orgs`).

**Публичное** (анонимно, rate limit)
- `POST /public/org-applications` `{ orgName, bin, type, regionKato, moCode?, adminName, email, phone, consent }` → `{ id, number, statusToken }`; отправляет 6-значный код на почту.
- `POST /public/org-applications/{id}/verify-email` `{ code, statusToken }`; `POST /public/org-applications/{id}/resend-code`; `GET /public/org-applications/{id}?statusToken=` → `{ number, orgName, email, status: pending_email|pending_review|approved|rejected, submittedAt }`.
- `GET /public/invites/{token}` → `{ displayName, email, orgName, moCode, role, invitedBy, invitedAt, expiresAt }`; `POST /public/invites/{token}/accept` `{ password, acceptedRules }` (пароль — по политике realm; пользователь включается, почта подтверждается); `POST /public/invites/{token}/decline`.
- `GET /public/login-examples` → `{ wait: { regionName, profileName, p50Days, p90Days, within30 }, rx: { mnn, covered, fillP50, fillP90 } }`.
- `POST /public/password-reset` `{ email }` → всегда 202 `{ accepted: true }`, не раскрывая, есть ли такая почта; если пользователь найден и включён — Admin API `PUT /users/{id}/execute-actions-email` `["UPDATE_PASSWORD"]` (срок 1 ч, `client_id=darumen-web`, `redirect_uri` — корень веба `Web:PublicOrigin`), письмо шлёт Keycloak своим SMTP. Экран «Восстановление пароля» в мобилке.

Почта: `IEmailSender` (SMTP из `Mail:Smtp:*`; в dev — Mailpit `localhost:1025`, интерфейс `localhost:8025`); шаблоны — по доске «Письма системы». Без SMTP письма не уходят, API говорит об этом явно.

## Keycloak

- Realm: `loginTheme` и `emailTheme` = `darumen`; `ru`/`kk`; `rememberMe`, `resetPasswordAllowed`; `bruteForceProtected` (5 попыток, блокировка 15 мин); политика паролей `length(12) and upperCase(1) and lowerCase(1) and digits(1) and notUsername and passwordHistory(5)` (демо-пароли не меняются — политика действует при смене); OTP — TOTP, 6 цифр, 30 с; `ssoSessionIdleTimeout` 30 мин, «запомнить» — 30 дней; события входа хранятся 30 дней; SMTP из переменных окружения.
- Клиент `darumen-admin` (confidential, service account, секрет из `KEYCLOAK_ADMIN_CLIENT_SECRET`): роли `realm-management` `view-users`, `manage-users`, `query-users`, `view-events`, `view-realm`, `manage-realm` — только для API.
- Страницы темы по доскам W-Auth-*: вход, «Забыли пароль», «Письмо отправлено», новый пароль со шкалой надёжности, «Пароль изменён», второй фактор (TOTP; SMS — «после интеграции»), настройка аутентификатора, ошибки, «ссылка устарела», «аккаунт заблокирован», «сессия истекла», выход.

## Клиенты

- **Веб**: `useAuth().can(code)`, мета маршрута `permission`, меню строится из разрешений; при отказе — состояние «Нет доступа к разделу» с кнопкой «Запросить доступ» (`POST /me/access-requests`). Домашний экран — первый доступный: `admin.roles` → пользователи; `org.cabinet` + `mo_code` → кабинет своей организации; `worklist.view` → рабочий список; `data.steward` → консоль оператора данных; `admin.users` → журнал аудита; `gov.map` → карта; `route.own` → «Мой путь».
- **Мобилка**: тот же `/me`; shell врача при `worklist.view`, гражданина при `route.own`; остальные роли — экран «Кабинет доступен в веб-версии».
- Проверки на клиенте — только UX: любое действие перепроверяется API, 403 от API показывается как «Нет доступа».
- Гостевого режима нет: без входа открыты только страница входа, регистрация организации, приглашение и памятка по QR. Ссылка «Сроки ожидания без входа» с досок входа не переносится (гость убран 27.09.2026).
