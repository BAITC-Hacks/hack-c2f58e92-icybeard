#!/usr/bin/env bash
# Восстановление одной БД стенда (darumen или keycloak) из дампа сервиса backup (postgres-backup-local).
# Запускается на VM под deploy (руками или `make restore` с ноутбука):
#
#   restore.sh --list                          # какие дампы есть
#   restore.sh keycloak                        # из last/keycloak-latest.sql.gz (последний дамп)
#   restore.sh darumen daily/darumen-20261001.sql.gz
#   restore.sh keycloak /abs/path/keycloak-x.sql.gz --yes   # без вопроса (для скриптов)
#
# Что делает: 1) страховочный дамп текущей БД в BACKUP_DIR/pre-restore/; 2) останавливает сервисы, которые пишут в
# эту БД (keycloak — keycloak; darumen — api и intake); 3) пересоздаёт БД (DROP ... WITH (FORCE), CREATE ... OWNER);
# 4) заливает дамп через psql с ON_ERROR_STOP; 5) запускает сервисы обратно и ждёт healthcheck.
# Postgres и остальные сервисы не перезапускаются. Секреты не читаются и не печатаются: psql работает внутри
# контейнера postgres от суперпользователя darumen по локальному сокету. Страховочные дампы (pre-restore/) читает
# только владелец: VM общая, в дампах хэши паролей и секреты клиентов Keycloak.
set -euo pipefail
umask 077

# Каталог стенда — родитель bin/, из которого запущен скрипт (<стенд>/bin/restore.sh — симлинк в шаблон)
SELF_BIN="$(cd "$(dirname "$0")" && pwd)"
if [ -z "${DARUMEN_DIR:-}" ] && [ "${SELF_BIN##*/}" != bin ]; then
  echo "restore.sh запускается как <каталог стенда>/bin/restore.sh или с DARUMEN_DIR=<каталог стенда>" >&2
  exit 2
fi
DARUMEN_DIR="${DARUMEN_DIR:-${SELF_BIN%/bin}}"
ENV_FILE="${ENV_FILE:-$DARUMEN_DIR/.env}"
BACKUP_DIR="${BACKUP_DIR:-$DARUMEN_DIR/backups}"
PROJECT="${COMPOSE_PROJECT:-darumen}"

log() { printf '%s restore: %s\n' "$(date '+%H:%M:%S')" "$*" >&2; }
die() { log "ОШИБКА: $*"; exit 1; }

usage() {
  sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

compose_file() {
  # CD-релиз (current → releases/<тег>) главнее ручного `make deploy` (исходники в корне DARUMEN_DIR)
  local f
  for f in "${COMPOSE_FILE_PATH:-}" "$DARUMEN_DIR/current/infra/docker-compose.prod.yml" "$DARUMEN_DIR/infra/docker-compose.prod.yml"; do
    if [ -n "$f" ] && [ -f "$f" ]; then printf '%s\n' "$f"; return 0; fi
  done
  die "не найден docker-compose.prod.yml (задайте COMPOSE_FILE_PATH)"
}

list_dumps() {
  [ -d "$BACKUP_DIR" ] || die "нет каталога бэкапов $BACKUP_DIR"
  (cd "$BACKUP_DIR" && find . -name '*.sql.gz' \( -type f -o -type l \) | sed 's|^\./||' | sort)
}

wait_healthy() {
  local svc="$1" cid status=""
  cid="$("${DC[@]}" ps -q "$svc")"
  [ -n "$cid" ] || die "контейнер $svc не найден"
  for _ in $(seq 1 60); do
    status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$cid")"
    case "$status" in
      healthy|running) log "$svc: $status"; return 0 ;;
    esac
    sleep 3
  done
  die "$svc не стал healthy за 3 минуты (последний статус: $status)"
}

YES=0
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --yes|-y) YES=1 ;;
    --list) list_dumps; exit 0 ;;
    -h|--help) usage ;;
    *) ARGS+=("$arg") ;;
  esac
done
[ "${#ARGS[@]}" -ge 1 ] && [ "${#ARGS[@]}" -le 2 ] || usage

DB="${ARGS[0]}"
case "$DB" in
  darumen) OWNER=darumen; SERVICES=(api intake) ;;
  keycloak) OWNER=keycloak; SERVICES=(keycloak) ;;
  *) die "БД должна быть darumen или keycloak, а не '$DB'" ;;
esac

