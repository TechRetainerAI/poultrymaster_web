// The frame every Generic report draws in, as
// `components/generic/report-shell.tsx`: back link, title, the period
// picker with From/To and Run, KPI tiles, and read-only tables that scroll
// sideways inside their own card on a phone.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../poultry/reports/report_format.dart' show periodGroups, periodToRange, rangeToPeriod;
import '../../poultry/trackers/tracker_logic.dart' show tNum, tStr;
import '../../poultry/trackers/tracker_widgets.dart';
import '../generic_kit.dart';

// ------------------------------------------------------------- formatting

final _money = NumberFormat.currency(name: 'GHS', symbol: 'GHS ', decimalDigits: 2);

/// fmtMoney: every report shows money the same way.
String fmtMoney(Object? n) => _money.format(tNum(n));

DateTime? _date(Object? d) => tStr(d).isEmpty ? null : DateTime.tryParse(tStr(d));

/// fmtMonth: "Oct 2026".
String fmtMonth(Object? d) => _date(d) == null ? '—' : DateFormat('MMM y').format(_date(d)!);

/// fmtDate: "Oct 30, 2026", or a dash.
String fmtDate(Object? d) => _date(d) == null ? '—' : DateFormat('MMM d, y').format(_date(d)!);

/// fmtPct: one decimal place.
String fmtPct(num n) => '${n.toStringAsFixed(1)}%';

String ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

typedef GenericRange = ({String from, String to});

/// currentMonthRange: this month, what a report opens on unless it says otherwise.
GenericRange currentMonthRange([DateTime? today]) {
  final n = today ?? DateTime.now();
  return (from: ymd(DateTime(n.year, n.month, 1)), to: ymd(n));
}

/// trailingMonthsRange: the last [months] months from a month boundary.
GenericRange trailingMonthsRange(int months, [DateTime? today]) {
  final n = today ?? DateTime.now();
  return (from: ymd(DateTime(n.year, n.month - (months - 1), 1)), to: ymd(n));
}

/// The rows of a list response.
List<Map<String, dynamic>> reportRows(Object? r) => [
      if (r is List)
        for (final x in r)
          if (x is Map) Map<String, dynamic>.from(x),
    ];

String reportError(Object e) => e is ApiException ? e.message : '$e';

// ------------------------------------------------------------- widgets

enum Accent { slate, emerald, rose, amber }

Color accentColor(Accent a) => switch (a) {
      Accent.slate => TColors.slate900,
      Accent.emerald => const Color(0xFF047857),
      Accent.rose => const Color(0xFFE11D48),
      Accent.amber => const Color(0xFFD97706),
    };

/// ReportStat: a KPI tile.
class ReportStat extends StatelessWidget {
  const ReportStat({super.key, required this.title, required this.value, this.hint, this.accent = Accent.slate});
  final String title;
  final String value;
  final String? hint;
  final Accent accent;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: TColors.slate200),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.toUpperCase(), style: const TextStyle(fontSize: 11, letterSpacing: 0.5, color: TColors.slate500)),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: accentColor(accent))),
            ),
            if (hint != null) ...[
              const SizedBox(height: 2),
              Text(hint!, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            ],
          ],
        ),
      );
}

/// The KPI tiles two to a row, as the web's grid-cols-2 on a phone.
class StatGrid extends StatelessWidget {
  const StatGrid(this.stats, {super.key, this.columns = 2});
  final List<Widget> stats;
  final int columns;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          children: [
            for (var i = 0; i < stats.length; i += columns)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var j = i; j < i + columns; j++) ...[
                        if (j > i) const SizedBox(width: 10),
                        Expanded(child: j < stats.length ? stats[j] : const SizedBox()),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
}

/// One column of a ReportTable.
class RCol {
  const RCol(this.header, this.cell, {this.right = false, this.color, this.bold = false});
  final String header;
  final Object Function(Map<String, dynamic> r) cell;
  final bool right;
  final Color? color;
  final bool bold;
}

/// ReportTable: a read-only table in a card; wide ones scroll inside it.
class ReportTable extends StatelessWidget {
  const ReportTable({super.key, this.title, required this.columns, required this.rows, required this.empty});
  final String? title;
  final List<RCol> columns;
  final List<Map<String, dynamic>> rows;
  final String empty;

  Widget _cell(RCol c, Object v) {
    if (v is Widget) return Align(alignment: c.right ? Alignment.centerRight : Alignment.centerLeft, child: v);
    return Text(
      '$v',
      textAlign: c.right ? TextAlign.right : TextAlign.left,
      style: TextStyle(fontSize: 13, color: c.color ?? TColors.slate900, fontWeight: c.bold ? FontWeight.w600 : FontWeight.w400),
    );
  }

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: TColors.slate200),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(title!.toUpperCase(), style: const TextStyle(fontSize: 11, letterSpacing: 0.5, color: TColors.slate500)),
              ),
            if (rows.isEmpty)
              Text(empty, style: const TextStyle(fontSize: 13, color: TColors.slate500))
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 32,
                  dataRowMinHeight: 34,
                  dataRowMaxHeight: 48,
                  horizontalMargin: 0,
                  columnSpacing: 18,
                  headingTextStyle: const TextStyle(fontSize: 11, color: TColors.slate500, fontWeight: FontWeight.w600),
                  columns: [for (final c in columns) DataColumn(label: Text(c.header.toUpperCase()), numeric: c.right)],
                  rows: [
                    for (final r in rows) DataRow(cells: [for (final c in columns) DataCell(_cell(c, c.cell(r)))]),
                  ],
                ),
              ),
          ],
        ),
      );
}

