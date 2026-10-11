// The pieces every Poultry tracker page is built from, mirroring the web's
// tracker markup: the header band (icon, title, blurb, links, Refresh), the
// figure tiles, the "Breakdown" cards (components/cash/flow-breakdown-card),
// the striped scorecards with the "View table format" toggle, a sortable
// table with a totals footer, the pagination bar, the adjustment dialog and
// "View cost breakdown" (components/poultry/cost-breakdown-dialog).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/buttons.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../shared/business_dates.dart';
import '../reports/report_format.dart';
import '../reports/report_routes.dart';
import 'tracker_logic.dart';

// ------------------------------------------------------------------ palette

class TColors {
  const TColors._();
  static const slate900 = Color(0xFF0F172A);
  static const slate800 = Color(0xFF1E293B);
  static const slate700 = Color(0xFF334155);
  static const slate600 = Color(0xFF475569);
  static const slate500 = Color(0xFF566579);  // a shade darker than Tailwind's, for legibility
  static const slate400 = Color(0xFF7F8EA3);  // a shade darker than Tailwind's, for legibility
  static const slate300 = Color(0xFFCBD5E1);
  static const slate200 = Color(0xFFE2E8F0);
  static const slate100 = Color(0xFFF1F5F9);
  static const slate50 = Color(0xFFF8FAFC);
  static const emerald600 = Color(0xFF059669);
  static const emerald700 = Color(0xFF047857);
  static const emerald800 = Color(0xFF065F46);
  static const emerald900 = Color(0xFF064E3B);
  static const emerald100 = Color(0xFFD1FAE5);
  static const emerald300 = Color(0xFF6EE7B7);
  static const emerald50 = Color(0xFFECFDF5);
  static const emerald200 = Color(0xFFA7F3D0);
  static const emerald500 = Color(0xFF10B981);
  static const red600 = Color(0xFFDC2626);
  static const red700 = Color(0xFFB91C1C);
  static const red800 = Color(0xFF991B1B);
  static const red900 = Color(0xFF7F1D1D);
  static const red100 = Color(0xFFFEE2E2);
  static const red300 = Color(0xFFFCA5A5);
  static const red50 = Color(0xFFFEF2F2);
  static const red200 = Color(0xFFFECACA);
  static const rose500 = Color(0xFFF43F5E);
  static const rose600 = Color(0xFFE11D48);
  static const rose700 = Color(0xFFBE123C);
  static const rose800 = Color(0xFF9F1239);
  static const rose100 = Color(0xFFFFE4E6);
  static const rose50 = Color(0xFFFFF1F2);
  static const rose200 = Color(0xFFFECDD3);
  static const amber50 = Color(0xFFFFFBEB);
  static const amber100 = Color(0xFFFEF3C7);
  static const amber200 = Color(0xFFFDE68A);
  static const amber300 = Color(0xFFFCD34D);
  static const amber600 = Color(0xFFD97706);
  static const amber700 = Color(0xFFB45309);
  static const amber800 = Color(0xFF92400E);
  static const amber900 = Color(0xFF78350F);
  static const sky100 = Color(0xFFE0F2FE);
  static const sky300 = Color(0xFF7DD3FC);
  static const sky700 = Color(0xFF0369A1);
  static const sky800 = Color(0xFF075985);
  static const sky900 = Color(0xFF0C4A6E);
  static const blue100 = Color(0xFFDBEAFE);
  static const blue200 = Color(0xFFBFDBFE);
  static const blue300 = Color(0xFF93C5FD);
  static const blue600 = Color(0xFF2563EB);
  static const blue900 = Color(0xFF1E3A8A);
  static const violet50 = Color(0xFFF5F3FF);
  static const violet100 = Color(0xFFEDE9FE);
  static const violet200 = Color(0xFFDDD6FE);
  static const violet600 = Color(0xFF7C3AED);
  static const violet700 = Color(0xFF6D28D9);
  static const violet800 = Color(0xFF5B21B6);
  static const green100 = Color(0xFFDCFCE7);
  static const green700 = Color(0xFF15803D);
}

// ------------------------------------------------------------------ toast

void trackerToast(BuildContext context, String title, {String? description, bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      backgroundColor: error ? TColors.rose700 : null,
      content: Text(description == null ? title : '$title — $description'),
    ));
}

// ------------------------------------------------------------------ header

