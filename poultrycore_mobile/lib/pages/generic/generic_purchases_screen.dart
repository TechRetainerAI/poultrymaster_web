// Generic → Purchasing → Purchases, as `app/generic-purchases/page.tsx`, and
// New purchase (`app/generic-purchases/new`). A purchase is created as a Draft;
// approving it puts the stock up, takes the cash paid out and adds any unpaid
// balance to the supplier's ledger.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/money/money_widgets.dart';
import '../poultry/sales/balances_widgets.dart';
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/business_dates.dart';
import '../shared/company_clock.dart';
import 'generic_customer_payments_screen.dart' show genericPaymentBadge;
import 'generic_kit.dart';
import 'generic_products_screen.dart' show genericEmptyCard;
import 'generic_sales_screen.dart' show genericBackLink, genericCard, genericTotalRow;
import 'generic_suppliers_screen.dart' show genericOrange;
import 'reports/generic_report_kit.dart' show fmtMoney;

const genericPurchaseStatuses = ['All', 'Draft', 'Approved', 'Cancelled'];
const genericPurchasePayMethods = ['Cash', 'MoMo', 'Bank', 'Card', 'Credit', 'Mixed'];

/// The list's filters: search (supplier, status, notes) and dates on purchaseDate.
List<Map> filterGenericPurchases(List<Map> rows, {String search = '', String from = '', String to = ''}) {
  final q = search.trim().toLowerCase();
  return rows.where((r) {
    final day = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(tStr(r['purchaseDate']))?[1];
    if (day != null) {
      if (from.isNotEmpty && day.compareTo(from) < 0) return false;
      if (to.isNotEmpty && day.compareTo(to) > 0) return false;
    }
    if (q.isNotEmpty && !['supplierName', 'status', 'notes'].any((k) => tStr(r[k]).toLowerCase().contains(q))) return false;
    return true;
  }).toList();
}

String _dash(Object? v) => tStr(v).isEmpty ? '–' : tStr(v);

class GenericPurchasesScreen extends StatefulWidget {
  const GenericPurchasesScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<GenericPurchasesScreen> createState() => _GenericPurchasesScreenState();
}

class _GenericPurchasesScreenState extends State<GenericPurchasesScreen> {
  List<Map> _rows = [];
  bool _loading = true;
  String _status = 'All';
  final _search = TextEditingController();
  String _from = '', _to = '';
  Duration _offset = DateTime.now().timeZoneOffset;

