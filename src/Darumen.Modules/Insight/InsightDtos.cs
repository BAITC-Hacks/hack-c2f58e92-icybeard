namespace Darumen.Modules.Insight;

public sealed record AskRequestDto(string? Question, string? RegionKato);

public sealed record ChartSeriesDto(string Name, IReadOnlyList<double?> Data);

public sealed record ChartDto(string Type, string Title, IReadOnlyList<string> X, IReadOnlyList<ChartSeriesDto> Series);

public sealed record AskResponseDto(
    string Answer, double? Value, string? Unit, ChartDto? Chart, IReadOnlyList<string> ToolsUsed, IReadOnlyList<string> Sources, string Model);

public sealed class InsightOptions
{
    public const string Section = "Insight";

    public string Model { get; set; } = "claude-sonnet-5";

    public string? ApiKey { get; set; }

    public int MaxOutputTokens { get; set; } = 900;

    public int MaxToolCalls { get; set; } = 8;
}
