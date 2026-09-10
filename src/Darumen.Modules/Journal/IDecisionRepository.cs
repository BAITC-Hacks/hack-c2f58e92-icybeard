using Darumen.Shared.Api;

namespace Darumen.Modules.Journal;

public interface IDecisionRepository
{
    /// <summary>Записывает решение; при повторном Idempotency-Key возвращает уже записанное (Created = false).</summary>
    Task<(DecisionDto Decision, bool Created)> RecordAsync(NewDecision decision, CancellationToken cancellationToken);

    Task<Paged<DecisionDto>> ListAsync(string? actor, string? subject, int page, int size, CancellationToken cancellationToken);
}
