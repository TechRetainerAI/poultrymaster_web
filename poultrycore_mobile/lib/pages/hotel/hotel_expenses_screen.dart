// Hotel → Sales, Expenses & Money → Expenses, as `app/hotel-expenses/page.tsx`:
// Poultry's layout in violet. Search and a Filters sheet (dates, category),
// This Month / Total (Filtered), the expandable cards, Add / Edit Expense
// (the money moves when it is saved), Delete (a cancel that gives paid money
// back), and the Categories dialog.
// API: /Hotel/finance/expenses (+ /{id}, /{id}/cancel), /finance/expense-categories,
// /finance/cash-accounts and /Hotel/suppliers.

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/ui/form_dialog.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/money/money_widgets.dart';
import '../poultry/reports/report_format.dart' show FarmMoney;
import '../poultry/sales/balances_logic.dart' show pageSlice;
import '../poultry/sales/balances_widgets.dart' show CompactPager, LoadingLine;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart';
import '../restaurant/restaurant_expenses_screen.dart' show fmtShortDate;
import 'hotel_kit.dart';

/// The web's payment methods: (value, label).
const hotelExpenseMethods = [
  ('Cash', 'Cash'),
  ('MobileMoney', 'Mobile Money'),
  ('Bank', 'Bank Transfer'),
  ('Card', 'Card'),
  ('Credit', 'Credit (no cash account)'),
];

const _keys = [
  'hotelExpenseId', 'expenseDate', 'paymentMethod', 'hotelCashAccountId', 'paidTo', 'hotelExpenseCategoryId', 'hotelSupplierId',
  'hotelExpenseCategoryId', 'isActive', 'accountName', 'currentBalance', 'supplierName',
];

String _day(Object? d) => tStr(d).length >= 10 ? tStr(d).substring(0, 10) : tStr(d);
String _today() => hotelYmd(DateTime.now());
String _cat(Map e) => tStr(e['category']).isEmpty ? 'Uncategorized' : tStr(e['category']);

/// Deleted (and edited-away) expenses stay as Cancelled rows; the list hides them.
bool hotelExpenseLive(Map e) => tStr(e['status']) != 'Cancelled';

/// The list's filters, applied on the phone as the web applies them in the browser.
List<Map> filterHotelExpenses(List<Map> expenses,
    {int? focusId, String category = 'all', String from = '', String to = '', String search = ''}) {
  final q = search.trim().toLowerCase();
  return [
    for (final e in expenses)
      if ((focusId == null || tIntOrNull(e['hotelExpenseId']) == focusId) &&
          hotelExpenseLive(e) &&
          (category == 'all' || _cat(e) == category) &&
          (from.isEmpty || _day(e['expenseDate']).compareTo(from) >= 0) &&
          (to.isEmpty || _day(e['expenseDate']).compareTo(to) <= 0) &&
          (q.isEmpty ||
              [e['category'], e['description'], e['vendor'], e['paidTo'], e['notes']]
                  .where((x) => x != null && '$x'.isNotEmpty)
                  .join(' ')
                  .toLowerCase()
                  .contains(q)))
        e,
  ];
}

class HotelExpensesScreen extends StatefulWidget {
  const HotelExpensesScreen({super.key, required this.session, required this.company, this.focusExpenseId});
  final Session session;
  final Company company;

  /// `?expenseId=` (from Supplier Balances / Payments): the list narrowed to one bill.
  final int? focusExpenseId;

  @override
  State<HotelExpensesScreen> createState() => _HotelExpensesScreenState();
}

