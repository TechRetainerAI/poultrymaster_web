// Hotel → Restaurant & Bar: Orders (`app/hotel-restaurant`, with its point of
// sale), Menu (`app/hotel-menu`), Kitchen (`app/hotel-kitchen`) and Tables
// (`app/hotel-restaurant-tables`). Amounts print as plain "0.00", as the web's
// toFixed(2). The web prints the receipt in a new window; here it is a roll
// PDF handed to the phone's share sheet (print from there), as the Restaurant
// POS does.
// API: /Hotel/restaurant/menu, /tables, /orders (+ /{id}/status),
// /Hotel/setup/table-locations, /Hotel/bookings, /Hotel/staff.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/money/money_widgets.dart' show MobileCardList, twoUp;
import '../poultry/reports/report_export.dart';
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart';
import 'hotel_kit.dart';
import 'hotel_other_select.dart';

Object? _v(Map m, String k) => m[k] ?? m[k.toLowerCase()];
String _money(Object? v) => tNum(v).toStringAsFixed(2);
int _orderId(Map o) => tIntOrNull(_v(o, 'hotelRestaurantOrderId')) ?? 0;
int _menuId(Map m) => tIntOrNull(_v(m, 'hotelMenuItemId')) ?? 0;
String _tableNo(Map t) => tStr(_v(t, 'tableNumber'));

/// The order flow: what each status moves to next.
const hotelOrderNext = {'Placed': 'Preparing', 'Preparing': 'Ready', 'Ready': 'Served'};

/// ORDER_STATUS_COLOR.
(Color, Color) _orderTone(Object? s) => switch (tStr(s)) {
      'Placed' => (const Color(0xFFFEE2E2), const Color(0xFFB91C1C)),
      'Preparing' => (const Color(0xFFFEF3C7), const Color(0xFFB45309)),
      'Ready' => (const Color(0xFFD1FAE5), const Color(0xFF047857)),
      'Served' => (TColors.slate100, TColors.slate700),
      _ => (TColors.slate100, TColors.slate700),
    };

/// The tables' STATUS_COLOR.
(Color, Color) _tableTone(Object? s) => switch (tStr(s)) {
      'Available' => (const Color(0xFFD1FAE5), const Color(0xFF047857)),
      'Occupied' => (TColors.violet100, TColors.violet700),
      'Reserved' => (const Color(0xFFDBEAFE), const Color(0xFF1D4ED8)),
      _ => (TColors.slate50, TColors.slate700),
    };

Widget _orderBadge(Object? s) {
  final (bg, fg) = _orderTone(s);
  return hotelBadge(tStr(s), bg, fg);
}

Future<void> _setStatus(BuildContext context, ApiClient api, String farmId, Map o, String next, String toast) async {
  try {
    await api.patch('/api/Hotel/restaurant/orders/${_orderId(o)}/status', query: {'farmId': farmId}, body: {'status': next});
    if (context.mounted) trackerToast(context, toast);
  } on ApiException catch (e) {
    if (context.mounted) trackerToast(context, 'Failed', description: e.message, error: true);
  }
}

String _fmtTime(Object? v) {
  final d = DateTime.tryParse(tStr(v))?.toLocal();
  if (d == null) return '—';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.day}/${d.month}/${d.year}, ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}

// ======================================================================== Orders

class HotelRestaurantOrdersScreen extends StatefulWidget {
  const HotelRestaurantOrdersScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<HotelRestaurantOrdersScreen> createState() => _HotelRestaurantOrdersScreenState();
}

