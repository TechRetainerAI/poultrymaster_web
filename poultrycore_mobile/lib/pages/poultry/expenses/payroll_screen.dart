import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../shared/business_dates.dart';
import '../../shared/company_clock.dart';
import '../money/money_widgets.dart';
import '../reports/report_format.dart';
import '../reports/report_routes.dart' show openAppHref;
import '../sales/balances_logic.dart' show pageSlice;
import '../sales/balances_widgets.dart';
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../trackers/tracker_widgets.dart';

/// Poultry → Expenses → Payroll, as `app/poultry-payroll/page.tsx`: payroll
/// runs (Draft → Approved → Paid, reopen, cancel, delete), their staff lines
/// and the deductions behind each line (`payroll-deductions-dialog.tsx`).

const payrollStatuses = ['Draft', 'Approved', 'Paid', 'Reopened', 'Cancelled'];
const payrollPaymentMethods = ['Cash', 'MoMo', 'Bank'];
const payrollDeductionTypes = [
  ('EmployeeLoanRepayment', 'Employee loan repayment'),
  ('SalaryAdvanceRepayment', 'Salary advance repayment'),
  ('OtherDeduction', 'Other deduction'),
];
String payrollDeductionTypeLabel(Object? t) => payrollDeductionTypes.where((e) => e.$1 == tStr(t)).firstOrNull?.$2 ?? tStr(t);

/// STATUS_STYLE: (bg, fg).
(Color, Color) payrollStatusTone(Object? s) => switch (tStr(s)) {
      'Approved' => (TColors.blue100, const Color(0xFF1D4ED8)),
      'Paid' => (const Color(0xFFDCFCE7), const Color(0xFF15803D)),
      'Reopened' => (TColors.amber100, TColors.amber700),
      'Cancelled' => (const Color(0xFFFFE4E6), TColors.rose700),
      _ => (TColors.slate100, TColors.slate700),
    };

Widget payrollBadge(Object? s) {
  final (bg, fg) = payrollStatusTone(s);
  return TBadge(tStr(s), bg: bg, fg: fg);
}

String payrollDay(Object? s) => tStr(s).isEmpty ? '—' : tStr(s).split('T').first;

/// payrollDeductionFor: what an advance takes off a payslip — only advances
/// repaid by payroll (or mixed), never more than is still owed.
num payrollDeductionFor(Map e) {
  final m = tStr(e['repaymentMethod']);
  if (m != 'PayrollDeduction' && m != 'Mixed') return 0;
  final d = tNum(e['defaultPayrollDeduction']), o = tNum(e['outstandingBalance']);
  return d < o ? d : o;
}

bool payrollEditable(Object? status) => tStr(status) == 'Draft' || tStr(status) == 'Reopened';

String _today() => DateTime.now().toUtc().toIso8601String().substring(0, 10);

