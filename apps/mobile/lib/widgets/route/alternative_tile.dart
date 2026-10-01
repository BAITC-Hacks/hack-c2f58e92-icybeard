import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../l10n/strings.dart';
import '../../theme/tokens.dart';
import '../../theme/tones.dart';
import '../../theme/typography.dart';
import '../format.dart';
import '../org_name.dart';
import '../status_chip.dart';

/// Разница в днях между своей больницей и альтернативой по тем же округлённым дням, что видны на экране
/// (RouteAlternatives.vue): `round(baseline) − round(p50)`, «≈ 4 и ≈ 2 → на 2 дн.». Больше нуля — альтернатива
/// быстрее. null — своей медианы нет (или она не число), сравнивать не с чем.
int? alternativeDayDifference({required double? baselineDays, required double p50Days}) {
  if (baselineDays == null || !baselineDays.isFinite || !p50Days.isFinite) {
    return null;
  }
  return baselineDays.round() - p50Days.round();
}

/// Фраза сравнения под числом плитки — всегда одна из трёх, нейтрально: «на N дн. меньше, чем в вашей больнице» /
/// «на N дн. больше, …» / «как в вашей больнице». null — разницы нет ([alternativeDayDifference] вернул null).
String? alternativeCompareText(S s, int? difference) {
  if (difference == null) {
    return null;
  }
  if (difference > 0) {
    return s.routeCompareFaster(difference);
  }
  return difference < 0 ? s.routeCompareSlower(-difference) : s.routeCompareSame;
}

/// Плитка «Где быстрее» гражданина (RouteAlternatives.vue, §2.11): рамка border-soft radius 14. Сверху на всю ширину —
/// короткое имя больницы (тап — полное юридическое имя), под ним код и «сосед: {регион}» для соседнего региона.
/// Ниже одной строкой «половина пациентов ждёт не больше … ≈ N дн.» — число справа, зелёным только когда больница
/// быстрее своей по округлённым дням, — и под ней серая фраза сравнения. Последней строкой — [action] экрана
/// («Попросить рассмотреть», только при `can('request_transfer')`) или, при [requested], чип «запрос отправлен»
/// вместо действия. На телефоне блоки идут один под другим, а не двумя колонками веба: при крупном шрифте узкая
/// колонка рвала бы слова. Риск отказа гражданину не показывается. Список (`offeredAlternatives`), пустое состояние
/// и блокировка кнопок на время запроса — у экрана.
class AlternativeTile extends StatelessWidget {
  const AlternativeTile({super.key, required this.alternative, this.baselineDays, this.neighbourRegion, this.action, this.requested = false});

  final Alternative alternative;

  /// Медиана своей больницы (`route.forecast.p50Days`); null — без сравнения и без зелёного.
  final double? baselineDays;

  /// Название региона альтернативы — показывается только при `isNeighborRegion`; без него — только код.
  final String? neighbourRegion;

  /// Действие экрана под плиткой; скрыто, если [requested].
  final Widget? action;

  /// По этой больнице уже открыта просьба гражданина (`route.openRequest?.toMoCode == moCode`).
  final bool requested;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final a = alternative;
    final region = neighbourRegion;
    final sub = [a.moCode, if (a.isNeighborRegion && region != null && region.isNotEmpty) s.routeNeighbourRegion(region)].join(' · ');
    final difference = alternativeDayDifference(baselineDays: baselineDays, p50Days: a.p50Days);
    final compare = alternativeCompareText(s, difference);
    final small = theme.textTheme.rowDetail.copyWith(color: colors.muted);
    final footer = requested ? StatusChip(s.routeRequestSent, tone: StatusTone.accent) : action;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 14),
      decoration: BoxDecoration(border: Border.all(color: colors.borderSoft), borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OrgName(a.name, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700), maxLines: 2),
          const SizedBox(height: 2),
          Text(sub, style: small),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: Text(s.routeTileLead, style: small)),
              const SizedBox(width: AppSpacing.md),
              _TileDays(p50Days: a.p50Days, faster: (difference ?? 0) > 0),
            ],
          ),
          if (compare != null) ...[const SizedBox(height: 2), Text(compare, style: small)],
          if (footer != null) Padding(padding: const EdgeInsets.only(top: AppSpacing.sm), child: Align(alignment: AlignmentDirectional.centerStart, child: footer)),
        ],
      ),
    );
  }
}

/// «≈ N дн.» плитки: число крупно 800 табличными цифрами, единица рядом по базовой линии; [faster] — ok и
/// success-soft-text, иначе чернила и text-secondary.
class _TileDays extends StatelessWidget {
  const _TileDays({required this.p50Days, required this.faster});

  final double p50Days;
  final bool faster;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text('≈ ${days(p50Days)}', style: theme.textTheme.headlineSmall?.copyWith(color: faster ? AppTones.of(context).ok.fg : colors.ink).merge(AppType.numeric)),
        const SizedBox(width: AppSpacing.xs),
        Text(S.at(context).daysUnit, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: faster ? colors.okSoftText : colors.muted)),
      ],
    );
  }
}
