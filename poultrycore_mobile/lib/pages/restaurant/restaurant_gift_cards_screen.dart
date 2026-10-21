// Restaurant → Growth → Gift Cards, as `app/restaurant-gift-cards/page.tsx`:
// Check Balance and Issue Card, four stat cards, search by card number, and a
// row per card (Reload / Redeem while Active, History). Issuing a card to a
// recipient with an email address also emails them the card, as the web does.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/sales/balances_widgets.dart' show LoadingLine;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/business_dates.dart' show fmtDateTime;
import '../shared/company_clock.dart';
import 'restaurant_widgets.dart';

/// STATUS_COLORS: bg, fg.
const giftCardStatusColors = <String, (Color, Color)>{
  'Active': (Color(0xFFDCFCE7), Color(0xFF15803D)),
  'Redeemed': (Color(0xFFF3E8FF), Color(0xFF7E22CE)),
  'Expired': (Color(0xFFFEE2E2), Color(0xFFB91C1C)),
  'Disabled': (Color(0xFFF3F4F6), Color(0xFF374151)),
};

/// The "Paid with" choices for selling or reloading a card (migration 323).
const giftCardPaymentMethods = <(String, String)>[
  ('Cash', 'Cash'),
  ('Card', 'Card'),
  ('MobileMoney', 'Mobile Money'),
  ('Complimentary', 'Complimentary (no payment)'),
];

Widget giftStatusBadge(String status) {
  final (bg, fg) = giftCardStatusColors[status] ?? giftCardStatusColors['Disabled']!;
  return rBadge(status, bg: bg, fg: fg);
}

String _usd(Object? n) => '\$${tNum(n).toStringAsFixed(2)}';

/// The gift card email, word for word with the web's HTML.
String giftCardEmailHtml({required String recipientName, required String purchaserName, required String message, required num amount, required String cardNumber}) => '''
<!DOCTYPE html><html><head><meta charset="utf-8"></head>
<body style="margin:0;padding:0;background:#f1f5f9;font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif">
<div style="max-width:500px;margin:0 auto;padding:24px">
  <div style="background:linear-gradient(135deg,#e11d48,#be123c);color:white;padding:30px;border-radius:16px 16px 0 0;text-align:center">
    <h1 style="margin:0;font-size:24px">You've Received a Gift Card!</h1>
  </div>
  <div style="background:white;padding:24px;border-radius:0 0 16px 16px;box-shadow:0 2px 8px rgba(0,0,0,.1)">
    <p>Dear ${recipientName.isEmpty ? 'Friend' : recipientName},</p>
    ${purchaserName.isNotEmpty ? '<p><strong>$purchaserName</strong> has sent you a gift card!</p>' : '<p>Someone special has sent you a gift card!</p>'}
    ${message.isNotEmpty ? '<div style="background:#fdf2f8;padding:16px;border-radius:12px;border-left:4px solid #e11d48;margin:16px 0;font-style:italic;color:#64748b">"$message"</div>' : ''}
    <div style="background:#fdf2f8;border:2px dashed #e11d48;border-radius:16px;padding:24px;margin:20px 0;text-align:center">
      <p style="color:#64748b;font-size:12px;margin:0 0 8px;text-transform:uppercase;letter-spacing:1px">Your Gift Card</p>
      <p style="font-size:32px;font-weight:800;color:#e11d48;margin:0">${amount.toStringAsFixed(2)}</p>
      <p style="font-family:monospace;font-size:18px;font-weight:700;color:#1e293b;margin:12px 0 0;letter-spacing:2px">$cardNumber</p>
    </div>
    <p style="text-align:center;color:#64748b;font-size:13px">Present this card number when making a purchase. Enjoy!</p>
  </div>
</div></body></html>''';

class RestaurantGiftCardsScreen extends StatefulWidget {
  const RestaurantGiftCardsScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<RestaurantGiftCardsScreen> createState() => _RestaurantGiftCardsScreenState();
}

class _RestaurantGiftCardsScreenState extends State<RestaurantGiftCardsScreen> {
  bool _loading = true;
  List<Map> _cards = [];
  Map? _stats;
  String _search = '';
  Duration _offset = Duration.zero;

  ApiClient get _api => widget.session.farmClient;
  Map<String, dynamic> get _q => {'farmId': widget.company.farmId};

