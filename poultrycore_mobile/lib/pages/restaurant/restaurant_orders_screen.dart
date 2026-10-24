// Restaurant → Orders & Kitchen → All Orders, as `app/restaurant-orders/page.tsx`:
// status / type / source filters and Refresh, four figures, a row per order
// (online rows marked rose, with the next status steps), refreshed quietly
// every 10 s, and the order detail with Take payment, Pay later, Refund and
// "Add this person as a customer".
//
// Pressing Completed on an order that still owes money takes payment first
// (the server refuses to complete it unpaid), then completes it.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/reports/report_routes.dart' show openAppHref;
import '../poultry/sales/balances_widgets.dart' show LoadingLine;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr;
import '../poultry/trackers/tracker_widgets.dart';
import 'restaurant_money_kit.dart' show rField, rDateInput, rDialog, rCancel;
import 'restaurant_order_money.dart';
import 'restaurant_roles.dart' show restaurantRose;
import 'restaurant_widgets.dart';

const orderStatusColors = <String, Color>{
  'Placed': Color(0xFF3B82F6),
  'Confirmed': Color(0xFF6366F1),
  'Preparing': Color(0xFFF59E0B),
  'Ready': Color(0xFF22C55E),
  'Served': Color(0xFF14B8A6),
  'Completed': Color(0xFF6B7280),
  'Cancelled': Color(0xFFEF4444),
  'Refunded': Color(0xFFEC4899),
};
const orderStatusFlow = <String, List<String>>{
  'Placed': ['Confirmed', 'Cancelled'],
  'Confirmed': ['Preparing', 'Cancelled'],
  'Preparing': ['Ready'],
  'Ready': ['Served'],
  'Served': ['Completed'],
};

/// An order is "online" when it carries a source (QR / Web / App).
bool isOnlineOrder(Map o) => tStr(o['onlineSource']).isNotEmpty;

String onlineLabel(Map o) => 'ONLINE${switch (tStr(o['onlineSource'])) {
      'QR' => ' · QR',
      'Web' => ' · WEB',
      _ => '',
    }}';

/// The Active filter drops finished orders; the source filter is client-side.
List<Map> visibleOrders(List<Map> orders, String source) => [
      for (final o in orders)
        if (source == 'all' || (source == 'online') == isOnlineOrder(o)) o,
    ];

class RestaurantOrdersScreen extends StatefulWidget {
  const RestaurantOrdersScreen({super.key, required this.session, required this.company, this.openOrderId});
  final Session session;
  final Company company;

  /// Sales → Edit lands here with ?orderId=: open that order.
  final int? openOrderId;

  @override
  State<RestaurantOrdersScreen> createState() => _RestaurantOrdersScreenState();
}

class _RestaurantOrdersScreenState extends State<RestaurantOrdersScreen> {
  bool _loading = true;
  List<Map> _orders = [];
  String _status = 'active';
  String _type = 'all';
  String _source = 'all';
  Timer? _poll;

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  Map<String, dynamic> get _q => {'farmId': _farmId};

  @override
  void initState() {
    super.initState();
    _load(first: true);
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _fetch().then(_apply).catchError((Object _) {}));
    final id = widget.openOrderId;
    if (id != null && id > 0) WidgetsBinding.instance.addPostFrameCallback((_) => _openDetail({'orderId': id}));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _toast(String title, {String? description, bool error = false}) {
    if (mounted) trackerToast(context, title, description: description, error: error);
  }

  String _err(Object e) => e is ApiException ? e.message : '$e';

  Future<List<Map>> _fetch() async {
    final r = await _api.get('/api/Restaurant/orders', query: {
      ..._q,
      '_': 1,
      if (_status != 'active' && _status != 'all') 'status': _status,
      if (_type != 'all') 'orderType': _type,
    });
    return [for (final x in (r is List ? r : const [])) if (x is Map) x];
  }

