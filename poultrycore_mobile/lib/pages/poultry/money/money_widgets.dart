// The pieces the Money pages share, mirroring the web components they use:
// components/ui/mobile-card-list.tsx (the phone layout of every Money list)
// and the pages' compact KPI Tile with its info tooltip.

import 'package:flutter/material.dart';

import '../trackers/tracker_widgets.dart';
import '../sales/balances_widgets.dart' show CompactPager;

/// HIGHLIGHT_TONES: (tile bg, border, label, value).
enum Accent { emerald, blue, violet, amber, rose, slate }

(Color, Color, Color, Color) accentTone(Accent a) => switch (a) {
      Accent.emerald => (TColors.emerald100, TColors.emerald300, TColors.emerald900, TColors.emerald800),
      Accent.blue => (TColors.blue100, TColors.blue300, TColors.blue900, const Color(0xFF1E40AF)),
      Accent.violet => (TColors.violet100, const Color(0xFFC4B5FD), const Color(0xFF4C1D95), const Color(0xFF4C1D95)),
      Accent.amber => (TColors.amber100, TColors.amber300, TColors.amber900, TColors.amber800),
      Accent.rose => (TColors.rose100, const Color(0xFFFDA4AF), const Color(0xFF881337), TColors.rose700),
      Accent.slate => (TColors.slate100, TColors.slate300, TColors.slate600, TColors.slate900),
    };

class Highlight {
  const Highlight(this.label, this.value, {this.accent = Accent.slate, this.wide = false});
  final String label;
  final String value;
  final Accent accent;
  final bool wide;
}

/// MobileCardList: one collapsible card per item (open by default), striped
/// when asked, with highlight tiles, a details grid and actions; "View table
/// format" flips to [table], and the pager follows either view.
class MobileCardList<T> extends StatefulWidget {
  const MobileCardList({
    super.key,
    required this.items,
    required this.keyOf,
    required this.primary,
    this.secondary,
    this.highlights,
    this.details,
    this.actions,
    this.extra,
    this.trailing,
    required this.table,
    this.striped = false,
    this.stripeBlue = false,
    this.pager,
    this.defaultOpen = true,
  });
  final List<T> items;
  final String Function(T) keyOf;
  final String Function(T) primary;
  final String Function(T)? secondary;
  final List<Highlight> Function(T)? highlights;
  final List<(String, String)> Function(T)? details;
  final List<Widget> Function(T)? actions;

  /// Under the details, as the web's `extra` slot.
  final Widget Function(T)? extra;
  final Widget? Function(T)? trailing;
  final Widget Function(List<T> items) table;
  final bool striped;

  /// STRIPE_TONES.blue rather than the default amber.
  final bool stripeBlue;

  /// The DataPagination under the list, or null.
  final CompactPager? pager;

  /// Cards start open (the web's `defaultOpen`), or closed when false.
  final bool defaultOpen;

  @override
  State<MobileCardList<T>> createState() => _MobileCardListState<T>();
}

class _MobileCardListState<T> extends State<MobileCardList<T>> {
  bool _table = false;

  @override
  Widget build(BuildContext context) {
    if (_table) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TableViewBar(text: 'Table • Scroll → for more', onCards: () => setState(() => _table = false)),
        widget.table(widget.items),
        ?widget.pager,
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < widget.items.length; i++) ...[
        _Card<T>(
          key: ValueKey(widget.keyOf(widget.items[i])),
          item: widget.items[i],
          list: widget,
          stripe: widget.striped && i.isEven,
        ),
        const SizedBox(height: 8),
      ],
      TextButton.icon(
        onPressed: () => setState(() => _table = true),
        iconAlignment: IconAlignment.end,
        icon: const Icon(Icons.keyboard_arrow_down, size: 16),
        label: const Text('View table format'),
        style: TextButton.styleFrom(foregroundColor: TColors.slate600, minimumSize: const Size.fromHeight(40)),
      ),
      ?widget.pager,
    ]);
  }
}

class _Card<T> extends StatefulWidget {
  const _Card({super.key, required this.item, required this.list, required this.stripe});
  final T item;
  final MobileCardList<T> list;
  final bool stripe;
  @override
  State<_Card<T>> createState() => _CardState<T>();
}

class _CardState<T> extends State<_Card<T>> {
  late bool _open = widget.list.defaultOpen;

