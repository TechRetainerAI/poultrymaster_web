// Hotel → Sales, Expenses & Money → Expenses → Employee Loans & Advances, as
// `app/hotel-employee-loans/page.tsx` (migration 325). The four summary cards,
// the status tabs and the staff / type filters, the list with Details / Pay out /
// Record repayment / Cancel / Reverse, the New advance and Edit form, the loan's
// details with its repayments, Pay out, Record a repayment, and the reason
// prompts. `?staffId=` opens the page filtered to one staff member (the Staff
// page links here from its "Owes" column).
// API: /Hotel/employee-loans (+ /summary, /{id}, /disburse, /cancel, /reverse,
// /repayments), /Hotel/employee-loan-repayments (+ /{id}/reverse),
// /Hotel/staff, /Hotel/finance/cash-accounts.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../design/ui/form_dialog.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/money/money_widgets.dart' show MobileCardList, Highlight, Accent, twoUp;
import '../poultry/reports/report_format.dart' show FarmMoney;
import '../poultry/reports/report_routes.dart' show openAppHref;
import '../poultry/sales/balances_logic.dart' show pageSlice;
import '../poultry/sales/balances_widgets.dart' show CompactPager, LoadingLine;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/reason_select.dart' show cancelReasons, loanReversalReasons;
import '../water/water_payroll_screen.dart' show showWaterPayrollPrompt;
import 'hotel_kit.dart';

const hotelLoanTypes = {'SalaryAdvance': 'Salary advance', 'EmployeeLoan': 'Staff loan', 'OtherAdvance': 'Other advance'};
const hotelLoanMethods = {
  'PayrollDeduction': 'Deduct from payroll',
  'Mixed': 'Payroll and cash',
  'Cash': 'Cash',
  'MoMo': 'Mobile money',
  'Bank': 'Bank',
  'Other': 'Other',
};
const hotelLoanSources = {'Cash': 'Cash', 'MoMo': 'Mobile money', 'Bank': 'Bank', 'Other': 'Other'};
String hotelLoanMethodLabel(Object? v) => hotelLoanMethods[tStr(v)] ?? tStr(v);
String hotelLoanSourceLabel(Object? v) => v == 'Payroll' ? 'Payroll deduction' : hotelLoanSources[tStr(v)] ?? tStr(v);

const _tabs = [('OPEN', 'Open'), ('Active', 'Active'), ('Draft', 'Draft'), ('Paid', 'Paid'), ('CLOSED', 'Cancelled / reversed'), ('ALL', 'All')];

/// The status tab, staff, type and search filters.
List<Map> filterHotelLoans(List<Map> loans, {String tab = 'OPEN', String staff = 'ALL', String type = 'ALL', String search = ''}) {
  final q = search.trim().toLowerCase();
  return [
    for (final l in loans)
      if (switch (tab) {
            'OPEN' => l['status'] == 'Draft' || l['status'] == 'Active',
            'CLOSED' => ['Cancelled', 'Reversed', 'WrittenOff'].contains(l['status']),
            'ALL' => true,
            _ => l['status'] == tab,
          } &&
          (staff == 'ALL' || tStr(l['hotelStaffId']) == staff) &&
          (type == 'ALL' || l['loanType'] == type) &&
          (q.isEmpty || ['staffName', 'loanNumber', 'reference'].any((k) => tStr(l[k]).toLowerCase().contains(q))))
        l,
  ];
}

(Color, Color) _tone(Object? s) => switch (tStr(s)) {
      'Active' => (const Color(0xFFDBEAFE), const Color(0xFF1D4ED8)),
      'Paid' => (const Color(0xFFD1FAE5), const Color(0xFF047857)),
      'Cancelled' => (const Color(0xFFFEF3C7), const Color(0xFFB45309)),
      'Reversed' => (const Color(0xFFFEE2E2), const Color(0xFFB91C1C)),
      'WrittenOff' => (const Color(0xFFF3E8FF), const Color(0xFF7E22CE)),
      _ => (TColors.slate100, TColors.slate700),
    };
Widget _badge(Object? s) {
  final (bg, fg) = _tone(s);
  return hotelBadge(tStr(s), bg, fg);
}

