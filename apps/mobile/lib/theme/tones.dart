import 'package:flutter/material.dart';

import 'tokens.dart';

/// Пара «текст / фон» для чипов статусов и меток происхождения.
class Tone {
  const Tone(this.fg, this.bg);

  final Color fg;
  final Color bg;

  static Tone lerp(Tone a, Tone b, double t) => Tone(Color.lerp(a.fg, b.fg, t)!, Color.lerp(a.bg, b.bg, t)!);
}

/// Единственный источник цвета для OriginTag (ml / formula / ai) и StatusChip (ok / warn / danger / neutral /
/// accent / bench). Метки происхождения по системе: «ML-модель» — heal-wash/ink, «формула» — soft/ink-2,
/// «AI» — coral-wash/ink; внешний ориентир — bench-wash/ink. Экраны не обращаются к `Colors.*` — это проверяет CI.
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
  });

  factory AppTones.from(AppColors c) => AppTones(
        ml: Tone(c.ink, c.accentSoft),
        formula: Tone(c.muted, c.neutralSoft),
        ai: Tone(c.ink, c.dangerSoft),
        ok: Tone(c.ok, c.okSoft),
        warn: Tone(c.danger, c.dangerSoft),
        danger: Tone(c.danger, c.dangerSoft),
        neutral: Tone(c.muted, c.neutralSoft),
        accent: Tone(c.accent, c.neutralSoft),
        bench: Tone(c.ink, c.benchSoft),
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

  static AppTones of(BuildContext context) => Theme.of(context).extension<AppTones>() ?? AppTones.from(AppColors.light);

  @override
  AppTones copyWith({Tone? ml, Tone? formula, Tone? ai, Tone? ok, Tone? warn, Tone? danger, Tone? neutral, Tone? accent, Tone? bench}) => AppTones(
        ml: ml ?? this.ml,
        formula: formula ?? this.formula,
        ai: ai ?? this.ai,
        ok: ok ?? this.ok,
        warn: warn ?? this.warn,
        danger: danger ?? this.danger,
        neutral: neutral ?? this.neutral,
        accent: accent ?? this.accent,
        bench: bench ?? this.bench,
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
    );
  }
}

/// Доступ к сырым токенам темы из виджетов (hairline для строк, neutralSoft для вставок, accent для точек).
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette(this.colors);

  final AppColors colors;

  static AppColors of(BuildContext context) => Theme.of(context).extension<AppPalette>()?.colors ?? AppColors.light;

  @override
  AppPalette copyWith({AppColors? colors}) => AppPalette(colors ?? this.colors);

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) => other is AppPalette && t >= 0.5 ? other : this;
}
