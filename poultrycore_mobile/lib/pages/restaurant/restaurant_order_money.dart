// Take Payment and Refund, shared by the POS and the Orders screen, as
// `components/restaurant/order-money-dialogs.tsx` (migration 323):
//  - A payment sends the amount APPLIED to the bill, never the cash tendered.
//    Change is shown and never stored; the server refuses more than is due.
//  - Cash goes to a till. With several tills open the dialog asks which one;
//    with none open it lands in the main cash box.
//  - A gift card is a payment method, debited in the same call.

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/reason_select.dart';
import 'restaurant_money_kit.dart' show rField, rFin, rDialog, rCancel;

double round2(num n) => (n * 100).roundToDouble() / 100;
String orderMoney(num n) => round2(n).toStringAsFixed(2);

/// `value || 0` for a typed amount.
double _num(String v) => double.tryParse(v.trim()) ?? 0;

/// What a recorded payment comes back as.
class OrderPaymentResult {
  const OrderPaymentResult(this.order, {required this.method, required this.applied, required this.tendered, required this.change, required this.tip});
  final Map order;
  final String method;
  final double applied;
  final double tendered;
  final double change;
  final double tip;
}

const orderPayMethods = [
  ('Cash', Icons.payments_outlined, 'Cash'),
  ('Card', Icons.credit_card, 'Card'),
  ('MobileMoney', Icons.smartphone, 'Mobile Money'),
  ('GiftCard', Icons.card_giftcard, 'Gift Card'),
];
const orderRefundMethods = [('Cash', 'Cash'), ('Card', 'Card'), ('MobileMoney', 'Mobile Money'), ('Bank Transfer', 'Bank Transfer')];

/// The open tills; a failure leaves none, so cash goes to the cash box.
Future<List<Map>> loadOpenShifts(ApiClient api, String farmId) async {
  try {
    final r = await api.get(rFin('/shifts', farmId, {'status': 'Open'}));
    return [for (final x in (r is List ? r : const [])) if (x is Map) x];
  } catch (_) {
    return [];
  }
}

Future<Map> loadOrder(ApiClient api, String farmId, Object? orderId) async {
  final o = await api.get('/api/Restaurant/orders/$orderId', query: {'farmId': farmId});
  return o is Map ? o : {};
}

