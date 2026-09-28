.DEFAULT_GOAL := help
DATASETS_DIR ?= DataSets
PY ?= ml/.venv/bin/python
ENV_FILE ?= .env
# --env-file явно нужен: без него docker compose ищет .env рядом с первым -f (infra/), а не в корне репозитория;
# если .env ещё не создан (до cp .env.example .env), флаг не добавляем, чтобы compose не падал на отсутствующем файле
COMPOSE ?= docker compose $(if $(wildcard $(ENV_FILE)),--env-file $(ENV_FILE),) -f infra/docker-compose.yml
LOAD_ENV = $(if $(wildcard $(ENV_FILE)),set -a; . ./$(ENV_FILE); set +a;,)
# macOS arm64: grpc.tools везёт для macOS только x64-protoc, без Rosetta он не запускается («Bad CPU type in executable»).
# Если стоят нативные protoc и grpc_csharp_plugin из Homebrew (brew install protobuf grpc), Grpc.Tools берёт их.
ifeq ($(shell uname -sm 2>/dev/null),Darwin arm64)
ifneq ($(wildcard /opt/homebrew/bin/protoc),)
export PROTOBUF_PROTOC ?= /opt/homebrew/bin/protoc
export GRPC_PROTOC_PLUGIN ?= /opt/homebrew/bin/grpc_csharp_plugin
endif
endif

help: ## Список целей
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-14s %s\n", $$1, $$2}'

UV ?= uv
PYTHON_VERSION ?= 3.12

venv: ## Python-окружение для ml/ через uv
	@test -x $(PY) || $(UV) venv ml/.venv --python $(PYTHON_VERSION)
	@$(UV) pip install --python $(PY) -q -e "ml[dev]"

data: venv ## Проверить данные, загрузить в lakehouse, собрать справочники и витрины gold
	$(PY) scripts/download_datasets.py --verify-only referrals waiting refusals treated_count --base "$(DATASETS_DIR)"
	$(PY) -m darumen.intake add "$(DATASETS_DIR)" --contracts contracts --lakehouse lakehouse
	$(PY) -m darumen.refdata build --lakehouse lakehouse
	$(PY) -m darumen.lakehouse build --lakehouse lakehouse

intake-status: ## Манифесты загрузок
	$(PY) -m darumen.intake status --lakehouse lakehouse

refdata: venv ## Справочники и реестр организаций из silver
	$(PY) -m darumen.refdata build --lakehouse lakehouse

gold: venv ## Витрины gold из silver и refdata
	$(PY) -m darumen.lakehouse build --lakehouse lakehouse

publish: venv ## Опубликовать gold и refdata в Postgres и ClickHouse (нужен make serve)
	$(PY) -m darumen.lakehouse publish --lakehouse lakehouse

train: venv ## Обучить модели и зарегистрировать в MLflow
	$(PY) -m darumen.models.train

eval: venv ## Оценить модели против baseline на отложенной выборке
	$(PY) -m darumen.models.evaluate

serve: ## Поднять только инфраструктуру (Postgres, ClickHouse, Cube, Kafka, Schema Registry, Valkey, MinIO, Keycloak, Mailpit, MLflow)
	$(COMPOSE) up -d

up: ## Поднять всё в Docker: инфраструктура, API, сервис моделей, скрайб, веб на :3000 (Ollama на хосте)
	$(COMPOSE) --profile app up -d --build

down: ## Остановить все контейнеры
	$(COMPOSE) --profile app --profile pipeline --profile ollama down

logs: ## Логи приложения
	$(COMPOSE) --profile app logs -f --tail=100 api models scribe web

pipeline: ## Конвейер данных в контейнере: intake → refdata → gold → train → publish (DataSets и lakehouse с хоста)
	$(COMPOSE) --profile pipeline run --rm --build pipeline

pitch: ## Обновить копию презентации в веб-приложении из darumen-pitch.html
	cp darumen-pitch.html apps/web/public/pitch.html

# Цель деплоя: infra/deploy/targets/$(TARGET).env — govtech (VPS хакатона, https://icybeard.govtech-kz.com, по
# умолчанию) или jurek (Hetzner, https://dc.jurek.kz): make deploy TARGET=jurek
TARGET ?= govtech
include infra/deploy/targets/$(TARGET).env
VM_DIR ?= $(DEPLOY_PATH)

