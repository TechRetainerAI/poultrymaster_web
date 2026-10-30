import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/money/money_widgets.dart';
import '../poultry/reports/report_routes.dart' show openAppHref;
import '../poultry/sales/balances_logic.dart' show BalanceSide, pageSlice;
import '../poultry/sales/balances_widgets.dart';
import '../poultry/sales/sale_dialogs.dart' show showPaymentHistory;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/business_dates.dart';
import '../shared/company_clock.dart';
import '../shared/reason_select.dart' show cancelReasons;
import 'water_payroll_screen.dart' show showWaterPayrollPrompt;

/// Water → Expenses → Expenses, as `app/water-expenses/page.tsx`: one ledger
/// of direct WaterExpenses and per-delivery expenses (migration 085), Record
/// water expense (paid / partly paid / unpaid, migration 240), categories,
/// Submit → Approve, Cancel, and paying a bill through the Supplier Balances
/// payment screen.

const waterExpenseStatuses = ['Draft', 'Submitted', 'Approved', 'Rejected', 'Cancelled'];
const waterExpenseMethods = [('Cash', 'Cash'), ('MoMo', 'Mobile Money'), ('Bank', 'Bank'), ('Card', 'Card'), ('Credit', 'Credit'), ('Mixed', 'Mixed')];
const waterSupplierTypes = [
  'Raw Material Supplier', 'Packaging Supplier', 'Fuel Supplier', 'Machine Parts Supplier',
  'Vehicle Repair Supplier', 'Utility Provider', 'Service Provider', 'Other',
];

String _f2(Object? v) => tNum(v).toStringAsFixed(2);
String _day(Object? v) => tStr(v).split('T').first;

/// A row of the unified ledger: a direct expense or a delivery expense.
class WaterLedgerRow {
  const WaterLedgerRow(this.direct, this.row);
  final bool direct;
  final Map row;

  String get date => direct ? tStr(row['expenseDate']) : (row['returnDate'] != null ? tStr(row['returnDate']) : tStr(row['createdAt']));
  int get id => tIntOrNull(row[direct ? 'waterExpenseId' : 'waterDeliveryExpenseId']) ?? 0;
  String get key => direct ? 'exp-$id' : 'del-$id';

  /// unifiedStatus: a delivery expense follows its driver return.
  String get status {
    if (direct) return tStr(row['status']);
    final rs = tStr(row['returnStatus']);
    if (rs == 'Approved' || rs == 'Reconciled') return 'Approved';
    if (row['isApproved'] != true) return 'Draft';
    return 'Submitted';
  }
}

/// Merge both streams, newest first, ties by id descending.
List<WaterLedgerRow> mergeWaterExpenses(List<Map> expenses, List<Map> deliveries) {
  final all = [for (final e in expenses) WaterLedgerRow(true, e), for (final d in deliveries) WaterLedgerRow(false, d)];
  all.sort((a, b) => a.date == b.date ? b.id - a.id : b.date.compareTo(a.date));
  return all;
}

/// The page's search (five keys per kind) and calendar-day range.
List<WaterLedgerRow> filterWaterExpenses(List<WaterLedgerRow> rows, {String status = 'ALL', String search = '', String from = '', String to = ''}) {
  final s = search.trim().toLowerCase();
  return rows.where((e) {
    if (status != 'ALL' && e.status != status) return false;
    final d = _day(e.date);
    if (from.isNotEmpty && d.compareTo(from) < 0) return false;
    if (to.isNotEmpty && d.compareTo(to) > 0) return false;
    if (s.isEmpty) return true;
    final keys = e.direct
        ? ['categoryName', 'description', 'paidTo', 'supplierName', 'notes']
        : ['expenseCategory', 'description', 'driverName', 'vehicleNumber', 'notes'];
    return keys.any((k) => e.row[k] != null && '${e.row[k]}'.toLowerCase().contains(s));
  }).toList();
}

bool isWaterExpenseOverdue(Map e) {
  final due = DateTime.tryParse(tStr(e['dueDate']));
  if (due == null || tNum(e['balance']) <= 0) return false;
  final now = DateTime.now();
  return due.isBefore(DateTime(now.year, now.month, now.day));
}

String waterPaidToLabel(Map e) {
  for (final k in ['supplierName', 'paidTo']) {
    if (tStr(e[k]).trim().isNotEmpty) return tStr(e[k]).trim();
  }
  return '—';
}

