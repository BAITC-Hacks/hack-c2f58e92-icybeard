using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace Darumen.Tests.Fakes;

/// <summary>Проверка базы для /health в тестах: Postgres не поднимается, состояние базы задаёт сам тест.</summary>
public sealed class FakeDatabaseHealth : IHealthCheck
{
    public bool Up { get; set; } = true;

    public Task<HealthCheckResult> CheckHealthAsync(HealthCheckContext context, CancellationToken cancellationToken = default) =>
        Task.FromResult(Up ? HealthCheckResult.Healthy() : HealthCheckResult.Unhealthy("Postgres недоступен"));
}
