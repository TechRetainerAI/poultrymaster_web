// Restaurant → Money → Cash Flow, as `app/restaurant-cash-flow/page.tsx`: the
// one cash ledger (migration 323) with transfers, till floats/drops and
// opening balances left out, so Cash at Hand equals the Cash Accounts total.
// Add Adjustment records owner money or a loan, the real Restaurant documents.

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/money/cash_adjustment_dialog.dart';
import '../poultry/money/cash_flow_screen.dart' show cashFlowBuckets, withRunningBalance, previousRange, sourceTypeLabel;
import '../poultry/money/money_widgets.dart';
import '../poultry/reports/report_format.dart';
import '../poultry/reports/report_routes.dart';
import '../poultry/sales/balances_logic.dart' show pageSlice;
import '../poultry/sales/balances_widgets.dart';
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull, SortDir;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/business_dates.dart';
import '../shared/company_clock.dart';
import 'restaurant_roles.dart' show restaurantRose;

const _emptySummary = <String, num>{
  'moneyIn': 0, 'moneyOut': 0, 'netCashFlow': 0, 'openingCash': 0, 'closingCash': 0,
  'operatingIn': 0, 'operatingOut': 0, 'financingIn': 0, 'financingOut': 0, 'movementCount': 0, 'transferVolume': 0,
};

/// The flow-group filter of the Transaction History card.
const restaurantFlowFilters = [
  ('ALL', 'All categories'),
  ('OperatingIn', 'Operating income'),
  ('OperatingOut', 'Operating expense'),
  ('FinancingIn', 'Loans & owner money in'),
  ('FinancingOut', 'Loans & owner money out'),
  ('EmployeeLoanOut', 'Staff advances paid out'),
  ('EmployeeLoanIn', 'Staff advances repaid'),
];

/// Money in and out of each account over the period, best net first.
List<({String name, num moneyIn, num moneyOut})> cashByAccount(List<Map> rows) {
  final map = <String, (num, num)>{};
  for (final r in rows) {
    final name = tStr(r['accountName']).isEmpty ? 'Unassigned' : tStr(r['accountName']);
    final e = map[name] ?? (0, 0);
    final a = tNum(r['amount']);
    map[name] = a > 0 ? (e.$1 + a, e.$2) : (e.$1, e.$2 - a);
  }
  final out = [for (final e in map.entries) (name: e.key, moneyIn: e.value.$1, moneyOut: e.value.$2)];
  out.sort((a, b) => (b.moneyIn - b.moneyOut).compareTo(a.moneyIn - a.moneyOut));
  return out;
}

class RestaurantCashFlowScreen extends StatefulWidget {
  const RestaurantCashFlowScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<RestaurantCashFlowScreen> createState() => _RestaurantCashFlowScreenState();
}

class _RestaurantCashFlowScreenState extends State<RestaurantCashFlowScreen> {
  late String _from = defaultReportRange().from;
  late String _to = defaultReportRange().to;
  final _search = TextEditingController();
  String _flow = 'ALL';
  String _type = 'ALL';
  String _sortKey = 'date';
  bool _asc = false;

  List<Map> _rows = [];
  Map _summary = _emptySummary;
  Map _prev = _emptySummary;
  Map _allTime = _emptySummary;
  bool _loading = true;
  String _error = '';
  bool _explainOpen = false;
  int _page = 1;
  int _pageSize = 10;
  int _lastTotal = -1;
  FarmMoney _gh = const FarmMoney();
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  String get _fin => '/api/Restaurant/finance';
  String get _q => '?farmId=${Uri.encodeQueryComponent(_farmId)}';

