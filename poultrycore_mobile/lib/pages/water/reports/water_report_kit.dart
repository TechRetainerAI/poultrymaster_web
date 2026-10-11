import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../lookup_loader.dart';
import '../../poultry/reports/report_export.dart';
import '../../poultry/reports/report_format.dart';
import '../../poultry/reports/report_shell.dart';
import '../../poultry/reports/report_widgets.dart';
import '../../shared/business_dates.dart';
import 'water_reports_catalog_screen.dart';

// The plumbing every Water report page shares, so each report below is only
// what its web page computes: what it loads, its tiles, its PDF definition
// (columns + rows, which the web's phone view renders as scorecards) and any
// extra sections. A port of how `components/reports/report-shell.tsx` is used
// by `app/water-reports/*/page.tsx`.

num wn(Object? v) => toNum(v);

/// `(x ?? "").slice(0, 10)`.
String wday(Object? v) {
  final s = '${v ?? ''}';
  return s.length >= 10 ? s.substring(0, 10) : s;
}

/// `x ?? "—"`.
String wdash(Object? v) => v == null || '$v'.isEmpty ? '—' : '$v';

/// `String(v)` for a JSON number or text: whole numbers without ".0".
String wstr(Object? v) {
  if (v is num && v == v.truncate()) return '${v.toInt()}';
  return '${v ?? ''}';
}

/// `n.toLocaleString()` — up to three decimals, thousands separators.
String wloc(Object? v) => fmtNum(wn(v), 3);

/// A JS ISO day, `d.toISOString().split("T")[0]`, for a date `days` back.
String wdaysAgo(int days) => isoDay(DateTime.now().subtract(Duration(days: days)));

/// One extra dropdown in the filters row.
class WaterFilterDef {
  const WaterFilterDef({
    required this.key,
    required this.label,
    required this.initial,
    required this.options,
    this.summaryLabel,
  });
  final String key;

  /// Shown above the dropdown ('' for none, as the web's unlabeled ones).
  final String label;
  final String initial;

  /// (value, label); loaded once when the report opens.
  final Future<List<(String, String)>> Function(WaterReportQuery q) options;

  /// What "Filters used" calls it; null = not listed.
  final String? summaryLabel;
}

/// What a report's load and build are given.
class WaterReportQuery {
  WaterReportQuery(this.session, this.company, this.from, this.to, this.filters);
  final Session session;
  final Company company;
  final String from, to;
  final Map<String, String> filters;

  String get farmId => company.farmId;

  /// GET an array under /api; `farmId` is added.
  Future<List<Map<String, dynamic>>> list(String path, [Map<String, dynamic> query = const {}]) async {
    final res = await session.farmClient.get(path, query: {'farmId': farmId, ...query});
    return [
      for (final r in LookupLoader.rowsIn(res))
        if (r is Map) Map<String, dynamic>.from(r),
    ];
  }

  /// GET any JSON under /api; `farmId` is added.
  Future<dynamic> get(String path, [Map<String, dynamic> query = const {}]) =>
      session.farmClient.get(path, query: {'farmId': farmId, ...query});

  /// The `period(from, to)` query the report endpoints take.
  Map<String, dynamic> get period => {'fromDate': from, 'toDate': to};

  /// `x.catch(() => [])`.
  Future<List<Map<String, dynamic>>> listOrEmpty(String path, [Map<String, dynamic> query = const {}]) async {
    try {
      return await list(path, query);
    } catch (_) {
      return [];
    }
  }
}

/// A table after the summary, as the web's `<h2>` + table blocks.
class WaterSection {
  const WaterSection({
    this.heading,
    required this.columns,
    required this.rows,
    required this.empty,
    this.cards = true,
    this.totals,
  });
  final String? heading;
  final List<ReportColumn> columns;
  final List<List<String>> rows;
  final String empty;

  /// Scorecards (ReportTableCards) — false for the short roll-ups the web
  /// leaves as a plain table on a phone.
  final bool cards;
  final List<String>? totals;
}

