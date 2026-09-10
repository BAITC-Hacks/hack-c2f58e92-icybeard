using Darumen.Shared.Modules;

namespace Darumen.Modules.Medicines;

public sealed class MedicinesModule : IDarumenModule
{
    public string Name => "medicines";

    public void AddServices(IServiceCollection services, IConfiguration configuration)
    {
        services.AddScoped<IMedicinesRepository, MedicinesRepository>();
        services.AddScoped<MedicinesService>();
    }

    public void MapEndpoints(IEndpointRouteBuilder api) => MedicinesEndpoints.Map(api);
}
