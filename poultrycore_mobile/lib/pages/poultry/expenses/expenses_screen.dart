// Poultry → Expenses (app/expenses/page.tsx), at phone width: the search box,
// the Filters sheet (dates, flock, month, category, PDF / CSV), This Month and
// Total (Filtered), cards with Edit / Delete, the table with Pay, History, Cost
// breakdown and Supplier balance, and the Add / Edit Expense dialog with its
// payment-status rules (lib/expenses/payment-status.ts).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../shared/business_dates.dart';
import '../../shared/company_clock.dart';
import '../money/money_widgets.dart' show formSection, redCancelButton;
import '../reports/report_export.dart';
import '../reports/report_format.dart';
import '../reports/report_routes.dart' show openAppHref;
import '../sales/balances_logic.dart' show BalanceSide, toPesewas, fromPesewas;
import '../sales/balances_widgets.dart' show RecordPaymentScreen;
import '../sales/sale_dialogs.dart' show showPaymentHistory;
import '../sales/sales_logic.dart' show pageNumbers, salePageSizes;
import '../trackers/tracker_logic.dart'
    show tNum, tStr, tIntOrNull, trackerDate, localDateKey, sortRows, toggleSort, SortState;
import '../trackers/tracker_widgets.dart';
import 'deferred_costs_screen.dart' show noSecondPaymentTooltip;
import 'receipt_field.dart';

// ------------------------------------------------------------ receipts (lib/utils/expense-receipt.ts)

final _receiptSuffix = RegExp(r'\s*::rcpt:(/receipt-uploads/[^\s]+)::\s*$', caseSensitive: false);

String? receiptPathOf(Object? description) {
  final m = _receiptSuffix.firstMatch(tStr(description));
  final p = m?.group(1)?.trim();
  return p == null || p.isEmpty ? null : p;
}

String stripReceipt(Object? description) => tStr(description).replaceAll(_receiptSuffix, '').trimRight();

String appendReceipt(String description, String path) => '${stripReceipt(description).trimRight()}\n::rcpt:${path.trim()}::';

/// toReceiptViewUrl: a stored `/receipt-uploads/...` path is served by the web's
/// `/api/receipt-file/...` route.
String? receiptViewUrl(String? stored, String? farmId) {
  final raw = (stored ?? '').trim();
  if (raw.isEmpty) return null;
  if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
  final p = raw.startsWith('/') ? raw : '/$raw';
  if (p.startsWith('/receipt-uploads/')) return '/api/receipt-file/${p.replaceFirst(RegExp(r'^/+'), '')}';
  final farm = (farmId ?? '').trim();
  final uuid = RegExp(r'^/([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\.(png|jpe?g|webp)$', caseSensitive: false);
  if (farm.isNotEmpty) {
    final um = uuid.firstMatch(p);
    if (um != null) {
      final ext = um[2]!.toLowerCase() == 'jpeg' ? 'jpg' : um[2]!.toLowerCase();
      return '/api/receipt-file/receipt-uploads/$farm/${um[1]}.$ext';
    }
  }
  final ff = RegExp(r'^/([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})/([^/\s]+)$', caseSensitive: false).firstMatch(p);
  if (ff != null) return '/api/receipt-file/receipt-uploads/${ff[1]}/${ff[2]}';
  return p;
}

// ------------------------------------------------------------ payment status (lib/expenses/payment-status.ts)

const expenseCategories = ['Feed', 'Veterinary', 'Equipment', 'Labor', 'Utilities', 'Other'];
const expensePaymentMethods = ['Cash', 'Mobile Money', 'Credit Card', 'Bank Transfer', 'Check', 'Other'];
const selectablePaymentStatuses = ['Paid', 'PartiallyPaid', 'Unpaid'];
const paymentStatusLabels = {'Paid': 'Paid', 'PartiallyPaid': 'Partially paid', 'Unpaid': 'Unpaid', 'NonCash': 'Non-cash'};

/// Null for Paid (the API's "paid in full"), 0 for Unpaid, the entry for PartiallyPaid.
num? amountPaidForStatus(String status, num enteredPaid) => switch (status) {
      'Paid' => null,
      'Unpaid' => 0,
      _ => fromPesewas(toPesewas(enteredPaid)),
    };

bool requiresCashAccount(String status) => status == 'Paid' || status == 'PartiallyPaid';

/// validateExpensePayment's errors, in its order (the warning is left out:
/// the form shows it as an alert of its own).
List<String> expensePaymentErrors({
  required num total,
  required String status,
  required num amountPaid,
  String? paymentMethod,
  int? cashAccountId,
}) {
  final out = <String>[];
  final totalP = toPesewas(total);
  final resolved = amountPaidForStatus(status, amountPaid);
  final paidP = resolved == null ? totalP : toPesewas(resolved);
  if (totalP <= 0) out.add('Enter an amount greater than 0.');
  if (paidP < 0) out.add('Amount paid cannot be negative.');
  if (paidP > totalP && totalP > 0) out.add('Amount paid cannot exceed the ${fromPesewas(totalP).toStringAsFixed(2)} total.');
  if (status == 'PartiallyPaid' && paidP <= 0) out.add('A partially paid expense must have something paid against it.');
  if (status == 'PartiallyPaid' && paidP >= totalP && totalP > 0) out.add('That settles the whole bill — choose "Paid" instead.');
  if (requiresCashAccount(status)) {
    if (cashAccountId == null || cashAccountId == 0) out.add('Choose the cash account this money came out of.');
    if ((paymentMethod ?? '').trim().isEmpty) out.add('Choose a payment method.');
  }
  return out;
}

bool isPayableExpense(Map e) => tNum(e['balance']) > 0 && tStr(e['paymentStatus']) != 'NonCash' && (tIntOrNull(e['supplierId']) ?? 0) != 0;

bool isConsumptionExpense(Map e) =>
    tStr(e['sourceType']) == 'PoultryFeedConsumption' || tStr(e['sourceType']) == 'PoultryMedicationConsumption';

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

bool isOverdueExpense(Map e, [DateTime? today]) {
  final due = DateTime.tryParse(tStr(e['dueDate']));
  return due != null && tNum(e['balance']) > 0 && due.toLocal().isBefore(today ?? _today());
}

/// renderPaymentStatus's words.
String expenseStatusLabel(Map e, [DateTime? today]) {
  if (tStr(e['paymentStatus']) == 'NonCash') return 'Non-cash';
  if (tNum(e['balance']) <= 0) return 'Paid';
  if (isOverdueExpense(e, today)) return 'Overdue';
  if (tNum(e['amountPaid']) > 0) return 'Partially paid';
  return 'Unpaid';
}

