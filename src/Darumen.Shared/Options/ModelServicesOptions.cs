namespace Darumen.Shared.Options;

/// <summary>Адрес Python-сервисов моделей (gRPC), таймаут одного вызова и пакетного (все очереди региона за раз).</summary>
public sealed class ModelServicesOptions
{
    public const string Section = "ModelServices";

    public string Address { get; set; } = "http://localhost:50051";

    public int TimeoutSeconds { get; set; } = 5;

    public int BatchTimeoutSeconds { get; set; } = 30;
}