  void _apply(List<Map> list) {
    if (!mounted) return;
    setState(() => _orders = _status == 'active'
        ? [for (final o in list) if (!const ['Completed', 'Cancelled', 'Refunded'].contains(tStr(o['status']))) o]
        : list);
  }

  Future<void> _load({bool first = false}) async {
    try {
      _apply(await _fetch());
    } catch (e) {
      _toast('Failed', description: _err(e), error: true);
    }
    if (mounted && first) setState(() => _loading = false);
  }

  Future<void> _openDetail(Map o) async {
    try {
      final r = await Future.wait<Object?>([
        loadOrder(_api, _farmId, o['orderId']),
        _api.get('/api/Restaurant/orders/${o['orderId']}/items', query: _q),
      ]);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _OrderDetailDialog(
          session: widget.session,
          company: widget.company,
          order: r[0] as Map,
          items: [for (final x in (r[1] is List ? r[1] as List : const [])) if (x is Map) x],
          onChanged: () => _load(),
        ),
      );
    } catch (e) {
      _toast('Failed', description: _err(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/restaurant-orders');
    final shown = visibleOrders(_orders, _source);
    final now = DateTime.now();
    bool isToday(Map o) {
      final d = DateTime.tryParse(tStr(o['createdAt']))?.toLocal();
      return d != null && d.year == now.year && d.month == now.month && d.day == now.day;
    }

    final today = [for (final o in _orders) if (isToday(o)) o];
    final revenue = today.where((o) => tStr(o['paymentStatus']) == 'Paid').fold<num>(0, (s, o) => s + tNum(o['totalAmount']));
    final online = today.where(isOnlineOrder).length;
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Orders')),
      body: _loading
          ? const Padding(padding: EdgeInsets.all(20), child: LoadingLine('Loading…'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
                RPageHeader(
                  icon: Icons.assignment_outlined,
                  title: 'Orders',
                  subtitle: '${shown.length} orders shown${_source == 'all' ? '' : ' · ${_source == 'online' ? 'online' : 'walk-in'} only'}',
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: AppSelect<String>(
                      value: _status,
                      items: const [
                        AppSelectItem(value: 'active', label: 'Active'),
                        AppSelectItem(value: 'all', label: 'All'),
                        AppSelectItem(value: 'Placed', label: 'Placed'),
                        AppSelectItem(value: 'Preparing', label: 'Preparing'),
                        AppSelectItem(value: 'Ready', label: 'Ready'),
                        AppSelectItem(value: 'Completed', label: 'Completed'),
                        AppSelectItem(value: 'Cancelled', label: 'Cancelled'),
                      ],
                      onChanged: (v) {
                        setState(() => _status = v ?? 'active');
                        _load();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppSelect<String>(
                      value: _type,
                      items: const [
                        AppSelectItem(value: 'all', label: 'All Types'),
                        AppSelectItem(value: 'DineIn', label: 'Dine In'),
                        AppSelectItem(value: 'Takeaway', label: 'Takeaway'),
                        AppSelectItem(value: 'Delivery', label: 'Delivery'),
                      ],
                      onChanged: (v) {
                        setState(() => _type = v ?? 'all');
                        _load();
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: AppSelect<String>(
                      value: _source,
                      items: const [
                        AppSelectItem(value: 'all', label: 'All Sources'),
                        AppSelectItem(value: 'online', label: 'Online only'),
                        AppSelectItem(value: 'pos', label: 'Walk-in only'),
                      ],
                      onChanged: (v) => setState(() => _source = v ?? 'all'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh, size: 18)),
                ]),
                const SizedBox(height: 12),
                twoColumns([
                  RStatCard(label: 'Total Orders', value: '${_orders.length}', icon: Icons.assignment_outlined, color: 'blue'),
                  RStatCard(label: "Today's Revenue", value: revenue.toStringAsFixed(0), icon: Icons.attach_money, color: 'green'),
                  RStatCard(label: "Today's Orders", value: '${today.length}', icon: Icons.schedule, color: 'amber'),
                  RStatCard(label: 'Online Today', value: '$online', icon: Icons.public, color: 'rose'),
                ]),
                const SizedBox(height: 12),
                TCard(
                  child: shown.isEmpty
                      ? const REmptyState(
                          icon: Icons.assignment_outlined,
                          title: 'No orders found',
                          description: 'Orders will appear here once placed via POS or online',
                        )
                      : Column(children: [for (final o in shown) _row(o)]),
                ),
              ]),
            ),
    );
  }

  Widget _row(Map o) {
    final online = isOnlineOrder(o);
    final status = tStr(o['status']);
    final created = DateTime.tryParse(tStr(o['createdAt']));
    Widget meta(IconData? icon, String text, {Color? color}) => Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 12, color: color ?? TColors.slate500), const SizedBox(width: 3)],
          Flexible(child: Text(text, style: TextStyle(fontSize: 12, color: color ?? TColors.slate500))),
        ]);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: online ? const Color(0x66FFF1F2) : Colors.white,
        border: Border.all(color: online ? const Color(0xFFFECDD3) : TColors.slate200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _openDetail(o),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 6, color: online ? const Color(0xFFF43F5E) : Colors.transparent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 12, 8, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        Text(tStr(o['orderNumber']), style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700)),
                        online
                            ? rBadge(onlineLabel(o), bg: const Color(0xFFE11D48), fg: Colors.white)
                            : rBadge('WALK-IN', bg: Colors.white, fg: TColors.slate500, border: TColors.slate200),
                        rBadge(tStr(o['orderType']), bg: Colors.white, border: TColors.slate200),
                        rBadge(status, bg: orderStatusColors[status] ?? const Color(0xFF6B7280), fg: Colors.white),
                        if (tStr(o['paymentStatus']) == 'Paid') rBadge('Paid', bg: const Color(0xFFDCFCE7), fg: const Color(0xFF15803D)),
                        if (online && status == 'Placed') rBadge('Awaiting confirmation', bg: const Color(0xFFFEF3C7), fg: const Color(0xFF92400E)),
                        if (o['customerId'] != null) rBadge('✓ Customer', bg: const Color(0xFFD1FAE5), fg: const Color(0xFF065F46)),
                      ]),
                    ),
                    Text(tNum(o['totalAmount']).toStringAsFixed(2), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    const Icon(Icons.chevron_right, size: 18, color: Color(0xFFD1D5DB)),
                  ]),
                  const SizedBox(height: 4),
                  Wrap(spacing: 12, runSpacing: 2, children: [
                    if (created != null) meta(Icons.schedule, DateFormat('HH:mm').format(created.toLocal())),
                    if (tStr(o['tableNumber']).isNotEmpty) meta(Icons.place_outlined, 'Table ${tStr(o['tableNumber'])}'),
                    if (tStr(o['customerName']).isNotEmpty) meta(Icons.people_outline, tStr(o['customerName'])),
                    meta(null, '${tNum(o['itemCount']).toInt()} items'),
                    if (tStr(o['customerPhone']).isNotEmpty) meta(Icons.phone_outlined, tStr(o['customerPhone'])),
                    if (tStr(o['guestPaymentIntent']).isNotEmpty)
                      meta(null, 'Plans to pay by ${tStr(o['guestPaymentIntent'])}', color: const Color(0xFFE11D48)),
                  ]),
                  if (orderStatusFlow[status] != null) ...[
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, children: [
                      for (final next in orderStatusFlow[status]!)
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: next == 'Cancelled' ? const Color(0xFFEF4444) : restaurantRose,
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () => changeOrderStatus(context, _api, _farmId, o, next, onDone: _load),
                          child: Text(next),
                        ),
                    ]),
                  ],
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Moves [order] to [status]. Completing an order that still owes money takes
/// payment first and completes it once fully paid. Returns the fresh order.
Future<Map?> changeOrderStatus(BuildContext context, ApiClient api, String farmId, Map order, String status,
    {bool justPaid = false, required VoidCallback onDone}) async {
  final total = tNum(order['totalAmount']);
  if (status == 'Completed' && !justPaid && total > 0 && tNum(order['paidAmount']) < total) {
    try {
      final fresh = await loadOrder(api, farmId, order['orderId']);
      if (!context.mounted) return null;
      final r = await showDialog<OrderPaymentResult>(context: context, builder: (_) => TakePaymentDialog(api: api, farmId: farmId, order: fresh));
      if (r == null || !context.mounted) return null;
      paidToast(context, r);
      if (tStr(r.order['paymentStatus']) == 'Paid') {
        return await changeOrderStatus(context, api, farmId, r.order, 'Completed', justPaid: true, onDone: onDone);
      }
      onDone();
      return r.order;
    } catch (e) {
      if (context.mounted) trackerToast(context, 'Failed', description: e is ApiException ? e.message : '$e', error: true);
      return null;
    }
  }
  try {
    await api.patch('/api/Restaurant/orders/${order['orderId']}/status', query: {'farmId': farmId}, body: {'status': status});
    if (context.mounted) trackerToast(context, 'Order $status');
    onDone();
    return await loadOrder(api, farmId, order['orderId']);
  } catch (e) {
    if (context.mounted) trackerToast(context, 'Failed', description: e is ApiException ? e.message : '$e', error: true);
    return null;
  }
}