class _HotelRestaurantOrdersScreenState extends State<HotelRestaurantOrdersScreen> {
  List<Map> _tables = [], _orders = [], _menu = [], _bookings = [], _staff = [];
  bool _loading = true;
  String _filter = 'active';

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final q = {'farmId': _farmId};
    try {
      Future<Object?> soft(String p) async {
        try {
          return await _api.get(p, query: q);
        } on ApiException {
          return const [];
        }
      }

      final r = await Future.wait([
        _api.get('/api/Hotel/restaurant/tables', query: q),
        _api.get('/api/Hotel/restaurant/orders', query: q),
        _api.get('/api/Hotel/restaurant/menu', query: q),
        _api.get('/api/Hotel/bookings', query: q),
        soft('/api/Hotel/staff'),
      ]);
      if (!mounted) return;
      setState(() {
        _tables = hotelRows(r[0]);
        _orders = hotelRows(r[1]);
        _menu = hotelRows(r[2]);
        _bookings = [for (final b in hotelRows(r[3])) if (_v(b, 'status') == 'CheckedIn') b];
        _staff = [
          for (final s in hotelRows(r[4]))
            if (_v(s, 'isActive') == true && tStr(_v(s, 'department')).toLowerCase().contains('restaurant')) s,
        ];
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pos() async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _PosDialog(session: widget.session, company: widget.company, tables: _tables, menu: _menu, bookings: _bookings, staff: _staff),
    );
    if (done == true) _load();
  }

  Future<void> _advance(Map o) async {
    final next = hotelOrderNext[tStr(o['status'])];
    if (next == null) return;
    await _setStatus(context, _api, _farmId, o, next, '→ $next');
    await _load();
  }

  Widget _stat(String label, String value, Color color) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color))),
          Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
        ]),
      );

  Widget _chip(String label, bool on, VoidCallback tap) => on
      ? FilledButton(style: hotelPrimary.copyWith(minimumSize: const WidgetStatePropertyAll(Size(0, 34))), onPressed: tap, child: Text(label))
      : OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 34)), onPressed: tap, child: Text(label));

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/hotel-restaurant');
    final active = _orders.where((o) => o['status'] == 'Placed' || o['status'] == 'Preparing').length;
    final served = _orders.where((o) => o['status'] == 'Served').fold<num>(0, (s, o) => s + tNum(_v(o, 'totalAmount')));
    final visible = _filter == 'active' ? [for (final o in _orders) if (const ['Placed', 'Preparing', 'Ready'].contains(o['status'])) o] : _orders;
    return Scaffold(
      backgroundColor: TColors.slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Restaurant & Bar')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
          const Row(children: [
            Icon(Icons.shopping_cart_outlined, size: 24, color: hotelViolet),
            SizedBox(width: 10),
            Expanded(child: Text('Restaurant & Bar', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: TColors.slate900))),
          ]),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: hotelAddButton('New Order (POS)', _pos)),
          const SizedBox(height: 12),
          twoUp([
            _stat('Tables', '${_tables.length}', TColors.violet700),
            _stat('Active Orders', '$active', const Color(0xFFB91C1C)),
            _stat('Served Revenue', _money(served), const Color(0xFF047857)),
            _stat('Menu Items', '${_menu.length}', TColors.violet700),
          ]),
          const SizedBox(height: 14),
          if (_loading)
            const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: CircularProgressIndicator(color: hotelViolet)))
          else ...[
            const Text('TABLES', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: TColors.slate400)),
            const SizedBox(height: 8),
            if (_tables.isEmpty)
              const Text('No tables. Add from Restaurant Tables page.', style: TextStyle(fontSize: 13, color: TColors.slate400))
            else
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final t in _tables)
                  () {
                    final (bg, fg) = _tableTone(t['status']);
                    return Container(
                      width: 74,
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      decoration: BoxDecoration(color: bg, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
                      child: Column(children: [
                        Text(_tableNo(t), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
                        Text('${tStr(t['capacity'])} seats', style: TextStyle(fontSize: 10, color: fg)),
                      ]),
                    );
                  }(),
              ]),
            const SizedBox(height: 18),
            Row(children: [
              const Expanded(child: Text('ORDERS', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: TColors.slate400))),
              _chip('Active', _filter == 'active', () => setState(() => _filter = 'active')),
              const SizedBox(width: 6),
              _chip('All (${_orders.length})', _filter == 'all', () => setState(() => _filter = 'all')),
            ]),
            const SizedBox(height: 8),
            if (visible.isEmpty)
              TCard(
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Text('No orders.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate400)),
                ),
              )
            else
              MobileCardList<Map>(
                striped: true,
                items: visible,
                keyOf: (o) => '${_orderId(o)}',
                primary: (o) => '#${_orderId(o)} · ${tStr(_v(o, 'tableNumber')).isEmpty ? 'Takeaway' : tStr(_v(o, 'tableNumber'))}',
                secondary: (o) => _fmtTime(_v(o, 'orderTime')),
                trailing: (o) => _orderBadge(o['status']),
                details: (o) => [
                  ('Server', tStr(_v(o, 'serverName')).isEmpty ? '—' : tStr(_v(o, 'serverName'))),
                  ('Total', _money(_v(o, 'totalAmount'))),
                ],
                actions: (o) => [
                  if (hotelOrderNext[tStr(o['status'])] != null)
                    OutlinedButton(onPressed: () => _advance(o), child: Text(hotelOrderNext[tStr(o['status'])]!)),
                ],
                table: (items) => TrackerTable(
                  columns: const [
                    TCol('#', width: 60),
                    TCol('Table', width: 100),
                    TCol('Server', width: 130),
                    TCol('Status', width: 100),
                    TCol('Total', right: true, width: 100),
                    TCol('Time', width: 170),
                    TCol('Action', right: true, width: 120),
                  ],
                  rows: [
                    for (final o in items)
                      [
                        cellText('${_orderId(o)}'),
                        cellText(tStr(_v(o, 'tableNumber')).isEmpty ? 'Takeaway' : tStr(_v(o, 'tableNumber')), bold: true),
                        cellText(tStr(_v(o, 'serverName')).isEmpty ? '—' : tStr(_v(o, 'serverName'))),
                        Align(alignment: Alignment.centerLeft, child: _orderBadge(o['status'])),
                        cellText(_money(_v(o, 'totalAmount')), bold: true),
                        cellText(_fmtTime(_v(o, 'orderTime'))),
                        Align(
                          alignment: Alignment.centerRight,
                          child: hotelOrderNext[tStr(o['status'])] == null
                              ? const SizedBox.shrink()
                              : OutlinedButton(onPressed: () => _advance(o), child: Text(hotelOrderNext[tStr(o['status'])]!)),
                        ),
                      ],
                  ],
                ),
              ),
          ],
        ]),
      ),
    );
  }
}

