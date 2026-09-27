import 'package:flutter/material.dart';

import 'tokens.dart';
import 'tones.dart';
import 'typography.dart';

/// Светлая и тёмная темы из одних токенов «Тихой клиники»: фон ground, белые карточки radius 16 без рамки и тени,
/// primary-кнопки 52 px ink/белый, secondary — soft/ink, поля 52 px на soft-фоне без рамки, чипы radius 8.
/// Компонентные темы задают вид один раз — экраны не несут собственных стилей и не трогают `Colors.*`.
abstract final class AppTheme {
  static ThemeData light() => _build(AppColors.light, Brightness.light);

  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors c, Brightness brightness) {
    final onInk = brightness == Brightness.light ? AppColors.white : c.surface;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.ink,
      onPrimary: onInk,
      primaryContainer: c.accentSoft,
      onPrimaryContainer: c.ink,
      secondary: c.accent,
      onSecondary: onInk,
      secondaryContainer: c.neutralSoft,
      onSecondaryContainer: c.ink,
      tertiary: c.ok,
      onTertiary: onInk,
      tertiaryContainer: c.okSoft,
      onTertiaryContainer: c.ok,
      error: c.danger,
      onError: onInk,
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
      shadow: AppColors.shadow,
      scrim: AppColors.scrim,
      surfaceTint: AppColors.transparent,
    );
    final text = AppType.textTheme(c);
    final radius = BorderRadius.circular(AppRadius.md);
    final noBorder = OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none);
    final buttonShape = RoundedRectangleBorder(borderRadius: radius);
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
        surfaceTintColor: AppColors.transparent,
        foregroundColor: c.ink,
        centerTitle: false,
        titleTextStyle: text.headlineMedium,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: c.card,
        surfaceTintColor: AppColors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: buttonSize,
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: text.labelLarge,
          backgroundColor: c.ink,
          foregroundColor: onInk,
          disabledBackgroundColor: c.neutralSoft,
          disabledForegroundColor: c.faint,
        ),
      ),
      // secondary-кнопка: soft-фон, текст ink, без рамки (OutlinedButton и FilledButton.tonal выглядят одинаково)
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonSize,
          padding: buttonPadding,
          backgroundColor: c.neutralSoft,
          foregroundColor: c.ink,
          disabledForegroundColor: c.faint,
          side: BorderSide.none,
          shape: buttonShape,
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.ink,
          disabledForegroundColor: c.faint,
          textStyle: text.titleSmall,
          shape: buttonShape,
          minimumSize: const Size(0, AppSizes.compact),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: c.ink)),
      chipTheme: ChipThemeData(
        backgroundColor: c.neutralSoft,
        selectedColor: c.ink,
        side: BorderSide.none,
        labelStyle: text.labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.xs),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.neutralSoft,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 14),
        border: noBorder,
        enabledBorder: noBorder,
        focusedBorder: noBorder,
        disabledBorder: noBorder,
        errorBorder: noBorder,
        focusedErrorBorder: noBorder,
        // label живёт над полем (FieldLabel); labelText, если остался, ведёт себя как плейсхолдер
        floatingLabelBehavior: FloatingLabelBehavior.never,
        labelStyle: text.bodyMedium?.copyWith(color: c.faint),
        helperStyle: text.labelSmall,
        errorStyle: text.labelSmall?.copyWith(color: c.danger),
        hintStyle: text.bodyMedium?.copyWith(color: c.faint),
        prefixIconColor: c.muted,
        suffixIconColor: c.muted,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: c.card,
          selectedBackgroundColor: c.ink,
          selectedForegroundColor: onInk,
          foregroundColor: c.ink,
          side: BorderSide.none,
          textStyle: text.labelMedium?.copyWith(fontSize: 14),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? c.ink : AppColors.transparent),
        checkColor: WidgetStatePropertyAll(onInk),
        side: BorderSide(color: c.muted, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xs)),
      ),
      dividerTheme: DividerThemeData(color: c.hairline, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
        iconColor: c.muted,
        titleTextStyle: text.row,
        subtitleTextStyle: text.rowDetail.copyWith(color: c.faint),
        selectedColor: c.ink,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.ink,
        contentTextStyle: text.bodySmall?.copyWith(color: onInk, fontSize: 15),
        actionTextColor: c.accent,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.ink, linearTrackColor: c.neutralSoft),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.card,
        surfaceTintColor: AppColors.transparent,
        dragHandleColor: c.hairline,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg))),
      ),
      extensions: [AppTones.from(c), AppPalette(c)],
    );
  }
}
