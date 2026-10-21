// components/restaurant/reports/money-reports.tsx (migrations 323 / 324 / 326):
// the Restaurant cash & ledger reports. Every one reads the ONE cash ledger
// (or the Cash Flow built on it), so they agree with each other, with the
// account balances and with the Cash Flow page.

import 'package:flutter/material.dart';

import '../../poultry/money/cash_flow_screen.dart' show cashFlowBuckets, withRunningBalance;
import '../../poultry/reports/report_format.dart' show buildCashFlowAnalysis, categoryLabel, flowGroupLabel;
import '../../poultry/reports/report_widgets.dart' show ReportAnalysis;
import '../../poultry/trackers/tracker_logic.dart' show tNum, tStr;
import '../../poultry/trackers/tracker_widgets.dart' show TColors;
import 'restaurant_report_kit.dart';

const _inGreen = Color(0xFF059669);
const _netSlate = Color(0xFF334155);

num _n(Map r, String k) => tNum(r[k]);
String _s(Map r, String k) => tStr(r[k]);
Map<String, dynamic> _fromTo(RRange r) => {'from': r.from, 'to': r.to};
String _fin(String path) => '/api/Restaurant/finance$path';
bool _inRange(Object? s, String from, String to) {
  final d = d10(s);
  return d.compareTo(from) >= 0 && d.compareTo(to) <= 0;
}

/// ACCOUNT_TYPE_LABELS.
const restaurantAccountTypeLabels = {
  'Till': 'Till (cash drawer)',
  'CashBox': 'Cash box / safe',
  'PettyCash': 'Petty cash',
  'MobileMoney': 'Mobile money',
  'Bank': 'Bank account',
  'Other': 'Other',
};

/// LEDGER_SOURCE_LABELS.
const _ledgerSourceLabels = {
  'OpeningBalance': 'Opening balance',
  'OrderPayment': 'Order payment',
  'OrderRefund': 'Refund',
  'Expense': 'Expense',
  'ExpenseReversal': 'Expense deleted',
  'GiftCardSale': 'Gift card sale',
  'GiftCardReload': 'Gift card reload',
  'TransferOut': 'Transfer out',
  'TransferIn': 'Transfer in',
  'TransferReversalOut': 'Transfer reversed',
  'TransferReversalIn': 'Transfer reversed',
  'ShiftFloatOut': 'Float to till',
  'ShiftFloatIn': 'Opening float',
  'ShiftDropOut': 'Takings dropped',
  'ShiftDropIn': 'Takings from till',
  'ShiftVariance': 'Till over / short',
  'CountVariance': 'Count difference',
  'CountVarianceReversal': 'Count reversed',
  'OwnerContribution': 'Owner contribution',
  'OwnerDraw': 'Owner drawing',
  'OwnerContributionReversal': 'Contribution reversed',
  'OwnerDrawReversal': 'Drawing reversed',
  'LoanReceived': 'Loan received',
  'LoanReceivedReversal': 'Loan cancelled',
  'LoanRepayment': 'Loan repayment',
  'LoanRepaymentReversal': 'Repayment reversed',
  'Payroll': 'Payroll (net pay)',
  'EmployeeLoanDisbursement': 'Staff advance paid out',
  'EmployeeLoanReversal': 'Staff advance reversed',
  'EmployeeLoanRepayment': 'Staff advance repaid',
  'EmployeeLoanRepaymentReversal': 'Staff repayment reversed',
  'AssetPurchase': 'Capital investment',
  'AssetPurchaseReversal': 'Capital investment corrected',
  'AssetDisposal': 'Asset sold',
  'StockPurchase': 'Stock purchase',
  'StockPurchaseReversal': 'Stock purchase reversed',
  'SupplierPayment': 'Supplier payment',
  'SupplierPaymentReversal': 'Supplier payment reversed',
};

String ledgerSourceLabel(Object? s) {
  final v = tStr(s);
  if (v.isEmpty) return '—';
  return _ledgerSourceLabels[v] ?? v.replaceAllMapped(RegExp('([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}');
}

/// Same length period immediately before [from, to].
({String from, String to, int days}) _previousPeriod(String from, String to) {
  final f = DateTime.parse(from), t = DateTime.parse(to);
  final days = t.difference(f).inDays + 1 < 1 ? 1 : t.difference(f).inDays + 1;
  final pt = f.subtract(const Duration(days: 1));
  final pf = pt.subtract(Duration(days: days - 1));
  return (from: isoDay(pf), to: isoDay(pt), days: days);
}

Future<Map> _cashFlow(RCtx c, String from, String to) => c.map('/api/Restaurant/cash-flow', {'fromDate': from, 'toDate': to});

List<Map> _flowRows(Map cf) => [for (final x in (cf['rows'] is List ? cf['rows'] as List : const [])) if (x is Map) x];
Map _summary(Map? cf) => cf?['summary'] is Map ? cf!['summary'] as Map : const {};

/// Money in / out / net per day, oldest first, with the closing cash of each day.
List<Map> _byDay(List<Map> rows, num opening) {
  final map = <String, Map<String, dynamic>>{};
  for (final r in rows) {
    final d = d10(r['transactionDate']);
    final e = map.putIfAbsent(d, () => {'date': d, 'moneyIn': 0, 'moneyOut': 0});
    final a = _n(r, 'amount');
    if (a > 0) {
      e['moneyIn'] = e['moneyIn'] + a;
    } else {
      e['moneyOut'] = e['moneyOut'] - a;
    }
  }
  var running = opening;
  final days = map.values.toList()..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
  return [
    for (final e in days)
      {
        ...e,
        'net': (e['moneyIn'] as num) - (e['moneyOut'] as num),
        'closing': ((running += (e['moneyIn'] as num) - (e['moneyOut'] as num)) * 100).round() / 100,
      },
  ];
}

/// CashBreakdownPanel: title and total, then one bar per bucket.
Widget _breakdown(String title, String total, bool green, String empty, List<(String, String, num)> items) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
          Text(total, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 10),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(empty, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          )
        else
          for (final (label, value, pct) in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: TColors.slate600))),
                  Text('$value (${pct.toStringAsFixed(1)}%)', style: const TextStyle(fontSize: 12)),
                ]),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: (pct.clamp(0, 100) / 100).toDouble(),
                    minHeight: 8,
                    color: green ? const Color(0xFF10B981) : const Color(0xFFF43F5E),
                    backgroundColor: TColors.slate100,
                  ),
                ),
              ]),
            ),
      ]),
    );

