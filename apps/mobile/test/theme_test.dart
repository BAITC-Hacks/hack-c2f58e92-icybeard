import 'dart:convert';
import 'dart:io';

import 'package:darumen/theme/app_theme.dart';
import 'package:darumen/theme/tokens.dart';
import 'package:darumen/theme/tones.dart';
import 'package:darumen/theme/typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('light and dark themes are built from the same tokens with Manrope, dense scale and tabular numerals', () {
    final light = AppTheme.light();
    final dark = AppTheme.dark();
    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(AppType.family, 'Manrope');
    expect(light.textTheme.bodyMedium?.fontFamily, AppType.family);
    expect(light.textTheme.bodyMedium?.fontSize, 14.5, reason: 'тело 14.5 — текстовый ярус веба (type.text.base)');
    expect(light.textTheme.headlineMedium?.fontSize, 24, reason: 'заголовок экрана 24/800');
    expect(light.textTheme.headlineMedium?.fontWeight, FontWeight.w800);
    expect(light.textTheme.displayLarge?.fontSize, 40, reason: 'hero-число 40/800 (у Manrope нет 900)');
    expect(light.textTheme.displayLarge?.fontWeight, FontWeight.w800);
    expect(light.textTheme.labelLarge?.fontWeight, FontWeight.w800, reason: 'кнопки 15/800');
    expect(light.colorScheme.primary, ColorTokens.light.accent, reason: 'синяя гамма: primary — #2F6FE4');
    expect(dark.colorScheme.primary, ColorTokens.dark.accent);
    expect(light.scaffoldBackgroundColor, const Color(0xFFF5F6F8), reason: 'рабочие страницы — светло-серый --bg-page');
    expect(dark.scaffoldBackgroundColor, const Color(0xFF0D1526));
    expect(AppType.numeric.fontFeatures, contains(const FontFeature.tabularFigures()));
    expect(light.extension<AppTones>(), isNotNull);
    expect(dark.extension<AppPalette>()?.colors.surface, ColorTokens.dark.surface);
    expect(light.cardTheme.elevation, 0, reason: 'тень карточки — своя (--shadow-card), не elevation');
    final cardShape = light.cardTheme.shape as RoundedRectangleBorder;
    expect(cardShape.side, BorderSide.none, reason: 'карточки без рамки');
    expect(cardShape.borderRadius, BorderRadius.circular(18), reason: 'радиус карточек 18');
    expect(light.filledButtonTheme.style?.minimumSize?.resolve({})?.height, 48, reason: 'кнопки h48');
    expect(light.filledButtonTheme.style?.shape?.resolve({}), const StadiumBorder(), reason: 'кнопки всегда pill');
    expect(light.filledButtonTheme.style?.backgroundColor?.resolve({}), const Color(0xFF2F6FE4), reason: 'primary — --accent');
    expect(light.filledButtonTheme.style?.foregroundColor?.resolve({}), ColorTokens.white, reason: 'белый текст на синем');
    expect(light.outlinedButtonTheme.style?.backgroundColor?.resolve({}), const Color(0xFFEAF1FE), reason: 'secondary — --accent-subtle');
    expect(light.outlinedButtonTheme.style?.foregroundColor?.resolve({}), const Color(0xFF1E4FB8), reason: 'текст secondary — --accent-strong');
    expect(light.textButtonTheme.style?.foregroundColor?.resolve({}), const Color(0xFF2F6FE4), reason: 'ссылки — --link');
    expect(light.inputDecorationTheme.fillColor, ColorTokens.light.card, reason: 'поле белое');
    final enabled = light.inputDecorationTheme.enabledBorder as OutlineInputBorder;
    expect(enabled.borderSide.color, ColorTokens.light.hairline, reason: 'рамка поля 1.5 --border');
    expect(enabled.borderSide.width, 1.5);
    expect(enabled.borderRadius, BorderRadius.circular(12), reason: 'радиус поля 12');
    final focused = light.inputDecorationTheme.focusedBorder as OutlineInputBorder;
    expect(focused.borderSide.color, ColorTokens.light.accent, reason: 'фокус — обводка accent');
    expect(focused.borderSide.width, 2);
    final selectedTrack = light.switchTheme.trackColor?.resolve({WidgetState.selected});
    expect(selectedTrack, ColorTokens.light.accent, reason: 'включённый тумблер — accent');
    expect(light.switchTheme.trackColor?.resolve({}), ColorTokens.light.toggleOff);
  });

  testWidgets('danger button: danger-bg background with danger-text (components.md «Danger»)', (tester) async {
    late ButtonStyle style;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Builder(builder: (context) {
        style = AppButtons.danger(context);
        return const SizedBox();
      }),
    ));
    expect(style.backgroundColor?.resolve({}), const Color(0xFFFFE0E6));
    expect(style.foregroundColor?.resolve({}), const Color(0xFF9F1239));
  });

  group('design/tokens.json is the single source (the test reads the file, not literals)', () {
    // CI запускает flutter test из apps/mobile на полном чекауте: файл лежит двумя уровнями выше
    final tokens = jsonDecode(File('../../design/tokens.json').readAsStringSync()) as Map<String, dynamic>;
    Color hex(String value) => Color(int.parse('FF${value.substring(1)}', radix: 16));

    /// Роль tokens.json → поле ColorTokens. Новая роль в JSON без строки здесь роняет тест.
    Map<String, Color> roles(ColorTokens c) => {
          'bg-page': c.surface,
          'surface': c.card,
          'surface-sunken': c.surfaceSunken,
          'surface-muted': c.neutralSoft,
          'surface-hover': c.surfaceHover,
          'surface-info': c.surfaceInfo,
          'border': c.hairline,
          'border-soft': c.borderSoft,
          'border-strong': c.faint,
          'toggle-off': c.toggleOff,
          'text': c.ink,
          'text-secondary': c.muted,
          'text-muted': c.textMuted,
          'text-faint': c.textFaint,
          'text-on-accent': c.onAccent,
          'accent': c.accent,
          'accent-strong': c.accentHover,
          'accent-soft': c.accentSoft,
          'accent-subtle': c.accentSubtle,
          'accent-line': c.accentLine,
          'link': c.link,
          'success-bg': c.okSoft,
          'success-text': c.ok,
          'success-line': c.okLine,
          'success-soft-text': c.okSoftText,
          'warning-bg': c.warnSoft,
          'warning-text': c.warn,
          'warning-strong': c.warnStrong,
          'danger-bg': c.dangerSoft,
          'danger-text': c.danger,
          'danger-strong': c.dangerStrong,
          'scale-good': c.map1,
          'scale-mid': c.map3,
          'scale-bad': c.map5,
          'bar-neutral': c.barNeutral,
        };

    for (final (name, colors) in [('light', ColorTokens.light), ('dark', ColorTokens.dark)]) {
      test('$name colour roles equal tokens.json, derived roles follow their source roles', () {
        final json = (tokens[name] as Map<String, dynamic>).cast<String, String>();
        final mapped = roles(colors);
        expect(json.keys.toSet(), {...mapped.keys, 'bg-hero-gradient'}, reason: '$name: каждая роль JSON сопоставлена полю ColorTokens');
        for (final entry in mapped.entries) {
          expect(entry.value, hex(json[entry.key]!), reason: '$name.${entry.key}');
        }
        final stops = RegExp('#[0-9A-Fa-f]{6}').allMatches(json['bg-hero-gradient']!).map((m) => hex(m.group(0)!)).toList();
        expect(colors.heroGradient, stops, reason: '$name: градиент 4 остановки 0/30/55/100 %');
        // производные роли мобилки: «инфо» — accent-strong/accent-soft, метки AI и внешнего ориентира — surface-muted/text-secondary
        expect(colors.info, colors.accentHover);
        expect(colors.infoSoft, colors.accentSoft);
        expect(colors.ai, colors.muted);
        expect(colors.aiSoft, colors.neutralSoft);
        expect(colors.benchSoft, colors.neutralSoft);
      });

      test('$name map ramp map1…map5 equals scale-ramp', () {
        final ramp = ((tokens['scale-ramp'] as Map<String, dynamic>)[name] as List<dynamic>).cast<String>().map(hex).toList();
        expect([colors.map1, colors.map2, colors.map3, colors.map4, colors.map5], ramp);
      });
    }

    test('AppRadius keeps its mobile names and maps onto the tokens.json radius scale', () {
      final radius = (tokens['radius'] as Map<String, dynamic>).map((k, v) => MapEntry(k, (v as num).toDouble()));
      // мобильные имена сохранены (решение 13): md 12 — это JSON lg, lg 14 — JSON xl, plate 10 — JSON md
      const mapped = {
        'xs': AppRadius.xs,
        'sm': AppRadius.sm,
        'md': AppRadius.plate,
        'lg': AppRadius.md,
        'xl': AppRadius.lg,
        'card': AppRadius.card,
        'pill': AppRadius.pill,
      };
      const webOnly = {'cardLg'};
      expect(radius.keys.toSet(), {...mapped.keys, ...webOnly}, reason: 'каждый радиус JSON сопоставлен или явно веб-only');
      for (final entry in mapped.entries) {
        expect(entry.value, radius[entry.key], reason: 'radius.${entry.key}');
      }
    });

    test('type.text and type.mobile equal the AppType scale; every weight is one of font.weights', () {
      final type = tokens['type'] as Map<String, dynamic>;
      double size(String tier, String key) => ((type[tier] as Map<String, dynamic>)[key] as num).toDouble();
      final t = AppType.textTheme(ColorTokens.light);
      final text = <String, List<TextStyle?>>{
        'xs': [t.overline],
        'sm': [t.labelSmall, t.caption, t.labelMedium],
        'base-sm': [t.bodySmall, t.rowDetail],
        'base': [t.bodyMedium, t.titleSmall, t.row, t.rowStrong],
        'md': [t.bodyLarge, t.labelLarge],
        'lg': [t.titleMedium],
      };
      const textWebOnly = {'2xs', 'xl'};
      expect((type['text'] as Map<String, dynamic>).keys.toSet(), {...text.keys, ...textWebOnly});
      for (final entry in text.entries) {
        for (final style in entry.value) {
          expect(style?.fontSize, size('text', entry.key), reason: 'type.text.${entry.key}');
        }
      }
      final mobile = <String, List<double?>>{
        'title': [t.headlineMedium?.fontSize],
        'kpi': [t.headlineSmall?.fontSize],
        'heading': [t.titleLarge?.fontSize],
        'display': [t.displaySmall?.fontSize],
        'hero': [t.displayLarge?.fontSize, t.displayMedium?.fontSize],
        'nav': [AppType.navLabelSize],
      };
      expect((type['mobile'] as Map<String, dynamic>).keys.toSet(), mobile.keys.toSet());
      for (final entry in mobile.entries) {
        for (final value in entry.value) {
          expect(value, size('mobile', entry.key), reason: 'type.mobile.${entry.key}');
        }
      }
      final weights = ((tokens['font'] as Map<String, dynamic>)['weights'] as List<dynamic>).cast<num>().map((w) => w.toInt()).toSet();
      final styles = [
        t.displayLarge, t.displayMedium, t.displaySmall, t.headlineMedium, t.headlineSmall, t.titleLarge, t.titleMedium, t.titleSmall,
        t.bodyLarge, t.bodyMedium, t.bodySmall, t.labelLarge, t.labelMedium, t.labelSmall, t.row, t.rowStrong, t.rowDetail, t.overline,
      ];
      for (final style in styles) {
        expect(weights, contains(style!.fontWeight!.value), reason: '${style.fontSize}/${style.fontWeight}: начертание из tokens.json');
      }
      expect((tokens['font'] as Map<String, dynamic>)['family'], AppType.family);
    });

    test('layout.mobile equals AppSpacing and AppSizes', () {
      final layout = ((tokens['layout'] as Map<String, dynamic>)['mobile'] as Map<String, dynamic>).map((k, v) => MapEntry(k, (v as num).toDouble()));
      expect(layout, {
        'page': AppSpacing.page,
        'gap': AppSpacing.md,
        'control': AppSizes.control,
        'row': AppSizes.row,
        'nav': AppSizes.nav,
      });
    });
  });

  test('tones follow the blue palette: origin labels neutral pill, info/current — accent-soft/strong, amber risk', () {
    final tones = AppTones.from(ColorTokens.light);
    expect(tones.ml.fg, const Color(0xFF48536D), reason: 'бирюзовый «ML» упразднён — surface-muted/text-secondary');
    expect(tones.ml.bg, const Color(0xFFE8EEFA));
    expect(tones.formula.fg, const Color(0xFF48536D));
    expect(tones.formula.bg, const Color(0xFFE8EEFA));
    expect(tones.ai.fg, const Color(0xFF48536D), reason: 'лавандовый «AI» упразднён');
    expect(tones.ai.bg, const Color(0xFFE8EEFA));
    expect(tones.accent.fg, const Color(0xFF1E4FB8), reason: '«текущая»/«инфо» — accent-strong на accent-soft');
    expect(tones.accent.bg, const Color(0xFFDEEAFD));
    expect(tones.ok.fg, const Color(0xFF2A5C4E));
    expect(tones.ok.bg, const Color(0xFFDDF7C8));
    expect(tones.warn.fg, const Color(0xFF9A5A00), reason: 'риск и аномалии — янтарные, не синие');
    expect(tones.warn.bg, const Color(0xFFFFE9C7));
    expect(tones.danger.fg, const Color(0xFF9F1239));
    expect(tones.danger.bg, const Color(0xFFFFE0E6));
    expect(tones.neutral.bg, ColorTokens.light.surfaceSunken, reason: 'нейтральный статус — surface-sunken');
    expect(tones.bench.bg, ColorTokens.light.benchSoft);
    expect(tones.info.bg, ColorTokens.light.infoSoft);
    expect(tones.quiet.fg, ColorTokens.light.muted, reason: 'нейтральный круг состояния — surface-muted/text-secondary, как StateBlock веба');
    expect(tones.quiet.bg, ColorTokens.light.neutralSoft);
    expect(tones.copyWith(quiet: tones.ok).quiet, tones.ok);
    final mid = tones.lerp(AppTones.from(ColorTokens.dark), 0.5);
    expect(mid.ml.fg, isNot(tones.ml.fg));
  });
}