Object? _v(Map m, String k) => m[k] ?? m[k.toLowerCase()];
int _staffId(Map s) => tIntOrNull(_v(s, 'hotelStaffId')) ?? 0;
String _staffName(Map s) => '${tStr(_v(s, 'firstName'))} ${tStr(_v(s, 'lastName'))}'.trim();
int _accId(Map a) => tIntOrNull(_v(a, 'hotelCashAccountId')) ?? 0;
String _accName(Map a) => tStr(_v(a, 'accountName'));
int _loanId(Map l) => tIntOrNull(l['hotelEmployeeLoanId']) ?? 0;
String _no(Map l) => tStr(l['loanNumber']).isEmpty ? '#${_loanId(l)}' : tStr(l['loanNumber']);
String _today() => hotelYmd(DateTime.now());
String _fmtDate(Object? s) {
  final d = hotelParseYmd(tStr(s));
  return d == null ? '—' : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

bool _owes(Map l) => l['status'] == 'Active' || l['status'] == 'Paid';

class HotelEmployeeLoansScreen extends StatefulWidget {
  const HotelEmployeeLoansScreen({super.key, required this.session, required this.company, this.staffId});
  final Session session;
  final Company company;
  final int? staffId;

  @override
  State<HotelEmployeeLoansScreen> createState() => _HotelEmployeeLoansScreenState();
}

class _HotelEmployeeLoansScreenState extends State<HotelEmployeeLoansScreen> {
  List<Map> _loans = [], _staff = [], _accounts = [];
  Map? _summary;
  bool _loading = true;
  String _tab = 'OPEN', _type = 'ALL';
  late String _staffFilter = widget.staffId == null ? 'ALL' : '${widget.staffId}';
  final _search = TextEditingController();
  int _page = 1, _pageSize = 10;
  FarmMoney _gh = const FarmMoney();

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  Map<String, dynamic> get _q => {'farmId': _farmId};
  String _fmt(Object? v) => _gh(tNum(v));
  List<Map> get _activeAccounts => [for (final a in _accounts) if (_v(a, 'isActive') != false) a];

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _gh = m);
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
      final r = await Future.wait([
        _api.get('/api/Hotel/employee-loans', query: _q),
        _api.get('/api/Hotel/employee-loans/summary', query: _q),
        _api.get('/api/Hotel/staff', query: _q),
        _api.get('/api/Hotel/finance/cash-accounts', query: _q),
      ]);
      if (!mounted) return;
      setState(() {
        _loans = hotelRows(r[0]);
        _summary = r[1] is Map ? r[1] as Map : null;
        _staff = hotelRows(r[2]);
        _accounts = hotelRows(r[3]);
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed to load loans', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Map? _fresh(int id) => _loans.where((l) => _loanId(l) == id).firstOrNull;

  int? _single() => _activeAccounts.length == 1 ? _accId(_activeAccounts.first) : null;

  Future<void> _form([Map? editing]) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _LoanFormDialog(
        api: _api,
        farmId: _farmId,
        editing: editing,
        staff: _staff,
        accounts: _activeAccounts,
        fmt: _fmt,
        preStaff: _staffFilter == 'ALL' ? 0 : int.parse(_staffFilter),
        preAccount: _single(),
      ),
    );
    if (done == true) await _load();
  }

  Future<bool> _disburse(Map l) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _DisburseDialog(api: _api, farmId: _farmId, loan: l, accounts: _activeAccounts, fmt: _fmt, preAccount: _single()),
    );
    if (done == true) await _load();
    return done == true;
  }

  Future<bool> _repay(Map l) async {
    final pre = tIntOrNull(l['hotelCashAccountId']) ?? _single();
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _RepayDialog(api: _api, farmId: _farmId, loan: l, accounts: _activeAccounts, fmt: _fmt, preAccount: pre),
    );
    if (done == true) await _load();
    return done == true;
  }

  Future<bool> _cancel(Map l) async {
    var ok = false;
    await showWaterPayrollPrompt(
      context,
      title: 'Cancel ${tStr(l['loanNumber']).isEmpty ? 'loan' : tStr(l['loanNumber'])}?',
      options: cancelReasons,
      description: 'The draft is closed. No money has moved, so nothing else changes.',
      label: 'Reason (optional)',
      placeholder: '',
      confirm: 'Cancel loan',
      allowEmpty: true,
      onSubmit: (reason) async {
        try {
          await _api.post('/api/Hotel/employee-loans/${_loanId(l)}/cancel', body: {'farmId': _farmId, 'reason': reason.isEmpty ? null : reason});
          if (mounted) trackerToast(context, 'Loan cancelled');
          await _load();
          return ok = true;
        } on ApiException catch (e) {
          if (mounted) trackerToast(context, 'Could not cancel', description: e.message, error: true);
          return false;
        }
      },
    );
    return ok;
  }

  Future<bool> _reverse(Map l) async {
    var ok = false;
    await showWaterPayrollPrompt(
      context,
      title: 'Reverse ${tStr(l['loanNumber']).isEmpty ? 'loan' : tStr(l['loanNumber'])}?',
      options: loanReversalReasons,
      description:
          'Use this when the loan was a mistake. ${_fmt(l['principalAmount'])} goes back into ${tStr(l['cashAccountName']).isEmpty ? 'the account it came from' : tStr(l['cashAccountName'])}. Any repayments must be reversed first.',
      label: 'Reason',
      placeholder: '',
      confirm: 'Reverse loan',
      onSubmit: (reason) async {
        try {
          await _api.post('/api/Hotel/employee-loans/${_loanId(l)}/reverse', body: {'farmId': _farmId, 'reason': reason});
          if (mounted) trackerToast(context, 'Loan reversed');
          await _load();
          return ok = true;
        } on ApiException catch (e) {
          if (mounted) trackerToast(context, 'Could not reverse', description: e.message, error: true);
          return false;
        }
      },
    );
    return ok;
  }

  Future<void> _detail(Map loan) => showDialog<void>(
        context: context,
        builder: (_) => _DetailDialog(
          api: _api,
          farmId: _farmId,
          loan: loan,
          fmt: _fmt,
          fresh: _fresh,
          onDisburse: _disburse,
          onEdit: (l) async {
            await _form(l);
            return true;
          },
          onCancel: _cancel,
          onRepay: _repay,
          onReverse: _reverse,
          onChanged: _load,
        ),
      );

  /// Staff who have a loan; one since removed shows by the name on the loan.
  List<(String, String)> get _staffWithLoans {
    final ids = {for (final l in _loans) tStr(l['hotelStaffId'])};
    final m = <String, String>{
      for (final s in _staff)
        if (ids.contains('${_staffId(s)}')) '${_staffId(s)}': _staffName(s),
    };
    for (final l in _loans) {
      m.putIfAbsent(tStr(l['hotelStaffId']), () => tStr(l['staffName']).isEmpty ? 'Staff #${tStr(l['hotelStaffId'])}' : tStr(l['staffName']));
    }
    return m.entries.map((e) => (e.key, e.value)).toList()..sort((a, b) => a.$2.compareTo(b.$2));
  }

  List<Widget> _actions(Map l) {
    final st = tStr(l['status']);
    Widget out(String label, IconData icon, VoidCallback on) =>
        OutlinedButton.icon(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)), onPressed: on, icon: Icon(icon, size: 16), label: Text(label));
    Widget ghost(String label, IconData icon, VoidCallback on) => TextButton.icon(onPressed: on, icon: Icon(icon, size: 16), label: Text(label));
    return [
      out('Details', Icons.visibility_outlined, () => _detail(l)),
      if (st == 'Draft') out('Pay out', Icons.volunteer_activism_outlined, () => _disburse(l)),
      if (st == 'Active') out('Record repayment', Icons.account_balance_wallet_outlined, () => _repay(l)),
      if (st == 'Draft') ghost('Cancel', Icons.cancel_outlined, () => _cancel(l)),
      if (st == 'Active') ghost('Reverse', Icons.undo, () => _reverse(l)),
    ];
  }

  Widget _stat(String label, String value, {String? hint, Color color = TColors.slate900}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, letterSpacing: .5, color: TColors.slate500)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, maxLines: 1, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: color)),
          ),
          if (hint != null) Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: TColors.slate500)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/hotel-employee-loans');
    final filtered = filterHotelLoans(_loans, tab: _tab, staff: _staffFilter, type: _type, search: _search.text);
    if ((_page - 1) * _pageSize >= filtered.length && _page > 1) _page = 1;
    final owed = filtered.where((l) => l['status'] == 'Active').fold<num>(0, (s, l) => s + tNum(l['outstandingBalance']));
    final s = _summary;
    final staffOptions = _staffWithLoans;

    return Scaffold(
      backgroundColor: TColors.slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Employee Loans & Advances')),
      body: _loading && _loans.isEmpty
          ? const Center(child: CircularProgressIndicator(color: hotelViolet))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
                const HotelPageHeader(
                  icon: Icons.volunteer_activism_outlined,
                  title: 'Employee Loans & Advances',
                  description: 'Money lent to staff, and how it is being paid back',
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                      onPressed: () => openAppHref(context, widget.session, widget.company, '/hotel-payroll', label: 'Payroll'),
                      icon: const Icon(Icons.payments_outlined, size: 16),
                      label: const Text('Payroll'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: hotelAddButton('New advance', () => _form())),
                ]),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: TColors.violet50, border: Border.all(color: TColors.violet200), borderRadius: BorderRadius.circular(8)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.info_outline, size: 16, color: Color(0xFF4C1D95)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text.rich(
                        TextSpan(children: [
                          const TextSpan(text: 'An advance is '),
                          const TextSpan(text: 'not an expense', style: TextStyle(fontWeight: FontWeight.w700)),
                          const TextSpan(
                              text:
                                  ' — the staff member owes it back. Paying it out takes the amount from a cash account; cash repayments put it back. Deductions set on a payroll line are repaid when that payroll run is '),
                          const TextSpan(text: 'approved', style: TextStyle(fontWeight: FontWeight.w700)),
                          const TextSpan(text: ', and the P&L still shows the full wage. This is separate from '),
                          WidgetSpan(
                            alignment: PlaceholderAlignment.baseline,
                            baseline: TextBaseline.alphabetic,
                            child: InkWell(
                              onTap: () => openAppHref(context, widget.session, widget.company, '/hotel-loans', label: 'Loans (Financing)'),
                              child: const Text('Loans (Financing)',
                                  style: TextStyle(fontSize: 13, color: Color(0xFF4C1D95), decoration: TextDecoration.underline)),
                            ),
                          ),
                          const TextSpan(text: ', which is money the hotel borrowed.'),
                        ]),
                        style: const TextStyle(fontSize: 13, color: Color(0xFF4C1D95)),
                      ),
                    ),
                  ]),
                ),
                if (s != null) ...[
                  const SizedBox(height: 12),
                  twoUp([
                    _stat('Outstanding', _fmt(s['totalOutstanding']), hint: 'What staff still owe the hotel', color: const Color(0xFF4338CA)),
                    _stat('Advanced', _fmt(s['totalDisbursed']), hint: tNum(s['draftCount']) > 0 ? '${tStr(s['draftCount'])} draft' : null, color: const Color(0xFFE11D48)),
                    _stat('Repaid', _fmt(s['totalRepaid']), hint: '${_fmt(s['repaidViaPayroll'])} via payroll', color: const Color(0xFF047857)),
                    _stat('Active advances', '${tNum(s['activeCount']).toInt()}', hint: '${tNum(s['staffWithLoans']).toInt()} member(s) of staff'),
                  ]),
                  if (tNum(s['draftPayrollClaims']) > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('${_fmt(s['draftPayrollClaims'])} is set aside on draft payroll runs and is repaid when they are approved.',
                          style: const TextStyle(fontSize: 12, color: TColors.amber700)),
                    ),
                ],
                const SizedBox(height: 12),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final (v, label) in _tabs)
                    _tab == v
                        ? FilledButton(
                            style: hotelPrimary.copyWith(minimumSize: const WidgetStatePropertyAll(Size(0, 36))),
                            onPressed: () => setState(() => _tab = v),
                            child: Text(label),
                          )
                        : OutlinedButton(
                            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36)),
                            onPressed: () => setState(() {
                              _tab = v;
                              _page = 1;
                            }),
                            child: Text(label),
                          ),
                ]),
                const SizedBox(height: 10),
                AppInput(
                  controller: _search,
                  hintText: 'Search staff, loan no., reference…',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  onChanged: (_) => setState(() => _page = 1),
                ),
                const SizedBox(height: 8),
                AppSelect<String>(
                  value: _staffFilter,
                  hintText: 'All staff',
                  items: [
                    const AppSelectItem(value: 'ALL', label: 'All staff'),
                    if (_staffFilter != 'ALL' && !staffOptions.any((o) => o.$1 == _staffFilter)) AppSelectItem(value: _staffFilter, label: 'Staff #$_staffFilter'),
                    for (final (id, name) in staffOptions) AppSelectItem(value: id, label: name),
                  ],
                  onChanged: (v) => setState(() {
                    _staffFilter = v ?? 'ALL';
                    _page = 1;
                  }),
                ),
                const SizedBox(height: 8),
                AppSelect<String>(
                  value: _type,
                  items: [
                    const AppSelectItem(value: 'ALL', label: 'All types'),
                    for (final e in hotelLoanTypes.entries) AppSelectItem(value: e.key, label: e.value),
                  ],
                  onChanged: (v) => setState(() {
                    _type = v ?? 'ALL';
                    _page = 1;
                  }),
                ),
                if (filtered.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('${filtered.length} loan(s)${owed > 0 ? ' · ${_fmt(owed)} still owed' : ''}', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                  ),
                const SizedBox(height: 12),
                if (filtered.isEmpty)
                  TCard(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
                      child: Column(children: [
                        const Icon(Icons.volunteer_activism_outlined, size: 44, color: TColors.slate400),
                        const SizedBox(height: 12),
                        Text(_loans.isEmpty ? 'No staff loans or advances yet' : 'Nothing matches these filters',
                            textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: TColors.slate900)),
                        const SizedBox(height: 6),
                        const Text('Give a staff member an advance and set how much comes off each payroll.',
                            textAlign: TextAlign.center, style: TextStyle(color: TColors.slate600)),
                        const SizedBox(height: 14),
                        hotelAddButton('New advance', () => _form()),
                      ]),
                    ),
                  )
                else
                  MobileCardList<Map>(
                    striped: true,
                    items: pageSlice(filtered, _page, _pageSize),
                    keyOf: (l) => '${_loanId(l)}',
                    primary: (l) => '${_no(l)} · ${tStr(l['staffName']).isEmpty ? '—' : tStr(l['staffName'])}',
                    secondary: (l) => '${_fmtDate(l['disbursementDate'] ?? l['createdAt'])} · ${hotelLoanTypes[tStr(l['loanType'])] ?? tStr(l['loanType'])}',
                    trailing: (l) => _badge(l['status']),
                    highlights: (l) => [
                      Highlight('Outstanding', _fmt(_owes(l) ? l['outstandingBalance'] : 0), accent: Accent.blue, wide: true),
                      Highlight('Advanced', _fmt(l['principalAmount']), accent: Accent.rose),
                      Highlight('Repaid', _fmt(tNum(l['totalPrincipalRepaid']) + tNum(l['totalInterestRepaid'])), accent: Accent.emerald),
                    ],
                    details: (l) => [
                      ('Total repayable', _fmt(l['totalRepayable'])),
                      ('Repayment', hotelLoanMethodLabel(l['repaymentMethod'])),
                      ('Suggested per payroll', tNum(l['defaultPayrollDeduction']) != 0 ? _fmt(l['defaultPayrollDeduction']) : '—'),
                      ('Reference', tStr(l['reference']).isEmpty ? '—' : tStr(l['reference'])),
                      ('Purpose', tStr(l['notes']).isEmpty ? '—' : tStr(l['notes'])),
                      if (tNum(l['draftPayrollClaims']) > 0) ('On draft payroll', _fmt(l['draftPayrollClaims'])),
                    ],
                    actions: _actions,
                    table: (items) => TrackerTable(
                      columns: const [
                        TCol('Loan', width: 120),
                        TCol('Staff', width: 140),
                        TCol('Type', width: 120),
                        TCol('Given', right: true, width: 110),
                        TCol('To repay', right: true, width: 130),
                        TCol('Owed', right: true, width: 130),
                        TCol('Repayment', width: 150),
                        TCol('Status', width: 100),
                        TCol('Actions', right: true, width: 130),
                      ],
                      rows: [
                        for (final l in items)
                          [
                            InkWell(
                              onTap: () => _detail(l),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                                Text(_no(l), style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w600)),
                                Text(_fmtDate(l['disbursementDate'] ?? l['createdAt']), style: const TextStyle(fontSize: 11, color: TColors.slate500)),
                              ]),
                            ),
                            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                              Text(tStr(l['staffName']).isEmpty ? '—' : tStr(l['staffName']), style: const TextStyle(fontWeight: FontWeight.w500)),
                              if (l['staffIsActive'] == false) const Text('inactive', style: TextStyle(fontSize: 11, color: TColors.amber600)),
                            ]),
                            cellText(hotelLoanTypes[tStr(l['loanType'])] ?? tStr(l['loanType'])),
                            cellText(_fmt(l['principalAmount'])),
                            Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                              Text(_fmt(l['totalRepayable'])),
                              if (tNum(l['interestAmount']) > 0)
                                Text('incl. ${_fmt(l['interestAmount'])} interest', style: const TextStyle(fontSize: 11, color: TColors.slate500)),
                            ]),
                            Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                              Text(_owes(l) ? _fmt(l['outstandingBalance']) : '—',
                                  style: l['status'] == 'Active' && tNum(l['outstandingBalance']) > 0
                                      ? const TextStyle(color: TColors.red600, fontWeight: FontWeight.w600)
                                      : const TextStyle(color: TColors.slate500)),
                              if (tNum(l['draftPayrollClaims']) > 0)
                                Text('${_fmt(l['draftPayrollClaims'])} on draft payroll', style: const TextStyle(fontSize: 11, color: TColors.amber600)),
                            ]),
                            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                              Text(hotelLoanMethodLabel(l['repaymentMethod']), style: const TextStyle(fontSize: 12)),
                              if (tNum(l['defaultPayrollDeduction']) > 0)
                                Text('${_fmt(l['defaultPayrollDeduction'])} per payroll', style: const TextStyle(fontSize: 11, color: TColors.slate500)),
                            ]),
                            Align(alignment: Alignment.centerLeft, child: _badge(l['status'])),
                            Align(
                              alignment: Alignment.centerRight,
                              child: l['status'] == 'Draft'
                                  ? OutlinedButton(onPressed: () => _disburse(l), child: const Text('Pay out'))
                                  : l['status'] == 'Active'
                                      ? OutlinedButton(onPressed: () => _repay(l), child: const Text('Repay'))
                                      : const SizedBox.shrink(),
                            ),
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

