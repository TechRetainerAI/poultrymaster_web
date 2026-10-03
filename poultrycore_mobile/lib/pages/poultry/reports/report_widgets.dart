// Shared building blocks for the Poultry reports, as the web's
// `components/poultry-reports/poultry-report-ui.tsx`,
// `report-data-table.tsx` (its phone layout) and `poultry-report-filter.tsx`.

import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/buttons.dart';
import '../../../design/ui/inputs.dart';
import '../../shared/business_dates.dart';
import 'report_defs.dart';
import 'report_export.dart';
import 'report_format.dart';

// Tailwind tones.
const slate50 = Color(0xFFF8FAFC);
const slate100 = Color(0xFFF1F5F9);
const slate200 = Color(0xFFE2E8F0);
const slate300 = Color(0xFFCBD5E1);
const slate400 = Color(0xFF94A3B8);
const slate500 = Color(0xFF64748B);
const slate600 = Color(0xFF475569);
const slate700 = Color(0xFF334155);
const slate800 = Color(0xFF1E293B);
const slate900 = Color(0xFF0F172A);
const emerald500 = Color(0xFF10B981);
const emerald700 = Color(0xFF047857);
const rose500 = Color(0xFFF43F5E);
const rose700 = Color(0xFFBE123C);
const indigo500 = Color(0xFF6366F1);
const indigo700 = Color(0xFF4338CA);
const amber50 = Color(0xFFFFFBEB);
const amber100 = Color(0xFFFEF3C7);
const amber200 = Color(0xFFFDE68A);
const amber400 = Color(0xFFFBBF24);
const amber500 = Color(0xFFF59E0B);
const amber700 = Color(0xFFB45309);
const amber800 = Color(0xFF92400E);

Color accentValue(String? a) => switch (a) {
      'green' => emerald700,
      'rose' => rose700,
      'indigo' => indigo700,
      _ => slate900,
    };

Color accentRail(String? a) => switch (a) {
      'green' => emerald500,
      'rose' => rose500,
      'indigo' => indigo500,
      _ => amber400,
    };

// ------------------------------------------------------------ status badge

const _good = ['good', 'profit', 'paid', 'complete', 'in stock', 'ok', 'settled', 'balanced', 'active', 'completed'];
const _warn = ['watch', 'owing', 'incomplete', 'low', 'minor variance', 'not itemised', 'n/a', 'part paid'];
const _bad = ['critical', 'loss', 'unpaid', 'high', 'out of stock', 'check count', 'empty', 'closed', 'overdue'];

class ReportStatusBadge extends StatelessWidget {
  const ReportStatusBadge(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    final (bg, fg, border) = _good.contains(s)
        ? (const Color(0xFFD1FAE5), const Color(0xFF065F46), const Color(0xFFA7F3D0))
        : _bad.contains(s)
            ? (const Color(0xFFFFE4E6), const Color(0xFF9F1239), const Color(0xFFFECDD3))
            : _warn.contains(s)
                ? (amber100, amber800, amber200)
                : (slate100, slate700, slate200);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(6)),
      child: Text(status.isEmpty ? '—' : status, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: fg)),
    );
  }
}

// ------------------------------------------------------------------ states

class ReportLoading extends StatelessWidget {
  const ReportLoading({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 8),
          Text('Loading report…', style: TextStyle(color: slate400, fontSize: 13)),
        ]),
      );
}

class ReportEmpty extends StatelessWidget {
  const ReportEmpty({super.key, this.message});
  final String? message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(children: [
          const Icon(Icons.inbox_outlined, size: 40, color: slate300),
          const SizedBox(height: 8),
          const Text('No data for this selection', style: TextStyle(fontWeight: FontWeight.w500, color: slate700)),
          const SizedBox(height: 4),
          Text(message ?? 'Try a different date range or clear the filters.',
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: slate500)),
        ]),
      );
}

class ReportError extends StatelessWidget {
  const ReportError(this.message, {super.key, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1F2),
          border: Border.all(color: const Color(0xFFFECDD3)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.error_outline, size: 16, color: Color(0xFF9F1239))),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 13, color: Color(0xFF9F1239)))),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFE11D48), visualDensity: VisualDensity.compact),
              child: const Text('Retry', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
            ),
        ]),
      );
}

