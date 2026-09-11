namespace Darumen.Modules.Insight;

public sealed record AskRequestDto(string? Question, string? RegionKato);

public sealed record ChartSeriesDto(string Name, IReadOnlyList<double?> Data);

public sealed record ChartDto(string Type, string Title, IReadOnlyList<string> X, IReadOnlyList<ChartSeriesDto> Series);

public sealed record AskResponseDto(
    string Answer, double? Value, string? Unit, ChartDto? Chart, IReadOnlyList<string> ToolsUsed, IReadOnlyList<string> Sources, string Model);

public sealed class InsightOptions
{
    public const string Section = "Insight";
    public const string DeepSeek = "deepseek";
    public const string OpenAi = "openai";
    public const string Anthropic = "anthropic";

    /// <summary>deepseek (OpenAI-совместимый API, дешевле), openai или anthropic.</summary>
    public string Provider { get; set; } = DeepSeek;

    public string Model { get; set; } = "deepseek-chat";

    public string BaseUrl { get; set; } = "https://api.deepseek.com/v1";

    /// <summary>Ключ из конфигурации; иначе DEEPSEEK_API_KEY, OPENAI_API_KEY или ANTHROPIC_API_KEY по провайдеру.</summary>
    public string? ApiKey { get; set; }

    public int MaxOutputTokens { get; set; } = 900;

    public int MaxToolCalls { get; set; } = 8;
}
