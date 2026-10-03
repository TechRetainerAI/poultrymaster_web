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
import 'report_export.dart';
import 'report_format.dart';
import 'report_routes.dart';
import 'report_shell.dart';
import 'report_widgets.dart';
import 'reports_catalog_screen.dart';

num _n(Object? v) => toNum(v);
num _r2(num n) => (n * 100).round() / 100;
String _day(Object? v) => '${v ?? ''}'.length >= 10 ? '${v ?? ''}'.substring(0, 10) : '${v ?? ''}';

// =========================================================================
// Cash Account Report
// =========================================================================

const _cashTypes = ['factorycashbox', 'farmcashbox', 'ownercash', 'pettycash', 'drivercash', 'cash'];

/// cashAccountVocabulary(...).emptyHistory.
String emptyHistory(Object? accountType) {
  final t = '${accountType ?? ''}'.trim().toLowerCase();
  if (t == 'bankaccount' || t == 'bank') return 'This account has never been reconciled against a statement.';
  if (t == 'momowallet' || t == 'momo') return 'This account has never been reconciled against MoMo.';
  if (_cashTypes.contains(t)) return 'This account has never been counted.';
  return 'This account has never been reconciled.';
}

/// One account over the period (cashAccountsForPeriod).
class CashAccountRow {
  CashAccountRow({
    required this.accountId,
    required this.accountName,
    this.accountType,
    required this.isActive,
    required this.ledgerBalance,
    required this.cacheDrift,
    this.lastReconciledAt,
    this.daysSinceReconciled,
    required this.unclearedCount,
    required this.openingBalance,
    required this.periodIn,
    required this.periodOut,
  });
  final int accountId;
  final String accountName;
  final String? accountType;
  final bool isActive;
  final num ledgerBalance, cacheDrift;
  final String? lastReconciledAt;
  final num? daysSinceReconciled;
  final num unclearedCount;
  final num openingBalance, periodIn, periodOut;
  num sharePercent = 0;
  num get closingBalance => _r2(openingBalance + periodIn - periodOut);

  String? get attentionReason {
    if (cacheDrift.abs() >= 0.01) return 'Stored balance disagrees with its transactions';
    if (lastReconciledAt == null) return 'Never reconciled';
    if ((daysSinceReconciled ?? 0) > 30) return 'Not reconciled in ${fmtNum(daysSinceReconciled!, 0)} days';
    return null;
  }

  bool get needsAttention => attentionReason != null;

  /// accountStatusText: the one-line verdict, worded by account type.
  String status(FarmMoney m) {
    if (cacheDrift.abs() >= 0.01) return 'Stored balance off by ${m(cacheDrift.abs())}';
    if (lastReconciledAt == null) return emptyHistory(accountType);
    if (needsAttention) return attentionReason!;
    return 'Reconciled ${fmtNum(daysSinceReconciled ?? 0, 0)}d ago';
  }
}

