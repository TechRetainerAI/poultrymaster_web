import 'package:flutter/material.dart';

/// Palette and helpers for the web's mobile view.
///
/// Taken from the running site on a phone: a dark slate app header carrying the
/// VisibilityCore wordmark, a slightly lighter company bar beneath it, white
/// stat cards with coloured icon tiles, and a dark "All pages" sheet with
/// orange section headers.
class WebMobile {
  const WebMobile._();

  // Chrome
  static const header = Color(0xFF111827); // slate-900-ish app bar
  static const companyBar = Color(0xFF1E293B); // slate-800 selector strip
  static const sheet = Color(0xFF1E293B); // "All pages" sheet
  static const sheetField = Color(0xFF0F172A); // its search input
  static const orange = Color(0xFFF97316); // section headers, bottom bar

  // Card text
  static const cardLabel = Color(0xFF64748B); // slate-500 uppercase label
  static const cardValue = Color(0xFF0F172A); // slate-900 figure
  static const cardHint = Color(0xFF94A3B8); // slate-400 description

  /// The icon-tile colours the dashboard cycles through, in the order the web
  /// uses them.
  static const tileColors = <Color>[
    Color(0xFF3B82F6), // blue-500
    Color(0xFF22C55E), // green-500
    Color(0xFFF97316), // orange-500
    Color(0xFFA855F7), // purple-500
    Color(0xFF22C55E), // green-500
    Color(0xFF3B82F6), // blue-500
    Color(0xFFA855F7), // purple-500
    Color(0xFF6366F1), // indigo-500
  ];

  static Color tile(int i) => tileColors[i % tileColors.length];
}

/// Money as the web writes it on these screens: `GHC 360,793.50`.
///
/// The web uses the GHC code here rather than the ₵ symbol — worth matching,
/// because the two look quite different at a glance on a dashboard.
String ghc(num value) {
  final s = value.abs().toStringAsFixed(2);
  final parts = s.split('.');
  final digits = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  final sign = value < 0 ? '-' : '';
  return 'GHC $sign${buf.toString()}.${parts[1]}';
}