/// What a report shows once its data is in.
class WaterReportView {
  const WaterReportView({
    this.tiles = const [],
    required this.columns,
    required this.rows,
    this.empty = 'No rows.',
    this.totals,
    this.sections,
    this.before = const [],
    this.subtitle,
    this.landscape,
    this.activeFilters = const [],
    this.valueColor,
    this.pdf = true,
  });
  final List<SummaryCardData> tiles;

  /// The PDF table, and the phone cards when [sections] is null.
  final List<ReportColumn> columns;
  final List<List<String>> rows;
  final String empty;
  final List<String>? totals;

  /// The body when the page is more than its one PDF table.
  final List<WaterSection>? sections;

  /// Widgets above the body (a "Customer: …" line, a prompt).
  final List<Widget> before;
  final String? subtitle;
  final bool? landscape;

  /// filterSummary, with "ALL" and blanks already left out.
  final List<(String, String)> activeFilters;
  final Color? Function(int row, int col)? valueColor;

  /// False when the web page has no PDF definition (Export prints).
  final bool pdf;
}

/// One Water report page.
class WaterReport extends StatefulWidget {
  const WaterReport({
    super.key,
    required this.session,
    required this.company,
    required this.slug,
    required this.title,
    this.description,
    required this.filename,
    this.dated = true,
    this.initialFrom,
    this.initialTo,
    this.filters = const [],
    required this.load,
    required this.view,
  });
  final Session session;
  final Company company;
  final String slug;
  final String title;
  final String? description;
  final String filename;

  /// False for point-in-time reports (no Period / From / To).
  final bool dated;

  /// The page's own starting range when it is not defaultReportRange("last30").
  final String? initialFrom, initialTo;
  final List<WaterFilterDef> filters;
  final Future<Object?> Function(WaterReportQuery q) load;
  final WaterReportView Function(Object? data, WaterReportQuery q, FarmMoney money) view;

  @override
  State<WaterReport> createState() => _WaterReportState();
}

class _WaterReportState extends State<WaterReport> {
  late String _from = widget.initialFrom ?? defaultReportRange().from;
  late String _to = widget.initialTo ?? defaultReportRange().to;
  late final Map<String, String> _filters = {for (final f in widget.filters) f.key: f.initial};
  final Map<String, List<(String, String)>> _options = {};
  Object? _data;
  bool _busy = true;
  String? _error;
  FarmMoney _money = const FarmMoney();
  int _seq = 0;

