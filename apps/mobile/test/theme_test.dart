import 'dart:convert';
import 'dart:io';

import 'package:darumen/theme/app_theme.dart';
import 'package:darumen/theme/tokens.dart';
import 'package:darumen/theme/tones.dart';
import 'package:darumen/theme/typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('light and dark themes are built from the same tokens with Manrope, base 17 and tabular numerals', () {
    final light = AppTheme.light();
    final dark = AppTheme.dark();
    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(AppType.family, 'Manrope');
    expect(light.textTheme.bodyMedium?.fontFamily, AppType.family);
    expect(light.textTheme.bodyMedium?.fontSize, 17, reason: 'базовый кегль 17 («Тихая клиника»)');
    expect(light.textTheme.headlineMedium?.fontSize, 29, reason: 'H1 экрана 29/500');
    expect(light.textTheme.headlineMedium?.fontWeight, FontWeight.w500);
    expect(light.textTheme.displayLarge?.fontSize, 50, reason: 'hero-число 50/600');
    expect(light.textTheme.displayLarge?.fontWeight, FontWeight.w600);
    expect(light.colorScheme.primary, ColorTokens.light.accent, reason: 'Палитра C: primary — фиолетовый brand-акцент');
    expect(dark.colorScheme.primary, ColorTokens.dark.accent);
    expect(light.scaffoldBackgroundColor, const Color(0xFFF5F6F8), reason: 'холст «Белый холст»');
    expect(AppType.numeric.fontFeatures, contains(const FontFeature.tabularFigures()));
    expect(light.extension<AppTones>(), isNotNull);
    expect(dark.extension<AppPalette>()?.colors.surface, ColorTokens.dark.surface);
    expect(light.cardTheme.elevation, 0, reason: 'карточки без тени');
    expect((light.cardTheme.shape as RoundedRectangleBorder).side, BorderSide.none, reason: 'карточки без рамки');
    expect(light.filledButtonTheme.style?.minimumSize?.resolve({})?.height, 52);
    expect(light.filledButtonTheme.style?.backgroundColor?.resolve({}), const Color(0xFF5B5BD6), reason: 'primary — #5B5BD6');
    expect(light.filledButtonTheme.style?.foregroundColor?.resolve({}), ColorTokens.white, reason: 'белый текст на фиолетовом');
    expect(light.outlinedButtonTheme.style?.backgroundColor?.resolve({}), const Color(0xFFEAECF2), reason: 'secondary — inset/ink');
    expect(light.outlinedButtonTheme.style?.foregroundColor?.resolve({}), const Color(0xFF333333));
    expect(light.textButtonTheme.style?.foregroundColor?.resolve({}), const Color(0xFF4646B8), reason: 'ссылки — accentHover');
    expect(light.inputDecorationTheme.fillColor, ColorTokens.light.neutralSoft);
    expect((light.inputDecorationTheme.border as OutlineInputBorder).borderSide, BorderSide.none);
    expect((light.inputDecorationTheme.focusedBorder as OutlineInputBorder).borderSide.color, ColorTokens.light.accent, reason: 'фокус — обводка accent');
  });

  testWidgets('danger button: inset background with critical text (C-Tokens «Опасное действие»)', (tester) async {
    late ButtonStyle style;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Builder(builder: (context) {
        style = AppButtons.danger(context);
        return const SizedBox();
      }),
    ));
    expect(style.backgroundColor?.resolve({}), const Color(0xFFEAECF2));
    expect(style.foregroundColor?.resolve({}), const Color(0xFF9F1239));
  });

  test('tokens match design/tokens.json shared with the web client', () {
    final json = jsonDecode(File('../../design/tokens.json').readAsStringSync()) as Map<String, dynamic>;
    Color hex(String value) => Color(int.parse('FF${value.substring(1)}', radix: 16));
    for (final (name, colors) in [('light', ColorTokens.light), ('dark', ColorTokens.dark)]) {
      final expected = json[name] as Map<String, dynamic>;
      final actual = {
        'surface': colors.surface, 'card': colors.card, 'ink': colors.ink, 'muted': colors.muted, 'faint': colors.faint,
        'hairline': colors.hairline, 'accent': colors.accent, 'accentHover': colors.accentHover, 'accentSoft': colors.accentSoft,
        'neutralSoft': colors.neutralSoft, 'ok': colors.ok, 'okSoft': colors.okSoft, 'warn': colors.warn, 'warnSoft': colors.warnSoft,
        'warnStrong': colors.warnStrong, 'danger': colors.danger, 'dangerSoft': colors.dangerSoft, 'info': colors.info, 'infoSoft': colors.infoSoft,
        'ai': colors.ai, 'aiSoft': colors.aiSoft, 'benchSoft': colors.benchSoft,
        'map1': colors.map1, 'map2': colors.map2, 'map3': colors.map3, 'map4': colors.map4, 'map5': colors.map5,
      };
      expect(actual.keys.toSet(), expected.keys.toSet(), reason: '$name: каждый ключ tokens.json есть в ColorTokens, и наоборот');
      for (final entry in actual.entries) {
        expect(entry.value, hex(expected[entry.key] as String), reason: '$name.${entry.key}');
      }
    }
    expect(AppSpacing.lg, (json['space'] as Map<String, dynamic>)['lg']);
    expect((json['font'] as Map<String, dynamic>)['family'], AppType.family);
    expect((json['font'] as Map<String, dynamic>)['baseSize'], AppTheme.light().textTheme.bodyMedium?.fontSize);
  });

  test('tones follow Palette C chips: ML #D1FAFF/#333, formula inset/ink-2, AI lavender/#4646B8, current, amber risk', () {
    final tones = AppTones.from(ColorTokens.light);
    expect(tones.ml.fg, const Color(0xFF333333));
    expect(tones.ml.bg, const Color(0xFFD1FAFF));
    expect(tones.formula.fg, const Color(0xFF535768));
    expect(tones.formula.bg, const Color(0xFFEAECF2));
    expect(tones.ai.fg, const Color(0xFF4646B8));
    expect(tones.ai.bg, const Color(0xFFEDDFF7));
    expect(tones.accent.fg, const Color(0xFF4646B8), reason: '«текущая»');
    expect(tones.accent.bg, const Color(0xFFE7ECFF));
    expect(tones.ok.fg, const Color(0xFF2A5C4E));
    expect(tones.ok.bg, const Color(0xFFDDF7C8));
    expect(tones.warn.fg, const Color(0xFF9A5A00), reason: 'риск и аномалии — янтарные, не фиолетовые');
    expect(tones.warn.bg, const Color(0xFFFFE9C7));
    expect(tones.danger.fg, const Color(0xFF9F1239));
    expect(tones.danger.bg, const Color(0xFFFFE0E6));
    expect(tones.bench.bg, ColorTokens.light.benchSoft);
    expect(tones.info.bg, ColorTokens.light.infoSoft);
    final mid = tones.lerp(AppTones.from(ColorTokens.dark), 0.5);
    expect(mid.ml.fg, isNot(tones.ml.fg));
  });
}
