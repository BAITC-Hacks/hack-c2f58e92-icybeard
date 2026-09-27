import 'package:flutter/material.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../theme/typography.dart';
import 'format.dart';
import 'stage_stepper.dart';

/// Этапы Стандарта строками 56 px внутри карточки: слева галочка (пройдено), фиолетовый маркер (текущий) или пустой
/// круг (впереди); подпись 15 (500 у текущего); справа дата dd.MM, у предстоящих — нормативный срок или «—».
class RouteTimeline extends StatelessWidget {
  const RouteTimeline({super.key, required this.stages});

  final List<RouteStage> stages;

  @override
  Widget build(BuildContext context) {
    final ordered = [...stages]..sort((a, b) => a.order.compareTo(b.order));
    return Column(
      children: [
        for (final (i, stage) in ordered.indexed) _StageRow(stage: stage, last: i == ordered.length - 1),
      ],
    );
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow({required this.stage, required this.last});

  final RouteStage stage;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final current = stage.status == RouteCodes.current;
    final done = stage.status == RouteCodes.done;
    final upcoming = !current && !done;
    final detail = upcoming ? (stage.norm ?? '—') : dayMonth(stage.date);
    return Container(
      constraints: const BoxConstraints(minHeight: AppSizes.row),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: last ? null : BoxDecoration(border: Border(bottom: BorderSide(color: colors.hairline))),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: Center(
              child: done ? Icon(Icons.check, size: 18, color: colors.ink) : StageMarker(active: current),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              s.stageShort(stage.code) == stage.code ? stage.title : s.stageShort(stage.code),
              style: (current ? theme.textTheme.rowStrong : theme.textTheme.row).copyWith(color: upcoming ? colors.muted : colors.ink),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Flexible(
            child: Text(
              detail,
              style: theme.textTheme.bodySmall?.copyWith(color: current ? colors.ink : colors.muted, fontWeight: current ? FontWeight.w500 : FontWeight.w400).merge(AppType.numeric),
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
