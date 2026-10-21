// Restaurant → Expenses → Employee Loans & Advances, as
// `app/restaurant-staff-loans/page.tsx` (migration 326): money LENT TO staff.
// Paying out moves the principal out of a cash account; money handed back
// puts it in again; a payroll deduction is set on a payroll line and becomes a
// repayment when that run is approved. `?staffId=` opens it on one staff member.

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
import '../shared/reason_select.dart' show ReasonSelect, cancelReasons, loanReversalReasons;
import 'restaurant_money_kit.dart';
import 'restaurant_payroll_screen.dart' show staffLoanTypeLabel;
import 'restaurant_roles.dart' show restaurantRose;
import 'restaurant_widgets.dart';

const staffLoanTypes = [('SalaryAdvance', 'Salary advance'), ('EmployeeLoan', 'Staff loan'), ('OtherAdvance', 'Other advance')];
const staffLoanMethods = [('PayrollDeduction', 'Deduct from payroll'), ('Mixed', 'Payroll and cash'), ('Cash', 'Cash')];
const staffLoanRepaySources = [('Cash', 'Cash'), ('MoMo', 'Mobile money'), ('Bank', 'Bank')];
String staffLoanMethodLabel(Object? v) => staffLoanMethods.where((m) => m.$1 == tStr(v)).firstOrNull?.$2 ?? tStr(v);
String staffLoanSourceLabel(Object? v) =>
    tStr(v) == 'Payroll' ? 'Payroll deduction' : staffLoanRepaySources.where((m) => m.$1 == tStr(v)).firstOrNull?.$2 ?? tStr(v);

const staffLoanTabs = [('OPEN', 'Open'), ('Active', 'Active'), ('Draft', 'Draft'), ('Paid', 'Paid'), ('CLOSED', 'Cancelled / reversed'), ('ALL', 'All')];

/// The web's `num()`: blank is 0.
num _num(String s) => s.trim().isEmpty ? 0 : (num.tryParse(s.trim()) ?? double.nan);
String _d(Object? s) => tStr(s).isEmpty ? '—' : tStr(s).split('T').first;
String _plain(num v) => v == v.roundToDouble() ? v.toInt().toString() : '$v';

/// The list's filters: the tab, one staff member, and the search.
List<Map> filterStaffLoans(List<Map> loans, {String tab = 'OPEN', String staff = 'ALL', String search = ''}) {
  var list = loans;
  if (tab == 'OPEN') {
    list = [for (final l in list) if (l['status'] == 'Draft' || l['status'] == 'Active') l];
  } else if (tab == 'CLOSED') {
    list = [for (final l in list) if (l['status'] == 'Cancelled' || l['status'] == 'Reversed') l];
  } else if (tab != 'ALL') {
    list = [for (final l in list) if (l['status'] == tab) l];
  }
  if (staff != 'ALL') list = [for (final l in list) if ('${tIntOrNull(l['restaurantStaffId'])}' == staff) l];
  final q = search.trim().toLowerCase();
  if (q.isNotEmpty) {
    list = [
      for (final l in list)
        if (tStr(l['staffName']).toLowerCase().contains(q) || tStr(l['loanNumber']).toLowerCase().contains(q) || tStr(l['reference']).toLowerCase().contains(q)) l,
    ];
  }
  return list;
}

const _statusStyle = {
  'Draft': (TColors.slate100, TColors.slate700, TColors.slate200),
  'Active': (Color(0xFFEFF6FF), Color(0xFF1D4ED8), Color(0xFFBFDBFE)),
  'Paid': (Color(0xFFF0FDF4), Color(0xFF15803D), Color(0xFFBBF7D0)),
  'Cancelled': (TColors.amber50, TColors.amber700, TColors.amber200),
  'Reversed': (Color(0xFFFEF2F2), Color(0xFFB91C1C), Color(0xFFFECACA)),
};
Widget _status(Object? s) {
  final (bg, fg, b) = _statusStyle[tStr(s)] ?? (Colors.white, TColors.slate700, TColors.slate200);
  return rStatusBadge(tStr(s), bg: bg, fg: fg, border: b);
}

/// The calls and dialogs the list and the loan page share.
class _LoansApi {
  _LoansApi(this.session, this.company, this.fmt, this.accounts);
  final Session session;
  final Company company;
  FarmMoney fmt;
  List<Map> accounts;
  ApiClient get api => session.farmClient;
  String u(String path, [Map<String, Object?> q = const {}]) {
    final query = {'farmId': company.farmId};
    q.forEach((k, v) {
      if (v != null && '$v' != '') query[k] = '$v';
    });
    return Uri(path: '/api/Restaurant$path', queryParameters: query).toString();
  }

  Widget accountSelect(int? value, ValueChanged<int?> onChanged, String placeholder) => AppSelect<int>(
        value: value ?? -1,
        items: [
          AppSelectItem(value: -1, label: placeholder),
          for (final a in accounts) AppSelectItem(value: tIntOrNull(a['cashAccountId'])!, label: '${tStr(a['name'])} (${fmt(tNum(a['currentBalance']))})'),
        ],
        onChanged: (v) => onChanged(v == null || v == -1 ? null : v),
      );

