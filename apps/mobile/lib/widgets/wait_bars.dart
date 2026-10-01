import 'package:flutter/material.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../theme/typography.dart';
import 'citizen_more/wait_logic.dart';
import 'format.dart';
import 'org_name.dart';
import 'status_chip.dart';

/// Строки «Где быстрее в регионе» (веб `WaitView.vue`, бары wait-new): короткое имя больницы (переносится, тап —
/// полное юридическое), под ним код и «сосед: {регион}»; полоса 10 px одного цвета для всех строк, длина — срок
/// относительно самого долгого в списке; «половина пациентов ждёт не больше … ≈ N дн.» (зелёным, если быстрее
/// среднего по региону на округлённых днях) и фраза сравнения со средним. Действие под строкой — чип «Запрос
/// отправлен» или «Попросить рассмотреть»; какое показать, решает экран ([actionFor]). Риск отказа гражданину не
/// показывается.
class WaitBars extends StatelessWidget {
  const WaitBars({super.key, required this.alternatives, this.regionP50, this.regionName, this.actionFor});

  final List<Alternative> alternatives;

  /// Медиана региона (`predict.p50Days`) — база сравнения; null — без сравнения и без зелёного.
  final double? regionP50;

  /// Название региона по КАТО — для «сосед: {регион}»; без него — только код больницы.
  final String? Function(String regionKato)? regionName;

  /// Действие под строкой больницы (чип или кнопка); null — без действия.
  final Widget? Function(Alternative alternative)? actionFor;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final longest = alternatives.fold<double>(0, (m, a) => a.p50Days > m ? a.p50Days : m);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, a) in alternatives.indexed)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: i == alternatives.length - 1 ? null : BoxDecoration(border: Border(bottom: BorderSide(color: colors.hairline))),
            child: _WaitBarRow(
              alternative: a,
              share: waitBarShare(a.p50Days, longest),
              regionP50: regionP50,
              neighbour: a.isNeighborRegion && a.regionKato != null ? regionName?.call(a.regionKato!) : null,
              action: actionFor?.call(a),
            ),
          ),
      ],
    );
  }
}

class _WaitBarRow extends StatelessWidget {
  const _WaitBarRow({required this.alternative, required this.share, this.regionP50, this.neighbour, this.action});

  final Alternative alternative;
  final double share;
  final double? regionP50;
  final String? neighbour;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final a = alternative;
    final small = theme.textTheme.rowDetail.copyWith(color: colors.muted);
    final faster = waitIsFaster(regionP50: regionP50, p50: a.p50Days);
    final compare = waitCompareText(s, regionP50: regionP50, p50: a.p50Days);
    final sub = [a.moCode, if (neighbour != null && neighbour!.isNotEmpty) s.routeNeighbourRegion(neighbour!)].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OrgName(a.name, style: theme.textTheme.row.copyWith(fontWeight: FontWeight.w700), maxLines: 3),
        const SizedBox(height: 2),
        Text(sub, style: small),
        const SizedBox(height: AppSpacing.sm),
        ExcludeSemantics(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: Stack(
              children: [
                Container(height: 10, color: colors.neutralSoft),
                FractionallySizedBox(widthFactor: share, child: Container(height: 10, color: colors.accent.withValues(alpha: 0.75))),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: Text(s.routeTileLead, style: small)),
            const SizedBox(width: AppSpacing.md),
            Text.rich(
              TextSpan(children: [
                TextSpan(text: approxDays(a.p50Days), style: theme.textTheme.labelLarge?.copyWith(color: faster ? colors.ok : colors.ink)),
                TextSpan(text: ' ${s.daysUnit}', style: theme.textTheme.labelMedium?.copyWith(color: faster ? colors.okSoftText : colors.muted)),
              ]),
              style: AppType.numeric,
            ),
          ],
        ),
        if (compare != null) ...[const SizedBox(height: 2), Text(compare, style: small)],
        if (action != null) Padding(padding: const EdgeInsets.only(top: AppSpacing.sm), child: Align(alignment: AlignmentDirectional.centerStart, child: action)),
      ],
    );
  }
}

/// Чип «Запрос отправлен» у больницы с открытой просьбой (тон accent, как в вебе).
class WaitRequestedChip extends StatelessWidget {
  const WaitRequestedChip({super.key});

  @override
  Widget build(BuildContext context) => StatusChip(S.at(context).routeRequestSent, tone: StatusTone.accent);
}
