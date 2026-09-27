namespace Darumen.Modules.Access.Mail;

public sealed record EmailMessage(string To, string Subject, string Html, string Text);

/// <summary>Письма приложения. SendAsync не бросает: false — SMTP не настроен или письмо не ушло (ответ API скажет emailSent: false).</summary>
public interface IEmailSender
{
    Task<bool> SendAsync(EmailMessage message, CancellationToken cancellationToken);
}
