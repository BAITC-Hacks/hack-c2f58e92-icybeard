import 'package:flutter/material.dart';

/// Токены «синей гаммы» (handoff/tokens.json дизайн-холста «Darumen Health — макеты»): рабочие экраны на светло-сером
/// `--bg-page`, карточки белые radius 18 с мягкой тенью, текст — тёмно-синие чернила `--text`, единственный
/// brand-акцент — синий `--accent`; семантика good/attention/critical не менялась. Голубой градиент [heroGradient] —
/// только стартовый вход и главная гражданина. Светлая тема утверждена, тёмная — предложение из того же handoff.
/// Паритет значений проверяет `test/theme_test.dart`.
class ColorTokens {
  const ColorTokens({
    required this.surface,
    required this.card,
    required this.ink,
    required this.muted,
    required this.textMuted,
    required this.textFaint,
    required this.faint,
    required this.hairline,
    required this.borderSoft,
    required this.accent,
    required this.accentHover,
    required this.accentSoft,
    required this.accentSubtle,
    required this.accentLine,
    required this.link,
    required this.neutralSoft,
    required this.surfaceSunken,
    required this.surfaceHover,
    required this.surfaceInfo,
    required this.toggleOff,
    required this.ok,
    required this.okSoft,
    required this.okLine,
    required this.okSoftText,
    required this.warn,
    required this.warnSoft,
    required this.warnStrong,
    required this.danger,
    required this.dangerSoft,
    required this.dangerStrong,
    required this.info,
    required this.infoSoft,
    required this.ai,
    required this.aiSoft,
    required this.benchSoft,
    required this.barNeutral,
    required this.map1,
    required this.map2,
    required this.map3,
    required this.map4,
    required this.map5,
    required this.onAccent,
    required this.heroGradient,
    required this.shadowTint,
    required this.cardShadowAlpha,
    required this.popShadowAlpha,
  });

  /// bg-page — светло-серый нейтральный фон рабочих экранов.
  final Color surface;

  /// surface — белые карточки, поля и таббар.
  final Color card;

  /// text — основной текст, тёмно-синие чернила.
  final Color ink;

  /// text-secondary — вторичный текст, подписи, ячейки.
  final Color muted;

  /// text-muted и text-faint — декоративный и отключённый текст (будущие этапы, сноски). Подписи мелким шрифтом
  /// остаются на [muted]: у text-muted контраст на белом 3,9:1.
  final Color textMuted;
  final Color textFaint;

  /// border-strong — рамка чекбокса, будущий шаг, столбики тишины скрайба, точечное подчёркивание. Не для текста.
  final Color faint;

  /// border — разделители строк, рамки инпутов.
  final Color hairline;

  /// border-soft — рамки групп чек-листа, строк ленты и плиток альтернатив, линия степпера.
  final Color borderSoft;

  /// accent — primary-кнопка, активная локаль, прогресс, шаги, чекбокс.
  final Color accent;

  /// accent-strong — текст на светло-синем, активная вкладка, secondary-кнопка, hover.
  final Color accentHover;

  /// accent-soft — активный чип, статус «инфо», карточка-сигнал, кольцо фокуса.
  final Color accentSoft;

  /// accent-subtle — фон secondary-кнопки.
  final Color accentSubtle;

  /// accent-line — рамка mini-кнопки.
  final Color accentLine;

  /// link — ghost-ссылки («Попросить рассмотреть», «Регистрация →»).
  final Color link;

  /// surface-muted — трек локали, круглые кнопки шапки, чип пользователя, трек прогресса, метка происхождения.
  final Color neutralSoft;

  /// surface-sunken — фильтр-чипы, неактивные ячейки, номер шага, нейтральный статус.
  final Color surfaceSunken;

  /// surface-hover — кнопки-ответы, строки «Другой способ», выбранная опция списка.
  final Color surfaceHover;

  /// surface-info — подложка графиков, блок «Рекомендуется…», выбранная опция-карточка.
  final Color surfaceInfo;

  /// toggle-off — выключенный тумблер.
  final Color toggleOff;

  /// good — текст и заливка («покрыт», «совпало», «подтверждено»).
  final Color ok;
  final Color okSoft;

  /// success-line — линия пройденных этапов; success-soft-text — единица рядом с зелёным числом «быстрее».
  final Color okLine;
  final Color okSoftText;

  /// attention — риск и аномалии (всегда янтарные, никогда не синие); warnStrong — янтарные точки и полосы.
  final Color warn;
  final Color warnSoft;
  final Color warnStrong;

  /// critical — отказ, «Выйти», опасное действие; dangerStrong — красные акценты (точка записи, полоса риска).
  final Color danger;
  final Color dangerSoft;
  final Color dangerStrong;

  /// Сервисная информация «данные устарели» — информационный статус (accent-soft/accent-strong).
  final Color info;
  final Color infoSoft;

