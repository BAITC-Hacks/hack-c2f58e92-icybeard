using Microsoft.AspNetCore.Routing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace Darumen.Shared.Modules;

/// <summary>Модуль монолита: регистрирует свои сервисы и маршруты под /api/v1.</summary>
public interface IDarumenModule
{
    string Name { get; }
    void AddServices(IServiceCollection services, IConfiguration configuration);
    void MapEndpoints(IEndpointRouteBuilder api);
}

public static class ModuleRegistration
{
    public static IServiceCollection AddDarumenModules(this IServiceCollection services, IConfiguration configuration, params IDarumenModule[] modules)
    {
        foreach (var module in modules)
        {
            module.AddServices(services, configuration);
            services.AddSingleton(module);
        }

        return services;
    }

    public static IEndpointRouteBuilder MapDarumenModules(this IEndpointRouteBuilder api)
    {
        foreach (var module in api.ServiceProvider.GetServices<IDarumenModule>())
        {
            module.MapEndpoints(api);
        }

        return api;
    }
}
