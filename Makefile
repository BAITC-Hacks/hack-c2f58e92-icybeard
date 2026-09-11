.DEFAULT_GOAL := help
DATASETS_DIR ?= DataSets
PY ?= ml/.venv/bin/python
COMPOSE ?= docker compose -f infra/docker-compose.yml
ENV_FILE ?= .env
LOAD_ENV = $(if $(wildcard $(ENV_FILE)),set -a; . ./$(ENV_FILE); set +a;,)

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

serve: ## Поднять инфраструктуру и сервисы
	$(COMPOSE) up -d

down: ## Остановить сервисы
	$(COMPOSE) down

deploy: ## Задеплоить на dc.jurek.kz (rsync + docker compose на VM); первый раз: make deploy ARGS=--replace-dc
	scripts/deploy.sh $(ARGS)

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

ollama-model: ## Локальная модель для Insight и скрайба с контекстом 8k (нужен ollama pull qwen3.8:27b)
	ollama create darumen-qwen3.8:27b -f infra/ollama/Modelfile

lint: venv ## Линтеры
	$(PY) -m ruff check ml
	dotnet format Darumen.slnx --verify-no-changes

.PHONY: help venv data intake-status refdata gold publish train eval serve down build test proto models-serve scribe-serve venv-scribe dagster ollama-model lint