void paidToast(BuildContext context, OrderPaymentResult r) {
  final due = tNum(r.order['totalAmount']) - tNum(r.order['paidAmount']);
  trackerToast(context, '${r.applied.toStringAsFixed(2)} received',
      description: r.change > 0
          ? 'Give ${r.change.toStringAsFixed(2)} change.'
          : tStr(r.order['paymentStatus']) == 'Paid'
              ? 'Order fully paid.'
              : '${due.toStringAsFixed(2)} still due.');
}

class _OrderDetailDialog extends StatefulWidget {
  const _OrderDetailDialog({required this.session, required this.company, required this.order, required this.items, required this.onChanged});
  final Session session;
  final Company company;
  final Map order;
  final List<Map> items;
  final VoidCallback onChanged;

  @override
  State<_OrderDetailDialog> createState() => _OrderDetailDialogState();
}

class _OrderDetailDialogState extends State<_OrderDetailDialog> {
  late Map _o = widget.order;
  bool _linking = false;

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;

  Future<void> _refresh() async {
    final fresh = await loadOrder(_api, _farmId, _o['orderId']);
    if (mounted) setState(() => _o = fresh);
  }

  Future<void> _status(String next) async {
    final fresh = await changeOrderStatus(context, _api, _farmId, _o, next, onDone: widget.onChanged);
    if (fresh != null && mounted) setState(() => _o = fresh);
  }

