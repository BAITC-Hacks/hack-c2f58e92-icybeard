using Darumen.Shared.Modules;

namespace Darumen.Modules.RefData;

public sealed class RefDataModule : IDarumenModule
{
    public string Name => "refdata";

    public void AddServices(IServiceCollection services, IConfiguration configuration) =>
        services.AddScoped<IRefDataRepository, RefDataRepository>();

    public void MapEndpoints(IEndpointRouteBuilder api) => RefDataEndpoints.Map(api);
}