/// One line of the cart.
class HotelCartLine {
  HotelCartLine(this.item, this.quantity);
  final Map item;
  int quantity;
  num get total => tNum(item['price']) * quantity;
}

/// What the receipt prints.
typedef HotelReceipt = ({
  List<HotelCartLine> lines,
  num total,
  String customer,
  String table,
  String server,
  String? room,
  String payMethod,
  num received,
  num change,
  bool chargeToRoom,
  DateTime when,
});

/// printReceipt: the web's 280 px receipt on an 80 mm roll.
Future<Uint8List> hotelReceiptPdf(HotelReceipt r) async {
  final doc = pw.Document();
  final mono = pw.Font.courier();
  final bold = pw.Font.courierBold();
  pw.Widget row(String k, String v, {bool strong = false}) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Expanded(child: pw.Text(k, style: pw.TextStyle(font: mono, fontSize: strong ? 11 : 9))),
        pw.Text(v, style: pw.TextStyle(font: strong ? bold : mono, fontSize: strong ? 11 : 9)),
      ]);
  final dash = pw.Container(margin: const pw.EdgeInsets.symmetric(vertical: 5), height: .6, color: PdfColors.grey);
  String two(int n) => n.toString().padLeft(2, '0');
  final w = r.when;
  doc.addPage(pw.Page(
    pageFormat: const PdfPageFormat(80 * PdfPageFormat.mm, double.infinity, marginAll: 4 * PdfPageFormat.mm),
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Text('RESTAURANT', textAlign: pw.TextAlign.center, style: pw.TextStyle(font: bold, fontSize: 14)),
      pw.Text('${w.day}/${w.month}/${w.year} ${two(w.hour)}:${two(w.minute)}:${two(w.second)}',
          textAlign: pw.TextAlign.center, style: pw.TextStyle(font: mono, fontSize: 8, color: PdfColors.grey700)),
      dash,
      row('Customer:', r.customer),
      row('Table:', r.table),
      row('Server:', r.server),
      if (r.room != null) row('Room:', r.room!),
      dash,
      for (final l in r.lines) row('${tStr(l.item['name'])}  ${l.quantity} x ${_money(l.item['price'])}', _money(l.total)),
      dash,
      row('TOTAL', _money(r.total), strong: true),
      row('Payment:', r.payMethod),
      if (r.payMethod == 'Cash' && r.received > 0) row('Received:', _money(r.received)),
      if (r.change > 0) row('Change:', _money(r.change)),
      if (r.chargeToRoom)
        pw.Text('Added to Room ${r.room ?? ''} folio', textAlign: pw.TextAlign.center, style: pw.TextStyle(font: mono, fontSize: 8, color: PdfColors.deepPurple)),
      dash,
      pw.Text('Thank you for dining with us!', textAlign: pw.TextAlign.center, style: pw.TextStyle(font: mono, fontSize: 8, color: PdfColors.grey)),
    ]),
  ));
  return doc.save();
}

/// New Order — Point of Sale.
class _PosDialog extends StatefulWidget {
  const _PosDialog({required this.session, required this.company, required this.tables, required this.menu, required this.bookings, required this.staff});
  final Session session;
  final Company company;
  final List<Map> tables, menu, bookings, staff;

  @override
  State<_PosDialog> createState() => _PosDialogState();
}

class _PosDialogState extends State<_PosDialog> {
  final List<HotelCartLine> _cart = [];
  String _menuFilter = 'all', _table = '', _server = '', _customerType = 'walkin', _method = 'Cash';
  int? _booking;
  bool _chargeToRoom = false, _saving = false;
  final _customer = TextEditingController(), _received = TextEditingController();

  @override
  void dispose() {
    _customer.dispose();
    _received.dispose();
    super.dispose();
  }

  num get _total => _cart.fold<num>(0, (s, c) => s + c.total);
  num get _receivedNum => num.tryParse(_received.text) ?? 0;
  bool get _guestPicked => _customerType == 'guest' && _booking != null;

  void _add(Map m) => setState(() {
        final hit = _cart.where((c) => _menuId(c.item) == _menuId(m)).firstOrNull;
        hit == null ? _cart.add(HotelCartLine(m, 1)) : hit.quantity++;
      });

  void _qty(int i, int d) => setState(() {
        _cart[i].quantity = (_cart[i].quantity + d).clamp(0, 1 << 30);
        _cart.removeWhere((c) => c.quantity <= 0);
      });

  Map? get _bookingRow => widget.bookings.where((b) => tIntOrNull(_v(b, 'hotelBookingId')) == _booking).firstOrNull;

