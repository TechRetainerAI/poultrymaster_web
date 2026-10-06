import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/buttons.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../lookup_loader.dart';
import '../../shared/business_dates.dart';
import 'poultry_report_screen.dart';
import 'report_export.dart';
import 'report_format.dart';
import 'report_shell.dart';
import 'report_widgets.dart';
import 'reports_catalog_screen.dart';

num _n(Object? v) => toNum(v);
String _day(Object? v) => '${v ?? ''}'.length >= 10 ? '${v ?? ''}'.substring(0, 10) : '${v ?? ''}';

Future<List<Map>> _list(Session s, String path, Map<String, String> q) async =>
    [for (final r in LookupLoader.rowsIn(await s.farmClient.get(path, query: q))) if (r is Map) r];

// =========================================================================
// Daily Business Summary
// =========================================================================

/// /poultry-daily-summary: one day's income, production, costs and cash, from
/// the day's closing when there is one, otherwise the driver returns.
class DailyBusinessSummaryScreen extends StatefulWidget {
  const DailyBusinessSummaryScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<DailyBusinessSummaryScreen> createState() => _DailyBusinessSummaryScreenState();
}

class _DailyBusinessSummaryScreenState extends State<DailyBusinessSummaryScreen> {
  // The web's isoDate(new Date()): today.
  String _date = isoDay(DateTime.now());
  bool _busy = false;
  Map<String, dynamic>? _s;
  FarmMoney _money = const FarmMoney();
  late final String _generated = generatedNow();

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _money = m);
    });
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    final farm = widget.company.farmId;
    final scope = {'userId': widget.session.tokens.userId ?? '', 'farmId': farm};
    final day = {'farmId': farm, 'fromDate': _date, 'toDate': _date};
    bool on(Object? d) => _day(d) == _date;
    Future<List<Map>> safe(String p, Map<String, String> q) => _list(widget.session, p, q).catchError((_) => <Map>[]);
    try {
      final r = await Future.wait([
        safe('/api/Poultry/daily-closings', day),
        safe('/api/EggProduction', scope),
        safe('/api/Expense', scope),
        safe('/api/Poultry/loss-records', day),
        safe('/api/Poultry/raw-material-purchases', day),
        safe('/api/Poultry/driver-returns', day),
      ]);
      final closing = r[0].where((c) => on(c['closingDate'])).firstOrNull;
      final prods = [for (final p in r[1]) if (on(p['productionDate'])) p];
      final exps = [for (final e in r[2]) if (on(e['expenseDate'])) e];
      final byCat = <String, num>{};
      for (final e in exps) {
        final k = '${e['category'] ?? 'Uncategorised'}';
        byCat[k] = (byCat[k] ?? 0) + _n(e['amount']);
      }
      final purchases = r[4]
          .where((p) => on(p['purchaseDate']))
          .fold<num>(0, (s, p) => s + (p['totalCost'] != null ? _n(p['totalCost']) : _n(p['quantity']) * _n(p['unitCost'])));
      // Only approved losses count — a pending loss is a claim, not a cost.
      final losses = r[3].where((l) => l['status'] == 'Approved').fold<num>(0, (s, l) => s + _n(l['estimatedValue']));
      final returns = [
        for (final x in r[5])
          if (on(x['returnDate']) && (x['status'] == 'Approved' || x['status'] == 'Draft')) x,
      ];
      num sumR(String k) => returns.fold<num>(0, (s, x) => s + _n(x[k]));
      final Map<String, Object> income = closing != null
          ? {
              'total': _n(closing['totalIncome']),
              'cash': _n(closing['cashCollected'] ?? closing['cashAtHand']),
              'moMo': _n(closing['moMoCollected'] ?? closing['moMoBalance']),
              'bank': _n(closing['bankCollected'] ?? closing['bankBalance']),
              'creditSales': _n(closing['creditSales']),
              'customerCollections': _n(closing['customerCollections']),
              'eggsSold': _n(closing['eggsSold']),
              'driverShortages': sumR('shortageAmount'),
              'source': 'closing',
            }
          : returns.isNotEmpty
              ? {
                  'total': returns.fold<num>(
                      0, (s, x) => s + _n(x['cashCollected']) + _n(x['moMoCollected']) + _n(x['bankCollected']) + _n(x['creditSalesAmount'])),
                  'cash': sumR('cashCollected'),
                  'moMo': sumR('moMoCollected'),
                  'bank': sumR('bankCollected'),
                  'creditSales': sumR('creditSalesAmount'),
                  'customerCollections': 0,
                  'eggsSold': sumR('cratesSold'),
                  'driverShortages': sumR('shortageAmount'),
                  'source': 'returns',
                }
              : {
                  'total': 0, 'cash': 0, 'moMo': 0, 'bank': 0, 'creditSales': 0,
                  'customerCollections': 0, 'eggsSold': 0, 'driverShortages': 0, 'source': 'none',
                };
      setState(() => _s = {
            'eggsProduced': closing?['quantityProduced'] != null
                ? _n(closing!['quantityProduced'])
                : prods.fold<num>(0, (s, p) => s + _n(p['totalProduction'])),
            'brokenEggs': closing?['quantityDamaged'] != null
                ? _n(closing!['quantityDamaged'])
                : prods.fold<num>(0, (s, p) => s + _n(p['brokenEggs'])),
            'productionCost': _n(closing?['totalProductionCost']),
            'closingStock': _n(closing?['closingStock']),
            'mortality': _n(closing?['mortality']),
            'feedUsed': _n(closing?['feedUsedQty']),
            'rawMaterialPurchase': purchases,
            'expenses': exps.fold<num>(0, (s, e) => s + _n(e['amount'])),
            'expensesByCategory': byCat,
            'losses': losses,
            'closingStatus': closing?['status'],
            'cashDifference': closing == null ? null : _n(closing['cashDifference']),
            'income': income,
          });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load daily summary. $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _m(Object? n) => _money(_n(n));

  List<(String, String, String?)> get _incomeCards {
    final i = _s!['income'] as Map;
    return [
      ('Total income', _m(i['total']), 'green'),
      ('Cash', _m(i['cash']), null),
      ('MoMo', _m(i['moMo']), null),
      ('Bank', _m(i['bank']), null),
      ('Credit sales', _m(i['creditSales']), null),
      ('Customer collections', _m(i['customerCollections']), null),
      ('Eggs sold', fmtNum(_n(i['eggsSold']), 3), null),
      ('Driver shortages', _m(i['driverShortages']), _n(i['driverShortages']) != 0 ? 'rose' : null),
    ];
  }

  List<(String, String, String?)> get _productionCards => [
        ('Eggs produced', fmtNum(_n(_s!['eggsProduced']), 3), null),
        ('Broken eggs', fmtNum(_n(_s!['brokenEggs']), 3), _n(_s!['brokenEggs']) != 0 ? 'rose' : null),
        ('Closing egg stock', fmtNum(_n(_s!['closingStock']), 3), null),
        ('Mortality', fmtNum(_n(_s!['mortality']), 3), _n(_s!['mortality']) != 0 ? 'rose' : null),
      ];

  List<(String, String, String?)> get _costCards => [
        ('Production cost', _m(_s!['productionCost']), null),
        ('Feed used', fmtNum(_n(_s!['feedUsed']), 3), null),
        ('Raw material purchases', _m(_s!['rawMaterialPurchase']), null),
        ('Expenses', _m(_s!['expenses']), null),
        ('Loss value', _m(_s!['losses']), _n(_s!['losses']) != 0 ? 'rose' : null),
        ('Closing status', '${_s!['closingStatus'] ?? 'Not closed'}', null),
        ('Cash difference', _s!['cashDifference'] == null ? '—' : _m(_s!['cashDifference']), _n(_s!['cashDifference']) != 0 ? 'rose' : null),
      ];

  List<MapEntry<String, num>> get _categories =>
      ((_s!['expensesByCategory'] as Map<String, num>).entries.toList()..sort((a, b) => b.value.compareTo(a.value)));

  /// "Export PDF" prints the page on the web; here it is the same sections as
  /// a PDF.
  ReportDocument _document() {
    List<String> row(List<(String, String, String?)> cards) => [for (final c in cards) c.$2];
    List<ReportColumn> heads(List<(String, String, String?)> cards) => [for (final c in cards) ReportColumn(c.$1)];
    return ReportDocument(
      title: 'Daily Business Summary',
      filename: 'poultry-daily-summary',
      farmName: widget.company.name,
      fromDate: _date,
      toDate: _date,
      generatedBy: reportUser(widget.session),
      currencyLabel: _money.label,
      cards: [for (final c in _incomeCards) (label: c.$1, value: c.$2, accent: c.$3, note: null)],
      sections: [
        ReportSection(heading: 'Production', columns: heads(_productionCards), rows: [row(_productionCards)]),
        ReportSection(heading: 'Costs and cash', columns: heads(_costCards), rows: [row(_costCards)]),
        ReportSection(
          heading: 'Expense breakdown',
          columns: const [ReportColumn('Category'), ReportColumn('Amount', right: true)],
          rows: [for (final e in _categories) [e.key, _m(e.value)]],
        ),
      ],
      notes: [
        'Built from the day\'s production, expense, purchase, loss and closing records for $_date. '
            'Cash, production cost and closing stock come from the day\'s closing, so they read as zero until it is created.',
      ],
    );
  }

  Widget _section(String title, List<(String, String, String?)> cards) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ShellHeading(title),
        twoColumns([
          for (final c in cards)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: slate200), borderRadius: BorderRadius.circular(10)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.$1.toUpperCase(), style: const TextStyle(fontSize: 10.5, letterSpacing: .5, color: slate500)),
                const SizedBox(height: 4),
                Text(c.$2, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: accentValue(c.$3))),
              ]),
            ),
        ]),
      ]);

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-daily-summary');
    final s = _s;
    final source = s == null ? null : (s['income'] as Map)['source'];
    return Scaffold(
      backgroundColor: slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Daily Business Summary')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
        children: [
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.spaceBetween, children: [
            AppButton(
              label: 'Reports',
              icon: Icons.arrow_back,
              variant: AppButtonVariant.outline,
              size: AppButtonSize.sm,
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PoultryReportsCatalogScreen(session: widget.session, company: widget.company),
              )),
            ),
            AppButton(
              label: 'Export PDF',
              icon: Icons.print_outlined,
              size: AppButtonSize.sm,
              onPressed: s == null ? null : () => ReportExport.sharePdf(_document()),
            ),
          ]),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: slate200), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                padding: const EdgeInsets.only(bottom: 12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: slate200))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Daily Business Summary', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600, color: slate900)),
                  const SizedBox(height: 4),
                  for (final (k, v) in [
                    ('Company', widget.company.name.isEmpty ? '—' : widget.company.name),
                    ('Date', _date),
                    ('Currency', _money.label),
                    ('Generated', _generated),
                  ])
                    Text.rich(TextSpan(style: const TextStyle(fontSize: 13, color: slate500), children: [
                      TextSpan(text: '$k: ', style: const TextStyle(fontWeight: FontWeight.w500)),
                      TextSpan(text: v),
                    ])),
                ]),
              ),
              const Text('Date', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(
                  child: AppDateField(
                    value: businessDateAsDateTime(_date),
                    firstDate: DateTime(2000),
                    onChanged: (d) {
                      if (d == null) return;
                      setState(() => _date = isoDay(d));
                      _load();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                AppButton(label: 'Refresh', variant: AppButtonVariant.outline, size: AppButtonSize.sm, onPressed: _busy ? null : _load),
              ]),
              const SizedBox(height: 8),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Row(children: [
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text('Loading…', style: TextStyle(color: slate500)),
                  ]),
                )
              else if (s == null)
                const Text('No data for this date.', style: TextStyle(fontSize: 13, color: slate500))
              else ...[
                _section('Income', _incomeCards),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    source == 'closing'
                        ? "Income figures are taken from the day's closing (storefront and delivery sales combined)."
                        : source == 'returns'
                            ? "No closing for this day yet — income is computed from the day's driver returns. Create the closing for the full picture."
                            : 'No driver returns or closing recorded for this date.',
                    style: const TextStyle(fontSize: 12, color: slate500),
                  ),
                ),
                _section('Production', _productionCards),
                _section('Costs and cash', _costCards),
                const ShellHeading('Expense breakdown'),
                if (_categories.isEmpty)
                  const Text('No expenses recorded on this date.', style: TextStyle(fontSize: 13, color: slate500))
                else
                  for (final e in _categories)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: slate100))),
                      child: Row(children: [
                        Expanded(child: Text(e.key, style: const TextStyle(fontSize: 14))),
                        Text(_m(e.value), style: const TextStyle(fontSize: 14)),
                      ]),
                    ),
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.only(top: 10),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: slate200))),
                  child: Text(
                    "Built from the day's production, expense, purchase, loss and closing records for $_date. "
                    "Cash, production cost and closing stock come from the day's closing, so they read as zero until it is created.",
                    style: const TextStyle(fontSize: 12, color: slate500),
                  ),
                ),
              ],
            ]),
          ),
        ],
      ),
    );
  }
}

