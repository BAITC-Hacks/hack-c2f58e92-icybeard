using Darumen.Shared.Api;

namespace Darumen.Modules.Analytics;

public sealed record StreamDto(string StreamId, string Title, string Grain, IReadOnlyList<string> EntityKeys, IReadOnlyList<int> Horizons);

public sealed record ForecastPointDto(string Period, double Yhat, double Lo, double Hi);

public sealed record HistoryPointDto(string Period, double Y);

public sealed record BacktestDto(double Smape, double Mase, double BaselineSmape);

public sealed record ForecastResponseDto(
    string StreamId, IReadOnlyDictionary<string, string> Entity, IReadOnlyList<ForecastPointDto> Points,
    IReadOnlyList<HistoryPointDto> History, BacktestDto Backtest, ModelInfoDto Model, bool Flat);

public sealed record AnomalyDto(
    string Id, string StreamId, IReadOnlyDictionary<string, string> Entity, string Period, double Observed, double Expected,
    double Score, double PeerScore, string Severity, string Kind, string Status, string? RegionKato, string? Comment);

public sealed record AnomalyFilter(string? RegionKato, string? StreamId, string? Severity, string? Status);

public sealed record AckRequestDto(string? Comment, string? Status);

/// <summary>Статусы сигнала. Закрывающие статусы ставит человек; они же метки для дообучения детектора (models/anomaly_labels.py).</summary>
public static class AnomalyStatuses
{
    public const string Open = "open";
    public const string Acknowledged = "acknowledged";
    public const string Dismissed = "dismissed";

    public static readonly IReadOnlyList<string> Closing = [Acknowledged, Dismissed];
}

/// <summary>Решение человека по сигналу. RegionScope — регион, которым ограничен пользователь (главврач), иначе null.</summary>
public sealed record AnomalyAckCommand(string AnomalyId, string Status, string? Comment, string Actor, string Role, string? RegionScope);

public enum AckOutcome
{
    Acknowledged,
    NotFound,
    OutOfScope,
}

public sealed record IndexItemDto(string RegionKato, string Name, double ShareOver30, double P90Days, double IndexValue, int Rank, long N);

public sealed record LosItemDto(string RegionKato, string ProfileName, string? ProfileCode, long N, double LosMedianFact, double? LosP50Model);

public sealed record LosResponseDto(IReadOnlyList<LosItemDto> Items, string Method);

public sealed record IndexResponseDto(string Month, string ProfileCode, IReadOnlyList<IndexItemDto> Items, IReadOnlyList<string> Months, string Method);
