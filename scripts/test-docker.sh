#!/usr/bin/env bash
# Все тесты как в CI (.NET, Python, веб) в одном Linux-контейнере — для Windows, где make и protoc.exe не запускаются.
# Запуск из корня репозитория: test.cmd (Windows) или
#   docker run --rm -v "$PWD":/src:ro mcr.microsoft.com/dotnet/sdk:10.0 bash -c "tr -d '\r' < /src/scripts/test-docker.sh > /tmp/t.sh && bash /tmp/t.sh"
# Код копируется внутрь контейнера: рабочая копия (obj, node_modules, .venv) не меняется. Интеграционные тесты
# Kafka/Postgres — отдельно, как в CI (job integration).
set -uo pipefail
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1 Logging__LogLevel__Default=Error
failed=()
step() { local name=$1; shift; echo; echo "==== $name ===="; if "$@"; then echo "---- $name: OK"; else echo "---- $name: FAILED"; failed+=("$name"); fi; }

echo "Копирую код (без DataSets, lakehouse, node_modules, obj)…"
mkdir -p /work
tar -C /src --ignore-failed-read -cf - --exclude=./DataSets --exclude=./lakehouse --exclude=./mlruns --exclude=./.git --exclude=./.vs --exclude=./.idea --exclude='./Claude outputs' \
  --exclude='*/node_modules' --exclude='*/bin' --exclude='*/obj' --exclude='*/.venv' --exclude='*/__pycache__' . | tar -C /work -xf -
cd /work

echo "Ставлю uv и Node.js 22…"
curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1
export PATH="$HOME/.local/bin:$PATH"
curl -fsSL https://nodejs.org/dist/v22.12.0/node-v22.12.0-linux-x64.tar.gz | tar -xz -C /opt
export PATH="/opt/node-v22.12.0-linux-x64/bin:$PATH"

step ".NET" dotnet test Darumen.slnx -c Release --nologo -v q --logger "console;verbosity=normal"
step "Python" bash -c '
  uv venv ml/.venv --python 3.12 -q && uv pip install --python ml/.venv/bin/python -q -e "ml[dev]" &&
  ml/.venv/bin/python -m grpc_tools.protoc -I proto --python_out=ml/src --grpc_python_out=ml/src --pyi_out=ml/src proto/darumen/v1/*.proto &&
  touch ml/src/darumen/v1/__init__.py &&
  ml/.venv/bin/python -m ruff check ml && ml/.venv/bin/python -m pytest ml/tests -q'
step "Web" bash -c 'cd apps/web && npm ci --no-audit --no-fund --loglevel=error && npm run lint && npm run test -- --run'

echo
if [ ${#failed[@]} -eq 0 ]; then echo "ВСЕ ТЕСТЫ ПРОШЛИ"; else echo "УПАЛО: ${failed[*]}"; exit 1; fi
