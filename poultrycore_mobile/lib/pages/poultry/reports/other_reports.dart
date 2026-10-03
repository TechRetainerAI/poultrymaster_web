import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/buttons.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../lookup_loader.dart';
import '../../shared/business_dates.dart';
import '../../shared/company_clock.dart';
import 'dashboard_screen.dart' show sumLatestBirdsLeftByFlock;
import 'poultry_report_screen.dart';
import 'report_export.dart';
import 'report_format.dart';
import 'report_routes.dart';
import 'report_shell.dart';
import 'report_widgets.dart';
import 'reports_catalog_screen.dart';

num _n(Object? v) => toNum(v);
String _key(Object? v) => toBusinessDate(v) ?? '';

Future<List<Map>> _list(Session s, String path, Map<String, String> q) async =>
    [for (final r in LookupLoader.rowsIn(await s.farmClient.get(path, query: q))) if (r is Map) r];

/// "1/10/2026, 14:05" for an instant — `new Date(s).toLocaleString()`.
String _localeInstant(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}');
  if (d == null) return '—';
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.day}/${l.month}/${l.year}, ${two(l.hour)}:${two(l.minute)}';
}

Widget _dateBox(String label, String value, void Function(String) onPick, {String hint = 'Any'}) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 12, color: slate500)),
      const SizedBox(height: 4),
      AppDateField(
        value: businessDateAsDateTime(value),
        hintText: hint,
        firstDate: DateTime(2000),
        onChanged: (d) => onPick(d == null ? '' : isoDay(d)),
      ),
    ]);

// =========================================================================
// Batch Production Summary
// =========================================================================

/// /poultry/reports/batch-production-summary: production records rolled up
/// per flock batch, in the browser, as the web does.
class BatchProductionSummaryScreen extends StatefulWidget {
  const BatchProductionSummaryScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<BatchProductionSummaryScreen> createState() => _BatchProductionSummaryScreenState();
}

typedef _BatchRow = ({
  int id,
  String name,
  String code,
  String breed,
  int flocks,
  num placed,
  num current,
  num eggs,
  num broken,
  num avgDaily,
  num peakDaily,
  num? prodPct,
  num feedKg,
  num deaths,
  int records,
});

