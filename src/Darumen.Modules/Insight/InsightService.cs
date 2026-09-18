using Darumen.Modules.RefData;
using Darumen.Shared.Api;
using Microsoft.Extensions.AI;
using Microsoft.Extensions.Options;

namespace Darumen.Modules.Insight;

/// <summary>Фабрика клиента модели; null без ключа, чтобы API отвечал 503, а не падал.</summary>
public interface IInsightChatClientFactory
{
    IChatClient? Create();
}

public sealed class LlmChatClientFactory(IOptions<InsightOptions> options) : IInsightChatClientFactory
{
    public const string OllamaPlaceholderKey = "ollama";

    public static string KeyVariable(string provider) => provider.ToLowerInvariant() switch
    {
        InsightOptions.Anthropic => "ANTHROPIC_API_KEY",
        InsightOptions.OpenAi => "OPENAI_API_KEY",
        InsightOptions.Ollama => "OLLAMA_API_KEY",
        _ => "DEEPSEEK_API_KEY",
    };

    /// <summary>Ollama ключ не проверяет, поэтому локальный провайдер доступен без него.</summary>
    public string? ResolveKey()
    {
        var configured = string.IsNullOrWhiteSpace(options.Value.ApiKey) ? Environment.GetEnvironmentVariable(KeyVariable(options.Value.Provider)) : options.Value.ApiKey;
        if (string.IsNullOrWhiteSpace(configured) && string.Equals(options.Value.Provider, InsightOptions.Ollama, StringComparison.OrdinalIgnoreCase))
        {
            return OllamaPlaceholderKey;
        }

        return configured;
    }

    public IChatClient? Create()
    {
        var key = ResolveKey();
        if (string.IsNullOrWhiteSpace(key))
        {
            return null;
        }

        var settings = options.Value;
        if (string.Equals(settings.Provider, InsightOptions.Anthropic, StringComparison.OrdinalIgnoreCase))
        {
            return new Anthropic.AnthropicClient(new Anthropic.Core.ClientOptions { ApiKey = key }).AsIChatClient(settings.Model);
        }

        // DeepSeek и другие OpenAI-совместимые API: тот же клиент, другой адрес
        var client = new OpenAI.OpenAIClient(new System.ClientModel.ApiKeyCredential(key), new OpenAI.OpenAIClientOptions
        {
            Endpoint = new Uri(settings.BaseUrl),
            NetworkTimeout = TimeSpan.FromSeconds(settings.TimeoutSeconds),
            RetryPolicy = new System.ClientModel.Primitives.ClientRetryPolicy(settings.MaxRetries),
        });
        return client.GetChatClient(settings.Model).AsIChatClient();
    }
}

/// <summary>Справочная часть системного промпта: коды регионов и частых профилей, чтобы модель не тратила раунд на их поиск.</summary>
public sealed class InsightPromptCache
{
    public const int TopProfiles = 14;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private string? _reference;

    public async Task<string> ReferenceAsync(IRefDataRepository refData, CancellationToken cancellationToken)
    {
        if (_reference is not null)
        {
            return _reference;
        }

        await _gate.WaitAsync(cancellationToken);
        try
        {
            if (_reference is null)
            {
                var regions = await refData.RegionsAsync(Locale.Ru, cancellationToken);
                var profiles = (await refData.ProfilesAsync(cancellationToken)).Where(p => !p.IsDayHospital).Take(TopProfiles);
                _reference = "Коды регионов (КАТО): " + string.Join("; ", regions.Select(r => $"{r.RegionKato} {r.Name}")) +
                             ".\nЧастые профили коек: " + string.Join("; ", profiles.Select(p => $"{p.ProfileCode} {p.Name}")) +
                             ". Остальные профили: инструмент bed_profiles.";
            }

            return _reference;
        }
        finally
        {
            _gate.Release();
        }
    }
}

