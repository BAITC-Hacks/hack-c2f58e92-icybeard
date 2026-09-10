using Darumen.Shared.Modules;

namespace Darumen.Modules.Intake;

public sealed class IntakeModule : IDarumenModule
{
    public string Name => "intake";

    public void AddServices(IServiceCollection services, IConfiguration configuration) =>
        services.AddScoped<IIntakeRepository, IntakeRepository>();

    public void MapEndpoints(IEndpointRouteBuilder api) => IntakeEndpoints.Map(api);
}
