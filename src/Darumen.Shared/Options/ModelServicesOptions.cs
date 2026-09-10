namespace Darumen.Shared.Options;

/// <summary>Адрес Python-сервисов моделей (gRPC) и таймаут одного вызова.</summary>
public sealed class ModelServicesOptions
{
    public const string Section = "ModelServices";

    public string Address { get; set; } = "http://localhost:50051";

    public int TimeoutSeconds { get; set; } = 5;
}
