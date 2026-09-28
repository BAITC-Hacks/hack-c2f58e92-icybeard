#!/usr/bin/env bash
# CD-релизы Darumen на VM — forced command отдельного SSH-ключа CI в ~deploy/.ssh/authorized_keys:
#
#   command="/srv/darumen/bin/release.sh",no-pty,no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-user-rc ssh-ed25519 AAAA… darumen-ci
#
# Граница доверия. Ключ CI может только выбрать тег образов нашего реестра (ghcr.io/baitc-hacks/…), откатить стенд на
# прошлый релиз и посмотреть состояние. Файлов от CI скрипт не принимает и не читает. Форма инфраструктуры —
# compose-файл, SQL db-init и сами скрипты релиза — меняется только через `make vm-install-release`: человек кладёт
# шаблон (состав — infra/deploy/template-files.txt) в /srv/darumen/bin/template, а /srv/darumen/bin/release.sh и
# restore.sh — симлинки на копии из шаблона. Секреты — только в /srv/darumen/.env, релиз его не трогает.
#
# Протокол (команда — в SSH_ORIGINAL_COMMAND, при ручном запуске на VM — аргументами):
#   release <тег> <пользователь GHCR> <sha256 шаблона>
#       stdin: одна строка — токен GHCR для docker pull (пустая — без docker login); всё после первой строки
#       не читается. Хэш шаблона release.yml считает по чекауту тега (template-hash.sh); если он не совпал с
#       установленным шаблоном — отказ «шаблон на VM устарел» до любых изменений.
#   rollback   вернуть предыдущий релиз (симлинк previous)
#   status     какой релиз запущен, хэш установленного шаблона, релизы на диске, свежие бэкапы
#
# release: снимок шаблона в releases/<тег> → `compose config` с .env VM → pull образов <тег> → дамп БД перед
# релизом → up -d (db-init, keycloak, realm-sync, …) → healthcheck и realm-sync → smoke по 127.0.0.1:5173 →
# current → releases/<тег>, previous → прошлый. Сбой после up — автооткат на прежний current (или на ручной деплой
# из /srv/darumen/infra, если CD-релизов ещё не было). Вложенного восстановления нет: если не поднялся и откат,
# скрипт пишет «ОТКАТ НЕ УДАЛСЯ» и выходит — дальше человек (docs/deploy.md, «Откат»). Хранит 5 релизов, чистит
# образы остальных и кэш сборки.
set -euo pipefail
umask 027

# Переопределения DARUMEN_RELEASE_* — только для локальной проверки: клиент SSH переменные окружения передать не
# может (AcceptEnv sshd пропускает лишь LANG/LC_*, PermitUserEnvironment выключен), в проде — значения по умолчанию.
DARUMEN_DIR="${DARUMEN_RELEASE_DIR:-/srv/darumen}"
ENV_FILE="${DARUMEN_RELEASE_ENV_FILE:-$DARUMEN_DIR/.env}"
LAKEHOUSE_DIR="${DARUMEN_RELEASE_LAKEHOUSE_DIR:-$DARUMEN_DIR/lakehouse}"
BACKUP_DIR="${DARUMEN_RELEASE_BACKUP_DIR:-$DARUMEN_DIR/backups}"
PROJECT="${DARUMEN_RELEASE_PROJECT:-darumen}"
SMOKE_BASE="${DARUMEN_RELEASE_SMOKE_BASE:-http://127.0.0.1:5173}"
PULL="${DARUMEN_RELEASE_PULL:-1}"
WAIT_SECONDS="${DARUMEN_RELEASE_WAIT_SECONDS:-420}"
REGISTRY="ghcr.io/baitc-hacks/hack-c2f58e92-icybeard"
IMAGES=(api web models keycloak keycloak-config)
TEMPLATE_DIR="$DARUMEN_DIR/bin/template"
TEMPLATE_LIST="infra/deploy/template-files.txt"
RELEASES="$DARUMEN_DIR/releases"
KEEP=5
# путь|что ждём: text — любой ответ 2xx (MapHealthChecks отдаёт «Healthy»), json — JSON-объект
SMOKE_CHECKS=("/health|text" "/auth/realms/darumen|json" "/api/v1/public/service-status|json")

