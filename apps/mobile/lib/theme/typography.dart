import 'package:flutter/material.dart';

import 'tokens.dart';

/// Шкала Manrope «синей гаммы» по `design/tokens.json` (паритет — `test/theme_test.dart`). Два яруса:
/// - текстовый ярус общий с вебом (`type.text`): тело 14.5, вторичный текст и подстроки 13.5, подпись и чип 12,
///   kicker 11.5, заголовок карточки и состояния 16.5, ввод и кнопка 15;
/// - крупный ярус свой у телефона (`type.mobile`): заголовок экрана 24, KPI 22, организация 19, крупный срок 34,
///   hero 40, подпись вкладки 11 — веб-значения 26/28 на 360 dp при масштабе 1.3 не помещаются.
/// Начертания только 400/600/700/800 (у Manrope нет 900 — «900» макетов рендерится как 800). Цифры KPI, дней и дат —
/// табличные (`tnum`), чтобы столбцы не прыгали.
abstract final class AppType {
  static const family = 'Manrope';

  /// Подпись вкладки нижней навигации 11/700 (`type.mobile.nav`): «Хабарламалар» в трети 328 dp при масштабе 1.3.
  static const double navLabelSize = 11;

  /// Добавляется к стилю чисел: `style.merge(AppType.numeric)`.
  static const numeric = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

  static TextStyle _style(ColorTokens c, double size, FontWeight weight, {double height = 1.3, double? tracking, Color? color}) =>
      TextStyle(fontFamily: family, fontSize: size, fontWeight: weight, height: height, letterSpacing: tracking, color: color ?? c.ink);

  static TextTheme textTheme(ColorTokens c) => TextTheme(
        // hero-число экрана 40/800 −0.02em (доски: «53», «≈80», таймер скрайба) — type.mobile.hero
        displayLarge: _style(c, 40, FontWeight.w800, height: 1.0, tracking: -0.8),
        // hero в карточке (врач, направление) — те же 40/800
        displayMedium: _style(c, 40, FontWeight.w800, height: 1.05, tracking: -0.8),
        // крупный срок в тексте карточки 34/800 («≈54 дн.») — type.mobile.display
        displaySmall: _style(c, 34, FontWeight.w800, height: 1.05, tracking: -0.68),
        // заголовок экрана в топбаре 24/800 −0.01em — type.mobile.title
        headlineMedium: _style(c, 24, FontWeight.w800, height: 1.15, tracking: -0.24),
        // значение KPI, ячейка OTP, реф пациента крупно 22/800 — type.mobile.kpi
        headlineSmall: _style(c, 22, FontWeight.w800, height: 1.2, tracking: -0.22),
        // организация, МНН, заголовок нижнего листа 19/800 — type.mobile.heading
        titleLarge: _style(c, 19, FontWeight.w800, height: 1.25, tracking: -0.19),
        // заголовок карточки и состояния 16.5/800 — type.text.lg
        titleMedium: _style(c, 16.5, FontWeight.w800, height: 1.35),
        // заголовок свёрнутой секции, ссылка-действие, малая кнопка 14.5/700 — type.text.base
        titleSmall: _style(c, 14.5, FontWeight.w700, height: 1.35),
        // текст поля ввода и подсказки 15/400 — type.text.md
        bodyLarge: _style(c, 15, FontWeight.w400, height: 1.5),
        // тело 14.5/400 — type.text.base
        bodyMedium: _style(c, 14.5, FontWeight.w400, height: 1.5),
        // вторичный текст 13.5/400 text-secondary — type.text.base-sm
        bodySmall: _style(c, 13.5, FontWeight.w400, height: 1.45, color: c.muted),
        // кнопка 15/800 (pill h48) — type.text.md
        labelLarge: _style(c, 15, FontWeight.w800, height: 1.2),
        // чип и пилюля-фильтр 12/700 — type.text.sm
        labelMedium: _style(c, 12, FontWeight.w700, height: 1.2),
        // подпись/сноска 12/400 text-secondary — type.text.sm
        labelSmall: _style(c, 12, FontWeight.w400, height: 1.45, tracking: 0.1, color: c.muted),
      );
}

/// Стили, которых нет в Material-шкале: строка списка 14.5/600, kicker (uppercase 11.5/700 +0.05em),
/// подстрока списка и подпись.
extension AppTextStyles on TextTheme {
  /// Строка списка 14.5/600 (веб `.row`, type.text.base).
  TextStyle get row => bodyMedium!.copyWith(fontSize: 14.5, fontWeight: FontWeight.w600, height: 1.35);

  /// Акцентная строка списка 14.5/800.
  TextStyle get rowStrong => titleSmall!.copyWith(fontSize: 14.5, fontWeight: FontWeight.w800);

  /// Подстрока в списке 13.5/400 (веб `.row-sub`, type.text.base-sm) — цвет задаёт вызывающий (`copyWith(color: muted)`).
  TextStyle get rowDetail => bodyMedium!.copyWith(fontSize: 13.5, height: 1.4);

  /// Kicker над блоком 11.5/700 +0.05em (веб `.eyebrow`, type.text.xs): текст передаётся в верхнем регистре.
  TextStyle get overline => labelMedium!.copyWith(fontSize: 11.5, letterSpacing: 0.575);

  /// Подпись 12/400 text-secondary (веб `.caption`, type.text.sm; text-muted веба на мелком тексте даёт 3,9:1 — мало).
  TextStyle get caption => labelSmall!;
}
