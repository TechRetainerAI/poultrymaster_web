// Hotel → Sales, Expenses & Money → Expenses → Payroll, as `app/hotel-payroll/page.tsx`.
// The runs list (summary cards, status filter, per-status actions), New Payroll
// Run, and the run's details: totals, its staff lines with their staff loan
// deductions, Add All Staff / Add by Department, and the line form with the
// staff member's open loans. Cancel and Reopen pick a reason; Delete confirms.
// API: /Hotel/payroll-runs (+ /{id}, /items, /approve, /mark-paid, /cancel,
// /reopen), /Hotel/employee-loans/eligible, /Hotel/staff, /finance/cash-accounts.
// The web's money here is a fixed "GH₵ 0.00" (its currency()), so it is here too.

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/ui/form_dialog.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/money/money_widgets.dart' show MobileCardList, twoUp;
import '../poultry/reports/report_routes.dart' show openAppHref;
import '../poultry/sales/balances_logic.dart' show pageSlice;
import '../poultry/sales/balances_widgets.dart' show CompactPager, LoadingLine;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/business_dates.dart' show fmtInstant;
import '../shared/company_clock.dart';
import '../shared/reason_select.dart' show cancelReasons, reopenReasons;
import '../water/water_payroll_screen.dart' show showWaterPayrollPrompt;
import 'hotel_kit.dart';

/// currency(): "GH₵ 1200.00".
String hotelPayrollMoney(Object? v) => 'GH₵ ${tNum(v).toStringAsFixed(2)}';

const _methods = ['Cash', 'MoMo', 'Bank'];

const _loanTypes = {'SalaryAdvance': 'Salary advance', 'EmployeeLoan': 'Staff loan', 'OtherAdvance': 'Other advance'};
String hotelLoanTypeLabel(Object? v) => _loanTypes[tStr(v)] ?? tStr(v);

(Color, Color) _statusTone(String s) => switch (s) {
      'Approved' => (const Color(0xFFDBEAFE), const Color(0xFF1D4ED8)),
      'Paid' => (const Color(0xFFDCFCE7), const Color(0xFF15803D)),
      'Cancelled' => (const Color(0xFFFEE2E2), const Color(0xFFB91C1C)),
      _ => (const Color(0xFFF1F5F9), const Color(0xFF334155)),
    };

Widget _statusBadge(Object? s) {
  final (bg, fg) = _statusTone(tStr(s));
  return hotelBadge(tStr(s), bg, fg);
}

String _day(Object? d) => tStr(d).length >= 10 ? tStr(d).substring(0, 10) : tStr(d);
String _period(Map r) => '${_day(r['periodstart'])} — ${_day(r['periodend'])}';
int _runId(Map r) => tIntOrNull(r['hotelpayrollrunid']) ?? 0;
Object? _v(Map m, String k) => m[k] ?? m[k.toLowerCase()];
int _staffId(Map s) => tIntOrNull(_v(s, 'hotelStaffId')) ?? 0;
String _staffName(Map s) => '${tStr(_v(s, 'firstName'))} ${tStr(_v(s, 'lastName'))}';

/// Staff loan deductions on the run (on a cancelled run, what was reversed).
num hotelPayrollLoanTotal(Map detail) {
  final cancelled = tStr((detail['run'] as Map?)?['status']) == 'Cancelled';
  return [
    for (final d in rowsOf(detail['deductions']))
      if (tStr(d['status']) != 'Reversed' || cancelled) tNum(d['amount']),
  ].fold<num>(0, (s, a) => s + a);
}

/// One of the staff member's open loans on the line being edited.
class _LoanRow {
  _LoanRow(Map l, {required bool editing})
      : loanId = tIntOrNull(l['hotelEmployeeLoanId']) ?? 0,
        loanNumber = tStr(l['loanNumber']).isEmpty ? '#${tIntOrNull(l['hotelEmployeeLoanId']) ?? 0}' : tStr(l['loanNumber']),
        loanType = tStr(l['loanType']),
        outstanding = tNum(l['outstandingBalance']),
        available = tNum(l['available']),
        suggested = tNum(l['suggestedDeduction']),
        amount = TextEditingController(text: _plain(editing ? tNum(l['currentDeduction']) : tNum(l['suggestedDeduction'])));
  final int loanId;
  final String loanNumber, loanType;
  final num outstanding, available, suggested;
  final TextEditingController amount;
  num get value => num.tryParse(amount.text.trim()) ?? 0;
}

String _plain(num v) => v == v.roundToDouble() ? v.toInt().toString() : '$v';

class HotelPayrollScreen extends StatefulWidget {
  const HotelPayrollScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<HotelPayrollScreen> createState() => _HotelPayrollScreenState();
}

