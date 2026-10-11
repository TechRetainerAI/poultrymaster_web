import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../shared/business_dates.dart';
import '../reports/report_format.dart';
import '../reports/report_routes.dart';
import '../sales/balances_logic.dart' show pageSlice;
import '../sales/balances_widgets.dart';
import '../sales/payments_received_screen.dart' show fmtDateTimeLike;
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull, FlowBucket, assignPercentages, SortDir;
import '../trackers/tracker_widgets.dart';
import 'cash_adjustment_dialog.dart';
import 'money_widgets.dart';

// ------------------------------------------------------------------ logic

/// SOURCE_TYPE_LABELS: what kind of record a cash-flow row came from.
const _sourceTypeLabels = {
  'Sale': 'Sale',
  'CustomerPayment': 'Sale',
  'Expense': 'Expense',
  'ExpensePayment': 'Expense',
  'Adjustment': 'Adjustment',
  'OpeningBalance': 'Opening Balance',
  'OwnerInjection': 'Owner injection',
  'LoanReceived': 'Loan received',
  'Withdrawal': 'Withdrawal',
  'Correction': 'Correction',
  'OwnerContribution': 'Owner contribution',
  'OwnerDraw': 'Owner draw',
  'LoanRepayment': 'Loan repayment',
  'GuestPayment': 'Guest payment',
  'RestaurantOrder': 'Restaurant order',
  'DepositCollected': 'Deposit collected',
  'DepositRefunded': 'Deposit refunded',
};

String sourceTypeLabel(Object? raw) {
  final s = tStr(raw).trim();
  if (s.isEmpty) return '—';
  return _sourceTypeLabels[s] ??
      s.replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}').replaceFirstMapped(RegExp('^.'), (m) => m[0]!.toUpperCase());
}

num _round2(num n) => (n * 100).round() / 100;

/// cashFlowBuckets: money in (or out) grouped by category label, biggest first.
List<FlowBucket> cashFlowBuckets(List<Map> rows, bool inDirection) {
  final acc = <String, (num, int)>{};
  num total = 0;
  for (final r in rows) {
    final a = tNum(r['amount']);
    if (a == 0 || (a > 0) != inDirection) continue;
    final m = a.abs();
    final label = categoryLabel(r['category']);
    final b = acc[label];
    acc[label] = b == null ? (m, 1) : (b.$1 + m, b.$2 + 1);
    total += m;
  }
  final out = [for (final e in acc.entries) FlowBucket(e.key, e.key, _round2(e.value.$1), e.value.$2)]
    ..sort((a, b) {
      final c = b.amount.compareTo(a.amount);
      return c != 0 ? c : a.label.compareTo(b.label);
    });
  return assignPercentages(out, total);
}

/// withRunningBalance: oldest first (date, entry time, id), from opening cash.
List<Map> withRunningBalance(List<Map> rows, num opening) {
  final asc = [...rows]..sort((a, b) {
      final d = tStr(a['transactionDate']).compareTo(tStr(b['transactionDate']));
      if (d != 0) return d;
      final c = tStr(a['createdAt']).compareTo(tStr(b['createdAt']));
      if (c != 0) return c;
      return (tIntOrNull(a['id']) ?? 0) - (tIntOrNull(b['id']) ?? 0);
    });
  var running = opening;
  return [
    for (final r in asc) {...r, 'running': running = _round2(running + tNum(r['amount']))},
  ];
}

/// The window immediately before [from]..[to], same length; null when unbounded.
({String? from, String? to, int days}) previousRange(String from, String to) {
  final f = businessDateAsDateTime(from), t = businessDateAsDateTime(to);
  if (f == null || t == null) return (from: null, to: null, days: 0);
  final days = (DateTime.utc(t.year, t.month, t.day).difference(DateTime.utc(f.year, f.month, f.day)).inDays + 1).clamp(1, 1 << 30);
  final prevTo = DateTime(f.year, f.month, f.day - 1);
  final prevFrom = DateTime(prevTo.year, prevTo.month, prevTo.day - (days - 1));
  return (from: isoDay(prevFrom), to: isoDay(prevTo), days: days);
}