deploy: pitch ## Ручной деплой на стенд цели TARGET (по умолчанию VPS хакатона): rsync кода и витрин, сборка на VM
	TARGET=$(TARGET) scripts/deploy.sh $(ARGS)

# docker exec не наследует umask контейнера backup — задаём тот же 0077, что в compose (дампы читает только владелец)
VM_BACKUP = docker exec $$(docker ps -q --filter label=com.docker.compose.project=darumen --filter label=com.docker.compose.service=backup) bash -c "umask 0077 && exec /backup.sh"

deploy-data: ## Только данные: витрины lakehouse на VM + publish в Postgres (код и образы не трогает)
	TARGET=$(TARGET) scripts/deploy.sh --data-only

release-status: ## Что запущено на VM: текущий и прошлый релиз, хэш шаблона, контейнеры, диск, свежие бэкапы
	ssh $(DEPLOY_HOST) $(VM_DIR)/bin/release.sh status

rollback: ## Откатить стенд на предыдущий CD-релиз
	ssh $(DEPLOY_HOST) $(VM_DIR)/bin/release.sh rollback

backup-now: ## Дамп darumen и keycloak на VM прямо сейчас (backups/last)
	ssh $(DEPLOY_HOST) '$(VM_BACKUP) && ls -lt $(VM_DIR)/backups/last | head -5'

restore: ## Восстановить БД на VM из дампа: make restore DB=keycloak [DUMP=daily/keycloak-20261001.sql.gz]
	@test -n "$(DB)" || { echo "укажите DB=darumen или DB=keycloak" >&2; exit 2; }
	ssh -t $(DEPLOY_HOST) $(VM_DIR)/bin/restore.sh $(DB) $(DUMP)

vm-install-release: ## Шаблон релиза (compose, SQL, release.sh, restore.sh) на VM — разово и после каждой правки файлов из infra/deploy/template-files.txt, до тега
	DEPLOY_HOST=$(DEPLOY_HOST) VM_DIR=$(VM_DIR) infra/deploy/vm-install.sh

build: ## Собрать .NET и веб
	dotnet build Darumen.slnx -c Release --nologo -v q
	cd apps/web && npm run build

test: proto ## Все тесты: .NET, Python, веб
	dotnet test Darumen.slnx -c Release --nologo -v q
	$(PY) -m pytest ml/tests -q
	cd apps/web && npm run test -- --run

proto: venv ## Сгенерировать Python-код gRPC из proto/ в ml/src/darumen/v1 (в .gitignore)
	$(PY) -m grpc_tools.protoc -I proto --python_out=ml/src --grpc_python_out=ml/src --pyi_out=ml/src proto/darumen/v1/*.proto
	@touch ml/src/darumen/v1/__init__.py

models-serve: proto ## gRPC-сервисы моделей (Queue Intelligence, Load Forecasting) на :50051
	$(PY) -m darumen.services --lakehouse lakehouse --port 50051

scribe-serve: venv ## Сервис AI-скрайба (FastAPI) на :8010; faster-whisper через make venv-scribe
	$(LOAD_ENV) $(PY) -m darumen.scribe --port 8010

venv-scribe: venv ## Установить faster-whisper и anthropic для скрайба
	$(UV) pip install --python $(PY) -q -e "ml[dev,scribe]"

dagster: venv ## Dagster UI с линией активов silver → refdata → gold → models → published
	$(PY) -m dagster dev -m darumen.orchestration.definitions

ollama-model: ## Локальная модель для Insight и скрайба с контекстом 16k (нужен ollama pull qwen3.8:27b)
	ollama create darumen-qwen3.8:27b -f infra/ollama/Modelfile

lint: venv ## Линтеры
	$(PY) -m ruff check ml
	dotnet format Darumen.slnx --verify-no-changes

.PHONY: help venv data intake-status refdata gold publish train eval serve up down logs pipeline build test proto models-serve scribe-serve venv-scribe dagster ollama-model lint deploy deploy-data release-status rollback backup-now restore vm-install-release
