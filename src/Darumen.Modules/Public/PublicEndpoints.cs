using Darumen.Shared.Api;

namespace Darumen.Modules.Public;

public static class PublicEndpoints
{
    public static void Map(IEndpointRouteBuilder api)
    {
        var group = api.MapGroup("/public").WithTags("Public");

        group.MapGet("/daily", async (string? regionKato, HttpRequest http, DailyService service, CancellationToken ct) =>
            {
                var daily = await service.GetAsync(regionKato, Locale.From(http), ct);
                return daily is null ? Results.NotFound() : Results.Ok(daily);
            })
            .WithName("PublicDaily")
            .WithSummary("Гостю на главной: погода на сегодня и завтра по столице региона (Open-Meteo), бытовые советы по погоде и новости о здравоохранении из RSS. Без входа, без персональных данных, без медицинских рекомендаций")
            .Produces<DailyDto>();

        group.MapGet("/login-examples", async (HttpRequest http, LoginExamplesService service, CancellationToken ct) =>
                Results.Ok(await service.GetAsync(Locale.From(http), ct)))
            .WithName("LoginExamples")
            .WithSummary("Пример-карточки страницы входа: ожидание (г. Алматы · офтальмология: p50, p90, доля за 30 дней) и одно МНН с покрытием и сроками обеспечения; без входа, кэш 1 ч")
            .Produces<LoginExamplesDto>();
    }
}