public sealed class InsightService(IInsightChatClientFactory factory, InsightTools tools, IOptions<InsightOptions> options, IRefDataRepository refData, InsightPromptCache prompts)
{
    public const string SystemPrompt = """
        Ты аналитик Darumen Health для регулятора здравоохранения Казахстана. Отвечай коротко и с цифрой:
        не больше четырёх предложений или шести строк списка, без таблиц. Отвечай на том же языке, на котором задан
        вопрос (русский или казахский); если язык не ясен — по-русски.
        Данные: направления на плановую госпитализацию за I квартал 2025 года (ИС БГ), госпитализации с 2012 года (ЭРСБ),
        вакцинация, рецепты. Коды регионов и частых профилей даны ниже: бери их оттуда и сразу вызывай нужный инструмент,
        regions и bed_profiles вызывай только для кодов, которых нет в списке. Не выдумывай значения. Если данных нет, скажи об этом.
        Заверши ответ одной строкой на языке ответа: "Источник: <инструменты>" (рус.) или "Дереккөз: <құралдар>" (қаз.).
        """;

    public bool Available => factory.Create() is not null;

    public async Task<AskResponseDto> AskAsync(string question, string? regionKato, CancellationToken cancellationToken)
    {
        var inner = factory.Create() ?? throw new InvalidOperationException("Insight не настроен: задайте ANTHROPIC_API_KEY");
        var client = new ChatClientBuilder(inner).UseFunctionInvocation(configure: c => c.MaximumIterationsPerRequest = options.Value.MaxToolCalls).Build();
        var system = SystemPrompt + "\n" + await prompts.ReferenceAsync(refData, cancellationToken);
        if (options.Value.NoThinkHint && string.Equals(options.Value.Provider, InsightOptions.Ollama, StringComparison.OrdinalIgnoreCase))
        {
            system += "\n/no_think";
        }

        var messages = new List<ChatMessage>
        {
            new(ChatRole.System, system),
            new(ChatRole.User, string.IsNullOrWhiteSpace(regionKato) ? question : $"{question}\n(регион пользователя: {regionKato})"),
        };
        var chatOptions = new ChatOptions { Tools = [.. tools.All()], MaxOutputTokens = options.Value.MaxOutputTokens, Temperature = 0 };
        var effort = options.Value.ReasoningEffort;
        if (!string.IsNullOrWhiteSpace(effort) && !string.Equals(options.Value.Provider, InsightOptions.Anthropic, StringComparison.OrdinalIgnoreCase))
        {
            // reasoning_effort уходит в OpenAI-совместимый запрос как есть; для Ollama значение none выключает скрытые рассуждения
#pragma warning disable OPENAI001 // свойство помечено экспериментальным в OpenAI SDK, но именно оно управляет рассуждениями
            chatOptions.RawRepresentationFactory = _ => new OpenAI.Chat.ChatCompletionOptions { ReasoningEffortLevel = new OpenAI.Chat.ChatReasoningEffortLevel(effort) };
#pragma warning restore OPENAI001
        }

        ChatResponse response;
        try
        {
            response = await client.GetResponseAsync(messages, chatOptions, cancellationToken);
        }
        catch (Exception exception) when (exception is HttpRequestException or System.ClientModel.ClientResultException or TaskCanceledException)
        {
            throw new InsightUnavailableException($"{options.Value.Provider}/{options.Value.Model} не ответил: {exception.Message}", exception);
        }

        var answer = StripThinking(response.Text).Trim();
        var used = tools.Used.Distinct().ToList();
        return new AskResponseDto(answer, ExtractValue(answer), null, tools.Chart, used, used.Select(u => $"tool:{u}").ToList(), $"{options.Value.Provider}/{options.Value.Model}");
    }

    /// <summary>Qwen3 и похожие модели оборачивают размышления в теги think; в ответ они не попадают.</summary>
    public static string StripThinking(string text) =>
        System.Text.RegularExpressions.Regex.Replace(text ?? string.Empty, @"<think>.*?</think>", string.Empty, System.Text.RegularExpressions.RegexOptions.Singleline);

    /// <summary>Первое число в ответе, если оно есть: удобно для карточки с цифрой.</summary>
    public static double? ExtractValue(string answer)
    {
        var token = System.Text.RegularExpressions.Regex.Match(answer, @"-?\d+(?:[.,]\d+)?");
        return token.Success && double.TryParse(token.Value.Replace(',', '.'), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var value) ? value : null;
    }
}

/// <summary>Модель не отвечает или отказала: API отдаёт 503, а не 500.</summary>
public sealed class InsightUnavailableException(string message, Exception inner) : Exception(message, inner);