/// The page header band: icon square, title, blurb, the blue links row.
class TrackerHeader extends StatelessWidget {
  const TrackerHeader({
    super.key,
    required this.icon,
    required this.iconBg,
    required this.iconFg,
    required this.title,
    this.blurb,
    this.blurbSpans,
    this.links = const [],
    required this.session,
    required this.company,
  });
  final IconData icon;
  final Color iconBg;
  final Color iconFg;
  final String title;
  final String? blurb;
  final List<InlineSpan>? blurbSpans;
  final List<(String href, String label)> links;
  final Session session;
  final Company company;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 20, color: iconFg),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: TColors.slate900)),
              const SizedBox(height: 2),
              if (blurbSpans != null)
                Text.rich(TextSpan(children: blurbSpans),
                    style: const TextStyle(fontSize: 13, color: TColors.slate600))
              else if (blurb != null)
                Text(blurb!, style: const TextStyle(fontSize: 13, color: TColors.slate600)),
              if (links.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    for (final (href, label) in links)
                      InkWell(
                        onTap: () => openAppHref(context, session, company, href, label: label),
                        child: Text(label,
                            style: const TextStyle(
                                fontSize: 13, color: TColors.blue600, fontWeight: FontWeight.w500)),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Bold runs inside a blurb, as the web's <strong>.
TextSpan b(String s) => TextSpan(text: s, style: const TextStyle(fontWeight: FontWeight.w700));
TextSpan t(String s) => TextSpan(text: s);

/// The outlined Refresh button with its spinning icon.
class RefreshAction extends StatelessWidget {
  const RefreshAction({super.key, required this.busy, required this.onPressed});
  final bool busy;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Refresh',
        onPressed: busy ? null : onPressed,
        icon: busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.refresh),
      );
}

// ------------------------------------------------------------------ banners

class TrackerBanner extends StatelessWidget {
  const TrackerBanner.error(this.text, {super.key, this.spans})
      : bg = TColors.rose50,
        border = TColors.rose200,
        fg = TColors.rose800,
        icon = null;
  const TrackerBanner.warn(this.text, {super.key, this.spans})
      : bg = TColors.amber50,
        border = TColors.amber300,
        fg = TColors.amber900,
        icon = Icons.warning_amber_rounded;
  const TrackerBanner.info(this.text, {super.key, this.spans})
      : bg = Colors.white,
        border = TColors.slate200,
        fg = TColors.slate700,
        icon = null;
  final String text;
  final List<InlineSpan>? spans;
  final Color bg, border, fg;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) ...[Icon(icon, size: 16, color: TColors.amber700), const SizedBox(width: 8)],
            Expanded(
              child: spans != null
                  ? Text.rich(TextSpan(children: spans), style: TextStyle(fontSize: 13, color: fg))
                  : Text(text, style: TextStyle(fontSize: 13, color: fg)),
            ),
          ],
        ),
      );
}

class TrackerLoading extends StatelessWidget {
  const TrackerLoading(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => TCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Center(child: Text(text, style: const TextStyle(color: TColors.slate600))),
        ),
      );
}

// ------------------------------------------------------------------ card

/// The web Card: white (or tinted) with a border, header + content.
class TCard extends StatelessWidget {
  const TCard({
    super.key,
    this.title,
    this.titleWidget,
    this.eyebrow,
    this.description,
    this.descriptionSpans,
    this.trailing,
    this.headerExtra,
    required this.child,
    this.bg = Colors.white,
    this.border = TColors.slate200,
    this.padding = const EdgeInsets.all(14),
  });
  final String? title;
  final Widget? titleWidget;
  final String? eyebrow;
  final String? description;
  final List<InlineSpan>? descriptionSpans;
  final Widget? trailing;
  final Widget? headerExtra;
  final Widget child;
  final Color bg;
  final Color border;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final hasHeader = title != null || titleWidget != null || eyebrow != null;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasHeader) ...[
            if (eyebrow != null) Text(eyebrow!, style: const TextStyle(fontSize: 12.5, color: TColors.slate500)),
            if (title != null || titleWidget != null || trailing != null)
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  titleWidget ??
                      Text(title ?? '',
                          style:
                              const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: TColors.slate800)),
                  ?trailing,
                ],
              ),
            if (description != null || descriptionSpans != null) ...[
              const SizedBox(height: 4),
              descriptionSpans != null
                  ? Text.rich(TextSpan(children: descriptionSpans),
                      style: const TextStyle(fontSize: 12.5, color: TColors.slate500))
                  : Text(description!, style: const TextStyle(fontSize: 12.5, color: TColors.slate500)),
            ],
            ?headerExtra,
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ tiles

class TileData {
  const TileData(this.label, this.value, {this.color = TColors.slate900, this.suffix, this.sub, this.action});
  final String label;
  final String value;
  final Color color;
  final String? suffix;
  final String? sub;
  final Widget? action;
}

/// The figure tiles, two across on a phone (the web's mobile grid-cols-2).
class TileGrid extends StatelessWidget {
  const TileGrid(this.tiles, {super.key, this.columns = 2, this.boxed = false});
  final List<TileData> tiles;
  final int columns;

