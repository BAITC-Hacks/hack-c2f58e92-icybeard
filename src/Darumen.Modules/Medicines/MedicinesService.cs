using Darumen.Shared.Api;

namespace Darumen.Modules.Medicines;

/// <summary>Проверка рецепта: покрытие по активным спецификациям нозологии, сроки обеспечения из фактических
/// рецептов (плюс, если опубликована, p50 модели LightGBM-квантиль — 5.7 A) и сигнал дефицита по падению доли
/// обеспеченных рецептов за последние недели против собственной истории МНН и против МНН-ровесников (5.7 B).</summary>
public sealed class MedicinesService(IMedicinesRepository repository)
{
    public const string ModelName = "rx_fill";
    public const string ModelVersion = "1.0.0";
    public const int RecentWeeks = 4;
    public const int BaselineWeeks = 12;
    public const int MinIssuedForSignal = 20;
    public const double ShortageThreshold = 0.3;
    /// <summary>Насколько хуже ровесников по категории нужно обеспечивать рецепты, чтобы это само по себе
    /// стоило подсветить дефицит — даже когда собственной истории МНН мало для сигнала.</summary>
    public const double PeerShortageThreshold = 0.2;

    public async Task<CheckResponseDto> CheckAsync(CheckRequestDto request, CancellationToken cancellationToken)
    {
        var programs = string.IsNullOrWhiteSpace(request.NosologyId) ? [] : await repository.ProgramsAsync(request.NosologyId, cancellationToken);
        var weeks = string.IsNullOrWhiteSpace(request.MnnId) ? [] : await repository.WeeksAsync(request.MnnId, RecentWeeks + BaselineWeeks, cancellationToken);
        var months = string.IsNullOrWhiteSpace(request.NosologyId) ? [] : await repository.MonthsAsync(request.NosologyId, 3, cancellationToken);
        var alternatives = string.IsNullOrWhiteSpace(request.NosologyId)
            ? []
            : (await repository.MnnAsync(request.NosologyId, 6, cancellationToken))
                .Where(m => m.MnnId != request.MnnId).Take(5)
                .Select(m => new AlternativeMnnDto(m.MnnId, $"МНН {m.MnnId}", m.Issued12m)).ToList();

        var active = programs.Where(p => p.ActiveSpecs > 0).ToList();
        var program = active.OrderByDescending(p => p.ActiveSpecs).FirstOrDefault();
        var category = program?.CategoryId ?? months.LastOrDefault()?.CategoryId;
        var (p50, p90, pFilled, basis) = FillTimes(weeks, months);
        var fillDaysP50Model = string.IsNullOrWhiteSpace(request.MnnId)
            ? null
            : await repository.FillDaysP50ModelAsync(request.MnnId, cancellationToken);
        var peer = !string.IsNullOrWhiteSpace(request.MnnId) && !string.IsNullOrWhiteSpace(category)
            ? await repository.PeerFulfillmentAsync(request.MnnId, category, cancellationToken)
            : null;
        var shortage = Shortage(weeks, peer);
        var trainedThrough = weeks.Count > 0 ? weeks[^1].Week.ToString("yyyy-MM-dd") : months.Count > 0 ? months[^1].Month.ToString("yyyy-MM-dd") : string.Empty;
        return new CheckResponseDto(
            active.Count > 0,
            program is null ? null : $"Программа {program.ProgramId}",
            category,
            p50, p90, fillDaysP50Model, pFilled, shortage, [], alternatives, basis,
            new ModelInfoDto(ModelName, ModelVersion, trainedThrough));
    }