LOG_FILE=""
log() {
  local line
  line="$(date '+%Y-%m-%d %H:%M:%S') release: $*"
  printf '%s\n' "$line" >&2
  if [ -n "$LOG_FILE" ]; then printf '%s\n' "$line" >> "$LOG_FILE"; fi
}
die() { log "ОШИБКА: $1"; exit "${2:-1}"; }
# Релиз отклонён до изменения стека: отметка в каталоге релиза и код 3
reject() { echo rejected > "$1/STATUS"; die "$2 — стенд не трогал" 3; }

usage() {
  cat >&2 <<'EOF'
usage: release <тег> <пользователь GHCR> <sha256 шаблона>   (stdin: одна строка — токен GHCR)
       rollback
       status
EOF
  exit 2
}

# --- docker compose для каталога релиза -----------------------------------------------------------------------
# $1 — каталог с infra/docker-compose.prod.yml, $2 — тег образов. Переменные окружения главнее .env VM, поэтому
# REGISTRY/IMAGE_TAG/пути из .env на релиз не влияют.
dc() {
  local dir="$1" tag="$2"
  shift 2
  REGISTRY="$REGISTRY" IMAGE_TAG="$tag" LAKEHOUSE_DIR="$LAKEHOUSE_DIR" BACKUP_DIR="$BACKUP_DIR" \
    docker compose -p "$PROJECT" -f "$dir/infra/docker-compose.prod.yml" --env-file "$ENV_FILE" "$@"
}

release_tag_of() { cat "$1/IMAGE_TAG" 2>/dev/null || echo local; }

link_target() { # абсолютный путь, на который указывает симлинк, или пусто
  if [ -L "$1" ]; then (cd "$DARUMEN_DIR" && cd "$(readlink "$1")" 2>/dev/null && pwd -P) || true; fi
}

# Куда откатываться, если CD-релизов ещё не было: ручной деплой (scripts/deploy.sh) лежит в корне DARUMEN_DIR
manual_target() {
  if [ -f "$DARUMEN_DIR/infra/docker-compose.prod.yml" ]; then printf '%s\n' "$DARUMEN_DIR"; fi
}

# Хэш шаблона в каталоге $1 — тем же template-hash.sh, что в release.yml (он сам входит в шаблон)
template_hash() {
  sh "$1/infra/deploy/template-hash.sh" "$1"
}

# --- блокировка: один релиз за раз ----------------------------------------------------------------------------
acquire_lock() {
  mkdir -p "$RELEASES"
  if command -v flock >/dev/null 2>&1; then
    exec 9>"$RELEASES/.lock"
    flock -n 9 || die "уже идёт другой релиз или откат (блокировка $RELEASES/.lock)" 75
  else
    # запасной вариант без util-linux (локальная проверка на macOS)
    mkdir "$RELEASES/.lock.d" 2>/dev/null || die "уже идёт другой релиз (каталог $RELEASES/.lock.d)" 75
    trap 'rmdir "$RELEASES/.lock.d" 2>/dev/null || true' EXIT
  fi
}

# Дампы и страховочные копии читает только владелец (deploy): VM общая с POS и другими пользователями
protect_backups() {
  mkdir -p "$BACKUP_DIR"
  chmod -R go-rwx "$BACKUP_DIR" 2>/dev/null || log "⚠ не все файлы в $BACKUP_DIR удалось закрыть от группы и других пользователей (чужой владелец?)"
}

# --- образы ---------------------------------------------------------------------------------------------------
# Токен живёт только в переменной и во временном DOCKER_CONFIG (0700), который удаляется сразу после pull:
# ~/.docker/config.json пользователя deploy (там могут быть учётки POS для ghcr.io) не трогаем.
pull_images() {
  local dir="$1" tag="$2" token="$3" user="$4" cfg img rc=0
  cfg="$(mktemp -d)"
  if [ -n "$token" ]; then
    if ! printf '%s' "$token" | docker --config "$cfg" login ghcr.io -u "$user" --password-stdin >/dev/null; then
      rm -rf "$cfg"
      log "docker login ghcr.io не прошёл (токен истёк или нет packages:read)"
      return 1
    fi
  fi
  while IFS= read -r img; do
    [ -n "$img" ] || continue
    log "pull $img"
    if ! docker --config "$cfg" pull -q "$img" >/dev/null; then
      log "не удалось скачать $img"
      rc=1
      break
    fi
  done < <(dc "$dir" "$tag" config --images | sort -u)
  if [ -n "$token" ]; then docker --config "$cfg" logout ghcr.io >/dev/null 2>&1 || true; fi
  rm -rf "$cfg"
  return "$rc"
}

