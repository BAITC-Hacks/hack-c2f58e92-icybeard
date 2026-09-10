namespace Darumen.Modules.Medicines;

public interface IMedicinesRepository
{
    Task<IReadOnlyList<RxWeek>> WeeksAsync(string mnnId, int weeks, CancellationToken cancellationToken);

    Task<IReadOnlyList<RxMonth>> MonthsAsync(string nosologyId, int months, CancellationToken cancellationToken);

    Task<IReadOnlyList<DrugProgram>> ProgramsAsync(string nosologyId, CancellationToken cancellationToken);

    Task<IReadOnlyList<NosologyDto>> NosologiesAsync(int limit, CancellationToken cancellationToken);

    Task<IReadOnlyList<MnnDto>> MnnAsync(string nosologyId, int limit, CancellationToken cancellationToken);
}
