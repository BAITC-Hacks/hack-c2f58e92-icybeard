using Darumen.Shared.Modules;

namespace Darumen.Modules.Insight;

public sealed class InsightModule : IDarumenModule
{
    public string Name => "insight";

    public void AddServices(IServiceCollection services, IConfiguration configuration)
    {
        services.Configure<InsightOptions>(configuration.GetSection(InsightOptions.Section));
        services.AddSingleton<IInsightChatClientFactory, LlmChatClientFactory>();
        services.AddSingleton<InsightPromptCache>();
        services.AddScoped<InsightTools>();
        services.AddScoped<InsightService>();
    }

    public void MapEndpoints(IEndpointRouteBuilder api) => InsightEndpoints.Map(api);
}