// =========================================================================
// Closing Report
// =========================================================================

/// /poultry-closing-report-daily: every daily closing in the period, with
/// cash reconciliation and approval status.
class ClosingReportScreen extends StatefulWidget {
  const ClosingReportScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<ClosingReportScreen> createState() => _ClosingReportScreenState();
}

class _ClosingReportScreenState extends State<ClosingReportScreen> {
  late String _from = defaultReportRange().from, _to = defaultReportRange().to;
  List<Map> _rows = [];
  bool _busy = true;
  String? _error;
  FarmMoney _money = const FarmMoney();

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _money = m);
    });
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await _list(widget.session, '/api/Poultry/daily-closings', {'farmId': widget.company.farmId, 'fromDate': _from, 'toDate': _to});
      if (mounted) setState(() => _rows = r);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _note(Map c) => '${c['rejectionReason'] ?? ''}'.isNotEmpty
      ? 'Rejected: ${c['rejectionReason']}'
      : ('${c['managerNotes'] ?? ''}'.isEmpty ? '—' : '${c['managerNotes']}');

  static const _columns = [
    ReportColumn('Date'),
    ReportColumn('Produced', right: true),
    ReportColumn('Sold', right: true),
    ReportColumn('Income', right: true),
    ReportColumn('Expenses', right: true),
    ReportColumn('Cash at hand', right: true),
    ReportColumn('Counted', right: true),
    ReportColumn('Difference', right: true),
    ReportColumn('Status'),
    ReportColumn('Notes'),
  ];

  List<List<String>> get _table => [
        for (final c in _rows)
          [
            _day(c['closingDate']),
            fmtNum(_n(c['quantityProduced']), 3),
            fmtNum(_n(c['eggsSold']), 3),
            _money(_n(c['totalIncome'])),
            _money(_n(c['totalExpenses'])),
            _money(_n(c['cashAtHand'])),
            _money(_n(c['actualCashCounted'])),
            _money(_n(c['cashDifference'])),
            '${c['status'] ?? ''}',
            _note(c),
          ],
      ];

  @override
  Widget build(BuildContext context) {
    final approved = [for (final c in _rows) if (c['status'] == 'Approved') c];
    num sum(String k) => approved.fold<num>(0, (s, c) => s + _n(c[k]));
    final short = approved.where((c) => _n(c['cashDifference']) != 0).length;
    final diff = sum('cashDifference');
    final tiles = <SummaryCardData>[
      (label: 'Closings', value: '${approved.length} / ${_rows.length}', accent: null, note: null),
      (label: 'Income', value: _money(sum('totalIncome')), accent: 'green', note: null),
      (label: 'Expenses', value: _money(sum('totalExpenses')), accent: 'rose', note: null),
      (label: 'Cash at hand', value: _money(sum('cashAtHand')), accent: null, note: null),
      (
        label: short > 0 ? 'Cash difference ($short day${short == 1 ? '' : 's'})' : 'Cash difference',
        value: _money(diff),
        accent: diff != 0 ? 'rose' : null,
        note: null,
      ),
    ];
    return ReportShellScreen(
      session: widget.session,
      company: widget.company,
      href: '/poultry-closing-report-daily',
      title: 'Closing Report',
      description: 'Every daily closing, with cash reconciliation and approval status.',
      busy: _busy,
      error: _error,
      onClearError: () => setState(() => _error = null),
      fromDate: _from,
      toDate: _to,
      onRangeChanged: (f, t) {
        setState(() {
          _from = f;
          _to = t;
        });
        _load();
      },
      tiles: tiles,
      recordCount: _rows.length,
      onRefresh: _load,
      document: () => ReportDocument(
        title: 'Closing Report',
        filename: 'poultry-closing-report',
        farmName: widget.company.name,
        cards: [for (final t in tiles) (label: t.label, value: t.value, accent: null, note: null)],
        landscape: true,
        sections: [ReportSection(columns: _columns, rows: _table)],
      ),
      body: [
        ShellCards(
          columns: _columns,
          rows: _table,
          empty: 'No closings in this period.',
          valueColor: (r, c) => c == 7 && _n(_rows[r]['cashDifference']) != 0
              ? rose700
              : c == 8
                  ? switch (_rows[r]['status']) {
                      'Approved' => const Color(0xFF15803D),
                      'Submitted' => const Color(0xFF1D4ED8),
                      'Rejected' => const Color(0xFFB91C1C),
                      _ => null,
                    }
                  : null,
        ),
      ],
    );
  }
}