  Future<void> _place() async {
    setState(() => _saving = true);
    final chargeToRoom = _guestPicked && _chargeToRoom;
    final total = _total;
    try {
      await widget.session.farmClient.post('/api/Hotel/restaurant/orders', body: {
        'farmId': widget.company.farmId,
        if (_table.isNotEmpty) 'tableNumber': _table,
        if (_server.isNotEmpty) 'serverName': _server,
        if (_booking != null) 'hotelBookingId': _booking,
        'chargeToRoom': chargeToRoom,
        if (!chargeToRoom) 'paymentMethod': _method,
        'items': [
          for (final c in _cart) {'menuItemId': _menuId(c.item), 'quantity': c.quantity, 'unitPrice': tNum(c.item['price'])},
        ],
      });
      final b = _guestPicked ? _bookingRow : null;
      final receipt = (
        lines: List<HotelCartLine>.of(_cart),
        total: total,
        customer: b != null
            ? '${tStr(_v(b, 'guestFirstName'))} ${tStr(_v(b, 'guestLastName'))}'.trim()
            : (_customer.text.trim().isEmpty ? 'Walk-in Customer' : _customer.text.trim()),
        table: _table.isEmpty ? 'Takeaway' : _table,
        server: _server.isEmpty ? '—' : _server,
        room: b == null ? null : (tStr(_v(b, 'roomNumber')).isEmpty ? '—' : tStr(_v(b, 'roomNumber'))),
        payMethod: chargeToRoom ? 'Charged to Room' : _method,
        received: _receivedNum,
        change: _method == 'Cash' && !chargeToRoom && _receivedNum > total ? _receivedNum - total : 0,
        chargeToRoom: chargeToRoom,
        when: DateTime.now(),
      );
      if (!mounted) return;
      trackerToast(context, chargeToRoom ? 'Charged to room — ${_money(total)}' : 'Order created — ${_money(total)}');
      Navigator.pop(context, true);
      // printReceipt.
      try {
        await ReportExport.sharer('Receipt.pdf', await hotelReceiptPdf(receipt), 'application/pdf', 'Receipt');
      } catch (_) {}
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Failed', description: e.message, error: true);
    }
  }