// ------------------------------------------------------------------ dialogs

Widget _money(TextEditingController c, VoidCallback changed, {bool enabled = true}) => AppInput(
      controller: c,
      enabled: enabled,
      hintText: '0.00',
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
      onChanged: (_) => changed(),
    );

Widget _date(String value, ValueChanged<String> on) => AppDateField(
      value: hotelParseYmd(value),
      hintText: 'dd/mm/yyyy',
      onChanged: (d) => on(d == null ? '' : hotelYmd(d)),
    );

AppSelect<int> _accountSelect(List<Map> accounts, int? value, ValueChanged<int?> on, String Function(Object?) fmt, {bool balance = true}) => AppSelect<int>(
      value: value,
      hintText: 'Choose cash account',
      items: [
        for (final a in accounts) AppSelectItem(value: _accId(a), label: balance ? '${_accName(a)} (${fmt(_v(a, 'currentBalance'))})' : _accName(a)),
      ],
      onChanged: on,
    );

String _plain(num v) => v == 0 ? '' : (v == v.roundToDouble() ? v.toInt().toString() : '$v');

/// New loan or advance / Edit.
class _LoanFormDialog extends StatefulWidget {
  const _LoanFormDialog({
    required this.api,
    required this.farmId,
    required this.editing,
    required this.staff,
    required this.accounts,
    required this.fmt,
    required this.preStaff,
    required this.preAccount,
  });
  final ApiClient api;
  final String farmId;
  final Map? editing;
  final List<Map> staff, accounts;
  final String Function(Object?) fmt;
  final int preStaff;
  final int? preAccount;