  /// White boxes with a border (the Birds/Medication summary) rather than bare
  /// figures inside a tinted card (Egg/Feed).
  final bool boxed;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final gap = boxed ? 10.0 : 14.0;
      final w = (c.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final tile in tiles)
            SizedBox(
              width: w,
              child: Container(
                padding: boxed ? const EdgeInsets.all(14) : EdgeInsets.zero,
                decoration: boxed
                    ? BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: TColors.slate200),
                        borderRadius: BorderRadius.circular(12),
                      )
                    : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tile.label.toUpperCase(),
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: .5, color: TColors.slate500)),
                    const SizedBox(height: 4),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 4,
                      children: [
                        Text(tile.value,
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: tile.color)),
                        if (tile.suffix != null)
                          Text(tile.suffix!, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
                        ?tile.action,
                      ],
                    ),
                    if (tile.sub != null)
                      Text(tile.sub!, style: const TextStyle(fontSize: 11, color: TColors.slate500)),
                  ],
                ),
              ),
            ),
        ],
      );
    });
  }
}

/// The small copy-to-clipboard ghost button next to an on-hand figure.
class CopyButton extends StatelessWidget {
  const CopyButton({super.key, required this.value, required this.label, required this.toastText});
  final String value;
  final String label;
  final String toastText;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 32,
        height: 32,
        child: IconButton(
          tooltip: label,
          padding: EdgeInsets.zero,
          iconSize: 16,
          color: TColors.slate500,
          icon: const Icon(Icons.copy),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: value));
            if (context.mounted) trackerToast(context, 'Copied', description: toastText);
          },
        ),
      );
}

// ------------------------------------------------------------------ breakdown

/// FlowBreakdownCard: a bucketed list with share bars.
class FlowBreakdownCard extends StatelessWidget {
  const FlowBreakdownCard({
    super.key,
    required this.title,
    required this.buckets,
    required this.total,
    required this.inDirection,
    required this.fmt,
    required this.emptyText,
    this.description,
  });
  final String title;
  final List<FlowBucket> buckets;
  final num total;
  final bool inDirection;
  final String Function(num) fmt;
  final String emptyText;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final single = buckets.length == 1;
    return TCard(
      titleWidget: Row(
        children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
          Text(fmt(total),
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: inDirection ? TColors.emerald700 : TColors.rose700)),
        ],
      ),
      title: null,
      description: description,
      child: buckets.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text(emptyText, style: const TextStyle(fontSize: 13, color: TColors.slate500))),
            )
          : Column(
              children: [
                for (final bk in buckets)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Text.rich(
                                TextSpan(children: [
                                  TextSpan(text: bk.label),
                                  TextSpan(
                                    text: '  ${bk.count} ${bk.count == 1 ? 'entry' : 'entries'}',
                                    style: const TextStyle(fontSize: 11, color: TColors.slate400),
                                  ),
                                ]),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13, color: TColors.slate700),
                              ),
                            ),
                            Text(fmt(bk.amount),
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w500, color: TColors.slate900)),
                          ],
                        ),
                        if (!single) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: (bk.percent < 1 ? 1 : bk.percent) / 100,
                                    minHeight: 6,
                                    backgroundColor: TColors.slate100,
                                    color: inDirection ? TColors.emerald500 : TColors.rose500,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 92,
                                child: Text('${jsNum(bk.percent)}% of total',
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(fontSize: 11, color: TColors.slate500)),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

/// The "Breakdown" heading above a stack of FlowBreakdownCards.
class BreakdownSection extends StatelessWidget {
  const BreakdownSection({super.key, required this.cards});
  final List<Widget> cards;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('BREAKDOWN',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: .5, color: TColors.slate500)),
          const SizedBox(height: 10),
          for (final c in cards) ...[c, const SizedBox(height: 10)],
        ],
      );
}

// ------------------------------------------------------------------ scorecards

/// One of the trackers' mobile scorecards: striped, open by default, a header
/// row, two In/Out boxes, then details and actions under a divider.
class LedgerScorecard extends StatefulWidget {
  const LedgerScorecard({
    super.key,
    required this.index,
    required this.title,
    this.badge,
    required this.boxes,
    this.details = const [],
    this.actions = const [],
    this.trailing,
  });
  final int index;
  final String title;
  final String? badge;
  final List<ScoreBox> boxes;
  final List<(String, Widget)> details;
  final List<Widget> actions;
  final Widget? trailing;

  @override
  State<LedgerScorecard> createState() => _LedgerScorecardState();
}

class ScoreBox {
  const ScoreBox(this.label, this.value, this.tone, {this.wide = false});
  final String label;
  final String value;
  final ScoreTone tone;
  final bool wide;
}

enum ScoreTone { emerald, red, sky, violet, amber, slate }

(Color bg, Color border, Color label, Color value) _tone(ScoreTone t) => switch (t) {
      ScoreTone.emerald => (TColors.emerald100, TColors.emerald300, TColors.emerald900, TColors.emerald800),
      ScoreTone.red => (TColors.red100, TColors.red300, TColors.red900, TColors.red800),
      ScoreTone.sky => (TColors.sky100, TColors.sky300, TColors.sky900, TColors.sky800),
      ScoreTone.violet => (TColors.violet100, TColors.violet200, TColors.violet800, TColors.violet700),
      ScoreTone.amber => (TColors.amber100, TColors.amber300, TColors.amber900, TColors.amber800),
      ScoreTone.slate => (TColors.slate100, TColors.slate300, TColors.slate700, TColors.slate800),
    };