/// A compact table inside a panel: on the phone each row is a small card.
Widget _miniRows(List<List<(String, Widget)>> rows) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final cells in rows)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            DefaultTextStyle.merge(style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500), child: cells.first.$2),
            const SizedBox(height: 4),
            for (final (label, value) in cells.skip(1))
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(children: [
                  Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                  const SizedBox(width: 8),
                  Expanded(child: Align(alignment: Alignment.centerRight, child: DefaultTextStyle.merge(style: const TextStyle(fontSize: 12), child: value))),
                ]),
              ),
          ]),
        ),
    ]);

Text _t(String s, {Color? color, bool bold = false, bool strike = false}) => Text(s,
    textAlign: TextAlign.right,
    style: TextStyle(color: color, fontWeight: bold ? FontWeight.w600 : null, decoration: strike ? TextDecoration.lineThrough : null));

// ===========================================================================
// Cash Flow Detail
// ===========================================================================

final cashFlowDetail = RDef(
  load: (c, r) async {
    final p = _previousPeriod(r.from, r.to);
    final res = await Future.wait([_cashFlow(c, r.from, r.to), _cashFlow(c, p.from, p.to)]);
    final cur = res[0];
    final rows = withRunningBalance(_flowRows(cur), _n(_summary(cur), 'openingCash'));
    return RLoad(rows, {'cur': cur, 'prev': res[1], 'days': p.days});
  },
  summary: (r, f) {
    final s = _summary((r.meta as Map?)?['cur'] as Map?);
    if (s.isEmpty) return [];
    return [
      (label: 'Opening cash', value: f.money(s['openingCash'])),
      (label: 'Money in', value: f.money(s['moneyIn'])),
      (label: 'Money out', value: f.money(s['moneyOut'])),
      (label: 'Closing cash', value: f.money(s['closingCash'])),
      (label: 'From trading (in − out)', value: f.money(_n(s, 'operatingIn') - _n(s, 'operatingOut'))),
      (label: 'Loans & owner money (net)', value: f.money(_n(s, 'financingIn') - _n(s, 'financingOut'))),
    ];
  },
  panel: (r, f) {
    final m = r.meta as Map?;
    if (m == null) return null;
    final cur = m['cur'] as Map, prev = m['prev'] as Map;
    final s = _summary(cur), ps = _summary(prev);
    final days = m['days'] as int;
    final rows = _flowRows(cur);
    final ins = cashFlowBuckets(rows, true), outs = cashFlowBuckets(rows, false);
    final analysis = buildCashFlowAnalysis({
      'moneyIn': s['moneyIn'], 'moneyOut': s['moneyOut'], 'netCashFlow': s['netCashFlow'],
      'operatingIn': s['operatingIn'], 'operatingOut': s['operatingOut'], 'financingIn': s['financingIn'], 'financingOut': s['financingOut'],
      'cashAtHand': s['closingCash'], 'offLedgerIn': 0, 'offLedgerOut': 0, 'transferVolume': s['transferVolume'] ?? 0,
      'movementCount': s['movementCount'], 'daysInPeriod': days,
      'previousMoneyIn': ps['moneyIn'], 'previousMoneyOut': ps['moneyOut'], 'previousNetCashFlow': ps['netCashFlow'],
      'moneyInByCategory': [for (final b in ins) {'label': b.label, 'amount': b.amount, 'sharePercent': b.percent}],
      'moneyOutByCategory': [for (final b in outs) {'label': b.label, 'amount': b.amount, 'sharePercent': b.percent}],
    }, f.money);
    final byDay = _byDay(rows, _n(s, 'openingCash'));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (byDay.isNotEmpty) ...[
        reportCard('Cash by day', 'Money in and out each day, and the cash held at the end of it.',
            BarChartRows(items: [for (final d in byDay) (d['date'] as String).substring(5)], series: [
              ('Money in', _inGreen, [for (final d in byDay) d['moneyIn'] as num], f.money),
              ('Money out', const Color(0xFFE11D48), [for (final d in byDay) d['moneyOut'] as num], f.money),
              ('Cash held', _netSlate, [for (final d in byDay) d['closing'] as num], f.money),
            ])),
        const SizedBox(height: 12),
      ],
      _breakdown('Money in by source', f.money(s['moneyIn']), true, 'Nothing came in.',
          [for (final b in ins) (b.label, f.money(b.amount), b.percent)]),
      const SizedBox(height: 12),
      _breakdown('Money out by category', f.money(s['moneyOut']), false, 'Nothing went out.',
          [for (final b in outs) (b.label, f.money(b.amount), b.percent)]),
      const SizedBox(height: 12),
      ReportAnalysis(title: 'Analysis (compared with the previous $days day${days == 1 ? '' : 's'})', items: analysis),
    ]);
  },
  columns: [
    RCol('date', 'Date', (r, f) => d10(r['transactionDate'])),
    RCol('type', 'Type', (r, f) => flowGroupLabel(r['flowGroup']), secondary: true),
    RCol('cat', 'Category', (r, f) => categoryLabel(r['category'])),
    RCol('acct', 'Account', (r, f) => _s(r, 'accountName').isEmpty ? '—' : _s(r, 'accountName'), secondary: true),
    RCol('desc', 'Description', (r, f) => _s(r, 'description'), secondary: true),
    RCol('in', 'In', (r, f) => _n(r, 'amount') > 0 ? f.money(r['amount']) : '', numeric: true),
    RCol('out', 'Out', (r, f) => _n(r, 'amount') < 0 ? f.money(-_n(r, 'amount')) : '', numeric: true),
    RCol('run', 'Running cash', (r, f) => f.money(r['running']), numeric: true),
  ],
  tableTitle: 'Every movement',
  tableHint: 'Transfers between your own accounts are left out — they move money, they do not bring it in or send it out.',
  emptyText: 'No money moved in this period.',
);

