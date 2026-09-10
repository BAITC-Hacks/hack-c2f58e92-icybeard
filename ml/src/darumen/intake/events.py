"""Kafka events of the Data Intake Fabric in the Confluent Schema Registry wire format, so the .NET side
(Wolverine + ProtobufRegistrySerializer) and any other client read the same bytes.

    python -m darumen.intake.events emit --dataset bg_referrals --batch-id X --rows 10 --quarantined 1 --partitions a,b
    python -m darumen.intake.events tail --topic darumen.decision.recorded [--max 5] [--timeout 30]

Connection comes from KAFKA_BOOTSTRAP and SCHEMA_REGISTRY_URL (or --bootstrap / --registry).
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import uuid
from collections.abc import Callable
from typing import Any

from google.protobuf.json_format import MessageToDict

from ..v1 import common_pb2, events_pb2

TOPIC_BATCH_LOADED = "darumen.intake.batch.loaded"
TOPIC_DECISION_RECORDED = "darumen.decision.recorded"
TOPIC_STREAM_UPDATED = "darumen.stream.updated"
TOPIC_ANOMALY_DETECTED = "darumen.anomaly.detected"
MESSAGE_TYPES = {
    TOPIC_BATCH_LOADED: events_pb2.BatchLoaded,
    TOPIC_DECISION_RECORDED: events_pb2.DecisionRecorded,
    TOPIC_STREAM_UPDATED: events_pb2.StreamUpdated,
    TOPIC_ANOMALY_DETECTED: events_pb2.AnomalyDetected,
}
PRODUCER_NAME = "darumen-intake"
CONTENT_TYPE = b"application/x-protobuf"
FLUSH_TIMEOUT_S = 10


def meta(producer: str = PRODUCER_NAME) -> common_pb2.EventMeta:
    m = common_pb2.EventMeta(event_id=str(uuid.uuid4()), producer=producer)
    m.occurred_at.GetCurrentTime()
    return m


class EventPublisher:
    """Producer + serializer are injectable: tests use fakes, `connect` builds the real Confluent pair."""

    def __init__(self, producer: Any, serializer: Callable[[Any, Any], bytes], producer_name: str = PRODUCER_NAME):
        self._producer = producer
        self._serializer = serializer
        self._name = producer_name

    @classmethod
    def connect(cls, bootstrap: str, registry_url: str, producer_name: str = PRODUCER_NAME) -> EventPublisher:
        from confluent_kafka import Producer
        from confluent_kafka.schema_registry import SchemaRegistryClient
        from confluent_kafka.schema_registry.protobuf import ProtobufSerializer

        registry = SchemaRegistryClient({"url": registry_url})
        serializers = {topic: ProtobufSerializer(msg, registry, {"use.deprecated.format": False}) for topic, msg in MESSAGE_TYPES.items()}

        def serialize(message: Any, ctx: Any) -> bytes:
            return serializers[ctx.topic](message, ctx)

        return cls(Producer({"bootstrap.servers": bootstrap, "enable.idempotence": True}), serialize, producer_name)

    @classmethod
    def from_env(cls) -> EventPublisher | None:
        bootstrap, registry = os.environ.get("KAFKA_BOOTSTRAP"), os.environ.get("SCHEMA_REGISTRY_URL")
        return cls.connect(bootstrap, registry) if bootstrap and registry else None

    def publish(self, topic: str, message: Any, key: str) -> str:
        from confluent_kafka.serialization import MessageField, SerializationContext

        payload = self._serializer(message, SerializationContext(topic, MessageField.VALUE))
        self._producer.produce(topic, key=key.encode("utf-8"), value=payload, headers=[("content-type", CONTENT_TYPE)])
        self._producer.flush(FLUSH_TIMEOUT_S)
        return message.meta.event_id

    def batch_loaded(self, dataset: str, batch_id: str, rows_loaded: int, rows_quarantined: int, partitions: list[str]) -> str:
        event = events_pb2.BatchLoaded(meta=meta(self._name), dataset=dataset, batch_id=batch_id, rows_loaded=int(rows_loaded),
                                       rows_quarantined=int(rows_quarantined), partitions=list(partitions))
        return self.publish(TOPIC_BATCH_LOADED, event, key=batch_id)


def tail(bootstrap: str, registry_url: str, topic: str, max_messages: int = 5, timeout_s: float = 30.0) -> list[dict]:
    """Read the newest messages of a topic with the registry deserializer; prints JSON per message."""
    from confluent_kafka import Consumer
    from confluent_kafka.schema_registry.protobuf import ProtobufDeserializer
    from confluent_kafka.serialization import MessageField, SerializationContext

    deserializer = ProtobufDeserializer(MESSAGE_TYPES[topic], {"use.deprecated.format": False})
    consumer = Consumer({"bootstrap.servers": bootstrap, "group.id": f"tail-{uuid.uuid4()}", "auto.offset.reset": "earliest"})
    consumer.subscribe([topic])
    out: list[dict] = []
    import time

    deadline = time.time() + timeout_s
    try:
        while len(out) < max_messages and time.time() < deadline:
            msg = consumer.poll(1.0)
            if msg is None or msg.error():
                continue
            event = deserializer(msg.value(), SerializationContext(topic, MessageField.VALUE))
            out.append(MessageToDict(event, preserving_proto_field_name=True))
    finally:
        consumer.close()
    return out


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="darumen.intake.events", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--bootstrap", default=os.environ.get("KAFKA_BOOTSTRAP", "localhost:29092"))
    parser.add_argument("--registry", default=os.environ.get("SCHEMA_REGISTRY_URL", "http://localhost:8081"))
    sub = parser.add_subparsers(dest="command", required=True)
    emit = sub.add_parser("emit", help="отправить intake.batch.loaded")
    emit.add_argument("--dataset", required=True)
    emit.add_argument("--batch-id", required=True)
    emit.add_argument("--rows", type=int, default=0)
    emit.add_argument("--quarantined", type=int, default=0)
    emit.add_argument("--partitions", default="")
    tail_cmd = sub.add_parser("tail", help="прочитать сообщения топика")
    tail_cmd.add_argument("--topic", default=TOPIC_DECISION_RECORDED, choices=sorted(MESSAGE_TYPES))
    tail_cmd.add_argument("--max", type=int, default=5)
    tail_cmd.add_argument("--timeout", type=float, default=30.0)
    args = parser.parse_args(argv)
    if args.command == "emit":
        publisher = EventPublisher.connect(args.bootstrap, args.registry)
        partitions = [p for p in args.partitions.split(",") if p]
        event_id = publisher.batch_loaded(args.dataset, args.batch_id, args.rows, args.quarantined, partitions)
        print(f"{TOPIC_BATCH_LOADED} {args.batch_id} event {event_id}")
        return 0
    for event in tail(args.bootstrap, args.registry, args.topic, args.max, args.timeout):
        print(json.dumps(event, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