class _LedgerScorecardState extends State<LedgerScorecard> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final striped = widget.index.isEven;
    return Container(
      decoration: BoxDecoration(
        color: striped ? TColors.blue100 : Colors.white,
        border: Border.all(color: striped ? TColors.blue300 : TColors.slate200),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(widget.title,
                              style: const TextStyle(fontWeight: FontWeight.w600, color: TColors.slate900)),
                          if (widget.badge != null) TBadge(widget.badge!, bg: TColors.blue200, fg: TColors.blue900),
                        ],
                      ),
                    ),
                    ?widget.trailing,
                    Icon(_open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        size: 18, color: TColors.slate400),
                  ],
                ),
                if (widget.boxes.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  LayoutBuilder(builder: (context, c) {
                    final half = (c.maxWidth - 8) / 2;
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final box in widget.boxes)
                          SizedBox(width: box.wide ? c.maxWidth : half, child: _ScoreBoxView(box)),
                      ],
                    );
                  }),
                ],
              ],
            ),
          ),
          if (_open && (widget.details.isNotEmpty || widget.actions.isNotEmpty)) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: TColors.slate200),
            const SizedBox(height: 12),
            for (final (label, value) in widget.details)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Wrap(
                  spacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(label, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
                    DefaultTextStyle.merge(
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: TColors.slate900),
                      child: value,
                    ),
                  ],
                ),
              ),
            if (widget.actions.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  for (var i = 0; i < widget.actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(child: widget.actions[i]),
                  ],
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _ScoreBoxView extends StatelessWidget {
  const _ScoreBoxView(this.box);
  final ScoreBox box;
  @override
  Widget build(BuildContext context) {
    final (bg, border, label, value) = _tone(box.tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(box.label.toUpperCase(),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .4, color: label)),
          Text(box.value, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: value)),
        ],
      ),
    );
  }
}

class TBadge extends StatelessWidget {
  const TBadge(this.label, {super.key, required this.bg, required this.fg, this.border});
  final String label;
  final Color bg, fg;
  final Color? border;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: border == null ? null : Border.all(color: border!),
        ),
        child: Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: fg)),
      );
}

/// Edit / Delete buttons on an adjustment scorecard.
Widget scoreAction(String label, IconData icon, VoidCallback onTap, {bool danger = false}) => OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: danger ? TColors.red600 : TColors.slate800,
        minimumSize: const Size.fromHeight(40),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
    );

/// The table's Edit / Delete icon pair, compact enough for its column.
Widget rowActions({required VoidCallback onEdit, required VoidCallback onDelete}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Edit adjustment',
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.edit_outlined, size: 18),
          onPressed: onEdit,
        ),
        IconButton(
          tooltip: 'Delete adjustment',
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.delete_outline, size: 18, color: TColors.red600),
          onPressed: onDelete,
        ),
      ],
    );

/// "View table format ⌄" under the scorecards.
class ViewTableButton extends StatelessWidget {
  const ViewTableButton({super.key, required this.onPressed});
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: TColors.slate50,
          border: Border.all(color: TColors.slate200),
          borderRadius: BorderRadius.circular(8),
        ),
        child: TextButton.icon(
          onPressed: onPressed,
          iconAlignment: IconAlignment.end,
          icon: const Icon(Icons.keyboard_arrow_down, size: 16),
          label: const Text('View table format'),
          style: TextButton.styleFrom(foregroundColor: TColors.slate600, minimumSize: const Size.fromHeight(40)),
        ),
      );
}

/// "Table view • Scroll for more   ⌃ Cards" above the table.
class TableViewBar extends StatelessWidget {
  const TableViewBar({super.key, required this.onCards, this.text = 'Table view - scroll for more'});
  final VoidCallback onCards;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: const BoxDecoration(
          color: TColors.slate50,
          border: Border(bottom: BorderSide(color: TColors.slate200)),
        ),
        child: Row(
          children: [
            Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: TColors.slate600))),
            TextButton.icon(
              onPressed: onCards,
              icon: const Icon(Icons.keyboard_arrow_up, size: 16),
              label: const Text('Cards'),
            ),
          ],
        ),
      );
}

// ------------------------------------------------------------------ table

class TCol {
  const TCol(this.label, {this.sortKey, this.right = false, this.width = 110});
  final String label;
  final String? sortKey;
  final bool right;
  final double width;
}

/// A horizontally scrolling table with sortable headers and an optional
/// footer row, the web's `Table` + `SortableHeader` + `TableFooter`.
class TrackerTable extends StatelessWidget {
  const TrackerTable({
    super.key,
    required this.columns,
    required this.rows,
    this.footer,
    this.sort,
    this.onSort,
    this.emptyText,
  });
  final List<TCol> columns;
  final List<List<Widget>> rows;
  final List<Widget>? footer;
  final SortState? sort;
  final ValueChanged<String>? onSort;
  final String? emptyText;

