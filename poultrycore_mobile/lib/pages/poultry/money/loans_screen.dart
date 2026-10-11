import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../shared/business_dates.dart';
import '../../shared/company_clock.dart';
import '../reports/report_format.dart';
import '../reports/report_routes.dart' show openAppHref;
import '../sales/balances_logic.dart' show pageSlice;
import '../sales/balances_widgets.dart';
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../trackers/tracker_widgets.dart';
import 'loan_repayment_dialog.dart';
import 'money_widgets.dart';

/// Poultry → Money → Loans (Financing), as `app/poultry-loans/page.tsx`: who
/// lent the farm money, what is still owed, and what each repayment was made
/// of. Borrowing is not income; repaying principal is not an expense.

const lenderTypes = ['Bank', 'FinancialInstitution', 'Individual', 'Owner', 'FamilyFriend', 'Supplier', 'Other'];
const interestTypes = ['Simple', 'ReducingBalance', 'Flat', 'Unknown'];
const loanFrequencies = ['Weekly', 'BiWeekly', 'Monthly', 'Quarterly', 'Custom'];
const loanStatusFilters = ['All', 'Active', 'PaidOff', 'Draft', 'Cancelled'];

const _violet600 = Color(0xFF7C3AED);
const _violet700 = Color(0xFF6D28D9);

/// A "Loan received" typed on the Cash / Cash Flow page: no loan record behind it.
bool isFromCashFlow(Map l) => tStr(l['source']) == 'CashAdjustment';

/// What the Lender cell says: the gap is named, not dashed.
String lenderCell(Map l) {
  if (isFromCashFlow(l)) return 'Loan received';
  final name = tStr(l['lenderName']).trim();
  return name.isEmpty ? 'Lender not recorded' : name;
}

String loanNumber(Map l) => tStr(l['loanNumber']).isNotEmpty ? tStr(l['loanNumber']) : '#${tStr(l['poultryLoanId'])}';

String loanRowKey(Map l) =>
    '${tStr(l['source']).isEmpty ? 'Loan' : tStr(l['source'])}:${tStr(l['sourceId']).isEmpty ? tStr(l['poultryLoanId']) : tStr(l['sourceId'])}';

/// Repayments by the loan they paid down, newest first.
Map<int, List<Map>> paymentsByLoan(List<Map> payments) {
  final m = <int, List<Map>>{};
  for (final p in payments) {
    m.putIfAbsent(tIntOrNull(p['poultryLoanId']) ?? 0, () => []).add(p);
  }
  for (final list in m.values) {
    list.sort((a, b) => tStr(b['paymentDate']).compareTo(tStr(a['paymentDate'])));
  }
  return m;
}

/// statusClass: (bg, fg).
(Color, Color) loanStatusTone(Map l) {
  final st = tStr(l['status']);
  if (st == 'PaidOff') return (TColors.emerald100, TColors.emerald800);
  if (st == 'Cancelled') return (TColors.slate100, TColors.slate700);
  if (l['isOverdue'] == true) return (const Color(0xFFFFE4E6), const Color(0xFF9F1239));
  if (st == 'Draft') return (TColors.sky100, TColors.sky800);
  return (TColors.amber100, TColors.amber800);
}

class LoansScreen extends StatefulWidget {
  const LoansScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<LoansScreen> createState() => _LoansScreenState();
}

class _LoansScreenState extends State<LoansScreen> {
  List<Map> _accounts = [], _loans = [], _payments = [];
  Map? _summary;
  bool _loading = true;
  String _status = 'All';
  int _page = 1, _pageSize = 10, _lastTotal = -1;
  final Set<int> _expanded = {};

