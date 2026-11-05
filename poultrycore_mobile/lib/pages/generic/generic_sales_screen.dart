// Generic → Sales → Sales, as `app/generic-sales/page.tsx`, with its two
// sub-pages: New sale (`app/generic-sales/new`) and the sale itself
// (`app/generic-sales/[id]`). A sale is created as a Draft; approving it
// moves stock, cash and the customer ledger; an approved sale can be refunded.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

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
import 'generic_kit.dart';
import 'package:poultrycore_mobile/design/tone.dart';
import 'generic_products_screen.dart' show genericEmptyCard;
import 'reports/generic_report_kit.dart' show fmtMoney;

const genericSaleStatuses = ['All', 'Draft', 'Approved', 'Refunded', 'Cancelled'];
const genericSalesTypes = [
  'WalkInSale', 'CustomerSale', 'ProductSale', 'ServiceSale', 'MixedSale',
  'CreditSale', 'OnlineSale', 'DeliverySale', 'WholesaleSale', 'RetailSale',
];
const genericSalePayMethods = ['Cash', 'MoMo', 'Bank', 'Card', 'Mixed', 'Credit'];

/// statusBadgeClass: Approved emerald, Cancelled rose, Refunded amber, else slate.
Widget genericSaleBadge(Object? status) {
  final (bg, fg) = switch (tStr(status)) {
    'Approved' => (TColors.emerald100, TColors.emerald800),
    'Cancelled' => (TColors.rose100, TColors.rose800),
    'Refunded' => (TColors.amber100, TColors.amber800),
    _ => (TColors.slate100, TColors.slate800),
  };
  return TBadge(tStr(status), bg: bg, fg: fg);
}

/// The list's filters: search (customer, status, notes) and dates on saleDate.
List<Map> filterGenericSales(List<Map> rows, {String search = '', String from = '', String to = ''}) {
  final q = search.trim().toLowerCase();
  return rows.where((r) {
    final day = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(tStr(r['saleDate']))?[1];
    if (day != null) {
      if (from.isNotEmpty && day.compareTo(from) < 0) return false;
      if (to.isNotEmpty && day.compareTo(to) > 0) return false;
    }
    if (q.isNotEmpty && !['customerName', 'status', 'notes'].any((k) => tStr(r[k]).toLowerCase().contains(q))) return false;
    return true;
  }).toList();
}

String _customer(Map s) => tStr(s['customerName']).isEmpty ? 'Walk-in' : tStr(s['customerName']);

/// A label / value line of the Totals cards.
Widget genericTotalRow(String label, String value, {bool bold = false, Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(
          child: Text(label, style: TextStyle(fontSize: 14, color: bold ? TColors.slate900 : TColors.slate600, fontWeight: bold ? FontWeight.w600 : FontWeight.w400)),
        ),
        Text(value, style: TextStyle(fontSize: 14, color: color ?? TColors.slate900, fontWeight: bold || identical(color, TColors.rose700) ? FontWeight.w700 : FontWeight.w400)),
      ]),
    );

Widget genericCard(String? title, List<Widget> children, {bool smallTitle = false}) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Tone.bg(0xFFFFFFFF), border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (title != null) ...[
          Text(smallTitle ? title.toUpperCase() : title,
              style: smallTitle
                  ? const TextStyle(fontSize: 11, letterSpacing: .6, color: TColors.slate500)
                  : const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: TColors.slate900)),
          const SizedBox(height: 8),
        ],
        ...children,
      ]),
    );

Widget genericBackLink(BuildContext context, String label) => Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => Navigator.of(context).maybePop(),
        style: TextButton.styleFrom(foregroundColor: TColors.slate500, padding: EdgeInsets.zero),
        icon: const Icon(Icons.arrow_back, size: 14),
        label: Text(label, style: const TextStyle(fontSize: 13)),
      ),
    );

class GenericSalesScreen extends StatefulWidget {
  const GenericSalesScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<GenericSalesScreen> createState() => _GenericSalesScreenState();
}

class _GenericSalesScreenState extends State<GenericSalesScreen> {
  List<Map> _rows = [];
  bool _loading = true;
  String _status = 'All';
  final _search = TextEditingController();
  String _from = '', _to = '';
  Duration _offset = DateTime.now().timeZoneOffset;

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
    try {
      final r = rowsOf(await widget.session.farmClient
          .get('${genericBase(widget.company)}/sales', query: _status == 'All' ? null : {'status': _status}));
      if (mounted) setState(() => _rows = r);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load sales', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    _load();
  }

