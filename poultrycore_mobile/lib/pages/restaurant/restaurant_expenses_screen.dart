// Restaurant → Expenses → Expenses, as `app/restaurant-expenses/page.tsx`:
// Poultry's layout in rose. The list with search and a Filters sheet, two
// summary cards, Record / Edit Expense with the Supplier & Payment Status band
// (migration 329/337), Delete, and the Categories tab.
// API: /Restaurant/expenses, /expenses/categories, /expenses/payments,
// /setup/suppliers and /finance/accounts.

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/expenses/expenses_screen.dart'
    show amountPaidForStatus, requiresCashAccount, selectablePaymentStatuses, paymentStatusLabels;
import '../poultry/money/money_widgets.dart';
import '../poultry/reports/report_format.dart' show FarmMoney;
import '../poultry/sales/balances_logic.dart' show pageSlice;
import '../poultry/sales/balances_widgets.dart' show CompactPager, LoadingLine;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart';
import 'restaurant_money_kit.dart';
import 'restaurant_roles.dart' show restaurantRose;
import 'restaurant_widgets.dart';

const restaurantExpensePaymentMethods = ['Cash', 'Card', 'Bank Transfer', 'MobileMoney', 'Cheque'];

/// fmtShortDate: "Sep 28, 26", read off the yyyy-mm-dd string.
String fmtShortDate(Object? d) {
  final p = tStr(d).split('T').first.split('-');
  if (p.length < 3 || p.any((x) => x.isEmpty)) return tStr(d).isEmpty ? '—' : tStr(d);
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final m = int.tryParse(p[1]);
  final mon = m != null && m >= 1 && m <= 12 ? months[m - 1] : p[1];
  return '$mon ${int.tryParse(p[2]) ?? p[2]}, ${p[0].length >= 2 ? p[0].substring(2) : p[0]}';
}

/// The list's filters: focus, category, the date range and the search.
List<Map> filterRestaurantExpenses(List<Map> expenses, Map<int, Map> payments,
    {int? focusId, String category = 'all', String from = '', String to = '', String search = ''}) {
  final q = search.trim().toLowerCase();
  return [
    for (final e in expenses)
      if ((focusId == null || tIntOrNull(e['expenseId']) == focusId) &&
          (category == 'all' || (tStr(e['categoryName']).isEmpty ? 'Uncategorized' : tStr(e['categoryName'])) == category) &&
          (from.isEmpty || _day(e['expenseDate']).compareTo(from) >= 0) &&
          (to.isEmpty || _day(e['expenseDate']).compareTo(to) <= 0) &&
          (q.isEmpty ||
              [e['description'], e['categoryName'], e['supplierName'], payments[tIntOrNull(e['expenseId'])]?['supplierName'], e['receiptRef']]
                  .map((x) => x == null ? '' : '$x')
                  .join(' ')
                  .toLowerCase()
                  .contains(q)))
        e,
  ];
}

String _day(Object? d) => tStr(d).length >= 10 ? tStr(d).substring(0, 10) : tStr(d);

const _statusBadge = {
  'Paid': (TColors.emerald50, TColors.emerald700, TColors.emerald200),
  'PartiallyPaid': (TColors.amber50, TColors.amber700, TColors.amber200),
  'Unpaid': (Color(0xFFFEF2F2), Color(0xFFB91C1C), Color(0xFFFECACA)),
};

class RestaurantExpensesScreen extends StatefulWidget {
  const RestaurantExpensesScreen({super.key, required this.session, required this.company, this.focusExpenseId, this.categoriesTab = false});
  final Session session;
  final Company company;

  /// `?expenseId=` (from Supplier Balances / Payments): the list narrowed to one bill.
  final int? focusExpenseId;

  /// `?tab=categories`.
  final bool categoriesTab;

  @override
  State<RestaurantExpensesScreen> createState() => _RestaurantExpensesScreenState();
}

