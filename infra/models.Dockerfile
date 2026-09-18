FROM python:3.12-slim
WORKDIR /app
# libgomp1 — OpenMP-рантайм для LightGBM; без него import lightgbm падает в slim-образе
RUN apt-get update && apt-get install -y --no-install-recommends libgomp1 && rm -rf /var/lib/apt/lists/* \
 && pip install --no-cache-dir uv
COPY ml/pyproject.toml ml/pyproject.toml
COPY ml/src ml/src
COPY proto proto
COPY streams streams
COPY contracts contracts
COPY refdata refdata
# SCRIBE_EXTRAS=1 ставит faster-whisper и openai для сервиса скрайба (прод); INTAKE_EXTRAS=1 — openai для
# LLM-черновика контракта (4.6) в сервисе загрузки; по умолчанию (оба 0) — только модели
ARG SCRIBE_EXTRAS=0
ARG INTAKE_EXTRAS=0
RUN if [ "$SCRIBE_EXTRAS" = "1" ]; then uv pip install --system --no-cache -e "ml[scribe]"; \
    elif [ "$INTAKE_EXTRAS" = "1" ]; then uv pip install --system --no-cache -e "ml[intake]"; \
    else uv pip install --system --no-cache -e ml; fi \
 && python -m grpc_tools.protoc -I proto --python_out=ml/src --grpc_python_out=ml/src --pyi_out=ml/src proto/darumen/v1/*.proto \
 && touch ml/src/darumen/v1/__init__.py
ENV DARUMEN_LAKEHOUSE=/lakehouse DARUMEN_MODELS_PORT=50051
EXPOSE 50051
ENTRYPOINT ["python", "-m", "darumen.services"]
