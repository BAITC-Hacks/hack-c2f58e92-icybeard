namespace Darumen.Modules.Access.Status;

/// <summary>Доступен ли канал. Reason — машинная причина недоступности (<see cref="ServiceStatusReasons"/>), при available: true — null.</summary>
public sealed record ServiceAvailabilityDto(bool Available, string? Reason)
{
    public static readonly ServiceAvailabilityDto Up = new(true, null);

    public static ServiceAvailabilityDto Down(string reason) => new(false, reason);
}

/// <summary>Ответ GET /public/service-status: когда проверено (UTC) и состояние каждого канала.</summary>
public sealed record ServiceStatusDto(DateTime CheckedAt, ServiceAvailabilityDto Email, ServiceAvailabilityDto Push, ServiceAvailabilityDto Sms, ServiceAvailabilityDto Egov);

/// <summary>Причины недоступности — часть контракта для веба и мобилки, менять только вместе с клиентами.</summary>
public static class ServiceStatusReasons
{
    /// <summary>Mail:Smtp:Host пуст — письма не отправляются.</summary>
    public const string SmtpNotConfigured = "smtp_not_configured";

    /// <summary>Почтовый сервер задан, но не принимает TCP-соединение.</summary>
    public const string SmtpUnreachable = "smtp_unreachable";

    /// <summary>Сервис доставки (push, SMS) ещё не подключён.</summary>
    public const string NotReady = "not_ready";

    /// <summary>Адрес сервиса eGov mobile (Smart Bridge) не предоставлен.</summary>
    public const string EndpointNotProvided = "endpoint_not_provided";
}
