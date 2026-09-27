namespace Darumen.Modules.Access;

/// <summary>Публичный адрес веба: ссылки в письмах (/invite/{token}) и возврат после смены пароля в Keycloak.</summary>
public sealed class WebOptions
{
    public const string Section = "Web";

    public string PublicOrigin { get; set; } = "http://localhost:5173";

    public string Origin => PublicOrigin.TrimEnd('/');
}

/// <summary>Keycloak Admin REST API через конфиденциального клиента darumen-admin (client credentials). BaseUrl и Realm
/// по умолчанию берутся из Auth:Authority (http://keycloak:8080/realms/darumen → http://keycloak:8080 и darumen).</summary>
public sealed class KeycloakAdminOptions
{
    public const string Section = "Keycloak:Admin";

    /// <summary>Секрет локального realm (infra/keycloak, клиент darumen-admin) — только для разработки; на стенде задаётся
    /// переменной окружения Keycloak__Admin__ClientSecret (из KEYCLOAK_ADMIN_CLIENT_SECRET).</summary>
    public const string DevClientSecret = "darumen-admin-dev-secret";

    public string? BaseUrl { get; set; }

    public string? Realm { get; set; }

    public string ClientId { get; set; } = "darumen-admin";

    public string? ClientSecret { get; set; }

    public int TimeoutSeconds { get; set; } = 5;

    /// <summary>Клиент, на который Keycloak возвращает пользователя после письма «Сменить пароль».</summary>
    public string WebClientId { get; set; } = "darumen-web";

    public int MaxUsers { get; set; } = 2000;
}

/// <summary>SMTP для писем приложения (приглашение, код подтверждения, решение по заявке). Без Host письма не уходят,
/// ответы API говорят об этом (emailSent: false). В разработке — Mailpit на localhost:1025.</summary>
public sealed class MailOptions
{
    public const string Section = "Mail:Smtp";

    public string? Host { get; set; }

    public int Port { get; set; } = 25;

    public string? User { get; set; }

    public string? Password { get; set; }

    public string From { get; set; } = "Darumen Health <no-reply@darumen.local>";

    public bool EnableSsl { get; set; }

    public int TimeoutSeconds { get; set; } = 10;
}