/// cashAccountsForPeriod: union the accounts with their status rows, split
/// the ledger (everything up to [to]) at [from], and share by closing cash.
List<CashAccountRow> cashAccountsForPeriod(List<Map> accounts, List<Map> status, List<Map> entries, String from, String to) {
  final seed = {for (final a in accounts) _n(a['poultryCashAccountId']).toInt(): a};
  final st = {for (final s in status) _n(s['poultryCashAccountId']).toInt(): s};
  final ids = {...seed.keys, ...st.keys};
  final acc = <int, (num prior, num inn, num out)>{};
  for (final e in entries) {
    final amount = _n(e['amount']);
    if (amount == 0) continue;
    final day = _day(e['transactionDate']);
    if (day.isEmpty) continue;
    final id = _n(e['poultryCashAccountId']).toInt();
    final b = acc[id] ?? (0, 0, 0);
    if (day.compareTo(from) < 0) {
      acc[id] = (b.$1 + amount, b.$2, b.$3);
    } else if (day.compareTo(to) <= 0) {
      acc[id] = amount > 0 ? (b.$1, b.$2 + amount, b.$3) : (b.$1, b.$2, b.$3 - amount);
    }
  }
  final rows = [
    for (final id in ids)
      () {
        final s = st[id];
        final a = seed[id];
        final b = acc[id] ?? (0, 0, 0);
        return CashAccountRow(
          accountId: id,
          accountName: '${s?['accountName'] ?? a?['accountName'] ?? 'Account #$id'}',
          accountType: (s?['accountType'] ?? a?['accountType'])?.toString(),
          isActive: (s?['isActive'] ?? a?['isActive']) != false,
          ledgerBalance: _n(s?['ledgerBalance']),
          cacheDrift: _n(s?['cacheDrift']),
          lastReconciledAt: s?['lastReconciledAt']?.toString(),
          daysSinceReconciled: s?['daysSinceReconciled'] == null ? null : _n(s!['daysSinceReconciled']),
          unclearedCount: _n(s?['unclearedCount']),
          openingBalance: _r2(_n(a?['openingBalance']) + b.$1),
          periodIn: _r2(b.$2),
          periodOut: _r2(b.$3),
        );
      }(),
  ];
  final total = rows.fold<num>(0, (s, r) => s + r.closingBalance);
  for (final r in rows) {
    r.sharePercent = total > 0 ? _r2(r.closingBalance / total * 100) : 0;
  }
  rows.sort((a, b) {
    final c = b.closingBalance.compareTo(a.closingBalance);
    return c != 0 ? c : a.accountName.compareTo(b.accountName);
  });
  return rows;
}

class CashAccountReportScreen extends StatefulWidget {
  const CashAccountReportScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<CashAccountReportScreen> createState() => _CashAccountReportScreenState();
}

class _CashAccountReportScreenState extends State<CashAccountReportScreen> {
  late String _from = defaultReportRange().from, _to = defaultReportRange().to;
  List<CashAccountRow> _rows = [];
  List<Map> _entries = [];
  List<Map> _transfers = [];
  bool _busy = true;
  String? _error;
  String _account = 'ALL';
  FarmMoney _money = const FarmMoney();

