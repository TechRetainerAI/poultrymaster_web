// The shape of a Help Center entry (lib/help/help-types.ts) and the Feature
// Guide tile (poultry-help-content.ts FeatureGuide), plus the category colours
// (CATEGORY_TONES / toneFor) as Flutter colours.

import 'package:flutter/material.dart';

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
  'emerald': HelpTone(chipOn: Color(0xFF059669), rail: Color(0xFF34D399), badgeBg: Color(0xFFECFDF5), badgeBorder: Color(0xFFA7F3D0), badgeFg: Color(0xFF047857), tintBg: Color(0xFFD1FAE5), tintFg: Color(0xFF047857)),
  'amber': HelpTone(chipOn: Color(0xFFD97706), rail: Color(0xFFFBBF24), badgeBg: Color(0xFFFFFBEB), badgeBorder: Color(0xFFFDE68A), badgeFg: Color(0xFFB45309), tintBg: Color(0xFFFEF3C7), tintFg: Color(0xFFB45309)),
  'sky': HelpTone(chipOn: Color(0xFF0284C7), rail: Color(0xFF38BDF8), badgeBg: Color(0xFFF0F9FF), badgeBorder: Color(0xFFBAE6FD), badgeFg: Color(0xFF0369A1), tintBg: Color(0xFFE0F2FE), tintFg: Color(0xFF0369A1)),
  'violet': HelpTone(chipOn: Color(0xFF7C3AED), rail: Color(0xFFA78BFA), badgeBg: Color(0xFFF5F3FF), badgeBorder: Color(0xFFDDD6FE), badgeFg: Color(0xFF6D28D9), tintBg: Color(0xFFEDE9FE), tintFg: Color(0xFF6D28D9)),
  'rose': HelpTone(chipOn: Color(0xFFE11D48), rail: Color(0xFFFB7185), badgeBg: Color(0xFFFFF1F2), badgeBorder: Color(0xFFFECDD3), badgeFg: Color(0xFFBE123C), tintBg: Color(0xFFFFE4E6), tintFg: Color(0xFFBE123C)),
  'indigo': HelpTone(chipOn: Color(0xFF4F46E5), rail: Color(0xFF818CF8), badgeBg: Color(0xFFEEF2FF), badgeBorder: Color(0xFFC7D2FE), badgeFg: Color(0xFF4338CA), tintBg: Color(0xFFE0E7FF), tintFg: Color(0xFF4338CA)),
  'slate': HelpTone(chipOn: Color(0xFF334155), rail: Color(0xFF94A3B8), badgeBg: Color(0xFFF1F5F9), badgeBorder: Color(0xFFE2E8F0), badgeFg: Color(0xFF334155), tintBg: Color(0xFFE2E8F0), tintFg: Color(0xFF334155)),
};

/// The web's FALLBACK_TONE: indigo chip, slate rail and badge.
const fallbackHelpTone = HelpTone(chipOn: Color(0xFF4F46E5), rail: Color(0xFFCBD5E1), badgeBg: Color(0xFFF8FAFC), badgeBorder: Color(0xFFE2E8F0), badgeFg: Color(0xFF475569), tintBg: Color(0xFFE2E8F0), tintFg: Color(0xFF334155));

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