  WaterReportQuery get _q => WaterReportQuery(widget.session, widget.company, _from, _to, Map.of(_filters));

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _money = m);
    });
    for (final f in widget.filters) {
      f.options(_q).then((o) {
        if (mounted) setState(() => _options[f.key] = o);
      }).catchError((Object e) {
        if (mounted) setState(() => _options[f.key] = const []);
      });
    }
    _load();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final d = await widget.load(_q);
      if (mounted && seq == _seq) setState(() => _data = d);
    } on ApiException catch (e) {
      if (mounted && seq == _seq) setState(() => _error = e.message);
    } catch (e) {
      if (mounted && seq == _seq) setState(() => _error = '$e');
    } finally {
      if (mounted && seq == _seq) setState(() => _busy = false);
    }
  }

  Widget _filter(WaterFilterDef f) {
    final opts = _options[f.key] ?? const [];
    final value = _filters[f.key];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (f.label.isNotEmpty) ...[
          Text(f.label, style: const TextStyle(fontSize: 12, color: slate600)),
          const SizedBox(height: 4),
        ],
        AppSelect<String>(
          value: opts.any((o) => o.$1 == value) ? value : null,
          items: [for (final (v, l) in opts) AppSelectItem(value: v, label: l)],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _filters[f.key] = v);
            _load();
          },
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _q;
    final v = _data == null && _busy ? null : widget.view(_data, q, _money);
    final columns = v?.columns ?? const <ReportColumn>[];
    final rows = v?.rows ?? const <List<String>>[];
    final active = v?.activeFilters ?? const <(String, String)>[];
    final changed = widget.filters.any((f) => _filters[f.key] != f.initial);
    return ReportShellScreen(
      session: widget.session,
      company: widget.company,
      href: '/water-reports/${widget.slug}',
      catalog: (s, c) => WaterReportsCatalogScreen(session: s, company: c),
      title: widget.title,
      description: widget.description,
      busy: _busy,
      error: _error,
      onClearError: () => setState(() => _error = null),
      fromDate: widget.dated ? _from : null,
      toDate: widget.dated ? _to : null,
      onRangeChanged: widget.dated
          ? (f, t) {
              setState(() {
                _from = f;
                _to = t;
              });
              _load();
            }
          : null,
      extraFilters: [for (final f in widget.filters) _filter(f)],
      onClearFilters: widget.filters.isEmpty
          ? null
          : () {
              setState(() {
                for (final f in widget.filters) {
                  _filters[f.key] = f.initial;
                }
              });
              // Runs after the shell's own range reset, so this load (the
              // newest) is the one that lands.
              if (changed || widget.dated) _load();
            },
      activeFilters: active,
      tiles: v?.tiles ?? const [],
      recordCount: v == null || !v.pdf ? null : rows.length,
      onRefresh: _load,
      document: v == null || !v.pdf
          ? null
          : () => ReportDocument(
                title: widget.title,
                filename: widget.filename,
                farmName: widget.company.name,
                subtitle: v.subtitle,
                landscape: v.landscape,
                cards: [for (final t in v.tiles) (label: t.label, value: t.value, accent: null, note: null)],
                sections: [ReportSection(columns: columns, rows: rows, totals: v.totals)],
              ),
      body: v == null
          ? const []
          : [
              ...v.before,
              if (v.sections == null)
                ShellCards(columns: columns, rows: rows, totals: v.totals, empty: v.empty, valueColor: v.valueColor)
              else
                for (final (i, s) in v.sections!.indexed) ...[
                  if (s.heading != null) ShellHeading(s.heading!),
                  if (s.cards || s.rows.isEmpty)
                    ShellCards(
                      columns: s.columns,
                      rows: s.rows,
                      totals: s.totals,
                      empty: s.empty,
                      valueColor: i == 0 ? v.valueColor : null,
                    )
                  else
                    WaterMiniTable(columns: s.columns, rows: s.rows),
                ],
            ],
    );
  }
}

/// A short roll-up the web leaves as a plain table on a phone (By method,
/// By category): zebra rows, emerald header, right-aligned numbers.
class WaterMiniTable extends StatelessWidget {
  const WaterMiniTable({super.key, required this.columns, required this.rows});
  final List<ReportColumn> columns;
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    Widget cell(String t, bool right, {bool head = false}) => Expanded(
          flex: right ? 2 : 3,
          child: Text(
            head ? t.toUpperCase() : t,
            textAlign: right ? TextAlign.right : TextAlign.left,
            style: head
                ? const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: .5, color: Color(0xFF064E3B))
                : const TextStyle(fontSize: 13, color: slate900),
          ),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(border: Border.all(color: slate200), borderRadius: BorderRadius.circular(8)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Container(
          color: const Color(0xFFECFDF5),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(children: [for (final c in columns) cell(c.header, c.right, head: true)]),
        ),
        for (final (i, r) in rows.indexed)
          Container(
            color: i.isOdd ? const Color(0x99F8FAFC) : Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [for (final (ci, c) in columns.indexed) cell(ci < r.length ? r[ci] : '', c.right)]),
          ),
      ]),
    );
  }
}

/// SumTile in the shape the shell takes.
SummaryCardData tile(String label, String value, [String? accent]) =>
    (label: label, value: value, accent: accent, note: null);

/// `{ header }` / `{ header, align: "right" }`.
ReportColumn col(String header) => ReportColumn(header);
ReportColumn rcol(String header) => ReportColumn(header, right: true);
