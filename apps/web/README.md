# Darumen — веб-клиент

Vue 3 + TypeScript + Vite + PrimeVue 4.5. Роли — из Keycloak (realm `darumen`, публичный клиент `darumen-web`, PKCE);
гость видит «Ожидание для граждан» и «Проверку рецепта», остальные страницы — по ролям (`src/router/index.ts`, `meta.roles`).
Кнопка «Войти через eGov mobile» ведёт на экран «Скоро» до интеграции (`docs/egov-auth.md`).

## Запуск

```bash
cp .env.example .env              # адрес Keycloak (localhost:8080), база API пустая = прокси Vite на :8000
npm ci
npm run dev                       # http://localhost:5173, нужны make serve (Keycloak, Postgres) + API + make models-serve
npm run lint && npx vitest run    # vue-tsc + юнит-тесты (auth, roles, i18n-паритет, route, client, …)
npm run build                     # dist/ для nginx (infra/web.Dockerfile, infra/web/Dockerfile)
```

Демо-пользователи: `citizen1`, `doctor1`, `chief1`, `regulator1`, `steward1`, `admin1`, пароль `darumen`.

## Проверка в браузере

```bash
npm run walk                      # входит по ролям через Keycloak, снимает все страницы (RU/KK, светлая/тёмная) в e2e/shots
npm run deep-link                 # прямая ссылка на защищённую страницу после входа (Docker-сборка на :3000)
node e2e/login-check.mjs          # вход regulator1 → карта регионов на :3000
```

## Структура

- `src/router/` — маршруты с `meta.roles/title/nav` (меню шапки строится из них) и `roles.ts` (роли, домашние экраны).
- `src/stores/auth.ts` — сессия Keycloak (`keycloak-js`), `authHeaders()` для API, `keycloakUnavailable`.
- `src/api/` — `client.ts` (fetch + Bearer + `Accept-Language`), `endpoints.ts`, `types.ts` (контракты из `docs/api.md`).
- `src/views/` — страницы по ролям: `citizen/`, `route/` (Мой путь и маршрут пациента), `doctor/`, `gov/`, `steward/`.
- `src/components/` — `OriginTag` (метка «ML-модель / формула / AI-черновик» у каждого числа), графики, карта; `app/` — шапка, вход.
- `src/i18n/` — словари RU/KK (паритет ключей проверяет тест), `src/lib/` — форматирование и помощники маршрута.
