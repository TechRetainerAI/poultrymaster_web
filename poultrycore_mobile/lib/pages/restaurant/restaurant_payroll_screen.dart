// Restaurant → Expenses → Payroll, as `app/restaurant-payroll/page.tsx`
// (migration 326). A run goes Draft → Approved → Paid: lines and staff loan
// deductions are set on the draft; approving turns each loan deduction into a
// repayment; Paid takes the NET pay out of the chosen account. An Approved run
// can be reopened or cancelled. API: /Restaurant/payroll/*.

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/money/money_widgets.dart';
import '../poultry/reports/report_format.dart' show FarmMoney;
import '../poultry/reports/report_routes.dart' show openAppHref;
import '../poultry/sales/balances_logic.dart' show pageSlice;
import '../poultry/sales/balances_widgets.dart' show CompactPager, LoadingLine;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/reason_select.dart' show ReasonSelect, cancelReasons, reopenReasons;
import 'restaurant_money_kit.dart';
import 'restaurant_roles.dart' show restaurantRose;
import 'restaurant_widgets.dart';

const _staffLoanTypes = {'SalaryAdvance': 'Salary advance', 'EmployeeLoan': 'Staff loan', 'OtherAdvance': 'Other advance'};
String staffLoanTypeLabel(Object? v) => _staffLoanTypes[tStr(v)] ?? tStr(v);

/// The web's `n()`: blank is 0, junk is 0.
num _n(String s) => s.trim().isEmpty ? 0 : (num.tryParse(s.trim()) ?? 0);
String _d(Object? s) => tStr(s).isEmpty ? '—' : tStr(s).split('T').first;
String _plain(num v) => v == v.roundToDouble() ? v.toInt().toString() : '$v';

const _statusStyle = {
  'Draft': (TColors.slate100, TColors.slate700, TColors.slate200),
  'Approved': (Color(0xFFEFF6FF), Color(0xFF1D4ED8), Color(0xFFBFDBFE)),
  'Paid': (Color(0xFFF0FDF4), Color(0xFF15803D), Color(0xFFBBF7D0)),
  'Cancelled': (Color(0xFFFEF2F2), Color(0xFFB91C1C), Color(0xFFFECACA)),
};
Widget _status(Object? s) {
  final (bg, fg, b) = _statusStyle[tStr(s)] ?? (Colors.white, TColors.slate700, TColors.slate200);
  return rStatusBadge(tStr(s), bg: bg, fg: fg, border: b);
}

/// The pay date offered by Mark paid: the run's, unless it is in the future.
String markPaidDefaultDate(Map run) {
  final d = _d(run['payDate']);
  return d != '—' && d.compareTo(rTodayIso()) <= 0 ? d : rTodayIso();
}

/// Shared by the list and the run page: the calls, and the dialogs they open.
class _PayrollApi {
  _PayrollApi(this.session, this.company);
  final Session session;
  final Company company;
  ApiClient get api => session.farmClient;
  String u(String path, [Map<String, Object?> q = const {}]) {
    final query = {'farmId': company.farmId};
    q.forEach((k, v) {
      if (v != null && '$v' != '') query[k] = '$v';
    });
    return Uri(path: '/api/Restaurant$path', queryParameters: query).toString();
  }

  /// The web's `run()`: toast the failure under [label], the success message if any.
  Future<bool> run<T>(BuildContext context, String label, Future<T> Function() fn, [String? Function(T)? done]) async {
    try {
      final r = await fn();
      final msg = done?.call(r);
      if (msg != null && context.mounted) trackerToast(context, msg);
      return true;
    } on ApiException catch (e) {
      if (context.mounted) trackerToast(context, label, description: e.message, error: true);
      return false;
    }
  }

  Future<bool> approve(BuildContext context, Map r) => run<Object?>(
        context,
        'Could not approve',
        () => api.post(u('/payroll/runs/${tIntOrNull(r['payrollRunId'])}/approve')),
        (x) {
          final n = x is Map ? tNum(x['loanRepaymentsPosted']) : 0;
          return n > 0 ? 'Approved — ${_plain(n)} staff loan repayment(s) recorded' : 'Payroll run approved';
        },
      );

  Future<bool> markPaid(BuildContext context, Map r, List<Map> accounts, FarmMoney fmt) async =>
      await showDialog<bool>(context: context, builder: (_) => _MarkPaidDialog(api: this, run: r, accounts: accounts, fmt: fmt)) == true;

  Future<bool> reason(BuildContext context, Map r, {required bool reopen}) async =>
      await showDialog<bool>(context: context, builder: (_) => _ReasonDialog(api: this, run: r, reopen: reopen)) == true;