/// Backend notices: amber with a warning icon for warnings, plain slate with
/// an info icon for notes, so the two never look alike.
class ReportNotices extends StatelessWidget {
  const ReportNotices({super.key, required this.lines, required this.warning});
  final List<String> lines;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: warning ? amber50 : slate50,
        border: Border.all(color: warning ? amber200 : slate200),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(warning ? Icons.warning_amber_rounded : Icons.info_outline,
                    size: 14, color: warning ? amber800 : slate400),
              ),
              const SizedBox(width: 6),
              Expanded(child: Text(l, style: TextStyle(fontSize: 12, color: warning ? amber800 : slate600))),
            ]),
          ),
      ]),
    );
  }
}

// ----------------------------------------------------------- summary cards

typedef SummaryCardData = ({String label, String value, String? accent, String? note});

class SummaryCards extends StatelessWidget {
  const SummaryCards(this.cards, {super.key});
  final List<SummaryCardData> cards;

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: twoColumns([
        for (final c in cards)
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: slate200),
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1))],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.label.toUpperCase(), style: const TextStyle(fontSize: 10.5, letterSpacing: .5, color: slate500)),
                  const SizedBox(height: 4),
                  Text(c.value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: accentValue(c.accent))),
                  if (c.note != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(c.note!, style: const TextStyle(fontSize: 10, color: slate500)),
                    ),
                ]),
              ),
              Positioned(left: 0, top: 0, bottom: 0, width: 4, child: ColoredBox(color: accentRail(c.accent))),
            ]),
          ),
      ]),
    );
  }
}

/// Two equal columns that wrap, as the web's phone `grid-cols-2`.
Widget twoColumns(List<Widget> children, {double gap = 10}) => LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - gap) / 2;
      return Wrap(spacing: gap, runSpacing: gap, children: [for (final x in children) SizedBox(width: w, child: x)]);
    });

// --------------------------------------------------------------- the table

typedef TableColumn = ({String header, bool right, bool badge});

/// One sortable value per cell (strings, as the web sorts formatted cells).
int smartCompare(String? a, String? b) {
  if (a == null && b == null) return 0;
  if (a == null) return -1;
  if (b == null) return 1;
  bool looksDate(String s) => RegExp(r'[a-zA-Z]').hasMatch(s) || RegExp(r'[-/]').hasMatch(s);
  final ad = DateTime.tryParse(a), bd = DateTime.tryParse(b);
  if (looksDate(a) && looksDate(b) && ad != null && bd != null) return ad.compareTo(bd);
  num? loose(String v) {
    final c = v.replaceAll(RegExp(r'[^0-9.\-]'), '');
    if (c.isEmpty || c == '-' || c == '.') return null;
    return num.tryParse(c);
  }

  final an = loose(a), bn = loose(b);
  if (an != null && bn != null) return an.compareTo(bn);
  return a.toLowerCase().compareTo(b.toLowerCase());
}

/// The web's ReportDataTable as phones see it: a sort picker, one card per
/// row (amber header strip with the first value and its number), the totals
/// card, then "Showing a–b of n", the page size and the page numbers.
class ReportTable extends StatefulWidget {
  const ReportTable({
    super.key,
    required this.columns,
    required this.rows,
    this.totals,
    this.empty = 'No data for the selected filters.',
    this.cellColor,
  });
  final List<TableColumn> columns;
  final List<List<String>> rows;

  /// A coloured cell (the web's green / red Net, "Strong day"); null = plain.
  final Color? Function(List<String> row, int col)? cellColor;
  final List<String>? totals;
  final String empty;

  @override
  State<ReportTable> createState() => _ReportTableState();
}

class _ReportTableState extends State<ReportTable> {
  int? _sortCol;
  bool _desc = false;
  int _page = 1;
  int _pageSize = 10;

  @override
  void didUpdateWidget(ReportTable old) {
    super.didUpdateWidget(old);
    if (!identical(old.rows, widget.rows)) _page = 1;
  }

  List<List<String>> get _sorted {
    final c = _sortCol;
    if (c == null) return widget.rows;
    final s = [...widget.rows]..sort((a, b) => smartCompare(a[c], b[c]));
    return _desc ? s.reversed.toList() : s;
  }

  List<(int?, int)> _pageNumbers(int total, int page) {
    // (page, key); null = ellipsis.
    final List<int?> p;
    if (total <= 7) {
      p = [for (var i = 1; i <= total; i++) i];
    } else if (page <= 3) {
      p = [1, 2, 3, 4, null, total];
    } else if (page >= total - 2) {
      p = [1, null, total - 3, total - 2, total - 1, total];
    } else {
      p = [1, null, page - 1, page, page + 1, null, total];
    }
    return [for (final (i, x) in p.indexed) (x, i)];
  }