// =========================================================================
// Closing by Category
// =========================================================================

const closingCategorySections = <(String, Color, List<(String, String, bool)>)>[
  ('Financial Summary', Color(0xFF2563EB), [
    ('Total Sales / Income', 'TotalSales', true),
    ('Total Expenses', 'TotalExpenses', true),
    ('Total Raw Material Purchases', 'TotalRawMaterialPurchases', true),
    ('Total Feed Cost', 'TotalFeedCost', true),
    ('Total Medication Cost', 'TotalMedicationCost', true),
    ('Total Cost of Production', 'TotalCostOfProduction', true),
    ('Net Profit / Loss', 'NetProfitLoss', true),
    ('Amount Owed by Customers', 'TotalOwedByCustomers', true),
  ]),
  ('Production Summary', Color(0xFF059669), [
    ('Total Eggs Produced', 'TotalEggsProduced', false),
    ('Total Good Eggs', 'TotalGoodEggs', false),
    ('Total Broken Eggs', 'TotalBrokenEggs', false),
    ('Total Production Records', 'TotalProductionRecords', false),
    ('Average Eggs / Day', 'AvgEggsPerDay', false),
    ('Average Eggs / Record', 'AvgEggsPerRecord', false),
    ('Total Feed (kg)', 'TotalFeedKg', false),
    ('Total Feed Consumed', 'TotalFeedConsumed', false),
    ('Total Medication Consumed', 'TotalMedicationConsumed', false),
    ('Avg Production Cost / Egg', 'AvgProductionCostPerEgg', true),
  ]),
  ('Inventory Summary', Color(0xFF4F46E5), [
    ('Opening Egg Stock', 'OpeningEggStock', false),
    ('Closing Egg Stock', 'ClosingEggStock', false),
    ('Eggs Sold', 'EggsSold', false),
    ('Raw Materials Purchased (value)', 'RawMaterialsPurchased', true),
    ('Raw Materials Consumed (qty)', 'RawMaterialsConsumed', false),
  ]),
  ('Birds', Color(0xFF9333EA), [
    ('Placed Birds (overall)', 'PlacedBirds', false),
    ('Birds Left', 'BirdsLeft', false),
    ('Birds Lost', 'BirdsLost', false),
    ('Mortality Count', 'MortalityCount', false),
    ('Mortality Rate %', 'MortalityRatePct', false),
    ('Birds Purchased (inventory)', 'BirdsPurchased', false),
    ('Birds Sold (inventory)', 'BirdsSold', false),
  ]),
  ('Losses', Color(0xFFDC2626), [
    ('Production Loss (qty)', 'ProductionLossQty', false),
    ('Approved Loss Value', 'ApprovedLossValue', true),
    ('Broken Eggs', 'BrokenEggsTotal', false),
  ]),
  ('Cash & Delivery', Color(0xFFD97706), [
    ('Cash Sales Collected', 'CashSalesCollected', true),
    ('Cash Adjustments (net)', 'CashAdjustmentsNet', true),
    ('Estimated Cash Inflows', 'EstimatedCashInflows', true),
    ('Eggs Loaded for Delivery', 'EggsLoadedForDelivery', false),
    ('Eggs Returned', 'EggsReturned', false),
    ('Driver Collections', 'DriverCollections', true),
    ('Delivery Expenses', 'DeliveryExpenses', true),
  ]),
];

