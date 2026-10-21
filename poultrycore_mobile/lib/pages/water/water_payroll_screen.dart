import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/expenses/payroll_screen.dart' show PayrollDeductionsDialog, payrollBadge, payrollDeductionFor;
import '../poultry/money/money_widgets.dart';
import '../poultry/reports/report_format.dart';
import '../poultry/reports/report_routes.dart' show openAppHref;
import '../poultry/sales/balances_logic.dart' show pageSlice;
import '../poultry/sales/balances_widgets.dart';
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/business_dates.dart';
import '../shared/company_clock.dart';
import '../shared/reason_select.dart';
import 'reports/water_money_reports.dart' show waterMoneyRail;

/// Water → Expenses → Payroll, as `app/water-payroll/page.tsx`: pay runs
/// (Draft/Pending → Approved → Paid, Reopen, Cancel, Delete), opening a run to
/// add or replace staff lines with their advance deductions, and the run's
/// Details page (`app/water-payroll/[id]/page.tsx`). Water's page differs from
/// Poultry's: search/date filters, no pay-date prompt on Mark paid, Pending
/// runs editable, and the run opened in place rather than on a lines page.

/// EDITABLE_STATUSES: Reopened sits with Draft/Pending so corrections can be made.
bool waterPayrollEditable(Object? status) => const {'Draft', 'Pending', 'Reopened'}.contains(tStr(status));

String _day(Object? v) => tStr(v).split('T').first;
String _f2(Object? v) => tNum(v).toStringAsFixed(2);

class WaterPayrollScreen extends StatefulWidget {
  const WaterPayrollScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<WaterPayrollScreen> createState() => _WaterPayrollScreenState();
}

class _WaterPayrollScreenState extends State<WaterPayrollScreen> {
  List<Map> _runs = [], _staff = [], _accounts = [];
  bool _loading = true;
  final _search = TextEditingController();
  String _from = '', _to = '';
  int _page = 1, _pageSize = 10, _lastTotal = -1;
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  String get _me => Uri.encodeQueryComponent(widget.session.tokens.userId ?? '');
  String get _q => 'farmId=${Uri.encodeQueryComponent(_farmId)}';

