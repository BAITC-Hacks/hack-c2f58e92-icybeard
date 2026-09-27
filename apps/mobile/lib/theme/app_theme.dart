import 'package:flutter/material.dart';

import 'tokens.dart';
import 'tones.dart';
import 'typography.dart';

/// Светлая и тёмная темы из одних токенов Палитры C: холст ground, белые карточки radius 16 без рамки и тени,
/// primary-кнопки 52 px фиолетовый/белый, secondary — inset/ink, опасное действие — inset/critical ([AppButtons]),
/// TextButton и ссылки — accentHover, поля на inset-фоне без рамки (в фокусе — обводка 2 px accent), чипы radius 8.
/// Компонентные темы задают вид один раз — экраны не несут собственных стилей и не трогают `Colors.*`.
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
    final radius = BorderRadius.circular(AppRadius.md);
    final noBorder = OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none);
    OutlineInputBorder ring(Color color) => OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: color, width: 2));
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
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
      // secondary-кнопка: inset-фон, текст ink, без рамки (OutlinedButton и FilledButton.tonal выглядят одинаково)
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonSize,
          padding: buttonPadding,
          backgroundColor: c.neutralSoft,
          foregroundColor: c.ink,
          disabledForegroundColor: c.muted,
          side: BorderSide.none,
          shape: buttonShape,
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.accentHover,
          disabledForegroundColor: c.muted,
          textStyle: text.titleSmall,
          shape: buttonShape,
          minimumSize: const Size(0, AppSizes.compact),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: c.ink)),
      chipTheme: ChipThemeData(
        backgroundColor: c.neutralSoft,
        selectedColor: c.accentSoft,
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
        focusedBorder: ring(c.accent),
        disabledBorder: noBorder,
        errorBorder: ring(c.danger),
        focusedErrorBorder: ring(c.danger),
        // label живёт над полем (FieldLabel); labelText, если остался, ведёт себя как плейсхолдер
        floatingLabelBehavior: FloatingLabelBehavior.never,
        labelStyle: text.bodyMedium?.copyWith(color: c.muted),
        helperStyle: text.labelSmall,
        errorStyle: text.labelSmall?.copyWith(color: c.danger),
        hintStyle: text.bodyMedium?.copyWith(color: c.muted),
        prefixIconColor: c.muted,
        suffixIconColor: c.muted,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: c.card,
          selectedBackgroundColor: c.accent,
          selectedForegroundColor: onAccent,
          foregroundColor: c.ink,
          side: BorderSide.none,
          textStyle: text.labelMedium?.copyWith(fontSize: 14),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? c.accent : ColorTokens.transparent),
        checkColor: WidgetStatePropertyAll(onAccent),
        side: BorderSide(color: c.muted, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xs)),
      ),
      dividerTheme: DividerThemeData(color: c.hairline, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
        iconColor: c.muted,
        titleTextStyle: text.row,
        subtitleTextStyle: text.rowDetail.copyWith(color: c.muted),
        selectedColor: c.accentHover,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.ink,
        contentTextStyle: text.bodySmall?.copyWith(color: c.surface, fontSize: 15),
        actionTextColor: c.accentSoft,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent, linearTrackColor: c.neutralSoft),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.card,
        surfaceTintColor: ColorTokens.transparent,
        dragHandleColor: c.hairline,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg))),
      ),
      extensions: [AppTones.from(c), AppPalette(c)],
    );
  }
}

/// Кнопки вне темы по доске C-Tokens: «опасное действие» — inset-фон и critical-текст; малая кнопка 36 px (14/500)
/// в состояниях экрана и строках списка. Цвета — из палитры темы, без литералов.
abstract final class AppButtons {
  static ButtonStyle danger(BuildContext context, {bool small = false}) {
    final c = AppPalette.of(context);
    return OutlinedButton.styleFrom(
      backgroundColor: c.neutralSoft,
      foregroundColor: c.danger,
      side: BorderSide.none,
      minimumSize: small ? const Size(0, AppSizes.small) : const Size.fromHeight(AppSizes.control),
      padding: EdgeInsets.symmetric(horizontal: small ? 14 : AppSpacing.xl),
      textStyle: small ? _smallText(context) : null,
    );
  }

  /// Малая кнопка: primary (фиолетовая) для FilledButton, secondary (inset) для OutlinedButton.
  static ButtonStyle small(BuildContext context) => ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, AppSizes.small)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: AppSpacing.lg)),
        textStyle: WidgetStatePropertyAll(_smallText(context)),
      );

  static TextStyle? _smallText(BuildContext context) => Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 14);
}