  Future<void> _pay() async {
    final r = await showDialog<OrderPaymentResult>(context: context, builder: (_) => TakePaymentDialog(api: _api, farmId: _farmId, order: _o));
    if (r == null || !mounted) return;
    paidToast(context, r);
    widget.onChanged();
    setState(() => _o = r.order);
  }

  Future<void> _refund() async {
    final fresh = await showDialog<Map>(context: context, builder: (_) => RefundDialog(api: _api, farmId: _farmId, order: _o));
    if (fresh == null || !mounted) return;
    widget.onChanged();
    setState(() => _o = fresh);
  }

  Future<void> _payLater() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _PayLaterDialog(api: _api, farmId: _farmId, order: _o));
    if (ok != true || !mounted) return;
    trackerToast(context, 'Order ${tStr(_o['orderNumber'])} completed — pay later',
        description: '${(tNum(_o['totalAmount']) - tNum(_o['paidAmount'])).toStringAsFixed(2)} is now on Customer Balances.');
    widget.onChanged();
    await _refresh();
  }

  /// Saves the guest into the CRM; the server matches an existing customer by
  /// phone, so pressing it twice links rather than duplicates.
  Future<void> _addAsCustomer() async {
    setState(() => _linking = true);
    try {
      final r = await _api.post('/api/Restaurant/orders/${_o['orderId']}/link-customer', query: {'farmId': _farmId});
      final m = r is Map ? r : const {};
      final visits = tNum(m['totalVisits']).toInt();
      if (mounted) {
        trackerToast(context, m['created'] == true ? '${tStr(m['name'])} saved as a customer' : 'Matched ${tStr(m['name'])}',
            description: m['created'] == true
                ? tStr(m['message'])
                : '${tStr(m['message'])} Now $visits visit${visits == 1 ? '' : 's'} — ${tStr(m['segment'])}.');
      }
      await _refresh();
      widget.onChanged();
    } catch (e) {
      if (mounted) trackerToast(context, 'Could not save the customer', description: e is ApiException ? e.message : '$e', error: true);
    }
    if (mounted) setState(() => _linking = false);
  }

  @override
  Widget build(BuildContext context) {
    final o = _o;
    final status = tStr(o['status']);
    final online = isOnlineOrder(o);
    final created = DateTime.tryParse(tStr(o['createdAt']));
    final total = tNum(o['totalAmount']);
    final paid = tNum(o['paidAmount']);
    final canPay = !const ['Cancelled', 'Refunded'].contains(status) && paid < total;
    final canRefund = status != 'Refunded' && paid > 0;
    final canPayLater = canPay && o['customerId'] != null && status != 'Completed';
    Widget fact(String k, String v) => Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: const Color(0xFFF9FAFB), borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            Text(k, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(width: 8),
            Expanded(child: Text(v, textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
          ]),
        );
    Widget sum(String k, num v, {Color? color, bool neg = false, bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Text(k, style: TextStyle(fontSize: bold ? 17 : 14, fontWeight: bold ? FontWeight.w700 : null, color: color ?? (bold ? null : TColors.slate500))),
            const Spacer(),
            Text('${neg ? '-' : ''}${v.toStringAsFixed(2)}',
                style: TextStyle(fontSize: bold ? 17 : 14, fontWeight: bold ? FontWeight.w700 : null, color: bold ? const Color(0xFFBE123C) : color)),
          ]),
        );
    final contact = <Widget>[
      if (tStr(o['customerPhone']).isNotEmpty) _contact(Icons.phone_outlined, tStr(o['customerPhone'])),
      if (tStr(o['customerEmail']).isNotEmpty) _contact(Icons.mail_outline, tStr(o['customerEmail'])),
      if (tStr(o['guestPaymentIntent']).isNotEmpty)
        _contact(Icons.attach_money,
            'Plans to pay by ${tStr(o['guestPaymentIntent'])}${tNum(o['guestPaymentAmount']) != 0 ? ' (${tNum(o['guestPaymentAmount']).toStringAsFixed(2)})' : ''}'),
      if (tStr(o['deliveryAddress']).isNotEmpty) _contact(Icons.place_outlined, tStr(o['deliveryAddress'])),
    ];
    return AlertDialog(
      scrollable: true,
      title: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(tStr(o['orderNumber'])),
        online
            ? rBadge(onlineLabel(o), bg: const Color(0xFFE11D48), fg: Colors.white)
            : rBadge('WALK-IN', bg: Colors.white, fg: TColors.slate500, border: TColors.slate200),
        rBadge(status, bg: orderStatusColors[status] ?? const Color(0xFF6B7280), fg: Colors.white),
      ]),
      content: SizedBox(
        width: 480,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Order details and line items', style: TextStyle(fontSize: 13, color: TColors.slate500)),
          const SizedBox(height: 12),
          for (final (k, v) in [
            ('Type', tStr(o['orderType'])),
            ('Table', tStr(o['tableNumber']).isEmpty ? '—' : tStr(o['tableNumber'])),
            ('Customer', tStr(o['customerName']).isEmpty ? 'Walk-in' : tStr(o['customerName'])),
            ('Covers', '${tNum(o['covers']).toInt()}'),
            ('Server', tStr(o['servedBy']).isEmpty ? '—' : tStr(o['servedBy'])),
            ('Created', created == null ? '' : DateFormat('d/M/yyyy, HH:mm:ss').format(created.toLocal())),
          ]) ...[fact(k, v), const SizedBox(height: 6)],
          if (online) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: const Color(0x99FFF1F2), border: Border.all(color: const Color(0xFFFECDD3)), borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.public, size: 14, color: Color(0xFFBE123C)),
                  SizedBox(width: 6),
                  Text('ONLINE ORDER', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: .6, color: Color(0xFFBE123C))),
                ]),
                const SizedBox(height: 6),
                ...contact,
                if (status == 'Placed')
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: 'Not yet confirmed — the kitchen cannot see this order. Accept it under'),
                        TextSpan(text: ' New Guest Orders', style: TextStyle(fontWeight: FontWeight.w500)),
                        TextSpan(text: '.'),
                      ]),
                      style: TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                    ),
                  ),
              ]),
            ),
          ],
          if (tStr(o['customerName']).isNotEmpty || tStr(o['customerPhone']).isNotEmpty) ...[
            const SizedBox(height: 10),
            o['customerId'] != null
                ? Container(
                    padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                    decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5), border: Border.all(color: const Color(0xFFA7F3D0)), borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      const Icon(Icons.how_to_reg_outlined, size: 16, color: Color(0xFF065F46)),
                      const SizedBox(width: 8),
                      const Expanded(child: Text('Saved as a customer.', style: TextStyle(fontSize: 14, color: Color(0xFF065F46)))),
                      TextButton(
                        style: TextButton.styleFrom(foregroundColor: const Color(0xFF065F46)),
                        onPressed: () => openAppHref(context, widget.session, widget.company, '/restaurant-crm', label: 'Customers & CRM'),
                        child: const Text('View ›'),
                      ),
                    ]),
                  )
                : Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: const Color(0x80FFF1F2), border: Border.all(color: const Color(0xFFFECDD3)), borderRadius: BorderRadius.circular(12)),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.star_border, size: 16, color: Color(0xFFF43F5E)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Not a saved customer yet', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                          Text(
                              'Save ${tStr(o['customerName']).isEmpty ? 'this guest' : tStr(o['customerName'])}'
                              '${tStr(o['customerPhone']).isEmpty ? '' : ' (${tStr(o['customerPhone'])})'} so repeat visits are recognised and count towards Regular and VIP.',
                              style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: restaurantRose, visualDensity: VisualDensity.compact),
                            onPressed: _linking ? null : _addAsCustomer,
                            icon: const Icon(Icons.person_add_alt, size: 14),
                            label: const Text('Add this person as a customer'),
                          ),
                        ]),
                      ),
                    ]),
                  ),
          ],
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                color: const Color(0xFFF9FAFB),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: const Text('ITEMS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: .6, color: TColors.slate500)),
              ),
              for (final i in widget.items)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: TColors.slate200))),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Wrap(spacing: 6, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        Text('${tNum(i['quantity']).toInt()}x', style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFE11D48))),
                        Text(tStr(i['itemName']), style: const TextStyle(fontWeight: FontWeight.w500)),
                        rBadge(tStr(i['status']), bg: Colors.white, border: TColors.slate200),
                        if (tStr(i['notes']).isNotEmpty)
                          Text(tStr(i['notes']), style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: TColors.slate500)),
                      ]),
                    ),
                    Text(tNum(i['lineTotal']).toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.w500)),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: 10),
          sum('Subtotal', tNum(o['subtotal'])),
          if (tNum(o['discountAmount']) > 0) sum('Discount', tNum(o['discountAmount']), color: const Color(0xFFDC2626), neg: true),
          if (tNum(o['serviceChargeAmount']) > 0) sum('Service charge', tNum(o['serviceChargeAmount'])),
          if (tNum(o['taxAmount']) > 0) sum('Tax', tNum(o['taxAmount'])),
          const Divider(height: 14),
          sum('Total', total, bold: true),
          Row(children: [
            const Text('Paid', style: TextStyle(fontSize: 14, color: TColors.slate500)),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${paid.toStringAsFixed(2)} (${tStr(o['paymentStatus'])})',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: tStr(o['paymentStatus']) == 'Paid' ? FontWeight.w500 : null,
                      color: tStr(o['paymentStatus']) == 'Paid' ? const Color(0xFF16A34A) : const Color(0xFFD97706))),
            ),
          ]),
          if (orderStatusFlow[status] != null) ...[
            const SizedBox(height: 10),
            Row(children: [
              for (final (i, next) in orderStatusFlow[status]!.indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: next == 'Cancelled' ? const Color(0xFFEF4444) : restaurantRose),
                    onPressed: () => _status(next),
                    child: Text('Move to $next'),
                  ),
                ),
              ],
            ]),
          ],
          if (canPay || canRefund) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (canPay)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF15803D), side: const BorderSide(color: Color(0xFF86EFAC))),
                  onPressed: _pay,
                  icon: const Icon(Icons.attach_money, size: 16),
                  label: Text('Take payment (${(total - paid).toStringAsFixed(2)})'),
                ),
              if (canPayLater)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFB45309), side: const BorderSide(color: Color(0xFFFCD34D))),
                  onPressed: _payLater,
                  icon: const Icon(Icons.schedule, size: 16),
                  label: const Text('Pay later'),
                ),
              if (canRefund)
                OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFBE123C), side: const BorderSide(color: Color(0xFFFDA4AF))),
                  onPressed: _refund,
                  child: const Text('Refund'),
                ),
            ]),
          ],
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }

  Widget _contact(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Icon(icon, size: 14, color: const Color(0xFF9CA3AF)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14, color: Color(0xFF374151)))),
        ]),
      );
}