  Future<bool> delete(BuildContext context, Map r) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => rDialog(
          title: 'Delete ${tStr(r['runNumber'])}?',
          description: 'The run and its lines are removed. Nothing was posted for a draft or cancelled run, so no money changes.',
          children: const [],
          actions: [
            OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
            rConfirm('Delete', () async {
              final ok = await run<Object?>(
                  ctx, 'Could not delete', () => api.delete(u('/payroll/runs/${tIntOrNull(r['payrollRunId'])}')), (_) => 'Payroll run deleted');
              if (ok && ctx.mounted) Navigator.pop(ctx, true);
            }, color: TColors.red600),
          ],
        ),
      ) ==
      true;
}

/// "Main Cash Box (default)" or an active account with its balance.
Widget _accountSelect(List<Map> accounts, FarmMoney fmt, int? value, ValueChanged<int?> onChanged) => AppSelect<int>(
      value: value ?? -1,
      items: [
        const AppSelectItem(value: -1, label: 'Main Cash Box (default)'),
        for (final a in accounts)
          AppSelectItem(value: tIntOrNull(a['cashAccountId'])!, label: '${tStr(a['name'])} (${fmt(tNum(a['currentBalance']))})'),
      ],
      onChanged: (v) => onChanged(v == null || v == -1 ? null : v),
    );

class RestaurantPayrollScreen extends StatefulWidget {
  const RestaurantPayrollScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<RestaurantPayrollScreen> createState() => _RestaurantPayrollScreenState();
}

class _RestaurantPayrollScreenState extends State<RestaurantPayrollScreen> {
  late final _p = _PayrollApi(widget.session, widget.company);
  bool _loading = true;
  List<Map> _runs = [], _staff = [], _accounts = [];
  String _statusFilter = 'ALL';
  int _page = 1, _pageSize = 10;
  FarmMoney _gh = const FarmMoney();