  Widget _cell(int ci, String v, {bool bold = false, List<String>? row}) {
    final col = widget.columns[ci];
    if (col.badge && !bold) return ReportStatusBadge(v);
    final tint = row == null ? null : widget.cellColor?.call(row, ci);
    return Text(v,
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize: 13.5,
          color: tint ?? (bold ? slate900 : slate800),
          fontWeight: bold || tint != null ? FontWeight.w600 : FontWeight.w400,
          fontFeatures: col.right ? const [FontFeature.tabularFigures()] : null,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    if (rows.isEmpty) return Text(widget.empty, style: const TextStyle(fontSize: 13, color: slate500));
    final sorted = _sorted;
    final total = sorted.length;
    final pages = (total / _pageSize).ceil().clamp(1, 1 << 30);
    final page = _page.clamp(1, pages);
    final start = (page - 1) * _pageSize;
    final end = (start + _pageSize).clamp(0, total);
    final pageRows = sorted.sublist(start, end);
    final cols = widget.columns;

    Widget dl(List<String> values, {bool bold = false}) => Column(children: [
          for (var ci = bold ? 0 : 1; ci < values.length && ci < cols.length; ci++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                border: ci == (bold ? 0 : 1) ? null : Border(top: BorderSide(color: bold ? slate200 : slate100)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(cols[ci].header, style: const TextStyle(fontSize: 12, color: slate500)),
                const SizedBox(width: 12),
                Expanded(child: Align(alignment: Alignment.centerRight, child: _cell(ci, values[ci], bold: bold, row: bold ? null : values))),
              ]),
            ),
        ]);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: AppSelect<String>(
            value: _sortCol == null ? 'none' : '$_sortCol',
            hintText: 'Sort by…',
            items: [
              const AppSelectItem(value: 'none', label: 'No sorting'),
              for (final (i, c) in cols.indexed) AppSelectItem(value: '$i', label: c.header),
            ],
            onChanged: (v) => setState(() {
              _page = 1;
              if (v == null || v == 'none') {
                _sortCol = null;
                _desc = false;
              } else {
                final next = int.parse(v);
                if (next != _sortCol) _desc = false;
                _sortCol = next;
              }
            }),
          ),
        ),
        const SizedBox(width: 8),
        AppButton(
          label: _desc ? 'Desc' : 'Asc',
          icon: _desc ? Icons.arrow_downward : Icons.arrow_upward,
          variant: AppButtonVariant.outline,
          size: AppButtonSize.sm,
          onPressed: _sortCol == null ? null : () => setState(() => _desc = !_desc),
        ),
      ]),
      const SizedBox(height: 10),
      for (final (ri, r) in pageRows.indexed) ...[
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: slate200),
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1))],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(color: amber50, border: Border(bottom: BorderSide(color: amber200))),
              child: Row(children: [
                Expanded(
                  child: cols[0].badge
                      ? Align(alignment: Alignment.centerLeft, child: ReportStatusBadge(r[0]))
                      : Text(r[0], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: slate800)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: amber100, borderRadius: BorderRadius.circular(99)),
                  child: Text('#${start + ri + 1}',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: .6, color: amber700)),
                ),
              ]),
            ),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: dl(r)),
          ]),
        ),
        const SizedBox(height: 10),
      ],
      if (widget.totals != null) ...[
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: slate100,
            border: Border.all(color: slate300, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: dl(widget.totals!, bold: true),
        ),
        const SizedBox(height: 10),
      ],
      Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('Showing ${total == 0 ? 0 : start + 1}–$end of ${fmtNum(total, 0)}',
            style: const TextStyle(fontSize: 13, color: slate600)),
        SizedBox(
          width: 130,
          child: AppSelect<int>(
            value: _pageSize,
            items: [for (final n in const [10, 25, 50, 100]) AppSelectItem(value: n, label: '$n / page')],
            onChanged: (v) => setState(() {
              _pageSize = v ?? 10;
              _page = 1;
            }),
          ),
        ),
      ]),
      if (pages > 1) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 4, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          TextButton.icon(
            onPressed: page == 1 ? null : () => setState(() => _page = page - 1),
            icon: const Icon(Icons.chevron_left, size: 18),
            label: const Text('Previous'),
          ),
          for (final (p, k) in _pageNumbers(pages, page))
            p == null
                ? Padding(key: ValueKey('e$k'), padding: const EdgeInsets.symmetric(horizontal: 4), child: const Text('…'))
                : SizedBox(
                    key: ValueKey('p$p'),
                    width: 36,
                    height: 36,
                    child: p == page
                        ? OutlinedButton(onPressed: null, style: OutlinedButton.styleFrom(padding: EdgeInsets.zero), child: Text('$p'))
                        : TextButton(
                            onPressed: () => setState(() => _page = p),
                            style: TextButton.styleFrom(padding: EdgeInsets.zero),
                            child: Text('$p'),
                          ),
                  ),
          TextButton(
            onPressed: page == pages ? null : () => setState(() => _page = page + 1),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [Text('Next'), Icon(Icons.chevron_right, size: 18)]),
          ),
        ]),
      ],
    ]);
  }
}

