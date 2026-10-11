import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../shared/business_dates.dart';
import '../money/money_widgets.dart';
import '../reports/report_format.dart';
import '../reports/report_routes.dart' show openAppHref;
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../trackers/tracker_widgets.dart';

/// Poultry → Expenses → Employee Loans & Advances, as `app/poultry-employee-loans/page.tsx`:
/// money advanced to staff and what has come back. An advance is not an
/// expense, and getting it back is not income.

const employeeLoanTypes = [('EmployeeLoan', 'Employee loan'), ('SalaryAdvance', 'Salary advance'), ('OtherAdvance', 'Other advance')];
const employeeLoanRepaymentMethods = [
  ('PayrollDeduction', 'Payroll deduction'), ('Cash', 'Cash'), ('MoMo', 'MoMo'), ('Bank', 'Bank'), ('Mixed', 'Mixed'), ('Other', 'Other'),
];
const employeeLoanRepaymentSources = [('ManualCash', 'Cash'), ('MoMo', 'MoMo'), ('Bank', 'Bank'), ('Other', 'Other')];
const _sourceLabels = {'Payroll': 'Payroll', 'ManualCash': 'Cash', 'MoMo': 'MoMo', 'Bank': 'Bank', 'Other': 'Other'};
const _statusLabels = {
  'Draft': 'Draft', 'Active': 'Active', 'Paid': 'Paid', 'Cancelled': 'Cancelled', 'Reversed': 'Reversed', 'WrittenOff': 'Written off',
};
const employeeLoanPageSize = 25;

String _label(List<(String, String)> list, Object? v) => list.where((e) => e.$1 == tStr(v)).firstOrNull?.$2 ?? tStr(v);
String employeeLoanTypeLabel(Object? v) => _label(employeeLoanTypes, v);
String employeeLoanMethodLabel(Object? v) => _label(employeeLoanRepaymentMethods, v);
String employeeLoanSourceLabel(Object? v) => _sourceLabels[tStr(v)] ?? tStr(v);
String employeeLoanStatusLabel(Object? v) => _statusLabels[tStr(v)] ?? tStr(v);
String _date(Object? d) => tStr(d).isEmpty ? '—' : (tStr(d).length >= 10 ? tStr(d).substring(0, 10) : tStr(d));

/// statusClass: (bg, fg).
(Color, Color) employeeLoanTone(Object? s) => switch (tStr(s)) {
      'Active' => (TColors.amber100, TColors.amber800),
      'Paid' => (TColors.emerald100, TColors.emerald700),
      'Reversed' || 'Cancelled' => (TColors.slate200, TColors.slate500),
      'WrittenOff' => (const Color(0xFFFFE4E6), TColors.rose700),
      _ => (TColors.slate100, TColors.slate600),
    };

/// "Showing a–b of n" for the server-paged list.
(int, int) employeeLoanRange(int offset, int total) => (total == 0 ? 0 : offset + 1, (offset + employeeLoanPageSize).clamp(0, total));

Widget _loanBadge(Object? status) {
  final (bg, fg) = employeeLoanTone(status);
  return TBadge(employeeLoanStatusLabel(status), bg: bg, fg: fg);
}

class EmployeeLoansScreen extends StatefulWidget {
  const EmployeeLoansScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<EmployeeLoansScreen> createState() => _EmployeeLoansScreenState();
}