class _HotelExpensesScreenState extends State<HotelExpensesScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _expenses = [], _categories = [], _accounts = [], _suppliers = [];
  late int? _focusId = widget.focusExpenseId;
  final _search = TextEditingController();
  String _from = '', _to = '', _category = 'all';
  int _page = 1, _pageSize = 25;
  FarmMoney _gh = const FarmMoney();

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  Map<String, dynamic> get _q => {'farmId': _farmId};

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
        _api.get('/api/Hotel/finance/expenses', query: _q),
        _api.get('/api/Hotel/finance/expense-categories', query: _q),
        _api.get('/api/Hotel/finance/cash-accounts', query: _q),
      ]);
      if (!mounted) return;
      setState(() {
        _expenses = hotelAlias(hotelRows(r[0]), _keys);
        _categories = hotelAlias(hotelRows(r[1]), _keys);
        _accounts = hotelAlias(hotelRows(r[2]), _keys);
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
    // Suppliers load on their own; a failure leaves the list empty.
    try {
      final s = hotelAlias(hotelRows(await _api.get('/api/Hotel/suppliers', query: _q)), _keys);
      if (mounted) setState(() => _suppliers = [for (final x in s) if (x['isActive'] != false) x]);
    } on ApiException {
      if (mounted) setState(() => _suppliers = []);
    }
    if (mounted) setState(() => _loading = false);
  }

  int get _activeFilterCount => [_from, _to, _category != 'all' ? 'x' : ''].where((x) => x.isNotEmpty).length;

  void _clearFilters() => setState(() {
        _search.clear();
        _category = 'all';
        _from = '';
        _to = '';
        _focusId = null;
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
              FilterLabel('Start date', _dateBox(from, (v) => set(() => from = v))),
              const SizedBox(height: 12),
              FilterLabel('End date', _dateBox(to, (v) => set(() => to = v))),
              const SizedBox(height: 14),
              FilterLabel(
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

  Future<void> _expenseDialog([Map<String, dynamic>? editing]) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _ExpenseDialog(
        api: _api,
        farmId: _farmId,
        editing: editing,
        categories: _categories,
        accounts: _accounts,
        suppliers: _suppliers,
      ),
    );
    if (done == true) _load();
  }

  Future<void> _delete(Map e) async {
    final desc = tStr(e['description']);
    final ok = await hotelConfirmDelete(
      context,
      title: 'Delete expense?',
      message: '${desc.isNotEmpty ? '"$desc" will be removed.' : 'This expense will be removed.'} If it was paid, the money goes back to its account.',
      onConfirm: () => _api.post('/api/Hotel/finance/expenses/${tIntOrNull(e['hotelExpenseId'])}/cancel',
          body: {'farmId': _farmId, 'reason': 'Deleted'}),
    );
    if (!ok || !mounted) return;
    trackerToast(context, 'Expense deleted');
    _load();
  }

  Future<void> _categoriesDialog() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CategoriesDialog(api: _api, farmId: _farmId, categories: _categories, onAdded: _load),
    );
  }

  String _accountName(Map e) {
    final a = _accounts.where((a) => tIntOrNull(a['hotelCashAccountId']) == tIntOrNull(e['hotelCashAccountId'])).firstOrNull;
    return a == null || tStr(a['accountName']).isEmpty ? '—' : tStr(a['accountName']);
  }

  String _paidTo(Map e) => tStr(e['paidTo']).isNotEmpty ? tStr(e['paidTo']) : tStr(e['vendor']);

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/hotel-expenses');
    final live = _expenses.where(hotelExpenseLive).toList();
    final filtered = filterHotelExpenses(_expenses, focusId: _focusId, category: _category, from: _from, to: _to, search: _search.text);
    final month = _today().substring(0, 7);
    final monthTotal = live.where((e) => _day(e['expenseDate']).startsWith(month)).fold<num>(0, (s, e) => s + tNum(e['amount']));
    final filteredTotal = filtered.fold<num>(0, (s, e) => s + tNum(e['amount']));
    final categoryOptions = {for (final e in live) _cat(e)}.toList()..sort();
    if ((_page - 1) * _pageSize >= filtered.length && _page > 1) _page = 1;

    return Scaffold(
      backgroundColor: TColors.slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Expenses')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
          const HotelPageHeader(icon: Icons.attach_money, title: 'Expenses', description: 'Track operational costs and financial records'),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                onPressed: _categoriesDialog,
                icon: const Icon(Icons.sell_outlined, size: 16),
                label: const Text('Categories'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                style: hotelPrimary.copyWith(minimumSize: const WidgetStatePropertyAll(Size.fromHeight(44))),
                onPressed: () => _expenseDialog(),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Expense'),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          if (_focusId != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(color: TColors.violet50, border: Border.all(color: const Color(0xFFDDD6FE)), borderRadius: BorderRadius.circular(8)),
              child: Wrap(spacing: 12, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('Showing expense #$_focusId only.', style: const TextStyle(fontSize: 13, color: Color(0xFF4C1D95))),
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
          if (_loading)
            const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: LoadingLine('Loading…')))
          else if (live.isEmpty)
            TCard(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 30),
                child: Column(children: [
                  const Icon(Icons.receipt_long_outlined, size: 48, color: TColors.slate400),
                  const SizedBox(height: 12),
                  const Text('No expenses recorded yet', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: TColors.slate900)),
                  const SizedBox(height: 6),
                  const Text("Track your hotel's daily expenses and costs", textAlign: TextAlign.center, style: TextStyle(color: TColors.slate600)),
                  const SizedBox(height: 14),
                  hotelAddButton('Record First Expense', () => _expenseDialog()),
                ]),
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
              description: 'Manage your hotel expenses',
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
              child: MobileCardList<Map<String, dynamic>>(
                items: pageSlice(filtered.cast<Map<String, dynamic>>(), _page, _pageSize),
                striped: true,
                keyOf: (e) => '${e['hotelExpenseId']}',
                primary: (e) => fmtShortDate(e['expenseDate']),
                trailing: (e) => tStr(e['category']).isEmpty ? null : hotelBadge(tStr(e['category']), TColors.violet100, TColors.violet700),
                // The amount shrinks to fit rather than overflow a narrow card.
                secondaryBuilder: (e) => Row(children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(_gh(tNum(e['amount'])), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: TColors.red600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(tStr(e['description']), overflow: TextOverflow.ellipsis, style: const TextStyle(color: TColors.slate600))),
                ]),
                details: (e) => [
                  ('Payment', tStr(e['paymentMethod']).isEmpty ? 'Cash' : tStr(e['paymentMethod'])),
                  ('Paid to', _paidTo(e).isEmpty ? 'N/A' : _paidTo(e)),
                  // Drafts from before saving posted straight away: Edit posts them.
                  if ((tStr(e['status']).isEmpty ? 'Draft' : tStr(e['status'])) != 'Approved') ('Status', 'Not posted (Edit to post)'),
                  ('Account', _accountName(e)),
                  if (tStr(e['notes']).isNotEmpty) ('Notes', tStr(e['notes'])),
                ],
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
        ]),
      ),
    );
  }

  Widget _dateBox(String value, ValueChanged<String> onChanged) => AppDateField(
        value: hotelParseYmd(value),
        hintText: 'Pick a date',
        onChanged: (d) => onChanged(d == null ? '' : hotelYmd(d)),
      );

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

  Widget _table(List<Map<String, dynamic>> rows) => TrackerTable(
        columns: const [
          TCol('Date', width: 95),
          TCol('Description', width: 200),
          TCol('Category', width: 120),
          TCol('Supplier / Paid To', width: 140),
          TCol('Method', width: 110),
          TCol('Account', width: 130),
          TCol('Total', right: true, width: 110),
          TCol('Actions', right: true, width: 100),
        ],
        rows: [
          for (final e in rows)
            [
              cellText(_day(e['expenseDate']), color: TColors.slate500),
              cellText(tStr(e['description']), bold: true),
              tStr(e['category']).isEmpty
                  ? cellText('—')
                  : Align(alignment: Alignment.centerLeft, child: hotelBadge(tStr(e['category']), TColors.violet50, TColors.violet700)),
              cellText(_paidTo(e).isEmpty ? '—' : _paidTo(e)),
              Align(
                alignment: Alignment.centerLeft,
                child: hotelBadge(tStr(e['paymentMethod']).isEmpty ? 'Cash' : tStr(e['paymentMethod']), Colors.white, TColors.slate700),
              ),
              cellText(_accountName(e)),
              cellText(_gh(tNum(e['amount'])), color: TColors.red600, bold: true),
              Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _expenseDialog(e)),
                IconButton(
                    tooltip: 'Delete', icon: const Icon(Icons.delete_outline, size: 18, color: TColors.red600), onPressed: () => _delete(e)),
              ]),
            ],
        ],
      );
}

