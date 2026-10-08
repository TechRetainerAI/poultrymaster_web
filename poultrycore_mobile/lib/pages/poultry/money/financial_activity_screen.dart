import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../shared/company_clock.dart';
import '../reports/report_export.dart';
import '../reports/report_format.dart';
import '../reports/report_routes.dart';
import '../sales/balances_logic.dart' show pageSlice;
import '../sales/balances_widgets.dart' show CompactPager, LoadingLine;
import '../trackers/tracker_logic.dart' show tNum, tStr, sortRows, toggleSort, SortState;
import '../trackers/tracker_widgets.dart';
import 'money_widgets.dart';

// ------------------------------------------------------------------ logic

const faTips = {
  'moneyIn':
      'Actual money entering the company. Not the same as revenue — a loan, an owner contribution and a customer paying an old bill are all money in and none of them is income.',
  'moneyOut':
      "Actual money leaving the company. Not the same as an expense — repaying loan principal, buying equipment and paying a supplier for last month's bill all move money without being a cost.",
  'revenue': 'Business income recognised for Profit & Loss, on the day of the sale — not on the day it is paid for.',
  'expense': 'Cost recognised for Profit & Loss. It may be recognised long after the money left, or without any money moving at all.',
  'profit': 'Revenue minus expense recognised by this activity. Money in and money out are never part of it.',
  'runningCash': "The company's cash position after this activity. Non-cash activity leaves it unchanged.",
  'positions':
      'Which assets, debts, receivables, payables, inventory balances, loans or owner capital changed because of this event.',
};

const activityFilters = [
  ('ALL', 'All activity'),
  ('CASH', 'Cash activity'),
  ('PL', 'P&L activity'),
  ('Operating', 'Operating'),
  ('Financing', 'Financing'),
  ('Owner', 'Owner activity'),
  ('Capital', 'Capital activity'),
  ('Inventory', 'Inventory / cost recognition'),
  ('Transfer', 'Internal transfers'),
  ('EmployeeLoan', 'Employee advances'),
];
const cashFilters = [('ALL', 'Cash and non-cash'), ('CASH', 'Cash movement'), ('NON', 'Non-cash activity')];
const profitFilters = [('ALL', 'Any profit impact'), ('POS', 'Positive'), ('NEG', 'Negative'), ('NONE', 'No profit impact')];

const _positionLabels = {
  'Cash': 'Cash',
  'CustomerReceivable': 'Customer Receivable',
  'SupplierPayable': 'Supplier Payable',
  'Inventory': 'Inventory',
  'CapitalAsset': 'Capital Assets',
  'AccumulatedDepreciation': 'Accumulated Depreciation',
  'LoanLiability': 'Loan Liability',
  'OwnerCapital': 'Owner Capital',
  'EmployeeLoanReceivable': 'Employee Loan Receivable',
};
String positionLabel(Object? t) => _positionLabels[tStr(t)] ?? tStr(t);

/// activitySourceLink: the page that owns the event, or null.
(String, String)? activitySourceLink(Map r) {
  final id = r['sourceId'];
  return switch (tStr(r['sourceType'])) {
    'Sale' => ('/sales', 'View sale'),
    'CustomerPayment' => ('/poultry-payments', 'View payment'),
    'SupplierPayment' => ('/supplier-payments', 'View supplier payment'),
    'Expense' => ('/expenses', 'View expense'),
    'LoanReceived' || 'LoanPayment' => ('/poultry-loans', 'View loan'),
    'OwnerContribution' || 'OwnerDraw' => ('/poultry-owner-money', 'View owner money'),
    'CashTransfer' => ('/poultry-cash-transfers', 'View transfer'),
    'CapitalAsset' || 'CapitalAssetCost' || 'AssetDepreciation' => id != null && id != 0 ? ('/poultry-assets', 'View capital assets') : null,
    'PoultryRawMaterialPurchase' => ('/poultry-raw-materials?tab=purchases', 'View purchase'),
    'PoultryFeedConsumption' => ('/feed-inventory-tracker', 'View feed movements'),
    'PoultryMedicationConsumption' => ('/medication-tracker', 'View medication'),
    'PoultryInternalUsage' => ('/poultry-internal-use', 'View internal use'),
    'Payroll' => ('/poultry-payroll', 'View payroll'),
    'MainFlockBatch' => ('/flocks', 'View flock batch'),
    _ => null,
  };
}

