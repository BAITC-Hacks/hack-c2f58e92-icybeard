using Microsoft.Extensions.AI;
using Microsoft.Extensions.Options;

namespace Darumen.Modules.Insight;

/// <summary>Фабрика клиента модели; null без ключа, чтобы API отвечал 503, а не падал.</summary>
public interface IInsightChatClientFactory
{
    IChatClient? Create();
}

public sealed class AnthropicChatClientFactory(IOptions<InsightOptions> options) : IInsightChatClientFactory
{
    public IChatClient? Create()
    {
        var key = options.Value.ApiKey ?? Environment.GetEnvironmentVariable("ANTHROPIC_API_KEY");
        if (string.IsNullOrWhiteSpace(key))
        {
            return null;
        }

        var client = new Anthropic.AnthropicClient(new Anthropic.Core.ClientOptions { ApiKey = key });
        return client.AsIChatClient(options.Value.Model);
    }
}

public sealed class InsightService(IInsightChatClientFactory factory, InsightTools tools, IOptions<InsightOptions> options)
{
    public const string SystemPrompt = """
        Ты аналитик Darumen Health для регулятора здравоохранения Казахстана. Отвечай по-русски, коротко и с цифрой.
        Данные: направления на плановую госпитализацию за I квартал 2025 года (ИС БГ), госпитализации с 2012 года (ЭРСБ),
        вакцинация, рецепты. Регионы кодируются КАТО (двузначный), профили коек кодами (381 офтальмология для взрослых,
        021 терапия, 031 кардиология для взрослых). Используй инструменты; не выдумывай значения. Если данных нет, скажи об этом.
        Заверши ответ одной строкой "Источник: <инструменты>".
        """;

    public bool Available => factory.Create() is not null;

    public async Task<AskResponseDto> AskAsync(string question, string? regionKato, CancellationToken cancellationToken)
    {
        var inner = factory.Create() ?? throw new InvalidOperationException("Insight не настроен: задайте ANTHROPIC_API_KEY");
        var client = new ChatClientBuilder(inner).UseFunctionInvocation(configure: c => c.MaximumIterationsPerRequest = options.Value.MaxToolCalls).Build();
        var messages = new List<ChatMessage>
        {
            new(ChatRole.System, SystemPrompt),
            new(ChatRole.User, string.IsNullOrWhiteSpace(regionKato) ? question : $"{question}\n(регион пользователя: {regionKato})"),
        };
        var response = await client.GetResponseAsync(messages, new ChatOptions { Tools = [.. tools.All()], MaxOutputTokens = options.Value.MaxOutputTokens, Temperature = 0 }, cancellationToken);
        var answer = response.Text.Trim();
        var used = tools.Used.Distinct().ToList();
        return new AskResponseDto(answer, ExtractValue(answer), null, tools.Chart, used, used.Select(u => $"tool:{u}").ToList(), options.Value.Model);
    }

    /// <summary>Первое число в ответе, если оно есть: удобно для карточки с цифрой.</summary>
    public static double? ExtractValue(string answer)
    {
        var token = System.Text.RegularExpressions.Regex.Match(answer, @"-?\d+(?:[.,]\d+)?");
        return token.Success && double.TryParse(token.Value.Replace(',', '.'), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var value) ? value : null;
    }
}
