import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/money/money_widgets.dart';
import '../poultry/sales/balances_logic.dart' show pageSlice;
import '../poultry/sales/balances_widgets.dart';
import '../poultry/sales/sale_dialogs.dart' show showPaymentHistory;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull, tBool;
import '../poultry/trackers/tracker_widgets.dart';

/// Water → Sales, Expenses & Money → Sales → Sales, as
/// `app/water-sales/page.tsx`: the sales list (phone cards), New water sale
/// with per-line selling units (migration 084) and "Paid now", Details,
/// Mark as Paid / Record payment, the payment history, and Delete for a direct
/// sale. [focusSaleId] is the page's `?saleId=` (Customer Balances and
/// Payments → open sale).
class WaterSalesScreen extends StatefulWidget {
  const WaterSalesScreen({super.key, required this.session, required this.company, this.focusSaleId});
  final Session session;
  final Company company;
  final int? focusSaleId;

  @override
  State<WaterSalesScreen> createState() => _WaterSalesScreenState();
}

/// The payment-method Select of the New sale and Record payment dialogs.
const waterSaleMethods = [('Cash', 'Cash'), ('Mobile Money', 'Mobile Money'), ('Bank', 'Bank transfer'), ('Cheque', 'Cheque')];

/// unitOptionsFor: a sachet product sells by Bag or Sachet; anything else by
/// its own unit.
List<String> waterUnitOptionsFor(Map? p) {
  if (p == null) return const ['Unit'];
  if (tBool(p['isSachetProduct'])) return const ['Bag', 'Sachet'];
  return [p['unit'] == null ? 'Unit' : tStr(p['unit'])];
}

/// priceFor: BagPrice / SachetPrice (migration 084), falling back to UnitPrice.
num waterPriceFor(Map p, String sellingUnit) {
  if (tBool(p['isSachetProduct'])) {
    if (sellingUnit == 'Bag') return tNum(p['bagPrice'] ?? p['unitPrice']);
    if (sellingUnit == 'Sachet') return tNum(p['sachetPrice'] ?? p['unitPrice']);
  }
  return tNum(p['unitPrice']);
}

/// `new Date(s).toLocaleString()`.
String waterLocaleDateTime(Object? v) {
  final d = DateTime.tryParse(tStr(v));
  if (d == null) return 'Invalid Date';
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.day}/${l.month}/${l.year}, ${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
}

String _f2(Object? v) => tNum(v).toStringAsFixed(2);

/// StatusBadge.
Widget waterSaleStatusBadge(Object? status) {
  final s = tStr(status);
  final (bg, fg) = switch (s) {
    'Paid' => (TColors.emerald100, TColors.emerald700),
    'PartiallyPaid' => (TColors.amber100, TColors.amber700),
    'Cancelled' => (TColors.rose100, TColors.rose700),
    _ => (TColors.slate100, TColors.slate700),
  };
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
    child: Text(s, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: fg)),
  );
}

/// MethodBadge: how the sale was paid (migration 225), or an em dash.
Widget waterMethodBadge(Object? method) {
  if (method == null || tStr(method).isEmpty) return const Text('—', style: TextStyle(color: TColors.slate400));
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(4)),
    child: Text(tStr(method), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: TColors.slate700)),
  );
}

class _WaterSalesScreenState extends State<WaterSalesScreen> {
  List<Map> _sales = [];
  List<Map> _products = [];
  List<Map> _customers = [];
  bool _loading = true;
  late int? _focusSaleId = widget.focusSaleId != null && widget.focusSaleId! > 0 ? widget.focusSaleId : null;

  final _search = TextEditingController();
  String _from = '', _to = '';
  int _page = 1;
  int _pageSize = 10;
  int _lastTotal = -1;

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  String? get _me => widget.session.tokens.userId;