  Widget _toggle(String label, bool on, VoidCallback tap) => Expanded(
        child: on
            ? FilledButton(style: hotelPrimary.copyWith(minimumSize: const WidgetStatePropertyAll(Size(0, 36))), onPressed: tap, child: Text(label))
            : OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36)), onPressed: tap, child: Text(label)),
      );

  Widget _cashBox() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSelect<String>(
          value: _method,
          items: const [
            AppSelectItem(value: 'Cash', label: 'Cash'),
            AppSelectItem(value: 'Card', label: 'Card'),
            AppSelectItem(value: 'Mobile Money', label: 'Mobile Money'),
            AppSelectItem(value: 'Bank Transfer', label: 'Bank Transfer'),
          ],
          onChanged: (v) => setState(() => _method = v ?? 'Cash'),
        ),
        if (_method == 'Cash') ...[
          const SizedBox(height: 8),
          AppInput(
            controller: _received,
            hintText: 'Amount received',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
            onChanged: (_) => setState(() {}),
          ),
          if (_receivedNum > 0 && _receivedNum >= _total)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Change: ${_money(_receivedNum - _total)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF047857))),
            ),
          if (_receivedNum > 0 && _receivedNum < _total)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Short: ${_money(_total - _receivedNum)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: TColors.red600)),
            ),
        ],
      ]);

  @override
  Widget build(BuildContext context) {
    final cats = {for (final m in widget.menu) tStr(m['category'])}.toList();
    final menu = _menuFilter == 'all' ? widget.menu : [for (final m in widget.menu) if (tStr(m['category']) == _menuFilter) m];
    Widget catChip(String label, String v) => _menuFilter == v
        ? FilledButton(style: hotelPrimary.copyWith(minimumSize: const WidgetStatePropertyAll(Size(0, 32))), onPressed: () => setState(() => _menuFilter = v), child: Text(label))
        : OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 32)), onPressed: () => setState(() => _menuFilter = v), child: Text(label));
    final roomLabel = _customerType == 'guest' && _chargeToRoom;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: const Text('New Order — Point of Sale'),
        content: SizedBox(
          width: 720,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 4, runSpacing: 4, children: [catChip('All', 'all'), for (final c in cats) catChip(c, c)]),
            const SizedBox(height: 8),
            if (menu.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No menu items. Add from Menu page.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: TColors.slate400)),
              )
            else
              for (final m in menu)
                InkWell(
                  onTap: () => _add(m),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(tStr(m['name']), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                          Text(tStr(m['category']), style: const TextStyle(fontSize: 11, color: TColors.slate400)),
                        ]),
                      ),
                      Text(_money(m['price']), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: TColors.violet700)),
                    ]),
                  ),
                ),
            const Divider(height: 24),
            FilterLabel(
              'Table',
              AppSelect<String>(
                value: _table,
                items: [
                  const AppSelectItem(value: '', label: 'Takeaway / No table'),
                  for (final t in widget.tables) AppSelectItem(value: _tableNo(t), label: '${_tableNo(t)} (${tStr(t['capacity'])} seats)'),
                ],
                onChanged: (v) => setState(() => _table = v ?? ''),
              ),
            ),
            const SizedBox(height: 10),
            FilterLabel(
              'Server',
              AppSelect<String>(
                value: _server,
                items: [
                  const AppSelectItem(value: '', label: 'No server'),
                  for (final s in widget.staff)
                    () {
                      final name = '${tStr(_v(s, 'firstName'))} ${tStr(_v(s, 'lastName'))}';
                      final role = tStr(_v(s, 'role'));
                      return AppSelectItem(value: name, label: '$name${role.isNotEmpty ? ' — $role' : ''}');
                    }(),
                ],
                onChanged: (v) => setState(() => _server = v ?? ''),
              ),
            ),
            const SizedBox(height: 10),
            FilterLabel(
              'Customer',
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  _toggle('Walk-in', _customerType == 'walkin', () => setState(() {
                        _customerType = 'walkin';
                        _booking = null;
                      })),
                  const SizedBox(width: 6),
                  _toggle('Hotel Guest', _customerType == 'guest', () => setState(() {
                        _customerType = 'guest';
                        _customer.clear();
                      })),
                ]),
                const SizedBox(height: 8),
                if (_customerType == 'walkin')
                  AppInput(controller: _customer, hintText: 'Customer name (optional)')
                else
                  AppSelect<int>(
                    value: _booking ?? 0,
                    items: [
                      const AppSelectItem(value: 0, label: 'Select guest'),
                      for (final b in widget.bookings)
                        AppSelectItem(
                          value: tIntOrNull(_v(b, 'hotelBookingId')) ?? 0,
                          label: 'Room ${tStr(_v(b, 'roomNumber'))} — ${tStr(_v(b, 'guestFirstName'))} ${tStr(_v(b, 'guestLastName'))}',
                        ),
                    ],
                    onChanged: (v) => setState(() => _booking = v == null || v == 0 ? null : v),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Order Items (${_cart.length})', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                if (_cart.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text('Tap menu items to add', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: TColors.slate400)),
                  )
                else
                  for (final (i, c) in _cart.indexed)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(tStr(c.item['name']), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                            Text('${_money(c.item['price'])} each', style: const TextStyle(fontSize: 11, color: TColors.slate400)),
                          ]),
                        ),
                        IconButton(tooltip: 'Less', visualDensity: VisualDensity.compact, onPressed: () => _qty(i, -1), icon: const Icon(Icons.remove, size: 16)),
                        Text('${c.quantity}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        IconButton(tooltip: 'More', visualDensity: VisualDensity.compact, onPressed: () => _qty(i, 1), icon: const Icon(Icons.add, size: 16)),
                        SizedBox(width: 56, child: Text(_money(c.total), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600))),
                        IconButton(
                          tooltip: 'Remove',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setState(() => _cart.removeAt(i)),
                          icon: const Icon(Icons.delete_outline, size: 16, color: Color(0xFFEF4444)),
                        ),
                      ]),
                    ),
                const Divider(height: 20),
                Row(children: [
                  const Expanded(child: Text('Total', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
                  Text(_money(_total), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: TColors.violet700)),
                ]),
              ]),
            ),
            if (_cart.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Text('Payment', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  if (_guestPicked) ...[
                    Row(children: [
                      _toggle('Charge to Room', _chargeToRoom, () => setState(() => _chargeToRoom = true)),
                      const SizedBox(width: 6),
                      _toggle('Pay Now', !_chargeToRoom, () => setState(() => _chargeToRoom = false)),
                    ]),
                    const SizedBox(height: 8),
                    if (_chargeToRoom)
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: TColors.violet50, borderRadius: BorderRadius.circular(8)),
                        child: Text("${_money(_total)} will be added to the guest's room folio",
                            textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: TColors.violet700)),
                      )
                    else
                      _cashBox(),
                  ] else
                    _cashBox(),
                ]),
              ),
            ],
          ]),
        ),
        actions: [
          Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
            OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              style: hotelPrimary,
              onPressed: _saving || _cart.isEmpty ? null : _place,
              child: Text(roomLabel ? 'Charge to Room — ${_money(_total)}' : 'Pay & Place Order — ${_money(_total)}'),
            ),
          ]),
        ],
      ),
    );
  }
}

// ======================================================================== Menu

/// The built-in categories; HotelOtherSelect adds its own "Other".
const hotelMenuCategories = ['Breakfast', 'Lunch', 'Dinner', 'Drinks', 'Snacks', 'Desserts', 'Appetizers', 'Sides', 'Cocktails'];

class HotelMenuScreen extends StatefulWidget {
  const HotelMenuScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<HotelMenuScreen> createState() => _HotelMenuScreenState();
}

class _HotelMenuScreenState extends State<HotelMenuScreen> {
  List<Map> _items = [];
  bool _loading = true;

  ApiClient get _api => widget.session.farmClient;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = hotelRows(await _api.get('/api/Hotel/restaurant/menu', query: {'farmId': widget.company.farmId}));
      if (mounted) setState(() => _items = r);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _form([Map? editing]) async {
    final done = await showDialog<bool>(context: context, builder: (_) => _MenuItemDialog(session: widget.session, company: widget.company, editing: editing));
    if (done == true) _load();
  }

  Future<void> _delete(Map i) async {
    final ok = await hotelConfirmDelete(
      context,
      title: 'Delete ${tStr(i['name'])}?',
      message: 'Delete ${tStr(i['name'])}?',
      onConfirm: () => _api.delete('/api/Hotel/restaurant/menu/${_menuId(i)}', query: {'farmId': widget.company.farmId}),
    );
    if (!ok || !mounted) return;
    trackerToast(context, 'Deleted');
    _load();
  }