  /// Метка «AI» — упразднённый лавандовый стал нейтральной пилюлей surface-muted/text-secondary.
  final Color ai;
  final Color aiSoft;

  /// Внешний ориентир («ВОЗ/ЮНИСЕФ · 2021») — та же нейтральная пилюля.
  final Color benchSoft;

  /// bar-neutral — серые столбцы в сравнении «где быстрее».
  final Color barNeutral;

  /// Шкала good → mid → bad (--scale-*): выше — хуже; синий в шкале риска запрещён.
  final Color map1;
  final Color map2;
  final Color map3;
  final Color map4;
  final Color map5;

  /// text-on-accent — текст и иконки на синем.
  final Color onAccent;

  /// bg-hero-gradient (150deg, 0 → 30 → 55 → 100 %) — ТОЛЬКО стартовый вход и главная гражданина.
  final List<Color> heroGradient;

  /// Базовый цвет теней (rgba(24,52,110,…) в светлой, чёрный в тёмной) и их прозрачности.
  final Color shadowTint;

  /// shadow-card: (0 1px 2px, 0 8px 20px -12px).
  final (double, double) cardShadowAlpha;

  /// shadow-pop: (0 4px 10px, 0 24px 48px -18px) — плавающий таббар и всплывающие панели.
  final (double, double) popShadowAlpha;

  /// Остановки градиента из tokens.css: 0 / 30 / 55 / 100 %.
  static const heroGradientStops = [0.0, 0.3, 0.55, 1.0];

  /// Тень карточки (--shadow-card).
  List<BoxShadow> get cardShadow => [
        BoxShadow(color: shadowTint.withValues(alpha: cardShadowAlpha.$1), offset: const Offset(0, 1), blurRadius: 2),
        BoxShadow(color: shadowTint.withValues(alpha: cardShadowAlpha.$2), offset: const Offset(0, 8), blurRadius: 20, spreadRadius: -12),
      ];

  /// Тень плавающей панели (--shadow-pop): таббар, выпадающие списки.
  List<BoxShadow> get popShadow => [
        BoxShadow(color: shadowTint.withValues(alpha: popShadowAlpha.$1), offset: const Offset(0, 4), blurRadius: 10),
        BoxShadow(color: shadowTint.withValues(alpha: popShadowAlpha.$2), offset: const Offset(0, 24), blurRadius: 48, spreadRadius: -18),
      ];

  /// Белый и прозрачный — единственные цвета вне палитры (текст на accent, surfaceTint).
  static const white = Color(0xFFFFFFFF);
  static const transparent = Color(0x00000000);
  static const shadow = Color(0xFF000000);
  static const scrim = Color(0x8A000000);

  static const light = ColorTokens(
    surface: Color(0xFFF5F6F8),
    card: Color(0xFFFFFFFF),
    ink: Color(0xFF1B2440),
    muted: Color(0xFF48536D),
    textMuted: Color(0xFF76819A),
    textFaint: Color(0xFF9FA9BF),
    faint: Color(0xFFD3DCEC),
    hairline: Color(0xFFE1E8F5),
    borderSoft: Color(0xFFE6ECF7),
    accent: Color(0xFF2F6FE4),
    accentHover: Color(0xFF1E4FB8),
    accentSoft: Color(0xFFDEEAFD),
    accentSubtle: Color(0xFFEAF1FE),
    accentLine: Color(0xFFC9DBFA),
    link: Color(0xFF2F6FE4),
    neutralSoft: Color(0xFFE8EEFA),
    surfaceSunken: Color(0xFFEEF3FC),
    surfaceHover: Color(0xFFF4F7FD),
    surfaceInfo: Color(0xFFF6F8FC),
    toggleOff: Color(0xFFDCE4F2),
    ok: Color(0xFF2A5C4E),
    okSoft: Color(0xFFDDF7C8),
    okLine: Color(0xFFB9EBA0),
    okSoftText: Color(0xFF5C8A6E),
    warn: Color(0xFF9A5A00),
    warnSoft: Color(0xFFFFE9C7),
    warnStrong: Color(0xFFB45309),
    danger: Color(0xFF9F1239),
    dangerSoft: Color(0xFFFFE0E6),
    dangerStrong: Color(0xFFD6395E),
    info: Color(0xFF1E4FB8),
    infoSoft: Color(0xFFDEEAFD),
    ai: Color(0xFF48536D),
    aiSoft: Color(0xFFE8EEFA),
    benchSoft: Color(0xFFE8EEFA),
    barNeutral: Color(0xFFB4C0D8),
    map1: Color(0xFF8CC152),
    map2: Color(0xFFBFB546),
    map3: Color(0xFFF2A93B),
    map4: Color(0xFFE4714C),
    map5: Color(0xFFD6395E),
    onAccent: white,
    heroGradient: [Color(0xFFE8F0FE), Color(0xFFEEF3FD), Color(0xFFF2F5FB), Color(0xFFEAF3FA)],
    shadowTint: Color(0xFF18346E),
    cardShadowAlpha: (0.04, 0.10),
    popShadowAlpha: (0.06, 0.24),
  );

