import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/tokens.dart';
import '../../theme/tones.dart';

/// Этапы по `order` в новом списке (вход не меняется) — так их рисуют полоска и вертикальный список.
List<RouteStage> orderedStages(List<RouteStage> stages) => [...stages]..sort((a, b) => a.order.compareTo(b.order));

/// Индекс узла, до которого доходит линия прогресса (RouteTimeline.vue): текущий этап; если текущего нет и все
/// пройдены — последний; иначе 0 (ничего не закрашено). Отрезок между узлами i и i+1 закрашен, если i+1 ≤ индекса.
/// [stages] упорядочиваются здесь же.
int stageProgressIndex(List<RouteStage> stages) {
  final ordered = orderedStages(stages);
  final current = ordered.indexWhere((s) => s.status == RouteCodes.current);
  if (current >= 0) {
    return current;
  }
  final allDone = ordered.isNotEmpty && ordered.every((s) => s.status == RouteCodes.done);
  return allDone ? ordered.length - 1 : 0;
}

/// Узел этапа маршрута (RouteTimeline.vue, вариант citizen): пройден — заливка accent с белой галочкой; текущий —
/// accent-soft с рамкой 2.5 accent и точкой accent; будущий (и незнакомый статус) — фон карточки с рамкой 2
/// toggle-off. [status] — `RouteStage.status`. Размер по умолчанию 24 (строки списка), в полоске — 20. Декоративный:
/// озвучивание — у строки или полоски.
class StageNode extends StatelessWidget {
  const StageNode({super.key, required this.status, this.size = AppSizes.stageNode});

  final String status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final (fill, border, child) = switch (status) {
      RouteCodes.done => (colors.accent, null, Icon(Icons.check, size: size * 0.6, color: colors.onAccent)),
      RouteCodes.current => (
          colors.accentSoft,
          Border.all(color: colors.accent, width: 2.5),
          Container(width: size * 0.3, height: size * 0.3, decoration: BoxDecoration(shape: BoxShape.circle, color: colors.accent)),
        ),
      _ => (colors.card, Border.all(color: colors.toggleOff, width: 2), null),
    };
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: fill, border: border),
        child: child,
      ),
    );
  }
}

/// Отрезок линии этапов толщиной 2: [reached] — пройденная часть (accent), иначе border-soft. По [axis] линия
/// тянется по ширине (полоска) или по высоте (вертикальный список) — родитель задаёт длину (Expanded).
class StageConnector extends StatelessWidget {
  const StageConnector({super.key, required this.reached, this.axis = Axis.horizontal});

  final bool reached;
  final Axis axis;

  static const double thickness = 2;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final line = ColoredBox(color: reached ? colors.accent : colors.borderSoft);
    return axis == Axis.horizontal
        ? SizedBox(height: thickness, width: double.infinity, child: line)
        : SizedBox(width: thickness, height: double.infinity, child: line);
  }
}