  Widget _available(Map i) => _v(i, 'isAvailable') == true
      ? hotelBadge('Yes', const Color(0xFFD1FAE5), const Color(0xFF047857))
      : hotelBadge('No', const Color(0xFFFEE2E2), const Color(0xFFB91C1C));

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/hotel-menu');
    return Scaffold(
      backgroundColor: TColors.slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Menu Items')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
          Row(children: [
            const Icon(Icons.shopping_cart_outlined, size: 24, color: hotelViolet),
            const SizedBox(width: 10),
            const Text('Menu Items', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: TColors.slate900)),
            const SizedBox(width: 6),
            Expanded(child: Text('(${_items.length})', style: const TextStyle(fontSize: 13, color: TColors.slate500))),
          ]),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: hotelAddButton('Add Item', () => _form())),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: CircularProgressIndicator(color: hotelViolet)))
          else if (_items.isEmpty)
            TCard(
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Text('No menu items. Add your restaurant menu.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate400)),
              ),
            )
          else
            MobileCardList<Map>(
              striped: true,
              items: _items,
              keyOf: (i) => '${_menuId(i)}',
              primary: (i) => tStr(i['name']),
              secondary: (i) => tStr(i['category']),
              trailing: _available,
              details: (i) => [('Price', _money(i['price']))],
              actions: (i) => [
                IconButton(tooltip: 'Edit', onPressed: () => _form(i), icon: const Icon(Icons.edit_outlined, size: 18)),
                IconButton(tooltip: 'Delete', onPressed: () => _delete(i), icon: const Icon(Icons.delete_outline, size: 18, color: TColors.red600)),
              ],
              table: (items) => TrackerTable(
                columns: const [
                  TCol('Name', width: 160),
                  TCol('Category', width: 120),
                  TCol('Price', right: true, width: 90),
                  TCol('Available', width: 90),
                  TCol('Actions', right: true, width: 110),
                ],
                rows: [
                  for (final i in items)
                    [
                      cellText(tStr(i['name']), bold: true),
                      Align(alignment: Alignment.centerLeft, child: hotelBadge(tStr(i['category']), Colors.white, TColors.slate700)),
                      cellText(_money(i['price']), bold: true),
                      Align(alignment: Alignment.centerLeft, child: _available(i)),
                      Wrap(alignment: WrapAlignment.end, children: [
                        IconButton(tooltip: 'Edit', onPressed: () => _form(i), icon: const Icon(Icons.edit_outlined, size: 18)),
                        IconButton(tooltip: 'Delete', onPressed: () => _delete(i), icon: const Icon(Icons.delete_outline, size: 18, color: TColors.red600)),
                      ]),
                    ],
                ],
              ),
            ),
        ]),
      ),
    );
  }
}

class _MenuItemDialog extends StatefulWidget {
  const _MenuItemDialog({required this.session, required this.company, required this.editing});
  final Session session;
  final Company company;
  final Map? editing;

  @override
  State<_MenuItemDialog> createState() => _MenuItemDialogState();
}

class _MenuItemDialogState extends State<_MenuItemDialog> {
  late final Map? e = widget.editing;
  late final _name = TextEditingController(text: tStr(e?['name']));
  late final _price = TextEditingController(text: e == null ? '0' : _plain(tNum(e!['price'])));
  late final _desc = TextEditingController(text: tStr(e?['description']));
  late String _category = e == null ? 'Lunch' : tStr(e!['category']);
  final _categoryOther = GlobalKey<HotelOtherSelectState>();
  bool _saving = false;

  static String _plain(num v) => v == v.roundToDouble() ? v.toInt().toString() : '$v';

