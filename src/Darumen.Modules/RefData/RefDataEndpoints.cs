using Darumen.Shared.Api;

namespace Darumen.Modules.RefData;

public static class RefDataEndpoints
{
    private const int DefaultLimit = 50;
    private const int MaxLimit = 500;
    private static readonly TimeSpan CacheFor = TimeSpan.FromHours(1);

    public static void Map(IEndpointRouteBuilder api)
    {
        var group = api.MapGroup("/refdata").WithTags("RefData").CacheOutput(p => p.Expire(CacheFor).SetVaryByHeader("Accept-Language").SetVaryByQuery("*"));

        group.MapGet("/regions", async (HttpRequest http, IRefDataRepository repository, CancellationToken ct) =>
                Results.Ok(new { items = await repository.RegionsAsync(Locale.From(http), ct) }))
            .WithName("Regions").WithSummary("Регионы (КАТО), столицы и координаты");

        group.MapGet("/organizations", async (string? regionKato, string? q, int? limit, IRefDataRepository repository, CancellationToken ct) =>
                Results.Ok(new { items = await repository.OrganizationsAsync(regionKato, q, Math.Clamp(limit ?? DefaultLimit, 1, MaxLimit), ct) }))
            .WithName("Organizations").WithSummary("Реестр медицинских организаций с поиском по названию");

        group.MapGet("/profiles", async (IRefDataRepository repository, CancellationToken ct) =>
                Results.Ok(new { items = await repository.ProfilesAsync(ct) }))
            .WithName("Profiles").WithSummary("Профили коек");
    }
}
