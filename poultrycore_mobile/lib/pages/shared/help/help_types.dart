// The shape of a Help Center entry (lib/help/help-types.ts) and the Feature
// Guide tile (poultry-help-content.ts FeatureGuide), plus the category colours
// (CATEGORY_TONES / toneFor) as Flutter colours.

import 'package:flutter/material.dart';

import 'package:poultrycore_mobile/design/tone.dart';
enum HelpKind { faq, fix, term }

class HelpLink {
  const HelpLink(this.label, this.href);
  final String label;
  final String href;
}

class HelpEntry {
  const HelpEntry({
    required this.id,
    required this.kind,
    required this.category,
    required this.title,
    required this.body,
    this.keywords = const [],
    this.links = const [],
  });

  /// Stable; the web uses it as the #anchor of a shared link.
  final String id;
  final HelpKind kind;
  final String category;

  /// The question, the symptom, or the term.
  final String title;

  /// Paragraphs split by a blank line; "1. " lines are steps, "- " bullets.
  final String body;
  final List<String> keywords;
  final List<HelpLink> links;
}

class FeatureGuide {
  const FeatureGuide(this.icon, this.title, this.description, this.path, this.tone);
  final IconData icon;
  final String title, description, path;

  /// Tailwind colour family of the icon disc ("amber", "sky", ...).
  final String tone;
}

/// One colour family: the chosen chip, the card rail, the badge, the tint disc.
class HelpTone {
  const HelpTone({
    required this.chipOn,
    required this.rail,
    required this.badgeBg,
    required this.badgeBorder,
    required this.badgeFg,
    required this.tintBg,
    required this.tintFg,
  });
  final Color chipOn, rail, badgeBg, badgeBorder, badgeFg, tintBg, tintFg;
}

const _families = <String, HelpTone>{
  'emerald': HelpTone(chipOn: Tone.bg(0xFF059669), rail: Tone(0xFF34D399), badgeBg: Tone.bg(0xFFECFDF5), badgeBorder: Tone.line(0xFFA7F3D0), badgeFg: Tone.fg(0xFF047857), tintBg: Tone.bg(0xFFD1FAE5), tintFg: Tone.fg(0xFF047857)),
  'amber': HelpTone(chipOn: Tone.bg(0xFFD97706), rail: Tone(0xFFFBBF24), badgeBg: Tone.bg(0xFFFFFBEB), badgeBorder: Tone.line(0xFFFDE68A), badgeFg: Tone.fg(0xFFB45309), tintBg: Tone.bg(0xFFFEF3C7), tintFg: Tone.fg(0xFFB45309)),
  'sky': HelpTone(chipOn: Tone.bg(0xFF0284C7), rail: Tone(0xFF38BDF8), badgeBg: Tone.bg(0xFFF0F9FF), badgeBorder: Tone.line(0xFFBAE6FD), badgeFg: Tone.fg(0xFF0369A1), tintBg: Tone.bg(0xFFE0F2FE), tintFg: Tone.fg(0xFF0369A1)),
  'violet': HelpTone(chipOn: Tone.bg(0xFF7C3AED), rail: Tone(0xFFA78BFA), badgeBg: Tone.bg(0xFFF5F3FF), badgeBorder: Tone.line(0xFFDDD6FE), badgeFg: Tone.fg(0xFF6D28D9), tintBg: Tone.bg(0xFFEDE9FE), tintFg: Tone.fg(0xFF6D28D9)),
  'rose': HelpTone(chipOn: Tone.bg(0xFFE11D48), rail: Tone(0xFFFB7185), badgeBg: Tone.bg(0xFFFFF1F2), badgeBorder: Tone.line(0xFFFECDD3), badgeFg: Tone.fg(0xFFBE123C), tintBg: Tone.bg(0xFFFFE4E6), tintFg: Tone.fg(0xFFBE123C)),
  'indigo': HelpTone(chipOn: Tone.bg(0xFF4F46E5), rail: Tone(0xFF818CF8), badgeBg: Tone.bg(0xFFEEF2FF), badgeBorder: Tone.line(0xFFC7D2FE), badgeFg: Tone.fg(0xFF4338CA), tintBg: Tone.bg(0xFFE0E7FF), tintFg: Tone.fg(0xFF4338CA)),
  'slate': HelpTone(chipOn: Tone.bg(0xFF334155), rail: Tone(0xFF94A3B8), badgeBg: Tone.bg(0xFFF1F5F9), badgeBorder: Tone.line(0xFFE2E8F0), badgeFg: Tone.fg(0xFF334155), tintBg: Tone.bg(0xFFE2E8F0), tintFg: Tone.fg(0xFF334155)),
};

/// The web's FALLBACK_TONE: indigo chip, slate rail and badge.
const fallbackHelpTone = HelpTone(chipOn: Tone.bg(0xFF4F46E5), rail: Tone(0xFFCBD5E1), badgeBg: Tone.bg(0xFFF8FAFC), badgeBorder: Tone.line(0xFFE2E8F0), badgeFg: Tone.fg(0xFF475569), tintBg: Tone.bg(0xFFE2E8F0), tintFg: Tone.fg(0xFF334155));

const _categoryFamily = <String, String>{
  'Getting Started': 'emerald',
  'Flocks & Birds': 'amber',
  'Production & Eggs': 'sky',
  'Sales & Customers': 'violet',
  'Expenses & Purchases': 'rose',
  'Money & Reports': 'indigo',
  'Account & Access': 'slate',
};

/// toneFor(category): the same subject is the same colour everywhere.
HelpTone toneFor(String category) => _families[_categoryFamily[category]] ?? fallbackHelpTone;

/// A Feature Guide disc's colours, by family name.
HelpTone toneOfFamily(String family) => _families[family] ?? fallbackHelpTone;