/// formatActivityMoment: "10/05/2026 2:30 PM". The business date's own time,
/// else the entry time on the company clock, else the date alone.
String formatActivityMoment(Object? occurredAt, Object? createdAt, Duration offset) {
  final s = tStr(occurredAt).trim();
  if (s.isEmpty) return '—';
  final parts = s.split('T');
  final d = parts[0].split('-');
  if (d.length < 3 || d.any((x) => x.isEmpty)) return s;
  final day = '${d[1]}/${d[2]}/${d[0]}';
  var hhmm = parts.length > 1 && parts[1].length >= 5 ? parts[1].substring(0, 5) : '';
  if (hhmm.isEmpty || hhmm == '00:00') {
    final c = tStr(createdAt).trim();
    if (c.isNotEmpty) {
      final naive = !RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(c);
      final t = DateTime.tryParse(naive ? '${c}Z' : c);
      if (t != null) {
        final local = t.toUtc().add(offset);
        hhmm = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
      }
    }
  }
  if (hhmm.isEmpty || hhmm == '00:00') return day;
  final hh = int.tryParse(hhmm.split(':')[0]);
  if (hh == null) return day;
  final h12 = hh % 12 == 0 ? 12 : hh % 12;
  return '$day $h12:${hhmm.split(':')[1]} ${hh >= 12 ? 'PM' : 'AM'}';
}

/// The page's filters over the loaded rows.
List<Map> filterActivity(List<Map> rows,
    {String search = '', String type = 'ALL', String category = 'ALL', String activity = 'ALL', String cash = 'ALL', String profit = 'ALL'}) {
  final q = search.trim().toLowerCase();
  return rows.where((r) {
    if (q.isNotEmpty &&
        !'${tStr(r['description'])} ${tStr(r['type'])} ${tStr(r['category'])} ${tStr(r['partyName'])}'.toLowerCase().contains(q)) {
      return false;
    }
    if (type != 'ALL' && r['type'] != type) return false;
    if (category != 'ALL' && r['category'] != category) return false;
    final isCash = r['isCashActivity'] == true;
    final impact = tNum(r['profitImpact']);
    if (activity == 'CASH' && !isCash) return false;
    if (activity == 'PL' && impact == 0 && tNum(r['revenue']) == 0 && tNum(r['expense']) == 0) return false;
    if (!['ALL', 'CASH', 'PL'].contains(activity) && r['activityType'] != activity) return false;
    if (cash == 'CASH' && !isCash) return false;
    if (cash == 'NON' && isCash) return false;
    if (profit == 'POS' && impact <= 0) return false;
    if (profit == 'NEG' && impact >= 0) return false;
    if (profit == 'NONE' && impact != 0) return false;
    return true;
  }).toList();
}

