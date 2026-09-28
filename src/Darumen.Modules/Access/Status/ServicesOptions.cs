namespace Darumen.Modules.Access.Status;

/// <summary>Внешние каналы, которые ещё не подключены: push, SMS и вход через eGov mobile. Пока флаги не выставлены,
/// GET /public/service-status отвечает available: false, а веб и мобилка показывают канал недоступным (ничего не скрывают).</summary>
public sealed class ServicesOptions
{
    public const string Section = "Services";

    /// <summary>Services:Push:Ready — сервис push-уведомлений готов.</summary>
    public ReadinessOptions Push { get; set; } = new();

    /// <summary>Services:Sms:Ready — SMS-шлюз готов.</summary>
    public ReadinessOptions Sms { get; set; } = new();

    /// <summary>Services:Egov:Endpoint — адрес сервиса eGov mobile (Smart Bridge).</summary>
    public EgovOptions Egov { get; set; } = new();
}

/// <summary>Готов ли сервис доставки; по умолчанию нет.</summary>
public sealed class ReadinessOptions
{
    public bool Ready { get; set; }
}

/// <summary>Адрес сервиса eGov mobile (Smart Bridge); пока его не предоставили — пусто, и вход через eGov недоступен.</summary>
public sealed class EgovOptions
{
    public string? Endpoint { get; set; }
}
