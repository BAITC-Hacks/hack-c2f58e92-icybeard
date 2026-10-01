import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../theme/tokens.dart';
import '../../theme/tones.dart';
import '../../theme/typography.dart';

/// Верх фиксированной шкалы приоритета API (Worklist.cs: просрочка до 5, риск отказа до 3, есть быстрее +1,
/// открытый сигнал пациента +1).
const priorityMax = 10;

/// Приоритет API → целое 0…10: зажим в шкалу и округление (половина — вверх, как Math.round веба); нечисло — 0.
int priorityScore(num value) => value.isNaN ? 0 : value.clamp(0, priorityMax).round();

/// Полоса по постоянным порогам веба: 7–10 высокий, 4–6 средний, 0–3 низкий — «8» значит одно и то же в любом
/// регионе и профиле.
PriorityBand priorityBandOf(int score) => score >= 7
    ? PriorityBand.high
    : score >= 4
        ? PriorityBand.mid
        : PriorityBand.low;

/// Приоритет пациента в рабочем списке — число 0…10 в цветной пилюле (PriorityBadge.vue): высокий — danger,
/// средний — warn, низкий — ok (те же пары, что в вебе). Не меньше 32×32, при крупном шрифте растёт, а не обрезается;
/// на ширину строки не растягивается. Подсказка и доступная подпись — «Высокий приоритет · 8 из 10». Только
/// представление: бейдж не кнопка (тап — у строки списка). Для факта «Приоритет — 8 из 10» на странице пациента
/// экран берёт `S.priorityOutOfTen(priorityScore(value))`.
class PriorityBadge extends StatelessWidget {
  const PriorityBadge(this.value, {super.key});

  /// `priority` из API (WorklistItem, doctor-панель маршрута); значения вне 0…10 зажимаются.
  final num value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tones = AppTones.of(context);
    final score = priorityScore(value);
    final band = priorityBandOf(score);
    final tone = switch (band) {
      PriorityBand.high => tones.danger,
      PriorityBand.mid => tones.warn,
      PriorityBand.low => tones.ok,
    };
    final hint = S.at(context).priorityHint(band, score);
    return Tooltip(
      message: hint,
      excludeFromSemantics: true,
      child: Semantics(
        label: hint,
        excludeSemantics: true,
        child: DecoratedBox(
          decoration: ShapeDecoration(color: tone.bg, shape: const StadiumBorder()),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: AppSizes.priority, minHeight: AppSizes.priority),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: Text(
                  '$score',
                  style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700, height: 1.1, color: tone.fg).merge(AppType.numeric),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