/// Pay later (migration 333): complete the order now; what is left is owed by
/// its saved customer on Customer Balances. Optional due date.
class _PayLaterDialog extends StatefulWidget {
  const _PayLaterDialog({required this.api, required this.farmId, required this.order});
  final ApiClient api;
  final String farmId;
  final Map order;
  @override
  State<_PayLaterDialog> createState() => _PayLaterDialogState();
}

class _PayLaterDialogState extends State<_PayLaterDialog> {
  String _due = '';
  bool _saving = false;

  Future<void> _confirm() async {
    setState(() => _saving = true);
    try {
      await widget.api.post('/api/Restaurant/orders/${widget.order['orderId']}/pay-later',
          query: {'farmId': widget.farmId}, body: {'farmId': widget.farmId, 'dueDate': _due.isEmpty ? null : _due, 'notes': null});
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        trackerToast(context, 'Could not complete as pay later', description: e is ApiException ? e.message : '$e', error: true);
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final owed = tNum(o['totalAmount']) - tNum(o['paidAmount']);
    return rDialog(
      title: 'Pay later — ${tStr(o['orderNumber'])}',
      description: 'The order is completed now and ${owed.toStringAsFixed(2)} is owed by '
          '${tStr(o['customerName']).isEmpty ? 'this customer' : tStr(o['customerName'])}. It shows on Customer Balances until it is paid. '
          'The sale counts today; the cash counts when it is received.',
      children: [
        rField(
          'Due date (optional)',
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            rDateInput(_due, (d) => setState(() => _due = d)),
            const SizedBox(height: 4),
            const Text('Leave empty if it is due today.', style: TextStyle(fontSize: 12, color: TColors.slate500)),
          ]),
        ),
      ],
      actions: [
        rCancel(context, 'Cancel', busy: _saving),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: restaurantRose),
          onPressed: _saving ? null : _confirm,
          child: const Text('Complete as pay later'),
        ),
      ],
    );
  }
}
