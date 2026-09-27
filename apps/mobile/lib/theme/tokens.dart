import 'package:flutter/material.dart';

/// Токены «Тихая клиника» (docs/design-system.md) — те же значения, что в `design/tokens.json`, паритет проверяет
/// `test/theme_test.dart`. Молочный фон, тёмно-синие чернила, коралл — единственный сигнал (точки, маркеры,
/// предупреждения); карточки белые без рамок, линии только внутри списков. Тёмная тема — производная от той же
/// палитры, контраст ink/surface ≥ 4.5:1 в обеих.
class AppColors {
  const AppColors({
    required this.surface,
    required this.card,
    required this.ink,
    required this.muted,
    required this.faint,
    required this.hairline,
    required this.accent,
    required this.accentSoft,
    required this.ok,
    required this.okSoft,
    required this.warn,
    required this.warnSoft,
    required this.danger,
    required this.dangerSoft,
    required this.neutralSoft,
    required this.benchSoft,
    required this.dotIdle,
    required this.navShadow,
  });

  /// ground — фон экрана.
  final Color surface;

  /// card — карточки и поля выбора.
  final Color card;

  /// ink — основной текст, primary-кнопки, активные пилюли.
  final Color ink;

  /// ink-2 — вторичный текст, подписи, неактивные вкладки.
  final Color muted;

  /// ink-3 — подписи на белом (caption).
  final Color faint;

  /// Линии между строками списков.
  final Color hairline;

  /// coral — сигнал: точка активной вкладки, маркер этапа, бар «предложил врач».
  final Color accent;

  /// heal-wash — фон чипа «ML-модель» и «рекомендация» (текст ink).
  final Color accentSoft;

  /// sage — ok-текст и его фон («покрыт», «совпало»).
  final Color ok;
  final Color okSoft;

  /// coral-text / coral-wash — предупреждения; в этой системе warn и danger совпадают.
  final Color warn;
  final Color warnSoft;
  final Color danger;
  final Color dangerSoft;

  /// soft — вставки, нейтральные чипы, вторичные кнопки, круглые иконки-кнопки.
  final Color neutralSoft;

  /// bench-wash — чип внешнего ориентира («ВОЗ/ЮНИСЕФ · 2021»).
  final Color benchSoft;

  /// Неактивная точка в списках и столбики тишины в волне скрайба.
  final Color dotIdle;

  /// Тень плавающей навигации.
  final Color navShadow;

  /// Белый и прозрачный — единственные цвета вне палитры (текст на ink-кнопках, surfaceTint).
  static const white = Color(0xFFFFFFFF);
  static const transparent = Color(0x00000000);
  static const shadow = Color(0xFF000000);
  static const scrim = Color(0x8A000000);

  static const light = AppColors(
    surface: Color(0xFFF4F6F0),
    card: Color(0xFFFFFFFF),
    ink: Color(0xFF0F2C59),
    muted: Color(0xFF5B6577),
    faint: Color(0xFF6B7486),
    hairline: Color(0xFFE3E7DF),
    accent: Color(0xFFFF7F50),
    accentSoft: Color(0xFFDCE8E0),
    ok: Color(0xFF4F6B56),
    okSoft: Color(0xFFE3ECE4),
    warn: Color(0xFFB8431A),
    warnSoft: Color(0xFFFFE4D8),
    danger: Color(0xFFB8431A),
    dangerSoft: Color(0xFFFFE4D8),
    neutralSoft: Color(0xFFEDF0E8),
    benchSoft: Color(0xFFFFF6BF),
    dotIdle: Color(0xFFC9D1DA),
    navShadow: Color(0x0F0F2C59),
  );

  static const dark = AppColors(
    surface: Color(0xFF0B1E3D),
    card: Color(0xFF13294F),
    ink: Color(0xFFEEF2F7),
    muted: Color(0xFFA9B6C8),
    faint: Color(0xFF8E9DB3),
    hairline: Color(0xFF24406E),
    accent: Color(0xFFFF7F50),
    accentSoft: Color(0xFF1F3F3A),
    ok: Color(0xFF9CC3A6),
    okSoft: Color(0xFF1E3A2A),
    warn: Color(0xFFFFA07A),
    warnSoft: Color(0xFF4A2A1F),
    danger: Color(0xFFFFA07A),
    dangerSoft: Color(0xFF4A2A1F),
    neutralSoft: Color(0xFF1B3560),
    benchSoft: Color(0xFF4A4320),
    dotIdle: Color(0xFF3A5078),
    navShadow: Color(0x66000000),
  );
}

/// Шкала отступов: 4 / 8 / 12 / 16 / 24 / 32. Экраны используют только её, без «магических» чисел.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Боковой отступ экрана (шапка и контент): `padding 0 20`.
  static const double page = 20;
}

abstract final class AppRadius {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double pill = 999;
}

/// Размеры компонентов мобилки (docs/design-system.md, «Компоненты — мобилка»).
abstract final class AppSizes {
  /// Primary/secondary-кнопка и поле ввода.
  static const double control = 52;

  /// Компактное поле и пилюля-фильтр.
  static const double compact = 44;

  /// Кнопка-селектор (регион/профиль).
  static const double select = 48;

  /// Круглая кнопка-иконка в шапке.
  static const double iconButton = 40;

  /// Строка списка внутри карточки.
  static const double row = 56;

  /// Плавающая нижняя навигация.
  static const double nav = 64;

  /// Точка «новое/активное» (6), маркер текущего этапа (14), полоса этапа (3).
  static const double dot = 6;
  static const double marker = 14;
  static const double bar = 3;
}

abstract final class AppDurations {
  static const fast = Duration(milliseconds: 150);
  static const pulse = Duration(milliseconds: 900);
}
