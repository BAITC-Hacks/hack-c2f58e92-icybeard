import 'package:flutter/material.dart';

import 'tokens.dart';

/// Пара «текст / фон» для чипов статусов и меток происхождения.
class Tone {
  const Tone(this.fg, this.bg);

  final Color fg;
  final Color bg;

  static Tone lerp(Tone a, Tone b, double t) => Tone(Color.lerp(a.fg, b.fg, t)!, Color.lerp(a.bg, b.bg, t)!);
}

/// Единственный источник цвета для OriginTag (ml / formula / ai) и StatusChip (ok / warn / danger / neutral / accent).
/// Экраны не обращаются к `Colors.*` напрямую — это проверяет CI-grep.
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
  });

  factory AppTones.from(AppColors c) => AppTones(
        ml: Tone(c.accent, c.accentSoft),
        formula: Tone(c.muted, c.neutralSoft),
        ai: Tone(c.warn, c.warnSoft),
        ok: Tone(c.ok, c.okSoft),
        warn: Tone(c.warn, c.warnSoft),
        danger: Tone(c.danger, c.dangerSoft),
        neutral: Tone(c.muted, c.neutralSoft),
        accent: Tone(c.accent, c.accentSoft),
      );

  final Tone ml;
  final Tone formula;
  final Tone ai;
  final Tone ok;
  final Tone warn;
  final Tone danger;
  final Tone neutral;
  final Tone accent;

  static AppTones of(BuildContext context) => Theme.of(context).extension<AppTones>() ?? AppTones.from(AppColors.light);

  @override
  AppTones copyWith({Tone? ml, Tone? formula, Tone? ai, Tone? ok, Tone? warn, Tone? danger, Tone? neutral, Tone? accent}) => AppTones(
        ml: ml ?? this.ml,
        formula: formula ?? this.formula,
        ai: ai ?? this.ai,
        ok: ok ?? this.ok,
        warn: warn ?? this.warn,
        danger: danger ?? this.danger,
        neutral: neutral ?? this.neutral,
        accent: accent ?? this.accent,
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
    );
  }
}

/// Доступ к сырым токенам темы из виджетов (hairline для коннекторов таймлайна, faint для скелетонов и т.п.).
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette(this.colors);

  final AppColors colors;

  static AppColors of(BuildContext context) => Theme.of(context).extension<AppPalette>()?.colors ?? AppColors.light;

  @override
  AppPalette copyWith({AppColors? colors}) => AppPalette(colors ?? this.colors);

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) => other is AppPalette && t >= 0.5 ? other : this;
}