  @override
  void initState() {
    super.initState();
    CompanyClock.load(widget.session, widget.company).then((c) {
      if (mounted) setState(() => _offset = c.offset);
    });
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final q = {'farmId': _farmId};
      final r = await Future.wait([_api.get('/api/Water/payroll-runs', query: q), _api.get('/api/Water/staff', query: q), _api.get('/api/Water/cash-accounts', query: q)]);
      if (mounted) {
        setState(() {
          _runs = rowsOf(r[0]);
          _staff = rowsOf(r[1]);
          _accounts = rowsOf(r[2]);
        });
      }
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load payroll', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  int _id(Map r) => tIntOrNull(r['waterPayrollRunId']) ?? 0;
  String _period(Map r) => '${_day(r['periodStart'])} → ${_day(r['periodEnd'])}';

  /// filterByDateAndSearch on periodStart, searching status and notes.
  List<Map> get _visible {
    final q = _search.text.trim().toLowerCase();
    return _runs.where((r) {
      final day = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(tStr(r['periodStart']))?[1];
      if (day != null) {
        if (_from.isNotEmpty && day.compareTo(_from) < 0) return false;
        if (_to.isNotEmpty && day.compareTo(_to) > 0) return false;
      }
      if (q.isNotEmpty && !['status', 'notes'].any((k) => r[k] != null && '${r[k]}'.toLowerCase().contains(q))) return false;
      return true;
    }).toList();
  }

  Future<void> _newRun() async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _NewWaterRunDialog(session: widget.session, company: widget.company, accounts: _accounts),
    );
    if (done == true) _load();
  }

  Future<void> _open(Map r) async {
    Map? full;
    try {
      final res = await _api.get('/api/Water/payroll-runs/${_id(r)}', query: {'farmId': _farmId});
      full = res is Map ? res : null;
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Load failed', description: e.message, error: true);
      return;
    }
    if (full == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WaterPayrollRunEditor(session: widget.session, company: widget.company, run: full!, staff: _staff, offset: _offset),
      ),
    );
    _load();
  }

  void _details(Map r) => Navigator.of(context)
      .push(
        MaterialPageRoute(
          builder: (_) => WaterPayrollDetailScreen(session: widget.session, company: widget.company, runId: _id(r)),
        ),
      )
      .then((_) => _load());

  Future<void> _approve(Map r) => _run(() => _api.post('/api/Water/payroll-runs/${_id(r)}/approve?$_q&approvedBy=$_me'), 'Run approved', 'approve failed');

  Future<void> _pay(Map r) => _run(() => _api.post('/api/Water/payroll-runs/${_id(r)}/mark-paid?$_q&paidBy=$_me', body: {'payDate': null}), 'Run marked paid', 'pay failed');

  Future<void> _run(Future<dynamic> Function() call, String ok, String fail) async {
    try {
      await call();
      if (mounted) trackerToast(context, ok);
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, fail, description: e.message, error: true);
    }
  }

  Future<void> _cancel(Map r) => showWaterPayrollPrompt(
    context,
    title: 'Cancel payroll run',
    options: cancelReasons,
    description: 'Run for ${_period(r)} will be cancelled.',
    label: 'Reason (optional)',
    placeholder: 'e.g. ran twice, wrong period, replacing with corrected run…',
    confirm: 'Cancel run',
    allowEmpty: true,
    onSubmit: (reason) async {
      try {
        await _api.post('/api/Water/payroll-runs/${_id(r)}/cancel?$_q&cancelledBy=$_me', body: {'reason': reason.isEmpty ? null : reason});
        if (mounted) trackerToast(context, 'Payroll run cancelled');
        await _load();
        return true;
      } on ApiException catch (e) {
        if (mounted) trackerToast(context, 'Cancel failed', description: e.message, error: true);
        return false;
      }
    },
  );

  Future<void> _reopen(Map r) => showWaterPayrollReopen(context, session: widget.session, company: widget.company, run: r, onDone: _load);

  Future<void> _delete(Map r) async {
    final ok = await confirmDelete(
      context,
      title: 'Delete payroll run?',
      description:
          '${_period(r)}\n\nThis removes the payroll run and all its employee payroll lines. Only available while the run is Draft, Pending, or Reopened — and never while an approved expense is still linked.',
      confirmLabel: 'Delete',
    );
    if (!ok) return;
    try {
      await _api.delete('/api/Water/payroll-runs/${_id(r)}?$_q&deletedBy=$_me');
      if (mounted) trackerToast(context, 'Payroll run removed');
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Delete failed', description: e.message, error: true);
    }
  }

  List<Widget> _actions(Map r) {
    final st = tStr(r['status']);
    Widget b(String label, VoidCallback on, {IconData? icon, Color? color}) => OutlinedButton.icon(
      onPressed: on,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: color == null ? null : BorderSide(color: color.withValues(alpha: .35)),
      ),
      icon: Icon(icon ?? Icons.circle, size: icon == null ? 0 : 16),
      label: Text(label),
    );
    return [
      b('Details', () => _details(r), icon: Icons.open_in_new),
      b('Open', () => _open(r)),
      if (waterPayrollEditable(st)) b(st == 'Reopened' ? 'Re-approve' : 'Approve', () => _approve(r), icon: Icons.check_circle_outline),
      if (st == 'Approved') b('Mark paid', () => _pay(r), color: const Color(0xFF15803D)),
      if (st == 'Approved' || st == 'Paid') b('Reopen', () => _reopen(r), color: TColors.amber700),
      if (waterPayrollEditable(st)) b('Delete', () => _delete(r), icon: Icons.delete_outline, color: TColors.red600),
      if (st != 'Cancelled' && st != 'Paid' && st != 'Approved' && st != 'Reopened') b('Cancel', () => _cancel(r), icon: Icons.cancel_outlined, color: TColors.red600),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/water-payroll');
    final visible = _visible;
    if (visible.length != _lastTotal) {
      _lastTotal = visible.length;
      _page = 1;
    }
    final pageRows = pageSlice(visible, _page, _pageSize);
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Payroll')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            const Row(
              children: [
                Icon(Icons.payments_outlined, size: 24, color: Color(0xFF0284C7)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Payroll',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => openAppHref(context, widget.session, widget.company, '/water-employee-loans', label: 'Employee Loans & Advances'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  icon: const Icon(Icons.volunteer_activism_outlined, size: 16),
                  label: const Text('Employee Loans & Advances'),
                ),
                FilledButton.icon(
                  onPressed: _newRun,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('New run'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ListFiltersCard(
              search: _search,
              searchPlaceholder: 'Search status or notes',
              onSearch: () => setState(() {}),
              from: _from,
              to: _to,
              onDates: (f, t) => setState(() {
                _from = f;
                _to = t;
              }),
              onClear: () => setState(() {
                _search.clear();
                _from = '';
                _to = '';
              }),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(padding: EdgeInsets.all(16), child: LoadingLine('Loading…'))
            else if (_runs.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: TColors.slate200),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'No payroll runs yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: TColors.slate500),
                ),
              )
            else if (visible.isNotEmpty)
              MobileCardList<Map>(
                striped: true,
                items: pageRows,
                keyOf: (r) => '${_id(r)}',
                primary: _period,
                secondaryBuilder: (r) => Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [Text('Net ${_f2(r['totalNetPay'])}'), payrollBadge(r['status'])]),
                highlights: (r) => [Highlight('Gross', _f2(r['totalGrossPay']), accent: Accent.blue), Highlight('Net', _f2(r['totalNetPay']), accent: Accent.emerald)],
                details: (r) => [
                  ('Period', '${fmtDateTime(r['periodStart'], r, _offset)} → ${fmtDateTime(r['periodEnd'], r, _offset)}'),
                  ('Cash account', tStr(r['cashAccountName']).isEmpty ? '—' : tStr(r['cashAccountName'])),
                  ('Status', tStr(r['status'])),
                ],
                actions: _actions,
                table: (items) => TrackerTable(
                  columns: const [
                    TCol('Period', width: 220),
                    TCol('Gross', right: true, width: 100),
                    TCol('Net', right: true, width: 100),
                    TCol('Cash account', width: 130),
                    TCol('Status', width: 110),
                    TCol('Actions', right: true, width: 420),
                  ],
                  rows: [
                    for (final r in items)
                      [
                        cellText('${fmtDateTime(r['periodStart'], r, _offset)} → ${fmtDateTime(r['periodEnd'], r, _offset)}', bold: true),
                        Align(alignment: Alignment.centerRight, child: cellText(_f2(r['totalGrossPay']))),
                        Align(alignment: Alignment.centerRight, child: cellText(_f2(r['totalNetPay']), bold: true)),
                        cellText(tStr(r['cashAccountName']).isEmpty ? '—' : tStr(r['cashAccountName'])),
                        Align(alignment: Alignment.centerLeft, child: payrollBadge(r['status'])),
                        Wrap(alignment: WrapAlignment.end, spacing: 4, children: _actions(r)),
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

// ------------------------------------------------------------------ dialogs

/// PromptDialog: a title, a description, one text box, and a confirm button.
/// With [options] the reason is picked from that list, and the box opens only
/// for "Other" (lib/reversal-reasons.ts).
Future<void> showWaterPayrollPrompt(
  BuildContext context, {
  required String title,
  required String description,
  required String label,
  required String placeholder,
  required String confirm,
  bool allowEmpty = false,
  List<String>? options,
  required Future<bool> Function(String reason) onSubmit,
}) => showDialog<void>(
  context: context,
  builder: (_) => _PromptDialog(
      title: title, description: description, label: label, placeholder: placeholder, confirm: confirm, allowEmpty: allowEmpty, options: options, onSubmit: onSubmit),
);

/// "Reopen payroll run": a reason is required; the linked expense is reversed
/// (and the cash refunded when the run was Paid).
Future<void> showWaterPayrollReopen(BuildContext context, {required Session session, required Company company, required Map run, required Future<void> Function() onDone}) => showWaterPayrollPrompt(
  context,
  title: 'Reopen payroll run',
  description:
      'Run for ${_day(run['periodStart'])} → ${_day(run['periodEnd'])} will be reopened. The linked payroll expense will be reversed${tStr(run['status']) == 'Paid' ? ' and the cash account refunded' : ''}.',
  label: 'Reason *',
  placeholder: 'e.g. wrong amount for Kofi, missed bonus, correcting period…',
  confirm: 'Reopen run',
  options: reopenReasons,
  onSubmit: (reason) async {
    if (reason.trim().isEmpty) {
      trackerToast(context, 'Reason required', description: 'Tell future-you why this payroll is being reopened.', error: true);
      return false;
    }
    try {
      await session.farmClient.post(
        '/api/Water/payroll-runs/${tStr(run['waterPayrollRunId'])}/unapprove?farmId=${Uri.encodeQueryComponent(company.farmId)}&reopenedBy=${Uri.encodeQueryComponent(session.tokens.userId ?? '')}',
        body: {'reason': reason.trim()},
      );
      if (context.mounted) trackerToast(context, 'Payroll reopened', description: 'Linked expense reversed. Make corrections and approve again.');
      await onDone();
      return true;
    } on ApiException catch (e) {
      if (context.mounted) trackerToast(context, 'Reopen failed', description: e.message, error: true);
      return false;
    }
  },
);

class _PromptDialog extends StatefulWidget {
  const _PromptDialog(
      {required this.title, required this.description, required this.label, required this.placeholder, required this.confirm, required this.allowEmpty, this.options, required this.onSubmit});
  final String title, description, label, placeholder, confirm;
  final bool allowEmpty;
  final List<String>? options;
  final Future<bool> Function(String) onSubmit;
  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  final _text = TextEditingController();
  bool _busy = false;
  String _choice = '';
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final r = promptReasonValue(widget.options, _choice, _text.text, label: widget.label, allowEmpty: widget.allowEmpty);
    if (r.error != null) return setState(() => _error = r.error);
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.onSubmit(r.value!);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    // A set width, as Poultry's reason dialog has, so it does not shrink to its text.
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.description, style: const TextStyle(fontSize: 13, color: TColors.slate600)),
          const SizedBox(height: 12),
          if (widget.options == null)
            FilterLabel(widget.label, AppInput(controller: _text, hintText: widget.placeholder, onChanged: (_) => setState(() {})))
          else
            FilterLabel(
              widget.label,
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                AppSelect<String>(
                  value: _choice.isEmpty ? null : _choice,
                  hintText: 'Select a reason',
                  items: [for (final o in widget.options!) AppSelectItem(value: o, label: o)],
                  onChanged: (v) => setState(() {
                    _choice = v ?? '';
                    _error = null;
                  }),
                ),
                if (_choice == 'Other') ...[
                  const SizedBox(height: 8),
                  AppInput(controller: _text, hintText: 'Say what happened', autofocus: true, onChanged: (_) => setState(() {})),
                ],
              ]),
            ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(_error!, style: const TextStyle(fontSize: 13, color: TColors.rose700)),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        style: FilledButton.styleFrom(backgroundColor: TColors.red600),
        onPressed: _busy || (widget.options == null && !widget.allowEmpty && _text.text.trim().isEmpty) ? null : _go,
        child: Text(widget.confirm),
      ),
    ],
  );
}

/// New payroll run: period, the cash account used at Mark-Paid, notes.
class _NewWaterRunDialog extends StatefulWidget {
  const _NewWaterRunDialog({required this.session, required this.company, required this.accounts});
  final Session session;
  final Company company;
  final List<Map> accounts;
  @override
  State<_NewWaterRunDialog> createState() => _NewWaterRunDialogState();
}

class _NewWaterRunDialogState extends State<_NewWaterRunDialog> {
  String _start = '', _end = '';
  int _account = 0;
  final _notes = TextEditingController();

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_start.isEmpty || _end.isEmpty) {
      trackerToast(context, 'Period required', error: true);
      return;
    }
    try {
      await widget.session.farmClient.post(
        '/api/Water/payroll-runs?createdBy=${Uri.encodeQueryComponent(widget.session.tokens.userId ?? '')}',
        body: {'periodStart': _start, 'periodEnd': _end, 'waterCashAccountId': _account == 0 ? null : _account, 'notes': _notes.text.isEmpty ? null : _notes.text, 'farmId': widget.company.farmId},
      );
      if (!mounted) return;
      trackerToast(context, 'Run created');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Create failed', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = [
      for (final a in widget.accounts)
        if (a['isActive'] == true) a,
    ];
    return AlertDialog(
      scrollable: true,
      title: const Row(
        children: [
          Icon(Icons.payments_outlined, color: Color(0xFF2563EB)),
          SizedBox(width: 8),
          Flexible(child: Text('New payroll run')),
        ],
      ),
      // A set width, as Poultry's New run dialog has: without it the dialog
      // shrinks to its content and the fields come out squeezed.
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Open a payroll run for a pay period', style: TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 12),
            formSection('Period', const Color(0xFF4F46E5), [
              FilterLabel('Period start *', FilterDate(value: _start, hint: 'Pick a date', onChanged: (v) => setState(() => _start = v))),
              FilterLabel('Period end *', FilterDate(value: _end, hint: 'Pick a date', onChanged: (v) => setState(() => _end = v))),
            ]),
            const SizedBox(height: 10),
            formSection('Payment', TColors.amber600, [
              FilterLabel(
                'Cash account (used at Mark-Paid)',
                AppSelect<int>(
                  value: _account == 0 ? null : _account,
                  hintText: 'Pick account',
                  items: [for (final a in active) AppSelectItem(value: tIntOrNull(a['waterCashAccountId']) ?? 0, label: '${tStr(a['accountName'])} (${_f2(a['currentBalance'])})')],
                  onChanged: (v) => setState(() => _account = v ?? 0),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            formSection('Notes', TColors.slate500, [FilterLabel('Notes', AppInput(controller: _notes))]),
          ],
        ),
      ),
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: TColors.red600),
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _create, child: const Text('Create')),
      ],
    );
  }
}