/// The CSV the web downloads (no BOM), quoted only where needed.
String activityCsv(List<Map> rows, Duration offset) {
  String esc(Object? v) {
    final s = v == null ? '' : '$v';
    return RegExp(r'[",\n]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  String n(Object? v) {
    final x = tNum(v);
    if (x == 0) return '';
    return x == x.roundToDouble() ? x.toInt().toString() : '$x';
  }

  final lines = ['Date,Type,Category,Description,Money In,Money Out,Revenue,Expense,Profit Impact,Running Cash'];
  for (final r in rows) {
    final rc = tNum(r['runningCash']);
    lines.add([
      formatActivityMoment(r['occurredAt'], r['createdAt'], offset),
      tStr(r['type']),
      tStr(r['category']),
      tStr(r['description']),
      n(r['moneyIn']),
      n(r['moneyOut']),
      n(r['revenue']),
      n(r['expense']),
      n(r['profitImpact']),
      rc == rc.roundToDouble() ? rc.toInt().toString() : '$rc',
    ].map(esc).join(','));
  }
  return lines.join('\n');
}

// ------------------------------------------------------------------ screen

/// Poultry → Money → Financial Activity, as
/// `app/poultry-financial-activity/page.tsx`: how each event affected cash,
/// revenue, expense, profit and financial position (GET
/// /Poultry/financial-activity, migration 290). Phone layout.
class FinancialActivityScreen extends StatefulWidget {
  const FinancialActivityScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;
  @override
  State<FinancialActivityScreen> createState() => _FinancialActivityScreenState();
}

class _FinancialActivityScreenState extends State<FinancialActivityScreen> {
  late String _from = defaultReportRange('thisMonth').from;
  late String _to = defaultReportRange('thisMonth').to;
  Map? _data;
  bool _loading = true;
  bool _refreshing = false;
  String _error = '';
  final _search = TextEditingController();
  String _activity = 'ALL', _cash = 'ALL', _profit = 'ALL', _type = 'ALL', _category = 'ALL';
  final Set<String> _expanded = {};
  SortState _sort = (key: null, dir: null);
  int _page = 1;
  int _pageSize = 25;
  int _lastTotal = -1;
  FarmMoney _gh = const FarmMoney();
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _gh = m);
    });
    CompanyClock.load(widget.session, widget.company).then((c) {
      if (mounted) setState(() => _offset = c.offset);
    });
    _load(first: true);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool first = false}) async {
    setState(() {
      _error = '';
      if (first) _loading = true;
    });
    try {
      final res = await _api.get('/api/Poultry/financial-activity', query: {
        'farmId': widget.company.farmId,
        if (_from.isNotEmpty) 'fromDate': _from,
        if (_to.isNotEmpty) 'toDate': _to,
      });
      if (mounted) setState(() => _data = res is Map ? res : null);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) {
      setState(() {
        _loading = false;
        _refreshing = false;
      });
    }
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    await _load();
  }

  bool get _filtersActive =>
      _search.text.trim().isNotEmpty || _type != 'ALL' || _category != 'ALL' || _activity != 'ALL' || _cash != 'ALL' || _profit != 'ALL';

  String _money(Object? v) => tNum(v) == 0 ? '—' : _gh(tNum(v));

  Future<void> _exportCsv(List<Map> rows) => ReportExport.sharer(
      'financial-activity-$_from-to-$_to.csv', utf8.encode(activityCsv(rows, _offset)), 'text/csv', 'Financial Activity');

  void _go(String href, String label) => openAppHref(context, widget.session, widget.company, href, label: label);

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-financial-activity');
    final rows = rowsOf(_data?['rows']);
    final s = _data?['summary'] is Map ? _data!['summary'] as Map : null;
    final types = {for (final r in rows) if (tStr(r['type']).isNotEmpty) tStr(r['type'])}.toList()..sort();
    final cats = {for (final r in rows) if (tStr(r['category']).isNotEmpty) tStr(r['category'])}.toList()..sort();
    final filtered =
        filterActivity(rows, search: _search.text, type: _type, category: _category, activity: _activity, cash: _cash, profit: _profit);
    final sorted = sortRows(filtered, _sort, (r, k) => switch (k) {
          'date' => '${tStr(r['occurredAt'])}|${tStr(r['createdAt'])}',
          'description' => tStr(r['description']),
          'moneyIn' || 'moneyOut' || 'revenue' || 'expense' || 'profitImpact' || 'runningCash' => tNum(r[k]),
          _ => r[k],
        });
    if (sorted.length != _lastTotal) {
      _lastTotal = sorted.length;
      _page = 1;
    }
    final pageRows = pageSlice(sorted, _page, _pageSize);
    num tin = 0, tout = 0, trev = 0, texp = 0;
    for (final r in filtered) {
      tin += tNum(r['moneyIn']);
      tout += tNum(r['moneyOut']);
      trev += tNum(r['revenue']);
      texp += tNum(r['expense']);
    }
    final tprofit = trev - texp;
    final period = rangeToPeriod(_from, _to);

    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Financial Activity')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: const Color(0xFFE0E7FF), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.show_chart, size: 20, color: Color(0xFF4338CA)),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Financial Activity', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: TColors.slate900)),
                  Text('See how business activity affects cash, revenue, expenses, profit and financial position.',
                      style: TextStyle(fontSize: 13, color: TColors.slate600)),
                ]),
              ),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                onPressed: () => _go('/cash-flow', 'Cash Flow'),
                icon: const Icon(Icons.swap_horiz, size: 16),
                label: const Text('Cash Flow'),
              ),
              OutlinedButton.icon(
                onPressed: () => _go('/poultry-profit-loss', 'Profit & Loss'),
                icon: const Icon(Icons.bar_chart, size: 16),
                label: const Text('Profit & Loss'),
              ),
              OutlinedButton.icon(
                onPressed: filtered.isEmpty ? null : () => _exportCsv(filtered),
                icon: const Icon(Icons.download, size: 16),
                label: const Text('Export CSV'),
              ),
              OutlinedButton.icon(
                onPressed: _refreshing || _loading ? null : _refresh,
                icon: _refreshing
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh'),
              ),
            ]),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                border: Border.all(color: const Color(0xFFC7D2FE)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'Financial Activity combines cash movement and profit recognition so you can see why cash flow and profit may differ.',
                style: TextStyle(fontSize: 12, color: Color(0xFF312E81)),
              ),
            ),
            const SizedBox(height: 12),
            if (_error.isNotEmpty) ...[TrackerBanner.error(_error), const SizedBox(height: 12)],
            if (s != null) ...[
              twoUp([
                _stat('Money In', _gh(tNum(s['moneyIn'])), tip: faTips['moneyIn'], color: TColors.emerald700),
                _stat('Money Out', _gh(tNum(s['moneyOut'])), tip: faTips['moneyOut'], color: TColors.rose700),
                _stat('Net Cash Flow', _gh(tNum(s['netCashFlow'])),
                    color: tNum(s['netCashFlow']) < 0 ? TColors.rose700 : TColors.emerald700, hint: 'Opening ${_gh(tNum(s['openingCash']))}'),
                _stat('Closing Cash', _gh(tNum(s['closingCash'])), tip: faTips['runningCash']),
                _stat('Revenue', _gh(tNum(s['revenue'])), tip: faTips['revenue'], color: TColors.emerald700),
                _stat('Expenses', _gh(tNum(s['expense'])), tip: faTips['expense'], color: TColors.rose700),
                _stat('Net Profit', _gh(tNum(s['netProfit'])),
                    tip: faTips['profit'],
                    color: tNum(s['netProfit']) < 0 ? TColors.rose700 : TColors.emerald700,
                    hint: '${tNum(s['cashEvents']).toInt()} cash · ${tNum(s['nonCashEvents']).toInt()} non-cash events'),
              ]),
              const SizedBox(height: 8),
              const Text.rich(
                TextSpan(children: [
                  TextSpan(text: 'Net Cash Flow and Net Profit are different', style: TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(
                      text:
                          ' because some cash movements are not revenue or expenses, while some revenue or expenses may be recognised without cash moving at the same time.'),
                ]),
                style: TextStyle(fontSize: 12, color: TColors.slate600),
              ),
              const SizedBox(height: 12),
            ],
            TCard(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                AppSelect<String>(
                  value: period,
                  items: [
                    for (final (_, opts) in periodGroups)
                      for (final (k, l) in opts) AppSelectItem(value: k, label: l),
                  ],
                  onChanged: (k) {
                    final r = k == null ? null : periodToRange(k);
                    if (r != null) {
                      setState(() {
                        _from = r.from;
                        _to = r.to;
                      });
                      _load();
                    }
                  },
                ),
                const SizedBox(height: 8),
                filterRow([
                  FilterDate(value: _from, hint: 'From date', onChanged: (v) {
                    setState(() => _from = v);
                    _load();
                  }),
                  FilterDate(value: _to, hint: 'To date', onChanged: (v) {
                    setState(() => _to = v);
                    _load();
                  }),
                ]),
                const SizedBox(height: 8),
                AppInput(controller: _search, hintText: 'Search…', onChanged: (_) => setState(() {})),
                const SizedBox(height: 8),
                filterRow([
                  AppSelect<String>(
                    value: _activity,
                    hintText: 'Activity',
                    items: [for (final (v, l) in activityFilters) AppSelectItem(value: v, label: l)],
                    onChanged: (v) => setState(() => _activity = v ?? 'ALL'),
                  ),
                  AppSelect<String>(
                    value: _cash,
                    hintText: 'Cash',
                    items: [for (final (v, l) in cashFilters) AppSelectItem(value: v, label: l)],
                    onChanged: (v) => setState(() => _cash = v ?? 'ALL'),
                  ),
                ]),
                const SizedBox(height: 8),
                filterRow([
                  AppSelect<String>(
                    value: _profit,
                    hintText: 'Profit impact',
                    items: [for (final (v, l) in profitFilters) AppSelectItem(value: v, label: l)],
                    onChanged: (v) => setState(() => _profit = v ?? 'ALL'),
                  ),
                  AppSelect<String>(
                    value: _type,
                    hintText: 'Type',
                    items: [const AppSelectItem(value: 'ALL', label: 'All types'), for (final t in types) AppSelectItem(value: t, label: t)],
                    onChanged: (v) => setState(() => _type = v ?? 'ALL'),
                  ),
                ]),
                const SizedBox(height: 8),
                AppSelect<String>(
                  value: _category,
                  hintText: 'Category',
                  items: [const AppSelectItem(value: 'ALL', label: 'All categories'), for (final c in cats) AppSelectItem(value: c, label: c)],
                  onChanged: (v) => setState(() => _category = v ?? 'ALL'),
                ),
                if (_filtersActive) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton(
                      onPressed: () => setState(() {
                        _search.clear();
                        _type = 'ALL';
                        _category = 'ALL';
                        _activity = 'ALL';
                        _cash = 'ALL';
                        _profit = 'ALL';
                      }),
                      child: const Text('Reset filters'),
                    ),
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 12),
            TCard(
              padding: const EdgeInsets.all(10),
              child: _loading
                  ? const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: LoadingLine('Loading financial activity…')))
                  : filtered.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 12),
                          child: Text(rows.isEmpty ? 'No financial activity in this period.' : 'No activity matches those filters.',
                              textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
                        )
                      : MobileCardList<Map>(
                          items: pageRows,
                          striped: true,
                          keyOf: (r) => tStr(r['eventKey']),
                          primary: (r) => tStr(r['type']),
                          secondary: (r) => '${formatActivityMoment(r['occurredAt'], r['createdAt'], _offset)} · ${tStr(r['category'])}',
                          highlights: (r) {
                            final p = tNum(r['profitImpact']);
                            return [
                              Highlight('Money in', _money(r['moneyIn']), accent: Accent.emerald),
                              Highlight('Money out', _money(r['moneyOut']), accent: Accent.rose),
                              Highlight('Profit impact', p == 0 ? '—' : _gh(p),
                                  accent: p > 0 ? Accent.emerald : p < 0 ? Accent.rose : Accent.slate, wide: true),
                            ];
                          },
                          details: (r) => [
                            ('Description', tStr(r['description']).isEmpty ? '—' : tStr(r['description'])),
                            ('Revenue', _money(r['revenue'])),
                            ('Expense', _money(r['expense'])),
                            ('Running cash', _gh(tNum(r['runningCash']))),
                          ],
                          extra: _positions,
                          table: (items) => _table(items, filtered.length, (tin, tout, trev, texp, tprofit)),
                          pager: CompactPager(
                            total: sorted.length,
                            page: _page,
                            pageSize: _pageSize,
                            onPage: (p) => setState(() => _page = p),
                            onPageSize: (v) => setState(() {
                              _pageSize = v;
                              _page = 1;
                            }),
                          ),
                        ),
            ),
            const SizedBox(height: 12),
            const Text(
              "Money In and Money Out are the same figures Cash Flow reports, and exclude transfers between the company's own accounts — those move money without any entering or leaving the business, and their account legs are in the row detail. Revenue and Expense are the same figures Profit & Loss recognises. Capital purchases and stock bought under “expense when consumed” spend cash without being a cost yet; depreciation and stock consumption are a cost without spending cash.",
              style: TextStyle(fontSize: 11, color: TColors.slate500),
            ),
          ],
        ),
      ),
    );
  }

  /// Stat: the figure stays on one line and shrinks with its length.
  Widget _stat(String label, String value, {String? tip, String? hint, Color? color}) {
    final n = value.length;
    final size = n > 17 ? 13.0 : n > 14 ? 15.0 : n > 11 ? 17.0 : 22.0;
    final body = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(),
            overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: TColors.slate500)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, maxLines: 1, style: TextStyle(fontSize: size, fontWeight: FontWeight.w700, color: color ?? TColors.slate900)),
        ),
        if (hint != null) Text(hint, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: TColors.slate400)),
      ]),
    );
    return tip == null ? body : Tooltip(message: tip, triggerMode: TooltipTriggerMode.longPress, child: body);
  }

  Widget _positions(Map r) {
    final changes = rowsOf(r['positionChanges']);
    if (changes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Text('This event did not change any tracked financial position.', style: TextStyle(fontSize: 13, color: TColors.slate500)),
      );
    }
    final link = activitySourceLink(r);
    const sm = TextStyle(fontSize: 11, color: TColors.slate500);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Tooltip(
        message: faTips['positions']!,
        child: const Text('FINANCIAL POSITION CHANGES',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .4, color: TColors.slate500)),
      ),
      const SizedBox(height: 6),
      TrackerTable(
        columns: const [
          TCol('Position', width: 150),
          TCol('Increase', right: true, width: 100),
          TCol('Decrease', right: true, width: 100),
          TCol('Explanation', width: 200),
        ],
        rows: [
          for (final p in changes)
            [
              Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(positionLabel(p['positionType']), style: const TextStyle(fontWeight: FontWeight.w500)),
                Text(tStr(p['positionName']), style: sm),
              ]),
              cellText(tNum(p['increaseAmount']) != 0 ? _gh(tNum(p['increaseAmount'])) : '—', color: TColors.emerald700),
              cellText(tNum(p['decreaseAmount']) != 0 ? _gh(tNum(p['decreaseAmount'])) : '—', color: TColors.rose700),
              cellText(tStr(p['explanation']).isEmpty ? '—' : tStr(p['explanation']), color: TColors.slate600),
            ],
        ],
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 14, runSpacing: 4, children: [
        if (tStr(r['sourceNumber']).isNotEmpty) Text('Reference ${r['sourceNumber']}', style: sm),
        if (tStr(r['cashAccountName']).isNotEmpty) Text('Account: ${r['cashAccountName']}', style: sm),
        if (tStr(r['partyName']).isNotEmpty) Text('Party: ${r['partyName']}', style: sm),
        if (tStr(r['plLine']).isNotEmpty) Text('P&L line: ${r['plLine']}', style: sm),
        if (tStr(r['status']).isNotEmpty && r['status'] != 'Posted')
          Text('Status: ${r['status']}', style: const TextStyle(fontSize: 11, color: TColors.amber700)),
        Text('Recorded ${formatActivityMoment(r['occurredAt'], r['createdAt'], _offset)}', style: sm),
        if (link != null)
          InkWell(
            onTap: () => _go(link.$1, link.$2),
            child: Text('${link.$2} →', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: TColors.blue600)),
          ),
      ]),
    ]);
  }

  Widget _table(List<Map> items, int count, (num, num, num, num, num) t) {
    final (tin, tout, trev, texp, tprofit) = t;
    Color pc(num p) => p > 0 ? TColors.emerald700 : p < 0 ? TColors.rose700 : TColors.slate400;
    const cols = [
      TCol('', width: 34),
      TCol('Date', sortKey: 'date', width: 150),
      TCol('Type', sortKey: 'type', width: 150),
      TCol('Category', sortKey: 'category', width: 130),
      TCol('Description', sortKey: 'description', width: 220),
      TCol('Money In', sortKey: 'moneyIn', right: true, width: 110),
      TCol('Money Out', sortKey: 'moneyOut', right: true, width: 110),
      TCol('Revenue', sortKey: 'revenue', right: true, width: 110),
      TCol('Expense', sortKey: 'expense', right: true, width: 110),
      TCol('Profit Impact', sortKey: 'profitImpact', right: true, width: 120),
      TCol('Running Cash', sortKey: 'runningCash', right: true, width: 120),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TrackerTable(
        sort: _sort,
        onSort: (k) => setState(() {
          _sort = toggleSort(k, _sort);
          _page = 1;
        }),
        columns: cols,
        rows: [
          for (final r in items)
            () {
              final key = tStr(r['eventKey']);
              final open = _expanded.contains(key);
              final p = tNum(r['profitImpact']);
              void tog() => setState(() => _expanded.contains(key) ? _expanded.remove(key) : _expanded.add(key));
              return [
                InkWell(
                  onTap: tog,
                  child: Icon(open ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, size: 16, color: TColors.slate400),
                ),
                InkWell(onTap: tog, child: cellText(formatActivityMoment(r['occurredAt'], r['createdAt'], _offset))),
                Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
                  Text(tStr(r['type']), style: const TextStyle(fontWeight: FontWeight.w500)),
                  if (r['isInternalTransfer'] == true) const TBadge('internal', bg: Colors.white, fg: TColors.slate600, border: TColors.slate200),
                ]),
                cellText(tStr(r['category']), color: TColors.slate600),
                cellText(tStr(r['description']).isEmpty ? '—' : tStr(r['description'])),
                cellText(_money(r['moneyIn']), color: TColors.emerald700),
                cellText(_money(r['moneyOut']), color: TColors.rose700),
                cellText(_money(r['revenue']), color: TColors.emerald700),
                cellText(_money(r['expense']), color: TColors.rose700),
                cellText(p == 0 ? '—' : _gh(p), color: pc(p), bold: true),
                cellText(_gh(tNum(r['runningCash'])), color: TColors.slate700),
              ];
            }(),
        ],
        footer: [
          const SizedBox(),
          Text.rich(TextSpan(children: [
            TextSpan(text: _filtersActive ? 'Filtered total' : 'Period total', style: const TextStyle(fontWeight: FontWeight.w500)),
            TextSpan(text: ' ($count ${count == 1 ? 'event' : 'events'})', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          ])),
          const SizedBox(),
          const SizedBox(),
          const SizedBox(),
          cellText(_money(tin), color: TColors.emerald700, bold: true),
          cellText(_money(tout), color: TColors.rose700, bold: true),
          cellText(_money(trev), color: TColors.emerald700, bold: true),
          cellText(_money(texp), color: TColors.rose700, bold: true),
          cellText(tprofit == 0 ? '—' : _gh(tprofit), color: pc(tprofit), bold: true),
          const SizedBox(),
        ],
      ),
      // Each open event's position detail, under the table.
      for (final r in items)
        if (_expanded.contains(tStr(r['eventKey'])))
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(10),
            color: TColors.slate50,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('${tStr(r['type'])} · ${formatActivityMoment(r['occurredAt'], r['createdAt'], _offset)}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              _positions(r),
            ]),
          ),
    ]);
  }
}