  /// The web gates reversal on water.customer-payments.reverse; the phone has
  /// no permission flags, so Staff are the ones left out.
  bool get _canReverse => (widget.company.role ?? '').toLowerCase() != 'staff';

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final q = {'farmId': _farmId};
      final r = await Future.wait([
        _api.get('/api/Water/sales', query: q),
        _api.get('/api/Water/products', query: q),
        _api.get('/api/Water/customers', query: q),
      ]);
      if (mounted) {
        setState(() {
          _sales = rowsOf(r[0]);
          _products = rowsOf(r[1]);
          _customers = rowsOf(r[2]);
        });
      }
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load sales', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Only Finished Goods are sellable (migration 063).
  List<Map> get _saleable => [for (final p in _products) if (tBool(p['isActive']) && tStr(p['productType']) == 'FinishedGood') p];

  /// The focused sale wins over the other filters; otherwise
  /// filterByDateAndSearch on saleDate and customerName / status / notes.
  List<Map> get _visible {
    if (_focusSaleId != null) return [for (final s in _sales) if (tIntOrNull(s['waterSaleId']) == _focusSaleId) s];
    final q = _search.text.trim().toLowerCase();
    return _sales.where((r) {
      if (_from.isNotEmpty || _to.isNotEmpty) {
        final day = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(tStr(r['saleDate']))?[1];
        if (day != null) {
          if (_from.isNotEmpty && day.compareTo(_from) < 0) return false;
          if (_to.isNotEmpty && day.compareTo(_to) > 0) return false;
        }
      }
      if (q.isNotEmpty && !['customerName', 'status', 'notes'].any((k) => r[k] != null && '${r[k]}'.toLowerCase().contains(q))) {
        return false;
      }
      return true;
    }).toList();
  }

  bool _fromDelivery(Map s) => tStr(s['sourceType']) == 'DeliveryRun';
  bool _owing(Map s) => tStr(s['status']) != 'Cancelled' && tNum(s['balance']) > 0;
  int _id(Map s) => tIntOrNull(s['waterSaleId']) ?? 0;
  String _customer(Map s) => s['customerName'] == null ? 'Walk-in' : tStr(s['customerName']);

