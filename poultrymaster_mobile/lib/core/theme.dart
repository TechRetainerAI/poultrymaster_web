import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// PoultryMaster brand: deep forest green + egg-yolk amber on warm cream.
/// Headings use Sora, body uses Plus Jakarta Sans.
class AppColors {
  static const Color primary = Color(0xFF1E6B3C);
  static const Color primaryDark = Color(0xFF144C2A);
  static const Color accent = Color(0xFFF2A93B);
  static const Color cream = Color(0xFFF8F6F0);
  static const Color surface = Colors.white;
  static const Color ink = Color(0xFF1C2520);
  static const Color inkMuted = Color(0xFF60706A);
  static const Color danger = Color(0xFFC64533);
  static const Color info = Color(0xFF2E6FA8);
  static const Color success = Color(0xFF2E8B57);
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.accent,
      error: AppColors.danger,
      surface: AppColors.surface,
    ),
    scaffoldBackgroundColor: AppColors.cream,
  );

  final body = GoogleFonts.plusJakartaSansTextTheme(base.textTheme)
      .apply(bodyColor: AppColors.ink, displayColor: AppColors.ink);
  final textTheme = body.copyWith(
    displayLarge: GoogleFonts.sora(textStyle: body.displayLarge, fontWeight: FontWeight.w700),
    displayMedium: GoogleFonts.sora(textStyle: body.displayMedium, fontWeight: FontWeight.w700),
    displaySmall: GoogleFonts.sora(textStyle: body.displaySmall, fontWeight: FontWeight.w700),
    headlineLarge: GoogleFonts.sora(textStyle: body.headlineLarge, fontWeight: FontWeight.w700),
    headlineMedium: GoogleFonts.sora(textStyle: body.headlineMedium, fontWeight: FontWeight.w700),
    headlineSmall: GoogleFonts.sora(textStyle: body.headlineSmall, fontWeight: FontWeight.w700),
    titleLarge: GoogleFonts.sora(textStyle: body.titleLarge, fontWeight: FontWeight.w600),
    titleMedium: GoogleFonts.sora(textStyle: body.titleMedium, fontWeight: FontWeight.w600),
  );

  return base.copyWith(
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.cream,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge?.copyWith(fontSize: 20),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
      ),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.10)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.10)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
      ),
      labelStyle: textTheme.bodyMedium?.copyWith(color: AppColors.inkMuted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: textTheme.titleMedium?.copyWith(fontSize: 16, color: Colors.white),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: AppColors.primary, width: 1.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: textTheme.titleMedium?.copyWith(fontSize: 16),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.primary.withValues(alpha: 0.12),
      height: 68,
      labelTextStyle: WidgetStatePropertyAll(
        textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: DividerThemeData(color: Colors.black.withValues(alpha: 0.06)),
  );
}
