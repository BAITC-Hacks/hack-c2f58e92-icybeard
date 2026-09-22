import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import 'format.dart';

/// Вертикальный таймлайн стадий Стандарта: пройденные — залитый узел и дата, текущая — акцентный узел, предстоящие —
/// пустой узел и нормативный срок. Чистый виджет без обращений к API — тестируется отдельно.
class RouteTimeline extends StatelessWidget {
  const RouteTimeline({super.key, required this.stages});

  final List<RouteStage> stages;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    return Column(
      children: [
        for (var i = 0; i < stages.length; i++) _Row(stage: stages[i], last: i == stages.length - 1, theme: theme, colors: colors),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.stage, required this.last, required this.theme, required this.colors});

  final RouteStage stage;
  final bool last;
  final ThemeData theme;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final current = stage.status == RouteCodes.current;
    final done = stage.status == RouteCodes.done;
    final upcoming = !current && !done;
    final nodeColor = current || done ? colors.accent : colors.hairline;
    final titleStyle = theme.textTheme.bodyMedium?.copyWith(
      color: upcoming ? colors.muted : colors.ink,
      fontWeight: current ? FontWeight.w600 : FontWeight.w400,
    );
    final detail = upcoming ? stage.norm : stage.date == null ? null : dateShort(stage.date);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: current ? 14 : 10,
                  height: current ? 14 : 10,
                  margin: EdgeInsets.only(top: current ? 4 : 6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done || current ? nodeColor : colors.card,
                    border: Border.all(color: nodeColor, width: 2),
                  ),
                ),
                if (!last) Expanded(child: Container(width: 2, color: done ? colors.accent : colors.hairline)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(stage.title, style: titleStyle),
                  if (detail != null && detail.isNotEmpty) Text(detail, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
