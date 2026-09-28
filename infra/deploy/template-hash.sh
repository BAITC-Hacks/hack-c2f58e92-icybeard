#!/bin/sh
# Хэш шаблона релиза — одна реализация на всех: release.yml (по чекауту тега), make vm-install-release (локально и
# на VM после установки) и release.sh на VM (по /srv/darumen/bin/template). Состав шаблона —
# infra/deploy/template-files.txt: пути от корня, по одному в строке, в порядке `LC_ALL=C sort`, без дублей;
# список перечисляет и сам себя. Хэш = sha256 от вывода `sha256sum <файлы списка>` (строки «<sha256>  <путь>»):
# меняется при правке, добавлении, удалении и переименовании любого файла шаблона.
#
#   sh infra/deploy/template-hash.sh .                                                  # корень репозитория
#   sh /srv/darumen/bin/template/infra/deploy/template-hash.sh /srv/darumen/bin/template   # на VM
set -eu

root="${1:?usage: template-hash.sh <корень шаблона>}"
list="infra/deploy/template-files.txt"

fail() {
  echo "template-hash: $*" >&2
  exit 1
}

cd "$root" || fail "нет каталога $root"
[ -f "$list" ] || fail "нет $root/$list"
# Только простые относительные пути: без пробелов, `..` и ведущего `/` — их безопасно передать sha256sum списком
if grep -Evq '^[A-Za-z0-9_][A-Za-z0-9._/-]*$' "$list" || grep -q '\.\.' "$list"; then
  fail "в $list недопустимая строка (разрешены [A-Za-z0-9._/-], без .., пустых строк и ведущего /)"
fi
LC_ALL=C sort -cu "$list" 2>/dev/null || fail "$list не отсортирован (LC_ALL=C sort) или содержит дубли"
grep -qx "$list" "$list" || fail "$list должен перечислять сам себя"
while IFS= read -r f; do
  [ -f "$f" ] && [ -r "$f" ] || fail "нет файла шаблона $root/$f"
done < "$list"

if command -v sha256sum >/dev/null 2>&1; then
  sha256() { sha256sum "$@"; }
else
  sha256() { shasum -a 256 "$@"; }   # macOS без coreutils: тот же формат «<sha256>  <путь>»
fi
# shellcheck disable=SC2046 # пути проверены выше: без пробелов и спецсимволов
sha256 $(cat "$list") | sha256 | cut -c1-64