  Widget _cell(TCol c, Widget child, {bool header = false, Color? bg}) => Container(
        width: c.width,
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        alignment: c.right ? Alignment.centerRight : Alignment.centerLeft,
        child: DefaultTextStyle.merge(
          style: TextStyle(
            fontSize: 13,
            color: header ? TColors.slate600 : TColors.slate900,
            fontWeight: header ? FontWeight.w600 : FontWeight.w400,
          ),
          child: child,
        ),
      );

  @override
  Widget build(BuildContext context) {
    Widget header(TCol c) {
      if (c.sortKey == null || onSort == null) return Text(c.label);
      final active = sort?.key == c.sortKey && sort?.dir != null;
      return InkWell(
        onTap: () => onSort!(c.sortKey!),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Text(c.label)),
            const SizedBox(width: 2),
            Icon(
              !active
                  ? Icons.unfold_more
                  : sort!.dir == SortDir.asc
                      ? Icons.arrow_upward
                      : Icons.arrow_downward,
              size: 13,
              color: active ? TColors.slate900 : TColors.slate400,
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: TColors.slate200))),
            child: Row(children: [for (final c in columns) _cell(c, header(c), header: true)]),
          ),
          if (rows.isEmpty && emptyText != null)
            SizedBox(
              width: columns.fold<double>(0, (s, c) => s + c.width),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text(emptyText!, style: const TextStyle(color: TColors.slate500))),
              ),
            ),
          for (final r in rows)
            Container(
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: TColors.slate100))),
              child: Row(children: [for (var i = 0; i < columns.length; i++) _cell(columns[i], r[i])]),
            ),
          if (footer != null)
            Row(children: [
              for (var i = 0; i < columns.length; i++) _cell(columns[i], footer![i], bg: TColors.slate50),
            ]),
        ],
      ),
    );
  }
}

Text cellText(String s, {Color? color, bool bold = false, bool strike = false}) => Text(
      s,
      overflow: TextOverflow.ellipsis,
      maxLines: 2,
      style: TextStyle(
        color: color,
        fontWeight: bold ? FontWeight.w700 : null,
        decoration: strike ? TextDecoration.lineThrough : null,
      ),
    );

// ------------------------------------------------------------------ pagination

/// "Showing a-b of n  [10 / page]   Previous  Page x of y  Next".
class TrackerPager extends StatelessWidget {
  const TrackerPager({
    super.key,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.onPage,
    required this.onPageSize,
    this.showingLine = true,
    this.rowsLabel = false,
  });
  final int total;
  final int page;
  final int pageSize;
  final ValueChanged<int> onPage;
  final ValueChanged<int> onPageSize;

  /// "Showing a-b of n" (Egg/Feed/Medication) rather than nothing.
  final bool showingLine;

  /// Birds' "Page x of y (n rows)" wording.
  final bool rowsLabel;

  int get totalPages => total == 0 ? 1 : ((total + pageSize - 1) ~/ pageSize);

  @override
  Widget build(BuildContext context) {
    final safe = page.clamp(1, totalPages);
    final from = (safe - 1) * pageSize + 1;
    final to = (safe * pageSize).clamp(0, total);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: const BoxDecoration(
        color: TColors.slate50,
        border: Border(top: BorderSide(color: TColors.slate200)),
      ),
      child: Column(
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 6,
            children: [
              if (rowsLabel)
                Text('Page $safe of $totalPages ($total rows)',
                    style: const TextStyle(fontSize: 12, color: TColors.slate600))
              else if (showingLine)
                Text('Showing $from-$to of $total', style: const TextStyle(fontSize: 12, color: TColors.slate600)),
              SizedBox(
                width: 120,
                child: AppSelect<int>(
                  value: pageSize,
                  items: [for (final n in trackerPageSizes) AppSelectItem(value: n, label: '$n / page')],
                  onChanged: (v) {
                    if (v != null) onPageSize(v);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Wraps rather than overflowing on a 360 px phone.
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 4,
            children: [
              OutlinedButton(onPressed: safe <= 1 ? null : () => onPage(safe - 1), child: const Text('Previous')),
              if (!rowsLabel)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text('Page $safe of $totalPages', style: const TextStyle(fontSize: 12, color: TColors.slate600)),
                )
              else
                const SizedBox(width: 8),
              OutlinedButton(
                  onPressed: safe >= totalPages ? null : () => onPage(safe + 1), child: const Text('Next')),
            ],
          ),
        ],
      ),
    );
  }
}

List<T> pageOf<T>(List<T> rows, int page, int size) {
  final pages = rows.isEmpty ? 1 : (rows.length + size - 1) ~/ size;
  final safe = page.clamp(1, pages);
  final start = (safe - 1) * size;
  if (start >= rows.length) return const [];
  return rows.sublist(start, (start + size).clamp(0, rows.length));
}

// ------------------------------------------------------------------ filters