// ------------------------------------------------------------ filters

class ExpenseFilters {
  String search = '', from = '', to = '', flock = 'all', month = 'all', category = 'all', cashAccount = 'all';
  int? focusId;
}

DateTime? _localDate(Object? v) => DateTime.tryParse(tStr(v))?.toLocal();

String _paidTo(Map e) => tStr(e['paidTo'] ?? e['supplier']);

List<Map> filterExpenses(List<Map> rows, ExpenseFilters f) {
  final q = f.search.trim().toLowerCase();
  return rows.where((e) {
    if (q.isNotEmpty) {
      final flockStr = tStr(e['flockId']);
      final idStr = tStr(e['expenseId']);
      final qNum = int.tryParse(q.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      final numeric = qNum > 0 && (flockStr == '$qNum' || idStr == '$qNum');
      final hit = stripReceipt(e['description']).toLowerCase().contains(q) ||
          tStr(e['category']).toLowerCase().contains(q) ||
          tStr(e['paymentMethod']).toLowerCase().contains(q) ||
          _paidTo(e).toLowerCase().contains(q) ||
          flockStr.contains(q) ||
          idStr.contains(q) ||
          numeric;
      if (!hit) return false;
    }
    final day = localDateKey(e['expenseDate']);
    if (f.from.isNotEmpty && day.compareTo(f.from) < 0) return false;
    if (f.to.isNotEmpty && day.compareTo(f.to) > 0) return false;
    if (f.flock != 'all' && tStr(e['flockId']) != f.flock) return false;
    if (f.month != 'all' && _localDate(e['expenseDate'])?.month != int.tryParse(f.month)) return false;
    if (f.category != 'all' && tStr(e['category']).toLowerCase() != f.category.toLowerCase()) return false;
    if (f.cashAccount == 'none' && e['poultryCashAccountId'] != null) return false;
    if (f.cashAccount != 'all' && f.cashAccount != 'none' && tStr(e['poultryCashAccountId']) != f.cashAccount) return false;
    if (f.focusId != null && tIntOrNull(e['expenseId']) != f.focusId) return false;
    return true;
  }).toList();
}

const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

(Color, Color) categoryColors(Object? c) => switch (tStr(c)) {
      'Feed' => (const Color(0xFFDCFCE7), const Color(0xFF166534)),
      'Veterinary' => (const Color(0xFFFEE2E2), const Color(0xFF991B1B)),
      'Equipment' => (const Color(0xFFDBEAFE), const Color(0xFF1E40AF)),
      'Labor' => (const Color(0xFFFEF9C3), const Color(0xFF854D0E)),
      'Utilities' => (const Color(0xFFF3E8FF), const Color(0xFF6B21A8)),
      _ => (const Color(0xFFF3F4F6), const Color(0xFF1F2937)),
    };

String _n2(num n) {
  final s = n.abs().toStringAsFixed(2);
  final parts = s.split('.');
  final whole = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return '${n < 0 ? '-' : ''}$whole.${parts[1]}';
}

// ------------------------------------------------------------ screen

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key, required this.session, required this.company, this.focusExpenseId, this.cashAccount});
  final Session session;
  final Company company;

  /// `?expenseId=`: the list narrowed to one expense.
  final int? focusExpenseId;

  /// `?cashAccount=`: an account id, or `none`.
  final String? cashAccount;

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  List<Map> _rows = [], _flocks = [], _batches = [], _suppliers = [], _accounts = [];
  bool _loading = true, _flocksLoading = true, _table = false;
  String _error = '';
  final _search = TextEditingController();
  final _f = ExpenseFilters();
  SortState _sort = (key: null, dir: null);
  int _page = 1, _perPage = 10;
  FarmMoney _fmt = const FarmMoney();
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  String get _userId => widget.session.tokens.userId ?? '';

  /// The web gates Pay / Reverse on poultry.supplier-payments.*; the app has no
  /// permission flags, so the Staff role is the one left out.
  bool get _canPay => (widget.company.role ?? '').toLowerCase() != 'staff';

  @override
  void initState() {
    super.initState();
    _f.focusId = widget.focusExpenseId;
    final ca = widget.cashAccount;
    if (ca != null && ca.isNotEmpty) _f.cashAccount = ca;
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _fmt = m);
    });
    CompanyClock.load(widget.session, widget.company).then((c) {
      if (mounted) setState(() => _offset = c.offset);
    });
    _load();
    _loadLookups();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Map<String, String> get _ctx => {'userId': _userId, 'farmId': _farmId};

  Future<void> _load() async {
    try {
      final res = await _api.get('/api/Expense', query: _ctx);
      if (mounted) setState(() => _rows = rowsOf(res));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message.isNotEmpty ? e.message : 'Failed to load expenses');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadLookups() async {
    Future<List<Map>> list(String path, Map<String, String> q) async {
      try {
        return rowsOf(await _api.get(path, query: q));
      } on ApiException {
        return <Map>[];
      }
    }

    final r = await Future.wait([
      list('/api/Flock', _ctx),
      list('/api/MainFlockBatch', _ctx),
      list('/api/Supplier', _ctx),
      list('/api/Poultry/cash-accounts', {'farmId': _farmId}),
    ]);
    if (!mounted) return;
    setState(() {
      _flocks = r[0];
      _batches = r[1];
      _suppliers = r[2];
      _accounts = [
        for (final a in r[3])
          if (a['isActive'] == true)
            {
              'id': a['poultryCashAccountId'],
              'name': a['accountName'],
              'currentBalance': a['currentBalance'],
              'allowNegativeBalance': a['allowNegativeBalance'],
            },
      ];
      _flocksLoading = false;
    });
  }

  List<String> get _usedDescriptions =>
      ({for (final e in _rows) stripReceipt(e['description']).trim()}..remove('')).toList()..sort((a, b) => a.compareTo(b));

  int get _activeCount => [
        _f.search.isNotEmpty, _f.from.isNotEmpty, _f.to.isNotEmpty,
        _f.flock != 'all', _f.month != 'all', _f.category != 'all', _f.cashAccount != 'all',
      ].where((b) => b).length;

  List<Map> _sorted(List<Map> rows) => sortRows(rows, _sort, (e, k) => switch (k) {
        'expenseDate' => DateTime.tryParse(tStr(e['expenseDate'])),
        'amount' || 'amountPaid' || 'balance' => tNum(e[k]),
        'description' => stripReceipt(e['description']),
        _ => e[k],
      });

  // ------------------------------------------------------------ actions

  Future<void> _openForm([int? expenseId]) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => ExpenseFormDialog(
        session: widget.session,
        company: widget.company,
        expenseId: expenseId,
        flocks: _flocks,
        batches: _batches,
        flocksLoading: _flocksLoading,
        suppliers: _suppliers,
        accounts: _accounts,
        descriptionOptions: expenseId == null ? _usedDescriptions : null,
      ),
    );
    if (ok == true) _load();
  }

  Future<void> _delete(Map e) async {
    final desc = stripReceipt(e['description']);
    final yes = await confirmDelete(context,
        title: 'Delete expense?',
        description: desc.isNotEmpty ? 'This will permanently remove “$desc”.' : 'This action cannot be undone.');
    if (!yes || !mounted) return;
    final id = tIntOrNull(e['expenseId']) ?? 0;
    final farm = tStr(e['farmId']).isNotEmpty ? tStr(e['farmId']) : _farmId;
    try {
      await _api.delete('/api/Expense/$id?userId=${Uri.encodeQueryComponent(_userId)}&farmId=${Uri.encodeQueryComponent(farm)}');
      if (!mounted) return;
      setState(() => _rows = _rows.where((r) => tIntOrNull(r['expenseId']) != id).toList());
      trackerToast(context, 'Expense deleted', description: 'Record has been removed.');
    } on ApiException catch (ex) {
      if (!mounted) return;
      final msg = ex.message.isNotEmpty ? ex.message : 'Failed to delete expense';
      setState(() => _error = msg);
      trackerToast(context, 'Delete failed', description: msg);
    }
  }

  Map _asOpenDocument(Map e) {
    final d = DateTime.tryParse(tStr(e['expenseDate']));
    final label = stripReceipt(e['description']);
    return {
      'documentType': 'Expense',
      'documentId': e['expenseId'],
      'reference': 'E${tStr(e['expenseId'])}',
      'documentDate': e['expenseDate'],
      'label': label.isNotEmpty ? label : tStr(e['category']),
      'totalAmount': e['amount'],
      'amountPaid': e['amountPaid'],
      'balance': e['balance'],
      'dueDate': e['dueDate'],
      'ageDays': d == null ? 0 : DateTime.now().difference(d).inDays.clamp(0, 1 << 31),
      'status': e['paymentStatus'],
      'isOverdue': isOverdueExpense(e),
      'cashAccountId': e['poultryCashAccountId'],
    };
  }

  String _partyName(Map e) {
    for (final v in [e['supplierName'], e['paidTo']]) {
      if (v != null) return tStr(v);
    }
    return 'Supplier';
  }

  Future<void> _pay(Map e) async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => RecordPaymentScreen(
        session: widget.session,
        company: widget.company,
        party: {'partyId': e['supplierId'], 'partyName': _partyName(e)},
        single: _asOpenDocument(e),
        cashAccounts: _accounts,
        side: BalanceSide.supplier,
        sourceType: 'ExpenseEntry',
      ),
    ));
    if (ok == true) _load();
  }

  void _history(Map e) => showPaymentHistory(context,
      session: widget.session,
      company: widget.company,
      partyId: tIntOrNull(e['supplierId']),
      partyName: e['supplierName'] != null || e['paidTo'] != null ? _partyName(e) : null,
      documentType: 'Expense',
      documentId: tIntOrNull(e['expenseId']),
      canReverse: _canPay,
      onReversed: _load,
      side: BalanceSide.supplier);

  void _breakdown(Map e) => showCostBreakdown(context,
      session: widget.session,
      company: widget.company,
      productionRecordId: tIntOrNull(e['sourceId']) ?? 0,
      money: _fmt,
      title: 'What this expense is made of');

  void _href(String href, String label) => openAppHref(context, widget.session, widget.company, href, label: label);

  void _receipt(Map e) {
    final url = receiptViewUrl(receiptPathOf(e['description']), tStr(e['farmId']));
    if (url != null) _href(url, 'Receipt');
  }

  // ------------------------------------------------------------ export

  List<List<String>> _pdfRows(List<Map> rows) => [
        for (final e in rows)
          [
            tStr(e['expenseId']),
            fmtDateTime(e['expenseDate'], e, _offset),
            tStr(e['category']),
            stripReceipt(e['description']),
            _n2(tNum(e['amount'])),
            tStr(e['paymentMethod']),
          ],
      ];

  Future<void> _exportPdf(List<Map> rows) async {
    if (rows.isEmpty) {
      trackerToast(context, 'Nothing to export', description: 'No expenses match the current filters.', error: true);
      return;
    }
    final total = rows.fold<num>(0, (s, e) => s + tNum(e['amount']));
    try {
      await ReportExport.sharePdf(ReportDocument(
        title: 'Expenses Report',
        filename: 'expenses',
        farmName: widget.company.name,
        sections: [
          ReportSection(
            columns: const [
              ReportColumn('ID'), ReportColumn('Date'), ReportColumn('Category'), ReportColumn('Description'),
              ReportColumn('Amount', right: true), ReportColumn('Payment'),
            ],
            rows: _pdfRows(rows),
            totals: ['', '', '', 'Total (Filtered)', _n2(total), ''],
          ),
        ],
        notes: ['Total (Filtered): ${_n2(total)}'],
      ));
    } catch (_) {
      if (mounted) trackerToast(context, 'PDF export failed', description: 'Could not generate PDF. Please try again.', error: true);
    }
  }

  Future<void> _exportCsv(List<Map> rows) {
    const headers = ['ExpenseId', 'ExpenseDate', 'Category', 'Description', 'Amount', 'PaymentMethod', 'PaidTo', 'FlockId'];
    String esc(String v) => v.contains(',') || v.contains('"') || v.contains('\n') ? '"${v.replaceAll('"', '""')}"' : v;
    final lines = [
      headers.join(','),
      for (final e in rows)
        [
          tStr(e['expenseId']),
          DateTime.tryParse(tStr(e['expenseDate']))?.toUtc().toIso8601String().substring(0, 10) ?? '',
          tStr(e['category']),
          stripReceipt(e['description']).replaceAll(RegExp(r'\n|\r'), ' '),
          tStr(e['amount']),
          tStr(e['paymentMethod']),
          _paidTo(e),
          tStr(e['flockId']),
        ].map(esc).join(','),
    ];
    return ReportExport.sharer('expenses-${DateTime.now().toUtc().toIso8601String().substring(0, 10)}.csv',
        utf8.encode(lines.join('\n')), 'text/csv', 'Expenses');
  }

  // ------------------------------------------------------------ filters sheet

  Future<void> _openFilters(List<Map> filtered) async {
    var from = _f.from, to = _f.to, flock = _f.flock, month = _f.month, category = _f.category;
    final categories = <String>{for (final e in _rows) if (tStr(e['category']).isNotEmpty) tStr(e['category'])}.toList();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final changed = from != _f.from || to != _f.to || flock != _f.flock || month != _f.month || category != _f.category;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Filters', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 14),
              const Text('Date range', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate700)),
              const SizedBox(height: 10),
              FilterLabel('Start date', FilterDate(value: from, hint: 'Start date', onChanged: (v) => set(() => from = v))),
              const SizedBox(height: 12),
              FilterLabel('End date', FilterDate(value: to, hint: 'End date', onChanged: (v) => set(() => to = v))),
              const SizedBox(height: 14),
              FilterLabel(
                'Flock',
                AppSelect<String>(
                  value: flock,
                  items: [
                    const AppSelectItem(value: 'all', label: 'All Flocks'),
                    for (final fl in _flocks) AppSelectItem(value: tStr(fl['flockId']), label: tStr(fl['name'])),
                  ],
                  onChanged: (v) => set(() => flock = v ?? 'all'),
                ),
              ),
              const SizedBox(height: 12),
              FilterLabel(
                'Month',
                AppSelect<String>(
                  value: month,
                  items: [
                    const AppSelectItem(value: 'all', label: 'All Months'),
                    for (var i = 0; i < 12; i++) AppSelectItem(value: '${i + 1}', label: _months[i]),
                  ],
                  onChanged: (v) => set(() => month = v ?? 'all'),
                ),
              ),
              const SizedBox(height: 12),
              FilterLabel(
                'Category',
                AppSelect<String>(
                  value: category,
                  items: [
                    const AppSelectItem(value: 'all', label: 'All Category'),
                    for (final c in categories) AppSelectItem(value: c, label: c),
                  ],
                  onChanged: (v) => set(() => category = v ?? 'all'),
                ),
              ),
              const SizedBox(height: 18),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                    onPressed: () => _exportPdf(filtered),
                    icon: const Icon(Icons.description_outlined, size: 16),
                    label: const Text('PDF'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                    onPressed: () => _exportCsv(filtered),
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text('CSV'),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: () {
                      // The web's mobile "Clear all" leaves a ?cashAccount= filter in place.
                      setState(() {
                        _search.clear();
                        _f
                          ..search = ''
                          ..from = ''
                          ..to = ''
                          ..flock = 'all'
                          ..month = 'all'
                          ..category = 'all';
                        _page = 1;
                      });
                      Navigator.pop(ctx);
                      trackerToast(context, 'Filters cleared');
                    },
                    child: const Text('Clear all'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: !changed
                        ? null
                        : () {
                            setState(() {
                              _f
                                ..from = from
                                ..to = to
                                ..flock = flock
                                ..month = month
                                ..category = category;
                              _page = 1;
                            });
                            Navigator.pop(ctx);
                            trackerToast(context, 'Filters applied', description: 'Expense list updated.');
                          },
                    child: const Text('Apply'),
                  ),
                ),
              ]),
            ]),
          ),
        );
      }),
    );
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/expenses');
    final filtered = filterExpenses(_rows, _f);
    final sorted = _sorted(filtered);
    final totalPages = sorted.isEmpty ? 1 : (sorted.length + _perPage - 1) ~/ _perPage;
    final page = _page.clamp(1, totalPages);
    final start = (page - 1) * _perPage;
    final pageRows = sorted.sublist(start.clamp(0, sorted.length), (start + _perPage).clamp(0, sorted.length));
    final now = DateTime.now();
    final thisMonth = _rows.where((e) {
      final d = _localDate(e['expenseDate']);
      return d != null && d.month == now.month && d.year == now.year;
    }).fold<num>(0, (s, e) => s + tNum(e['amount']));
    final filteredTotal = filtered.fold<num>(0, (s, e) => s + tNum(e['amount']));

    Widget figure(String label, String value) => TCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: TColors.slate900)),
            ),
          ]),
        );

    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Expenses')),
      body: _loading
          ? const Center(child: TrackerLoading('Loading expenses...'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
                children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: TColors.red100, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.attach_money, size: 20, color: TColors.red600),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Expenses', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: TColors.slate900)),
                        Text('Track operational costs and financial records', style: TextStyle(fontSize: 13, color: TColors.slate600)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: TColors.blue600, minimumSize: const Size.fromHeight(44)),
                    onPressed: () => _openForm(),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Expense'),
                  ),
                  const SizedBox(height: 16),
                  if (_f.focusId != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F9FF),
                        border: Border.all(color: const Color(0xFFBAE6FD)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, children: [
                        Text('Showing expense #${_f.focusId} only.', style: const TextStyle(fontSize: 13, color: Color(0xFF0C4A6E))),
                        OutlinedButton(
                          onPressed: () => setState(() => _f.focusId = null),
                          child: const Text('Show all expenses'),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_error.isNotEmpty) ...[
                    TrackerBanner.error(_error),
                    const SizedBox(height: 12),
                  ],
                  AppInput(
                    controller: _search,
                    hintText: 'Search expenses...',
                    prefixIcon: const Icon(Icons.search, size: 18, color: TColors.slate400),
                    onChanged: (v) => setState(() {
                      _f.search = v;
                      _page = 1;
                    }),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                    onPressed: () => _openFilters(filtered),
                    icon: const Icon(Icons.filter_list, size: 18),
                    label: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Flexible(child: Text('Filters', overflow: TextOverflow.ellipsis)),
                      if (_activeCount > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(color: const Color(0xFFF97316), borderRadius: BorderRadius.circular(999)),
                          child: Text('$_activeCount', style: const TextStyle(fontSize: 12, color: Colors.white)),
                        ),
                      ],
                    ]),
                  ),
                  const SizedBox(height: 16),
                  figure('This Month', _fmt(thisMonth)),
                  const SizedBox(height: 12),
                  figure('Total (Filtered)', _fmt(filteredTotal)),
                  const SizedBox(height: 16),
                  if (filtered.isEmpty)
                    TCard(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 30),
                        child: Column(children: [
                          const Icon(Icons.attach_money, size: 48, color: TColors.slate400),
                          const SizedBox(height: 14),
                          const Text('No expenses found', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Text(
                            _f.search.isNotEmpty || _f.from.isNotEmpty || _f.to.isNotEmpty
                                ? 'No expenses match your search criteria.'
                                : 'Start tracking your farm expenses.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: TColors.slate600),
                          ),
                          const SizedBox(height: 18),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: TColors.blue600),
                            onPressed: () => _openForm(),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add First Expense'),
                          ),
                        ]),
                      ),
                    )
                  else
                    TCard(
                      title: 'Expenses',
                      description: 'Manage your farm expenses',
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        if (!_table) ...[
                          for (var i = 0; i < pageRows.length; i++) ...[_card(pageRows[i], i), const SizedBox(height: 10)],
                          ViewTableButton(onPressed: () => setState(() => _table = true)),
                        ] else ...[
                          TableViewBar(text: 'Table • Scroll → for more', onCards: () => setState(() => _table = false)),
                          _tableView(pageRows),
                        ],
                        _pagination(sorted.length, page, totalPages, start),
                      ]),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _categoryBadge(Map e) {
    final (bg, fg) = categoryColors(e['category']);
    return TBadge(tStr(e['category']), bg: bg, fg: fg);
  }

  Widget _statusBadge(Map e) {
    final st = expenseStatusLabel(e);
    final (bg, fg, border) = switch (st) {
      'Non-cash' => (Colors.white, TColors.slate600, TColors.slate300),
      'Paid' => (TColors.emerald100, TColors.emerald800, null),
      'Overdue' => (TColors.red100, TColors.red800, null),
      'Partially paid' => (TColors.amber100, TColors.amber800, null),
      _ => (TColors.slate100, TColors.slate700, null),
    };
    return TBadge(st, bg: bg, fg: fg, border: border);
  }

  Widget _receiptIcon(Map e) => receiptPathOf(e['description']) == null
      ? const SizedBox.shrink()
      : IconButton(
          tooltip: 'View receipt',
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.image_outlined, size: 16, color: TColors.blue600),
          onPressed: () => _receipt(e),
        );

  Widget _card(Map e, int i) {
    Widget kv(String l, String v) => Wrap(spacing: 4, children: [
          Text(l, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
          Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ]);
    final validId = (tIntOrNull(e['expenseId']) ?? 0) > 0;
    return _ExpenseCard(
      key: ValueKey('expense-${e['expenseId']}-$i'),
      striped: i.isEven,
      header: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(trackerDate(e['expenseDate']), style: const TextStyle(fontWeight: FontWeight.w600, color: TColors.slate900)),
          _categoryBadge(e),
        ]),
        const SizedBox(height: 4),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Text(_fmt(tNum(e['amount'])), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: TColors.red600)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(stripReceipt(e['description']),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: TColors.slate600)),
          ),
          _receiptIcon(e),
        ]),
      ]),
      details: Row(children: [
        Expanded(child: kv('Payment', tStr(e['paymentMethod']).isEmpty ? 'N/A' : tStr(e['paymentMethod']))),
        Expanded(child: kv('Paid to', tStr(e['paidTo']).isEmpty ? 'N/A' : tStr(e['paidTo']))),
      ]),
      actions: Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(backgroundColor: Colors.white, minimumSize: const Size.fromHeight(40)),
            onPressed: validId ? () => _openForm(tIntOrNull(e['expenseId'])) : null,
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('Edit'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: TColors.red600,
              side: const BorderSide(color: TColors.red200),
              minimumSize: const Size.fromHeight(40),
            ),
            onPressed: () => _delete(e),
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('Delete'),
          ),
        ),
      ]),
    );
  }

  Widget _tableView(List<Map> rows) {
    IconButton icon(String tip, IconData i, VoidCallback? onTap, {Color? color}) => IconButton(
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
          padding: EdgeInsets.zero,
          icon: Icon(i, size: 18, color: color),
          onPressed: onTap,
        );
    return TrackerTable(
      sort: _sort,
      onSort: (k) => setState(() => _sort = toggleSort(k, _sort)),
      columns: const [
        TCol('Date', sortKey: 'expenseDate', width: 100),
        TCol('Description', sortKey: 'description', width: 220),
        TCol('Category', sortKey: 'category', width: 120),
        TCol('Supplier / Paid To', sortKey: 'paidTo', width: 140),
        TCol('Total', sortKey: 'amount', right: true, width: 110),
        TCol('Paid', sortKey: 'amountPaid', right: true, width: 110),
        TCol('Balance', sortKey: 'balance', right: true, width: 110),
        TCol('Status', sortKey: 'paymentStatus', width: 120),
        TCol('Method', sortKey: 'paymentMethod', width: 120),
        TCol('Actions', width: 230),
      ],
      rows: [
        for (final e in rows)
          [
            cellText(trackerDate(e['expenseDate'])),
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Flexible(child: Text(stripReceipt(e['description']), style: const TextStyle(fontWeight: FontWeight.w500))),
                _receiptIcon(e),
              ]),
              if (tStr(e['notes']).isNotEmpty) Text(tStr(e['notes']), style: const TextStyle(fontSize: 13, color: TColors.slate500)),
              if (isConsumptionExpense(e)) ...[
                const Tooltip(
                  message: noSecondPaymentTooltip,
                  child: Text('Inventory cost recognition', style: TextStyle(fontSize: 10, color: TColors.slate500)),
                ),
                if ((tIntOrNull(e['sourceId']) ?? 0) != 0)
                  InkWell(
                    onTap: () => _breakdown(e),
                    child: const Text('View cost breakdown',
                        style: TextStyle(fontSize: 10, color: TColors.sky700, decoration: TextDecoration.underline)),
                  ),
              ],
            ]),
            Align(alignment: Alignment.centerLeft, child: _categoryBadge(e)),
            cellText(tStr(e['supplierName']).isNotEmpty
                ? tStr(e['supplierName'])
                : (tStr(e['paidTo']).isNotEmpty ? tStr(e['paidTo']) : 'N/A'),
                color: TColors.slate600),
            cellText(_fmt(tNum(e['amount'])), bold: true),
            cellText(_fmt(tNum(e['amountPaid'])), color: TColors.slate600),
            cellText(_fmt(tNum(e['balance'])), color: tNum(e['balance']) > 0 ? TColors.amber700 : TColors.slate400, bold: true),
            Align(alignment: Alignment.centerLeft, child: _statusBadge(e)),
            Align(
              alignment: Alignment.centerLeft,
              child: TBadge(tStr(e['paymentMethod']).isEmpty ? 'N/A' : tStr(e['paymentMethod']),
                  bg: Colors.white, fg: TColors.slate800, border: TColors.slate200),
            ),
            Wrap(alignment: WrapAlignment.end, children: [
              icon('Edit', Icons.edit_outlined,
                  (tIntOrNull(e['expenseId']) ?? 0) > 0 ? () => _openForm(tIntOrNull(e['expenseId'])) : null),
              if (_canPay && isPayableExpense(e))
                icon('Record a payment against this expense', Icons.payments_outlined, () => _pay(e), color: TColors.emerald700),
              if (tNum(e['amountPaid']) > 0) icon('Payments applied to this expense', Icons.history, () => _history(e)),
              if (isConsumptionExpense(e) && (tIntOrNull(e['sourceId']) ?? 0) != 0)
                icon('How this cost was worked out', Icons.layers_outlined, () => _breakdown(e), color: TColors.sky700),
              if ((tIntOrNull(e['supplierId']) ?? 0) != 0)
                icon("Open this supplier's balance", Icons.local_shipping_outlined, () => _href('/supplier-balances', 'Supplier Balances')),
              icon('Delete', Icons.delete_outline, () => _delete(e), color: TColors.red600),
            ]),
          ],
      ],
    );
  }

  Widget _pagination(int total, int page, int totalPages, int start) {
    final end = (start + _perPage).clamp(0, total);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: const BoxDecoration(color: TColors.slate50, border: Border(top: BorderSide(color: TColors.slate200))),
      child: Column(children: [
        Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 6, children: [
          Text('Showing ${start + 1} to $end of $total records', style: const TextStyle(fontSize: 13, color: TColors.slate600)),
          SizedBox(
            width: 120,
            child: AppSelect<int>(
              value: _perPage,
              items: [for (final n in salePageSizes) AppSelectItem(value: n, label: '$n / page')],
              onChanged: (v) => setState(() {
                _perPage = v ?? _perPage;
                _page = 1;
              }),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 2, children: [
          TextButton.icon(
            onPressed: page == 1 ? null : () => setState(() => _page = page - 1),
            icon: const Icon(Icons.chevron_left, size: 18),
            label: const Text('Previous'),
          ),
          for (final p in pageNumbers(page, totalPages))
            p == 'ellipsis'
                ? const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('…'))
                : SizedBox(
                    width: 36,
                    height: 36,
                    child: p == page
                        ? OutlinedButton(style: OutlinedButton.styleFrom(padding: EdgeInsets.zero), onPressed: () {}, child: Text('$p'))
                        : TextButton(
                            style: TextButton.styleFrom(padding: EdgeInsets.zero),
                            onPressed: () => setState(() => _page = p as int),
                            child: Text('$p'),
                          ),
                  ),
          TextButton.icon(
            onPressed: page == totalPages ? null : () => setState(() => _page = page + 1),
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.chevron_right, size: 18),
            label: const Text('Next'),
          ),
        ]),
      ]),
    );
  }
}