// ------------------------------------------------------------------ Add / Edit Expense

class _ExpenseDialog extends StatefulWidget {
  const _ExpenseDialog({
    required this.api,
    required this.farmId,
    required this.editing,
    required this.categories,
    required this.accounts,
    required this.suppliers,
  });
  final ApiClient api;
  final String farmId;
  final Map<String, dynamic>? editing;
  final List<Map<String, dynamic>> categories, accounts, suppliers;

  @override
  State<_ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends State<_ExpenseDialog> {
  String _date = _today();
  int? _categoryId;
  String _category = '';
  final _description = TextEditingController();
  final _amount = TextEditingController();
  String _method = 'Cash';
  int? _accountId;
  int? _supplierId;
  final _paidTo = TextEditingController();
  final _notes = TextEditingController();
  String _vendor = '';
  bool _saving = false;

  bool get _editing => widget.editing != null;
  List<Map> get _activeCategories => [for (final c in widget.categories) if (c['isActive'] != false) c];

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    if (e == null) {
      // openNew: the first active category, today, Cash.
      final first = _activeCategories.firstOrNull;
      _category = tStr(first?['name']);
      _categoryId = tIntOrNull(first?['hotelExpenseCategoryId']);
      return;
    }
    _category = tStr(e['category']);
    _description.text = tStr(e['description']);
    final amount = tNum(e['amount']);
    _amount.text = amount == 0 ? '' : (amount == amount.roundToDouble() ? '${amount.toInt()}' : '$amount');
    _date = _day(e['expenseDate']);
    _vendor = tStr(e['vendor']);
    _notes.text = tStr(e['notes']);
    _method = tStr(e['paymentMethod']).isEmpty ? 'Cash' : tStr(e['paymentMethod']);
    _accountId = tIntOrNull(e['hotelCashAccountId']);
    _paidTo.text = tStr(e['paidTo']);
    _categoryId = tIntOrNull(e['hotelExpenseCategoryId']);
    _supplierId = tIntOrNull(e['hotelSupplierId']);
  }

