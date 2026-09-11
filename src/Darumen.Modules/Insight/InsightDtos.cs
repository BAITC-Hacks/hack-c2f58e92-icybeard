namespace Darumen.Modules.Insight;

public sealed record AskRequestDto(string? Question, string? RegionKato);

public sealed record ChartSeriesDto(string Name, IReadOnlyList<double?> Data);

public sealed record ChartDto(string Type, string Title, IReadOnlyList<string> X, IReadOnlyList<ChartSeriesDto> Series);

public sealed record AskResponseDto(
    string Answer, double? Value, string? Unit, ChartDto? Chart, IReadOnlyList<string> ToolsUsed, IReadOnlyList<string> Sources, string Model);

public sealed class InsightOptions
{
    public const string Section = "Insight";
    public const string Ollama = "ollama";
    public const string DeepSeek = "deepseek";
    public const string OpenAi = "openai";
    public const string Anthropic = "anthropic";

    /// <summary>ollama (локальная модель, без ключа), deepseek, openai или anthropic.</summary>
    public string Provider { get; set; } = Ollama;

    public string Model { get; set; } = "darumen-qwen3.8:27b";

    public string BaseUrl { get; set; } = "http://localhost:11434/v1";

    /// <summary>Для Qwen3 в Ollama: добавить /no_think в системный промпт, чтобы не тратить время на размышления.</summary>
    public bool NoThinkHint { get; set; } = true;

    /// <summary>Ключ из конфигурации; иначе DEEPSEEK_API_KEY, OPENAI_API_KEY или ANTHROPIC_API_KEY по провайдеру.</summary>
    public string? ApiKey { get; set; }

    public int MaxOutputTokens { get; set; } = 900;

    public int MaxToolCalls { get; set; } = 8;

    /// <summary>Таймаут одного обращения к модели; локальные модели медленные, но повторы им не помогают.</summary>
    public int TimeoutSeconds { get; set; } = 180;

    public int MaxRetries { get; set; }
}
