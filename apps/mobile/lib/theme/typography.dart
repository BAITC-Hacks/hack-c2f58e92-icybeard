import 'package:flutter/material.dart';

import 'tokens.dart';

/// Шкала Onest. Базовый кегль 16 — среди пользователей много пожилых (docs/mobile-and-doctor.md); заголовки 600.
/// Цифры KPI, дней и дат — табличные (у Onest есть `tnum`), чтобы столбцы не прыгали при обновлении.
abstract final class AppType {
  static const family = 'Onest';

  /// Добавляется к стилю чисел: `style.merge(AppType.numeric)`.
  static const numeric = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

  static TextTheme textTheme(AppColors c) {
    TextStyle style(double size, FontWeight weight, {double height = 1.3, Color? color}) =>
        TextStyle(fontFamily: family, fontSize: size, fontWeight: weight, height: height, color: color ?? c.ink);

    return TextTheme(
      displaySmall: style(32, FontWeight.w600, height: 1.15),
      headlineSmall: style(24, FontWeight.w600, height: 1.2),
      titleLarge: style(20, FontWeight.w600, height: 1.25),
      titleMedium: style(18, FontWeight.w600),
      titleSmall: style(16, FontWeight.w600),
      bodyLarge: style(16, FontWeight.w400, height: 1.45),
      bodyMedium: style(16, FontWeight.w400, height: 1.45),
      bodySmall: style(14, FontWeight.w400, height: 1.4, color: c.muted),
      labelLarge: style(16, FontWeight.w600, height: 1.2),
      labelMedium: style(13, FontWeight.w500, height: 1.2),
      labelSmall: style(12, FontWeight.w500, height: 1.2, color: c.muted),
    );
  }
}