/// One expense card: open by default, amber on even rows as the web stripes them.
class _ExpenseCard extends StatefulWidget {
  const _ExpenseCard({super.key, required this.striped, required this.header, required this.details, required this.actions});
  final bool striped;
  final Widget header, details, actions;
  @override
  State<_ExpenseCard> createState() => _ExpenseCardState();
}

class _ExpenseCardState extends State<_ExpenseCard> {
  bool _open = true;
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: widget.striped ? TColors.amber100 : Colors.white,
          border: Border.all(color: widget.striped ? TColors.amber300 : TColors.slate200),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: widget.header),
              Icon(_open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: TColors.slate400),
            ]),
          ),
          if (_open) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: TColors.slate100),
            const SizedBox(height: 12),
            widget.details,
            const SizedBox(height: 12),
            widget.actions,
          ],
        ]),
      );
}

// ------------------------------------------------------------ Add / Edit Expense

class ExpenseFormDialog extends StatefulWidget {
  const ExpenseFormDialog({
    super.key,
    required this.session,
    required this.company,
    this.expenseId,
    required this.flocks,
    required this.batches,
    required this.flocksLoading,
    required this.suppliers,
    required this.accounts,
    this.descriptionOptions,
  });
  final Session session;
  final Company company;

  /// Null = Add Expense.
  final int? expenseId;
  final List<Map> flocks, batches, suppliers, accounts;
  final bool flocksLoading;