  Future<bool> payOut(BuildContext context, Map l) async =>
      await showDialog<bool>(context: context, builder: (_) => _PayOutDialog(api: this, loan: l)) == true;
  Future<bool> repay(BuildContext context, Map l) async =>
      await showDialog<bool>(context: context, builder: (_) => _RepayDialog(api: this, loan: l)) == true;
  Future<bool> reason(BuildContext context, String kind, {Map? loan, Map? repayment}) async =>
      await showDialog<bool>(context: context, builder: (_) => _ReasonDialog(api: this, kind: kind, loan: loan, repayment: repayment)) == true;
}

class RestaurantStaffLoansScreen extends StatefulWidget {
  const RestaurantStaffLoansScreen({super.key, required this.session, required this.company, this.staffId});
  final Session session;
  final Company company;

  /// `?staffId=`: the page filtered to one staff member.
  final int? staffId;

  @override
  State<RestaurantStaffLoansScreen> createState() => _RestaurantStaffLoansScreenState();
}

class _RestaurantStaffLoansScreenState extends State<RestaurantStaffLoansScreen> {
  late final _p = _LoansApi(widget.session, widget.company, const FarmMoney(), []);
  bool _loading = true;
  List<Map> _loans = [], _staff = [];
  Map? _summary;
  String _tab = 'OPEN';
  late String _staffFilter = widget.staffId != null ? '${widget.staffId}' : 'ALL';
  final _search = TextEditingController();
  int _page = 1, _pageSize = 10;