class _TillPicker extends StatelessWidget {
  const _TillPicker({required this.shifts, required this.value, required this.onChanged});
  final List<Map> shifts;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (shifts.isEmpty) {
      return const Text('No till shift is open — cash will be recorded in the main cash box.',
          style: TextStyle(fontSize: 12, color: TColors.slate500));
    }
    if (shifts.length == 1) {
      return Text.rich(
        TextSpan(children: [
          const TextSpan(text: 'Cash goes into '),
          TextSpan(text: tStr(shifts.first['tillName']), style: const TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: ' (${tStr(shifts.first['shiftNumber'])}).'),
        ]),
        style: const TextStyle(fontSize: 12, color: TColors.slate500),
      );
    }
    return rField(
      'Till',
      AppSelect<int>(
        value: value,
        hintText: 'Which till is the cash going into?',
        items: [
          for (final s in shifts)
            AppSelectItem(
              value: tNum(s['shiftId']).toInt(),
              label: '${tStr(s['tillName'])} — ${tStr(s['shiftNumber'])}${tStr(s['openedBy']).isEmpty ? '' : ' (${tStr(s['openedBy'])})'}',
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

/// Take payment. Pops with an [OrderPaymentResult] once recorded.
class TakePaymentDialog extends StatefulWidget {
  const TakePaymentDialog({super.key, required this.api, required this.farmId, required this.order});
  final ApiClient api;
  final String farmId;
  final Map order;

  @override
  State<TakePaymentDialog> createState() => _TakePaymentDialogState();
}

class _TakePaymentDialogState extends State<TakePaymentDialog> {
  List<Map> _shifts = [];
  String _method = 'Cash';
  late final double _due = round2(tNum(widget.order['totalAmount']) - tNum(widget.order['paidAmount']));
  late final _tendered = TextEditingController(text: _due != 0 ? orderMoney(_due) : '');
  late final _amount = TextEditingController(text: _due != 0 ? orderMoney(_due) : '');
  final _tip = TextEditingController();
  final _reference = TextEditingController();
  int? _shiftId;
  double? _cardBalance;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    loadOpenShifts(widget.api, widget.farmId).then((s) {
      if (mounted) setState(() => _shifts = s);
    });
  }

  @override
  void dispose() {
    for (final c in [_tendered, _amount, _tip, _reference]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isCash => _method == 'Cash';
  double get _tenderedNum => round2(_num(_tendered.text));
  double get _applied => _isCash ? round2(_tenderedNum < _due ? _tenderedNum : _due) : round2(_num(_amount.text));
  double get _change => _isCash ? round2(_tenderedNum - _due > 0 ? _tenderedNum - _due : 0) : 0;
  double get _tipNum => round2(_num(_tip.text));

  String? get _problem {
    if (_due <= 0) return 'This order is already fully paid.';
    if (_applied <= 0) return _isCash ? 'Enter the cash received.' : 'Enter the amount.';
    if (!_isCash && _applied > _due) return 'The most you can take is ${orderMoney(_due)}.';
    if (_method == 'GiftCard' && _reference.text.trim().isEmpty) return 'Enter the gift card number.';
    if (_method == 'GiftCard' && _cardBalance != null && _applied > _cardBalance!) return 'The card only has ${orderMoney(_cardBalance!)}.';
    if (_isCash && _shifts.length > 1 && _shiftId == null) return 'Choose the till.';
    if (_tipNum < 0) return 'A tip cannot be negative.';
    if (_method == 'GiftCard' && _tipNum > 0) return 'A tip cannot be paid from a gift card.';
    return null;
  }

  Future<void> _lookUpCard() async {
    final ref = _reference.text.trim();
    if (ref.isEmpty) return;
    Map? card;
    try {
      final r = await widget.api.get('/api/Restaurant/gift-cards/balance/${Uri.encodeComponent(ref)}', query: {'farmId': widget.farmId});
      card = r is Map ? r : null;
    } catch (_) {
      card = null;
    }
    if (!mounted) return;
    if (card == null) {
      setState(() => _cardBalance = null);
      trackerToast(context, 'Card not found', error: true);
      return;
    }
    final bal = tNum(card['currentBalance']).toDouble();
    setState(() {
      _cardBalance = bal;
      _amount.text = orderMoney(bal < _due ? bal : _due);
    });
    if (tStr(card['status']) != 'Active') trackerToast(context, 'Card is ${tStr(card['status'])}', error: true);
  }

  Future<void> _submit() async {
    if (_problem != null) return;
    setState(() => _saving = true);
    final o = widget.order;
    try {
      await widget.api.post('/api/Restaurant/orders/${o['orderId']}/payments', query: {'farmId': widget.farmId}, body: {
        'paymentMethod': _method,
        'amount': _applied,
        'tipAmount': _tipNum,
        'reference': _method == 'GiftCard' ? _reference.text.trim() : null,
        'shiftId': _isCash ? _shiftId : null,
      });
      final fresh = await loadOrder(widget.api, widget.farmId, o['orderId']);
      if (!mounted) return;
      Navigator.pop(
          context,
          OrderPaymentResult(fresh,
              method: _method, applied: _applied, tendered: _isCash ? _tenderedNum : _applied, change: _change, tip: _tipNum));
    } catch (e) {
      if (mounted) {
        trackerToast(context, 'Payment not recorded', description: e is ApiException ? e.message : '$e', error: true);
        setState(() => _saving = false);
      }
    }
  }

  Widget _figure(String label, String value, {bool green = false}) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: green ? const Color(0xFFF0FDF4) : null,
            border: Border.all(color: green ? const Color(0xFFBBF7D0) : TColors.slate200),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(children: [
            Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        ),
      );

  Widget _bigBox(TextEditingController c) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(border: OutlineInputBorder()),
      );

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final paid = tNum(o['paidAmount']);
    final problem = _problem;
    Widget line(String k, num v, {bool red = false, bool neg = false}) => Row(children: [
          Text(k, style: TextStyle(fontSize: 12, color: red ? const Color(0xFFDC2626) : null)),
          const Spacer(),
          Text('${neg ? '-' : ''}${orderMoney(v)}', style: TextStyle(fontSize: 12, color: red ? const Color(0xFFDC2626) : null)),
        ]);
    return rDialog(
      title: 'Take payment — ${tStr(o['orderNumber'])}',
      description: 'Total ${orderMoney(tNum(o['totalAmount']))}${paid > 0 ? ' · paid ${orderMoney(paid)}' : ''} · due ${orderMoney(_due)}',
      children: [
        if (tNum(o['taxAmount']) > 0 || tNum(o['serviceChargeAmount']) > 0 || tNum(o['discountAmount']) > 0)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFF9FAFB), borderRadius: BorderRadius.circular(8)),
            child: Column(children: [
              line('Subtotal', tNum(o['subtotal'])),
              if (tNum(o['discountAmount']) > 0) line('Discount', tNum(o['discountAmount']), red: true, neg: true),
              if (tNum(o['serviceChargeAmount']) > 0) line('Service charge', tNum(o['serviceChargeAmount'])),
              if (tNum(o['taxAmount']) > 0) line('Tax', tNum(o['taxAmount'])),
            ]),
          ),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.8,
          children: [
            for (final (id, icon, label) in orderPayMethods)
              Material(
                color: _method == id ? const Color(0xFFFFF1F2) : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: _method == id ? const Color(0xFFF43F5E) : TColors.slate200, width: 2),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _method = id),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(icon, size: 20, color: _method == id ? const Color(0xFFE11D48) : TColors.slate500),
                    const SizedBox(height: 4),
                    Text(label,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _method == id ? const Color(0xFFBE123C) : TColors.slate600)),
                  ]),
                ),
              ),
          ],
        ),
        if (_isCash) ...[
          rField('Cash received', _bigBox(_tendered)),
          Row(children: [
            _figure('Applied to bill', orderMoney(_applied)),
            const SizedBox(width: 8),
            _figure('Change to give', orderMoney(_change), green: _change > 0),
          ]),
          _TillPicker(shifts: _shifts, value: _shiftId, onChanged: (v) => setState(() => _shiftId = v)),
        ] else ...[
          if (_method == 'GiftCard')
            rField(
              'Gift card number',
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(
                    child: AppInput(
                      controller: _reference,
                      hintText: 'GC-XXXXXXXX',
                      onChanged: (_) => setState(() => _cardBalance = null),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: _lookUpCard, child: const Text('Check')),
                ]),
                if (_cardBalance != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Balance ${orderMoney(_cardBalance!)}', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                  ),
              ]),
            ),
          rField(
            'Amount',
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _bigBox(_amount),
              if (_applied > 0 && _applied < _due)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Part payment — ${orderMoney(_due - _applied)} will still be due.',
                      style: const TextStyle(fontSize: 12, color: Color(0xFFB45309))),
                ),
            ]),
          ),
        ],
        if (_method != 'GiftCard')
          rField('Tip (optional)', AppInput(controller: _tip, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}))),
        if (problem != null && _due > 0) Text(problem, style: const TextStyle(fontSize: 12, color: Color(0xFFBE123C))),
      ],
      actions: [
        rCancel(context, 'Cancel', busy: _saving),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
          onPressed: problem != null || _saving ? null : _submit,
          icon: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check, size: 16),
          label: Text('Record ${orderMoney(_applied)}'),
        ),
      ],
    );
  }
}

