// Hotel → Sales, Expenses & Money → Money → Cash Flow, as `app/hotel-cash-flow/page.tsx`
// (migration 316): an independent report built on /Hotel/cash-flow, from guest
// payments, walk-in restaurant orders, deposits, approved expenses, paid payroll
// and the other cash documents, never from the account balances. Poultry's
// layout (lib/pages/poultry/money/cash_flow_screen.dart) with the Hotel's eight
// tiles, its filters and wording, no edit or delete on a row, and Add Adjustment
// recorded as the Hotel document it really is.

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
import '../poultry/reports/report_routes.dart' show openAppHref;
import '../poultry/sales/balances_logic.dart' show pageSlice;
import '../poultry/sales/balances_widgets.dart';
import '../poultry/sales/payments_received_screen.dart' show fmtDateTimeLike;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull, SortDir;
import '../poultry/trackers/tracker_widgets.dart';
import 'hotel_kit.dart';

const _empty = <String, num>{
  'moneyIn': 0, 'moneyOut': 0, 'netCashFlow': 0, 'openingCash': 0, 'closingCash': 0,
  'operatingIn': 0, 'operatingOut': 0, 'financingIn': 0, 'financingOut': 0, 'movementCount': 0,
};

class HotelCashFlowScreen extends StatefulWidget {
  const HotelCashFlowScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<HotelCashFlowScreen> createState() => _HotelCashFlowScreenState();
}

class _HotelCashFlowScreenState extends State<HotelCashFlowScreen> {
  late String _from = defaultReportRange().from;
  late String _to = defaultReportRange().to;
  final _search = TextEditingController();
  String _flow = 'ALL', _type = 'ALL', _sortKey = 'date';
  bool _asc = false;
  List<Map> _rows = [];
  Map _summary = _empty, _prev = _empty, _allTime = _empty;
  bool _loading = true, _explainOpen = false;
  String _error = '';
  int _page = 1, _pageSize = 10, _lastTotal = -1;
  FarmMoney _gh = const FarmMoney();

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;

