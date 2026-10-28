// The web's components/restaurant/* building blocks: PageHeader, StatCard and
// EmptyState, plus the rose tab strip and the small badge the Restaurant pages
// share.

import 'dart:convert';

import 'package:flutter/material.dart';

import '../poultry/trackers/tracker_widgets.dart' show TColors;
import 'restaurant_roles.dart' show restaurantRose;

/// A picture the web stored either as a data URI (how Menu uploads save it) or
/// as a plain URL; [fallback] when there is none or it cannot be read.
Widget restaurantImage(String src, {required Widget fallback, BoxFit fit = BoxFit.cover}) {
  if (src.isEmpty) return fallback;
  if (src.startsWith('data:')) {
    try {
      return Image.memory(base64Decode(src.substring(src.indexOf(',') + 1)), fit: fit, gaplessPlayback: true, errorBuilder: (_, _, _) => fallback);
    } catch (_) {
      return fallback;
    }
  }
  return Image.network(src, fit: fit, errorBuilder: (_, _, _) => fallback);
}

/// PageHeader: the rose icon tile, title and subtitle; actions full width below.
class RPageHeader extends StatelessWidget {
  const RPageHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.tileColor = const Color(0xFFFFE4E6),
    this.iconColor = restaurantRose,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  /// The icon tile; Hotel's copies of these pages pass violet.
  final Color tileColor, iconColor;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: tileColor, borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 22, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
              if (subtitle != null) Text(subtitle!, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
            ]),
          ),
        ]),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(children: [
            for (final (i, a) in actions.indexed) ...[if (i > 0) const SizedBox(width: 8), Expanded(child: a)],
          ]),
        ],
      ]);
}

/// The rose primary button the pages use.
Widget roseButton(String label, VoidCallback? onTap, {IconData icon = Icons.add, Color color = restaurantRose}) => FilledButton.icon(
      style: FilledButton.styleFrom(backgroundColor: color, minimumSize: const Size.fromHeight(44)),
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );

/// StatCard colours (border-l-* and the icon tile).
const rStatColors = <String, (Color, Color, Color)>{
  'rose': (Color(0xFFF43F5E), Color(0xFFFFF1F2), Color(0xFFE11D48)),
  'green': (Color(0xFF22C55E), Color(0xFFF0FDF4), Color(0xFF16A34A)),
  'blue': (Color(0xFF3B82F6), Color(0xFFEFF6FF), Color(0xFF2563EB)),
  'amber': (Color(0xFFF59E0B), Color(0xFFFFFBEB), Color(0xFFD97706)),
  'purple': (Color(0xFFA855F7), Color(0xFFFAF5FF), Color(0xFF9333EA)),
  'red': (Color(0xFFEF4444), Color(0xFFFEF2F2), Color(0xFFDC2626)),
  'indigo': (Color(0xFF6366F1), Color(0xFFEEF2FF), Color(0xFF4F46E5)),
};

class RStatCard extends StatelessWidget {
  const RStatCard({super.key, required this.label, required this.value, required this.icon, this.color = 'rose'});
  final String label;
  final String value;
  final IconData icon;
  final String color;

  @override
  Widget build(BuildContext context) {
    final (stripe, tileBg, tileFg) = rStatColors[color] ?? rStatColors['rose']!;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: TColors.slate200)),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 4, color: stripe),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(color: tileBg, borderRadius: BorderRadius.circular(8)),
                  child: Icon(icon, size: 18, color: tileFg),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                    Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                  ]),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Two-per-row grid of [children].
Widget twoColumns(List<Widget> children, {double gap = 10}) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < children.length; i += 2) ...[
        if (i > 0) SizedBox(height: gap),
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: children[i]),
            SizedBox(width: gap),
            Expanded(child: i + 1 < children.length ? children[i + 1] : const SizedBox.shrink()),
          ]),
        ),
      ],
    ]);

/// EmptyState.
class REmptyState extends StatelessWidget {
  const REmptyState({super.key, required this.icon, required this.title, this.description, this.actionLabel, this.onAction});
  final IconData icon;
  final String title;
  final String? description;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
        decoration: BoxDecoration(border: Border.all(color: TColors.slate200, width: 2), borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          Icon(icon, size: 44, color: const Color(0xFFD1D5DB)),
          const SizedBox(height: 10),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF6B7280))),
          if (description != null) ...[
            const SizedBox(height: 4),
            Text(description!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 14),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: restaurantRose), onPressed: onAction, child: Text(actionLabel!)),
          ],
        ]),
      );
}

/// The rose tab strip: (value, icon, label, trailing badge or null).
class RTabs extends StatelessWidget {
  const RTabs({super.key, required this.tabs, required this.value, required this.onChanged});
  final List<(String, IconData, String, Widget?)> tabs;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: TColors.slate200),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1))],
        ),
        child: Wrap(spacing: 4, runSpacing: 4, children: [
          for (final (v, icon, label, badge) in tabs)
            Material(
              color: value == v ? const Color(0xFFFFF1F2) : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => onChanged(v),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, size: 16, color: value == v ? const Color(0xFFBE123C) : TColors.slate600),
                    const SizedBox(width: 6),
                    Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: value == v ? const Color(0xFFBE123C) : TColors.slate600)),
                    if (badge != null) ...[const SizedBox(width: 6), badge],
                  ]),
                ),
              ),
            ),
        ]),
      );
}

/// A small pill badge.
Widget rBadge(String text, {Color bg = const Color(0xFFF3F4F6), Color fg = const Color(0xFF374151), Color? border}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: bg, border: Border.all(color: border ?? bg), borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );

/// A form label, with the rose star when required.
Widget rLabel(String text, {bool required = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text.rich(TextSpan(children: [
        TextSpan(text: text),
        if (required) const TextSpan(text: ' *', style: TextStyle(color: Color(0xFFF43F5E))),
      ]), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
    );

/// Cancel / confirm, wrapping rather than overflowing on a narrow phone.
Widget rDialogActions(BuildContext context, String confirm, VoidCallback? onConfirm, {Color color = restaurantRose}) =>
    Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
      OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(style: FilledButton.styleFrom(backgroundColor: color), onPressed: onConfirm, child: Text(confirm)),
    ]);
