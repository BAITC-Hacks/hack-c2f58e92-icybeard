import 'package:flutter/material.dart';

import 'tokens.dart';

/// Шкала Manrope (docs/design-system.md, «Типографика»): базовый кегль 17, заголовок экрана 29/500 с плотным
/// трекингом, hero-число 50/600. Цифры KPI, дней и дат — табличные (`tnum`), чтобы столбцы не прыгали.
abstract final class AppType {
  static const family = 'Manrope';

  /// Добавляется к стилю чисел: `style.merge(AppType.numeric)`.
  static const numeric = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

  static TextStyle _style(AppColors c, double size, FontWeight weight, {double height = 1.3, double? tracking, Color? color}) =>
      TextStyle(fontFamily: family, fontSize: size, fontWeight: weight, height: height, letterSpacing: tracking, color: color ?? c.ink);

  static TextTheme textTheme(AppColors c) => TextTheme(
        // hero-число 50/600 −0.02em
        displayLarge: _style(c, 50, FontWeight.w600, height: 1.0, tracking: -1.0),
        // hero в карточке врача и таймер скрайба 42/600
        displayMedium: _style(c, 42, FontWeight.w600, height: 1.05, tracking: -0.84),
        // слово-знак на входе 35/600
        displaySmall: _style(c, 35, FontWeight.w600, height: 1.05, tracking: -0.7),
        // H1 экрана 29/500 −0.02em
        headlineMedium: _style(c, 29, FontWeight.w500, height: 1.05, tracking: -0.58),
        // реф пациента крупно 24/500 −0.01em
        headlineSmall: _style(c, 24, FontWeight.w500, height: 1.2, tracking: -0.24),
        // организация, МНН 20/500 −0.01em
        titleLarge: _style(c, 20, FontWeight.w500, height: 1.2, tracking: -0.2),
        // заголовок карточки/секции 17/500
        titleMedium: _style(c, 17, FontWeight.w500, height: 1.3),
        // акцентная строка списка, ссылка-действие 15/500
        titleSmall: _style(c, 15, FontWeight.w500, height: 1.35),
        bodyLarge: _style(c, 17, FontWeight.w400, height: 1.45),
        bodyMedium: _style(c, 17, FontWeight.w400, height: 1.45),
        // подпись 14/400 ink-2
        bodySmall: _style(c, 14, FontWeight.w400, height: 1.4, color: c.muted),
        // кнопка 17/500
        labelLarge: _style(c, 17, FontWeight.w500, height: 1.2),
        // чип и навигация 12/500 +0.02em
        labelMedium: _style(c, 12, FontWeight.w500, height: 1.2, tracking: 0.24),
        // caption/сноска 12/400 +0.02em ink-2
        labelSmall: _style(c, 12, FontWeight.w400, height: 1.35, tracking: 0.24, color: c.muted),
      );
}

/// Стили, которых нет в Material-шкале: строка списка 15, label над блоком (uppercase 12/500 +0.06em),
/// подпись на белом (ink-3) и ссылка-действие.
extension AppTextStyles on TextTheme {
  /// Строка списка 15/400.
  TextStyle get row => bodyMedium!.copyWith(fontSize: 15, height: 1.35);

  /// Акцентная строка списка 15/500.
  TextStyle get rowStrong => titleSmall!;

  /// Подстрока в списке 13/400 ink-3 — цвет задаёт вызывающий (`copyWith(color: faint)`).
  TextStyle get rowDetail => bodyMedium!.copyWith(fontSize: 13, height: 1.4);

  /// Label над блоком: текст передаётся в верхнем регистре.
  TextStyle get overline => labelMedium!.copyWith(letterSpacing: 0.72);

  /// Caption на белом 12/400 +0.02em (цвет ink-3 задаёт вызывающий).
  TextStyle get caption => labelSmall!;
}
