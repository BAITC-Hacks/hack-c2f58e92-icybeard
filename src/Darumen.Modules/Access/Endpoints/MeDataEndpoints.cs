using System.Text;
using System.Text.Json;
using Darumen.Modules.Access.Data;
using Darumen.Modules.Access.Identity;
using Darumen.Modules.Access.Services;
using Darumen.Modules.Journal;
using Darumen.Modules.RefData;
using Darumen.Shared.Api;
using Darumen.Shared.Auth;

namespace Darumen.Modules.Access.Endpoints;

/// <summary>Профиль, уведомления, согласия, «кто смотрел мои данные» и выгрузка своих данных.</summary>
public static class MeDataEndpoints
{
    private const int AccessLogLimit = 100;
    private const int ExportLimit = 500;
    private static readonly string[] ReadOnlyProfileFields = ["displayName", "position", "specialty", "moCode"];
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    public static void Map(RouteGroupBuilder me)
    {
        me.MapGet("/profile", async (HttpContext http, IAccountStore account, IIdentityAdmin identity, OrgDirectory orgs, CancellationToken ct) =>
                Results.Ok(await ProfileAsync(http, account, identity, orgs, ct)))
            .WithName("MyProfile").WithSummary("Профиль: ФИО, должность и специальность только для чтения (меняет администратор), телефон, язык, часовой пояс")
            .Produces<ProfileDto>();

        me.MapPut("/profile", async (ProfileUpdateDto body, HttpContext http, IAccountStore account, IIdentityAdmin identity, OrgDirectory orgs, CancellationToken ct) =>
            {
                var errors = AccountValidation.Profile(body);
                if (errors.Any)
                {
                    return errors.Problem();
                }

                var user = CurrentUser.From(http);
                var current = await account.SettingsAsync(user.UserId, ct);
                var now = DateTimeOffset.UtcNow;
                await account.SaveSettingsAsync(new UserSettings(user.UserId, user.Actor, Normalize(body.Phone), body.Language!, body.TimeZone!,
                    current?.NotificationsJson, now, now), ct);
                return Results.Ok(await ProfileAsync(http, account, identity, orgs, ct));
            })
            .WithName("UpdateMyProfile").WithSummary("Изменить телефон, язык (ru | kk) и часовой пояс (IANA)")
            .Produces<ProfileDto>().ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity);

        me.MapGet("/notifications", async (HttpContext http, IAccountStore account, CancellationToken ct) =>
                Results.Ok(NotificationSettings.ToDto(NotificationSettings.Parse((await account.SettingsAsync(CurrentUser.From(http).UserId, ct))?.NotificationsJson))))
            .WithName("MyNotifications").WithSummary("Уведомления по событиям и каналам, тихие часы, дайджест; событие security всегда включено")
            .Produces<NotificationsDto>();