/// A share bar with its percentage, as the web's "Share" cells.
Widget shareCell(num pct, Color bar) => Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 64,
        height: 6,
        decoration: BoxDecoration(color: TColors.slate100, borderRadius: BorderRadius.circular(3)),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: (pct.clamp(0, 100)) / 100,
          child: Container(decoration: BoxDecoration(color: bar, borderRadius: BorderRadius.circular(3))),
        ),
      ),
      const SizedBox(width: 6),
      Text(fmtPct(pct), style: const TextStyle(fontSize: 13)),
    ]);

/// A small status badge.
Widget reportBadge(String text, {Color bg = TColors.slate100, Color fg = TColors.slate700, bool outline = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: outline ? Colors.white : bg,
        border: outline ? Border.all(color: TColors.slate200) : null,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );

/// GenericReportShell: the back link, title, description, the filter card
/// and the body (a loading line while [loading]).
class GenericReportShell extends StatelessWidget {
  const GenericReportShell({
    super.key,
    required this.session,
    required this.company,
    required this.href,
    required this.title,
    this.description,
    required this.icon,
    this.iconColor = genericEmerald,
    this.range,
    this.onRangeChange,
    this.showDates = true,
    this.extraFilters = const [],
    required this.onRun,
    required this.loading,
    required this.children,
  });

  final Session session;
  final Company company;
  final String href;
  final String title;
  final String? description;
  final IconData icon;
  final Color iconColor;

  /// Null for a report with no date range (Break-even, Inventory value).
  final GenericRange? range;
  final ValueChanged<GenericRange>? onRangeChange;

  /// False for the older reports that show only the period picker.
  final bool showDates;
  final List<Widget> extraFilters;
  final VoidCallback? onRun;
  final bool loading;
  final List<Widget> children;

  DateTime? _parse(String s) => s.length < 10 ? null : DateTime.tryParse(s.substring(0, 10));

  @override
  Widget build(BuildContext context) {
    final r = range;
    final lead = sidebarLeading(context, session, company, href: href);
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: TColors.slate500, padding: EdgeInsets.zero),
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back, size: 14),
              label: const Text('Back to reports', style: TextStyle(fontSize: 13)),
            ),
          ),
          GenericTitle(icon: icon, iconColor: iconColor, title: title, subtitle: description),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: TColors.slate200),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (r != null) ...[
                  FilterLabel(
                    'Period',
                    AppSelect<String>(
                      value: rangeToPeriod(r.from, r.to),
                      items: [
                        for (final (_, opts) in periodGroups)
                          for (final (k, l) in opts) AppSelectItem(value: k, label: l),
                      ],
                      onChanged: (k) {
                        final p = k == null ? null : periodToRange(k);
                        if (p != null) onRangeChange?.call((from: p.from, to: p.to));
                      },
                    ),
                  ),
                  if (showDates) ...[
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: FilterLabel(
                          'From',
                          AppDateField(
                            value: _parse(r.from),
                            hintText: 'dd/mm/yyyy',
                            onChanged: (d) => onRangeChange?.call((from: d == null ? '' : ymd(d), to: r.to)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilterLabel(
                          'To',
                          AppDateField(
                            value: _parse(r.to),
                            hintText: 'dd/mm/yyyy',
                            onChanged: (d) => onRangeChange?.call((from: r.from, to: d == null ? '' : ymd(d))),
                          ),
                        ),
                      ),
                    ]),
                  ],
                ],
                for (final f in extraFilters) ...[const SizedBox(height: 10), f],
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: loading ? null : onRun,
                  icon: loading ? busyIcon(true, Icons.play_arrow) : const SizedBox.shrink(),
                  label: const Text('Run'),
                ),
              ],
            ),
          ),
          if (loading)
            const Row(children: [
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 8),
              Text('Loading…', style: TextStyle(color: TColors.slate500)),
            ])
          else
            ...children,
        ],
      ),
    );
  }
}

/// useReport: hold a range, run a loader, toast its errors.
mixin GenericReportState<T extends StatefulWidget> on State<T> {
  Session get session;
  Company get company;
  GenericModules gm = const GenericModules();
  bool loading = true;
  late GenericRange range;

  /// The report's own request.
  Future<void> fetch();

  String get reportsBase => '${genericBase(company)}/reports';

  /// fromDate/toDate, left out when empty.
  Map<String, dynamic> get rangeQuery => {
        if (range.from.isNotEmpty) 'fromDate': range.from,
        if (range.to.isNotEmpty) 'toDate': range.to,
      };

  void startReport(GenericRange initial) {
    range = initial;
    loadGenericModules(session, company).then((v) {
      if (mounted) setState(() => gm = v);
    });
    run();
  }

  Future<void> run() async {
    setState(() => loading = true);
    try {
      await fetch();
    } catch (e) {
      if (mounted) trackerToast(context, 'Could not load report', description: reportError(e), error: true);
    }
    if (mounted) setState(() => loading = false);
  }
}