class _EmployeeLoansScreenState extends State<EmployeeLoansScreen> {
  List<Map> _rows = [], _staff = [], _accounts = [];
  int _total = 0, _offset = 0;
  Map? _summary;
  bool _loading = true, _historyLoading = false;
  String _error = '', _status = 'Active', _staffId = 'ALL', _loanType = 'ALL';
  final _search = TextEditingController();
  Map<int, List<Map>> _history = {};
  FarmMoney _fmt = const FarmMoney();

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _fmt = m);
    });
    _loadLookups();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadLookups() async {
    try {
      final r = await Future.wait([
        _api.get('/api/Poultry/staff', query: {'farmId': _farmId}),
        _api.get('/api/Poultry/cash-accounts', query: {'farmId': _farmId}),
      ]);
      if (!mounted) return;
      setState(() {
        _staff = [for (final s in rowsOf(r[0])) if (s['isActive'] == true && s['isDeleted'] != true) s];
        _accounts = rowsOf(r[1]);
      });
    } on ApiException {
      // Silent, as the web: the filters and dialogs just have fewer options.
    }
  }

  Future<void> _load() async {
    setState(() => _error = '');
    try {
      final r = await Future.wait([
        _api.get('/api/Poultry/employee-loans', query: {
          'farmId': _farmId,
          if (_status.isNotEmpty) 'status': _status,
          if (_search.text.trim().isNotEmpty) 'search': _search.text.trim(),
          if (_staffId != 'ALL') 'staffId': _staffId,
          if (_loanType != 'ALL') 'loanType': _loanType,
          'limit': '$employeeLoanPageSize',
          'offset': '$_offset',
        }),
        _api.get('/api/Poultry/employee-loans/summary', query: {'farmId': _farmId}),
      ]);
      if (!mounted) return;
      final page = r[0] is Map ? r[0] as Map : const {};
      setState(() {
        _rows = rowsOf(page['items']);
        _total = tIntOrNull(page['totalCount']) ?? 0;
        _summary = r[1] is Map ? r[1] as Map : null;
      });
      _loadHistories();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Every listed loan's repayments, for the detail dialog.
  Future<void> _loadHistories() async {
    if (_rows.isEmpty) return setState(() => _history = {});
    setState(() => _historyLoading = true);
    final pairs = await Future.wait([
      for (final l in _rows)
        () async {
          final id = tIntOrNull(l['poultryEmployeeLoanId']) ?? 0;
          try {
            return MapEntry(id, rowsOf(await _api.get('/api/Poultry/employee-loans/$id/repayments', query: {'farmId': _farmId})));
          } on ApiException {
            return MapEntry(id, <Map>[]);
          }
        }(),
    ]);
    if (mounted) {
      setState(() {
        _history = Map.fromEntries(pairs);
        _historyLoading = false;
      });
    }
  }

  void _refilter(VoidCallback change) {
    setState(() {
      change();
      _offset = 0;
    });
    _load();
  }

  /// run(): toast "That did not work" on failure, the given title on success.
  Future<bool> _run(Future<void> Function() fn, String ok) async {
    try {
      await fn();
      if (mounted) trackerToast(context, ok);
      await _load();
      return true;
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'That did not work', description: e.message, error: true);
      return false;
    }
  }

  Map<String, Object?> get _who => {'farmId': _farmId};

  Future<void> _newLoan() => showDialog<void>(
        context: context,
        builder: (ctx) => NewEmployeeLoanDialog(
          staff: _staff,
          accounts: _accounts,
          fmt: _fmt,
          onSave: (input) async {
            final ok = await _run(
                () => _api.post('/api/Poultry/employee-loans', body: {...input, ..._who, 'createdBy': widget.session.tokens.userId}),
                'Advance recorded');
            if (ok && ctx.mounted) Navigator.pop(ctx);
          },
        ),
      );

  Future<void> _disburse(Map l) => showDialog<void>(
        context: context,
        builder: (ctx) => DisburseLoanDialog(
          loan: l,
          accounts: _accounts,
          fmt: _fmt,
          onSave: (input) async {
            final ok = await _run(
                () => _api.post('/api/Poultry/employee-loans/${tStr(l['poultryEmployeeLoanId'])}/disburse',
                    body: {...input, ..._who, 'disbursedBy': widget.session.tokens.userId}),
                'Advance handed over');
            if (ok && ctx.mounted) Navigator.pop(ctx);
          },
        ),
      );

  Future<void> _repay(Map l) => showDialog<void>(
        context: context,
        builder: (ctx) => RepayLoanDialog(
          loan: l,
          accounts: _accounts,
          fmt: _fmt,
          onSave: (input) async {
            final ok = await _run(
                () => _api.post('/api/Poultry/employee-loans/repayments', body: {...input, ..._who, 'createdBy': widget.session.tokens.userId}),
                'Repayment recorded');
            if (ok && ctx.mounted) Navigator.pop(ctx);
          },
        ),
      );

  /// One dialog for cancelling a draft, reversing an advance, or reversing a repayment.
  Future<void> _undo({Map? loan, Map? repayment}) async {
    final draft = loan != null && tStr(loan['status']) == 'Draft';
    await showDialog<void>(
      context: context,
      builder: (ctx) => _UndoDialog(
        title: repayment != null ? 'Reverse this repayment' : draft ? 'Cancel this advance' : 'Reverse this advance',
        description: repayment != null
            ? 'The repayment stays on the record, marked reversed, and what the worker owes goes back up. Any cash that came in goes back out.'
            : draft
                ? 'Nothing has been handed over, so there is nothing to undo financially.'
                : 'The money goes back to the cash account and the claim on the worker disappears. Refused if any repayment is still posted — reverse those first.',
        onUndo: (r) => _run(() async {
          final body = {..._who, 'reason': r, 'actionBy': widget.session.tokens.userId};
          if (repayment != null) {
            await _api.post('/api/Poultry/employee-loans/repayments/${tStr(repayment['poultryEmployeeLoanRepaymentId'])}/reverse', body: body);
          } else if (loan != null) {
            await _api.post('/api/Poultry/employee-loans/${tStr(loan['poultryEmployeeLoanId'])}/${draft ? 'cancel' : 'reverse'}', body: body);
          }
        }, 'Done'),
      ),
    );
  }

  Future<void> _details(Map l) => showDialog<void>(
        context: context,
        builder: (ctx) => LoanDetailDialog(
          loan: l,
          rows: _history[tIntOrNull(l['poultryEmployeeLoanId']) ?? 0] ?? const [],
          loading: _historyLoading,
          fmt: _fmt,
          onReverse: (r) {
            Navigator.pop(ctx);
            _undo(repayment: r);
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-employee-loans');
    final s = _summary;
    final (from, to) = employeeLoanRange(_offset, _total);
    final filtered = _status.isNotEmpty || _search.text.isNotEmpty || _staffId != 'ALL' || _loanType != 'ALL';

    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Employee Loans & Advances')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            const Row(children: [
              Icon(Icons.people_outline, size: 24, color: Color(0xFF4F46E5)),
              SizedBox(width: 8),
              Expanded(child: Text('Employee Loans & Advances', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900))),
            ]),
            const SizedBox(height: 4),
            const Text.rich(
              TextSpan(children: [
                TextSpan(text: 'Money advanced to staff, and repayments made through payroll or direct payment. An advance is '),
                TextSpan(text: 'not an expense', style: TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: ' — it is money the worker owes you — and getting it back is '),
                TextSpan(text: 'not income', style: TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: '.'),
              ]),
              style: TextStyle(fontSize: 13, color: TColors.slate500),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton(
                onPressed: () => openAppHref(context, widget.session, widget.company, '/poultry-payroll', label: 'Payroll'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                child: const Text('Payroll'),
              ),
              FilledButton.icon(
                onPressed: _newLoan,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New loan / advance'),
              ),
            ]),
            const SizedBox(height: 14),
            twoUp([
              moneyStat('Outstanding', _fmt(tNum(s?['outstandingTotal'])), hint: 'What staff still owe the farm', color: const Color(0xFF4338CA)),
              moneyStat('Advanced', _fmt(tNum(s?['disbursedInPeriod'])), color: TColors.rose600),
              moneyStat('Repaid', _fmt(tNum(s?['repaidInPeriod'])), color: TColors.emerald700),
              moneyStat('Active advances', tStr(s?['activeLoans']).isEmpty ? '0' : tStr(s?['activeLoans']),
                  hint: '${tStr(s?['staffWithActiveLoans']).isEmpty ? '0' : tStr(s?['staffWithActiveLoans'])} member(s) of staff'),
            ]),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (k, l) in const [('Active', 'Active'), ('Paid', 'Paid'), ('', 'All')])
                filterChipButton(l, _status == k, () => _refilter(() => _status = k)),
            ]),
            const SizedBox(height: 10),
            AppInput(controller: _search, hintText: 'Search number, name, purpose, reference', onChanged: (_) => _refilter(() {})),
            const SizedBox(height: 10),
            AppSelect<String>(
              value: _staffId,
              items: [
                const AppSelectItem(value: 'ALL', label: 'All staff'),
                for (final st in _staff) AppSelectItem(value: tStr(st['poultryStaffId']), label: '${tStr(st['firstName'])} ${tStr(st['lastName'])}'),
              ],
              onChanged: (v) => _refilter(() => _staffId = v ?? 'ALL'),
            ),
            const SizedBox(height: 10),
            AppSelect<String>(
              value: _loanType,
              items: [
                const AppSelectItem(value: 'ALL', label: 'All types'),
                for (final (v, l) in employeeLoanTypes) AppSelectItem(value: v, label: l),
              ],
              onChanged: (v) => _refilter(() => _loanType = v ?? 'ALL'),
            ),
            const SizedBox(height: 14),
            if (_error.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: const Color(0xFFFEF2F2), border: Border.all(color: const Color(0xFFFECACA)), borderRadius: BorderRadius.circular(12)),
                child: Text(_error, style: const TextStyle(fontSize: 13, color: Color(0xFF991B1B))),
              ),
              const SizedBox(height: 14),
            ],
            if (_loading)
              const Row(children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 8),
                Text('Loading…', style: TextStyle(color: TColors.slate500)),
              ])
            else if (_rows.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
                child: Text(filtered ? 'No advances match this filter.' : 'No advances recorded yet.',
                    textAlign: TextAlign.center, style: const TextStyle(color: TColors.slate500)),
              )
            else ...[
              MobileCardList<Map>(
                striped: true,
                items: _rows,
                keyOf: (l) => tStr(l['poultryEmployeeLoanId']),
                primary: (l) =>
                    '${tStr(l['loanNumber']).isNotEmpty ? tStr(l['loanNumber']) : '#${tStr(l['poultryEmployeeLoanId'])}'} · ${tStr(l['staffName'])}',
                secondary: (l) => '${_date(l['disbursementDate'])} · ${employeeLoanTypeLabel(l['loanType'])}',
                trailing: (l) => Padding(padding: const EdgeInsets.only(left: 6), child: _loanBadge(l['status'])),
                highlights: (l) => [
                  Highlight('Outstanding', _fmt(tNum(l['outstandingBalance'])), accent: Accent.blue, wide: true),
                  Highlight('Advanced', _fmt(tNum(l['principalAmount'])), accent: Accent.rose),
                  Highlight('Repaid', _fmt(tNum(l['totalRepaid'])), accent: Accent.emerald),
                ],
                details: (l) => [
                  ('Total repayable', _fmt(tNum(l['totalRepayable']))),
                  ('Repayment', employeeLoanMethodLabel(l['repaymentMethod'])),
                  ('Suggested per payroll', tNum(l['defaultPayrollDeduction']) != 0 ? _fmt(tNum(l['defaultPayrollDeduction'])) : '—'),
                  ('Paid from', tStr(l['cashAccountName']).isEmpty ? '—' : tStr(l['cashAccountName'])),
                  ('Reference', tStr(l['referenceNumber']).isEmpty ? '—' : tStr(l['referenceNumber'])),
                  ('Purpose', tStr(l['purpose']).isNotEmpty ? tStr(l['purpose']) : (tStr(l['description']).isNotEmpty ? tStr(l['description']) : '—')),
                  ('Repayments', tStr(l['repaymentCount']).isEmpty ? '0' : tStr(l['repaymentCount'])),
                ],
                actions: (l) {
                  final st = tStr(l['status']);
                  return [
                    OutlinedButton.icon(onPressed: () => _details(l), icon: const Icon(Icons.visibility_outlined, size: 16), label: const Text('Details')),
                    if (st == 'Draft')
                      OutlinedButton.icon(
                          onPressed: () => _disburse(l), icon: const Icon(Icons.account_balance_wallet_outlined, size: 16), label: const Text('Hand over')),
                    if (st == 'Active')
                      OutlinedButton.icon(onPressed: () => _repay(l), icon: const Icon(Icons.payments_outlined, size: 16), label: const Text('Record repayment')),
                    if (st == 'Draft') TextButton(onPressed: () => _undo(loan: l), child: const Text('Cancel')),
                    if (st == 'Active' || st == 'Paid')
                      TextButton.icon(onPressed: () => _undo(loan: l), icon: const Icon(Icons.undo, size: 16), label: const Text('Reverse')),
                  ];
                },
                table: (items) => TrackerTable(
                  columns: const [
                    TCol('Loan #', width: 110),
                    TCol('Employee', width: 130),
                    TCol('Type', width: 120),
                    TCol('Issued', width: 100),
                    TCol('Advanced', right: true, width: 110),
                    TCol('Repayable', right: true, width: 110),
                    TCol('Repaid', right: true, width: 110),
                    TCol('Outstanding', right: true, width: 120),
                    TCol('Repayment', width: 130),
                    TCol('Status', width: 100),
                    TCol('', width: 200),
                  ],
                  rows: [
                    for (final l in items)
                      () {
                        final st = tStr(l['status']);
                        Widget money(Object? v, {bool bold = false}) => Align(
                            alignment: Alignment.centerRight,
                            child: Text(_fmt(tNum(v)), style: TextStyle(fontWeight: bold ? FontWeight.w600 : null)));
                        return <Widget>[
                          InkWell(
                            onTap: () => _details(l),
                            child: Text(tStr(l['loanNumber']).isNotEmpty ? tStr(l['loanNumber']) : '#${tStr(l['poultryEmployeeLoanId'])}',
                                style: const TextStyle(fontWeight: FontWeight.w500)),
                          ),
                          cellText(tStr(l['staffName'])),
                          Text(employeeLoanTypeLabel(l['loanType']), style: const TextStyle(fontSize: 12)),
                          cellText(_date(l['disbursementDate'])),
                          money(l['principalAmount']),
                          money(l['totalRepayable']),
                          money(l['totalRepaid']),
                          money(l['outstandingBalance'], bold: true),
                          Text(employeeLoanMethodLabel(l['repaymentMethod']), style: const TextStyle(fontSize: 12)),
                          Align(alignment: Alignment.centerLeft, child: _loanBadge(st)),
                          Wrap(alignment: WrapAlignment.end, children: [
                            IconButton(onPressed: () => _details(l), icon: const Icon(Icons.visibility_outlined, size: 18)),
                            if (st == 'Draft') OutlinedButton(onPressed: () => _disburse(l), child: const Text('Hand over')),
                            if (st == 'Active') OutlinedButton(onPressed: () => _repay(l), child: const Text('Repay')),
                            if (st != 'Reversed' && st != 'Cancelled') IconButton(onPressed: () => _undo(loan: l), icon: const Icon(Icons.undo, size: 18)),
                          ]),
                        ];
                      }(),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: Text('Showing $from–$to of $_total', style: const TextStyle(fontSize: 13, color: TColors.slate500))),
                OutlinedButton(
                  onPressed: _offset == 0
                      ? null
                      : () {
                          setState(() => _offset = (_offset - employeeLoanPageSize).clamp(0, _offset));
                          _load();
                        },
                  child: const Text('Previous'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: to >= _total
                      ? null
                      : () {
                          setState(() => _offset += employeeLoanPageSize);
                          _load();
                        },
                  child: const Text('Next'),
                ),
              ]),
            ],
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFFF0F9FF), border: Border.all(color: const Color(0xFFBAE6FD)), borderRadius: BorderRadius.circular(12)),
              child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline, size: 16, color: TColors.sky700),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Repayments taken from a wage do not show as money coming in, because none did — the farm simply paid out less that month. They still reduce what the worker owes. To undo one, reopen the payroll run that created it.',
                    style: TextStyle(fontSize: 12, color: TColors.sky900),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _num(TextEditingController c, VoidCallback changed) => AppInput(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
      onChanged: (_) => changed(),
    );