/// /poultry-closing-report: the period's totals in six coloured sections.
class ClosingByCategoryScreen extends StatefulWidget {
  const ClosingByCategoryScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<ClosingByCategoryScreen> createState() => _ClosingByCategoryScreenState();
}

class _ClosingByCategoryScreenState extends State<ClosingByCategoryScreen> {
  // The web: three years back from 1 January, to today.
  String _from = '${DateTime.now().year - 3}-01-01';
  String _to = isoDay(DateTime.now());
  Map? _data;
  bool _loading = false;
  FarmMoney _money = const FarmMoney();

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _money = m);
    });
    _run();
  }

  Future<void> _run() async {
    setState(() => _loading = true);
    try {
      final r = await widget.session.farmClient
          .get('/api/Poultry/closing-report', query: {'farmId': widget.company.farmId, 'fromDate': _from, 'toDate': _to});
      if (mounted) setState(() => _data = r is Map ? r : null);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load report. ${e.message}')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmt(String key, bool money) {
    // The API's PascalCase keys arrive camelCased.
    final v = _data?[key[0].toLowerCase() + key.substring(1)];
    if (v == null) return '—';
    return money ? _money(_n(v)) : fmtNum(_n(v), 3);
  }

  Widget _date(String label, String value, void Function(String) set) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: slate500)),
          const SizedBox(height: 4),
          AppDateField(
            value: businessDateAsDateTime(value),
            firstDate: DateTime(2000),
            onChanged: (d) {
              if (d != null) setState(() => set(isoDay(d)));
            },
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-closing-report');
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Closing by Category')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
        children: [
          const Text('Period totals grouped into financial, production, inventory and birds.',
              style: TextStyle(fontSize: 13, color: slate500)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: slate200), borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                _date('From', _from, (v) => _from = v),
                const SizedBox(width: 8),
                _date('To', _to, (v) => _to = v),
              ]),
              const SizedBox(height: 10),
              AppButton(label: 'Run report', busy: _loading, onPressed: _loading ? null : _run),
            ]),
          ),
          const SizedBox(height: 14),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Row(children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 8),
                Text('Loading…', style: TextStyle(color: slate500)),
              ]),
            )
          else if (_data != null)
            for (final (title, color, rows) in closingCategorySections)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: slate200), borderRadius: BorderRadius.circular(10)),
                clipBehavior: Clip.antiAlias,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Container(
                    color: color,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    child: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                  for (final (i, (label, key, money)) in rows.indexed)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(border: i == rows.length - 1 ? null : const Border(bottom: BorderSide(color: slate200))),
                      child: Row(children: [
                        Expanded(child: Text(label, style: const TextStyle(fontSize: 14, color: slate600))),
                        Text(_fmt(key, money), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                      ]),
                    ),
                ]),
              ),
        ],
      ),
    );
  }
}
