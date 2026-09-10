using Microsoft.Extensions.Logging;

namespace Darumen.Shared.Messaging;

/// <summary>Публикация доменных событий; до подключения Wolverine события только логируются.</summary>
public interface IEventPublisher
{
    ValueTask PublishAsync<T>(T @event, CancellationToken cancellationToken = default) where T : class;
}

public sealed class LoggingEventPublisher(ILogger<LoggingEventPublisher> logger) : IEventPublisher
{
    public ValueTask PublishAsync<T>(T @event, CancellationToken cancellationToken = default) where T : class
    {
        logger.LogInformation("Event {EventType}: {@Event}", typeof(T).Name, @event);
        return ValueTask.CompletedTask;
    }
}
