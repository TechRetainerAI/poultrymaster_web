// Generic → Purchasing → Expenses, as `app/generic-expenses/page.tsx`, and New
// expense (`app/generic-expenses/new`). An expense is created as a Draft;
// approving it charges the cash account, or posts a credit expense to the
// supplier's ledger.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/money/money_widgets.dart';
import '../poultry/sales/balances_widgets.dart';
import '../poultry/trackers/tracker_logic.dart' show tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/business_dates.dart';
import '../shared/company_clock.dart';
import 'generic_kit.dart';
import 'generic_products_screen.dart' show genericEmptyCard;
import 'generic_sales_screen.dart' show genericBackLink, genericCard;
import 'reports/generic_report_kit.dart' show fmtMoney;

const genericExpenseStatuses = ['All', 'Draft', 'Approved', 'Rejected'];

/// PAY_METHODS: MoMo is stored, "Mobile Money" is shown.
const genericExpensePayMethods = [
  ('Cash', 'Cash'),
  ('MoMo', 'Mobile Money'),
  ('Bank', 'Bank'),
  ('Card', 'Card'),
  ('Credit', 'Credit'),
];

const _amber600 = Color(0xFFD97706);

/// badgeClass: Approved emerald, Rejected rose, Submitted sky, Cancelled and
/// anything else slate.
Widget genericExpenseBadge(Object? status) {
  final (bg, fg) = switch (tStr(status)) {
    'Approved' => (TColors.emerald100, TColors.emerald800),
    'Rejected' => (TColors.rose100, TColors.rose800),
    'Submitted' => (TColors.sky100, TColors.sky800),
    'Cancelled' => (TColors.slate100, TColors.slate700),
    _ => (TColors.slate100, TColors.slate800),
  };
  return TBadge(tStr(status), bg: bg, fg: fg);
}

/// The list's filters: search (category, description, paid to, notes) and dates.
List<Map> filterGenericExpenses(List<Map> rows, {String search = '', String from = '', String to = ''}) {
  final q = search.trim().toLowerCase();
  return rows.where((r) {
    final day = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(tStr(r['expenseDate']))?[1];
    if (day != null) {
      if (from.isNotEmpty && day.compareTo(from) < 0) return false;
      if (to.isNotEmpty && day.compareTo(to) > 0) return false;
    }
    if (q.isNotEmpty && !['categoryName', 'description', 'paidTo', 'notes'].any((k) => tStr(r[k]).toLowerCase().contains(q))) return false;
    return true;
  }).toList();
}

String _dash(Object? v) => tStr(v).isEmpty ? '–' : tStr(v);

class GenericExpensesScreen extends StatefulWidget {
  const GenericExpensesScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<GenericExpensesScreen> createState() => _GenericExpensesScreenState();
}

class _GenericExpensesScreenState extends State<GenericExpensesScreen> {
  List<Map> _rows = [];
  bool _loading = true;
  String _status = 'All';
  final _search = TextEditingController();
  String _from = '', _to = '';
  Duration _offset = DateTime.now().timeZoneOffset;

