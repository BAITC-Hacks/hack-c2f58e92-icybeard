using Darumen.Contracts.V1;
using Darumen.Shared.Api;
using Darumen.Shared.Auth;
using Darumen.Shared.Messaging;

namespace Darumen.Modules.Analytics;

public static class AnalyticsEndpoints
{
    public const string AllProfiles = "all";
    private const string IndexMethod =
        "Индекс = 100 − среднее перцентильных рангов региона по доле ожидавших дольше 30 дней и по 90-му перцентилю ожидания внутри месяца и профиля; " +
        "100 у самого доступного региона. Строки с числом госпитализаций меньше 5 подавлены.";

    public static void Map(IEndpointRouteBuilder api)
    {
        api.MapGet("/streams", async (IAnalyticsRepository repository, CancellationToken ct) =>
                Results.Ok(new { items = await repository.StreamsAsync(ct) }))
            .RequireAuthorization(Policies.Authenticated)
            .WithTags("Forecast").WithName("Streams").WithSummary("Каталог зарегистрированных потоков");

        api.MapGet("/forecast/{streamId}", async (string streamId, int? horizon, HttpRequest http, ForecastService service, CancellationToken ct) =>
                await service.ForecastAsync(streamId, ParseEntity(http.Query), horizon ?? 0, ct))
            .RequireAuthorization(Policies.ChiefOrRegulator)
            .WithTags("Forecast").WithName("Forecast").WithSummary("Прогноз потока для сущности: entity[regionKato]=75&entity[profileCode]=381")
            .Produces<ForecastResponseDto>().ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity).ProducesProblem(StatusCodes.Status404NotFound);

        var anomalies = api.MapGroup("/anomalies").WithTags("Anomalies").RequireAuthorization(Policies.ChiefOrRegulator);
        anomalies.MapGet("/", async (string? regionKato, string? streamId, string? severity, string? status, int? page, int? size,
                IAnalyticsRepository repository, CancellationToken ct) =>
            {
                var (p, s) = Paging.Normalize(page, size);
                return Results.Ok(await repository.AnomaliesAsync(new AnomalyFilter(regionKato, streamId, severity, status ?? "open"), p, s, ct));
            })
            .WithName("Anomalies").WithSummary("Сигналы аномалий, по умолчанию открытые, отсортированы по силе")
            .Produces<Paged<AnomalyDto>>();

        anomalies.MapPost("/{id}/ack", async (string id, AckRequestDto? body, HttpContext http, IAnalyticsRepository repository, CancellationToken ct) =>
            {
                var status = string.IsNullOrWhiteSpace(body?.Status) ? "acknowledged" : body.Status;
                var user = CurrentUser.From(http);
                var acknowledged = await repository.AcknowledgeAsync(id, status, body?.Comment, user.Actor,
                    () => new DecisionRecorded
                    {
                        Meta = Events.Meta(),
                        DecisionId = id,
                        ActorRole = user.Role,
                        Subject = "anomaly",
                        Recommended = "open",
                        Chosen = status,
                        Reason = body?.Comment ?? string.Empty,
                    },
                    ct);
                return acknowledged ? Results.NoContent() : Results.NotFound();
            })
            .WithName("AcknowledgeAnomaly").WithSummary("Подтвердить или закрыть сигнал")
            .Produces(StatusCodes.Status204NoContent).Produces(StatusCodes.Status404NotFound);

        api.MapGet("/quality", (QualityService quality) => quality.Report())
            .RequireAuthorization(Policies.Authenticated)
            .WithTags("Quality").WithName("ModelQuality")
            .WithSummary("Качество моделей: отчёты обучения против baseline, разбор по регионам и профилям, доля плоских прогнозов");

        api.MapGet("/index", async (string? month, string? profileCode, HttpRequest http, IAnalyticsRepository repository, CancellationToken ct) =>
            {
                var months = await repository.IndexMonthsAsync(ct);
                if (months.Count == 0)
                {
                    return Results.Ok(new IndexResponseDto(month ?? string.Empty, profileCode ?? AllProfiles, [], [], IndexMethod));
                }

                var chosen = string.IsNullOrWhiteSpace(month) ? months[^1] : month;
                if (!months.Contains(chosen))
                {
                    return new ValidationErrors().Add("month", $"нет данных за {chosen}; доступны {string.Join(", ", months)}").Problem();
                }

                var profile = string.IsNullOrWhiteSpace(profileCode) ? AllProfiles : profileCode;
                var items = await repository.IndexAsync(chosen, profile, Locale.From(http), ct);
                return Results.Ok(new IndexResponseDto(chosen, profile, items, months, IndexMethod));
            })
            .WithTags("Index").WithName("AccessIndex").WithSummary("Индекс доступности плановой госпитализации по регионам")
            .Produces<IndexResponseDto>().ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity);
    }

    /// <summary>entity[regionKato]=75 → region_kato: 75; ключи в snake_case тоже принимаются.</summary>
    internal static IReadOnlyDictionary<string, string> ParseEntity(IQueryCollection query)
    {
        var entity = new Dictionary<string, string>();
        foreach (var (key, value) in query)
        {
            if (key.StartsWith("entity[", StringComparison.Ordinal) && key.EndsWith(']'))
            {
                entity[EntityJson.ToSnake(key[7..^1])] = value.ToString();
            }
        }

        return entity;
    }
}
