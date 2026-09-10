using System.Data.Common;
using Dapper;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;

namespace Darumen.Shared.Data;

public interface IDbConnectionFactory
{
    Task<DbConnection> OpenAsync(CancellationToken cancellationToken = default);
}

public sealed class NpgsqlConnectionFactory(NpgsqlDataSource dataSource) : IDbConnectionFactory
{
    public async Task<DbConnection> OpenAsync(CancellationToken cancellationToken = default) =>
        await dataSource.OpenConnectionAsync(cancellationToken);
}

public static class DataRegistration
{
    public const string DefaultConnection = "Host=localhost;Database=darumen;Username=darumen;Password=darumen";

    public static string PostgresConnection(this IConfiguration configuration) =>
        configuration.GetConnectionString("Postgres") ?? DefaultConnection;

    public static IServiceCollection AddDarumenPostgres(this IServiceCollection services, IConfiguration configuration)
    {
        DefaultTypeMap.MatchNamesWithUnderscores = true;
        services.AddSingleton(_ => NpgsqlDataSource.Create(configuration.PostgresConnection()));
        services.AddSingleton<IDbConnectionFactory, NpgsqlConnectionFactory>();
        return services;
    }
}