  bool get _canView => (widget.company.role ?? '').toLowerCase() != 'staff';

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _p.fmt = m);
    });
    if (_canView) {
      _load();
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([
        _p.api.get(_p.u('/staff-loans')),
        _p.api.get(_p.u('/staff-loans/summary')),
        _p.api.get(_p.u('/staff')),
        loadRestaurantAccounts(_p.api, widget.company.farmId),
      ]);
      if (!mounted) return;
      setState(() {
        _loans = rowsOf(r[0]);
        _summary = r[1] is Map ? r[1] as Map : null;
        _staff = rowsOf(r[2]);
        _p.accounts = [for (final a in r[3] as List<Map>) if (a['isActive'] == true) a];
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load staff loans', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _form([Map? editing]) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _LoanFormDialog(api: _p, staff: _staff, editing: editing, staffId: _staffFilter != 'ALL' ? int.tryParse(_staffFilter) : null),
    );
    if (done == true) _load();
  }

  Future<void> _open(Map l) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _LoanPage(api: _p, loanId: tIntOrNull(l['staffLoanId'])!, staff: _staff, onChanged: _load),
      ));

  Future<void> _act(Future<bool> Function() f) async {
    if (await f()) _load();
  }

  List<Widget> _actions(Map l) {
    final st = tStr(l['status']);
    return [
      OutlinedButton.icon(onPressed: () => _open(l), icon: const Icon(Icons.visibility_outlined, size: 16), label: const Text('Details')),
      if (st == 'Draft')
        OutlinedButton.icon(
            onPressed: () => _act(() => _p.payOut(context, l)), icon: const Icon(Icons.volunteer_activism_outlined, size: 16), label: const Text('Pay out')),
      if (st == 'Active')
        OutlinedButton.icon(
            onPressed: () => _act(() => _p.repay(context, l)),
            icon: const Icon(Icons.account_balance_wallet_outlined, size: 16),
            label: const Text('Record repayment')),
      if (st == 'Draft')
        TextButton.icon(onPressed: () => _act(() => _p.reason(context, 'cancel', loan: l)), icon: const Icon(Icons.block, size: 16), label: const Text('Cancel')),
      if (st == 'Active')
        TextButton.icon(onPressed: () => _act(() => _p.reason(context, 'reverse', loan: l)), icon: const Icon(Icons.undo, size: 16), label: const Text('Reverse')),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/restaurant-staff-loans');
    final gh = _p.fmt;
    Widget body;
    if (_loading) {
      body = const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: LoadingLine('Loading…')));
    } else if (!_canView) {
      body = const TCard(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(
            child: Text('You do not have access to staff loans. Ask an admin for the Staff & payroll permission.',
                textAlign: TextAlign.center, style: TextStyle(color: TColors.slate600)),
          ),
        ),
      );
    } else {
      final s = _summary;
      final staffWithLoans = <int, String>{
        for (final l in _loans) tIntOrNull(l['restaurantStaffId']) ?? 0: tStr(l['staffName']).isEmpty ? 'Staff #${l['restaurantStaffId']}' : tStr(l['staffName']),
      }.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      final filtered = filterStaffLoans(_loans, tab: _tab, staff: _staffFilter, search: _search.text);
      if ((_page - 1) * _pageSize >= filtered.length && _page > 1) _page = 1;
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        RPageHeader(
          icon: Icons.volunteer_activism_outlined,
          title: 'Employee Loans & Advances',
          subtitle: 'Money lent to staff, and how it is being paid back',
          actions: [
            OutlinedButton.icon(
              onPressed: () => openAppHref(context, widget.session, widget.company, '/restaurant-payroll', label: 'Payroll'),
              icon: const Icon(Icons.payments_outlined, size: 16),
              label: const Text('Payroll'),
            ),
            roseButton('New advance', () => _form()),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: TColors.rose50, border: Border.all(color: TColors.rose200), borderRadius: BorderRadius.circular(8)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.info_outline, size: 16, color: Color(0xFF881337)),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  const TextSpan(text: 'An advance is '),
                  const TextSpan(text: 'not an expense', style: TextStyle(fontWeight: FontWeight.w700)),
                  const TextSpan(
                      text: ' — the staff member owes it back. Paying it out takes the amount from a cash account; money handed back puts it in again. Deductions set on a payroll line are repaid when that payroll is '),
                  const TextSpan(text: 'approved', style: TextStyle(fontWeight: FontWeight.w700)),
                  const TextSpan(text: ', and the P&L still shows the full wage. This is separate from '),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: GestureDetector(
                      onTap: () => openAppHref(context, widget.session, widget.company, '/restaurant-loans', label: 'Loans'),
                      child: const Text('Loans', style: TextStyle(fontSize: 13, color: Color(0xFF881337), decoration: TextDecoration.underline)),
                    ),
                  ),
                  const TextSpan(text: ', which is money the restaurant borrowed.'),
                ]),
                style: const TextStyle(fontSize: 13, color: Color(0xFF881337)),
              ),
            ),
          ]),
        ),
        if (s != null) ...[
          const SizedBox(height: 14),
          twoColumns([
            MoneyStat(label: 'Outstanding', value: gh(tNum(s['totalOutstanding'])), hint: 'What staff still owe the restaurant', accent: 'indigo'),
            MoneyStat(label: 'Advanced', value: gh(tNum(s['totalDisbursed'])), hint: tNum(s['draftCount']) > 0 ? '${_plain(tNum(s['draftCount']))} draft' : null, accent: 'rose'),
            MoneyStat(label: 'Repaid', value: gh(tNum(s['totalRepaid'])), hint: '${gh(tNum(s['repaidViaPayroll']))} via payroll', accent: 'emerald'),
            MoneyStat(label: 'Active advances', value: _plain(tNum(s['activeCount'])), hint: '${_plain(tNum(s['staffWithLoans']))} member(s) of staff'),
          ]),
          if (tNum(s['draftPayrollClaims']) > 0) ...[
            const SizedBox(height: 8),
            Text('${gh(tNum(s['draftPayrollClaims']))} is set aside on draft payroll runs and is repaid when they are approved.',
                style: const TextStyle(fontSize: 12, color: TColors.amber700)),
          ],
        ],
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (v, l) in staffLoanTabs)
            _tab == v
                ? FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: restaurantRose, visualDensity: VisualDensity.compact),
                    onPressed: () {},
                    child: Text(l))
                : OutlinedButton(
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: () => setState(() {
                          _tab = v;
                          _page = 1;
                        }),
                    child: Text(l)),
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
          items: [
            const AppSelectItem(value: 'ALL', label: 'All staff'),
            for (final e in staffWithLoans) AppSelectItem(value: '${e.key}', label: e.value),
            if (_staffFilter != 'ALL' && !staffWithLoans.any((e) => '${e.key}' == _staffFilter)) AppSelectItem(value: _staffFilter, label: 'Staff #$_staffFilter'),
          ],
          onChanged: (v) => setState(() {
            _staffFilter = v ?? 'ALL';
            _page = 1;
          }),
        ),
        const SizedBox(height: 14),
        if (filtered.isEmpty)
          TCard(
            child: REmptyState(
              icon: Icons.volunteer_activism_outlined,
              title: _loans.isEmpty ? 'No staff loans or advances yet' : 'Nothing matches these filters',
              description: 'Give a staff member an advance and set how much comes off each payroll.',
              actionLabel: 'New advance',
              onAction: () => _form(),
            ),
          )
        else
          TCard(
            padding: const EdgeInsets.all(10),
            child: MobileCardList<Map>(
              items: pageSlice(filtered, _page, _pageSize),
              striped: true,
              keyOf: (l) => '${l['staffLoanId']}',
              primary: (l) => '${tStr(l['loanNumber'])} · ${tStr(l['staffName']).isEmpty ? '—' : tStr(l['staffName'])}',
              secondary: (l) => '${_d(tStr(l['disbursementDate']).isNotEmpty ? l['disbursementDate'] : l['createdAt'])} · ${staffLoanTypeLabel(l['loanType'])}',
              trailing: (l) => _status(l['status']),
              highlights: (l) {
                final live = l['status'] == 'Active' || l['status'] == 'Paid';
                return [
                  Highlight('Outstanding', gh(live ? tNum(l['outstandingBalance']) : 0), accent: Accent.blue, wide: true),
                  Highlight('Advanced', gh(tNum(l['principalAmount'])), accent: Accent.rose),
                  Highlight('Repaid', gh(tNum(l['totalPrincipalRepaid']) + tNum(l['totalInterestRepaid'])), accent: Accent.emerald),
                ];
              },
              details: (l) => [
                ('Total repayable', gh(tNum(l['totalRepayable']))),
                ('Repayment', staffLoanMethodLabel(l['repaymentMethod'])),
                ('Suggested per payroll', tNum(l['defaultPayrollDeduction']) > 0 ? gh(tNum(l['defaultPayrollDeduction'])) : '—'),
                ('Paid from', tStr(l['cashAccountName']).isEmpty ? '—' : tStr(l['cashAccountName'])),
                ('Reference', tStr(l['reference']).isEmpty ? '—' : tStr(l['reference'])),
                ('Purpose', tStr(l['notes']).isEmpty ? '—' : tStr(l['notes'])),
                ('Repayments', _plain(tNum(l['repaymentCount']))),
                if (tNum(l['draftPayrollClaims']) > 0) ('On draft payroll', gh(tNum(l['draftPayrollClaims']))),
              ],
              actions: _actions,
              table: (rows) => TrackerTable(
                columns: const [
                  TCol('Loan', width: 120), TCol('Staff', width: 150), TCol('Type', width: 120), TCol('Given', right: true, width: 120),
                  TCol('Owed', right: true, width: 130), TCol('Repayment', width: 150), TCol('Status', width: 100), TCol('', right: true, width: 120),
                ],
                rows: [
                  for (final l in rows)
                    [
                      InkWell(
                        onTap: () => _open(l),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text(tStr(l['loanNumber']), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          Text(_d(tStr(l['disbursementDate']).isNotEmpty ? l['disbursementDate'] : l['createdAt']), style: const TextStyle(fontSize: 11, color: TColors.slate500)),
                        ]),
                      ),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(tStr(l['staffName']).isEmpty ? '—' : tStr(l['staffName']), style: const TextStyle(fontWeight: FontWeight.w500)),
                        if (l['staffIsActive'] == false) const Text('inactive / removed', style: TextStyle(fontSize: 11, color: TColors.amber600)),
                      ]),
                      cellText(staffLoanTypeLabel(l['loanType'])),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                        Text(gh(tNum(l['principalAmount']))),
                        if (tNum(l['interestAmount']) > 0) Text('+${gh(tNum(l['interestAmount']))} interest', style: const TextStyle(fontSize: 11, color: TColors.slate500)),
                      ]),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                        Text(l['status'] == 'Active' || l['status'] == 'Paid' ? gh(tNum(l['outstandingBalance'])) : '—',
                            style: TextStyle(
                                color: l['status'] == 'Active' ? TColors.red600 : TColors.slate500,
                                fontWeight: l['status'] == 'Active' ? FontWeight.w600 : FontWeight.w400)),
                        if (tNum(l['draftPayrollClaims']) > 0)
                          Text('${gh(tNum(l['draftPayrollClaims']))} on draft payroll', style: const TextStyle(fontSize: 11, color: TColors.amber600)),
                      ]),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(staffLoanMethodLabel(l['repaymentMethod']), style: const TextStyle(fontSize: 12)),
                        if (tNum(l['defaultPayrollDeduction']) > 0)
                          Text('${gh(tNum(l['defaultPayrollDeduction']))} per payroll', style: const TextStyle(fontSize: 11, color: TColors.slate500)),
                      ]),
                      Align(alignment: Alignment.centerLeft, child: _status(l['status'])),
                      l['status'] == 'Draft'
                          ? OutlinedButton(onPressed: () => _act(() => _p.payOut(context, l)), child: const Text('Pay out'))
                          : l['status'] == 'Active'
                              ? OutlinedButton(onPressed: () => _act(() => _p.repay(context, l)), child: const Text('Repay'))
                              : const SizedBox(),
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
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Employee Loans & Advances')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [body]),
      ),
    );
  }
}