// ------------------------------------------------------------------ editor

/// The web's "Run: … → …" dialog, as a page: totals, items (with the active
/// advance hint and the deductions breakdown), history, and Add / replace item.
class WaterPayrollRunEditor extends StatefulWidget {
  const WaterPayrollRunEditor({super.key, required this.session, required this.company, required this.run, required this.staff, required this.offset});
  final Session session;
  final Company company;
  final Map run;
  final List<Map> staff;
  final Duration offset;
  @override
  State<WaterPayrollRunEditor> createState() => _WaterPayrollRunEditorState();
}

class _WaterPayrollRunEditorState extends State<WaterPayrollRunEditor> {
  late Map _run = widget.run;
  Map<int, Map> _hints = {};
  int _staffId = 0;
  final _basic = TextEditingController(text: '0'),
      _daily = TextEditingController(text: '0'),
      _commission = TextEditingController(text: '0'),
      _bonus = TextEditingController(text: '0'),
      _deductions = TextEditingController(text: '0');
  List<Map> _staffLoans = [];
  bool _staffLoansBusy = false;

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  int get _runId => tIntOrNull(_run['waterPayrollRunId']) ?? 0;

  @override
  void initState() {
    super.initState();
    _loadHints();
  }

  @override
  void dispose() {
    for (final c in [_basic, _daily, _commission, _bonus, _deductions]) {
      c.dispose();
    }
    super.dispose();
  }