  static const dark = ColorTokens(
    surface: Color(0xFF0D1526),
    card: Color(0xFF141E33),
    ink: Color(0xFFE7EDF8),
    muted: Color(0xFFB5C0D6),
    textMuted: Color(0xFF8D9AB5),
    textFaint: Color(0xFF66738F),
    faint: Color(0xFF33446B),
    hairline: Color(0xFF27365A),
    borderSoft: Color(0xFF22304F),
    accent: Color(0xFF2F6FE4),
    accentHover: Color(0xFFA9C6FF),
    accentSoft: Color(0xFF1B3263),
    accentSubtle: Color(0xFF172A50),
    accentLine: Color(0xFF2C4A85),
    link: Color(0xFF8DB4FF),
    neutralSoft: Color(0xFF1F2C48),
    surfaceSunken: Color(0xFF1A2640),
    surfaceHover: Color(0xFF1A2640),
    surfaceInfo: Color(0xFF172238),
    toggleOff: Color(0xFF33446B),
    ok: Color(0xFF8FDDB0),
    okSoft: Color(0xFF16382B),
    okLine: Color(0xFF2F6B4F),
    okSoftText: Color(0xFF7CC39B),
    warn: Color(0xFFF4C574),
    warnSoft: Color(0xFF3A2A10),
    warnStrong: Color(0xFFE59A3A),
    danger: Color(0xFFFF9FB3),
    dangerSoft: Color(0xFF3F1824),
    dangerStrong: Color(0xFFF0607F),
    info: Color(0xFFA9C6FF),
    infoSoft: Color(0xFF1B3263),
    ai: Color(0xFFB5C0D6),
    aiSoft: Color(0xFF1F2C48),
    benchSoft: Color(0xFF1F2C48),
    barNeutral: Color(0xFF3A4A6E),
    map1: Color(0xFF7DB548),
    map2: Color(0xFFB0A83C),
    map3: Color(0xFFE39B30),
    map4: Color(0xFFE17450),
    map5: Color(0xFFE04D6E),
    onAccent: white,
    heroGradient: [Color(0xFF0F1B34), Color(0xFF0E1830), Color(0xFF0D1526), Color(0xFF0E1A2C)],
    shadowTint: shadow,
    cardShadowAlpha: (0.30, 0.55),
    popShadowAlpha: (0.35, 0.70),
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

  /// Боковой отступ экрана (шапка и контент): `padding 0 16` по мобильным доскам.
  static const double page = 16;
}

/// Радиусы синей гаммы: 4 — полоски, 8 — статус-бейджи, 10 — плашка сигнала и заметка в ленте событий,
/// 12 — поля и внутренние блоки, 14 — заметки и строки-плашки, 18 — карточки, pill — кнопки и чипы.
abstract final class AppRadius {
  static const double xs = 4;
  static const double sm = 8;
  static const double plate = 10;
  static const double md = 12;
  static const double lg = 14;
  static const double card = 18;
  static const double pill = 999;
}

/// Размеры компонентов мобилки по доскам m-* синей гаммы.
abstract final class AppSizes {
  /// Primary/secondary-кнопка и поле ввода — h48.
  static const double control = 48;

  /// Компактное поле и пилюля-фильтр (touch target ≥ 44).
  static const double compact = 44;

  /// Кнопка-селектор (регион/профиль) и поле входа.
  static const double select = 48;

  /// Круглая кнопка-иконка в шапке (назад 40 px на surface-muted).
  static const double iconButton = 40;

  /// Малая кнопка в состояниях экрана и в строках («Завершить», «Повторить»).
  static const double small = 36;

  /// Строка списка внутри карточки.
  static const double row = 56;

  /// Плавающая нижняя pill-панель.
  static const double nav = 64;

  /// Точка «новое/активное» (6), маркер текущего этапа (14), полоса этапа (3).
  static const double dot = 6;
  static const double marker = 14;
  static const double bar = 3;

  /// Полоска активной вкладки таббара 16×3.
  static const double navPipWidth = 16;

  /// Иконка в круге у состояний экрана (states-new).
  static const double stateIcon = 48;

  /// Счётчик на вкладке и колокольчике (16), кружок приоритета 0…10 (32), узел этапа (24), точка ленты событий (30).
  static const double badge = 16;
  static const double priority = 32;
  static const double stageNode = 24;
  static const double feedDot = 30;
}

abstract final class AppDurations {
  static const fast = Duration(milliseconds: 150);
  static const pulse = Duration(milliseconds: 900);
}
