# Darumen — мобильное приложение

Flutter-клиент Darumen Health для двух ролей: **гражданин** (Главная, Мой путь, Сколько ждут, Проверка рецепта,
Вакцинация, Уведомления, Профиль) и **врач** (Пациенты → маршрут пациента → AI-скрайб, Входящие направления
принимающей больницы, Журнал решений, Уведомления персонала, ассистент нового направления, Профиль). Остальные роли
видят экран «Кабинет доступен в веб-версии». Приложение повторяет веб-кабинет в телефонной раскладке: тексты RU/KK —
дословно из веб-словарей, кнопки действий — только из того, что разрешил сервер (`progress.allowed` маршрута,
`allowed` входящего направления), машину состояний маршрута клиент не считает. Дизайн — «синяя гамма»
(`docs/design-system.md`, токены `design/tokens.json`): белые карточки, плавающая пилюля вкладок, у каждого числа —
метка происхождения («прогноз модели», «расчёт по правилу», «черновик ИИ»).

## Экраны и маршруты

| Путь | Экран | Кто видит |
|---|---|---|
| `/login`, `/login/otp`, `/login/forgot` | вход, второй фактор, восстановление пароля | все |
| `/home` | Главная: запрос записи приёма, карточка состояния маршрута с кнопками, «Ваша больница», плитки | гражданин (`route.own`), вкладка |
| `/home/route`, `/home/route/leaflet/:token` | Мой путь (этапы, прогноз, «Где быстрее», перевод, анализы, журнал) и памятка после приёма | гражданин |
| `/home/wait?region=&profile=`, `/home/medicines`, `/home/vaccination` | Сколько ждут, Проверка рецепта (`medicines.check`), Вакцинация | гражданин |
| `/updates` | Уведомления маршрута, счётчик на вкладке | гражданин, вкладка |
| `/profile` (+ `security`, `notifications`, `consents`) | Профиль: личные данные, язык, регион, безопасность, каналы, данные и согласия | гражданин, вкладка |
| `/doctor/patients`, `/doctor/patients/:ref` | рабочий список (приоритет 0…10, флаги, поиск, сортировка) и маршрут пациента | `worklist.view`, вкладка |
| `/doctor/patients/:ref/scribe` | AI-скрайб приёма по согласию пациента | `scribe.use` |
| `/doctor/incoming` | Входящие направления: подтвердить, отказать, перенести, госпитализирован, не пришёл, выписать | `worklist.view` + своя больница, вкладка со счётчиком |
| `/doctor/decisions` | Журнал решений | `decisions.own` или `decisions.all`, вкладка |
| `/doctor/profile` (+ те же экраны аккаунта) | Профиль врача | вкладка |
| `/doctor/notifications` | Уведомления персонала (колокольчик рабочего списка) | вне вкладок |
| `/doctor/referral?moCode=&profileCode=` | Ассистент нового направления | `referral.assist`, вне вкладок |
| `/web` | «Кабинет доступен в веб-версии» | роли без мобильного кабинета |

Кабинет выбирается по разрешениям (`lib/router/guards.dart`): `worklist.view` — врачебный, `route.own` — гражданский,
иначе `/web`. Неизвестный адрес ведёт на домашний экран роли. Внутри вкладок — `context.go`, экраны вне вкладок
открываются `context.push`.

## Запуск

Локальный стек поднимается из корня репозитория: `make up` (API на `:8000`, Keycloak на `:8080`, веб на `:3000`).
Тестовые маршруты в разных стадиях перевода — `python scripts/dev/seed_routes.py`.

```bash
flutter pub get
flutter run -d emulator-5554 --dart-define=API_BASE=http://10.0.2.2:8000 --dart-define=KEYCLOAK_URL=http://10.0.2.2:8080   # Android
flutter run -d "iPhone 17"   --dart-define=API_BASE=http://localhost:8000  --dart-define=KEYCLOAK_URL=http://localhost:8080  # iOS-симулятор
flutter run --dart-define=API_BASE=https://dc.jurek.kz --dart-define=KEYCLOAK_URL=https://dc.jurek.kz/auth               # стенд
```

