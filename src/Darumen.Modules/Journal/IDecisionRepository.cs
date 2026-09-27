using Darumen.Shared.Api;

namespace Darumen.Modules.Journal;

public interface IDecisionRepository
{
    /// <summary>Записывает решение и событие в одной транзакции (outbox); при повторном Idempotency-Key
    /// возвращает уже записанное (Created = false) и ничего не публикует.</summary>
    Task<(DecisionDto Decision, bool Created)> RecordAsync(NewDecision decision, Func<DecisionDto, object> outboxEvent, CancellationToken cancellationToken);

    /// <summary>subjectId — решения по одному предмету (например, реф пациента для маршрута); null — без фильтра.</summary>
    Task<Paged<DecisionDto>> ListAsync(string? actor, string? subject, string? subjectId, int page, int size, CancellationToken cancellationToken);

    /// <summary>Решения, касающиеся организации (scope own у decisions.all): актор из этой организации (actor_mo_code) или
    /// организация в recommended/chosen (направления и маршруты её пациентов).</summary>
    Task<Paged<DecisionDto>> ListForOrganizationAsync(string moCode, string? actor, string? subject, string? subjectId, int page, int size, CancellationToken cancellationToken);
}