// ------------------------------------------------------------------ New / edit

class _LoanFormDialog extends StatefulWidget {
  const _LoanFormDialog({required this.api, required this.staff, this.editing, this.staffId});
  final _LoansApi api;
  final List<Map> staff;
  final Map? editing;
  final int? staffId;
  @override
  State<_LoanFormDialog> createState() => _LoanFormDialogState();
}

class _LoanFormDialogState extends State<_LoanFormDialog> {
  late final Map? _e = widget.editing;
  late int? _staffId = _e != null ? tIntOrNull(_e['restaurantStaffId']) : widget.staffId;
  late String _type = _e != null ? tStr(_e['loanType']) : 'SalaryAdvance';
  late String _method = _e != null ? tStr(_e['repaymentMethod']) : 'PayrollDeduction';
  late final _principal = TextEditingController(text: _e != null ? _plain(tNum(_e['principalAmount'])) : '');
  late final _interest = TextEditingController(text: _e != null && tNum(_e['interestAmount']) != 0 ? _plain(tNum(_e['interestAmount'])) : '');
  late final _perPayroll =
      TextEditingController(text: _e != null && tNum(_e['defaultPayrollDeduction']) != 0 ? _plain(tNum(_e['defaultPayrollDeduction'])) : '');
  late String _expectedEnd = _e != null && tStr(_e['expectedEndDate']).isNotEmpty ? _d(_e['expectedEndDate']) : '';
  late final _reference = TextEditingController(text: _e != null ? tStr(_e['reference']) : '');
  late final _notes = TextEditingController(text: _e != null ? tStr(_e['notes']) : '');
  bool _disburseNow = true;
  int? _account;
  String _disbursementDate = rTodayIso();
  bool _saving = false;

