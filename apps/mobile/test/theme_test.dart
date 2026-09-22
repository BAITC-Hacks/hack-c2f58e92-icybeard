import 'dart:convert';
import 'dart:io';

import 'package:darumen/theme/app_theme.dart';
import 'package:darumen/theme/tokens.dart';
import 'package:darumen/theme/tones.dart';
import 'package:darumen/theme/typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('light and dark themes are built from the same tokens with Onest and tabular numerals', () {
    final light = AppTheme.light();
    final dark = AppTheme.dark();
    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(light.textTheme.bodyMedium?.fontFamily, AppType.family);
    expect(light.textTheme.bodyMedium?.fontSize, 16, reason: 'базовый кегль 16 — пожилые пользователи');
    expect(light.colorScheme.primary, AppColors.light.accent);
    expect(dark.colorScheme.primary, AppColors.dark.accent);
    expect(light.scaffoldBackgroundColor, const Color(0xFFFDFDFB));
    expect(AppType.numeric.fontFeatures, contains(const FontFeature.tabularFigures()));
    expect(light.extension<AppTones>(), isNotNull);
    expect(dark.extension<AppPalette>()?.colors.surface, AppColors.dark.surface);
    expect(light.cardTheme.elevation, 0, reason: 'карточки без тени, только hairline');
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
      };
      for (final entry in actual.entries) {
        expect(entry.value, hex(expected[entry.key] as String), reason: '$name.${entry.key}');
      }
    }
    expect(AppSpacing.lg, (json['space'] as Map<String, dynamic>)['lg']);
  });

  test('tones map origin kinds to accent, neutral and warn pairs', () {
    final tones = AppTones.from(AppColors.light);
    expect(tones.ml.fg, AppColors.light.accent);
    expect(tones.formula.bg, AppColors.light.neutralSoft);
    expect(tones.ai.fg, AppColors.light.warn);
    expect(tones.danger.bg, AppColors.light.dangerSoft);
    final mid = tones.lerp(AppTones.from(AppColors.dark), 0.5);
    expect(mid.ml.fg, isNot(tones.ml.fg));
  });
}
