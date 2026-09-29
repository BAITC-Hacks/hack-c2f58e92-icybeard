import 'package:flutter/material.dart';

import 'tokens.dart';

/// Пара «текст / фон» для чипов статусов и меток происхождения.
class Tone {
  const Tone(this.fg, this.bg);

  final Color fg;
  final Color bg;

  static Tone lerp(Tone a, Tone b, double t) => Tone(Color.lerp(a.fg, b.fg, t)!, Color.lerp(a.bg, b.bg, t)!);
}

/// Единственный источник цвета для OriginTag (ml / formula / ai), StatusChip (ok / warn / danger / neutral /
/// accent / bench) и состояний экрана (info). Синяя гамма (handoff/components.md): метки происхождения (ML /
/// формула / AI) — нейтральная пилюля surface-muted/text-secondary (бирюзовый и лавандовый упразднены), «инфо» и
/// «текущая» (accent) — accent-soft/accent-strong, good — зелёный, attention (риск, аномалии) — янтарный,
/// critical — красный; нейтральный статус — surface-sunken/text-secondary. Экраны не обращаются к `Colors.*`.
class AppTones extends ThemeExtension<AppTones> {
  const AppTones({
    required this.ml,
    required this.formula,
    required this.ai,
    required this.ok,
    required this.warn,
    required this.danger,
    required this.neutral,
    required this.accent,
    required this.bench,
    required this.info,
  });

  factory AppTones.from(ColorTokens c) => AppTones(
        ml: Tone(c.muted, c.neutralSoft),
        formula: Tone(c.muted, c.neutralSoft),
        ai: Tone(c.ai, c.aiSoft),
        ok: Tone(c.ok, c.okSoft),
        warn: Tone(c.warn, c.warnSoft),
        danger: Tone(c.danger, c.dangerSoft),
        neutral: Tone(c.muted, c.surfaceSunken),
        accent: Tone(c.accentHover, c.accentSoft),
        bench: Tone(c.muted, c.benchSoft),
        info: Tone(c.info, c.infoSoft),
      );

  final Tone ml;
  final Tone formula;
  final Tone ai;
  final Tone ok;
  final Tone warn;
  final Tone danger;
  final Tone neutral;
  final Tone accent;
  final Tone bench;

  /// Сервисная информация: «данные устарели».
  final Tone info;

  static AppTones of(BuildContext context) => Theme.of(context).extension<AppTones>() ?? AppTones.from(ColorTokens.light);

  @override
  AppTones copyWith({Tone? ml, Tone? formula, Tone? ai, Tone? ok, Tone? warn, Tone? danger, Tone? neutral, Tone? accent, Tone? bench, Tone? info}) => AppTones(
        ml: ml ?? this.ml,
        formula: formula ?? this.formula,
        ai: ai ?? this.ai,
        ok: ok ?? this.ok,
        warn: warn ?? this.warn,
        danger: danger ?? this.danger,
        neutral: neutral ?? this.neutral,
        accent: accent ?? this.accent,
        bench: bench ?? this.bench,
        info: info ?? this.info,
      );

  @override
  AppTones lerp(ThemeExtension<AppTones>? other, double t) {
    if (other is! AppTones) {
      return this;
    }
    return AppTones(
      ml: Tone.lerp(ml, other.ml, t),
      formula: Tone.lerp(formula, other.formula, t),
      ai: Tone.lerp(ai, other.ai, t),
      ok: Tone.lerp(ok, other.ok, t),
      warn: Tone.lerp(warn, other.warn, t),
      danger: Tone.lerp(danger, other.danger, t),
      neutral: Tone.lerp(neutral, other.neutral, t),
      accent: Tone.lerp(accent, other.accent, t),
      bench: Tone.lerp(bench, other.bench, t),
      info: Tone.lerp(info, other.info, t),
    );
  }
}

/// Доступ к сырым токенам темы из виджетов (hairline для строк, neutralSoft для вставок, accent для точек и полос).
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette(this.colors);

  final ColorTokens colors;

  static ColorTokens of(BuildContext context) => Theme.of(context).extension<AppPalette>()?.colors ?? ColorTokens.light;

  @override
  AppPalette copyWith({ColorTokens? colors}) => AppPalette(colors ?? this.colors);

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) => other is AppPalette && t >= 0.5 ? other : this;
}