// ===========================================================================
// Cash Movement
// ===========================================================================

final cashMovement = RDef(
  load: (c, r) async {
    final cur = await _cashFlow(c, r.from, r.to);
    return RLoad(_byDay(_flowRows(cur), _n(_summary(cur), 'openingCash')), cur);
  },
  summary: (r, f) {
    final s = _summary(r.meta as Map?);
    if (s.isEmpty) return [];
    return [
      (label: 'Opening cash', value: f.money(s['openingCash'])),
      (label: 'Money in', value: f.money(s['moneyIn'])),
      (label: 'Money out', value: f.money(s['moneyOut'])),
      (label: 'Net movement', value: f.money(s['netCashFlow'])),
      (label: 'Closing cash (= all account balances)', value: f.money(s['closingCash'])),
    ];
  },
  panel: (r, f) => r.rows.isEmpty
      ? null
      : reportCard('Net movement by day', 'Green days added cash; red days used it.',
          BarChartRows(signed: true, items: [for (final d in r.rows) (d['date'] as String).substring(5)], series: [
            ('Net', _inGreen, [for (final d in r.rows) d['net'] as num], f.money),
          ])),
  columns: [
    RCol('date', 'Date', (r, f) => _s(r, 'date')),
    RCol('in', 'Money in', (r, f) => f.money(r['moneyIn']), numeric: true),
    RCol('out', 'Money out', (r, f) => f.money(r['moneyOut']), numeric: true),
    RCol('net', 'Net', (r, f) => f.money(r['net']),
        numeric: true, render: (r, f) => coloured(f.money(r['net']), _n(r, 'net') < 0 ? red600 : emerald700)),
    RCol('close', 'Cash at end of day', (r, f) => f.money(r['closing']), numeric: true),
  ],
  tableTitle: 'Day by day',
  emptyText: 'No money moved in this period.',
);

// ===========================================================================
// Cash Account Report
// ===========================================================================

({String text, String tone}) _accountStatus(Map a) {
  if ((_n(a, 'currentBalance') - _n(a, 'ledgerBalance')).abs() > 0.005) return (text: 'Out of sync', tone: 'bad');
  if (_n(a, 'closingBalance') < 0) return (text: 'Below zero', tone: 'bad');
  if (_s(a, 'accountType') == 'Till') return (text: 'Counted at shift close', tone: 'muted');
  final last = DateTime.tryParse(_s(a, 'lastCountedAt'));
  if (last == null) return (text: 'Never counted', tone: 'warn');
  final days = DateTime.now().difference(last).inDays;
  return days > 30 ? (text: 'Counted $days days ago', tone: 'warn') : (text: 'Counted recently', tone: 'good');
}