const _emptySummary = <String, num>{
  'moneyIn': 0, 'moneyOut': 0, 'netCashFlow': 0, 'openingCash': 0, 'closingCash': 0,
  'operatingIn': 0, 'operatingOut': 0, 'financingIn': 0, 'financingOut': 0, 'movementCount': 0,
};

const _sourceOwnedHint = 'Sales and expenses are managed from their own pages.';

// ------------------------------------------------------------------ screen

/// Poultry → Money → Cash Flow, as `app/cash-flow/page.tsx`: an independent
/// report built from GET /Poultry/cash-flow (receipts, expenses, capital) —
/// never from account balances. Phone layout.
class CashFlowScreen extends StatefulWidget {
  const CashFlowScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<CashFlowScreen> createState() => _CashFlowScreenState();
}

class _CashFlowScreenState extends State<CashFlowScreen> {
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
  Map? _customers, _suppliers;
  List<Map> _accounts = [];
  bool _loading = true;
  String _error = '';
  bool _explainOpen = false;
  int _page = 1;
  int _pageSize = 10;
  int _lastTotal = -1;
  FarmMoney _gh = const FarmMoney();

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;

  /// canViewCashLedger on the web; the phone has no feature flags, so Staff
  /// are the ones refused.
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
    final res = await _api.get('/api/Poultry/cash-flow', query: {
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
      settle(_api.get('/api/Poultry/customer-balances/summary', query: {'farmId': _farmId})),
      settle(_api.get('/api/Poultry/supplier-balances/summary', query: {'farmId': _farmId})),
      settle(_api.get('/api/Poultry/cash-accounts', query: {'farmId': _farmId})),
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
      _customers = r[2] is Map ? r[2] as Map : null;
      _suppliers = r[3] is Map ? r[3] as Map : null;
      _accounts = rowsOf(r[4]);
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

  // ------------------------------------------------------------ actions

  List<AdjustableAccount> get _adjustable => [
        for (final a in _accounts)
          (accountId: tIntOrNull(a['poultryCashAccountId']) ?? 0, accountName: tStr(a['accountName']), isActive: a['isActive'] == true),
      ];

  Future<void> _adjust([CashAdjustmentSeed? editing]) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => CashAdjustmentDialog(
        accounts: _adjustable,
        fmtMoney: _gh.call,
        editing: editing,
        onSubmit: (i) => _submitAdjustment(i, editing),
      ),
    );
    if (done == true) _load();
  }

  Future<void> _submitAdjustment(AdjustmentInput i, CashAdjustmentSeed? editing) async {
    final userId = widget.session.tokens.userId;
    if (editing != null) {
      await _api.put('/api/Cash/Adjustment/${editing.adjustmentId}', body: {
        'FarmId': _farmId,
        'AdjustmentDate': i.adjustmentDate,
        'AdjustmentType': i.adjustmentType,
        'Amount': i.amount,
        'Description': i.description.isEmpty ? null : i.description,
      });
      return;
    }
    // Borrowing is a real loan; its create writes its own cash row.
    if (i.adjustmentType == 'LoanReceived' && i.amount > 0) {
      await _api.post('/api/Poultry/loans', body: {
        'lenderName': (i.lenderName ?? '').trim(),
        'originalPrincipal': i.amount,
        'amountReceived': i.amount,
        'startDate': i.adjustmentDate,
        'loanDate': i.adjustmentDate,
        'poultryCashAccountId': i.accountId,
        'notes': i.description.isEmpty ? null : i.description,
        'farmId': _farmId,
        'createdBy': userId,
      });
      return;
    }
    // Owner money is a record of its own, amount positive, direction in the type.
    if ((i.adjustmentType == 'OwnerInjection' || i.adjustmentType == 'Withdrawal') && i.accountId != null && i.amount != 0) {
      await _api.post('/api/Poultry/owner-money', body: {
        'transactionType': i.adjustmentType == 'OwnerInjection' ? 'Contribution' : 'Draw',
        'amount': i.amount.abs(),
        'poultryCashAccountId': i.accountId,
        'transactionDate': i.adjustmentDate,
        'notes': i.description.isEmpty ? null : i.description,
        'ownerName': i.ownerName,
        'farmId': _farmId,
        'createdBy': userId,
      });
      return;
    }
    // Always the capital record (what Cash Flow reads), then the account too.
    await _api.post('/api/Cash/Adjustment', body: {
      'UserId': userId,
      'FarmId': _farmId,
      'AdjustmentDate': i.adjustmentDate,
      'AdjustmentType': i.adjustmentType,
      'Amount': i.amount,
      'Description': i.description.isEmpty ? null : i.description,
    });
    if (i.accountId != null) {
      final label = adjustmentTypes.where((t) => t.$1 == i.adjustmentType).firstOrNull?.$2 ?? i.adjustmentType;
      await _api.post('/api/Poultry/cash-accounts/${i.accountId}/adjust?farmId=${Uri.encodeQueryComponent(_farmId)}', body: {
        'amount': i.amount,
        'reason': i.description.isNotEmpty ? '$label - ${i.description}' : label,
        'createdBy': userId,
      });
    }
  }

