// Restaurant → Orders & Kitchen → POS / New Order, as
// `app/restaurant-pos/page.tsx`. On the web the menu and the order panel sit
// side by side (stacked on a phone); here the menu fills the screen and the
// order panel — order type, table, customer, the cart and Place Order, then
// the placed order with Pay — opens from the bar at the bottom.
//
// Placing an order: create it, add each line, recalc (the server applies the
// tax and service charge saved in Restaurant Setup), and enrol a named
// customer in loyalty. Paying in full completes it and shows the receipt:
// Close, Email, Download PDF and Print Receipt.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/reports/report_export.dart' show ReportExport;
import '../poultry/sales/balances_widgets.dart' show LoadingLine;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr;
import '../poultry/trackers/tracker_widgets.dart';
import 'restaurant_order_money.dart';
import 'restaurant_roles.dart' show restaurantRose;
import 'restaurant_widgets.dart' show restaurantImage;

class PosCartLine {
  PosCartLine(this.menuItemId, this.name, this.price);
  final int menuItemId;
  final String name;
  final num price;
  int quantity = 1;
  String notes = '';
}

/// The receipt the POS shows once an order is paid in full. `amount` is what
/// the customer handed over; `change` what went back.
class PosReceipt {
  const PosReceipt(this.order, this.items, {required this.method, required this.amount, required this.tip, required this.change});
  final Map order;
  final List<Map> items;
  final String method;
  final double amount;
  final double tip;
  final double change;
}

String _when(Object? createdAt) {
  final d = DateTime.tryParse(tStr(createdAt));
  return DateFormat('d/M/yyyy, HH:mm:ss').format((d ?? DateTime.now()).toLocal());
}

/// Download PDF (A5): header, order facts, the item table, totals, payment.
Future<Uint8List> posInvoicePdf(PosReceipt r, String farmName, Map? template) async {
  final o = r.order;
  final doc = pw.Document();
  pw.Widget right(String k, String v, {bool bold = false}) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
        pw.SizedBox(width: 60, child: pw.Text(k, style: pw.TextStyle(fontSize: bold ? 11 : 9, fontWeight: bold ? pw.FontWeight.bold : null))),
        pw.SizedBox(
            width: 50,
            child: pw.Text(v, textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: bold ? 11 : 9, fontWeight: bold ? pw.FontWeight.bold : null))),
      ]);
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a5,
    margin: const pw.EdgeInsets.all(28),
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Text(farmName, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
      if (tStr(template?['headerText']).isNotEmpty) pw.Text(tStr(template?['headerText']), textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 9)),
      pw.Text('INVOICE / RECEIPT', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 10)),
      pw.SizedBox(height: 10),
      pw.Text('Date: ${_when(o['createdAt'])}', style: const pw.TextStyle(fontSize: 9)),
      pw.Text('Order: ${tStr(o['orderNumber'])}', style: const pw.TextStyle(fontSize: 9)),
      pw.Text('Type: ${tStr(o['orderType'])}${tStr(o['tableNumber']).isNotEmpty ? ' | Table ${tStr(o['tableNumber'])}' : ''}',
          style: const pw.TextStyle(fontSize: 9)),
      if (tStr(o['customerName']).isNotEmpty) pw.Text('Customer: ${tStr(o['customerName'])}', style: const pw.TextStyle(fontSize: 9)),
      pw.SizedBox(height: 8),
      pw.TableHelper.fromTextArray(
        headers: ['Qty', 'Item', 'Price'],
        data: [for (final i in r.items) ['${tNum(i['quantity']).toInt()}', tStr(i['itemName']), tNum(i['lineTotal']).toStringAsFixed(2)]],
        headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF0F0F0)),
        cellStyle: const pw.TextStyle(fontSize: 9),
        border: null,
        columnWidths: {0: const pw.FixedColumnWidth(30), 2: const pw.FixedColumnWidth(55)},
        cellAlignments: {0: pw.Alignment.center, 2: pw.Alignment.centerRight},
      ),
      pw.SizedBox(height: 8),
      right('Subtotal:', tNum(o['subtotal']).toStringAsFixed(2)),
      if (tNum(o['discountAmount']) > 0) right('Discount:', '-${tNum(o['discountAmount']).toStringAsFixed(2)}'),
      if (tNum(o['serviceChargeAmount']) > 0) right('Service:', tNum(o['serviceChargeAmount']).toStringAsFixed(2)),
      if (tNum(o['taxAmount']) > 0) right('Tax:', tNum(o['taxAmount']).toStringAsFixed(2)),
      right('Total:', tNum(o['totalAmount']).toStringAsFixed(2), bold: true),
      pw.SizedBox(height: 8),
      pw.Text('Payment: ${r.method}', style: const pw.TextStyle(fontSize: 9)),
      pw.Text('Amount Paid: ${r.amount.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 9)),
      if (r.change > 0) pw.Text('Change: ${r.change.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 9)),
      if (r.tip > 0) pw.Text('Tip: ${r.tip.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 9)),
      pw.SizedBox(height: 10),
      pw.Text('Thank you for dining with us!', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 9)),
      if (tStr(template?['footerText']).isNotEmpty) pw.Text(tStr(template?['footerText']), textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 9)),
      pw.Text('Powered by PoultryMaster', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey)),
    ]),
  ));
  return doc.save();
}

