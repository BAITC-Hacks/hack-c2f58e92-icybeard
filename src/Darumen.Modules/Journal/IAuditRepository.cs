using Darumen.Shared.Api;

namespace Darumen.Modules.Journal;

public interface IAuditRepository
{
    Task<Paged<AuditEntryDto>> ListAsync(string? actor, int page, int size, CancellationToken cancellationToken);
}