/// A definition's columns as a table, with its badges and totals.
ReportTable reportTableFor(List<ColumnDef> columns, List<Map> rows, FmtCtx ctx) => ReportTable(
      columns: [for (final c in columns) (header: c.header, right: c.right, badge: c.badge)],
      rows: [
        for (final r in rows) [for (final c in columns) c.cell(r, ctx)],
      ],
      totals: reportTotalsRow(columns, rows, ctx),
      empty: 'No rows for this selection.',
    );

// ------------------------------------------------------- breakdown + analysis

class ReportBreakdown extends StatelessWidget {
  const ReportBreakdown({super.key, required this.groups, required this.summary, required this.ctx});
  final List<BreakdownGroup> groups;
  final Map summary;
  final FmtCtx ctx;

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final g in groups)
        if (g.items(summary).isNotEmpty) g,
    ];
    if (shown.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final g in shown)
        Container(
          margin: const EdgeInsets.only(top: 14),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(border: Border.all(color: slate200), borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(g.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: slate800))),
              if (g.total != null)
                Text(g.total!(summary, ctx), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: slate900)),
            ]),
            const SizedBox(height: 10),
            for (final it in g.items(summary))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(child: Text(it.label, style: const TextStyle(fontSize: 12, color: slate600))),
                    Text.rich(TextSpan(style: const TextStyle(fontSize: 12, color: slate800), children: [
                      TextSpan(text: it.value(summary, ctx)),
                      if (it.percent(summary) != null)
                        TextSpan(
                            text: ' (${it.percent(summary)!.toStringAsFixed(1)}%)', style: const TextStyle(color: slate400)),
                    ])),
                  ]),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: clampPct(it.percent(summary)) / 100,
                      minHeight: 8,
                      color: g.green ? emerald500 : rose500,
                      backgroundColor: slate100,
                    ),
                  ),
                ]),
              ),
          ]),
        ),
    ]);
  }
}

class ReportAnalysis extends StatelessWidget {
  const ReportAnalysis({super.key, required this.title, required this.items});
  final String title;
  final List<AnalysisItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(border: Border.all(color: slate200), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: slate800)),
        const SizedBox(height: 10),
        for (final a in items)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: slate200), borderRadius: BorderRadius.circular(6)),
            clipBehavior: Clip.antiAlias,
            child: Stack(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 9, 10, 9),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.title,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: a.tone == 'good' ? const Color(0xFF065F46) : a.tone == 'watch' ? amber800 : slate800,
                      )),
                  const SizedBox(height: 3),
                  Text(a.detail, style: const TextStyle(fontSize: 11.5, color: slate600, height: 1.35)),
                ]),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 4,
                child: ColoredBox(color: a.tone == 'good' ? emerald500 : a.tone == 'watch' ? amber500 : slate300),
              ),
            ]),
          ),
      ]),
    );
  }
}

// ----------------------------------------------------------------- exports

class ReportExportButtons extends StatelessWidget {
  const ReportExportButtons({super.key, required this.onCsv, required this.onEmail, required this.onPdf, this.busy = false, this.disabled = false});
  final VoidCallback onCsv, onEmail, onPdf;
  final bool busy, disabled;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [
        AppButton(
            label: 'CSV', icon: Icons.table_chart_outlined, variant: AppButtonVariant.outline, size: AppButtonSize.sm, onPressed: disabled ? null : onCsv),
        AppButton(label: 'Email', icon: Icons.mail_outline, variant: AppButtonVariant.outline, size: AppButtonSize.sm, onPressed: disabled ? null : onEmail),
        AppButton(label: 'PDF', icon: Icons.print_outlined, size: AppButtonSize.sm, busy: busy, onPressed: disabled || busy ? null : onPdf),
      ]);
}