Параметры сборки — в `lib/config/env.dart`:

| `--dart-define` | Что задаёт | Без флага |
|---|---|---|
| `API_BASE` | адрес API | `http://10.0.2.2:8000` на Android-эмуляторе, `http://localhost:8000` на остальных |
| `KEYCLOAK_URL` | адрес Keycloak | то же с портом `8080` |
| `WEB_BASE` | веб-кабинет: регистрация организации, действия Keycloak, публичная памятка, разделы только для веба | хост API, порт `8000` → `3000` |
| `DEFAULT_REGION` | регион учётной записи без клейма `region_kato` | `75` (г. Алматы) |

В debug-сборке разрешён http (эмулятор), в release — только https (`android/app/src/*/res/xml/network_security_config.xml`).

Вход — Keycloak (realm `darumen`, клиент `darumen-mobile`), пароль демо-пользователей `darumen`: `citizen1` —
гражданин (регион 75); `doctor1` — врач больницы 028B; `doctor2` — врач 22GN, принимающая больница для переводов из
028B; `chief1` — главврач 028B (входящие и журнал); `admin1` — врачебный кабинет без больницы; `regulator1`,
`steward1`, `auditor1` — экран веб-версии. Гостевого режима нет: без входа открыт только экран входа. Токены хранятся
в защищённом хранилище платформы (`flutter_secure_storage`); на web-таргете — в localStorage браузера.

Опросы сервера идут только на переднем плане: колокольчик гражданина и персонала — раз в минуту (и сразу после
действий и при возвращении в приложение), согласие пациента на запись — каждые 5 с, пока ждём ответа и экран виден.
Доступность внешних сервисов приложение берёт из `GET /api/v1/public/service-status` (без токена; при запуске, при
возвращении в приложение и каждые 5 минут): пока адрес eGov mobile (Smart Bridge) не предоставлен, кнопка «Войти
через eGov mobile» вторичная, с подписью «Сервис eGov mobile сейчас недоступен» (см. `docs/egov-auth.md`); пока почта
не работает — баннер в обоих кабинетах и карточка на экране восстановления пароля; почта, SMS и push в настройках
уведомлений выключены и подписаны причиной. Если статус получить не удалось — про почту ничего не утверждается,
push, SMS и eGov считаются недоступными.

## Структура

- `lib/api/` — `ApiClient` (`client.dart`: Bearer и `Accept-Language` на каждый запрос, `newIdempotencyKey` — один
  ключ на нажатие) и модели (`models.dart` реэкспортирует файлы по разделам контракта `docs/api.md`); экраны
  импортируют только эти два файла. Ошибки — `ApiException` (409 с `stateCode`, 422 с полями, 403 с причиной).
- `lib/state/` — `Session` (роль, разрешения, регион и больница), `AppScope` с общими провайдерами:
  `CitizenRouteController` (маршрут гражданина и его действия), `CitizenNotificationsNotifier` и
  `StaffBellNotifier` (колокольчики на `SessionPoller`), `ServiceStatusNotifier`.
- `lib/router/` — два `StatefulShellRoute` (гражданин и врач), чистый `guard` и вкладки со счётчиками.
- `lib/screens/` — по файлу на экран.
- `lib/widgets/` — общие виджеты (`PageScaffold`, `AppCard`, `StatusChip`, `OriginTag`, `KpiTile` / `StatGrid`,
  `HeroNumber`, `CollapsibleSection`, состояния загрузки и ошибок, `PickerSheet`, `api_error.dart` — один рецепт
  обработки ошибок, `format.dart`), набор маршрута `route/` (этапы, журнал, анализы, альтернативы, приоритет,
  факторы прогноза) и папки разделов: `citizen/`, `citizen_more/`, `account/`, `doctor/`, `incoming/`,
  `referral/`, `scribe/`, `decisions/`.