    /// <summary>Сроки по МНН за последние недели, иначе по нозологии за последние месяцы.</summary>
    public static (double? P50, double? P90, double? PFilled14d, string Basis) FillTimes(IReadOnlyList<RxWeek> weeks, IReadOnlyList<RxMonth> months)
    {
        var recent = weeks.TakeLast(RecentWeeks).Where(w => w.Fulfilled > 0).ToList();
        if (recent.Count > 0)
        {
            var fulfilled = recent.Sum(w => w.Fulfilled);
            return (Weighted(recent, w => w.FillDaysP50, w => w.Fulfilled), Weighted(recent, w => w.FillDaysP90, w => w.Fulfilled),
                (double)recent.Sum(w => w.Fulfilled14d) / fulfilled, $"по {fulfilled} обеспеченным рецептам МНН за {recent.Count} нед.");
        }

        var monthly = months.Where(m => m.Fulfilled > 0).ToList();
        if (monthly.Count > 0)
        {
            var fulfilled = monthly.Sum(m => m.Fulfilled);
            return (Weighted(monthly, m => m.FillDaysP50, m => m.Fulfilled), Weighted(monthly, m => m.FillDaysP90, m => m.Fulfilled),
                (double)monthly.Sum(m => m.Fulfilled14d) / fulfilled, $"по {fulfilled} обеспеченным рецептам нозологии за {monthly.Count} мес.");
        }

        return (null, null, null, "фактических рецептов нет");
    }

    /// <summary>Доля обеспеченных к выписанным за последние недели против базовых недель того же МНН (own baseline)
    /// и, если передан, против МНН-ровесников той же категории за последние 12 месяцев (5.7 B). Оба сравнения
    /// возвращаются отдельно (Score/Basis — own, PeerRatio/PeerBasis — peer); итоговый Flag срабатывает по худшему
    /// из двух, чтобы дефицит, заметный только на фоне похожих МНН, не терялся при спокойной собственной истории.</summary>
    public static ShortageDto Shortage(IReadOnlyList<RxWeek> weeks, PeerFulfillmentDto? peer = null)
    {
        var recent = weeks.TakeLast(RecentWeeks).ToList();
        var baseline = weeks.SkipLast(RecentWeeks).ToList();
        var issuedRecent = recent.Sum(w => w.Issued);
        var ratioRecent = issuedRecent > 0 ? (double)recent.Sum(w => w.Fulfilled) / issuedRecent : (double?)null;

        var peerRatio = peer?.Ratio;
        var peerBasis = peer is null
            ? null
            : $"обеспечено {peer.Ratio:P0} выписанных за последние 12 мес. у {peer.PeerMnnCount} МНН той же категории (без этого МНН)";
        var peerFlag = ratioRecent is not null && peerRatio is > 0 && ratioRecent.Value / peerRatio.Value < 1 - PeerShortageThreshold;
        var peerScore = peerFlag ? Math.Clamp(1 - ratioRecent!.Value / peerRatio!.Value, 0, 1) : 0;

        if (issuedRecent < MinIssuedForSignal || baseline.Sum(b => b.Issued) < MinIssuedForSignal)
        {
            // собственной истории мало для сигнала — но сравнение с ровесниками всё ещё может его дать
            return new ShortageDto(peerFlag, Math.Round(peerScore, 2), "мало рецептов для сигнала по своей истории", peerRatio, peerBasis);
        }

        var ratioBase = (double)baseline.Sum(w => w.Fulfilled) / baseline.Sum(w => w.Issued);
        if (ratioBase <= 0)
        {
            return new ShortageDto(peerFlag, Math.Round(peerScore, 2), "базовых обеспечений нет", peerRatio, peerBasis);
        }

        var ownScore = Math.Clamp(1 - ratioRecent!.Value / ratioBase, 0, 1);
        var score = Math.Max(ownScore, peerScore);
        var basis = $"обеспечено {ratioRecent:P0} выписанных за {RecentWeeks} нед. против {ratioBase:P0} за предыдущие {baseline.Count}";
        return new ShortageDto(score >= ShortageThreshold, Math.Round(score, 2), basis, peerRatio, peerBasis);
    }

    private static double? Weighted<T>(IReadOnlyList<T> rows, Func<T, double?> value, Func<T, long> weight)
    {
        var pairs = rows.Where(r => value(r) is not null).Select(r => (v: value(r)!.Value, w: (double)weight(r))).ToList();
        var total = pairs.Sum(p => p.w);
        return total > 0 ? Math.Round(pairs.Sum(p => p.v * p.w) / total, 1) : null;
    }
}
