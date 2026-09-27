namespace Darumen.Modules.Access;

public sealed record NotificationEventInfo(string Code, string TitleRu, string TitleKk, bool DefaultEmail, bool Locked);

public sealed record ConsentInfo(string Code, string TitleRu, string TitleKk, bool Required, bool DefaultGranted);

/// <summary>События уведомлений и согласия аккаунта (доски аккаунта): коды, подписи RU/KK, значения по умолчанию.</summary>
public static class AccountCatalog
{
    public const string Security = "security";
    public const string DigestOff = "off";

    public static readonly IReadOnlyList<string> Digests = [DigestOff, "daily", "weekly"];

    public static readonly IReadOnlyList<string> Languages = ["ru", "kk"];

    public const string DefaultTimeZone = "Asia/Almaty";

    public static readonly IReadOnlyList<NotificationEventInfo> Events =
    [
        new(Security, "Безопасность аккаунта: вход, смена пароля, новые сессии", "Аккаунт қауіпсіздігі: кіру, құпиясөзді ауыстыру, жаңа сессиялар", true, true),
        new("route_updates", "Изменения моего маршрута", "Менің бағытымдағы өзгерістер", false, false),
        new("patient_signals", "Сигналы пациентов", "Пациенттердің сигналдары", false, false),
        new("referral_decisions", "Решения по направлениям", "Жолдамалар бойынша шешімдер", false, false),
        new("anomalies", "Аномалии и риски", "Аномалиялар мен тәуекелдер", false, false),
        new("data_uploads", "Загрузки данных", "Деректерді жүктеу", false, false),
        new("access_requests", "Запросы доступа", "Қолжетімділік сұраулары", false, false),
        new("org_applications", "Заявки организаций", "Ұйымдардың өтінімдері", false, false),
    ];

    public static readonly IReadOnlyList<ConsentInfo> Consents =
    [
        new("forecasts", "Использование моих данных для прогноза сроков ожидания (обязательное)", "Күту мерзімдерін болжау үшін деректерімді пайдалану (міндетті)", true, true),
        new("anonymized_stats", "Обезличенная статистика для улучшения сервиса", "Қызметті жақсарту үшін иесіздендірілген статистика", false, false),
        new("research_exports", "Обезличенные выгрузки для научных исследований", "Ғылыми зерттеулерге арналған иесіздендірілген деректер", false, false),
    ];
}
