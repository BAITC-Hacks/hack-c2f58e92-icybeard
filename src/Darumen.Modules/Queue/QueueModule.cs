using Darumen.Contracts.V1;
using Darumen.Shared.Modules;
using Darumen.Shared.Options;
using Microsoft.Extensions.Options;

namespace Darumen.Modules.Queue;

public sealed class QueueModule : IDarumenModule
{
    public string Name => "queue";

    public void AddServices(IServiceCollection services, IConfiguration configuration)
    {
        services.AddGrpcClient<QueueIntelligence.QueueIntelligenceClient>((sp, o) =>
            o.Address = new Uri(sp.GetRequiredService<IOptions<ModelServicesOptions>>().Value.Address));
        services.AddScoped<IQueueStateRepository, QueueStateRepository>();
        services.AddScoped<QueueService>();
    }

    public void MapEndpoints(IEndpointRouteBuilder api) => QueueEndpoints.Map(api);
}