  ApiClient get _c => widget.session.farmClient;
  String get _farm => widget.company.farmId;

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _money = m);
    });
    _load();
  }

  Future<(List<Map>?, ApiException?)> _try(String path, Map<String, String> q) async {
    try {
      return ([for (final r in LookupLoader.rowsIn(await _c.get(path, query: q))) if (r is Map) r], null);
    } on ApiException catch (e) {
      return (null, e);
    }
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await Future.wait([
      _try('/api/Poultry/cash-accounts', {'farmId': _farm}),
      _try('/api/Poultry/cash-reconciliations/account-status', {'farmId': _farm}),
      // No fromDate: everything up to the period end, so the earlier rows
      // become each account's opening balance.
      _try('/api/Poultry/cash-accounts/transactions', {'farmId': _farm, 'toDate': '${_to}T23:59:59.999'}),
      _try('/api/Poultry/cash-transfers', {'farmId': _farm}),
    ]);
    if (!mounted) return;
    if (r[0].$1 == null && r[2].$1 == null) {
      setState(() {
        _error = r[0].$2?.message ?? 'Could not load the cash accounts.';
        _rows = [];
        _entries = [];
        _transfers = [];
        _busy = false;
      });
      return;
    }
    final all = r[2].$1 ?? [];
    setState(() {
      _rows = cashAccountsForPeriod(r[0].$1 ?? [], r[1].$1 ?? [], all, _from, _to);
      _entries = [
        for (final e in all)
          if (_day(e['transactionDate']).isNotEmpty &&
              _day(e['transactionDate']).compareTo(_from) >= 0 &&
              _day(e['transactionDate']).compareTo(_to) <= 0)
            e,
      ];
      _transfers = r[3].$1 ?? [];
      _busy = false;
    });
  }

  ({num opening, num moneyIn, num moneyOut, num closing}) get _totals => (
        opening: _r2(_rows.fold<num>(0, (s, r) => s + r.openingBalance)),
        moneyIn: _r2(_rows.fold<num>(0, (s, r) => s + r.periodIn)),
        moneyOut: _r2(_rows.fold<num>(0, (s, r) => s + r.periodOut)),
        closing: _r2(_rows.fold<num>(0, (s, r) => s + r.closingBalance)),
      );

  static const _accountColumns = [
    ReportColumn('Account'),
    ReportColumn('Type'),
    ReportColumn('Opening', right: true),
    ReportColumn('In', right: true),
    ReportColumn('Out', right: true),
    ReportColumn('Closing', right: true),
    ReportColumn('Share', right: true),
    ReportColumn('Status (as of today)'),
  ];

  List<String> _accountRow(CashAccountRow r, {bool uncleared = true}) => [
        r.isActive ? r.accountName : '${r.accountName} (inactive)',
        r.accountType ?? '—',
        _money(r.openingBalance),
        r.periodIn != 0 ? _money(r.periodIn) : '—',
        r.periodOut != 0 ? _money(r.periodOut) : '—',
        _money(r.closingBalance),
        '${r.sharePercent.toStringAsFixed(1)}%',
        r.status(_money) + (uncleared && r.unclearedCount > 0 ? ' · ${fmtNum(r.unclearedCount, 0)} uncleared' : ''),
      ];

  ReportDocument _document() {
    final t = _totals;
    final balances = (_r2(t.opening + t.moneyIn - t.moneyOut) - t.closing).abs() < 0.01;
    return ReportDocument(
      title: 'Poultry Cash Account Report',
      filename: 'poultry-cash-accounts',
      farmName: widget.company.name,
      landscape: true,
      cards: [
        (label: 'Opening', value: _money(t.opening), accent: null, note: 'Start of period'),
        (label: 'Money in', value: _money(t.moneyIn), accent: 'green', note: null),
        (label: 'Money out', value: _money(t.moneyOut), accent: 'rose', note: null),
        (label: 'Closing', value: _money(t.closing), accent: 'indigo', note: 'End of period'),
        (
          label: 'Accounts needing attention',
          value: '${_rows.where((r) => r.needsAttention).length}',
          accent: null,
          note: 'As of today, not of the period',
        ),
      ],
      sections: [
        ReportSection(
          columns: _accountColumns,
          rows: [for (final r in _rows) _accountRow(r, uncleared: false)],
          totals: [
            'All accounts', '', _money(t.opening), _money(t.moneyIn), _money(t.moneyOut), _money(t.closing), '100.0%',
            balances ? '' : 'Totals do not balance',
          ],
        ),
      ],
    );
  }

  void _link(String href, String label) => openAppHref(context, widget.session, widget.company, href, label: label);

  @override
  Widget build(BuildContext context) {
    final t = _totals;
    final implied = _r2(t.opening + t.moneyIn - t.moneyOut);
    final discrepancy = _r2(implied - t.closing);
    final selected = _account == 'ALL' ? null : int.tryParse(_account);
    // Running balance only for one account, from its own opening figure.
    final asc = [
      for (final e in _entries)
        if (selected == null || _n(e['poultryCashAccountId']).toInt() == selected) e,
    ]..sort((a, b) {
        final d = '${a['transactionDate'] ?? ''}'.compareTo('${b['transactionDate'] ?? ''}');
        return d != 0 ? d : _n(a['poultryCashTransactionId']).compareTo(_n(b['poultryCashTransactionId']));
      });
    final running = <num?>[];
    var bal = selected == null ? 0 : (_rows.where((r) => r.accountId == selected).firstOrNull?.openingBalance ?? 0);
    for (final e in asc) {
      bal = _r2(bal + _n(e['amount']));
      running.add(selected == null ? null : bal);
    }
    final ledger = asc.reversed.toList();
    final ledgerRunning = running.reversed.toList();
    final transfers = [
      for (final x in _transfers)
        if (() {
          final d = _day(x['transferDate']);
          return d.isEmpty || (d.compareTo(_from) >= 0 && d.compareTo(_to) <= 0);
        }())
          x,
    ]..sort((a, b) => '${b['transferDate'] ?? ''}'.compareTo('${a['transferDate'] ?? ''}'));
    final approved = transfers.where((x) => x['status'] == 'Approved');
    final pending = transfers.where((x) => x['status'] == 'Draft').length;
    final attention = _rows.where((r) => r.needsAttention).length;
    final uncleared = _rows.fold<num>(0, (s, r) => s + r.unclearedCount);

    return ReportShellScreen(
      session: widget.session,
      company: widget.company,
      href: '/poultry/reports/cash-accounts',
      title: 'Cash Account Report',
      description: 'Where your money sits, what moved through each account, and which accounts need attention.',
      busy: _busy,
      error: _error,
      onClearError: () => setState(() => _error = null),
      fromDate: _from,
      toDate: _to,
      onRangeChanged: (f, to) {
        setState(() {
          _from = f;
          _to = to;
        });
        _load();
      },
      recordCount: _rows.length,
      onRefresh: _load,
      document: _document,
      tiles: [
        (label: 'Cash at hand', value: _money(_r2(_rows.fold<num>(0, (s, r) => s + r.ledgerBalance))), accent: 'indigo', note: null),
        (label: 'Money in', value: _money(t.moneyIn), accent: 'green', note: null),
        (label: 'Money out', value: _money(t.moneyOut), accent: 'rose', note: null),
        (label: 'Accounts', value: '${_rows.length}', accent: null, note: null),
        (label: 'Need attention', value: '$attention', accent: attention > 0 ? 'rose' : null, note: null),
        (label: 'Uncleared items', value: fmtNum(uncleared, 0), accent: null, note: null),
      ],
      body: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: slate50, border: Border.all(color: slate200), borderRadius: BorderRadius.circular(6)),
          child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Text('These figures come from the cash-account ledger — what each account holds. They are ',
                style: TextStyle(fontSize: 12, color: slate600)),
            const Text('not', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: slate600)),
            const Text(' expected to match ', style: TextStyle(fontSize: 12, color: slate600)),
            InkWell(
              onTap: () => _link('/cash-flow', 'Cash Flow'),
              child: const Text('Cash Flow', style: TextStyle(fontSize: 12, color: slate600, decoration: TextDecoration.underline)),
            ),
            const Text(', which is built from sales, expenses and capital and reads no account at all. Where the two disagree, ',
                style: TextStyle(fontSize: 12, color: slate600)),
            InkWell(
              onTap: () => _link('/poultry-cash-reconciliation', 'Cash reconciliation'),
              child: const Text('reconciliation', style: TextStyle(fontSize: 12, color: slate600, decoration: TextDecoration.underline)),
            ),
            const Text(' is the answer.', style: TextStyle(fontSize: 12, color: slate600)),
          ]),
        ),
        const ShellHeading('Where the money sits'),
        ShellCards(
          columns: _accountColumns,
          rows: [for (final r in _rows) _accountRow(r)],
          empty: 'No cash accounts yet.',
          valueColor: (ri, ci) => switch (ci) {
            3 => emerald700,
            4 => rose700,
            5 => _rows[ri].closingBalance < 0 ? rose700 : null,
            7 => _rows[ri].needsAttention ? amber800 : slate500,
            _ => _rows[ri].isActive ? null : slate500,
          },
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: slate200), borderRadius: BorderRadius.circular(8)),
          child: Text.rich(TextSpan(style: const TextStyle(fontSize: 12, color: slate600), children: [
            const TextSpan(text: 'Opening '),
            TextSpan(text: _money(t.opening), style: const TextStyle(fontWeight: FontWeight.w700, color: slate900)),
            TextSpan(text: '  + in ', style: const TextStyle(color: emerald700)),
            TextSpan(text: _money(t.moneyIn), style: const TextStyle(fontWeight: FontWeight.w700, color: emerald700)),
            TextSpan(text: '  − out ', style: const TextStyle(color: rose700)),
            TextSpan(text: _money(t.moneyOut), style: const TextStyle(fontWeight: FontWeight.w700, color: rose700)),
            const TextSpan(text: '  = closing '),
            TextSpan(text: _money(t.closing), style: const TextStyle(fontWeight: FontWeight.w700, color: slate900)),
            if (discrepancy.abs() >= 0.01) ...[
              const TextSpan(text: ' — off by ', style: TextStyle(color: rose700)),
              TextSpan(text: _money(discrepancy.abs()), style: const TextStyle(fontWeight: FontWeight.w700, color: rose700)),
            ],
          ])),
        ),
        const ShellHeading('Ledger'),
        AppSelect<String>(
          value: _account,
          items: [
            const AppSelectItem(value: 'ALL', label: 'All accounts'),
            for (final r in _rows) AppSelectItem(value: '${r.accountId}', label: '${r.accountName}${r.isActive ? '' : ' (inactive)'}'),
          ],
          onChanged: (v) => setState(() => _account = v ?? 'ALL'),
        ),
        const SizedBox(height: 8),
        ShellCards(
          columns: const [
            ReportColumn('Date'),
            ReportColumn('Account'),
            ReportColumn('Source'),
            ReportColumn('Description'),
            ReportColumn('In', right: true),
            ReportColumn('Out', right: true),
            ReportColumn('Balance', right: true),
          ],
          rows: [
            for (final (i, e) in ledger.indexed)
              [
                _day(e['transactionDate']),
                '${e['accountName'] ?? '—'}',
                categoryLabel(e['sourceType']),
                '${e['description'] ?? '—'}',
                _n(e['amount']) > 0 ? _money(_n(e['amount'])) : '—',
                _n(e['amount']) < 0 ? _money(-_n(e['amount'])) : '—',
                ledgerRunning[i] == null ? '—' : _money(ledgerRunning[i]!),
              ],
          ],
          empty: 'Nothing moved through ${selected == null ? 'any account' : 'this account'} in this period.',
          valueColor: (r, c) => c == 4 ? emerald700 : c == 5 ? rose700 : null,
        ),
        const ShellHeading('Transfers between your own accounts'),
        Text(
          '${approved.length} approved moving ${_money(_r2(approved.fold<num>(0, (s, x) => s + _n(x['amount']).abs())))}'
          '${pending > 0 ? ', $pending still pending' : ''}. These are not income or spending — the money never left the business — so they are excluded from Cash Flow.',
          style: const TextStyle(fontSize: 12, color: slate500),
        ),
        const SizedBox(height: 8),
        ShellCards(
          columns: const [ReportColumn('Date'), ReportColumn('From'), ReportColumn('To'), ReportColumn('Amount', right: true), ReportColumn('Status')],
          rows: [
            for (final x in transfers)
              [_day(x['transferDate']), '${x['fromAccountName'] ?? '—'}', '${x['toAccountName'] ?? '—'}', _money(_n(x['amount']).abs()), '${x['status'] ?? ''}'],
          ],
          empty: 'No transfers in this period.',
          valueColor: (r, c) => c != 4
              ? null
              : transfers[r]['status'] == 'Approved'
                  ? emerald700
                  : transfers[r]['status'] == 'Draft'
                      ? slate700
                      : amber800,
        ),
      ],
    );
  }
}