/// The emailed receipt (A5): the same header, the item grid and the total.
Future<Uint8List> posEmailPdf(PosReceipt r, String farmName, Map? template) async {
  final o = r.order;
  final doc = pw.Document();
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a5,
    margin: const pw.EdgeInsets.all(28),
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Text(farmName, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
      if (tStr(template?['headerText']).isNotEmpty) pw.Text(tStr(template?['headerText']), textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 8)),
      pw.Text('Order: ${tStr(o['orderNumber'])} | ${tStr(o['orderType'])}${tStr(o['tableNumber']).isNotEmpty ? ' | Table ${tStr(o['tableNumber'])}' : ''}',
          textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 9)),
      pw.Text(_when(o['createdAt']), textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 9)),
      pw.SizedBox(height: 8),
      pw.TableHelper.fromTextArray(
        headers: ['Item', 'Qty', 'Price', 'Total'],
        data: [
          for (final i in r.items)
            [tStr(i['itemName']), '${tNum(i['quantity']).toInt()}', tNum(i['unitPrice']).toStringAsFixed(2), tNum(i['lineTotal']).toStringAsFixed(2)],
        ],
        headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
        headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFBE123C)),
        cellStyle: const pw.TextStyle(fontSize: 8),
      ),
      pw.SizedBox(height: 8),
      pw.Text('Total: ${tNum(o['totalAmount']).toStringAsFixed(2)}', textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 10)),
      pw.SizedBox(height: 10),
      pw.Text('Thank you for dining with us!', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 9)),
    ]),
  ));
  return doc.save();
}

