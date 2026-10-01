import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../l10n/strings.dart';
import '../../theme/tokens.dart';
import '../../theme/tones.dart';
import '../../theme/typography.dart';
import '../format.dart';
import 'stage_node.dart';

/// Этапы маршрута вертикальными строками — телефонная раскладка степпера RouteTimeline.vue: слева узел 24 и линия
/// 2 до следующего узла (пройденная часть — accent, до центра текущего), справа заголовок этапа с сервера
/// (`RouteStage.title`, на языке запроса — включая «Перевод») и под ним дата `дд.мм.гггг`, а без даты — норма
/// Стандарта; без того и другого подстроки нет. Заголовок: пройден — чернила, текущий — accent-strong 800, будущий —
/// text-secondary. Строка озвучивается «Этап k из n: заголовок» и подстрокой. Пустой список — ничего.
class StageList extends StatelessWidget {
  const StageList({super.key, required this.stages});

  /// `PatientRoute.timeline` в любом порядке — рисуется по `order`.
  final List<RouteStage> stages;

  @override
  Widget build(BuildContext context) {
    final ordered = orderedStages(stages);
    if (ordered.isEmpty) {
      return const SizedBox.shrink();
    }
    final progress = stageProgressIndex(ordered);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, stage) in ordered.indexed)
          _StageRow(stage: stage, step: i + 1, total: ordered.length, reachedBelow: i + 1 <= progress, last: i == ordered.length - 1),
      ],
    );
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow({required this.stage, required this.step, required this.total, required this.reachedBelow, required this.last});

  final RouteStage stage;
  final int step;
  final int total;
  final bool reachedBelow;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final date = stage.date;
    final sub = date != null && date.isNotEmpty ? dateShort(date) : (stage.norm ?? '');
    final titleStyle = switch (stage.status) {
      RouteCodes.done => theme.textTheme.row.copyWith(color: colors.ink),
      RouteCodes.current => theme.textTheme.rowStrong.copyWith(color: colors.accentHover),
      _ => theme.textTheme.row.copyWith(color: colors.muted),
    };
    return Semantics(
      container: true,
      label: S.at(context).stepperSemantics(step, total, stage.title),
      value: sub.isEmpty ? null : sub,
      excludeSemantics: true,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: AppSizes.stageNode,
              child: Column(
                children: [
                  StageNode(status: stage.status),
                  if (!last) Expanded(child: StageConnector(reached: reachedBelow, axis: Axis.vertical)),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: 2, bottom: last ? 0 : AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(stage.title, style: titleStyle),
                    if (sub.isNotEmpty) Text(sub, style: theme.textTheme.caption.copyWith(color: colors.muted).merge(AppType.numeric)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
