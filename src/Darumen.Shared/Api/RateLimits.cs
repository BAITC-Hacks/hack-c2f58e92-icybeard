using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;

namespace Darumen.Shared.Api;

public sealed class RateLimitOptions
{
    public const string Section = "RateLimits";

    /// <summary>Запросов в минуту на пользователя к эндпоинтам, которые вызывают языковую модель или распознавание речи.</summary>
    public int ModelCallsPerMinute { get; set; } = 20;

    /// <summary>Запросов в минуту с одного адреса к публичным формам: заявка организации, код почты, приглашение, восстановление пароля.</summary>
    public int PublicFormsPerMinute { get; set; } = 10;
}

/// <summary>Ограничение частоты для дорогих вызовов: каждый вопрос Insight и черновик скрайба стоит денег провайдеру
/// или минуты CPU. Лимит считается на пользователя, для анонимных запросов — на адрес клиента.</summary>
public static class RateLimits
{
    /// <summary>Политика для Insight и скрайба (имя используется и в маршрутах YARP в appsettings.json).</summary>
    public const string ModelCalls = "model-calls";

    /// <summary>Анонимные POST (/public/org-applications, /public/invites, /public/password-reset): лимит на адрес клиента.</summary>
    public const string PublicForms = "public-forms";

    public static IServiceCollection AddDarumenRateLimits(this IServiceCollection services, IConfiguration configuration)
    {
        services.Configure<RateLimitOptions>(configuration.GetSection(RateLimitOptions.Section));
        services.AddRateLimiter(limiter =>
        {
            limiter.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
            limiter.AddPolicy(ModelCalls, http => RateLimitPartition.GetFixedWindowLimiter(
                PartitionKey(http),
                _ => new FixedWindowRateLimiterOptions
                {
                    // настройки читаются при первом запросе ключа: в тестах и на стенде лимит задаётся конфигурацией
                    PermitLimit = http.RequestServices.GetRequiredService<IOptions<RateLimitOptions>>().Value.ModelCallsPerMinute,
                    Window = TimeSpan.FromMinutes(1),
                    QueueLimit = 0,
                }));
            limiter.AddPolicy(PublicForms, http => RateLimitPartition.GetFixedWindowLimiter(
                $"public:{http.Connection.RemoteIpAddress}",
                _ => new FixedWindowRateLimiterOptions
                {
                    PermitLimit = http.RequestServices.GetRequiredService<IOptions<RateLimitOptions>>().Value.PublicFormsPerMinute,
                    Window = TimeSpan.FromMinutes(1),
                    QueueLimit = 0,
                }));
        });
        return services;
    }

    public static string PartitionKey(HttpContext http)
    {
        var user = CurrentUser.From(http);
        return user.Actor != CurrentUser.Anonymous ? $"user:{user.Actor}" : $"ip:{http.Connection.RemoteIpAddress}";
    }
}
