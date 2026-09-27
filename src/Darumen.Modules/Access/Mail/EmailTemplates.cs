using System.Globalization;
using static Darumen.Modules.Access.Mail.EmailLayout;

namespace Darumen.Modules.Access.Mail;

/// <summary>Письма приложения (RU): приглашение, код подтверждения почты заявки, решение по заявке. Смену пароля и
/// «Забыли пароль» шлёт Keycloak своей темой писем.</summary>
public static class EmailTemplates
{
    private static readonly CultureInfo Ru = CultureInfo.GetCultureInfo("ru-RU");

    public static EmailMessage Invitation(string to, string displayName, string roleTitle, string? orgName, string invitedBy, string url, DateTimeOffset expiresAt)
    {
        const string title = "Вас пригласили в Darumen Health";
        var expires = Date(expiresAt);
        var body = Paragraph($"Здравствуйте, {E(displayName)}! {E(invitedBy)} приглашает вас в Darumen Health.")
                   + Facts(("Роль", roleTitle), ("Организация", orgName), ("Ссылка действует до", expires))
                   + Paragraph("Нажмите кнопку, придумайте пароль и примите правила работы с данными — после этого можно войти.")
                   + Button(url, "Принять приглашение")
                   + Note($"Если кнопка не открывается, скопируйте ссылку в браузер: {E(url)}. Если вы не ждали приглашения, просто не отвечайте на письмо.");
        var text = $"{title}\n\n{displayName}, {invitedBy} приглашает вас в Darumen Health.\nРоль: {roleTitle}\n" +
                   (orgName is null ? string.Empty : $"Организация: {orgName}\n") +
                   $"Принять приглашение: {url}\nСсылка действует до {expires}.";
        return new EmailMessage(to, title, Page(title, $"Роль: {roleTitle}. Ссылка действует до {expires}.", body), text);
    }

    public static EmailMessage VerificationCode(string to, string orgName, string number, string code, int minutes)
    {
        const string title = "Код подтверждения почты";
        var body = Paragraph($"Вы подали заявку на подключение организации «{E(orgName)}» к Darumen Health. Введите код на странице заявки:")
                   + Code(code)
                   + Facts(("Заявка", number), ("Код действует", $"{minutes} минут"))
                   + Note("Никому не сообщайте код. Если заявку подавали не вы, просто не отвечайте на письмо — без кода она не будет рассмотрена.");
        var text = $"{title}\n\nКод: {code}\nЗаявка {number} ({orgName}). Код действует {minutes} минут.";
        return new EmailMessage(to, $"{code} — {title.ToLowerInvariant()}", Page(title, $"Код {code} для заявки {number}", body), text);
    }

    public static EmailMessage ApplicationApproved(string to, string orgName, string number, string url, DateTimeOffset expiresAt)
    {
        const string title = "Заявка одобрена";
        var expires = Date(expiresAt);
        var body = Paragraph($"Заявка на подключение организации «{E(orgName)}» одобрена. Вы — администратор организации в Darumen Health.")
                   + Facts(("Заявка", number), ("Роль", "Администратор организации"), ("Ссылка действует до", expires))
                   + Paragraph("Нажмите кнопку, придумайте пароль и пригласите коллег из своей организации.")
                   + Button(url, "Активировать доступ")
                   + Note($"Ссылка: {E(url)}");
        var text = $"{title}\n\nЗаявка {number} ({orgName}) одобрена.\nАктивировать доступ: {url}\nСсылка действует до {expires}.";
        return new EmailMessage(to, $"{title}: {orgName}", Page(title, $"Заявка {number} одобрена", body), text);
    }

    public static EmailMessage ApplicationRejected(string to, string orgName, string number, string reason)
    {
        const string title = "Заявка отклонена";
        var body = Paragraph($"Заявка на подключение организации «{E(orgName)}» к Darumen Health отклонена.")
                   + Facts(("Заявка", number), ("Причина", reason))
                   + Paragraph("Исправьте данные и подайте заявку снова.");
        var text = $"{title}\n\nЗаявка {number} ({orgName}) отклонена.\nПричина: {reason}";
        return new EmailMessage(to, $"{title}: {orgName}", Page(title, $"Заявка {number} отклонена", body), text);
    }

    private static string Date(DateTimeOffset at) => at.ToOffset(TimeSpan.FromHours(5)).ToString("d MMMM yyyy, HH:mm", Ru);
}
