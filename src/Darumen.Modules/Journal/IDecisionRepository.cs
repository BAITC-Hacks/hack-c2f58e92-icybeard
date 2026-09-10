using Darumen.Shared.Api;

namespace Darumen.Modules.Journal;

public interface IDecisionRepository
{
    /// <summary>Записывает решение и событие в одной транзакции (outbox); при повторном Idempotency-Key
    /// возвращает уже записанное (Created = false) и ничего не публикует.</summary>
    Task<(DecisionDto Decision, bool Created)> RecordAsync(NewDecision decision, Func<DecisionDto, object> outboxEvent, CancellationToken cancellationToken);

    Task<Paged<DecisionDto>> ListAsync(string? actor, string? subject, int page, int size, CancellationToken cancellationToken);
}