  @override
  State<_LoanFormDialog> createState() => _LoanFormDialogState();
}

class _LoanFormDialogState extends State<_LoanFormDialog> {
  late final Map? e = widget.editing;
  late int _staffId = e == null ? widget.preStaff : tIntOrNull(e!['hotelStaffId']) ?? 0;
  late String _type = e == null ? 'SalaryAdvance' : tStr(e!['loanType']);
  late String _method = e == null ? 'PayrollDeduction' : tStr(e!['repaymentMethod']);
  late final _principal = TextEditingController(text: e == null ? '' : _plain(tNum(e!['principalAmount'])));
  late final _interest = TextEditingController(text: e == null ? '' : _plain(tNum(e!['interestAmount'])));
  late final _perPayroll = TextEditingController(text: e == null ? '' : _plain(tNum(e!['defaultPayrollDeduction'])));
  late final _reference = TextEditingController(text: tStr(e?['reference']));
  late final _notes = TextEditingController(text: tStr(e?['notes']));
  late String _end = e == null ? '' : tStr(e!['expectedEndDate']).length >= 10 ? tStr(e!['expectedEndDate']).substring(0, 10) : '';
  bool _disburseNow = true;
  late int? _account = widget.preAccount;
  String _paidOn = _today();
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_principal, _interest, _perPayroll, _reference, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  num get _p => num.tryParse(_principal.text) ?? 0;
  num get _i => num.tryParse(_interest.text) ?? 0;
  num get _per => num.tryParse(_perPayroll.text) ?? 0;
  bool get _byPayroll => _method == 'PayrollDeduction' || _method == 'Mixed';
  bool get _moneyLocked => e != null && e!['status'] != 'Draft';
  String? _opt(TextEditingController c) => c.text.isEmpty ? null : c.text;

