using Darumen.Api;
using Darumen.Modules.Access.Data;
using Darumen.Modules.Access.Identity;
using Darumen.Modules.Access.Mail;
using Darumen.Modules.Access.Status;
using Darumen.Contracts.V1;
using Darumen.Modules.Analytics;
using Darumen.Modules.Insight;
using Darumen.Modules.Intake;
using Darumen.Modules.Journal;
using Darumen.Modules.Medicines;
using Darumen.Modules.Public;
using Darumen.Modules.Queue;
using Darumen.Modules.RefData;
using Darumen.Shared.Api;
using Darumen.Shared.Auth;
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

    public FakeInsightFactory Insight { get; } = new();

    public FakeWeather Weather { get; } = new();

    public FakeNews News { get; } = new();

    public InMemoryPermissionStore Permissions { get; } = new();

    public FakeIdentityAdmin Identity { get; } = new();

    public FakeEmailSender Mail { get; } = new();

    /// <summary>Проба почтового сервера для GET /public/service-status (по умолчанию сервер «доступен»).</summary>
    public FakeSmtpProbe SmtpProbe { get; } = new();

    public InMemoryInvitationStore Invitations { get; } = new();

    public InMemoryOrgApplicationStore Applications { get; } = new();

    public InMemoryAccountStore Accounts { get; } = new();

    public InMemoryActivity Activity { get; } = new();

    /// <summary>Клиент с ролью для схемы заголовков; moCode — клейм mo_code (scope own), session — клейм sid.</summary>
    public HttpClient CreateClient(string role, string actor = "user-1", string? region = null, string? moCode = null, string? session = null)
    {
        var client = CreateClient();
        client.DefaultRequestHeaders.Add(HeaderAuthenticationHandler.ActorHeader, actor);
        client.DefaultRequestHeaders.Add(HeaderAuthenticationHandler.RoleHeader, role);
        AddHeader(client, HeaderAuthenticationHandler.RegionHeader, region);
        AddHeader(client, HeaderAuthenticationHandler.MoCodeHeader, moCode);
        AddHeader(client, HeaderAuthenticationHandler.SessionHeader, session);
        return client;
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseSetting(MigrationHostedService.Setting, "false");
        builder.UseSetting($"{MessagingOptions.Section}:Mode", MessagingOptions.StubMode);
        builder.UseSetting($"{AuthOptions.Section}:Mode", AuthOptions.HeadersMode);
        // публичные формы ограничены по адресу, а у TestServer адрес один на все тесты класса; лимит проверяет отдельный тест
        builder.UseSetting($"{RateLimitOptions.Section}:{nameof(RateLimitOptions.PublicFormsPerMinute)}", "10000");
        // общий лимит на /api/* тоже считается по одному адресу TestServer; лимит проверяют отдельные тесты RateLimitTests
        builder.UseSetting($"{GlobalRateLimitOptions.Section}:{nameof(GlobalRateLimitOptions.PermitLimit)}", "100000");
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
            services.RemoveAll<IWorklistRepository>();
            services.AddSingleton<IWorklistRepository, InMemoryWorklist>();
            services.RemoveAll<IMedicinesRepository>();
            services.AddSingleton<IMedicinesRepository, InMemoryMedicines>();
            services.RemoveAll<IInsightChatClientFactory>();
            services.AddSingleton<IInsightChatClientFactory>(Insight);
            services.RemoveAll<IWeatherSource>();
            services.AddSingleton<IWeatherSource>(Weather);
            services.RemoveAll<INewsSource>();
            services.AddSingleton<INewsSource>(News);
            services.RemoveAll<IIntakeRepository>();
            services.AddSingleton<IIntakeRepository, InMemoryIntake>();
            ReplaceAccess(services);
        });
    }

    private void ReplaceAccess(IServiceCollection services)
    {
        // журнал аудита пишется в Postgres фоновым писателем: в тестах он не нужен и не должен трогать базу разработчика
        foreach (var writer in services.Where(d => d.ImplementationType == typeof(AuditWriter)).ToList())
        {
            services.Remove(writer);
        }

        services.RemoveAll<IPermissionStore>();
        services.AddSingleton<IPermissionStore>(Permissions);
        services.RemoveAll<IIdentityAdmin>();
        services.AddSingleton<IIdentityAdmin>(Identity);
        services.RemoveAll<IEmailSender>();
        services.AddSingleton<IEmailSender>(Mail);
        services.RemoveAll<ISmtpProbe>();
        services.AddSingleton<ISmtpProbe>(SmtpProbe);
        services.RemoveAll<IInvitationStore>();
        services.AddSingleton<IInvitationStore>(Invitations);
        services.RemoveAll<IOrgApplicationStore>();
        services.AddSingleton<IOrgApplicationStore>(Applications);
        services.RemoveAll<IAccountStore>();
        services.AddSingleton<IAccountStore>(Accounts);
        services.RemoveAll<IActivityReader>();
        services.AddSingleton<IActivityReader>(Activity);
        services.RemoveAll<IOrgDataStatus>();
        services.AddSingleton<IOrgDataStatus>(Activity);
        services.RemoveAll<IAuditRepository>();
        services.AddSingleton<IAuditRepository, InMemoryAudit>();
    }

    private static void AddHeader(HttpClient client, string name, string? value)
    {
        if (value is not null)
        {
            client.DefaultRequestHeaders.Add(name, value);
        }
    }
}