/// Print Receipt: the on-screen receipt on an 80 mm roll.
Future<Uint8List> posRollPdf(PosReceipt r, String farmName, Map? template) async {
  final o = r.order;
  final doc = pw.Document();
  final mono = pw.Font.courier();
  final bold = pw.Font.courierBold();
  pw.Widget row(String k, String v, {bool strong = false}) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Expanded(child: pw.Text(k, style: pw.TextStyle(font: strong ? bold : mono, fontSize: strong ? 11 : 9))),
        pw.Text(v, style: pw.TextStyle(font: strong ? bold : mono, fontSize: strong ? 11 : 9)),
      ]);
  final dash = pw.Container(margin: const pw.EdgeInsets.symmetric(vertical: 5), height: .6, color: PdfColors.black);
  doc.addPage(pw.Page(
    pageFormat: const PdfPageFormat(80 * PdfPageFormat.mm, double.infinity, marginAll: 4 * PdfPageFormat.mm),
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Text(farmName, textAlign: pw.TextAlign.center, style: pw.TextStyle(font: bold, fontSize: 13)),
      if (tStr(template?['headerText']).isNotEmpty)
        pw.Text(tStr(template?['headerText']), textAlign: pw.TextAlign.center, style: pw.TextStyle(font: mono, fontSize: 8)),
      pw.Text(_when(o['createdAt']), textAlign: pw.TextAlign.center, style: pw.TextStyle(font: mono, fontSize: 8)),
      pw.Text('Order: ${tStr(o['orderNumber'])}', textAlign: pw.TextAlign.center, style: pw.TextStyle(font: bold, fontSize: 9)),
      pw.Text('${tStr(o['orderType'])}${tStr(o['tableNumber']).isNotEmpty ? ' | Table ${tStr(o['tableNumber'])}' : ''}',
          textAlign: pw.TextAlign.center, style: pw.TextStyle(font: mono, fontSize: 9)),
      if (tStr(o['customerName']).isNotEmpty)
        pw.Text('Customer: ${tStr(o['customerName'])}', textAlign: pw.TextAlign.center, style: pw.TextStyle(font: mono, fontSize: 9)),
      dash,
      for (final i in r.items) row('${tNum(i['quantity']).toInt()} x ${tStr(i['itemName'])}', tNum(i['lineTotal']).toStringAsFixed(2)),
      dash,
      row('Subtotal', tNum(o['subtotal']).toStringAsFixed(2)),
      if (tNum(o['discountAmount']) > 0) row('Discount', '-${tNum(o['discountAmount']).toStringAsFixed(2)}'),
      if (tNum(o['serviceChargeAmount']) > 0) row('Service charge', tNum(o['serviceChargeAmount']).toStringAsFixed(2)),
      if (tNum(o['taxAmount']) > 0) row('Tax', tNum(o['taxAmount']).toStringAsFixed(2)),
      row('TOTAL', tNum(o['totalAmount']).toStringAsFixed(2), strong: true),
      dash,
      row('Paid (${r.method})', r.amount.toStringAsFixed(2)),
      if (r.change > 0) row('Change', r.change.toStringAsFixed(2)),
      if (r.tip > 0) row('Tip', r.tip.toStringAsFixed(2)),
      dash,
      pw.Text('Thank you for dining with us!', textAlign: pw.TextAlign.center, style: pw.TextStyle(font: mono, fontSize: 9)),
      if (tStr(template?['footerText']).isNotEmpty)
        pw.Text(tStr(template?['footerText']), textAlign: pw.TextAlign.center, style: pw.TextStyle(font: mono, fontSize: 8)),
      pw.Text('Powered by PoultryMaster', textAlign: pw.TextAlign.center, style: pw.TextStyle(font: mono, fontSize: 7, color: PdfColors.grey)),
    ]),
  ));
  return doc.save();
}

class RestaurantPosScreen extends StatefulWidget {
  const RestaurantPosScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<RestaurantPosScreen> createState() => _RestaurantPosScreenState();
}

class _RestaurantPosScreenState extends State<RestaurantPosScreen> {
  bool _loading = true;
  List<Map> _categories = [];
  List<Map> _items = [];
  List<Map> _tables = [];
  List<Map> _customers = [];
  Map? _template;
  int? _selectedCat;
  String _search = '';
  final List<PosCartLine> _cart = [];
  String _orderType = 'DineIn';
  int? _table;
  int? _customerId;
  String _customerName = '';
  Map? _activeOrder;
  List<Map> _activeItems = [];
  bool _placing = false;

