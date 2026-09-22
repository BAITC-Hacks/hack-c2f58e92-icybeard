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

        group.MapGet("/organizations", async (string? regionKato, string? q, string? profileCode, int? limit, IRefDataRepository repository, CancellationToken ct) =>
                Results.Ok(new { items = await repository.OrganizationsAsync(regionKato, q, profileCode, Math.Clamp(limit ?? DefaultLimit, 1, MaxLimit), ct) }))
            .WithName("Organizations").WithSummary("Реестр медицинских организаций с поиском по названию");

        group.MapGet("/profiles", async (IRefDataRepository repository, CancellationToken ct) =>
                Results.Ok(new { items = await repository.ProfilesAsync(ct) }))
            .WithName("Profiles").WithSummary("Профили коек");

        group.MapGet("/seasonality", async (IRefDataRepository repository, CancellationToken ct) =>
                Results.Ok(new { items = await repository.SeasonalityAsync(ct) }))
            .WithName("Seasonality").WithSummary("Внешние сезонные формы (NHS, 2017–2019): множители месяцев при среднем = 1, ориентир для месяцев вне наблюдённого квартала");

        group.MapGet("/vaccination", async (IRefDataRepository repository, CancellationToken ct) =>
                Results.Ok(new { items = await repository.VaccinationAsync(ct) }))
            .WithName("VaccinationBenchmarks").WithSummary("Оценки охвата вакцинацией WUENIC (ВОЗ/ЮНИСЕФ) по Казахстану: внешний ориентир для сигналов, не факт");

        group.MapGet("/vaccination-plans", async (string? regionKato, IRefDataRepository repository, CancellationToken ct) =>
                Results.Ok(new { items = await repository.VaccinationPlansAsync(regionKato, ct) }))
            .WithName("VaccinationPlans").WithSummary("Коды планов вакцинации, встречающиеся в данных — для переключателя потока на странице региона");

        group.MapGet("/route-standard", async (HttpRequest http, IRefDataRepository repository, CancellationToken ct) =>
                Results.Ok(await repository.RouteStandardAsync(Locale.From(http), ct)))
            .WithName("RouteStandard").WithSummary("Стандарт стационарной помощи (приказ МЗ РК ҚР-ДСМ-27): стадии маршрута, чек-лист приложения 5 со сроками давности, причины отказа и ориентир МЗ РК по ожиданию — логистика, не медицинские рекомендации")
            .Produces<RouteStandardDto>();
    }
}