  @override
  void dispose() {
    for (final c in [_name, _price, _desc]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return trackerToast(context, 'Name required', error: true);
    setState(() => _saving = true);
    final body = {
      'farmId': widget.company.farmId,
      'name': _name.text,
      'category': _category,
      'description': _desc.text,
      'price': num.tryParse(_price.text) ?? 0,
    };
    try {
      final api = widget.session.farmClient;
      if (e != null) {
        await api.put('/api/Hotel/restaurant/menu/${_menuId(e!)}', body: body);
        if (mounted) trackerToast(context, 'Updated');
      } else {
        await api.post('/api/Hotel/restaurant/menu', body: body);
        if (mounted) trackerToast(context, 'Menu item added');
      }
      await _categoryOther.currentState?.remember();
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (x) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Failed', description: x.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => HotelDialog(
        icon: Icons.restaurant_menu,
        title: e != null ? 'Edit Item' : 'Add Menu Item',
        saveLabel: e != null ? 'Update' : 'Add',
        saving: _saving,
        onSave: _save,
        children: [
          FilterLabel('Name *', AppInput(controller: _name, hintText: 'e.g. Jollof Rice')),
          FilterLabel(
            'Category',
            HotelOtherSelect(
              key: _categoryOther,
              session: widget.session,
              company: widget.company,
              listKey: 'MenuCategory',
              baseOptions: hotelMenuCategories,
              value: _category,
              onChanged: (v) => setState(() => _category = v ?? ''),
              placeholder: 'Select category',
              otherLabel: 'Other (type category)',
            ),
          ),
          FilterLabel(
            'Price',
            AppInput(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
            ),
          ),
          FilterLabel('Description', AppInput(controller: _desc)),
        ],
      );
}

// ======================================================================== Kitchen

/// STATUS_COLOR (the dot) and STATUS_BG (the card).
const _kitchenDot = {'Placed': Color(0xFFEF4444), 'Preparing': Color(0xFFF59E0B), 'Ready': Color(0xFF10B981), 'Served': Color(0xFF94A3B8)};
const _kitchenBg = {
  'Placed': (Color(0xFFFEF2F2), Color(0xFFFCA5A5)),
  'Preparing': (Color(0xFFFFFBEB), Color(0xFFFCD34D)),
  'Ready': (Color(0xFFECFDF5), Color(0xFF6EE7B7)),
  'Served': (TColors.slate50, TColors.slate200),
};

class HotelKitchenScreen extends StatefulWidget {
  const HotelKitchenScreen({super.key, required this.session, required this.company, this.now});
  final Session session;
  final Company company;

  /// The clock "Xm ago" is measured against (tests pass a fixed one).
  final DateTime Function()? now;

  @override
  State<HotelKitchenScreen> createState() => _HotelKitchenScreenState();
}

class _HotelKitchenScreenState extends State<HotelKitchenScreen> {
  List<Map> _orders = [];
  bool _loading = true;
  String _view = 'active';

  ApiClient get _api => widget.session.farmClient;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = hotelRows(await _api.get('/api/Hotel/restaurant/orders', query: {'farmId': widget.company.farmId}));
      if (mounted) setState(() => _orders = r);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _move(Map o) async {
    final next = hotelOrderNext[tStr(o['status'])];
    if (next == null) return;
    await _setStatus(context, _api, widget.company.farmId, o, next, 'Order moved to $next');
    await _load();
  }

  Widget _card(Map o, String status) {
    final (bg, border) = _kitchenBg[status]!;
    final next = hotelOrderNext[status];
    final t = DateTime.tryParse(tStr(_v(o, 'orderTime')));
    final elapsed = t == null ? 0 : ((widget.now?.call() ?? DateTime.now()).difference(t).inSeconds / 60).round();
    final delivered = DateTime.tryParse(tStr(_v(o, 'deliveredTime')))?.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final total = tNum(_v(o, 'totalAmount'));
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: bg, border: Border(left: BorderSide(color: border, width: 4), top: BorderSide(color: border), right: BorderSide(color: border), bottom: BorderSide(color: border)), borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('Table ${tStr(_v(o, 'tableNumber')).isEmpty ? 'Takeaway' : tStr(_v(o, 'tableNumber'))}', style: const TextStyle(fontWeight: FontWeight.w700))),
          Text('${elapsed}m ago', style: const TextStyle(fontSize: 11, color: TColors.slate400)),
        ]),
        if (tStr(_v(o, 'serverName')).isNotEmpty) Text('Server: ${tStr(_v(o, 'serverName'))}', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
        if (total > 0) Text(_money(total), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        if (tStr(o['notes']).isNotEmpty) Text(tStr(o['notes']), style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: TColors.slate500)),
        if (status == 'Served')
          Text('✓ Served ${delivered == null ? '' : '${two(delivered.hour)}:${two(delivered.minute)}:${two(delivered.second)}'}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF059669))),
        if (next != null) ...[
          const SizedBox(height: 6),
          status == 'Ready'
              ? OutlinedButton.icon(
                  onPressed: () => _move(o),
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.arrow_forward, size: 14),
                  label: Text('Move to $next'),
                )
              : FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: status == 'Placed' ? TColors.red600 : TColors.slate900, foregroundColor: Colors.white),
                  onPressed: () => _move(o),
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.arrow_forward, size: 14),
                  label: Text('Move to $next'),
                ),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/hotel-kitchen');
    int count(bool Function(Object?) f) => _orders.where((o) => f(o['status'])).length;
    final active = count((s) => s == 'Placed' || s == 'Preparing');
    final ready = count((s) => s == 'Ready');
    final served = count((s) => s == 'Served');
    final statuses = _view == 'active' ? const ['Placed', 'Preparing', 'Ready'] : const ['Placed', 'Preparing', 'Ready', 'Served'];
    Widget chip(String label, bool on, VoidCallback tap) => on
        ? FilledButton(style: hotelPrimary.copyWith(minimumSize: const WidgetStatePropertyAll(Size(0, 34))), onPressed: tap, child: Text(label))
        : OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 34)), onPressed: tap, child: Text(label));
    return Scaffold(
      backgroundColor: TColors.slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Kitchen Display')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
          const Row(children: [
            Icon(Icons.monitor_heart_outlined, size: 24, color: hotelViolet),
            SizedBox(width: 10),
            Expanded(child: Text('Kitchen Display', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: TColors.slate900))),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (active > 0) hotelBadge('$active active', const Color(0xFFFEE2E2), const Color(0xFFB91C1C)),
            if (ready > 0) hotelBadge('$ready ready to serve', const Color(0xFFD1FAE5), const Color(0xFF047857)),
            hotelBadge('$served served today', TColors.slate100, TColors.slate700),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            chip('Active Orders', _view == 'active', () => setState(() => _view = 'active')),
            chip('All Orders (${_orders.length})', _view == 'all', () => setState(() => _view = 'all')),
          ]),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: CircularProgressIndicator(color: hotelViolet)))
          else
            for (final status in statuses) ...[
              () {
                final col = [for (final o in _orders) if (o['status'] == status) o];
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Container(width: 12, height: 12, decoration: BoxDecoration(color: _kitchenDot[status], shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Text(status.toUpperCase(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 6),
                    Text('(${col.length})', style: const TextStyle(fontSize: 12, color: TColors.slate400)),
                  ]),
                  const SizedBox(height: 8),
                  if (col.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
                      child: const Text('Empty', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: TColors.slate300)),
                    )
                  else
                    for (final o in col) _card(o, status),
                  const SizedBox(height: 14),
                ]);
              }(),
            ],
        ]),
      ),
    );
  }
}