class PayrollScreen extends StatefulWidget {
  const PayrollScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  List<Map> _runs = [], _accounts = [], _staff = [];
  bool _loading = true;
  String _status = 'all';
  int _page = 1, _pageSize = 10, _lastTotal = -1;
  FarmMoney _gh = const FarmMoney();
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  String get _q => 'farmId=${Uri.encodeQueryComponent(_farmId)}';
  String get _me => Uri.encodeQueryComponent(widget.session.tokens.userId ?? '');

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _gh = m);
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
        _api.get('/api/Poultry/payroll-runs', query: q),
        _api.get('/api/Poultry/cash-accounts', query: q),
        _api.get('/api/Poultry/staff', query: q),
      ]);
      if (!mounted) return;
      setState(() {
        _runs = rowsOf(r[0]);
        _accounts = rowsOf(r[1]);
        _staff = rowsOf(r[2]);
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load payroll', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  int _id(Map r) => tIntOrNull(r['poultryPayrollRunId']) ?? 0;

  Future<void> _newRun() async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _NewRunDialog(session: widget.session, company: widget.company, accounts: _accounts),
    );
    if (done == true) _load();
  }

  Future<void> _lines(Map r) async {
    try {
      final full = await _api.get('/api/Poultry/payroll-runs/${_id(r)}', query: {'farmId': _farmId});
      if (!mounted || full is! Map) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PayrollLinesScreen(session: widget.session, company: widget.company, run: full, staff: _staff, fmt: _gh),
      ));
      _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not open run', description: e.message, error: true);
    }
  }

  Future<void> _approve(Map r) async {
    try {
      await _api.post('/api/Poultry/payroll-runs/${_id(r)}/approve?$_q&approvedBy=$_me');
      if (mounted) trackerToast(context, 'Run approved', description: 'A linked expense was created.');
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Approve failed', description: e.message, error: true);
    }
  }

  Future<void> _markPaid(Map r) async {
    String date = _today();
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        return AlertDialog(
          scrollable: true,
          title: const Row(children: [
            Icon(Icons.check_circle_outline, color: Color(0xFF16A34A)),
            SizedBox(width: 6),
            Flexible(child: Text('Mark paid')),
          ]),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(
                'Posts a cash-out of ${_gh(tNum(r['totalNetPay']))} to ${tStr(r['cashAccountName']).isEmpty ? "the run's cash account" : tStr(r['cashAccountName'])}.',
                style: const TextStyle(fontSize: 13, color: TColors.slate500),
              ),
              const SizedBox(height: 12),
              FilterLabel('Pay date', AppDateField(value: businessDateAsDateTime(date), onChanged: (d) => set(() => date = d == null ? date : isoDay(d)))),
              if (tIntOrNull(r['poultryCashAccountId']) == null)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'No cash account is set on this run — no cash-out will be posted. Edit the run to set one first if you want the balance to move.',
                    style: TextStyle(fontSize: 12, color: TColors.amber700),
                  ),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                try {
                  await _api.post('/api/Poultry/payroll-runs/${_id(r)}/mark-paid?$_q&paidBy=$_me', body: {'payDate': date});
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) trackerToast(context, 'Run marked paid', description: 'Cash-out posted to the selected account.');
                  await _load();
                } on ApiException catch (e) {
                  if (mounted) trackerToast(context, 'Mark paid failed', description: e.message, error: true);
                }
              },
              child: const Text('Mark paid'),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _reason(Map r, String kind) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _ReasonDialog(
        kind: kind,
        onConfirm: (reason) async {
          if (kind == 'cancel') {
            await _api.post('/api/Poultry/payroll-runs/${_id(r)}/cancel?$_q&cancelledBy=$_me', body: {'reason': reason});
            if (mounted) trackerToast(context, 'Run cancelled');
          } else {
            await _api.post('/api/Poultry/payroll-runs/${_id(r)}/unapprove?$_q&reopenedBy=$_me', body: {'reason': reason});
            if (mounted) trackerToast(context, 'Run reopened', description: 'Expense and cash-out reversed.');
          }
        },
      ),
    );
    if (done == true) _load();
  }

  Future<void> _delete(Map r) async {
    final ok = await confirmDelete(context,
        title: 'Delete this payroll run?',
        description: 'Permanently deletes the run and its lines. Only Draft, Reopened or Cancelled runs can be deleted.',
        confirmLabel: 'Delete run');
    if (!ok) return;
    try {
      await _api.delete('/api/Poultry/payroll-runs/${_id(r)}?$_q&deletedBy=$_me');
      if (mounted) trackerToast(context, 'Run deleted');
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not delete run', description: e.message, error: true);
    }
  }

  void _details(Map r) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PayrollRunDetailScreen(session: widget.session, company: widget.company, runId: _id(r)),
      ));

  /// renderActions: which buttons a run's status allows.
  List<Widget> _actions(Map r, {bool icons = false}) {
    final st = tStr(r['status']);
    Widget b(String label, IconData icon, VoidCallback on, {Color? color}) => icons
        ? IconButton(tooltip: label, onPressed: on, icon: Icon(icon, size: 18, color: color))
        : OutlinedButton.icon(
            onPressed: on,
            style: OutlinedButton.styleFrom(foregroundColor: color),
            icon: Icon(icon, size: 16),
            label: Text(label),
          );
    return [
      b('Details', Icons.visibility_outlined, () => _details(r)),
      b('Lines', Icons.people_outline, () => _lines(r)),
      if (st == 'Draft' || st == 'Reopened') b('Approve', Icons.check_circle_outline, () => _approve(r), color: const Color(0xFF1D4ED8)),
      if (st == 'Approved') b('Mark paid', Icons.payments_outlined, () => _markPaid(r), color: const Color(0xFF15803D)),
      if (st == 'Approved' || st == 'Paid') b('Reopen', Icons.replay, () => _reason(r, 'unapprove'), color: TColors.amber700),
      if (st == 'Draft' || st == 'Approved') b('Cancel', Icons.cancel_outlined, () => _reason(r, 'cancel'), color: TColors.rose600),
      if (st == 'Draft' || st == 'Reopened' || st == 'Cancelled') b('Delete', Icons.delete_outline, () => _delete(r), color: TColors.red600),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-payroll');
    final visible = _status == 'all' ? _runs : [for (final r in _runs) if (tStr(r['status']) == _status) r];
    if (visible.length != _lastTotal) {
      _lastTotal = visible.length;
      _page = 1;
    }
    final pageRows = pageSlice(visible, _page, _pageSize);
    final netPaid = _runs.where((r) => tStr(r['status']) == 'Paid').fold<num>(0, (s, r) => s + tNum(r['totalNetPay']));
    Widget stat(String label, String value, {Color? color}) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: color)),
          ]),
        );
    String period(Map r) => '${fmtDateTime(r['periodStart'], r, _offset)} → ${fmtDateTime(r['periodEnd'], r, _offset)}';

    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Payroll')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            const Row(children: [
              Icon(Icons.payments_outlined, size: 24, color: Color(0xFF16A34A)),
              SizedBox(width: 8),
              Expanded(child: Text('Payroll', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900))),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                onPressed: () => openAppHref(context, widget.session, widget.company, '/poultry-employee-loans', label: 'Employee Loans & Advances'),
                icon: const Icon(Icons.volunteer_activism_outlined, size: 16),
                label: const Text('Employee Loans & Advances'),
              ),
              FilledButton.icon(onPressed: _newRun, icon: const Icon(Icons.add, size: 16), label: const Text('New payroll run')),
            ]),
            const SizedBox(height: 14),
            twoUp([
              stat('Total runs', '${_runs.length}'),
              stat('Draft', '${_runs.where((r) => tStr(r['status']) == 'Draft').length}'),
              stat('Approved', '${_runs.where((r) => tStr(r['status']) == 'Approved').length}'),
              stat('Total net paid', _gh(netPaid), color: const Color(0xFF15803D)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              const Text('Status', style: TextStyle(fontSize: 14, color: TColors.slate600)),
              const SizedBox(width: 10),
              Expanded(
                child: AppSelect<String>(
                  value: _status,
                  items: [const AppSelectItem(value: 'all', label: 'All'), for (final s in payrollStatuses) AppSelectItem(value: s, label: s)],
                  onChanged: (v) => setState(() => _status = v ?? 'all'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(padding: EdgeInsets.all(16), child: LoadingLine('Loading…'))
            else if (_runs.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
                child: const Text('No payroll runs yet. Create one to start paying staff.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate500)),
              )
            else
              MobileCardList<Map>(
                striped: true,
                stripeBlue: true,
                items: pageRows,
                keyOf: (r) => '${_id(r)}',
                primary: (r) => '${payrollDay(r['periodStart'])} → ${payrollDay(r['periodEnd'])}',
                secondary: (r) => tStr(r['cashAccountName']).isEmpty ? 'No cash account' : tStr(r['cashAccountName']),
                trailing: (r) => Padding(padding: const EdgeInsets.only(left: 6), child: payrollBadge(r['status'])),
                highlights: (r) => [
                  Highlight('Net pay', _gh(tNum(r['totalNetPay'])), accent: Accent.blue),
                  Highlight('Deductions', _gh(tNum(r['totalDeductions'])), accent: Accent.rose),
                ],
                details: (r) => [
                  ('Period', period(r)),
                  ('Gross', _gh(tNum(r['totalGrossPay']))),
                  ('Cash account', tStr(r['cashAccountName']).isEmpty ? '—' : tStr(r['cashAccountName'])),
                  ('Status', tStr(r['status'])),
                ],
                actions: _actions,
                table: (items) => TrackerTable(
                  columns: const [
                    TCol('Period', width: 230),
                    TCol('Gross', right: true, width: 110),
                    TCol('Deductions', right: true, width: 110),
                    TCol('Net', right: true, width: 110),
                    TCol('Cash account', width: 120),
                    TCol('Status', width: 100),
                    TCol('Actions', right: true, width: 300),
                  ],
                  rows: [
                    for (final r in items)
                      [
                        Text(period(r), style: const TextStyle(fontWeight: FontWeight.w500)),
                        Align(alignment: Alignment.centerRight, child: Text(_gh(tNum(r['totalGrossPay'])))),
                        Align(alignment: Alignment.centerRight, child: Text(_gh(tNum(r['totalDeductions'])))),
                        Align(alignment: Alignment.centerRight, child: Text(_gh(tNum(r['totalNetPay'])), style: const TextStyle(fontWeight: FontWeight.w600))),
                        cellText(tStr(r['cashAccountName']).isEmpty ? '—' : tStr(r['cashAccountName'])),
                        Align(alignment: Alignment.centerLeft, child: payrollBadge(r['status'])),
                        Wrap(alignment: WrapAlignment.end, children: _actions(r, icons: true)),
                      ],
                  ],
                ),
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

/// New payroll run: a Draft, then add staff lines.
class _NewRunDialog extends StatefulWidget {
  const _NewRunDialog({required this.session, required this.company, required this.accounts});
  final Session session;
  final Company company;
  final List<Map> accounts;

  @override
  State<_NewRunDialog> createState() => _NewRunDialogState();
}

class _NewRunDialogState extends State<_NewRunDialog> {
  String _start = _today(), _end = _today(), _pay = '', _account = '0';
  final _notes = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() => _saving = true);
    try {
      await widget.session.farmClient.post(
        '/api/Poultry/payroll-runs?createdBy=${Uri.encodeQueryComponent(widget.session.tokens.userId ?? '')}',
        body: {
          'periodStart': _start,
          'periodEnd': _end,
          'payDate': _pay.isEmpty ? null : _pay,
          'poultryCashAccountId': _account == '0' ? null : int.parse(_account),
          'notes': _notes.text.isEmpty ? null : _notes.text,
          'farmId': widget.company.farmId,
        },
      );
      if (!mounted) return;
      trackerToast(context, 'Payroll run created');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Could not create run', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: const Row(children: [
          Icon(Icons.payments_outlined, color: Color(0xFF16A34A)),
          SizedBox(width: 6),
          Flexible(child: Text('New payroll run')),
        ]),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Create a Draft run, then add staff lines', style: TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 12),
            formSection('Period', const Color(0xFF4F46E5), [
              FilterLabel('Period start *', AppDateField(value: businessDateAsDateTime(_start), onChanged: (d) => setState(() => _start = d == null ? _start : isoDay(d)))),
              FilterLabel('Period end *', AppDateField(value: businessDateAsDateTime(_end), onChanged: (d) => setState(() => _end = d == null ? _end : isoDay(d)))),
              FilterLabel(
                'Pay date',
                AppDateField(
                  value: _pay.isEmpty ? null : businessDateAsDateTime(_pay),
                  hintText: 'dd/mm/yyyy',
                  onChanged: (d) => setState(() => _pay = d == null ? '' : isoDay(d)),
                ),
              ),
              FilterLabel(
                'Cash account (paid from)',
                AppSelect<String>(
                  value: _account,
                  hintText: 'Select account',
                  items: [
                    const AppSelectItem(value: '0', label: '— None —'),
                    for (final a in widget.accounts)
                      if (a['isActive'] == true) AppSelectItem(value: tStr(a['poultryCashAccountId']), label: tStr(a['accountName'])),
                  ],
                  onChanged: (v) => setState(() => _account = v ?? '0'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            formSection('Notes', TColors.slate600, [FilterLabel('Notes', AppInput(controller: _notes))]),
          ]),
        ),
        actions: [
          redCancelButton(_saving ? null : () => Navigator.pop(context, false)),
          FilledButton(onPressed: _saving ? null : _create, child: Text(_saving ? 'Creating…' : 'Create run')),
        ],
      );
}

/// Reopen (reason required) or Cancel (reason optional).
class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.kind, required this.onConfirm});
  final String kind;
  final Future<void> Function(String reason) onConfirm;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reopen = widget.kind == 'unapprove';
    return AlertDialog(
      scrollable: true,
      title: Text(reopen ? 'Reopen run' : 'Cancel run'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            reopen ? 'Reverses the linked expense and any cash-out, and returns the run to Reopened.' : 'Cancels this run and removes any linked expense.',
            style: const TextStyle(fontSize: 13, color: TColors.slate500),
          ),
          const SizedBox(height: 12),
          FilterLabel(reopen ? 'Reason *' : 'Reason', AppInput(controller: _reason, hintText: 'Why?')),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Back')),
        FilledButton(
          onPressed: () async {
            if (reopen && _reason.text.trim().isEmpty) return trackerToast(context, 'A reason is required', error: true);
            try {
              await widget.onConfirm(_reason.text);
              if (context.mounted) Navigator.pop(context, true);
            } on ApiException catch (e) {
              if (context.mounted) trackerToast(context, 'Action failed', description: e.message, error: true);
            }
          },
          child: Text(reopen ? 'Reopen' : 'Cancel run'),
        ),
      ],
    );
  }
}

/// The run's staff lines (the web's "Staff lines" dialog) as a page: the
/// lines, each line's deductions, and the add / update form while editable.
class PayrollLinesScreen extends StatefulWidget {
  const PayrollLinesScreen({super.key, required this.session, required this.company, required this.run, required this.staff, required this.fmt});
  final Session session;
  final Company company;
  final Map run;
  final List<Map> staff;
  final FarmMoney fmt;

  @override
  State<PayrollLinesScreen> createState() => _PayrollLinesScreenState();
}

class _PayrollLinesScreenState extends State<PayrollLinesScreen> {
  late Map _run = widget.run;
  List<Map> _staffLoans = [];
  bool _loansBusy = false, _saving = false;
  String _staffId = '0', _method = 'Cash';
  final _basic = TextEditingController(text: '0'), _daily = TextEditingController(text: '0'), _comm = TextEditingController(text: '0');
  final _bonus = TextEditingController(text: '0'), _ded = TextEditingController(text: '0'), _notes = TextEditingController();

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  int get _runId => tIntOrNull(_run['poultryPayrollRunId']) ?? 0;
  FarmMoney get _gh => widget.fmt;

  @override
  void dispose() {
    for (final c in [_basic, _daily, _comm, _bonus, _ded, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _refresh() async {
    final full = await _api.get('/api/Poultry/payroll-runs/$_runId', query: {'farmId': _farmId});
    if (mounted && full is Map) setState(() => _run = full);
  }

  void _resetForm() {
    _staffId = '0';
    _method = 'Cash';
    for (final c in [_basic, _daily, _comm, _bonus, _ded]) {
      c.text = '0';
    }
    _notes.clear();
    _staffLoans = [];
  }

  /// prefillFromStaff: the member's base pay, then their advances' deductions.
  Future<void> _pickStaff(String id) async {
    final s = widget.staff.where((x) => tStr(x['poultryStaffId']) == id).firstOrNull;
    setState(() {
      _staffId = id;
      if (s != null) _basic.text = _plain(tNum(s['basePay']));
    });
    if (id == '0') return setState(() => _staffLoans = []);
    setState(() => _loansBusy = true);
    try {
      final list = rowsOf(await _api.get('/api/Poultry/employee-loans/eligible', query: {'farmId': _farmId, 'staffId': id}));
      if (!mounted) return;
      setState(() {
        _staffLoans = list;
        _ded.text = _plain(list.fold<num>(0, (s, e) => s + payrollDeductionFor(e)));
      });
    } on ApiException {
      if (mounted) setState(() => _staffLoans = []);
    }
    if (mounted) setState(() => _loansBusy = false);
  }

  static String _plain(num v) => v == v.roundToDouble() ? v.toInt().toString() : '$v';
  num _n(TextEditingController c) => num.tryParse(c.text) ?? 0;

  /// autoAddSuggestedDeductions: one repayment row per payroll advance not yet on the line.
  Future<List<String>> _autoAdd(Map item, String staffId) async {
    try {
      final itemId = tIntOrNull(item['poultryPayrollItemId']) ?? 0;
      final r = await Future.wait([
        _api.get('/api/Poultry/employee-loans/eligible', query: {'farmId': _farmId, 'staffId': staffId}),
        _api.get('/api/Poultry/payroll-deductions', query: {'farmId': _farmId, 'payrollItemId': '$itemId'}),
      ]);
      final already = {for (final d in rowsOf(r[1])) if (d['poultryEmployeeLoanId'] != null) tIntOrNull(d['poultryEmployeeLoanId'])};
      final added = <String>[];
      for (final e in rowsOf(r[0])) {
        final lid = tIntOrNull(e['poultryEmployeeLoanId']);
        if (already.contains(lid)) continue;
        final amount = payrollDeductionFor(e);
        if (amount <= 0) continue;
        await _api.post('/api/Poultry/payroll-deductions', body: {
          'poultryPayrollItemId': itemId,
          'deductionType': tStr(e['loanType']) == 'SalaryAdvance' ? 'SalaryAdvanceRepayment' : 'EmployeeLoanRepayment',
          'amount': amount,
          'poultryEmployeeLoanId': lid,
          'farmId': _farmId,
          'savedBy': widget.session.tokens.userId,
        });
        added.add('${tStr(e['loanNumber']).isNotEmpty ? tStr(e['loanNumber']) : '#$lid'} ${_gh(amount)}');
      }
      return added;
    } on ApiException {
      return [];
    }
  }

  Future<void> _addItem() async {
    if (_staffId == '0') return trackerToast(context, 'Pick a staff member', error: true);
    setState(() => _saving = true);
    final staffId = _staffId;
    try {
      final saved = await _api.post('/api/Poultry/payroll-runs/$_runId/items', query: {'farmId': _farmId}, body: {
        'poultryStaffId': int.parse(staffId),
        'basicPay': _n(_basic),
        'dailyWage': _n(_daily),
        'commission': _n(_comm),
        'bonus': _n(_bonus),
        'deductions': _n(_ded),
        'paymentMethod': _method,
        'notes': _notes.text.isEmpty ? null : _notes.text,
      });
      final added = await _autoAdd(saved is Map ? saved : const {}, staffId);
      setState(_resetForm);
      await _refresh();
      if (mounted && added.isNotEmpty) {
        trackerToast(context, added.length == 1 ? 'Advance repayment added' : '${added.length} advance repayments added',
            description: '${added.join(', ')} — review before approving. Nothing is repaid until you approve.');
      }
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not save line', description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _removeItem(Map it) async {
    try {
      await _api.delete('/api/Poultry/payroll-runs/items/${tStr(it['poultryPayrollItemId'])}?farmId=${Uri.encodeQueryComponent(_farmId)}');
      await _refresh();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not remove line', description: e.message, error: true);
    }
  }

  Future<void> _deductions(Map it) async {
    await showDialog<void>(
      context: context,
      builder: (_) => PayrollDeductionsDialog(
        session: widget.session,
        company: widget.company,
        itemId: tIntOrNull(it['poultryPayrollItemId']) ?? 0,
        staffId: tIntOrNull(it['poultryStaffId']) ?? 0,
        staffName: tStr(it['staffName']).isNotEmpty ? tStr(it['staffName']) : '#${tStr(it['poultryStaffId'])}',
        runStatus: tStr(_run['status']),
        fmt: _gh,
        onChanged: _refresh,
      ),
    );
  }

  Widget _numField(String label, TextEditingController c) => FilterLabel(
        label,
        AppInput(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
          onChanged: (_) => setState(() {}),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final items = rowsOf(_run['items']);
    final editable = payrollEditable(_run['status']);
    final loanTotal = _staffLoans.fold<num>(0, (s, e) => s + payrollDeductionFor(e));
    return Scaffold(
      appBar: AppBar(title: const Text('Staff lines')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 96),
        children: [
          Text('${payrollDay(_run['periodStart'])} → ${payrollDay(_run['periodEnd'])} · Net ${_gh(tNum(_run['totalNetPay']))}',
              style: const TextStyle(fontSize: 13, color: TColors.slate500)),
          const SizedBox(height: 12),
          if (items.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('No lines yet.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate500)))
          else
            for (final it in items) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(tStr(it['staffName']).isNotEmpty ? tStr(it['staffName']) : '#${tStr(it['poultryStaffId'])}',
                            style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.slate900)),
                        Text.rich(TextSpan(children: [
                          const TextSpan(text: 'Net '),
                          TextSpan(text: _gh(tNum(it['netPay'])), style: const TextStyle(fontWeight: FontWeight.w600, color: TColors.slate700)),
                        ]), style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                      ]),
                    ),
                    if (editable)
                      IconButton(
                        tooltip: 'Remove line',
                        onPressed: () => _removeItem(it),
                        icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444)),
                      ),
                  ]),
                  const SizedBox(height: 6),
                  twoUp([
                    Text('Basic ${_gh(tNum(it['basicPay']))}', style: const TextStyle(fontSize: 13)),
                    Text('Daily ${_gh(tNum(it['dailyWage']))}', style: const TextStyle(fontSize: 13)),
                    Text('Comm. ${_gh(tNum(it['commission']))}', style: const TextStyle(fontSize: 13)),
                    Text('Bonus ${_gh(tNum(it['bonus']))}', style: const TextStyle(fontSize: 13)),
                  ]),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () => _deductions(it),
                    child: Text.rich(TextSpan(children: [
                      const TextSpan(text: 'Deductions ', style: TextStyle(color: TColors.slate500)),
                      TextSpan(
                        text: _gh(tNum(it['deductions'])),
                        style: const TextStyle(fontWeight: FontWeight.w500, decoration: TextDecoration.underline, decorationStyle: TextDecorationStyle.dotted),
                      ),
                      const TextSpan(text: '  view breakdown', style: TextStyle(fontSize: 11, color: TColors.slate400)),
                    ]), style: const TextStyle(fontSize: 13)),
                  ),
                ]),
              ),
              const SizedBox(height: 8),
            ],
          const SizedBox(height: 8),
          if (!editable)
            const Text('Lines can only be edited while the run is a Draft.', style: TextStyle(fontSize: 13, color: TColors.slate500))
          else
            formSection('Add / update a line', TColors.amber600, [
              FilterLabel(
                'Staff',
                AppSelect<String>(
                  value: _staffId == '0' ? null : _staffId,
                  hintText: 'Pick staff',
                  items: [
                    for (final s in widget.staff)
                      if (s['isActive'] == true)
                        AppSelectItem(value: tStr(s['poultryStaffId']), label: '${tStr(s['firstName'])} ${tStr(s['lastName'])}'),
                  ],
                  onChanged: (v) => _pickStaff(v ?? '0'),
                ),
              ),
              FilterLabel(
                'Payment method',
                AppSelect<String>(
                  value: _method,
                  items: [for (final m in payrollPaymentMethods) AppSelectItem(value: m, label: m)],
                  onChanged: (v) => setState(() => _method = v ?? 'Cash'),
                ),
              ),
              _numField('Basic pay', _basic),
              _numField('Daily wage', _daily),
              _numField('Commission', _comm),
              _numField('Bonus', _bonus),
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _numField('Deductions', _ded),
                if (_staffId != '0' && _staffLoans.any((e) => payrollDeductionFor(e) > 0))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Includes ${_gh(loanTotal)} of advance repayment. Anything above that is recorded as an other deduction.',
                        style: const TextStyle(fontSize: 11, color: TColors.slate500)),
                  ),
              ]),
              FilterLabel('Notes', AppInput(controller: _notes)),
              if (_staffId != '0' && (_loansBusy || _staffLoans.isNotEmpty))
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFEEF2FF), border: Border.all(color: const Color(0xFFC7D2FE)), borderRadius: BorderRadius.circular(6)),
                  child: _loansBusy
                      ? const LoadingLine('Checking advances…')
                      : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Text(_staffLoans.length == 1 ? '1 active advance' : '${_staffLoans.length} active advances',
                              style: const TextStyle(fontWeight: FontWeight.w500, color: Color(0xFF312E81))),
                          const SizedBox(height: 4),
                          for (final e in _staffLoans)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Wrap(alignment: WrapAlignment.spaceBetween, spacing: 12, children: [
                                Text.rich(TextSpan(children: [
                                  TextSpan(text: tStr(e['loanNumber'])),
                                  TextSpan(text: ' · ${_gh(tNum(e['outstandingBalance']))} outstanding', style: const TextStyle(color: Color(0xB34338CA))),
                                ]), style: const TextStyle(fontSize: 13, color: Color(0xFF312E81))),
                                Builder(builder: (_) {
                                  final will = payrollDeductionFor(e);
                                  final byPayroll = tStr(e['repaymentMethod']) == 'PayrollDeduction' || tStr(e['repaymentMethod']) == 'Mixed';
                                  return will > 0
                                      ? Text.rich(TextSpan(children: [
                                          const TextSpan(text: 'will deduct '),
                                          TextSpan(text: _gh(will), style: const TextStyle(fontWeight: FontWeight.w700)),
                                        ]), style: const TextStyle(fontSize: 12, color: Color(0xFF312E81)))
                                      : Text(
                                          byPayroll ? 'no amount set — add it by hand' : 'repaid by ${tStr(e['repaymentMethod']).toLowerCase()} — not deducted here',
                                          style: const TextStyle(fontSize: 12, color: Color(0xFF312E81)));
                                }),
                              ]),
                            ),
                          const Text(
                            'Added automatically when you add the line, and editable afterwards from the Deductions figure. Nothing is repaid until the payroll is approved.',
                            style: TextStyle(fontSize: 11, color: Color(0xCC4338CA)),
                          ),
                        ]),
                ),
              FilledButton(onPressed: _saving ? null : _addItem, child: Text(_saving ? 'Saving…' : 'Add / update line')),
            ]),
        ],
      ),
    );
  }
}

