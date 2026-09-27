import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../models/company.dart';

/// Company-type colours, taken from the web.
///
/// Two separate palettes exist there and both are reproduced here:
///
/// * The **nav accent** (solid), documented in `lib/nav/nav-model.ts`:
///   sky-600 Water, orange-500 Poultry, emerald-600 Generic, violet-600 Hotel,
///   rose-600 Restaurant.
/// * The **type badge** (pastel), from `TYPE_BADGE` in the business-office
///   screens: amber-100/700 Poultry, blue-100/700 Water, slate-100/700 Generic.
///
/// The web's TYPE_BADGE map predates the Restaurant and Hotel modules and has
/// no entry for them, so those two badges are derived from their own nav accent
/// family (rose and violet) at the same 100/700 steps. If the web adds them
/// later, copy its values over these.
class TypeColors {
  const TypeColors._();

  // Tailwind palette values used by the web.
  static const amber100 = Color(0xFFFEF3C7);
  static const amber700 = Color(0xFFB45309);
  static const blue100 = Color(0xFFDBEAFE);
  static const blue700 = Color(0xFF1D4ED8);
  static const slate100 = Color(0xFFF1F5F9);
  static const slate700 = Color(0xFF334155);
  static const rose100 = Color(0xFFFFE4E6);
  static const rose700 = Color(0xFFBE123C);
  static const violet100 = Color(0xFFEDE9FE);
  static const violet700 = Color(0xFF6D28D9);

  // Nav accents.
  static const sky600 = Color(0xFF0284C7); // Water
  static const orange500 = Color(0xFFF97316); // Poultry
  static const emerald600 = Color(0xFF059669); // Generic
  static const violet600 = Color(0xFF7C3AED); // Hotel
  static const rose600 = Color(0xFFE11D48); // Restaurant

  /// The solid colour the web tints a company's nav panel with.
  static Color accent(CompanyType type) => switch (type) {
        CompanyType.poultry => orange500,
        CompanyType.water => sky600,
        CompanyType.generic => emerald600,
        CompanyType.hotel => violet600,
        CompanyType.restaurant => rose600,
        CompanyType.unknown => slate700,
      };
}

class CompanyTypeBadge extends StatelessWidget {
  const CompanyTypeBadge({super.key, required this.type, this.dense = true});

  final CompanyType type;
  final bool dense;

  static IconData iconFor(CompanyType type) => switch (type) {
        CompanyType.poultry => Icons.egg_outlined,
        CompanyType.water => Icons.water_drop_outlined,
        CompanyType.generic => Icons.storefront_outlined,
        CompanyType.restaurant => Icons.restaurant_outlined,
        CompanyType.hotel => Icons.hotel_outlined,
        CompanyType.unknown => Icons.help_outline,
      };

  ({Color bg, Color fg}) _style(ColorScheme scheme) => switch (type) {
        CompanyType.poultry => (bg: TypeColors.amber100, fg: TypeColors.amber700),
        CompanyType.water => (bg: TypeColors.blue100, fg: TypeColors.blue700),
        CompanyType.generic => (bg: TypeColors.slate100, fg: TypeColors.slate700),
        CompanyType.restaurant => (bg: TypeColors.rose100, fg: TypeColors.rose700),
        CompanyType.hotel => (bg: TypeColors.violet100, fg: TypeColors.violet700),
        CompanyType.unknown => (bg: TypeColors.slate100, fg: TypeColors.slate700),
      };

  @override
  Widget build(BuildContext context) {
    final s = _style(Theme.of(context).colorScheme);
    // The web Badge is rounded-md with px-2 py-0.5 and text-xs font-medium.
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 2 : 4),
      decoration: BoxDecoration(
        color: s.bg,
        borderRadius: BorderRadius.circular(Dim.radiusMd),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconFor(type), size: dense ? 12 : 14, color: s.fg),
          const SizedBox(width: 4), // gap-1
          Text(
            type.label,
            style: TextStyle(
              color: s.fg,
              fontSize: 12, // text-xs
              fontWeight: FontWeight.w500, // font-medium
            ),
          ),
        ],
      ),
    );
  }
}