/// "Email “title”": recipients, comma separated; a PDF is generated and sent.
Future<void> showReportEmailDialog(
  BuildContext context, {
  required ApiClient client,
  required ReportDocument Function() document,
  required String defaultRecipient,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _EmailDialog(client: client, document: document, defaultRecipient: defaultRecipient),
    );

class _EmailDialog extends StatefulWidget {
  const _EmailDialog({required this.client, required this.document, required this.defaultRecipient});
  final ApiClient client;
  final ReportDocument Function() document;
  final String defaultRecipient;

  @override
  State<_EmailDialog> createState() => _EmailDialogState();
}

class _EmailDialogState extends State<_EmailDialog> {
  late final _to = TextEditingController(text: widget.defaultRecipient);
  bool _sending = false;

  @override
  void dispose() {
    _to.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final messenger = ScaffoldMessenger.of(context);
    final list = ReportExport.recipients(_to.text);
    if (list == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Enter a valid email address')));
      return;
    }
    setState(() => _sending = true);
    try {
      await ReportExport.email(widget.client, widget.document(), list);
      messenger.showSnackBar(SnackBar(
          content: Text('Report emailed. Sent to ${list.length == 1 ? list.first : '${list.length} recipients'}.')));
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Email failed. ${e.message.isEmpty ? 'Could not send.' : e.message}')));
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_sending,
        child: AlertDialog(
          title: Text('Email “${widget.document().title}”'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Recipient email(s)', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            AppInput(controller: _to, hintText: 'owner@example.com, accountant@example.com', keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 6),
            const Text('Separate multiple addresses with commas. A PDF of this report is generated and sent.',
                style: TextStyle(fontSize: 12, color: slate500)),
          ]),
          actions: [
            TextButton(onPressed: _sending ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
            FilledButton(onPressed: _sending ? null : _send, child: Text(_sending ? 'Sending…' : 'Send')),
          ],
        ),
      );
}

// ------------------------------------------------------------------ filter

class ReportFilterValue {
  ReportFilterValue({
    required this.fromDate,
    required this.toDate,
    this.flockId,
    this.customerName,
    this.supplierName,
    this.category,
    this.includeClosedFlocks = false,
  });
  String fromDate;
  String toDate;
  int? flockId;
  String? customerName;
  String? supplierName;
  String? category;
  bool includeClosedFlocks;

  static ReportFilterValue initial() {
    final r = defaultReportRange();
    return ReportFilterValue(fromDate: r.from, toDate: r.to);
  }
}

const _all = '__ALL__';

/// The filter bar, stacked one field per row as the web lays it out on a
/// phone: Period, From, To, then whichever of Flock / Customer / Supplier /
/// Category / Include closed flocks the report uses, then Clear.
class ReportFilterPanel extends StatefulWidget {
  const ReportFilterPanel({
    super.key,
    required this.value,
    required this.onChanged,
    required this.onReset,
    required this.show,
    this.flocks = const [],
    this.customers = const [],
    this.categories = const [],
  });
  final ReportFilterValue value;
  final VoidCallback onChanged;
  final VoidCallback onReset;
  final ReportFilters show;

  /// (id, name).
  final List<(int, String)> flocks;
  final List<String> customers;
  final List<String> categories;

  @override
  State<ReportFilterPanel> createState() => _ReportFilterPanelState();
}

class _ReportFilterPanelState extends State<ReportFilterPanel> {
  late final _supplier = TextEditingController(text: widget.value.supplierName ?? '');

  @override
  void didUpdateWidget(ReportFilterPanel old) {
    super.didUpdateWidget(old);
    final want = widget.value.supplierName ?? '';
    if (_supplier.text != want) _supplier.text = want;
  }

  @override
  void dispose() {
    _supplier.dispose();
    super.dispose();
  }

  Widget _field(String label, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: slate600)),
          const SizedBox(height: 4),
          child,
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final v = widget.value;
    void set(VoidCallback f) {
      f();
      widget.onChanged();
    }

    final period = rangeToPeriod(v.fromDate, v.toDate);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _field(
        'Period',
        AppSelect<String>(
          value: period,
          items: [
            for (final (group, opts) in periodGroups)
              for (final (k, l) in opts) AppSelectItem(value: k, label: '$l  ·  $group'),
          ],
          onChanged: (k) {
            final r = k == null ? null : periodToRange(k);
            if (r != null) {
              set(() {
                v.fromDate = r.from;
                v.toDate = r.to;
              });
            }
          },
        ),
      ),
      _field(
          'From',
          AppDateField(
            value: businessDateAsDateTime(v.fromDate),
            firstDate: DateTime(2000),
            onChanged: (d) {
              if (d != null) set(() => v.fromDate = isoDay(d));
            },
          )),
      _field(
          'To',
          AppDateField(
            value: businessDateAsDateTime(v.toDate),
            firstDate: DateTime(2000),
            onChanged: (d) {
              if (d != null) set(() => v.toDate = isoDay(d));
            },
          )),
      if (widget.show.flock)
        _field(
          'Flock',
          AppSelect<String>(
            value: v.flockId == null ? _all : '${v.flockId}',
            hintText: 'All flocks',
            items: [
              const AppSelectItem(value: _all, label: 'All flocks'),
              for (final (id, name) in widget.flocks) AppSelectItem(value: '$id', label: name),
            ],
            onChanged: (x) => set(() => v.flockId = x == null || x == _all ? null : int.tryParse(x)),
          ),
        ),
      if (widget.show.customer)
        _field(
          'Customer',
          AppSelect<String>(
            value: v.customerName ?? _all,
            hintText: 'All customers',
            items: [
              const AppSelectItem(value: _all, label: 'All customers'),
              for (final c in widget.customers) AppSelectItem(value: c, label: c),
            ],
            onChanged: (x) => set(() => v.customerName = x == null || x == _all ? null : x),
          ),
        ),
      if (widget.show.supplier)
        _field(
          'Supplier / payee',
          AppInput(
            controller: _supplier,
            hintText: 'Any supplier',
            onChanged: (x) => set(() => v.supplierName = x.isEmpty ? null : x),
          ),
        ),
      if (widget.show.category)
        _field(
          'Category',
          AppSelect<String>(
            value: v.category ?? _all,
            hintText: 'All categories',
            items: [
              const AppSelectItem(value: _all, label: 'All categories'),
              for (final c in widget.categories) AppSelectItem(value: c, label: c),
            ],
            onChanged: (x) => set(() => v.category = x == null || x == _all ? null : x),
          ),
        ),
      if (widget.show.includeClosedFlocks)
        AppCheckbox(
          value: v.includeClosedFlocks,
          onChanged: (x) => set(() => v.includeClosedFlocks = x),
          label: 'Include closed flocks',
        ),
      const SizedBox(height: 6),
      AppButton(label: 'Clear', variant: AppButtonVariant.outline, size: AppButtonSize.sm, fullWidth: true, onPressed: widget.onReset),
      const SizedBox(height: 12),
    ]);
  }
}

