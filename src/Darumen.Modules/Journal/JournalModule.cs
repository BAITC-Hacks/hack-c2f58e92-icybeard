using Darumen.Shared.Modules;

namespace Darumen.Modules.Journal;

public sealed class JournalModule : IDarumenModule
{
    public string Name => "journal";

    public void AddServices(IServiceCollection services, IConfiguration configuration)
    {
        services.AddScoped<IDecisionRepository, DecisionRepository>();
        services.AddScoped<IAuditRepository, AuditRepository>();
    }

    public void MapEndpoints(IEndpointRouteBuilder api) => JournalEndpoints.Map(api);
}