final cashAccounts = RDef(
  load: (c, r) async {
    final res = await Future.wait([
      c.list(_fin('/ledger/period'), _fromTo(r)),
      c.list(_fin('/ledger/rows'), _fromTo(r)),
      c.list(_fin('/transfers'), _fromTo(r)),
    ]);
    final accounts = [for (final a in res[0]) if (a['isActive'] == true || _n(a, 'txnCount') > 0 || _n(a, 'closingBalance') != 0) a];
    return RLoad(res[1], {'accounts': accounts, 'transfers': res[2]});
  },
  summary: (r, f) {
    final a = ((r.meta as Map?)?['accounts'] as List<Map>?) ?? const [];
    return [
      (label: 'Opening (all accounts)', value: f.money(sumOf(a, (x) => _n(x, 'openingBalance')))),
      (label: 'Money in', value: f.money(sumOf(a, (x) => _n(x, 'moneyIn')))),
      (label: 'Money out', value: f.money(sumOf(a, (x) => _n(x, 'moneyOut')))),
      (label: 'Closing (all accounts)', value: f.money(sumOf(a, (x) => _n(x, 'closingBalance')))),
      (label: 'Moved between accounts', value: f.money(sumOf(a, (x) => _n(x, 'transfersOut')))),
      (label: 'Accounts needing attention', value: '${a.where((x) => const {'bad', 'warn'}.contains(_accountStatus(x).tone)).length}'),
    ];
  },
  panel: (r, f) {
    final a = ((r.meta as Map?)?['accounts'] as List<Map>?) ?? const [];
    final t = ((r.meta as Map?)?['transfers'] as List<Map>?) ?? const [];
    final open = sumOf(a, (x) => _n(x, 'openingBalance')), inn = sumOf(a, (x) => _n(x, 'moneyIn')), out = sumOf(a, (x) => _n(x, 'moneyOut'));
    final tin = sumOf(a, (x) => _n(x, 'transfersIn')), tout = sumOf(a, (x) => _n(x, 'transfersOut')), close = sumOf(a, (x) => _n(x, 'closingBalance'));
    final off = ((open + inn - out + tin - tout - close) * 100).round() / 100;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      reportCard(
        'Where the money sits',
        "Each account's opening, movements and closing for the period. Status is as of today.",
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _miniRows([
            for (final x in a)
              [
                (
                  'Account',
                  Text.rich(TextSpan(children: [
                    TextSpan(text: _s(x, 'name')),
                    if (x['isActive'] != true) const TextSpan(text: ' (inactive)', style: TextStyle(fontSize: 12, color: TColors.slate400)),
                  ])),
                ),
                ('Type', _t(restaurantAccountTypeLabels[_s(x, 'accountType')] ?? _s(x, 'accountType'))),
                ('Opening', _t(f.money(x['openingBalance']))),
                ('In', _t(f.money(x['moneyIn']), color: emerald700)),
                ('Out', _t(f.money(x['moneyOut']), color: rose700)),
                ('Transfers in', _t(f.money(x['transfersIn']))),
                ('Transfers out', _t(f.money(x['transfersOut']))),
                ('Closing', _t(f.money(x['closingBalance']), bold: true, color: _n(x, 'closingBalance') < 0 ? red600 : null)),
                ('Share', _t(close != 0 ? f.pct(_n(x, 'closingBalance') / close * 100) : '—')),
                ('Status', toneBadge(_accountStatus(x).text, _accountStatus(x).tone)),
              ],
          ]),
          Text(
            'Check: ${f.money(open)} opening + ${f.money(inn)} in − ${f.money(out)} out + ${f.money(tin)} transfers in − ${f.money(tout)} '
            'transfers out = ${f.money(close)} closing${off != 0 ? ' — off by ${f.money(off)}' : ' ✓'}',
            style: TextStyle(fontSize: 12, color: off == 0 ? TColors.slate500 : red700),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      reportCard(
        'Transfers',
        'Money moved between your own accounts in the period.',
        t.isEmpty
            ? const Text('No transfers in this period.', style: TextStyle(fontSize: 13, color: TColors.slate500))
            : _miniRows([
                for (final x in t)
                  [
                    ('Date', _t(d10(x['transferDate']), strike: _s(x, 'status') == 'Reversed')),
                    ('Number', _t(_s(x, 'transferNumber'))),
                    ('From', _t(_s(x, 'fromAccountName'))),
                    ('To', _t(_s(x, 'toAccountName'))),
                    ('Amount', _t(f.money(x['amount']), strike: _s(x, 'status') == 'Reversed')),
                    ('Status', _t(_s(x, 'status'))),
                  ],
              ]),
      ),
    ]);
  },
  columns: [
    RCol('date', 'Date', (r, f) => d10(r['txnDate'])),
    RCol('acct', 'Account', (r, f) => _s(r, 'accountName')),
    RCol('what', 'What', (r, f) => ledgerSourceLabel(r['sourceType']) + (r['isInternal'] == true ? ' (internal)' : '')),
    RCol('desc', 'Description', (r, f) => _s(r, 'description'), secondary: true),
    RCol('in', 'In', (r, f) => _n(r, 'amount') > 0 ? f.money(r['amount']) : '', numeric: true),
    RCol('out', 'Out', (r, f) => _n(r, 'amount') < 0 ? f.money(-_n(r, 'amount')) : '', numeric: true),
    RCol('bal', 'Account balance', (r, f) => f.money(r['runningBalance']), numeric: true),
  ],
  tableTitle: 'Ledger — every account',
  tableHint: "Account balance is that account's balance after the row. Internal rows are transfers, till floats and drops.",
  emptyText: 'No ledger rows in this period.',
);

// ===========================================================================
// Money Movement
// ===========================================================================

