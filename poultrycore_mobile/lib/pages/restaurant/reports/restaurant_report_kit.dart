// The Restaurant report frame, as the web's components/reports/module-report-shell.tsx
// and components/reports/report-table.tsx:
//
//   * a report is DATA — what to load, its columns, its KPI tiles, an optional
//     panel — and every one gets the same shell: "All reports", the header with
//     the group chip, View PDF / CSV / Email, and the date control its dateMode
//     asks for (a range with presets, a single day with a stepper, or none);
//   * a column defines its cell ONCE, in `value`. The screen, the PDF and the
//     CSV are all built from it, so they cannot disagree;
//   * on a phone every table row is a card: the first column as its heading and
//     the non-secondary columns as label / value pairs.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../poultry/reports/poultry_report_screen.dart' show defaultEmailRecipient, reportUser;
import '../../poultry/reports/report_export.dart';
import '../../poultry/trackers/tracker_logic.dart' show tNum, tStr;
import '../../poultry/trackers/tracker_widgets.dart';
import '../restaurant_roles.dart' show restaurantRose;
import 'restaurant_reports_catalog.dart';

// ---------------------------------------------------------------------------
// Formatting (makeFmt)
// ---------------------------------------------------------------------------

/// The formatters handed to every report. The currency comes from the
/// restaurant profile, so a figure always says what it is denominated in.
class RFmt {
  RFmt(this.currency);
  final String currency;

  static String _group(num n, int dp) {
    final f = NumberFormat.decimalPattern('en_US')
      ..minimumFractionDigits = dp
      ..maximumFractionDigits = dp;
    return f.format(n);
  }

  /// 1240.5 -> "GHS 1,240.50"
  String money(Object? n) => '$currency ${_group(tNum(n), 2)}';

  /// 1240.5 -> "1,240.50"
  String num_(Object? n, [int dp = 2]) => _group(tNum(n), dp);

  /// 12.5 -> "12.5%"
  String pct(Object? n, [int dp = 1]) => '${_group(tNum(n), dp)}%';

  /// 42.4 -> "42m", 95 -> "1h 35m"
  String mins(Object? n) {
    final v = tNum(n).round();
    return v < 60 ? '${v}m' : '${v ~/ 60}h ${v % 60}m';
  }

  String int_(Object? n) => _group(tNum(n), 0);
}

/// The first ten characters of a date string.
String d10(Object? s) {
  final v = tStr(s);
  return v.length >= 10 ? v.substring(0, 10) : v;
}

num sumOf(Iterable<Map> rows, num Function(Map r) f) => rows.fold<num>(0, (t, r) => t + f(r));

// ---------------------------------------------------------------------------
// Report definitions
// ---------------------------------------------------------------------------

class RRange {
  const RRange({required this.from, required this.to, required this.date});
  final String from, to;

  /// The single-day value, for reports whose dateMode is single.
  final String date;
  RRange copyWith({String? from, String? to, String? date}) => RRange(from: from ?? this.from, to: to ?? this.to, date: date ?? this.date);
}

String isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// defaultReportRange: the last 30 days, with today as the single date.
RRange defaultRRange() {
  final now = DateTime.now();
  return RRange(from: isoDay(now.subtract(const Duration(days: 29))), to: isoDay(now), date: isoDay(now));
}

class RCol {
  const RCol(this.key, this.label, this.value, {this.render, this.numeric = false, this.secondary = false});
  final String key;
  final String label;

  /// The cell's text. Screen, PDF and CSV all come from this.
  final String Function(Map r, RFmt f) value;

  /// Screen-only enrichment (a badge, a coloured figure).
  final Widget Function(Map r, RFmt f)? render;
  final bool numeric;

  /// Dropped from the phone card when it is secondary detail.
  final bool secondary;
}

class RLoad {
  const RLoad(this.rows, [this.meta]);
  final List<Map> rows;
  final Object? meta;
}