  bool get _locked => _e != null && _e['status'] != 'Draft';
  bool get _byPayroll => _method == 'PayrollDeduction' || _method == 'Mixed';
  num get _total => _num(_principal.text) + _num(_interest.text);
  int get _periods => _byPayroll && _num(_perPayroll.text) > 0 ? (_total / _num(_perPayroll.text)).ceil() : 0;

  @override
  void dispose() {
    for (final c in [_principal, _interest, _perPayroll, _reference, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_e == null && _staffId == null) return trackerToast(context, 'Choose the staff member', error: true);
    if (!(_num(_principal.text) > 0)) return trackerToast(context, 'Enter the amount given', error: true);
    if (_byPayroll && !(_num(_perPayroll.text) > 0)) return trackerToast(context, 'Set how much to deduct from each payroll', error: true);
    setState(() => _saving = true);
    final p = widget.api;
    final common = {
      'loanType': _type,
      'principalAmount': _num(_principal.text),
      'interestAmount': _num(_interest.text),
      'repaymentMethod': _method,
      'defaultPayrollDeduction': _num(_perPayroll.text),
      'expectedEndDate': _expectedEnd.isEmpty ? null : _expectedEnd,
      'reference': _reference.text.isEmpty ? null : _reference.text,
      'notes': _notes.text.isEmpty ? null : _notes.text,
    };
    try {
      if (_e != null) {
        await p.api.put(p.u('/staff-loans/${tIntOrNull(_e['staffLoanId'])}'), body: common);
        if (mounted) trackerToast(context, 'Loan updated');
      } else {
        await p.api.post(p.u('/staff-loans'), body: {
          'restaurantStaffId': _staffId,
          ...common,
          'disburseNow': _disburseNow,
          'cashAccountId': _account,
          'disbursementDate': _disburseNow ? _disbursementDate : null,
        });
        if (mounted) trackerToast(context, _disburseNow ? 'Advance paid out' : 'Saved as a draft — pay it out when the money is handed over');
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Could not save', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = widget.api.fmt;
    final staffChoices = _e != null ? widget.staff : [for (final s in widget.staff) if (s['isActive'] == true) s];
    String name(Map s) => '${tStr(s['firstName'])} ${tStr(s['lastName'])}'.trim();
    return PopScope(
      canPop: !_saving,
      child: rDialog(
        title: _e != null ? 'Edit ${tStr(_e['loanNumber'])}' : 'New loan or advance',
        description: _e != null
            ? (_locked ? 'Money has moved, so only the repayment plan and notes can change.' : 'Still a draft: anything can change.')
            : 'Who is borrowing, how much, and how they will pay it back.',
        children: [
          rField(
            'Staff member *',
            AppSelect<int>(
              value: _staffId,
              hintText: 'Choose staff',
              enabled: _e == null,
              items: [for (final s in staffChoices) AppSelectItem(value: tIntOrNull(s['restaurantStaffId'])!, label: '${name(s)} — ${tStr(s['role'])}')],
              onChanged: (v) => setState(() => _staffId = v),
            ),
          ),
          rField(
            'Type',
            AppSelect<String>(
              value: _type,
              enabled: !_locked,
              items: [for (final (v, l) in staffLoanTypes) AppSelectItem(value: v, label: l)],
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
          ),
          rField('Amount given *', AppInput(controller: _principal, enabled: !_locked, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}))),
          rField('Interest (flat amount)', AppInput(controller: _interest, enabled: !_locked, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}))),
          rField('Total to repay', rFigureBox('', _total.isNaN ? '—' : fmt(_total))),
          rField(
            'Repayment method',
            AppSelect<String>(
              value: _method,
              items: [for (final (v, l) in staffLoanMethods) AppSelectItem(value: v, label: l)],
              onChanged: (v) => setState(() => _method = v ?? _method),
            ),
          ),
          rField('Deduct per payroll${_byPayroll ? ' *' : ''}', rNumberInput(_perPayroll, onChanged: () => setState(() {}))),
          rField('Expected to finish', rDateInput(_expectedEnd, (v) => setState(() => _expectedEnd = v))),
          rField('Reference', AppInput(controller: _reference)),
          if (_periods > 0)
            Text('Cleared in about $_periods payroll run${_periods == 1 ? '' : 's'}. Payroll will suggest this deduction automatically.',
                style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          rField('Notes', AppInput(controller: _notes, minLines: 2, maxLines: 4)),
          if (_e == null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                InkWell(
                  onTap: () => setState(() => _disburseNow = !_disburseNow),
                  child: Row(children: [
                    Checkbox(value: _disburseNow, onChanged: (v) => setState(() => _disburseNow = v == true)),
                    const Expanded(child: Text('Pay the money out now', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
                  ]),
                ),
                if (_disburseNow) ...[
                  const SizedBox(height: 8),
                  rField('Paid from', widget.api.accountSelect(_account, (v) => setState(() => _account = v), 'Main Cash Box (default)')),
                  const SizedBox(height: 10),
                  rField('Date paid', rDateInput(_disbursementDate, (v) => setState(() => _disbursementDate = v), max: rTodayIso())),
                ] else
                  const Text('Saved as a draft; nothing moves until you pay it out.', style: TextStyle(fontSize: 12, color: TColors.slate500)),
              ]),
            ),
        ],
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          rConfirm(
            _e != null ? 'Save changes' : _disburseNow ? 'Give ${fmt(_num(_principal.text).isNaN ? 0 : _num(_principal.text))}' : 'Save draft',
            _saving ? null : _save,
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ Pay out / repay / reason

class _PayOutDialog extends StatefulWidget {
  const _PayOutDialog({required this.api, required this.loan});
  final _LoansApi api;
  final Map loan;
  @override
  State<_PayOutDialog> createState() => _PayOutDialogState();
}

class _PayOutDialogState extends State<_PayOutDialog> {
  int? _account;
  String _date = rTodayIso();
  late final _reference = TextEditingController(text: tStr(widget.loan['reference']));
  bool _saving = false;

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    setState(() => _saving = true);
    final l = widget.loan, p = widget.api;
    try {
      await p.api.post(p.u('/staff-loans/${tIntOrNull(l['staffLoanId'])}/disburse'),
          body: {'cashAccountId': _account, 'disbursementDate': _date, 'reference': _reference.text.isEmpty ? null : _reference.text});
      if (!mounted) return;
      trackerToast(context, '${p.fmt(tNum(l['principalAmount']))} paid out to ${tStr(l['staffName']).isEmpty ? 'staff' : tStr(l['staffName'])}');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Could not pay out', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.loan;
    return rDialog(
      title: 'Pay out ${tStr(l['loanNumber'])}',
      description: '${widget.api.fmt(tNum(l['principalAmount']))} to ${tStr(l['staffName'])}. The amount leaves the account you choose.',
      children: [
        rField('Paid from', widget.api.accountSelect(_account, (v) => setState(() => _account = v), 'Main Cash Box (default)')),
        rField('Date paid', rDateInput(_date, (v) => setState(() => _date = v), max: rTodayIso())),
        rField('Reference', AppInput(controller: _reference)),
      ],
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Back')),
        rConfirm('Pay out', _saving ? null : _go),
      ],
    );
  }
}

class _RepayDialog extends StatefulWidget {
  const _RepayDialog({required this.api, required this.loan});
  final _LoansApi api;
  final Map loan;
  @override
  State<_RepayDialog> createState() => _RepayDialogState();
}

class _RepayDialogState extends State<_RepayDialog> {
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  String _source = 'Cash';
  int? _account;
  String _date = rTodayIso();
  bool _saving = false;

  num get _owed => tNum(widget.loan['outstandingBalance']);

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final amt = _num(_amount.text);
    final p = widget.api;
    if (!(amt > 0)) return trackerToast(context, 'Enter the amount repaid', error: true);
    if (amt > _owed) return trackerToast(context, 'That is more than the ${p.fmt(_owed)} still owed', error: true);
    setState(() => _saving = true);
    try {
      await p.api.post(p.u('/staff-loans/${tIntOrNull(widget.loan['staffLoanId'])}/repayments'), body: {
        'amount': amt,
        'sourceType': _source,
        'cashAccountId': _account,
        'repaymentDate': _date,
        'reference': _reference.text.isEmpty ? null : _reference.text,
        'notes': null,
      });
      if (!mounted) return;
      trackerToast(context, 'Repayment recorded');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Could not record repayment', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.loan;
    return rDialog(
      title: 'Record a repayment',
      description:
          '${tStr(l['staffName'])} · ${tStr(l['loanNumber'])} · owes ${widget.api.fmt(_owed)}. For money handed back directly; payroll deductions are set on the payroll run.',
      children: [
        rField(
          'Amount *',
          Row(children: [
            Expanded(child: rNumberInput(_amount)),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: () => setState(() => _amount.text = _plain(_owed)), child: const Text('All')),
          ]),
        ),
        rField(
          'Paid by',
          AppSelect<String>(
            value: _source,
            items: [for (final (v, l) in staffLoanRepaySources) AppSelectItem(value: v, label: l)],
            onChanged: (v) => setState(() => _source = v ?? 'Cash'),
          ),
        ),
        rField('Paid into', widget.api.accountSelect(_account, (v) => setState(() => _account = v), 'The default account for that method')),
        rField('Date', rDateInput(_date, (v) => setState(() => _date = v), max: rTodayIso())),
        rField('Reference', AppInput(controller: _reference)),
      ],
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Back')),
        rConfirm('Record', _saving ? null : _go),
      ],
    );
  }
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.api, required this.kind, this.loan, this.repayment});
  final _LoansApi api;

  /// cancel / reverse / reverseRepayment.
  final String kind;
  final Map? loan, repayment;
  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  String _reason = '';
  bool _saving = false;

  Future<void> _go() async {
    if (widget.kind != 'cancel' && _reason.trim().isEmpty) return trackerToast(context, 'Give a reason', error: true);
    setState(() => _saving = true);
    final p = widget.api;
    try {
      final path = switch (widget.kind) {
        'cancel' => '/staff-loans/${tIntOrNull(widget.loan!['staffLoanId'])}/cancel',
        'reverse' => '/staff-loans/${tIntOrNull(widget.loan!['staffLoanId'])}/reverse',
        _ => '/staff-loans/repayments/${tIntOrNull(widget.repayment!['repaymentId'])}/reverse',
      };
      await p.api.post(p.u(path), body: {'reason': _reason});
      if (!mounted) return;
      trackerToast(context, widget.kind == 'cancel' ? 'Loan cancelled' : 'Reversed');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Could not do that', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = widget.api.fmt;
    final l = widget.loan, r = widget.repayment;
    return rDialog(
      title: switch (widget.kind) {
        'cancel' => 'Cancel ${tStr(l?['loanNumber'])}?',
        'reverse' => 'Reverse ${tStr(l?['loanNumber'])}?',
        _ => 'Reverse this repayment?',
      },
      description: switch (widget.kind) {
        'cancel' => 'The draft is closed. No money has moved.',
        'reverse' =>
          '${fmt(tNum(l?['principalAmount']))} goes back into ${tStr(l?['cashAccountName']).isEmpty ? 'the account it came from' : tStr(l?['cashAccountName'])}, dated today. Any repayments must be reversed first.',
        _ => '${fmt(tNum(r?['amount']))} goes back out of ${tStr(r?['cashAccountName']).isEmpty ? 'its account' : tStr(r?['cashAccountName'])}, dated today, and is owed again.',
      },
      children: [
        rField(widget.kind == 'cancel' ? 'Reason (optional)' : 'Reason *',
            ReasonSelect(options: widget.kind == 'cancel' ? cancelReasons : loanReversalReasons, value: _reason, onChanged: (v) => setState(() => _reason = v))),
      ],
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Back')),
        rConfirm('Confirm', _saving ? null : _go, color: TColors.red600),
      ],
    );
  }
}

// ------------------------------------------------------------------ Loan page

/// The web's detail dialog, as a page of its own on a phone.
class _LoanPage extends StatefulWidget {
  const _LoanPage({required this.api, required this.loanId, required this.staff, required this.onChanged});
  final _LoansApi api;
  final int loanId;
  final List<Map> staff;
  final Future<void> Function() onChanged;
  @override
  State<_LoanPage> createState() => _LoanPageState();
}

class _LoanPageState extends State<_LoanPage> {
  Map? _loan;
  List<Map> _repayments = [];