images_present() { # все образы релиза есть локально — можно поднимать без реестра (откат)
  local dir="$1" tag="$2" img
  while IFS= read -r img; do
    [ -n "$img" ] || continue
    docker image inspect "$img" >/dev/null 2>&1 || { log "нет образа $img"; return 1; }
  done < <(dc "$dir" "$tag" config --images | sort -u)
}

# --- запуск и проверки ----------------------------------------------------------------------------------------
backup_before_release() {
  local cid
  cid="$(docker ps -q --filter "label=com.docker.compose.project=$PROJECT" \
    --filter label=com.docker.compose.service=backup --filter status=running | head -n1)"
  if [ -z "$cid" ]; then
    log "сервис backup ещё не запущен — дамп перед релизом пропускаю (первый релиз с бэкапами)"
    return 0
  fi
  log "дамп darumen и keycloak перед релизом (backups/last)"
  # docker exec не наследует umask основного процесса контейнера — задаём тот же, что в compose (0077)
  docker exec "$cid" bash -c 'umask 0077 && exec /backup.sh' >/dev/null 2>&1 \
    || { log "дамп перед релизом не удался (docker logs $cid)"; return 1; }
}

wait_stack() {
  local dir="$1" tag="$2" deadline=$((SECONDS + WAIT_SECONDS)) next_note=$((SECONDS + 30)) svc state code health bad pending
  while :; do
    bad=""
    pending=""
    while IFS='|' read -r svc state code health; do
      [ -n "$svc" ] || continue
      case "$svc" in
        db-init|realm-sync)
          if [ "$state" = exited ]; then
            [ "$code" = 0 ] || bad="$bad $svc(exit $code)"
          else
            pending="$pending $svc($state)"
          fi ;;
        backup)
          # не для пользователей: достаточно, что планировщик запущен (его healthcheck не должен валить релиз)
          case "$state" in
            running) ;;
            restarting|created) pending="$pending $svc($state)" ;;
            *) bad="$bad $svc($state)" ;;
          esac ;;
        *)
          case "$state" in
            running)
              if [ -n "$health" ] && [ "$health" != healthy ]; then pending="$pending $svc($health)"; fi ;;
            restarting|created) pending="$pending $svc($state)" ;;
            *) bad="$bad $svc($state)" ;;
          esac ;;
      esac
    done < <(dc "$dir" "$tag" ps -a --format '{{.Service}}|{{.State}}|{{.ExitCode}}|{{.Health}}')
    if [ -n "$bad" ]; then log "сервисы упали:$bad"; return 1; fi
    if [ -z "$pending" ]; then log "все сервисы healthy, db-init и realm-sync завершились успешно"; return 0; fi
    if [ "$SECONDS" -ge "$deadline" ]; then log "не дождался за ${WAIT_SECONDS} с:$pending"; return 1; fi
    if [ "$SECONDS" -ge "$next_note" ]; then log "жду:$pending"; next_note=$((SECONDS + 30)); fi
    sleep 5
  done
}

smoke() {
  local check path kind url body
  for check in "${SMOKE_CHECKS[@]}"; do
    path="${check%%|*}"
    kind="${check##*|}"
    url="$SMOKE_BASE$path"
    body=""
    for _ in $(seq 1 20); do
      if body="$(curl -fsS --max-time 10 "$url" 2>/dev/null)" && [ -n "$body" ]; then
        if [ "$kind" != json ] || [ "${body#\{}" != "$body" ]; then break; fi
      fi
      body=""
      sleep 3
    done
    if [ -z "$body" ]; then log "smoke: $url не ответил ($kind)"; return 1; fi
    log "smoke: $url OK"
  done
}

# Поднять стек из каталога $1 с тегом $2 и проверить; 0 — всё хорошо
bring_up() {
  local dir="$1" tag="$2"
  log "up -d: $dir (образы $tag)"
  dc "$dir" "$tag" up -d --no-build --pull never --remove-orphans || { log "docker compose up завершился с ошибкой"; return 1; }
  wait_stack "$dir" "$tag" || return 1
  smoke || return 1
}

dump_failure_context() {
  local dir="$1" tag="$2"
  dc "$dir" "$tag" ps -a --format 'table {{.Service}}\t{{.State}}\t{{.Status}}' >&2 || true
  dc "$dir" "$tag" logs --no-color --tail=40 realm-sync keycloak api >&2 2>/dev/null || true
}

