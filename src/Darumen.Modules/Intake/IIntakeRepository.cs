using Darumen.Shared.Api;

namespace Darumen.Modules.Intake;

public interface IIntakeRepository
{
    Task<Paged<BatchDto>> BatchesAsync(string? status, string? dataset, int page, int size, CancellationToken cancellationToken);
}
