import 'package:flutter/material.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';

/// Прогресс этапов Стандарта по доскам M-Home/M-Route: полосы 3 px radius 2 (пройдено — accent, впереди — hairline)
/// и точка 14 px accent с белой обводкой 2 px на текущем; под ними три подписи 12 ink-2 — первый · текущий ·
/// последний. `compact` — только полосы.
class StageStepper extends StatelessWidget {
  const StageStepper({super.key, required this.stages, this.compact = false});

  final List<RouteStage> stages;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final ordered = [...stages]..sort((a, b) => a.order.compareTo(b.order));
    if (ordered.isEmpty) {
      return const SizedBox.shrink();
    }
    final current = ordered.indexWhere((x) => x.status == RouteCodes.current);
    final labels = [
      s.stageShort(ordered.first.code),
      if (current > 0 && current < ordered.length - 1) s.stageShort(ordered[current].code),
      s.stageShort(ordered.last.code),
    ];
    return Semantics(
      label: current < 0 ? null : s.stepperSemantics(current + 1, ordered.length, ordered[current].title),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final (i, stage) in ordered.indexed) ...[
                if (i > 0) const SizedBox(width: AppSpacing.xs),
                if (stage.status == RouteCodes.current) StageMarker(active: true) else Expanded(child: StageBar(done: stage.status == RouteCodes.done)),
              ],
            ],
          ),
          if (!compact) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final (i, label) in labels.indexed)
                  Flexible(
                    child: Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(color: colors.muted, letterSpacing: 0),
                      textAlign: i == 0 ? TextAlign.start : i == labels.length - 1 ? TextAlign.end : TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Полоса этапа 3 px: accent — пройдено, hairline — впереди.
class StageBar extends StatelessWidget {
  const StageBar({super.key, required this.done});

  final bool done;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return Container(
      height: AppSizes.bar,
      decoration: BoxDecoration(color: done ? colors.accent : colors.hairline, borderRadius: BorderRadius.circular(2)),
    );
  }
}

/// Маркер этапа 14 px: активный — accent с обводкой 2 px цвета карточки, неактивный — пустой круг с обводкой hairline.
class StageMarker extends StatelessWidget {
  const StageMarker({super.key, required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return Container(
      width: AppSizes.marker,
      height: AppSizes.marker,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? colors.accent : ColorTokens.transparent,
        border: Border.all(color: active ? colors.card : colors.hairline, width: 2),
      ),
    );
  }
}