        me.MapPut("/notifications", async (NotificationsUpdateDto body, HttpContext http, IAccountStore account, CancellationToken ct) =>
            {
                var errors = AccountValidation.Notifications(body);
                if (errors.Any)
                {
                    return errors.Problem();
                }

                var user = CurrentUser.From(http);
                var settings = NotificationSettings.From(body);
                var current = await account.SettingsAsync(user.UserId, ct);
                await account.SaveSettingsAsync(new UserSettings(user.UserId, user.Actor, current?.Phone, current?.Language ?? AccountCatalog.Languages[0],
                    current?.TimeZone ?? AccountCatalog.DefaultTimeZone, JsonSerializer.Serialize(settings, Json), current?.ProfileCheckedAt, DateTimeOffset.UtcNow), ct);
                return Results.Ok(NotificationSettings.ToDto(settings));
            })
            .WithName("UpdateMyNotifications").WithSummary("Сохранить настройки уведомлений")
            .Produces<NotificationsDto>().ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity);

        me.MapGet("/consents", async (HttpContext http, IAccountStore account, CancellationToken ct) =>
                Results.Ok(new { items = Consents(await account.ConsentsAsync(CurrentUser.From(http).UserId, ct)) }))
            .WithName("MyConsents").WithSummary("Согласия: forecasts (обязательное), anonymized_stats, research_exports");

        me.MapPut("/consents/{code}", async (string code, ConsentUpdateDto body, HttpContext http, IAccountStore account, AdminActions actions, CancellationToken ct) =>
            {
                var consent = AccountCatalog.Consents.FirstOrDefault(c => c.Code == code);
                if (consent is null)
                {
                    return Results.Problem(statusCode: StatusCodes.Status404NotFound, title: "Нет такого согласия", detail: code);
                }

                if (body.Granted is null || (consent.Required && body.Granted == false))
                {
                    return new ValidationErrors().Add("granted", body.Granted is null ? "обязательное поле" : "обязательное согласие нельзя отозвать").Problem();
                }

                var user = CurrentUser.From(http);
                await account.SetConsentAsync(user.UserId, code, body.Granted.Value, ct);
                actions.Audit(http, "consent", $"{code}={body.Granted.Value}");
                return Results.Ok(new { items = Consents(await account.ConsentsAsync(user.UserId, ct)) });
            })
            .WithName("UpdateMyConsent").WithSummary("Дать или отозвать согласие; обязательное отозвать нельзя")
            .ProducesProblem(StatusCodes.Status404NotFound).ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity);

        me.MapGet("/access-log", async (HttpContext http, IActivityReader activity, IServiceProvider services, CancellationToken ct) =>
            {
                var user = CurrentUser.From(http);
                var needles = new List<string> { user.UserId, user.Actor };
                if (user.Roles.Contains(Roles.Citizen) && await PatientRefAsync(http, services, ct) is { } patientRef)
                {
                    needles.Add(patientRef);
                }

                var rows = await activity.MentionsAsync(needles.Distinct().ToList(), user.Actor, AccessLogLimit, ct);
                return Results.Ok(new { items = rows.Select(r => new AccessLogItemDto(r.At, r.Actor, r.Role, r.Method, r.Path, r.Status)).ToList() });
            })
            .WithName("MyAccessLog").WithSummary("Кто и что смотрел по мне: записи аудита других пользователей с моим идентификатором или маршрутом");

        me.MapGet("/export", async (HttpContext http, IAccountStore account, IActivityReader activity, IDecisionRepository decisions, CancellationToken ct) =>
            {
                var csv = await ExportCsvAsync(http, account, activity, decisions, ct);
                return Results.File(Encoding.UTF8.GetPreamble().Concat(Encoding.UTF8.GetBytes(csv)).ToArray(), "text/csv; charset=utf-8", "darumen-account.csv");
            })
            .WithName("MyExport").WithSummary("Мои данные одним CSV: профиль, согласия, мои решения и запросы (ИИН — маской)");
    }

    private static async Task<ProfileDto> ProfileAsync(HttpContext http, IAccountStore account, IIdentityAdmin identity, OrgDirectory orgs, CancellationToken ct)
    {
        var user = CurrentUser.From(http);
        var settings = await account.SettingsAsync(user.UserId, ct);
        var identityUser = await MeEndpoints.SafeAsync(() => identity.UserAsync(user.UserId, ct), null);
        return new ProfileDto(
            MeEndpoints.DisplayName(http.User, user.Actor), identityUser?.Attribute(IdentityAttributes.Position), identityUser?.Attribute(IdentityAttributes.Specialty),
            http.User.FindFirst(DarumenClaims.Email)?.Value ?? identityUser?.Email, settings?.Phone, settings?.Language ?? AccountCatalog.Languages[0],
            settings?.TimeZone ?? AccountCatalog.DefaultTimeZone, user.MoCode, await orgs.NameAsync(user.MoCode, ct), user.RegionKato, IinMask.Mask(user.Iin),
            ReadOnlyProfileFields);
    }

    private static List<ConsentDto> Consents(IReadOnlyList<ConsentRecord> stored) =>
        AccountCatalog.Consents.Select(c =>
        {
            var record = stored.FirstOrDefault(s => s.Code == c.Code);
            return new ConsentDto(c.Code, c.TitleRu, c.TitleKk, c.Required, c.Required || (record?.Granted ?? c.DefaultGranted), record?.UpdatedAt);
        }).ToList();

    private static async Task<string?> PatientRefAsync(HttpContext http, IServiceProvider services, CancellationToken ct) =>
        await MeEndpoints.SafeAsync(() => RouteEndpoints.CitizenPatientRefAsync(http, services.GetRequiredService<IWorklistRepository>(),
            services.GetRequiredService<IRefDataRepository>(), services.GetRequiredService<QueuePredictions>(), ct), null);

    private static async Task<string> ExportCsvAsync(HttpContext http, IAccountStore account, IActivityReader activity, IDecisionRepository decisions, CancellationToken ct)
    {
        var user = CurrentUser.From(http);
        var settings = await account.SettingsAsync(user.UserId, ct);
        var csv = new StringBuilder("section,field,value\n");
        void Row(string section, string field, object? value) =>
            csv.Append(Csv(section)).Append(',').Append(Csv(field)).Append(',').Append(Csv(Convert.ToString(value, System.Globalization.CultureInfo.InvariantCulture))).Append('\n');

        Row("profile", "actor", user.Actor);
        Row("profile", "displayName", MeEndpoints.DisplayName(http.User, user.Actor));
        Row("profile", "roles", string.Join(' ', user.Roles));
        Row("profile", "moCode", user.MoCode);
        Row("profile", "regionKato", user.RegionKato);
        Row("profile", "iin", IinMask.Mask(user.Iin));
        Row("profile", "phone", settings?.Phone);
        Row("profile", "language", settings?.Language);
        Row("profile", "timeZone", settings?.TimeZone);
        foreach (var consent in Consents(await account.ConsentsAsync(user.UserId, ct)))
        {
            Row("consent", consent.Code, consent.Granted);
        }

        foreach (var decision in (await decisions.ListAsync(user.Actor, null, null, 1, ExportLimit, ct)).Items)
        {
            Row("decision", $"{decision.RecordedAt:O} {decision.Subject}", $"{decision.SubjectId}: {decision.Chosen?.GetRawText()} ({decision.Reason})");
        }

        foreach (var entry in await activity.ByActorAsync(user.Actor, ExportLimit, ct))
        {
            Row("request", entry.At.ToString("O"), $"{entry.Method} {entry.Path} {entry.Status}");
        }

        return csv.ToString();
    }

    private static string Csv(string? value)
    {
        var text = value ?? string.Empty;
        // формулы в Excel не исполняются: значение, начинающееся с = + - @, экранируется апострофом
        if (text.Length > 0 && "=+-@".Contains(text[0]))
        {
            text = "'" + text;
        }

        return text.IndexOfAny([',', '"', '\n', '\r']) >= 0 ? $"\"{text.Replace("\"", "\"\"")}\"" : text;
    }

    private static string? Normalize(string? phone) => string.IsNullOrWhiteSpace(phone) ? null : phone.Trim();
}