  String _plain(num n) => n == n.roundToDouble() ? '${n.toInt()}' : '$n';
  num _n(TextEditingController c) => num.tryParse(c.text) ?? 0;

  /// One request for the whole run: which lines have advances outstanding.
  Future<void> _loadHints() async {
    try {
      final rows = rowsOf(await _api.get('/api/Water/payroll-deductions/run/$_runId', query: {'farmId': _farmId}));
      if (mounted) setState(() => _hints = {for (final r in rows) tIntOrNull(r['waterPayrollItemId']) ?? 0: r});
    } on ApiException {
      if (mounted) setState(() => _hints = {});
    }
  }

  Future<void> _refresh() async {
    try {
      final r = await _api.get('/api/Water/payroll-runs/$_runId', query: {'farmId': _farmId});
      if (r is Map && mounted) setState(() => _run = r);
      await _loadHints();
    } on ApiException {
      // no-op, as the web
    }
  }

  /// prefillFromStaff: Basic from the staff record's basePay, then the advances.
  void _pickStaff(int id) {
    final m = widget.staff.where((x) => tIntOrNull(x['waterStaffId']) == id).firstOrNull;
    setState(() {
      _staffId = id;
      if (m != null) _basic.text = _plain(tNum(m['basePay']));
    });
    _loadStaffLoans(id);
  }

  Future<void> _loadStaffLoans(int id) async {
    if (id == 0) {
      setState(() => _staffLoans = []);
      return;
    }
    setState(() => _staffLoansBusy = true);
    try {
      final list = rowsOf(await _api.get('/api/Water/employee-loans/eligible', query: {'farmId': _farmId, 'staffId': '$id'}));
      final auto = list.fold<num>(0, (s, e) => s + payrollDeductionFor(e));
      if (mounted) {
        setState(() {
          _staffLoans = list;
          _deductions.text = _plain(auto);
        });
      }
    } on ApiException {
      if (mounted) setState(() => _staffLoans = []);
    }
    if (mounted) setState(() => _staffLoansBusy = false);
  }

