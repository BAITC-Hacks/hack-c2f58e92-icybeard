namespace Darumen.Modules.Medicines;

public interface IMedicinesRepository
{
    Task<IReadOnlyList<RxWeek>> WeeksAsync(string mnnId, int weeks, CancellationToken cancellationToken);

    Task<IReadOnlyList<RxMonth>> MonthsAsync(string nosologyId, int months, CancellationToken cancellationToken);

    Task<IReadOnlyList<DrugProgram>> ProgramsAsync(string nosologyId, CancellationToken cancellationToken);

    Task<IReadOnlyList<NosologyDto>> NosologiesAsync(int limit, CancellationToken cancellationToken);

    Task<IReadOnlyList<MnnDto>> MnnAsync(string nosologyId, int limit, CancellationToken cancellationToken);

    /// <summary>Топ МНН по объёму выписанных рецептов за год без фильтра по нозологии — по всем нозологиям сразу
    /// (5.7 C: список для прогноза спроса по топ-50 МНН).</summary>
    Task<IReadOnlyList<MnnDto>> TopMnnAsync(int limit, CancellationToken cancellationToken);

    /// <summary>p50 срока обеспечения, предсказанный моделью, из gold.rx_fill_by_mnn (5.7 A). Null, если МНН нет
    /// в витрине или витрина ещё не опубликована — вызывающий код показывает фактические сроки без модели.</summary>
    Task<double?> FillDaysP50ModelAsync(string mnnId, CancellationToken cancellationToken);

    /// <summary>Доля обеспеченных к выписанным рецептам за последние 12 месяцев по МНН той же категории, кроме
    /// самого МНН (5.7 B: дефицит против похожих МНН, а не только против собственной истории). Null, если для
    /// категории нет других МНН с данными.</summary>
    Task<PeerFulfillmentDto?> PeerFulfillmentAsync(string mnnId, string categoryId, CancellationToken cancellationToken);
}
