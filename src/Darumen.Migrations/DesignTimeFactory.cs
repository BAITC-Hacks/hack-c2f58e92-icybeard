using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace Darumen.Migrations;

/// <summary>Для dotnet ef: строка подключения из POSTGRES_CONNECTION или локальный compose.</summary>
public sealed class DesignTimeFactory : IDesignTimeDbContextFactory<DarumenDbContext>
{
    public const string DefaultConnection = "Host=localhost;Database=darumen;Username=darumen;Password=darumen";

    public DarumenDbContext CreateDbContext(string[] args)
    {
        var connection = Environment.GetEnvironmentVariable("POSTGRES_CONNECTION") ?? DefaultConnection;
        return new DarumenDbContext(new DbContextOptionsBuilder<DarumenDbContext>().UseNpgsql(connection).Options);
    }
}
