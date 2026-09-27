using System.Text.Json;

namespace Darumen.Modules.Access.Services;

public sealed record NotificationChannels(bool InApp, bool Email, bool Sms, bool Push);

/// <summary>Настройки уведомлений в auth.user_settings.notifications (jsonb). Событие security нельзя выключить: in-app и почта всегда включены.</summary>
public sealed record NotificationSettings(
    IReadOnlyDictionary<string, NotificationChannels> Events, string? QuietFrom, string? QuietTo, bool QuietExceptRegulator, string Digest)
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    public static NotificationSettings Default { get; } = new(new Dictionary<string, NotificationChannels>(), null, null, false, AccountCatalog.DigestOff);

    public static NotificationSettings Parse(string? json)
    {
        if (string.IsNullOrWhiteSpace(json))
        {
            return Default;
        }

        try
        {
            return JsonSerializer.Deserialize<NotificationSettings>(json, Json) ?? Default;
        }
        catch (JsonException)
        {
            return Default;
        }
    }

    public static NotificationSettings From(NotificationsUpdateDto body) => new(
        (body.Events ?? []).Where(e => e.Code is not null).GroupBy(e => e.Code!)
            .ToDictionary(g => g.Key, g => new NotificationChannels(g.Last().InApp, g.Last().Email, g.Last().Sms, g.Last().Push)),
        Blank(body.QuietFrom), Blank(body.QuietTo), body.QuietExceptRegulator, body.Digest ?? AccountCatalog.DigestOff);

    public static NotificationsDto ToDto(NotificationSettings settings) => new(
        AccountCatalog.Events.Select(e =>
        {
            var channels = settings.Events.GetValueOrDefault(e.Code) ?? new NotificationChannels(true, e.DefaultEmail, false, false);
            return e.Locked
                ? new NotificationEventDto(e.Code, e.TitleRu, e.TitleKk, true, true, channels.Sms, channels.Push, true)
                : new NotificationEventDto(e.Code, e.TitleRu, e.TitleKk, channels.InApp, channels.Email, channels.Sms, channels.Push, false);
        }).ToList(),
        settings.QuietFrom, settings.QuietTo, settings.QuietExceptRegulator, settings.Digest);

    private static string? Blank(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
