using Darumen.Contracts.V1;
using Darumen.Shared.Api;
using Darumen.Shared.Options;
using Microsoft.Extensions.Options;

namespace Darumen.Modules.Analytics;

public sealed class ForecastService(
    LoadForecasting.LoadForecastingClient client,
    IAnalyticsRepository repository,
    IOptions<ModelServicesOptions> options)
{
    public const int HistoryPeriods = 24;

    public async Task<IResult> ForecastAsync(string streamId, IReadOnlyDictionary<string, string> entity, int horizon, CancellationToken cancellationToken)
    {
        var stream = (await repository.StreamsAsync(cancellationToken)).FirstOrDefault(s => s.StreamId == streamId);
        if (stream is null)
        {
            return Results.Problem(statusCode: StatusCodes.Status404NotFound, title: "Поток не найден", detail: $"streamId '{streamId}' не зарегистрирован");
        }

        var missing = stream.EntityKeys.Where(k => !entity.ContainsKey(k)).ToList();
        if (missing.Count > 0)
        {
            return new ValidationErrors().Add("entity", $"нужны ключи: {string.Join(", ", stream.EntityKeys)}; нет: {string.Join(", ", missing)}").Problem();
        }

        var request = new ForecastRequest { StreamId = streamId, Horizon = horizon };
        foreach (var key in stream.EntityKeys)
        {
            request.Entity[key] = entity[key];
        }

        var response = await client.ForecastAsync(request, deadline: DateTime.UtcNow.AddSeconds(options.Value.TimeoutSeconds), cancellationToken: cancellationToken);
        var canonical = EntityJson.Canonical(stream.EntityKeys, entity);
        var history = await repository.HistoryAsync(streamId, canonical, HistoryPeriods + response.Points.Count, cancellationToken);
        var firstForecast = response.Points.FirstOrDefault()?.Period;
        if (firstForecast is not null)
        {
            // хвост истории, который источник ещё догружает, модель отбросила; показываем ряд до первого прогнозного периода
            history = history.Where(h => string.CompareOrdinal(h.Period, firstForecast) < 0).TakeLast(HistoryPeriods).ToList();
        }
        var ordered = stream.EntityKeys.ToDictionary(k => k, k => entity[k]);
        return Results.Ok(new ForecastResponseDto(
            streamId, ordered,
            response.Points.Select(p => new ForecastPointDto(p.Period, p.Yhat, p.Lo, p.Hi)).ToList(),
            history,
            new BacktestDto(response.Backtest?.Smape ?? 0, response.Backtest?.Mase ?? 0, response.Backtest?.BaselineSmape ?? 0),
            response.Model.ToDto()));
    }
}
