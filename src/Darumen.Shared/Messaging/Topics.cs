namespace Darumen.Shared.Messaging;

/// <summary>Топики Kafka; каждому соответствует сообщение из proto/darumen/v1/events.proto, схема в реестре под субъектом topic-value.</summary>
public static class Topics
{
    public const string BatchLoaded = "darumen.intake.batch.loaded";
    public const string StreamUpdated = "darumen.stream.updated";
    public const string ModelDeployed = "darumen.model.deployed";
    public const string AnomalyDetected = "darumen.anomaly.detected";
    public const string DecisionRecorded = "darumen.decision.recorded";
    public const string NotificationRequested = "darumen.notification.requested";
}
