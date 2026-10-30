// Restaurant → Money → Loans (Financing), as `app/restaurant-loans/page.tsx`:
// money the restaurant borrowed and its repayments. Principal moves cash and
// reduces what is owed; interest and fees are costs on the Profit & Loss.
// API: /Restaurant/finance/loans (migration 323).

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/money/money_widgets.dart';
import '../poultry/reports/report_format.dart' show FarmMoney;
import '../poultry/sales/balances_logic.dart' show pageSlice;
import '../poultry/sales/balances_widgets.dart' show CompactPager, LoadingLine;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/reason_select.dart' show loanReversalReasons;
import 'restaurant_money_kit.dart';
import 'restaurant_widgets.dart';

/// The page's five cards, from the loans as loaded.
({num outstanding, int activeCount, num costsPaid, int overdue, num borrowed, num received, num repaid, String? nextDue})
    restaurantLoanStats(List<Map> loans) {
  final active = [for (final l in loans) if (l['status'] == 'Active') l];
  final live = [for (final l in loans) if (l['status'] != 'Cancelled') l];
  num sum(List<Map> ls, num Function(Map) f) => ls.fold<num>(0, (s, l) => s + f(l));
  final due = [for (final l in active) if (tStr(l['dueDate']).isNotEmpty) tStr(l['dueDate'])]..sort();
  return (
    outstanding: sum(active, (l) => tNum(l['outstandingPrincipal'])),
    activeCount: active.length,
    costsPaid: sum(live, (l) => tNum(l['interestPaid']) + tNum(l['feesPaid'])),
    overdue: loans.where((l) => l['isOverdue'] == true).length,
    borrowed: sum(live, (l) => tNum(l['principal'])),
    received: sum(live, (l) => tNum(l['amountReceived'])),
    repaid: sum(live, (l) => tNum(l['principalRepaid'])),
    nextDue: due.isEmpty ? null : due.first,
  );
}

Widget _loanStatusBadge(Object? status) => switch (tStr(status)) {
      'Active' => rStatusBadge('Active', bg: const Color(0xFFEFF6FF), fg: const Color(0xFF1D4ED8), border: const Color(0xFFBFDBFE)),
      'PaidOff' => rStatusBadge('Paid off', bg: const Color(0xFFF0FDF4), fg: const Color(0xFF15803D), border: const Color(0xFFBBF7D0)),
      final s => rStatusBadge(s, bg: TColors.slate100, fg: TColors.slate600, border: TColors.slate200),
    };

String _loanNumber(Map l) => tStr(l['loanNumber']).isNotEmpty ? tStr(l['loanNumber']) : '#${tIntOrNull(l['loanId'])}';

bool _cancellable(Map l) =>
    l['status'] == 'Active' && tNum(l['principalRepaid']) + tNum(l['interestPaid']) + tNum(l['feesPaid']) == 0;

class RestaurantLoansScreen extends StatefulWidget {
  const RestaurantLoansScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<RestaurantLoansScreen> createState() => _RestaurantLoansScreenState();
}