  Future<void> _newSale() async {
    final done = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => _NewWaterSaleScreen(
        session: widget.session,
        company: widget.company,
        products: _products,
        saleable: _saleable,
        customers: _customers,
      ),
    ));
    if (done == true) _loadAll();
  }

  Future<Map?> _fetch(int id) async {
    final res = await _api.get('/api/Water/sales/$id', query: {'farmId': _farmId});
    return res is Map ? res : null;
  }

  Future<void> _openDetail(Map sale) async {
    Map? detail;
    try {
      detail = await _fetch(_id(sale));
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load sale', description: e.message, error: true);
      return;
    }
    if (detail == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _WaterSaleDetailDialog(sale: detail!, onPay: _openPay, refetch: _fetch),
    );
  }

  /// openPay: the Record payment dialog for one sale, prefilled with its
  /// balance. True when a payment was recorded.
  Future<bool> _openPay(Map sale) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _WaterPaymentDialog(sale: sale, onRecord: _recordPayment),
    );
    if (ok == true) await _loadAll();
    return ok == true;
  }

  /// recordPayment. Returns true on success, so the dialog can close.
  Future<bool> _recordPayment(Map target, num amount, String method) async {
    if (amount <= 0) {
      trackerToast(context, 'Enter an amount', error: true);
      return false;
    }
    if (amount > tNum(target['balance']) + 0.001) {
      trackerToast(context, 'Amount exceeds balance', error: true);
      return false;
    }
    try {
      await _api.post('/api/Water/payments', body: {
        'waterSaleId': _id(target),
        'amount': amount,
        'paymentMethod': method,
        'farmId': _farmId,
        'createdBy': (_me ?? '').isEmpty ? null : _me,
      });
      if (mounted) trackerToast(context, 'Payment recorded');
      return true;
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Payment failed', description: e.message, error: true);
      return false;
    }
  }

  void _history(Map s) => showPaymentHistory(context,
      session: widget.session,
      company: widget.company,
      partyName: s['customerName'] == null ? null : tStr(s['customerName']),
      documentType: 'WaterSale',
      documentId: _id(s),
      canReverse: _canReverse,
      onReversed: _loadAll,
      api: '/api/Water');

  Future<void> _delete(Map s) async {
    final ok = await confirmDelete(context,
        title: 'Delete sale #${_id(s)}?',
        description: 'This permanently removes the sale and its payments, and restores the stock it took out. This cannot be undone.',
        confirmLabel: 'Delete sale');
    if (!ok) return;
    try {
      await _api.delete('/api/Water/sales/${_id(s)}', query: {'farmId': _farmId});
      if (mounted) trackerToast(context, 'Sale #${_id(s)} deleted', description: 'Stock was restored.');
      await _loadAll();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Delete failed', description: e.message, error: true);
    }
  }

  Widget _markPaid(Map s, {bool compact = false}) => FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: TColors.emerald600,
          foregroundColor: Colors.white,
          minimumSize: Size(0, compact ? 32 : 40),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        onPressed: () => _openPay(s),
        icon: const Icon(Icons.check_circle_outline, size: 16),
        label: const Text('Mark as Paid'),
      );

  /// The card's actions: Mark as Paid (owing), Details, and Delete — or
  /// "From delivery" for a sale its driver return owns.
  List<Widget> _cardActions(Map s) => [
        if (_owing(s)) Expanded(child: _markPaid(s)),
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 8)),
            onPressed: () => _openDetail(s),
            child: const Text('Details'),
          ),
        ),
        if (_fromDelivery(s))
          const Expanded(
            child: Tooltip(
              message: 'This sale came from a delivery — undo it from the delivery return.',
              child: SizedBox(
                height: 40,
                child: Center(child: Text('From delivery', style: TextStyle(fontSize: 12, color: TColors.slate400))),
              ),
            ),
          )
        else
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: TColors.red600,
                side: const BorderSide(color: TColors.red200),
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed: () => _delete(s),
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('Delete'),
            ),
          ),
      ];

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/water-sales');
    final visible = _visible;
    if (visible.length != _lastTotal) {
      _lastTotal = visible.length;
      _page = 1;
    }
    final pageRows = pageSlice(visible, _page, _pageSize);

    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Water sales')),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            const Row(children: [
              Icon(Icons.shopping_cart_outlined, size: 24, color: Color(0xFF0284C7)),
              SizedBox(width: 8),
              Expanded(child: Text('Water sales', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900))),
            ]),
            const SizedBox(height: 10),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
              onPressed: _newSale,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New sale'),
            ),
            const SizedBox(height: 16),
            if (_focusSaleId != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F9FF),
                  border: Border.all(color: const Color(0xFFBAE6FD)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(children: [
                  Expanded(
                    child: Text.rich(TextSpan(children: [
                      const TextSpan(text: 'Showing sale '),
                      TextSpan(text: 'W$_focusSaleId', style: const TextStyle(fontWeight: FontWeight.w700)),
                      const TextSpan(text: ' only.'),
                    ]), style: const TextStyle(fontSize: 13, color: TColors.sky900)),
                  ),
                  TextButton(onPressed: () => setState(() => _focusSaleId = null), child: const Text('Show all sales')),
                ]),
              ),
              const SizedBox(height: 12),
            ],
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
            if (_loading)
              const Padding(padding: EdgeInsets.all(16), child: LoadingLine('Loading…'))
            else if (_sales.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
                child: const Text('No sales yet.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate500)),
              )
            else if (visible.isNotEmpty)
              MobileCardList<Map>(
                striped: true,
                items: pageRows,
                keyOf: (s) => '${_id(s)}',
                primary: (s) => '#${_id(s)} · ${_customer(s)}',
                secondaryBuilder: (s) => Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(waterLocaleDateTime(s['saleDate'])),
                    const Text('·'),
                    waterSaleStatusBadge(s['status']),
                    const Text('·'),
                    Text.rich(TextSpan(children: [
                      const TextSpan(text: 'Paid '),
                      TextSpan(text: _f2(s['amountPaid']), style: const TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: ' / ${_f2(s['totalAmount'])}'),
                    ])),
                  ],
                ),
                highlights: (s) => [
                  Highlight('Total', _f2(s['totalAmount']), accent: Accent.blue),
                  Highlight('Paid', _f2(s['amountPaid']), accent: Accent.emerald),
                  Highlight('Balance', _f2(s['balance']), accent: tNum(s['balance']) > 0 ? Accent.rose : Accent.slate, wide: true),
                ],
                details: (s) => [
                  ('Date', waterLocaleDateTime(s['saleDate'])),
                  ('Customer', _customer(s)),
                  ('Method', s['paymentMethod'] == null || tStr(s['paymentMethod']).isEmpty ? '—' : tStr(s['paymentMethod'])),
                  ('Status', tStr(s['status'])),
                  ('Source', _fromDelivery(s) ? 'Delivery #${s['sourceId'] ?? '—'}' : 'Direct sale'),
                ],
                actions: (s) => [Row(children: _spaced(_cardActions(s)))],
                table: (items) => TrackerTable(
                  columns: const [
                    TCol('#', width: 60), TCol('Date', width: 170), TCol('Customer', width: 140),
                    TCol('Total', right: true, width: 100), TCol('Paid', right: true, width: 100), TCol('Balance', right: true, width: 100),
                    TCol('Method', width: 120), TCol('Status', width: 230), TCol('Actions', right: true, width: 330),
                  ],
                  rows: [
                    for (final s in items)
                      [
                        cellText('#${_id(s)}'),
                        cellText(waterLocaleDateTime(s['saleDate'])),
                        s['customerName'] == null ? cellText('Walk-in', color: TColors.slate400) : cellText(tStr(s['customerName'])),
                        Align(alignment: Alignment.centerRight, child: cellText(_f2(s['totalAmount']))),
                        Align(alignment: Alignment.centerRight, child: cellText(_f2(s['amountPaid']))),
                        Align(
                          alignment: Alignment.centerRight,
                          child: cellText(_f2(s['balance']), color: tNum(s['balance']) > 0 ? TColors.rose600 : TColors.slate500),
                        ),
                        Align(alignment: Alignment.centerLeft, child: waterMethodBadge(s['paymentMethod'])),
                        Row(children: [
                          waterSaleStatusBadge(s['status']),
                          if (_owing(s))
                            TextButton(
                              onPressed: () => _openPay(s),
                              style: TextButton.styleFrom(foregroundColor: TColors.rose600, textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                              child: const Text('Awaiting payment →'),
                            ),
                        ]),
                        Wrap(alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          if (_owing(s)) _markPaid(s, compact: true),
                          IconButton(tooltip: 'Payment history', onPressed: () => _history(s), icon: const Icon(Icons.history, size: 18)),
                          TextButton(onPressed: () => _openDetail(s), child: const Text('Details')),
                          if (_fromDelivery(s))
                            const Tooltip(
                              message: 'From a delivery — undo it from the delivery return.',
                              child: Text('From delivery', style: TextStyle(fontSize: 12, color: TColors.slate400)),
                            )
                          else
                            IconButton(
                              tooltip: 'Delete sale',
                              onPressed: () => _delete(s),
                              icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444)),
                            ),
                        ]),
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

  List<Widget> _spaced(List<Widget> xs) => [
        for (var i = 0; i < xs.length; i++) ...[if (i > 0) const SizedBox(width: 8), xs[i]],
      ];
}

