using Darumen.Api;
using Darumen.Contracts.V1;
using Darumen.Modules.Analytics;
using Darumen.Modules.Intake;
using Darumen.Modules.Journal;
using Darumen.Modules.Queue;
using Darumen.Modules.RefData;
using Darumen.Shared.Messaging;
using Darumen.Tests.Fakes;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace Darumen.Tests;

/// <summary>API с подменёнными gRPC-клиентами и хранилищами: контракт REST проверяется без Python и Postgres.</summary>
public sealed class TestApp : WebApplicationFactory<Program>
{
    public FakeQueueClient Queue { get; } = new();

    public FakeForecastClient Forecast { get; } = new();

    public FakeSimulationClient Simulation { get; } = new();

    public InMemoryAnalytics Analytics { get; } = new();

    public InMemoryDecisions Decisions { get; } = new();

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseSetting(MigrationHostedService.Setting, "false");
        builder.UseSetting($"{MessagingOptions.Section}:Mode", MessagingOptions.StubMode);
        builder.ConfigureServices(services =>
        {
            services.RemoveAll<QueueIntelligence.QueueIntelligenceClient>();
            services.AddSingleton<QueueIntelligence.QueueIntelligenceClient>(Queue);
            services.RemoveAll<LoadForecasting.LoadForecastingClient>();
            services.AddSingleton<LoadForecasting.LoadForecastingClient>(Forecast);
            services.RemoveAll<Simulation.SimulationClient>();
            services.AddSingleton<Simulation.SimulationClient>(Simulation);
            services.RemoveAll<IQueueStateRepository>();
            services.AddSingleton<IQueueStateRepository, InMemoryQueueStates>();
            services.RemoveAll<IAnalyticsRepository>();
            services.AddSingleton<IAnalyticsRepository>(Analytics);
            services.RemoveAll<IDecisionRepository>();
            services.AddSingleton<IDecisionRepository>(Decisions);
            services.RemoveAll<IRefDataRepository>();
            services.AddSingleton<IRefDataRepository, InMemoryRefData>();
            services.RemoveAll<IIntakeRepository>();
            services.AddSingleton<IIntakeRepository, InMemoryIntake>();
        });
    }
}