  @override
  void initState() {
    super.initState();
    CompanyClock.load(widget.session, widget.company).then((c) {
      if (mounted) setState(() => _offset = c.offset);
    });
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([
        _api.get('/api/Restaurant/gift-cards', query: _q),
        _api.get('/api/Restaurant/gift-cards/stats', query: _q),
      ]);
      _cards = [for (final x in (r[0] is List ? r[0] as List : const [])) if (x is Map) x];
      _stats = r[1] is Map ? r[1] as Map : null;
    } catch (_) {
      if (mounted) trackerToast(context, 'Error', description: 'Failed to load gift cards', error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _issue() async {
    final issued = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => _IssueCardForm(api: _api, farmId: widget.company.farmId),
    ));
    if (issued == true) _load();
  }

  Future<void> _check() => showDialog<void>(context: context, builder: (_) => _CheckBalanceDialog(api: _api, farmId: widget.company.farmId));

  Future<void> _redeem(Map card) async {
    final done = await showDialog<bool>(context: context, builder: (_) => _AmountDialog(api: _api, farmId: widget.company.farmId, card: card, redeem: true));
    if (done == true) _load();
  }

  Future<void> _reload(Map card) async {
    final done = await showDialog<bool>(context: context, builder: (_) => _AmountDialog(api: _api, farmId: widget.company.farmId, card: card, redeem: false));
    if (done == true) _load();
  }

  Future<void> _history(Map card) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Transaction History'),
          content: SizedBox(
            width: 460,
            child: FutureBuilder<Object?>(
              future: _api.get('/api/Restaurant/gift-cards/${card['giftCardId']}/transactions', query: _q).catchError((Object _) {
                if (ctx.mounted) trackerToast(ctx, 'Error', description: 'Failed to load transactions', error: true);
                return const <Object>[];
              }),
              builder: (_, snap) {
                final txs = [for (final x in (snap.data is List ? snap.data as List : const [])) if (x is Map) x];
                return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Card: ${tStr(card['cardNumber'])}', style: const TextStyle(fontSize: 13, color: TColors.slate500)),
                  const SizedBox(height: 10),
                  if (snap.connectionState != ConnectionState.done)
                    const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(color: Color(0xFFF43F5E))))
                  else if (txs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Column(children: [
                        Icon(Icons.history, size: 40, color: Color(0xFFD1D5DB)),
                        SizedBox(height: 6),
                        Text('No transactions yet', style: TextStyle(fontSize: 13, color: TColors.slate500)),
                      ]),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 320),
                      child: ListView(shrinkWrap: true, children: [
                        for (final tx in txs)
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: TColors.slate200))),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                                    rBadge(tStr(tx['transactionType']), bg: Colors.white, border: TColors.slate200),
                                    if (tStr(tx['orderId']).isNotEmpty)
                                      Text('Order #${tStr(tx['orderId'])}', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                                  ]),
                                  if (tStr(tx['notes']).isNotEmpty)
                                    Text(tStr(tx['notes']), style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                                  Text(
                                    DateTime.tryParse(tStr(tx['createdAt'])) == null
                                        ? tStr(tx['createdAt'])
                                        : DateFormat('d/M/yyyy, HH:mm:ss').format(DateTime.parse(tStr(tx['createdAt'])).toLocal()),
                                    style: const TextStyle(fontSize: 12, color: TColors.slate500),
                                  ),
                                ]),
                              ),
                              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                Text('${tNum(tx['amount']) >= 0 ? '+' : ''}${_usd(tx['amount'])}',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: tNum(tx['amount']) >= 0 ? const Color(0xFF15803D) : const Color(0xFFDC2626))),
                                Text('Bal: ${_usd(tx['balanceAfter'])}', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                              ]),
                            ]),
                          ),
                      ]),
                    ),
                ]);
              },
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/restaurant-gift-cards');
    final filtered = [for (final c in _cards) if (tStr(c['cardNumber']).toLowerCase().contains(_search.toLowerCase())) c];
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Gift Cards')),
      body: _loading
          ? const Padding(padding: EdgeInsets.all(20), child: LoadingLine('Loading…'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
                RPageHeader(
                  icon: Icons.card_giftcard,
                  title: 'Gift Cards',
                  subtitle: 'Issue, manage, and redeem gift cards',
                  actions: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                      onPressed: _check,
                      icon: const Icon(Icons.search, size: 18),
                      label: const Text('Check Balance'),
                    ),
                    roseButton('Issue Card', _issue),
                  ],
                ),
                const SizedBox(height: 14),
                twoColumns([
                  RStatCard(label: 'Total Cards', value: '${tNum(_stats?['totalCards']).toInt()}', icon: Icons.credit_card, color: 'rose'),
                  RStatCard(label: 'Active Cards', value: '${tNum(_stats?['activeCards']).toInt()}', icon: Icons.card_giftcard, color: 'green'),
                  RStatCard(label: 'Total Issued', value: _usd(_stats?['totalIssued']), icon: Icons.attach_money, color: 'blue'),
                  RStatCard(label: 'Total Redeemed', value: _usd(_stats?['totalRedeemed']), icon: Icons.swap_horiz, color: 'purple'),
                ]),
                const SizedBox(height: 14),
                if (_cards.isNotEmpty) ...[
                  AppInput(hintText: 'Search by card number...', prefixIcon: const Icon(Icons.search, size: 18), onChanged: (v) => setState(() => _search = v)),
                  const SizedBox(height: 12),
                ],
                if (_cards.isEmpty)
                  TCard(
                    child: REmptyState(
                      icon: Icons.card_giftcard,
                      title: 'No gift cards issued yet',
                      description: 'Issue digital or physical gift cards for your customers',
                      actionLabel: 'Issue First Card',
                      onAction: _issue,
                    ),
                  )
                else if (filtered.isEmpty)
                  const TCard(child: REmptyState(icon: Icons.search, title: 'No cards match your search', description: 'Try a different card number'))
                else
                  TCard(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Column(children: [
                      for (final (i, c) in filtered.indexed) ...[
                        if (i > 0) const Divider(height: 1, color: TColors.slate200),
                        _cardRow(c),
                      ],
                    ]),
                  ),
              ]),
            ),
    );
  }

  Widget _cardRow(Map card) {
    final active = tStr(card['status']) == 'Active';
    final meta = [
      '${_usd(card['initialBalance'])} → ${_usd(card['currentBalance'])}',
      if (tStr(card['purchaserName']).isNotEmpty) 'From: ${tStr(card['purchaserName'])}',
      if (tStr(card['recipientName']).isNotEmpty) 'To: ${tStr(card['recipientName'])}',
      if (tStr(card['expiryDate']).isNotEmpty) 'Exp: ${fmtDateTime(card['expiryDate'], null, _offset)}',
    ];
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _history(card),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: const Color(0xFFFFF1F2), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.card_giftcard, size: 20, color: Color(0xFFF43F5E)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(tStr(card['cardNumber']), style: const TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.w600)),
                rBadge(tStr(card['cardType']), bg: Colors.white, border: TColors.slate200),
                giftStatusBadge(tStr(card['status'])),
              ]),
              const SizedBox(height: 2),
              Wrap(spacing: 10, runSpacing: 2, children: [
                for (final m in meta) Text(m, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
              ]),
            ]),
          ),
          if (active) ...[
            IconButton(tooltip: 'Reload', icon: const Icon(Icons.refresh, size: 18), onPressed: () => _reload(card)),
            IconButton(tooltip: 'Redeem', icon: const Icon(Icons.swap_horiz, size: 18), onPressed: () => _redeem(card)),
          ],
          IconButton(tooltip: 'History', icon: const Icon(Icons.history, size: 18), onPressed: () => _history(card)),
        ]),
      ),
    );
  }
}