final moneyMovement = RDef(
  load: (c, r) async {
    final res = await Future.wait([
      c.list(_fin('/transfers'), _fromTo(r)),
      c.list(_fin('/owner-money'), _fromTo(r)),
      c.list(_fin('/loans')),
      c.list(_fin('/loans/payments')),
    ]);
    final transfers = res[0], owner = res[1], loans = res[2];
    final repayments = [for (final p in res[3]) if (_inRange(p['paymentDate'], r.from, r.to)) p];
    final loansInPeriod = [for (final l in loans) if (_inRange(l['loanDate'], r.from, r.to)) l];
    final rows = <Map>[
      for (final t in transfers)
        {
          'date': d10(t['transferDate']), 'kind': 'Transfer', 'number': _s(t, 'transferNumber'),
          'detail': '${_s(t, 'fromAccountName')} → ${_s(t, 'toAccountName')}', 'account': '', 'moneyIn': 0, 'moneyOut': 0, 'status': _s(t, 'status'),
        },
      for (final o in owner)
        {
          'date': d10(o['entryDate']), 'kind': _s(o, 'entryType') == 'Contribution' ? 'Owner contribution' : 'Owner drawing',
          'number': _s(o, 'entryNumber'), 'detail': _s(o, 'ownerName'), 'account': _s(o, 'accountName'),
          'moneyIn': _s(o, 'entryType') == 'Contribution' ? _n(o, 'amount') : 0, 'moneyOut': _s(o, 'entryType') == 'Draw' ? _n(o, 'amount') : 0,
          'status': _s(o, 'status'),
        },
      for (final l in loansInPeriod)
        {
          'date': d10(l['loanDate']), 'kind': 'Loan received', 'number': _s(l, 'loanNumber'),
          'detail': '${_s(l, 'lenderName')} — borrowed ${_n(l, 'principal').toStringAsFixed(2)}', 'account': _s(l, 'receivedAccountName'),
          'moneyIn': _s(l, 'status') == 'Cancelled' ? 0 : _n(l, 'amountReceived'), 'moneyOut': 0, 'status': _s(l, 'status'),
        },
      for (final p in repayments)
        {
          'date': d10(p['paymentDate']), 'kind': 'Loan repayment', 'number': _s(p, 'loanNumber'),
          'detail': '${_s(p, 'lenderName')} — principal ${_n(p, 'principalAmount').toStringAsFixed(2)}, interest '
              '${_n(p, 'interestAmount').toStringAsFixed(2)}, fees ${_n(p, 'feeAmount').toStringAsFixed(2)}',
          'account': _s(p, 'accountName'), 'moneyIn': 0, 'moneyOut': _s(p, 'status') == 'Posted' ? _n(p, 'totalAmount') : 0,
          'status': _s(p, 'status'),
        },
    ]..sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
    return RLoad(rows, {'transfers': transfers, 'owner': owner, 'loans': loans, 'repayments': repayments});
  },
  summary: (r, f) {
    final m = r.meta as Map?;
    if (m == null) return [];
    List<Map> live(Object? x) => [for (final y in (x as List<Map>)) if (_s(y, 'status') == 'Posted') y];
    final owner = live(m['owner']);
    final rp = live(m['repayments']);
    return [
      (label: 'Moved between accounts', value: f.money(sumOf(live(m['transfers']), (t) => _n(t, 'amount')))),
      (
        label: 'Owner put in / took out',
        value: '${f.money(sumOf(owner.where((o) => _s(o, 'entryType') == 'Contribution'), (o) => _n(o, 'amount')))} / '
            '${f.money(sumOf(owner.where((o) => _s(o, 'entryType') == 'Draw'), (o) => _n(o, 'amount')))}',
      ),
      (label: 'Still owed on loans', value: f.money(sumOf((m['loans'] as List<Map>).where((l) => _s(l, 'status') == 'Active'), (l) => _n(l, 'outstandingPrincipal')))),
      (label: 'Principal repaid', value: f.money(sumOf(rp, (p) => _n(p, 'principalAmount')))),
      (label: 'Cost of borrowing (interest + fees)', value: f.money(sumOf(rp, (p) => _n(p, 'interestAmount') + _n(p, 'feeAmount')))),
    ];
  },
  panel: (r, f) {
    final loans = [for (final l in ((r.meta as Map?)?['loans'] as List<Map>?) ?? const <Map>[]) if (_s(l, 'status') != 'Cancelled') l];
    if (loans.isEmpty) return null;
    return reportCard(
      'Loans',
      'Every loan not cancelled, with what is still owed today.',
      _miniRows([
        for (final l in loans)
          [
            ('Loan', Text(_s(l, 'loanNumber'))),
            ('Lender', _t(_s(l, 'lenderName'))),
            ('Borrowed', _t(f.money(l['principal']))),
            ('Received', _t(f.money(l['amountReceived']))),
            ('Repaid', _t(f.money(l['principalRepaid']))),
            ('Still owed', _t(f.money(l['outstandingPrincipal']), bold: true)),
            ('Interest + fees', _t(f.money(_n(l, 'interestPaid') + _n(l, 'feesPaid')))),
            (
              'Status',
              toneBadge(l['isOverdue'] == true ? 'Overdue' : _s(l, 'status'),
                  l['isOverdue'] == true ? 'bad' : (_s(l, 'status') == 'PaidOff' ? 'good' : 'muted')),
            ),
          ],
      ]),
    );
  },
  columns: [
    RCol('date', 'Date', (r, f) => _s(r, 'date')),
    RCol('kind', 'Movement', (r, f) => _s(r, 'kind')),
    RCol('num', 'Number', (r, f) => _s(r, 'number'), secondary: true),
    RCol('detail', 'Detail', (r, f) => _s(r, 'detail'), secondary: true),
    RCol('acct', 'Account', (r, f) => _s(r, 'account'), secondary: true),
    RCol('in', 'In', (r, f) => _n(r, 'moneyIn') != 0 ? f.money(r['moneyIn']) : '', numeric: true),
    RCol('out', 'Out', (r, f) => _n(r, 'moneyOut') != 0 ? f.money(r['moneyOut']) : '', numeric: true),
    RCol('status', 'Status', (r, f) => _s(r, 'status'),
        render: (r, f) => toneBadge(_s(r, 'status'), const {'Reversed', 'Cancelled'}.contains(_s(r, 'status')) ? 'muted' : 'good')),
  ],
  tableTitle: 'Transfers, owner money and loans',
  tableHint: 'Transfers show no in/out: they move money between your own accounts. Reversed rows carry no amount.',
  emptyText: 'No transfers, owner money or loan activity in this period.',
);