  Future<void> _delete(Map r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this adjustment?'),
        content: const Text(
            'It stops being counted in Cash Flow. Any cash account balance it moved is not affected — correct that from Cash Accounts if you need to.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: TColors.red600),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete adjustment'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _api.delete('/api/Cash/Adjustment/${tIntOrNull(r['sourceId'])}?farmId=${Uri.encodeQueryComponent(_farmId)}');
      _load();
    } on ApiException catch (e) {
      if (mounted) {
        trackerToast(context, 'Could not delete the adjustment',
            description: e.message.isNotEmpty ? e.message : 'Could not delete the adjustment.', error: true);
      }
    }
  }

  // ------------------------------------------------------------ derived

  List<Map> get _history {
    final filtered = [
      for (final r in _rows)
        if ((_flow == 'ALL' || r['flowGroup'] == _flow) && (_type == 'ALL' || categoryLabel(r['category']) == _type)) r,
    ];
    final running = withRunningBalance(filtered, tNum(_summary['openingCash']));
    Object? v(Map r) => switch (_sortKey) {
          'date' => '${dayOfStr(r['transactionDate'])}|${tStr(r['createdAt'])}',
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

  static String dayOfStr(Object? v) {
    final s = tStr(v);
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  List<AnalysisItem> get _analysis {
    final prev = previousRange(_from, _to);
    final ins = cashFlowBuckets(_rows, true), outs = cashFlowBuckets(_rows, false);
    return buildCashFlowAnalysis({
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
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/cash-flow');
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
    final negative = tNum(_summary['closingCash']) < 0;
    final types = {for (final r in _rows) categoryLabel(r['category'])}.toList()..sort();
    final history = _history;
    if (history.length != _lastTotal) {
      _lastTotal = history.length;
      _page = 1;
    }
    final pageRows = pageSlice(history, _page, _pageSize);
    final s = _summary;
    final net = tNum(s['netCashFlow']);
    final strict = tNum(s['operatingIn']) - tNum(s['operatingOut']);

    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Cash Flow')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
          children: [
            const Row(children: [
              Icon(Icons.account_balance_wallet_outlined, size: 20, color: TColors.emerald600),
              SizedBox(width: 6),
              Text('Cash Flow', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: TColors.slate900)),
            ]),
            const Text('What the business earned and spent', style: TextStyle(fontSize: 12, color: TColors.slate500)),
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
              FilledButton.icon(onPressed: () => _adjust(), icon: const Icon(Icons.add, size: 16), label: const Text('Add Adjustment')),
            ]),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => openAppHref(context, widget.session, widget.company, '/poultry-cash-accounts', label: 'Cash Account'),
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
                        child: Text('Where your money came from and went.',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate900)),
                      ),
                      Icon(_explainOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 18, color: TColors.slate400),
                    ]),
                  ),
                ),
                if (_explainOpen)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Text(
                      'Built from your sales, expenses and capital records. Operating money is what the business earned and spent; capital is money put in or taken out by owners and lenders. Transfers between your own cash accounts are not cash flow and are excluded — they are managed in Cash Accounts. Customer and Supplier Balances show what is still owed either way.',
                      style: TextStyle(fontSize: 12, color: TColors.slate600),
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
                  tip: 'Customer receipts plus any capital put into the business during the selected period.',
                ),
                InfoTile(
                  label: 'Money Out',
                  value: _gh(tNum(s['moneyOut'])),
                  note: 'For selected period',
                  color: TColors.rose700,
                  icon: Icons.trending_down,
                  tip: 'Expenses paid plus any capital taken out during the selected period.',
                ),
                InfoTile(
                  label: 'Cash at Hand',
                  value: _gh(tNum(_allTime['closingCash'])),
                  note: 'All time',
                  color: tNum(_allTime['closingCash']) < 0 ? TColors.rose700 : null,
                  tip: 'Every movement ever recorded, in minus out — NOT limited to the selected period. This is what your records say you should be holding across all cash accounts; it is not read from the accounts themselves, and comparing the two is what reconciliation is for.',
                ),
                InfoTile(
                  label: 'Net Cash Flow',
                  value: '${net > 0 ? '+' : ''}${_gh(net)}',
                  note: 'For selected period',
                  color: net >= 0 ? TColors.emerald700 : TColors.rose700,
                  tip: 'Money In minus Money Out. Positive means the business ended the period with more cash than it started with.',
                ),
                InfoTile(
                  label: 'Net Cash Flow (Strictly business)',
                  value: '${strict > 0 ? '+' : ''}${_gh(strict)}',
                  note: 'Excludes adjustments',
                  color: strict >= 0 ? TColors.emerald700 : TColors.rose700,
                  tip: 'Operating income minus operating spending, with capital adjustments left out — no owner injections, withdrawals or loans. This is whether the business funded ITSELF: the Net Cash Flow tile beside it can look healthy while this one is negative, which means the shortfall was covered by money put in rather than earned.',
                ),
                InfoTile(
                  label: 'Customer Balances',
                  value: _customers != null ? _gh(tNum(_customers!['totalBalance'])) : '—',
                  note: _customers != null ? 'All time · ${tIntOrNull(_customers!['partyCount']) ?? 0} customers owing' : 'All time',
                  icon: Icons.people_outline,
                  tip: 'Total unpaid or partially paid customer sales. Money customers still owe you — not cash, and not counted above until it is received.',
                ),
                InfoTile(
                  label: 'Supplier Balances',
                  value: _suppliers != null ? _gh(tNum(_suppliers!['totalBalance'])) : '—',
                  note: _suppliers != null ? 'All time · ${tIntOrNull(_suppliers!['partyCount']) ?? 0} suppliers owed' : 'All time',
                  icon: Icons.local_shipping_outlined,
                  tip: 'Total unpaid or partially paid purchases. Money you still owe suppliers — not counted above until it is paid.',
                ),
              ]),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 8, runSpacing: 2, children: [
                    Text.rich(TextSpan(children: [const TextSpan(text: 'Opening '), TextSpan(text: _gh(tNum(s['openingCash'])), style: const TextStyle(fontWeight: FontWeight.w700, color: TColors.slate900))])),
                    Text.rich(TextSpan(children: [const TextSpan(text: '+ in '), TextSpan(text: _gh(tNum(s['moneyIn'])), style: const TextStyle(fontWeight: FontWeight.w700))]),
                        style: const TextStyle(color: TColors.emerald700)),
                    Text.rich(TextSpan(children: [const TextSpan(text: '− out '), TextSpan(text: _gh(tNum(s['moneyOut'])), style: const TextStyle(fontWeight: FontWeight.w700))]),
                        style: const TextStyle(color: TColors.rose700)),
                    Text.rich(TextSpan(children: [const TextSpan(text: '= closing '), TextSpan(text: _gh(tNum(s['closingCash'])), style: const TextStyle(fontWeight: FontWeight.w700, color: TColors.slate900))])),
                  ].map((w) => DefaultTextStyle.merge(style: const TextStyle(fontSize: 12, color: TColors.slate600), child: w)).toList()),
                  if (tNum(s['financingIn']) > 0 || tNum(s['financingOut']) > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Includes'
                        '${tNum(s['financingIn']) > 0 ? ' ${_gh(tNum(s['financingIn']))} of capital in' : ''}'
                        '${tNum(s['financingIn']) > 0 && tNum(s['financingOut']) > 0 ? ' and' : ''}'
                        '${tNum(s['financingOut']) > 0 ? ' ${_gh(tNum(s['financingOut']))} taken out' : ''}'
                        ' — money put in or withdrawn by owners and lenders, not earned or spent by trading.',
                        style: const TextStyle(fontSize: 12, color: TColors.slate500),
                      ),
                    ),
                ]),
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
                        AppSelectItem(value: 'FinancingIn', label: 'Capital received'),
                        AppSelectItem(value: 'FinancingOut', label: 'Capital withdrawn'),
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
                        child: Text('No cash movement in this period. Record a sale, an expense or an adjustment and it appears here.',
                            textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: TColors.slate500)),
                      )
                    : MobileCardList<Map>(
                        items: pageRows,
                        striped: true,
                        stripeBlue: true,
                        keyOf: (r) => '${r['rowSource']}-${r['id']}',
                        primary: (r) => categoryLabel(r['category']),
                        secondary: (r) => '${fmtDateTimeLike(r['transactionDate'])} · ${flowGroupLabel(r['flowGroup'])}',
                        highlights: (r) {
                          final a = tNum(r['amount']);
                          return [
                            Highlight(a < 0 ? 'Money out' : 'Money in', '${a < 0 ? '−' : '+'}${_gh(a.abs())}',
                                accent: a < 0 ? Accent.rose : Accent.emerald),
                            Highlight('Running cash', _gh(tNum(r['running'])), accent: Accent.blue),
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
          TCol('Actions', right: true, width: 100),
        ],
        rows: [
          for (final r in rows)
            () {
              final a = tNum(r['amount']);
              final manage = r['rowSource'] == 'Adjustment';
              return [
                cellText(fmtDateTimeLike(r['transactionDate'])),
                cellText(categoryLabel(r['category'])),
                Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(flowGroupLabel(r['flowGroup']), style: const TextStyle(color: TColors.slate600)),
                  Text(sourceTypeLabel(r['sourceType']), style: const TextStyle(fontSize: 11, color: TColors.slate400)),
                ]),
                cellText(tStr(r['description']).isEmpty ? '—' : tStr(r['description'])),
                cellText(a > 0 ? _gh(a) : '—', color: TColors.emerald700),
                cellText(a < 0 ? _gh(a.abs()) : '—', color: TColors.rose600),
                cellText(_gh(tNum(r['running'])), bold: true),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: manage ? 'Edit this adjustment' : _sourceOwnedHint,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.edit_outlined, size: 18, color: TColors.slate600),
                    onPressed: !manage
                        ? null
                        : () => _adjust(CashAdjustmentSeed(
                              adjustmentId: tIntOrNull(r['sourceId']) ?? 0,
                              adjustmentType: adjustmentTypeFromLabel(r['sourceType']),
                              adjustmentDate: tStr(r['transactionDate']),
                              amount: a,
                              description: tStr(r['description']),
                            )),
                  ),
                  IconButton(
                    tooltip: manage ? 'Delete this adjustment' : _sourceOwnedHint,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.delete_outline, size: 18, color: TColors.rose600),
                    onPressed: !manage ? null : () => _delete(r),
                  ),
                ]),
              ];
            }(),
        ],
      );

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
              Expanded(child: figure('Net', '${net > 0 ? '+' : ''}${_gh(net)}', net >= 0 ? TColors.emerald700 : TColors.rose700)),
            ]),
            if (negative) ...[
              label('Worth checking first'),
              TrackerBanner.error('', spans: const [
                TextSpan(text: 'Closing cash is negative.', style: TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(
                    text: ' The recorded transactions add up to less than nothing, which usually means an opening balance was never entered, or spending was recorded before the income that funded it.'),
              ]),
            ],
            label('About these figures'),
            TrackerBanner.info(
              'These figures come from your sales, expenses and capital records — not from your cash account balances. Closing cash is not expected to match what your accounts hold; comparing the two is what reconciliation is for.',
              spans: [
                const TextSpan(
                    text: 'These figures come from your sales, expenses and capital records — not from your cash account balances. Closing cash is '),
                const TextSpan(text: 'not', style: TextStyle(fontWeight: FontWeight.w700)),
                const TextSpan(text: ' expected to match what your accounts hold; comparing the two is what '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: GestureDetector(
                    onTap: () => openAppHref(context, widget.session, widget.company, '/poultry-cash-reconciliation', label: 'Reconciliation'),
                    child: const Text('reconciliation', style: TextStyle(fontSize: 12, decoration: TextDecoration.underline)),
                  ),
                ),
                const TextSpan(text: ' is for.'),
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