/// What a loader is handed: the client, the company and the range.
class RCtx {
  const RCtx(this.session, this.company);
  final Session session;
  final Company company;
  ApiClient get api => session.farmClient;
  String get farmId => company.farmId;

  Future<Object?> get(String path, [Map<String, dynamic> query = const {}]) => api.get(path, query: {'farmId': farmId, ...query});

  Future<List<Map>> list(String path, [Map<String, dynamic> query = const {}]) async {
    final r = await get(path, query);
    return [for (final x in (r is List ? r : const [])) if (x is Map) x];
  }

  Future<Map> map(String path, [Map<String, dynamic> query = const {}]) async {
    final r = await get(path, query);
    return r is Map ? r : const {};
  }
}

typedef RCard = ({String label, String value});

class RDef {
  const RDef({
    required this.load,
    required this.columns,
    this.summary,
    this.panel,
    this.tableTitle,
    this.tableHint,
    this.emptyText,
    this.rows,
  });
  final Future<RLoad> Function(RCtx c, RRange r) load;
  final List<RCol> columns;

  /// KPI tiles above the table, also in the PDF and the CSV.
  final List<RCard> Function(RLoad r, RFmt f)? summary;

  /// A chart or extra panel between the tiles and the table.
  final Widget? Function(RLoad r, RFmt f)? panel;
  final String? tableTitle;
  final String? tableHint;
  final String? emptyText;

  /// deriveMetricRows: the rows a single-object report builds from its meta.
  final List<Map> Function(Object? meta, RFmt f)? rows;
}

// ---------------------------------------------------------------------------
// Presentation
// ---------------------------------------------------------------------------

const _tones = [Color(0xFF10B981), Color(0xFFF43F5E), Color(0xFF6366F1), Color(0xFFF59E0B)];

class StatGrid extends StatelessWidget {
  const StatGrid(this.cards, {super.key});
  final List<RCard> cards;

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();
    final rows = <Widget>[];
    for (var i = 0; i < cards.length; i += 2) {
      rows.add(IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var j = i; j < i + 2; j++) ...[
            if (j > i) const SizedBox(width: 10),
            Expanded(child: j < cards.length ? _card(cards[j], _tones[j % _tones.length]) : const SizedBox.shrink()),
          ],
        ]),
      ));
      rows.add(const SizedBox(height: 10));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }

  // border-l-4 in the tone: a stripe inside a rounded card (Flutter cannot
  // round a border whose sides differ in colour).
  Widget _card(RCard c, Color tone) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: TColors.slate200)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 4, color: tone),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(c.value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: TColors.slate900)),
                const SizedBox(height: 2),
                Text(c.label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
              ]),
            ),
          ),
        ]),
      );
}

/// ToneBadge: good / warn / bad / muted.
Widget toneBadge(String text, String tone) {
  final (bg, fg, border) = switch (tone) {
    'good' => (const Color(0xFFECFDF5), const Color(0xFF047857), const Color(0xFFA7F3D0)),
    'warn' => (const Color(0xFFFFFBEB), const Color(0xFFB45309), const Color(0xFFFDE68A)),
    'bad' => (const Color(0xFFFEF2F2), const Color(0xFFB91C1C), const Color(0xFFFECACA)),
    _ => (const Color(0xFFF8FAFC), const Color(0xFF475569), TColors.slate200),
  };
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(999)),
    child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: fg)),
  );
}

/// A figure in a colour, for the render-only cells.
Widget coloured(String text, Color color, {bool bold = false}) =>
    Text(text, textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: color, fontWeight: bold ? FontWeight.w600 : FontWeight.w500));

const red700 = Color(0xFFB91C1C);
const red600 = Color(0xFFDC2626);
const amber700 = Color(0xFFB45309);
const amber600 = Color(0xFFD97706);
const emerald700 = Color(0xFF047857);
const rose700 = Color(0xFFBE123C);

