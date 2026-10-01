using Darumen.Modules.Journal;

namespace Darumen.Tests.Fakes;

/// <summary>Сервис скрайба без Python: сессии и утверждения в памяти.</summary>
public sealed class FakeScribe : IScribeService
{
    private readonly HashSet<string> _sessions = [];
    private readonly HashSet<string> _approved = [];

    public List<(string Language, string Actor, string PatientRef)> Created { get; } = [];

    public Task<string> CreateSessionAsync(string language, string actor, string patientRef, CancellationToken ct)
    {
        var id = Guid.NewGuid().ToString("N")[..16];
        _sessions.Add(id);
        Created.Add((language, actor, patientRef));
        return Task.FromResult(id);
    }

    public List<string> Discarded { get; } = [];

    public Task DiscardAsync(string sessionId, CancellationToken ct)
    {
        Discarded.Add(sessionId);
        _sessions.Remove(sessionId);
        return Task.CompletedTask;
    }

    public Task<string?> ApproveAsync(string sessionId, ScribeApproveRequestDto body, CancellationToken ct)
    {
        if (!_sessions.Contains(sessionId))
        {
            return Task.FromResult<string?>(null);
        }

        if (!_approved.Add(sessionId))
        {
            throw new ScribeServiceException(409, "session already approved, audio was deleted");
        }

        return Task.FromResult<string?>("leaflet-" + sessionId);
    }
}