set_link() { # замена симлинка $1 → $2 (относительный путь внутри DARUMEN_DIR)
  # Без -T mv положил бы временную ссылку ВНУТРЬ каталога, на который указывает старая ссылка
  if mv --version >/dev/null 2>&1; then   # GNU coreutils (VM): атомарно через rename
    ln -sfn "$2" "$DARUMEN_DIR/.$1.tmp"
    mv -Tf "$DARUMEN_DIR/.$1.tmp" "$DARUMEN_DIR/$1"
  else                                    # BSD (локальная проверка на macOS)
    ln -sfn "$2" "$DARUMEN_DIR/$1"
  fi
}

rel_path() { # releases/<тег> для каталога релиза, иначе пусто (ручной деплой)
  case "$1" in
    "$RELEASES"/*) printf 'releases/%s\n' "${1#"$RELEASES"/}" ;;
  esac
}

# --- уборка: 5 последних релизов и их образы ------------------------------------------------------------------
prune() {
  local cur prev dir n=0 keep_tags=" local " repo tag
  cur="$(link_target "$DARUMEN_DIR/current")"
  prev="$(link_target "$DARUMEN_DIR/previous")"
  while IFS= read -r dir; do
    dir="${dir%/}"
    [ -d "$dir" ] || continue
    n=$((n + 1))
    if [ "$n" -le "$KEEP" ] || [ "$dir" = "$cur" ] || [ "$dir" = "$prev" ]; then
      keep_tags="$keep_tags$(release_tag_of "$dir") "
    else
      log "удаляю старый релиз $(basename "$dir")"
      rm -rf "$dir"
    fi
  done < <(ls -1dt "$RELEASES"/*/ 2>/dev/null)
  find "$RELEASES" -maxdepth 1 -name '.incoming.*' -mmin +60 -exec rm -rf {} + 2>/dev/null || true
  for repo in "${IMAGES[@]}"; do
    while IFS= read -r tag; do
      case "$keep_tags" in
        *" $tag "*) ;;
        *) if docker image rm "$REGISTRY/$repo:$tag" >/dev/null 2>&1; then log "удалён образ $repo:$tag"; fi ;;
      esac
    done < <(docker image ls "$REGISTRY/$repo" --format '{{.Tag}}')
  done
  docker image prune -f >/dev/null || true
  docker builder prune -f --keep-storage 2GB >/dev/null 2>&1 || true
}

