import 'package:flutter/material.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../theme/typography.dart';
import 'format.dart';

/// Горизонтальный степпер этапов Стандарта: пять точек с коннекторами, короткие подписи и даты под
/// пройденными. `compact` — только точки (мини-степпер в карточке на главной).
class StageStepper extends StatelessWidget {
  const StageStepper({super.key, required this.stages, this.compact = false});

  final List<RouteStage> stages;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final ordered = [...stages]..sort((a, b) => a.order.compareTo(b.order));
    if (ordered.isEmpty) {
      return const SizedBox.shrink();
    }
    final current = ordered.indexWhere((x) => x.status == RouteCodes.current);
    return Semantics(
      label: current < 0 ? null : s.stepperSemantics(current + 1, ordered.length, ordered[current].title),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < ordered.length; i++)
            Expanded(
              child: _Step(
                stage: ordered[i],
                label: s.stageShort(ordered[i].code),
                leftDone: i > 0 && ordered[i - 1].status == RouteCodes.done,
                rightDone: ordered[i].status == RouteCodes.done,
                first: i == 0,
                last: i == ordered.length - 1,
                compact: compact,
              ),
            ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.stage,
    required this.label,
    required this.leftDone,
    required this.rightDone,
    required this.first,
    required this.last,
    required this.compact,
  });

  final RouteStage stage;
  final String label;
  final bool leftDone;
  final bool rightDone;
  final bool first;
  final bool last;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final done = stage.status == RouteCodes.done;
    final current = stage.status == RouteCodes.current;
    final size = current ? 16.0 : 10.0;
    final passed = done || current;
    return Column(
      children: [
        SizedBox(
          height: 16,
          child: Row(
            children: [
              Expanded(child: Container(height: 2, color: first ? null : (leftDone ? colors.accent : colors.hairline))),
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? colors.accent : colors.card,
                  border: Border.all(color: passed ? colors.accent : colors.hairline, width: current ? 3 : 2),
                ),
              ),
              Expanded(child: Container(height: 2, color: last ? null : (rightDone ? colors.accent : colors.hairline))),
            ],
          ),
        ),
        if (!compact) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: passed ? colors.ink : colors.muted, fontWeight: current ? FontWeight.w600 : FontWeight.w500),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (passed && stage.date != null)
            Text(dayMonth(stage.date), style: theme.textTheme.labelSmall?.merge(AppType.numeric), textAlign: TextAlign.center),
        ],
      ],
    );
  }
}