class _RestaurantExpensesScreenState extends State<RestaurantExpensesScreen> {
  bool _loading = true;
  List<Map> _expenses = [], _categories = [], _accounts = [], _suppliers = [];
  Map<int, Map> _payments = {};
  late String _tab = widget.categoriesTab ? 'categories' : 'expenses';
  late int? _focusId = widget.focusExpenseId;
  final _search = TextEditingController();
  final _newCategory = TextEditingController();
  String _from = '', _to = '', _category = 'all';
  int _page = 1, _pageSize = 25;
  FarmMoney _gh = const FarmMoney();

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  String _r(String path, [Map<String, Object?> query = const {}]) {
    final q = {'farmId': _farmId};
    query.forEach((k, v) {
      if (v != null && '$v' != '') q[k] = '$v';
    });
    return Uri(path: '/api/Restaurant$path', queryParameters: q).toString();
  }

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
    _newCategory.dispose();
    super.dispose();
  }

  Future<Object?> _soft(Future<Object?> f) async {
    try {
      return await f;
    } on ApiException {
      return const [];
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await Future.wait<Object?>([
        _api.get(_r('/expenses', {'_': '1', 'from': _from, 'to': _to})),
        _api.get(_r('/expenses/categories')),
        _soft(loadRestaurantAccounts(_api, _farmId)),
        _soft(_api.get(_r('/expenses/payments', {'from': _from, 'to': _to}))),
        _soft(_api.get(_r('/setup/suppliers'))),
      ]);
      if (!mounted) return;
      setState(() {
        _expenses = rowsOf(r[0]);
        _categories = rowsOf(r[1]);
        _accounts = [for (final a in rowsOf(r[2])) if (a['isActive'] == true) a];
        _payments = {for (final p in rowsOf(r[3])) if (tIntOrNull(p['expenseId']) != null) tIntOrNull(p['expenseId'])!: p};
        _suppliers = [for (final s in rowsOf(r[4])) if (s['isactive'] != false) s];
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Error loading data', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  int get _activeFilterCount => [_from, _to, _category != 'all' ? 'x' : ''].where((x) => x.isNotEmpty).length;

  void _clearFilters() => setState(() {
        _search.clear();
        _category = 'all';
        _from = '';
        _to = '';
        _page = 1;
      });

  Future<void> _openFilters(List<String> categoryOptions) async {
    var from = _from, to = _to, category = _category;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Filters', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 14),
              const Text('Date range', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate700)),
              const SizedBox(height: 10),
              rField('Start date', rDateInput(from, (v) => set(() => from = v))),
              const SizedBox(height: 12),
              rField('End date', rDateInput(to, (v) => set(() => to = v))),
              const SizedBox(height: 14),
              rField(
                'Category',
                AppSelect<String>(
                  value: category,
                  items: [
                    const AppSelectItem(value: 'all', label: 'All categories'),
                    for (final c in categoryOptions) AppSelectItem(value: c, label: c),
                  ],
                  onChanged: (v) => set(() => category = v ?? 'all'),
                ),
              ),
              const SizedBox(height: 18),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: () {
                      _clearFilters();
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
                    onPressed: () {
                      setState(() {
                        _from = from;
                        _to = to;
                        _category = category;
                        _page = 1;
                      });
                      Navigator.pop(ctx);
                    },
                    child: const Text('Apply'),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _expenseDialog([Map? editing]) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _ExpenseDialog(
        api: _api,
        farmId: _farmId,
        editing: editing,
        payment: editing == null ? null : _payments[tIntOrNull(editing['expenseId'])],
        categories: _categories,
        accounts: _accounts,
        suppliers: _suppliers,
        gh: _gh,
      ),
    );
    if (done == true) _load();
  }

  Future<void> _delete(Map e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text('Delete this expense? The money is put back into the account it was paid from.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.delete(_r('/expenses/${tIntOrNull(e['expenseId'])}'));
      if (mounted) trackerToast(context, 'Deleted', description: 'Expense removed and its money returned to the account.');
      _load();
    } on ApiException catch (err) {
      if (mounted) trackerToast(context, 'Error', description: err.message.isEmpty ? 'Failed to delete.' : err.message, error: true);
    }
  }

  Future<void> _addCategory() async {
    final name = _newCategory.text.trim();
    if (name.isEmpty) return;
    try {
      await _api.post(_r('/expenses/categories'), body: {'name': name});
      if (mounted) trackerToast(context, 'Success', description: 'Category added.');
      _newCategory.clear();
      _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Error', description: e.message.isEmpty ? 'Failed to add category.' : e.message, error: true);
    }
  }

  Future<void> _deleteCategory(Map c) async {
    try {
      await _api.delete(_r('/expenses/categories/${tIntOrNull(c['expenseCategoryId'])}'));
      if (mounted) trackerToast(context, 'Deleted', description: 'Category removed.');
      _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Error', description: e.message.isEmpty ? 'Failed to delete category.' : e.message, error: true);
    }
  }

  String _paidTo(Map e) {
    final p = _payments[tIntOrNull(e['expenseId'])];
    final s = tStr(p?['supplierName']).isNotEmpty ? tStr(p?['supplierName']) : tStr(e['supplierName']);
    return s;
  }

  Widget _statusChip(Map p) {
    final st = tStr(p['paymentStatus']);
    final (bg, fg, border) = _statusBadge[st] ?? (Colors.white, TColors.slate700, TColors.slate200);
    return rStatusBadge(paymentStatusLabels[st] ?? st, bg: bg, fg: fg, border: border);
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/restaurant-expenses');
    Widget body;
    if (_loading) {
      body = const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: LoadingLine('Loading…')));
    } else {
      final filtered =
          filterRestaurantExpenses(_expenses, _payments, focusId: _focusId, category: _category, from: _from, to: _to, search: _search.text);
      final filteredTotal = filtered.fold<num>(0, (s, e) => s + tNum(e['amount']));
      final month = DateTime.now().toUtc().toIso8601String().substring(0, 7);
      final monthTotal = _expenses.where((e) => tStr(e['expenseDate']).startsWith(month)).fold<num>(0, (s, e) => s + tNum(e['amount']));
      final categoryOptions = {for (final e in _expenses) tStr(e['categoryName']).isEmpty ? 'Uncategorized' : tStr(e['categoryName'])}.toList()..sort();
      if ((_page - 1) * _pageSize >= filtered.length && _page > 1) _page = 1;
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        RPageHeader(
          icon: Icons.attach_money,
          title: 'Expenses',
          subtitle: 'Track operational costs and financial records',
          actions: [
            OutlinedButton.icon(
              onPressed: () => setState(() => _tab = _tab == 'categories' ? 'expenses' : 'categories'),
              icon: const Icon(Icons.sell_outlined, size: 16),
              label: Text(_tab == 'categories' ? 'Expenses' : 'Categories'),
            ),
            roseButton('Add Expense', () => _expenseDialog()),
          ],
        ),
        const SizedBox(height: 14),
        if (_tab == 'expenses') ...[
          if (_focusId != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(color: TColors.rose50, border: Border.all(color: TColors.rose200), borderRadius: BorderRadius.circular(8)),
              child: Wrap(spacing: 12, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('Showing expense #$_focusId only.', style: const TextStyle(fontSize: 13, color: Color(0xFF881337))),
                OutlinedButton(onPressed: () => setState(() => _focusId = null), child: const Text('Show all expenses')),
              ]),
            ),
            const SizedBox(height: 12),
          ],
          AppInput(controller: _search, hintText: 'Search expenses...', prefixIcon: const Icon(Icons.search, size: 18), onChanged: (_) => setState(() => _page = 1)),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => _openFilters(categoryOptions),
              icon: const Icon(Icons.filter_list, size: 16),
              label: Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('Filters'),
                if (_activeFilterCount > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(color: const Color(0xFFF97316), borderRadius: BorderRadius.circular(999)),
                    child: Text('$_activeFilterCount', style: const TextStyle(fontSize: 12, color: Colors.white)),
                  ),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 14),
          _summary('This Month', _gh(monthTotal)),
          const SizedBox(height: 12),
          _summary('Total (Filtered)', _gh(filteredTotal)),
          const SizedBox(height: 14),
          if (_expenses.isEmpty)
            TCard(
              child: REmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'No expenses recorded yet',
                description: "Track your restaurant's daily expenses and costs",
                actionLabel: 'Record First Expense',
                onAction: () => _expenseDialog(),
              ),
            )
          else if (filtered.isEmpty)
            const TCard(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 36),
                child: Column(children: [
                  Icon(Icons.attach_money, size: 48, color: TColors.slate400),
                  SizedBox(height: 12),
                  Text('No expenses found', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: TColors.slate900)),
                  SizedBox(height: 6),
                  Text('No expenses match your search criteria.', style: TextStyle(color: TColors.slate600)),
                ]),
              ),
            )
          else
            TCard(
              title: 'Expenses',
              description: 'Manage your restaurant expenses',
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
              child: MobileCardList<Map>(
                items: pageSlice(filtered, _page, _pageSize),
                striped: true,
                keyOf: (e) => '${e['expenseId']}',
                primary: (e) => fmtShortDate(e['expenseDate']),
                trailing: (e) => tStr(e['categoryName']).isEmpty
                    ? null
                    : rStatusBadge(tStr(e['categoryName']), bg: const Color(0xFFFFE4E6), fg: TColors.rose700, border: TColors.rose200),
                secondaryBuilder: (e) => Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                  Text(_gh(tNum(e['amount'])), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: TColors.red600)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(tStr(e['description']), overflow: TextOverflow.ellipsis, style: const TextStyle(color: TColors.slate600))),
                ]),
                details: (e) {
                  final p = _payments[tIntOrNull(e['expenseId'])];
                  return [
                    ('Payment', tStr(e['paymentMethod']).isEmpty ? 'N/A' : tStr(e['paymentMethod'])),
                    ('Paid to', _paidTo(e).isEmpty ? 'N/A' : _paidTo(e)),
                    ('Status', p == null ? '—' : (paymentStatusLabels[tStr(p['paymentStatus'])] ?? tStr(p['paymentStatus']))),
                    ('Still owed', p != null && tNum(p['balance']) > 0 ? _gh(tNum(p['balance'])) : '—'),
                    if (tStr(e['receiptRef']).isNotEmpty) ('Reference', tStr(e['receiptRef'])),
                  ];
                },
                actions: (e) => [
                  OutlinedButton.icon(onPressed: () => _expenseDialog(e), icon: const Icon(Icons.edit_outlined, size: 16), label: const Text('Edit')),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: TColors.red600, side: const BorderSide(color: Color(0xFFFECACA))),
                    onPressed: () => _delete(e),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Delete'),
                  ),
                ],
                table: _table,
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
        ] else
          _categoriesTab(),
      ]);
    }
    return Scaffold(
      backgroundColor: TColors.slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Expenses')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [body]),
      ),
    );
  }

  Widget _summary(String label, String value) => TCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, maxLines: 1, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: TColors.slate900)),
          ),
        ]),
      );

  Widget _table(List<Map> rows) => TrackerTable(
        columns: const [
          TCol('Date', width: 95),
          TCol('Description', width: 200),
          TCol('Category', width: 120),
          TCol('Supplier / Paid To', width: 140),
          TCol('Method', width: 110),
          TCol('Status', width: 130),
          TCol('Total', right: true, width: 110),
          TCol('Actions', right: true, width: 100),
        ],
        rows: [
          for (final e in rows)
            () {
              final p = _payments[tIntOrNull(e['expenseId'])];
              return [
                cellText(_day(e['expenseDate']), color: TColors.slate500),
                Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(tStr(e['description']), style: const TextStyle(fontWeight: FontWeight.w500)),
                  if (tStr(e['receiptRef']).isNotEmpty) Text('Ref: ${tStr(e['receiptRef'])}', style: const TextStyle(fontSize: 11, color: TColors.slate500)),
                ]),
                tStr(e['categoryName']).isEmpty
                    ? cellText('—')
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: rStatusBadge(tStr(e['categoryName']), bg: TColors.rose50, fg: TColors.rose700, border: TColors.rose200)),
                cellText(_paidTo(e).isEmpty ? '—' : _paidTo(e)),
                tStr(e['paymentMethod']).isEmpty ? cellText('—') : Align(alignment: Alignment.centerLeft, child: rStatusBadge(tStr(e['paymentMethod']))),
                p == null
                    ? cellText('—')
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        _statusChip(p),
                        if (tNum(p['balance']) > 0)
                          Text('owed ${tNum(p['balance']).toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, color: TColors.slate500)),
                      ]),
                cellText(_gh(tNum(e['amount'])), color: TColors.red600, bold: true),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _expenseDialog(e)),
                  IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline, size: 18), onPressed: () => _delete(e)),
                ]),
              ];
            }(),
        ],
      );

  Widget _categoriesTab() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppInput(
          controller: _newCategory,
          hintText: 'New category name',
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _addCategory(),
        ),
        const SizedBox(height: 8),
        roseButton('Add Category', _newCategory.text.trim().isEmpty ? null : _addCategory),
        const SizedBox(height: 14),
        if (_categories.isEmpty)
          const TCard(child: REmptyState(icon: Icons.sell_outlined, title: 'No categories yet', description: 'Add expense categories to organise your spending'))
        else
          TCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (final (i, c) in _categories.indexed)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: TColors.slate200))),
                  child: Row(children: [
                    const Icon(Icons.sell_outlined, size: 16, color: Color(0xFFF43F5E)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        Text(tStr(c['name']), style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.slate900)),
                        if (c['isActive'] == false) rStatusBadge('Inactive', fg: TColors.slate400),
                      ]),
                    ),
                    IconButton(tooltip: 'Delete category', icon: const Icon(Icons.delete_outline, size: 18, color: TColors.slate400), onPressed: () => _deleteCategory(c)),
                  ]),
                ),
            ]),
          ),
      ]);
}

