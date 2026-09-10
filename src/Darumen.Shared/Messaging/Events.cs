using System.Diagnostics;
using Darumen.Contracts.V1;
using Google.Protobuf.WellKnownTypes;

namespace Darumen.Shared.Messaging;

public static class Events
{
    public const string Producer = "darumen-api";

    /// <summary>Конверт события: уникальный id для идемпотентности, время, производитель, trace.</summary>
    public static EventMeta Meta() => new()
    {
        EventId = Guid.NewGuid().ToString(),
        OccurredAt = Timestamp.FromDateTimeOffset(DateTimeOffset.UtcNow),
        Producer = Producer,
        TraceId = Activity.Current?.TraceId.ToString() ?? string.Empty,
    };
}