  @override
  void dispose() {
    for (final c in [_description, _amount, _paidTo, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final amount = num.tryParse(_amount.text.trim()) ?? 0;
    String? error;
    if (_description.text.trim().isEmpty) {
      error = 'Description required';
    } else if (amount <= 0) {
      error = 'Amount must be > 0';
    } else if (_method != 'Credit' && _accountId == null) {
      error = 'Select a cash account';
    } else if (_method == 'Credit' && _supplierId == null) {
      // An expense not paid now is owed to someone: Supplier Balances needs the supplier.
      error = 'Choose the supplier this expense is owed to';
    }
    if (error != null) {
      trackerToast(context, error, error: true);
      return;
    }
    setState(() => _saving = true);
    final body = {
      'category': _category,
      'description': _description.text,
      'amount': amount,
      'expenseDate': _date,
      'vendor': _vendor,
      'notes': _notes.text,
      'paymentMethod': _method,
      'hotelCashAccountId': _accountId,
      'paidTo': _paidTo.text,
      'hotelExpenseCategoryId': _categoryId,
      'hotelSupplierId': _supplierId,
      'farmId': widget.farmId,
    };
    try {
      // Like Poultry, the money moves when the expense is saved.
      if (_editing) {
        await widget.api.put('/api/Hotel/finance/expenses/${tIntOrNull(widget.editing!['hotelExpenseId'])}', body: body);
      } else {
        await widget.api.post('/api/Hotel/finance/expenses', body: {...body, 'postNow': true});
      }
      if (!mounted) return;
      trackerToast(context, _editing ? 'Expense updated' : 'Expense recorded');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Failed', description: e.message, error: true);
    }
  }

  static String _purpose(Object? p) => switch (tStr(p)) {
        'FrontDesk' => ' [Front Desk]',
        'Expenses' => ' [Expenses]',
        'POS' => ' [POS]',
        'Payroll' => ' [Payroll]',
        _ => '',
      };

  @override
  Widget build(BuildContext context) {
    final credit = _method == 'Credit';
    return HotelDialog(
      icon: _editing ? Icons.edit_outlined : Icons.account_balance_wallet_outlined,
      title: _editing ? 'Edit Expense' : 'Add Expense',
      saving: _saving,
      saveLabel: _saving ? 'Saving...' : (_editing ? 'Save changes' : 'Save Expense'),
      onSave: _save,
      children: [
        Text(_editing ? 'Update the expense. The money moves to match.' : 'The money leaves the chosen account when you save.',
            style: const TextStyle(fontSize: 13, color: TColors.slate500)),
        TintedSection(title: 'Expense Details', color: FormColor.blue, children: [
          FilterLabel(
            'Expense date *',
            AppDateField(
              value: hotelParseYmd(_date),
              lastDate: DateTime.now(),
              onChanged: (d) => setState(() => _date = d == null ? '' : hotelYmd(d)),
            ),
          ),
          FilterLabel(
            'Category *',
            AppSelect<int>(
              value: _categoryId,
              hintText: 'Pick category',
              items: [
                for (final c in _activeCategories)
                  if (tIntOrNull(c['hotelExpenseCategoryId']) != null) AppSelectItem(value: tIntOrNull(c['hotelExpenseCategoryId'])!, label: tStr(c['name'])),
              ],
              onChanged: (v) => setState(() {
                _categoryId = v;
                _category = tStr(widget.categories.where((c) => tIntOrNull(c['hotelExpenseCategoryId']) == v).firstOrNull?['name']);
              }),
            ),
          ),
          FilterLabel('Description *', AppInput(controller: _description, hintText: 'e.g. Laundry detergent')),
        ]),
        TintedSection(title: 'Payment', color: FormColor.amber, children: [
          FilterLabel('Amount *', AppInput(controller: _amount, keyboardType: const TextInputType.numberWithOptions(decimal: true))),
          FilterLabel(
            'Payment method',
            AppSelect<String>(
              value: _method,
              items: [for (final (v, l) in hotelExpenseMethods) AppSelectItem(value: v, label: l)],
              onChanged: (v) => setState(() => _method = v ?? 'Cash'),
            ),
          ),
          if (!credit)
            FilterLabel(
              'Cash account (debit from) *',
              AppSelect<int>(
                value: _accountId,
                hintText: 'Pick account to debit',
                items: [
                  for (final a in widget.accounts)
                    if (a['isActive'] != false && tIntOrNull(a['hotelCashAccountId']) != null)
                      AppSelectItem(
                        value: tIntOrNull(a['hotelCashAccountId'])!,
                        label: '${tStr(a['accountName'])}${_purpose(a['purpose'])} — Bal: ${tNum(a['currentBalance']).toStringAsFixed(2)}',
                      ),
                ],
                onChanged: (v) => setState(() => _accountId = v),
              ),
            ),
        ]),
        TintedSection(title: 'Details', color: FormColor.slate, children: [
          FilterLabel(
            credit ? 'Supplier *' : 'Supplier',
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AppSelect<int>(
                value: _supplierId ?? -1,
                hintText: 'Select a supplier',
                items: [
                  const AppSelectItem(value: -1, label: 'None'),
                  for (final s in widget.suppliers)
                    if (tIntOrNull(s['hotelSupplierId']) != null) AppSelectItem(value: tIntOrNull(s['hotelSupplierId'])!, label: tStr(s['supplierName'])),
                ],
                onChanged: (v) => setState(() {
                  final s = widget.suppliers.where((x) => tIntOrNull(x['hotelSupplierId']) == v).firstOrNull;
                  _supplierId = s == null ? null : tIntOrNull(s['hotelSupplierId']);
                  if (s != null) _paidTo.text = tStr(s['supplierName']);
                }),
              ),
              if (credit) ...[
                const SizedBox(height: 4),
                const Text('This bill appears on Supplier Balances.', style: TextStyle(fontSize: 12, color: TColors.slate500)),
              ],
            ]),
          ),
          FilterLabel('Paid to / Vendor', AppInput(controller: _paidTo, hintText: 'Supplier name')),
          FilterLabel('Notes', AppTextarea(controller: _notes)),
        ]),
      ],
    );
  }
}