/// Issue Gift Card.
class _IssueCardForm extends StatefulWidget {
  const _IssueCardForm({required this.api, required this.farmId});
  final ApiClient api;
  final String farmId;
  @override
  State<_IssueCardForm> createState() => _IssueCardFormState();
}

class _IssueCardFormState extends State<_IssueCardForm> {
  String _type = 'Digital';
  final _amount = TextEditingController();
  final _purchaser = TextEditingController();
  final _purchaserPhone = TextEditingController();
  final _recipient = TextEditingController();
  final _recipientEmail = TextEditingController();
  final _message = TextEditingController();
  String _expiry = '';
  String _method = 'Cash';
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_amount, _purchaser, _purchaserPhone, _recipient, _recipientEmail, _message]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final amount = num.tryParse(_amount.text) ?? 0;
    if (amount <= 0) return trackerToast(context, 'Validation', description: 'Amount is required', error: true);
    setState(() => _saving = true);
    try {
      final res = await widget.api.post('/api/Restaurant/gift-cards', query: {'farmId': widget.farmId}, body: {
        'cardType': _type,
        'amount': amount,
        'purchaserName': _purchaser.text,
        'purchaserPhone': _purchaserPhone.text,
        'recipientName': _recipient.text,
        'recipientEmail': _recipientEmail.text,
        'message': _message.text,
        'expiryDate': _expiry,
        'paymentMethod': _method,
      });
      final number = res is Map ? tStr(res['cardNumber']) : '';
      if (!mounted) return;
      trackerToast(context, 'Card Issued', description: 'Card $number created successfully');
      // Email the card to the recipient. The card is already issued, so a failed
      // email never fails the whole flow.
      final to = _recipientEmail.text.trim();
      if (to.isNotEmpty) {
        try {
          final r = await widget.api.post('/api/Email/send-html', body: {
            'to': _recipientEmail.text,
            'subject': "You've Received a Gift Card — $number",
            'body': giftCardEmailHtml(
                recipientName: _recipient.text, purchaserName: _purchaser.text, message: _message.text, amount: amount, cardNumber: number),
          });
          // send-html answers 200 even when the send fails; the outcome is in the body.
          final sent = r is! Map || r['success'] != false;
          if (mounted) {
            sent
                ? trackerToast(context, 'Email sent', description: 'Gift card emailed to ${_recipientEmail.text}')
                : trackerToast(context, 'Card issued, but the email was not sent',
                    description: tStr(r['message']).isNotEmpty ? tStr(r['message']) : 'Could not email ${_recipientEmail.text}. The card number is $number.',
                    error: true);
          }
        } on ApiException catch (e) {
          if (mounted) {
            trackerToast(context, 'Card issued, but the email was not sent',
                description: e.message.isNotEmpty ? e.message : 'Card number $number.', error: true);
          }
        }
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        trackerToast(context, 'Error', description: e.message.isNotEmpty ? e.message : 'Failed to issue card', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Issue Gift Card')),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 28), children: [
          const Text('Create a new digital or physical gift card', style: TextStyle(fontSize: 13, color: TColors.slate500)),
          const SizedBox(height: 16),
          rLabel('Card Type'),
          AppSelect<String>(
            value: _type,
            items: const [AppSelectItem(value: 'Digital', label: 'Digital'), AppSelectItem(value: 'Physical', label: 'Physical')],
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          const SizedBox(height: 12),
          rLabel('Amount', required: true),
          AppInput(
            controller: _amount,
            hintText: '50.00',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
          ),
          const SizedBox(height: 12),
          rLabel('Purchaser Name'),
          AppInput(controller: _purchaser),
          const SizedBox(height: 12),
          rLabel('Purchaser Phone'),
          AppInput(controller: _purchaserPhone, keyboardType: TextInputType.phone),
          const SizedBox(height: 12),
          rLabel('Recipient Name'),
          AppInput(controller: _recipient),
          const SizedBox(height: 12),
          rLabel('Recipient Email'),
          AppInput(controller: _recipientEmail, keyboardType: TextInputType.emailAddress),
          const SizedBox(height: 12),
          rLabel('Personal Message'),
          AppTextarea(controller: _message, hintText: 'Happy Birthday! Enjoy your meal...', rows: 2),
          const SizedBox(height: 12),
          rLabel('Expiry Date'),
          AppDateField(
            value: DateTime.tryParse(_expiry),
            hintText: 'dd/mm/yyyy',
            onChanged: (d) => setState(() => _expiry = d == null
                ? ''
                : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}'),
          ),
          const SizedBox(height: 12),
          // Selling a card is money in; a complimentary card moves no money.
          rLabel('Paid with'),
          AppSelect<String>(
            value: _method,
            items: [for (final (v, l) in giftCardPaymentMethods) AppSelectItem(value: v, label: l)],
            onChanged: (v) => setState(() => _method = v ?? _method),
          ),
          const SizedBox(height: 20),
          rDialogActions(context, 'Issue Card', _saving ? null : _save),
        ]),
      );
}

