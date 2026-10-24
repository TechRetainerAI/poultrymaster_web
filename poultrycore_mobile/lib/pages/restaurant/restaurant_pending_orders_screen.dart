// Restaurant → Orders & Kitchen → New Guest Orders, as
// `app/restaurant-pending-orders/page.tsx`: orders guests sent from their
// phones wait here (migration 248 keeps them off the kitchen display) until
// staff Accept or Reject them. Polled every 10 s; a chime on new arrivals
// (never on the first load) unless Sound is off; older orders turn amber at
// 5 minutes and red at 10.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/sales/balances_widgets.dart' show LoadingLine;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/reason_select.dart';
import 'restaurant_money_kit.dart' show rDialog, rCancel;
import 'restaurant_orders_screen.dart' show onlineLabel;
import 'restaurant_widgets.dart';

/// waitTone: border and background by how long the order has waited.
(Color, Color) pendingWaitTone(num mins) {
  if (mins >= 10) return (const Color(0xFFFCA5A5), const Color(0xFFFEF2F2));
  if (mins >= 5) return (const Color(0xFFFCD34D), const Color(0xFFFFFBEB));
  return (TColors.slate200, Colors.white);
}

class RestaurantPendingOrdersScreen extends StatefulWidget {
  const RestaurantPendingOrdersScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<RestaurantPendingOrdersScreen> createState() => _RestaurantPendingOrdersScreenState();
}

class _RestaurantPendingOrdersScreenState extends State<RestaurantPendingOrdersScreen> {
  bool _loading = true;
  List<Map> _orders = [];
  int? _busy;
  bool _soundOn = true;
  int _prevCount = 0;
  Timer? _poll;

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  Map<String, dynamic> get _q => {'farmId': _farmId};

