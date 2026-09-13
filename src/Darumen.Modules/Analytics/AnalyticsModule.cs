using Darumen.Contracts.V1;
using Darumen.Shared.Modules;
using Darumen.Shared.Options;
using Microsoft.Extensions.Options;

namespace Darumen.Modules.Analytics;

public sealed class AnalyticsModule : IDarumenModule
{
    public string Name => "analytics";

    public void AddServices(IServiceCollection services, IConfiguration configuration)
    {
        services.AddGrpcClient<LoadForecasting.LoadForecastingClient>((sp, o) =>
            o.Address = new Uri(sp.GetRequiredService<IOptions<ModelServicesOptions>>().Value.Address));
        services.AddScoped<IAnalyticsRepository, AnalyticsRepository>();
        services.AddScoped<ForecastService>();
        services.Configure<QualityOptions>(configuration.GetSection(QualityOptions.Section));
        services.AddScoped<QualityService>(); // scoped: тянет репозиторий для меток сигналов
    }

    public void MapEndpoints(IEndpointRouteBuilder api) => AnalyticsEndpoints.Map(api);
}