  Future<void> _save() async {
    if (e == null && _staffId == 0) return trackerToast(context, 'Choose the staff member', error: true);
    if (_p <= 0) return trackerToast(context, 'Enter the amount given', error: true);
    if (_byPayroll && _per <= 0) return trackerToast(context, 'Set how much to deduct from each payroll', error: true);
    if (e == null && _disburseNow && _account == null) return trackerToast(context, 'Choose the cash account the money is paid from', error: true);
    setState(() => _saving = true);
    try {
      if (e != null) {
        await widget.api.put('/api/Hotel/employee-loans/${_loanId(e!)}', body: {
          'farmId': widget.farmId,
          'loanType': _type,
          'principalAmount': _p,
          'interestAmount': _i,
          'repaymentMethod': _method,
          'defaultPayrollDeduction': _per,
          'expectedEndDate': _end.isEmpty ? null : _end,
          'reference': _opt(_reference),
          'notes': _opt(_notes),
        });
        if (mounted) trackerToast(context, 'Loan updated');
      } else {
        final s = widget.staff.where((x) => _staffId == _staffId0(x)).firstOrNull;
        await widget.api.post('/api/Hotel/employee-loans', body: {
          'farmId': widget.farmId,
          'hotelStaffId': _staffId,
          'staffName': s == null ? null : _staffName(s),
          'loanType': _type,
          'principalAmount': _p,
          'interestAmount': _i,
          'repaymentMethod': _method,
          'defaultPayrollDeduction': _per,
          'expectedEndDate': _end.isEmpty ? null : _end,
          'reference': _opt(_reference),
          'notes': _opt(_notes),
          'disburseNow': _disburseNow,
          'hotelCashAccountId': _disburseNow ? _account : null,
          'disbursementDate': _disburseNow ? _paidOn : null,
        });
        if (mounted) {
          trackerToast(context, _disburseNow ? 'Advance given and paid out' : 'Loan saved as a draft — disburse it when the money is handed over');
        }
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (x) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Could not save', description: x.message, error: true);
    }
  }

  static int _staffId0(Map s) => tIntOrNull(_v(s, 'hotelStaffId')) ?? 0;

  @override
  Widget build(BuildContext context) {
    final total = _p + _i;
    final runs = _byPayroll && _per > 0 ? (total / _per).ceil() : 0;
    final staff = e != null ? widget.staff : [for (final s in widget.staff) if (_v(s, 'isActive') != false) s];
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: FormDialogTitle(icon: Icons.volunteer_activism_outlined, color: FormColor.purple, text: e != null ? 'Edit ${tStr(e!['loanNumber']).isEmpty ? 'loan' : tStr(e!['loanNumber'])}' : 'New loan or advance'),
        content: SizedBox(
          width: 560,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              e != null
                  ? _moneyLocked
                      ? 'Money has already moved, so only the repayment plan and notes can change.'
                      : 'This loan is still a draft; anything can change.'
                  : 'Who is borrowing, how much, and how they will pay it back.',
              style: const TextStyle(fontSize: 13, color: TColors.slate500),
            ),
            const SizedBox(height: 12),
            TintedSection(title: 'Staff and amount', color: FormColor.purple, children: [
              FilterLabel(
                'Staff member *',
                AppSelect<int>(
                  value: _staffId == 0 ? null : _staffId,
                  hintText: 'Choose staff',
                  enabled: e == null,
                  items: [
                    for (final s in staff)
                      AppSelectItem(value: _staffId0(s), label: '${_staffName(s)}${tStr(_v(s, 'role')).isNotEmpty ? ' — ${tStr(_v(s, 'role'))}' : ''}'),
                  ],
                  onChanged: (v) => setState(() => _staffId = v ?? 0),
                ),
              ),
              FilterLabel(
                'Type',
                AppSelect<String>(
                  value: _type,
                  enabled: !_moneyLocked,
                  items: [for (final t in hotelLoanTypes.entries) AppSelectItem(value: t.key, label: t.value)],
                  onChanged: (v) => setState(() => _type = v ?? _type),
                ),
              ),
              FilterLabel('Amount given *', _money(_principal, () => setState(() {}), enabled: !_moneyLocked)),
              FilterLabel('Interest (flat amount)', _money(_interest, () => setState(() {}), enabled: !_moneyLocked)),
            ]),
            const SizedBox(height: 8),
            Text.rich(TextSpan(children: [
              const TextSpan(text: 'Total to repay: '),
              TextSpan(text: widget.fmt(total), style: const TextStyle(fontWeight: FontWeight.w700)),
            ]), style: const TextStyle(fontSize: 13, color: TColors.slate600)),
            const SizedBox(height: 12),
            TintedSection(title: 'How it is paid back', color: FormColor.blue, children: [
              FilterLabel(
                'Repayment method',
                AppSelect<String>(
                  value: _method,
                  items: [for (final m in hotelLoanMethods.entries) AppSelectItem(value: m.key, label: m.value)],
                  onChanged: (v) => setState(() => _method = v ?? _method),
                ),
              ),
              FilterLabel(_byPayroll ? 'Deduct per payroll *' : 'Deduct per payroll', _money(_perPayroll, () => setState(() {}))),
              FilterLabel('Expected to finish', _date(_end, (v) => setState(() => _end = v))),
              FilterLabel('Reference', AppInput(controller: _reference, hintText: 'Voucher / note no.')),
            ]),
            if (runs > 0) ...[
              const SizedBox(height: 8),
              Text(
                'At ${widget.fmt(_per)} per payroll this is cleared in about $runs payroll run${runs == 1 ? '' : 's'}. Payroll will suggest this deduction for the staff member automatically.',
                style: const TextStyle(fontSize: 12, color: TColors.slate500),
              ),
            ],
            const SizedBox(height: 12),
            FilterLabel('Notes', AppInput(controller: _notes, minLines: 2, maxLines: 4)),
            if (e == null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  InkWell(
                    onTap: () => setState(() => _disburseNow = !_disburseNow),
                    child: Row(children: [
                      Checkbox(value: _disburseNow, activeColor: hotelViolet, onChanged: (v) => setState(() => _disburseNow = v ?? false)),
                      const Expanded(child: Text('Pay the money out now', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
                    ]),
                  ),
                  const SizedBox(height: 8),
                  if (_disburseNow) ...[
                    FilterLabel('Paid from *', _accountSelect(widget.accounts, _account, (v) => setState(() => _account = v), widget.fmt)),
                    const SizedBox(height: 10),
                    FilterLabel('Date paid', _date(_paidOn, (v) => setState(() => _paidOn = v))),
                  ] else
                    const Text('Saved as a draft. Nothing moves until you pay it out.', style: TextStyle(fontSize: 12, color: TColors.slate500)),
                ]),
              ),
            ],
          ]),
        ),
        actions: [
          FormDialogFooter(
            onCancel: () => Navigator.pop(context, false),
            cancelDisabled: _saving,
            children: [
              FilledButton(
                style: hotelPrimary,
                onPressed: _saving ? null : _save,
                child: Text(e != null
                    ? 'Save changes'
                    : _disburseNow
                        ? 'Give ${widget.fmt(_p)}'
                        : 'Save draft'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Pay out a draft.
class _DisburseDialog extends StatefulWidget {
  const _DisburseDialog({required this.api, required this.farmId, required this.loan, required this.accounts, required this.fmt, required this.preAccount});
  final ApiClient api;
  final String farmId;
  final Map loan;
  final List<Map> accounts;
  final String Function(Object?) fmt;
  final int? preAccount;

  @override
  State<_DisburseDialog> createState() => _DisburseDialogState();
}

class _DisburseDialogState extends State<_DisburseDialog> {
  late int? _account = widget.preAccount;
  String _date0 = _today();
  late final _reference = TextEditingController(text: tStr(widget.loan['reference']));
  bool _saving = false;

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_account == null) return trackerToast(context, 'Choose the cash account the money is paid from', error: true);
    setState(() => _saving = true);
    try {
      await widget.api.post('/api/Hotel/employee-loans/${_loanId(widget.loan)}/disburse', body: {
        'farmId': widget.farmId,
        'hotelCashAccountId': _account,
        'disbursementDate': _date0,
        'reference': _reference.text.isEmpty ? null : _reference.text,
      });
      if (!mounted) return;
      trackerToast(context,
          '${widget.fmt(widget.loan['principalAmount'])} paid out to ${tStr(widget.loan['staffName']).isEmpty ? 'staff' : tStr(widget.loan['staffName'])}');
      Navigator.pop(context, true);
    } on ApiException catch (x) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Could not disburse', description: x.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.loan;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: FormDialogTitle(icon: Icons.volunteer_activism_outlined, color: FormColor.purple, text: 'Pay out ${tStr(l['loanNumber'])}'),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${widget.fmt(l['principalAmount'])} to ${tStr(l['staffName'])}. The amount leaves the cash account you choose; the loan becomes active.',
                style: const TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 12),
            FilterLabel('Paid from *', _accountSelect(widget.accounts, _account, (v) => setState(() => _account = v), widget.fmt)),
            const SizedBox(height: 10),
            FilterLabel('Date paid', _date(_date0, (v) => setState(() => _date0 = v))),
            const SizedBox(height: 10),
            FilterLabel('Reference', AppInput(controller: _reference)),
          ]),
        ),
        actions: [
          Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
            OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Back')),
            FilledButton(style: hotelPrimary, onPressed: _saving ? null : _save, child: const Text('Pay out')),
          ]),
        ],
      ),
    );
  }
}