  @override
  void initState() {
    super.initState();
    _refresh().whenComplete(() {
      if (mounted) setState(() => _loading = false);
    });
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final r = await _api.get('/api/Restaurant/online/pending-orders', query: _q);
      final list = [for (final x in (r is List ? r : const [])) if (x is Map) x];
      if (_soundOn && _prevCount > 0 && list.length > _prevCount) SystemSound.play(SystemSoundType.alert);
      _prevCount = list.length;
      if (mounted) setState(() => _orders = list);
    } catch (_) {
      // A dropped poll is not worth a toast every 10 seconds.
    }
  }

  Future<void> _accept(Map o) async {
    setState(() => _busy = tNum(o['orderId']).toInt());
    try {
      final r = await _api.post('/api/Restaurant/online/orders/${o['orderId']}/accept', query: _q);
      if (mounted) trackerToast(context, 'Order ${tStr(o['orderNumber'])} confirmed', description: r is Map ? tStr(r['message']) : null);
      await _refresh();
    } catch (e) {
      if (mounted) trackerToast(context, 'Could not confirm', description: e is ApiException ? e.message : '$e', error: true);
    }
    if (mounted) setState(() => _busy = null);
  }

  Future<void> _reject(Map o) async {
    final done = await showDialog<bool>(context: context, builder: (_) => _RejectDialog(api: _api, farmId: _farmId, order: o));
    if (done == true) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/restaurant-pending-orders');
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('New Guest Orders')),
      body: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                const Icon(Icons.inbox_outlined, size: 24, color: Color(0xFFE11D48)),
                const Text('New Orders', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
                if (_orders.isNotEmpty) rBadge('${_orders.length}', bg: const Color(0xFFE11D48), fg: Colors.white),
              ]),
              const SizedBox(height: 2),
              const Text('Orders guests sent from their phones. They do not reach the kitchen until you accept them.',
                  style: TextStyle(fontSize: 13, color: TColors.slate500)),
            ]),
          ),
          OutlinedButton.icon(
            onPressed: () => setState(() => _soundOn = !_soundOn),
            icon: Icon(_soundOn ? Icons.volume_up_outlined : Icons.volume_off_outlined, size: 16),
            label: Text(_soundOn ? 'Sound on' : 'Sound off'),
          ),
        ]),
        const SizedBox(height: 16),
        if (_loading)
          const LoadingLine('Loading…')
        else if (_orders.isEmpty)
          const TCard(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Column(children: [
                Icon(Icons.inbox_outlined, size: 48, color: Color(0xFFD1D5DB)),
                SizedBox(height: 10),
                Text('No orders waiting', style: TextStyle(fontWeight: FontWeight.w500, color: Color(0xFF374151))),
                SizedBox(height: 4),
                Text('New orders from table QR codes appear here within a few seconds.',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: TColors.slate500)),
              ]),
            ),
          )
        else
          for (final o in _orders) _card(o),
      ]),
    );
  }

  Widget _card(Map o) {
    final mins = tNum(o['waitingMinutes']);
    final (border, bg) = pendingWaitTone(mins);
    final busy = _busy == tNum(o['orderId']).toInt();
    final count = tNum(o['itemCount']).toInt();
    Widget info(IconData icon, String text, {bool strong = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 1.5),
          child: Row(children: [
            Icon(icon, size: 14, color: const Color(0xFF9CA3AF)),
            const SizedBox(width: 6),
            Expanded(
                child: Text(text,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: strong ? FontWeight.w500 : null,
                        color: strong ? const Color(0xFF111827) : const Color(0xFF4B5563)))),
          ]),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, border: Border.all(color: border, width: 2), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 6, children: [
          rBadge(onlineLabel(o), bg: const Color(0xFFE11D48), fg: Colors.white),
          rBadge(tStr(o['orderType']), bg: Colors.white, fg: const Color(0xFF4B5563), border: TColors.slate200),
        ]),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (tStr(o['tableNumber']).isNotEmpty)
                rBadge('Table ${tStr(o['tableNumber'])}', bg: Colors.white, fg: const Color(0xFFBE123C), border: const Color(0xFFFDA4AF)),
              const SizedBox(height: 4),
              Text(tStr(o['orderNumber']), style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: TColors.slate500)),
            ]),
          ),
          const Icon(Icons.schedule, size: 14, color: TColors.slate500),
          const SizedBox(width: 3),
          Text('${mins.floor()}m', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
        ]),
        const SizedBox(height: 8),
        info(Icons.person_outline, tStr(o['customerName']).isEmpty ? 'Guest' : tStr(o['customerName']), strong: true),
        if (tStr(o['customerPhone']).isNotEmpty) info(Icons.phone_outlined, tStr(o['customerPhone'])),
        if (tStr(o['customerEmail']).isNotEmpty) info(Icons.mail_outline, tStr(o['customerEmail'])),
        if (tStr(o['guestPaymentIntent']).isNotEmpty) info(Icons.payments_outlined, 'Plans to pay by ${tStr(o['guestPaymentIntent'])}'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFF9FAFB), borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Icon(Icons.restaurant, size: 14, color: Color(0xFF6B7280)),
              const SizedBox(width: 6),
              Text('$count item${count == 1 ? '' : 's'}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF6B7280))),
            ]),
            const SizedBox(height: 4),
            Text(tStr(o['itemSummary']).isEmpty ? '—' : tStr(o['itemSummary']), style: const TextStyle(fontSize: 14, color: Color(0xFF1F2937))),
            if (tStr(o['notes']).isNotEmpty) ...[
              const Divider(height: 14),
              Text('“${tStr(o['notes'])}”', style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Color(0xFFB45309))),
            ],
          ]),
        ),
        const SizedBox(height: 8),
        Text(tNum(o['totalAmount']).toStringAsFixed(2),
            textAlign: TextAlign.right, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFFE11D48))),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF059669)),
              onPressed: busy ? null : () => _accept(o),
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Accept'),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFDC2626), side: const BorderSide(color: Color(0xFFFECACA))),
            onPressed: busy ? null : () => _reject(o),
            icon: const Icon(Icons.close, size: 16),
            label: const Text('Reject'),
          ),
        ]),
      ]),
    );
  }
}

class _RejectDialog extends StatefulWidget {
  const _RejectDialog({required this.api, required this.farmId, required this.order});
  final ApiClient api;
  final String farmId;
  final Map order;
  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  String _reason = '';
  bool _busy = false;

  Future<void> _confirm() async {
    setState(() => _busy = true);
    try {
      await widget.api.post('/api/Restaurant/online/orders/${widget.order['orderId']}/reject', query: {'farmId': widget.farmId}, body: {'reason': _reason});
      if (!mounted) return;
      trackerToast(context, 'Order ${tStr(widget.order['orderNumber'])} rejected');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        trackerToast(context, 'Could not reject', description: e is ApiException ? e.message : '$e', error: true);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => rDialog(
        title: 'Reject order ${tStr(widget.order['orderNumber'])}?',
        description: 'The guest sees this reason on their phone. It is the only way to tell them, so say something they can act on.',
        children: [
          ReasonSelect(
            options: orderRejectReasons,
            value: _reason,
            onChanged: (v) => setState(() => _reason = v),
            otherPlaceholder: 'e.g. Sorry, the kitchen has closed for the evening.',
            multiline: true,
          ),
        ],
        actions: [
          rCancel(context, 'Cancel'),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: _busy ? null : _confirm,
            child: const Text('Reject order'),
          ),
        ],
      );
}