/// Refund. Pops with the refreshed order once recorded.
class RefundDialog extends StatefulWidget {
  const RefundDialog({super.key, required this.api, required this.farmId, required this.order});
  final ApiClient api;
  final String farmId;
  final Map order;

  @override
  State<RefundDialog> createState() => _RefundDialogState();
}

class _RefundDialogState extends State<RefundDialog> {
  List<Map> _shifts = [];
  late final double _paid = round2(tNum(widget.order['paidAmount']));
  late final _amount = TextEditingController(text: _paid != 0 ? orderMoney(_paid) : '');
  String _method = 'Cash';
  String _reason = '';
  int? _shiftId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    loadOpenShifts(widget.api, widget.farmId).then((s) {
      if (mounted) setState(() => _shifts = s);
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  double get _amt => round2(_num(_amount.text));

  String? get _problem {
    if (_paid <= 0) return 'Nothing has been paid on this order.';
    if (_amt <= 0) return 'Enter the amount to refund.';
    if (_amt > _paid) return 'You cannot refund more than the ${orderMoney(_paid)} paid.';
    if (_reason.trim().isEmpty) return 'Give a reason.';
    if (_method == 'Cash' && _shifts.length > 1 && _shiftId == null) return 'Choose the till the cash comes out of.';
    return null;
  }

  Future<void> _submit() async {
    if (_problem != null) return;
    setState(() => _saving = true);
    final o = widget.order;
    try {
      await widget.api.post('/api/Restaurant/orders/${o['orderId']}/refunds', query: {'farmId': widget.farmId}, body: {
        'amount': _amt,
        'paymentMethod': _method,
        'reason': _reason.trim(),
        'shiftId': _method == 'Cash' ? _shiftId : null,
      });
      final fresh = await loadOrder(widget.api, widget.farmId, o['orderId']);
      if (!mounted) return;
      trackerToast(context, 'Refunded ${orderMoney(_amt)}', description: tStr(fresh['status']) == 'Refunded' ? 'The order is now Refunded.' : null);
      Navigator.pop(context, fresh);
    } catch (e) {
      if (mounted) {
        trackerToast(context, 'Refund not recorded', description: e is ApiException ? e.message : '$e', error: true);
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    return rDialog(
      title: 'Refund — ${tStr(widget.order['orderNumber'])}',
      description: 'Paid so far: ${orderMoney(_paid)}. Refunding all of it marks the order Refunded.',
      children: [
        rField('Amount', AppInput(controller: _amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}))),
        rField(
          'Refund as',
          AppSelect<String>(
            value: _method,
            items: [for (final (v, l) in orderRefundMethods) AppSelectItem(value: v, label: l)],
            onChanged: (v) => setState(() => _method = v ?? 'Cash'),
          ),
        ),
        rField('Reason', ReasonSelect(options: orderRefundReasons, value: _reason, onChanged: (v) => setState(() => _reason = v))),
        if (_method == 'Cash') _TillPicker(shifts: _shifts, value: _shiftId, onChanged: (v) => setState(() => _shiftId = v)),
        if (problem != null && _paid > 0) Text(problem, style: const TextStyle(fontSize: 12, color: Color(0xFFBE123C))),
      ],
      actions: [
        rCancel(context, 'Cancel', busy: _saving),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE11D48)),
          onPressed: problem != null || _saving ? null : _submit,
          icon: const Icon(Icons.replay, size: 16),
          label: Text('Refund ${orderMoney(_amt)}'),
        ),
      ],
    );
  }
}