/// Record a repayment (cash, MoMo, bank).
class _RepayDialog extends StatefulWidget {
  const _RepayDialog({required this.api, required this.farmId, required this.loan, required this.accounts, required this.fmt, required this.preAccount});
  final ApiClient api;
  final String farmId;
  final Map loan;
  final List<Map> accounts;
  final String Function(Object?) fmt;
  final int? preAccount;

  @override
  State<_RepayDialog> createState() => _RepayDialogState();
}

class _RepayDialogState extends State<_RepayDialog> {
  final _amount = TextEditingController(), _reference = TextEditingController(), _notes = TextEditingController();
  String _source = 'Cash', _date0 = _today();
  late int? _account = widget.preAccount;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_amount, _reference, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final amount = num.tryParse(_amount.text) ?? 0;
    final owed = tNum(widget.loan['outstandingBalance']);
    if (amount <= 0) return trackerToast(context, 'Enter the amount repaid', error: true);
    if (amount > owed) return trackerToast(context, 'That is more than the ${widget.fmt(owed)} still owed', error: true);
    if (_account == null) return trackerToast(context, 'Choose the account the money went into', error: true);
    setState(() => _saving = true);
    try {
      await widget.api.post('/api/Hotel/employee-loan-repayments', body: {
        'farmId': widget.farmId,
        'hotelEmployeeLoanId': _loanId(widget.loan),
        'amount': amount,
        'sourceType': _source,
        'hotelCashAccountId': _account,
        'repaymentDate': _date0,
        'reference': _reference.text.isEmpty ? null : _reference.text,
        'notes': _notes.text.isEmpty ? null : _notes.text,
      });
      if (!mounted) return;
      trackerToast(context, 'Repayment recorded');
      Navigator.pop(context, true);
    } on ApiException catch (x) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Could not record repayment', description: x.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.loan;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: const FormDialogTitle(icon: Icons.account_balance_wallet_outlined, color: FormColor.purple, text: 'Record a repayment'),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              '${tStr(l['staffName'])} · ${tStr(l['loanNumber'])} · owes ${widget.fmt(l['outstandingBalance'])}. For money handed back directly. Payroll deductions are set on the payroll run instead.',
              style: const TextStyle(fontSize: 13, color: TColors.slate500),
            ),
            const SizedBox(height: 12),
            FilterLabel(
              'Amount *',
              Row(children: [
                Expanded(child: _money(_amount, () => setState(() {}))),
                const SizedBox(width: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: () => setState(() => _amount.text = _plain(tNum(l['outstandingBalance']))),
                  child: const Text('All'),
                ),
              ]),
            ),
            const SizedBox(height: 10),
            FilterLabel(
              'Paid by',
              AppSelect<String>(
                value: _source,
                items: [for (final s in hotelLoanSources.entries) AppSelectItem(value: s.key, label: s.value)],
                onChanged: (v) => setState(() => _source = v ?? 'Cash'),
              ),
            ),
            const SizedBox(height: 10),
            FilterLabel('Paid into *', _accountSelect(widget.accounts, _account, (v) => setState(() => _account = v), widget.fmt, balance: false)),
            const SizedBox(height: 10),
            FilterLabel('Date', _date(_date0, (v) => setState(() => _date0 = v))),
            const SizedBox(height: 10),
            FilterLabel('Reference', AppInput(controller: _reference)),
            const SizedBox(height: 10),
            FilterLabel('Notes', AppInput(controller: _notes, minLines: 2, maxLines: 4)),
          ]),
        ),
        actions: [
          Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
            OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Back')),
            FilledButton(style: hotelPrimary, onPressed: _saving ? null : _save, child: const Text('Record')),
          ]),
        ],
      ),
    );
  }
}

