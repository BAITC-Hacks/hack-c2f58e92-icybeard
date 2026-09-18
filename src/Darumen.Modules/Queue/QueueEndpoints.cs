using Darumen.Shared.Api;
using Darumen.Shared.Auth;

namespace Darumen.Modules.Queue;

public static class QueueEndpoints
{
    private const int DefaultSeriesDays = 90;
    private const int DefaultOverloadedLimit = 20;
    private const int MaxOverloadedLimit = 200;

    public static void Map(IEndpointRouteBuilder api)
    {
        var group = api.MapGroup("/queue").WithTags("Queue");

        group.MapPost("/predict", async (PredictRequestDto body, HttpRequest http, QueueService service, CancellationToken ct) =>
            {
                var errors = Validate(body);
                return errors.Any ? errors.Problem() : Results.Ok(await service.PredictAsync(body, Locale.From(http), ct));
            })
            .WithName("PredictWait")
            .WithSummary("Ожидание плановой госпитализации и риск отказа")
            .Produces<PredictResponseDto>()
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity);

        group.MapPost("/alternatives", async (AlternativesRequestDto body, QueueService service, CancellationToken ct) =>
            {
                var errors = Validate(body.Base);
                return errors.Any ? errors.Problem() : Results.Ok(await service.AlternativesAsync(body, ct));
            })
            .WithName("QueueAlternatives")
            .WithSummary("Организации того же региона и профиля с меньшим ожиданием")
            .Produces<AlternativesResponseDto>()
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity);

        group.MapGet("/organizations/{moCode}", async (string moCode, string profileCode, int? days, IQueueStateRepository repository, CancellationToken ct) =>
            {
                var series = await repository.SeriesAsync(moCode, profileCode, days ?? DefaultSeriesDays, ct);
                return series is null ? Results.NotFound() : Results.Ok(series);
            })
            .RequireAuthorization(Policies.ChiefOrRegulator)
            .WithName("QueueOrganizationSeries")
            .WithSummary("Ряд очереди и пропускной способности организации по профилю")
            .Produces<OrganizationSeriesDto>()
            .Produces(StatusCodes.Status404NotFound);

        group.MapGet("/overloaded", async (string? regionKato, string? profileCode, int? limit, IQueueStateRepository repository, CancellationToken ct) =>
                Results.Ok(new { items = await repository.OverloadedAsync(regionKato, profileCode, Math.Clamp(limit ?? DefaultOverloadedLimit, 1, MaxOverloadedLimit), ct) }))
            .RequireAuthorization(Policies.ChiefOrRegulator)
            .WithName("QueueOverloaded")
            .WithSummary("Организации с нагрузкой (поток / госпитализации) больше 1, самые загруженные — первыми");
    }

    internal static ValidationErrors Validate(PredictRequestDto body)
    {
        var errors = new ValidationErrors()
            .Require("profileCode", body.ProfileCode)
            .Kato("regionKato", body.RegionKato)
            .Date("registrationDate", body.RegistrationDate);
        if (string.IsNullOrWhiteSpace(body.RegionKato) && string.IsNullOrWhiteSpace(body.MoCode))
        {
            errors.Add("regionKato", "нужен regionKato или moCode");
        }

        return errors;
    }
}