// ======================================================================== Tables

class HotelTablesScreen extends StatefulWidget {
  const HotelTablesScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<HotelTablesScreen> createState() => _HotelTablesScreenState();
}

class _HotelTablesScreenState extends State<HotelTablesScreen> {
  List<Map> _tables = [];
  List<String> _locations = [];
  bool _loading = true;

  ApiClient get _api => widget.session.farmClient;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final q = {'farmId': widget.company.farmId};
    try {
      final t = hotelRows(await _api.get('/api/Hotel/restaurant/tables', query: q));
      List<String> l = [];
      try {
        l = [for (final x in hotelRows(await _api.get('/api/Hotel/setup/table-locations', query: q))) tStr(x['description'])];
      } on ApiException {
        l = [];
      }
      if (mounted) {
        setState(() {
          _tables = t;
          _locations = l;
        });
      }
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _add() async {
    final done = await showDialog<bool>(context: context, builder: (_) => _TableDialog(session: widget.session, company: widget.company, locations: _locations));
    if (done == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/hotel-restaurant-tables');
    return Scaffold(
      backgroundColor: TColors.slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Restaurant Tables')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
          const Row(children: [
            Icon(Icons.grid_view, size: 24, color: hotelViolet),
            SizedBox(width: 10),
            Expanded(child: Text('Restaurant Tables', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: TColors.slate900))),
          ]),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: hotelAddButton('Add Table', _add)),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: CircularProgressIndicator(color: hotelViolet)))
          else if (_tables.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Text('No tables. Add your restaurant tables.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate400)),
            )
          else
            twoUp([
              for (final t in _tables)
                () {
                  final (bg, fg) = _tableTone(t['status']);
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
                    child: Column(children: [
                      Text(_tableNo(t), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: TColors.violet700)),
                      Text('${tStr(t['capacity'])} seats', style: const TextStyle(fontSize: 13, color: TColors.slate500)),
                      if (tStr(t['location']).isNotEmpty) Text(tStr(t['location']), style: const TextStyle(fontSize: 11, color: TColors.slate400)),
                      const SizedBox(height: 8),
                      hotelBadge(tStr(t['status']), bg, fg),
                    ]),
                  );
                }(),
            ]),
        ]),
      ),
    );
  }
}

class _TableDialog extends StatefulWidget {
  const _TableDialog({required this.session, required this.company, required this.locations});
  final Session session;
  final Company company;
  final List<String> locations;

  @override
  State<_TableDialog> createState() => _TableDialogState();
}

class _TableDialogState extends State<_TableDialog> {
  final _number = TextEditingController(), _capacity = TextEditingController(text: '4');
  String _location = '';
  final _locationOther = GlobalKey<HotelOtherSelectState>();
  bool _saving = false;

  @override
  void dispose() {
    _number.dispose();
    _capacity.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_number.text.trim().isEmpty) return trackerToast(context, 'Table number required', error: true);
    setState(() => _saving = true);
    try {
      await widget.session.farmClient.post('/api/Hotel/restaurant/tables', body: {
        'farmId': widget.company.farmId,
        'tableNumber': _number.text,
        'capacity': int.tryParse(_capacity.text) ?? 0,
        'location': _location,
      });
      await _locationOther.currentState?.remember();
      if (!mounted) return;
      trackerToast(context, 'Table added');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Failed', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => HotelDialog(
        icon: Icons.grid_view,
        title: 'Add Table',
        saveLabel: 'Add',
        saving: _saving,
        onSave: _save,
        children: [
          FilterLabel('Table Number *', AppInput(controller: _number, hintText: 'e.g. T1, A1')),
          FilterLabel(
            'Capacity',
            AppInput(controller: _capacity, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
          ),
          FilterLabel(
            'Location',
            HotelOtherSelect(
              key: _locationOther,
              session: widget.session,
              company: widget.company,
              listKey: 'TableLocation',
              baseOptions: widget.locations,
              value: _location,
              onChanged: (v) => setState(() => _location = v ?? ''),
              placeholder: 'Select location',
              includeNone: true,
              otherLabel: 'Other (type location)',
            ),
          ),
        ],
      );
}