/// The loan's details: figures, plan, actions and its repayments.
class _DetailDialog extends StatefulWidget {
  const _DetailDialog({
    required this.api,
    required this.farmId,
    required this.loan,
    required this.fmt,
    required this.fresh,
    required this.onDisburse,
    required this.onEdit,
    required this.onCancel,
    required this.onRepay,
    required this.onReverse,
    required this.onChanged,
  });
  final ApiClient api;
  final String farmId;
  final Map loan;
  final String Function(Object?) fmt;
  final Map? Function(int id) fresh;
  final Future<bool> Function(Map) onDisburse, onEdit, onCancel, onRepay, onReverse;
  final Future<void> Function() onChanged;

  @override
  State<_DetailDialog> createState() => _DetailDialogState();
}

class _DetailDialogState extends State<_DetailDialog> {
  late Map _l = widget.loan;
  List<Map> _reps = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadReps();
  }

  Future<void> _loadReps() async {
    setState(() => _loading = true);
    try {
      final r = hotelRows(await widget.api.get('/api/Hotel/employee-loans/${_loanId(_l)}/repayments', query: {'farmId': widget.farmId}));
      if (mounted) setState(() => _reps = r);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed to load repayments', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  /// After an action: the list was reloaded; read this loan from it again.
  Future<void> _after(Future<bool> Function(Map) action) async {
    if (!await action(_l) || !mounted) return;
    final f = widget.fresh(_loanId(_l));
    if (f == null) return Navigator.pop(context);
    setState(() => _l = f);
    await _loadReps();
  }

  Future<void> _reverseRep(Map rp) => showWaterPayrollPrompt(
        context,
        title: 'Reverse this repayment?',
        options: loanReversalReasons,
        description:
            '${widget.fmt(rp['amount'])} goes back out of ${tStr(rp['cashAccountName']).isEmpty ? 'its cash account' : tStr(rp['cashAccountName'])} and is owed again.',
        label: 'Reason',
        placeholder: '',
        confirm: 'Reverse repayment',
        onSubmit: (reason) async {
          try {
            await widget.api.post('/api/Hotel/employee-loan-repayments/${tStr(rp['hotelEmployeeLoanRepaymentId'])}/reverse',
                body: {'farmId': widget.farmId, 'reason': reason});
            if (mounted) trackerToast(context, 'Repayment reversed');
            await widget.onChanged();
            final f = widget.fresh(_loanId(_l));
            if (mounted && f != null) setState(() => _l = f);
            await _loadReps();
            return true;
          } on ApiException catch (e) {
            if (mounted) trackerToast(context, 'Could not reverse', description: e.message, error: true);
            return false;
          }
        },
      );

  @override
  Widget build(BuildContext context) {
    final l = _l, fmt = widget.fmt, st = tStr(l['status']);
    Widget fig(String label, String value, [Color? tone]) => Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 11, color: TColors.slate500)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: tone)),
            ),
          ]),
        );
    Widget line(String label, String value, {Color? color}) => Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Text.rich(TextSpan(children: [
            TextSpan(text: '$label: ', style: const TextStyle(color: TColors.slate500)),
            TextSpan(text: value),
          ]), style: TextStyle(fontSize: 13, color: color)),
        );
    final violet = hotelPrimary.copyWith(minimumSize: const WidgetStatePropertyAll(Size(0, 38)));
    final out = OutlinedButton.styleFrom(minimumSize: const Size(0, 38));
    return AlertDialog(
      scrollable: true,
      title: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('${tStr(l['loanNumber']).isEmpty ? 'Loan' : tStr(l['loanNumber'])} · ${tStr(l['staffName'])}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        _badge(st),
      ]),
      content: SizedBox(
        width: 620,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            '${hotelLoanTypes[tStr(l['loanType'])] ?? tStr(l['loanType'])} · ${hotelLoanMethodLabel(l['repaymentMethod'])}${tNum(l['defaultPayrollDeduction']) > 0 ? ' · ${fmt(l['defaultPayrollDeduction'])} per payroll' : ''}',
            style: const TextStyle(fontSize: 13, color: TColors.slate500),
          ),
          const SizedBox(height: 12),
          twoUp([
            fig('Given', fmt(l['principalAmount'])),
            fig('To repay', fmt(l['totalRepayable'])),
            fig('Repaid', fmt(tNum(l['totalPrincipalRepaid']) + tNum(l['totalInterestRepaid'])), const Color(0xFF059669)),
            fig('Owed', _owes(l) ? fmt(l['outstandingBalance']) : '—', TColors.red600),
          ]),
          const SizedBox(height: 12),
          line('Paid out', tStr(l['disbursementDate']).isNotEmpty ? '${_fmtDate(l['disbursementDate'])} from ${tStr(l['cashAccountName']).isEmpty ? '—' : tStr(l['cashAccountName'])}' : 'not yet'),
          line('Expected to finish', _fmtDate(l['expectedEndDate'])),
          if (tNum(l['interestAmount']) > 0) line('Interest repaid', '${fmt(l['totalInterestRepaid'])} of ${fmt(l['interestAmount'])}'),
          if (tStr(l['reference']).isNotEmpty) line('Reference', tStr(l['reference'])),
          if (tNum(l['draftPayrollClaims']) > 0)
            Text('${fmt(l['draftPayrollClaims'])} set to be deducted on a draft payroll run', style: const TextStyle(fontSize: 13, color: TColors.amber700)),
          if (tStr(l['notes']).isNotEmpty) line('Notes', tStr(l['notes'])),
          if (tStr(l['reversedReason']).isNotEmpty)
            Text('${st == 'Cancelled' ? 'Cancelled' : 'Reversed'}: ${tStr(l['reversedReason'])}${tStr(l['reversedBy']).isNotEmpty ? ' — ${tStr(l['reversedBy'])}' : ''}',
                style: const TextStyle(fontSize: 13, color: Color(0xFFB91C1C))),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (st == 'Draft') ...[
              FilledButton.icon(style: violet, onPressed: () => _after(widget.onDisburse), icon: const Icon(Icons.volunteer_activism_outlined, size: 16), label: const Text('Pay out')),
              OutlinedButton.icon(style: out, onPressed: () => _after(widget.onEdit), icon: const Icon(Icons.edit_outlined, size: 16), label: const Text('Edit')),
              OutlinedButton.icon(
                style: out.copyWith(foregroundColor: const WidgetStatePropertyAll(TColors.amber700)),
                onPressed: () => _after(widget.onCancel),
                icon: const Icon(Icons.cancel_outlined, size: 16),
                label: const Text('Cancel'),
              ),
            ],
            if (st == 'Active' || st == 'Paid') ...[
              if (st == 'Active')
                FilledButton.icon(
                    style: violet, onPressed: () => _after(widget.onRepay), icon: const Icon(Icons.account_balance_wallet_outlined, size: 16), label: const Text('Record repayment')),
              OutlinedButton.icon(style: out, onPressed: () => _after(widget.onEdit), icon: const Icon(Icons.edit_outlined, size: 16), label: const Text('Edit plan')),
              OutlinedButton.icon(
                style: out.copyWith(foregroundColor: const WidgetStatePropertyAll(Color(0xFFB91C1C))),
                onPressed: () => _after(widget.onReverse),
                icon: const Icon(Icons.undo, size: 16),
                label: const Text('Reverse loan'),
              ),
            ],
          ]),
          const SizedBox(height: 14),
          const Text('Repayments', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (_loading)
            const LoadingLine('Loading…')
          else if (_reps.isEmpty)
            const Text('No repayments yet.', style: TextStyle(fontSize: 13, color: TColors.slate500))
          else
            for (final rp in _reps)
              Opacity(
                opacity: rp['status'] == 'Reversed' ? .6 : 1,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${_fmtDate(rp['repaymentDate'])} · ${hotelLoanSourceLabel(rp['sourceType'])}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        Text(
                          rp['sourceType'] == 'Payroll'
                              ? 'Payroll ${tStr(rp['payrollPeriod']).isEmpty ? '#${tStr(rp['hotelPayrollRunId'])}' : tStr(rp['payrollPeriod'])} · no cash moved'
                              : tStr(rp['cashAccountName']).isNotEmpty
                                  ? 'into ${tStr(rp['cashAccountName'])}'
                                  : 'no cash account',
                          style: const TextStyle(fontSize: 11, color: TColors.slate500),
                        ),
                        Text('Owed after ${fmt(rp['balanceAfter'])}', style: const TextStyle(fontSize: 11, color: TColors.slate500)),
                        const SizedBox(height: 4),
                        hotelBadge(tStr(rp['status']), rp['status'] == 'Posted' ? const Color(0xFFD1FAE5) : const Color(0xFFFEE2E2),
                            rp['status'] == 'Posted' ? const Color(0xFF047857) : const Color(0xFFB91C1C)),
                        if (tStr(rp['reversedReason']).isNotEmpty) Text(tStr(rp['reversedReason']), style: const TextStyle(fontSize: 11, color: TColors.slate500)),
                      ]),
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(fmt(rp['amount']), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      if (tNum(rp['interestAmount']) > 0) Text('${fmt(rp['interestAmount'])} interest', style: const TextStyle(fontSize: 11, color: TColors.slate500)),
                      if (rp['status'] == 'Posted' && rp['sourceType'] != 'Payroll')
                        IconButton(tooltip: 'Reverse this repayment', onPressed: () => _reverseRep(rp), icon: const Icon(Icons.undo, size: 16)),
                    ]),
                  ]),
                ),
              ),
          const SizedBox(height: 4),
          const Text('A payroll repayment is undone by reopening or cancelling its payroll run, so the payroll and the loan always agree.',
              style: TextStyle(fontSize: 11, color: TColors.slate500)),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}