# --- команды --------------------------------------------------------------------------------------------------
cmd_release() {
  local tag="$1" user="$2" want="$3" token="" rc=0 t0 have stage rel prev_dir prev_tag cur f
  acquire_lock

  # stdin: только первая строка (не длиннее 4096 символов, не дольше 30 с) — токен GHCR. Остальное не читается:
  # stdin сразу отключается, никакие данные от CI дальше не попадают ни в файлы, ни в команды.
  t0=$SECONDS
  IFS= read -r -t 30 -n 4096 token || rc=$?
  exec 0</dev/null
  # таймаут: bash ≥ 4 возвращает код > 128, bash 3.2 — 1, поэтому смотрим и на прошедшее время
  if [ "$rc" -gt 128 ] || { [ "$rc" -ne 0 ] && [ $((SECONDS - t0)) -ge 30 ]; }; then
    die "не дождался токена GHCR в stdin (30 с)" 2
  fi
  if [ -n "$token" ] && ! [[ "$token" =~ ^[A-Za-z0-9_.=-]{1,4096}$ ]]; then
    token=""
    die "токен GHCR недопустимого формата" 2
  fi

  # Шаблон на VM должен совпасть с шаблоном тега — проверка до любых изменений на диске и в стеке
  [ -f "$TEMPLATE_DIR/$TEMPLATE_LIST" ] \
    || die "шаблон на VM не установлен ($TEMPLATE_DIR) — выполните make vm-install-release" 3
  have="$(template_hash "$TEMPLATE_DIR")" \
    || die "не удалось посчитать хэш шаблона $TEMPLATE_DIR — выполните make vm-install-release" 3
  if [ "$have" != "$want" ]; then
    die "шаблон на VM устарел — выполните make vm-install-release (на VM $have, у тега $want)" 3
  fi

  # Снимок шаблона для этого релиза (по нему же пойдёт откат) и повторная сверка — на случай установки посреди копирования
  mkdir -p "$RELEASES"
  stage="$(mktemp -d "$RELEASES/.incoming.XXXXXX")"
  while IFS= read -r f; do
    mkdir -p "$stage/$(dirname "$f")"
    cp -p "$TEMPLATE_DIR/$f" "$stage/$f"
  done < "$TEMPLATE_DIR/$TEMPLATE_LIST"
  if [ "$(template_hash "$stage" 2>/dev/null)" != "$want" ]; then
    rm -rf "$stage"
    die "шаблон менялся во время релиза — повторите запуск" 3
  fi

  rel="$RELEASES/$tag"
  cur="$(link_target "$DARUMEN_DIR/current")"
  if [ "$cur" = "$rel" ]; then log "тег $tag уже текущий — выкатываю повторно"; fi
  rm -rf "$rel"
  mv "$stage" "$rel"
  printf '%s\n' "$tag" > "$rel/IMAGE_TAG"
  printf '%s\n' "$want" > "$rel/TEMPLATE_SHA256"
  echo pending > "$rel/STATUS"
  LOG_FILE="$rel/release.log"
  log "релиз $tag: шаблон $want"

  [ -f "$ENV_FILE" ] || reject "$rel" "нет $ENV_FILE — секреты стенда кладутся руками (docs/deploy.md)"
  for d in gold models refdata; do
    [ -d "$LAKEHOUSE_DIR/$d" ] || reject "$rel" "нет $LAKEHOUSE_DIR/$d — сначала make deploy-data с машины с данными"
  done
  dc "$rel" "$tag" config -q || reject "$rel" "docker compose config не прошёл (не хватает переменной в .env? см. вывод выше)"

  if [ "$PULL" = 1 ]; then
    pull_images "$rel" "$tag" "$token" "$user" || { token=""; reject "$rel" "pull образов не удался"; }
  else
    log "pull пропущен (DARUMEN_RELEASE_PULL=0) — образы должны быть локально"
  fi
  token=""
  images_present "$rel" "$tag" || reject "$rel" "не все образы $tag на месте"

  # Прежнее состояние для автоотката: текущий CD-релиз, иначе ручной деплой
  prev_dir="$cur"
  if [ -z "$prev_dir" ] || [ "$prev_dir" = "$rel" ]; then prev_dir="$(link_target "$DARUMEN_DIR/previous")"; fi
  if [ -z "$prev_dir" ]; then prev_dir="$(manual_target)"; fi
  protect_backups
  backup_before_release || reject "$rel" "без свежего дампа релиз не выкатываю"

  if bring_up "$rel" "$tag"; then
    if [ -n "$cur" ] && [ "$cur" != "$rel" ]; then set_link previous "$(rel_path "$cur")"; fi
    set_link current "releases/$tag"
    rm -f "$DARUMEN_DIR/MANUAL_DEPLOY"   # отметка scripts/deploy.sh: стенд снова на CD-релизе
    echo ok > "$rel/STATUS"
    log "релиз $tag выкачен: current → releases/$tag"
    prune
    return 0
  fi

  echo failed > "$rel/STATUS"
  log "релиз $tag НЕ прошёл проверки"
  dump_failure_context "$rel" "$tag"
  [ -n "$prev_dir" ] || die "откатываться некуда (ни прошлого релиза, ни ручного деплоя) — стенд в состоянии $tag"
  prev_tag="$(release_tag_of "$prev_dir")"
  log "автооткат на $prev_dir (образы $prev_tag)"
  if images_present "$prev_dir" "$prev_tag" && bring_up "$prev_dir" "$prev_tag"; then
    log "откат выполнен, стенд снова на $prev_tag"
  else
    # Вложенного восстановления нет намеренно: третий up поверх двух неудачных чаще вредит, чем помогает
    log "ОТКАТ НЕ УДАЛСЯ — нужен человек: ssh deploy@VM, /srv/darumen/bin/release.sh status (docs/deploy.md, «Откат»)"
  fi
  exit 1
}

cmd_rollback() {
  local cur prev prev_tag
  acquire_lock
  cur="$(link_target "$DARUMEN_DIR/current")"
  prev="$(link_target "$DARUMEN_DIR/previous")"
  if [ -z "$prev" ]; then
    prev="$(manual_target)"
    [ -n "$prev" ] || die "нет предыдущего релиза и ручного деплоя — откатываться некуда"
    log "предыдущего CD-релиза нет — откатываюсь на ручной деплой ($prev)"
  fi
  prev_tag="$(release_tag_of "$prev")"
  images_present "$prev" "$prev_tag" || die "образы $prev_tag удалены — выкатите нужный тег заново (release)"
  log "откат: ${cur:-?} → $prev (образы $prev_tag)"
  if ! bring_up "$prev" "$prev_tag"; then
    dump_failure_context "$prev" "$prev_tag"
    die "откат не прошёл проверки — нужен человек (docs/deploy.md, «Откат»)"
  fi
  if [ -n "$(rel_path "$prev")" ]; then
    set_link current "$(rel_path "$prev")"
  else
    rm -f "$DARUMEN_DIR/current"
  fi
  if [ -n "$cur" ] && [ -n "$(rel_path "$cur")" ]; then
    set_link previous "$(rel_path "$cur")"
    echo rolled-back > "$cur/STATUS"
  else
    rm -f "$DARUMEN_DIR/previous"
  fi
  log "откат выполнен: стенд на $prev_tag"
}