  String get _base => '${genericBase(widget.company)}/purchases';

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
      if (mounted) trackerToast(context, 'Could not load purchases', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  /// New purchase lands on the Draft filter, as the web's redirect does.
  Future<void> _new() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => GenericNewPurchaseScreen(session: widget.session, company: widget.company)),
    );
    if (saved == true) setState(() => _status = 'Draft');
    _load();
  }

  Future<void> _approve(Map p) async {
    final id = tIntOrNull(p['genericPurchaseId']) ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Approve purchase #$id?'),
        content: const Text(
            'Inventory will go up, cash will go down by the amount paid, and any unpaid balance will be added to the supplier ledger. All atomic.'),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Approve')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.session.farmClient.post('$_base/$id/approve', body: {});
      if (mounted) trackerToast(context, 'Purchase #$id approved', description: 'Inventory and cash/supplier balances updated.');
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Approve failed', description: e.message, error: true);
    }
  }

  List<Widget> _actions(Map p) => tStr(p['status']) != 'Draft'
      ? const []
      : [
          OutlinedButton.icon(
            onPressed: () => _approve(p),
            style: OutlinedButton.styleFrom(foregroundColor: TColors.emerald700, side: const BorderSide(color: TColors.emerald200)),
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Approve'),
          ),
        ];

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/generic-purchases');
    final visible = filterGenericPurchases(_rows, search: _search.text, from: _from, to: _to);
    Color? bal(Map p) => tNum(p['balance']) > 0 ? TColors.rose700 : null;
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Purchases')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            const Row(children: [
              Icon(Icons.inventory_2_outlined, size: 24, color: genericOrange),
              SizedBox(width: 8),
              Expanded(child: Text('Purchases', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900))),
            ]),
            Text('${_rows.length} purchase(s)', style: const TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 10),
            FilledButton.icon(onPressed: _new, icon: const Icon(Icons.add, size: 18), label: const Text('New purchase')),
            const SizedBox(height: 12),
            Wrap(spacing: 4, runSpacing: 4, children: [
              for (final s in genericPurchaseStatuses)
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
              genericEmptyCard('No purchases yet.')
            else ...[
              ListFiltersCard(
                search: _search,
                searchPlaceholder: 'Search supplier, status or notes',
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
                keyOf: (p) => '${tIntOrNull(p['genericPurchaseId'])}',
                primary: (p) => '#${tStr(p['genericPurchaseId'])} · ${_dash(p['supplierName'])}',
                secondary: (p) => [
                  fmtDateTime(p['purchaseDate'], p, _offset),
                  if (tStr(p['invoiceNumber']).isNotEmpty) 'Inv ${tStr(p['invoiceNumber'])}',
                ].join(' · '),
                trailing: (p) => Padding(padding: const EdgeInsets.only(left: 6), child: genericPaymentBadge(p['status'])),
                details: (p) => [
                  ('Date', fmtDateTime(p['purchaseDate'], p, _offset)),
                  ('Supplier', _dash(p['supplierName'])),
                  ('Invoice', _dash(p['invoiceNumber'])),
                  ('Total', fmtMoney(p['totalAmount'])),
                  ('Paid', fmtMoney(p['amountPaid'])),
                  ('Balance', fmtMoney(p['balance'])),
                ],
                detailColor: (p, label) => label == 'Balance' ? bal(p) : null,
                actions: _actions,
                table: (items) => TrackerTable(
                  columns: const [
                    TCol('#', width: 60), TCol('Date', width: 140), TCol('Supplier', width: 140), TCol('Invoice', width: 100),
                    TCol('Total', right: true, width: 110), TCol('Paid', right: true, width: 110), TCol('Balance', right: true, width: 110),
                    TCol('Status', width: 100), TCol('', width: 130),
                  ],
                  rows: [
                    for (final p in items)
                      [
                        cellText('#${tStr(p['genericPurchaseId'])}'),
                        cellText(fmtDateTime(p['purchaseDate'], p, _offset)),
                        cellText(_dash(p['supplierName'])),
                        cellText(_dash(p['invoiceNumber'])),
                        Align(alignment: Alignment.centerRight, child: Text(fmtMoney(p['totalAmount']))),
                        Align(alignment: Alignment.centerRight, child: Text(fmtMoney(p['amountPaid']))),
                        Align(alignment: Alignment.centerRight, child: Text(fmtMoney(p['balance']), style: TextStyle(color: bal(p)))),
                        Align(alignment: Alignment.centerLeft, child: genericPaymentBadge(p['status'])),
                        Wrap(children: _actions(p)),
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

// ------------------------------------------------------------- new purchase

class _Line {
  int? productId;
  String description = '';
  final quantity = TextEditingController(text: '1');
  final unitCost = TextEditingController(text: '0');
  final discount = TextEditingController(text: '0');
  final key = UniqueKey();

  num get qty => num.tryParse(quantity.text) ?? 0;
  num get cost => num.tryParse(unitCost.text) ?? 0;
  num get disc => num.tryParse(discount.text) ?? 0;
  num get total => qty * cost - disc;

  void dispose() {
    for (final c in [quantity, unitCost, discount]) {
      c.dispose();
    }
  }
}

class GenericNewPurchaseScreen extends StatefulWidget {
  const GenericNewPurchaseScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<GenericNewPurchaseScreen> createState() => _GenericNewPurchaseScreenState();
}

class _GenericNewPurchaseScreenState extends State<GenericNewPurchaseScreen> {
  bool _loading = true, _saving = false;
  List<Map> _suppliers = [], _products = [], _accounts = [];
  String _date = DateTime.now().toUtc().toIso8601String().substring(0, 10);
  String _supplierId = '', _method = 'Cash', _accountId = '';
  final _invoice = TextEditingController(), _notes = TextEditingController();
  final _headerDisc = TextEditingController(text: '0'), _tax = TextEditingController(text: '0'), _paid = TextEditingController(text: '0');
  final List<_Line> _lines = [_Line()];

  String get _base => genericBase(widget.company);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_invoice, _notes, _headerDisc, _tax, _paid]) {
      c.dispose();
    }
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final api = widget.session.farmClient;
    try {
      final r = await Future.wait([api.get('$_base/suppliers'), api.get('$_base/products'), api.get('$_base/cash-accounts')]);
      if (!mounted) return;
      setState(() {
        _suppliers = rowsOf(r[0]);
        _products = rowsOf(r[1]);
        _accounts = rowsOf(r[2]);
        final first = _accounts.where((a) => a['isActive'] == true).firstOrNull;
        if (first != null) _accountId = tStr(first['genericCashAccountId']);
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load options', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  num _n(TextEditingController c) => num.tryParse(c.text) ?? 0;
  num get _subtotal => _lines.fold<num>(0, (s, l) => s + l.total);
  num get _total => _subtotal - _n(_headerDisc) + _n(_tax);
  num get _balance => _total - _n(_paid);

  static String _plain(num v) => v == v.roundToDouble() ? v.toInt().toString() : '$v';

  void _pickProduct(_Line l, String? id) {
    final p = _products.where((x) => tStr(x['genericProductId']) == id).firstOrNull;
    setState(() {
      if (p == null) {
        l.productId = null;
        l.description = '';
        return;
      }
      l.productId = tIntOrNull(p['genericProductId']);
      l.description = tStr(p['productName']);
      if (tNum(p['costPrice']) > 0) l.unitCost.text = _plain(tNum(p['costPrice']));
    });
  }

  Future<void> _save() async {
    final items = [
      for (final l in _lines)
        if (l.qty > 0 && l.productId != null)
          {
            'genericProductId': l.productId,
            'description': l.description.isEmpty ? null : l.description,
            'quantity': l.qty,
            'unitCost': l.cost,
            'discountAmount': l.disc,
          },
    ];
    if (items.isEmpty) return trackerToast(context, 'Add at least one product line', error: true);
    if (_balance > 0 && _supplierId.isEmpty) return trackerToast(context, 'Credit purchase requires a supplier', error: true);
    setState(() => _saving = true);
    try {
      final created = await widget.session.farmClient.post('$_base/purchases', body: {
        'purchaseDate': _date,
        'genericSupplierId': _supplierId.isEmpty ? null : int.parse(_supplierId),
        'headerDiscountAmount': _n(_headerDisc),
        'taxAmount': _n(_tax),
        'amountPaid': _n(_paid),
        'paymentMethod': _method,
        'genericCashAccountId': _accountId.isEmpty ? null : int.parse(_accountId),
        'invoiceNumber': _invoice.text.isEmpty ? null : _invoice.text,
        'notes': _notes.text.isEmpty ? null : _notes.text,
        'items': items,
        'farmId': widget.company.farmId,
      });
      if (created is Map && mounted) {
        trackerToast(context, 'Purchase #${tStr(created['genericPurchaseId'])} created as Draft',
            description: 'Review and approve to bump inventory and cash.');
        Navigator.of(context).pop(true);
        return;
      }
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not create purchase', description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  Widget _num(TextEditingController c, {int decimals = 2}) => AppInput(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp('^\\d*\\.?\\d{0,$decimals}'))],
        onChanged: (_) => setState(() {}),
      );

  Widget _small(String label, Widget child) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
        const SizedBox(height: 2),
        child,
      ]);

  Widget _lineCard(_Line l) => Container(
        key: l.key,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: AppSelect<String>(
                value: l.productId == null ? null : '${l.productId}',
                hintText: '— select product —',
                items: [
                  for (final p in _products)
                    AppSelectItem(
                      value: tStr(p['genericProductId']),
                      label: '${tStr(p['productName'])}${tStr(p['sku']).isEmpty ? '' : ' (${tStr(p['sku'])})'}',
                    ),
                ],
                onChanged: (v) => _pickProduct(l, v),
              ),
            ),
            IconButton(
              tooltip: 'Remove row',
              onPressed: () => setState(() {
                _lines.remove(l);
                l.dispose();
              }),
              icon: const Icon(Icons.close, size: 18, color: TColors.rose600),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _small('Qty', _num(l.quantity, decimals: 3))),
            const SizedBox(width: 8),
            Expanded(child: _small('Unit cost', _num(l.unitCost))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _small('Discount', _num(l.discount))),
            const SizedBox(width: 8),
            Expanded(
              child: _small(
                'Line total',
                SizedBox(
                  height: 40,
                  child: Align(alignment: Alignment.centerRight, child: Text(fmtMoney(l.total), style: const TextStyle(fontWeight: FontWeight.w600))),
                ),
              ),
            ),
          ]),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final balance = _balance;
    return Scaffold(
      appBar: AppBar(title: const Text('New purchase')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
        children: [
          genericBackLink(context, 'Back to purchases'),
          const Row(children: [
            Icon(Icons.inventory_2_outlined, size: 24, color: genericOrange),
            SizedBox(width: 8),
            Expanded(child: Text('New purchase', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900))),
          ]),
          const SizedBox(height: 14),
          if (_loading)
            const LoadingLine('Loading…')
          else ...[
            genericCard(null, [
              FilterLabel(
                'Purchase date',
                AppDateField(value: businessDateAsDateTime(_date), onChanged: (d) => setState(() => _date = d == null ? _date : isoDay(d))),
              ),
              const SizedBox(height: 12),
              FilterLabel(
                'Supplier',
                AppSelect<String>(
                  value: _supplierId.isEmpty ? '__none__' : _supplierId,
                  items: [
                    const AppSelectItem(value: '__none__', label: '— none —'),
                    for (final s in _suppliers) AppSelectItem(value: tStr(s['genericSupplierId']), label: tStr(s['supplierName'])),
                  ],
                  onChanged: (v) => setState(() => _supplierId = v == null || v == '__none__' ? '' : v),
                ),
              ),
              const SizedBox(height: 12),
              FilterLabel('Invoice number', AppInput(controller: _invoice, inputFormatters: [LengthLimitingTextInputFormatter(60)])),
            ]),
            const SizedBox(height: 14),
            genericCard(null, [
              Row(children: [
                const Expanded(child: Text('Items', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: TColors.slate900))),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _lines.add(_Line())),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add row'),
                ),
              ]),
              const SizedBox(height: 10),
              for (var i = 0; i < _lines.length; i++) ...[if (i > 0) const SizedBox(height: 10), _lineCard(_lines[i])],
            ]),
            const SizedBox(height: 14),
            genericCard('Payment', [
              Row(children: [
                Expanded(child: FilterLabel('Discount (header)', _num(_headerDisc))),
                const SizedBox(width: 10),
                Expanded(child: FilterLabel('Tax', _num(_tax))),
              ]),
              const SizedBox(height: 12),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: FilterLabel('Amount paid now', _num(_paid))),
                const SizedBox(width: 10),
                Expanded(
                  child: FilterLabel(
                    'Method',
                    AppSelect<String>(
                      value: _method,
                      items: [for (final m in genericPurchasePayMethods) AppSelectItem(value: m, label: m)],
                      onChanged: (v) => setState(() => _method = v ?? _method),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              FilterLabel(
                'Cash account (paid from)',
                AppSelect<String>(
                  value: _accountId.isEmpty ? '__none__' : _accountId,
                  items: [
                    const AppSelectItem(value: '__none__', label: '— none / credit —'),
                    for (final a in _accounts.where((a) => a['isActive'] == true))
                      AppSelectItem(value: tStr(a['genericCashAccountId']), label: '${tStr(a['accountName'])} (${tStr(a['accountType'])})'),
                  ],
                  onChanged: (v) => setState(() => _accountId = v == null || v == '__none__' ? '' : v),
                ),
              ),
              const SizedBox(height: 12),
              FilterLabel('Notes', AppInput(controller: _notes, minLines: 2, maxLines: 4)),
            ]),
            const SizedBox(height: 14),
            genericCard('Totals', [
              genericTotalRow('Subtotal', fmtMoney(_subtotal)),
              genericTotalRow('Header discount', fmtMoney(_n(_headerDisc))),
              genericTotalRow('Tax', fmtMoney(_n(_tax))),
              genericTotalRow('Total', fmtMoney(_total), bold: true),
              genericTotalRow('Paid now', fmtMoney(_n(_paid)), color: TColors.emerald700),
              genericTotalRow('Balance owed to supplier', fmtMoney(balance), color: balance > 0 ? TColors.rose700 : null),
              const SizedBox(height: 14),
              Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
                OutlinedButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('Cancel')),
                FilledButton(
                  onPressed: _saving ? null : _save,
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
        ],
      ),
    );
  }
}
