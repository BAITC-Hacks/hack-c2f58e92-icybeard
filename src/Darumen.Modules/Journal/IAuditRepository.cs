using Darumen.Shared.Api;

namespace Darumen.Modules.Journal;

public interface IAuditRepository
{
    /// <summary>moCode — только записи актёров этой организации (scope own у admin.users).</summary>
    Task<Paged<AuditEntryDto>> ListAsync(string? actor, string? moCode, int page, int size, CancellationToken cancellationToken);
}