  /// canViewCashLedger on the web; the phone has no feature flags, so Staff
  /// are the ones refused.
  bool get _canView => (widget.company.role ?? '').toLowerCase() != 'staff';

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _gh = m);
    });
    CompanyClock.load(widget.session, widget.company).then((c) {
      if (mounted) setState(() => _offset = c.offset);
    });
    if (_canView) _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<Map?> _cashFlow([String? from, String? to]) async {
    final res = await _api.get('/api/Restaurant/cash-flow', query: {
      'farmId': _farmId,
      if ((from ?? '').isNotEmpty) 'fromDate': from,
      if ((to ?? '').isNotEmpty) 'toDate': to,
    });
    return res is Map ? res : null;
  }

  Map _summaryOf(Map? r) {
    final s = r?['summary'];
    if (s is! Map) return _emptySummary;
    return {for (final k in _emptySummary.keys) k: tNum(s[k])};
  }

  Future<void> _load() async {
    setState(() => _error = '');
    final prev = previousRange(_from, _to);
    Future<Object?> settle(Future<dynamic> f) async {
      try {
        return await f;
      } on ApiException {
        return null;
      }
    }

    String? curErr;
    Map? cur;
    try {
      cur = await _cashFlow(_from, _to);
    } on ApiException catch (e) {
      curErr = e.message;
    }
    final r = await Future.wait<Object?>([
      prev.from != null && prev.to != null ? settle(_cashFlow(prev.from, prev.to)) : Future.value(null),
      settle(_cashFlow()),
    ]);
    if (!mounted) return;
    setState(() {
      if (curErr == null) {
        _rows = rowsOf(cur?['rows']);
        _summary = _summaryOf(cur);
      } else {
        _error = curErr;
        _rows = [];
        _summary = _emptySummary;
      }
      _prev = _summaryOf(r[0] as Map?);
      _allTime = _summaryOf(r[1] as Map?);
      _loading = false;
    });
  }

  void _setDates(String f, String t) {
    setState(() {
      _from = f;
      _to = t;
      _loading = true;
    });
    _load();
  }

  void _go(String href, String label) => openAppHref(context, widget.session, widget.company, href, label: label);

  // ------------------------------------------------------------ Add Adjustment

  Future<void> _adjust() async {
    List<AdjustableAccount> accounts = [];
    try {
      accounts = [
        for (final a in rowsOf(await _api.get('$_fin/accounts', query: {'farmId': _farmId})))
          (accountId: tIntOrNull(a['cashAccountId']) ?? 0, accountName: tStr(a['name']), isActive: a['isActive'] == true),
      ];
    } on ApiException {
      accounts = [];
    }
    if (!mounted) return;
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => CashAdjustmentDialog(
        accounts: accounts,
        fmtMoney: _gh.call,
        allowedTypes: const ['OwnerInjection', 'LoanReceived', 'Withdrawal'],
        onSubmit: _submit,
      ),
    );
    if (done == true) {
      setState(() => _loading = true);
      _load();
    }
  }

  /// Each type is the real Restaurant document it is: a loan, or owner money.
  Future<void> _submit(AdjustmentInput i) async {
    if (i.accountId == null) throw ApiException(0, 'Choose the cash account.');
    final notes = i.description.isEmpty ? null : i.description;
    if (i.adjustmentType == 'LoanReceived') {
      if (i.amount <= 0) throw ApiException(0, 'A loan received is a positive amount. Correct an existing loan on Loans (Financing).');
      await _api.post('$_fin/loans$_q', body: {
        'lenderName': (i.lenderName ?? '').trim(),
        'principal': i.amount,
        'amountReceived': i.amount,
        'receivedAccountId': i.accountId,
        'loanDate': i.adjustmentDate,
        'notes': notes,
      });
      return;
    }
    if (i.adjustmentType == 'OwnerInjection' || i.adjustmentType == 'Withdrawal') {
      await _api.post('$_fin/owner-money$_q', body: {
        'entryType': i.adjustmentType == 'OwnerInjection' ? 'Contribution' : 'Draw',
        'cashAccountId': i.accountId,
        'amount': i.amount.abs(),
        'entryDate': i.adjustmentDate,
        'ownerName': i.ownerName,
        'notes': notes,
      });
      return;
    }
    throw ApiException(0, 'This kind of adjustment is not recorded here. Use Cash Accounts.');
  }

  // ------------------------------------------------------------ derived

  List<Map> get _history {
    final filtered = [
      for (final r in _rows)
        if ((_flow == 'ALL' || r['flowGroup'] == _flow) && (_type == 'ALL' || categoryLabel(r['category']) == _type)) r,
    ];
    final running = withRunningBalance(filtered, tNum(_summary['openingCash']));
    Object? v(Map r) => switch (_sortKey) {
          'date' => '${tStr(r['transactionDate'])}|${tStr(r['createdAt'])}',
          'type' => categoryLabel(r['category']),
          'category' => flowGroupLabel(r['flowGroup']),
          'description' => tStr(r['description']),
          'in' => tNum(r['amount']) > 0 ? tNum(r['amount']) : 0,
          'out' => tNum(r['amount']) < 0 ? -tNum(r['amount']) : 0,
          'running' => tNum(r['running']),
          _ => r[_sortKey],
        };
    final indexed = [for (var i = 0; i < running.length; i++) (i, running[i])]
      ..sort((a, b) {
        final x = v(a.$2), y = v(b.$2);
        final c = x is num && y is num ? x.compareTo(y) : '$x'.compareTo('$y');
        return c != 0 ? (_asc ? c : -c) : a.$1 - b.$1;
      });
    final list = [for (final e in indexed) e.$2];
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return list;
    return [
      for (final r in list)
        if ([r['description'], r['category'], r['sourceType']].any((x) => x != null && '$x'.toLowerCase().contains(q))) r,
    ];
  }

  List<AnalysisItem> get _analysis {
    final prev = previousRange(_from, _to);
    final ins = cashFlowBuckets(_rows, true), outs = cashFlowBuckets(_rows, false);
    return buildCashFlowAnalysis({
      ..._summary,
      'cashAtHand': _allTime['closingCash'],
      'offLedgerIn': 0,
      'offLedgerOut': 0,
      'daysInPeriod': prev.days,
      'previousMoneyIn': _prev['moneyIn'],
      'previousMoneyOut': _prev['moneyOut'],
      'previousNetCashFlow': _prev['netCashFlow'],
      'moneyInByCategory': [for (final b in ins) {'label': b.label, 'amount': b.amount, 'sharePercent': b.percent}],
      'moneyOutByCategory': [for (final b in outs) {'label': b.label, 'amount': b.amount, 'sharePercent': b.percent}],
    }, _gh.call);
  }

  String _signed(num n) => '${n > 0 ? '+' : ''}${_gh(n)}';

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/restaurant-cash-flow');
    if (!_canView) {
      return Scaffold(
        appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Cash Flow')),
        body: const Padding(
          padding: EdgeInsets.all(16),
          child: TCard(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: Text('You do not have access to Cash Flow.', style: TextStyle(color: TColors.slate600))),
            ),
          ),
        ),
      );
    }
    final s = _summary;
    final negative = tNum(s['closingCash']) < 0;
    final types = {for (final r in _rows) categoryLabel(r['category'])}.toList()..sort();
    final history = _history;
    if (history.length != _lastTotal) {
      _lastTotal = history.length;
      _page = 1;
    }
    final pageRows = pageSlice(history, _page, _pageSize);
    final strict = tNum(s['operatingIn']) - tNum(s['operatingOut']);
    final financing = tNum(s['financingIn']) - tNum(s['financingOut']);
    final cashAtHand = tNum(_allTime['closingCash']);
    final byAccount = cashByAccount(_rows);
    const small = TextStyle(fontSize: 12, color: TColors.slate600);

    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Cash Flow')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
          children: [
            const Row(children: [
              Icon(Icons.restaurant, size: 20, color: Color(0xFFE11D48)),
              SizedBox(width: 6),
              Text('Cash Flow', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: TColors.slate900)),
            ]),
            const Text('What the restaurant received and spent', style: TextStyle(fontSize: 12, color: TColors.slate500)),
            const SizedBox(height: 8),
            twoUp([
              OutlinedButton.icon(
                onPressed: _loading ? null : () => _insights(negative),
                icon: const Icon(Icons.lightbulb_outline, size: 16),
                label: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Flexible(child: Text('Cash Flow Insights', overflow: TextOverflow.ellipsis)),
                  if (negative) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(color: const Color(0xFFF59E0B), borderRadius: BorderRadius.circular(999)),
                      child: const Text('1', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ]),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: restaurantRose),
                onPressed: _adjust,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Adjustment'),
              ),
            ]),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _go('/restaurant-cash-accounts', 'Cash Accounts'),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('View Cash Accounts'),
            ),
            const SizedBox(height: 6),
            Wrap(spacing: 16, runSpacing: 4, children: [
              _link(Icons.calculate_outlined, 'Tills & Shifts', '/restaurant-tills'),
              _link(Icons.insert_chart_outlined, 'Cash Flow report', '/restaurant-reports/cash-flow-detail'),
            ]),
            const SizedBox(height: 12),
            // Closed by default on a phone, as the web's Collapsible.
            Container(
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                InkWell(
                  onTap: () => setState(() => _explainOpen = !_explainOpen),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      const Expanded(
                        child: Text('Where your money came from and went.',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate900)),
                      ),
                      Icon(_explainOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 18, color: TColors.slate400),
                    ]),
                  ),
                ),
                if (_explainOpen)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Text.rich(
                      TextSpan(children: [
                        const TextSpan(
                            text: 'Built from your orders, expenses, purchases and capital records, through the cash ledger every till, cash box, bank and wallet posts to. '
                                'Operating money is what the restaurant earned and spent; capital is money put in or taken out by owners and lenders. '
                                'Transfers between your own cash accounts (and till floats and drops) are not cash flow and are excluded — they are managed in '),
                        _spanLink('Cash Accounts', '/restaurant-cash-accounts'),
                        const TextSpan(text: '. Customer and Supplier Balances show what is still owed either way.'),
                      ]),
                      style: small,
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
            ListFiltersCard(
              search: _search,
              searchPlaceholder: 'Search description, category…',
              onSearch: () => setState(() {}),
              from: _from,
              to: _to,
              onDates: _setDates,
              onClear: () {
                _search.clear();
                _setDates('', '');
              },
            ),
            const SizedBox(height: 12),
            if (_error.isNotEmpty) ...[TrackerBanner.error(_error), const SizedBox(height: 12)],
            if (_loading)
              const TrackerLoading('Loading cash flow…')
            else ...[
              twoUp([
                InfoTile(label: 'Opening Cash', value: _gh(tNum(s['openingCash'])), note: 'Start of period', tip: 'Everything before this period started.'),
                InfoTile(
                  label: 'Money In',
                  value: _gh(tNum(s['moneyIn'])),
                  note: 'For selected period',
                  color: TColors.emerald700,
                  icon: Icons.trending_up,
                  tip: 'Order payments (tips included), gift-card sales, loans received and owner contributions.',
                ),
                InfoTile(
                  label: 'Money Out',
                  value: _gh(tNum(s['moneyOut'])),
                  note: 'For selected period',
                  color: TColors.rose700,
                  icon: Icons.trending_down,
                  tip: 'Expenses, refunds, loan repayments and owner drawings.',
                ),
                InfoTile(
                  label: 'Cash at Hand',
                  value: _gh(cashAtHand),
                  note: 'All accounts, today',
                  color: cashAtHand < 0 ? TColors.rose700 : null,
                  tip: 'Every till, cash box, bank and wallet added together — the same total as Cash Accounts.',
                ),
              ]),
              const SizedBox(height: 8),
              twoUp([
                InfoTile(
                  label: 'Net Cash Flow',
                  value: _signed(tNum(s['netCashFlow'])),
                  note: 'For selected period',
                  color: tNum(s['netCashFlow']) >= 0 ? TColors.emerald700 : TColors.rose700,
                  tip: 'Money In minus Money Out.',
                ),
                InfoTile(
                  label: 'Net Cash Flow (Strictly business)',
                  value: _signed(strict),
                  note: 'Trading only',
                  color: strict >= 0 ? TColors.emerald700 : TColors.rose700,
                  tip: 'What trading brought in less what it cost — loans and owner money left out. Negative means the restaurant was kept going by borrowing or the owner.',
                ),
                InfoTile(
                  label: 'Loans & Owner Money',
                  value: _signed(financing),
                  note: 'Net for period',
                  color: financing >= 0 ? TColors.emerald700 : TColors.rose700,
                  tip: 'Loans received and owner contributions, less loan repayments and owner drawings.',
                ),
                InfoTile(
                  label: 'Closing Cash',
                  value: _gh(tNum(s['closingCash'])),
                  note: 'End of period',
                  color: negative ? TColors.rose700 : null,
                  tip: 'Opening + In - Out for this period.',
                ),
              ]),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
                child: DefaultTextStyle.merge(
                  style: small,
                  child: Wrap(spacing: 8, runSpacing: 2, children: [
                    Text.rich(TextSpan(children: [const TextSpan(text: 'Opening '), _bold(_gh(tNum(s['openingCash'])), TColors.slate900)])),
                    Text.rich(TextSpan(children: [const TextSpan(text: '+ in '), _bold(_gh(tNum(s['moneyIn'])))]), style: const TextStyle(color: TColors.emerald700)),
                    Text.rich(TextSpan(children: [const TextSpan(text: '- out '), _bold(_gh(tNum(s['moneyOut'])))]), style: const TextStyle(color: TColors.rose700)),
                    Text.rich(TextSpan(children: [const TextSpan(text: '= closing '), _bold(_gh(tNum(s['closingCash'])), TColors.slate900)])),
                    Text('· ${tNum(s['movementCount']).toInt()} movements', style: const TextStyle(color: TColors.slate400)),
                    if (tNum(s['transferVolume']) > 0)
                      Text('· ${_gh(tNum(s['transferVolume']))} moved between your own accounts (not counted)', style: const TextStyle(color: TColors.slate400)),
                  ]),
                ),
              ),
              if (byAccount.isNotEmpty) ...[
                const SizedBox(height: 12),
                TCard(
                  title: 'Cash by account',
                  descriptionSpans: [
                    const TextSpan(text: "Where this period's money came in and went out. Balances are on "),
                    _spanLink('Cash Accounts', '/restaurant-cash-accounts'),
                    const TextSpan(text: '.'),
                  ],
                  padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
                  child: TrackerTable(
                    columns: const [
                      TCol('Account', width: 140),
                      TCol('Money in', right: true, width: 110),
                      TCol('Money out', right: true, width: 110),
                      TCol('Net', right: true, width: 110),
                    ],
                    rows: [
                      for (final a in byAccount)
                        [
                          cellText(a.name, bold: true),
                          cellText(_gh(a.moneyIn), color: TColors.emerald700),
                          cellText(_gh(a.moneyOut), color: TColors.rose600),
                          cellText(_gh(a.moneyIn - a.moneyOut), color: a.moneyIn - a.moneyOut < 0 ? TColors.rose700 : TColors.emerald700, bold: true),
                        ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TCard(
                title: 'Transaction History',
                description: 'Every cash movement in the selected period.',
                headerExtra: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(children: [
                    AppSelect<String>(
                      value: _flow,
                      items: [for (final (v, l) in restaurantFlowFilters) AppSelectItem(value: v, label: l)],
                      onChanged: (v) => setState(() => _flow = v ?? 'ALL'),
                    ),
                    const SizedBox(height: 8),
                    AppSelect<String>(
                      value: _type,
                      hintText: 'All types',
                      items: [const AppSelectItem(value: 'ALL', label: 'All types'), for (final t in types) AppSelectItem(value: t, label: t)],
                      onChanged: (v) => setState(() => _type = v ?? 'ALL'),
                    ),
                  ]),
                ),
                padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
                child: history.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: Text('No cash movement in this period.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: TColors.slate500)),
                      )
                    : MobileCardList<Map>(
                        items: pageRows,
                        striped: true,
                        keyOf: (r) => '${r['rowSource']}-${r['id']}',
                        primary: (r) => categoryLabel(r['category']),
                        secondary: (r) => '${fmtDateTime(r['transactionDate'], r, _offset)} · ${flowGroupLabel(r['flowGroup'])}',
                        highlights: (r) {
                          final a = tNum(r['amount']);
                          return [
                            Highlight(a < 0 ? 'Money out' : 'Money in', '${a < 0 ? '-' : '+'}${_gh(a.abs())}', accent: a < 0 ? Accent.rose : Accent.emerald),
                            Highlight('Running cash', _gh(tNum(r['running'])), accent: Accent.rose),
                          ];
                        },
                        details: (r) => [
                          ('Category', flowGroupLabel(r['flowGroup'])),
                          ('Recorded as', sourceTypeLabel(r['sourceType'])),
                          ('Account', tStr(r['accountName']).isEmpty ? '—' : tStr(r['accountName'])),
                          ('Description', tStr(r['description']).isEmpty ? '—' : tStr(r['description'])),
                        ],
                        table: _table,
                        pager: CompactPager(
                          total: history.length,
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
            ],
          ],
        ),
      ),
    );
  }

  TextSpan _bold(String t, [Color? c]) => TextSpan(text: t, style: TextStyle(fontWeight: FontWeight.w700, color: c));

  InlineSpan _spanLink(String text, String href) => WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: GestureDetector(
          onTap: () => _go(href, text),
          child: Text(text, style: const TextStyle(fontSize: 12, color: TColors.slate600, decoration: TextDecoration.underline)),
        ),
      );

  Widget _link(IconData icon, String label, String href) => InkWell(
        onTap: () => _go(href, label),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: TColors.slate600),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate600)),
        ]),
      );

  Widget _table(List<Map> rows) => TrackerTable(
        sort: (key: _sortKey, dir: _asc ? SortDir.asc : SortDir.desc),
        onSort: (k) => setState(() {
          if (k == _sortKey) {
            _asc = !_asc;
          } else {
            _sortKey = k;
            _asc = true;
          }
        }),
        columns: const [
          TCol('Date', sortKey: 'date', width: 130),
          TCol('Type', sortKey: 'type', width: 130),
          TCol('Category', sortKey: 'category', width: 170),
          TCol('Description', sortKey: 'description', width: 220),
          TCol('Money In', sortKey: 'in', right: true, width: 110),
          TCol('Money Out', sortKey: 'out', right: true, width: 110),
          TCol('Running cash', sortKey: 'running', right: true, width: 120),
        ],
        rows: [
          for (final r in rows)
            () {
              final a = tNum(r['amount']);
              final acct = tStr(r['accountName']);
              return [
                cellText(fmtDateTime(r['transactionDate'], r, _offset)),
                cellText(categoryLabel(r['category'])),
                Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(flowGroupLabel(r['flowGroup']), style: const TextStyle(color: TColors.slate600)),
                  Text('${sourceTypeLabel(r['sourceType'])}${acct.isNotEmpty ? ' · $acct' : ''}',
                      style: const TextStyle(fontSize: 11, color: TColors.slate400)),
                ]),
                cellText(tStr(r['description']).isEmpty ? '—' : tStr(r['description'])),
                cellText(a > 0 ? _gh(a) : '—', color: TColors.emerald700),
                cellText(a < 0 ? _gh(a.abs()) : '—', color: TColors.rose600),
                cellText(_gh(tNum(r['running'])), bold: true),
              ];
            }(),
        ],
      );

  /// CashFlowInsightsDialog with the Restaurant's warning and note.
  void _insights(bool negative) {
    final analysis = _analysis;
    final ins = cashFlowBuckets(_rows, true), outs = cashFlowBuckets(_rows, false);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .85,
        maxChildSize: .95,
        builder: (ctx, controller) {
          Widget label(String t) => Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 6),
                child: Text(t.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: TColors.slate500)),
              );
          Widget figure(String l, String v, Color c) => Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l, style: const TextStyle(fontSize: 11, color: TColors.slate500)),
                  Text(v, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c)),
                ]),
              );
          final net = tNum(_summary['netCashFlow']);
          return ListView(controller: controller, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
            const Row(children: [
              Icon(Icons.lightbulb_outline, color: Color(0xFF0284C7)),
              SizedBox(width: 8),
              Flexible(child: Text('Cash Flow Insights', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
            ]),
            Text('$_from to $_to — in plain language.', style: const TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: figure('Money in', _gh(tNum(_summary['moneyIn'])), TColors.emerald700)),
              const SizedBox(width: 8),
              Expanded(child: figure('Money out', _gh(tNum(_summary['moneyOut'])), TColors.rose700)),
              const SizedBox(width: 8),
              Expanded(child: figure('Net', _signed(net), net >= 0 ? TColors.emerald700 : TColors.rose700)),
            ]),
            if (negative) ...[
              label('Worth checking first'),
              const TrackerBanner.error('', spans: [
                TextSpan(text: 'Closing cash is negative.', style: TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: ' Spending exceeds recorded income for this period.'),
              ]),
            ],
            label('About these figures'),
            const TrackerBanner.info(
              'Built from the cash ledger: order payments (tips included), refunds, expenses, gift-card sales, owner money, loans and till over/short. Transfers between your own accounts are left out.',
            ),
            label('What happened'),
            for (final a in analysis)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: a.tone == 'good' ? TColors.emerald50 : a.tone == 'watch' ? TColors.amber50 : TColors.slate50,
                  border: Border.all(color: a.tone == 'good' ? TColors.emerald200 : a.tone == 'watch' ? TColors.amber200 : TColors.slate200),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(
                    a.tone == 'good' ? Icons.trending_up : a.tone == 'watch' ? Icons.warning_amber_rounded : Icons.info_outline,
                    size: 16,
                    color: a.tone == 'good' ? TColors.emerald700 : a.tone == 'watch' ? TColors.amber700 : TColors.slate600,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(a.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate900)),
                      const SizedBox(height: 2),
                      Text(a.detail, style: const TextStyle(fontSize: 12, color: TColors.slate600)),
                    ]),
                  ),
                ]),
              ),
            label('Where the money moved'),
            FlowBreakdownCard(
              title: 'Money In by Source',
              inDirection: true,
              buckets: ins,
              total: tNum(_summary['moneyIn']),
              fmt: _gh.call,
              description: 'Everything that came in this period. Transfers between your own accounts are not counted.',
              emptyText: 'No money came in during this period.',
            ),
            const SizedBox(height: 10),
            FlowBreakdownCard(
              title: 'Money Out by Use',
              inDirection: false,
              buckets: outs,
              total: tNum(_summary['moneyOut']),
              fmt: _gh.call,
              description: 'Everything that went out this period. Transfers between your own accounts are not counted.',
              emptyText: 'No money went out during this period.',
            ),
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))),
          ]);
        },
      ),
    );
  }
}