// ------------------------------------------------------------------ Record / Edit Expense

class _ExpenseDialog extends StatefulWidget {
  const _ExpenseDialog({
    required this.api,
    required this.farmId,
    required this.editing,
    required this.payment,
    required this.categories,
    required this.accounts,
    required this.suppliers,
    required this.gh,
  });
  final ApiClient api;
  final String farmId;
  final Map? editing;
  final Map? payment;
  final List<Map> categories, accounts, suppliers;
  final FarmMoney gh;

  @override
  State<_ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends State<_ExpenseDialog> {
  String _date = DateTime.now().toUtc().toIso8601String().substring(0, 10);
  int? _categoryId;
  final _description = TextEditingController();
  final _amount = TextEditingController();
  String _method = 'Cash';
  int? _cashAccountId;
  int? _supplierId;
  final _supplierName = TextEditingController();
  final _receipt = TextEditingController();
  String _status = 'Paid';
  final _partPaid = TextEditingController();
  String _dueDate = '';
  bool _saving = false;

  bool get _editing => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    if (e != null) {
      final p = widget.payment;
      final amount = tNum(e['amount']);
      final paidAtEntry = p?['paidAtEntry'] != null ? tNum(p!['paidAtEntry']) : amount;
      _date = tStr(e['expenseDate']).split('T').first;
      _categoryId = tIntOrNull(e['categoryId']);
      _description.text = tStr(e['description']);
      _amount.text = amount == 0 ? '' : _plain(amount);
      _method = tStr(e['paymentMethod']).isEmpty ? 'Cash' : tStr(e['paymentMethod']);
      _supplierName.text = tStr(e['supplierName']);
      _receipt.text = tStr(e['receiptRef']);
      _cashAccountId = tIntOrNull(p?['cashAccountId']);
      _supplierId = tIntOrNull(p?['supplierId']);
      _dueDate = tStr(p?['dueDate']).split('T').first;
      _status = paidAtEntry >= amount ? 'Paid' : paidAtEntry > 0 ? 'PartiallyPaid' : 'Unpaid';
      if (_status == 'PartiallyPaid') _partPaid.text = _plain(paidAtEntry);
    }
  }