  void _new() => _push(GenericNewSaleScreen(session: widget.session, company: widget.company));
  void _open(Map s) => _push(GenericSaleDetailScreen(session: widget.session, company: widget.company, saleId: tIntOrNull(s['genericSaleId']) ?? 0));

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/generic-sales');
    final visible = filterGenericSales(_rows, search: _search.text, from: _from, to: _to);
    Color? balanceColor(Map s) => tNum(s['balance']) > 0 ? TColors.rose700 : null;
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Sales')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            const Row(children: [
              Icon(Icons.shopping_cart_outlined, size: 24, color: genericEmerald),
              SizedBox(width: 8),
              Expanded(child: Text('Sales', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900))),
            ]),
            Text('${_rows.length} ${_status == 'All' ? '' : _status.toLowerCase()} sale(s)', style: const TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 10),
            FilledButton.icon(onPressed: _new, icon: const Icon(Icons.add, size: 18), label: const Text('New sale')),
            const SizedBox(height: 12),
            Wrap(spacing: 4, runSpacing: 4, children: [
              for (final s in genericSaleStatuses)
                filterChipButton(s, s == _status, () {
                  if (s == _status) return;
                  setState(() => _status = s);
                  _load();
                }),
            ]),
            const SizedBox(height: 12),
            if (_loading)
              const LoadingLine('Loading...')
            else if (_rows.isEmpty)
              genericEmptyCard(
                '',
                child: Wrap(alignment: WrapAlignment.center, children: [
                  const Text('No sales yet. ', style: TextStyle(color: TColors.slate500)),
                  InkWell(
                    onTap: _new,
                    child: const Text('Record your first one →', style: TextStyle(color: TColors.emerald700, decoration: TextDecoration.underline)),
                  ),
                ]),
              )
            else ...[
              ListFiltersCard(
                search: _search,
                searchPlaceholder: 'Search customer, status or notes',
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
                keyOf: (s) => '${tIntOrNull(s['genericSaleId'])}',
                primary: (s) => '#${tStr(s['genericSaleId'])} · ${_customer(s)}',
                onPrimary: _open,
                secondary: (s) => '${fmtDateTime(s['saleDate'], s, _offset)} · ${tStr(s['salesType'])}',
                trailing: (s) => Padding(padding: const EdgeInsets.only(left: 6), child: genericSaleBadge(s['status'])),
                details: (s) => [
                  ('Date', fmtDateTime(s['saleDate'], s, _offset)),
                  ('Customer', _customer(s)),
                  ('Type', tStr(s['salesType'])),
                  ('Total', fmtMoney(s['totalAmount'])),
                  ('Paid', fmtMoney(s['amountPaid'])),
                  ('Balance', fmtMoney(s['balance'])),
                ],
                detailColor: (s, label) => label == 'Balance' ? balanceColor(s) : null,
                actions: (s) => [OutlinedButton(onPressed: () => _open(s), child: const Text('Details'))],
                table: (items) => TrackerTable(
                  columns: const [
                    TCol('#', width: 60), TCol('Date', width: 140), TCol('Customer', width: 140), TCol('Type', width: 110),
                    TCol('Total', right: true, width: 110), TCol('Paid', right: true, width: 110), TCol('Balance', right: true, width: 110),
                    TCol('Status', width: 100), TCol('', width: 90),
                  ],
                  rows: [
                    for (final s in items)
                      [
                        InkWell(
                          onTap: () => _open(s),
                          child: Text('#${tStr(s['genericSaleId'])}', style: const TextStyle(color: TColors.emerald700, decoration: TextDecoration.underline)),
                        ),
                        cellText(fmtDateTime(s['saleDate'], s, _offset)),
                        cellText(_customer(s)),
                        cellText(tStr(s['salesType'])),
                        Align(alignment: Alignment.centerRight, child: Text(fmtMoney(s['totalAmount']))),
                        Align(alignment: Alignment.centerRight, child: Text(fmtMoney(s['amountPaid']))),
                        Align(alignment: Alignment.centerRight, child: Text(fmtMoney(s['balance']), style: TextStyle(color: balanceColor(s)))),
                        Align(alignment: Alignment.centerLeft, child: genericSaleBadge(s['status'])),
                        TextButton(onPressed: () => _open(s), child: const Text('Details')),
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

// ------------------------------------------------------------------ new sale

class _Line {
  String itemType = 'Product';
  int? productId;
  final description = TextEditingController();
  final quantity = TextEditingController(text: '1');
  final unitPrice = TextEditingController(text: '0');
  final discount = TextEditingController(text: '0');
  final key = UniqueKey();

  num get qty => num.tryParse(quantity.text) ?? 0;
  num get price => num.tryParse(unitPrice.text) ?? 0;
  num get disc => num.tryParse(discount.text) ?? 0;
  num get total => qty * price - disc;

  void dispose() {
    for (final c in [description, quantity, unitPrice, discount]) {
      c.dispose();
    }
  }
}

class GenericNewSaleScreen extends StatefulWidget {
  const GenericNewSaleScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<GenericNewSaleScreen> createState() => _GenericNewSaleScreenState();
}

class _GenericNewSaleScreenState extends State<GenericNewSaleScreen> {
  bool _loading = true, _saving = false;
  List<Map> _customers = [], _products = [], _accounts = [];
  String _date = DateTime.now().toUtc().toIso8601String().substring(0, 10);
  String _customerId = '', _salesType = 'WalkInSale', _method = 'Cash', _accountId = '';
  final _receipt = TextEditingController(), _notes = TextEditingController();
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
    for (final c in [_receipt, _notes, _headerDisc, _tax, _paid]) {
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
      final r = await Future.wait([api.get('$_base/customers'), api.get('$_base/products'), api.get('$_base/cash-accounts')]);
      if (!mounted) return;
      setState(() {
        _customers = rowsOf(r[0]);
        _products = rowsOf(r[1]);
        _accounts = rowsOf(r[2]);
        // Default to the first active cash account.
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

  void _pickProduct(_Line l, String? id) {
    final p = _products.where((x) => tStr(x['genericProductId']) == id).firstOrNull;
    setState(() {
      if (p == null) {
        l.productId = null;
        l.description.text = '';
        return;
      }
      l.productId = tIntOrNull(p['genericProductId']);
      l.description.text = tStr(p['productName']);
      if (tNum(p['sellingPrice']) > 0) l.unitPrice.text = _plain(tNum(p['sellingPrice']));
    });
  }

  static String _plain(num v) => v == v.roundToDouble() ? v.toInt().toString() : '$v';

  Future<void> _save() async {
    final items = [
      for (final l in _lines)
        if (l.qty > 0 && (l.itemType == 'Service' || l.productId != null))
          {
            'itemType': l.itemType,
            'genericProductId': l.itemType == 'Product' ? l.productId : null,
            'genericServiceId': null,
            'description': l.description.text.isEmpty ? null : l.description.text,
            'quantity': l.qty,
            'unitPrice': l.price,
            'discountAmount': l.disc,
          },
    ];
    if (items.isEmpty) return trackerToast(context, 'Add at least one item', error: true);
    setState(() => _saving = true);
    try {
      final created = await widget.session.farmClient.post('$_base/sales', body: {
        'saleDate': _date,
        'genericCustomerId': _customerId.isEmpty ? null : int.parse(_customerId),
        'salesType': _salesType,
        'salesChannel': null,
        'headerDiscountAmount': _n(_headerDisc),
        'taxAmount': _n(_tax),
        'amountPaid': _n(_paid),
        'paymentMethod': _method,
        'genericCashAccountId': _accountId.isEmpty ? null : int.parse(_accountId),
        'receiptNumber': _receipt.text.isEmpty ? null : _receipt.text,
        'notes': _notes.text.isEmpty ? null : _notes.text,
        'items': items,
        'farmId': widget.company.farmId,
      });
      if (created is Map && mounted) {
        final id = tIntOrNull(created['genericSaleId']) ?? 0;
        trackerToast(context, 'Sale #$id created as Draft', description: 'Review and approve to commit it.');
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => GenericSaleDetailScreen(session: widget.session, company: widget.company, saleId: id)),
        );
        return;
      }
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not create sale', description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  Widget _num(TextEditingController c, {int decimals = 2, Key? key}) => AppInput(
        key: key,
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
        decoration: BoxDecoration(color: Tone.bg(0xFFFFFFFF), border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            SizedBox(
              width: 112,
              child: AppSelect<String>(
                value: l.itemType,
                items: const [AppSelectItem(value: 'Product', label: 'Product'), AppSelectItem(value: 'Service', label: 'Service')],
                onChanged: (v) => setState(() => l.itemType = v ?? l.itemType),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: l.itemType == 'Product'
                  ? AppSelect<String>(
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
                    )
                  : AppInput(controller: l.description, hintText: 'Service description'),
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
            Expanded(child: _small('Unit price', _num(l.unitPrice))),
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
    final balance = _total - _n(_paid);
    return Scaffold(
      appBar: AppBar(title: const Text('New sale')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
        children: [
          genericBackLink(context, 'Back to sales'),
          const Row(children: [
            Icon(Icons.shopping_cart_outlined, size: 24, color: genericEmerald),
            SizedBox(width: 8),
            Expanded(child: Text('New sale', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900))),
          ]),
          const SizedBox(height: 14),
          if (_loading)
            const LoadingLine('Loading…')
          else ...[
            genericCard(null, [
              FilterLabel(
                'Sale date',
                AppDateField(value: businessDateAsDateTime(_date), onChanged: (d) => setState(() => _date = d == null ? _date : isoDay(d))),
              ),
              const SizedBox(height: 12),
              FilterLabel(
                'Sales type',
                AppSelect<String>(
                  value: _salesType,
                  items: [for (final t in genericSalesTypes) AppSelectItem(value: t, label: t)],
                  onChanged: (v) => setState(() => _salesType = v ?? _salesType),
                ),
              ),
              const SizedBox(height: 12),
              FilterLabel(
                'Customer (optional)',
                AppSelect<String>(
                  value: _customerId.isEmpty ? '__walk_in__' : _customerId,
                  items: [
                    const AppSelectItem(value: '__walk_in__', label: '— Walk-in —'),
                    for (final c in _customers) AppSelectItem(value: tStr(c['genericCustomerId']), label: tStr(c['customerName'])),
                  ],
                  onChanged: (v) => setState(() => _customerId = v == null || v == '__walk_in__' ? '' : v),
                ),
              ),
              const SizedBox(height: 12),
              FilterLabel('Receipt no.', AppInput(controller: _receipt, inputFormatters: [LengthLimitingTextInputFormatter(60)])),
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
                Expanded(child: FilterLabel('Amount paid', _num(_paid))),
                const SizedBox(width: 10),
                Expanded(
                  child: FilterLabel(
                    'Method',
                    AppSelect<String>(
                      value: _method,
                      items: [for (final m in genericSalePayMethods) AppSelectItem(value: m, label: m)],
                      onChanged: (v) => setState(() => _method = v ?? _method),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              FilterLabel(
                'Cash account (receives payment)',
                AppSelect<String>(
                  value: _accountId.isEmpty ? '__none__' : _accountId,
                  items: [
                    const AppSelectItem(value: '__none__', label: '— none / credit sale —'),
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
              genericTotalRow('Paid', fmtMoney(_n(_paid)), color: TColors.emerald700),
              genericTotalRow('Balance', fmtMoney(balance), color: balance > 0 ? TColors.rose700 : null),
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

// -------------------------------------------------------------- sale detail

class GenericSaleDetailScreen extends StatefulWidget {
  const GenericSaleDetailScreen({super.key, required this.session, required this.company, required this.saleId});
  final Session session;
  final Company company;
  final int saleId;

  @override
  State<GenericSaleDetailScreen> createState() => _GenericSaleDetailScreenState();
}

class _GenericSaleDetailScreenState extends State<GenericSaleDetailScreen> {
  Map? _sale;
  bool _loading = true, _acting = false;

  int get _id => widget.saleId;
  String get _url => '${genericBase(widget.company)}/sales/$_id';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final s = await widget.session.farmClient.get(_url);
      if (mounted) setState(() => _sale = s is Map ? s : null);
    } on ApiException catch (e) {
      // getSale: a missing sale is null (Sale not found), anything else a toast.
      if (mounted && e.statusCode != 404) trackerToast(context, 'Could not load sale', description: e.message, error: true);
      if (mounted) setState(() => _sale = null);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _act(String path, String okTitle, String? okDesc, String failTitle, {Map<String, dynamic> body = const {}}) async {
    setState(() => _acting = true);
    try {
      await widget.session.farmClient.post('$_url/$path', body: body);
      if (mounted) trackerToast(context, okTitle, description: okDesc);
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, failTitle, description: e.message, error: true);
    }
    if (mounted) setState(() => _acting = false);
  }

  Future<bool> _confirm(String title, String description, String cancel, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(description),
          actions: [
            OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: Text(cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
          ],
        ),
      ) ==
      true;

  Future<void> _cancel() async {
    if (!await _confirm('Cancel this draft sale?',
        'This marks the sale as Cancelled. It has no inventory or cash impact (the sale was never approved).', 'Keep it', 'Yes, cancel')) {
      return;
    }
    await _act('cancel', 'Sale #$_id cancelled.', null, 'Cancel failed');
  }

  Future<void> _refund() async {
    if (!await _confirm(
        'Refund this sale?',
        'This will return inventory to stock, refund the cash from the receiving account, and reverse any credit on the customer ledger. All three are atomic.',
        'Cancel',
        'Yes, refund')) {
      return;
    }
    await _act('refund', 'Sale #$_id refunded', 'Stock + cash + customer ledger reversed.', 'Refund failed');
  }

  /// `new Date(saleDate).toLocaleString()`.
  static String _when(Object? raw) {
    final d = DateTime.tryParse(tStr(raw));
    return d == null ? tStr(raw) : DateFormat('M/d/y, h:mm:ss a').format(d.isUtc ? d.toLocal() : d);
  }

  @override
  Widget build(BuildContext context) {
    final s = _sale;
    return Scaffold(
      appBar: AppBar(title: Text('Sale #$_id')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
          children: [
            genericBackLink(context, 'Back to sales'),
            if (_loading && s == null)
              const LoadingLine('Loading…')
            else if (s == null)
              genericEmptyCard('Sale not found.')
            else ...[
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
                Text('Sale #${tStr(s['genericSaleId'])}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900)),
                genericSaleBadge(s['status']),
              ]),
              Text(_when(s['saleDate']), style: const TextStyle(fontSize: 13, color: TColors.slate500)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (tStr(s['status']) == 'Draft') ...[
                  FilledButton.icon(
                    onPressed: _acting ? null : () => _act('approve', 'Sale #$_id approved', 'Inventory, cash and customer ledger updated.', 'Approve failed'),
                    style: FilledButton.styleFrom(backgroundColor: Tone.button(TColors.emerald600)),
                    icon: _acting
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check, size: 16),
                    label: const Text('Approve'),
                  ),
                  OutlinedButton.icon(onPressed: _acting ? null : _cancel, icon: const Icon(Icons.delete_outline, size: 16), label: const Text('Cancel')),
                ],
                if (tStr(s['status']) == 'Approved') OutlinedButton(onPressed: _acting ? null : _refund, child: const Text('Refund')),
              ]),
              const SizedBox(height: 14),
              genericCard('Items', [
                for (final i in rowsOf(s['items']))
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: TColors.slate100))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        Expanded(
                          child: Text(
                            tStr(i['description']).isNotEmpty
                                ? tStr(i['description'])
                                : i['genericProductId'] != null
                                    ? 'Product #${tStr(i['genericProductId'])}'
                                    : 'Service #${tStr(i['genericServiceId'])}',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                        Text(fmtMoney(i['lineTotal'] ?? 0), style: const TextStyle(fontWeight: FontWeight.w600)),
                      ]),
                      Text(
                        '${tStr(i['itemType'])} · Qty ${tStr(i['quantity'])} × ${fmtMoney(i['unitPrice'])} · Discount ${fmtMoney(i['discountAmount'])}',
                        style: const TextStyle(fontSize: 12, color: TColors.slate500),
                      ),
                    ]),
                  ),
              ], smallTitle: true),
              const SizedBox(height: 14),
              genericCard('Totals', [
                genericTotalRow('Subtotal', fmtMoney(s['subtotalAmount'])),
                genericTotalRow('Discount', fmtMoney(s['discountAmount'])),
                genericTotalRow('Tax', fmtMoney(s['taxAmount'])),
                genericTotalRow('Total', fmtMoney(s['totalAmount']), bold: true),
                genericTotalRow('Paid (${tStr(s['paymentMethod']).isEmpty ? '—' : tStr(s['paymentMethod'])})', fmtMoney(s['amountPaid']), color: TColors.emerald700),
                genericTotalRow('Balance', fmtMoney(s['balance']), color: tNum(s['balance']) > 0 ? TColors.rose700 : null),
              ], smallTitle: true),
              const SizedBox(height: 14),
              genericCard('Header', [
                Text.rich(TextSpan(text: 'Customer: ', children: [TextSpan(text: _customer(s), style: const TextStyle(fontWeight: FontWeight.w700))])),
                Text('Type: ${tStr(s['salesType'])}${tStr(s['salesChannel']).isEmpty ? '' : ' / ${tStr(s['salesChannel'])}'}'),
                Text('Receipt: ${tStr(s['receiptNumber']).isEmpty ? '—' : tStr(s['receiptNumber'])}'),
                Text.rich(TextSpan(text: 'Payment status: ', children: [
                  TextSpan(text: tStr(s['paymentStatus']), style: const TextStyle(fontWeight: FontWeight.w700)),
                ])),
                if (tStr(s['notes']).isNotEmpty) ...[const Divider(height: 16), Text(tStr(s['notes']))],
              ], smallTitle: true),
            ],
          ],
        ),
      ),
    );
  }
}
