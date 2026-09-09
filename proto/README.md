# Контракты

Единый источник схем для gRPC между .NET и Python и для событий Kafka. Пакет `darumen.v1`, изменения только обратно совместимые; несовместимые идут в `v2`.

- `common.proto`: ссылки на регион и организацию, объяснение прогноза, сведения о модели, конверт события.
- `queue.proto`: сервис Queue Intelligence (ожидание, отказ, альтернативы).
- `forecast.proto`: сервис Load Forecasting для любого зарегистрированного потока.
- `events.proto`: сообщения топиков Kafka.

Генерация: в .NET через пакет `Grpc.Tools` (файлы подключаются в `Darumen.Shared`), в Python через `grpcio-tools` (`python -m grpc_tools.protoc -I proto --python_out=ml/gen --grpc_python_out=ml/gen proto/darumen/v1/*.proto`). Схемы событий регистрируются в Confluent Schema Registry под субъектами `<topic>-value`.
