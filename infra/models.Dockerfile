FROM python:3.12-slim
WORKDIR /app
# libgomp1 — OpenMP-рантайм для LightGBM; без него import lightgbm падает в slim-образе
RUN apt-get update && apt-get install -y --no-install-recommends libgomp1 && rm -rf /var/lib/apt/lists/* \
 && pip install --no-cache-dir uv
# SCRIBE_EXTRAS=1 ставит faster-whisper и openai для сервиса скрайба (прод); INTAKE_EXTRAS=1 — openai для
# LLM-черновика контракта (4.6) в сервисе загрузки; по умолчанию (оба 0) — только модели
ARG SCRIBE_EXTRAS=0
ARG INTAKE_EXTRAS=0
# сначала только зависимости из pyproject.toml: этот долгий слой Docker берёт из кэша, пока не меняются сами
# зависимости, — правка кода в ml/src больше не скачивает все пакеты заново
COPY ml/pyproject.toml ml/pyproject.toml
RUN if [ "$SCRIBE_EXTRAS" = "1" ]; then uv pip install --system --no-cache -r ml/pyproject.toml --extra scribe; \
    elif [ "$INTAKE_EXTRAS" = "1" ]; then uv pip install --system --no-cache -r ml/pyproject.toml --extra intake; \
    else uv pip install --system --no-cache -r ml/pyproject.toml; fi
COPY ml/src ml/src
COPY proto proto
COPY streams streams
COPY contracts contracts
COPY refdata refdata
RUN uv pip install --system --no-cache --no-deps -e ml \
 && python -m grpc_tools.protoc -I proto --python_out=ml/src --grpc_python_out=ml/src --pyi_out=ml/src proto/darumen/v1/*.proto \
 && touch ml/src/darumen/v1/__init__.py
ENV DARUMEN_LAKEHOUSE=/lakehouse DARUMEN_MODELS_PORT=50051
EXPOSE 50051
ENTRYPOINT ["python", "-m", "darumen.services"]