Widget _switchRow(String title, String hint, bool v, ValueChanged<bool> on) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            Text(hint, style: const TextStyle(fontSize: 11, color: TColors.slate500)),
          ]),
        ),
        Switch(value: v, onChanged: on),
      ]),
    );

AppSelect<String> _accountSelect(List<Map> accounts, String value, ValueChanged<String> on, {required FarmMoney fmt, bool balances = true, String hint = 'Choose a cash account'}) =>
    AppSelect<String>(
      value: value.isEmpty ? null : value,
      hintText: hint,
      items: [
        for (final a in accounts)
          AppSelectItem(
            value: tStr(a['poultryCashAccountId']),
            label: balances ? '${tStr(a['accountName'])} — ${fmt(tNum(a['currentBalance']))}' : tStr(a['accountName']),
          ),
      ],
      onChanged: (v) => on(v ?? ''),
    );

/// New loan or advance.
class NewEmployeeLoanDialog extends StatefulWidget {
  const NewEmployeeLoanDialog({super.key, required this.staff, required this.accounts, required this.fmt, required this.onSave});
  final List<Map> staff, accounts;
  final FarmMoney fmt;
  final Future<void> Function(Map<String, Object?> input) onSave;

  @override
  State<NewEmployeeLoanDialog> createState() => _NewEmployeeLoanDialogState();
}

