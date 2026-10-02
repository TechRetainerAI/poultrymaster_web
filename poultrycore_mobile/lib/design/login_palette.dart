import 'package:flutter/material.dart';

/// Palette for the sign-in screen.
///
/// The login page does **not** use the neutral shadcn theme the rest of the app
/// uses. It is a dark slate panel with orange accents, and on a phone it fills
/// the whole screen (`w-full lg:w-1/2`) — the marketing column beside it is
/// `hidden lg:flex`, so mobile correctly shows only this panel.
///
/// Values are Tailwind's, matching `app/login/page.tsx`.
class LoginPalette {
  const LoginPalette._();

  // Panel gradient: bg-gradient-to-br from-slate-800 to-slate-900
  static const slate800 = Color(0xFF1E293B);
  static const slate900 = Color(0xFF0F172A);

  static const slate700 = Color(0xFF334155); // input fill, at 50% alpha
  static const slate600 = Color(0xFF475569); // input border
  static const slate500 = Color(0xFF64748B); // checkbox + eye-button border
  static const slate400 = Color(0xFF94A3B8); // placeholder
  static const slate300 = Color(0xFFCBD5E1); // field icons, helper text
  static const slate200 = Color(0xFFE2E8F0); // eye-button icon

  // Accent
  static const orange500 = Color(0xFFF97316); // submit + focus ring
  static const orange600 = Color(0xFFEA580C); // submit hover
  static const orange400 = Color(0xFFFB923C); // links
  static const orange300 = Color(0xFFFDBA74); // org icon

  // Error block: bg-red-900/20, border-red-500/30, text-red-300
  static const red900 = Color(0xFF7F1D1D);
  static const red500 = Color(0xFFEF4444);
  static const red300 = Color(0xFFFCA5A5);

  static const LinearGradient panel = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [slate800, slate900],
  );
}
