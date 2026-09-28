#!/bin/sh
# shellcheck disable=SC2016 # $( и ${ в шаблонах sed/grep — литералы, раскрывать их не нужно
# Переводит плейсхолдеры Keycloak `${VAR:по умолчанию}` / `${VAR}` в синтаксис keycloak-config-cli
# `$(env:VAR:-по умолчанию)` / `$(env:VAR)`.
# Один файл realm (infra/keycloak/darumen-realm.json) обслуживает и Keycloak (dev: start-dev --import-realm, прод:
# первый старт на пустой БД), и realm-sync (keycloak-config-cli): у Keycloak подстановка `${...}`, у config-cli —
# `$(...)` через Apache Commons StringSubstitutor, где значение по умолчанию отделяется `:-`.
# Трогаем только имена в ВЕРХНЕМ регистре: ключи сообщений Keycloak (`${username}`, `${email}`) в конфиге профиля
# пользователя — не переменные и должны остаться как есть. `)` в значении по умолчанию недопустим (это суффикс
# переменной у config-cli) — такой плейсхолдер останется непереведённым, и проверка ниже остановит сборку.
#
#   infra/keycloak/render-realm.sh infra/keycloak/darumen-realm.json > /tmp/realm-for-config-cli.json
set -eu

src="${1:?usage: render-realm.sh <realm.json>}"

if grep -q '\$(' "$src"; then
  echo "render-realm: в $src уже есть последовательность \$( — config-cli примет её за переменную" >&2
  exit 1
fi

out="$(sed -E \
  -e 's/\$\{([A-Z][A-Z0-9_]*):([^})]*)\}/$(env:\1:-\2)/g' \
  -e 's/\$\{([A-Z][A-Z0-9_]*)\}/$(env:\1)/g' \
  "$src")"

if printf '%s\n' "$out" | grep -Eq '\$\{[A-Z][A-Z0-9_]*[:}]'; then
  echo "render-realm: в $src остался непереведённый плейсхолдер \${VAR...} (скобка в значении по умолчанию?)" >&2
  exit 1
fi

printf '%s\n' "$out"