class _NewEmployeeLoanDialogState extends State<NewEmployeeLoanDialog> {
  String _staff = '', _type = 'EmployeeLoan', _method = 'PayrollDeduction', _account = '';
  String _date = DateTime.now().toUtc().toIso8601String().substring(0, 10);
  final _amount = TextEditingController(text: '0'), _deduction = TextEditingController(text: '0');
  final _interest = TextEditingController(text: '0'), _purpose = TextEditingController(), _ref = TextEditingController();
  bool _interestOn = false, _now = true, _saving = false;

  @override
  void dispose() {
    for (final c in [_amount, _deduction, _interest, _purpose, _ref]) {
      c.dispose();
    }
    super.dispose();
  }

  num get _principal => num.tryParse(_amount.text) ?? 0;
  num get _interestAmt => num.tryParse(_interest.text) ?? 0;
  bool get _canSave => _staff.isNotEmpty && _principal > 0 && (!_now || _account.isNotEmpty);

  Future<void> _save() async {
    setState(() => _saving = true);
    final ded = num.tryParse(_deduction.text) ?? 0;
    await widget.onSave({
      'poultryStaffId': int.parse(_staff),
      'loanType': _type,
      'principalAmount': _principal,
      'disbursementDate': _date,
      'purpose': _purpose.text.isEmpty ? null : _purpose.text,
      'notes': null,
      'repaymentMethod': _method,
      'defaultPayrollDeduction': ded == 0 ? null : ded,
      'interestEnabled': _interestOn,
      'interestAmount': _interestOn ? _interestAmt : 0,
      'disburseNow': _now,
      'poultryCashAccountId': _now ? int.parse(_account) : null,
      'paymentMethod': _now ? 'Cash' : null,
      'referenceNumber': _ref.text.isEmpty ? null : _ref.text,
    });
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final fmt = widget.fmt;
    return AlertDialog(
      scrollable: true,
      title: const Row(children: [
        Icon(Icons.payments_outlined, color: Color(0xFF4F46E5)),
        SizedBox(width: 6),
        Flexible(child: Text('New loan or advance')),
      ]),
      content: SizedBox(
        width: 560,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('This is money the worker will owe you. It is not a cost, and it does not touch Profit & Loss.',
              style: TextStyle(fontSize: 13, color: TColors.slate500)),
          const SizedBox(height: 12),
          FilterLabel(
            'Employee *',
            AppSelect<String>(
              value: _staff.isEmpty ? null : _staff,
              hintText: 'Choose a member of staff',
              items: [
                for (final s in widget.staff)
                  AppSelectItem(value: tStr(s['poultryStaffId']), label: '${tStr(s['firstName'])} ${tStr(s['lastName'])} — ${tStr(s['role'])}'),
              ],
              onChanged: (v) => setState(() => _staff = v ?? ''),
            ),
          ),
          const SizedBox(height: 10),
          FilterLabel(
            'Type *',
            AppSelect<String>(
              value: _type,
              items: [for (final (v, l) in employeeLoanTypes) AppSelectItem(value: v, label: l)],
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
          ),
          const SizedBox(height: 10),
          FilterLabel('Amount *', _num(_amount, () => setState(() {}))),
          const SizedBox(height: 10),
          FilterLabel('Date *', AppDateField(value: businessDateAsDateTime(_date), onChanged: (d) => setState(() => _date = d == null ? _date : isoDay(d)))),
          const SizedBox(height: 10),
          FilterLabel(
            'How will it be repaid?',
            AppSelect<String>(
              value: _method,
              items: [for (final (v, l) in employeeLoanRepaymentMethods) AppSelectItem(value: v, label: l)],
              onChanged: (v) => setState(() => _method = v ?? _method),
            ),
          ),
          const SizedBox(height: 10),
          FilterLabel('Suggested amount per payroll', _num(_deduction, () => setState(() {}))),
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Offered when preparing payroll. Nothing is deducted automatically.', style: TextStyle(fontSize: 11, color: TColors.slate500)),
          ),
          const SizedBox(height: 10),
          FilterLabel('Purpose', AppInput(controller: _purpose, hintText: 'School fees, medical, rent…')),
          const SizedBox(height: 10),
          _switchRow('Charge interest', 'Most farm advances are interest-free.', _interestOn, (v) => setState(() => _interestOn = v)),
          if (_interestOn) ...[const SizedBox(height: 10), FilterLabel('Interest amount', _num(_interest, () => setState(() {})))],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: TColors.slate50, borderRadius: BorderRadius.circular(6)),
            child: Text.rich(TextSpan(children: [
              const TextSpan(text: 'Total the worker will owe: '),
              TextSpan(text: fmt(_principal + (_interestOn ? _interestAmt : 0)), style: const TextStyle(fontWeight: FontWeight.w700)),
            ]), style: const TextStyle(fontSize: 13)),
          ),
          const SizedBox(height: 10),
          _switchRow('Hand the money over now', 'Off records the agreement only — nothing leaves the cash account and the worker owes nothing yet.', _now,
              (v) => setState(() => _now = v)),
          if (_now) ...[
            const SizedBox(height: 10),
            FilterLabel('Pay from *', _accountSelect(widget.accounts, _account, (v) => setState(() => _account = v), fmt: fmt)),
            const SizedBox(height: 10),
            FilterLabel('Reference', AppInput(controller: _ref, hintText: 'MoMo ID, voucher number…')),
          ],
        ]),
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _saving || !_canSave ? null : _save, child: Text(_now ? 'Record and hand over' : 'Record only')),
      ],
    );
  }
}

