#!/usr/bin/env bash
# Установка шаблона релиза на VM — только человеком, с обычным ssh-доступом deploy (make vm-install-release).
# Кладёт файлы из infra/deploy/template-files.txt (release.sh, restore.sh, template-hash.sh, compose-файл, SQL
# db-init) в /srv/darumen/bin/template, заменяя прежний шаблон целиком, и делает симлинки
# /srv/darumen/bin/release.sh и restore.sh на копии из шаблона. Ключ CI этого не может: его forced command
# принимает только release/rollback/status, а release сверяет хэш шаблона с хэшем тега.
# Повторять после правки любого файла из списка — до выпуска тега (иначе релиз откажет: «шаблон на VM устарел»).
#
#   infra/deploy/vm-install.sh                                   # deploy@195.201.7.56:/srv/darumen/bin
#   VM_SSH='sh -c' VM_DIR=/tmp/srv infra/deploy/vm-install.sh    # локальная проверка без ssh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LIST="infra/deploy/template-files.txt"
VM_DIR="${VM_DIR:-/srv/darumen}"
VM_SSH="${VM_SSH:-ssh ${DEPLOY_HOST:-deploy@195.201.7.56}}"

[[ "$VM_DIR" =~ ^/[A-Za-z0-9._/-]+$ ]] || { echo "VM_DIR должен быть абсолютным путём из [A-Za-z0-9._/-]" >&2; exit 2; }

cd "$ROOT"
local_hash="$(sh infra/deploy/template-hash.sh .)"
files=()
while IFS= read -r f; do files+=("$f"); done < "$LIST"

# release.yml считает хэш по файлам тега: незакоммиченные правки дадут другой хэш, и релиз тега будет отклонён
if ! git diff --quiet HEAD -- "${files[@]}" 2>/dev/null; then
  echo "⚠ файлы шаблона отличаются от HEAD: релиз пройдёт, только если тег указывает на это же содержимое" >&2
fi

# На VM: распаковать во временный каталог, атомарно подменить template, обновить симлинки, посчитать хэш
remote_script="$(cat <<'SH'
set -eu
umask 022
d="__VM_DIR__/bin"
mkdir -p "$d"
rm -rf "$d/.template.new" "$d/.template.old"
mkdir "$d/.template.new"
tar -xf - -C "$d/.template.new"
chmod -R go-w "$d/.template.new"
if [ -d "$d/template" ]; then mv "$d/template" "$d/.template.old"; fi
mv "$d/.template.new" "$d/template"
rm -rf "$d/.template.old"
ln -sfn template/infra/deploy/release.sh "$d/release.sh"
ln -sfn template/infra/deploy/restore.sh "$d/restore.sh"
sh "$d/template/infra/deploy/template-hash.sh" "$d/template"
SH
)"
remote_script="${remote_script//__VM_DIR__/$VM_DIR}"

# bsdtar (macOS) без расширенных атрибутов — иначе GNU tar на VM ругается на заголовки LIBARCHIVE.xattr
if tar --version 2>/dev/null | grep -q 'GNU tar'; then
  tar_create=(tar -cf -)
else
  tar_create=(env COPYFILE_DISABLE=1 tar --no-xattrs --no-mac-metadata -cf -)
fi

echo "→ шаблон $local_hash (${#files[@]} файлов) → $VM_DIR/bin/template"
# shellcheck disable=SC2086 # VM_SSH — команда с аргументами («ssh deploy@host» или «sh -c»)
remote_hash="$("${tar_create[@]}" "${files[@]}" | $VM_SSH "$remote_script")"

if [ "$remote_hash" != "$local_hash" ]; then
  echo "✗ хэш установленного шаблона $remote_hash ≠ локальному $local_hash" >&2
  exit 1
fi
echo "✓ шаблон установлен: $remote_hash"
echo "  forced command ключа CI: $VM_DIR/bin/release.sh (симлинк на шаблон), проверка: $VM_DIR/bin/release.sh status"
