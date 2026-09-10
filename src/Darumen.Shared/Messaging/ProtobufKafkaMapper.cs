using System.Text;
using Confluent.Kafka;
using Google.Protobuf;
using Wolverine;
using Wolverine.Kafka;
using Wolverine.Util;

namespace Darumen.Shared.Messaging;

/// <summary>Маппер конверта для топиков, где живёт ровно один тип сообщения из events.proto.
/// Входящие сообщения от Python не несут заголовков Wolverine, поэтому тип сообщения задаётся топиком;
/// исходящие получают только нейтральные заголовки (content-type, event-id), понятные любому клиенту.</summary>
public sealed class ProtobufKafkaMapper<T> : IKafkaEnvelopeMapper where T : class, IMessage<T>, new()
{
    public const string ContentTypeHeader = "content-type";
    public const string MessageTypeHeader = "message-type";
    public const string EventIdHeader = "event-id";

    private readonly string _messageTypeName = typeof(T).ToMessageTypeName();
    private readonly string _protoTypeName = new T().Descriptor.FullName;

    public void MapEnvelopeToOutgoing(Envelope envelope, Message<string, byte[]> outgoing)
    {
        outgoing.Value = envelope.Data ?? [];
        outgoing.Key = envelope.PartitionKey ?? envelope.Id.ToString();
        outgoing.Headers = new Headers
        {
            { ContentTypeHeader, Encoding.UTF8.GetBytes(ProtobufRegistrySerializer<T>.ProtobufContentType) },
            { MessageTypeHeader, Encoding.UTF8.GetBytes(_protoTypeName) },
            { EventIdHeader, Encoding.UTF8.GetBytes(envelope.Id.ToString()) },
        };
    }

    public void MapIncomingToEnvelope(Envelope envelope, Message<string, byte[]> incoming)
    {
        envelope.Data = incoming.Value;
        envelope.MessageType = _messageTypeName;
        envelope.ContentType = ProtobufRegistrySerializer<T>.ProtobufContentType;
        if (!string.IsNullOrEmpty(incoming.Key))
        {
            envelope.PartitionKey = incoming.Key;
        }
    }
}
