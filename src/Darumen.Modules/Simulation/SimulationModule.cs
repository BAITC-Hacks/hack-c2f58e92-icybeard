using Darumen.Shared.Modules;
using Darumen.Shared.Options;
using Microsoft.Extensions.Options;

namespace Darumen.Modules.Simulation;

public sealed class SimulationModule : IDarumenModule
{
    public string Name => "simulation";

    public void AddServices(IServiceCollection services, IConfiguration configuration) =>
        services.AddGrpcClient<Contracts.V1.Simulation.SimulationClient>((sp, o) =>
            o.Address = new Uri(sp.GetRequiredService<IOptions<ModelServicesOptions>>().Value.Address));

    public void MapEndpoints(IEndpointRouteBuilder api) => SimulationEndpoints.Map(api);
}