  /// canViewCashLedger on the web; the phone has no feature flags, so Staff are refused.
  bool get _canView => (widget.company.role ?? '').toLowerCase() != 'staff';

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _gh = m);
    });
    if (_canView) _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<Map?> _cashFlow([String? from, String? to]) async {
    final res = await _api.get('/api/Hotel/cash-flow', query: {
      'farmId': _farmId,
      if ((from ?? '').isNotEmpty) 'fromDate': from,
      if ((to ?? '').isNotEmpty) 'toDate': to,
    });
    return res is Map ? res : null;
  }

  Map _summaryOf(Map? r) {
    final s = r?['summary'];
    if (s is! Map) return _empty;
    return {for (final k in _empty.keys) k: tNum(s[k])};
  }

  Future<void> _load() async {
    setState(() => _error = '');
    final prev = previousRange(_from, _to);
    Future<Map?> settle(Future<Map?> f) async {
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
    final r = await Future.wait<Map?>([
      prev.from != null && prev.to != null ? settle(_cashFlow(prev.from, prev.to)) : Future.value(null),
      settle(_cashFlow()),
    ]);
    if (!mounted) return;
    setState(() {
      _rows = curErr == null ? rowsOf(cur?['rows']) : [];
      _summary = curErr == null ? _summaryOf(cur) : _empty;
      _error = curErr ?? '';
      _prev = _summaryOf(r[0]);
      _allTime = _summaryOf(r[1]);
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

  // ------------------------------------------------------------ Add Adjustment

  Future<void> _adjust() async {
    List<AdjustableAccount> accounts = [];
    try {
      accounts = [
        for (final a in hotelRows(await _api.get('/api/Hotel/finance/cash-accounts', query: {'farmId': _farmId})))
          (
            accountId: tIntOrNull(a['hotelCashAccountId'] ?? a['hotelcashaccountid']) ?? 0,
            accountName: tStr(a['accountName'] ?? a['accountname']),
            isActive: (a['isActive'] ?? a['isactive']) != false,
          ),
      ];
    } on ApiException {
      accounts = [];
    }
    if (!mounted) return;
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => CashAdjustmentDialog(accounts: accounts, fmtMoney: _gh.call, onSubmit: _submit),
    );
    if (done == true) {
      setState(() => _loading = true);
      _load();
    }
  }

  /// Opening Balance / Correction → a cash adjustment on the account (331);
  /// Owner injection / Withdrawal → owner money; Loan received → a loan.
  Future<void> _submit(AdjustmentInput i) async {
    if (i.accountId == null) throw ApiException(400, 'Choose the cash account.');
    final q = {'farmId': _farmId};
    final notes = i.description.isEmpty ? null : i.description;
    if (i.adjustmentType == 'LoanReceived') {
      if (i.amount <= 0) throw ApiException(400, 'A loan received is a positive amount. Correct an existing loan on Loans (Financing).');
      await _api.post('/api/Hotel/loans', query: q, body: {
        'farmId': _farmId,
        'lenderName': (i.lenderName ?? '').trim(),
        'lenderType': 'Other',
        'accountNumber': null,
        'originalPrincipal': i.amount,
        'amountReceived': i.amount,
        'hotelCashAccountId': i.accountId,
        'startDate': i.adjustmentDate,
        'interestRate': null,
        'interestType': null,
        'termMonths': null,
        'paymentFrequency': null,
        'nextPaymentDate': null,
        'notes': notes,
      });
      return;
    }
    if (i.adjustmentType == 'OwnerInjection' || i.adjustmentType == 'Withdrawal') {
      await _api.post('/api/Hotel/owner-money', query: q, body: {
        'farmId': _farmId,
        'transactionType': i.adjustmentType == 'OwnerInjection' ? 'Contribution' : 'Draw',
        'amount': i.amount.abs(),
        'hotelCashAccountId': i.accountId,
        'transactionDate': i.adjustmentDate,
        'paymentMethod': null,
        'ownerName': i.ownerName,
        'referenceNumber': null,
        'notes': notes,
      });
      return;
    }
    await _api.post('/api/Hotel/finance/cash-accounts/${i.accountId}/adjust', query: q, body: {
      'farmId': _farmId,
      'amount': i.amount,
      'reason': i.adjustmentType == 'OpeningBalance' ? 'Opening balance correction' : (i.description.trim().isEmpty ? 'Other' : i.description.trim()),
    });
  }

  // ------------------------------------------------------------ derived

  List<Map> get _history {
    final filtered = [
      for (final r in _rows)
        if ((_flow == 'ALL' || r['flowGroup'] == _flow) && (_type == 'ALL' || categoryLabel(r['category']) == _type)) r,
    ];
    final running = withRunningBalance(filtered, tNum(_summary['openingCash']));
    Object? v(Map r) => switch (_sortKey) {
          'date' => '${_day(r['transactionDate'])}|${tStr(r['createdAt'])}',
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
    final q = _search.text.trim().toLowerCase();
    return [
      for (final e in indexed)
        if (q.isEmpty || [e.$2['description'], e.$2['category'], e.$2['sourceType']].any((x) => x != null && '$x'.toLowerCase().contains(q))) e.$2,
    ];
  }

  static String _day(Object? v) {
    final s = tStr(v);
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  String _signed(num n) => '${n > 0 ? '+' : ''}${_gh(n)}';

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/hotel-cash-flow');
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
    final net = tNum(s['netCashFlow']);
    final strict = tNum(s['operatingIn']) - tNum(s['operatingOut']);
    final financing = tNum(s['financingIn']) - tNum(s['financingOut']);
    Color tone(num n) => n >= 0 ? TColors.emerald700 : TColors.rose700;

    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Cash Flow')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
          children: [
            const Row(children: [
              Icon(Icons.hotel_outlined, size: 20, color: hotelViolet),
              SizedBox(width: 6),
              Text('Cash Flow', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: TColors.slate900)),
            ]),
            const Text('What the hotel earned and spent', style: TextStyle(fontSize: 12, color: TColors.slate500)),
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
              FilledButton.icon(style: hotelPrimary, onPressed: _adjust, icon: const Icon(Icons.add, size: 16), label: const Text('Add Adjustment')),
            ]),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => openAppHref(context, widget.session, widget.company, '/hotel-cash-accounts', label: 'Cash Accounts'),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('View Cash Accounts'),
            ),
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
                        child: Text('Where your money came from and went.', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate900)),
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
                            text:
                                'Built from your guest payments, walk-in restaurant orders, deposits, approved expenses, supply purchases, supplier payments, payroll, staff advances, capital investments, owner money, loans and cash adjustments. Room-service orders charged to a guest folio are counted when the guest pays, not when the order is placed. Operating money is what the hotel earned and spent; capital is money put in or taken out by owners and lenders. Transfers between your own cash accounts are not cash flow and are excluded — they are managed in '),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.baseline,
                          baseline: TextBaseline.alphabetic,
                          child: GestureDetector(
                            onTap: () => openAppHref(context, widget.session, widget.company, '/hotel-cash-accounts', label: 'Cash Accounts'),
                            child: const Text('Cash Accounts', style: TextStyle(fontSize: 12, color: TColors.slate600, decoration: TextDecoration.underline)),
                          ),
                        ),
                        const TextSpan(text: '. Customer and Supplier Balances show what is still owed either way.'),
                      ]),
                      style: const TextStyle(fontSize: 12, color: TColors.slate600),
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
                InfoTile(
                  label: 'Opening Cash',
                  value: _gh(tNum(s['openingCash'])),
                  note: 'Start of period',
                  tip: 'Everything recorded before this period started. Measured from your transactions, not read from an account balance.',
                ),
                InfoTile(
                  label: 'Money In',
                  value: _gh(tNum(s['moneyIn'])),
                  note: 'For selected period',
                  color: TColors.emerald700,
                  icon: Icons.trending_up,
                  tip: 'Guest payments, walk-in restaurant orders and deposits received during the selected period.',
                ),
                InfoTile(
                  label: 'Money Out',
                  value: _gh(tNum(s['moneyOut'])),
                  note: 'For selected period',
                  color: TColors.rose700,
                  icon: Icons.trending_down,
                  tip: 'Approved expenses, paid payroll and refunded deposits during the selected period.',
                ),
                InfoTile(
                  label: 'Cash at Hand',
                  value: _gh(tNum(_allTime['closingCash'])),
                  note: 'All time',
                  color: tNum(_allTime['closingCash']) < 0 ? TColors.rose700 : null,
                  tip: 'Every movement ever recorded, in minus out — NOT limited to the selected period. This is what your records say you should be holding; it is not read from the accounts themselves.',
                ),
                InfoTile(
                  label: 'Net Cash Flow',
                  value: _signed(net),
                  note: 'For selected period',
                  color: tone(net),
                  tip: 'Money In minus Money Out. Positive means the hotel ended the period with more cash than it started with.',
                ),
                InfoTile(
                  label: 'Net Cash Flow (Strictly business)',
                  value: _signed(strict),
                  note: 'Trading only',
                  color: tone(strict),
                  tip: "What the hotel's trading brought in less what it cost — loans and owner money left out. Negative means the hotel was kept going by borrowing or the owner.",
                ),
                InfoTile(
                  label: 'Loans & Owner Money',
                  value: _signed(financing),
                  note: 'Net for period',
                  color: tone(financing),
                  tip: 'Loans received and owner contributions, less loan repayments and owner drawings.',
                ),
                InfoTile(
                  label: 'Closing Cash',
                  value: _gh(tNum(s['closingCash'])),
                  note: 'End of period',
                  color: negative ? TColors.rose700 : null,
                  tip: "Opening cash plus money in minus money out. This is the period's closing figure, not all-time.",
                ),
              ]),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
                child: Wrap(spacing: 8, runSpacing: 2, children: [
                  Text.rich(TextSpan(children: [const TextSpan(text: 'Opening '), TextSpan(text: _gh(tNum(s['openingCash'])), style: const TextStyle(fontWeight: FontWeight.w700, color: TColors.slate900))])),
                  Text.rich(TextSpan(children: [const TextSpan(text: '+ in '), TextSpan(text: _gh(tNum(s['moneyIn'])), style: const TextStyle(fontWeight: FontWeight.w700))]),
                      style: const TextStyle(color: TColors.emerald700)),
                  Text.rich(TextSpan(children: [const TextSpan(text: '- out '), TextSpan(text: _gh(tNum(s['moneyOut'])), style: const TextStyle(fontWeight: FontWeight.w700))]),
                      style: const TextStyle(color: TColors.rose700)),
                  Text.rich(TextSpan(children: [const TextSpan(text: '= closing '), TextSpan(text: _gh(tNum(s['closingCash'])), style: const TextStyle(fontWeight: FontWeight.w700, color: TColors.slate900))])),
                ].map((w) => DefaultTextStyle.merge(style: const TextStyle(fontSize: 12, color: TColors.slate600), child: w)).toList()),
              ),
              const SizedBox(height: 12),
              TCard(
                title: 'Transaction History',
                description: 'Every cash movement in the selected period.',
                headerExtra: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(children: [
                    AppSelect<String>(
                      value: _flow,
                      items: const [
                        AppSelectItem(value: 'ALL', label: 'All categories'),
                        AppSelectItem(value: 'OperatingIn', label: 'Operating income'),
                        AppSelectItem(value: 'OperatingOut', label: 'Operating expense'),
                        AppSelectItem(value: 'EmployeeLoanOut', label: 'Staff advances out'),
                        AppSelectItem(value: 'EmployeeLoanIn', label: 'Staff advances repaid'),
                      ],
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
                        child: Text(
                          'No cash movement in this period. Record a guest payment, approve an expense or complete a payroll run and it appears here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: TColors.slate500),
                        ),
                      )
                    : MobileCardList<Map>(
                        items: pageSlice(history, _page, _pageSize),
                        striped: true,
                        keyOf: (r) => '${r['rowSource']}-${r['id']}',
                        primary: (r) => categoryLabel(r['category']),
                        secondary: (r) => '${fmtDateTimeLike(r['transactionDate'])} · ${flowGroupLabel(r['flowGroup'])}',
                        highlights: (r) {
                          final a = tNum(r['amount']);
                          return [
                            Highlight(a < 0 ? 'Money out' : 'Money in', '${a < 0 ? '-' : '+'}${_gh(a.abs())}', accent: a < 0 ? Accent.rose : Accent.emerald),
                            Highlight('Running cash', _gh(tNum(r['running'])), accent: Accent.amber),
                          ];
                        },
                        details: (r) => [
                          ('Category', flowGroupLabel(r['flowGroup'])),
                          ('Recorded as', sourceTypeLabel(r['sourceType'])),
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
          TCol('Date', sortKey: 'date', width: 120),
          TCol('Type', sortKey: 'type', width: 130),
          TCol('Category', sortKey: 'category', width: 150),
          TCol('Description', sortKey: 'description', width: 220),
          TCol('Money In', sortKey: 'in', right: true, width: 110),
          TCol('Money Out', sortKey: 'out', right: true, width: 110),
          TCol('Running cash', sortKey: 'running', right: true, width: 120),
        ],
        rows: [
          for (final r in rows)
            [
              cellText(fmtDateTimeLike(r['transactionDate'])),
              cellText(categoryLabel(r['category'])),
              Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(flowGroupLabel(r['flowGroup']), style: const TextStyle(color: TColors.slate600)),
                Text(sourceTypeLabel(r['sourceType']), style: const TextStyle(fontSize: 11, color: TColors.slate400)),
              ]),
              cellText(tStr(r['description']).isEmpty ? '—' : tStr(r['description'])),
              cellText(tNum(r['amount']) > 0 ? _gh(tNum(r['amount'])) : '—', color: TColors.emerald700),
              cellText(tNum(r['amount']) < 0 ? _gh(tNum(r['amount']).abs()) : '—', color: TColors.rose600),
              cellText(_gh(tNum(r['running'])), bold: true),
            ],
        ],
      );

  /// CashFlowInsightsDialog with the Hotel's warning and note.
  void _insights(bool negative) {
    final prev = previousRange(_from, _to);
    final ins = cashFlowBuckets(_rows, true), outs = cashFlowBuckets(_rows, false);
    final analysis = buildCashFlowAnalysis({
      ..._summary,
      'cashAtHand': _allTime['closingCash'],
      'offLedgerIn': 0,
      'offLedgerOut': 0,
      'transferVolume': 0,
      'daysInPeriod': prev.days,
      'previousMoneyIn': _prev['moneyIn'],
      'previousMoneyOut': _prev['moneyOut'],
      'previousNetCashFlow': _prev['netCashFlow'],
      'moneyInByCategory': [for (final b in ins) {'label': b.label, 'amount': b.amount, 'sharePercent': b.percent}],
      'moneyOutByCategory': [for (final b in outs) {'label': b.label, 'amount': b.amount, 'sharePercent': b.percent}],
    }, _gh.call);
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
                  FittedBox(fit: BoxFit.scaleDown, child: Text(v, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c))),
                ]),
              );
          final net = tNum(_summary['netCashFlow']);
          return ListView(controller: controller, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
            const Row(children: [
              Icon(Icons.lightbulb_outline, color: hotelViolet),
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
              TrackerBanner.error('', spans: const [
                TextSpan(text: 'Closing cash is negative.', style: TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(
                    text:
                        ' The recorded transactions add up to less than nothing, which usually means an opening balance was never entered, or spending was recorded before the income that funded it.'),
              ]),
            ],
            label('About these figures'),
            TrackerBanner.info(
              'These figures come from your guest payments, restaurant orders, approved expenses and paid payroll — not from your cash account balances. Closing cash is not expected to match what your accounts hold; comparing the two is what reconciliation is for.',
              spans: const [
                TextSpan(
                    text:
                        'These figures come from your guest payments, restaurant orders, approved expenses and paid payroll — not from your cash account balances. Closing cash is '),
                TextSpan(text: 'not', style: TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: ' expected to match what your accounts hold; comparing the two is what reconciliation is for.'),
              ],
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