/// Hand over a draft advance.
class DisburseLoanDialog extends StatefulWidget {
  const DisburseLoanDialog({super.key, required this.loan, required this.accounts, required this.fmt, required this.onSave});
  final Map loan;
  final List<Map> accounts;
  final FarmMoney fmt;
  final Future<void> Function(Map<String, Object?> input) onSave;

  @override
  State<DisburseLoanDialog> createState() => _DisburseLoanDialogState();
}

class _DisburseLoanDialogState extends State<DisburseLoanDialog> {
  String _account = '';
  final _ref = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _ref.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.loan;
    final fmt = widget.fmt;
    return AlertDialog(
      scrollable: true,
      title: Text('Hand over ${fmt(tNum(l['principalAmount']))}'),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            'To ${tStr(l['staffName'])}. The cash leaves the account and ${tStr(l['staffName'])} will owe ${fmt(tNum(l['totalRepayable']))}. No expense is recorded.',
            style: const TextStyle(fontSize: 13, color: TColors.slate500),
          ),
          const SizedBox(height: 12),
          FilterLabel('Pay from *', _accountSelect(widget.accounts, _account, (v) => setState(() => _account = v), fmt: fmt)),
          const SizedBox(height: 10),
          FilterLabel('Reference', AppInput(controller: _ref)),
        ]),
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving || _account.isEmpty
              ? null
              : () async {
                  setState(() => _saving = true);
                  await widget.onSave({
                    'poultryCashAccountId': int.parse(_account),
                    'paymentMethod': 'Cash',
                    'referenceNumber': _ref.text.isEmpty ? null : _ref.text,
                  });
                  if (mounted) setState(() => _saving = false);
                },
          child: const Text('Hand it over'),
        ),
      ],
    );
  }
}