  /// canViewRestaurantStaff on the web; Staff are the ones refused here.
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
      final r = await Future.wait([
        _p.api.get(_p.u('/payroll/runs')),
        _p.api.get(_p.u('/staff')),
        loadRestaurantAccounts(_p.api, widget.company.farmId),
      ]);
      if (!mounted) return;
      setState(() {
        _runs = rowsOf(r[0]);
        _staff = rowsOf(r[1]);
        _accounts = [for (final a in r[2] as List<Map>) if (a['isActive'] == true) a];
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load payroll', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _newRun() async {
    final done = await showDialog<bool>(context: context, builder: (_) => _NewRunDialog(api: _p, accounts: _accounts, fmt: _gh));
    if (done == true) _load();
  }

  Future<void> _open(Map r) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _RunPage(api: _p, runId: tIntOrNull(r['payrollRunId'])!, staff: _staff, accounts: _accounts, fmt: _gh, onChanged: _load),
    ));
  }

  List<Widget> _actions(Map r) {
    Widget b(String tip, IconData icon, Color color, Future<bool> Function() on) =>
        IconButton(tooltip: tip, icon: Icon(icon, size: 18, color: color), onPressed: () async {
          if (await on()) _load();
        });
    final st = tStr(r['status']);
    return [
      IconButton(tooltip: 'Open', icon: const Icon(Icons.visibility_outlined, size: 18), onPressed: () => _open(r)),
      if (st == 'Draft') ...[
        b('Approve', Icons.check_circle_outline, const Color(0xFF2563EB), () => _p.approve(context, r)),
        b('Cancel', Icons.block, TColors.amber600, () => _p.reason(context, r, reopen: false)),
        b('Delete', Icons.delete_outline, TColors.red600, () => _p.delete(context, r)),
      ],
      if (st == 'Approved') ...[
        b('Mark paid', Icons.account_balance_wallet_outlined, const Color(0xFF16A34A), () => _p.markPaid(context, r, _accounts, _gh)),
        b('Reopen to correct', Icons.undo, TColors.slate600, () => _p.reason(context, r, reopen: true)),
        b('Cancel', Icons.block, TColors.amber600, () => _p.reason(context, r, reopen: false)),
      ],
      if (st == 'Cancelled') b('Delete', Icons.delete_outline, TColors.red600, () => _p.delete(context, r)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/restaurant-payroll');
    Widget body;
    if (_loading) {
      body = const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: LoadingLine('Loading…')));
    } else if (!_canView) {
      body = const TCard(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(
            child: Text('You do not have access to payroll. Ask an admin for the Staff & payroll permission.',
                textAlign: TextAlign.center, style: TextStyle(color: TColors.slate600)),
          ),
        ),
      );
    } else {
      final filtered = [for (final r in _runs) if (_statusFilter == 'ALL' || r['status'] == _statusFilter) r];
      final approved = [for (final r in _runs) if (r['status'] == 'Approved') r];
      final lastPaid = _runs.where((r) => r['status'] == 'Paid').firstOrNull;
      if ((_page - 1) * _pageSize >= filtered.length && _page > 1) _page = 1;
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        RPageHeader(
          icon: Icons.payments_outlined,
          title: 'Payroll',
          subtitle: 'Pay runs for restaurant staff, with staff loan deductions',
          actions: [
            OutlinedButton.icon(
              onPressed: () => openAppHref(context, widget.session, widget.company, '/restaurant-staff-loans', label: 'Employee Loans & Advances'),
              icon: const Icon(Icons.volunteer_activism_outlined, size: 16),
              label: const Text('Employee Loans & Advances', overflow: TextOverflow.ellipsis),
            ),
            roseButton('New payroll run', _newRun),
          ],
        ),
        const SizedBox(height: 14),
        twoColumns([
          RStatCard(label: 'Draft runs', value: '${_runs.where((r) => r['status'] == 'Draft').length}', icon: Icons.calendar_month_outlined, color: 'blue'),
          RStatCard(
              label: 'Approved, not yet paid (${approved.length})',
              value: _gh(approved.fold<num>(0, (s, r) => s + tNum(r['totalNet']))),
              icon: Icons.check_circle_outline,
              color: 'amber'),
          RStatCard(
              label: lastPaid != null ? 'Last paid · ${tStr(lastPaid['runNumber'])}' : 'Last paid',
              value: lastPaid != null ? _gh(tNum(lastPaid['totalNet'])) : '—',
              icon: Icons.account_balance_wallet_outlined,
              color: 'green'),
          RStatCard(label: 'Active staff', value: '${_staff.where((s) => s['isActive'] == true).length}', icon: Icons.groups_outlined),
        ]),
        const SizedBox(height: 14),
        AppSelect<String>(
          value: _statusFilter,
          items: [for (final s in ['ALL', 'Draft', 'Approved', 'Paid', 'Cancelled']) AppSelectItem(value: s, label: s == 'ALL' ? 'All runs' : s)],
          onChanged: (v) => setState(() {
            _statusFilter = v ?? 'ALL';
            _page = 1;
          }),
        ),
        const SizedBox(height: 14),
        if (filtered.isEmpty)
          TCard(
            child: REmptyState(
              icon: Icons.payments_outlined,
              title: _runs.isEmpty ? 'No payroll runs yet' : 'No runs with this status',
              description: 'Create a run for the pay period, add your staff, approve it, then mark it paid.',
              actionLabel: 'New payroll run',
              onAction: _newRun,
            ),
          )
        else
          TCard(
            padding: const EdgeInsets.all(10),
            child: MobileCardList<Map>(
              items: pageSlice(filtered, _page, _pageSize),
              striped: true,
              keyOf: (r) => '${r['payrollRunId']}',
              primary: (r) => tStr(r['runNumber']),
              secondary: (r) => '${_d(r['periodStart'])} – ${_d(r['periodEnd'])} · pay ${_d(r['payDate'])}',
              trailing: (r) => _status(r['status']),
              onPrimary: _open,
              highlights: (r) => [
                Highlight('Net pay', _gh(tNum(r['totalNet'])), accent: Accent.emerald, wide: true),
                Highlight('Gross', _gh(tNum(r['totalGross']))),
                Highlight('Deductions', _gh(tNum(r['totalDeductions'])), accent: Accent.rose),
              ],
              details: (r) => [
                ('Staff', '${tNum(r['lineCount']).toInt()}'),
                if (tNum(r['totalLoanDeductions']) > 0) ('Staff loans', _gh(tNum(r['totalLoanDeductions']))),
              ],
              actions: _actions,
              table: (rows) => TrackerTable(
                columns: const [
                  TCol('Run', width: 120), TCol('Period', width: 190), TCol('Staff', right: true, width: 60),
                  TCol('Gross', right: true, width: 110), TCol('Deductions', right: true, width: 130), TCol('Net pay', right: true, width: 110),
                  TCol('Status', width: 100), TCol('Actions', right: true, width: 220),
                ],
                rows: [
                  for (final r in rows)
                    [
                      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(tStr(r['runNumber']), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                        Text('pay ${_d(r['payDate'])}', style: const TextStyle(fontSize: 11, color: TColors.slate500)),
                      ]),
                      cellText('${_d(r['periodStart'])} – ${_d(r['periodEnd'])}'),
                      cellText('${tNum(r['lineCount']).toInt()}'),
                      cellText(_gh(tNum(r['totalGross']))),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                        Text(_gh(tNum(r['totalDeductions']))),
                        if (tNum(r['totalLoanDeductions']) > 0)
                          Text('${_gh(tNum(r['totalLoanDeductions']))} staff loans', style: const TextStyle(fontSize: 11, color: TColors.rose700)),
                      ]),
                      cellText(_gh(tNum(r['totalNet'])), bold: true),
                      Align(alignment: Alignment.centerLeft, child: _status(r['status'])),
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
          ),
      ]);
    }
    return Scaffold(
      backgroundColor: TColors.slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Payroll')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [body]),
      ),
    );
  }
}