// ------------------------------------------------------------------ Categories

class _CategoriesDialog extends StatefulWidget {
  const _CategoriesDialog({required this.api, required this.farmId, required this.categories, required this.onAdded});
  final ApiClient api;
  final String farmId;
  final List<Map<String, dynamic>> categories;
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
    final name = _name.text.trim();
    if (name.isEmpty) return;
    try {
      await widget.api.post('/api/Hotel/finance/expense-categories', body: {'name': name, 'farmId': widget.farmId});
      if (!mounted) return;
      // The web closes the dialog, reloads, then says so.
      Navigator.pop(context);
      await widget.onAdded();
      if (mounted) trackerToast(context, 'Category added');
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: const FormDialogTitle(icon: Icons.sell_outlined, color: FormColor.purple, text: 'Expense Categories'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Manage categories for hotel expenses', style: TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 12),
            if (widget.categories.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No categories yet', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate400)),
              )
            else
              for (final c in widget.categories)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
                  child: Row(children: [
                    Expanded(child: Text(tStr(c['name']))),
                    if (c['isActive'] == false) hotelBadge('inactive', Colors.white, TColors.slate600),
                  ]),
                ),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(child: AppInput(controller: _name, hintText: 'New category name', onSubmitted: (_) => _add())),
              const SizedBox(width: 8),
              FilledButton(style: hotelPrimary, onPressed: _add, child: const Text('Add')),
            ]),
          ]),
        ),
      );
}