- `lib/l10n/` — ручной словарь RU/KK: класс `S` и части по разделам (`strings_route`, `strings_citizen`,
  `strings_doctor`, `strings_incoming`, `strings_scribe`, `strings_account`, …); ключ веба — в комментарии у строки.
- `lib/theme/` — токены (`tokens.dart`, паритет с `design/tokens.json`), шкала Manrope (`typography.dart`), тона
  (`tones.dart`), светлая и тёмная темы. Цвета — только из темы, размеры шрифта — только из шкалы; CI проверяет, что
  в `lib` нет `Colors.*`.
- `assets/fonts/` — Manrope 400/600/700/800 (SIL OFL 1.1, `OFL-Manrope.txt`).

## Проверка

```bash
flutter analyze && flutter test
flutter test test/incoming_referrals_test.dart          # один файл
flutter test --plain-name 'Kazakh'                      # по имени теста
```

Тесты сгруппированы по префиксу файла: `api_*` и `*_models_test` — клиент на `MockClient` (метод, путь, query, тело,
Idempotency-Key, разбор настоящих ответов из `test/fixtures/api`) и ошибки API; `theme_test`, `format_test`,
`design_*` — токены и общие виджеты; `route_kit_*` — набор маршрута; `citizen_*`, `citizen_more_*`, `account_*` —
экраны гражданина и аккаунта; `doctor_*`, `incoming_*`, `referral_*`, `scribe_*`, `decisions_*`,
`staff_notifications_test` — экраны врача; `state_*`, `session*`, `router_guard_test`, `shell_test`, `navigation_*`
— состояние, guard и навигация. `*_strings_test` сверяют словарь с `apps/web/src/i18n/*.ts` дословно, поэтому тесты
запускаются из полного репозитория. У каждого экрана есть проверка «казахский при масштабе 1.3 на телефоне 360 dp
без переполнений».

Проверка на живом локальном стеке — `test_live/` (в CI не входит, нужны `make up` и `python scripts/dev/seed_routes.py`):

```bash
flutter test test_live/api_contract_test.dart   # только чтение: маршруты, рабочий список, входящие, колокольчики, ошибки 409/422
flutter test test_live/api_chain_test.dart      # меняет стенд: согласие → подтверждение → выписка, согласие на запись → памятка
```

Обвязка виджет-тестов — `test/support/harness.dart`:

```dart
final (session, backend) = await demoSession(DemoUser.doctor2, api: {
  '/journal/referrals/incoming': fixtureList('incoming'),                     // 200 JSON
  'POST /journal/referrals/d-1/confirm': recorded(),                          // 201 {decisionId, recordedAt}
  '/route/me/consent': problem(409, 'Ждём подтверждения больницы', stateCode: 'transfer_pending_confirmation'),
  '/journal/notifications/bell': (http.Request request) => {...},             // ответ на каждый запрос
});
await pumpScreen(tester, session, const IncomingReferralsScreen(), locale: 'kk', textScale: 1.3, size: phoneNarrow);
final router = await pumpRouterApp(tester, session, location: '/doctor/incoming');   // всё приложение с роутером
expect(backend.calls('GET', '/journal/referrals/incoming').single.url.queryParameters['moCode'], '22GN');
```

`demoSession` входит демо-пользователем (`DemoUser`: роли и клеймы как в `infra/keycloak/darumen-realm.json`) через
мок-Keycloak; `/me` отвечает разрешениями из матрицы `docs/rbac.md`, фоновые опросы получают пустые ответы, остальное
неизвестное — 404. Ключ ответа — окончание пути, с методом впереди при необходимости; `backend.routes[...]` меняет
ответ посреди теста. `pumpScreen` ставит экран в те же провайдеры, тему и локализацию, что и приложение (без
GoRouter); `pumpRouterApp` — всё приложение с настоящим роутером, кабинетами и guard. Вместо `pumpAndSettle` —
`pumpFrames` (скелетоны пульсируют бесконечно).