// ------------------------------------------------------------- letterhead

/// The report card's header: amber rail, farm, title, description, then
/// Period / Currency / Generated / Records.
class ReportLetterhead extends StatelessWidget {
  const ReportLetterhead({
    super.key,
    required this.farmName,
    required this.title,
    required this.description,
    required this.lines,
  });
  final String farmName;
  final String title;
  final String description;
  final List<(String, String)> lines;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.only(bottom: 12),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: slate200))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(farmName.toUpperCase(),
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: .8, color: amber700)),
          const SizedBox(height: 2),
          Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600, color: slate900)),
          const SizedBox(height: 4),
          Text(description, style: const TextStyle(fontSize: 13, color: slate500)),
          const SizedBox(height: 8),
          for (final (k, v) in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text.rich(TextSpan(style: const TextStyle(fontSize: 13, color: slate500), children: [
                TextSpan(text: '$k: ', style: const TextStyle(fontWeight: FontWeight.w500, color: slate600)),
                TextSpan(text: v),
              ])),
            ),
        ]),
      );
}

/// The white report card with the amber band across its top.
class ReportCard extends StatelessWidget {
  const ReportCard({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: slate200),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            height: 6,
            decoration: const BoxDecoration(gradient: LinearGradient(colors: [amber500, amber400])),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ]),
      );
}
