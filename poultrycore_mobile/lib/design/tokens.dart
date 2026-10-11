import 'package:flutter/material.dart';

/// Design tokens ported from the web app's `app/globals.css`.
///
/// The web defines these in OKLCH (shadcn/ui neutral theme). Flutter has no
/// OKLCH `Color`, so each value was converted to sRGB rather than eyeballed —
/// these hexes are the same pixels the browser renders.
///
/// Keep this file in sync with `poultrycore-main/app/globals.css`. If a token
/// changes there, convert and change it here; do not approximate.
class Dim {
  const Dim._();

  // --radius: 0.625rem  →  10px, with shadcn's derived steps.
  static const double radius = 10;
  static const double radiusSm = 6; // radius - 4
  static const double radiusMd = 8; // radius - 2
  static const double radiusLg = 10; // radius
  static const double radiusXl = 14; // radius + 4
}

/// Light theme values (`:root`).
class LightTokens {
  const LightTokens._();

  static const background = Color(0xFFFFFFFF);
  static const foreground = Color(0xFF0A0A0A);
  static const card = Color(0xFFFFFFFF);
  static const cardForeground = Color(0xFF0A0A0A);
  static const popover = Color(0xFFFFFFFF);
  static const popoverForeground = Color(0xFF0A0A0A);
  static const primary = Color(0xFF171717);
  static const primaryForeground = Color(0xFFFAFAFA);
  static const secondary = Color(0xFFF5F5F5);
  static const secondaryForeground = Color(0xFF171717);
  static const muted = Color(0xFFF5F5F5);
  // Darker than the web's #737373 so secondary text never reads as disabled.
  static const mutedForeground = Color(0xFF525252);
  static const accent = Color(0xFFF5F5F5);
  static const accentForeground = Color(0xFF171717);
  // The live site ships #e40014 as the hex fallback for
  // oklch(0.577 0.245 27.325). A direct OKLCH→sRGB conversion gives #e7000b —
  // the browser clips this out-of-gamut colour slightly differently. Use what
  // visibilitycore.com actually paints, not the mathematical conversion.
  static const destructive = Color(0xFFE40014);
  static const destructiveForeground = Color(0xFFFAFAFA);
  static const border = Color(0xFFE5E5E5);
  static const input = Color(0xFFE5E5E5);
  static const ring = Color(0xFFA1A1A1);
  static const sidebar = Color(0xFFFAFAFA);

  static const chart = <Color>[
    Color(0xFFF54900),
    Color(0xFF009689),
    Color(0xFF104E64),
    Color(0xFFFFB900),
    Color(0xFFFE9A00),
  ];
}

/// Dark theme values (`.dark`).
class DarkTokens {
  const DarkTokens._();

  static const background = Color(0xFF0A0A0A);
  static const foreground = Color(0xFFFAFAFA);
  static const card = Color(0xFF0A0A0A);
  static const cardForeground = Color(0xFFFAFAFA);
  static const popover = Color(0xFF0A0A0A);
  static const popoverForeground = Color(0xFFFAFAFA);
  static const primary = Color(0xFFFAFAFA);
  static const primaryForeground = Color(0xFF171717);
  static const secondary = Color(0xFF262626);
  static const secondaryForeground = Color(0xFFFAFAFA);
  static const muted = Color(0xFF262626);
  static const mutedForeground = Color(0xFFA1A1A1);
  static const accent = Color(0xFF262626);
  static const accentForeground = Color(0xFFFAFAFA);
  static const destructive = Color(0xFF82181A);
  static const destructiveForeground = Color(0xFFFAFAFA);
  static const border = Color(0xFF262626);
  static const input = Color(0xFF262626);
  static const ring = Color(0xFF525252);
  static const sidebar = Color(0xFF171717);

  static const chart = <Color>[
    Color(0xFF1447E6),
    Color(0xFF00BC7D),
    Color(0xFFFE9A00),
    Color(0xFFAD46FF),
    Color(0xFFFF2056),
  ];
}