class _BatchProductionSummaryScreenState extends State<BatchProductionSummaryScreen> {
  List<Map> _records = [], _flocks = [], _batches = [];
  bool _loading = true;
  String _error = '';
  String _search = '', _from = '', _to = '';
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final q = {'userId': widget.session.tokens.userId ?? '', 'farmId': widget.company.farmId};
    try {
      final r = await Future.wait([
        _list(widget.session, '/api/ProductionRecord', q),
        _list(widget.session, '/api/Flock', q).catchError((_) => <Map>[]),
        _list(widget.session, '/api/MainFlockBatch', q).catchError((_) => <Map>[]),
      ]);
      setState(() {
        _records = r[0];
        _flocks = r[1];
        _batches = r[2];
        _error = '';
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message.isEmpty ? 'Failed to load production records' : e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_BatchRow> get _rows {
    final recs = [
      for (final r in _records)
        if ((_from.isEmpty || _key(r['date']).compareTo(_from) >= 0) && (_to.isEmpty || _key(r['date']).compareTo(_to) <= 0)) r,
    ];
    final batchOf = <int, int?>{};
    final flocksByBatch = <int, Set<int>>{};
    for (final f in _flocks) {
      final fid = _n(f['flockId']).toInt();
      final bid = f['batchId'] == null ? null : _n(f['batchId']).toInt();
      batchOf[fid] = bid;
      if (bid != null) flocksByBatch.putIfAbsent(bid, () => {}).add(fid);
    }
    final out = <_BatchRow>[
      for (final b in _batches)
        () {
          final bid = _n(b['batchId']).toInt();
          final mine = [for (final r in recs) if (r['flockId'] != null && batchOf[_n(r['flockId']).toInt()] == bid) r];
          num sum(String k) => mine.fold<num>(0, (s, r) => s + _n(r[k]));
          final eggs = sum('totalProduction');
          final birds = sum('noOfBirds');
          final byDate = <String, num>{};
          for (final r in mine) {
            final k = _key(r['date']);
            byDate[k] = (byDate[k] ?? 0) + _n(r['totalProduction']);
          }
          final days = byDate.length;
          return (
            id: bid,
            name: '${b['batchName'] ?? ''}'.isEmpty ? 'Batch #$bid' : '${b['batchName']}',
            code: '${b['batchCode'] ?? ''}',
            breed: '${b['breed'] ?? ''}',
            flocks: flocksByBatch[bid]?.length ?? 0,
            placed: _n(b['numberOfBirds']),
            current: sumLatestBirdsLeftByFlock(mine),
            eggs: eggs,
            broken: sum('brokenEggs'),
            avgDaily: days > 0 ? eggs / days : 0,
            peakDaily: days > 0 ? byDate.values.reduce((a, c) => a > c ? a : c) : 0,
            prodPct: birds > 0 ? eggs / birds * 100 : null,
            feedKg: sum('feedKg'),
            deaths: sum('mortality'),
            records: mine.length,
          );
        }(),
    ];
    final q = _search.trim().toLowerCase();
    final filtered = q.isEmpty
        ? out
        : [for (final r in out) if (r.name.toLowerCase().contains(q) || r.code.toLowerCase().contains(q) || r.breed.toLowerCase().contains(q)) r];
    filtered.sort((a, b) {
      final c = b.eggs.compareTo(a.eggs);
      return c != 0 ? c : a.name.compareTo(b.name);
    });
    return filtered;
  }

  static String _int(num n) => fmtNum(n.round(), 0);
  static String _pct(num? v) => v == null ? '—' : '${v.toStringAsFixed(1)}%';

  static const _columns = [
    ReportColumn('Batch'), ReportColumn('Code'), ReportColumn('Breed'),
    ReportColumn('Flocks', right: true), ReportColumn('Birds placed', right: true),
    ReportColumn('Current birds', right: true), ReportColumn('Total eggs', right: true),
    ReportColumn('Avg daily', right: true), ReportColumn('Peak daily', right: true),
    ReportColumn('Broken', right: true), ReportColumn('Prod %', right: true),
    ReportColumn('Feed (kg)', right: true), ReportColumn('Deaths', right: true),
  ];

  List<String> _cells(_BatchRow r) => [
        r.name, r.code.isEmpty ? '—' : r.code, r.breed.isEmpty ? '—' : r.breed, '${r.flocks}', _int(r.placed), _int(r.current),
        _int(r.eggs), _int(r.avgDaily), _int(r.peakDaily), _int(r.broken), _pct(r.prodPct), r.feedKg.toStringAsFixed(2), _int(r.deaths),
      ];

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry/reports/batch-production-summary');
    final rows = _rows;
    final eggs = rows.fold<num>(0, (s, r) => s + r.eggs);
    final placed = rows.fold<num>(0, (s, r) => s + r.placed);
    final feed = rows.fold<num>(0, (s, r) => s + r.feedKg);
    final deaths = rows.fold<num>(0, (s, r) => s + r.deaths);
    final pcts = [for (final r in rows) if (r.prodPct != null) r.prodPct!];
    final avgPct = pcts.isEmpty ? null : pcts.reduce((a, b) => a + b) / pcts.length;
    final cards = <(String, String, String, String?)>[
      ('Batches', '${rows.where((r) => r.records > 0).length}', 'of ${rows.length} with production', null),
      ('Total Eggs', _int(eggs), '${eggs ~/ 30}c + ${eggs.toInt() % 30}p', 'green'),
      ('Birds Placed', _int(placed), 'across all batches', null),
      ('Avg Production %', _pct(avgPct), 'eggs ÷ birds logged', 'green'),
      ('Feed (kg)', feed.toStringAsFixed(2), 'total consumed', null),
      ('Deaths', _int(deaths), 'in selected range', 'rose'),
    ];
    final totals = rows.isEmpty
        ? null
        : [
            'Totals', '', '', '${rows.fold<int>(0, (s, r) => s + r.flocks)}', _int(placed), _int(rows.fold<num>(0, (s, r) => s + r.current)),
            _int(eggs), '', '', _int(rows.fold<num>(0, (s, r) => s + r.broken)), _pct(avgPct), feed.toStringAsFixed(2), _int(deaths),
          ];
    ReportDocument doc() => ReportDocument(
          title: 'Batch Production Summary',
          filename: 'poultry-batch-production-summary',
          farmName: widget.company.name,
          fromDate: _from.isEmpty ? null : _from,
          toDate: _to.isEmpty ? null : _to,
          generatedBy: reportUser(widget.session),
          landscape: true,
          cards: [for (final c in cards) (label: c.$1, value: c.$2, accent: c.$4, note: null)],
          filters: [if (_search.trim().isNotEmpty) ('Search', _search.trim())],
          sections: [ReportSection(columns: _columns, rows: [for (final r in rows) _cells(r)], totals: totals)],
        );
    Future<void> csv() {
      String esc(String v) => '"${v.replaceAll('"', '""')}"';
      final body = [for (final r in rows) _cells(r).map(esc).join(',')].join('\n');
      final text = '${esc('Batch Production Summary')}\n${esc('Farm: ${widget.company.name}')},'
          '${esc('Period: ${_from.isEmpty ? 'all' : _from} to ${_to.isEmpty ? 'all' : _to}')}\n\n'
          '${_columns.map((c) => esc(c.header)).join(',')}\n$body';
      return ReportExport.sharer('poultry-batch-production-summary-${_from.isEmpty ? 'all' : _from}_${_to.isEmpty ? 'all' : _to}.csv',
          [0xEF, 0xBB, 0xBF, ...utf8.encode(text)], 'text/csv', 'Batch Production Summary');
    }

    return Scaffold(
      backgroundColor: slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Batch Production Summary')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
          children: [
            Row(children: [
              IconButton(
                tooltip: 'Poultry reports',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PoultryReportsCatalogScreen(session: widget.session, company: widget.company),
                )),
              ),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: const Color(0xFFD1FAE5), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.inventory_2_outlined, color: Color(0xFF059669)),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Production performance rolled up per flock batch.', style: TextStyle(fontSize: 13, color: slate600)),
              ),
            ]),
            if (_error.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFFEF2F2), border: Border.all(color: const Color(0xFFFECACA)), borderRadius: BorderRadius.circular(8)),
                child: Text(_error, style: const TextStyle(color: Color(0xFFB91C1C))),
              ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: slate200), borderRadius: BorderRadius.circular(8)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                AppInput(
                  key: ValueKey('search-${_search.isEmpty}'),
                  initialValue: _search,
                  hintText: 'Search batch, code, breed…',
                  onChanged: (v) => setState(() => _search = v),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _dateBox('From', _from, (v) => setState(() => _from = v))),
                  const SizedBox(width: 8),
                  Expanded(child: _dateBox('To', _to, (v) => setState(() => _to = v))),
                ]),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
                  AppButton(
                    label: 'Reset',
                    icon: Icons.refresh,
                    variant: AppButtonVariant.outline,
                    size: AppButtonSize.sm,
                    onPressed: () => setState(() {
                      _search = '';
                      _from = '';
                      _to = '';
                    }),
                  ),
                  ReportExportButtons(
                    onCsv: csv,
                    onEmail: () => showReportEmailDialog(
                      context,
                      client: widget.session.farmClient,
                      document: doc,
                      defaultRecipient: defaultEmailRecipient(widget.session, widget.company),
                    ),
                    onPdf: () async {
                      setState(() => _downloading = true);
                      try {
                        await ReportExport.sharePdf(doc());
                      } finally {
                        if (mounted) setState(() => _downloading = false);
                      }
                    },
                    busy: _downloading,
                    disabled: _loading || rows.isEmpty,
                  ),
                ]),
              ]),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else ...[
              twoColumns([
                for (final c in cards)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white, border: Border.all(color: slate200), borderRadius: BorderRadius.circular(12)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(c.$1.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: .5, color: slate500)),
                      Text(c.$2,
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: c.$4 == 'green' ? const Color(0xFF059669) : c.$4 == 'rose' ? const Color(0xFFDC2626) : slate900,
                          )),
                      Text(c.$3, style: const TextStyle(fontSize: 11.5, color: slate400)),
                    ]),
                  ),
              ]),
              const SizedBox(height: 14),
              ShellCards(
                columns: _columns,
                rows: [for (final r in rows) _cells(r)],
                totals: totals,
                empty: 'No batches found for the selected filters.',
                valueColor: (r, c) => c == 6
                    ? emerald700
                    : c == 9
                        ? const Color(0xFFB91C1C)
                        : c == 12 && rows[r].deaths > 0
                            ? const Color(0xFFB91C1C)
                            : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// =========================================================================
// Feed Production Reports
// =========================================================================

/// /poultry-feed-production/reports: posted feed batches with full costing,
/// and ingredient usage.
class FeedProductionReportsScreen extends StatefulWidget {
  const FeedProductionReportsScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<FeedProductionReportsScreen> createState() => _FeedProductionReportsScreenState();
}

class _FeedProductionReportsScreenState extends State<FeedProductionReportsScreen> {
  String _from = '', _to = '';
  bool _loading = true;
  List<Map> _batches = [], _usage = [];
  FarmMoney _money = const FarmMoney();
  Duration _offset = Duration.zero;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _money = m);
    });
    CompanyClock.load(widget.session, widget.company).then((c) {
      if (mounted) setState(() => _offset = c.offset);
    });
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final q = {
      'farmId': widget.company.farmId,
      if (_from.isNotEmpty) 'fromDate': _from,
      if (_to.isNotEmpty) 'toDate': _to,
    };
    try {
      final r = await Future.wait([
        _list(widget.session, '/api/Poultry/feed-production', {...q, 'status': 'Posted'}),
        _list(widget.session, '/api/Poultry/feed-production/reports/ingredient-usage', q),
      ]);
      setState(() {
        _batches = r[0];
        _usage = r[1];
      });
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load reports. ${e.message}')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _when(Map b) {
    final k = _key(b['productionDate']);
    if (k.isEmpty) return '—';
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final p = k.split('-');
    final d = '${int.parse(p[2])} ${m[int.parse(p[1]) - 1]} ${p[0]}';
    for (final c in ['createdDate', 'createdAt', 'dateCreated', 'createdOn']) {
      final v = b[c];
      if (v is String && v.trim().isNotEmpty) {
        final full = fmtInstant(v, _offset);
        final at = full.lastIndexOf(', ');
        if (at > 0) return '$d, ${full.substring(at + 2)}';
      }
    }
    return d;
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-feed-production/reports');
    num sum(List<Map> l, String k) => l.fold<num>(0, (s, x) => s + _n(x[k]));
    Widget mini(String label, String value) => Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: slate200), borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, letterSpacing: .4, color: slate500)),
            Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: slate900)),
          ]),
        );
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Feed Production Reports')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PoultryReportsCatalogScreen(session: widget.session, company: widget.company),
              )),
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('Back'),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: slate200), borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: _dateBox('From', _from, (v) => setState(() => _from = v))),
                const SizedBox(width: 8),
                Expanded(child: _dateBox('To', _to, (v) => setState(() => _to = v))),
              ]),
              const SizedBox(height: 10),
              AppButton(label: 'Apply', busy: _loading, onPressed: _loading ? null : _load),
            ]),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Row(children: [
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 8),
              Text('Loading…', style: TextStyle(color: slate500)),
            ])
          else ...[
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 0, icon: Icon(Icons.factory_outlined, size: 16), label: Text('Feed Production')),
                ButtonSegment(value: 1, icon: Icon(Icons.grass, size: 16), label: Text('Ingredient Usage')),
              ],
              selected: {_tab},
              onSelectionChanged: (s) => setState(() => _tab = s.first),
            ),
            const SizedBox(height: 12),
            if (_tab == 0) ...[
              twoColumns(gap: 8, [
                mini('Batches', fmtNum(_batches.length, 0)),
                mini('Qty produced', fmtNum(sum(_batches, 'quantityProduced'), 3)),
                mini('Ingredient cost', _money(sum(_batches, 'totalIngredientCost'))),
                mini('Additional cost', _money(sum(_batches, 'totalAdditionalCost'))),
                mini('Total cost', _money(sum(_batches, 'totalProductionCost'))),
              ]),
              const SizedBox(height: 12),
              _TappableCards(
                columns: const [
                  ReportColumn('Batch #'), ReportColumn('Date'), ReportColumn('Finished Feed'), ReportColumn('Qty', right: true),
                  ReportColumn('Ingredient', right: true), ReportColumn('Additional', right: true), ReportColumn('Total', right: true),
                  ReportColumn('Cost/Unit', right: true),
                ],
                rows: [
                  for (final b in _batches)
                    [
                      '${b['batchNumber'] ?? ''}',
                      _when(b),
                      '${b['finishedFeedItemName'] ?? '—'}',
                      '${fmtNum(_n(b['quantityProduced']), 3)}${'${b['outputUnit'] ?? ''}'.isNotEmpty ? ' ${b['outputUnit']}' : ''}',
                      _money(_n(b['totalIngredientCost'])),
                      _money(_n(b['totalAdditionalCost'])),
                      _money(_n(b['totalProductionCost'])),
                      _money(_n(b['costPerOutputUnit'])),
                    ],
                ],
                empty: 'No posted batches in this range.',
                // A row opens that batch, as the web's row click does.
                onTap: (i) => openAppHref(context, widget.session, widget.company,
                    '/poultry-feed-production/${_batches[i]['poultryFeedProductionBatchId']}',
                    label: 'Feed batch ${_batches[i]['batchNumber'] ?? ''}'),
              ),
            ] else ...[
              Text.rich(TextSpan(style: const TextStyle(fontSize: 13, color: slate500), children: [
                const TextSpan(text: 'Total ingredient cost across posted batches: '),
                TextSpan(text: _money(sum(_usage, 'totalCost')), style: const TextStyle(fontWeight: FontWeight.w600, color: slate800)),
              ])),
              const SizedBox(height: 10),
              ShellCards(
                columns: const [
                  ReportColumn('Ingredient'), ReportColumn('Total used', right: true), ReportColumn('From inventory', right: true),
                  ReportColumn('Bought', right: true), ReportColumn('Cost', right: true), ReportColumn('Batches', right: true),
                ],
                rows: [
                  for (final u in _usage)
                    [
                      '${u['ingredientName'] ?? ''}',
                      '${fmtNum(_n(u['totalQuantityUsed']), 3)}${'${u['unitOfMeasure'] ?? ''}'.isNotEmpty ? ' ${u['unitOfMeasure']}' : ''}',
                      fmtNum(_n(u['fromInventoryQuantity']), 3),
                      fmtNum(_n(u['purchasedQuantity']), 3),
                      _money(_n(u['totalCost'])),
                      '${_n(u['batchCount']).toInt()}',
                    ],
                ],
                empty: 'No ingredient usage in this range.',
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// ShellCards whose rows open something.
class _TappableCards extends StatelessWidget {
  const _TappableCards({required this.columns, required this.rows, required this.empty, required this.onTap});
  final List<ReportColumn> columns;
  final List<List<String>> rows;
  final String empty;
  final void Function(int row) onTap;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return ShellCards(columns: columns, rows: rows, empty: empty);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (i, r) in rows.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => onTap(i),
            child: IgnorePointer(child: ShellCards(columns: columns, rows: [r])),
          ),
        ),
    ]);
  }
}

