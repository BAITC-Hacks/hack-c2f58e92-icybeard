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
    expect(light.textTheme.bodyMedium?.fontSize, 13.5, reason: 'тело 13.5 (синяя гамма плотнее)');
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

  test('tokens match handoff/tokens.json of the blue design canvas', () {
    Color hex(String value) => Color(int.parse('FF${value.substring(1)}', radix: 16));
    // Значения из project/handoff/tokens.json (light утверждён, dark — предложение);
    // производные роли: info = accent-strong/accent-soft, метки происхождения — surface-muted/text-secondary.
    final expected = {
      'light': {
        'surface': '#F5F6F8', 'card': '#FFFFFF', 'ink': '#1B2440', 'muted': '#48536D', 'faint': '#D3DCEC',
        'hairline': '#E1E8F5', 'accent': '#2F6FE4', 'accentHover': '#1E4FB8', 'accentSoft': '#DEEAFD',
        'accentSubtle': '#EAF1FE', 'accentLine': '#C9DBFA', 'link': '#2F6FE4', 'neutralSoft': '#E8EEFA',
        'surfaceSunken': '#EEF3FC', 'surfaceHover': '#F4F7FD', 'surfaceInfo': '#F6F8FC', 'toggleOff': '#DCE4F2',
        'ok': '#2A5C4E', 'okSoft': '#DDF7C8', 'warn': '#9A5A00', 'warnSoft': '#FFE9C7', 'warnStrong': '#B45309',
        'danger': '#9F1239', 'dangerSoft': '#FFE0E6', 'dangerStrong': '#D6395E',
        'info': '#1E4FB8', 'infoSoft': '#DEEAFD', 'ai': '#48536D', 'aiSoft': '#E8EEFA', 'benchSoft': '#E8EEFA',
        'barNeutral': '#B4C0D8', 'map1': '#8CC152', 'map3': '#F2A93B', 'map5': '#D6395E',
        'borderSoft': '#E6ECF7', 'textMuted': '#76819A', 'textFaint': '#9FA9BF', 'okLine': '#B9EBA0', 'okSoftText': '#5C8A6E',
      },
      'dark': {
        'surface': '#0D1526', 'card': '#141E33', 'ink': '#E7EDF8', 'muted': '#B5C0D6', 'faint': '#33446B',
        'hairline': '#27365A', 'accent': '#2F6FE4', 'accentHover': '#A9C6FF', 'accentSoft': '#1B3263',
        'accentSubtle': '#172A50', 'accentLine': '#2C4A85', 'link': '#8DB4FF', 'neutralSoft': '#1F2C48',
        'surfaceSunken': '#1A2640', 'surfaceHover': '#1A2640', 'surfaceInfo': '#172238', 'toggleOff': '#33446B',
        'ok': '#8FDDB0', 'okSoft': '#16382B', 'warn': '#F4C574', 'warnSoft': '#3A2A10', 'warnStrong': '#E59A3A',
        'danger': '#FF9FB3', 'dangerSoft': '#3F1824', 'dangerStrong': '#F0607F',
        'info': '#A9C6FF', 'infoSoft': '#1B3263', 'ai': '#B5C0D6', 'aiSoft': '#1F2C48', 'benchSoft': '#1F2C48',
        'barNeutral': '#3A4A6E', 'map1': '#7DB548', 'map3': '#E39B30', 'map5': '#E04D6E',
        'borderSoft': '#22304F', 'textMuted': '#8D9AB5', 'textFaint': '#66738F', 'okLine': '#2F6B4F', 'okSoftText': '#7CC39B',
      },
    };
    for (final (name, colors) in [('light', ColorTokens.light), ('dark', ColorTokens.dark)]) {
      final actual = {
        'surface': colors.surface, 'card': colors.card, 'ink': colors.ink, 'muted': colors.muted, 'faint': colors.faint,
        'hairline': colors.hairline, 'accent': colors.accent, 'accentHover': colors.accentHover, 'accentSoft': colors.accentSoft,
        'accentSubtle': colors.accentSubtle, 'accentLine': colors.accentLine, 'link': colors.link, 'neutralSoft': colors.neutralSoft,
        'surfaceSunken': colors.surfaceSunken, 'surfaceHover': colors.surfaceHover, 'surfaceInfo': colors.surfaceInfo,
        'toggleOff': colors.toggleOff,
        'ok': colors.ok, 'okSoft': colors.okSoft, 'warn': colors.warn, 'warnSoft': colors.warnSoft, 'warnStrong': colors.warnStrong,
        'danger': colors.danger, 'dangerSoft': colors.dangerSoft, 'dangerStrong': colors.dangerStrong,
        'info': colors.info, 'infoSoft': colors.infoSoft, 'ai': colors.ai, 'aiSoft': colors.aiSoft, 'benchSoft': colors.benchSoft,
        'barNeutral': colors.barNeutral, 'map1': colors.map1, 'map3': colors.map3, 'map5': colors.map5,
        'borderSoft': colors.borderSoft, 'textMuted': colors.textMuted, 'textFaint': colors.textFaint,
        'okLine': colors.okLine, 'okSoftText': colors.okSoftText,
      };
      final want = expected[name]!;
      expect(actual.keys.toSet(), want.keys.toSet(), reason: '$name: проверяются все токены');
      for (final entry in actual.entries) {
        expect(entry.value, hex(want[entry.key]!), reason: '$name.${entry.key}');
      }
      expect(colors.heroGradient.length, 4, reason: '$name: градиент 4 остановки (0/30/55/100 %)');
    }
    expect(ColorTokens.light.heroGradient.first, const Color(0xFFE8F0FE));
    expect(ColorTokens.dark.heroGradient.first, const Color(0xFF0F1B34));
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
    final mid = tones.lerp(AppTones.from(ColorTokens.dark), 0.5);
    expect(mid.ml.fg, isNot(tones.ml.fg));
  });
}
