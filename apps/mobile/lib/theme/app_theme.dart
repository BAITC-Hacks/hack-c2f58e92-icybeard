import 'package:flutter/material.dart';

import 'tokens.dart';
import 'tones.dart';
import 'typography.dart';

/// Светлая и тёмная темы из одних токенов синей гаммы: рабочие экраны на `--bg-page`, белые карточки radius 18
/// с тенью `--shadow-card`, все кнопки — pill h48 (primary — accent/белый 15/800, secondary — accent-subtle/
/// accent-strong, опасное действие — danger-bg/danger-text, [AppButtons]), TextButton и ссылки — `--link`,
/// поля белые с рамкой 1.5 px `--border` radius 12 (в фокусе — обводка 2 px accent), чипы — pill на
/// surface-sunken. Компонентные темы задают вид один раз — экраны не несут собственных стилей и не трогают `Colors.*`.
abstract final class AppTheme {
  static ThemeData light() => _build(ColorTokens.light, Brightness.light);

  static ThemeData dark() => _build(ColorTokens.dark, Brightness.dark);

  static ThemeData _build(ColorTokens c, Brightness brightness) {
    final onAccent = c.onAccent;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.accent,
      onPrimary: onAccent,
      primaryContainer: c.accentSoft,
      onPrimaryContainer: c.accentHover,
      secondary: c.accentHover,
      onSecondary: onAccent,
      secondaryContainer: c.neutralSoft,
      onSecondaryContainer: c.ink,
      tertiary: c.ok,
      onTertiary: onAccent,
      tertiaryContainer: c.okSoft,
      onTertiaryContainer: c.ok,
      error: c.danger,
      onError: onAccent,
      errorContainer: c.dangerSoft,
      onErrorContainer: c.danger,
      surface: c.surface,
      onSurface: c.ink,
      onSurfaceVariant: c.muted,
      outline: c.hairline,
      outlineVariant: c.hairline,
      surfaceContainerLowest: c.card,
      surfaceContainerLow: c.card,
      surfaceContainer: c.neutralSoft,
      surfaceContainerHigh: c.neutralSoft,
      surfaceContainerHighest: c.neutralSoft,
      inverseSurface: c.ink,
      onInverseSurface: c.surface,
      inversePrimary: c.accentSoft,
      shadow: ColorTokens.shadow,
      scrim: ColorTokens.scrim,
      surfaceTint: ColorTokens.transparent,
    );
    final text = AppType.textTheme(c);
    final fieldRadius = BorderRadius.circular(AppRadius.md);
    OutlineInputBorder line(Color color, {double width = 1.5}) =>
        OutlineInputBorder(borderRadius: fieldRadius, borderSide: BorderSide(color: color, width: width));
    const buttonShape = StadiumBorder();
    const buttonSize = Size.fromHeight(AppSizes.control);
    const buttonPadding = EdgeInsets.symmetric(horizontal: AppSpacing.xl);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.surface,
      canvasColor: c.surface,
      fontFamily: AppType.family,
      textTheme: text,
      dividerColor: c.hairline,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: c.surface,
        surfaceTintColor: ColorTokens.transparent,
        foregroundColor: c.ink,
        centerTitle: false,
        titleTextStyle: text.headlineMedium,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: c.card,
        surfaceTintColor: ColorTokens.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: buttonSize,
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: text.labelLarge,
          backgroundColor: c.accent,
          foregroundColor: onAccent,
          disabledBackgroundColor: c.neutralSoft,
          disabledForegroundColor: c.muted,
        ),
      ),
      // secondary-кнопка: pill accent-subtle/accent-strong без рамки (OutlinedButton и FilledButton.tonal одинаковы)
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonSize,
          padding: buttonPadding,
          backgroundColor: c.accentSubtle,
          foregroundColor: c.accentHover,
          disabledForegroundColor: c.muted,
          side: BorderSide.none,
          shape: buttonShape,
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.link,
          disabledForegroundColor: c.muted,
          textStyle: text.titleSmall,
          shape: buttonShape,
          minimumSize: const Size(0, AppSizes.compact),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: c.ink)),
      chipTheme: ChipThemeData(
        backgroundColor: c.surfaceSunken,
        selectedColor: c.accentSoft,
        side: BorderSide.none,
        labelStyle: text.labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: AppSpacing.sm),
        shape: const StadiumBorder(),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.card,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 13),
        border: line(c.hairline),
        enabledBorder: line(c.hairline),
        focusedBorder: line(c.accent, width: 2),
        disabledBorder: line(c.hairline),
        errorBorder: line(c.dangerStrong),
        focusedErrorBorder: line(c.dangerStrong, width: 2),
        // label живёт над полем (FieldLabel); labelText, если остался, ведёт себя как плейсхолдер
        floatingLabelBehavior: FloatingLabelBehavior.never,
        labelStyle: text.bodyLarge?.copyWith(color: c.muted),
        helperStyle: text.labelSmall,
        errorStyle: text.labelSmall?.copyWith(color: c.danger),
        hintStyle: text.bodyLarge?.copyWith(color: c.muted),
        prefixIconColor: c.muted,
        suffixIconColor: c.muted,
      ),
      // сегмент: трек surface-muted, активный — белая пилюля с текстом ink
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: c.neutralSoft,
          selectedBackgroundColor: c.card,
          selectedForegroundColor: c.ink,
          foregroundColor: c.muted,
          side: BorderSide.none,
          textStyle: text.labelMedium,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? c.accent : ColorTokens.transparent),
        checkColor: WidgetStatePropertyAll(onAccent),
        side: BorderSide(color: c.faint, width: 1.5),
        // чекбокс radius 6 по components.md
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(ColorTokens.white),
        trackColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? c.accent : c.toggleOff),
        trackOutlineColor: const WidgetStatePropertyAll(ColorTokens.transparent),
      ),
      dividerTheme: DividerThemeData(color: c.hairline, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
        iconColor: c.muted,
        titleTextStyle: text.row,
        subtitleTextStyle: text.rowDetail.copyWith(color: c.muted),
        // выбранная опция списка (веб: surface-hover, текст остаётся --text, галочка accent рисуется в строке)
        selectedColor: c.ink,
        selectedTileColor: c.surfaceHover,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.ink,
        contentTextStyle: text.bodyMedium?.copyWith(color: c.surface),
        actionTextColor: c.accentSoft,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent, linearTrackColor: c.neutralSoft),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.card,
        surfaceTintColor: ColorTokens.transparent,
        dragHandleColor: c.faint,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card))),
      ),
      extensions: [AppTones.from(c), AppPalette(c)],
    );
  }
}

/// Кнопки вне темы по components.md: «опасное действие» — danger-bg/danger-text pill; малая кнопка 36 px
/// в состояниях экрана и строках списка. Цвета — из палитры темы, без литералов.
abstract final class AppButtons {
  static ButtonStyle danger(BuildContext context, {bool small = false}) {
    final c = AppPalette.of(context);
    return OutlinedButton.styleFrom(
      backgroundColor: c.dangerSoft,
      foregroundColor: c.danger,
      side: BorderSide.none,
      minimumSize: small ? const Size(0, AppSizes.small) : const Size.fromHeight(AppSizes.control),
      padding: EdgeInsets.symmetric(horizontal: small ? 14 : AppSpacing.xl),
      textStyle: small ? _smallText(context) : null,
    );
  }

  /// Малая кнопка: primary (синяя) для FilledButton, secondary (accent-subtle) для OutlinedButton.
  static ButtonStyle small(BuildContext context) => ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, AppSizes.small)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: AppSpacing.lg)),
        textStyle: WidgetStatePropertyAll(_smallText(context)),
      );

  static TextStyle? _smallText(BuildContext context) => Theme.of(context).textTheme.titleSmall;
}
