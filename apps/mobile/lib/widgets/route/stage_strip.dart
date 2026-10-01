import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../l10n/strings.dart';
import 'stage_node.dart';

/// Компактная полоска этапов для карточки маршрута на главной: только узлы (20) и линия между ними, без подписей —
/// шесть подписей в ширину телефона не помещаются (решение Q3/§2.4). Подпись «{total} этапов · {done} пройдено» или
/// заголовок текущего этапа ставит экран рядом. Включает этап «Перевод», когда он есть в таймлайне. Озвучивается
/// как «Этап k из n: заголовок текущего этапа»; без текущего — «n этапов · m пройдено». Пустой список — ничего.
class StageStrip extends StatelessWidget {
  const StageStrip({super.key, required this.stages, this.nodeSize = compactNode});

  /// `PatientRoute.timeline` в любом порядке — рисуется по `order`.
  final List<RouteStage> stages;
  final double nodeSize;

  /// Узел в компактной полоске меньше, чем в строках списка (24).
  static const double compactNode = 20;

  @override
  Widget build(BuildContext context) {
    final ordered = orderedStages(stages);
    if (ordered.isEmpty) {
      return const SizedBox.shrink();
    }
    final s = S.at(context);
    final progress = stageProgressIndex(ordered);
    final current = ordered.indexWhere((stage) => stage.status == RouteCodes.current);
    final done = ordered.where((stage) => stage.status == RouteCodes.done).length;
    final label = current >= 0 ? s.stepperSemantics(current + 1, ordered.length, ordered[current].title) : s.routeStagesCount(ordered.length, done);
    return Semantics(
      container: true,
      label: label,
      child: Row(
        children: [
          for (final (i, stage) in ordered.indexed) ...[
            StageNode(status: stage.status, size: nodeSize),
            if (i < ordered.length - 1) Expanded(child: StageConnector(reached: i + 1 <= progress)),
          ],
        ],
      ),
    );
  }
}
