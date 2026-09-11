FROM python:3.12-slim
WORKDIR /app
RUN pip install --no-cache-dir uv
COPY ml/pyproject.toml ml/pyproject.toml
COPY ml/src ml/src
COPY proto proto
COPY streams streams
# SCRIBE_EXTRAS=1 ставит faster-whisper и openai для сервиса скрайба (прод); по умолчанию — только модели
ARG SCRIBE_EXTRAS=0
RUN if [ "$SCRIBE_EXTRAS" = "1" ]; then uv pip install --system --no-cache -e "ml[scribe]"; else uv pip install --system --no-cache -e ml; fi \
 && python -m grpc_tools.protoc -I proto --python_out=ml/src --grpc_python_out=ml/src --pyi_out=ml/src proto/darumen/v1/*.proto \
 && touch ml/src/darumen/v1/__init__.py
ENV DARUMEN_LAKEHOUSE=/lakehouse DARUMEN_MODELS_PORT=50051
EXPOSE 50051
ENTRYPOINT ["python", "-m", "darumen.services"]