/// Record a repayment the worker hands over (a payroll deduction is added on the payroll run).
class RepayLoanDialog extends StatefulWidget {
  const RepayLoanDialog({super.key, required this.loan, required this.accounts, required this.fmt, required this.onSave});
  final Map loan;
  final List<Map> accounts;
  final FarmMoney fmt;
  final Future<void> Function(Map<String, Object?> input) onSave;

  @override
  State<RepayLoanDialog> createState() => _RepayLoanDialogState();
}

class _RepayLoanDialogState extends State<RepayLoanDialog> {
  final _amount = TextEditingController(text: '0'), _ref = TextEditingController();
  String _source = 'ManualCash', _account = '', _date = DateTime.now().toUtc().toIso8601String().substring(0, 10);
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _ref.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.loan;
    final fmt = widget.fmt;
    final amount = num.tryParse(_amount.text) ?? 0;
    final owed = tNum(l['outstandingBalance']);
    final over = amount > owed;
    final left = owed - amount > 0 ? owed - amount : 0;
    return AlertDialog(
      scrollable: true,
      title: const Text('Record a repayment'),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            '${tStr(l['staffName'])} · ${tStr(l['loanNumber'])} · ${fmt(owed)} outstanding. Money the worker hands over — a payroll deduction is added on the payroll run instead.',
            style: const TextStyle(fontSize: 13, color: TColors.slate500),
          ),
          const SizedBox(height: 12),
          FilterLabel('Amount *', _num(_amount, () => setState(() {}))),
          if (over)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('More than the ${fmt(owed)} still owed.', style: const TextStyle(fontSize: 11, color: TColors.rose600)),
            ),
          const SizedBox(height: 10),
          FilterLabel('Date', AppDateField(value: businessDateAsDateTime(_date), onChanged: (d) => setState(() => _date = d == null ? _date : isoDay(d)))),
          const SizedBox(height: 10),
          FilterLabel(
            'How *',
            AppSelect<String>(
              value: _source,
              items: [for (final (v, lb) in employeeLoanRepaymentSources) AppSelectItem(value: v, label: lb)],
              onChanged: (v) => setState(() => _source = v ?? _source),
            ),
          ),
          const SizedBox(height: 10),
          FilterLabel('Into *', _accountSelect(widget.accounts, _account, (v) => setState(() => _account = v), fmt: fmt, balances: false, hint: 'Cash account')),
          const SizedBox(height: 10),
          FilterLabel('Reference', AppInput(controller: _ref, hintText: 'MoMo ID, receipt number…')),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: TColors.slate50, borderRadius: BorderRadius.circular(6)),
            child: Text.rich(TextSpan(children: [
              const TextSpan(text: 'Still owed afterwards: '),
              TextSpan(text: fmt(left), style: const TextStyle(fontWeight: FontWeight.w700)),
            ]), style: const TextStyle(fontSize: 13)),
          ),
        ]),
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving || amount <= 0 || over || _account.isEmpty
              ? null
              : () async {
                  setState(() => _saving = true);
                  await widget.onSave({
                    'poultryEmployeeLoanId': tIntOrNull(l['poultryEmployeeLoanId']),
                    'amount': amount,
                    'sourceType': _source,
                    'repaymentDate': _date,
                    'poultryCashAccountId': int.parse(_account),
                    'referenceNumber': _ref.text.isEmpty ? null : _ref.text,
                  });
                  if (mounted) setState(() => _saving = false);
                },
          child: const Text('Record it'),
        ),
      ],
    );
  }
}