/// The semantic tokens the web uses that Material's [ColorScheme] has no slot
/// for. Read them via `context.tokens`.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.muted,
    required this.mutedForeground,
    required this.border,
    required this.input,
    required this.ring,
    required this.card,
    required this.cardForeground,
    required this.accent,
    required this.accentForeground,
    required this.destructive,
    required this.destructiveForeground,
    required this.sidebar,
    required this.chart,
  });

  final Color muted;
  final Color mutedForeground;
  final Color border;
  final Color input;
  final Color ring;
  final Color card;
  final Color cardForeground;
  final Color accent;
  final Color accentForeground;
  final Color destructive;
  final Color destructiveForeground;
  final Color sidebar;
  final List<Color> chart;

  static const light = AppTokens(
    muted: LightTokens.muted,
    mutedForeground: LightTokens.mutedForeground,
    border: LightTokens.border,
    input: LightTokens.input,
    ring: LightTokens.ring,
    card: LightTokens.card,
    cardForeground: LightTokens.cardForeground,
    accent: LightTokens.accent,
    accentForeground: LightTokens.accentForeground,
    destructive: LightTokens.destructive,
    destructiveForeground: LightTokens.destructiveForeground,
    sidebar: LightTokens.sidebar,
    chart: LightTokens.chart,
  );

  static const dark = AppTokens(
    muted: DarkTokens.muted,
    mutedForeground: DarkTokens.mutedForeground,
    border: DarkTokens.border,
    input: DarkTokens.input,
    ring: DarkTokens.ring,
    card: DarkTokens.card,
    cardForeground: DarkTokens.cardForeground,
    accent: DarkTokens.accent,
    accentForeground: DarkTokens.accentForeground,
    destructive: DarkTokens.destructive,
    destructiveForeground: DarkTokens.destructiveForeground,
    sidebar: DarkTokens.sidebar,
    chart: DarkTokens.chart,
  );

  @override
  AppTokens copyWith({
    Color? muted,
    Color? mutedForeground,
    Color? border,
    Color? input,
    Color? ring,
    Color? card,
    Color? cardForeground,
    Color? accent,
    Color? accentForeground,
    Color? destructive,
    Color? destructiveForeground,
    Color? sidebar,
    List<Color>? chart,
  }) =>
      AppTokens(
        muted: muted ?? this.muted,
        mutedForeground: mutedForeground ?? this.mutedForeground,
        border: border ?? this.border,
        input: input ?? this.input,
        ring: ring ?? this.ring,
        card: card ?? this.card,
        cardForeground: cardForeground ?? this.cardForeground,
        accent: accent ?? this.accent,
        accentForeground: accentForeground ?? this.accentForeground,
        destructive: destructive ?? this.destructive,
        destructiveForeground: destructiveForeground ?? this.destructiveForeground,
        sidebar: sidebar ?? this.sidebar,
        chart: chart ?? this.chart,
      );

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    return AppTokens(
      muted: Color.lerp(muted, other.muted, t)!,
      mutedForeground: Color.lerp(mutedForeground, other.mutedForeground, t)!,
      border: Color.lerp(border, other.border, t)!,
      input: Color.lerp(input, other.input, t)!,
      ring: Color.lerp(ring, other.ring, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardForeground: Color.lerp(cardForeground, other.cardForeground, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentForeground: Color.lerp(accentForeground, other.accentForeground, t)!,
      destructive: Color.lerp(destructive, other.destructive, t)!,
      destructiveForeground:
          Color.lerp(destructiveForeground, other.destructiveForeground, t)!,
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
      chart: t < .5 ? chart : other.chart,
    );
  }
}

extension TokensOf on BuildContext {
  AppTokens get tokens =>
      Theme.of(this).extension<AppTokens>() ?? AppTokens.light;
}