// ------------------------------------------------------------------ New run

class _NewRunDialog extends StatefulWidget {
  const _NewRunDialog({required this.api, required this.accounts, required this.fmt});
  final _PayrollApi api;
  final List<Map> accounts;
  final FarmMoney fmt;
  @override
  State<_NewRunDialog> createState() => _NewRunDialogState();
}

class _NewRunDialogState extends State<_NewRunDialog> {
  String _start = '${rTodayIso().substring(0, 8)}01', _end = rTodayIso(), _pay = rTodayIso();
  int? _account;
  final _notes = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() => _saving = true);
    final ok = await widget.api.run<Object?>(
      context,
      'Could not create the payroll run',
      () => widget.api.api.post(widget.api.u('/payroll/runs'), body: {
        'periodStart': _start,
        'periodEnd': _end,
        'payDate': _pay.isEmpty ? null : _pay,
        'cashAccountId': _account,
        'notes': _notes.text.isEmpty ? null : _notes.text,
      }),
      (_) => 'Payroll run created',
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => rDialog(
        title: 'New payroll run',
        description: 'Choose the pay period. Staff are added after the run is created.',
        children: [
          rField('Period start *', rDateInput(_start, (v) => setState(() => _start = v))),
          rField('Period end *', rDateInput(_end, (v) => setState(() => _end = v))),
          rField('Pay date', rDateInput(_pay, (v) => setState(() => _pay = v))),
          rField('Pay from', _accountSelect(widget.accounts, widget.fmt, _account, (v) => setState(() => _account = v))),
          rField('Notes', AppInput(controller: _notes)),
        ],
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          rConfirm('Create', _saving ? null : _create),
        ],
      );
}

// ------------------------------------------------------------------ Mark paid / reason

class _MarkPaidDialog extends StatefulWidget {
  const _MarkPaidDialog({required this.api, required this.run, required this.accounts, required this.fmt});
  final _PayrollApi api;
  final Map run;
  final List<Map> accounts;
  final FarmMoney fmt;
  @override
  State<_MarkPaidDialog> createState() => _MarkPaidDialogState();
}

class _MarkPaidDialogState extends State<_MarkPaidDialog> {
  late String _date = markPaidDefaultDate(widget.run);
  late int? _account = tIntOrNull(widget.run['cashAccountId']);
  bool _saving = false;

  Future<void> _go() async {
    setState(() => _saving = true);
    final r = widget.run;
    final ok = await widget.api.run<Object?>(
      context,
      'Could not mark paid',
      () => widget.api.api.post(widget.api.u('/payroll/runs/${tIntOrNull(r['payrollRunId'])}/mark-paid'),
          body: {'payDate': _date, 'cashAccountId': _account}),
      (_) => '${widget.fmt(tNum(r['totalNet']))} net pay paid out',
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.run;
    return rDialog(
      title: 'Mark ${tStr(r['runNumber'])} paid',
      description:
          '${widget.fmt(tNum(r['totalNet']))} net pay leaves the account below. The P&L shows ${widget.fmt(tNum(r['totalGross']))} of wages.',
      children: [
        rField('Paid on', rDateInput(_date, (v) => setState(() => _date = v), max: rTodayIso())),
        rField('Paid from', _accountSelect(widget.accounts, widget.fmt, _account, (v) => setState(() => _account = v))),
      ],
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Back')),
        rConfirm('Mark paid', _saving ? null : _go, color: const Color(0xFF16A34A)),
      ],
    );
  }
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.api, required this.run, required this.reopen});
  final _PayrollApi api;
  final Map run;
  final bool reopen;
  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  String _reason = '';
  bool _saving = false;

  Future<void> _go() async {
    if (widget.reopen && _reason.trim().isEmpty) {
      trackerToast(context, 'Give a reason', error: true);
      return;
    }
    setState(() => _saving = true);
    final id = tIntOrNull(widget.run['payrollRunId']);
    final ok = await widget.api.run<Object?>(
      context,
      widget.reopen ? 'Could not reopen' : 'Could not cancel',
      () => widget.api.api.post(widget.api.u('/payroll/runs/$id/${widget.reopen ? 'reopen' : 'cancel'}'), body: {'reason': _reason}),
      (_) => widget.reopen ? 'Payroll run reopened' : 'Payroll run cancelled',
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => rDialog(
        title: widget.reopen ? 'Reopen ${tStr(widget.run['runNumber'])}?' : 'Cancel ${tStr(widget.run['runNumber'])}?',
        description: widget.reopen
            ? 'The run goes back to Draft so its lines can be corrected. Staff loan repayments it recorded are reversed, and come back when it is approved again.'
            : 'The run is closed. Any staff loan repayments it recorded are reversed; no money has left for it.',
        children: [
          rField(widget.reopen ? 'Reason *' : 'Reason (optional)',
              ReasonSelect(options: widget.reopen ? reopenReasons : cancelReasons, value: _reason, onChanged: (v) => setState(() => _reason = v))),
        ],
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Back')),
          rConfirm(widget.reopen ? 'Reopen' : 'Cancel run', _saving ? null : _go, color: widget.reopen ? restaurantRose : TColors.red600),
        ],
      );
}