/// Check Gift Card Balance.
class _CheckBalanceDialog extends StatefulWidget {
  const _CheckBalanceDialog({required this.api, required this.farmId});
  final ApiClient api;
  final String farmId;
  @override
  State<_CheckBalanceDialog> createState() => _CheckBalanceDialogState();
}

class _CheckBalanceDialogState extends State<_CheckBalanceDialog> {
  final _number = TextEditingController();
  Map? _result;
  bool _checking = false;

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final n = _number.text.trim();
    if (n.isEmpty) return;
    setState(() {
      _checking = true;
      _result = null;
    });
    Map? res;
    try {
      final r = await widget.api.get('/api/Restaurant/gift-cards/balance/${Uri.encodeComponent(n)}', query: {'farmId': widget.farmId});
      res = r is Map && r.isNotEmpty ? r : null;
    } catch (_) {
      // checkGiftCardBalance answers null for a missing card or any failure.
      res = null;
    }
    if (!mounted) return;
    setState(() {
      _checking = false;
      _result = res;
    });
    if (res == null) trackerToast(context, 'Not Found', description: 'No card found with that number', error: true);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: const Text('Check Gift Card Balance'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            rLabel('Card Number'),
            AppInput(controller: _number, hintText: 'GC-XXXXXXXX', onChanged: (_) => setState(() {})),
            const SizedBox(height: 12),
            roseButton('Check Balance', _checking || _number.text.trim().isEmpty ? null : _check, icon: Icons.search),
            if (_result != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4), border: Border.all(color: const Color(0xFFBBF7D0)), borderRadius: BorderRadius.circular(10)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                        child: Text(tStr(_result!['cardNumber']),
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.w600))),
                    giftStatusBadge(tStr(_result!['status'])),
                  ]),
                  const SizedBox(height: 4),
                  Text(_usd(_result!['currentBalance']), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF15803D))),
                  Text('Initial: ${_usd(_result!['initialBalance'])}', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                ]),
              ),
            ],
          ]),
        ),
      );
}

