using Darumen.Shared.Api;
using Darumen.Shared.Auth;
using Darumen.Shared.Data;
using Darumen.Shared.Options;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace Darumen.Shared;

public static class ServiceCollectionExtensions
{
    /// <summary>Сквозные сервисы монолита: настройки, Postgres, события, обработка ошибок.</summary>
    public static IServiceCollection AddDarumenCore(this IServiceCollection services, IConfiguration configuration)
    {
        services.Configure<ModelServicesOptions>(configuration.GetSection(ModelServicesOptions.Section));
        services.AddDarumenPostgres(configuration);
        services.AddDarumenAuth(configuration);
        services.AddDarumenRateLimits(configuration);
        services.AddSingleton<AuditQueue>();
        services.AddHostedService<AuditWriter>();
        services.AddProblemDetails();
        services.AddExceptionHandler<UpstreamExceptionHandler>();
        return services;
    }
}