(Color, Color) waterExpenseStatusTone(String s) => switch (s) {
      'Submitted' => (TColors.blue100, const Color(0xFF1D4ED8)),
      'Approved' => (const Color(0xFFDCFCE7), const Color(0xFF15803D)),
      'Rejected' => (TColors.rose100, TColors.rose700),
      'Cancelled' => (TColors.amber100, TColors.amber700),
      _ => (TColors.slate100, TColors.slate700),
    };

Widget _statusBadge(String s) {
  final (bg, fg) = waterExpenseStatusTone(s);
  return TBadge(s, bg: bg, fg: fg);
}

/// renderPaymentBadge: Non-cash / Paid / Overdue / Partially paid / Unpaid.
Widget waterPaymentBadge(Map e) {
  if (tStr(e['paymentStatus']) == 'NonCash' || tStr(e['sourceType']) == 'WaterInternalUsage') {
    return const TBadge('Non-cash', bg: TColors.slate100, fg: TColors.slate600);
  }
  if (tNum(e['balance']) <= 0) return const TBadge('Paid', bg: TColors.emerald100, fg: TColors.emerald800);
  if (isWaterExpenseOverdue(e)) return const TBadge('Overdue', bg: TColors.red100, fg: TColors.red800);
  if (tNum(e['amountPaid']) > 0) return const TBadge('Partially paid', bg: TColors.amber100, fg: TColors.amber800);
  return const TBadge('Unpaid', bg: TColors.slate100, fg: TColors.slate700);
}

/// ExpenseSourceLink: (label, href) for an expense's source, or null.
(String, String?)? waterExpenseSource(Map e) {
  var type = tStr(e['sourceType']);
  var id = tIntOrNull(e['sourceId']);
  if (type.isEmpty && tIntOrNull(e['linkedWaterProductionBatchId']) != null) {
    type = 'ProductionBatch';
    id = tIntOrNull(e['linkedWaterProductionBatchId']);
  }
  if (type.isEmpty || id == null || id == 0) return null;
  return switch (type) {
    'ProductionBatch' => ('Production', '/water-production-batches/$id'),
    'RawMaterialPurchase' => ('Inventory & Supply Purchase', '/water-supply-purchases?purchaseId=$id'),
    'Payroll' => ('Payroll Run #$id', '/water-payroll/$id'),
    _ => ('$type #$id', null),
  };
}

class WaterExpensesScreen extends StatefulWidget {
  const WaterExpensesScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;
  @override
  State<WaterExpensesScreen> createState() => _WaterExpensesScreenState();
}

class _WaterExpensesScreenState extends State<WaterExpensesScreen> {
  List<Map> _expenses = [], _deliveries = [], _categories = [], _accounts = [];
  bool _loading = true;
  String _status = 'ALL';
  final _search = TextEditingController();
  String _from = '', _to = '';
  int _page = 1, _pageSize = 10, _lastTotal = -1;
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  String get _q => 'farmId=${Uri.encodeQueryComponent(_farmId)}';
  String get _me => Uri.encodeQueryComponent(widget.session.tokens.userId ?? '');

