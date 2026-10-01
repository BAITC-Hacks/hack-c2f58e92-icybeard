import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../theme/typography.dart';

/// Счётчик непрочитанного (дизайн-система §2.9): пилюля высотой не меньше 16, ширина от 16 и растёт под число,
/// поля по 4 по бокам, фон `dangerStrong` (белый текст 4,56:1; в тёмной теме свой токен), текст 11/700 `onAccent`.
/// 0 и меньше — пилюли нет; больше 99 — «99+». С [child] пилюля висит над его правым верхним углом
/// (`top: -4, right: -8`) и не меняет его размер — так она стоит на иконке вкладки и на кнопке-колокольчике.
/// Число из дерева семантики исключено: что оно значит («Уведомления, новых: 3»), озвучивает вкладка или кнопка.
class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.count, this.child});

  /// Ключ самой пилюли — для тестов и поиска на экране.
  static const pillKey = ValueKey('count-badge-pill');

  /// Порог, после которого показывается «99+».
  static const max = 99;

  final int count;

  /// Иконка или кнопка, на которой висит счётчик; null — только пилюля.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final pill = count > 0 ? _Pill(text: count > max ? '$max+' : '$count') : null;
    if (child == null) {
      return pill ?? const SizedBox.shrink();
    }
    if (pill == null) {
      return child!;
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [child!, Positioned(top: -4, right: -8, child: pill)],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});

  /// Крупный системный шрифт увеличивает и счётчик, но не больше 1,3× — иначе пилюля закроет иконку.
  static const _maxScale = 1.3;

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return ExcludeSemantics(
      child: Container(
        key: CountBadge.pillKey,
        constraints: const BoxConstraints(minWidth: AppSizes.badge, minHeight: AppSizes.badge),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        decoration: BoxDecoration(color: colors.dangerStrong, borderRadius: BorderRadius.circular(AppRadius.pill)),
        // множители 1 — пилюля облегает число (а не растягивается на всё доступное место), минимум 16×16 — от рамки
        child: Align(
          widthFactor: 1,
          heightFactor: 1,
          child: Text(
            text,
            maxLines: 1,
            textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: _maxScale),
            style: TextStyle(fontSize: AppType.navLabelSize, fontWeight: FontWeight.w700, height: 1.2, color: colors.onAccent),
          ),
        ),
      ),
    );
  }
}