// ===========================================================================
// Till & Count Variances
// ===========================================================================

final tillVariances = RDef(
  load: (c, r) async {
    final res = await Future.wait([
      c.list(_fin('/shifts'), {'status': 'Closed', ..._fromTo(r)}),
      c.list(_fin('/counts')),
    ]);
    final rows = <Map>[
      for (final s in res[0])
        {
          'date': d10(_s(s, 'closedAt').isNotEmpty ? s['closedAt'] : s['openedAt']), 'kind': 'Till shift', 'account': _s(s, 'tillName'),
          'reference': _s(s, 'shiftNumber'), 'expected': _n(s, 'expectedCash'), 'counted': _n(s, 'countedCash'),
          'difference': _n(s, 'variance'), 'by': _s(s, 'closedBy'), 'note': _s(s, 'closeNotes'),
        },
      for (final c2 in res[1])
        if (_inRange(c2['countDate'], r.from, r.to) && _s(c2, 'status') == 'Posted')
          {
            'date': d10(c2['countDate']), 'kind': 'Account count', 'account': _s(c2, 'accountName'), 'reference': 'Count #${_s(c2, 'countId')}',
            'expected': _n(c2, 'systemBalance'), 'counted': _n(c2, 'countedBalance'), 'difference': _n(c2, 'difference'),
            'by': _s(c2, 'createdBy'), 'note': _s(c2, 'notes'),
          },
    ]..sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
    return RLoad(rows);
  },
  summary: (r, f) => [
    (label: 'Short (total)', value: f.money(-sumOf(r.rows.where((x) => _n(x, 'difference') < 0), (x) => _n(x, 'difference')))),
    (label: 'Over (total)', value: f.money(sumOf(r.rows.where((x) => _n(x, 'difference') > 0), (x) => _n(x, 'difference')))),
    (label: 'Net over / short', value: f.money(sumOf(r.rows, (x) => _n(x, 'difference')))),
    (label: 'Counts that balanced', value: '${r.rows.where((x) => _n(x, 'difference') == 0).length} of ${r.rows.length}'),
  ],
  columns: [
    RCol('date', 'Date', (r, f) => _s(r, 'date')),
    RCol('kind', 'Type', (r, f) => _s(r, 'kind'), secondary: true),
    RCol('acct', 'Till / account', (r, f) => _s(r, 'account')),
    RCol('ref', 'Reference', (r, f) => _s(r, 'reference'), secondary: true),
    RCol('exp', 'Expected', (r, f) => f.money(r['expected']), numeric: true),
    RCol('cnt', 'Counted', (r, f) => f.money(r['counted']), numeric: true),
    RCol('diff', 'Over / short', (r, f) => f.money(r['difference']),
        numeric: true,
        render: (r, f) {
          final d = _n(r, 'difference');
          return coloured(f.money(d), d < 0 ? red600 : d > 0 ? amber600 : emerald700, bold: d != 0);
        }),
    RCol('by', 'By', (r, f) => _s(r, 'by'), secondary: true),
    RCol('note', 'Note', (r, f) => _s(r, 'note'), secondary: true),
  ],
  tableTitle: 'Every cash-up and count',
  tableHint: 'Differences were posted to the ledger at the time, so they are already in Cash Flow and the P&L (as Cash over / short).',
  emptyText: 'No shifts were closed and no accounts counted in this period.',
);

// ===========================================================================
// Closing Report
// ===========================================================================

final closingReport = RDef(
  load: (c, r) async => RLoad(await c.list(_fin('/daily-closing'), {'limit': 366, ..._fromTo(r)})),
  summary: (r, f) {
    final closed = [for (final x in r.rows) if (_s(x, 'status') == 'Closed') x];
    return [
      (label: 'Days closed', value: '${closed.length}${r.rows.length > closed.length ? ' (${r.rows.length - closed.length} reopened)' : ''}'),
      (label: 'Net sales', value: f.money(sumOf(closed, (x) => _n(x, 'netSales')))),
      (label: 'Money in / out', value: '${f.money(sumOf(closed, (x) => _n(x, 'moneyIn')))} / ${f.money(sumOf(closed, (x) => _n(x, 'moneyOut')))}'),
      (label: 'Cash over / short', value: f.money(sumOf(closed, (x) => _n(x, 'cashVariance')))),
    ];
  },
  columns: [
    RCol('date', 'Day', (r, f) => d10(r['closingDate'])),
    RCol('status', 'Status', (r, f) => _s(r, 'status'), render: (r, f) => toneBadge(_s(r, 'status'), _s(r, 'status') == 'Closed' ? 'good' : 'warn')),
    RCol('orders', 'Orders', (r, f) => f.int_(r['orderCount']), numeric: true, secondary: true),
    RCol('sales', 'Net sales', (r, f) => f.money(r['netSales']), numeric: true),
    RCol('tax', 'Tax', (r, f) => f.money(r['taxCollected']), numeric: true, secondary: true),
    RCol('in', 'Money in', (r, f) => f.money(r['moneyIn']), numeric: true),
    RCol('out', 'Money out', (r, f) => f.money(r['moneyOut']), numeric: true),
    RCol('var', 'Over / short', (r, f) => f.money(r['cashVariance']), numeric: true),
    RCol('by', 'Closed by', (r, f) => _s(r, 'closedBy'), secondary: true),
    RCol('why', 'Reopen reason', (r, f) => _s(r, 'reopenReason'), secondary: true),
  ],
  tableTitle: 'Closed days',
  tableHint: 'Figures are the snapshot taken when the day was closed.',
  emptyText: 'No day in this period has been closed. Close days from Money → Daily Closing.',
);

