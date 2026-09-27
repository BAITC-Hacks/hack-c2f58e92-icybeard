import 'package:flutter/material.dart';

/// Токены Палитры C «Белый холст» (доска C-Tokens, docs/design-system.md) — те же значения, что в
/// `design/tokens.json`, паритет проверяет `test/theme_test.dart`. Белые карточки на светло-сером холсте, текст #333,
/// фиолетовый — единственный brand-акцент (primary-кнопки, навигация, серия графика); аномалии и риск — только
/// янтарные. Тёмная тема — производная от той же палитры, контраст ink/surface ≥ 4.5:1 в обеих.
class ColorTokens {
  const ColorTokens({
    required this.surface,
    required this.card,
    required this.ink,
    required this.muted,
    required this.faint,
    required this.hairline,
    required this.accent,
    required this.accentHover,
    required this.accentSoft,
    required this.neutralSoft,
    required this.ok,
    required this.okSoft,
    required this.warn,
    required this.warnSoft,
    required this.warnStrong,
    required this.danger,
    required this.dangerSoft,
    required this.info,
    required this.infoSoft,
    required this.ai,
    required this.aiSoft,
    required this.benchSoft,
    required this.map1,
    required this.map2,
    required this.map3,
    required this.map4,
    required this.map5,
    required this.onAccent,
    required this.navShadow,
  });

  /// ground — светло-серый холст экрана.
  final Color surface;

  /// card — белые карточки и поля выбора.
  final Color card;

  /// ink — основной текст.
  final Color ink;

  /// ink-2 — вторичный текст, подписи, неактивные вкладки. Единственный вторичный цвет текста.
  final Color muted;

  /// dot-off — неактивная точка, столбики тишины в волне скрайба, скелетоны. Не для текста: контраст на белом < 3:1.
  final Color faint;

  /// Разделители строк списков.
  final Color hairline;

  /// Brand primary — primary-кнопки, активная пилюля, точка навигации, полосы прогресса и серия графика.
  final Color accent;

  /// Наведение и ссылки: TextButton, стрелка «→» у ссылок-действий, текст чипов «AI» и «текущая».
  final Color accentHover;

  /// selected — активный пункт, выбранная строка, чип «текущая», карточка-сигнал, круглые кнопки шапки.
  final Color accentSoft;

  /// inset — поле ввода, вторичная и «опасная» кнопки, нейтральные чипы.
  final Color neutralSoft;

  /// good — текст и заливка («покрыт», «совпало», «подтверждено»).
  final Color ok;
  final Color okSoft;

  /// attention — риск и аномалии (всегда янтарные, никогда не фиолетовые); warnStrong — янтарные точки и полосы.
  final Color warn;
  final Color warnSoft;
  final Color warnStrong;

  /// critical — отказ, «Выйти», опасное действие.
  final Color danger;
  final Color dangerSoft;

  /// info / ML — фон чипа «ML-модель» (текст чипа — ink) и состояния «данные устарели».
  final Color info;
  final Color infoSoft;

  /// lavender — чип «AI» и маркер заголовка.
  final Color ai;
  final Color aiSoft;

  /// Внешний ориентир («ВОЗ/ЮНИСЕФ · 2021»), совпадает с infoSoft.
  final Color benchSoft;

  /// Рамп карты: выше — хуже.
  final Color map1;
  final Color map2;
  final Color map3;
  final Color map4;
  final Color map5;

  /// ink-inverse — текст и иконки на фиолетовом (белый в светлой теме, холст — в тёмной).
  final Color onAccent;

  /// Тень плавающей навигации `0 -4px 16px`.
  final Color navShadow;

  /// Белый и прозрачный — единственные цвета вне палитры (текст на primary, surfaceTint).
  static const white = Color(0xFFFFFFFF);
  static const transparent = Color(0x00000000);
  static const shadow = Color(0xFF000000);
  static const scrim = Color(0x8A000000);

  static const light = ColorTokens(
    surface: Color(0xFFF5F6F8),
    card: Color(0xFFFFFFFF),
    ink: Color(0xFF333333),
    muted: Color(0xFF535768),
    faint: Color(0xFFC4C9D8),
    hairline: Color(0xFFE4E7EE),
    accent: Color(0xFF5B5BD6),
    accentHover: Color(0xFF4646B8),
    accentSoft: Color(0xFFE7ECFF),
    neutralSoft: Color(0xFFEAECF2),
    ok: Color(0xFF2A5C4E),
    okSoft: Color(0xFFDDF7C8),
    warn: Color(0xFF9A5A00),
    warnSoft: Color(0xFFFFE9C7),
    warnStrong: Color(0xFFB45309),
    danger: Color(0xFF9F1239),
    dangerSoft: Color(0xFFFFE0E6),
    info: Color(0xFF0E6F8A),
    infoSoft: Color(0xFFD1FAFF),
    ai: Color(0xFF4646B8),
    aiSoft: Color(0xFFEDDFF7),
    benchSoft: Color(0xFFD1FAFF),
    map1: Color(0xFFEEF0FB),
    map2: Color(0xFFDDE1FA),
    map3: Color(0xFFB6BCF0),
    map4: Color(0xFF8386E0),
    map5: Color(0xFF5B5BD6),
    onAccent: white,
    navShadow: Color(0x0F333558),
  );

  static const dark = ColorTokens(
    surface: Color(0xFF16171D),
    card: Color(0xFF1F2029),
    ink: Color(0xFFE8E9F0),
    muted: Color(0xFFA3A7B8),
    faint: Color(0xFF4A4E5E),
    hairline: Color(0xFF2C2E3A),
    accent: Color(0xFF8B8BF0),
    accentHover: Color(0xFFA5A5F5),
    accentSoft: Color(0xFF2A2B52),
    neutralSoft: Color(0xFF272936),
    ok: Color(0xFF8FD3B8),
    okSoft: Color(0xFF1E3A30),
    warn: Color(0xFFF0B45A),
    warnSoft: Color(0xFF3D2E14),
    warnStrong: Color(0xFFF59E0B),
    danger: Color(0xFFF48CA5),
    dangerSoft: Color(0xFF40202A),
    info: Color(0xFF6FD3EE),
    infoSoft: Color(0xFF15343D),
    ai: Color(0xFFB9A5F0),
    aiSoft: Color(0xFF2E2440),
    benchSoft: Color(0xFF15343D),
    map1: Color(0xFF23253A),
    map2: Color(0xFF2F3260),
    map3: Color(0xFF4B4F9A),
    map4: Color(0xFF6A6DC8),
    map5: Color(0xFF8B8BF0),
    onAccent: Color(0xFF16171D),
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

  /// Кнопка-селектор (регион/профиль) и поле входа.
  static const double select = 48;

  /// Круглая кнопка-иконка в шапке.
  static const double iconButton = 40;

  /// Малая кнопка в состояниях экрана и в строках («Завершить», «Повторить»).
  static const double small = 36;

  /// Строка списка внутри карточки.
  static const double row = 56;

  /// Плавающая нижняя навигация.
  static const double nav = 64;

  /// Точка «новое/активное» (6), маркер текущего этапа (14), полоса этапа (3).
  static const double dot = 6;
  static const double marker = 14;
  static const double bar = 3;

  /// Иконка в круге у состояний экрана (W-States).
  static const double stateIcon = 48;
}

abstract final class AppDurations {
  static const fast = Duration(milliseconds: 150);
  static const pulse = Duration(milliseconds: 900);
}
