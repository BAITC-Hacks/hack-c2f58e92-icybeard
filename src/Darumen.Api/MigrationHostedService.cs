using Darumen.Migrations;
using Microsoft.EntityFrameworkCore;

namespace Darumen.Api;

/// <summary>Применяет миграции при старте; без Postgres приложение всё равно поднимается и отвечает 503 на данных.</summary>
public sealed class MigrationHostedService(IServiceProvider services, IConfiguration configuration, ILogger<MigrationHostedService> logger) : IHostedService
{
    public const string Setting = "Database:MigrateOnStartup";

    public async Task StartAsync(CancellationToken cancellationToken)
    {
        if (!configuration.GetValue(Setting, true))
        {
            return;
        }

        try
        {
            using var scope = services.CreateScope();
            await scope.ServiceProvider.GetRequiredService<DarumenDbContext>().Database.MigrateAsync(cancellationToken);
            logger.LogInformation("Database migrations applied");
        }
        catch (Exception exception)
        {
            logger.LogWarning(exception, "Postgres is unavailable, migrations were not applied");
        }
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}
