# Darumen — мобильное приложение

Flutter-клиент Darumen Health для двух ролей: **гражданин** (Главная с карточкой «Моя госпитализация», Мой путь,
Сколько ждут, Лекарства, Вакцинация, Уведомления, Профиль) и **врач ПМСП** (Пациенты → маршрут пациента →
ассистент направления, Скрайб, Профиль). Структура — по образцу NHS App: три вкладки у гражданина, статусы вместо
новостей, каждое число подписано меткой происхождения («ML‑модель», «формула», «AI‑черновик»).

## Запуск

```bash
flutter pub get
flutter run -d emulator-5554 --dart-define=API_BASE=http://10.0.2.2:8000 --dart-define=KEYCLOAK_URL=http://10.0.2.2:8080   # Android
flutter run -d "iPhone 17"   --dart-define=API_BASE=http://localhost:8000  --dart-define=KEYCLOAK_URL=http://localhost:8080  # iOS-симулятор
flutter run --dart-define=API_BASE=https://dc.jurek.kz --dart-define=KEYCLOAK_URL=https://dc.jurek.kz/auth               # стенд
```

Без `--dart-define` берутся адреса локального стека (`make up`): Android-эмулятор ходит на `10.0.2.2`, остальные — на
`localhost`. Все параметры сборки — в `lib/config/env.dart` (`API_BASE`, `KEYCLOAK_URL`, `DEFAULT_REGION`, `EGOV_ENABLED`).
В debug-сборке разрешён http (эмулятор), в release — только https (`android/app/src/*/res/xml/network_security_config.xml`).

Вход — Keycloak (realm `darumen`, клиент `darumen-mobile`): демо-пользователи `citizen1` и `doctor1`, пароль `darumen`.
Кнопка «Войти через eGov mobile» до появления доступа от НИТ ведёт на экран «Скоро» (см. `docs/egov-auth.md`).
Гость видит публичные экраны без входа. Токены хранятся в защищённом хранилище платформы (`flutter_secure_storage`);
на web-таргете — в localStorage браузера.

## Структура

- `lib/theme/` — токены «Clinical Minimal» (`tokens.dart`), типографика Onest (`typography.dart`), тона статусов
  (`tones.dart`), сборка светлой и тёмной тем (`app_theme.dart`). Экраны не используют `Colors.*` напрямую — CI это проверяет.
- `lib/widgets/` — `PageScaffold`, `Section`, `KpiTile`, `OriginTag`, `StatusChip`, `RouteTimeline`, `ChecklistTile`,
  `EmptyState`, `Skeleton`, `ErrorBox`, `LoadStateView`, `RouteView` (общее тело маршрута для обеих ролей), `AppShell`.
- `lib/router/` — два `StatefulShellRoute` (гражданин `/home`, `/updates`, `/profile`; врач `/doctor/*`) и чистый `guard`.
- `lib/state/` — `Session` (роль, регион и ИИН из клеймов токена), `TokenStore`, `LoadState`.
- `lib/api/` — `ApiClient` (Bearer + `Accept-Language`) и модели, включая `PatientRoute` (`docs/api.md`, раздел Route).
- `lib/l10n/strings.dart` — ручной словарь RU/KK; казахский длиннее на ~15 %, подписи вкладок ≤ 12 символов.
- `assets/fonts/` — Onest 400/500/600/700 (SIL OFL 1.1, `OFL.txt`), покрывает казахскую кириллицу, есть `tnum`.

## Проверка

```bash
flutter analyze && flutter test
```

Тесты: guard роутера по ролям, сессия с мок-Keycloak (клеймы, обновление токена, invalid_grant), тема и токены,
виджеты (таймлайн, метка происхождения, чек-лист, казахский при масштабе 1.3× без переполнений), модели API.