  /// The used descriptions; given on create only, where the description is a
  /// select with "Other (type your own)". Edit gets a plain text box.
  final List<String>? descriptionOptions;

  @override
  State<ExpenseFormDialog> createState() => _ExpenseFormDialogState();
}

class _ExpenseFormDialogState extends State<ExpenseFormDialog> {
  static const _all = 'ALL', _other = 'Other';

  bool get _edit => widget.expenseId != null;
  bool _fetching = false, _saving = false;
  String _error = '';

  String _batch = _all, _flock = '', _category = '', _method = '', _account = '', _supplier = '', _status = 'Paid', _due = '';
  late String _date = isoDay(DateTime.now().toUtc());
  final _amount = TextEditingController(), _paid = TextEditingController(), _desc = TextEditingController(), _note = TextEditingController();
  String _descChoice = '';
  String? _savedReceipt;
  ReceiptImage? _pendingReceipt;
  bool _hasDbAttachment = false;
  String _farm = '';
  FarmMoney _money = const FarmMoney();

  String get _userId => widget.session.tokens.userId ?? '';

  @override
  void initState() {
    super.initState();
    _farm = widget.company.farmId;
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _money = m);
    });
    if (_edit) _fetch();
  }

  @override
  void dispose() {
    for (final c in [_amount, _paid, _desc, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() => _fetching = true);
    try {
      final res = await widget.session.farmClient
          .get('/api/Expense/${widget.expenseId}', query: {'userId': _userId, 'farmId': widget.company.farmId});
      final e = res is Map && res['data'] is Map ? res['data'] as Map : res as Map;
      final raw = tStr(e['description']);
      _savedReceipt = receiptPathOf(raw);
      _hasDbAttachment = e['hasAttachmentImage'] == true;
      if (tStr(e['farmId']).isNotEmpty) _farm = tStr(e['farmId']);
      final st = tStr(e['paymentStatus']);
      setState(() {
        _flock = (tIntOrNull(e['flockId']) ?? 0) != 0 ? tStr(e['flockId']) : _all;
        _date = DateTime.tryParse(tStr(e['expenseDate']))?.toUtc().toIso8601String().substring(0, 10) ?? _date;
        _category = tStr(e['category']);
        _desc.text = stripReceipt(raw);
        _amount.text = tStr(e['amount']);
        _method = tStr(e['paymentMethod']);
        _account = (tIntOrNull(e['poultryCashAccountId']) ?? 0) != 0 ? tStr(e['poultryCashAccountId']) : '';
        _supplier = (tIntOrNull(e['supplierId']) ?? 0) != 0 ? tStr(e['supplierId']) : '';
        _status = st == 'PartiallyPaid' || st == 'Unpaid' ? st : 'Paid';
        _paid.text = tStr(e['amountPaid'] ?? e['amount']);
        _due = DateTime.tryParse(tStr(e['dueDate']))?.toUtc().toIso8601String().substring(0, 10) ?? '';
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message.isNotEmpty ? e.message : 'Failed to load expense');
    } on TypeError {
      setState(() => _error = 'Failed to load expense');
    }
    if (mounted) setState(() => _fetching = false);
  }

  String get _description => widget.descriptionOptions != null
      ? (_descChoice == _other ? _note.text.trim() : _descChoice)
      : _desc.text;

  List<Map> get _flockOptions => [
        for (final f in widget.flocks)
          if (f['flockId'] != null && tStr(f['name']).isNotEmpty && (_batch == _all || tStr(f['batchId']) == _batch)) f,
      ];

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = '';
    });
    String? guide;
    final amount = num.tryParse(_amount.text) ?? 0;
    if (_flock.isEmpty) {
      _error = 'Choose a flock';
      guide = 'Select which flock this expense belongs to (or the closest match from the list).';
    } else if (_category.isEmpty) {
      _error = 'Choose a category';
      guide = 'Pick an expense category so reports and cash stay organized.';
    } else if (_description.trim().isEmpty) {
      _error = 'Add a short description';
      guide = 'Add a few words describing what this expense was for — it helps later when you search.';
    } else if (_amount.text.isEmpty || amount <= 0) {
      _error = 'Enter amount';
      guide = 'Enter the amount spent as a number greater than zero.';
    } else if (_method.isEmpty && requiresCashAccount(_status)) {
      _error = 'Choose payment method';
      guide = 'Select how this was paid (cash, mobile money, bank, etc.).';
    } else {
      final errs = expensePaymentErrors(
        total: amount,
        status: _status,
        amountPaid: num.tryParse(_paid.text) ?? 0,
        paymentMethod: _method,
        cashAccountId: int.tryParse(_account),
      );
      if (errs.isNotEmpty) _error = guide = errs.first;
    }
    if (guide != null) {
      trackerToast(context, 'Almost there', description: guide);
      setState(() => _saving = false);
      return;
    }

    var description = _description.trim();
    final pending = _pendingReceipt;
    if (pending != null) {
      final up = await uploadExpenseReceipt(widget.session, pending, _edit ? _farm : widget.company.farmId);
      if (!mounted) return;
      if (!up.ok) {
        setState(() {
          _error = (up.message ?? '').isNotEmpty ? up.message! : 'Receipt upload failed';
          _saving = false;
        });
        return;
      }
      description = appendReceipt(description, up.path!);
    } else if (_edit && _savedReceipt != null) {
      description = appendReceipt(description, _savedReceipt!);
    }
    final body = <String, Object?>{
      'farmId': _edit ? _farm : widget.company.farmId,
      'userId': _userId,
      'expenseDate': '${_date}T00:00:00Z',
      'category': _category,
      'description': description,
      'amount': amount,
      if (!_edit || _method.isNotEmpty) 'paymentMethod': _method,
      'flockId': _flock == _all ? null : int.tryParse(_flock),
      'poultryCashAccountId': requiresCashAccount(_status) && _account.isNotEmpty ? int.tryParse(_account) : null,
      'supplierId': _supplier.isEmpty ? null : int.tryParse(_supplier),
      'amountPaid': amountPaidForStatus(_status, num.tryParse(_paid.text) ?? 0),
      'dueDate': _due.isEmpty ? null : _due,
    };
    try {
      if (_edit) {
        await widget.session.farmClient.put('/api/Expense/${widget.expenseId}', body: body);
      } else {
        await widget.session.farmClient.post('/api/Expense', body: body);
      }
      if (!mounted) return;
      trackerToast(context, 'Success!', description: _edit ? 'Expense updated successfully.' : 'Expense created successfully.');
      Navigator.pop(context, true);
      return;
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _saving = false);
  }

  Widget _field(String label, Widget child, {String? hint}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate700)),
          const SizedBox(height: 6),
          child,
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(hint, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          ],
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final busy = _saving;
    final money = num.tryParse(_amount.text) ?? 0;
    final paidShown = _status == 'PartiallyPaid' ? null : (_status == 'Paid' ? _amount.text : '0');
    final balance = (money - (_status == 'Paid' ? money : _status == 'Unpaid' ? 0 : (num.tryParse(_paid.text) ?? 0))).clamp(0, double.infinity);
    final flockOpts = _flockOptions;
    final decimal = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];

    return AlertDialog(
      scrollable: true,
      title: Row(children: [
        Icon(_edit ? Icons.edit_outlined : Icons.attach_money, size: 20, color: _edit ? TColors.blue600 : TColors.emerald600),
        const SizedBox(width: 8),
        Text(_edit ? 'Edit Expense' : 'Add Expense'),
      ]),
      content: SizedBox(
        width: 640,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_edit ? 'Update expense information' : 'Record a new farm expense',
              style: const TextStyle(fontSize: 13, color: TColors.slate500)),
          const SizedBox(height: 12),
          if (_error.isNotEmpty) ...[
            TrackerBanner.error(_error),
            const SizedBox(height: 12),
          ],
          if (_fetching)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Column(children: [
                CircularProgressIndicator(),
                SizedBox(height: 8),
                Text('Loading expense...', style: TextStyle(color: TColors.slate600)),
              ]),
            )
          else ...[
            formSection('Flock & Date', const Color(0xFF4F46E5), [
              _field(
                'Batch',
                AppSelect<String>(
                  value: _batch,
                  hintText: 'All batches',
                  items: [
                    const AppSelectItem(value: _all, label: 'All batches'),
                    for (final b in widget.batches)
                      if (b['batchId'] != null)
                        AppSelectItem(
                          value: tStr(b['batchId']),
                          label: tStr(b['batchName']).isNotEmpty
                              ? tStr(b['batchName'])
                              : (tStr(b['batchCode']).isNotEmpty ? tStr(b['batchCode']) : 'Batch #${b['batchId']}'),
                        ),
                  ],
                  onChanged: (v) => setState(() {
                    _batch = v ?? _all;
                    if (_batch != _all && _flock.isNotEmpty && _flock != _all && !_flockOptions.any((f) => tStr(f['flockId']) == _flock)) {
                      _flock = '';
                    }
                  }),
                ),
                hint: 'Filters flocks below.',
              ),
              _field(
                'Select Flock *',
                AppSelect<String>(
                  value: _flock.isEmpty ? null : _flock,
                  hintText: 'Choose a flock',
                  items: [
                    const AppSelectItem(value: _all, label: 'All flocks (farm-wide)'),
                    for (final f in flockOpts) AppSelectItem(value: tStr(f['flockId']), label: tStr(f['name'])),
                  ],
                  onChanged: (v) => setState(() => _flock = v ?? ''),
                ),
                hint: widget.flocksLoading
                    ? 'Loading flocks...'
                    : flockOpts.isEmpty
                        ? (widget.flocks.isEmpty
                            ? 'No flocks in the database for this farm. Add a flock on the Flocks page first.'
                            : 'Flocks could not be loaded. Check your connection and try again.')
                        : null,
              ),
              _field(
                'Expense Date *',
                AppDateField(
                  value: businessDateAsDateTime(_date),
                  enabled: !busy,
                  onChanged: (v) => setState(() => _date = v == null ? '' : isoDay(v)),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            formSection('Category & Payment', const Color(0xFF16A34A), [
              _field(
                'Category *',
                AppSelect<String>(
                  value: _category.isEmpty ? null : _category,
                  hintText: 'Select category',
                  items: [for (final c in expenseCategories) AppSelectItem(value: c, label: c)],
                  onChanged: (v) => setState(() => _category = v ?? ''),
                ),
              ),
              _field(
                'Amount *',
                AppInput(
                  controller: _amount,
                  hintText: '0.00',
                  enabled: !busy,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: decimal,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              _field(
                'Payment Method *',
                AppSelect<String>(
                  value: _method.isEmpty ? null : _method,
                  hintText: 'Select payment method',
                  items: [for (final m in expensePaymentMethods) AppSelectItem(value: m, label: m)],
                  onChanged: (v) => setState(() => _method = v ?? ''),
                ),
              ),
              _field(
                'Pay from cash account',
                AppSelect<String>(
                  value: _account.isEmpty ? 'none' : _account,
                  enabled: !busy,
                  items: [
                    const AppSelectItem(value: 'none', label: 'None (no cash movement)'),
                    for (final a in widget.accounts)
                      AppSelectItem(value: tStr(a['id']), label: '${tStr(a['name'])} (${tNum(a['currentBalance']).toStringAsFixed(2)})'),
                  ],
                  onChanged: (v) => setState(() => _account = v == null || v == 'none' ? '' : v),
                ),
                hint: 'Posts a cash-out and reduces the account balance.',
              ),
            ]),
            const SizedBox(height: 12),
            formSection('Supplier & Payment Status', const Color(0xFF0284C7), [
              _field(
                'Supplier / Paid To',
                AppSelect<String>(
                  value: _supplier.isEmpty ? 'none' : _supplier,
                  enabled: !busy,
                  items: [
                    const AppSelectItem(value: 'none', label: 'Not linked to a supplier'),
                    for (final s in widget.suppliers) AppSelectItem(value: tStr(s['supplierId']), label: tStr(s['name'])),
                  ],
                  onChanged: (v) => setState(() => _supplier = v == null || v == 'none' ? '' : v),
                ),
              ),
              _field(
                'Payment Status *',
                AppSelect<String>(
                  value: _status,
                  enabled: !busy,
                  items: [for (final s in selectablePaymentStatuses) AppSelectItem(value: s, label: paymentStatusLabels[s]!)],
                  onChanged: (v) => setState(() => _status = v ?? 'Paid'),
                ),
              ),
              _field(
                'Amount Paid${_status == 'PartiallyPaid' ? ' *' : ''}',
                paidShown == null
                    ? AppInput(
                        controller: _paid,
                        hintText: '0.00',
                        enabled: !busy,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: decimal,
                        onChanged: (_) => setState(() {}),
                      )
                    : AppInput(key: ValueKey('paid-$_status-$paidShown'), initialValue: paidShown, hintText: '0.00', enabled: false),
                hint: 'Balance: ${_money(balance)}',
              ),
              _field(
                'Due Date',
                AppDateField(
                  value: businessDateAsDateTime(_due),
                  hintText: 'Pick a date',
                  enabled: !busy && _status != 'Paid',
                  onChanged: (v) => setState(() => _due = v == null ? '' : isoDay(v)),
                ),
                hint: "Overrides the supplier's payment terms.",
              ),
              if (_status != 'Paid' && _supplier.isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
                  child: const Text('Select a supplier if you want this unpaid expense to appear in Supplier Balances.',
                      style: TextStyle(fontSize: 13, color: TColors.slate700)),
                ),
            ]),
            const SizedBox(height: 12),
            formSection('Description', const Color(0xFFD97706), [
              if (widget.descriptionOptions != null) ...[
                AppSelect<String>(
                  value: _descChoice.isEmpty ? null : _descChoice,
                  enabled: !busy,
                  hintText: 'What was this expense for?',
                  items: [
                    for (final o in widget.descriptionOptions!) AppSelectItem(value: o, label: o),
                    const AppSelectItem(value: _other, label: '$_other (type your own)'),
                  ],
                  onChanged: (v) => setState(() {
                    _descChoice = v ?? '';
                    if (_descChoice != _other) _note.clear();
                  }),
                ),
                if (_descChoice == _other) ...[
                  const SizedBox(height: 8),
                  AppInput(controller: _note, autofocus: true, enabled: !busy, hintText: 'Enter your description', onChanged: (_) => setState(() {})),
                ],
              ] else
                AppInput(controller: _desc, enabled: !busy, maxLines: 3, minLines: 3, hintText: 'Enter expense description...'),
              const SizedBox(height: 12),
              _receiptSlot(),
            ]),
          ],
        ]),
      ),
      actions: [
        redCancelButton(() => Navigator.pop(context, false)),
        FilledButton.icon(
          onPressed: busy || widget.flocksLoading || _fetching ? null : _submit,
          icon: busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Icon(_edit ? Icons.edit_outlined : Icons.attach_money, size: 16),
          label: Text(busy ? (_edit ? 'Saving...' : 'Creating...') : (_edit ? 'Save Changes' : 'Create Expense')),
        ),
      ],
    );
  }


  Widget _receiptSlot() => ExpenseReceiptField(
        session: widget.session,
        existingUrl: receiptViewUrl(_savedReceipt, _farm),
        dbAttachment: _edit && _hasDbAttachment && _userId.isNotEmpty
            ? ReceiptDbAttachment(expenseId: widget.expenseId!, userId: _userId, farmId: _farm)
            : null,
        pending: _pendingReceipt,
        onPending: (f) => setState(() => _pendingReceipt = f),
        onRemoveExisting: _edit ? () => setState(() => _savedReceipt = null) : null,
        disabled: _saving,
      );
}

/// `/expenses?expenseId=` and `/expenses?cashAccount=` open the list narrowed.
Widget? expensesScreenForHref(String href, Session s, Company c) {
  final uri = Uri.tryParse(href);
  if (uri == null || uri.path != '/expenses' || uri.query.isEmpty) return null;
  final id = int.tryParse(uri.queryParameters['expenseId'] ?? '');
  return ExpensesScreen(
    session: s,
    company: c,
    focusExpenseId: id != null && id > 0 ? id : null,
    cashAccount: uri.queryParameters['cashAccount'],
  );
}