// ------------------------------------------------------------------ new sale

class _Line {
  _Line(this.productId, this.sellingUnit, this.quantity, this.unitPrice);
  int productId;
  String sellingUnit;
  int quantity;
  num unitPrice;
  final qty = TextEditingController();
  final price = TextEditingController();
}

/// The "New water sale" dialog, as a page on the phone.
class _NewWaterSaleScreen extends StatefulWidget {
  const _NewWaterSaleScreen({
    required this.session,
    required this.company,
    required this.products,
    required this.saleable,
    required this.customers,
  });
  final Session session;
  final Company company;
  final List<Map> products;
  final List<Map> saleable;
  final List<Map> customers;

  @override
  State<_NewWaterSaleScreen> createState() => _NewWaterSaleScreenState();
}

class _NewWaterSaleScreenState extends State<_NewWaterSaleScreen> {
  int? _customerId;
  final List<_Line> _lines = [];
  bool _paidNow = false;
  String _paidMethod = 'Cash';
  final _notes = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _notes.dispose();
    for (final l in _lines) {
      l.qty.dispose();
      l.price.dispose();
    }
    super.dispose();
  }

  Map? _product(int id) => widget.products.where((p) => tIntOrNull(p['waterProductId']) == id).firstOrNull;

  num get _total => _lines.fold<num>(0, (a, l) => a + l.quantity * l.unitPrice);

  String _num(num v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';

  void _addLine() {
    if (widget.saleable.isEmpty) {
      trackerToast(context, 'Add a finished-good product first');
      return;
    }
    final first = widget.saleable.first;
    final unit = waterUnitOptionsFor(first).first;
    final l = _Line(tIntOrNull(first['waterProductId']) ?? 0, unit, 1, waterPriceFor(first, unit));
    l.qty.text = '1';
    l.price.text = _num(l.unitPrice);
    setState(() => _lines.add(l));
  }

  void _removeLine(int i) {
    final l = _lines.removeAt(i);
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      l.qty.dispose();
      l.price.dispose();
    });
  }

  /// Switching product resets the selling unit and its price.
  void _setProduct(_Line l, int id) {
    final p = _product(id);
    setState(() {
      l.productId = id;
      if (p != null) {
        l.sellingUnit = waterUnitOptionsFor(p).first;
        l.unitPrice = waterPriceFor(p, l.sellingUnit);
        l.price.text = _num(l.unitPrice);
      }
    });
  }

  /// Switching selling unit fills the matching price.
  void _setUnit(_Line l, String unit) {
    final p = _product(l.productId);
    setState(() {
      l.sellingUnit = unit;
      if (p != null) {
        l.unitPrice = waterPriceFor(p, unit);
        l.price.text = _num(l.unitPrice);
      }
    });
  }

  Future<void> _save() async {
    if (_lines.isEmpty) {
      trackerToast(context, 'Add at least one product', error: true);
      return;
    }
    if (_lines.any((l) => l.quantity < 1)) {
      trackerToast(context, 'Quantity must be ≥ 1', error: true);
      return;
    }
    setState(() => _saving = true);
    final api = widget.session.farmClient;
    final farmId = widget.company.farmId;
    final me = widget.session.tokens.userId;
    final createdBy = (me ?? '').isEmpty ? null : me;
    try {
      final created = await api.post('/api/Water/sales', body: {
        'waterCustomerId': _customerId,
        'notes': _notes.text.isEmpty ? null : _notes.text,
        'items': [
          for (final l in _lines) {'waterProductId': l.productId, 'quantity': l.quantity, 'unitPrice': l.unitPrice, 'sellingUnit': l.sellingUnit},
        ],
        'farmId': farmId,
        'createdBy': createdBy,
      });
      final id = created is Map ? tIntOrNull(created['waterSaleId']) : null;
      final total = _total;
      if (!mounted) return;
      if (_paidNow && id != null && id != 0 && total > 0) {
        try {
          await api.post('/api/Water/payments', body: {
            'waterSaleId': id,
            'amount': total,
            'paymentMethod': _paidMethod.isEmpty ? 'Cash' : _paidMethod,
            'farmId': farmId,
            'createdBy': createdBy,
          });
          if (mounted) trackerToast(context, 'Sale #$id recorded · Paid in full');
        } on ApiException catch (e) {
          // The sale is saved; say the payment failed, but don't roll back.
          if (mounted) {
            trackerToast(context, 'Sale #$id recorded, but payment failed',
                description: e.message.isEmpty ? 'You can record payment from the row.' : e.message, error: true);
          }
        }
      } else {
        trackerToast(context, 'Sale #${id ?? ''} recorded',
            description: total > 0 ? "Tap 'Mark as Paid' on the row when payment is collected." : null);
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Sale failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(t, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
      );

  Widget _productSelect(_Line l) => DropdownButtonFormField<int>(
        key: ValueKey('p${l.hashCode}|${l.productId}'),
        initialValue: widget.saleable.any((p) => tIntOrNull(p['waterProductId']) == l.productId) ? l.productId : null,
        isExpanded: true,
        itemHeight: null,
        onChanged: (v) {
          if (v != null) _setProduct(l, v);
        },
        selectedItemBuilder: (_) => [
          for (final p in widget.saleable)
            Align(
              alignment: Alignment.centerLeft,
              child: Text('${tStr(p['name'])} ${p['unit'] != null && tStr(p['unit']).isNotEmpty ? '(${tStr(p['unit'])})' : ''}',
                  overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
            ),
        ],
        items: [
          for (final p in widget.saleable)
            DropdownMenuItem<int>(
              value: tIntOrNull(p['waterProductId']),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('${tStr(p['name'])} ${p['unit'] != null && tStr(p['unit']).isNotEmpty ? '(${tStr(p['unit'])})' : ''}',
                    overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
                Text('stock ${tStr(p['stockOnHand'])}', style: const TextStyle(fontSize: 11, color: TColors.slate400)),
              ]),
            ),
        ],
      );

  Widget _lineCard(int i) {
    final l = _lines[i];
    final units = waterUnitOptionsFor(_product(l.productId));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _label('Product'),
      _productSelect(l),
      const SizedBox(height: 8),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          flex: 6,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _label('Selling Unit'),
            AppSelect<String>(
              value: units.contains(l.sellingUnit) ? l.sellingUnit : units.first,
              items: [for (final u in units) AppSelectItem(value: u, label: u)],
              onChanged: (v) {
                if (v != null) _setUnit(l, v);
              },
            ),
          ]),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _label('Qty'),
            AppNumberInput(
              controller: l.qty,
              hintText: '',
              onChanged: (v) => setState(() => l.quantity = int.tryParse(v.isEmpty ? '0' : v) ?? 0),
            ),
          ]),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _label('Unit Price'),
            AppNumberInput(
              controller: l.price,
              hintText: '',
              allowDecimal: true,
              onChanged: (v) => setState(() => l.unitPrice = num.tryParse(v.isEmpty ? '0' : v) ?? 0),
            ),
          ]),
        ),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            _label('Line Total'),
            Text((l.quantity * l.unitPrice).toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.slate700)),
          ]),
        ),
        IconButton(
          tooltip: 'Remove line',
          onPressed: () => _removeLine(i),
          icon: const Icon(Icons.close, size: 18, color: Color(0xFFEF4444)),
        ),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New water sale')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _label('Customer'),
          AppSelect<int>(
            value: _customerId ?? 0,
            hintText: 'Walk-in / cash',
            items: [
              const AppSelectItem(value: 0, label: 'Walk-in / cash'),
              for (final c in widget.customers)
                if (tIntOrNull(c['waterCustomerId']) != null) AppSelectItem(value: tIntOrNull(c['waterCustomerId'])!, label: tStr(c['name'])),
            ],
            onChanged: (v) => setState(() => _customerId = v == null || v == 0 ? null : v),
          ),
          const SizedBox(height: 12),
          Row(children: [
            const Expanded(child: Text('Items', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate900))),
            OutlinedButton.icon(onPressed: _addLine, icon: const Icon(Icons.add, size: 14), label: const Text('Add line')),
          ]),
          const SizedBox(height: 8),
          if (_lines.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(border: Border.all(color: TColors.slate300), borderRadius: BorderRadius.circular(6)),
              child: const Text.rich(
                TextSpan(children: [
                  TextSpan(text: 'No items. Click '),
                  TextSpan(text: 'Add line', style: TextStyle(fontWeight: FontWeight.w500)),
                  TextSpan(text: '.'),
                ]),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: TColors.slate400),
              ),
            )
          else
            for (var i = 0; i < _lines.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _lineCard(i),
            ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: Text.rich(TextSpan(children: [
              const TextSpan(text: 'Total: '),
              TextSpan(text: _total.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.w600)),
            ]), style: const TextStyle(fontSize: 14, color: TColors.slate900)),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: TColors.slate50, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Payment status', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate900)),
              const SizedBox(height: 4),
              RadioGroup<bool>(
                groupValue: _paidNow,
                onChanged: (v) => setState(() => _paidNow = v ?? false),
                child: Wrap(spacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                _radio('Pay later (pending)', false),
                _radio('Paid now', true),
                if (_paidNow)
                  SizedBox(
                    width: 192,
                    child: AppSelect<String>(
                      value: _paidMethod,
                      items: [for (final (v, l) in waterSaleMethods) AppSelectItem(value: v, label: l)],
                      onChanged: (v) => setState(() => _paidMethod = v ?? _paidMethod),
                    ),
                  ),
              ]),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _label('Notes'),
            AppInput(controller: _notes),
          ]),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _saving || _lines.isEmpty ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Record sale'),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _radio(String label, bool value) => InkWell(
        onTap: () => setState(() => _paidNow = value),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Radio<bool>(
            value: value,
            visualDensity: VisualDensity.compact,
          ),
          Flexible(child: Text(label, style: const TextStyle(fontSize: 14))),
        ]),
      );
}

