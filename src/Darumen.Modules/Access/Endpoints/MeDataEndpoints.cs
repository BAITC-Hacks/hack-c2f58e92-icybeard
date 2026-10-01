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
        var kk = settings?.Language == "kk";
        string L(string ru, string kz) => kk ? kz : ru;
        var zone = Zone(settings?.TimeZone);
        string When(DateTimeOffset at) => TimeZoneInfo.ConvertTime(at, zone).ToString("dd.MM.yyyy HH:mm", System.Globalization.CultureInfo.InvariantCulture);

        // разделитель «;» и BOM: русский/казахский Excel открывает файл сразу по колонкам и в UTF-8
        var csv = new StringBuilder();
        void Row(string section, string field, string? value) =>
            csv.Append(Csv(section)).Append(';').Append(Csv(field)).Append(';').Append(Csv(value)).Append("\r\n");

        Row(L("Раздел", "Бөлім"), L("Поле", "Өріс"), L("Значение", "Мәні"));
        var profile = L("Профиль", "Профиль");
        Row(profile, L("Логин", "Логин"), user.Actor);
        Row(profile, L("Имя", "Аты-жөні"), MeEndpoints.DisplayName(http.User, user.Actor));
        Row(profile, L("Роли", "Рөлдер"), string.Join(", ", user.Roles));
        Row(profile, L("Код организации", "Ұйым коды"), user.MoCode);
        Row(profile, L("Регион (код КАТО)", "Өңір (ҚАТО коды)"), user.RegionKato);
        Row(profile, L("ИИН (скрыт частично)", "ЖСН (ішінара жасырылған)"), IinMask.Mask(user.Iin));
        Row(profile, L("Телефон", "Телефон"), settings?.Phone);
        Row(profile, L("Язык интерфейса", "Интерфейс тілі"), (settings?.Language ?? AccountCatalog.Languages[0]) == "kk" ? "қазақша" : L("русский", "орысша"));
        Row(profile, L("Часовой пояс", "Уақыт белдеуі"), settings?.TimeZone ?? AccountCatalog.DefaultTimeZone);

        var consentSection = L("Согласие", "Келісім");
        foreach (var consent in Consents(await account.ConsentsAsync(user.UserId, ct)))
        {
            var title = kk && !string.IsNullOrEmpty(consent.TitleKk) ? consent.TitleKk : consent.TitleRu;
            Row(consentSection, title, consent.Granted ? L("да", "иә") : L("нет", "жоқ"));
        }

        var decisionSection = L("Решение", "Шешім");
        foreach (var decision in (await decisions.ListAsync(user.Actor, null, null, 1, ExportLimit, ct)).Items)
        {
            var chosen = decision.Chosen?.GetRawText();
            var text = string.Join("; ", new[]
            {
                $"{decision.Subject} {decision.SubjectId}".Trim(),
                string.IsNullOrWhiteSpace(chosen) || chosen == "null" ? null : $"{L("выбор", "таңдау")}: {chosen}",
                string.IsNullOrWhiteSpace(decision.Reason) ? null : $"{L("причина", "себебі")}: {decision.Reason}",
            }.Where(x => !string.IsNullOrEmpty(x)));
            Row(decisionSection, When(decision.RecordedAt), text);
        }

        var requestSection = L("Действие в системе", "Жүйедегі әрекет");
        foreach (var entry in await activity.ByActorAsync(user.Actor, ExportLimit, ct))
        {
            var verb = entry.Method.ToUpperInvariant() switch
            {
                "GET" => L("просмотр", "қарау"),
                "POST" => L("отправка", "жіберу"),
                "PUT" or "PATCH" => L("изменение", "өзгерту"),
                "DELETE" => L("удаление", "жою"),
                _ => entry.Method,
            };
            var result = entry.Status < 400 ? L("успешно", "сәтті") : L($"ошибка {entry.Status}", $"қате {entry.Status}");
            Row(requestSection, When(entry.At), $"{verb}: {entry.Path} — {result}");
        }

        return csv.ToString();
    }

    private static TimeZoneInfo Zone(string? id)
    {
        try
        {
            return TimeZoneInfo.FindSystemTimeZoneById(string.IsNullOrWhiteSpace(id) ? AccountCatalog.DefaultTimeZone : id);
        }
        catch (Exception e) when (e is TimeZoneNotFoundException or InvalidTimeZoneException)
        {
            return TimeZoneInfo.Utc;
        }
    }

    private static string Csv(string? value)
    {
        var text = value ?? string.Empty;
        // формулы в Excel не исполняются: значение, начинающееся с = + - @, экранируется апострофом
        if (text.Length > 0 && "=+-@".Contains(text[0]))
        {
            text = "'" + text;
        }

        return text.IndexOfAny([';', ',', '"', '\n', '\r']) >= 0 ? $"\"{text.Replace("\"", "\"\"")}\"" : text;
    }

    private static string? Normalize(string? phone) => string.IsNullOrWhiteSpace(phone) ? null : phone.Trim();
}