  /// autoAddSuggestedDeductions: Draft deductions for advances repaid by
  /// payroll, never twice. A failure never loses the saved item.
  Future<List<String>> _autoAdd(int itemId, int staffId) async {
    try {
      final r = await Future.wait([
        _api.get('/api/Water/employee-loans/eligible', query: {'farmId': _farmId, 'staffId': '$staffId'}),
        _api.get('/api/Water/payroll-deductions', query: {'farmId': _farmId, 'payrollItemId': '$itemId'}),
      ]);
      final already = {
        for (final d in rowsOf(r[1]))
          if (d['waterEmployeeLoanId'] != null) tIntOrNull(d['waterEmployeeLoanId']),
      };
      final added = <String>[];
      for (final e in rowsOf(r[0])) {
        final lid = tIntOrNull(e['waterEmployeeLoanId']);
        if (already.contains(lid)) continue;
        final amount = payrollDeductionFor(e);
        if (amount <= 0) continue;
        await _api.post(
          '/api/Water/payroll-deductions',
          body: {
            'waterPayrollItemId': itemId,
            'deductionType': tStr(e['loanType']) == 'SalaryAdvance' ? 'SalaryAdvanceRepayment' : 'EmployeeLoanRepayment',
            'amount': amount,
            'waterEmployeeLoanId': lid,
            'farmId': _farmId,
            'savedBy': widget.session.tokens.userId,
          },
        );
        added.add('${tStr(e['loanNumber']).isNotEmpty ? tStr(e['loanNumber']) : '#$lid'} ${amount.toStringAsFixed(2)}');
      }
      return added;
    } on ApiException {
      return [];
    }
  }

  Future<void> _save() async {
    if (_staffId == 0) {
      trackerToast(context, 'Pick staff', error: true);
      return;
    }
    try {
      final staffId = _staffId;
      final saved = await _api.post(
        '/api/Water/payroll-runs/$_runId/items',
        query: {'farmId': _farmId},
        body: {
          'waterStaffId': staffId,
          'basicPay': _n(_basic),
          'dailyWage': _n(_daily),
          'commission': _n(_commission),
          'bonus': _n(_bonus),
          'deductions': _n(_deductions),
          'paymentMethod': 'Cash',
          'notes': '',
        },
      );
      final itemId = saved is Map ? tIntOrNull(saved['waterPayrollItemId']) ?? 0 : 0;
      final added = await _autoAdd(itemId, staffId);
      setState(() {
        _staffId = 0;
        for (final c in [_basic, _daily, _commission, _bonus, _deductions]) {
          c.text = '0';
        }
        _staffLoans = [];
      });
      await _refresh();
      if (mounted) {
        trackerToast(context, 'Item saved', description: added.isEmpty ? null : '${added.join(', ')} — review before approving. Nothing is repaid until you approve.');
      }
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Save failed', description: e.message, error: true);
    }
  }

  Future<void> _remove(Map i) async {
    try {
      await _api.delete('/api/Water/payroll-runs/items/${tStr(i['waterPayrollItemId'])}?farmId=${Uri.encodeQueryComponent(_farmId)}');
      await _refresh();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Remove failed', description: e.message, error: true);
    }
  }

  Future<void> _breakdown(Map i) => showDialog<void>(
    context: context,
    builder: (_) => PayrollDeductionsDialog(
      session: widget.session,
      company: widget.company,
      rail: waterMoneyRail,
      itemId: tIntOrNull(i['waterPayrollItemId']) ?? 0,
      staffId: tIntOrNull(i['waterStaffId']) ?? 0,
      staffName: tStr(i['staffName']).isEmpty ? '#${tStr(i['waterStaffId'])}' : tStr(i['staffName']),
      runStatus: tStr(_run['status']),
      fmt: const FarmMoney(),
      onChanged: _refresh,
    ),
  );

  Widget _money(String label, TextEditingController c) =>
      FilterLabel(label, AppInput(controller: c, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))]));

  @override
  Widget build(BuildContext context) {
    final r = _run;
    final items = rowsOf(r['items']);
    final editable = waterPayrollEditable(r['status']);
    final sm = const TextStyle(fontSize: 13, color: TColors.slate500);
    Widget total(String label, String value, {Color? color}) => Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$label: ', style: sm),
          TextSpan(
            text: value,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color ?? TColors.slate900),
          ),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Run')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Run: ${_day(r['periodStart'])} → ${_day(r['periodEnd'])}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              payrollBadge(r['status']),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              total('Gross', _f2(r['totalGrossPay'])),
              total('Deductions', _f2(r['totalDeductions'])),
              total('Net', _f2(r['totalNetPay']), color: const Color(0xFF15803D)),
            ],
          ),
          const Divider(height: 28),
          const Text('Items', style: TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          if (items.isEmpty) const Text('No items yet.', style: TextStyle(fontSize: 13, color: TColors.slate500)) else for (final i in items) ...[_itemCard(i, editable), const SizedBox(height: 8)],
          if (r['approvedBy'] != null || r['paidBy'] != null || r['reopenedBy'] != null || r['reapprovedBy'] != null) ...[
            const Divider(height: 28),
            const Text('History', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            ...waterPayrollHistory(r, widget.offset, withCreated: false),
          ],
          if (editable) ...[
            const Divider(height: 28),
            const Text('Add / replace item', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            FilterLabel(
              'Staff',
              AppSelect<int>(
                value: _staffId == 0 ? null : _staffId,
                hintText: 'Pick staff',
                items: [
                  for (final s in widget.staff)
                    if (s['isActive'] == true) AppSelectItem(value: tIntOrNull(s['waterStaffId']) ?? 0, label: '${tStr(s['firstName'])} ${tStr(s['lastName'])} (${tStr(s['role'])})'),
                ],
                onChanged: (v) => _pickStaff(v ?? 0),
              ),
            ),
            const SizedBox(height: 8),
            filterRow([_money('Basic', _basic), _money('Daily', _daily)]),
            const SizedBox(height: 8),
            filterRow([_money('Commission', _commission), _money('Bonus', _bonus)]),
            const SizedBox(height: 8),
            _money('Deductions', _deductions),
            if (_staffId > 0 && (_staffLoansBusy || _staffLoans.isNotEmpty)) ...[const SizedBox(height: 8), _advancesPanel()],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
              child: const Text('Save item'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _itemCard(Map i, bool editable) {
    final hint = _hints[tIntOrNull(i['waterPayrollItemId']) ?? 0];
    final count = tIntOrNull(hint?['activeLoanCount']) ?? 0;
    Widget kv(String k, Object? v) => Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$k ',
            style: const TextStyle(color: TColors.slate500),
          ),
          TextSpan(
            text: _f2(v),
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ],
      ),
      style: const TextStyle(fontSize: 13),
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: TColors.slate200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(tStr(i['staffName']).isEmpty ? '#${tStr(i['waterStaffId'])}' : tStr(i['staffName']), style: const TextStyle(fontWeight: FontWeight.w500)),
                    if (count > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0xFFF0F9FF), borderRadius: BorderRadius.circular(4)),
                        child: Text(count == 1 ? 'active advance' : '$count active advances', style: const TextStyle(fontSize: 10, color: TColors.sky700)),
                      ),
                  ],
                ),
              ),
              if (editable)
                IconButton(
                  tooltip: 'Remove',
                  onPressed: () => _remove(i),
                  icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: kv('Basic', i['basicPay'])),
              Expanded(child: kv('Daily', i['dailyWage'])),
            ],
          ),
          Row(
            children: [
              Expanded(child: kv('Commission', i['commission'])),
              Expanded(child: kv('Bonus', i['bonus'])),
            ],
          ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Deductions ', style: TextStyle(fontSize: 13, color: TColors.slate500)),
              InkWell(
                onTap: () => _breakdown(i),
                child: Text(
                  _f2(i['deductions']),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, decoration: TextDecoration.underline, decorationStyle: TextDecorationStyle.dotted),
                ),
              ),
              const SizedBox(width: 4),
              const Text('view breakdown', style: TextStyle(fontSize: 11, color: TColors.slate400)),
            ],
          ),
          const Divider(height: 10),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(
                  text: 'Net ',
                  style: TextStyle(color: TColors.slate500),
                ),
                TextSpan(
                  text: _f2(i['netPay']),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            style: const TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }

  /// What this person already owes, before the item is saved.
  Widget _advancesPanel() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFF0F9FF),
      border: Border.all(color: const Color(0xFFBAE6FD)),
      borderRadius: BorderRadius.circular(6),
    ),
    child: _staffLoansBusy
        ? const Text('Checking advances…', style: TextStyle(fontSize: 13, color: TColors.slate500))
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _staffLoans.length == 1 ? '1 active advance' : '${_staffLoans.length} active advances',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: TColors.sky900),
              ),
              const SizedBox(height: 6),
              for (final e in _staffLoans)
                Builder(
                  builder: (_) {
                    final m = tStr(e['repaymentMethod']);
                    final byPayroll = m == 'PayrollDeduction' || m == 'Mixed';
                    final will = payrollDeductionFor(e);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Wrap(
                        spacing: 12,
                        alignment: WrapAlignment.spaceBetween,
                        children: [
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: tStr(e['loanNumber'])),
                                TextSpan(
                                  text: ' · ${_f2(e['outstandingBalance'])} outstanding',
                                  style: const TextStyle(color: Color(0xB30369A1)),
                                ),
                              ],
                            ),
                            style: const TextStyle(fontSize: 13, color: TColors.sky900),
                          ),
                          will > 0
                              ? Text.rich(
                                  TextSpan(
                                    children: [
                                      const TextSpan(text: 'will deduct '),
                                      TextSpan(
                                        text: will.toStringAsFixed(2),
                                        style: const TextStyle(fontWeight: FontWeight.w700),
                                      ),
                                    ],
                                  ),
                                  style: const TextStyle(fontSize: 12, color: TColors.sky900),
                                )
                              : Text(byPayroll ? 'no amount set — add it by hand' : 'repaid by ${m.toLowerCase()} — not deducted here', style: const TextStyle(fontSize: 12, color: TColors.sky900)),
                        ],
                      ),
                    );
                  },
                ),
              const SizedBox(height: 6),
              const Text(
                'Added automatically when you save the item, and editable afterwards from the Deductions figure. Nothing is repaid until the payroll is approved.',
                style: TextStyle(fontSize: 11, color: Color(0xCC0369A1)),
              ),
            ],
          ),
  );
}

