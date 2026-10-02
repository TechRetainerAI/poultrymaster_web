import 'package:flutter/material.dart';

import 'tokens.dart';

/// Flutter theme that reproduces the web app's shadcn/ui styling.
///
/// Metrics are taken from the web components, not invented:
///   button  h-9 (36px), px-4, rounded-md (8px), text-sm (14px), font-medium
///   input   h-9 (36px), px-3, 1px border-input, rounded-md, 3px focus ring
/// Tailwind's rem values are 16px-based, so h-9 = 2.25rem = 36px.
class AppTheme {
  const AppTheme._();

  /// Geist is the web's typeface. If the font files are not bundled, Flutter
  /// falls back to the platform sans — metrics stay correct either way because
  /// sizes and weights are set explicitly below.
  static const String? fontFamily = null;

  static ThemeData light() => _build(
        brightness: Brightness.light,
        tokens: AppTokens.light,
        background: LightTokens.background,
        foreground: LightTokens.foreground,
        primary: LightTokens.primary,
        onPrimary: LightTokens.primaryForeground,
        secondary: LightTokens.secondary,
        onSecondary: LightTokens.secondaryForeground,
      );

  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        tokens: AppTokens.dark,
        background: DarkTokens.background,
        foreground: DarkTokens.foreground,
        primary: DarkTokens.primary,
        onPrimary: DarkTokens.primaryForeground,
        secondary: DarkTokens.secondary,
        onSecondary: DarkTokens.secondaryForeground,
      );

  static ThemeData _build({
    required Brightness brightness,
    required AppTokens tokens,
    required Color background,
    required Color foreground,
    required Color primary,
    required Color onPrimary,
    required Color secondary,
    required Color onSecondary,
  }) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      secondary: secondary,
      onSecondary: onSecondary,
      error: tokens.destructive,
      onError: tokens.destructiveForeground,
      surface: background,
      onSurface: foreground,
      surfaceContainerHighest: tokens.muted,
      onSurfaceVariant: tokens.mutedForeground,
      outline: tokens.border,
      outlineVariant: tokens.border,
      shadow: const Color(0x14000000),
    );

    // rounded-md — shadcn derives this as radius - 2px.
    final mdRadius = BorderRadius.circular(Dim.radiusMd);

    OutlineInputBorder inputBorder(Color color, {double width = 1}) =>
        OutlineInputBorder(
          borderRadius: mdRadius,
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      dividerColor: tokens.border,
      extensions: [tokens],

      // text-sm is the web's default body size.
      textTheme: _textTheme(foreground, tokens.mutedForeground),

      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: foreground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        shape: Border(bottom: BorderSide(color: tokens.border)),
        titleTextStyle: TextStyle(
          color: foreground,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
      ),

      dividerTheme: DividerThemeData(
        color: tokens.border,
        thickness: 1,
        space: 1,
      ),

      cardTheme: CardThemeData(
        color: tokens.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Dim.radiusXl),
          side: BorderSide(color: tokens.border),
        ),
      ),

      // Web inputs are h-9 (36px), which is fine for a mouse but below the
      // 48dp touch-target floor Material and Android accessibility both set.
      //
      // Rather than invent a size, this follows the web's own precedent: its
      // login form — the one screen built for people typing on a phone —
      // uses h-12 (48px). So 48 is the product's own answer for touch input,
      // not a departure from it.
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        constraints: const BoxConstraints(minHeight: 48),
        border: inputBorder(tokens.input),
        enabledBorder: inputBorder(tokens.input),
        focusedBorder: inputBorder(tokens.ring),
        errorBorder: inputBorder(tokens.destructive),
        focusedErrorBorder: inputBorder(tokens.destructive),
        disabledBorder: inputBorder(tokens.input),
        hintStyle: TextStyle(color: tokens.mutedForeground, fontSize: 14),
        labelStyle: TextStyle(color: foreground, fontSize: 14),
        floatingLabelStyle: TextStyle(color: foreground, fontSize: 14),
        errorStyle: TextStyle(color: tokens.destructive, fontSize: 12.5),
        suffixIconColor: tokens.mutedForeground,
        prefixIconColor: tokens.mutedForeground,
      ),

      // Default variant: h-9 px-4, rounded-md, text-sm font-medium.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          elevation: 0,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          shape: RoundedRectangleBorder(borderRadius: mdRadius),
        ),
      ),

      // Secondary variant.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: secondary,
          foregroundColor: onSecondary,
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          elevation: 0,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          shape: RoundedRectangleBorder(borderRadius: mdRadius),
        ),
      ),

      // Outline variant.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          backgroundColor: background,
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          side: BorderSide(color: tokens.border),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          shape: RoundedRectangleBorder(borderRadius: mdRadius),
        ),
      ),

      // Ghost variant.
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: foreground,
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          shape: RoundedRectangleBorder(borderRadius: mdRadius),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: tokens.secondaryOrMuted,
        side: BorderSide(color: tokens.border),
        labelStyle: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w500, color: foreground),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: tokens.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Dim.radiusXl),
          side: BorderSide(color: tokens.border),
        ),
        titleTextStyle: TextStyle(
            color: foreground, fontSize: 17, fontWeight: FontWeight.w600),
        contentTextStyle: TextStyle(color: tokens.mutedForeground, fontSize: 14),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: tokens.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Dim.radiusXl)),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: foreground,
        contentTextStyle: TextStyle(color: background, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: mdRadius),
      ),

      listTileTheme: ListTileThemeData(
        iconColor: tokens.mutedForeground,
        textColor: foreground,
        shape: RoundedRectangleBorder(borderRadius: mdRadius),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? tokens.card : background),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? primary : tokens.muted),
        trackOutlineColor: WidgetStateProperty.all(tokens.border),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? primary : Colors.transparent),
        checkColor: WidgetStateProperty.all(onPrimary),
        side: BorderSide(color: tokens.border, width: 1),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(Dim.radiusSm - 2)),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: tokens.muted,
        circularTrackColor: tokens.muted,
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: foreground,
          borderRadius: BorderRadius.circular(Dim.radiusSm),
        ),
        textStyle: TextStyle(color: background, fontSize: 12),
      ),
    );
  }

  static TextTheme _textTheme(Color fg, Color muted) {
    // Tailwind scale: text-xs 12, text-sm 14, text-base 16, text-lg 18,
    // text-xl 20, text-2xl 24, text-3xl 30.
    return TextTheme(
      displaySmall: TextStyle(
          fontSize: 30, fontWeight: FontWeight.w700, color: fg, letterSpacing: -0.6),
      headlineMedium: TextStyle(
          fontSize: 24, fontWeight: FontWeight.w700, color: fg, letterSpacing: -0.4),
      headlineSmall: TextStyle(
          fontSize: 20, fontWeight: FontWeight.w600, color: fg, letterSpacing: -0.3),
      titleLarge: TextStyle(
          fontSize: 18, fontWeight: FontWeight.w600, color: fg, letterSpacing: -0.2),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: fg),
      titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: fg),
      bodyLarge: TextStyle(fontSize: 16, color: fg),
      bodyMedium: TextStyle(fontSize: 14, color: fg),
      bodySmall: TextStyle(fontSize: 12.5, color: muted),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: fg),
      labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: muted),
      labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: muted),
    );
  }
}

extension on AppTokens {
  /// shadcn uses `secondary` and `muted` interchangeably for chip surfaces;
  /// they resolve to the same value in this theme.
  Color get secondaryOrMuted => muted;
}