  @override
  Widget build(BuildContext context) {
    final l = widget.list;
    final it = widget.item;
    final stripeBg = l.stripeBlue ? TColors.blue100 : TColors.amber100;
    final stripeBorder = l.stripeBlue ? TColors.blue300 : TColors.amber300;
    final hs = l.highlights?.call(it) ?? const <Highlight>[];
    final ds = l.details?.call(it) ?? const <(String, String)>[];
    final acts = l.actions?.call(it) ?? const <Widget>[];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.stripe ? stripeBg : Colors.white,
        border: Border.all(color: widget.stripe ? stripeBorder : TColors.slate200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.primary(it), style: const TextStyle(fontWeight: FontWeight.w600, color: TColors.slate900)),
                  if (l.secondary != null) ...[
                    const SizedBox(height: 2),
                    Text(l.secondary!(it), style: const TextStyle(fontSize: 13, color: TColors.slate600)),
                  ],
                ]),
              ),
              ?l.trailing?.call(it),
              Icon(_open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: TColors.slate400),
            ]),
            if (hs.isNotEmpty) ...[
              const SizedBox(height: 10),
              LayoutBuilder(builder: (context, c) {
                final half = (c.maxWidth - 8) / 2;
                return Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final h in hs)
                    SizedBox(
                      width: h.wide ? c.maxWidth : half,
                      child: Builder(builder: (context) {
                        final (bg, border, lc, vc) = accentTone(h.accent);
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(8)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(h.label.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: lc)),
                            Text(h.value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: vc)),
                          ]),
                        );
                      }),
                    ),
                ]);
              }),
            ],
          ]),
        ),
        if (_open && (ds.isNotEmpty || acts.isNotEmpty || l.extra != null)) ...[
          const SizedBox(height: 12),
          Divider(height: 1, color: widget.stripe ? const Color(0xB3E2E8F0) : TColors.slate100),
          const SizedBox(height: 10),
          if (ds.isNotEmpty)
            LayoutBuilder(builder: (context, c) {
              final half = (c.maxWidth - 8) / 2;
              return Wrap(spacing: 8, runSpacing: 8, children: [
                for (final (label, value) in ds)
                  SizedBox(
                    width: half,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                      Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                    ]),
                  ),
              ]);
            }),
          if (l.extra != null) ...[const SizedBox(height: 8), l.extra!(it)],
          if (acts.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: acts),
          ],
        ],
      ]),
    );
  }
}

/// The Money pages' compact KPI tile: label with an info tooltip, the figure,
/// and a note under it.
class InfoTile extends StatelessWidget {
  const InfoTile({super.key, required this.label, required this.value, required this.tip, this.note, this.color, this.icon});
  final String label;
  final String value;
  final String tip;
  final String? note;
  final Color? color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (icon != null) ...[Icon(icon, size: 14, color: TColors.slate500), const SizedBox(width: 4)],
            Expanded(
              child: Text(label.toUpperCase(),
                  overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, letterSpacing: .4, color: TColors.slate500)),
            ),
            Tooltip(
              message: tip,
              triggerMode: TooltipTriggerMode.tap,
              showDuration: const Duration(seconds: 8),
              child: const Icon(Icons.info_outline, size: 15, color: TColors.slate400),
            ),
          ]),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: color ?? TColors.slate900)),
          if (note != null) Text(note!, style: const TextStyle(fontSize: 11, color: TColors.slate500)),
        ]),
      );
}

/// Two tiles per row, as the pages' grid-cols-2 on a phone.
Widget twoUp(List<Widget> tiles) => LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - 8) / 2;
      return Wrap(spacing: 8, runSpacing: 8, children: [for (final t in tiles) SizedBox(width: w, child: t)]);
    });

/// The Money pages' Stat card: uppercase label, the figure, an optional hint,
/// each on one line.
Widget moneyStat(String label, String value, {String? hint, Color color = TColors.slate900}) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: .6, color: TColors.slate500)),
        const SizedBox(height: 4),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
        if (hint != null) Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: TColors.slate500)),
      ]),
    );

/// A filter button: filled when chosen ("default", or "secondary"), outlined otherwise.
Widget filterChipButton(String label, bool on, VoidCallback tap, {bool secondary = false}) => on
    ? FilledButton(
        onPressed: tap,
        style: FilledButton.styleFrom(
          visualDensity: VisualDensity.compact,
          backgroundColor: secondary ? TColors.slate100 : TColors.slate900,
          foregroundColor: secondary ? TColors.slate900 : Colors.white,
        ),
        child: Text(label),
      )
    : OutlinedButton(onPressed: tap, style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact), child: Text(label));

/// FormSection: a coloured title band over its fields.
Widget formSection(String title, Color band, List<Widget> children) => Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: band,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 12), children[i]],
          ]),
        ),
      ]),
    );

/// The dialogs' red Cancel button.
Widget redCancelButton(VoidCallback? onTap) => FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(backgroundColor: TColors.red600, foregroundColor: Colors.white),
      child: const Text('Cancel'),
    );
