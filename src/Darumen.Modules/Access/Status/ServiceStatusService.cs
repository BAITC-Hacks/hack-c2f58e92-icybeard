using Microsoft.Extensions.Options;

namespace Darumen.Modules.Access.Status;

/// <summary>Собирает ответ GET /public/service-status: почта — по пробе SMTP, push и SMS — по Services:*:Ready,
/// eGov mobile — по наличию Services:Egov:Endpoint.</summary>
public sealed class ServiceStatusService(MailServerStatus mail, IOptions<ServicesOptions> services, TimeProvider clock)
{
    public async Task<ServiceStatusDto> GetAsync()
    {
        var options = services.Value;
        var email = await mail.CheckAsync();
        return new ServiceStatusDto(CheckedAt(), email, Readiness(options.Push.Ready), Readiness(options.Sms.Ready), Egov(options.Egov.Endpoint));
    }

    /// <summary>UTC с точностью до секунды: в JSON — «2026-09-28T10:15:00Z».</summary>
    private DateTime CheckedAt()
    {
        var now = clock.GetUtcNow().UtcDateTime;
        return now.AddTicks(-(now.Ticks % TimeSpan.TicksPerSecond));
    }

    private static ServiceAvailabilityDto Readiness(bool ready) =>
        ready ? ServiceAvailabilityDto.Up : ServiceAvailabilityDto.Down(ServiceStatusReasons.NotReady);

    private static ServiceAvailabilityDto Egov(string? endpoint) =>
        string.IsNullOrWhiteSpace(endpoint) ? ServiceAvailabilityDto.Down(ServiceStatusReasons.EndpointNotProvided) : ServiceAvailabilityDto.Up;
}
