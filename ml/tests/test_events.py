from darumen.intake.events import TOPIC_BATCH_LOADED, EventPublisher, meta
from darumen.v1 import events_pb2


class FakeProducer:
    def __init__(self):
        self.messages = []
        self.flushed = 0

    def produce(self, topic, key, value, headers):
        self.messages.append((topic, key, value, headers))

    def flush(self, timeout):
        self.flushed += 1


def test_batch_loaded_is_serialized_with_meta_and_key():
    producer = FakeProducer()
    publisher = EventPublisher(producer, lambda message, ctx: message.SerializeToString(), producer_name="test")
    event_id = publisher.batch_loaded("bg_referrals", "bg_referrals-20250101-abc", 767084, 46, ["region_kato=10/p_month=2025-01"])
    topic, key, value, headers = producer.messages[0]
    assert topic == TOPIC_BATCH_LOADED and key == b"bg_referrals-20250101-abc" and producer.flushed == 1
    event = events_pb2.BatchLoaded.FromString(value)
    assert event.meta.event_id == event_id and event.meta.producer == "test" and event.meta.occurred_at.seconds > 0
    assert event.rows_loaded == 767084 and event.rows_quarantined == 46 and list(event.partitions) == ["region_kato=10/p_month=2025-01"]
    assert headers == [("content-type", b"application/x-protobuf")]


def test_publisher_from_env_requires_both_settings(monkeypatch):
    monkeypatch.delenv("KAFKA_BOOTSTRAP", raising=False)
    monkeypatch.delenv("SCHEMA_REGISTRY_URL", raising=False)
    assert EventPublisher.from_env() is None
    assert meta("x").producer == "x" and len(meta().event_id) == 36
