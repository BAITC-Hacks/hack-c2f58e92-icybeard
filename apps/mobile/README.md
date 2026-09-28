# Darumen — мобильное приложение

Flutter-клиент Darumen Health для двух ролей: **гражданин** (Главная с карточкой «Моя госпитализация», Мой путь,
Сколько ждут, Проверка рецепта, Вакцинация, Уведомления, Профиль) и **врач ПМСП** (Пациенты → маршрут пациента →
ассистент направления и AI-скрайб, Журнал решений, Профиль). Дизайн — «Тихая клиника» (`docs/design-system.md`,
доски холста Claude Design): молочный фон, чернильные карточки-кнопки, коралл как единственный сигнал, плавающая
пилюля навигации с тремя вкладками у каждой роли; каждое число подписано меткой происхождения («ML-модель»,
«Формула», «AI»).

## Запуск

```bash
flutter pub get
flutter run -d emulator-5554 --dart-define=API_BASE=http://10.0.2.2:8000 --dart-define=KEYCLOAK_URL=http://10.0.2.2:8080   # Android
flutter run -d "iPhone 17"   --dart-define=API_BASE=http://localhost:8000  --dart-define=KEYCLOAK_URL=http://localhost:8080  # iOS-симулятор
flutter run --dart-define=API_BASE=https://dc.jurek.kz --dart-define=KEYCLOAK_URL=https://dc.jurek.kz/auth               # стенд
```

Без `--dart-define` берутся адреса локального стека (`make up`): Android-эмулятор ходит на `10.0.2.2`, остальные — на
`localhost`. Все параметры сборки — в `lib/config/env.dart` (`API_BASE`, `KEYCLOAK_URL`, `DEFAULT_REGION`).
В debug-сборке разрешён http (эмулятор), в release — только https (`android/app/src/*/res/xml/network_security_config.xml`).

Вход — Keycloak (realm `darumen`, клиент `darumen-mobile`): демо-пользователи `citizen1` и `doctor1`, пароль `darumen`.
Доступность внешних сервисов приложение берёт из `GET /api/v1/public/service-status` (без токена; при запуске, при
возвращении в приложение и каждые 5 минут на переднем плане): пока адрес eGov mobile (Smart Bridge) не предоставлен,
кнопка «Войти через eGov mobile» вторичная, с подписью «Сервис eGov mobile сейчас недоступен», и лист объясняет, что
входить нужно по логину (см. `docs/egov-auth.md`); пока почта не работает — баннер в обоих кабинетах и карточка на
экране восстановления пароля; почта, SMS и push в настройках уведомлений выключены и подписаны причиной, сохранённые
значения не сбрасываются. Если статус получить не удалось — про почту ничего не утверждается, push, SMS и eGov
считаются недоступными.
Гостевого режима нет: без входа открыт только экран входа. Токены хранятся в защищённом хранилище платформы (`flutter_secure_storage`);
на web-таргете — в localStorage браузера.

## Структура

- `lib/theme/` — токены «Тихой клиники» (`tokens.dart`, паритет с `design/tokens.json` проверяет `theme_test`),
  шкала Manrope (`typography.dart`), тона чипов (`tones.dart`), сборка светлой и тёмной тем (`app_theme.dart`).
  Экраны не используют `Colors.*` напрямую — CI это проверяет.
- `lib/widgets/` — `PageScaffold` (шапка с круглыми кнопками и H1, нижняя зона под primary-кнопку), `AppCard` /
  `CardLabel` / `ListRow` / `FieldLabel`, `SignalCard` (coral-wash), `PillFilter`, `CircleIconButton` / `LanguageButton`,
  `HeroNumber`, `StageStepper` (полосы + маркер), `RouteTimeline`, `WaitBars`, `OriginTag`, `StatusChip`, `EmptyState`,
  `Skeleton`, `ErrorBox`, `LoadStateView`, `RouteView` / `DoctorRouteView`, `AppShell` с плавающей `FloatingNav`.
- `lib/router/` — два `StatefulShellRoute` (гражданин `/home`, `/updates`, `/profile`; врач `/doctor/patients`,
  `/doctor/decisions`, `/doctor/profile`; ассистент и скрайб — `/doctor/patients/:ref/{referral,scribe}` и без
  пациента `/doctor/referral`, `/doctor/scribe` вне вкладок) и чистый `guard`.
- `lib/state/` — `Session` (роль, регион и ИИН из клеймов токена), `TokenStore`, `LoadState`.
- `lib/api/` — `ApiClient` (Bearer + `Accept-Language`) и модели, включая `PatientRoute` (`docs/api.md`, раздел Route).
- `lib/l10n/strings.dart` — ручной словарь RU/KK; казахский длиннее на ~15 %, подписи вкладок ≤ 12 символов.
- `assets/fonts/` — Manrope 400/500/600 (SIL OFL 1.1, `OFL-Manrope.txt`), покрывает казахскую кириллицу, есть `tnum`.

## Проверка

```bash
flutter analyze && flutter test
```

Тесты: guard роутера по ролям, shell с плавающей навигацией (три вкладки у каждой роли, скрытие на вложенных
экранах), сессия с мок-Keycloak (клеймы, обновление токена, invalid_grant), тема и токены (паритет с
`design/tokens.json`), экраны на мок-API (вход без гостя, главная без погоды, маршрут с «Понятно», рабочий список,
журнал, скрайб), виджеты (степпер, таймлайн, метка происхождения, чек-лист, казахский при масштабе 1.3× без
переполнений), модели API.