/// A labelled date box that can be cleared, for the ledger filters.
class FilterDate extends StatelessWidget {
  const FilterDate({super.key, required this.value, required this.onChanged, required this.hint});
  final String value; // yyyy-MM-dd or ''
  final ValueChanged<String> onChanged;
  final String hint;
  @override
  Widget build(BuildContext context) {
    final d = businessDateAsDateTime(value);
    return Row(
      children: [
        Expanded(
          child: AppDateField(
            value: d,
            hintText: hint,
            onChanged: (v) => onChanged(v == null ? '' : isoDay(v)),
          ),
        ),
        if (value.isNotEmpty)
          IconButton(
            tooltip: 'Clear $hint',
            icon: const Icon(Icons.close, size: 16),
            onPressed: () => onChanged(''),
          ),
      ],
    );
  }
}

class FilterLabel extends StatelessWidget {
  const FilterLabel(this.text, this.child, {super.key});
  final String text;
  final Widget child;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: TColors.slate700)),
          const SizedBox(height: 4),
          child,
        ],
      );
}

/// Two filter controls side by side.
Widget filterRow(List<Widget> children) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: children[i]),
        ],
      ],
    );

// ------------------------------------------------------------------ dialogs

Future<bool> confirmDelete(BuildContext context,
    {required String title, required String description, String confirmLabel = 'Delete'}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(description),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: TColors.red600),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

/// The Egg / Feed "Add adjustment" dialog. Returns null on cancel.
class AdjustmentForm {
  AdjustmentForm(this.type, this.date, this.delta, this.description);
  String type;
  String date; // yyyy-MM-dd
  String delta;
  String description;
}

class AdjustmentDialog extends StatefulWidget {
  const AdjustmentDialog({
    super.key,
    required this.title,
    required this.description,
    required this.deltaLabel,
    required this.deltaHint,
    required this.decimal,
    required this.initial,
    required this.editing,
    required this.onSave,
  });
  final String title;
  final String description;
  final String deltaLabel;
  final String deltaHint;
  final bool decimal;
  final AdjustmentForm initial;
  final bool editing;

  /// Returns true when saved; the dialog then closes.
  final Future<bool> Function(AdjustmentForm form) onSave;

  @override
  State<AdjustmentDialog> createState() => _AdjustmentDialogState();
}

class _AdjustmentDialogState extends State<AdjustmentDialog> {
  late final AdjustmentForm f = widget.initial;
  late final _delta = TextEditingController(text: f.delta);
  late final _desc = TextEditingController(text: f.description);
  bool _busy = false;

  @override
  void dispose() {
    _delta.dispose();
    _desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.description, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 14),
            FilterLabel(
              'Type',
              AppSelect<String>(
                value: f.type,
                items: [for (final (v, l) in adjustmentTypes) AppSelectItem(value: v, label: l)],
                onChanged: (v) => setState(() => f.type = v ?? f.type),
              ),
            ),
            const SizedBox(height: 12),
            FilterLabel(
              'Date',
              AppDateField(
                value: businessDateAsDateTime(f.date),
                onChanged: (v) => setState(() => f.date = v == null ? '' : isoDay(v)),
              ),
            ),
            const SizedBox(height: 12),
            FilterLabel(
              widget.deltaLabel,
              AppInput(
                controller: _delta,
                hintText: widget.deltaHint,
                keyboardType: TextInputType.numberWithOptions(signed: true, decimal: widget.decimal),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(widget.decimal ? RegExp(r'^-?\d*[.,]?\d*') : RegExp(r'^-?\d*')),
                ],
                onChanged: (v) => f.delta = v,
              ),
            ),
            const SizedBox(height: 12),
            FilterLabel(
              'Description (optional)',
              AppInput(
                controller: _desc,
                hintText: 'e.g. Stocktake correction',
                onChanged: (v) => f.description = v,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        AppButton(
          label: widget.editing ? 'Update' : 'Save',
          busy: _busy,
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  final ok = await widget.onSave(f);
                  if (!context.mounted) return;
                  setState(() => _busy = false);
                  if (ok) Navigator.pop(context);
                },
        ),
      ],
    );
  }
}

/// The ISO timestamp the web sends for a picked day: noon local, as UTC.
String adjustmentIso(String day) {
  final d = businessDateAsDateTime(day);
  if (d == null) return DateTime.now().toUtc().toIso8601String();
  return DateTime(d.year, d.month, d.day, 12).toUtc().toIso8601String();
}

// ------------------------------------------------------------------ cost breakdown

const _operationalCostTip =
    'The stock this activity actually used up, at what it cost. Some of it may have been charged to Profit & Loss earlier, when it was bought.';
const _newlyRecognizedTip = 'The part of this usage that is being charged to Profit & Loss now.';
const _alreadyExpensedTip =
    'The part of this usage that was already charged to Profit & Loss when the stock was bought. It is not charged again.';
const _noSecondPaymentTip =
    'Charging this to Profit & Loss moves no money. The cash left the business when the stock was bought.';

