import 'package:flutter/material.dart';

import 'tokens.dart';
import 'tones.dart';
import 'typography.dart';

/// Светлая и тёмная темы из одних токенов: явная ColorScheme (без seed), плоский AppBar, карточки без тени с
/// hairline-границей, кнопки 48 px, NavigationBar с мягким индикатором. Компонентные темы задают вид один раз —
/// экраны не несут собственных стилей.
abstract final class AppTheme {
  static ThemeData light() => _build(AppColors.light, Brightness.light);

  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors c, Brightness brightness) {
    final onAccent = brightness == Brightness.light ? Colors.white : c.surface;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.accent,
      onPrimary: onAccent,
      primaryContainer: c.accentSoft,
      onPrimaryContainer: c.accent,
      secondary: c.muted,
      onSecondary: c.surface,
      secondaryContainer: c.neutralSoft,
      onSecondaryContainer: c.ink,
      tertiary: c.warn,
      onTertiary: onAccent,
      tertiaryContainer: c.warnSoft,
      onTertiaryContainer: c.warn,
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
      shadow: Colors.black,
      scrim: Colors.black54,
      surfaceTint: Colors.transparent,
    );
    final text = AppType.textTheme(c);
    final radius = BorderRadius.circular(AppRadius.md);
    final hairline = BorderSide(color: c.hairline);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.surface,
      canvasColor: c.surface,
      fontFamily: AppType.family,
      textTheme: text,
      dividerColor: c.hairline,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: c.ink,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: c.card,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: radius, side: hairline),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          foregroundColor: c.ink,
          side: hairline,
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: c.accent, textStyle: text.labelLarge),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.neutralSoft,
        selectedColor: c.accentSoft,
        side: hairline,
        labelStyle: text.labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        shape: const StadiumBorder(),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.card,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 14),
        border: OutlineInputBorder(borderRadius: radius, borderSide: hairline),
        enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: hairline),
        focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c.accent, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c.danger)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c.danger, width: 1.5)),
        labelStyle: text.bodySmall,
        helperStyle: text.labelSmall,
        hintStyle: text.bodyMedium?.copyWith(color: c.faint),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: c.accentSoft,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(color: states.contains(WidgetState.selected) ? c.accent : c.muted, size: 22),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelSmall!.copyWith(color: states.contains(WidgetState.selected) ? c.ink : c.muted),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: c.accentSoft,
          selectedForegroundColor: c.accent,
          foregroundColor: c.ink,
          side: hairline,
          textStyle: text.labelMedium,
        ),
      ),
      dividerTheme: DividerThemeData(color: c.hairline, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
        iconColor: c.muted,
        titleTextStyle: text.bodyLarge,
        subtitleTextStyle: text.bodySmall,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.ink,
        contentTextStyle: text.bodyMedium?.copyWith(color: c.surface),
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.card,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg))),
      ),
      extensions: [AppTones.from(c), AppPalette(c)],
    );
  }
}
