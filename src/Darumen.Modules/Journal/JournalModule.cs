using Darumen.Shared.Modules;

namespace Darumen.Modules.Journal;

public sealed class JournalModule : IDarumenModule
{
    public string Name => "journal";

    public void AddServices(IServiceCollection services, IConfiguration configuration)
    {
        services.AddScoped<IDecisionRepository, DecisionRepository>();
        services.AddScoped<IAuditRepository, AuditRepository>();
        services.AddScoped<IWorklistRepository, WorklistRepository>();
        services.AddScoped<INotificationReadRepository, NotificationReadRepository>();
        services.AddMemoryCache();
        services.AddScoped<QueuePredictions>();
        // сервис скрайба (Python) — тот же адрес, что у прокси /api/v1/scribe/*
        services.AddHttpClient<IScribeService, ScribeHttpService>(client =>
        {
            client.BaseAddress = new Uri(configuration[ScribeHttpService.AddressKey] ?? "http://localhost:8010/");
            client.Timeout = TimeSpan.FromSeconds(60);
        });
    }

    public void MapEndpoints(IEndpointRouteBuilder api)
    {
        JournalEndpoints.Map(api);
        RouteEndpoints.Map(api);
        NotificationBellEndpoints.Map(api);
        ScribeEndpoints.Map(api);
    }
}
