using Darumen.Modules.Access.Status;

namespace Darumen.Modules.Access.Endpoints;

/// <summary>Анонимно: какие внешние каналы сейчас работают (почта, push, SMS, вход через eGov mobile). Веб и мобилка
/// показывают недоступные каналы честно — баннер «почтовый сервер недоступен», выключенные колонки уведомлений, пояснение у eGov.</summary>
public static class ServiceStatusEndpoints
{
    private static readonly TimeSpan CacheFor = TimeSpan.FromSeconds(30);

    public static void Map(IEndpointRouteBuilder api) =>
        api.MapGet("/public/service-status", async (ServiceStatusService service) => Results.Ok(await service.GetAsync()))
            .AllowAnonymous().WithTags("Public").CacheOutput(policy => policy.Expire(CacheFor))
            .WithName("ServiceStatus")
            .WithSummary("Статус каналов: email (smtp_not_configured | smtp_unreachable), push и sms (not_ready), egov (endpoint_not_provided); кэш 30 с, проба SMTP — 60 с")
            .Produces<ServiceStatusDto>();
}