// ------------------------------------------------------------------ detail

/// "Sale #N": customer, date, payment method, the money tiles, the items, and
/// Record payment while it is owed.
class _WaterSaleDetailDialog extends StatefulWidget {
  const _WaterSaleDetailDialog({required this.sale, required this.onPay, required this.refetch});
  final Map sale;
  final Future<bool> Function(Map sale) onPay;
  final Future<Map?> Function(int id) refetch;

  @override
  State<_WaterSaleDetailDialog> createState() => _WaterSaleDetailDialogState();
}

class _WaterSaleDetailDialogState extends State<_WaterSaleDetailDialog> {
  late Map _sale = widget.sale;

  Future<void> _pay() async {
    final ok = await widget.onPay(_sale);
    if (!ok || !mounted) return;
    try {
      final fresh = await widget.refetch(tIntOrNull(_sale['waterSaleId']) ?? 0);
      if (fresh != null && mounted) setState(() => _sale = fresh);
    } on ApiException {
      // The list reloads anyway; the dialog keeps what it had.
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _sale;
    final owing = tStr(s['status']) != 'Cancelled' && tNum(s['balance']) > 0;
    Widget kv(String k, Widget v) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            Text(k, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(width: 8),
            Expanded(child: Align(alignment: Alignment.centerRight, child: v)),
          ]),
        );
    Widget tile(String label, String value, Color color) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, letterSpacing: .5, color: TColors.slate500)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: color)),
              ),
            ]),
          ),
        );
    final items = rowsOf(s['items']);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: TColors.sky100, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.receipt_outlined, size: 16, color: Color(0xFF0284C7)),
            ),
            const SizedBox(width: 8),
            Flexible(child: Text('Sale #${tStr(s['waterSaleId'])}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
            const SizedBox(width: 8),
            waterSaleStatusBadge(s['status']),
          ]),
        ),
        const Divider(height: 1),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                decoration: BoxDecoration(color: TColors.slate50, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
                child: Column(children: [
                  kv('Customer', Text(s['customerName'] == null ? 'Walk-in' : tStr(s['customerName']),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: TColors.slate900))),
                  const Divider(height: 1),
                  kv('Date', Text(waterLocaleDateTime(s['saleDate']), style: const TextStyle(fontSize: 13, color: TColors.slate700))),
                  const Divider(height: 1),
                  kv('Payment method', waterMethodBadge(s['paymentMethod'])),
                ]),
              ),
              const SizedBox(height: 14),
              Row(children: [
                tile('Total', _f2(s['totalAmount']), TColors.slate900),
                const SizedBox(width: 8),
                tile('Paid', _f2(s['amountPaid']), TColors.emerald700),
                const SizedBox(width: 8),
                tile('Balance', _f2(s['balance']), tNum(s['balance']) > 0 ? TColors.rose600 : TColors.emerald700),
              ]),
              const SizedBox(height: 14),
              const Text('ITEMS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: .5, color: TColors.slate500)),
              const SizedBox(height: 6),
              TrackerTable(
                columns: const [
                  TCol('Product', width: 140), TCol('Selling Unit', width: 150), TCol('Qty', right: true, width: 60),
                  TCol('Unit Price', right: true, width: 90), TCol('Line Total', right: true, width: 100),
                ],
                rows: [
                  for (final it in items)
                    [
                      cellText(tStr(it['productName']), bold: true),
                      Text.rich(TextSpan(children: [
                        TextSpan(text: it['sellingUnit'] == null ? '—' : tStr(it['sellingUnit'])),
                        if (it['baseUnit'] != null && it['baseQuantity'] != null && it['sellingUnit'] != null && it['sellingUnit'] != it['baseUnit'])
                          TextSpan(
                            text: ' (${_grouped(tNum(it['baseQuantity']))} ${tStr(it['baseUnit'])})',
                            style: const TextStyle(fontSize: 12, color: TColors.slate400),
                          ),
                      ]), style: const TextStyle(color: TColors.slate600)),
                      Align(alignment: Alignment.centerRight, child: cellText(tStr(it['quantity']))),
                      Align(alignment: Alignment.centerRight, child: cellText(_f2(it['unitPrice']))),
                      Align(
                        alignment: Alignment.centerRight,
                        child: cellText((it['lineTotal'] != null ? tNum(it['lineTotal']) : tNum(it['quantity']) * tNum(it['unitPrice'])).toStringAsFixed(2), bold: true),
                      ),
                    ],
                ],
              ),
            ]),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
            if (owing)
              FilledButton.icon(onPressed: _pay, icon: const Icon(Icons.account_balance_wallet_outlined, size: 16), label: const Text('Record payment')),
            OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ]),
        ),
      ]),
    );
  }
}