cmd_status() {
  local cur prev dir installed
  cur="$(link_target "$DARUMEN_DIR/current")"
  prev="$(link_target "$DARUMEN_DIR/previous")"
  installed="$(template_hash "$TEMPLATE_DIR" 2>/dev/null || echo "не установлен — make vm-install-release")"
  echo "шаблон:   $installed"
  echo "current:  ${cur:-нет (ручной деплой или ещё не было релизов)}"
  if [ -n "$cur" ]; then echo "          шаблон релиза $(cat "$cur/TEMPLATE_SHA256" 2>/dev/null || echo '?')"; fi
  if [ -f "$DARUMEN_DIR/MANUAL_DEPLOY" ]; then
    echo "поверх него ручной деплой (make deploy): $(cat "$DARUMEN_DIR/MANUAL_DEPLOY")"
  fi
  echo "previous: ${prev:-нет}"
  echo "релизы (новые сверху):"
  while IFS= read -r dir; do
    dir="${dir%/}"
    printf '  %-24s образы %-16s %s\n' "$(basename "$dir")" "$(release_tag_of "$dir")" "$(cat "$dir/STATUS" 2>/dev/null || echo '?')"
  done < <(ls -1dt "$RELEASES"/*/ 2>/dev/null)
  echo "контейнеры:"
  docker ps -a --filter "label=com.docker.compose.project=$PROJECT" \
    --format '  {{.Label "com.docker.compose.service"}}  {{.Image}}  {{.Status}}' | sort
  echo "диск:"
  df -h "$DARUMEN_DIR" | sed 's/^/  /'
  echo "последние бэкапы:"
  # shellcheck disable=SC2012 # имена дампов фиксированные (<db>-<дата>.sql.gz)
  if [ -d "$BACKUP_DIR/last" ]; then ls -1t "$BACKUP_DIR/last" | head -n 4 | sed 's/^/  /'; else echo "  нет"; fi
  if [ -n "$(find "$ENV_FILE" "$BACKUP_DIR" -maxdepth 0 \( -perm -g=r -o -perm -o=r \) 2>/dev/null)" ]; then
    echo "⚠ .env или каталог бэкапов доступны группе или другим пользователям VM: chmod 600 $ENV_FILE; chmod -R go-rwx $BACKUP_DIR"
  fi
}

# --- разбор команды -------------------------------------------------------------------------------------------
if [ -n "${SSH_ORIGINAL_COMMAND:-}" ]; then
  read -r -a ARGV <<< "$SSH_ORIGINAL_COMMAND"
elif [ "$#" -gt 0 ]; then
  ARGV=("$@")
else
  usage
fi

TAG_RE='^(v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]{0,30})?|sha-[0-9a-f]{7,40})$'
USER_RE='^[A-Za-z0-9][A-Za-z0-9-]{0,38}(\[bot\])?$'
HASH_RE='^[0-9a-f]{64}$'

case "${ARGV[0]:-}" in
  release)
    [ "${#ARGV[@]}" -eq 4 ] || usage
    [[ "${ARGV[1]}" =~ $TAG_RE ]] || die "недопустимый тег '${ARGV[1]}' (vX.Y.Z[-pre] или sha-<hex>)" 2
    [[ "${ARGV[2]}" =~ $USER_RE ]] || die "недопустимое имя пользователя реестра" 2
    [[ "${ARGV[3]}" =~ $HASH_RE ]] || die "недопустимый хэш шаблона (ожидается sha256: 64 символа 0-9a-f)" 2
    cmd_release "${ARGV[1]}" "${ARGV[2]}" "${ARGV[3]}" ;;
  rollback)
    [ "${#ARGV[@]}" -eq 1 ] || usage
    cmd_rollback ;;
  status)
    [ "${#ARGV[@]}" -eq 1 ] || usage
    cmd_status ;;
  *) usage ;;
esac