/// "View cost breakdown": which purchase lots one usage drew from.
/// GET /api/Poultry/deferred-inventory-costs/breakdown/{productionRecordId}.
Future<void> showCostBreakdown(
  BuildContext context, {
  required Session session,
  required Company company,
  required int productionRecordId,
  required FarmMoney money,
  String title = 'Cost breakdown',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .8,
      maxChildSize: .95,
      builder: (ctx, controller) => _CostBreakdownBody(
        controller: controller,
        session: session,
        company: company,
        id: productionRecordId,
        money: money,
        title: title,
      ),
    ),
  );
}

class _CostBreakdownBody extends StatefulWidget {
  const _CostBreakdownBody({
    required this.controller,
    required this.session,
    required this.company,
    required this.id,
    required this.money,
    required this.title,
  });
  final ScrollController controller;
  final Session session;
  final Company company;
  final int id;
  final FarmMoney money;
  final String title;
  @override
  State<_CostBreakdownBody> createState() => _CostBreakdownBodyState();
}

class _CostBreakdownBodyState extends State<_CostBreakdownBody> {
  List<Map>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await widget.session.farmClient.get(
          '/api/Poultry/deferred-inventory-costs/breakdown/${widget.id}',
          query: {'farmId': widget.company.farmId});
      if (!mounted) return;
      setState(() => _rows = [if (res is List) for (final r in res) if (r is Map) r]);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  (String, String) _explain(String raw) {
    final t = raw.toLowerCase();
    if (t.contains('does not exist') || t.contains('undefined function') || t.contains('42883')) {
      return (
        'The cost breakdown aren\'t switched on yet.',
        'This company\'s database is missing an update this screen needs. Ask whoever looks after your system to apply it — nothing is wrong with your data.'
      );
    }
    if (t.contains('401') || t.contains('403') || t.contains('unauthor') || t.contains('forbid')) {
      return ('You do not have permission to view this.', 'Ask an administrator to give you access for this company.');
    }
    return ('Could not load the cost breakdown.', 'Check your connection and try again. Nothing has been changed.');
  }

