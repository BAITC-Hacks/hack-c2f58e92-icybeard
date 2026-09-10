.DEFAULT_GOAL := help
DATASETS_DIR ?= DataSets
PY ?= ml/.venv/bin/python
COMPOSE ?= docker compose -f infra/docker-compose.yml

help: ## Список целей
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-14s %s\n", $$1, $$2}'

venv: ## Python-окружение для ml/
	@test -d ml/.venv || python3 -m venv ml/.venv
	@$(PY) -m pip install -q -U pip
	@$(PY) -m pip install -q -e "ml[dev]"

data: venv ## Скачать и проверить данные, собрать silver и gold
	$(PY) scripts/download_datasets.py --verify-only referrals waiting refusals treated_count --base "$(DATASETS_DIR)"
	$(PY) -m darumen.lakehouse.build --datasets "$(DATASETS_DIR)"

train: venv ## Обучить модели и зарегистрировать в MLflow
	$(PY) -m darumen.models.train

eval: venv ## Оценить модели против baseline на отложенной выборке
	$(PY) -m darumen.models.evaluate

serve: ## Поднять инфраструктуру и сервисы
	$(COMPOSE) up -d

down: ## Остановить сервисы
	$(COMPOSE) down

build: ## Собрать .NET и веб
	dotnet build Darumen.slnx -c Release --nologo -v q
	cd apps/web && npm run build

test: venv ## Все тесты: .NET, Python, веб
	dotnet test Darumen.slnx -c Release --nologo -v q
	$(PY) -m pytest ml/tests -q
	cd apps/web && npm run test -- --run

proto: venv ## Сгенерировать Python-код из proto/
	mkdir -p ml/src/darumen/gen
	$(PY) -m grpc_tools.protoc -I proto --python_out=ml/src/darumen/gen --grpc_python_out=ml/src/darumen/gen proto/darumen/v1/*.proto

lint: venv ## Линтеры
	$(PY) -m ruff check ml
	dotnet format Darumen.slnx --verify-no-changes

.PHONY: help venv data train eval serve down build test proto lint
