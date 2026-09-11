#!/usr/bin/env bash
# Деплой Darumen на VM dc.jurek.kz (Hetzner): rsync кода и витрин + docker compose на хосте.
#
#   scripts/deploy.sh                # полный цикл: sync → build → up → publish → health
#   scripts/deploy.sh --replace-dc   # то же, но сначала гасит старый стек GovTech Camp (/srv/govtech-camp)
#   scripts/deploy.sh --no-publish   # без перепубликации gold в Postgres (только код)
#
# Требования: ssh-доступ deploy@195.201.7.56 по ключу, docker на VM, файл infra/deploy/.env.prod
# (образец — infra/deploy/.env.prod.example). Хостовый Caddy уже проксирует dc.jurek.kz → 127.0.0.1:5173.
set -euo pipefail

HOST="${DEPLOY_HOST:-deploy@195.201.7.56}"
DEST="${DEPLOY_PATH:-/srv/darumen}"
ENV_FILE="${DEPLOY_ENV_FILE:-infra/deploy/.env.prod}"
OLD_STACK="${OLD_STACK_PATH:-/srv/govtech-camp}"
URL="${PUBLIC_URL:-https://dc.jurek.kz}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

REPLACE_DC=0; PUBLISH=1
for arg in "$@"; do
  case "$arg" in
    --replace-dc) REPLACE_DC=1 ;;
    --no-publish) PUBLISH=0 ;;
    *) echo "unknown flag: $arg" >&2; exit 2 ;;
  esac
done

[ -f "$ROOT/$ENV_FILE" ] || { echo "нет $ENV_FILE — скопируйте infra/deploy/.env.prod.example и заполните" >&2; exit 1; }
for d in gold models refdata; do
  [ -d "$ROOT/lakehouse/$d" ] || { echo "нет lakehouse/$d — сначала make data / make train" >&2; exit 1; }
done

RSYNC=(rsync -az --delete
  --exclude '.git' --exclude '/DataSets' --exclude '/lakehouse' --exclude '/mlruns' --exclude '/refdata'
  --exclude '.venv' --exclude 'node_modules' --exclude 'bin' --exclude 'obj' --exclude '__pycache__'
  --exclude 'dist' --exclude '/apps/mobile' --exclude '/docs' --exclude '.env' --exclude '.env.*'
  --exclude 'infra/cube/.cubestore' --exclude '.DS_Store' --exclude '*.duckdb')

echo "→ создаю $DEST на $HOST"
# /srv принадлежит root: если mkdir не проходит, пробуем sudo без пароля; иначе подсказываем, что сделать руками
ssh "$HOST" "mkdir -p '$DEST/lakehouse' 2>/dev/null || (sudo -n mkdir -p '$DEST/lakehouse' && sudo -n chown -R \$(id -u):\$(id -g) '$DEST')" || {
  echo "✗ не могу создать $DEST под пользователем ${HOST%@*}. Один раз выполните:" >&2
  echo "    ssh -t $HOST 'sudo mkdir -p $DEST && sudo chown \$(id -u):\$(id -g) $DEST'" >&2
  echo "  либо деплойте в домашний каталог: DEPLOY_PATH=~/darumen make deploy ARGS=--replace-dc" >&2
  exit 1
}

echo "→ синхронизирую код"
"${RSYNC[@]}" "$ROOT/" "$HOST:$DEST/"

echo "→ синхронизирую витрины lakehouse (gold, models, refdata, manifests)"
rsync -az --delete \
  --include '/gold/***' --include '/models/***' --include '/refdata/***' --include '/manifests/***' --exclude '*' \
  "$ROOT/lakehouse/" "$HOST:$DEST/lakehouse/"

echo "→ кладу .env"
scp -q "$ROOT/$ENV_FILE" "$HOST:$DEST/.env"

# LAKEHOUSE_DIR задаём из DEST, чтобы .env.prod не зависел от пути на VM
COMPOSE="LAKEHOUSE_DIR=$DEST/lakehouse docker compose -f $DEST/infra/docker-compose.prod.yml --env-file $DEST/.env"

if [ "$REPLACE_DC" = 1 ]; then
  echo "→ останавливаю старый стек GovTech Camp в $OLD_STACK (тома не трогаю)"
  ssh "$HOST" "if [ -f '$OLD_STACK/docker-compose.prod.yml' ]; then cd '$OLD_STACK' && docker compose -f docker-compose.prod.yml down; else echo '   старого стека нет, пропускаю'; fi"
fi

echo "→ сборка и запуск"
ssh "$HOST" "cd '$DEST' && $COMPOSE build --pull && $COMPOSE up -d --remove-orphans"

if [ "$PUBLISH" = 1 ]; then
  echo "→ публикую gold и refdata в Postgres"
  ssh "$HOST" "cd '$DEST' && $COMPOSE --profile tools run --rm publish"
fi

echo "→ чищу неиспользуемые образы"
# кэш сборки на 8 ГБ VM быстро съедает диск: оставляем 2 ГБ для инкрементальных сборок
ssh "$HOST" "docker image prune -f >/dev/null; docker builder prune -f --keep-storage 2GB >/dev/null"

echo "→ проверка"
ssh "$HOST" "$COMPOSE ps"
for i in $(seq 1 30); do
  if curl -fsS --max-time 5 "$URL/health" >/dev/null 2>&1; then
    echo "✓ $URL/health отвечает"; curl -fsS --max-time 10 "$URL/api/v1/" ; echo; exit 0
  fi
  sleep 2
done
echo "✗ $URL/health не ответил за 60 с — смотрите: ssh $HOST '$COMPOSE logs --tail=100 api'" >&2
exit 1