/// PayrollDeductionsDialog: what the money taken off one payslip is for.
class PayrollDeductionsDialog extends StatefulWidget {
  const PayrollDeductionsDialog({
    super.key,
    required this.session,
    required this.company,
    required this.itemId,
    required this.staffId,
    required this.staffName,
    required this.runStatus,
    required this.fmt,
    required this.onChanged,
  });
  final Session session;
  final Company company;
  final int itemId, staffId;
  final String staffName, runStatus;
  final FarmMoney fmt;
  final Future<void> Function() onChanged;

  @override
  State<PayrollDeductionsDialog> createState() => _PayrollDeductionsDialogState();
}

class _PayrollDeductionsDialogState extends State<PayrollDeductionsDialog> {
  List<Map> _rows = [], _eligible = [];
  bool _loading = true, _busy = false;
  String _type = 'EmployeeLoanRepayment', _loanId = '';
  final _amount = TextEditingController(text: '0'), _desc = TextEditingController();

  ApiClient get _api => widget.session.farmClient;
  bool get _editable => payrollEditable(widget.runStatus);
  bool get _isLoan => _type == 'EmployeeLoanRepayment' || _type == 'SalaryAdvanceRepayment';
  Map? get _chosen => _eligible.where((e) => tStr(e['poultryEmployeeLoanId']) == _loanId).firstOrNull;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await Future.wait([
        _api.get('/api/Poultry/payroll-deductions', query: {'farmId': widget.company.farmId, 'payrollItemId': '${widget.itemId}'}),
        _api.get('/api/Poultry/employee-loans/eligible', query: {'farmId': widget.company.farmId, 'staffId': '${widget.staffId}'}),
      ]);
      if (!mounted) return;
      setState(() {
        _rows = rowsOf(r[0]);
        _eligible = rowsOf(r[1]);
        if (_eligible.isNotEmpty) {
          final e = _eligible.first;
          _loanId = tStr(e['poultryEmployeeLoanId']);
          final d = tNum(e['defaultPayrollDeduction']), o = tNum(e['outstandingBalance']);
          _amount.text = _plain(d < o ? d : o);
        } else {
          _loanId = '';
          _type = 'OtherDeduction';
        }
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load the breakdown', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  static String _plain(num v) => v == v.roundToDouble() ? v.toInt().toString() : '$v';

  Future<void> _run(Future<void> Function() fn, String ok) async {
    setState(() => _busy = true);
    try {
      await fn();
      if (mounted) trackerToast(context, ok);
      await _load();
      await widget.onChanged();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'That did not work', description: e.message, error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final fmt = widget.fmt;
    final amount = num.tryParse(_amount.text) ?? 0;
    final c = _chosen;
    final over = _isLoan && c != null && amount > tNum(c['outstandingBalance']);
    final canAdd = _editable && amount > 0 && !over && (!_isLoan || _loanId.isNotEmpty);
    final total = _rows.fold<num>(0, (s, r) => s + tNum(r['amount']));
    return AlertDialog(
      scrollable: true,
      title: Text('Deductions — ${widget.staffName}'),
      content: SizedBox(
        width: 560,
        child: _loading
            ? const Padding(padding: EdgeInsets.all(16), child: LoadingLine('Loading…'))
            : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('What the money taken off this payslip is for. These rows always add up to the Deductions figure on the line.',
                    style: TextStyle(fontSize: 13, color: TColors.slate500)),
                const SizedBox(height: 12),
                TrackerTable(
                  emptyText: 'Nothing deducted from this payslip.',
                  columns: const [TCol('What for', width: 190), TCol('Detail', width: 160), TCol('Amount', right: true, width: 110), TCol('', width: 48)],
                  rows: [
                    for (final r in _rows)
                      [
                        Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          Text(r['isLegacy'] == true ? 'Other deduction' : payrollDeductionTypeLabel(r['deductionType']),
                              style: TextStyle(color: r['isLegacy'] == true ? TColors.slate500 : null)),
                          if (tStr(r['status']) == 'Posted' && r['isLegacy'] != true) const TBadge('Posted', bg: TColors.emerald100, fg: TColors.emerald700),
                        ]),
                        Text(
                          tStr(r['loanNumber']).isNotEmpty
                              ? '${tStr(r['loanNumber'])}${r['loanOutstanding'] != null ? ' · ${fmt(tNum(r['loanOutstanding']))} left' : ''}'
                              : (tStr(r['description']).isEmpty ? '—' : tStr(r['description'])),
                          style: const TextStyle(fontSize: 12),
                        ),
                        Align(alignment: Alignment.centerRight, child: Text(fmt(tNum(r['amount'])))),
                        _editable && r['isLegacy'] != true && tStr(r['status']) == 'Draft' && r['poultryPayrollItemDeductionId'] != null
                            ? IconButton(
                                onPressed: _busy
                                    ? null
                                    : () => _run(
                                        () => _api.delete('/api/Poultry/payroll-deductions/${tStr(r['poultryPayrollItemDeductionId'])}'
                                            '?farmId=${Uri.encodeQueryComponent(widget.company.farmId)}&deletedBy=${Uri.encodeQueryComponent(widget.session.tokens.userId ?? '')}'),
                                        'Deduction removed'),
                                icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444)),
                              )
                            : const SizedBox.shrink(),
                      ],
                  ],
                  footer: [
                    const Text('Total', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox.shrink(),
                    Align(alignment: Alignment.centerRight, child: Text(fmt(total), style: const TextStyle(fontWeight: FontWeight.w600))),
                    const SizedBox.shrink(),
                  ],
                ),
                const SizedBox(height: 12),
                if (_editable)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const Text('Add a deduction', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 10),
                      FilterLabel(
                        'What for *',
                        AppSelect<String>(
                          value: _type,
                          items: [
                            for (final (v, l) in payrollDeductionTypes)
                              AppSelectItem(
                                value: v,
                                label: '$l${v != 'OtherDeduction' && _eligible.isEmpty ? ' (no active advances)' : ''}',
                                enabled: v == 'OtherDeduction' || _eligible.isNotEmpty,
                              ),
                          ],
                          onChanged: (v) => setState(() {
                            _type = v ?? _type;
                            if (_type == 'OtherDeduction') _loanId = '';
                          }),
                        ),
                      ),
                      if (_isLoan) ...[
                        const SizedBox(height: 10),
                        FilterLabel(
                          'Which advance *',
                          AppSelect<String>(
                            value: _loanId.isEmpty ? null : _loanId,
                            hintText: 'Choose an advance',
                            items: [
                              for (final e in _eligible)
                                AppSelectItem(
                                  value: tStr(e['poultryEmployeeLoanId']),
                                  label: '${tStr(e['loanNumber'])} — ${fmt(tNum(e['outstandingBalance']))} outstanding',
                                ),
                            ],
                            onChanged: (v) => setState(() {
                              _loanId = v ?? '';
                              final e = _chosen;
                              if (e != null) {
                                final d = tNum(e['defaultPayrollDeduction']), o = tNum(e['outstandingBalance']);
                                _amount.text = _plain(d < o ? d : o);
                              }
                            }),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      FilterLabel(
                        'Amount *',
                        AppInput(
                          controller: _amount,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      if (over)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('Only ${fmt(tNum(c['outstandingBalance']))} is left on ${tStr(c['loanNumber'])}.',
                              style: const TextStyle(fontSize: 11, color: TColors.rose600)),
                        ),
                      if (!_isLoan) ...[
                        const SizedBox(height: 10),
                        FilterLabel('What is it', AppInput(controller: _desc, hintText: 'Uniform, tools, damage…')),
                      ],
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: _busy || !canAdd
                              ? null
                              : () => _run(() async {
                                    await _api.post('/api/Poultry/payroll-deductions', body: {
                                      'poultryPayrollItemId': widget.itemId,
                                      'deductionType': _type,
                                      'amount': amount,
                                      'poultryEmployeeLoanId': _isLoan ? int.parse(_loanId) : null,
                                      'description': _desc.text.isEmpty ? null : _desc.text,
                                      'farmId': widget.company.farmId,
                                      'savedBy': widget.session.tokens.userId,
                                    });
                                    _amount.text = '0';
                                    _desc.clear();
                                  }, 'Deduction added'),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add'),
                        ),
                      ),
                    ]),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: TColors.slate50, borderRadius: BorderRadius.circular(6)),
                    child: Text('This payroll is ${widget.runStatus}. Reopen it to change deductions.', style: const TextStyle(fontSize: 12, color: TColors.slate600)),
                  ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFF0F9FF), border: Border.all(color: const Color(0xFFBAE6FD)), borderRadius: BorderRadius.circular(6)),
                  child: const Text.rich(
                    TextSpan(children: [
                      TextSpan(text: 'Nothing here changes what a worker owes yet. Advances are only repaid when this payroll is '),
                      TextSpan(text: 'approved', style: TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: ' — and reopening it puts them back.'),
                    ]),
                    style: TextStyle(fontSize: 12, color: TColors.sky900),
                  ),
                ),
              ]),
      ),
      actions: [OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}