  _LoansApi get _p => widget.api;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  /// refresh(): the list, then this loan and its repayments, read fresh.
  Future<void> _refresh() async {
    try {
      final r = await Future.wait([
        _p.api.get(_p.u('/staff-loans')),
        _p.api.get(_p.u('/staff-loans/repayments', {'loanId': widget.loanId})),
      ]);
      if (!mounted) return;
      setState(() {
        _loan = rowsOf(r[0]).where((l) => tIntOrNull(l['staffLoanId']) == widget.loanId).firstOrNull;
        _repayments = rowsOf(r[1]);
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load repayments', description: e.message, error: true);
    }
  }

  Future<void> _act(Future<bool> Function() f) async {
    if (await f()) {
      await widget.onChanged();
      await _refresh();
    }
  }

  Future<void> _edit(Map l) async {
    final done = await showDialog<bool>(context: context, builder: (_) => _LoanFormDialog(api: _p, staff: widget.staff, editing: l));
    if (done == true) {
      await widget.onChanged();
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = _loan;
    final fmt = _p.fmt;
    if (l == null) return Scaffold(appBar: AppBar(title: const Text('Staff loan')), body: const Center(child: LoadingLine('Loading…')));
    final st = tStr(l['status']);
    final live = st == 'Active' || st == 'Paid';
    Widget figure(String label, String value, [Color? c]) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c ?? TColors.slate900))),
          ]),
        );
    Widget line(String k, String v, [Color? c]) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text.rich(TextSpan(children: [
            TextSpan(text: '$k ', style: const TextStyle(color: TColors.slate500)),
            TextSpan(text: v, style: TextStyle(color: c ?? TColors.slate900)),
          ]), style: const TextStyle(fontSize: 13)),
        );
    return Scaffold(
      backgroundColor: TColors.slate50,
      appBar: AppBar(title: Text(tStr(l['loanNumber']))),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('${tStr(l['loanNumber'])} · ${tStr(l['staffName'])}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            _status(st),
          ]),
          const SizedBox(height: 4),
          Text(
              '${staffLoanTypeLabel(l['loanType'])} · ${staffLoanMethodLabel(l['repaymentMethod'])}${tNum(l['defaultPayrollDeduction']) > 0 ? ' · ${fmt(tNum(l['defaultPayrollDeduction']))} per payroll' : ''}',
              style: const TextStyle(fontSize: 13, color: TColors.slate500)),
          const SizedBox(height: 12),
          twoColumns([
            figure('Given', fmt(tNum(l['principalAmount']))),
            figure('To repay', fmt(tNum(l['totalRepayable']))),
            figure('Repaid', fmt(tNum(l['totalPrincipalRepaid']) + tNum(l['totalInterestRepaid'])), const Color(0xFF16A34A)),
            figure('Owed', live ? fmt(tNum(l['outstandingBalance'])) : '—', TColors.red600),
          ], gap: 8),
          const SizedBox(height: 12),
          line('Paid out:', tStr(l['disbursementDate']).isNotEmpty ? '${_d(l['disbursementDate'])} from ${tStr(l['cashAccountName']).isEmpty ? '—' : tStr(l['cashAccountName'])}' : 'not yet'),
          line('Expected to finish:', _d(l['expectedEndDate'])),
          if (tNum(l['draftPayrollClaims']) > 0)
            Text('${fmt(tNum(l['draftPayrollClaims']))} set to be deducted on a draft payroll', style: const TextStyle(fontSize: 13, color: TColors.amber700)),
          if (tStr(l['notes']).isNotEmpty) line('Notes:', tStr(l['notes'])),
          if (tStr(l['closedReason']).isNotEmpty) Text('$st: ${tStr(l['closedReason'])}', style: const TextStyle(fontSize: 13, color: Color(0xFFB91C1C))),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (st == 'Draft') ...[
              roseButton('Pay out', () => _act(() => _p.payOut(context, l)), icon: Icons.volunteer_activism_outlined),
              OutlinedButton.icon(onPressed: () => _edit(l), icon: const Icon(Icons.edit_outlined, size: 16), label: const Text('Edit')),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: TColors.amber700),
                onPressed: () => _act(() => _p.reason(context, 'cancel', loan: l)),
                icon: const Icon(Icons.block, size: 16),
                label: const Text('Cancel'),
              ),
            ],
            if (live) ...[
              if (st == 'Active') roseButton('Record repayment', () => _act(() => _p.repay(context, l)), icon: Icons.account_balance_wallet_outlined),
              OutlinedButton.icon(onPressed: () => _edit(l), icon: const Icon(Icons.edit_outlined, size: 16), label: const Text('Edit plan')),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFB91C1C)),
                onPressed: () => _act(() => _p.reason(context, 'reverse', loan: l)),
                icon: const Icon(Icons.undo, size: 16),
                label: const Text('Reverse loan'),
              ),
            ],
          ]),
          const SizedBox(height: 16),
          const Text('Repayments', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (_repayments.isEmpty)
            const Text('No repayments yet.', style: TextStyle(fontSize: 13, color: TColors.slate500))
          else
            for (final rp in _repayments) _repaymentCard(rp),
          const SizedBox(height: 8),
          const Text('A payroll repayment is undone by reopening or cancelling its payroll run, so the payroll and the loan always agree.',
              style: TextStyle(fontSize: 12, color: TColors.slate500)),
        ]),
      ),
    );
  }

  Widget _repaymentCard(Map rp) {
    final fmt = _p.fmt;
    final reversed = rp['status'] == 'Reversed';
    final payroll = rp['sourceType'] == 'Payroll';
    return Opacity(
      opacity: reversed ? .6 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(10)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${_d(rp['repaymentDate'])} · ${staffLoanSourceLabel(rp['sourceType'])}', style: const TextStyle(fontWeight: FontWeight.w500)),
              Text(
                  payroll
                      ? '${tStr(rp['payrollRunNumber']).isEmpty ? 'payroll' : tStr(rp['payrollRunNumber'])} · no cash moved'
                      : 'into ${tStr(rp['cashAccountName']).isEmpty ? '—' : tStr(rp['cashAccountName'])}',
                  style: const TextStyle(fontSize: 12, color: TColors.slate500)),
              const SizedBox(height: 4),
              Text.rich(TextSpan(children: [
                TextSpan(text: fmt(tNum(rp['amount'])), style: const TextStyle(fontWeight: FontWeight.w700)),
                if (tNum(rp['interestAmount']) > 0) TextSpan(text: ' (${fmt(tNum(rp['interestAmount']))} interest)', style: const TextStyle(color: TColors.slate500)),
                TextSpan(text: ' · owed after ${fmt(tNum(rp['balanceAfter']))}', style: const TextStyle(color: TColors.slate500)),
              ]), style: const TextStyle(fontSize: 13)),
              if (tStr(rp['reversedReason']).isNotEmpty) Text(tStr(rp['reversedReason']), style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            rp['status'] == 'Posted'
                ? rStatusBadge('Posted', bg: const Color(0xFFF0FDF4), fg: const Color(0xFF15803D), border: const Color(0xFFBBF7D0))
                : rStatusBadge(tStr(rp['status']), bg: const Color(0xFFFEF2F2), fg: const Color(0xFFB91C1C), border: const Color(0xFFFECACA)),
            if (rp['status'] == 'Posted' && !payroll)
              IconButton(
                tooltip: 'Reverse this repayment',
                icon: const Icon(Icons.undo, size: 18),
                onPressed: () => _act(() => _p.reason(context, 'reverseRepayment', repayment: rp)),
              ),
          ]),
        ]),
      ),
    );
  }
}