  FarmMoney _fmt = const FarmMoney();
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _fmt = m);
    });
    CompanyClock.load(widget.session, widget.company).then((c) {
      if (mounted) setState(() => _offset = c.offset);
    });
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final q = {'farmId': _farmId};
      final r = await Future.wait([
        _api.get('/api/Poultry/cash-accounts', query: q),
        _api.get('/api/Poultry/loans', query: q),
        _api.get('/api/Poultry/loan-payments', query: q),
        _api.get('/api/Poultry/loans/summary', query: q),
      ]);
      if (!mounted) return;
      setState(() {
        _accounts = rowsOf(r[0]);
        _loans = rowsOf(r[1]);
        _payments = rowsOf(r[2]);
        _summary = r[3] is Map ? r[3] as Map : null;
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load loans', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  String _dt(Object? d, [Map? row]) => fmtDateTime(d, row, _offset);
  String _next(Object? d) => tStr(d).isEmpty ? '–' : _dt(d);

  Future<void> _newLoan() async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => NewLoanDialog(session: widget.session, company: widget.company, accounts: _accounts, fmt: _fmt),
    );
    if (done == true) _load();
  }

  Future<void> _repay(Map l) async {
    if (isFromCashFlow(l)) return;
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => LoanRepaymentDialog(
        loan: l,
        accounts: _accounts,
        fmtMoney: _fmt.call,
        entityLabel: 'farm',
        onSubmit: (i) => _api.post('/api/Poultry/loans/${i.loanId}/record-repayment', body: {
          'poultryCashAccountId': i.accountId,
          'principalAmount': i.principalAmount,
          'interestAmount': i.interestAmount,
          'feeAmount': i.feeAmount,
          'otherAmount': i.otherAmount,
          'paymentDate': i.paymentDate,
          'paymentMethod': i.paymentMethod,
          'referenceNumber': i.referenceNumber,
          'notes': i.notes,
          'nextPaymentDate': i.nextPaymentDate,
          'poultryLoanId': i.loanId,
          'farmId': _farmId,
          'createdBy': widget.session.tokens.userId,
        }),
      ),
    );
    if (done == true) _load();
  }

  Future<void> _reverse(Map p) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => ReverseRepaymentDialog(session: widget.session, company: widget.company, payment: p, fmt: _fmt, when: _dt(p['paymentDate'], p)),
    );
    if (done == true) _load();
  }

  void _toCashFlow() => openAppHref(context, widget.session, widget.company, '/cash-flow', label: 'Cash Flow');

  /// LoanRepaymentList: one stacked block per repayment.
  Widget _repaymentList(List<Map> ps) {
    if (ps.isEmpty) {
      return const Text('No repayments recorded against this loan yet.', style: TextStyle(fontSize: 12, color: TColors.slate500));
    }
    Widget part(String label, num v, {bool cost = false}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 11, color: TColors.slate500)),
            Text(_fmt(v), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: cost ? TColors.amber700 : null)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('REPAYMENT HISTORY', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: .4, color: TColors.slate500)),
      const SizedBox(height: 4),
      const Text('The total is what left the bank. Only the interest and the fees reach the profit and loss.',
          style: TextStyle(fontSize: 11, color: TColors.slate500)),
      for (final p in ps) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_dt(p['paymentDate'], p), style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.slate900)),
                  Text(
                    '${tStr(p['paymentNumber']).isNotEmpty ? tStr(p['paymentNumber']) : '#${tStr(p['poultryLoanPaymentId'])}'}'
                    '${tStr(p['accountName']).isNotEmpty ? ' · ${tStr(p['accountName'])}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: TColors.slate500),
                  ),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(_fmt(tNum(p['totalAmount'])),
                    style: tStr(p['status']) == 'Reversed'
                        ? const TextStyle(fontWeight: FontWeight.w600, color: TColors.slate400, decoration: TextDecoration.lineThrough)
                        : const TextStyle(fontWeight: FontWeight.w600, color: TColors.slate900)),
                const SizedBox(height: 2),
                tStr(p['status']) == 'Reversed'
                    ? TBadge(tStr(p['status']), bg: TColors.slate100, fg: TColors.slate700)
                    : TBadge(tStr(p['status']), bg: TColors.emerald100, fg: TColors.emerald800),
              ]),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              part('Principal', tNum(p['principalAmount'])),
              part('Interest', tNum(p['interestAmount']), cost: true),
              part('Fees', tNum(p['feeAmount']), cost: true),
            ]),
            if (tStr(p['status']) == 'Posted') ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _reverse(p),
                icon: const Icon(Icons.undo, size: 14),
                label: const Text('Reverse'),
              ),
            ],
          ]),
        ),
      ],
    ]);
  }

  /// LoanRepaymentTable: the opened row's repayments in the table view.
  Widget _repaymentTable(List<Map> ps) {
    if (ps.isEmpty) {
      return const Text('No repayments recorded against this loan yet.', style: TextStyle(fontSize: 13, color: TColors.slate500));
    }
    Widget money(Object? v, {Color? color, bool struck = false, bool bold = false}) => Align(
          alignment: Alignment.centerRight,
          child: Text(_fmt(tNum(v)),
              style: TextStyle(
                color: struck ? TColors.slate400 : color,
                fontWeight: bold ? FontWeight.w500 : null,
                decoration: struck ? TextDecoration.lineThrough : null,
              )),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('The total is what left the bank. Only the interest and the fees reach the profit and loss.',
          style: TextStyle(fontSize: 12, color: TColors.slate500)),
      const SizedBox(height: 6),
      TrackerTable(
        columns: const [
          TCol('Date', width: 140),
          TCol('Payment #', width: 110),
          TCol('Principal', right: true, width: 110),
          TCol('Interest', right: true, width: 110),
          TCol('Fees', right: true, width: 100),
          TCol('Total paid', right: true, width: 120),
          TCol('Account', width: 120),
          TCol('Status', width: 100),
          TCol('', width: 110),
        ],
        rows: [
          for (final p in ps)
            [
              cellText(_dt(p['paymentDate'], p)),
              Text(tStr(p['paymentNumber']).isNotEmpty ? tStr(p['paymentNumber']) : '#${tStr(p['poultryLoanPaymentId'])}',
                  style: const TextStyle(fontWeight: FontWeight.w500)),
              money(p['principalAmount']),
              money(p['interestAmount'], color: TColors.amber700),
              money(p['feeAmount'], color: TColors.amber700),
              money(p['totalAmount'], struck: tStr(p['status']) == 'Reversed', bold: true),
              Text(tStr(p['accountName']).isEmpty ? '–' : tStr(p['accountName']), style: const TextStyle(color: TColors.slate500)),
              Align(
                alignment: Alignment.centerLeft,
                child: tStr(p['status']) == 'Reversed'
                    ? TBadge(tStr(p['status']), bg: TColors.slate100, fg: TColors.slate700)
                    : TBadge(tStr(p['status']), bg: TColors.emerald100, fg: TColors.emerald800),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: tStr(p['status']) == 'Posted'
                    ? OutlinedButton.icon(onPressed: () => _reverse(p), icon: const Icon(Icons.undo, size: 14), label: const Text('Reverse'))
                    : const SizedBox.shrink(),
              ),
            ],
        ],
      ),
    ]);
  }

  Widget _table(List<Map> items, Map<int, List<Map>> byLoan) {
    final open = [for (final l in items) if (_expanded.contains(tIntOrNull(l['poultryLoanId']) ?? 0)) l];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TrackerTable(
        columns: const [
          TCol('', width: 36),
          TCol('Loan #', width: 130),
          TCol('Lender', width: 130),
          TCol('Borrowed', right: true, width: 120),
          TCol('Received', right: true, width: 120),
          TCol('Repaid', right: true, width: 120),
          TCol('Still owed', right: true, width: 120),
          TCol('Interest', right: true, width: 110),
          TCol('Fees', right: true, width: 110),
          TCol('Next payment', width: 130),
          TCol('Status', width: 100),
          TCol('', width: 110),
        ],
        rows: [
          for (final l in items)
            () {
              final id = tIntOrNull(l['poultryLoanId']) ?? 0;
              final n = byLoan[id]?.length ?? 0;
              final isOpen = _expanded.contains(id);
              void tog() => setState(() => _expanded.contains(id) ? _expanded.remove(id) : _expanded.add(id));
              Widget money(Object? v, {bool cost = false, bool bold = false}) => Align(
                    alignment: Alignment.centerRight,
                    child: Text(_fmt(tNum(v)),
                        style: TextStyle(color: cost ? TColors.amber700 : null, fontWeight: bold ? FontWeight.w500 : null)),
                  );
              final (bg, fg) = loanStatusTone(l);
              return <Widget>[
                InkWell(
                  onTap: tog,
                  child: Icon(isOpen ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, size: 18, color: TColors.slate400),
                ),
                InkWell(
                  onTap: tog,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(loanNumber(l), style: const TextStyle(fontWeight: FontWeight.w500)),
                    Text(n == 0 ? 'no repayments' : '$n repayment${n == 1 ? '' : 's'}',
                        style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(tStr(l['lenderName'])),
                  Text(tStr(l['lenderType']), style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                ]),
                money(l['originalPrincipal']),
                money(l['amountReceived']),
                money(l['totalPrincipalRepaid']),
                money(l['outstandingPrincipal'], bold: true),
                money(l['totalInterestPaid'], cost: true),
                money(l['totalFeesPaid'], cost: true),
                Text(_next(l['nextPaymentDate']), style: TextStyle(color: l['isOverdue'] == true ? TColors.rose600 : null)),
                Align(alignment: Alignment.centerLeft, child: TBadge(l['isOverdue'] == true ? 'Overdue' : tStr(l['status']), bg: bg, fg: fg)),
                Align(
                  alignment: Alignment.centerRight,
                  child: isRepayableLoan(l)
                      ? OutlinedButton(onPressed: () => _repay(l), child: const Text('Repay'))
                      : isFromCashFlow(l)
                          ? InkWell(
                              onTap: _toCashFlow,
                              child: const Text('Cash Flow',
                                  style: TextStyle(fontSize: 11, color: TColors.slate500, decoration: TextDecoration.underline)),
                            )
                          : const SizedBox.shrink(),
                ),
              ];
            }(),
        ],
      ),
      // The opened rows' repayments, under the table on a phone.
      for (final l in open) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: TColors.slate50, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(loanNumber(l), style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            _repaymentTable(byLoan[tIntOrNull(l['poultryLoanId']) ?? 0] ?? const []),
          ]),
        ),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-loans');
    final visible = _status == 'All' ? _loans : [for (final l in _loans) if (tStr(l['status']) == _status) l];
    if (visible.length != _lastTotal) {
      _lastTotal = visible.length;
      _page = 1;
    }
    final pageRows = pageSlice(visible, _page, _pageSize);
    final byLoan = paymentsByLoan(_payments);
    final s = _summary;
    final overdue = tIntOrNull(s?['overdueLoans']) ?? 0;

    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Loans (Financing)')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            const Row(children: [
              Icon(Icons.payments_outlined, size: 24, color: _violet600),
              SizedBox(width: 8),
              Expanded(
                child: Text('Loans (Financing)', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900)),
              ),
            ]),
            const SizedBox(height: 4),
            const Text.rich(
              TextSpan(children: [
                TextSpan(text: 'Money the farm has borrowed. Borrowing is '),
                TextSpan(text: 'not income', style: TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: ' and repaying principal is '),
                TextSpan(text: 'not an expense', style: TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: ' — only the interest and the fees are the cost of borrowing.'),
              ]),
              style: TextStyle(fontSize: 13, color: TColors.slate500),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _newLoan,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Record loan'),
              ),
            ),
            const SizedBox(height: 14),
            twoUp([
              moneyStat('Still owed', _fmt(tNum(s?['outstandingPrincipal'])),
                  hint: '${tIntOrNull(s?['activeLoans']) ?? 0} active loan(s)', color: _violet700),
              moneyStat('Borrowed', _fmt(tNum(s?['totalBorrowed'])), hint: '${_fmt(tNum(s?['totalReceived']))} received'),
              moneyStat('Principal repaid', _fmt(tNum(s?['totalPrincipalRepaid'])), color: TColors.emerald700),
              moneyStat('Cost of borrowing', _fmt(tNum(s?['totalInterestPaid']) + tNum(s?['totalFeesPaid'])),
                  hint: 'Interest and fees — the only part that is an expense', color: TColors.amber700),
              moneyStat('Next payment', tStr(s?['nextPaymentDate']).isEmpty ? '—' : _dt(s?['nextPaymentDate']),
                  hint: overdue > 0 ? '$overdue overdue' : null, color: overdue > 0 ? TColors.rose600 : TColors.slate900),
            ]),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final st in loanStatusFilters) filterChipButton(st, _status == st, () => setState(() => _status = st)),
            ]),
            const SizedBox(height: 14),
            if (_loading)
              const Row(children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 8),
                Text('Loading…', style: TextStyle(color: TColors.slate500)),
              ])
            else if (visible.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
                child: Text(_loans.isEmpty ? 'No loans recorded yet.' : 'No loans match this filter.',
                    textAlign: TextAlign.center, style: const TextStyle(color: TColors.slate500)),
              )
            else
              MobileCardList<Map>(
                striped: true,
                items: pageRows,
                keyOf: loanRowKey,
                primary: (l) => '${loanNumber(l)} · ${lenderCell(l)}',
                secondary: (l) => '${_dt(l['startDate'], l)} · ${isFromCashFlow(l) ? 'Recorded on Cash Flow' : tStr(l['lenderType'])}',
                trailing: (l) {
                  final (bg, fg) = loanStatusTone(l);
                  return Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: TBadge(l['isOverdue'] == true ? 'Overdue' : tStr(l['status']), bg: bg, fg: fg),
                  );
                },
                highlights: (l) => [
                  Highlight('Still owed', _fmt(tNum(l['outstandingPrincipal']))),
                  Highlight('Borrowed', _fmt(tNum(l['originalPrincipal']))),
                ],
                details: (l) => [
                  ('Received', _fmt(tNum(l['amountReceived']))),
                  ('Principal repaid', _fmt(tNum(l['totalPrincipalRepaid']))),
                  ('Interest paid', _fmt(tNum(l['totalInterestPaid']))),
                  ('Fees paid', _fmt(tNum(l['totalFeesPaid']))),
                  ('Rate', l['interestRate'] != null ? '${tStr(l['interestRate'])}% ${tStr(l['interestType'])}' : '–'),
                  ('Next payment', _next(l['nextPaymentDate'])),
                  ('Repayments', tStr(l['paymentCount']).isEmpty ? '0' : tStr(l['paymentCount'])),
                ],
                extra: (l) => _repaymentList(byLoan[tIntOrNull(l['poultryLoanId']) ?? 0] ?? const []),
                actions: (l) => [
                  if (isRepayableLoan(l))
                    OutlinedButton.icon(
                      onPressed: () => _repay(l),
                      icon: const Icon(Icons.payments_outlined, size: 16),
                      label: const Text('Repay'),
                    ),
                  if (isFromCashFlow(l))
                    InkWell(
                      onTap: _toCashFlow,
                      child: const Text('Recorded on Cash Flow — edit the amount there.',
                          style: TextStyle(fontSize: 11, color: TColors.slate500, decoration: TextDecoration.underline)),
                    ),
                ],
                table: (items) => _table(items, byLoan),
                pager: CompactPager(
                  total: visible.length,
                  page: _page,
                  pageSize: _pageSize,
                  onPage: (p) => setState(() => _page = p),
                  onPageSize: (v) => setState(() {
                    _pageSize = v;
                    _page = 1;
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Record a Loan.
class NewLoanDialog extends StatefulWidget {
  const NewLoanDialog({super.key, required this.session, required this.company, required this.accounts, required this.fmt});
  final Session session;
  final Company company;
  final List<Map> accounts;
  final FarmMoney fmt;

  @override
  State<NewLoanDialog> createState() => _NewLoanDialogState();
}

class _NewLoanDialogState extends State<NewLoanDialog> {
  final _lender = TextEditingController();
  final _accNo = TextEditingController();
  final _principal = TextEditingController(text: '0');
  final _received = TextEditingController(text: '0');
  final _rate = TextEditingController();
  final _term = TextEditingController();
  final _notes = TextEditingController();
  String _lenderType = 'Bank', _interestType = 'ReducingBalance', _frequency = 'Monthly', _account = '';
  String _start = DateTime.now().toUtc().toIso8601String().substring(0, 10), _nextDue = '';
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_lender, _accNo, _principal, _received, _rate, _term, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  num get _princ => num.tryParse(_principal.text) ?? 0;
  num get _recv => num.tryParse(_received.text) ?? 0;

  Future<void> _save() async {
    if (_lender.text.trim().isEmpty) return trackerToast(context, 'Who lent the money?', error: true);
    if (_princ <= 0) return trackerToast(context, 'Enter the loan amount', error: true);
    if (_recv > _princ) return trackerToast(context, 'Received cannot exceed the principal', error: true);
    if (_recv > 0 && _account.isEmpty) return trackerToast(context, 'Which account received it?', error: true);
    setState(() => _saving = true);
    final recv = _recv;
    String? opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    try {
      await widget.session.farmClient.post('/api/Poultry/loans', body: {
        'lenderName': _lender.text.trim(),
        'lenderType': _lenderType,
        'accountNumber': opt(_accNo),
        'originalPrincipal': _princ,
        'amountReceived': recv,
        'poultryCashAccountId': recv > 0 ? int.parse(_account) : null,
        'startDate': _start,
        'interestRate': _rate.text.isNotEmpty ? num.tryParse(_rate.text) : null,
        'interestType': _interestType,
        'termMonths': _term.text.isNotEmpty ? num.tryParse(_term.text) : null,
        'paymentFrequency': _frequency,
        'nextPaymentDate': _nextDue.isEmpty ? null : _nextDue,
        'notes': opt(_notes),
        'farmId': widget.company.farmId,
        'createdBy': widget.session.tokens.userId,
      });
      if (!mounted) return;
      trackerToast(context, 'Loan recorded',
          description: recv > 0
              ? '${widget.fmt(recv)} in. It is money in, not revenue — the farm borrowed it.'
              : 'No money recorded as received yet.');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Could not record the loan', description: e.message, error: true);
    }
  }

  Widget _num(String label, TextEditingController c, {String? info}) => FilterLabel(
        label,
        Row(children: [
          Expanded(
            child: AppInput(
              controller: c,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (info != null) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: info,
              triggerMode: TooltipTriggerMode.tap,
              child: const Icon(Icons.info_outline, size: 16, color: TColors.slate400),
            ),
          ],
        ]),
      );

  Widget _select(String label, String value, List<String> options, ValueChanged<String> on) => FilterLabel(
        label,
        AppSelect<String>(
          value: value,
          items: [for (final o in options) AppSelectItem(value: o, label: o)],
          onChanged: (v) => setState(() => on(v ?? value)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final fmt = widget.fmt;
    final active = [for (final a in widget.accounts) if (a['isActive'] == true) a];
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: const Row(children: [
          Icon(Icons.payments_outlined, color: _violet600),
          SizedBox(width: 6),
          Flexible(child: Text('Record a Loan')),
        ]),
        content: SizedBox(
          width: 520,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('The money arriving is cash in, but it is not revenue — the farm borrowed it and still owes it.',
                style: TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 12),
            formSection('Lender', _violet600, [
              FilterLabel('Lender *', AppInput(controller: _lender, hintText: 'Who lent the money?')),
              _select('Lender type', _lenderType, lenderTypes, (v) => _lenderType = v),
              FilterLabel('Account number', AppInput(controller: _accNo)),
            ]),
            const SizedBox(height: 12),
            formSection('The money', TColors.emerald600, [
              _num('Amount borrowed *', _principal, info: 'What the farm OWES. This is what the debt starts at.'),
              _num('Amount received', _received, info: 'What actually ARRIVED. Less than the principal when the lender withheld a fee.'),
              FilterLabel(
                'Account that received it',
                AppSelect<String>(
                  value: _account.isEmpty ? null : _account,
                  hintText: 'Where did the money land?',
                  items: [
                    for (final a in active)
                      AppSelectItem(
                        value: tStr(a['poultryCashAccountId']),
                        label: '${tStr(a['accountName'])} — ${fmt(tNum(a['currentBalance']))}',
                      ),
                  ],
                  onChanged: (v) => setState(() => _account = v ?? ''),
                ),
              ),
              if (_princ > _recv && _recv > 0)
                Text(
                  '${fmt(_princ - _recv)} less than the principal — usually a fee the lender withheld. You will still owe the full ${fmt(_princ)}. Record the fee as an expense yourself if you want it in the accounts.',
                  style: const TextStyle(fontSize: 12, color: TColors.slate500),
                ),
            ]),
            const SizedBox(height: 12),
            formSection('Terms', const Color(0xFF2563EB), [
              FilterLabel(
                'Start date *',
                AppDateField(
                  value: businessDateAsDateTime(_start),
                  onChanged: (d) => setState(() => _start = d == null ? _start : isoDay(d)),
                ),
              ),
              FilterLabel(
                'Next payment due',
                AppDateField(
                  value: _nextDue.isEmpty ? null : businessDateAsDateTime(_nextDue),
                  hintText: 'dd/mm/yyyy',
                  onChanged: (d) => setState(() => _nextDue = d == null ? '' : isoDay(d)),
                ),
              ),
              _num('Interest rate (%)', _rate),
              _select('Interest type', _interestType, interestTypes, (v) => _interestType = v),
              _num('Term (months)', _term),
              _select('Repayment frequency', _frequency, loanFrequencies, (v) => _frequency = v),
            ]),
            const SizedBox(height: 12),
            formSection('Notes', TColors.slate600, [
              FilterLabel('Notes', AppInput(controller: _notes, minLines: 2, maxLines: 4)),
            ]),
          ]),
        ),
        actions: [
          redCancelButton(_saving ? null : () => Navigator.pop(context, false)),
          FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Recording...' : 'Record Loan')),
        ],
      ),
    );
  }
}

/// Reverse Repayment: the debt goes back up, the cash returns, the costs cancel.
class ReverseRepaymentDialog extends StatefulWidget {
  const ReverseRepaymentDialog({
    super.key,
    required this.session,
    required this.company,
    required this.payment,
    required this.fmt,
    required this.when,
  });
  final Session session;
  final Company company;
  final Map payment;
  final FarmMoney fmt;
  final String when;

  @override
  State<ReverseRepaymentDialog> createState() => _ReverseRepaymentDialogState();
}

class _ReverseRepaymentDialogState extends State<ReverseRepaymentDialog> {
  final _reason = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (_reason.text.trim().length < 3) {
      return trackerToast(context, 'Say why', description: 'The reason is written to the audit trail.', error: true);
    }
    setState(() => _saving = true);
    try {
      await widget.session.farmClient.post(
        '/api/Poultry/loan-payments/${tStr(widget.payment['poultryLoanPaymentId'])}/reverse',
        query: {'farmId': widget.company.farmId, 'reversedBy': widget.session.tokens.userId ?? ''},
        body: {'reason': _reason.text.trim()},
      );
      if (!mounted) return;
      trackerToast(context, 'Repayment reversed', description: 'The debt is back up and the cash returned.');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Could not reverse', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.payment;
    final fmt = widget.fmt;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: const Row(children: [
          Icon(Icons.undo, color: TColors.amber600),
          SizedBox(width: 6),
          Flexible(child: Text('Reverse Repayment')),
        ]),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text(
              'The debt goes back up, the cash returns, and the interest and fee costs are cancelled. Every original row stays on the record.',
              style: TextStyle(fontSize: 13, color: TColors.slate500),
            ),
            const SizedBox(height: 12),
            formSection('Repayment being reversed', TColors.slate600, [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tStr(p['paymentNumber']).isNotEmpty ? tStr(p['paymentNumber']) : '#${tStr(p['poultryLoanPaymentId'])}',
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text('${fmt(tNum(p['totalAmount']))} on ${widget.when}'),
                const SizedBox(height: 4),
                Text(
                  '${fmt(tNum(p['principalAmount']))} principal · ${fmt(tNum(p['interestAmount']))} interest · ${fmt(tNum(p['feeAmount']))} fees',
                  style: const TextStyle(fontSize: 12, color: TColors.slate500),
                ),
              ]),
            ]),
            const SizedBox(height: 12),
            formSection('Why', TColors.amber600, [
              FilterLabel('Reason *', AppInput(controller: _reason, hintText: 'Why is this being reversed?', minLines: 3, maxLines: 5)),
              const Text('Written to the audit trail.', style: TextStyle(fontSize: 11, color: TColors.slate500)),
            ]),
          ]),
        ),
        actions: [
          redCancelButton(_saving ? null : () => Navigator.pop(context, false)),
          FilledButton(
            onPressed: _saving ? null : _go,
            style: FilledButton.styleFrom(backgroundColor: TColors.red600, foregroundColor: Colors.white),
            child: Text(_saving ? 'Reversing...' : 'Reverse'),
          ),
        ],
      ),
    );
  }
}