  /// water.supplier-payments.create / .reverse; the phone has no permission
  /// flags, so Staff are the ones left out.
  bool get _canPay => (widget.company.role ?? '').toLowerCase() != 'staff';

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
      final r = await Future.wait([
        _api.get('/api/Water/expenses', query: {...q, if (_status != 'ALL') 'status': _status}),
        _api.get('/api/Water/delivery-expenses', query: q),
        _api.get('/api/Water/expense-categories', query: q),
        _api.get('/api/Water/cash-accounts', query: q),
      ]);
      if (mounted) {
        setState(() {
          _expenses = rowsOf(r[0]);
          _deliveries = rowsOf(r[1]);
          _categories = rowsOf(r[2]);
          _accounts = rowsOf(r[3]);
        });
      }
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load expenses', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _record() async {
    final done = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => _RecordWaterExpenseScreen(session: widget.session, company: widget.company, categories: _categories, accounts: _accounts),
    ));
    if (done == true) _load();
  }

  Future<void> _categoriesDialog() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CategoriesDialog(session: widget.session, company: widget.company, categories: _categories, onAdded: _load),
    );
  }

  Future<void> _action(Map d, String action) async {
    final id = tStr(d['waterExpenseId']);
    try {
      if (action == 'submit') await _api.post('/api/Water/expenses/$id/submit?$_q');
      if (action == 'approve') await _api.post('/api/Water/expenses/$id/approve?$_q&approvedBy=$_me');
      if (mounted) trackerToast(context, 'Expense ${action}d');
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, '$action failed', description: e.message, error: true);
    }
  }

  Future<void> _cancel(Map d) => showWaterPayrollPrompt(
        context,
        title: 'Cancel expense',
        options: cancelReasons,
        description: 'Expense #${tStr(d['waterExpenseId'])} will be moved to Cancelled. Optionally tell the team why.',
        label: 'Reason (optional)',
        placeholder: 'e.g. duplicate entry, wrong amount, supplier refunded…',
        confirm: 'Cancel expense',
        allowEmpty: true,
        onSubmit: (reason) async {
          try {
            await _api.post('/api/Water/expenses/${tStr(d['waterExpenseId'])}/cancel?$_q&cancelledBy=$_me', body: {'reason': reason.isEmpty ? null : reason});
            if (mounted) trackerToast(context, 'Expense canceled');
            await _load();
            return true;
          } on ApiException catch (e) {
            if (mounted) trackerToast(context, 'Cancel failed', description: e.message, error: true);
            return false;
          }
        },
      );

  List<Map> get _payAccounts => [
        for (final a in _accounts)
          if (a['isActive'] == true)
            {'id': a['waterCashAccountId'], 'name': a['accountName'], 'currentBalance': a['currentBalance'], 'allowNegativeBalance': a['allowNegativeBalance']},
      ];

  String _partyName(Map e) => tStr(e['supplierName']).isNotEmpty ? tStr(e['supplierName']) : (tStr(e['paidTo']).isNotEmpty ? tStr(e['paidTo']) : 'Supplier');

  Future<void> _pay(Map e) async {
    final date = DateTime.tryParse(tStr(e['expenseDate']));
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => RecordPaymentScreen(
        session: widget.session,
        company: widget.company,
        api: '/api/Water',
        party: {'partyId': e['supplierId'], 'partyName': _partyName(e)},
        single: {
          'documentType': 'Expense',
          'documentId': e['waterExpenseId'],
          'reference': 'E${tStr(e['waterExpenseId'])}',
          'documentDate': e['expenseDate'],
          'label': tStr(e['description']).isNotEmpty ? e['description'] : (tStr(e['categoryName']).isNotEmpty ? e['categoryName'] : 'Expense'),
          'totalAmount': e['amount'],
          'amountPaid': e['amountPaid'],
          'balance': e['balance'],
          'dueDate': e['dueDate'],
          'ageDays': date == null ? 0 : DateTime.now().difference(date).inDays.clamp(0, 1 << 31),
          'status': e['paymentStatus'] ?? 'Unpaid',
          'isOverdue': isWaterExpenseOverdue(e),
          'cashAccountId': e['waterCashAccountId'],
        },
        cashAccounts: _payAccounts,
        side: BalanceSide.supplier,
        sourceType: 'ExpenseEntry',
      ),
    ));
    if (ok == true) _load();
  }

  void _history(Map e) => showPaymentHistory(context,
      session: widget.session,
      company: widget.company,
      api: '/api/Water',
      partyId: tIntOrNull(e['supplierId']),
      partyName: tStr(e['supplierName']).isNotEmpty || tStr(e['paidTo']).isNotEmpty ? _partyName(e) : null,
      documentType: 'Expense',
      documentId: tIntOrNull(e['waterExpenseId']),
      canReverse: _canPay,
      onReversed: _load,
      side: BalanceSide.supplier);

  void _href(String href, String label) => openAppHref(context, widget.session, widget.company, href, label: label);

  Widget _sourceCell(Map e) {
    final s = waterExpenseSource(e);
    if (s == null) return const Text('—', style: TextStyle(color: TColors.slate400));
    if (s.$2 == null) return Text(s.$1, style: const TextStyle(fontSize: 12, color: TColors.slate500));
    return InkWell(onTap: () => _href(s.$2!, s.$1), child: Text(s.$1, style: const TextStyle(fontSize: 12, color: Color(0xFF4338CA))));
  }

  Widget _deliveryLink(Map d) {
    final lid = tIntOrNull(d['waterVehicleLoadingId']);
    if (lid == null || lid == 0) return const Text('Delivery', style: TextStyle(color: TColors.rose700));
    return InkWell(
      onTap: () => _href('/water-driver-returns/$lid', 'Delivery'),
      child: Text('Delivery #$lid', style: const TextStyle(color: TColors.rose700)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/water-expenses');
    final all = mergeWaterExpenses(_expenses, _deliveries);
    final byStatus = filterWaterExpenses(all, status: _status);
    final approved = byStatus.where((e) => e.status == 'Approved').fold<num>(0, (s, e) => s + tNum(e.row['amount']));
    final visible = filterWaterExpenses(all, status: _status, search: _search.text, from: _from, to: _to);
    if (visible.length != _lastTotal) {
      _lastTotal = visible.length;
      _page = 1;
    }
    final pageRows = pageSlice(visible, _page, _pageSize);
    Widget stat(String label, String value) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: TColors.slate900)),
          ]),
        );

    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Water expenses')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
          const Row(children: [
            Icon(Icons.receipt_outlined, size: 24, color: Color(0xFF0284C7)),
            SizedBox(width: 8),
            Expanded(child: Text('Water expenses', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900))),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(onPressed: _categoriesDialog, icon: const Icon(Icons.sell_outlined, size: 16), label: const Text('Categories')),
            FilledButton.icon(onPressed: _record, icon: const Icon(Icons.add, size: 16), label: const Text('Record expense')),
          ]),
          const SizedBox(height: 14),
          ListFiltersCard(
            search: _search,
            searchPlaceholder: 'Search category, description, paid to or notes',
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
            extras: [
              AppSelect<String>(
                value: _status,
                items: [
                  const AppSelectItem(value: 'ALL', label: 'All statuses'),
                  for (final s in waterExpenseStatuses) AppSelectItem(value: s, label: s),
                ],
                onChanged: (v) {
                  setState(() => _status = v ?? 'ALL');
                  _load();
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          twoUp([stat('Approved total', approved.toStringAsFixed(2)), stat('Rows shown', '${byStatus.length}')]),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(padding: EdgeInsets.all(16), child: LoadingLine('Loading…'))
          else if (all.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
              child: Text('No expenses ${_status != 'ALL' ? 'with status "$_status" ' : ''}yet.',
                  textAlign: TextAlign.center, style: const TextStyle(color: TColors.slate500)),
            )
          else if (visible.isNotEmpty)
            MobileCardList<WaterLedgerRow>(
              striped: true,
              items: pageRows,
              keyOf: (e) => e.key,
              primary: (e) => '${e.direct ? (tStr(e.row['categoryName']).isEmpty ? '—' : tStr(e.row['categoryName'])) : tStr(e.row['expenseCategory'])} · ${_f2(e.row['amount'])}',
              secondaryBuilder: (e) => Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(_day(e.date)),
                _statusBadge(e.status),
                TBadge(e.direct ? 'Direct' : 'Delivery', bg: Colors.white, fg: TColors.slate700, border: TColors.slate300),
              ]),
              highlights: (e) => [Highlight('Amount', _f2(e.row['amount']), accent: Accent.rose, wide: true)],
              details: (e) => e.direct
                  ? [
                      ('Date', fmtDateTime(e.row['expenseDate'], e.row, _offset)),
                      ('Category', tStr(e.row['categoryName']).isEmpty ? '—' : tStr(e.row['categoryName'])),
                      ('Paid to', waterPaidToLabel(e.row)),
                      ('Source', waterExpenseSource(e.row)?.$1 ?? '—'),
                      ('Method', tStr(e.row['paymentMethod'])),
                      ('Status', tStr(e.row['status'])),
                      ('Description', tStr(e.row['description']).isEmpty ? '—' : tStr(e.row['description'])),
                    ]
                  : [
                      ('Date', _day(e.date)),
                      ('Category', tStr(e.row['expenseCategory'])),
                      ('Paid to', tStr(e.row['driverName']).isEmpty ? '—' : tStr(e.row['driverName'])),
                      ('Source', tIntOrNull(e.row['waterVehicleLoadingId']) != null ? 'Delivery #${tStr(e.row['waterVehicleLoadingId'])}' : 'Delivery'),
                      ('Method', '—'),
                      ('Status', e.status),
                      ('Description', tStr(e.row['description']).isEmpty ? '—' : tStr(e.row['description'])),
                    ],
              detailTap: (e, label) {
                if (label != 'Source') return null;
                if (!e.direct) {
                  final lid = tIntOrNull(e.row['waterVehicleLoadingId']);
                  return lid == null ? null : () => _href('/water-driver-returns/$lid', 'Delivery');
                }
                final s = waterExpenseSource(e.row);
                return s?.$2 == null ? null : () => _href(s!.$2!, s.$1);
              },
              actions: (e) {
                if (!e.direct) return const [];
                final d = e.row, st = tStr(d['status']);
                return [
                  if (st == 'Draft') OutlinedButton(onPressed: () => _action(d, 'submit'), child: const Text('Submit')),
                  if (st == 'Draft' || st == 'Submitted')
                    OutlinedButton.icon(
                      onPressed: () => _action(d, 'approve'),
                      style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF15803D)),
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text('Approve'),
                    ),
                  if (st != 'Cancelled' && st != 'Rejected')
                    OutlinedButton.icon(
                      onPressed: () => _cancel(d),
                      style: OutlinedButton.styleFrom(foregroundColor: TColors.red600),
                      icon: const Icon(Icons.cancel_outlined, size: 16),
                      label: const Text('Cancel'),
                    ),
                ];
              },
              table: (items) => TrackerTable(
                columns: const [
                  TCol('Date', width: 130), TCol('Category', width: 120), TCol('Description', width: 180), TCol('Supplier / Paid to', width: 140),
                  TCol('Total', right: true, width: 90), TCol('Paid', right: true, width: 90), TCol('Balance', right: true, width: 90),
                  TCol('Payment', width: 110), TCol('Method', width: 80), TCol('Due', width: 100), TCol('Source', width: 170),
                  TCol('Status', width: 100), TCol('Actions', right: true, width: 220),
                ],
                rows: [
                  for (final e in items)
                    if (e.direct)
                      () {
                        final d = e.row, st = tStr(d['status']);
                        return <Widget>[
                          cellText(fmtDateTime(d['expenseDate'], d, _offset)),
                          cellText(tStr(d['categoryName']).isEmpty ? '—' : tStr(d['categoryName'])),
                          cellText(tStr(d['description']).isEmpty ? '—' : tStr(d['description'])),
                          cellText(waterPaidToLabel(d)),
                          Align(alignment: Alignment.centerRight, child: cellText(_f2(d['amount']))),
                          Align(alignment: Alignment.centerRight, child: cellText(_f2(d['amountPaid']), color: TColors.slate600)),
                          Align(
                            alignment: Alignment.centerRight,
                            child: cellText(_f2(d['balance']), bold: true, color: tNum(d['balance']) > 0 ? TColors.amber700 : TColors.slate400),
                          ),
                          Align(alignment: Alignment.centerLeft, child: waterPaymentBadge(d)),
                          cellText(tStr(d['paymentMethod'])),
                          cellText(d['dueDate'] == null ? '—' : _day(d['dueDate']), color: isWaterExpenseOverdue(d) ? TColors.red600 : TColors.slate600),
                          _sourceCell(d),
                          Align(alignment: Alignment.centerLeft, child: _statusBadge(st)),
                          Wrap(alignment: WrapAlignment.end, children: [
                            if (st == 'Draft') TextButton(onPressed: () => _action(d, 'submit'), child: const Text('Submit')),
                            if (st == 'Draft' || st == 'Submitted')
                              IconButton(
                                  tooltip: 'Approve',
                                  onPressed: () => _action(d, 'approve'),
                                  icon: const Icon(Icons.check_circle_outline, size: 18, color: Color(0xFF16A34A))),
                            if (_canPay && st == 'Approved' && tNum(d['balance']) > 0 && d['supplierId'] != null && tStr(d['sourceType']).isEmpty)
                              IconButton(
                                  tooltip: 'Record a payment against this bill',
                                  onPressed: () => _pay(d),
                                  icon: const Icon(Icons.payments_outlined, size: 18, color: TColors.emerald600)),
                            if (tNum(d['amountPaid']) > 0)
                              IconButton(tooltip: 'Payments applied to this bill', onPressed: () => _history(d), icon: const Icon(Icons.history, size: 18)),
                            if (st != 'Cancelled' && st != 'Rejected')
                              IconButton(tooltip: 'Cancel', onPressed: () => _cancel(d), icon: const Icon(Icons.cancel_outlined, size: 18, color: TColors.rose500)),
                          ]),
                        ];
                      }()
                    else
                      <Widget>[
                        cellText(_day(e.date)),
                        cellText(tStr(e.row['expenseCategory'])),
                        cellText(tStr(e.row['description']).isEmpty ? '—' : tStr(e.row['description'])),
                        cellText(tStr(e.row['driverName']).isEmpty ? '—' : tStr(e.row['driverName'])),
                        Align(alignment: Alignment.centerRight, child: cellText(_f2(e.row['amount']))),
                        Align(alignment: Alignment.centerRight, child: cellText(_f2(e.row['amount']), color: TColors.slate600)),
                        Align(alignment: Alignment.centerRight, child: cellText('0.00', color: TColors.slate400)),
                        const Align(alignment: Alignment.centerLeft, child: TBadge('Paid', bg: TColors.emerald100, fg: TColors.emerald800)),
                        cellText('—'),
                        cellText('—'),
                        _deliveryLink(e.row),
                        Align(alignment: Alignment.centerLeft, child: _statusBadge(e.status)),
                        const Align(alignment: Alignment.centerRight, child: Text('on return', style: TextStyle(fontSize: 12, color: TColors.slate400))),
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
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------ record

/// "Record water expense", as a page.
class _RecordWaterExpenseScreen extends StatefulWidget {
  const _RecordWaterExpenseScreen({required this.session, required this.company, required this.categories, required this.accounts});
  final Session session;
  final Company company;
  final List<Map> categories, accounts;
  @override
  State<_RecordWaterExpenseScreen> createState() => _RecordWaterExpenseScreenState();
}

class _RecordWaterExpenseScreenState extends State<_RecordWaterExpenseScreen> {
  late String _date = _todayLocal();
  late int _category = tIntOrNull(widget.categories.where((c) => c['isActive'] == true).firstOrNull?['waterExpenseCategoryId']) ?? 0;
  final _amount = TextEditingController(text: '0'), _paid = TextEditingController(), _desc = TextEditingController(),
      _paidTo = TextEditingController(), _notes = TextEditingController();
  String _method = 'Cash';
  String _state = 'Paid';
  String _due = '';
  int? _account;
  int? _supplier;
  List<Map> _suppliers = [];
  bool _suppliersLoading = true;
  bool _saving = false;

  ApiClient get _api => widget.session.farmClient;

  static String _todayLocal() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  num get _amountN => num.tryParse(_amount.text) ?? 0;

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
  }

  @override
  void dispose() {
    for (final c in [_amount, _paid, _desc, _paidTo, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSuppliers() async {
    try {
      final r = rowsOf(await _api.get('/api/Water/suppliers', query: {'farmId': widget.company.farmId}));
      if (mounted) setState(() => _suppliers = r);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load suppliers', description: e.message, error: true);
    }
    if (mounted) setState(() => _suppliersLoading = false);
  }

  /// Water encodes unpaid as Credit, so the two controls stay in step.
  void _setState(String next) {
    setState(() {
      _state = next;
      if (next == 'Unpaid') {
        _method = 'Credit';
        _account = null;
      } else if (_method == 'Credit') {
        _method = 'Cash';
      }
      if (next == 'Paid') _due = '';
    });
  }

  Future<void> _addSupplier() async {
    final created = await showDialog<Map>(context: context, builder: (_) => WaterAddSupplierDialog(session: widget.session, company: widget.company));
    if (created == null || !mounted) return;
    setState(() {
      _suppliers = [..._suppliers, created]..sort((a, b) => tStr(a['supplierName']).compareTo(tStr(b['supplierName'])));
      _supplier = tIntOrNull(created['waterSupplierId']);
    });
  }

  Future<void> _save() async {
    if (_category == 0) return trackerToast(context, 'Pick a category', error: true);
    if (_amountN <= 0) return trackerToast(context, 'Amount must be greater than zero', error: true);
    if (_method != 'Credit' && _account == null) return trackerToast(context, 'Cash account required for non-credit expenses', error: true);
    final paidNow = _state == 'PartiallyPaid' ? (num.tryParse(_paid.text) ?? 0) : 0;
    if (_state == 'PartiallyPaid' && (paidNow <= 0 || paidNow >= _amountN)) {
      return trackerToast(context, 'Enter how much of the bill has been paid',
          description: 'Something between 0 and ${_amountN.toStringAsFixed(2)}. Use Paid or Unpaid for the whole thing.', error: true);
    }
    if (_state != 'Paid' && _supplier == null) {
      trackerToast(context, 'No supplier picked', description: 'This bill will not appear in Supplier Balances.');
    }
    setState(() => _saving = true);
    try {
      final created = await _api.post('/api/Water/expenses', body: {
        'waterExpenseCategoryId': _category,
        'expenseDate': _date,
        'description': _desc.text,
        'amount': _amountN,
        'paidTo': _paidTo.text,
        'supplierId': _supplier,
        'paymentMethod': _method,
        'waterCashAccountId': _account,
        'notes': _notes.text,
        'farmId': widget.company.farmId,
        'createdBy': widget.session.tokens.userId,
      });
      final id = created is Map ? tStr(created['waterExpenseId']) : '';
      if (_state != 'Paid' || _due.isNotEmpty) {
        await _api.post('/api/Water/expenses/$id/payment', query: {'farmId': widget.company.farmId}, body: {
          'amountPaid': _state == 'Paid' ? null : paidNow,
          'dueDate': _due.isEmpty ? null : _due,
        });
      }
      if (!mounted) return;
      trackerToast(context, 'Expense recorded as Draft');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Save failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  Widget _num(TextEditingController c, {bool enabled = true, String? shown}) => AppInput(
        key: shown == null ? null : ValueKey('shown|$shown'),
        controller: shown == null ? c : null,
        initialValue: shown,
        enabled: enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
        onChanged: (_) => setState(() {}),
      );

  @override
  Widget build(BuildContext context) {
    final active = [for (final a in widget.accounts) if (a['isActive'] == true) a];
    final cats = [for (final c in widget.categories) if (c['isActive'] == true) c];
    return Scaffold(
      appBar: AppBar(title: const Text('Record water expense')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 28), children: [
        const Text('Log a new expense for review and approval', style: TextStyle(fontSize: 13, color: TColors.slate500)),
        const SizedBox(height: 12),
        formSection('Basics', const Color(0xFF4F46E5), [
          FilterLabel('Expense date *', FilterDate(value: _date, hint: 'Pick a date', onChanged: (v) => setState(() => _date = v))),
          const SizedBox(height: 8),
          FilterLabel(
            'Category *',
            AppSelect<int>(
              value: cats.any((c) => tIntOrNull(c['waterExpenseCategoryId']) == _category) ? _category : null,
              hintText: 'Pick category',
              items: [for (final c in cats) AppSelectItem(value: tIntOrNull(c['waterExpenseCategoryId']) ?? 0, label: tStr(c['name']))],
              onChanged: (v) => setState(() => _category = v ?? 0),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        formSection('Payment', TColors.amber600, [
          FilterLabel('Amount *', _num(_amount)),
          const SizedBox(height: 8),
          FilterLabel(
            'Payment method',
            AppSelect<String>(
              value: _method,
              items: [for (final (v, l) in waterExpenseMethods) AppSelectItem(value: v, label: l)],
              onChanged: (v) => setState(() => _method = v ?? _method),
            ),
          ),
          const SizedBox(height: 8),
          FilterLabel(
            'Payment status *',
            AppSelect<String>(
              value: _state,
              items: const [
                AppSelectItem(value: 'Paid', label: 'Paid'),
                AppSelectItem(value: 'PartiallyPaid', label: 'Partially paid'),
                AppSelectItem(value: 'Unpaid', label: 'Unpaid'),
              ],
              onChanged: (v) => _setState(v ?? 'Paid'),
            ),
          ),
          const SizedBox(height: 8),
          FilterLabel(
            'Amount paid${_state == 'PartiallyPaid' ? ' *' : ''}',
            _state == 'PartiallyPaid'
                ? _num(_paid)
                : _num(_paid, enabled: false, shown: _state == 'Paid' ? _amount.text : '0'),
          ),
          const SizedBox(height: 8),
          FilterLabel(
            'Due date',
            IgnorePointer(
              ignoring: _state == 'Paid',
              child: Opacity(
                opacity: _state == 'Paid' ? .5 : 1,
                child: FilterDate(value: _due, hint: 'Pick a date', onChanged: (v) => setState(() => _due = v)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          FilterLabel(
            'Cash account${_method != 'Credit' ? ' *' : ''}',
            AppSelect<int>(
              value: _account,
              hintText: _method == 'Credit' ? '(not required for credit)' : 'Pick account',
              items: [
                for (final a in active)
                  AppSelectItem(value: tIntOrNull(a['waterCashAccountId']) ?? 0, label: '${tStr(a['accountName'])} (${_f2(a['currentBalance'])})'),
              ],
              onChanged: (v) => setState(() => _account = v),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        formSection('Details', TColors.slate500, [
          FilterLabel('Description', AppInput(controller: _desc, hintText: 'e.g. Fuel for Truck 1')),
          const SizedBox(height: 8),
          FilterLabel(
            'Paid to (Supplier)',
            AppSelect<int>(
              value: _supplier ?? -1,
              hintText: _suppliersLoading ? 'Loading suppliers…' : 'Select supplier…',
              items: [
                const AppSelectItem(value: -1, label: 'No supplier / Other (use freetext below)'),
                for (final s in _suppliers)
                  AppSelectItem(
                    value: tIntOrNull(s['waterSupplierId']) ?? 0,
                    label: '${tStr(s['supplierName'])}${tStr(s['supplierType']).isNotEmpty ? ' · ${tStr(s['supplierType'])}' : ''}',
                  ),
                const AppSelectItem(value: -2, label: '+ Add new supplier…'),
              ],
              onChanged: (v) {
                if (v == -2) {
                  _addSupplier();
                } else {
                  setState(() => _supplier = v == null || v == -1 ? null : v);
                }
              },
            ),
          ),
          const SizedBox(height: 8),
          FilterLabel('Paid to (freetext, optional)', AppInput(controller: _paidTo, hintText: 'Used only if no supplier picked above')),
          const SizedBox(height: 8),
          FilterLabel('Notes', AppTextarea(controller: _notes)),
        ]),
        const SizedBox(height: 16),
        Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
          FilledButton(style: FilledButton.styleFrom(backgroundColor: TColors.red600), onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save as Draft')),
        ]),
      ]),
    );
  }
}

/// SupplierSelect's "Add supplier" quick-add.
class WaterAddSupplierDialog extends StatefulWidget {
  const WaterAddSupplierDialog({super.key, required this.session, required this.company, this.defaultType = 'Other'});
  final Session session;
  final Company company;

  /// SupplierSelect's defaultNewSupplierType.
  final String defaultType;
  @override
  State<WaterAddSupplierDialog> createState() => _WaterAddSupplierDialogState();
}

class _WaterAddSupplierDialogState extends State<WaterAddSupplierDialog> {
  final _name = TextEditingController(), _contact = TextEditingController(), _phone = TextEditingController(), _email = TextEditingController();
  late String _type = widget.defaultType;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _contact, _phone, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return trackerToast(context, 'Supplier name is required', error: true);
    setState(() => _saving = true);
    try {
      final created = await widget.session.farmClient.post('/api/Water/suppliers', body: {
        'supplierName': _name.text,
        'supplierType': _type,
        'contactPerson': _contact.text,
        'phone': _phone.text,
        'email': _email.text,
        'farmId': widget.company.farmId,
        'createdBy': widget.session.tokens.userId,
      });
      if (!mounted) return;
      final row = created is Map ? created : <String, dynamic>{};
      trackerToast(context, 'Supplier added', description: tStr(row['supplierName']));
      Navigator.pop(context, row);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not save supplier', description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: const Text('Add supplier'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Quick-add. You can fill in the rest of the details from the Suppliers page later.',
              style: TextStyle(fontSize: 13, color: TColors.slate500)),
          const SizedBox(height: 12),
          FilterLabel('Supplier name *', AppInput(controller: _name, hintText: 'e.g. Goil Station, ECG, Acme Spare Parts')),
          const SizedBox(height: 8),
          FilterLabel(
            'Supplier type',
            AppSelect<String>(
              value: _type,
              items: [for (final t in waterSupplierTypes) AppSelectItem(value: t, label: t)],
              onChanged: (v) => setState(() => _type = v ?? 'Other'),
            ),
          ),
          const SizedBox(height: 8),
          FilterLabel('Contact person', AppInput(controller: _contact)),
          const SizedBox(height: 8),
          FilterLabel('Phone', AppInput(controller: _phone)),
          const SizedBox(height: 8),
          FilterLabel('Email', AppInput(controller: _email, keyboardType: TextInputType.emailAddress)),
        ]),
        actions: [
          OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.add, size: 16),
            label: Text(_saving ? 'Saving…' : 'Add supplier'),
          ),
        ],
      );
}

/// "Expense categories": the existing list and Add new.
class _CategoriesDialog extends StatefulWidget {
  const _CategoriesDialog({required this.session, required this.company, required this.categories, required this.onAdded});
  final Session session;
  final Company company;
  final List<Map> categories;
  final Future<void> Function() onAdded;
  @override
  State<_CategoriesDialog> createState() => _CategoriesDialogState();
}

class _CategoriesDialogState extends State<_CategoriesDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (_name.text.trim().isEmpty) return;
    try {
      await widget.session.farmClient.post('/api/Water/expense-categories', body: {'name': _name.text.trim(), 'farmId': widget.company.farmId, 'isActive': true});
      if (!mounted) return;
      Navigator.pop(context);
      await widget.onAdded();
      if (mounted) trackerToast(context, 'Category added');
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Add failed', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: const Row(children: [
          Icon(Icons.sell_outlined, color: Color(0xFF2563EB)),
          SizedBox(width: 8),
          Flexible(child: Text('Expense categories')),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Manage the categories used to organise expenses', style: TextStyle(fontSize: 13, color: TColors.slate500)),
          const SizedBox(height: 12),
          formSection('Existing categories', const Color(0xFF4F46E5), [
            for (final c in widget.categories)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(4)),
                child: Row(children: [
                  Expanded(child: Text(tStr(c['name']))),
                  if (c['isActive'] != true) const TBadge('inactive', bg: Colors.white, fg: TColors.slate700, border: TColors.slate300),
                ]),
              ),
          ]),
          const SizedBox(height: 10),
          formSection('Add new', TColors.emerald600, [
            Row(children: [
              Expanded(child: AppInput(controller: _name, hintText: 'New category name')),
              const SizedBox(width: 8),
              FilledButton(onPressed: _add, child: const Text('Add')),
            ]),
          ]),
        ]),
      );
}
