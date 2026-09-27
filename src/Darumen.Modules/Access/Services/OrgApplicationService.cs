using Darumen.Modules.Access.Data;
using Darumen.Modules.Access.Mail;
using Darumen.Shared.Api;
using Darumen.Shared.Auth;

namespace Darumen.Modules.Access.Services;

public sealed record ApplicationOutcome(OrgApplication? Application, IResult? Problem, bool EmailSent = false);

/// <summary>Заявка организации: почта подтверждается 6-значным кодом (15 минут, 5 попыток, повтор не раньше чем через 60 с),
/// затем заявку рассматривает регулятор; одобрение создаёт администратора организации с приглашением.</summary>
public sealed class OrgApplicationService(IOrgApplicationStore store, IEmailSender mail, TimeProvider time)
{
    public static readonly TimeSpan CodeLifetime = TimeSpan.FromMinutes(15);
    public static readonly TimeSpan ResendAfter = TimeSpan.FromSeconds(60);
    public const int MaxAttempts = 5;

    public async Task<(OrgApplication Application, string StatusToken, bool EmailSent)> SubmitAsync(OrgApplicationRequestDto body, CancellationToken ct)
    {
        var now = time.GetUtcNow();
        var statusToken = Tokens.New();
        var code = Tokens.NewCode();
        var id = Guid.NewGuid();
        var application = await store.AddAsync(new OrgApplication(
            id, string.Empty, body.OrgName!.Trim(), body.Bin!.Trim(), body.Type!.Trim(), body.RegionKato!, Blank(body.MoCode), body.AdminName!.Trim(),
            body.Email!.Trim().ToLowerInvariant(), body.Phone!.Trim(), body.Consent, OrgApplicationStatuses.PendingEmail, Tokens.Hash(statusToken),
            CodeHash(id, code), now + CodeLifetime, now, 0, now, null, null, null, null, null), ct);
        var sent = await SendCodeAsync(application, code, ct);
        return (application, statusToken, sent);
    }

    public async Task<ApplicationOutcome> VerifyAsync(Guid id, VerifyEmailDto body, CancellationToken ct)
    {
        var (application, problem) = await AuthorizeAsync(id, body.StatusToken, ct);
        if (problem is not null)
        {
            return new ApplicationOutcome(null, problem);
        }

        if (application!.Status != OrgApplicationStatuses.PendingEmail)
        {
            return new ApplicationOutcome(application, null); // почта уже подтверждена — повтор безопасен
        }

        var now = time.GetUtcNow();
        if (application.EmailCodeHash is null || application.EmailCodeExpiresAt <= now || application.EmailCodeAttempts >= MaxAttempts)
        {
            return new ApplicationOutcome(null, CodeProblem("код устарел или исчерпаны попытки — запросите новый"));
        }

        if (string.IsNullOrWhiteSpace(body.Code) || !Tokens.Matches($"{id}:{body.Code.Trim()}", application.EmailCodeHash))
        {
            await store.SaveAsync(application with { EmailCodeAttempts = application.EmailCodeAttempts + 1 }, ct);
            return new ApplicationOutcome(null, CodeProblem($"неверный код, осталось попыток: {MaxAttempts - application.EmailCodeAttempts - 1}"));
        }

        var verified = application with
        {
            Status = OrgApplicationStatuses.PendingReview, EmailVerifiedAt = now, EmailCodeHash = null, EmailCodeExpiresAt = null,
        };
        await store.SaveAsync(verified, ct);
        return new ApplicationOutcome(verified, null);
    }

    public async Task<ApplicationOutcome> ResendAsync(Guid id, string? statusToken, CancellationToken ct)
    {
        var (application, problem) = await AuthorizeAsync(id, statusToken, ct);
        if (problem is not null)
        {
            return new ApplicationOutcome(null, problem);
        }

        if (application!.Status != OrgApplicationStatuses.PendingEmail)
        {
            return new ApplicationOutcome(null, new ValidationErrors().Add("status", "почта уже подтверждена").Problem());
        }

        var now = time.GetUtcNow();
        var wait = application.EmailCodeSentAt + ResendAfter - now;
        if (wait > TimeSpan.Zero)
        {
            var seconds = (int)Math.Ceiling(wait.Value.TotalSeconds);
            return new ApplicationOutcome(null, Results.Problem(statusCode: StatusCodes.Status429TooManyRequests, title: "Слишком часто",
                detail: $"новый код можно запросить через {seconds} с", extensions: new Dictionary<string, object?> { ["retryAfterSeconds"] = seconds }));
        }

        var code = Tokens.NewCode();
        var renewed = application with { EmailCodeHash = CodeHash(id, code), EmailCodeExpiresAt = now + CodeLifetime, EmailCodeSentAt = now, EmailCodeAttempts = 0 };
        await store.SaveAsync(renewed, ct);
        return new ApplicationOutcome(renewed, null, await SendCodeAsync(renewed, code, ct));
    }

    /// <summary>Заявка по id и statusToken: неизвестная заявка и неверный токен неразличимы (404).</summary>
    public async Task<(OrgApplication? Application, IResult? Problem)> AuthorizeAsync(Guid id, string? statusToken, CancellationToken ct)
    {
        var application = await store.GetAsync(id, ct);
        return application is not null && !string.IsNullOrWhiteSpace(statusToken) && Tokens.Matches(statusToken, application.StatusTokenHash)
            ? (application, null)
            : (null, Results.Problem(statusCode: StatusCodes.Status404NotFound, title: "Заявка не найдена", detail: "проверьте ссылку на заявку"));
    }

    public static ValidationErrors Validate(OrgApplicationRequestDto body)
    {
        var errors = new ValidationErrors().Require("orgName", body.OrgName).Require("type", body.Type).Require("regionKato", body.RegionKato)
            .Kato("regionKato", body.RegionKato).Require("adminName", body.AdminName);
        if (string.IsNullOrWhiteSpace(body.Bin) || body.Bin.Trim().Length != 12 || !body.Bin.Trim().All(char.IsAsciiDigit))
        {
            errors.Add("bin", "БИН — 12 цифр");
        }

        AccountValidation.Email(errors, "email", body.Email);
        AccountValidation.Phone(errors, "phone", body.Phone, required: true);
        AccountValidation.MaxLength(errors, "orgName", body.OrgName, 300);
        AccountValidation.MaxLength(errors, "adminName", body.AdminName);
        AccountValidation.MaxLength(errors, "type", body.Type, 50);
        AccountValidation.MaxLength(errors, "moCode", body.MoCode, 20);
        if (!body.Consent)
        {
            errors.Add("consent", "нужно согласие на обработку данных");
        }

        foreach (var (field, value) in new[] { ("orgName", body.OrgName), ("adminName", body.AdminName), ("type", body.Type), ("moCode", body.MoCode) })
        {
            if (value?.Any(char.IsControl) == true)
            {
                errors.Add(field, "недопустимые символы");
            }
        }

        return errors;
    }

    public static string MaskEmail(string email)
    {
        var at = email.IndexOf('@');
        return at <= 1 ? email : $"{email[0]}***{email[at..]}";
    }

    private Task<bool> SendCodeAsync(OrgApplication application, string code, CancellationToken ct) =>
        mail.SendAsync(EmailTemplates.VerificationCode(application.Email, application.OrgName, application.Number, code, (int)CodeLifetime.TotalMinutes), ct);

    private static string CodeHash(Guid id, string code) => Tokens.Hash($"{id}:{code}");

    private static IResult CodeProblem(string message) => new ValidationErrors().Add("code", message).Problem();

    private static string? Blank(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
