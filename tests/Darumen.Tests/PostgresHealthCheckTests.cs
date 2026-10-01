using System.Data.Common;
using Darumen.Api;
using Darumen.Shared.Data;
using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace Darumen.Tests;

public sealed class PostgresHealthCheckTests
{
    [Fact]
    public async Task Unreachable_database_is_reported_unhealthy_instead_of_throwing()
    {
        var check = new PostgresHealthCheck(new FailingConnections());
        var context = new HealthCheckContext { Registration = new HealthCheckRegistration("postgres", check, failureStatus: null, tags: null) };

        var result = await check.CheckHealthAsync(context);

        Assert.Equal(HealthStatus.Unhealthy, result.Status);
        Assert.Equal("Postgres недоступен", result.Description);
        Assert.IsType<InvalidOperationException>(result.Exception);
    }

    private sealed class FailingConnections : IDbConnectionFactory
    {
        public Task<DbConnection> OpenAsync(CancellationToken cancellationToken = default) =>
            Task.FromException<DbConnection>(new InvalidOperationException("connection refused"));
    }
}