/// A titled card, as the web's chartCard / card.
Widget reportCard(String title, String? hint, Widget body) => TCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        if (hint != null) ...[
          const SizedBox(height: 2),
          Text(hint, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
        ],
        const SizedBox(height: 10),
        body,
      ]),
    );

/// The phone's chart: one row per item with a bar per series, values beside.
/// (The web draws recharts bar / line / pie charts; the app has no chart
/// library, so every chart reads as these bars, with the same data.)
class BarChartRows extends StatelessWidget {
  const BarChartRows({super.key, required this.items, required this.series, this.signed = false});

  /// Label per row.
  final List<String> items;

  /// (name, colour, values, format) per series; values line up with [items].
  final List<(String, Color, List<num>, String Function(num))> series;

  /// Negative values draw in the second colour of the series (net by day).
  final bool signed;

  @override
  Widget build(BuildContext context) {
    final maxes = [for (final s in series) s.$3.fold<num>(0, (m, v) => v.abs() > m ? v.abs() : m)];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (series.length > 1)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(spacing: 12, children: [
            for (final s in series)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: s.$2, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 4),
                Text(s.$1, style: const TextStyle(fontSize: 11, color: TColors.slate600)),
              ]),
          ]),
        ),
      for (var i = 0; i < items.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(items[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: TColors.slate700)),
            for (final (k, s) in series.indexed)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: maxes[k] == 0 ? 0 : (s.$3[i].abs() / maxes[k]).clamp(0, 1).toDouble(),
                        minHeight: 8,
                        color: signed && s.$3[i] < 0 ? const Color(0xFFE11D48) : s.$2,
                        backgroundColor: TColors.slate100,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 110,
                    child: Text(s.$4(s.$3[i]), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, color: TColors.slate700)),
                  ),
                ]),
              ),
          ]),
        ),
    ]);
  }
}

/// A pie chart's slices, as share bars ("Name 42%").
Widget shareBars(List<(String, num)> slices, {String Function(num)? fmt}) {
  final total = slices.fold<num>(0, (t, s) => t + s.$2);
  const colors = [
    Color(0xFFE11D48), Color(0xFFF43F5E), Color(0xFFFB7185), Color(0xFFFDA4AF), Color(0xFFFECDD3), Color(0xFF9F1239), Color(0xFFBE123C), Color(0xFF881337),
  ];
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    for (final (i, (name, v)) in slices.indexed)
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: TColors.slate700))),
            Text('${fmt != null ? '${fmt(v)}  ' : ''}${total == 0 ? 0 : (v / total * 100).toStringAsFixed(0)}%',
                style: const TextStyle(fontSize: 12, color: TColors.slate700)),
          ]),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : (v / total).clamp(0, 1).toDouble(),
              minHeight: 8,
              color: colors[i % colors.length],
              backgroundColor: TColors.slate100,
            ),
          ),
        ]),
      ),
  ]);
}

class ReportTableCard extends StatelessWidget {
  const ReportTableCard({super.key, required this.def, required this.rows, required this.fmt});
  final RDef def;
  final List<Map> rows;
  final RFmt fmt;

  @override
  Widget build(BuildContext context) {
    final cols = def.columns;
    Widget cell(RCol c, Map r, {bool heading = false}) {
      final w = c.render?.call(r, fmt);
      if (w != null) return w;
      return Text(c.value(r, fmt),
          textAlign: heading || !c.numeric ? TextAlign.left : TextAlign.right,
          style: heading
              ? const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate900)
              : const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: TColors.slate900));
    }

    return TCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (def.tableTitle != null) Text(def.tableTitle!, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        if (def.tableHint != null) ...[
          const SizedBox(height: 2),
          Text(def.tableHint!, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
        ],
        if (def.tableTitle != null || def.tableHint != null) const SizedBox(height: 10),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 36),
            child: Column(children: [
              const Icon(Icons.description_outlined, size: 32, color: Color(0xFFCBD5E1)),
              const SizedBox(height: 8),
              Text(def.emptyText ?? 'No data for this period.',
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
            ]),
          )
        else
          for (final r in rows)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                cell(cols.first, r, heading: true),
                const SizedBox(height: 6),
                for (final c in cols.skip(1).where((c) => !c.secondary))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(c.label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                      const SizedBox(width: 8),
                      Expanded(child: Align(alignment: Alignment.centerRight, child: cell(c, r))),
                    ]),
                  ),
              ]),
            ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// The shell