  @override
  Widget build(BuildContext context) {
    final gh = widget.money;
    final rows = _rows;
    final live = [for (final r in rows ?? const <Map>[]) if (!tBool(r['isReversed'])) r];
    final operational = live.fold<num>(0, (a, r) => a + tNum(r['operationalCost']));
    final recognized = live.fold<num>(0, (a, r) => a + tNum(r['recognizedCost']));
    final already = operational - recognized;
    final quantity = live.fold<num>(0, (a, r) => a + tNum(r['quantityDrawn']));
    final unit = live.isNotEmpty ? tStr(live.first['productionUnit']) : '';

    Widget figure(String label, String value, ScoreTone tone, [String? hint]) {
      final (bg, border, l, v) = _tone(tone);
      return Tooltip(
        message: hint ?? '',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: l)),
            Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: v)),
          ]),
        ),
      );
    }

    Widget section(String label) => Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 6),
          child: Text(label.toUpperCase(),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: TColors.slate500)),
        );

    return ListView(
      controller: widget.controller,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Row(children: [
          const Icon(Icons.layers_outlined, size: 18, color: Color(0xFF0284C7)),
          const SizedBox(width: 8),
          Expanded(child: Text(widget.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 4),
        const Text('Which purchase lots this usage drew from, and how much of that cost reaches Profit & Loss today.',
            style: TextStyle(fontSize: 13, color: TColors.slate500)),
        const SizedBox(height: 12),
        if (_error != null) ...[
          const Icon(Icons.warning_amber_rounded, color: TColors.amber600, size: 28),
          Text(_explain(_error!).$1, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(_explain(_error!).$2, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          ExpansionTile(
            title: const Text('Technical detail', style: TextStyle(fontSize: 12, color: TColors.slate400)),
            children: [Text(_error!, style: const TextStyle(fontFamily: 'monospace', fontSize: 11))],
          ),
        ] else if (rows == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Row(children: [
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 8),
              Flexible(child: Text('Loading cost breakdown…', style: TextStyle(color: TColors.slate500))),
            ]),
          )
        else if (rows.isEmpty)
          const Text(
              'No cost layers were recorded for this record. Stock removed by a manual adjustment or internal-use entry does not draw from purchase lots, so it has no breakdown.',
              style: TextStyle(fontSize: 13, color: TColors.slate500))
        else ...[
          section('What this cost'),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.4,
            children: [
              figure('Total quantity', '${loc(quantity)}${unit.isNotEmpty ? ' $unit' : ''}', ScoreTone.sky),
              figure('Stock used (cost)', gh(operational), ScoreTone.violet, _operationalCostTip),
              figure('Effective unit cost',
                  quantity > 0 ? '${gh(operational / quantity)}${unit.isNotEmpty ? ' / $unit' : ''}' : '—', ScoreTone.slate),
              figure('Already expensed earlier', gh(already), ScoreTone.emerald, _alreadyExpensedTip),
              figure('Charged to P&L now', gh(recognized), recognized > 0 ? ScoreTone.amber : ScoreTone.slate,
                  _newlyRecognizedTip),
            ],
          ),
          section('Where it came from${rows.length > 1 ? ' · ${rows.length} lots' : ''}'),
          for (var i = 0; i < rows.length; i++) _lot(rows[i], i, gh),
          const SizedBox(height: 8),
          const Text(_noSecondPaymentTip, style: TextStyle(fontSize: 11, color: TColors.slate500)),
        ],
      ],
    );
  }

  Widget _lot(Map r, int i, FarmMoney gh) {
    final reversed = tBool(r['isReversed']);
    final rec = tNum(r['recognizedCost']);
    final strike = reversed ? TextDecoration.lineThrough : null;
    final meta = [
      '#${r['poultryRawMaterialPurchaseId']}',
      if (tStr(r['purchaseDate']).isNotEmpty) formatShortDate(r['purchaseDate']),
      if (tStr(r['supplierName']).isNotEmpty) tStr(r['supplierName']),
      if (tStr(r['feedProductionBatchNumber']).isNotEmpty) tStr(r['feedProductionBatchNumber']),
    ].join(' · ');
    Widget fact(String l, String v, [Color? c]) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l, style: const TextStyle(fontSize: 11, color: TColors.slate500)),
          Text(v, style: TextStyle(fontWeight: FontWeight.w500, color: c ?? TColors.slate900, decoration: strike)),
        ]);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: reversed ? TColors.rose100 : (i.isEven ? TColors.blue100 : Colors.white),
        border: Border(
          left: BorderSide(color: reversed ? TColors.rose500 : (i.isEven ? TColors.blue300 : TColors.slate200), width: 4),
          top: BorderSide(color: reversed ? TColors.rose200 : TColors.slate200),
          right: BorderSide(color: reversed ? TColors.rose200 : TColors.slate200),
          bottom: BorderSide(color: reversed ? TColors.rose200 : TColors.slate200),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tStr(r['itemName']), style: TextStyle(fontWeight: FontWeight.w500, decoration: strike)),
              Text(meta, style: const TextStyle(fontSize: 11, color: TColors.slate500)),
            ]),
          ),
          TBadge(tStr(r['recognitionLabel']),
              bg: rec > 0 ? TColors.amber50 : TColors.emerald50,
              fg: rec > 0 ? TColors.amber800 : TColors.emerald800,
              border: rec > 0 ? TColors.amber300 : TColors.emerald300),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 18, runSpacing: 6, children: [
          fact('Qty drawn', '${loc(tNum(r['quantityDrawn']))}${tStr(r['productionUnit']).isNotEmpty ? ' ${r['productionUnit']}' : ''}'),
          fact('Unit cost', gh(tNum(r['unitCostAtDraw']))),
          fact('Cost', gh(tNum(r['operationalCost']))),
          fact('New expense', rec > 0 ? gh(rec) : '—', rec > 0 ? TColors.amber700 : TColors.slate300),
        ]),
      ]),
    );
  }
}

/// The "Cost recognised" cell: recognised / of stock cost / View cost breakdown.
class RecognizedCostCell extends StatelessWidget {
  const RecognizedCostCell({
    super.key,
    required this.cost,
    required this.recognized,
    required this.reversed,
    required this.money,
    this.onBreakdown,
  });
  final num? cost;
  final num? recognized;
  final bool reversed;
  final FarmMoney money;
  final VoidCallback? onBreakdown;
  @override
  Widget build(BuildContext context) {
    if (cost == null) return const Text('—', style: TextStyle(color: TColors.slate300));
    if (reversed) return const Text('Reversed', style: TextStyle(color: TColors.slate400));
    final rec = recognized ?? 0;
    return Tooltip(
      message: recognizedCostNote(rec, cost!),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(money(rec),
              style: TextStyle(
                  fontWeight: rec > 0 ? FontWeight.w500 : FontWeight.w400,
                  color: rec > 0 ? TColors.amber700 : TColors.slate500)),
          Text(rec > 0 ? 'of ${money(cost)} stock cost' : '${money(cost)} expensed at purchase',
              textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, color: TColors.slate500)),
          if (onBreakdown != null)
            InkWell(
              onTap: onBreakdown,
              child: const Text('View cost breakdown',
                  style: TextStyle(
                      fontSize: 11,
                      color: TColors.blue600,
                      decoration: TextDecoration.underline,
                      decorationStyle: TextDecorationStyle.dotted)),
            ),
        ],
      ),
    );
  }
}

/// Lists from an API answer that may be a bare list or wrapped.
List<Map> rowsOf(Object? res) {
  if (res is List) return [for (final r in res) if (r is Map) r];
  if (res is Map) {
    for (final k in const ['data', 'items', 'rows', 'result']) {
      final v = res[k];
      if (v is List) return [for (final r in v) if (r is Map) r];
    }
  }
  return const [];
}