  static String _plain(num n) => n == n.roundToDouble() ? n.toInt().toString() : '$n';

  @override
  void dispose() {
    for (final c in [_description, _amount, _supplierName, _receipt, _partPaid]) {
      c.dispose();
    }
    super.dispose();
  }

  num get _amountValue => num.tryParse(_amount.text.trim()) ?? 0;

  Future<void> _save() async {
    final amount = _amountValue;
    if (_description.text.trim().isEmpty || amount == 0) {
      trackerToast(context, 'Validation', description: 'Description and amount are required.', error: true);
      return;
    }
    final paid = amountPaidForStatus(_status, num.tryParse(_partPaid.text.trim()) ?? 0);
    if (_status == 'PartiallyPaid' && (paid == null || paid <= 0 || paid >= amount)) {
      trackerToast(context, 'Validation',
          description: 'A partially paid expense must have something paid against it, and less than the total.', error: true);
      return;
    }
    setState(() => _saving = true);
    final body = {
      'expenseDate': _date,
      'categoryId': _categoryId,
      'description': _description.text,
      'amount': amount,
      'paymentMethod': _method,
      'supplierName': _supplierName.text,
      'receiptRef': _receipt.text,
      'cashAccountId': requiresCashAccount(_status) ? _cashAccountId : null,
      'supplierId': _supplierId,
      'amountPaid': paid,
      'dueDate': _status == 'Paid' || _dueDate.isEmpty ? null : _dueDate,
      'farmId': widget.farmId,
    };
    try {
      if (_editing) {
        await widget.api.put('/api/Restaurant/expenses/${tIntOrNull(widget.editing!['expenseId'])}', body: body);
        if (mounted) trackerToast(context, 'Success', description: 'Expense updated.');
      } else {
        await widget.api.post('/api/Restaurant/expenses', body: body);
        if (mounted) trackerToast(context, 'Success', description: 'Expense recorded.');
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Error',
          description: e.message.isNotEmpty ? e.message : (_editing ? 'Failed to update expense.' : 'Failed to create expense.'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final paidBox = _status == 'PartiallyPaid' ? null : (_status == 'Paid' ? (_amountValue == 0 ? '' : _plain(_amountValue)) : '0');
    return rDialog(
      title: _editing ? 'Edit Expense' : 'Record Expense',
      description: _editing ? 'Update expense information' : 'Log a business expense',
      children: [
        rField('Date', rDateInput(_date, (v) => setState(() => _date = v))),
        rField(
          'Category',
          AppSelect<int>(
            value: _categoryId,
            hintText: 'Select category',
            items: [for (final c in widget.categories) AppSelectItem(value: tIntOrNull(c['expenseCategoryId'])!, label: tStr(c['name']))],
            onChanged: (v) => setState(() => _categoryId = v),
          ),
        ),
        rField('Description', AppInput(controller: _description, hintText: 'e.g. Weekly produce from supplier'), required: true),
        rField('Amount', rNumberInput(_amount, onChanged: () => setState(() {})), required: true),
        rField(
          'Payment Method',
          AppSelect<String>(
            value: _method,
            items: [for (final m in restaurantExpensePaymentMethods) AppSelectItem(value: m, label: m)],
            onChanged: (v) => setState(() => _method = v ?? 'Cash'),
          ),
        ),
        if (requiresCashAccount(_status))
          rField(
            'Paid from',
            AppSelect<int>(
              value: _cashAccountId ?? -1,
              items: [
                AppSelectItem(value: -1, label: 'Default account for $_method'),
                for (final a in widget.accounts)
                  AppSelectItem(value: tIntOrNull(a['cashAccountId'])!, label: '${tStr(a['name'])} — ${tNum(a['currentBalance']).toStringAsFixed(2)}'),
              ],
              onChanged: (v) => setState(() => _cashAccountId = v == null || v == -1 ? null : v),
            ),
          ),
        // Supplier & Payment Status: who this is owed to, and how much has been paid.
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              color: const Color(0xFF0284C7),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: const Text('Supplier & Payment Status', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                rField(
                  'Supplier / Paid To',
                  AppSelect<int>(
                    value: _supplierId ?? -1,
                    items: [
                      const AppSelectItem(value: -1, label: 'Not linked to a supplier'),
                      for (final s in widget.suppliers) AppSelectItem(value: tIntOrNull(s['restaurantsupplierid'])!, label: tStr(s['name'])),
                    ],
                    onChanged: (v) => setState(() {
                      final s = widget.suppliers.where((x) => tIntOrNull(x['restaurantsupplierid']) == v).firstOrNull;
                      _supplierId = s == null ? null : tIntOrNull(s['restaurantsupplierid']);
                      if (s != null) _supplierName.text = tStr(s['name']);
                    }),
                  ),
                ),
                const SizedBox(height: 12),
                rField(
                  'Payment Status *',
                  AppSelect<String>(
                    value: _status,
                    items: [for (final st in selectablePaymentStatuses) AppSelectItem(value: st, label: paymentStatusLabels[st] ?? st)],
                    onChanged: (v) => setState(() => _status = v ?? 'Paid'),
                  ),
                ),
                const SizedBox(height: 12),
                rField(
                  'Amount Paid${_status == 'PartiallyPaid' ? ' *' : ''}',
                  _status == 'PartiallyPaid'
                      ? rNumberInput(_partPaid)
                      : Container(
                          height: 44,
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                              color: TColors.slate50, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
                          child: Text(paidBox ?? '', style: const TextStyle(color: TColors.slate500)),
                        ),
                ),
                const SizedBox(height: 12),
                rField(
                  'Due Date',
                  IgnorePointer(
                    ignoring: _status == 'Paid',
                    child: Opacity(opacity: _status == 'Paid' ? .5 : 1, child: rDateInput(_dueDate, (v) => setState(() => _dueDate = v))),
                  ),
                ),
                if (_status != 'Paid' && _supplierId == null) ...[
                  const SizedBox(height: 10),
                  const Text('Select a supplier if you want this unpaid expense to appear in Supplier Balances.',
                      style: TextStyle(fontSize: 12, color: TColors.amber700)),
                ],
              ]),
            ),
          ]),
        ),
        rField(
          'Supplier (name only)',
          AppInput(controller: _supplierName, hintText: 'If not in the supplier list (optional)', enabled: _supplierId == null),
        ),
        rField('Receipt / reference', AppInput(controller: _receipt, hintText: 'Receipt or invoice no. (optional)')),
      ],
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        rConfirm(_saving ? 'Saving...' : (_editing ? 'Save Changes' : 'Record Expense'), _saving ? null : _save, color: restaurantRose),
      ],
    );
  }
}