// ---------------------------------------------------------------------------

/// The presets that replaced the old Daily / Weekly / Monthly pages.
List<(String, RRange Function(RRange))> reportPresets() {
  final n = DateTime.now();
  final today = isoDay(n);
  return [
    ('Today', (r) => r.copyWith(from: today, to: today)),
    ('7 days', (r) => r.copyWith(from: isoDay(n.subtract(const Duration(days: 6))), to: today)),
    ('30 days', (r) => r.copyWith(from: isoDay(n.subtract(const Duration(days: 29))), to: today)),
    ('This month', (r) => r.copyWith(from: isoDay(DateTime(n.year, n.month, 1)), to: today)),
    ('Last month', (r) => r.copyWith(from: isoDay(DateTime(n.year, n.month - 1, 1)), to: isoDay(DateTime(n.year, n.month, 0)))),
  ];
}

class RestaurantReportScreen extends StatefulWidget {
  const RestaurantReportScreen({super.key, required this.session, required this.company, required this.slug, required this.def});
  final Session session;
  final Company company;
  final String slug;
  final RDef def;

  @override
  State<RestaurantReportScreen> createState() => _RestaurantReportScreenState();
}

class _RestaurantReportScreenState extends State<RestaurantReportScreen> {
  RRange _range = defaultRRange();
  RLoad? _result;
  bool _loading = true;
  int _seq = 0;
  String _name = '', _currency = '';
  String? _address, _phone;

  RCtx get _ctx => RCtx(widget.session, widget.company);
  RFmt get _fmt => RFmt(_currency);
  ({RestaurantReportEntry report, RestaurantReportGroup group}) get _match => findRestaurantReport(widget.slug)!;

  @override
  void initState() {
    super.initState();
    _name = widget.company.name.isEmpty ? 'Restaurant' : widget.company.name;
    _loadProfile();
    _load();
  }