  /// Repaints the open order panel when the page's state changes.
  final _tick = ValueNotifier<int>(0);

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  Map<String, dynamic> get _q => {'farmId': _farmId};
  String get _farmName => widget.company.name.isEmpty ? 'Restaurant' : widget.company.name;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tick.dispose();
    super.dispose();
  }

  void _set(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
    _tick.value++;
  }

  List<Map> _rows(Object? v) => [for (final x in (v is List ? v : const [])) if (x is Map) x];
  Future<List<Map>> _availableTables() async => _rows(await _api.get('/api/Restaurant/floor/tables', query: {..._q, '_': 1, 'status': 'Available'}));

  void _toast(String title, {String? description, bool error = false}) {
    if (mounted) trackerToast(context, title, description: description, error: error);
  }

  String _err(Object e) => e is ApiException ? e.message : '$e';

  Future<void> _load() async {
    try {
      final r = await Future.wait<Object?>([
        _api.get('/api/Restaurant/menu/categories', query: _q),
        _api.get('/api/Restaurant/menu/items', query: {..._q, '_': 1}),
        _availableTables(),
        _api.get('/api/Restaurant/crm/customers', query: {..._q, '_': 1}).catchError((Object _) => const []),
        _api.get('/api/Restaurant/expenses/receipt-template', query: _q).catchError((Object _) => null),
      ]);
      _categories = _rows(r[0]);
      _items = [for (final i in _rows(r[1])) if (i['isAvailable'] != false && i['isActive'] != false) i];
      _tables = _rows(r[2]);
      _customers = _rows(r[3]);
      _template = r[4] is Map ? r[4] as Map : null;
    } catch (e) {
      _toast('Failed to load', description: _err(e), error: true);
    }
    _set(() => _loading = false);
  }

  List<Map> get _filtered => [
        for (final i in _items)
          if ((_selectedCat == null || tNum(i['menuCategoryId']).toInt() == _selectedCat) &&
              (_search.isEmpty || tStr(i['name']).toLowerCase().contains(_search.toLowerCase())))
            i,
      ];

  void _add(Map item) => _set(() {
        final id = tNum(item['menuItemId']).toInt();
        final line = _cart.where((c) => c.menuItemId == id).firstOrNull;
        if (line != null) {
          line.quantity++;
        } else {
          _cart.add(PosCartLine(id, tStr(item['name']), tNum(item['price'])));
        }
      });

  int get _cartCount => _cart.fold(0, (n, c) => n + c.quantity);
  num get _cartTotal => _cart.fold<num>(0, (s, c) => s + c.price * c.quantity);

  Future<void> _placeOrder() async {
    if (_cart.isEmpty) {
      _toast('Cart is empty', error: true);
      return;
    }
    _set(() => _placing = true);
    try {
      final tableNum = _table == null ? null : _tables.where((t) => tNum(t['tableId']).toInt() == _table).firstOrNull?['tableNumber'];
      final created = await _api.post('/api/Restaurant/orders', body: {
        'orderType': _orderType,
        'tableId': _table,
        'tableNumber': ?tableNum,
        'customerId': ?_customerId,
        if (_customerName.isNotEmpty) 'customerName': _customerName,
        'covers': 1,
        'farmId': _farmId,
      });
      final orderId = created is Map ? created['orderId'] : null;
      final orderNumber = created is Map ? tStr(created['orderNumber']) : '';
      for (final c in _cart) {
        await _api.post('/api/Restaurant/orders/$orderId/items', body: {
          'menuItemId': c.menuItemId,
          'itemName': c.name,
          'quantity': c.quantity,
          'unitPrice': c.price,
          if (c.notes.isNotEmpty) 'notes': c.notes,
          'modifiers': const [],
          'farmId': _farmId,
          'orderId': orderId,
        });
      }
      // No rates: the server applies the ones saved in Restaurant Setup.
      await _api.post('/api/Restaurant/orders/$orderId/recalc', query: _q, body: {'taxRate': null, 'serviceChargeRate': null});
      if (_customerId != null || _customerName.isNotEmpty) {
        try {
          await _api.post('/api/Restaurant/loyalty/accounts',
              query: _q, body: {'customerName': _customerName.isEmpty ? 'Guest' : _customerName, 'customerId': ?_customerId});
        } catch (_) {/* already enrolled or loyalty off */}
      }
      _toast('Order $orderNumber placed!');
      final r = await Future.wait<Object?>([
        loadOrder(_api, _farmId, orderId),
        _api.get('/api/Restaurant/orders/$orderId/items', query: _q),
      ]);
      _activeOrder = r[0] as Map;
      _activeItems = _rows(r[1]);
      _cart.clear();
      _tables = await _availableTables();
    } catch (e) {
      _toast('Order failed', description: _err(e), error: true);
    }
    _set(() => _placing = false);
  }

  Future<void> _pay() async {
    final o = _activeOrder;
    if (o == null) return;
    final r = await showDialog<OrderPaymentResult>(context: context, builder: (_) => TakePaymentDialog(api: _api, farmId: _farmId, order: o));
    if (r == null) return;
    if (tStr(r.order['paymentStatus']) != 'Paid') {
      _set(() => _activeOrder = r.order);
      _toast('${r.applied.toStringAsFixed(2)} received',
          description:
              '${(tNum(r.order['totalAmount']) - tNum(r.order['paidAmount'])).toStringAsFixed(2)} still due on ${tStr(r.order['orderNumber'])}.');
      return;
    }
    try {
      await _api.patch('/api/Restaurant/orders/${r.order['orderId']}/status', query: _q, body: {'status': 'Completed'});
      _toast('Payment recorded & order completed');
      final receipt = PosReceipt(r.order, [..._activeItems], method: r.method, amount: r.tendered, tip: r.tip, change: r.change);
      _set(() {
        _activeOrder = null;
        _activeItems = [];
      });
      _tables = await _availableTables();
      _set(() {});
      if (!mounted) return;
      // The order panel is the page's sheet; the receipt opens over the page.
      Navigator.of(context).popUntil((route) => route is! ModalBottomSheetRoute);
      await showDialog<void>(context: context, builder: (_) => _ReceiptDialog(receipt: receipt, farmName: _farmName, template: _template, customers: _customers, api: _api));
    } catch (e) {
      _toast('Paid, but the order could not be completed', description: _err(e), error: true);
    }
  }

  Future<void> _openPanel() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (sheet) => FractionallySizedBox(
          heightFactor: .9,
          child: ValueListenableBuilder<int>(valueListenable: _tick, builder: (_, _, _) => _activeOrder != null ? _activePanel(sheet) : _cartPanel(sheet)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/restaurant-pos');
    final items = _filtered;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('POS / New Order')),
      body: _loading
          ? const Padding(padding: EdgeInsets.all(20), child: LoadingLine('Loading…'))
          : Column(children: [
              Container(
                color: const Color(0xFFF9FAFB),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    _catChip('All', _selectedCat == null, () => _set(() => _selectedCat = null)),
                    for (final c in _categories)
                      if (c['isActive'] != false)
                        _catChip(tStr(c['name']), _selectedCat == tNum(c['menuCategoryId']).toInt(),
                            () => _set(() => _selectedCat = tNum(c['menuCategoryId']).toInt())),
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: AppInput(
                  hintText: 'Search menu items...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  onChanged: (v) => _set(() => _search = v),
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.restaurant, size: 48, color: Color(0xFF9CA3AF)),
                          const SizedBox(height: 10),
                          const Text('No items found', style: TextStyle(fontWeight: FontWeight.w500, color: Color(0xFF9CA3AF))),
                          Text(_search.isNotEmpty ? 'Try a different search' : 'Add items to your menu first',
                              style: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
                        ]),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 8, crossAxisSpacing: 8, mainAxisExtent: 210),
                        itemCount: items.length,
                        itemBuilder: (_, i) => _itemTile(items[i]),
                      ),
              ),
              _bottomBar(),
            ]),
    );
  }

  Widget _catChip(String label, bool on, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: on
            ? FilledButton(style: FilledButton.styleFrom(backgroundColor: restaurantRose, visualDensity: VisualDensity.compact), onPressed: onTap, child: Text(label))
            : OutlinedButton(style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact), onPressed: onTap, child: Text(label)),
      );

  Widget _itemTile(Map item) {
    final url = tStr(item['imageUrl']);
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: TColors.slate200)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _add(item),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Container(
              color: const Color(0xFFF3F4F6),
              child: restaurantImage(url, fallback: const Icon(Icons.restaurant, size: 28, color: Color(0xFFD1D5DB))),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tStr(item['name']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              Text(tStr(item['categoryName']).isEmpty ? 'Uncategorized' : tStr(item['categoryName']),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                    child: Text(tNum(item['price']).toStringAsFixed(2),
                        style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFE11D48)))),
                if (tNum(item['prepTime']) > 0)
                  Text('${tNum(item['prepTime']).toInt()}m', style: const TextStyle(fontSize: 10, color: TColors.slate500)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _bottomBar() {
    final o = _activeOrder;
    final label = o != null
        ? '${tStr(o['orderNumber'])} · Pay ${(tNum(o['totalAmount']) - tNum(o['paidAmount'])).toStringAsFixed(2)}'
        : _cart.isEmpty
            ? 'New Order · cart is empty'
            : 'View order · $_cartCount item${_cartCount == 1 ? '' : 's'} · ${_cartTotal.toStringAsFixed(2)}';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: TColors.slate200))),
      child: SafeArea(
        top: false,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: o != null ? const Color(0xFF16A34A) : restaurantRose,
            minimumSize: const Size.fromHeight(50),
          ),
          onPressed: _openPanel,
          icon: Icon(o != null ? Icons.credit_card : Icons.shopping_cart_outlined, size: 18),
          label: Text(label),
        ),
      ),
    );
  }

  Widget _panelHeader(BuildContext sheet, Widget title, {Color? bg}) => Container(
        color: bg ?? const Color(0xFFF9FAFB),
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(children: [
          Expanded(child: title),
          IconButton(tooltip: 'Close', onPressed: () => Navigator.of(sheet).pop(), icon: const Icon(Icons.close, size: 18)),
        ]),
      );

  Widget _cartPanel(BuildContext sheet) {
    return Column(children: [
      _panelHeader(
        sheet,
        Row(children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: const Color(0xFFFFE4E6), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.shopping_cart_outlined, size: 16, color: Color(0xFFE11D48)),
          ),
          const SizedBox(width: 8),
          const Text('New Order', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        ]),
      ),
      Container(
        color: const Color(0xFFF9FAFB),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: AppSelect<String>(
                value: _orderType,
                items: const [
                  AppSelectItem(value: 'DineIn', label: 'Dine In'),
                  AppSelectItem(value: 'Takeaway', label: 'Takeaway'),
                  AppSelectItem(value: 'Delivery', label: 'Delivery'),
                  AppSelectItem(value: 'DriveThrough', label: 'Drive Through'),
                ],
                onChanged: (v) => _set(() => _orderType = v ?? 'DineIn'),
              ),
            ),
            if (_orderType == 'DineIn') ...[
              const SizedBox(width: 8),
              Expanded(
                child: AppSelect<int>(
                  value: _table ?? -1,
                  items: [
                    const AppSelectItem(value: -1, label: 'No table'),
                    for (final t in _tables)
                      AppSelectItem(value: tNum(t['tableId']).toInt(), label: 'Table ${tStr(t['tableNumber'])} (${tNum(t['capacity']).toInt()})'),
                  ],
                  onChanged: (v) => _set(() => _table = v == null || v == -1 ? null : v),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 8),
          AppSelect<int>(
            value: _customerId ?? -1,
            items: [
              const AppSelectItem(value: -1, label: 'Walk-in (Guest)'),
              for (final c in _customers)
                AppSelectItem(
                    value: tNum(c['customerId']).toInt(), label: '${tStr(c['name'])} ${tStr(c['phone']).isEmpty ? '' : '(${tStr(c['phone'])})'}'.trim()),
            ],
            onChanged: (v) => _set(() {
              if (v == null || v == -1) {
                _customerId = null;
                _customerName = '';
              } else {
                final c = _customers.where((x) => tNum(x['customerId']).toInt() == v).firstOrNull;
                if (c != null) {
                  _customerId = v;
                  _customerName = tStr(c['name']);
                }
              }
            }),
          ),
        ]),
      ),
      Expanded(
        child: _cart.isEmpty
            ? const Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.shopping_cart_outlined, size: 40, color: Color(0xFF9CA3AF)),
                  SizedBox(height: 6),
                  Text('Cart is empty', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF9CA3AF))),
                  Text('Tap items on the menu to add them', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                ]),
              )
            : ListView(padding: const EdgeInsets.all(16), children: [
                for (final (i, c) in _cart.indexed)
                  Container(
                    padding: const EdgeInsets.only(bottom: 10),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: TColors.slate200))),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(c.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                          Text('${c.price.toStringAsFixed(2)} each', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                        ]),
                      ),
                      IconButton.outlined(
                        tooltip: 'Decrease quantity',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _set(() => c.quantity = c.quantity > 1 ? c.quantity - 1 : 1),
                        icon: const Icon(Icons.remove, size: 14),
                      ),
                      SizedBox(width: 28, child: Text('${c.quantity}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
                      IconButton.outlined(
                        tooltip: 'Increase quantity',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _set(() => c.quantity++),
                        icon: const Icon(Icons.add, size: 14),
                      ),
                      SizedBox(
                        width: 60,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text((c.price * c.quantity).toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                          InkWell(
                            onTap: () => _set(() => _cart.removeAt(i)),
                            child: const Icon(Icons.close, size: 16, color: Color(0xFFF87171), semanticLabel: 'Remove'),
                          ),
                        ]),
                      ),
                    ]),
                  ),
              ]),
      ),
      if (_cart.isNotEmpty)
        Container(
          color: const Color(0xFFF9FAFB),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const Text('Total', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const Spacer(),
                Text(_cartTotal.toStringAsFixed(2), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFFBE123C))),
              ]),
              const SizedBox(height: 10),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: restaurantRose, minimumSize: const Size.fromHeight(48)),
                onPressed: _placing ? null : _placeOrder,
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Place Order', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        ),
    ]);
  }

  Widget _activePanel(BuildContext sheet) {
    final o = _activeOrder!;
    Widget line(String k, num v, {Color? color, bool neg = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Text(k, style: TextStyle(fontSize: 14, color: color ?? TColors.slate500)),
            const Spacer(),
            Text('${neg ? '-' : ''}${v.toStringAsFixed(2)}', style: TextStyle(fontSize: 14, color: color)),
          ]),
        );
    return Column(children: [
      _panelHeader(
        sheet,
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tStr(o['orderNumber']), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF14532D))),
              Text('${tStr(o['orderType'])} ${tStr(o['tableNumber']).isEmpty ? '' : '| Table ${tStr(o['tableNumber'])}'}',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF15803D))),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: const Color(0xFF16A34A), borderRadius: BorderRadius.circular(999)),
            child: Text(tStr(o['status']), style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ]),
        bg: const Color(0xFFF0FDF4),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          for (final oi in _activeItems)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: TColors.slate200))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text.rich(TextSpan(children: [
                      TextSpan(
                          text: '${tNum(oi['quantity']).toInt()}x ', style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFE11D48))),
                      TextSpan(text: tStr(oi['itemName'])),
                    ])),
                    if (tStr(oi['notes']).isNotEmpty)
                      Text(tStr(oi['notes']), style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: TColors.slate500)),
                  ]),
                ),
                Text(tNum(oi['lineTotal']).toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.w500)),
              ]),
            ),
        ]),
      ),
      Container(
        color: const Color(0xFFF9FAFB),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            line('Subtotal', tNum(o['subtotal'])),
            if (tNum(o['discountAmount']) > 0) line('Discount', tNum(o['discountAmount']), color: const Color(0xFFDC2626), neg: true),
            if (tNum(o['serviceChargeAmount']) > 0) line('Service charge', tNum(o['serviceChargeAmount'])),
            if (tNum(o['taxAmount']) > 0) line('Tax', tNum(o['taxAmount'])),
            const Divider(height: 18),
            Row(children: [
              const Text('Total', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(tNum(o['totalAmount']).toStringAsFixed(2), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFFBE123C))),
            ]),
            if (tNum(o['paidAmount']) > 0) line('Paid so far', tNum(o['paidAmount']), color: const Color(0xFF15803D)),
            const SizedBox(height: 10),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16A34A), minimumSize: const Size.fromHeight(48)),
              onPressed: _pay,
              icon: const Icon(Icons.credit_card, size: 18),
              label: Text('Pay ${(tNum(o['totalAmount']) - tNum(o['paidAmount'])).toStringAsFixed(2)}'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => _set(() {
                _activeOrder = null;
                _activeItems = [];
              }),
              child: const Text('New Order'),
            ),
          ]),
        ),
      ),
    ]);
  }
}