/// The audit lines (Created / Approved / Paid / Reopened / Re-approved).
List<Widget> waterPayrollHistory(Map r, Duration offset, {bool withCreated = true}) {
  const sm = TextStyle(fontSize: 13, color: TColors.slate600);
  Widget line(String who, String by, String tail, {String? quote}) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$who by '),
          TextSpan(
            text: by,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          TextSpan(text: tail),
          if (quote != null) ...[
            const TextSpan(text: ' — '),
            TextSpan(
              text: '"$quote"',
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ),
      style: sm,
    ),
  );
  String on(String key) => r[key] != null ? ' on ${fmtDateTime(r[key], r, offset)}' : '';
  return [
    if (withCreated && r['createdBy'] != null) line('Created', tStr(r['createdBy']), ' on ${fmtDateTime(r['createdAt'], r, offset)}'),
    if (r['approvedBy'] != null) line('Approved', tStr(r['approvedBy']), on('approvedAt')),
    if (r['paidBy'] != null) line('Paid', tStr(r['paidBy']), on('paidAt')),
    if (r['reopenedBy'] != null)
      line('Reopened', tStr(r['reopenedBy']), r['reopenedAt'] != null ? ' on ${_day(r['reopenedAt'])}' : '', quote: tStr(r['reopenReason']).isEmpty ? null : tStr(r['reopenReason'])),
    if (r['reapprovedBy'] != null) line('Re-approved', tStr(r['reapprovedBy']), on('reapprovedAt')),
  ];
}

// ------------------------------------------------------------------ details