/// Redeem Gift Card / Reload Gift Card.
class _AmountDialog extends StatefulWidget {
  const _AmountDialog({required this.api, required this.farmId, required this.card, required this.redeem});
  final ApiClient api;
  final String farmId;
  final Map card;
  final bool redeem;
  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  final _amount = TextEditingController();
  final _order = TextEditingController();
  String _method = 'Cash';
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _order.dispose();
    super.dispose();
  }

  num get _value => num.tryParse(_amount.text) ?? 0;

  Future<void> _go() async {
    if (_value <= 0) return;
    setState(() => _saving = true);
    final number = tStr(widget.card['cardNumber']);
    try {
      if (widget.redeem) {
        final r = await widget.api.post('/api/Restaurant/gift-cards/redeem', query: {'farmId': widget.farmId}, body: {
          'cardNumber': number,
          'amount': _value,
          'orderId': ?int.tryParse(_order.text),
        });
        final ok = r is Map && r['success'] == true;
        if (!mounted) return;
        if (ok) {
          trackerToast(context, 'Redeemed', description: '${tStr(r['message'])} - New balance: ${tNum(r['newBalance']).toStringAsFixed(2)}');
          Navigator.pop(context, true);
          return;
        }
        trackerToast(context, 'Failed', description: r is Map ? tStr(r['message']) : '', error: true);
      } else {
        await widget.api.post('/api/Restaurant/gift-cards/reload', query: {'farmId': widget.farmId}, body: {
          'cardNumber': number,
          'amount': _value,
          'paymentMethod': _method,
          'cashAccountId': null,
        });
        if (!mounted) return;
        trackerToast(context, 'Reloaded', description: '${_value.toStringAsFixed(2)} added to $number');
        Navigator.pop(context, true);
        return;
      }
    } on ApiException catch (e) {
      if (mounted) {
        trackerToast(context, 'Error',
            description: e.message.isNotEmpty ? e.message : (widget.redeem ? 'Redemption failed' : 'Reload failed'), error: true);
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    return AlertDialog(
      scrollable: true,
      title: Text(widget.redeem ? 'Redeem Gift Card' : 'Reload Gift Card'),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.redeem ? 'Deduct balance from this gift card' : 'Add funds to this gift card',
              style: const TextStyle(fontSize: 13, color: TColors.slate500)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFF9FAFB), border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Expanded(child: Text(tStr(card['cardNumber']), style: const TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.w600))),
              Text(_usd(card['currentBalance']), style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF15803D))),
            ]),
          ),
          const SizedBox(height: 12),
          rLabel('Amount', required: true),
          AppInput(
            controller: _amount,
            hintText: widget.redeem ? '0.00' : '25.00',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          if (widget.redeem) ...[
            Text.rich(TextSpan(children: [
              const TextSpan(text: 'Order ID '),
              const TextSpan(text: '(optional)', style: TextStyle(fontSize: 12, color: TColors.slate500, fontWeight: FontWeight.w400)),
            ]), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            AppInput(controller: _order, hintText: 'e.g. 1234', keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
          ] else ...[
            rLabel('Paid with'),
            AppSelect<String>(
              value: _method,
              items: [for (final (v, l) in giftCardPaymentMethods) AppSelectItem(value: v, label: l)],
              onChanged: (v) => setState(() => _method = v ?? _method),
            ),
          ],
          const SizedBox(height: 16),
          rDialogActions(context, widget.redeem ? 'Redeem' : 'Reload', _saving || _value <= 0 ? null : _go),
        ]),
      ),
    );
  }
}
