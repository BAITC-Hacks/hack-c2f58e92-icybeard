using System.Net;
using System.Net.Mail;
using System.Net.Mime;
using System.Text;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace Darumen.Modules.Access.Mail;

/// <summary>SMTP через System.Net.Mail без сторонних пакетов: в разработке — Mailpit (localhost:1025, веб-интерфейс :8025),
/// на стенде — SMTP из Mail__Smtp__*. Без Host письма не отправляются. Адрес получателя в журнал не пишется.</summary>
public sealed class SmtpEmailSender(IOptions<MailOptions> options, ILogger<SmtpEmailSender> logger) : IEmailSender
{
    public async Task<bool> SendAsync(EmailMessage message, CancellationToken cancellationToken)
    {
        var settings = options.Value;
        if (string.IsNullOrWhiteSpace(settings.Host))
        {
            return false;
        }

        try
        {
            using var mail = Build(message, settings.From);
            using var client = new SmtpClient(settings.Host, settings.Port)
            {
                EnableSsl = settings.EnableSsl,
                Timeout = (int)TimeSpan.FromSeconds(settings.TimeoutSeconds).TotalMilliseconds,
                DeliveryMethod = SmtpDeliveryMethod.Network,
            };
            if (!string.IsNullOrWhiteSpace(settings.User))
            {
                client.Credentials = new NetworkCredential(settings.User, settings.Password);
            }

            await client.SendMailAsync(mail, cancellationToken);
            return true;
        }
        catch (Exception exception) when (exception is SmtpException or InvalidOperationException or IOException or FormatException or ArgumentException
                                              || (exception is OperationCanceledException && !cancellationToken.IsCancellationRequested))
        {
            logger.LogWarning(exception, "Email \"{Subject}\" was not sent via {Host}:{Port}", message.Subject, settings.Host, settings.Port);
            return false;
        }
    }

    private static MailMessage Build(EmailMessage message, string from)
    {
        var mail = new MailMessage(new MailAddress(from).Address, message.To)
        {
            From = new MailAddress(from),
            Subject = SingleLine(message.Subject),
            SubjectEncoding = Encoding.UTF8,
            BodyEncoding = Encoding.UTF8,
            Body = message.Text,
            IsBodyHtml = false,
        };
        mail.AlternateViews.Add(AlternateView.CreateAlternateViewFromString(message.Html, Encoding.UTF8, MediaTypeNames.Text.Html));
        return mail;
    }

    /// <summary>Тема письма — одна строка: переводы строк из пользовательских полей (название организации) не попадают в заголовки.</summary>
    private static string SingleLine(string value) => string.Join(' ', value.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries));
}
