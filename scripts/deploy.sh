#!/usr/bin/env bash
# shellcheck disable=SC2029 # команды для VM намеренно собираются на клиенте (пути и флаги отсюда)
# Ручной деплой Darumen на VM: rsync кода и витрин + сборка образов и docker compose на хосте. Куда — цель
# infra/deploy/targets/<TARGET>.env: govtech (по умолчанию) — VPS хакатона, https://icybeard.govtech-kz.com;
# jurek — Hetzner, https://dc.jurek.kz. Пример: TARGET=jurek scripts/deploy.sh (или make deploy TARGET=jurek).
# Основной путь — CD по тегу (.github/workflows/release.yml → /srv/darumen/bin/release.sh, образы из GHCR);
# этот скрипт нужен для данных (lakehouse есть только на машине разработчика) и как запасной путь без CI.
#
#   scripts/deploy.sh                # полный цикл: sync кода и витрин → build → up → publish → проверка
#   scripts/deploy.sh --data-only    # только витрины lakehouse + publish в Postgres (make deploy-data), код и образы не трогает
#   scripts/deploy.sh --replace-dc   # полный цикл, но сначала гасит старый стек GovTech Camp (/srv/govtech-camp)
#   scripts/deploy.sh --no-publish   # без перепубликации gold в Postgres (только код)
#
# Требования: ssh-доступ к хосту цели по ключу, docker compose на VM, env-файл цели (DEPLOY_ENV_FILE; образец —
# infra/deploy/.env.prod.example). TLS терминирует Caddy на хосте и проксирует домен на 127.0.0.1:<WEB_PORT из env>.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Значения цели; переменные окружения DEPLOY_HOST, DEPLOY_PATH, DEPLOY_ENV_FILE, PUBLIC_URL, DEPLOY_PRUNE главнее файла
TARGET="${TARGET:-govtech}"
[[ "$TARGET" =~ ^[a-z0-9-]+$ ]] || { echo "недопустимая цель '$TARGET'" >&2; exit 2; }
TARGET_FILE="$ROOT/infra/deploy/targets/$TARGET.env"
if [ ! -f "$TARGET_FILE" ]; then
  printf "нет цели '%s' — есть:" "$TARGET" >&2
  for f in "$ROOT"/infra/deploy/targets/*.env; do printf ' %s' "$(basename "$f" .env)" >&2; done
  echo >&2
  exit 2
fi
while IFS='=' read -r key value; do
  case "$key" in
    '' | '#'*) continue ;;
    DEPLOY_HOST | DEPLOY_PATH | DEPLOY_ENV_FILE | PUBLIC_URL | DEPLOY_PRUNE | DEPLOY_SEQUENTIAL_BUILD) ;;
    *) echo "$TARGET_FILE: неизвестный ключ $key" >&2; exit 2 ;;
  esac
  if [ -z "${!key:-}" ]; then printf -v "$key" '%s' "$value"; fi
done < "$TARGET_FILE"
HOST="${DEPLOY_HOST:?в цели $TARGET нет DEPLOY_HOST}"
DEST="${DEPLOY_PATH:?в цели $TARGET нет DEPLOY_PATH}"
ENV_FILE="${DEPLOY_ENV_FILE:?в цели $TARGET нет DEPLOY_ENV_FILE}"
URL="${PUBLIC_URL:?в цели $TARGET нет PUBLIC_URL}"
PRUNE="${DEPLOY_PRUNE:-0}"
SEQUENTIAL_BUILD="${DEPLOY_SEQUENTIAL_BUILD:-0}"
OLD_STACK="${OLD_STACK_PATH:-/srv/govtech-camp}"
echo "цель $TARGET: $HOST:$DEST → $URL"

REPLACE_DC=0; PUBLISH=1; DATA_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --replace-dc) REPLACE_DC=1 ;;
    --no-publish) PUBLISH=0 ;;
    --data-only) DATA_ONLY=1 ;;
    *) echo "unknown flag: $arg" >&2; exit 2 ;;
  esac
done

[ -f "$ROOT/$ENV_FILE" ] || { echo "нет $ENV_FILE — скопируйте infra/deploy/.env.prod.example и заполните (docs/deploy.md, «Цели деплоя»)" >&2; exit 1; }
# Имена обязательных переменных (значения не читаем и не печатаем)
for var in POSTGRES_PASSWORD KEYCLOAK_DB_PASSWORD KEYCLOAK_ADMIN_PASSWORD KEYCLOAK_ADMIN_CLIENT_SECRET; do
  grep -Eq "^${var}=.+" "$ROOT/$ENV_FILE" || { echo "в $ENV_FILE не задан $var (см. infra/deploy/.env.prod.example)" >&2; exit 1; }
done
for d in gold models refdata; do
  [ -d "$ROOT/lakehouse/$d" ] || { echo "нет lakehouse/$d — сначала make data / make train" >&2; exit 1; }
done

# Каталоги CD (releases, current, previous, bin) и бэкапы живут в том же /srv/darumen — rsync --delete их не трогает
RSYNC=(rsync -az --delete
  --exclude '.git' --exclude '/DataSets' --exclude '/lakehouse' --exclude '/mlruns'
  --exclude '.venv' --exclude 'node_modules' --exclude 'bin' --exclude 'obj' --exclude '__pycache__'
  --exclude 'dist' --exclude '/apps/mobile' --exclude '/docs' --exclude '.env' --exclude '.env.*'
  --exclude 'infra/cube/.cubestore' --exclude '.DS_Store' --exclude '*.duckdb'
  --exclude '/releases' --exclude '/current' --exclude '/previous' --exclude '/.current.tmp' --exclude '/.previous.tmp'
  --exclude '/backups' --exclude '/MANUAL_DEPLOY')

echo "→ создаю $DEST на $HOST"
# /srv принадлежит root: если mkdir не проходит, пробуем sudo без пароля; иначе подсказываем, что сделать руками
ssh "$HOST" "mkdir -p '$DEST/lakehouse' '$DEST/backups' 2>/dev/null || (sudo -n mkdir -p '$DEST/lakehouse' '$DEST/backups' && sudo -n chown -R \$(id -u):\$(id -g) '$DEST')" || {
  echo "✗ не могу создать $DEST под пользователем ${HOST%@*}. Один раз выполните:" >&2
  echo "    ssh -t $HOST 'sudo mkdir -p $DEST && sudo chown \$(id -u):\$(id -g) $DEST'" >&2
  echo "  либо деплойте в домашний каталог: DEPLOY_PATH=~/darumen make deploy ARGS=--replace-dc" >&2
  exit 1
}

# Дампы (хэши паролей, секреты клиентов Keycloak) не должны читаться другими пользователями общей VM
ssh "$HOST" "chmod 700 '$DEST/backups' && chmod -R go-rwx '$DEST/backups'" \
  || echo "⚠ не удалось закрыть $DEST/backups от других пользователей VM — проверьте владельца файлов" >&2

if [ "$DATA_ONLY" = 0 ]; then
  echo "→ синхронизирую код"
  "${RSYNC[@]}" "$ROOT/" "$HOST:$DEST/"
fi

echo "→ синхронизирую витрины lakehouse (gold, models, refdata, manifests)"
rsync -az --delete \
  --include '/gold/***' --include '/models/***' --include '/refdata/***' --include '/manifests/***' --exclude '*' \
  "$ROOT/lakehouse/" "$HOST:$DEST/lakehouse/"

if [ "$DATA_ONLY" = 0 ]; then
  echo "→ кладу .env"
  scp -q "$ROOT/$ENV_FILE" "$HOST:$DEST/.env"
  ssh "$HOST" "chmod 600 '$DEST/.env'"
fi

# Пути и образы задаём явно: переменные окружения главнее .env. Ручной деплой собирает образы на VM с тегом local;
# для --data-only берём compose-файл текущего CD-релиза, если он есть (тег — из releases/<тег>/IMAGE_TAG).
# BACKUP_UID/GID — чтобы дампы на хосте принадлежали пользователю стенда; раскрываются на VM. В rootless Docker (VPS
# хакатона) на пользователя хоста отображается только root контейнера (0:0), в обычном — его собственные uid:gid.
ROOTLESS="docker info --format '{{.SecurityOptions}}' 2>/dev/null | grep -q rootless"
REMOTE_ENV="LAKEHOUSE_DIR=$DEST/lakehouse BACKUP_DIR=$DEST/backups BACKUP_UID=\$($ROOTLESS && echo 0 || id -u) BACKUP_GID=\$($ROOTLESS && echo 0 || id -g)"
COMPOSE="$REMOTE_ENV IMAGE_TAG=local docker compose -p darumen -f $DEST/infra/docker-compose.prod.yml --env-file $DEST/.env"
if [ "$DATA_ONLY" = 1 ]; then
  COMPOSE="if [ -f $DEST/current/IMAGE_TAG ]; then F=$DEST/current/infra/docker-compose.prod.yml; T=\$(cat $DEST/current/IMAGE_TAG); else F=$DEST/infra/docker-compose.prod.yml; T=local; fi; $REMOTE_ENV IMAGE_TAG=\$T docker compose -p darumen -f \$F --env-file $DEST/.env"
  echo "→ публикую gold и refdata в Postgres (образы и контейнеры не трогаю)"
  ssh "$HOST" "cd '$DEST' && $COMPOSE --profile tools run --rm publish"
  echo "✓ данные обновлены; сервис моделей перечитает витрины после перезапуска: ssh $HOST 'docker restart darumen-models-1'"
  exit 0
fi

if [ "$REPLACE_DC" = 1 ]; then
  echo "→ останавливаю старый стек GovTech Camp в $OLD_STACK (тома не трогаю)"
  ssh "$HOST" "if [ -f '$OLD_STACK/docker-compose.prod.yml' ]; then cd '$OLD_STACK' && docker compose -f docker-compose.prod.yml down; else echo '   старого стека нет, пропускаю'; fi"
fi

echo "→ сборка и запуск"
if [ "$SEQUENTIAL_BUILD" = 1 ]; then
  # по одному сервису: на маленькой общей VM параллельная сборка .NET, Vite, Python и Keycloak уводит её в swap
  # shellcheck disable=SC2016 # $s раскрывается на VM
  ssh "$HOST" "cd '$DEST' && for s in \$($COMPOSE config --services); do $COMPOSE build --pull \"\$s\" || exit 1; done && $COMPOSE up -d --remove-orphans"
else
  ssh "$HOST" "cd '$DEST' && $COMPOSE build --pull && $COMPOSE up -d --remove-orphans"
fi
ssh "$HOST" "printf 'manual %s %s\n' '$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)' \"\$(date -u +%FT%TZ)\" > '$DEST/MANUAL_DEPLOY'"

echo "→ жду realm-sync (keycloak-config-cli приводит realm к infra/keycloak/darumen-realm.json)"
# shellcheck disable=SC2016 # $cid и $code раскрываются на VM
ssh "$HOST" 'cid=$(docker ps -aq --filter label=com.docker.compose.project=darumen --filter label=com.docker.compose.service=realm-sync | head -n1); [ -n "$cid" ] || { echo "✗ контейнер realm-sync не найден" >&2; exit 1; }; code=$(docker wait "$cid"); if [ "$code" != 0 ]; then docker logs --tail 60 "$cid" >&2; echo "✗ realm-sync завершился с кодом $code" >&2; exit 1; fi; echo "✓ realm-sync: realm применён"'

if [ "$PUBLISH" = 1 ]; then
  echo "→ публикую gold и refdata в Postgres"
  ssh "$HOST" "cd '$DEST' && $COMPOSE --profile tools run --rm publish"
fi

if [ "$PRUNE" = 1 ]; then
  echo "→ чищу неиспользуемые образы"
  # кэш сборки на 8 ГБ VM быстро съедает диск: оставляем 2 ГБ для инкрементальных сборок
  ssh "$HOST" "docker image prune -f >/dev/null; docker builder prune -f --keep-storage 2GB >/dev/null"
else
  echo "→ образы и кэш сборки не чищу (DEPLOY_PRUNE=0: Docker на хосте общий с другими командами)"
fi

echo "→ проверка"
ssh "$HOST" "$COMPOSE ps"
check() { # $1 — путь, $2 — сколько попыток по 2 с
  local _
  for _ in $(seq 1 "$2"); do
    if curl -fsS --max-time 5 "$URL$1" >/dev/null 2>&1; then echo "✓ $URL$1 отвечает"; return 0; fi
    sleep 2
  done
  echo "✗ $URL$1 не ответил за $(( $2 * 2 )) с — смотрите: ssh $HOST 'cd $DEST && $COMPOSE logs --tail=100 api keycloak'" >&2
  return 1
}
check /health 60
check /auth/realms/darumen 30
check /api/v1/public/service-status 15
curl -fsS --max-time 10 "$URL/api/v1/"; echo
