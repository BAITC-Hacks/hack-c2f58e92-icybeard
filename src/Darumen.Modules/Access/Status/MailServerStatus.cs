using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace Darumen.Modules.Access.Status;

/// <summary>Доступность почтового сервера для GET /public/service-status. Без Mail:Smtp:Host — smtp_not_configured; иначе
/// TCP-проба host:port (не дольше <see cref="ProbeTimeout"/>), результат живёт <see cref="CacheFor"/>. Потокобезопасно:
/// одновременные запросы ждут одну пробу. Не бросает. Warning в журнал — только когда состояние меняется; логин и пароль
/// SMTP здесь не читаются и в журнал не попадают.</summary>
public sealed class MailServerStatus(IOptions<MailOptions> options, ISmtpProbe probe, TimeProvider clock, ILogger<MailServerStatus> logger)
{
    public static readonly TimeSpan ProbeTimeout = TimeSpan.FromSeconds(3);

    public static readonly TimeSpan CacheFor = TimeSpan.FromSeconds(60);

    private const string AvailableState = "available";

    private readonly SemaphoreSlim _gate = new(1, 1);
    private ProbeResult? _last;
    private string? _state;

    public async Task<ServiceAvailabilityDto> CheckAsync()
    {
        var settings = options.Value;
        if (string.IsNullOrWhiteSpace(settings.Host))
        {
            return Settle(ServiceAvailabilityDto.Down(ServiceStatusReasons.SmtpNotConfigured), null, settings.Port);
        }

        var host = settings.Host.Trim();
        if (Fresh(Volatile.Read(ref _last), host, settings.Port) is { } cached)
        {
            return cached;
        }

        // без токена запроса: ожидание ограничено одной пробой (3 с), а оборванный клиентом запрос не должен
        // оставлять остальных без результата
        await _gate.WaitAsync();
        try
        {
            if (Fresh(Volatile.Read(ref _last), host, settings.Port) is { } again)
            {
                return again;
            }

            var status = await ProbeAsync(host, settings.Port)
                ? ServiceAvailabilityDto.Up
                : ServiceAvailabilityDto.Down(ServiceStatusReasons.SmtpUnreachable);
            Volatile.Write(ref _last, new ProbeResult(host, settings.Port, clock.GetUtcNow(), status));
            return Settle(status, host, settings.Port);
        }
        finally
        {
            _gate.Release();
        }
    }

    private ServiceAvailabilityDto? Fresh(ProbeResult? result, string host, int port) =>
        result is not null && result.Host == host && result.Port == port && clock.GetUtcNow() - result.At < CacheFor ? result.Status : null;

    private async Task<bool> ProbeAsync(string host, int port)
    {
        try
        {
            return await probe.CanConnectAsync(host, port, ProbeTimeout);
        }
        catch (Exception exception)
        {
            // проба по контракту не бросает; если всё же бросила — это «сервер недоступен», а не 500 у статуса
            logger.LogDebug(exception, "Mail server probe failed");
            return false;
        }
    }

    /// <summary>Запоминает состояние и пишет в журнал только его смену (первая проверка — тоже смена).</summary>
    private ServiceAvailabilityDto Settle(ServiceAvailabilityDto status, string? host, int port)
    {
        var state = status.Reason ?? AvailableState;
        if (Interlocked.Exchange(ref _state, state) == state)
        {
            return status;
        }

        if (status.Available)
        {
            logger.LogInformation("Mail server {Host}:{Port} accepts connections, emails are sent", host, port);
        }
        else if (host is null)
        {
            logger.LogWarning("Mail server is not configured (Mail:Smtp:Host is empty): emails are not sent");
        }
        else
        {
            logger.LogWarning("Mail server {Host}:{Port} is unreachable: emails are not sent", host, port);
        }

        return status;
    }

    private sealed record ProbeResult(string Host, int Port, DateTimeOffset At, ServiceAvailabilityDto Status);
}