/// The loan's figures, facts and repayment history.
class LoanDetailDialog extends StatelessWidget {
  const LoanDetailDialog({super.key, required this.loan, required this.rows, required this.loading, required this.fmt, required this.onReverse});
  final Map loan;
  final List<Map> rows;
  final bool loading;
  final FarmMoney fmt;
  final ValueChanged<Map> onReverse;

  @override
  Widget build(BuildContext context) {
    final l = loan;
    Widget fig(String label, String value, {bool strong = false}) => Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, letterSpacing: .4, color: TColors.slate500)),
            Text(value, style: TextStyle(fontSize: 16, fontWeight: strong ? FontWeight.w700 : FontWeight.w600, color: strong ? TColors.slate900 : TColors.slate700)),
          ]),
        );
    final facts = [
      ('Purpose', tStr(l['purpose']).isNotEmpty ? tStr(l['purpose']) : (tStr(l['description']).isNotEmpty ? tStr(l['description']) : '—')),
      ('Interest', l['interestEnabled'] == true ? fmt(tNum(l['interestAmount'])) : 'None'),
      ('Suggested per payroll', tNum(l['defaultPayrollDeduction']) != 0 ? fmt(tNum(l['defaultPayrollDeduction'])) : '—'),
      ('Paid from', tStr(l['cashAccountName']).isEmpty ? '—' : tStr(l['cashAccountName'])),
      ('Reference', tStr(l['referenceNumber']).isEmpty ? '—' : tStr(l['referenceNumber'])),
      ('Handed over', _date(l['disbursedAt'])),
    ];
    return AlertDialog(
      scrollable: true,
      title: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(tStr(l['loanNumber']).isNotEmpty ? tStr(l['loanNumber']) : '#${tStr(l['poultryEmployeeLoanId'])}'),
        const Text('·', style: TextStyle(color: TColors.slate400)),
        Text(tStr(l['staffName'])),
        _loanBadge(l['status']),
      ]),
      content: SizedBox(
        width: 640,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            '${employeeLoanTypeLabel(l['loanType'])} · issued ${_date(l['disbursementDate'])} · repaid by ${employeeLoanMethodLabel(l['repaymentMethod'])}',
            style: const TextStyle(fontSize: 13, color: TColors.slate500),
          ),
          const SizedBox(height: 12),
          twoUp([
            fig('Advanced', fmt(tNum(l['principalAmount']))),
            fig('Repayable', fmt(tNum(l['totalRepayable']))),
            fig('Repaid', fmt(tNum(l['totalRepaid']))),
            fig('Outstanding', fmt(tNum(l['outstandingBalance'])), strong: true),
          ]),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
            child: twoUp([
              for (final (h, v) in facts)
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(h.toUpperCase(), style: const TextStyle(fontSize: 11, letterSpacing: .4, color: TColors.slate500)),
                  Text(v, style: const TextStyle(fontSize: 13, color: TColors.slate900)),
                ]),
            ]),
          ),
          if (tStr(l['notes']).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Notes: ${tStr(l['notes'])}', style: const TextStyle(fontSize: 13))),
          if (tStr(l['reversalReason']).isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 4), child: Text('Reversal reason: ${tStr(l['reversalReason'])}', style: const TextStyle(fontSize: 13))),
          const SizedBox(height: 12),
          const Text('REPAYMENT HISTORY', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: .4, color: TColors.slate500)),
          const SizedBox(height: 4),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Row(children: [
                SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 8),
                Text('Loading repayments…', style: TextStyle(fontSize: 13, color: TColors.slate500)),
              ]),
            )
          else if (rows.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text('Nothing repaid yet.', style: TextStyle(fontSize: 13, color: TColors.slate500)))
          else
            TrackerTable(
              columns: const [
                TCol('Date', width: 100),
                TCol('How', width: 110),
                TCol('Reference', width: 170),
                TCol('Amount', right: true, width: 110),
                TCol('Balance before', right: true, width: 120),
                TCol('Balance after', right: true, width: 120),
                TCol('Status', width: 100),
                TCol('', width: 110),
              ],
              rows: [
                for (final r in rows)
                  () {
                    final reversed = tStr(r['status']) == 'Reversed';
                    final payroll = tStr(r['sourceType']) == 'Payroll';
                    final grey = reversed ? const TextStyle(color: TColors.slate400) : null;
                    return <Widget>[
                      Text(_date(r['repaymentDate']), style: grey),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(employeeLoanSourceLabel(r['sourceType']), style: grey),
                        if (payroll) const Text('no cash moved', style: TextStyle(fontSize: 11, color: TColors.slate400)),
                      ]),
                      Text(
                        payroll
                            ? (tStr(r['payrollPeriodStart']).isNotEmpty
                                ? 'Payroll ${_date(r['payrollPeriodStart'])} – ${_date(r['payrollPeriodEnd'])}'
                                : 'Payroll run ${tStr(r['poultryPayrollRunId']).isEmpty ? '—' : tStr(r['poultryPayrollRunId'])}')
                            : (tStr(r['referenceNumber']).isNotEmpty
                                ? tStr(r['referenceNumber'])
                                : (tStr(r['cashAccountName']).isNotEmpty ? tStr(r['cashAccountName']) : '—')),
                        style: const TextStyle(fontSize: 12),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(fmt(tNum(r['amount'])),
                            style: TextStyle(decoration: reversed ? TextDecoration.lineThrough : null, color: grey?.color)),
                      ),
                      Align(alignment: Alignment.centerRight, child: Text(fmt(tNum(r['balanceBefore'])), style: grey)),
                      Align(alignment: Alignment.centerRight, child: Text(fmt(tNum(r['balanceAfter'])), style: grey)),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: reversed
                            ? Tooltip(
                                message: tStr(r['reversalReason']),
                                child: const TBadge('Reversed', bg: TColors.slate100, fg: TColors.slate600),
                              )
                            : const TBadge('Posted', bg: TColors.emerald100, fg: TColors.emerald700),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: !reversed && !payroll
                            ? TextButton.icon(onPressed: () => onReverse(r), icon: const Icon(Icons.undo, size: 15), label: const Text('Reverse'))
                            : !reversed && payroll
                                ? const Tooltip(
                                    message: 'Reopen the payroll run to reverse this repayment.',
                                    child: Text('via payroll', style: TextStyle(fontSize: 11, color: TColors.slate400)),
                                  )
                                : const SizedBox.shrink(),
                      ),
                    ];
                  }(),
              ],
            ),
        ]),
      ),
      actions: [OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}

/// The reason prompt behind Cancel / Reverse (one dialog for all three).
class _UndoDialog extends StatefulWidget {
  const _UndoDialog({required this.title, required this.description, required this.onUndo});
  final String title, description;
  final Future<bool> Function(String? reason) onUndo;

  @override
  State<_UndoDialog> createState() => _UndoDialogState();
}

class _UndoDialogState extends State<_UndoDialog> {
  final _reason = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: TColors.amber600),
          const SizedBox(width: 6),
          Flexible(child: Text(widget.title)),
        ]),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(widget.description, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 12),
            FilterLabel('Reason', AppInput(controller: _reason, hintText: 'Why is this being undone?', minLines: 2, maxLines: 4)),
          ]),
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Keep it')),
          FilledButton(
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    final ok = await widget.onUndo(_reason.text.isEmpty ? null : _reason.text);
                    if (!context.mounted) return;
                    if (ok) {
                      Navigator.pop(context);
                    } else {
                      setState(() => _busy = false);
                    }
                  },
            child: const Text('Undo it'),
          ),
        ],
      );
}