class _RestaurantLoansScreenState extends State<RestaurantLoansScreen> {
  bool _loading = true;
  List<Map> _loans = [];
  List<Map> _accounts = [];
  int _page = 1, _pageSize = 10;
  FarmMoney _gh = const FarmMoney();

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  bool get _canView => (widget.company.role ?? '').toLowerCase() != 'staff';

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _gh = m);
    });
    if (_canView) {
      _load();
    } else {
      _loading = false;
    }
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([_api.get(rFin('/loans', _farmId)), loadRestaurantAccounts(_api, _farmId)]);
      if (!mounted) return;
      setState(() {
        _loans = rowsOf(r[0]);
        _accounts = [for (final a in r[1] as List<Map>) if (a['isActive'] == true) a];
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load loans', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  String? get _defaultAccount => _accounts.length == 1 ? '${tIntOrNull(_accounts.first['cashAccountId'])}' : null;

  Future<void> _newLoan() async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _LoanDialog(api: _api, farmId: _farmId, accounts: _accounts, gh: _gh, account: _defaultAccount),
    );
    if (done == true) _load();
  }

  Future<void> _repay(Map loan) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _RepayDialog(api: _api, farmId: _farmId, loan: loan, accounts: _accounts, gh: _gh, account: _defaultAccount),
    );
    if (done == true) _load();
  }

  Future<void> _payments(Map loan) => showDialog<void>(
        context: context,
        builder: (_) => _PaymentsDialog(
          api: _api,
          farmId: _farmId,
          loan: loan,
          gh: _gh,
          reloadLoans: () async {
            await _load();
            return _loans.where((l) => l['loanId'] == loan['loanId']).firstOrNull ?? loan;
          },
        ),
      );

  Future<void> _cancel(Map l) async {
    final received = tNum(l['amountReceived']);
    final account = tStr(l['receivedAccountName']);
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => RReasonDialog(
        title: 'Cancel loan from ${tStr(l['lenderName'])}',
        description: 'Only possible when the loan has no repayments; it returns the money received'
            '${received > 0 && account.isNotEmpty ? ' (${_gh(received)} comes back out of $account).' : '.'}',
        options: loanReversalReasons,
        keepLabel: 'Keep loan',
        confirmLabel: 'Cancel loan',
        busyLabel: 'Cancelling...',
        errorTitle: 'Could not cancel the loan',
        submit: (reason) => _api.post(rFin('/loans/${tIntOrNull(l['loanId'])}/cancel', _farmId), body: {'reason': reason}),
      ),
    );
    if (done == true) {
      if (mounted) trackerToast(context, 'Loan cancelled', description: 'The money received was taken back out of the account.');
      _load();
    }
  }

  List<Widget> _actions(Map l) => [
        if (l['status'] == 'Active') roseButton('Repay', () => _repay(l), icon: Icons.payments_outlined),
        OutlinedButton.icon(onPressed: () => _payments(l), icon: const Icon(Icons.format_list_numbered, size: 16), label: const Text('Payments')),
        if (_cancellable(l))
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: TColors.red600),
            onPressed: () => _cancel(l),
            icon: const Icon(Icons.block, size: 16),
            label: const Text('Cancel'),
          ),
      ];

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/restaurant-loans');
    Widget body;
    if (_loading) {
      body = const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: LoadingLine('Loading…')));
    } else if (!_canView) {
      body = const TCard(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: Text('You do not have access to Loans.', style: TextStyle(color: TColors.slate600))),
        ),
      );
    } else {
      final s = restaurantLoanStats(_loans);
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        RPageHeader(
          icon: Icons.account_balance_outlined,
          title: 'Loans (Financing)',
          subtitle: 'Money the restaurant borrowed and its repayments',
          actions: [roseButton('Record loan', _newLoan)],
        ),
        const SizedBox(height: 12),
        twoColumns([
          MoneyStat(label: 'Still owed', value: _gh(s.outstanding), hint: '${s.activeCount} active loan(s)', accent: 'rose'),
          MoneyStat(label: 'Borrowed', value: _gh(s.borrowed), hint: '${_gh(s.received)} received'),
          MoneyStat(label: 'Principal repaid', value: _gh(s.repaid), accent: 'emerald'),
          MoneyStat(label: 'Cost of borrowing', value: _gh(s.costsPaid), hint: 'Interest and fees — the only part that is an expense', accent: 'amber'),
          MoneyStat(
            label: 'Next payment',
            value: s.nextDue != null ? rDateOnly(s.nextDue) : '—',
            hint: s.overdue > 0 ? '${s.overdue} overdue' : null,
            accent: s.overdue > 0 ? 'rose' : 'slate',
          ),
        ]),
        const SizedBox(height: 16),
        if (_loans.isEmpty)
          TCard(
            child: REmptyState(
              icon: Icons.account_balance_outlined,
              title: 'No loans recorded',
              description: 'Record money the restaurant has borrowed so repayments are tracked',
              actionLabel: 'Record loan',
              onAction: _newLoan,
            ),
          )
        else
          TCard(
            padding: const EdgeInsets.all(10),
            child: MobileCardList<Map>(
              items: pageSlice(_loans, _page, _pageSize),
              striped: true,
              keyOf: (l) => '${l['loanId']}',
              primary: (l) => tStr(l['lenderName']),
              secondary: (l) => '${_loanNumber(l)} · ${rDateOnly(l['loanDate'])}',
              trailing: (l) => _loanStatusBadge(l['status']),
              highlights: (l) => [
                Highlight('Still owed', _gh(tNum(l['outstandingPrincipal'])), accent: Accent.rose, wide: true),
                Highlight('Borrowed', _gh(tNum(l['principal']))),
                Highlight('Repaid', _gh(tNum(l['principalRepaid'])), accent: Accent.emerald),
              ],
              details: (l) => [
                ('Interest + fees', _gh(tNum(l['interestPaid']) + tNum(l['feesPaid']))),
                ('Due', '${rDateOnly(l['dueDate'])}${l['isOverdue'] == true ? ' Overdue' : ''}'),
                ('Received into', tStr(l['receivedAccountName']).isEmpty ? '—' : tStr(l['receivedAccountName'])),
                ('Interest rate', l['interestRate'] != null ? '${_plain(l['interestRate'])}%' : '—'),
                if (l['status'] == 'Cancelled' && tStr(l['cancelReason']).isNotEmpty) ('Cancelled', tStr(l['cancelReason'])),
              ],
              actions: _actions,
              table: _table,
              pager: CompactPager(
                total: _loans.length,
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
      ]);
    }
    return Scaffold(
      backgroundColor: TColors.slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Loans (Financing)')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [body]),
      ),
    );
  }

  Widget _table(List<Map> rows) => TrackerTable(
        columns: const [
          TCol('Loan', width: 170),
          TCol('Date', width: 100),
          TCol('Principal', right: true, width: 110),
          TCol('Outstanding', right: true, width: 110),
          TCol('Repaid', right: true, width: 110),
          TCol('Interest + fees', right: true, width: 120),
          TCol('Due', width: 110),
          TCol('Status', width: 100),
          TCol('Actions', right: true, width: 330),
        ],
        rows: [
          for (final l in rows)
            () {
              final grey = l['status'] == 'Cancelled' ? TColors.slate400 : null;
              return [
                Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(tStr(l['lenderName']), style: TextStyle(fontWeight: FontWeight.w500, color: grey ?? TColors.slate900)),
                  Text(_loanNumber(l), style: const TextStyle(fontSize: 11, color: TColors.slate500)),
                  if (l['status'] == 'Cancelled' && tStr(l['cancelReason']).isNotEmpty)
                    Text(tStr(l['cancelReason']), style: const TextStyle(fontSize: 11, color: TColors.slate400)),
                ]),
                cellText(rDateOnly(l['loanDate']), color: grey),
                cellText(_gh(tNum(l['principal'])), color: grey),
                cellText(_gh(tNum(l['outstandingPrincipal'])), color: grey, bold: true),
                cellText(_gh(tNum(l['principalRepaid'])), color: grey),
                cellText(_gh(tNum(l['interestPaid']) + tNum(l['feesPaid'])), color: grey),
                Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(rDateOnly(l['dueDate']), style: TextStyle(fontSize: 12, color: grey)),
                  if (l['isOverdue'] == true) rStatusBadge('Overdue', bg: TColors.red600, fg: Colors.white, border: TColors.red600),
                ]),
                Align(alignment: Alignment.centerLeft, child: _loanStatusBadge(l['status'])),
                Wrap(alignment: WrapAlignment.end, spacing: 6, runSpacing: 6, children: _actions(l)),
              ];
            }(),
        ],
      );
}

