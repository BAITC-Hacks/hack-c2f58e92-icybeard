import 'package:flutter/material.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'format.dart';
import 'org_name.dart';
import 'status_chip.dart';

/// Строка «Где быстрее»/«Альтернативы»: короткое имя организации 15, дни справа 17/500, чип риска по требованию
/// (только врачу), действие («Попросить» / «Направить») справа.
class AlternativeRow extends StatelessWidget {
  const AlternativeRow({super.key, required this.alternative, this.trailing, this.showRisk = false, this.showP90 = false});

  final Alternative alternative;
  final Widget? trailing;
  final bool showRisk;
  final bool showP90;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final a = alternative;
    final notes = [
      if (a.distanceKm > 0) '${a.distanceKm.round()} ${s.kmUnit}',
      if (a.isNeighborRegion) s.externalBenchmark,
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OrgName(a.name, style: theme.textTheme.row, maxLines: 2),
                if (showRisk || notes.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (showRisk) StatusChip(s.riskShort(pct(a.pRefusal)), tone: a.pRefusal > 0.2 ? StatusTone.danger : StatusTone.neutral),
                      if (notes.isNotEmpty) Text(notes.join(' · '), style: theme.textTheme.labelSmall),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${days(a.p50Days)} ${s.daysUnit}', style: theme.textTheme.titleMedium?.merge(AppType.numeric)),
              if (showP90) Text('p90 ${days(a.p90Days)}', style: theme.textTheme.labelSmall?.merge(AppType.numeric)),
            ],
          ),
          // действие ограничено по ширине: длинный чип («запрос отправлен») обрезается, а не переполняет строку
          if (trailing != null) ...[const SizedBox(width: AppSpacing.xs), ConstrainedBox(constraints: const BoxConstraints(maxWidth: 150), child: trailing)],
        ],
      ),
    );
  }
}