// ===========================================================================
// Takings by Account
// ===========================================================================

final takingsByAccount = RDef(
  load: (c, r) async => RLoad(await c.list(_fin('/reports/takings-by-account'), _fromTo(r))),
  summary: (r, f) => [
    (label: 'Taken (bills)', value: f.money(sumOf(r.rows, (x) => _n(x, 'takings')))),
    (label: 'Tips', value: f.money(sumOf(r.rows, (x) => _n(x, 'tips')))),
    (label: 'Refunded', value: f.money(sumOf(r.rows, (x) => _n(x, 'refunds')))),
    (label: 'Net received', value: f.money(sumOf(r.rows, (x) => _n(x, 'netTotal')))),
  ],
  panel: (r, f) {
    final byAcct = <String, num>{};
    for (final x in r.rows) {
      byAcct[_s(x, 'accountName')] = (byAcct[_s(x, 'accountName')] ?? 0) + _n(x, 'netTotal');
    }
    final data = [for (final e in byAcct.entries) if (e.value > 0) (e.key, e.value)];
    if (data.isEmpty) return null;
    return reportCard('Share by account', 'Gift-card payments are listed as "No cash moved" — that value came in when the card was sold.',
        shareBars(data, fmt: f.money));
  },
  columns: [
    RCol('acct', 'Account', (r, f) => _s(r, 'accountName')),
    RCol('type', 'Type', (r, f) => restaurantAccountTypeLabels[_s(r, 'accountType')] ?? _s(r, 'accountType'), secondary: true),
    RCol('method', 'Method', (r, f) => _s(r, 'paymentMethod')),
    RCol('n', 'Payments', (r, f) => f.int_(r['paymentCount']), numeric: true, secondary: true),
    RCol('take', 'Taken', (r, f) => f.money(r['takings']), numeric: true),
    RCol('tips', 'Tips', (r, f) => f.money(r['tips']), numeric: true, secondary: true),
    RCol('ref', 'Refunded', (r, f) => f.money(r['refunds']), numeric: true),
    RCol('net', 'Net received', (r, f) => f.money(r['netTotal']), numeric: true),
  ],
  tableTitle: 'Takings by account and method',
  emptyText: 'No payments were taken in this period.',
);

// ===========================================================================
// Profit vs Cash
// ===========================================================================

final profitVsCash = RDef(
  load: (c, r) async => RLoad(await c.list(_fin('/reports/profit-vs-cash'), _fromTo(r))),
  summary: (r, f) {
    num get(String k) => _n(r.rows.firstWhere((x) => _s(x, 'lineKey') == k, orElse: () => const {}), 'amount');
    return [
      (label: 'Net profit', value: f.money(get('net_profit'))),
      (label: 'Net cash flow', value: f.money(get('net_cash'))),
      (label: 'Difference to explain', value: f.money(get('net_cash') - get('net_profit'))),
      (label: 'Unexplained', value: f.money(get('check'))),
    ];
  },
  panel: (r, f) {
    if (r.rows.isEmpty) return null;
    final visible = [for (final x in r.rows) if (_s(x, 'kind') != 'adjust' || _n(x, 'amount') != 0) x];
    return reportCard(
      'From profit to cash',
      'Start at the profit the P&L reports; each line is a reason cash moved by a different amount.',
      Column(children: [
        for (final x in visible)
          Builder(builder: (_) {
            final kind = _s(x, 'kind'), amt = _n(x, 'amount');
            final strong = kind == 'start' || kind == 'result';
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: TColors.slate200))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_s(x, 'label'),
                        style: TextStyle(
                            fontSize: kind == 'check' ? 12 : 13,
                            fontWeight: strong ? FontWeight.w600 : null,
                            color: kind == 'check' ? TColors.slate500 : null)),
                    if (kind == 'adjust' && _s(x, 'explanation').isNotEmpty)
                      Text(_s(x, 'explanation'), style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                  ]),
                ),
                const SizedBox(width: 8),
                Text('${kind == 'adjust' && amt > 0 ? '+' : ''}${f.money(amt)}',
                    style: TextStyle(
                      fontSize: kind == 'check' ? 12 : 13,
                      fontWeight: strong ? FontWeight.w600 : null,
                      color: amt < 0 ? rose700 : (kind == 'adjust' ? emerald700 : (kind == 'check' ? TColors.slate500 : null)),
                    )),
              ]),
            );
          }),
      ]),
    );
  },
  columns: [
    RCol('line', 'Line', (r, f) => _s(r, 'label')),
    RCol('amt', 'Amount', (r, f) => f.money(r['amount']), numeric: true),
    RCol('why', 'Why', (r, f) => _s(r, 'explanation'), secondary: true),
  ],
  tableTitle: 'Every line of the bridge',
  emptyText: 'Nothing happened in this period.',
);