/// One payroll run, as `app/poultry-payroll/[id]/page.tsx`: totals, the
/// employee breakdown, year to date, the linked expense and the audit trail.
class PayrollRunDetailScreen extends StatefulWidget {
  const PayrollRunDetailScreen({super.key, required this.session, required this.company, required this.runId});
  final Session session;
  final Company company;
  final int runId;

  @override
  State<PayrollRunDetailScreen> createState() => _PayrollRunDetailScreenState();
}

class _PayrollRunDetailScreenState extends State<PayrollRunDetailScreen> {
  Map? _data;
  bool _loading = true;
  FarmMoney _gh = const FarmMoney();

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _gh = m);
    });
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await widget.session.farmClient.get('/api/Poultry/payroll-runs/${widget.runId}/details', query: {'farmId': widget.company.farmId});
      if (mounted) setState(() => _data = r is Map ? r : null);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load run', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Widget _stat(String label, String value, {Color? color, double size = 19}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: size, fontWeight: FontWeight.w600, color: color)),
        ]),
      );

  Widget _card(String title, Widget child) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.slate700)),
          const SizedBox(height: 8),
          child,
        ]),
      );

  Widget _dl(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
          const SizedBox(width: 12),
          Expanded(child: Text(v, textAlign: TextAlign.right, style: const TextStyle(fontSize: 13))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-payroll');
    final run = _data?['run'] is Map ? _data!['run'] as Map : null;
    final ytd = _data?['ytdTotals'] is Map ? _data!['ytdTotals'] as Map : null;
    final exp = _data?['linkedExpense'] is Map ? _data!['linkedExpense'] as Map : null;
    final byStaff = rowsOf(_data?['ytdByStaff']);
    final gh = _gh;
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Payroll run')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).maybePop(),
              style: TextButton.styleFrom(foregroundColor: TColors.slate600, padding: EdgeInsets.zero),
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('Back to Payroll'),
            ),
          ),
          if (_loading)
            const Padding(padding: EdgeInsets.all(16), child: LoadingLine('Loading…'))
          else if (run == null)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Payroll run not found.', style: TextStyle(color: TColors.slate500))))
          else ...[
            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              const Icon(Icons.payments_outlined, color: Color(0xFF16A34A)),
              Text('Payroll · ${payrollDay(run['periodStart'])} → ${payrollDay(run['periodEnd'])}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: TColors.slate900)),
              payrollBadge(run['status']),
            ]),
            const SizedBox(height: 12),
            twoUp([
              _stat('Gross pay', gh(tNum(run['totalGrossPay']))),
              _stat('Deductions', gh(tNum(run['totalDeductions'])), color: TColors.rose600),
              _stat('Net pay', gh(tNum(run['totalNetPay'])), color: const Color(0xFF15803D)),
              _stat('Pay date', payrollDay(run['payDate'])),
            ]),
            const SizedBox(height: 12),
            _card(
              'Employee breakdown',
              TrackerTable(
                emptyText: 'No staff lines.',
                columns: const [
                  TCol('Staff', width: 130), TCol('Role', width: 110), TCol('Basic', right: true, width: 100), TCol('Daily', right: true, width: 100),
                  TCol('Commission', right: true, width: 110), TCol('Bonus', right: true, width: 100), TCol('Deductions', right: true, width: 110),
                  TCol('Net', right: true, width: 110),
                ],
                rows: [
                  for (final it in rowsOf(run['items']))
                    [
                      Text(tStr(it['staffName']).isNotEmpty ? tStr(it['staffName']) : '#${tStr(it['poultryStaffId'])}', style: const TextStyle(fontWeight: FontWeight.w500)),
                      cellText(tStr(it['staffRole']).isEmpty ? '—' : tStr(it['staffRole'])),
                      for (final k in ['basicPay', 'dailyWage', 'commission', 'bonus', 'deductions'])
                        Align(alignment: Alignment.centerRight, child: Text(gh(tNum(it[k])))),
                      Align(alignment: Alignment.centerRight, child: Text(gh(tNum(it['netPay'])), style: const TextStyle(fontWeight: FontWeight.w600))),
                    ],
                ],
              ),
            ),
            if (ytd != null) ...[
              const SizedBox(height: 12),
              twoUp([
                _stat('YTD gross (${tStr(ytd['year'])})', gh(tNum(ytd['ytdGrossPaid'])), size: 17),
                _stat('YTD net paid', gh(tNum(ytd['ytdNetPaid'])), color: const Color(0xFF15803D), size: 17),
                _stat('Payroll runs', tStr(ytd['totalPayrollRuns']), size: 17),
                _stat('Staff paid', tStr(ytd['totalStaffPaid']), size: 17),
              ]),
              if (byStaff.isNotEmpty) ...[
                const SizedBox(height: 12),
                _card(
                  'Year-to-date by staff (${tStr(ytd['year'])})',
                  TrackerTable(
                    columns: const [
                      TCol('Staff', width: 130), TCol('Role', width: 110), TCol('YTD gross', right: true, width: 110),
                      TCol('YTD deductions', right: true, width: 130), TCol('YTD net', right: true, width: 110),
                    ],
                    rows: [
                      for (final s in byStaff)
                        [
                          Text(tStr(s['staffName']).isNotEmpty ? tStr(s['staffName']) : '#${tStr(s['poultryStaffId'])}', style: const TextStyle(fontWeight: FontWeight.w500)),
                          cellText(tStr(s['staffRole']).isEmpty ? '—' : tStr(s['staffRole'])),
                          Align(alignment: Alignment.centerRight, child: Text(gh(tNum(s['ytdGross'])))),
                          Align(alignment: Alignment.centerRight, child: Text(gh(tNum(s['ytdDeductions'])))),
                          Align(alignment: Alignment.centerRight, child: Text(gh(tNum(s['ytdNet'])), style: const TextStyle(fontWeight: FontWeight.w600))),
                        ],
                    ],
                  ),
                ),
              ],
            ],
            const SizedBox(height: 12),
            _card(
              'Linked expense',
              exp != null
                  ? Column(children: [
                      _dl('Category', tStr(exp['category']).isEmpty ? 'Payroll' : tStr(exp['category'])),
                      _dl('Amount', gh(tNum(exp['amount']))),
                      _dl('Date', payrollDay(exp['expenseDate'])),
                      _dl('Description', tStr(exp['description']).isEmpty ? '—' : tStr(exp['description'])),
                    ])
                  : const Text('No linked expense (created when the run is approved).', style: TextStyle(fontSize: 13, color: TColors.slate500)),
            ),
            const SizedBox(height: 12),
            _card(
              'Audit',
              Column(children: [
                _dl('Created by', tStr(run['createdBy']).isEmpty ? '—' : tStr(run['createdBy'])),
                _dl('Approved', tStr(run['approvedBy']).isEmpty ? '—' : '${tStr(run['approvedBy'])} · ${payrollDay(run['approvedAt'])}'),
                _dl('Paid', tStr(run['paidBy']).isEmpty ? '—' : '${tStr(run['paidBy'])} · ${payrollDay(run['paidAt'])}'),
                if (tStr(run['reopenedBy']).isNotEmpty) _dl('Reopened', '${tStr(run['reopenedBy'])} · ${payrollDay(run['reopenedAt'])}'),
                if (tStr(run['reopenReason']).isNotEmpty) _dl('Reopen reason', tStr(run['reopenReason'])),
                if (tStr(run['reapprovedBy']).isNotEmpty) _dl('Reapproved', '${tStr(run['reapprovedBy'])} · ${payrollDay(run['reapprovedAt'])}'),
                _dl('Cash account', tStr(run['cashAccountName']).isEmpty ? '—' : tStr(run['cashAccountName'])),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}