// ------------------------------------------------------------------ Run page

class _LoanRow {
  _LoanRow(this.loan, String amount) : amount = TextEditingController(text: amount);
  final Map loan;
  final TextEditingController amount;
  num get available => tNum(loan['available']);
  num get outstanding => tNum(loan['outstandingBalance']);
}

/// The web's run-detail dialog, as a page of its own on a phone.
class _RunPage extends StatefulWidget {
  const _RunPage({required this.api, required this.runId, required this.staff, required this.accounts, required this.fmt, required this.onChanged});
  final _PayrollApi api;
  final int runId;
  final List<Map> staff, accounts;
  final FarmMoney fmt;
  final Future<void> Function() onChanged;
  @override
  State<_RunPage> createState() => _RunPageState();
}

class _RunPageState extends State<_RunPage> {
  Map? _detail;
  bool _saving = false;
  int? _editingLineId;
  int? _staffId;
  final _basic = TextEditingController(), _allow = TextEditingController(), _ot = TextEditingController();
  final _bonus = TextEditingController(), _other = TextEditingController();
  String _method = 'Cash';
  List<_LoanRow> _loans = [];

  _PayrollApi get _p => widget.api;
  FarmMoney get _gh => widget.fmt;
  Map get _run => (_detail?['run'] as Map?) ?? const {};
  List<Map> get _lines => rowsOf(_detail?['lines']);
  List<Map> get _deductions => rowsOf(_detail?['deductions']);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    for (final c in [_basic, _allow, _ot, _bonus, _other, ..._loans.map((l) => l.amount)]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final r = await _p.api.get(_p.u('/payroll/runs/${widget.runId}'));
      if (mounted) setState(() => _detail = r is Map ? r : null);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not open the run', description: e.message, error: true);
    }
  }

  Future<void> _afterChange() async {
    await _reload();
    await widget.onChanged();
  }

  void _resetLine() => setState(() {
        _editingLineId = null;
        _staffId = null;
        for (final c in [_basic, _allow, _ot, _bonus, _other]) {
          c.clear();
        }
        _method = 'Cash';
        _loans = [];
      });

  Future<void> _loadLoans(int staffId, int? lineId) async {
    setState(() => _loans = []);
    try {
      final rows = rowsOf(await _p.api.get(_p.u('/staff-loans/eligible', {'staffId': staffId, 'excludeLineId': lineId})));
      if (!mounted) return;
      setState(() => _loans = [
            for (final l in rows) _LoanRow(l, _plain(tNum(lineId != null ? l['currentDeduction'] : l['suggestedDeduction']))),
          ]);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load staff loans', description: e.message, error: true);
    }
  }

  void _pickStaff(int? id) {
    final s = widget.staff.where((x) => tIntOrNull(x['restaurantStaffId']) == id).firstOrNull;
    _resetLine();
    setState(() {
      _staffId = id;
      _basic.text = s == null ? '' : _plain(tNum(s['basePay']));
    });
    if (id != null) _loadLoans(id, null);
  }

  void _editLine(Map l) {
    setState(() {
      _editingLineId = tIntOrNull(l['payrollLineId']);
      _staffId = tIntOrNull(l['restaurantStaffId']);
      _basic.text = _plain(tNum(l['basicPay']));
      String opt(Object? v) => tNum(v) != 0 ? _plain(tNum(v)) : '';
      _allow.text = opt(l['allowances']);
      _ot.text = opt(l['overtime']);
      _bonus.text = opt(l['bonus']);
      _other.text = opt(l['otherDeductions']);
      _method = tStr(l['paymentMethod']).isEmpty ? 'Cash' : tStr(l['paymentMethod']);
    });
    _loadLoans(_staffId!, _editingLineId);
  }

  num get _gross => _n(_basic.text) + _n(_allow.text) + _n(_ot.text) + _n(_bonus.text);
  num get _loanSum => _loans.fold<num>(0, (s, l) => s + _n(l.amount.text));
  num get _net => _gross - _n(_other.text) - _loanSum;

  Future<void> _saveLine() async {
    if (_staffId == null) return trackerToast(context, 'Choose the staff member', error: true);
    final over = _loans.where((l) => _n(l.amount.text) > l.available + 0.001).firstOrNull;
    if (over != null) return trackerToast(context, 'At most ${_gh(over.available)} can be deducted for ${tStr(over.loan['loanNumber'])}', error: true);
    if (_net < 0) return trackerToast(context, 'Deductions are more than the pay', error: true);
    setState(() => _saving = true);
    final editing = _editingLineId != null;
    final ok = await _p.run<Object?>(
      context,
      'Could not save the line',
      () => _p.api.post(_p.u('/payroll/runs/${widget.runId}/lines'), body: {
        'restaurantStaffId': _staffId,
        'basicPay': _n(_basic.text),
        'allowances': _n(_allow.text),
        'overtime': _n(_ot.text),
        'bonus': _n(_bonus.text),
        'otherDeductions': _n(_other.text),
        'paymentMethod': _method,
        'loanDeductions': [for (final l in _loans) {'loanId': tIntOrNull(l.loan['staffLoanId']), 'amount': _n(l.amount.text)}],
      }),
      (_) => editing ? 'Line updated' : 'Line added',
    );
    if (mounted) setState(() => _saving = false);
    if (ok) {
      _resetLine();
      await _afterChange();
    }
  }

  Future<void> _removeLine(Map l) async {
    final ok = await _p.run<Object?>(
        context, 'Could not remove the line', () => _p.api.delete(_p.u('/payroll/lines/${tIntOrNull(l['payrollLineId'])}')), (_) => 'Line removed');
    if (ok) {
      if (_editingLineId == tIntOrNull(l['payrollLineId'])) _resetLine();
      await _afterChange();
    }
  }

  Future<void> _addAll() async {
    setState(() => _saving = true);
    final ok = await _p.run<Object?>(context, 'Could not add staff', () => _p.api.post(_p.u('/payroll/runs/${widget.runId}/add-all-staff')), (x) {
      final n = x is Map ? tNum(x['added']) : 0;
      return n > 0
          ? '${_plain(n)} staff member(s) added at their base pay, with suggested loan deductions'
          : 'Every active staff member is already on this run';
    });
    if (mounted) setState(() => _saving = false);
    if (ok) await _afterChange();
  }

  Future<void> _act(Future<bool> Function() f) async {
    if (await f()) await _afterChange();
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    if (d == null) {
      return Scaffold(appBar: AppBar(title: const Text('Payroll run')), body: const Center(child: LoadingLine('Loading…')));
    }
    final run = _run;
    final st = tStr(run['status']);
    final isDraft = st == 'Draft';
    final onRun = {for (final l in _lines) tIntOrNull(l['restaurantStaffId'])};
    final notOnRun = [for (final s in widget.staff) if (s['isActive'] == true && !onRun.contains(tIntOrNull(s['restaurantStaffId']))) s];
    final loanTotal = tNum(run['totalLoanDeductions']);
    Widget figure(String label, String value, Color c) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c))),
          ]),
        );

    return Scaffold(
      backgroundColor: TColors.slate50,
      appBar: AppBar(title: Text(tStr(run['runNumber']))),
      body: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('${tStr(run['runNumber'])} · ${_d(run['periodStart'])} – ${_d(run['periodEnd'])}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: TColors.slate900)),
          _status(st),
        ]),
        const SizedBox(height: 4),
        Text('Pay date ${_d(run['payDate'])} · paid from ${tStr(run['cashAccountName']).isEmpty ? 'Main Cash Box' : tStr(run['cashAccountName'])}',
            style: const TextStyle(fontSize: 13, color: TColors.slate500)),
        const SizedBox(height: 12),
        twoColumns([
          figure('Gross pay', _gh(tNum(run['totalGross'])), TColors.slate900),
          figure('Other deductions', _gh(tNum(run['totalDeductions']) - loanTotal), TColors.amber700),
          figure('Staff loan repayments', _gh(loanTotal), TColors.rose700),
          figure('Net pay', _gh(tNum(run['totalNet'])), const Color(0xFF15803D)),
        ], gap: 8),
        if (loanTotal > 0) ...[
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.info_outline, size: 14, color: TColors.slate600),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                isDraft
                    ? 'Staff loan deductions are recorded as repayments when this run is approved.'
                    : st == 'Cancelled'
                        ? "This run's staff loan repayments were reversed."
                        : "These deductions are recorded against the staff members' loans.",
                style: const TextStyle(fontSize: 12, color: TColors.slate600),
              ),
            ),
          ]),
        ],
        const SizedBox(height: 12),
        TCard(
          padding: const EdgeInsets.all(10),
          child: _lines.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('No staff on this run yet.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate400)))
              : Column(children: [
                  for (final l in _lines) _lineCard(l, isDraft),
                ]),
        ),
        if (isDraft) ...[
          if (notOnRun.isNotEmpty && _editingLineId == null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: TColors.rose50, border: Border.all(color: TColors.rose200), borderRadius: BorderRadius.circular(8)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '${notOnRun.length}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      const TextSpan(text: ' active staff member(s) are not on this run yet.'),
                    ]),
                    style: const TextStyle(fontSize: 13, color: TColors.rose800)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: TColors.rose700, side: const BorderSide(color: Color(0xFFFDA4AF))),
                  onPressed: _saving ? null : _addAll,
                  icon: const Icon(Icons.groups_outlined, size: 16),
                  label: const Text('Add all at base pay'),
                ),
              ]),
            ),
          ],
          if (_editingLineId != null || notOnRun.isNotEmpty) ...[
            const SizedBox(height: 12),
            _lineForm(notOnRun),
          ],
        ],
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (isDraft)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
              onPressed: _saving || _lines.isEmpty ? null : () => _act(() => _p.approve(context, run)),
              icon: const Icon(Icons.check_circle_outline, size: 16),
              label: const Text('Approve'),
            ),
          if (st == 'Approved') ...[
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
              onPressed: () => _act(() => _p.markPaid(context, run, widget.accounts, _gh)),
              icon: const Icon(Icons.account_balance_wallet_outlined, size: 16),
              label: const Text('Mark paid'),
            ),
            OutlinedButton.icon(
              onPressed: () => _act(() => _p.reason(context, run, reopen: true)),
              icon: const Icon(Icons.undo, size: 16),
              label: const Text('Reopen'),
            ),
          ],
        ]),
        const SizedBox(height: 10),
        DefaultTextStyle.merge(
          style: const TextStyle(fontSize: 12, color: TColors.slate500),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (tStr(run['createdBy']).isNotEmpty) Text('Created by ${tStr(run['createdBy'])}'),
            if (tStr(run['approvedBy']).isNotEmpty) Text('Approved by ${tStr(run['approvedBy'])}'),
            if (tStr(run['paidBy']).isNotEmpty) Text('Paid by ${tStr(run['paidBy'])} on ${_d(run['payDate'])}'),
            if (tStr(run['reopenedBy']).isNotEmpty) Text('Last reopened by ${tStr(run['reopenedBy'])}: ${tStr(run['reopenReason'])}'),
            if (tStr(run['cancelledBy']).isNotEmpty)
              Text('Cancelled by ${tStr(run['cancelledBy'])}${tStr(run['cancelReason']).isNotEmpty ? ': ${tStr(run['cancelReason'])}' : ''}'),
          ]),
        ),
      ]),
    );
  }

  Widget _lineCard(Map l, bool isDraft) {
    final id = tIntOrNull(l['payrollLineId']);
    final deds = [for (final x in _deductions) if (tIntOrNull(x['payrollLineId']) == id) x];
    Widget kv(String k, num v) => Padding(
          padding: const EdgeInsets.only(right: 14, top: 2),
          child: Text.rich(TextSpan(children: [
            TextSpan(text: '$k ', style: const TextStyle(color: TColors.slate500)),
            TextSpan(text: _gh(v), style: const TextStyle(color: TColors.slate900)),
          ]), style: const TextStyle(fontSize: 12)),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _editingLineId == id ? TColors.rose50 : Colors.white,
        border: Border.all(color: TColors.slate200),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tStr(l['staffName']), style: const TextStyle(fontWeight: FontWeight.w600, color: TColors.slate900)),
              Text('${tStr(l['staffRole'])}${tStr(l['salaryType']).isNotEmpty ? ' · ${tStr(l['salaryType'])}' : ''}',
                  style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            const Text('Net', style: TextStyle(fontSize: 11, color: TColors.slate500)),
            Text(_gh(tNum(l['netPay'])), style: const TextStyle(fontWeight: FontWeight.w700, color: TColors.slate900)),
          ]),
        ]),
        const SizedBox(height: 6),
        Wrap(children: [
          kv('Basic', tNum(l['basicPay'])),
          kv('Allowances', tNum(l['allowances'])),
          kv('Overtime', tNum(l['overtime'])),
          kv('Bonus', tNum(l['bonus'])),
          kv('Gross', tNum(l['grossPay'])),
          kv('Deductions', tNum(l['otherDeductions']) + tNum(l['loanDeductions'])),
        ]),
        for (final x in deds)
          Text('${tStr(x['loanNumber'])} ${_gh(tNum(x['amount']))}',
              style: TextStyle(
                fontSize: 12,
                color: x['status'] == 'Reversed' ? TColors.slate400 : TColors.rose700,
                decoration: x['status'] == 'Reversed' ? TextDecoration.lineThrough : null,
              )),
        if (isDraft)
          Align(
            alignment: Alignment.centerRight,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _editLine(l)),
              IconButton(tooltip: 'Remove', icon: const Icon(Icons.delete_outline, size: 18, color: TColors.red600), onPressed: () => _removeLine(l)),
            ]),
          ),
      ]),
    );
  }

  Widget _lineForm(List<Map> notOnRun) {
    final editingName = _lines.where((l) => tIntOrNull(l['payrollLineId']) == _editingLineId).firstOrNull?['staffName'];
    Widget money(String label, TextEditingController c) => rField(label, rNumberInput(c, onChanged: () => setState(() {})));
    return TCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(_editingLineId != null ? 'Edit line: ${tStr(editingName)}' : 'Add one staff member',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        rField(
          'Staff *',
          AppSelect<int>(
            value: _staffId,
            hintText: 'Choose staff',
            enabled: _editingLineId == null,
            items: [
              if (_editingLineId != null && _staffId != null) AppSelectItem(value: _staffId!, label: tStr(editingName)),
              for (final s in notOnRun)
                AppSelectItem(
                  value: tIntOrNull(s['restaurantStaffId'])!,
                  label: '${'${tStr(s['firstName'])} ${tStr(s['lastName'])}'.trim()} — ${tStr(s['role'])} (${tStr(s['salaryType'])} ${_gh(tNum(s['basePay']))})',
                ),
            ],
            onChanged: _pickStaff,
          ),
        ),
        const SizedBox(height: 12),
        twoColumns([
          money('Basic pay', _basic),
          money('Allowances', _allow),
          money('Overtime', _ot),
          money('Bonus', _bonus),
          money('Other deductions', _other),
          rField(
            'Paid by',
            AppSelect<String>(
              value: _method,
              items: [for (final m in ['Cash', 'MoMo', 'Bank']) AppSelectItem(value: m, label: m)],
              onChanged: (v) => setState(() => _method = v ?? 'Cash'),
            ),
          ),
        ], gap: 10),
        if (_loans.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: TColors.rose50, border: Border.all(color: TColors.rose200), borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Row(children: [
                Icon(Icons.volunteer_activism_outlined, size: 16, color: TColors.rose800),
                SizedBox(width: 6),
                Flexible(child: Text('Staff loan deductions', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: TColors.rose800))),
              ]),
              for (final l in _loans) ...[
                const SizedBox(height: 10),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: tStr(l.loan['loanNumber']), style: const TextStyle(fontWeight: FontWeight.w600)),
                    TextSpan(text: ' · ${staffLoanTypeLabel(l.loan['loanType'])}'),
                    TextSpan(text: ' — owes ${_gh(l.outstanding)}', style: const TextStyle(color: TColors.slate600)),
                    if (l.available < l.outstanding)
                      TextSpan(text: ' (${_gh(l.outstanding - l.available)} already on another draft run)', style: const TextStyle(color: TColors.amber700)),
                    if (tNum(l.loan['suggestedDeduction']) > 0)
                      TextSpan(text: ' · suggested ${_gh(tNum(l.loan['suggestedDeduction']))}', style: const TextStyle(color: TColors.slate500)),
                  ]),
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 6),
                rNumberInput(l.amount, onChanged: () => setState(() {})),
              ],
              const SizedBox(height: 8),
              const Text(
                'Taken from net pay; nothing extra leaves the till. The loan balance falls when the run is approved. Set 0 to skip a loan this period.',
                style: TextStyle(fontSize: 12, color: TColors.rose800),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          'Gross ${_gh(_gross)} · Net pay ${_gh(_net)}${_net < 0 ? ' — deductions are more than the pay' : ''}',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _net < 0 ? TColors.red600 : TColors.slate700),
        ),
        const SizedBox(height: 10),
        Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
          if (_editingLineId != null) OutlinedButton(onPressed: _resetLine, child: const Text('Cancel')),
          rConfirm(_editingLineId != null ? 'Update line' : 'Add line', _saving ? null : _saveLine),
        ]),
      ]),
    );
  }
}
