using System.Globalization;
using System.Text.RegularExpressions;
using Darumen.Shared.Api;

namespace Darumen.Modules.Access.Services;

/// <summary>Проверки форм аккаунта и публичных форм: 422 с полями.</summary>
public static partial class AccountValidation
{
    public const int MaxNameLength = 200;
    public const int MaxEmailLength = 320;

    public static ValidationErrors Profile(ProfileUpdateDto body)
    {
        var errors = new ValidationErrors().Require("language", body.Language).Require("timeZone", body.TimeZone);
        if (body.Language is not null && !AccountCatalog.Languages.Contains(body.Language))
        {
            errors.Add("language", "ожидается ru или kk");
        }

        if (!string.IsNullOrWhiteSpace(body.TimeZone) && !TimeZoneInfo.TryFindSystemTimeZoneById(body.TimeZone, out _))
        {
            errors.Add("timeZone", "ожидается часовой пояс IANA, например Asia/Almaty");
        }

        return Phone(errors, "phone", body.Phone, required: false);
    }

    public static ValidationErrors Notifications(NotificationsUpdateDto body)
    {
        var errors = new ValidationErrors();
        var unknown = (body.Events ?? []).Where(e => AccountCatalog.Events.All(k => k.Code != e.Code)).Select(e => e.Code ?? "null").ToList();
        if (unknown.Count > 0)
        {
            errors.Add("events", $"неизвестные события: {string.Join(", ", unknown)}");
        }

        if (!IsTime(body.QuietFrom) || !IsTime(body.QuietTo) || string.IsNullOrWhiteSpace(body.QuietFrom) != string.IsNullOrWhiteSpace(body.QuietTo))
        {
            errors.Add("quietFrom", "тихие часы задаются парой HH:mm");
        }

        if (body.Digest is not null && !AccountCatalog.Digests.Contains(body.Digest))
        {
            errors.Add("digest", $"ожидается одно из: {string.Join(", ", AccountCatalog.Digests)}");
        }

        return errors;
    }

    public static ValidationErrors Email(ValidationErrors errors, string field, string? value)
    {
        errors.Require(field, value);
        if (!string.IsNullOrWhiteSpace(value) && (value.Length > MaxEmailLength || !EmailPattern().IsMatch(value.Trim())))
        {
            errors.Add(field, "ожидается адрес почты");
        }

        return errors;
    }

    public static ValidationErrors Phone(ValidationErrors errors, string field, string? value, bool required)
    {
        if (required)
        {
            errors.Require(field, value);
        }

        if (!string.IsNullOrWhiteSpace(value) && !PhonePattern().IsMatch(value.Trim()))
        {
            errors.Add(field, "ожидается телефон, например +7 701 000 00 00");
        }

        return errors;
    }

    public static ValidationErrors MaxLength(ValidationErrors errors, string field, string? value, int max = MaxNameLength)
    {
        if (value?.Length > max)
        {
            errors.Add(field, $"не длиннее {max} символов");
        }

        return errors;
    }

    private static bool IsTime(string? value) =>
        string.IsNullOrWhiteSpace(value) || TimeOnly.TryParseExact(value, "HH:mm", CultureInfo.InvariantCulture, DateTimeStyles.None, out _);

    [GeneratedRegex(@"^[^@\s]+@[^@\s]+\.[^@\s]+$")]
    private static partial Regex EmailPattern();

    [GeneratedRegex(@"^\+?[0-9 ()\-]{7,20}$")]
    private static partial Regex PhonePattern();
}