// =========================================================================
// Changes Report
// =========================================================================

/// actionKind.
String actionKind(Object? action) => switch ('${action ?? ''}'.toUpperCase()) {
      'POST' || 'CREATE' || 'CREATED' => 'Created',
      'PUT' || 'PATCH' || 'UPDATE' || 'UPDATED' => 'Updated',
      'DELETE' || 'DELETED' => 'Deleted',
      'GET' || 'VIEW' || 'VIEWED' => 'Viewed',
      _ => 'Other',
    };

/// friendlyResource: "PoultryCashAccount" → "Cash Account".
String friendlyResource(Object? r) {
  final s = '${r ?? ''}';
  if (s.isEmpty) return 'Record';
  final out = s.replaceFirst(RegExp('^Poultry', caseSensitive: false), '').replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}').trim();
  return out.isEmpty ? s : out;
}

const _noiseKeys = {'farmid', 'createdby', 'updatedby', 'deletedby', 'userid', 'companyid', 'tenantid'};

/// buildFields: the record's values a person can read, noise and ids dropped.
List<(String, String)> buildFields(Object? raw) {
  Object? data;
  try {
    data = raw == null || '$raw'.isEmpty ? null : jsonDecode('$raw');
  } catch (_) {
    data = null;
  }
  if (data is! Map) return const [];
  Object? req = data['request'] ?? data;
  if (req is Map) {
    final keys = [for (final k in req.keys) if (!['method', 'path', 'response'].contains(k)) k];
    if (keys.length == 1 && req[keys.first] is Map) req = req[keys.first];
  }
  if (req is! Map) return const [];
  final guid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', caseSensitive: false);
  String humanize(String k) => k
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .replaceFirstMapped(RegExp('^.'), (m) => m[0]!.toUpperCase())
      .replaceAll(RegExp(r'\bId\b'), 'ID');
  final out = <(String, String)>[];
  req.forEach((k, v) {
    final key = '$k', lk = key.toLowerCase();
    if (v == null || v == '') return;
    if (_noiseKeys.contains(lk) || (v is String && (guid.hasMatch(v) || v.startsWith('0001-01-01')))) return;
    if (v is num && lk.endsWith('id') && v == 0) return;
    if (v is Map || v is List) return;
    String value;
    if (v is bool) {
      value = v ? 'Yes' : 'No';
    } else if (v is String && RegExp('date|time', caseSensitive: false).hasMatch(key) && RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(v)) {
      value = _localeInstant(v);
    } else {
      value = '$v';
    }
    out.add((humanize(key), value));
  });
  return out;
}

