import 'package:flutter/material.dart';

/// Токены «Clinical Minimal» — те же значения, что в питч-деке и в веб-токенах (`design/tokens.json`): один
/// приглушённый бирюзовый акцент, чернильный текст, hairline-границы, много воздуха. Тёмная тема — те же роли,
/// другие значения; контраст muted/ink к фону ≥ 4.5:1 в обеих темах.
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
  });

  /// Фон экрана.
  final Color surface;

  /// Фон карточек и полей.
  final Color card;

  /// Основной текст.
  final Color ink;

  /// Второстепенный текст и неактивные иконки.
  final Color muted;

  /// Плейсхолдеры и скелетоны.
  final Color faint;

  /// Границы карточек, разделители, коннекторы таймлайна.
  final Color hairline;

  /// Единственный акцент: кнопки, активная вкладка, метка «ML‑модель».
  final Color accent;
  final Color accentSoft;
  final Color ok;
  final Color okSoft;
  final Color warn;
  final Color warnSoft;
  final Color danger;
  final Color dangerSoft;

  /// Фон нейтральных чипов и метки «формула».
  final Color neutralSoft;

  static const light = AppColors(
    surface: Color(0xFFFDFDFB),
    card: Color(0xFFFFFFFF),
    ink: Color(0xFF101418),
    muted: Color(0xFF6E7680),
    faint: Color(0xFFB9BFC4),
    hairline: Color(0xFFE6E8E6),
    accent: Color(0xFF0F766E),
    accentSoft: Color(0xFFE4EFED),
    ok: Color(0xFF2F7D4F),
    okSoft: Color(0xFFE6F1EA),
    warn: Color(0xFF92600A),
    warnSoft: Color(0xFFF6ECDF),
    danger: Color(0xFF8A3B2E),
    dangerSoft: Color(0xFFF3E6E3),
    neutralSoft: Color(0xFFECEFF3),
  );

  static const dark = AppColors(
    surface: Color(0xFF0E1213),
    card: Color(0xFF161B1D),
    ink: Color(0xFFECEEEA),
    muted: Color(0xFF9AA3AA),
    faint: Color(0xFF5C656C),
    hairline: Color(0xFF242B2E),
    accent: Color(0xFF3FA89E),
    accentSoft: Color(0xFF173B38),
    ok: Color(0xFF7FC39A),
    okSoft: Color(0xFF1C3326),
    warn: Color(0xFFD9A85B),
    warnSoft: Color(0xFF3A2E18),
    danger: Color(0xFFD08B7E),
    dangerSoft: Color(0xFF3A231F),
    neutralSoft: Color(0xFF22282B),
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
}

abstract final class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double pill = 999;
}

abstract final class AppDurations {
  static const fast = Duration(milliseconds: 150);
  static const pulse = Duration(milliseconds: 900);
}
