using Darumen.Shared.Modules;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Net.Http.Headers;

namespace Darumen.Modules.Public;

public sealed class PublicModule : IDarumenModule
{
    public string Name => "public";

    public void AddServices(IServiceCollection services, IConfiguration configuration)
    {
        services.Configure<PublicOptions>(configuration.GetSection(PublicOptions.Section));
        services.AddMemoryCache();
        services.TryAddSingleton(TimeProvider.System);
        var timeout = TimeSpan.FromSeconds(Math.Max(1, configuration.GetSection(PublicOptions.Section).GetValue<int?>(nameof(PublicOptions.TimeoutSeconds)) ?? 8));
        services.AddHttpClient<IWeatherSource, OpenMeteoClient>(c => c.Timeout = timeout);
        services.AddHttpClient<INewsSource, RssNewsClient>(c =>
        {
            c.Timeout = timeout;
            c.DefaultRequestHeaders.TryAddWithoutValidation(HeaderNames.UserAgent, "Darumen/1.0 (+https://dc.jurek.kz)"); // без UA ленты отвечают 403
        });
        services.AddScoped<DailyService>();
    }

    public void MapEndpoints(IEndpointRouteBuilder api) => PublicEndpoints.Map(api);
}
