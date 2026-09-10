using Darumen.Modules.Insight;
using Microsoft.Extensions.AI;

namespace Darumen.Tests.Fakes;

/// <summary>Модель, которая на первый ход зовёт инструмент access_index, а на второй отвечает текстом с цифрой.</summary>
public sealed class FakeChatClient : IChatClient
{
    public int Calls { get; private set; }

    public Task<ChatResponse> GetResponseAsync(IEnumerable<ChatMessage> messages, ChatOptions? options = null, CancellationToken cancellationToken = default)
    {
        Calls++;
        var history = messages.ToList();
        var toolResults = history.SelectMany(m => m.Contents).OfType<FunctionResultContent>().ToList();
        if (toolResults.Count == 0)
        {
            var call = new FunctionCallContent("call-1", "access_index", new Dictionary<string, object?> { ["month"] = null, ["profileCode"] = "381" });
            return Task.FromResult(new ChatResponse(new ChatMessage(ChatRole.Assistant, [call])));
        }

        var payload = toolResults[0].Result?.ToString() ?? string.Empty;
        var answer = payload.Contains("62") ? "Лучший регион по офтальмологии: Павлодарская область, индекс 95.2.\nИсточник: access_index" : "Данных нет.";
        return Task.FromResult(new ChatResponse(new ChatMessage(ChatRole.Assistant, answer)));
    }

    public IAsyncEnumerable<ChatResponseUpdate> GetStreamingResponseAsync(IEnumerable<ChatMessage> messages, ChatOptions? options = null, CancellationToken cancellationToken = default) =>
        throw new NotSupportedException();

    public object? GetService(Type serviceType, object? serviceKey = null) => null;

    public void Dispose()
    {
    }
}

public sealed class FakeInsightFactory : IInsightChatClientFactory
{
    public bool Enabled { get; set; } = true;

    public FakeChatClient Client { get; } = new();

    public IChatClient? Create() => Enabled ? Client : null;
}