DUMP="${ARGS[1]:-last/$DB-latest.sql.gz}"
case "$DUMP" in
  /*) ;;
  *) DUMP="$BACKUP_DIR/$DUMP" ;;
esac
[ -e "$DUMP" ] || die "нет дампа $DUMP (список: $0 --list)"
case "$(basename "$DUMP")" in
  "$DB"-*.sql.gz) ;;
  *) die "дамп $(basename "$DUMP") не похож на дамп БД $DB (ожидается $DB-*.sql.gz)" ;;
esac
gzip -t "$DUMP" || die "дамп $DUMP повреждён (gzip -t)"
[ -f "$ENV_FILE" ] || die "нет $ENV_FILE"

DC=(docker compose -p "$PROJECT" -f "$(compose_file)" --env-file "$ENV_FILE")
PG=("${DC[@]}" exec -T postgres)

# Останавливаем только то, что сейчас запущено (упавший intake не должен ломать восстановление)
STOP=()
while IFS= read -r running; do
  for svc in "${SERVICES[@]}"; do
    if [ "$svc" = "$running" ]; then STOP+=("$svc"); fi
  done
done < <("${DC[@]}" ps --status running --services)

log "БД $DB ← $(readlink -f "$DUMP") ($(du -h "$(readlink -f "$DUMP")" | cut -f1))"
stop_list="(ничего не запущено)"
if [ "${#STOP[@]}" -gt 0 ]; then stop_list="${STOP[*]}"; fi
log "будут остановлены на время восстановления: $stop_list"
if [ "$YES" != 1 ]; then
  [ -t 0 ] || die "без терминала нужен флаг --yes"
  read -r -p "Текущие данные БД $DB будут заменены. Введите имя БД для подтверждения: " answer
  [ "$answer" = "$DB" ] || die "подтверждение не совпало, ничего не менял"
fi

"${PG[@]}" pg_isready -U darumen -d postgres >/dev/null || die "postgres не отвечает"

mkdir -p "$BACKUP_DIR/pre-restore"
chmod 700 "$BACKUP_DIR/pre-restore"
SAFETY="$BACKUP_DIR/pre-restore/$DB-$(date +%Y%m%d-%H%M%S).sql.gz"
if "${PG[@]}" psql -U darumen -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '$DB'" | grep -q 1; then
  log "страховочный дамп текущей БД → $SAFETY"
  "${PG[@]}" pg_dump -U darumen -d "$DB" | gzip -6 > "$SAFETY"
fi

restart_services() {
  [ "${#STOP[@]}" -gt 0 ] || return 0
  log "запускаю ${STOP[*]}"
  "${DC[@]}" start "${STOP[@]}"
}
STOPPED=0
on_exit() {
  if [ "$STOPPED" = 1 ]; then
    log "восстановление НЕ завершено — запускаю сервисы обратно; прежнее состояние БД: $SAFETY"
    restart_services || true
  fi
}
trap on_exit EXIT

if [ "${#STOP[@]}" -gt 0 ]; then
  log "останавливаю ${STOP[*]}"
  STOPPED=1
  "${DC[@]}" stop "${STOP[@]}"
fi

"${PG[@]}" psql -U darumen -d postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname = '$OWNER'" | grep -q 1 \
  || die "нет роли $OWNER — сначала поднимите стек (db-init создаёт роль keycloak)"

log "пересоздаю БД $DB (владелец $OWNER)"
"${PG[@]}" psql -v ON_ERROR_STOP=1 -q -U darumen -d postgres \
  -c "DROP DATABASE IF EXISTS \"$DB\" WITH (FORCE)" \
  -c "CREATE DATABASE \"$DB\" OWNER \"$OWNER\""
if [ "$DB" = keycloak ]; then
  "${PG[@]}" psql -v ON_ERROR_STOP=1 -q -U darumen -d postgres \
    -c "REVOKE ALL ON DATABASE keycloak FROM PUBLIC" -c "GRANT CONNECT, TEMPORARY ON DATABASE keycloak TO keycloak"
fi

log "заливаю дамп"
gunzip -c "$DUMP" | "${PG[@]}" psql -v ON_ERROR_STOP=1 -q -U darumen -d "$DB" >/dev/null

STOPPED=0
restart_services
if [ "${#STOP[@]}" -gt 0 ]; then
  for svc in "${STOP[@]}"; do wait_healthy "$svc"; done
fi
log "готово: БД $DB восстановлена из $(basename "$DUMP"); прежнее состояние — $SAFETY"