/// /poultry/reports/changes: every create, update and delete on the farm.
class ChangesReportScreen extends StatefulWidget {
  const ChangesReportScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<ChangesReportScreen> createState() => _ChangesReportScreenState();
}

class _ChangesReportScreenState extends State<ChangesReportScreen> {
  static const _pageSize = 15;
  List<Map> _logs = [];
  bool _loading = true;
  String _error = '';
  String _search = '', _action = 'changes', _from = '', _to = '';
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final r = await widget.session.farmClient.get('/api/AuditLogs', query: {'page': '1', 'pageSize': '500', 'farmId': widget.company.farmId});
      setState(() => _logs = [for (final l in LookupLoader.rowsIn(r)) if (l is Map) l]);
    } on ApiException catch (e) {
      setState(() {
        _error = e.statusCode == 0 && e.message.contains('too long')
            ? 'Request timed out. The Farm API may be cold-starting — wait a moment and refresh.'
            : e.message.isEmpty
                ? 'Failed to load changes. Check your connection.'
                : e.message;
        _logs = [];
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _user(Object? name) {
    final n = '${name ?? ''}';
    if (n.isNotEmpty && n.toLowerCase() != 'unknown') return n;
    return (widget.session.username ?? '').isNotEmpty ? widget.session.username! : 'Unknown';
  }

  List<Map> get _filtered {
    final q = _search.trim().toLowerCase();
    final out = [
      for (final l in _logs)
        if (() {
          final kind = actionKind(l['action']);
          if (_action == 'changes' && kind == 'Viewed') return false;
          if (['Created', 'Updated', 'Deleted'].contains(_action) && kind != _action) return false;
          final d = '${l['timestamp'] ?? ''}'.split('T').first;
          if (_from.isNotEmpty && d.compareTo(_from) < 0) return false;
          if (_to.isNotEmpty && d.compareTo(_to) > 0) return false;
          if (q.isEmpty) return true;
          return ['resource', 'action', 'userName', 'details', 'resourceId'].any((k) => '${l[k] ?? ''}'.toLowerCase().contains(q));
        }())
          l,
    ];
    out.sort((a, b) => '${b['timestamp'] ?? ''}'.compareTo('${a['timestamp'] ?? ''}'));
    return out;
  }

  Future<void> _csv(List<Map> rows) {
    String cell(Object? v) {
      final s = '${v ?? ''}';
      return RegExp(r'[",\n]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;
    }

    final lines = [
      ['When', 'User', 'Action', 'Record', 'Record ID', 'Status', 'Details'],
      for (final l in rows)
        [
          _localeInstant(l['timestamp']),
          _user(l['userName']),
          actionKind(l['action']),
          '${l['resource'] ?? ''}',
          '${l['resourceId'] ?? ''}',
          '${l['status'] ?? ''}',
          '${l['details'] ?? ''}'.replaceAll(RegExp(r'\s+'), ' ').trim(),
        ],
    ];
    return ReportExport.sharer('poultry-changes-report-${isoDay(DateTime.now())}.csv',
        utf8.encode(lines.map((r) => r.map(cell).join(',')).join('\n')), 'text/csv', 'Poultry Changes Report');
  }

  void _view(Map l) {
    final fields = buildFields(l['data']);
    final kind = actionKind(l['action']);
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('$kind · ${friendlyResource(l['resource'])}${'${l['resourceId'] ?? ''}'.isNotEmpty ? ' #${l['resourceId']}' : ''}'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              twoColumns(gap: 8, [
                for (final (k, v) in [
                  ('When', _localeInstant(l['timestamp'])),
                  ('User', _user(l['userName'])),
                  ('Action', '$kind ${friendlyResource(l['resource']).toLowerCase()}'),
                  ('Status', '${l['status'] ?? ''}'),
                ])
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(k, style: const TextStyle(fontSize: 12, color: slate500)),
                    Text(v, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  ]),
              ]),
              const SizedBox(height: 14),
              const Text('Record details', style: TextStyle(fontSize: 13, color: slate500)),
              const SizedBox(height: 6),
              if (fields.isEmpty)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: slate50, border: Border.all(color: slate200), borderRadius: BorderRadius.circular(6)),
                  child: const Text('No field-level details were recorded for this change.', style: TextStyle(fontSize: 13, color: slate500)),
                )
              else
                Container(
                  decoration: BoxDecoration(border: Border.all(color: slate200), borderRadius: BorderRadius.circular(6)),
                  child: Column(children: [
                    for (final (i, (label, value)) in fields.indexed)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: slate100))),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(label, style: const TextStyle(fontSize: 13, color: slate500)),
                          const SizedBox(width: 12),
                          Expanded(child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                        ]),
                      ),
                  ]),
                ),
            ]),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry/reports/changes');
    final filtered = _filtered;
    final pages = (filtered.length / _pageSize).ceil().clamp(1, 1 << 30);
    final page = _page.clamp(1, pages);
    final shown = filtered.skip((page - 1) * _pageSize).take(_pageSize).toList();
    void refilter(VoidCallback f) => setState(() {
          f();
          _page = 1;
        });
    return Scaffold(
      backgroundColor: slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Poultry Changes Report')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: AppButton(
                label: 'Poultry reports',
                icon: Icons.arrow_back,
                variant: AppButtonVariant.outline,
                size: AppButtonSize.sm,
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PoultryReportsCatalogScreen(session: widget.session, company: widget.company),
                )),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Every create, update and delete on this farm — who changed what, and when.',
                style: TextStyle(fontSize: 13, color: slate600)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: AppButton(label: 'Refresh', icon: Icons.refresh, variant: AppButtonVariant.outline, size: AppButtonSize.sm, busy: _loading, onPressed: _loading ? null : _load),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppButton(
                  label: 'Export CSV',
                  icon: Icons.download,
                  variant: AppButtonVariant.outline,
                  size: AppButtonSize.sm,
                  onPressed: filtered.isEmpty ? null : () => _csv(filtered),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            const Text('Search', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            AppInput(initialValue: _search, hintText: 'Record, user, details…', onChanged: (v) => refilter(() => _search = v)),
            const SizedBox(height: 8),
            const Text('Action', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            AppSelect<String>(
              value: _action,
              items: const [
                AppSelectItem(value: 'changes', label: 'All changes'),
                AppSelectItem(value: 'Created', label: 'Created'),
                AppSelectItem(value: 'Updated', label: 'Updated'),
                AppSelectItem(value: 'Deleted', label: 'Deleted'),
                AppSelectItem(value: 'all', label: 'All activity (incl. views)'),
              ],
              onChanged: (v) => refilter(() => _action = v ?? 'changes'),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _dateBox('From', _from, (v) => refilter(() => _from = v))),
              const SizedBox(width: 8),
              Expanded(child: _dateBox('To', _to, (v) => refilter(() => _to = v))),
            ]),
            if (_error.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFFFF1F2), border: Border.all(color: const Color(0xFFFECDD3)), borderRadius: BorderRadius.circular(6)),
                child: Text(_error, style: const TextStyle(fontSize: 13, color: rose700)),
              ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: slate200), borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (_loading)
                  const Padding(padding: EdgeInsets.all(30), child: Text('Loading changes…', textAlign: TextAlign.center, style: TextStyle(color: slate500)))
                else if (shown.isEmpty)
                  const Padding(
                      padding: EdgeInsets.all(30),
                      child: Text('No changes match the current filters.', textAlign: TextAlign.center, style: TextStyle(color: slate500)))
                else
                  for (final (i, l) in shown.indexed)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: slate100))),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                              _ActionBadge(actionKind(l['action'])),
                              Text.rich(TextSpan(style: const TextStyle(fontSize: 14, color: slate700), children: [
                                TextSpan(text: friendlyResource(l['resource'])),
                                if ('${l['resourceId'] ?? ''}'.isNotEmpty)
                                  TextSpan(text: ' #${l['resourceId']}', style: const TextStyle(color: slate400)),
                              ])),
                            ]),
                            const SizedBox(height: 4),
                            Text(_user(l['userName']), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: slate800)),
                            Text(_localeInstant(l['timestamp']), style: const TextStyle(fontSize: 12, color: slate700)),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                border: Border.all(color: l['status'] == 'Failed' ? const Color(0xFFFECDD3) : const Color(0xFFA7F3D0)),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text('${l['status'] ?? ''}',
                                  style: TextStyle(fontSize: 11.5, color: l['status'] == 'Failed' ? rose700 : emerald700)),
                            ),
                          ]),
                        ),
                        TextButton.icon(onPressed: () => _view(l), icon: const Icon(Icons.visibility_outlined, size: 16), label: const Text('View')),
                      ]),
                    ),
                if (!_loading && filtered.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    decoration: const BoxDecoration(border: Border(top: BorderSide(color: slate100))),
                    child: Row(children: [
                      Expanded(
                        child: Text(
                          '${(page - 1) * _pageSize + 1}–${(page * _pageSize).clamp(0, filtered.length)} of ${filtered.length}',
                          style: const TextStyle(fontSize: 13, color: slate500),
                        ),
                      ),
                      AppButton(label: 'Previous', variant: AppButtonVariant.outline, size: AppButtonSize.sm, onPressed: page <= 1 ? null : () => setState(() => _page = page - 1)),
                      const SizedBox(width: 6),
                      AppButton(label: 'Next', variant: AppButtonVariant.outline, size: AppButtonSize.sm, onPressed: page >= pages ? null : () => setState(() => _page = page + 1)),
                    ]),
                  ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionBadge extends StatelessWidget {
  const _ActionBadge(this.kind);
  final String kind;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (kind) {
      'Created' => (const Color(0xFFD1FAE5), emerald700),
      'Updated' => (amber100, amber700),
      'Deleted' => (const Color(0xFFFFE4E6), rose700),
      _ => (slate100, slate600),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(kind, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: fg)),
    );
  }
}
