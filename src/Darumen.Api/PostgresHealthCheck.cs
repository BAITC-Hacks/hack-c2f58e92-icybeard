using Darumen.Shared.Data;
using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace Darumen.Api;

/// <summary>/health отвечает Unhealthy, если Postgres не отвечает на SELECT 1. Раньше проверок не было и /health был
/// Healthy при упавшей базе — оркестратор и мониторинг не видели деградацию.</summary>
public sealed class PostgresHealthCheck(IDbConnectionFactory connections) : IHealthCheck
{
    public async Task<HealthCheckResult> CheckHealthAsync(HealthCheckContext context, CancellationToken cancellationToken = default)
    {
        try
        {
            await using var connection = await connections.OpenAsync(cancellationToken);
            await using var command = connection.CreateCommand();
            command.CommandText = "SELECT 1";
            await command.ExecuteScalarAsync(cancellationToken);
            return HealthCheckResult.Healthy();
        }
        catch (Exception e)
        {
            return HealthCheckResult.Unhealthy("Postgres недоступен", e);
        }
    }
}
