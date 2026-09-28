using System.Globalization;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;

namespace Darumen.Shared.Api;

/// <summary>Общий лимит на /api/*: RateLimiting:PermitLimit запросов за RateLimiting:WindowSeconds на пользователя.
/// Лимит щедрый — он защищает стенд от перебора и зацикленных клиентов, а не ограничивает обычную работу.</summary>
public sealed class GlobalRateLimitOptions
{
    public const string Section = "RateLimiting";

    /// <summary>false — общий лимит выключен (лимиты дорогих вызовов и публичных форм остаются).</summary>
    public bool Enabled { get; set; } = true;

    public int PermitLimit { get; set; } = 600;

    public int WindowSeconds { get; set; } = 60;
}

/// <summary>Глобальный ограничитель частоты: окно на пользователя (sub из токена), без входа — на адрес клиента
/// (за Caddy и nginx адрес восстанавливает UseForwardedHeaders). /health, OpenAPI и Scalar не ограничиваются. Отказ — 429
/// problem+json с detail `rate_limited` и Retry-After, для всех политик (общей, model-calls, public-forms).</summary>
public static class GlobalRateLimit
{
    /// <summary>Машинная причина в detail ответа 429.</summary>
    public const string RejectedDetail = "rate_limited";

    private static readonly PathString ApiPrefix = new("/api");

    public static PartitionedRateLimiter<HttpContext> Create() => PartitionedRateLimiter.Create<HttpContext, string>(Partition);

    public static async ValueTask OnRejectedAsync(OnRejectedContext context, CancellationToken cancellationToken)
    {
        var http = context.HttpContext;
        if (context.Lease.TryGetMetadata(MetadataName.RetryAfter, out var retryAfter))
        {
            http.Response.Headers.RetryAfter = Math.Max(1, (int)Math.Ceiling(retryAfter.TotalSeconds)).ToString(CultureInfo.InvariantCulture);
        }

        // клиент без JSON в Accept получит 429 без тела — статус уже выставлен ограничителем
        await http.RequestServices.GetRequiredService<IProblemDetailsService>().TryWriteAsync(new ProblemDetailsContext
        {
            HttpContext = http,
            ProblemDetails = new() { Status = StatusCodes.Status429TooManyRequests, Title = "Слишком много запросов", Detail = RejectedDetail },
        });
    }

    private static RateLimitPartition<string> Partition(HttpContext http)
    {
        var options = http.RequestServices.GetRequiredService<IOptions<GlobalRateLimitOptions>>().Value;
        if (!options.Enabled || !http.Request.Path.StartsWithSegments(ApiPrefix))
        {
            return RateLimitPartition.GetNoLimiter(string.Empty);
        }

        // настройки читаются при создании окна ключа: в тестах и на стенде лимит задаётся конфигурацией
        return RateLimitPartition.GetFixedWindowLimiter(RateLimits.PartitionKey(http), _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = Math.Max(1, options.PermitLimit),
            Window = TimeSpan.FromSeconds(Math.Max(1, options.WindowSeconds)),
            QueueLimit = 0,
        });
    }
}