// ===========================================================================
// Payroll (326): runs PAID in the period, per staff member.
// ===========================================================================

final payrollReport = RDef(
  load: (c, r) async => RLoad(await c.list('/api/Restaurant/payroll/report', _fromTo(r))),
  summary: (r, f) => [
    (label: 'Gross wages (P&L)', value: f.money(sumOf(r.rows, (x) => _n(x, 'grossPay')))),
    (label: 'Net pay (cash out)', value: f.money(sumOf(r.rows, (x) => _n(x, 'netPay')))),
    (label: 'Staff loan repayments', value: f.money(sumOf(r.rows, (x) => _n(x, 'loanDeductions')))),
    (label: 'Staff paid', value: f.int_(r.rows.length)),
  ],
  columns: [
    RCol('s', 'Staff', (r, f) => _s(r, 'staffName').isEmpty ? '—' : _s(r, 'staffName')),
    RCol('role', 'Role', (r, f) => _s(r, 'staffRole'), secondary: true),
    RCol('runs', 'Runs', (r, f) => f.int_(r['runs']), numeric: true, secondary: true),
    RCol('basic', 'Basic', (r, f) => f.money(r['basicPay']), numeric: true, secondary: true),
    RCol('extra', 'Allowances, overtime & bonus', (r, f) => f.money(r['extras']), numeric: true, secondary: true),
    RCol('gross', 'Gross', (r, f) => f.money(r['grossPay']), numeric: true),
    RCol('other', 'Other deductions', (r, f) => f.money(r['otherDeductions']), numeric: true, secondary: true),
    RCol('loan', 'Loan repayments', (r, f) => f.money(r['loanDeductions']), numeric: true),
    RCol('net', 'Net pay', (r, f) => f.money(r['netPay']), numeric: true),
  ],
  tableTitle: 'Wages paid, by staff member',
  tableHint: 'Only payroll runs marked Paid, by pay date.',
  emptyText: 'No payroll was paid in this period. Pay staff from Money → Payroll.',
);

// ===========================================================================
// Employee Loans & Advances (326)
// ===========================================================================

final staffLoansReport = RDef(
  load: (c, r) async => RLoad(await c.list('/api/Restaurant/staff-loans/staff-report', _fromTo(r))),
  summary: (r, f) => [
    (label: 'Owed by staff now', value: f.money(sumOf(r.rows, (x) => _n(x, 'outstanding')))),
    (label: 'Advanced in period', value: f.money(sumOf(r.rows, (x) => _n(x, 'disbursedInPeriod')))),
    (label: 'Repaid in period', value: f.money(sumOf(r.rows, (x) => _n(x, 'repaidCashInPeriod') + _n(x, 'repaidPayrollInPeriod')))),
    (label: 'Staff owing', value: f.int_(r.rows.where((x) => _n(x, 'outstanding') > 0).length)),
  ],
  columns: [
    RCol('s', 'Staff', (r, f) => (_s(r, 'staffName').isEmpty ? '—' : _s(r, 'staffName')) + (r['staffIsActive'] == true ? '' : ' (inactive)')),
    RCol('role', 'Role', (r, f) => _s(r, 'role'), secondary: true),
    RCol('act', 'Active loans', (r, f) => f.int_(r['activeLoans']), numeric: true, secondary: true),
    RCol('owed', 'Owed now', (r, f) => f.money(r['outstanding']), numeric: true),
    RCol('adv', 'Advanced', (r, f) => f.money(r['disbursedInPeriod']), numeric: true),
    RCol('cash', 'Repaid in cash', (r, f) => f.money(r['repaidCashInPeriod']), numeric: true, secondary: true),
    RCol('pay', 'Repaid via payroll', (r, f) => f.money(r['repaidPayrollInPeriod']), numeric: true, secondary: true),
    RCol('int', 'Interest', (r, f) => f.money(r['interestInPeriod']), numeric: true, secondary: true),
    RCol('last', 'Last repayment', (r, f) => d10(r['lastRepaymentDate']).isEmpty ? '—' : d10(r['lastRepaymentDate']), secondary: true),
  ],
  tableTitle: 'Staff loans and advances',
  tableHint: "Owed now is today's balance; the other amounts are for the selected dates.",
  emptyText: 'No staff loans or advances yet.',
);

/// The ledger half of REPORT_REGISTRY.
final restaurantMoneyReportDefs = <String, RDef>{
  'profit-vs-cash': profitVsCash,
  'payroll': payrollReport,
  'staff-loans': staffLoansReport,
  'cash-flow-detail': cashFlowDetail,
  'cash-movement': cashMovement,
  'cash-accounts': cashAccounts,
  'money-movement': moneyMovement,
  'takings-by-account': takingsByAccount,
  'till-variances': tillVariances,
  'closing-report': closingReport,
};