  // Branding and currency for the exports. A failure is not fatal.
  Future<void> _loadProfile() async {
    try {
      final p = await _ctx.map('/api/Restaurant/setup/profile');
      if (!mounted) return;
      setState(() {
        _name = tStr(p['restaurantName']).isNotEmpty ? tStr(p['restaurantName']) : _name;
        final addr = [p['address'], p['city'], p['country']].map(tStr).where((s) => s.isNotEmpty).join(', ');
        _address = addr.isEmpty ? null : addr;
        _phone = tStr(p['phone']).isEmpty ? null : tStr(p['phone']);
        _currency = tStr(p['defaultCurrency']);
      });
    } catch (_) {}
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() => _loading = true);
    try {
      final r = await widget.def.load(_ctx, _range);
      if (!mounted || seq != _seq) return;
      _result = r;
    } catch (e) {
      if (!mounted || seq != _seq) return;
      _result = const RLoad([]);
      trackerToast(context, 'Could not load report', description: e is ApiException ? e.message : '$e', error: true);
    }
    if (mounted && seq == _seq) setState(() => _loading = false);
  }

  void _setRange(RRange r) {
    setState(() => _range = r);
    _load();
  }

  /// The result with derived metric rows, for the single-object reports.
  RLoad? get _shaped {
    final r = _result;
    if (r == null) return null;
    final derived = widget.def.rows?.call(r.meta, _fmt) ?? const [];
    return derived.isNotEmpty ? RLoad(derived, r.meta) : r;
  }

  String get _mode => _match.report.dateMode;

  String get _periodLabel => switch (_mode) {
        'single' => _range.date,
        'none' => '',
        _ => '${_range.from} to ${_range.to}',
      };

  String get _filename => '${widget.slug}-${switch (_mode) {
        'single' => _range.date,
        'none' => 'current',
        _ => '${_range.from}_${_range.to}',
      }}';

  ReportDocument? _document() {
    final r = _shaped;
    if (r == null) return null;
    final f = _fmt;
    final cards = widget.def.summary?.call(r, f) ?? const [];
    final title = _match.report.title;
    return ReportDocument(
      title: title,
      filename: _filename,
      farmName: _name,
      fromDate: _mode == 'range' ? _range.from : null,
      toDate: _mode == 'range' ? _range.to : null,
      generatedBy: reportUser(widget.session),
      currencyLabel: _currency.isEmpty ? null : _currency,
      subtitle: [
        _periodLabel.isNotEmpty ? '$title — $_periodLabel' : title,
        ?_address,
        ?_phone,
      ].join('  ·  '),
      cards: [for (final c in cards) (label: c.label, value: c.value, accent: null, note: null)],
      sections: [
        ReportSection(
          columns: [for (final c in widget.def.columns) ReportColumn(c.label, right: c.numeric)],
          rows: [for (final row in r.rows) [for (final c in widget.def.columns) c.value(row, f)]],
        ),
      ],
      rose: true,
    );
  }

  /// The CSV: title and period, the KPI tiles as label / value rows, a blank
  /// line, then the table — the same object the PDF is built from.
  List<int> _csvBytes() {
    final r = _shaped!;
    final f = _fmt;
    String esc(Object? v) => '"${'${v ?? ''}'.replaceAll('"', '""')}"';
    final b = StringBuffer()..writeln([_match.report.title, _periodLabel.isEmpty ? 'Current position' : _periodLabel].map(esc).join(','));
    final cards = widget.def.summary?.call(r, f) ?? const [];
    if (cards.isNotEmpty) {
      for (final c in cards) {
        b.writeln([c.label, c.value].map(esc).join(','));
      }
      b.writeln();
    }
    b.writeln(widget.def.columns.map((c) => esc(c.label)).join(','));
    for (final row in r.rows) {
      b.writeln(widget.def.columns.map((c) => esc(c.value(row, f))).join(','));
    }
    return [0xEF, 0xBB, 0xBF, ...utf8.encode(b.toString())];
  }

  bool get _canExport => !_loading && (_shaped?.rows.isNotEmpty ?? false);

  Future<void> _viewPdf() async {
    final d = _document();
    if (d == null) return;
    await ReportExport.sharer('$_filename.pdf', await ReportExport.buildPdf(d), 'application/pdf', d.title);
  }

  Future<void> _csv() => ReportExport.sharer('$_filename.csv', _csvBytes(), 'text/csv', _match.report.title);

  void _email() => showDialog<void>(
        context: context,
        builder: (_) => RestaurantReportEmailDialog(
          session: widget.session,
          company: widget.company,
          title: _match.report.title,
          periodLabel: _periodLabel,
          propertyName: _name,
          pdf: () async => (bytes: await ReportExport.buildPdf(_document()!), filename: '$_filename.pdf'),
          csv: () => (bytes: _csvBytes(), filename: '$_filename-${isoDay(DateTime.now())}.csv'),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final m = _match;
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/restaurant-reports');
    final shaped = _shaped;
    final f = _fmt;
    final cards = shaped == null ? const <RCard>[] : (widget.def.summary?.call(shaped, f) ?? const []);
    final panel = shaped == null ? null : widget.def.panel?.call(shaped, f);
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: Text(m.report.title)),
      body: ListView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 32), children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: TColors.slate600),
            onPressed: () => openRestaurantReportsCatalog(context, widget.session, widget.company),
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const Text('All reports'),
          ),
        ),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: m.group.color, borderRadius: BorderRadius.circular(12)),
            child: Icon(m.report.icon, size: 22, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(m.report.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: TColors.slate900)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(999)),
                  child: Text(m.group.label.toUpperCase(), style: const TextStyle(fontSize: 10, letterSpacing: .5, color: TColors.slate600)),
                ),
              ]),
              const SizedBox(height: 2),
              Text(m.report.description, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        // View PDF / CSV / Email: disabled, never hidden, when there is nothing
        // to export. Print is desktop-only on the web, so it is not here.
        Row(children: [
          for (final (i, (label, icon, onTap)) in [
            ('View PDF', Icons.visibility_outlined, _viewPdf),
            ('CSV', Icons.table_view_outlined, _csv),
            ('Email', Icons.mail_outline, () async => _email()),
          ].indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(40), padding: const EdgeInsets.symmetric(horizontal: 6)),
                onPressed: _canExport ? onTap : null,
                icon: Icon(icon, size: 16),
                label: Text(label),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 12),
        if (_mode == 'range') _rangeControl(),
        if (_mode == 'single') _singleControl(),
        if (_mode == 'none')
          const Text('This report shows the current position, so it has no date filter.',
              style: TextStyle(fontSize: 12, color: TColors.slate500)),
        const SizedBox(height: 12),
        if (_loading)
          TCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 8),
                Text('Loading ${m.report.title.toLowerCase()}…', style: const TextStyle(fontSize: 13, color: TColors.slate500)),
              ]),
            ),
          )
        else if (shaped != null) ...[
          StatGrid(cards),
          if (panel != null) ...[panel, const SizedBox(height: 12)],
          ReportTableCard(def: widget.def, rows: shaped.rows, fmt: f),
        ],
      ]),
    );
  }

  Widget _dateBox(String value, ValueChanged<String> onChanged) => AppDateField(
        value: DateTime.tryParse(value),
        hintText: value,
        onChanged: (d) {
          if (d != null) onChanged(isoDay(d));
        },
      );

  Widget _rangeControl() => TCard(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const SizedBox(width: 36, child: Text('From', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: TColors.slate500))),
            Expanded(child: _dateBox(_range.from, (v) => _setRange(_range.copyWith(from: v)))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            const SizedBox(width: 36, child: Text('To', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: TColors.slate500))),
            Expanded(child: _dateBox(_range.to, (v) => _setRange(_range.copyWith(to: v)))),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (label, compute) in reportPresets())
              Builder(builder: (_) {
                final v = compute(_range);
                final active = v.from == _range.from && v.to == _range.to;
                return active
                    ? FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: restaurantRose, visualDensity: VisualDensity.compact),
                        onPressed: () => _setRange(v),
                        child: Text(label, style: const TextStyle(fontSize: 12)),
                      )
                    : OutlinedButton(
                        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                        onPressed: () => _setRange(v),
                        child: Text(label, style: const TextStyle(fontSize: 12)),
                      );
              }),
          ]),
        ]),
      );

  Widget _singleControl() {
    String shift(int days) => isoDay((DateTime.tryParse(_range.date) ?? DateTime.now()).add(Duration(days: days)));
    return TCard(
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        IconButton.outlined(tooltip: 'Previous day', onPressed: () => _setRange(_range.copyWith(date: shift(-1))), icon: const Icon(Icons.chevron_left)),
        const SizedBox(width: 6),
        Expanded(child: _dateBox(_range.date, (v) => _setRange(_range.copyWith(date: v)))),
        const SizedBox(width: 6),
        IconButton.outlined(tooltip: 'Next day', onPressed: () => _setRange(_range.copyWith(date: shift(1))), icon: const Icon(Icons.chevron_right)),
        const SizedBox(width: 6),
        OutlinedButton(onPressed: () => _setRange(_range.copyWith(date: isoDay(DateTime.now()))), child: const Text('Today')),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Email (components/reports/report-email-dialog.tsx)
// ---------------------------------------------------------------------------

typedef RAttachment = ({List<int> bytes, String filename});

class RestaurantReportEmailDialog extends StatefulWidget {
  const RestaurantReportEmailDialog({
    super.key,
    required this.session,
    required this.company,
    required this.title,
    required this.periodLabel,
    required this.propertyName,
    required this.pdf,
    required this.csv,
  });
  final Session session;
  final Company company;
  final String title;
  final String periodLabel;
  final String propertyName;
  final Future<RAttachment> Function() pdf;
  final RAttachment Function() csv;

  @override
  State<RestaurantReportEmailDialog> createState() => _RestaurantReportEmailDialogState();
}

class _RestaurantReportEmailDialogState extends State<RestaurantReportEmailDialog> {
  late final _to = TextEditingController(text: defaultEmailRecipient(widget.session, widget.company));
  final _note = TextEditingController();
  String _attach = 'pdf';
  bool _sending = false;

  @override
  void dispose() {
    _to.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final list = ReportExport.recipients(_to.text);
    if (list == null) {
      return trackerToast(context, 'Enter a valid email address', description: 'Separate several with commas.', error: true);
    }
    setState(() => _sending = true);
    try {
      final a = _attach == 'csv' ? widget.csv() : await widget.pdf();
      final period = widget.periodLabel.isNotEmpty ? ' (${widget.periodLabel})' : '';
      final sender = reportUser(widget.session);
      await widget.session.farmClient.postFile(
        '/api/Email/Report',
        field: 'file',
        bytes: a.bytes,
        filename: a.filename,
        contentType: _attach == 'csv' ? 'text/csv' : 'application/pdf',
        fields: {
          'to': list.join(','),
          'subject': '${widget.title}$period',
          // Left out when nothing was typed, so the server's own template is used.
          if (_note.text.trim().isNotEmpty) 'body': _note.text.trim(),
          'farmName': widget.propertyName,
          'reportTitle': widget.title,
          'senderName': ?sender,
        },
      );
      if (!mounted) return;
      trackerToast(context, 'Report emailed',
          description: '${_attach.toUpperCase()} sent to ${list.length == 1 ? list.first : '${list.length} recipients'}.');
      Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Email failed', description: e.message.isEmpty ? 'Could not send.' : e.message, error: true);
    }
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) => PopScope(
        // Not closable mid-send.
        canPop: !_sending,
        child: AlertDialog(
          scrollable: true,
          title: Text('Email “${widget.title}”', style: const TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Recipient email(s)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              AppInput(controller: _to, hintText: 'owner@example.com, accountant@example.com', keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 4),
              const Text('Separate multiple addresses with commas.', style: TextStyle(fontSize: 12, color: TColors.slate500)),
              const SizedBox(height: 14),
              const Text('Attach as', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              Row(children: [
                for (final (i, a) in ['pdf', 'csv'].indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => setState(() => _attach = a),
                      child: Container(
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _attach == a ? const Color(0xFFFFF1F2) : null,
                          border: Border.all(color: _attach == a ? const Color(0xFFFDA4AF) : TColors.slate200),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text.rich(TextSpan(children: [
                          TextSpan(text: a.toUpperCase(), style: TextStyle(fontWeight: FontWeight.w500, color: _attach == a ? rose700 : TColors.slate600)),
                          TextSpan(text: a == 'pdf' ? ' formatted' : ' spreadsheet', style: const TextStyle(fontSize: 11, color: TColors.slate400)),
                        ]), style: const TextStyle(fontSize: 14)),
                      ),
                    ),
                  ),
                ],
              ]),
              const SizedBox(height: 14),
              const Text('Message (optional)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              AppTextarea(controller: _note, hintText: 'Leave blank to use the standard message.', rows: 3),
            ]),
          ),
          actions: [
            OutlinedButton(onPressed: _sending ? null : () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: restaurantRose),
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.mail_outline, size: 16),
              label: Text(_sending ? 'Sending…' : 'Send'),
            ),
          ],
        ),
      );
}