/// `app/water-payroll/[id]/page.tsx`: header with actions, the totals, history,
/// the employee breakdown, year-to-date, and the linked expense.
class WaterPayrollDetailScreen extends StatefulWidget {
  const WaterPayrollDetailScreen({super.key, required this.session, required this.company, required this.runId});
  final Session session;
  final Company company;
  final int runId;
  @override
  State<WaterPayrollDetailScreen> createState() => _WaterPayrollDetailScreenState();
}

class _WaterPayrollDetailScreenState extends State<WaterPayrollDetailScreen> {
  Map? _data;
  bool _loading = true;
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;
  String get _q => 'farmId=${Uri.encodeQueryComponent(widget.company.farmId)}';
  String get _me => Uri.encodeQueryComponent(widget.session.tokens.userId ?? '');

  @override
  void initState() {
    super.initState();
    CompanyClock.load(widget.session, widget.company).then((c) {
      if (mounted) setState(() => _offset = c.offset);
    });
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await _api.get('/api/Water/payroll-runs/${widget.runId}/details', query: {'farmId': widget.company.farmId});
      if (mounted) setState(() => _data = r is Map ? r : null);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load payroll', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _do(Future<dynamic> Function() call, String ok, String fail) async {
    try {
      await call();
      if (mounted) trackerToast(context, ok);
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, fail, description: e.message, error: true);
    }
  }

  Future<void> _delete(Map run, String period) async {
    final ok = await confirmDelete(
      context,
      title: 'Delete payroll run?',
      description:
          '$period\n\nThis removes the payroll run and all its employee payroll lines. Only available while the run is Draft, Pending, or Reopened — and never while an approved expense is still linked.',
      confirmLabel: 'Delete',
    );
    if (!ok) return;
    try {
      await _api.delete('/api/Water/payroll-runs/${widget.runId}?$_q&deletedBy=$_me');
      if (mounted) {
        trackerToast(context, 'Payroll run removed');
        Navigator.pop(context);
      }
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Delete failed', description: e.message, error: true);
    }
  }

  Widget _tile(String label, String value, {Color? color}) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: TColors.slate200),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: color ?? TColors.slate900),
        ),
      ],
    ),
  );

  Widget _card(List<Widget> children) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: TColors.slate200),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
  );

  @override
  Widget build(BuildContext context) {
    final run = _data?['run'] is Map ? _data!['run'] as Map : null;
    final ytd = _data?['ytdTotals'] is Map ? _data!['ytdTotals'] as Map : null;
    final expense = _data?['linkedExpense'] is Map ? _data!['linkedExpense'] as Map : null;
    final byStaff = rowsOf(_data?['ytdByStaff']);
    const rose = TColors.rose700, emerald = TColors.emerald700;
    Widget kv(String k, String v) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$k: ',
              style: const TextStyle(color: TColors.slate500),
            ),
            TextSpan(
              text: v,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ],
        ),
        style: const TextStyle(fontSize: 13),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Payroll run')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back, size: 16), label: const Text('Payroll runs')),
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(padding: EdgeInsets.all(16), child: LoadingLine('Loading…'))
            else if (run == null)
              _card([const Text('Payroll run not found.', style: TextStyle(color: TColors.slate500))])
            else ...[
              Builder(
                builder: (_) {
                  final st = tStr(run['status']);
                  final period = '${_day(run['periodStart'])} → ${_day(run['periodEnd'])}';
                  final id = tStr(run['waterPayrollRunId']);
                  return _card([
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Icon(Icons.payments_outlined, color: Color(0xFF0284C7)),
                        Text(
                          'Payroll Run #$id',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: TColors.slate900),
                        ),
                        payrollBadge(st),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (waterPayrollEditable(st))
                          FilledButton.icon(
                            onPressed: () => _do(() => _api.post('/api/Water/payroll-runs/$id/approve?$_q&approvedBy=$_me'), st == 'Reopened' ? 'Run re-approved' : 'Run approved', 'Approve failed'),
                            icon: const Icon(Icons.check_circle_outline, size: 16),
                            label: Text(st == 'Reopened' ? 'Re-approve' : 'Approve'),
                          ),
                        if (st == 'Approved')
                          OutlinedButton(
                            onPressed: () => _do(() => _api.post('/api/Water/payroll-runs/$id/mark-paid?$_q&paidBy=$_me', body: {'payDate': null}), 'Marked paid', 'Mark paid failed'),
                            child: const Text('Mark paid'),
                          ),
                        if (st == 'Approved' || st == 'Paid')
                          OutlinedButton.icon(
                            onPressed: () => showWaterPayrollReopen(context, session: widget.session, company: widget.company, run: run, onDone: _load),
                            style: OutlinedButton.styleFrom(foregroundColor: TColors.amber700),
                            icon: const Icon(Icons.restart_alt, size: 16),
                            label: const Text('Reopen'),
                          ),
                        if (waterPayrollEditable(st))
                          OutlinedButton.icon(
                            onPressed: () => _delete(run, period),
                            style: OutlinedButton.styleFrom(foregroundColor: TColors.red600),
                            icon: const Icon(Icons.delete_outline, size: 16),
                            label: const Text('Delete'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    kv('Period', period),
                    kv('Pay date', run['payDate'] == null ? '—' : fmtDateTime(run['payDate'], run, _offset)),
                    kv('Cash account', tStr(run['cashAccountName']).isEmpty ? '—' : tStr(run['cashAccountName'])),
                    kv('Notes', tStr(run['notes']).isEmpty ? '—' : tStr(run['notes'])),
                    const SizedBox(height: 8),
                    twoUp([_tile('Gross', _f2(run['totalGrossPay'])), _tile('Deductions', _f2(run['totalDeductions']), color: rose), _tile('Net', _f2(run['totalNetPay']), color: emerald)]),
                  ]);
                },
              ),
              if (run['approvedBy'] != null || run['paidBy'] != null || run['reopenedBy'] != null || run['reapprovedBy'] != null || run['createdBy'] != null) ...[
                const SizedBox(height: 12),
                _card([
                  const Row(
                    children: [
                      Icon(Icons.description_outlined, size: 16, color: TColors.slate400),
                      SizedBox(width: 6),
                      Text('History', style: TextStyle(fontWeight: FontWeight.w500)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...waterPayrollHistory(run, _offset),
                ]),
              ],
              const SizedBox(height: 12),
              _card([
                const Text('Employee breakdown', style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                if (rowsOf(run['items']).isEmpty)
                  const Text('No payroll items for this run.', style: TextStyle(fontSize: 13, color: TColors.slate500))
                else
                  TrackerTable(
                    columns: const [
                      TCol('Staff', width: 140),
                      TCol('Basic', right: true),
                      TCol('Daily', right: true),
                      TCol('Commission', right: true),
                      TCol('Bonus', right: true),
                      TCol('Deductions', right: true),
                      TCol('Gross', right: true),
                      TCol('Net', right: true),
                    ],
                    rows: [
                      for (final i in rowsOf(run['items']))
                        [
                          cellText(tStr(i['staffName']).isEmpty ? 'Staff #${tStr(i['waterStaffId'])}' : tStr(i['staffName']), bold: true),
                          cellText(_f2(i['basicPay'])),
                          cellText(_f2(i['dailyWage'])),
                          cellText(_f2(i['commission'])),
                          cellText(_f2(i['bonus'])),
                          cellText(_f2(i['deductions']), color: rose),
                          cellText((tNum(i['basicPay']) + tNum(i['dailyWage']) + tNum(i['commission']) + tNum(i['bonus'])).toStringAsFixed(2)),
                          cellText(_f2(i['netPay']), bold: true, color: emerald),
                        ],
                    ],
                  ),
              ]),
              const SizedBox(height: 12),
              _card([
                Text('Year-to-date · ${ytd?['year'] ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                twoUp([
                  _tile('YTD Gross', _f2(ytd?['ytdGrossPaid'])),
                  _tile('YTD Deductions', _f2(ytd?['ytdDeductions']), color: rose),
                  _tile('YTD Net', _f2(ytd?['ytdNetPaid']), color: emerald),
                  _tile('Total runs', '${tIntOrNull(ytd?['totalPayrollRuns']) ?? 0}'),
                  _tile('Distinct staff', '${tIntOrNull(ytd?['totalStaffPaid']) ?? 0}'),
                ]),
                const SizedBox(height: 8),
                if (byStaff.isEmpty)
                  const Text('No approved/paid runs in this year yet.', style: TextStyle(fontSize: 13, color: TColors.slate500))
                else
                  TrackerTable(
                    columns: const [
                      TCol('Staff', width: 140),
                      TCol('YTD Basic', right: true),
                      TCol('YTD Daily', right: true),
                      TCol('YTD Commission', right: true, width: 130),
                      TCol('YTD Bonus', right: true),
                      TCol('YTD Deductions', right: true, width: 130),
                      TCol('YTD Gross', right: true),
                      TCol('YTD Net', right: true),
                    ],
                    rows: [
                      for (final s in byStaff)
                        [
                          cellText(tStr(s['staffName']).isEmpty ? 'Staff #${tStr(s['waterStaffId'])}' : tStr(s['staffName']), bold: true),
                          cellText(_f2(s['ytdBasic'])),
                          cellText(_f2(s['ytdDaily'])),
                          cellText(_f2(s['ytdCommission'])),
                          cellText(_f2(s['ytdBonus'])),
                          cellText(_f2(s['ytdDeductions']), color: rose),
                          cellText(_f2(s['ytdGross'])),
                          cellText(_f2(s['ytdNet']), bold: true, color: emerald),
                        ],
                    ],
                  ),
              ]),
              const SizedBox(height: 12),
              _card([
                const Row(
                  children: [
                    Icon(Icons.receipt_outlined, size: 16, color: TColors.slate400),
                    SizedBox(width: 6),
                    Text('Linked expense', style: TextStyle(fontWeight: FontWeight.w500)),
                  ],
                ),
                const SizedBox(height: 8),
                if (expense == null)
                  const Text(
                    'No linked expense yet. An expense is created automatically when this run is approved (migration 075) and reversed on Cancel/Unapprove.',
                    style: TextStyle(fontSize: 13, color: TColors.slate500),
                  )
                else ...[
                  kv('Category', tStr(expense['categoryName']).isEmpty ? '#${tStr(expense['waterExpenseCategoryId'])}' : tStr(expense['categoryName'])),
                  kv('Amount', _f2(expense['amount'])),
                  kv('Date', fmtDateTime(expense['expenseDate'], expense, _offset)),
                  kv('Status', tStr(expense['status']).isEmpty ? '—' : tStr(expense['status'])),
                  kv(
                    'Payment',
                    '${tStr(expense['paymentMethod']).isEmpty ? '—' : tStr(expense['paymentMethod'])} ${tStr(expense['cashAccountName']).isNotEmpty ? '· ${tStr(expense['cashAccountName'])}' : ''}',
                  ),
                  kv('Source', '${tStr(expense['sourceType'])} #${tStr(expense['sourceId'])}'),
                  kv('Description', tStr(expense['description']).isEmpty ? '—' : tStr(expense['description'])),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () => openAppHref(context, widget.session, widget.company, '/water-expenses', label: 'Expenses'),
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('Open in Expenses'),
                    ),
                  ),
                ],
              ]),
            ],
          ],
        ),
      ),
    );
  }
}
