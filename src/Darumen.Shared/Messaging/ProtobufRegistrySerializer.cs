using Confluent.Kafka;
using Confluent.SchemaRegistry;
using Confluent.SchemaRegistry.Serdes;
using Google.Protobuf;
using Wolverine;
using Wolverine.Runtime.Serialization;

namespace Darumen.Shared.Messaging;

/// <summary>Сериализатор Wolverine поверх Confluent ProtobufSerializer: формат Schema Registry
/// (magic byte, id схемы, индексы сообщения, тело), схема регистрируется под субъектом topic-value,
/// Python-клиенты с confluent-kafka читают и пишут те же байты.</summary>
public sealed class ProtobufRegistrySerializer<T> : IMessageSerializer where T : class, IMessage<T>, new()
{
    public const string ProtobufContentType = "application/x-protobuf";

    private readonly ProtobufSerializer<T> _serializer;
    private readonly ProtobufDeserializer<T> _deserializer;
    private readonly SerializationContext _context;

    public ProtobufRegistrySerializer(ISchemaRegistryClient registry, string topic)
    {
        _serializer = new ProtobufSerializer<T>(registry, new ProtobufSerializerConfig
        {
            AutoRegisterSchemas = true,
            SubjectNameStrategy = SubjectNameStrategy.Topic,
            UseDeprecatedFormat = false,
        });
        _deserializer = new ProtobufDeserializer<T>(registry, new ProtobufDeserializerConfig { UseDeprecatedFormat = false });
        _context = new SerializationContext(MessageComponentType.Value, topic);
    }

    public string ContentType => ProtobufContentType;

    public byte[] WriteMessage(object message) => message is T typed
        ? _serializer.SerializeAsync(typed, _context).GetAwaiter().GetResult()
        : throw new InvalidOperationException($"{typeof(T).Name} expected, got {message.GetType().Name}");

    public byte[] Write(Envelope envelope) => WriteMessage(envelope.Message ?? throw new InvalidOperationException("envelope without message"));

    public object ReadFromData(Type messageType, Envelope envelope) => ReadFromData(envelope.Data ?? []);

    public object ReadFromData(byte[] data) => _deserializer.DeserializeAsync(data, data.Length == 0, _context).GetAwaiter().GetResult()
        ?? throw new InvalidOperationException($"empty {typeof(T).Name} payload");
}
