using Darumen.Contracts.V1;
using Grpc.Core;

namespace Darumen.Tests.Fakes;

public static class Grpc
{
    public static AsyncUnaryCall<T> Unary<T>(T response) =>
        new(Task.FromResult(response), Task.FromResult(new Metadata()), () => Status.DefaultSuccess, () => new Metadata(), () => { });

    public static ModelInfo Model(string name = "wait_quantile") => new() { Name = name, Version = "1.0.0", TrainedThrough = "2025-02-28" };

    public static Explanation Explanation() => new()
    {
        SummaryRu = "Базовое ожидание 10 дн.",
        SummaryKz = "Базалық күту 10 күн",
        Factors = { new Factor { Name = "queue_len", Contribution = 3.2, TextRu = "очередь: 40", TextKz = "кезек: 40" } },
    };
}

public sealed class FakeQueueClient : QueueIntelligence.QueueIntelligenceClient
{
    public Func<PredictWaitRequest, PredictWaitResponse> OnPredictWait { get; set; } = _ => new PredictWaitResponse
    {
        P50Days = 12,
        P90Days = 40,
        PWithin30Days = 0.7,
        Explanation = Grpc.Explanation(),
        Model = Grpc.Model(),
    };

    public Func<PredictWaitRequest, PredictRefusalResponse> OnPredictRefusal { get; set; } = _ => new PredictRefusalResponse
    {
        PRefusal = 0.08,
        Explanation = Grpc.Explanation(),
        Model = Grpc.Model(),
    };

    public Func<AlternativesRequest, AlternativesResponse> OnAlternatives { get; set; } = r => new AlternativesResponse
    {
        Model = Grpc.Model(),
        Alternatives =
        {
            new Alternative { Organization = new OrganizationRef { MoCode = "22GN", Name = "Больница 2", Region = new RegionRef { Kato = "75" } }, P50Days = 8.8, P90Days = 20, PRefusal = 0.05, DistanceKm = 0 },
            new Alternative { Organization = new OrganizationRef { MoCode = "229T", Name = "Больница 3", Region = new RegionRef { Kato = "75" } }, P50Days = 21.8, P90Days = 50, PRefusal = 0.1, DistanceKm = 0 },
        },
    };

    public override AsyncUnaryCall<PredictWaitResponse> PredictWaitAsync(PredictWaitRequest request, CallOptions options) => Grpc.Unary(OnPredictWait(request));

    public override AsyncUnaryCall<PredictRefusalResponse> PredictRefusalAsync(PredictWaitRequest request, CallOptions options) => Grpc.Unary(OnPredictRefusal(request));

    public override AsyncUnaryCall<AlternativesResponse> AlternativesAsync(AlternativesRequest request, CallOptions options) => Grpc.Unary(OnAlternatives(request));
}

public sealed class FakeForecastClient : LoadForecasting.LoadForecastingClient
{
    public ForecastRequest? LastRequest { get; private set; }

    public override AsyncUnaryCall<ForecastResponse> ForecastAsync(ForecastRequest request, CallOptions options)
    {
        LastRequest = request;
        var response = new ForecastResponse
        {
            Backtest = new BacktestMetrics { Smape = 0.05, Mase = 0.8, BaselineSmape = 0.07 },
            Model = Grpc.Model("AutoETS"),
        };
        for (var h = 1; h <= Math.Max(request.Horizon, 1); h++)
        {
            response.Points.Add(new ForecastPoint { Period = $"2026-0{h}", Yhat = 800 + h, Lo = 700, Hi = 900 });
        }

        return Grpc.Unary(response);
    }
}

public sealed class FakeSimulationClient : Simulation.SimulationClient
{
    public override AsyncUnaryCall<SimulateResponse> SimulateAsync(SimulateRequest request, CallOptions options) => Grpc.Unary(new SimulateResponse
    {
        Organisations = 5,
        Baseline = new ScenarioOutcome { MeanWaitDays = 30 },
        Scenario = new ScenarioOutcome { MeanWaitDays = 30 - request.CapacityDeltaPct / 5 },
        DeltaDays = -request.CapacityDeltaPct / 5,
        CiLow = -request.CapacityDeltaPct / 4,
        CiHigh = -request.CapacityDeltaPct / 6,
        Assumptions = { "поток ±20 %" },
        Model = Grpc.Model("fluid_queue"),
        // 3.4: имитирует ml-сервис — +N коек / 5 (условный LOS) даёт дополнительные госпитализации в день сверх базовых 20.
        AdmissionsPerDay = 20 + request.BedsDelta / 5,
    });

    public override AsyncUnaryCall<RedistributeResponse> RedistributeAsync(RedistributeRequest request, CallOptions options) => Grpc.Unary(new RedistributeResponse
    {
        Moves =
        {
            new Move
            {
                From = new OrganizationRef { MoCode = "SLOW", Name = "Медленная", Region = new RegionRef { Kato = request.Region.Kato } },
                To = new OrganizationRef { MoCode = "FAST", Name = "Быстрая", Region = new RegionRef { Kato = request.Region.Kato } },
                ShareOfSourcePct = 20, ArrivalsPerDay = 1.2, WaitFromBefore = 60, WaitFromAfter = 48, WaitToBefore = 5, WaitToAfter = 9,
            },
        },
        TotalWaitDaysBefore = 1000,
        TotalWaitDaysAfter = 800,
        TotalDeltaDays = -200,
        HorizonDays = 90,
        Model = Grpc.Model("fluid_queue"),
    });
}