// =========================================================================
// Money Movement
// =========================================================================

/// /poultry/reports/money: cash transfers, owner money, loans and loan
/// repayments — none of it income or expense except interest and fees.
class MoneyMovementScreen extends StatefulWidget {
  const MoneyMovementScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<MoneyMovementScreen> createState() => _MoneyMovementScreenState();
}

class _MoneyMovementScreenState extends State<MoneyMovementScreen> {
  // Month start to today, as the web.
  String _from = isoDay(DateTime(DateTime.now().year, DateTime.now().month, 1));
  String _to = isoDay(DateTime.now());
  bool _loading = true;
  List<Map> _transfers = [], _owner = [], _loans = [], _repayments = [];
  FarmMoney _money = const FarmMoney();
  Duration _offset = Duration.zero;

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
    final q = {'farmId': widget.company.farmId};
    Future<List<Map>> list(String p) async =>
        [for (final r in LookupLoader.rowsIn(await widget.session.farmClient.get(p, query: q))) if (r is Map) r];
    try {
      final r = await Future.wait([
        list('/api/Poultry/cash-transfers'),
        list('/api/Poultry/owner-money'),
        list('/api/Poultry/loans'),
        list('/api/Poultry/loan-payments'),
      ]);
      if (mounted) {
        setState(() {
          _transfers = r[0];
          _owner = r[1];
          _loans = r[2];
          _repayments = r[3];
        });
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load the report. ${e.message}')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _in(Object? iso) {
    final d = _day(iso);
    return d.isNotEmpty && d.compareTo(_from) >= 0 && d.compareTo(_to) <= 0;
  }

  /// fmtDateTime: the business date plus the time it was entered.
  String _when(Object? date, Map row) {
    final k = toBusinessDate(date);
    if (k == null) return '';
    final p = k.split('-');
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final d = '${int.parse(p[2])} ${m[int.parse(p[1]) - 1]} ${p[0]}';
    for (final c in ['createdDate', 'createdAt', 'dateCreated', 'createdOn']) {
      final v = row[c];
      if (v is String && v.trim().isNotEmpty) {
        final full = fmtInstant(v, _offset);
        final at = full.lastIndexOf(', ');
        if (at > 0) return '$d, ${full.substring(at + 2)}';
      }
    }
    return d;
  }

  num _sum(Iterable<Map> xs, String k) => xs.fold<num>(0, (t, x) => t + _n(x[k]));

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry/reports/money');
    final xf = [for (final r in _transfers) if (_in(r['transferDate'])) r];
    final om = [for (final r in _owner) if (_in(r['transactionDate'])) r];
    final rp = [for (final r in _repayments) if (_in(r['paymentDate'])) r];
    final xfLive = xf.where((r) => r['status'] == 'Approved');
    final omLive = om.where((r) => r['status'] == 'Posted');
    final rpLive = rp.where((r) => r['status'] == 'Posted');
    final contributions = _sum(omLive.where((r) => r['transactionType'] == 'Contribution'), 'amount');
    final draws = _sum(omLive.where((r) => r['transactionType'] == 'Draw'), 'amount');
    final liveLoans = [for (final l in _loans) if (l['status'] != 'Cancelled') l];

    return Scaffold(
      backgroundColor: slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Money Movement')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: slate500, padding: EdgeInsets.zero),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PoultryReportsCatalogScreen(session: widget.session, company: widget.company),
                )),
                icon: const Icon(Icons.arrow_back, size: 14),
                label: const Text('Back to reports', style: TextStyle(fontSize: 13)),
              ),
            ),
            const Row(children: [
              Icon(Icons.account_balance_wallet_outlined, color: Color(0xFF7C3AED)),
              SizedBox(width: 8),
              Text('Money Movement', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600, color: slate900)),
            ]),
            const SizedBox(height: 4),
            const Text.rich(TextSpan(style: TextStyle(fontSize: 13, color: slate500), children: [
              TextSpan(text: "Transfers between the farm's own accounts, money the owner put in or took out, and borrowed money. "),
              TextSpan(text: 'None of this is income or expense', style: TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: ' — except the interest and fees on a repayment, which are the only part that reaches the profit and loss.'),
            ])),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: slate200), borderRadius: BorderRadius.circular(10)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: _date('From', _from, (v) => setState(() => _from = v))),
                  const SizedBox(width: 8),
                  Expanded(child: _date('To', _to, (v) => setState(() => _to = v))),
                ]),
                const SizedBox(height: 10),
                AppButton(label: 'Refresh', variant: AppButtonVariant.outline, busy: _loading, onPressed: _loading ? null : _load),
              ]),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Row(children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 8),
                Text('Loading…', style: TextStyle(color: slate500)),
              ])
            else ...[
              _Section(
                icon: Icons.swap_horiz,
                title: 'Cash transfers',
                note: "Moving money between the farm's own accounts. Never company-wide money in or money out — the same money is simply in a different box.",
                tiles: [
                  ('Moved', _money(_sum(xfLive, 'amount')), null),
                  ('Transfers', '${xfLive.length}', null),
                  ('Reversed', '${xf.where((r) => r['status'] == 'Reversed').length}', null),
                ],
                empty: xf.isEmpty ? 'No transfers in this period.' : null,
                child: ShellCards(
                  columns: const [
                    ReportColumn('Date'), ReportColumn('Transfer #'), ReportColumn('From'), ReportColumn('To'),
                    ReportColumn('Amount', right: true), ReportColumn('Status'),
                  ],
                  rows: [
                    for (final r in xf)
                      [
                        _when(r['transferDate'], r),
                        '${r['transferNumber'] ?? '#${r['poultryCashTransferId']}'}',
                        '${r['fromAccountName'] ?? '–'}',
                        '→ ${r['toAccountName'] ?? '–'}',
                        _money(_n(r['amount'])),
                        '${r['status'] ?? ''}',
                      ],
                  ],
                  struck: (r, c) => c == 4 && xf[r]['status'] == 'Reversed',
                  valueColor: (r, c) => c == 5 ? _statusColor('${xf[r]['status']}') : null,
                ),
              ),
              _Section(
                icon: Icons.account_balance_wallet_outlined,
                title: 'Owner money',
                note: 'What the owner put in and took out. A contribution is not revenue and a draw is not an expense — neither touches profit.',
                tiles: [
                  ('Contributions', _money(contributions), const Color(0xFF047857)),
                  ('Draws', _money(draws), const Color(0xFFC2410C)),
                  ('Net funding', _money(contributions - draws), contributions - draws >= 0 ? const Color(0xFF047857) : const Color(0xFFE11D48)),
                ],
                empty: om.isEmpty ? 'No owner money in this period.' : null,
                child: ShellCards(
                  columns: const [
                    ReportColumn('Date'), ReportColumn('Number'), ReportColumn('Owner'), ReportColumn('Type'),
                    ReportColumn('Account'), ReportColumn('Amount', right: true), ReportColumn('Status'),
                  ],
                  rows: [
                    for (final r in om)
                      [
                        _when(r['transactionDate'], r),
                        '${r['transactionNumber'] ?? '#${r['poultryOwnerMoneyId']}'}',
                        '${r['ownerName'] ?? '–'}',
                        '${r['transactionType'] ?? ''}',
                        '${r['accountName'] ?? '–'}',
                        '${r['transactionType'] == 'Draw' ? '−' : '+'}${_money(_n(r['amount']))}',
                        '${r['status'] ?? ''}',
                      ],
                  ],
                  struck: (r, c) => c == 5 && om[r]['status'] == 'Reversed',
                  valueColor: (r, c) => c == 6 ? _statusColor('${om[r]['status']}') : null,
                ),
              ),
              _Section(
                icon: Icons.payments_outlined,
                title: 'Loans',
                note: 'Borrowed money. Receiving it is not income, and the debt is what was borrowed — which can exceed what arrived if the lender withheld a fee.',
                tiles: [
                  ('Still owed', _money(_sum(liveLoans, 'outstandingPrincipal')), const Color(0xFF6D28D9)),
                  ('Borrowed', _money(_sum(liveLoans, 'originalPrincipal')), null),
                  ('Received', _money(_sum(liveLoans, 'amountReceived')), null),
                  ('Principal repaid', _money(_sum(liveLoans, 'totalPrincipalRepaid')), const Color(0xFF047857)),
                ],
                empty: _loans.isEmpty ? 'No loans on record.' : null,
                footnote: 'Loan totals are as they stand today, not sliced by the period — an outstanding balance is a position, not a flow.',
                child: ShellCards(
                  columns: const [
                    ReportColumn('Loan #'), ReportColumn('Lender'), ReportColumn('Borrowed', right: true),
                    ReportColumn('Received', right: true), ReportColumn('Repaid', right: true), ReportColumn('Still owed', right: true),
                    ReportColumn('Interest', right: true), ReportColumn('Fees', right: true), ReportColumn('Status'),
                  ],
                  rows: [
                    for (final l in _loans)
                      [
                        '${l['loanNumber'] ?? '#${l['poultryLoanId']}'}',
                        '${l['lenderName'] ?? (l['source'] == 'CashAdjustment' ? 'Recorded on Cash Flow' : '–')}',
                        _money(_n(l['originalPrincipal'])),
                        _money(_n(l['amountReceived'])),
                        _money(_n(l['totalPrincipalRepaid'])),
                        _money(_n(l['outstandingPrincipal'])),
                        _money(_n(l['totalInterestPaid'])),
                        _money(_n(l['totalFeesPaid'])),
                        l['isOverdue'] == true ? 'Overdue' : '${l['status'] ?? ''}',
                      ],
                  ],
                  valueColor: (r, c) => c == 6 || c == 7
                      ? amber700
                      : c == 8
                          ? _statusColor(_loans[r]['isOverdue'] == true ? 'Overdue' : '${_loans[r]['status']}')
                          : null,
                ),
              ),
              _Section(
                icon: Icons.payments_outlined,
                title: 'Loan repayments',
                note: 'What left the bank, and what it was for. Only the interest and fee columns are an expense — the principal column is the farm reducing a debt.',
                tiles: [
                  ('Total paid', _money(_sum(rpLive, 'totalAmount')), null),
                  ('Of which principal', _money(_sum(rpLive, 'principalAmount')), null),
                  ('Cost of borrowing', _money(_sum(rpLive, 'interestAmount') + _sum(rpLive, 'feeAmount')), amber700),
                ],
                empty: rp.isEmpty ? 'No repayments in this period.' : null,
                child: ShellCards(
                  columns: const [
                    ReportColumn('Date'), ReportColumn('Payment #'), ReportColumn('Lender'), ReportColumn('Principal', right: true),
                    ReportColumn('Interest', right: true), ReportColumn('Fees', right: true), ReportColumn('Total paid', right: true),
                    ReportColumn('Account'), ReportColumn('Status'),
                  ],
                  rows: [
                    for (final r in rp)
                      [
                        _when(r['paymentDate'], r),
                        '${r['paymentNumber'] ?? '#${r['poultryLoanPaymentId']}'}',
                        '${r['lenderName'] ?? '–'}',
                        _money(_n(r['principalAmount'])),
                        _money(_n(r['interestAmount'])),
                        _money(_n(r['feeAmount'])),
                        _money(_n(r['totalAmount'])),
                        '${r['accountName'] ?? '–'}',
                        '${r['status'] ?? ''}',
                      ],
                  ],
                  struck: (r, c) => c == 6 && rp[r]['status'] == 'Reversed',
                  valueColor: (r, c) => c == 4 || c == 5
                      ? amber700
                      : c == 8
                          ? _statusColor('${rp[r]['status']}')
                          : null,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static Color _statusColor(String s) => switch (s) {
        'Reversed' || 'Cancelled' => slate700,
        'Overdue' => const Color(0xFF9F1239),
        'PaidOff' => const Color(0xFF065F46),
        _ => const Color(0xFF075985),
      };

  Widget _date(String label, String value, void Function(String) set) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        AppDateField(
          value: businessDateAsDateTime(value),
          firstDate: DateTime(2000),
          onChanged: (d) {
            if (d != null) set(isoDay(d));
          },
        ),
      ]);
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.note,
    required this.tiles,
    required this.empty,
    required this.child,
    this.footnote,
  });
  final IconData icon;
  final String title, note;
  final List<(String, String, Color?)> tiles;
  final String? empty;
  final String? footnote;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: slate200), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 20, color: slate500)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: slate900)),
                Text(note, style: const TextStyle(fontSize: 12, color: slate500)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          twoColumns(gap: 8, [
            for (final (label, value, color) in tiles)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: slate50, border: Border.all(color: slate200), borderRadius: BorderRadius.circular(6)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, letterSpacing: .4, color: slate500)),
                  Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color ?? slate900)),
                ]),
              ),
          ]),
          const SizedBox(height: 12),
          if (empty != null)
            Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text(empty!, style: const TextStyle(fontSize: 13, color: slate500)))
          else
            child,
          if (footnote != null)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(footnote!, style: const TextStyle(fontSize: 12, color: slate400))),
        ]),
      );
}
