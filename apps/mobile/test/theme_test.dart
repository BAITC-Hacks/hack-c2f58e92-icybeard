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
    expect(light.colorScheme.primary, AppColors.light.ink, reason: 'primary-кнопки — ink, не коралл');
    expect(dark.colorScheme.primary, AppColors.dark.ink);
    expect(light.scaffoldBackgroundColor, const Color(0xFFF4F6F0));
    expect(AppType.numeric.fontFeatures, contains(const FontFeature.tabularFigures()));
    expect(light.extension<AppTones>(), isNotNull);
    expect(dark.extension<AppPalette>()?.colors.surface, AppColors.dark.surface);
    expect(light.cardTheme.elevation, 0, reason: 'карточки без тени');
    expect((light.cardTheme.shape as RoundedRectangleBorder).side, BorderSide.none, reason: 'карточки без рамки');
    expect(light.filledButtonTheme.style?.minimumSize?.resolve({})?.height, 52);
    expect(light.filledButtonTheme.style?.backgroundColor?.resolve({}), AppColors.light.ink);
    expect(light.outlinedButtonTheme.style?.backgroundColor?.resolve({}), AppColors.light.neutralSoft, reason: 'secondary — soft/ink');
    expect(light.inputDecorationTheme.fillColor, AppColors.light.neutralSoft);
    expect((light.inputDecorationTheme.border as OutlineInputBorder).borderSide, BorderSide.none);
  });

  test('tokens match design/tokens.json shared with the web client', () {
    final json = jsonDecode(File('../../design/tokens.json').readAsStringSync()) as Map<String, dynamic>;
    Color hex(String value) => Color(int.parse('FF${value.substring(1)}', radix: 16));
    for (final (name, colors) in [('light', AppColors.light), ('dark', AppColors.dark)]) {
      final expected = json[name] as Map<String, dynamic>;
      final actual = {
        'surface': colors.surface, 'card': colors.card, 'ink': colors.ink, 'muted': colors.muted, 'faint': colors.faint,
        'hairline': colors.hairline, 'accent': colors.accent, 'accentSoft': colors.accentSoft, 'ok': colors.ok, 'okSoft': colors.okSoft,
        'warn': colors.warn, 'warnSoft': colors.warnSoft, 'danger': colors.danger, 'dangerSoft': colors.dangerSoft, 'neutralSoft': colors.neutralSoft,
        'benchSoft': colors.benchSoft,
      };
      for (final entry in actual.entries) {
        expect(entry.value, hex(expected[entry.key] as String), reason: '$name.${entry.key}');
      }
    }
    expect(AppSpacing.lg, (json['space'] as Map<String, dynamic>)['lg']);
    expect((json['font'] as Map<String, dynamic>)['family'], AppType.family);
    expect((json['font'] as Map<String, dynamic>)['baseSize'], AppTheme.light().textTheme.bodyMedium?.fontSize);
  });

  test('tones follow the quiet-clinic mapping: ML and AI chips carry ink text, bench chip on bench-wash', () {
    final tones = AppTones.from(AppColors.light);
    expect(tones.ml.fg, AppColors.light.ink);
    expect(tones.ml.bg, AppColors.light.accentSoft);
    expect(tones.formula.fg, AppColors.light.muted);
    expect(tones.formula.bg, AppColors.light.neutralSoft);
    expect(tones.ai.fg, AppColors.light.ink);
    expect(tones.ai.bg, AppColors.light.dangerSoft);
    expect(tones.warn.fg, AppColors.light.danger);
    expect(tones.danger.bg, AppColors.light.dangerSoft);
    expect(tones.bench.bg, AppColors.light.benchSoft);
    expect(tones.accent.fg, AppColors.light.accent);
    final mid = tones.lerp(AppTones.from(AppColors.dark), 0.5);
    expect(mid.ml.fg, isNot(tones.ml.fg));
  });
}