class _ReceiptDialog extends StatelessWidget {
  const _ReceiptDialog({required this.receipt, required this.farmName, required this.template, required this.customers, required this.api});
  final PosReceipt receipt;
  final String farmName;
  final Map? template;
  final List<Map> customers;
  final ApiClient api;

  Future<void> _email(BuildContext context) async {
    final o = receipt.order;
    final cust = customers.where((c) => o['customerId'] != null && tNum(c['customerId']) == tNum(o['customerId'])).firstOrNull;
    final email = tStr(cust?['email']);
    if (email.isEmpty) {
      trackerToast(context, 'No email', description: 'This customer has no email address on file.', error: true);
      return;
    }
    try {
      final bytes = await posEmailPdf(receipt, farmName, template);
      await api.postFile('/api/Email/Report', field: 'file', bytes: bytes, filename: 'Receipt_${tStr(o['orderNumber'])}.pdf', contentType: 'application/pdf', fields: {
        'to': email,
        'subject': 'Your Receipt — Order ${tStr(o['orderNumber'])}',
        'body':
            '<p>Dear ${tStr(cust?['name'])},</p><p>Please find your receipt attached for Order ${tStr(o['orderNumber'])}.</p><p>Thank you for dining with us!</p>',
        'farmName': farmName,
        'reportTitle': 'Receipt ${tStr(o['orderNumber'])}',
        'senderName': farmName,
      });
      if (context.mounted) trackerToast(context, 'Receipt emailed', description: 'Sent to $email');
    } catch (e) {
      if (context.mounted) trackerToast(context, 'Email failed', description: e is ApiException ? e.message : '$e', error: true);
    }
  }