class _HotelPayrollScreenState extends State<HotelPayrollScreen> {
  List<Map> _runs = [];
  bool _loading = true;
  String _status = 'all';
  int _page = 1, _pageSize = 10;

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  Map<String, dynamic> get _q => {'farmId': _farmId};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = rowsOf(await _api.get('/api/Hotel/payroll-runs', query: _q));
      if (mounted) setState(() => _runs = r);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed to load payroll runs', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _newRun() async {
    List<Map> accounts = [];
    try {
      accounts = rowsOf(await _api.get('/api/Hotel/finance/cash-accounts', query: _q));
    } on ApiException {
      accounts = [];
    }
    if (!mounted) return;
    final done = await showDialog<bool>(context: context, builder: (_) => _NewRunDialog(api: _api, farmId: _farmId, accounts: accounts));
    if (done == true) _load();
  }

  Future<void> _openDetail(Map r) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => HotelPayrollRunScreen(session: widget.session, company: widget.company, runId: _runId(r)),
    ));
    _load();
  }

  Future<void> _approve(Map r) async {
    try {
      await _api.post('/api/Hotel/payroll-runs/${_runId(r)}/approve?farmId=${Uri.encodeQueryComponent(_farmId)}');
      if (mounted) {
        trackerToast(context, 'Payroll run approved', description: 'Staff loan deductions on this run are now recorded as repayments.');
      }
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Approve failed', description: e.message, error: true);
    }
  }

  Future<void> _markPaid(Map r) async {
    try {
      await _api.post('/api/Hotel/payroll-runs/${_runId(r)}/mark-paid', body: {'farmId': _farmId});
      if (mounted) {
        final acct = tStr(r['cashaccountname']).isEmpty ? 'the Payroll account' : tStr(r['cashaccountname']);
        trackerToast(context, 'Payroll run marked as paid', description: '${hotelPayrollMoney(r['totalnetpay'])} net pay taken from $acct.');
      }
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Mark paid failed', description: e.message, error: true);
    }
  }

  Future<void> _cancel(Map r) => hotelPayrollCancel(context, api: _api, farmId: _farmId, run: r, onDone: _load);
  Future<void> _reopen(Map r) => hotelPayrollReopen(context, api: _api, farmId: _farmId, run: r, onDone: _load);

  Future<void> _delete(Map r) async {
    final ok = await hotelConfirmDelete(
      context,
      title: 'Delete Payroll Run?',
      message: 'Are you sure you want to delete "${_period(r)}"? This action cannot be undone.',
      onConfirm: () => _api.delete('/api/Hotel/payroll-runs/${_runId(r)}', query: _q),
    );
    if (!ok || !mounted) return;
    trackerToast(context, 'Payroll run deleted');
    _load();
  }

  List<Widget> _actions(Map r) {
    Widget b(String tip, IconData icon, VoidCallback on, [Color? color]) =>
        IconButton(tooltip: tip, onPressed: on, icon: Icon(icon, size: 18, color: color));
    final st = tStr(r['status']);
    return [
      b('Details', Icons.visibility_outlined, () => _openDetail(r)),
      if (st == 'Draft') ...[
        b('Approve', Icons.check, () => _approve(r), const Color(0xFF2563EB)),
        b('Cancel', Icons.close, () => _cancel(r), const Color(0xFFEA580C)),
        b('Delete', Icons.delete_outline, () => _delete(r), TColors.red600),
      ],
      if (st == 'Approved') ...[
        b('Mark Paid', Icons.account_balance_wallet_outlined, () => _markPaid(r), const Color(0xFF16A34A)),
        b('Reopen to correct', Icons.restart_alt, () => _reopen(r), TColors.slate600),
        b('Cancel', Icons.close, () => _cancel(r), const Color(0xFFEA580C)),
      ],
      if (st == 'Cancelled') b('Delete', Icons.delete_outline, () => _delete(r), TColors.red600),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/hotel-payroll');
    final filtered = [for (final r in _runs) if (_status == 'all' || tStr(r['status']) == _status) r];
    if ((_page - 1) * _pageSize >= filtered.length && _page > 1) _page = 1;
    final paid = _runs.where((r) => tStr(r['status']) == 'Paid').fold<num>(0, (s, r) => s + tNum(r['totalnetpay']));
    Widget stat(String label, String value, Color color) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, maxLines: 1, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color)),
            ),
          ]),
        );

    return Scaffold(
      backgroundColor: TColors.slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Payroll')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
          const Row(children: [
            Icon(Icons.payments_outlined, size: 24, color: hotelViolet),
            SizedBox(width: 10),
            Expanded(child: Text('Payroll', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: TColors.slate900))),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => openAppHref(context, widget.session, widget.company, '/hotel-employee-loans', label: 'Employee Loans & Advances'),
              icon: const Icon(Icons.savings_outlined, size: 16),
              label: const Text('Employee Loans & Advances'),
            ),
            FilledButton.icon(
              style: hotelPrimary.copyWith(minimumSize: const WidgetStatePropertyAll(Size(0, 44))),
              onPressed: _newRun,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('New payroll run'),
            ),
          ]),
          const SizedBox(height: 14),
          twoUp([
            stat('Total Runs', '${_runs.length}', TColors.slate900),
            stat('Draft', '${_runs.where((r) => tStr(r['status']) == 'Draft').length}', TColors.slate700),
            stat('Approved', '${_runs.where((r) => tStr(r['status']) == 'Approved').length}', const Color(0xFF1D4ED8)),
            stat('Total Net Paid', hotelPayrollMoney(paid), const Color(0xFF15803D)),
          ]),
          const SizedBox(height: 14),
          AppSelect<String>(
            value: _status,
            hintText: 'Filter by status',
            items: const [
              AppSelectItem(value: 'all', label: 'All'),
              AppSelectItem(value: 'Draft', label: 'Draft'),
              AppSelectItem(value: 'Approved', label: 'Approved'),
              AppSelectItem(value: 'Paid', label: 'Paid'),
              AppSelectItem(value: 'Cancelled', label: 'Cancelled'),
            ],
            onChanged: (v) => setState(() {
              _status = v ?? 'all';
              _page = 1;
            }),
          ),
          const SizedBox(height: 14),
          if (_loading)
            const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: LoadingLine('Loading…')))
          else if (filtered.isEmpty)
            TCard(
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Text('No payroll runs found. Create one to get started.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate400)),
              ),
            )
          else
            MobileCardList<Map>(
              striped: true,
              items: pageSlice(filtered, _page, _pageSize),
              keyOf: (r) => '${_runId(r)}',
              primary: _period,
              trailing: (r) => _statusBadge(r['status']),
              details: (r) => [
                ('Gross', hotelPayrollMoney(r['totalgrosspay'])),
                ('Deductions', hotelPayrollMoney(r['totaldeductions'])),
                ('Net', hotelPayrollMoney(r['totalnetpay'])),
                ('Cash Account', tStr(r['cashaccountname']).isEmpty ? '-' : tStr(r['cashaccountname'])),
              ],
              actions: _actions,
              table: (items) => TrackerTable(
                columns: const [
                  TCol('Period', width: 200),
                  TCol('Gross', right: true, width: 110),
                  TCol('Deductions', right: true, width: 110),
                  TCol('Net', right: true, width: 110),
                  TCol('Cash Account', width: 130),
                  TCol('Status', width: 100),
                  TCol('Actions', right: true, width: 200),
                ],
                rows: [
                  for (final r in items)
                    [
                      cellText(_period(r), bold: true),
                      cellText(hotelPayrollMoney(r['totalgrosspay'])),
                      cellText(hotelPayrollMoney(r['totaldeductions'])),
                      cellText(hotelPayrollMoney(r['totalnetpay']), bold: true),
                      cellText(tStr(r['cashaccountname']).isEmpty ? '-' : tStr(r['cashaccountname'])),
                      Align(alignment: Alignment.centerLeft, child: _statusBadge(r['status'])),
                      Wrap(alignment: WrapAlignment.end, children: _actions(r)),
                    ],
                ],
              ),
              pager: CompactPager(
                total: filtered.length,
                page: _page,
                pageSize: _pageSize,
                onPage: (p) => setState(() => _page = p),
                onPageSize: (v) => setState(() {
                  _pageSize = v;
                  _page = 1;
                }),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Cancel: a reason from the list, optional; staff loan repayments are reversed.
Future<void> hotelPayrollCancel(BuildContext context,
        {required ApiClient api, required String farmId, required Map run, required Future<void> Function() onDone}) =>
    showWaterPayrollPrompt(
      context,
      title: 'Cancel Payroll Run',
      options: cancelReasons,
      description: 'Cancel run for period ${_period(run)}? Any staff loan repayments it recorded are reversed.',
      label: 'Reason (optional)',
      placeholder: 'e.g. Duplicate run, incorrect period',
      confirm: 'Cancel Run',
      allowEmpty: true,
      onSubmit: (reason) async {
        try {
          await api.post('/api/Hotel/payroll-runs/${_runId(run)}/cancel', body: {'farmId': farmId, if (reason.isNotEmpty) 'cancelReason': reason});
          if (context.mounted) trackerToast(context, 'Payroll run cancelled');
          await onDone();
          return true;
        } on ApiException catch (e) {
          if (context.mounted) trackerToast(context, 'Cancel failed', description: e.message, error: true);
          return false;
        }
      },
    );

/// Reopen: Approved back to Draft; a reason is required.
Future<void> hotelPayrollReopen(BuildContext context,
        {required ApiClient api, required String farmId, required Map run, required Future<void> Function() onDone}) =>
    showWaterPayrollPrompt(
      context,
      title: 'Reopen Payroll Run',
      options: reopenReasons,
      description:
          'The run goes back to Draft so its lines can be corrected. Any staff loan repayments it recorded are reversed, and come back when it is approved again.',
      label: 'Reason',
      placeholder: 'e.g. Wrong bonus for one staff member',
      confirm: 'Reopen',
      onSubmit: (reason) async {
        try {
          await api.post('/api/Hotel/payroll-runs/${_runId(run)}/reopen', body: {'farmId': farmId, 'reason': reason});
          if (context.mounted) trackerToast(context, 'Payroll run reopened');
          await onDone();
          return true;
        } on ApiException catch (e) {
          if (context.mounted) trackerToast(context, 'Reopen failed', description: e.message, error: true);
          return false;
        }
      },
    );

// ------------------------------------------------------------------ New Payroll Run

class _NewRunDialog extends StatefulWidget {
  const _NewRunDialog({required this.api, required this.farmId, required this.accounts});
  final ApiClient api;
  final String farmId;
  final List<Map> accounts;

  @override
  State<_NewRunDialog> createState() => _NewRunDialogState();
}

class _NewRunDialogState extends State<_NewRunDialog> {
  String _start = '', _end = '';
  int _account = 0;
  final _notes = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_start.isEmpty || _end.isEmpty) {
      trackerToast(context, 'Period start and end are required', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.api.post('/api/Hotel/payroll-runs', body: {
        'periodStart': _start,
        'periodEnd': _end,
        if (_account != 0) 'hotelCashAccountId': _account,
        if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
        'farmId': widget.farmId,
      });
      if (!mounted) return;
      trackerToast(context, 'Payroll run created');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Create failed', description: e.message, error: true);
    }
  }

  Widget _date(String v, ValueChanged<String> on) =>
      AppDateField(value: hotelParseYmd(v), hintText: 'Pick a date', onChanged: (d) => setState(() => on(d == null ? '' : hotelYmd(d))));

  @override
  Widget build(BuildContext context) => HotelDialog(
        icon: Icons.payments_outlined,
        title: 'New Payroll Run',
        saving: _saving,
        saveLabel: 'Create',
        onSave: _create,
        children: [
          const Text('Create a new payroll period. You can add staff line items after creation.',
              style: TextStyle(fontSize: 13, color: TColors.slate500)),
          TintedSection(title: 'Period', color: FormColor.blue, children: [
            FilterLabel('Period Start *', _date(_start, (v) => _start = v)),
            FilterLabel('Period End *', _date(_end, (v) => _end = v)),
          ]),
          TintedSection(title: 'Payment', color: FormColor.amber, children: [
            FilterLabel(
              'Cash Account',
              AppSelect<int>(
                value: _account,
                hintText: 'Select cash account',
                items: [
                  const AppSelectItem(value: 0, label: '-- None --'),
                  for (final a in widget.accounts)
                    if (tIntOrNull(_v(a, 'hotelCashAccountId')) != null)
                      AppSelectItem(
                        value: tIntOrNull(_v(a, 'hotelCashAccountId'))!,
                        label: '${tStr(_v(a, 'accountName'))} (${tStr(_v(a, 'accountType'))})',
                      ),
                ],
                onChanged: (v) => setState(() => _account = v ?? 0),
              ),
            ),
          ]),
          TintedSection(title: 'Notes', color: FormColor.slate, children: [
            FilterLabel('Notes', AppInput(controller: _notes, hintText: 'Optional notes')),
          ]),
        ],
      );
}

// ------------------------------------------------------------------ the run

/// The web's detail dialog, as a full page on the phone.
class HotelPayrollRunScreen extends StatefulWidget {
  const HotelPayrollRunScreen({super.key, required this.session, required this.company, required this.runId});
  final Session session;
  final Company company;
  final int runId;

  @override
  State<HotelPayrollRunScreen> createState() => _HotelPayrollRunScreenState();
}

class _HotelPayrollRunScreenState extends State<HotelPayrollRunScreen> {
  Map? _detail;
  List<Map> _staff = [];
  bool _loading = true, _bulkAdding = false, _saving = false, _loansLoading = false;
  Duration _offset = DateTime.now().timeZoneOffset;

  // The line form. deductions is the OTHER deductions; loans are in _loans.
  int _staffIdSel = 0;
  int? _editingItemId;
  final _basic = TextEditingController(text: '0'), _daily = TextEditingController(text: '0');
  final _commission = TextEditingController(text: '0'), _bonus = TextEditingController(text: '0');
  final _deductions = TextEditingController(text: '0');
  String _method = 'Cash';
  List<_LoanRow> _loans = [];

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  Map<String, dynamic> get _q => {'farmId': _farmId};
  Map get _run => (_detail?['run'] as Map?) ?? const {};
  List<Map> get _items => rowsOf(_detail?['items']);
  bool get _draft => tStr(_run['status']) == 'Draft';

  @override
  void initState() {
    super.initState();
    CompanyClock.load(widget.session, widget.company).then((c) {
      if (mounted) setState(() => _offset = c.offset);
    });
    _open();
  }

  @override
  void dispose() {
    for (final c in [_basic, _daily, _commission, _bonus, _deductions, ..._loans.map((l) => l.amount)]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _open() async {
    try {
      final r = await Future.wait([
        _api.get('/api/Hotel/payroll-runs/${widget.runId}', query: _q),
        _api.get('/api/Hotel/staff', query: _q),
      ]);
      if (!mounted) return;
      setState(() {
        _detail = r[0] is Map ? r[0] as Map : const {};
        _staff = [for (final s in rowsOf(r[1])) if (_v(s, 'isActive') != false) s];
        _loading = false;
      });
      _resetForm();
    } on ApiException catch (e) {
      if (!mounted) return;
      trackerToast(context, 'Failed to load run details', description: e.message, error: true);
      Navigator.pop(context);
    }
  }

  Future<void> _refresh() async {
    try {
      final d = await _api.get('/api/Hotel/payroll-runs/${widget.runId}', query: _q);
      if (mounted) setState(() => _detail = d is Map ? d : _detail);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed to load run details', description: e.message, error: true);
    }
  }

  void _setLoans(List<_LoanRow> rows) {
    for (final l in _loans) {
      l.amount.dispose();
    }
    _loans = rows;
  }

  void _resetForm() => setState(() {
        _staffIdSel = 0;
        _editingItemId = null;
        for (final c in [_basic, _daily, _commission, _bonus, _deductions]) {
          c.text = '0';
        }
        _method = 'Cash';
        _setLoans([]);
      });

  /// The staff member's open loans, with this line's current or suggested deduction filled in.
  Future<void> _loadLoans(int staffId, int? itemId) async {
    setState(() => _setLoans([]));
    if (staffId == 0) return;
    setState(() => _loansLoading = true);
    try {
      final rows = rowsOf(await _api.get('/api/Hotel/employee-loans/eligible',
          query: {..._q, 'staffId': '$staffId', if (itemId != null) 'excludeItemId': '$itemId'}));
      if (mounted) setState(() => _setLoans([for (final l in rows) _LoanRow(l, editing: itemId != null)]));
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load staff loans', description: e.message, error: true);
    }
    if (mounted) setState(() => _loansLoading = false);
  }

  void _editItem(Map item) {
    setState(() {
      _editingItemId = tIntOrNull(item['hotelpayrollitemid']);
      _staffIdSel = tIntOrNull(item['hotelstaffid']) ?? 0;
      _basic.text = _plain(tNum(item['basicpay']));
      _daily.text = _plain(tNum(item['dailywage']));
      _commission.text = _plain(tNum(item['commission']));
      _bonus.text = _plain(tNum(item['bonus']));
      _deductions.text = _plain(tNum(item['otherdeductions'] ?? item['deductions']));
      _method = tStr(item['paymentmethod']).isEmpty ? 'Cash' : tStr(item['paymentmethod']);
    });
    _loadLoans(_staffIdSel, _editingItemId);
  }

  num _n(TextEditingController c) => num.tryParse(c.text.trim()) ?? 0;

  Future<void> _saveItem() async {
    if (_staffIdSel == 0) {
      trackerToast(context, 'Select a staff member', error: true);
      return;
    }
    final over = _loans.where((l) => l.value > l.available + 0.001).firstOrNull;
    if (over != null) {
      trackerToast(context, 'At most ${hotelPayrollMoney(over.available)} can be deducted for ${over.loanNumber}', error: true);
      return;
    }
    final staff = _staff.where((s) => _staffId(s) == _staffIdSel).firstOrNull;
    setState(() => _saving = true);
    try {
      await _api.post('/api/Hotel/payroll-runs/${widget.runId}/items', body: {
        'hotelStaffId': _staffIdSel,
        if (staff != null) 'staffName': _staffName(staff),
        if (staff != null) 'staffRole': _v(staff, 'role') ?? _v(staff, 'department'),
        'basicPay': _n(_basic),
        'dailyWage': _n(_daily),
        'commission': _n(_commission),
        'bonus': _n(_bonus),
        'deductions': _n(_deductions),
        'paymentMethod': _method,
        'loanDeductions': [for (final l in _loans) {'loanId': l.loanId, 'amount': l.value}],
        'hotelPayrollRunId': widget.runId,
        'farmId': _farmId,
      });
      if (!mounted) return;
      trackerToast(context, _editingItemId != null ? 'Line updated' : 'Line item saved');
      await _refresh();
      _resetForm();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Save failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _deleteItem(Map item) async {
    try {
      await _api.delete('/api/Hotel/payroll-runs/items/${tIntOrNull(item['hotelpayrollitemid'])}', query: _q);
      if (mounted) trackerToast(context, 'Item removed');
      await _refresh();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Delete failed', description: e.message, error: true);
    }
  }

  List<Map> get _remaining => [for (final s in _staff) if (!_items.any((it) => tIntOrNull(it['hotelstaffid']) == _staffId(s))) s];

  /// Each staff member at their base salary, with their open loans' suggested
  /// deductions capped so net pay stays at or above zero.
  Future<void> _bulkAdd(List<Map> staff) async {
    if (staff.isEmpty) return;
    setState(() => _bulkAdding = true);
    var added = 0, withLoans = 0;
    try {
      for (final s in staff) {
        final sid = _staffId(s);
        final salary = tNum(_v(s, 'salaryAmount'));
        final eligible = rowsOf(await _api.get('/api/Hotel/employee-loans/eligible', query: {..._q, 'staffId': '$sid'}));
        num room = salary;
        final loanDeductions = <Map<String, Object>>[];
        for (final l in eligible) {
          final suggested = tNum(l['suggestedDeduction']);
          final amt = suggested < (room > 0 ? room : 0) ? suggested : (room > 0 ? room : 0);
          room -= amt;
          if (amt > 0) loanDeductions.add({'loanId': tIntOrNull(l['hotelEmployeeLoanId']) ?? 0, 'amount': amt});
        }
        if (loanDeductions.isNotEmpty) withLoans++;
        await _api.post('/api/Hotel/payroll-runs/${widget.runId}/items', body: {
          'hotelStaffId': sid,
          'staffName': _staffName(s),
          'staffRole': _v(s, 'role') ?? _v(s, 'department'),
          'basicPay': salary,
          'dailyWage': 0,
          'commission': 0,
          'bonus': 0,
          'deductions': 0,
          'paymentMethod': 'Cash',
          'loanDeductions': loanDeductions,
          'hotelPayrollRunId': widget.runId,
          'farmId': _farmId,
        });
        added++;
      }
      if (mounted) {
        trackerToast(context, '$added staff member(s) added with their base salary',
            description: withLoans > 0 ? '$withLoans with a staff loan deduction — check the Deductions column.' : null);
      }
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Added $added, then failed', description: e.message, error: true);
    }
    await _refresh();
    if (mounted) setState(() => _bulkAdding = false);
  }

  Future<void> _addAll() async {
    if (_remaining.isEmpty) return trackerToast(context, 'All staff already added');
    await _bulkAdd(_remaining);
  }

  Future<void> _addDepartment(String dept) async {
    final rows = [for (final s in _remaining) if (tStr(_v(s, 'department')).toLowerCase() == dept.toLowerCase()) s];
    if (rows.isEmpty) return trackerToast(context, 'All $dept staff already added');
    await _bulkAdd(rows);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TColors.slate50,
      appBar: AppBar(title: Text(_loading ? 'Payroll Run' : 'Payroll Run: ${_period(_run)}')),
      body: _loading
          ? const Center(child: LoadingLine('Loading…'))
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
                Text('Status: ${tStr(_run['status'])}', style: const TextStyle(fontSize: 13, color: TColors.slate500)),
                const SizedBox(height: 12),
                ..._summary(),
                const SizedBox(height: 14),
                _itemsCard(),
                if (_draft) ...[const SizedBox(height: 14), ..._addSection()],
                const SizedBox(height: 14),
                _audit(),
              ]),
            ),
    );
  }

  List<Widget> _summary() {
    final st = tStr(_run['status']);
    Widget card(String label, String value, Color color, [String? note]) => TCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, maxLines: 1, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: color)),
            ),
            if (note != null) Text(note, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          ]),
        );
    return [
      for (final (i, w) in [
        card('Gross Pay', hotelPayrollMoney(_run['totalgrosspay']), TColors.slate900),
        card('Deductions', hotelPayrollMoney(_run['totaldeductions']), TColors.red600),
        card('Net Pay', hotelPayrollMoney(_run['totalnetpay']), const Color(0xFF15803D)),
        card(
          'Staff loan repayments',
          hotelPayrollMoney(hotelPayrollLoanTotal(_detail ?? const {})),
          TColors.violet700,
          st == 'Draft'
              ? 'recorded when the run is approved'
              : st == 'Cancelled'
                  ? 'reversed with the run'
                  : 'recorded against the loans',
        ),
      ].indexed) ...[if (i > 0) const SizedBox(height: 10), w],
    ];
  }

  Widget _itemsCard() {
    final deductions = rowsOf(_detail?['deductions']);
    if (_items.isEmpty) {
      return TCard(
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Text('No line items yet. Add staff below.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate400)),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final item in _items)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(tStr(item['staffname']).isEmpty ? 'Staff #${tStr(item['hotelstaffid'])}' : tStr(item['staffname']),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: TColors.slate900)),
                  if (tStr(item['staffrole']).isNotEmpty) Text('(${tStr(item['staffrole'])})', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                ]),
              ),
              if (_draft) ...[
                IconButton(tooltip: 'Edit line', onPressed: () => _editItem(item), icon: const Icon(Icons.edit_outlined, size: 18)),
                IconButton(tooltip: 'Remove line', onPressed: () => _deleteItem(item), icon: const Icon(Icons.delete_outline, size: 18, color: TColors.red600)),
              ],
            ]),
            const SizedBox(height: 6),
            for (final (label, key) in const [('Basic', 'basicpay'), ('Daily', 'dailywage'), ('Commission', 'commission'), ('Bonus', 'bonus'), ('Deductions', 'deductions')])
              _line(label, hotelPayrollMoney(item[key])),
            for (final d in deductions)
              if (tIntOrNull(d['hotelPayrollItemId']) == tIntOrNull(item['hotelpayrollitemid']))
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${tStr(d['loanNumber'])} ${hotelPayrollMoney(d['amount'])}',
                    style: TextStyle(
                      fontSize: 12,
                      color: tStr(d['status']) == 'Reversed' ? TColors.slate400 : TColors.violet700,
                      decoration: tStr(d['status']) == 'Reversed' ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
            const Divider(height: 14, color: TColors.slate100),
            _line('Net', hotelPayrollMoney(item['netpay']), bold: true),
          ]),
        ),
    ]);
  }

  Widget _line(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: TColors.slate500))),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: TColors.slate900)),
        ]),
      );

  List<Widget> _addSection() {
    final remaining = _remaining;
    final out = <Widget>[];
    if (remaining.isEmpty && _items.isNotEmpty) {
      out.add(Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: TColors.emerald50, border: Border.all(color: TColors.emerald200), borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          const Icon(Icons.check, size: 16, color: Color(0xFF059669)),
          const SizedBox(width: 8),
          Expanded(
            child: Text('All ${_items.length} active staff members have been added to this run.',
                style: const TextStyle(fontSize: 13, color: TColors.emerald700)),
          ),
        ]),
      ));
    } else if (remaining.isNotEmpty) {
      final depts = <String, int>{};
      for (final s in remaining) {
        final d = tStr(_v(s, 'department')).isEmpty ? 'Other' : tStr(_v(s, 'department'));
        depts[d] = (depts[d] ?? 0) + 1;
      }
      final sorted = depts.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
      out.add(Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: TColors.violet50, border: Border.all(color: const Color(0xFFDDD6FE)), borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text.rich(
            TextSpan(children: [
              TextSpan(text: '${remaining.length}', style: const TextStyle(fontWeight: FontWeight.w700)),
              const TextSpan(text: ' staff member(s) not yet added to this run'),
            ]),
            style: const TextStyle(fontSize: 13, color: TColors.violet700),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: TColors.violet700, side: const BorderSide(color: Color(0xFFC4B5FD))),
            onPressed: _bulkAdding ? null : _addAll,
            icon: Icon(_bulkAdding ? Icons.hourglass_empty : Icons.group_outlined, size: 16),
            label: Text(_bulkAdding ? 'Adding...' : 'Add All Staff'),
          ),
        ]),
      ));
      if (sorted.length > 1) {
        out.add(const SizedBox(height: 10));
        out.add(Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: TColors.slate50, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Row(children: [
              Icon(Icons.apartment, size: 12, color: TColors.slate500),
              SizedBox(width: 4),
              Text('Add by Department', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: TColors.slate500)),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in sorted)
                OutlinedButton(onPressed: _bulkAdding ? null : () => _addDepartment(e.key), child: Text('${e.key} (${e.value})', style: const TextStyle(fontSize: 12))),
            ]),
          ]),
        ));
      }
    }
    // The individual line form, while there is someone left to add or a line is being edited.
    if (_editingItemId != null || remaining.isNotEmpty) {
      out.add(const SizedBox(height: 12));
      out.add(_lineForm(remaining));
      if (_staffIdSel > 0 && (_loansLoading || _loans.isNotEmpty)) {
        out.add(const SizedBox(height: 12));
        out.add(_loanBox());
      }
    }
    return out;
  }

  Widget _num(String label, TextEditingController c) => FilterLabel(
        label,
        AppInput(controller: c, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {})),
      );

  Widget _lineForm(List<Map> remaining) {
    final editing = _editingItemId == null ? null : _items.where((i) => tIntOrNull(i['hotelpayrollitemid']) == _editingItemId).firstOrNull;
    return TintedSection(
      title: editing != null ? 'Edit line: ${tStr(editing['staffname'])}' : 'Add individual staff',
      color: FormColor.blue,
      children: [
        FilterLabel(
          'Staff *',
          AppSelect<int>(
            value: _staffIdSel,
            hintText: 'Select staff',
            enabled: editing == null,
            items: [
              const AppSelectItem(value: 0, label: '-- Select --'),
              if (editing != null)
                AppSelectItem(
                  value: _staffIdSel,
                  label: tStr(editing['staffname']).isEmpty ? 'Staff #$_staffIdSel' : tStr(editing['staffname']),
                ),
              for (final s in remaining)
                AppSelectItem(
                  value: _staffId(s),
                  label: '${_staffName(s)} — ${tStr(_v(s, 'role')).isNotEmpty ? tStr(_v(s, 'role')) : (tStr(_v(s, 'department')).isNotEmpty ? tStr(_v(s, 'department')) : 'Staff')}',
                ),
            ],
            onChanged: (v) {
              final sid = v ?? 0;
              final s = _staff.where((x) => _staffId(x) == sid).firstOrNull;
              setState(() {
                _staffIdSel = sid;
                _basic.text = _plain(tNum(s == null ? 0 : (_v(s, 'salaryAmount') ?? s['salary'])));
              });
              _loadLoans(sid, null);
            },
          ),
        ),
        _num('Basic Pay', _basic),
        _num('Daily Wage', _daily),
        _num('Commission', _commission),
        _num('Bonus', _bonus),
        _num('Other deductions', _deductions),
        FilterLabel(
          'Payment Method',
          AppSelect<String>(
            value: _method,
            items: [for (final m in _methods) AppSelectItem(value: m, label: m)],
            onChanged: (v) => setState(() => _method = v ?? 'Cash'),
          ),
        ),
        Row(children: [
          Expanded(
            child: FilledButton(
              style: hotelPrimary,
              onPressed: _saving ? null : _saveItem,
              child: Text(_saving ? 'Saving...' : (editing != null ? 'Update Line' : 'Save Line')),
            ),
          ),
          if (editing != null) ...[
            const SizedBox(width: 8),
            OutlinedButton(onPressed: _resetForm, child: const Text('Cancel')),
          ],
        ]),
      ],
    );
  }

  Widget _loanBox() {
    final gross = _n(_basic) + _n(_daily) + _n(_commission) + _n(_bonus);
    final net = gross - _n(_deductions) - _loans.fold<num>(0, (s, l) => s + l.value);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: TColors.violet50, border: Border.all(color: const Color(0xFFDDD6FE)), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.savings_outlined, size: 16, color: Color(0xFF5B21B6)),
          const SizedBox(width: 6),
          const Text('Staff loan deductions', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF5B21B6))),
          if (_loansLoading) ...[
            const SizedBox(width: 8),
            const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ]),
        for (final l in _loans) ...[
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: l.loanNumber, style: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'monospace')),
              TextSpan(text: ' · ${hotelLoanTypeLabel(l.loanType)}'),
              TextSpan(text: ' — owes ${hotelPayrollMoney(l.outstanding)}', style: const TextStyle(color: TColors.slate600)),
              if (l.available < l.outstanding)
                TextSpan(
                    text: ' (${hotelPayrollMoney(l.outstanding - l.available)} already on another draft run)', style: const TextStyle(color: TColors.amber700)),
              if (l.suggested > 0) TextSpan(text: ' · suggested ${hotelPayrollMoney(l.suggested)}', style: const TextStyle(color: TColors.slate500)),
            ]),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 4),
          AppInput(controller: l.amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {})),
        ],
        const SizedBox(height: 8),
        const Text(
          'Deducted from net pay; nothing leaves the cash account for it. The loan balance falls when this run is approved. Set 0 to skip a loan this period.',
          style: TextStyle(fontSize: 12, color: Color(0xFF5B21B6)),
        ),
        const SizedBox(height: 6),
        Text(
          'Net pay for this line: ${hotelPayrollMoney(net)}${net < 0 ? ' — deductions are more than the pay' : ''}',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: net < 0 ? TColors.red600 : TColors.slate700),
        ),
      ]),
    );
  }

  Widget _audit() {
    final r = _run;
    String when(Object? v) => fmtInstant(v, _offset);
    final lines = [
      if (tStr(r['createdby']).isNotEmpty) 'Created by: ${tStr(r['createdby'])} on ${when(r['createdat'])}',
      if (tStr(r['approvedby']).isNotEmpty) 'Approved by: ${tStr(r['approvedby'])} on ${when(r['approvedat'])}',
      if (tStr(r['paidby']).isNotEmpty) 'Paid by: ${tStr(r['paidby'])} on ${when(r['paidat'])}',
      if (tStr(r['cancelledby']).isNotEmpty) 'Cancelled by: ${tStr(r['cancelledby'])} — Reason: ${tStr(r['cancelreason']).isEmpty ? 'N/A' : tStr(r['cancelreason'])}',
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.only(top: 12),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: TColors.slate200))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final l in lines) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(l, style: const TextStyle(fontSize: 12, color: TColors.slate500))),
      ]),
    );
  }
}
