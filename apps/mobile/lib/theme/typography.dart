import 'package:flutter/material.dart';

import 'tokens.dart';

/// Шкала Manrope «синей гаммы» (handoff/README, components.md): плотнее старой — тело 13.5, UI-текст 700,
/// заголовок экрана 24/800, hero-числа 40/800 (у Manrope нет 900 — веса «900» макетов рендерятся как 800).
/// Цифры KPI, дней и дат — табличные (`tnum`), чтобы столбцы не прыгали.
abstract final class AppType {
  static const family = 'Manrope';

  /// Добавляется к стилю чисел: `style.merge(AppType.numeric)`.
  static const numeric = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

  static TextStyle _style(ColorTokens c, double size, FontWeight weight, {double height = 1.3, double? tracking, Color? color}) =>
      TextStyle(fontFamily: family, fontSize: size, fontWeight: weight, height: height, letterSpacing: tracking, color: color ?? c.ink);

  static TextTheme textTheme(ColorTokens c) => TextTheme(
        // hero-число экрана 40/800 −0.02em (доски: «53», «≈80», таймер скрайба)
        displayLarge: _style(c, 40, FontWeight.w800, height: 1.0, tracking: -0.8),
        // hero в карточке (врач, направление) — те же 40/800
        displayMedium: _style(c, 40, FontWeight.w800, height: 1.05, tracking: -0.8),
        // крупный срок в тексте карточки 34/800 («≈54 дн.»)
        displaySmall: _style(c, 34, FontWeight.w800, height: 1.05, tracking: -0.68),
        // заголовок экрана в топбаре 24/800 −0.01em
        headlineMedium: _style(c, 24, FontWeight.w800, height: 1.15, tracking: -0.24),
        // реф пациента крупно и ячейка OTP 22/800
        headlineSmall: _style(c, 22, FontWeight.w800, height: 1.2, tracking: -0.22),
        // организация, МНН 19/800
        titleLarge: _style(c, 19, FontWeight.w800, height: 1.25, tracking: -0.19),
        // заголовок карточки/секции 15/800 («Вы ещё ждёте госпитализацию?»)
        titleMedium: _style(c, 15, FontWeight.w800, height: 1.35),
        // акцентная строка списка, ссылка-действие 13.5/700
        titleSmall: _style(c, 13.5, FontWeight.w700, height: 1.35),
        bodyLarge: _style(c, 15, FontWeight.w400, height: 1.5),
        bodyMedium: _style(c, 13.5, FontWeight.w400, height: 1.5),
        // подпись 12.5/400 text-secondary
        bodySmall: _style(c, 12.5, FontWeight.w400, height: 1.45, color: c.muted),
        // кнопка 15/800 (pill h48)
        labelLarge: _style(c, 15, FontWeight.w800, height: 1.2),
        // чип и вкладка таббара 12/700
        labelMedium: _style(c, 12, FontWeight.w700, height: 1.2),
        // caption/сноска 11.5/400 text-muted
        labelSmall: _style(c, 11.5, FontWeight.w400, height: 1.45, tracking: 0.1, color: c.muted),
      );
}

/// Стили, которых нет в Material-шкале: строка списка 14/600, kicker (uppercase 11/700 +0.05em),
/// подпись на белом и акцентная строка.
extension AppTextStyles on TextTheme {
  /// Строка списка 14/600.
  TextStyle get row => bodyMedium!.copyWith(fontSize: 14, fontWeight: FontWeight.w600, height: 1.35);

  /// Акцентная строка списка 14/800.
  TextStyle get rowStrong => titleSmall!.copyWith(fontSize: 14, fontWeight: FontWeight.w800);

  /// Подстрока в списке 12.5/400 — цвет задаёт вызывающий (`copyWith(color: muted)`).
  TextStyle get rowDetail => bodyMedium!.copyWith(fontSize: 12.5, height: 1.4);

  /// Kicker над блоком 11/700 +0.05em: текст передаётся в верхнем регистре.
  TextStyle get overline => labelMedium!.copyWith(fontSize: 11, letterSpacing: 0.55);

  /// Caption на белом 11.5/400 text-muted.
  TextStyle get caption => labelSmall!;
}