  Future<void> _download() async {
    final bytes = await posInvoicePdf(receipt, farmName, template);
    await ReportExport.sharer('Receipt_${tStr(receipt.order['orderNumber'])}.pdf', bytes, 'application/pdf', 'Receipt');
  }

  Future<void> _print() async {
    final bytes = await posRollPdf(receipt, farmName, template);
    await ReportExport.sharer('Receipt_${tStr(receipt.order['orderNumber'])}_print.pdf', bytes, 'application/pdf', 'Receipt');
  }

  @override
  Widget build(BuildContext context) {
    final o = receipt.order;
    const mono = TextStyle(fontFamily: 'monospace', fontSize: 12);
    Widget row(String k, String v, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 1.5),
          child: Row(children: [
            Expanded(child: Text(k, style: mono.copyWith(fontWeight: bold ? FontWeight.w700 : null, fontSize: bold ? 14 : 12))),
            Text(v, style: mono.copyWith(fontWeight: bold ? FontWeight.w700 : null, fontSize: bold ? 14 : 12)),
          ]),
        );
    const dash = Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Divider(height: 1, color: Colors.black54));
    return AlertDialog(
      scrollable: true,
      title: const Text('Receipt'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Print or download the receipt for this order.', style: TextStyle(fontSize: 13, color: TColors.slate500)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(farmName, textAlign: TextAlign.center, style: mono.copyWith(fontSize: 16, fontWeight: FontWeight.w700)),
              if (tStr(template?['headerText']).isNotEmpty) Text(tStr(template?['headerText']), textAlign: TextAlign.center, style: mono.copyWith(fontSize: 10)),
              Text(_when(o['createdAt']), textAlign: TextAlign.center, style: mono.copyWith(fontSize: 10)),
              Text('Order: ${tStr(o['orderNumber'])}', textAlign: TextAlign.center, style: mono.copyWith(fontWeight: FontWeight.w700)),
              Text('${tStr(o['orderType'])}${tStr(o['tableNumber']).isNotEmpty ? ' | Table ${tStr(o['tableNumber'])}' : ''}',
                  textAlign: TextAlign.center, style: mono),
              if (tStr(o['customerName']).isNotEmpty) Text('Customer: ${tStr(o['customerName'])}', textAlign: TextAlign.center, style: mono),
              dash,
              for (final i in receipt.items) row('${tNum(i['quantity']).toInt()} x ${tStr(i['itemName'])}', tNum(i['lineTotal']).toStringAsFixed(2)),
              dash,
              row('Subtotal', tNum(o['subtotal']).toStringAsFixed(2)),
              if (tNum(o['discountAmount']) > 0) row('Discount', '-${tNum(o['discountAmount']).toStringAsFixed(2)}'),
              if (tNum(o['serviceChargeAmount']) > 0) row('Service charge', tNum(o['serviceChargeAmount']).toStringAsFixed(2)),
              if (tNum(o['taxAmount']) > 0) row('Tax', tNum(o['taxAmount']).toStringAsFixed(2)),
              row('TOTAL', tNum(o['totalAmount']).toStringAsFixed(2), bold: true),
              dash,
              row('Paid (${receipt.method})', receipt.amount.toStringAsFixed(2)),
              if (receipt.change > 0) row('Change', receipt.change.toStringAsFixed(2)),
              if (receipt.tip > 0) row('Tip', receipt.tip.toStringAsFixed(2)),
              dash,
              Text('Thank you for dining with us!', textAlign: TextAlign.center, style: mono),
              if (tStr(template?['footerText']).isNotEmpty) Text(tStr(template?['footerText']), textAlign: TextAlign.center, style: mono.copyWith(fontSize: 10)),
              Text('Powered by PoultryMaster', textAlign: TextAlign.center, style: mono.copyWith(fontSize: 9, color: const Color(0xFF999999))),
            ]),
          ),
        ]),
      ),
      actions: [
        Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          OutlinedButton.icon(onPressed: () => _email(context), icon: const Icon(Icons.mail_outline, size: 16), label: const Text('Email')),
          OutlinedButton.icon(onPressed: _download, icon: const Icon(Icons.download, size: 16), label: const Text('Download PDF')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: restaurantRose),
            onPressed: _print,
            icon: const Icon(Icons.print_outlined, size: 16),
            label: const Text('Print Receipt'),
          ),
        ]),
      ],
    );
  }
}