/// `Number(n).toLocaleString()`.
String _grouped(num n) {
  final neg = n < 0;
  final abs = n.abs();
  final whole = abs.truncate();
  final frac = abs - whole;
  final s = whole.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  var out = s;
  if (frac > 0) {
    final f = (frac * 1000).round();
    if (f > 0) out = '$s.${f.toString().padLeft(3, '0').replaceAll(RegExp(r'0+$'), '')}';
  }
  return neg ? '-$out' : out;
}

// ------------------------------------------------------------------ payment

/// "Record payment · Sale #N": Amount (the balance by default) and Method.
class _WaterPaymentDialog extends StatefulWidget {
  const _WaterPaymentDialog({required this.sale, required this.onRecord});
  final Map sale;
  final Future<bool> Function(Map target, num amount, String method) onRecord;

  @override
  State<_WaterPaymentDialog> createState() => _WaterPaymentDialogState();
}

class _WaterPaymentDialogState extends State<_WaterPaymentDialog> {
  late final _amount = TextEditingController(text: _initial());
  String _method = 'Cash';
  bool _saving = false;

  String _initial() {
    final b = tNum(widget.sale['balance']);
    if (b == 0) return '';
    return b == b.roundToDouble() ? '${b.toInt()}' : '$b';
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _record() async {
    setState(() => _saving = true);
    final ok = await widget.onRecord(widget.sale, num.tryParse(_amount.text.isEmpty ? '0' : _amount.text) ?? 0, _method);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Record payment · Sale #${tStr(widget.sale['waterSaleId'])}'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FilterLabel('Amount', AppNumberInput(controller: _amount, hintText: '', allowDecimal: true)),
        const SizedBox(height: 12),
        FilterLabel(
          'Method',
          AppSelect<String>(
            value: _method,
            items: [for (final (v, l) in waterSaleMethods) AppSelectItem(value: v, label: l)],
            onChanged: (v) => setState(() => _method = v ?? _method),
          ),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _record, child: Text(_saving ? 'Saving…' : 'Record')),
      ],
    );
  }
}