  String get _base => '${genericBase(widget.company)}/expenses';

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
      final r = rowsOf(await widget.session.farmClient.get(_base, query: _status == 'All' ? null : {'status': _status}));
      if (mounted) setState(() => _rows = r);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load expenses', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _new() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => GenericNewExpenseScreen(session: widget.session, company: widget.company)),
    );
    if (saved == true) setState(() => _status = 'Draft');
    _load();
  }

  Future<void> _approve(Map e) async {
    final id = tIntOrNull(e['genericExpenseId']) ?? 0;
    try {
      await widget.session.farmClient.post('$_base/$id/approve', body: {});
      if (mounted) trackerToast(context, 'Expense #$id approved.');
      await _load();
    } on ApiException catch (err) {
      if (mounted) trackerToast(context, 'Approve failed', description: err.message, error: true);
    }
  }

  List<Widget> _actions(Map e) => ['Draft', 'Submitted'].contains(tStr(e['status']))
      ? [
          OutlinedButton.icon(
            onPressed: () => _approve(e),
            style: OutlinedButton.styleFrom(foregroundColor: TColors.emerald700, side: const BorderSide(color: TColors.emerald200)),
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Approve'),
          ),
        ]
      : const [];

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/generic-expenses');
    final visible = filterGenericExpenses(_rows, search: _search.text, from: _from, to: _to);
    String title(Map e) => tStr(e['categoryName']).isNotEmpty
        ? tStr(e['categoryName'])
        : tStr(e['description']).isNotEmpty
            ? tStr(e['description'])
            : 'Expense';
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Expenses')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            const Row(children: [
              Icon(Icons.attach_money, size: 24, color: _amber600),
              SizedBox(width: 8),
              Expanded(child: Text('Expenses', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900))),
            ]),
            Text('${_rows.length} expense(s)', style: const TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 10),
            FilledButton.icon(onPressed: _new, icon: const Icon(Icons.add, size: 18), label: const Text('New expense')),
            const SizedBox(height: 12),
            Wrap(spacing: 4, runSpacing: 4, children: [
              for (final s in genericExpenseStatuses)
                filterChipButton(s, s == _status, () {
                  if (s == _status) return;
                  setState(() => _status = s);
                  _load();
                }),
            ]),
            const SizedBox(height: 12),
            if (_loading && _rows.isEmpty)
              const LoadingLine('Loading...')
            else if (_rows.isEmpty)
              genericEmptyCard('No expenses yet.')
            else ...[
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
              ),
              const SizedBox(height: 14),
              MobileCardList<Map>(
                items: visible,
                keyOf: (e) => '${tIntOrNull(e['genericExpenseId'])}',
                primary: (e) => '#${tStr(e['genericExpenseId'])} · ${title(e)}',
                secondary: (e) => '${fmtDateTime(e['expenseDate'], e, _offset)} · ${tStr(e['paymentMethod'])}',
                trailing: (e) => Padding(padding: const EdgeInsets.only(left: 6), child: genericExpenseBadge(e['status'])),
                details: (e) => [
                  ('Date', fmtDateTime(e['expenseDate'], e, _offset)),
                  ('Category', _dash(e['categoryName'])),
                  ('Description', _dash(e['description'])),
                  ('Supplier', _dash(e['supplierName'])),
                  ('Paid via', tStr(e['paymentMethod'])),
                  ('Amount', fmtMoney(e['amount'])),
                ],
                actions: _actions,
                table: (items) => TrackerTable(
                  columns: const [
                    TCol('#', width: 60), TCol('Date', width: 140), TCol('Category', width: 120), TCol('Description', width: 160),
                    TCol('Supplier', width: 120), TCol('Method', width: 80), TCol('Amount', right: true, width: 110), TCol('Status', width: 100),
                    TCol('', width: 130),
                  ],
                  rows: [
                    for (final e in items)
                      [
                        cellText('#${tStr(e['genericExpenseId'])}'),
                        cellText(fmtDateTime(e['expenseDate'], e, _offset)),
                        cellText(_dash(e['categoryName'])),
                        cellText(_dash(e['description'])),
                        cellText(_dash(e['supplierName'])),
                        cellText(tStr(e['paymentMethod'])),
                        Align(alignment: Alignment.centerRight, child: Text(fmtMoney(e['amount']))),
                        Align(alignment: Alignment.centerLeft, child: genericExpenseBadge(e['status'])),
                        Wrap(children: _actions(e)),
                      ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------- new expense

class GenericNewExpenseScreen extends StatefulWidget {
  const GenericNewExpenseScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<GenericNewExpenseScreen> createState() => _GenericNewExpenseScreenState();
}

class _GenericNewExpenseScreenState extends State<GenericNewExpenseScreen> {
  bool _loading = true, _saving = false;
  List<Map> _categories = [], _suppliers = [], _accounts = [];
  String _date = DateTime.now().toUtc().toIso8601String().substring(0, 10);
  String _categoryId = '', _method = 'Cash', _accountId = '', _supplierId = '';
  final _description = TextEditingController(), _amount = TextEditingController(text: '0');
  final _paidTo = TextEditingController(), _notes = TextEditingController();

  String get _base => genericBase(widget.company);
  bool get _credit => _method == 'Credit';

  /// isValid: an amount, a category, and a supplier (credit) or a cash account.
  bool get _valid {
    if ((num.tryParse(_amount.text) ?? 0) <= 0) return false;
    if (_categoryId.isEmpty) return false;
    if (_credit && _supplierId.isEmpty) return false;
    if (!_credit && _accountId.isEmpty) return false;
    return true;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_description, _amount, _paidTo, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final api = widget.session.farmClient;
    try {
      final r = await Future.wait([api.get('$_base/expense-categories'), api.get('$_base/suppliers'), api.get('$_base/cash-accounts')]);
      if (!mounted) return;
      setState(() {
        _categories = rowsOf(r[0]);
        _suppliers = rowsOf(r[1]);
        _accounts = rowsOf(r[2]);
        final first = _accounts.where((a) => a['isActive'] == true).firstOrNull;
        if (first != null) _accountId = tStr(first['genericCashAccountId']);
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load options', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (!_valid) {
      return trackerToast(context, 'Fill required fields',
          description: _credit ? 'Credit expense needs a supplier.' : 'Non-credit expense needs a cash account.', error: true);
    }
    setState(() => _saving = true);
    try {
      final created = await widget.session.farmClient.post('$_base/expenses', body: {
        'expenseDate': _date,
        'genericExpenseCategoryId': int.parse(_categoryId),
        'genericSupplierId': _supplierId.isEmpty ? null : int.parse(_supplierId),
        'description': _description.text.isEmpty ? null : _description.text,
        'amount': num.tryParse(_amount.text) ?? 0,
        'paidTo': _paidTo.text.isEmpty ? null : _paidTo.text,
        'paymentMethod': _method,
        'genericCashAccountId': _credit ? null : int.parse(_accountId),
        'notes': _notes.text.isEmpty ? null : _notes.text,
        'farmId': widget.company.farmId,
      });
      if (created is Map && mounted) {
        trackerToast(context, 'Expense #${tStr(created['genericExpenseId'])} created as Draft',
            description: 'Approve to charge cash or post to the supplier ledger.');
        Navigator.of(context).pop(true);
        return;
      }
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not create expense', description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  Widget _gap(Widget w) => Padding(padding: const EdgeInsets.only(bottom: 12), child: w);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New expense')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
        children: [
          genericBackLink(context, 'Back to expenses'),
          const Row(children: [
            Icon(Icons.attach_money, size: 24, color: _amber600),
            SizedBox(width: 8),
            Expanded(child: Text('New expense', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900))),
          ]),
          const SizedBox(height: 14),
          if (_loading)
            const LoadingLine('Loading…')
          else
            genericCard(null, [
              _gap(FilterLabel(
                'Date',
                AppDateField(value: businessDateAsDateTime(_date), onChanged: (d) => setState(() => _date = d == null ? _date : isoDay(d))),
              )),
              _gap(FilterLabel(
                'Category *',
                AppSelect<String>(
                  value: _categoryId.isEmpty ? null : _categoryId,
                  hintText: 'Choose category…',
                  items: [for (final c in _categories) AppSelectItem(value: tStr(c['genericExpenseCategoryId']), label: tStr(c['name']))],
                  onChanged: (v) => setState(() => _categoryId = v ?? ''),
                ),
              )),
              _gap(FilterLabel(
                'Description',
                AppInput(
                  controller: _description,
                  hintText: 'e.g. November rent, fuel for delivery, etc.',
                  inputFormatters: [LengthLimitingTextInputFormatter(500)],
                ),
              )),
              _gap(FilterLabel(
                'Amount *',
                AppInput(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                  onChanged: (_) => setState(() {}),
                ),
              )),
              _gap(FilterLabel(
                'Paid to',
                AppInput(controller: _paidTo, hintText: 'Optional payee name', inputFormatters: [LengthLimitingTextInputFormatter(200)]),
              )),
              _gap(FilterLabel(
                'Payment method *',
                AppSelect<String>(
                  value: _method,
                  items: [for (final (v, l) in genericExpensePayMethods) AppSelectItem(value: v, label: l)],
                  onChanged: (v) => setState(() => _method = v ?? _method),
                ),
              )),
              if (!_credit)
                _gap(FilterLabel(
                  'Cash account *',
                  AppSelect<String>(
                    value: _accountId.isEmpty ? null : _accountId,
                    hintText: 'Pick account…',
                    items: [
                      for (final a in _accounts.where((a) => a['isActive'] == true))
                        AppSelectItem(value: tStr(a['genericCashAccountId']), label: '${tStr(a['accountName'])} (${tStr(a['accountType'])})'),
                    ],
                    onChanged: (v) => setState(() => _accountId = v ?? ''),
                  ),
                ))
              else
                _gap(FilterLabel(
                  'Supplier (credit) *',
                  AppSelect<String>(
                    value: _supplierId.isEmpty ? null : _supplierId,
                    hintText: 'Pick supplier…',
                    items: [for (final s in _suppliers) AppSelectItem(value: tStr(s['genericSupplierId']), label: tStr(s['supplierName']))],
                    onChanged: (v) => setState(() => _supplierId = v ?? ''),
                  ),
                )),
              _gap(FilterLabel(
                'Notes',
                AppInput(controller: _notes, minLines: 2, maxLines: 4, inputFormatters: [LengthLimitingTextInputFormatter(1000)]),
              )),
              Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
                OutlinedButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('Cancel')),
                FilledButton(
                  onPressed: _saving || !_valid ? null : _save,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (_saving) ...[
                      const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                      const SizedBox(width: 8),
                    ],
                    const Text('Create as Draft'),
                  ]),
                ),
              ]),
            ]),
        ],
      ),
    );
  }
}