/// A number as the web prints it: 12, 12.5.
String _plain(Object? v) {
  final n = tNum(v);
  return n == n.roundToDouble() ? n.toInt().toString() : '$n';
}

// ------------------------------------------------------------------ Record loan

class _LoanDialog extends StatefulWidget {
  const _LoanDialog({required this.api, required this.farmId, required this.accounts, required this.gh, this.account});
  final ApiClient api;
  final String farmId;
  final List<Map> accounts;
  final FarmMoney gh;
  final String? account;

  @override
  State<_LoanDialog> createState() => _LoanDialogState();
}

class _LoanDialogState extends State<_LoanDialog> {
  final _lender = TextEditingController();
  final _principal = TextEditingController();
  final _received = TextEditingController();
  final _rate = TextEditingController();
  final _notes = TextEditingController();
  bool _receivedTouched = false;
  late String? _account = widget.account;
  String _loanDate = rTodayIso();
  String _dueDate = '';
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_lender, _principal, _received, _rate, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  void _toast(String t, String d) => trackerToast(context, t, description: d, error: true);

  Future<void> _save() async {
    final principal = rMoney(_principal.text);
    final received = _receivedTouched ? rMoney(_received.text) : principal;
    final rate = _rate.text.trim().isEmpty ? null : num.tryParse(_rate.text.trim());
    if (_lender.text.trim().isEmpty) return _toast('Enter the lender', 'Who lent the money?');
    if (principal == null || principal <= 0) return _toast('Enter the loan amount', 'The loan amount must be more than zero.');
    if (received == null || received < 0) return _toast('Check the amount received', 'It cannot be negative.');
    if (received > principal) return _toast('Check the amount received', 'You cannot receive more than the loan amount.');
    if (received > 0 && _account == null) return _toast('Pick an account', 'Choose the account the money was received into.');
    if (_rate.text.trim().isNotEmpty && (rate == null || rate < 0)) {
      return _toast('Check the interest rate', 'Leave it blank or enter a positive number.');
    }
    if (_loanDate.isNotEmpty && _loanDate.compareTo(rTodayIso()) > 0) {
      return _toast('Date is in the future', 'Pick today or an earlier loan date.');
    }
    if (_dueDate.isNotEmpty && _loanDate.isNotEmpty && _dueDate.compareTo(_loanDate) < 0) {
      return _toast('Check the due date', 'The due date cannot be before the loan date.');
    }
    setState(() => _saving = true);
    try {
      await widget.api.post(rFin('/loans', widget.farmId), body: {
        'lenderName': _lender.text.trim(),
        'principal': principal,
        'amountReceived': received,
        'receivedAccountId': received > 0 ? int.parse(_account!) : null,
        if (_loanDate.isNotEmpty) 'loanDate': _loanDate,
        'interestRate': rate,
        'dueDate': _dueDate.isEmpty ? null : _dueDate,
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      });
      if (!mounted) return;
      trackerToast(context, 'Loan recorded', description: received > 0 ? '${widget.gh(received)} added to the account.' : 'Loan recorded.');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Could not save the loan', e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Amount received follows the loan amount until it is typed into.
    if (!_receivedTouched && _received.text != _principal.text) _received.text = _principal.text;
    final p = rMoney(_principal.text), r = rMoney(_received.text);
    final kept = p != null && r != null && r < p ? rRound2(p - r) : 0;
    return PopScope(
      canPop: !_saving,
      child: rDialog(
        title: 'Record Loan',
        description: 'Money the restaurant borrowed. It is not income.',
        children: [
          rField('Lender', AppInput(controller: _lender, hintText: 'e.g. First Bank, a family member'), required: true),
          rField('Loan amount', rNumberInput(_principal, onChanged: () => setState(() {})), required: true),
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            rField(
              'Amount actually received',
              rNumberInput(_received, onChanged: () => setState(() => _receivedTouched = true)),
            ),
            const SizedBox(height: 4),
            Text('Lower if the lender kept fees upfront.${kept > 0 ? ' The lender kept ${widget.gh(kept)}.' : ''}',
                style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          ]),
          rField(
            'Received into',
            AppSelect<String>(
              value: _account,
              hintText: 'Select account',
              items: rAccountItems(widget.accounts, widget.gh.call),
              onChanged: (v) => setState(() => _account = v),
            ),
            required: (r ?? 0) > 0,
          ),
          rField('Loan date', rDateInput(_loanDate, (v) => setState(() => _loanDate = v), max: rTodayIso())),
          rField('Due date', rDateInput(_dueDate, (v) => setState(() => _dueDate = v), min: _loanDate)),
          rField('Interest rate %', rNumberInput(_rate, hint: 'Optional, for your records')),
          rField('Notes', AppInput(controller: _notes, hintText: 'Optional')),
        ],
        actions: [
          rCancel(context, 'Cancel', busy: _saving),
          rConfirm(_saving ? 'Saving...' : 'Record loan', _saving ? null : _save),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ Repay

class _RepayDialog extends StatefulWidget {
  const _RepayDialog({required this.api, required this.farmId, required this.loan, required this.accounts, required this.gh, this.account});
  final ApiClient api;
  final String farmId;
  final Map loan;
  final List<Map> accounts;
  final FarmMoney gh;
  final String? account;

  @override
  State<_RepayDialog> createState() => _RepayDialogState();
}

class _RepayDialogState extends State<_RepayDialog> {
  late String? _account = widget.account;
  final _principal = TextEditingController();
  final _interest = TextEditingController();
  final _fees = TextEditingController();
  final _notes = TextEditingController();
  String _date = rTodayIso();
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_principal, _interest, _fees, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  void _toast(String t, String d) => trackerToast(context, t, description: d, error: true);

  num get _owed => tNum(widget.loan['outstandingPrincipal']);

  Future<void> _save() async {
    final p = rMoney(_principal.text), i = rMoney(_interest.text), f = rMoney(_fees.text);
    if (_account == null) return _toast('Pick an account', 'Choose the account the payment comes from.');
    for (final (label, v) in [('Principal', p), ('Interest', i), ('Fees', f)]) {
      if (v == null || v < 0) return _toast('Check ${label.toLowerCase()}', '$label cannot be negative.');
    }
    final total = rRound2(p! + i! + f!);
    if (total <= 0) return _toast('Enter an amount', 'Enter the principal, interest or fees being paid.');
    if (p > rRound2(_owed)) return _toast('Too much principal', 'Only ${widget.gh(_owed)} is still owed on this loan.');
    if (_date.isNotEmpty && _date.compareTo(rTodayIso()) > 0) return _toast('Date is in the future', 'Pick today or an earlier date.');
    setState(() => _saving = true);
    try {
      await widget.api.post(rFin('/loans/${tIntOrNull(widget.loan['loanId'])}/repay', widget.farmId), body: {
        'cashAccountId': int.parse(_account!),
        'principal': p,
        'interest': i,
        'fees': f,
        if (_date.isNotEmpty) 'paymentDate': _date,
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      });
      if (!mounted) return;
      trackerToast(context, 'Repayment recorded', description: '${widget.gh(total)} paid to ${tStr(widget.loan['lenderName'])}.');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Could not record the repayment', e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = rMoney(_principal.text), i = rMoney(_interest.text), f = rMoney(_fees.text);
    final total = p == null || i == null || f == null ? null : rRound2(p + i + f);
    final after = p == null ? null : rRound2(_owed - p);
    void redraw() => setState(() {});
    return PopScope(
      canPop: !_saving,
      child: rDialog(
        title: 'Repay ${tStr(widget.loan['lenderName'])}',
        description: 'Principal reduces what you owe. Interest and fees are costs and appear on the Profit & Loss.',
        children: [
          rFigureBox('Still owed', widget.gh(_owed)),
          rField(
            'Paid from',
            AppSelect<String>(
              value: _account,
              hintText: 'Select account',
              items: rAccountItems(widget.accounts, widget.gh.call),
              onChanged: (v) => setState(() => _account = v),
            ),
            required: true,
          ),
          rField('Principal', rNumberInput(_principal, onChanged: redraw)),
          rField('Interest', rNumberInput(_interest, onChanged: redraw)),
          rField('Fees', rNumberInput(_fees, onChanged: redraw)),
          rField('Date', rDateInput(_date, (v) => setState(() => _date = v), max: rTodayIso())),
          rField('Notes', AppInput(controller: _notes, hintText: 'Optional')),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const Expanded(child: Text('Total leaving the account', style: TextStyle(fontSize: 13, color: TColors.slate500))),
                Text(total == null ? '—' : widget.gh(total), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                const Expanded(child: Text('Outstanding after', style: TextStyle(fontSize: 13, color: TColors.slate500))),
                Text(after == null ? '—' : widget.gh(after),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: (after ?? 0) < 0 ? TColors.red600 : null)),
              ]),
              if ((after ?? 0) < 0)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('Principal is more than what is still owed.', style: TextStyle(fontSize: 12, color: TColors.red600)),
                ),
            ]),
          ),
        ],
        actions: [
          rCancel(context, 'Cancel', busy: _saving),
          rConfirm(_saving ? 'Saving...' : 'Record repayment', _saving || (after ?? 0) < 0 ? null : _save),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ Payments

class _PaymentsDialog extends StatefulWidget {
  const _PaymentsDialog({required this.api, required this.farmId, required this.loan, required this.gh, required this.reloadLoans});
  final ApiClient api;
  final String farmId;
  final Map loan;
  final FarmMoney gh;
  final Future<Map> Function() reloadLoans;

  @override
  State<_PaymentsDialog> createState() => _PaymentsDialogState();
}

class _PaymentsDialogState extends State<_PaymentsDialog> {
  late Map _loan = widget.loan;
  List<Map> _payments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPayments();
  }

  Future<void> _loadPayments() async {
    setState(() => _loading = true);
    try {
      final r = await widget.api.get(rFin('/loans/${tIntOrNull(_loan['loanId'])}/payments', widget.farmId));
      if (mounted) setState(() => _payments = rowsOf(r));
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load payments', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _reverse(Map p) async {
    final gh = widget.gh;
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => RReasonDialog(
        title: 'Reverse repayment',
        description:
            '${gh(tNum(p['totalAmount']))} goes back into ${tStr(p['accountName'])}, and ${gh(tNum(p['principalAmount']))} is owed again.',
        options: loanReversalReasons,
        keepLabel: 'Keep it',
        confirmLabel: 'Reverse',
        busyLabel: 'Reversing...',
        errorTitle: 'Could not reverse',
        submit: (reason) =>
            widget.api.post(rFin('/loans/payments/${tIntOrNull(p['loanPaymentId'])}/reverse', widget.farmId), body: {'reason': reason}),
      ),
    );
    if (done != true || !mounted) return;
    trackerToast(context, 'Repayment reversed', description: 'The money went back into the account.');
    final live = await widget.reloadLoans();
    if (mounted) setState(() => _loan = live);
    await _loadPayments();
  }

  @override
  Widget build(BuildContext context) {
    final gh = widget.gh;
    return rDialog(
      title: 'Payments — ${tStr(_loan['lenderName'])}',
      description: '${_loanNumber(_loan)} · outstanding ${gh(tNum(_loan['outstandingPrincipal']))}',
      children: [
        if (_loading)
          const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: Text('Loading…', style: TextStyle(color: TColors.slate500))))
        else if (_payments.isEmpty)
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: Text('No repayments yet.', style: TextStyle(color: TColors.slate500))))
        else
          TrackerTable(
            columns: const [
              TCol('Date', width: 95),
              TCol('Account', width: 110),
              TCol('Principal', right: true, width: 100),
              TCol('Interest', right: true, width: 95),
              TCol('Fees', right: true, width: 90),
              TCol('Total', right: true, width: 100),
              TCol('Status', width: 130),
              TCol('', right: true, width: 110),
            ],
            rows: [
              for (final p in _payments)
                () {
                  final reversed = p['status'] != 'Posted';
                  final grey = reversed ? TColors.slate400 : null;
                  return [
                    cellText(rDateOnly(p['paymentDate']), color: grey),
                    cellText(tStr(p['accountName']), color: grey),
                    cellText(gh(tNum(p['principalAmount'])), color: grey),
                    cellText(gh(tNum(p['interestAmount'])), color: grey),
                    cellText(gh(tNum(p['feeAmount'])), color: grey),
                    Text(gh(tNum(p['totalAmount'])),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontWeight: FontWeight.w600, color: grey, decoration: reversed ? TextDecoration.lineThrough : null)),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      rStatusBadge(tStr(p['status'])),
                      if (reversed && tStr(p['reversalReason']).isNotEmpty)
                        Text(tStr(p['reversalReason']), style: const TextStyle(fontSize: 11, color: TColors.slate400)),
                    ]),
                    reversed
                        ? const SizedBox()
                        : OutlinedButton.icon(onPressed: () => _reverse(p), icon: const Icon(Icons.undo, size: 16), label: const Text('Reverse')),
                  ];
                }(),
            ],
          ),
      ],
      actions: [OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}
