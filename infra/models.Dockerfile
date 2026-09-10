FROM python:3.12-slim
WORKDIR /app
RUN pip install --no-cache-dir uv
COPY ml/pyproject.toml ml/pyproject.toml
COPY ml/src ml/src
COPY proto proto
COPY streams streams
RUN uv pip install --system --no-cache -e ml \
 && python -m grpc_tools.protoc -I proto --python_out=ml/src --grpc_python_out=ml/src --pyi_out=ml/src proto/darumen/v1/*.proto \
 && touch ml/src/darumen/v1/__init__.py
ENV DARUMEN_LAKEHOUSE=/lakehouse DARUMEN_MODELS_PORT=50051
EXPOSE 50051
ENTRYPOINT ["python", "-m", "darumen.services"]
