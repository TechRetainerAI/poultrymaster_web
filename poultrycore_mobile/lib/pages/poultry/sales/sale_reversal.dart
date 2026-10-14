// Migration 351 on the phone: a posted sale is viewed, reversed or corrected —
// never edited or deleted — and money held for a customer is applied or
// refunded. Ports of components/sales/sale-details-dialog.tsx,
// reverse-sale-dialog.tsx, apply-credit-dialog.tsx, refund-credit-dialog.tsx,
// customer-credit-panel.tsx and sale-lines-dialog.tsx.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../reports/report_format.dart';
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull, trackerDate;
import '../trackers/tracker_widgets.dart';
import 'sales_logic.dart';

String _newKey() {
  final r = Random();
  String h(int n) => List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
  return '${h(8)}-${h(4)}-4${h(3)}-${h(4)}-${h(12)}';
}

String _shortDate(Object? d) => tStr(d).isEmpty ? '—' : trackerDate(d);

Widget _sectionLabel(String text) => Padding(
  padding: const EdgeInsets.only(bottom: 6),
  child: Text(
    text.toUpperCase(),
    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .5, color: TColors.slate500),
  ),
);

Widget _row(String label, Widget value) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 3),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
      const SizedBox(width: 12),
      Expanded(
        child: Align(
          alignment: Alignment.centerRight,
          child: DefaultTextStyle.merge(
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: TColors.slate900),
            child: value,
          ),
        ),
      ),
    ],
  ),
);

Widget _box(List<Widget> children, {Color border = TColors.slate200, Color? color}) => Container(
  padding: const EdgeInsets.all(12),
  decoration: BoxDecoration(
    color: color,
    border: Border.all(color: border),
    borderRadius: BorderRadius.circular(6),
  ),
  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
);

Widget _postedBadge(bool reversed) => reversed
    ? const TBadge('Reversed', bg: TColors.red50, fg: TColors.red700, border: TColors.red300)
    : const TBadge('Posted', bg: TColors.emerald50, fg: TColors.emerald700, border: TColors.emerald300);

// ------------------------------------------------------------------ view a sale

/// What the user chose on the View sale page; the Sales page acts on it.
sealed class SaleDetailsAction {
  const SaleDetailsAction();
}

class SaleInvoiceAction extends SaleDetailsAction {
  const SaleInvoiceAction();
}

class SaleReverseAction extends SaleDetailsAction {
  const SaleReverseAction(this.mode);
  final String mode; // "reverse" | "correct"
}

class SaleRepostAction extends SaleDetailsAction {
  const SaleRepostAction();
}

class SaleShowAction extends SaleDetailsAction {
  const SaleShowAction(this.saleId);
  final int saleId;
}

/// The web's updateSale body for a note change: the sale as stored, with only
/// the note changed (the server refuses anything else).
Map<String, dynamic> noteUpdateBody(Map row, String farmId, String userId, String note) {
  bool has(Object? v) => v != null && v != '' && v != 0 && v != false;
  return {
    'farmId': farmId,
    'userId': userId,
    if (row['saleId'] != null) 'saleId': row['saleId'],
    if (has(row['saleDate'])) 'saleDate': row['saleDate'],
    if (has(row['product'])) 'product': row['product'],
    if (row['quantity'] != null) 'quantity': row['quantity'],
    if (row['unitPrice'] != null) 'unitPrice': row['unitPrice'],
    if (row['totalAmount'] != null) 'totalAmount': row['totalAmount'],
    if (has(row['paymentMethod'])) 'paymentMethod': row['paymentMethod'],
    if (has(row['customerName'])) 'customerName': row['customerName'],
    if (row['flockId'] != null) 'flockId': row['flockId'],
    if (note.isNotEmpty) 'saleDescription': note,
    if (row['paid'] != null) 'paid': row['paid'],
    if (row.containsKey('size')) 'size': row['size'],
    if (row.containsKey('poultryCashAccountId')) 'poultryCashAccountId': row['poultryCashAccountId'],
    'eggProductId': 0,
    if (has(row['createdDate'])) 'createdDate': row['createdDate'],
  };
}

/// View a sale (sale-details-dialog.tsx): read-only, with the actions that ARE
/// allowed — change the note, Correct Sale, Reverse Sale, Edit & repost, Invoice.
/// Pops a [SaleDetailsAction], or null. [onNoteSaved] runs after a note save.
class SaleDetailsScreen extends StatefulWidget {
  const SaleDetailsScreen({
    super.key,
    required this.session,
    required this.company,
    required this.sale,
    required this.flockLabel,
    required this.lineLabel,
    required this.canReverse,
    required this.canRepost,
    required this.onNoteSaved,
  });
  final Session session;
  final Company company;
  final Map sale;
  final String flockLabel;
  final String Function(Map line) lineLabel;
  final bool canReverse;
  final bool canRepost;
  final ValueChanged<String> onNoteSaved;

  @override
  State<SaleDetailsScreen> createState() => _SaleDetailsScreenState();
}

class _SaleDetailsScreenState extends State<SaleDetailsScreen> {
  late final _note = TextEditingController(text: tStr(widget.sale['saleDescription']));
  late String _savedNote = tStr(widget.sale['saleDescription']);
  bool _saving = false;
  Map? _reversal;
  FarmMoney _money = const FarmMoney();

  Map get s => widget.sale;
  bool get _reversed => isReversedSale(s);

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _money = m);
    });
    if (_reversed) _loadReversal();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _loadReversal() async {
    try {
      final r = await widget.session.farmClient.get('/api/Sale/${s['saleId']}/reversal', query: {'farmId': widget.company.farmId});
      if (mounted && r is Map) setState(() => _reversal = r);
    } on ApiException {
      // As the web: the row's own reversal fields stand in.
    }
  }

  Future<void> _saveNote() async {
    setState(() => _saving = true);
    final note = _note.text;
    try {
      await widget.session.farmClient.put(
        '/api/Sale/${s['saleId']}',
        body: noteUpdateBody(s, widget.company.farmId, widget.session.tokens.userId ?? '', note),
      );
      if (!mounted) return;
      trackerToast(context, 'Note saved');
      setState(() => _savedNote = note);
      widget.onNoteSaved(note);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Note not saved', description: e.message.isNotEmpty ? e.message : 'The sale was not changed.', error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final label = tStr(s['saleGroupNo']).isNotEmpty ? tStr(s['saleGroupNo']) : '#${s['saleId']}';
    final lines = saleLinesOf(s);
    final total = tNum(s['totalAmount']);
    final paid = tNum(s['amountPaid'] ?? (s['paid'] == false ? 0 : total));
    final rv = _reversal;
    final correctedBy = tIntOrNull(s['correctedBySaleId']) ?? tIntOrNull(rv?['correctionSaleId']);
    final corrects = tIntOrNull(s['correctsSaleId']);
    final restores = [
      for (final l in (rv?['lines'] is List ? rv!['lines'] as List : const []))
        if (l is Map) restoreLabel(l),
    ].whereType<String>();
    Widget link(int id) => InkWell(
      onTap: () => Navigator.pop(context, SaleShowAction(id)),
      child: Text(
        '#$id',
        style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF1D4ED8), decoration: TextDecoration.underline),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text('Sale $label')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        children: [
          Row(
            children: [
              Text('Sale $label', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              _postedBadge(_reversed),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _reversed
                ? 'This sale was reversed. It stays here for the record; it no longer counts as revenue, stock sold or money owed. Use Edit & repost to enter it again with the mistake fixed.'
                : 'A posted sale cannot be edited. If something is wrong, use Correct Sale (reverse it and enter it again) or Reverse Sale.',
            style: const TextStyle(fontSize: 13, color: TColors.slate500),
          ),
          const SizedBox(height: 14),
          if (corrects != null && corrects != 0) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(6)),
              child: Row(
                children: [
                  const Text('Correction of sale ', style: TextStyle(fontSize: 13, color: Color(0xFF1E40AF))),
                  link(corrects),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          _box([
            _row('Date', Text(_shortDate(s['saleDate']))),
            _row('Customer', Text(tStr(s['customerName']).isEmpty ? 'Walk-in' : tStr(s['customerName']))),
            _row('Flock', Text(widget.flockLabel)),
            _row('Payment method', Text(tStr(s['paymentMethod']).isEmpty ? '—' : tStr(s['paymentMethod']))),
            _row('Total', Text(_money(total))),
            if (!_reversed) _row('Paid', Text(_money(paid))),
            if (!_reversed) _row('Balance', Text(_money(max<num>(0, total - paid)))),
          ]),
          const SizedBox(height: 14),
          _sectionLabel(lines.length > 1 ? 'Lines' : 'Item'),
          for (final l in lines)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(color: TColors.slate200),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Expanded(child: Text(widget.lineLabel(l), style: const TextStyle(fontSize: 13))),
                  Text(_money(tNum(l['totalAmount'])), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          if (_reversed) ...[
            const SizedBox(height: 8),
            _sectionLabel('Reversal'),
            _box(border: TColors.red200, color: const Color(0x66FEF2F2), [
              _row(
                'Reversed',
                Text(
                  rv != null
                      ? '${rv['reversalNumber']} · ${_shortDate(rv['businessDate'])}'
                      : (tStr(s['reversedAt']).isNotEmpty ? _shortDate(s['reversedAt']) : '—'),
                ),
              ),
              _row(
                'By',
                Text(tStr(rv?['reversedBy']).isNotEmpty ? tStr(rv?['reversedBy']) : (tStr(s['reversedBy']).isNotEmpty ? tStr(s['reversedBy']) : '—')),
              ),
              _row(
                'Reason',
                Text(
                  rv != null
                      ? [tStr(rv['reasonCode']), tStr(rv['reason'])].where((x) => x.isNotEmpty).join(': ')
                      : (tStr(s['reversalReason']).isNotEmpty ? tStr(s['reversalReason']) : '—'),
                ),
              ),
              if (rv != null) _row('Payment handling', Text(reversalHandlingLabel[rv['paymentHandling']] ?? tStr(rv['paymentHandling']))),
              if (rv != null && tNum(rv['creditCreated']) > 0) _row('Customer credit created', Text(_money(tNum(rv['creditCreated'])))),
              if (rv != null && tNum(rv['cashReversed']) > 0) _row('Paid back out of cash', Text(_money(tNum(rv['cashReversed'])))),
              for (final p in (rv?['payments'] is List ? rv!['payments'] as List : const []))
                if (p is Map)
                  _row(
                    tStr(p['paymentNumbers']).isEmpty ? 'Payment' : tStr(p['paymentNumbers']),
                    Text('${_money(tNum(p['amount']))} — ${p['action'] == 'ReversePayment' ? 'reversed' : 'kept as credit'}'),
                  ),
              for (final t in restores) _row('Stock put back', Text(t)),
              if (correctedBy != null && correctedBy != 0) _row('Corrected by', link(correctedBy)),
            ]),
          ],
          const SizedBox(height: 14),
          _sectionLabel('Note'),
          if (_reversed)
            Text(tStr(s['saleDescription']).isEmpty ? '—' : tStr(s['saleDescription']), style: const TextStyle(fontSize: 13, color: TColors.slate700))
          else ...[
            AppInput(
              controller: _note,
              minLines: 2,
              maxLines: 4,
              hintText: "Internal note (does not change the sale's money or stock)",
              onChanged: (_) => setState(() {}),
            ),
            if (_note.text != _savedNote) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _saveNote,
                  icon: _saving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const SizedBox.shrink(),
                  label: const Text('Save note'),
                ),
              ),
            ],
          ],
          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            onPressed: () => Navigator.pop(context, const SaleInvoiceAction()),
            icon: const Icon(Icons.description_outlined, size: 18),
            label: const Text('Invoice'),
          ),
          if (_reversed && widget.canRepost && rv?['correctionSaleId'] == null) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: TColors.blue600, minimumSize: const Size.fromHeight(44)),
              onPressed: () => Navigator.pop(context, const SaleRepostAction()),
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('Edit & repost'),
            ),
          ],
          if (!_reversed && widget.canReverse) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: TColors.red700,
                side: const BorderSide(color: TColors.red200),
                minimumSize: const Size.fromHeight(44),
              ),
              onPressed: () => Navigator.pop(context, const SaleReverseAction('reverse')),
              icon: const Icon(Icons.undo, size: 18),
              label: const Text('Reverse sale'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: TColors.blue600, minimumSize: const Size.fromHeight(44)),
              onPressed: () => Navigator.pop(context, const SaleReverseAction('correct')),
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('Correct sale'),
            ),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ reverse / correct

/// What a confirmed reversal returns to the Sales page.
class SaleReversed {
  const SaleReversed({required this.reversal, required this.mode});
  final Map? reversal;
  final String mode;
  num get creditCreated => tNum(reversal?['creditCreated']);
  num get cashReversed => tNum(reversal?['cashReversed']);
}

/// Reverse Sale / Correct Sale (reverse-sale-dialog.tsx): the SERVER's preview
/// of what reversing does, the one question that is the user's — keep each
/// payment as customer credit, or reverse it — and a reason. Pops [SaleReversed].
class ReverseSaleScreen extends StatefulWidget {
  const ReverseSaleScreen({
    super.key,
    required this.session,
    required this.company,
    required this.saleId,
    required this.saleLabel,
    this.mode = 'reverse',
  });
  final Session session;
  final Company company;
  final int saleId;
  final String saleLabel;
  final String mode;

  @override
  State<ReverseSaleScreen> createState() => _ReverseSaleScreenState();
}

class _ReverseSaleScreenState extends State<ReverseSaleScreen> {
  Map? _preview;
  bool _loading = false;
  String? _loadError;
  Map<String, String> _handling = {};
  String? _reasonCode;
  final _reason = TextEditingController();
  bool _saving = false;
  String? _error;
  bool _stale = false;

  /// One key per opened dialog: a double tap, or a retry after a dropped
  /// response, returns the reversal already made instead of making another.
  String _idem = _newKey();
  FarmMoney _money = const FarmMoney();

  bool get _correct => widget.mode == 'correct';
  List<Map> get _payments => [
    for (final p in (_preview?['payments'] is List ? _preview!['payments'] as List : const []))
      if (p is Map) p,
  ];
  List<Map> get _blockers => [
    for (final b in (_preview?['blockers'] is List ? _preview!['blockers'] as List : const []))
      if (b is Map) b,
  ];

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _money = m);
    });
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load({bool keepChoices = false}) async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final res = await widget.session.farmClient.get('/api/Sale/${widget.saleId}/reversal-preview', query: {'farmId': widget.company.farmId});
      if (!mounted) return;
      setState(() {
        _preview = res is Map ? res : null;
        final d = defaultHandling(_payments);
        _handling = keepChoices ? {...d, ..._handling} : d;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message.isNotEmpty ? e.message : 'Could not work out what reversing this sale would do.');
    }
    if (mounted) setState(() => _loading = false);
  }

  bool get _noteRequired => _reasonCode == 'Other';
  bool get _canConfirm =>
      _preview != null && _blockers.isEmpty && _reasonCode != null && (!_noteRequired || _reason.text.trim().isNotEmpty) && !_saving && !_loading;

  Future<void> _confirm() async {
    final p = _preview;
    if (p == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final sent = {for (final x in _payments) tStr(x['key']): effectiveAction(x, _handling)};
    try {
      final res = await widget.session.farmClient.post(
        '/api/Sale/${widget.saleId}/reverse?farmId=${Uri.encodeQueryComponent(widget.company.farmId)}',
        body: {
          'farmId': widget.company.farmId,
          'userId': widget.session.tokens.userId,
          'reasonCode': _reasonCode,
          'reason': _reason.text.trim(),
          'paymentHandling': sent,
          'expectedFingerprint': p['fingerprint'],
          'idempotencyKey': _idem,
        },
      );
      if (!mounted) return;
      Navigator.pop(context, SaleReversed(reversal: res is Map && res['reversal'] is Map ? res['reversal'] as Map : null, mode: widget.mode));
    } on ApiException catch (e) {
      if (!mounted) return;
      final body = e.body;
      if (body is Map && body['stale'] == true) {
        // Something changed (a payment arrived, say). Show the new impact and
        // let the user confirm again — never act on the old one.
        setState(() {
          _saving = false;
          _stale = true;
          _idem = _newKey();
        });
        await _load(keepChoices: true);
        return;
      }
      setState(() {
        _saving = false;
        _error = e.message.isNotEmpty ? e.message : 'The sale was not reversed.';
      });
    }
  }

  Widget _figure(String label, String value, {String? tone}) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: TColors.slate200),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: TColors.slate500)),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: tone == 'warn'
                ? TColors.amber700
                : tone == 'good'
                ? TColors.emerald700
                : TColors.slate900,
          ),
        ),
      ],
    ),
  );

  Widget _grid(List<Widget> cells) => LayoutBuilder(
    builder: (context, c) {
      final w = (c.maxWidth - 8) / 2;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [for (final x in cells) SizedBox(width: w, child: x)],
      );
    },
  );

  Widget _will(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.check_circle_outline, size: 16, color: TColors.emerald600),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 13, color: TColors.slate700)),
        ),
      ],
    ),
  );

  Widget _choice(Map p, String value, String action, String title, String body, Color on, Color onBg) => InkWell(
    onTap: () => setState(() => _handling = {..._handling, tStr(p['key']): value}),
    child: Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: action == value ? onBg : null,
        border: Border.all(color: action == value ? on : TColors.slate200),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Radio<String>(value: value, visualDensity: VisualDensity.compact),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(body, style: const TextStyle(fontSize: 12, color: TColors.slate600)),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _payment(Map p) {
    final action = effectiveAction(p, _handling);
    final allocated = tNum(p['allocated']);
    final account = tStr(p['cashAccountName']);
    final meta = [tStr(p['paymentMethod']), account].where((x) => x.isNotEmpty).join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: TColors.slate200),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: tStr(p['paymentNumbers']).isEmpty ? 'Money received at the sale' : tStr(p['paymentNumbers'])),
                      TextSpan(
                        text: '  ${paymentSourceLabel(p)}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: TColors.slate500),
                      ),
                    ],
                  ),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: TColors.slate900),
                ),
              ),
              Text(_money(allocated), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${meta.isEmpty ? 'No cash account' : meta}'
            '${tNum(p['paymentTotal']) > allocated + 0.005 ? ' · ${_money(tNum(p['paymentTotal']))} payment, ${_money(allocated)} of it on this sale' : ''}',
            style: const TextStyle(fontSize: 12, color: TColors.slate500),
          ),
          if (allowsBoth(p))
            RadioGroup<String>(
              groupValue: action,
              onChanged: (v) => setState(() => _handling = {..._handling, tStr(p['key']): v ?? action}),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _choice(
                    p,
                    'KeepAsCredit',
                    action,
                    'Keep it as customer credit',
                    'The money stays received. ${_money(allocated)} becomes credit the customer can use on another sale. The cash account does not change.',
                    const Color(0xFF60A5FA),
                    const Color(0x99EFF6FF),
                  ),
                  _choice(
                    p,
                    'ReversePayment',
                    action,
                    'Reverse the payment',
                    '${tStr(p['paymentNumbers']).isNotEmpty ? 'Payment ${p['paymentNumbers']}' : 'The money received'} is reversed. '
                        '${account.isNotEmpty ? account : 'Its cash account'} decreases by ${_money(allocated)}, shown in Cash Flow as a payment reversal (not an expense).',
                    TColors.red300,
                    const Color(0x99FEF2F2),
                  ),
                ],
              ),
            )
          else if (action == 'ReversePayment')
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: TColors.red50, borderRadius: BorderRadius.circular(6)),
              child: Text(
                'This sale has no customer to hold the money as credit, so the ${_money(allocated)} is reversed: '
                '${account.isNotEmpty ? account : 'its cash account'} decreases by that amount.',
                style: const TextStyle(fontSize: 12, color: TColors.red800),
              ),
            )
          else
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: TColors.slate50, borderRadius: BorderRadius.circular(6)),
              child: Text(
                '${tStr(p['reverseUnavailableReason']).isNotEmpty ? tStr(p['reverseUnavailableReason']) : 'This payment stays Posted.'} '
                'Cash does not change; ${_money(allocated)} becomes customer credit. To give the money back, refund it from Customer Balances afterwards.',
                style: const TextStyle(fontSize: 12, color: TColors.slate700),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _preview;
    final title = _correct ? 'Correct sale ${widget.saleLabel}' : 'Reverse sale ${widget.saleLabel}?';
    final restores = [
      for (final l in (p?['lines'] is List ? p!['lines'] as List : const []))
        if (l is Map) restoreLabel(l),
    ].whereType<String>().toList();
    final outcome = p == null ? null : reversalOutcome(_payments, _handling);
    final paid = tNum(p?['paid']), outstanding = tNum(p?['outstanding']);

    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _correct ? TColors.blue600 : TColors.red600,
                      minimumSize: const Size.fromHeight(44),
                    ),
                    onPressed: _canConfirm ? _confirm : null,
                    child: _saving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(_correct ? 'Reverse and correct' : 'Reverse sale'),
                  ),
                ),
              ],
            ),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
          children: [
            Row(
              children: [
                Icon(_correct ? Icons.restart_alt : Icons.undo, size: 20, color: _correct ? TColors.blue600 : TColors.red600),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _correct
                  ? 'A posted sale is not edited. It is reversed, and a new sale is opened filled in from it for you to fix and save.'
                  : 'The sale stays in the history, marked Reversed. Its revenue, what the customer owes and its stock are undone with opposite entries.',
              style: const TextStyle(fontSize: 13, color: TColors.slate500),
            ),
            const SizedBox(height: 14),
            if (_loading && p == null)
              const Row(
                children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('Working out what this would do…', style: TextStyle(fontSize: 13, color: TColors.slate500)),
                ],
              )
            else if (_loadError != null)
              TrackerBanner.error(_loadError!)
            else if (p != null) ...[
              if (_stale) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: TColors.amber50,
                    border: Border.all(color: TColors.amber300),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 16, color: TColors.amber900),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This sale changed after the reversal preview was generated. Please review the updated impact before continuing.',
                          style: TextStyle(fontSize: 13, color: TColors.amber900),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (_blockers.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: TColors.red50,
                    border: Border.all(color: TColors.red200),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'This sale cannot be reversed here',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: TColors.red800),
                      ),
                      for (final b in _blockers) Text(tStr(b['message']), style: const TextStyle(fontSize: 13, color: TColors.red800)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              _sectionLabel('The sale'),
              _grid([
                _figure('Customer', tStr(p['customerName']).isEmpty ? 'Walk-in' : tStr(p['customerName'])),
                _figure('Sale total', _money(tNum(p['total']))),
                _figure('Paid', _money(paid), tone: paid > 0 ? 'good' : null),
                _figure('Outstanding', _money(outstanding), tone: outstanding > 0 ? 'warn' : null),
              ]),
              const SizedBox(height: 14),
              _sectionLabel('This reversal will'),
              _will("Reverse the sale's revenue of ${_money(tNum(p['total']))}"),
              if (restores.isNotEmpty) _will('Put back ${restores.join(', ')} — exactly what was sold'),
              if (outstanding > 0) _will('Remove the ${_money(outstanding)} the customer still owes on it'),
              if (_payments.isNotEmpty) _will('Release the payments applied to it (below)'),
              _will('Keep the sale, its payments and its stock movements in the history'),
              const SizedBox(height: 14),
              if (_payments.isNotEmpty) ...[
                _sectionLabel('Payment handling'),
                const Text(
                  'Reversing a sale does not by itself mean the money left the business. Choose what happened to it.',
                  style: TextStyle(fontSize: 13, color: TColors.slate600),
                ),
                const SizedBox(height: 8),
                for (final x in _payments) _payment(x),
                if (outcome != null)
                  _grid([
                    _figure('Becomes customer credit', _money(outcome.creditCreated)),
                    _figure('Money out of cash', _money(outcome.cashOut), tone: outcome.cashOut > 0 ? 'warn' : null),
                  ]),
              ] else
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: TColors.slate50, borderRadius: BorderRadius.circular(6)),
                  child: const Text('Nothing was paid on this sale, so no money moves.', style: TextStyle(fontSize: 13, color: TColors.slate600)),
                ),
              const SizedBox(height: 14),
              _sectionLabel('Reason'),
              AppSelect<String>(
                value: _reasonCode,
                hintText: 'Choose a reason',
                items: [for (final r in reversalReasons) AppSelectItem(value: r, label: r)],
                onChanged: (v) => setState(() => _reasonCode = v),
              ),
              const SizedBox(height: 8),
              AppInput(
                controller: _reason,
                minLines: 2,
                maxLines: 4,
                hintText: _noteRequired
                    ? 'Say what happened (needed for Other)'
                    : _correct
                    ? 'Note (optional), e.g. price should have been 25 per crate'
                    : 'Note (optional)',
                onChanged: (_) => setState(() {}),
              ),
              if (_error != null) ...[const SizedBox(height: 12), TrackerBanner.error(_error!)],
            ],
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ customer credit

/// Total credit a customer holds (0 when none).
Future<num> customerCreditTotal(Session session, Company company, int customerId) async {
  final res = await session.farmClient.get('/api/Poultry/customer-payments/credit/$customerId', query: {'farmId': company.farmId});
  final total = rowsOf(res).fold<num>(0, (t, r) => t + tNum(r['unapplied']));
  return (total * 100).round() / 100;
}

/// Who and what the credit is applied to.
class ApplyCreditTarget {
  const ApplyCreditTarget({
    required this.customerId,
    required this.customerName,
    required this.saleId,
    required this.saleLabel,
    required this.outstanding,
  });
  final int customerId;
  final String customerName;
  final int saleId;
  final String saleLabel;
  final num outstanding;
}

/// Apply customer credit to a sale: an allocation only — no new payment, no
/// Money In, no cash movement. Returns the amount applied, or null.
Future<num?> showApplyCredit(BuildContext context, {required Session session, required Company company, required ApplyCreditTarget target}) =>
    showDialog<num>(
      context: context,
      builder: (_) => _ApplyCreditDialog(session: session, company: company, target: target),
    );

class _ApplyCreditDialog extends StatefulWidget {
  const _ApplyCreditDialog({required this.session, required this.company, required this.target});
  final Session session;
  final Company company;
  final ApplyCreditTarget target;
  @override
  State<_ApplyCreditDialog> createState() => _ApplyCreditDialogState();
}

class _ApplyCreditDialogState extends State<_ApplyCreditDialog> {
  num? _credit;
  final _amount = TextEditingController();
  bool _saving = false;
  String? _error;
  FarmMoney _money = const FarmMoney();

  ApplyCreditTarget get t => widget.target;

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _money = m);
    });
    customerCreditTotal(widget.session, widget.company, t.customerId)
        .then((c) {
          if (!mounted) return;
          final suggested = min(c, t.outstanding);
          setState(() {
            _credit = c;
            _amount.text = suggested > 0 ? suggested.toStringAsFixed(2) : '';
          });
        })
        .catchError((Object e) {
          if (mounted) setState(() => _error = e is ApiException ? e.message : '$e');
        });
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  num get _value => num.tryParse(_amount.text) ?? 0;
  bool get _valid => _credit != null && _value > 0 && _value <= _credit! + 0.005 && _value <= t.outstanding + 0.005;

  Future<void> _apply() async {
    if (!_valid) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final farmId = widget.company.farmId;
    try {
      await widget.session.farmClient.post(
        '/api/Poultry/customer-payments/apply-credit?farmId=${Uri.encodeQueryComponent(farmId)}',
        body: {'farmId': farmId, 'customerId': t.customerId, 'saleId': t.saleId, 'amount': (_value * 100).round() / 100},
      );
      if (mounted) Navigator.pop(context, _value);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _saving = false);
  }

  Widget _cell(String label, String value) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: TColors.slate200),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: TColors.slate500)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      scrollable: true,
      title: const Row(
        children: [
          Icon(Icons.account_balance_wallet_outlined, color: TColors.emerald600),
          SizedBox(width: 8),
          Flexible(child: Text('Apply customer credit')),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Use money ${t.customerName.isEmpty ? 'the customer' : t.customerName} already paid to settle sale ${t.saleLabel}. '
              'No new payment is recorded and no cash moves.',
              style: const TextStyle(fontSize: 13, color: TColors.slate500),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _cell('Available credit', _credit == null ? '…' : _money(_credit!)),
                const SizedBox(width: 8),
                _cell('Sale outstanding', _money(t.outstanding)),
              ],
            ),
            const SizedBox(height: 12),
            FilterLabel(
              'Amount to apply',
              AppInput(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                onChanged: (_) => setState(() {}),
              ),
            ),
            if (_credit != null && _credit! <= 0) ...[
              const SizedBox(height: 4),
              const Text('This customer has no credit to apply.', style: TextStyle(fontSize: 12, color: TColors.slate500)),
            ],
            if (_error != null) ...[const SizedBox(height: 10), TrackerBanner.error(_error!)],
          ],
        ),
      ),
      actions: [
        OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Not now')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: TColors.emerald600),
          onPressed: !_valid || _saving ? null : _apply,
          child: Text(_saving ? 'Applying…' : 'Apply credit'),
        ),
      ],
    ),
  );
}

/// Refund customer credit: the business physically hands money back — real
/// Money Out from the account chosen here. Not an expense; no stock moves.
/// Returns true when the refund was recorded.
Future<bool> showRefundCredit(
  BuildContext context, {
  required Session session,
  required Company company,
  required int customerId,
  required String customerName,
  required num availableCredit,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) =>
        _RefundCreditDialog(session: session, company: company, customerId: customerId, customerName: customerName, availableCredit: availableCredit),
  );
  return ok == true;
}

class _RefundCreditDialog extends StatefulWidget {
  const _RefundCreditDialog({
    required this.session,
    required this.company,
    required this.customerId,
    required this.customerName,
    required this.availableCredit,
  });
  final Session session;
  final Company company;
  final int customerId;
  final String customerName;
  final num availableCredit;
  @override
  State<_RefundCreditDialog> createState() => _RefundCreditDialogState();
}

class _RefundCreditDialogState extends State<_RefundCreditDialog> {
  List<Map> _accounts = [];
  int? _account;
  String _method = 'Cash';
  late final _amount = TextEditingController(text: widget.availableCredit > 0 ? widget.availableCredit.toStringAsFixed(2) : '');
  final _reason = TextEditingController();
  bool _saving = false;
  String? _error;
  FarmMoney _money = const FarmMoney();

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _money = m);
    });
    widget.session.farmClient
        .get('/api/Poultry/cash-accounts', query: {'farmId': widget.company.farmId})
        .then((res) {
          if (!mounted) return;
          final active = [
            for (final a in rowsOf(res))
              if (a['isActive'] != false) a,
          ];
          setState(() {
            _accounts = active;
            _account = tIntOrNull(active.firstOrNull?['poultryCashAccountId']);
          });
        })
        .catchError((Object _) {
          if (mounted) setState(() => _accounts = []);
        });
  }

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  num get _value => num.tryParse(_amount.text) ?? 0;
  bool get _valid => _value > 0 && _value <= widget.availableCredit + 0.005 && _account != null && _reason.text.trim().isNotEmpty;

  Future<void> _save() async {
    if (!_valid) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final farmId = widget.company.farmId;
    try {
      await widget.session.farmClient.post(
        '/api/Poultry/customer-payments/refunds?farmId=${Uri.encodeQueryComponent(farmId)}',
        body: {
          'customerId': widget.customerId,
          'amount': (_value * 100).round() / 100,
          'poultryCashAccountId': _account,
          'paymentMethod': _method,
          'reason': _reason.text.trim(),
          'farmId': farmId,
        },
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      scrollable: true,
      title: const Row(
        children: [
          Icon(Icons.payments_outlined, color: TColors.amber600),
          SizedBox(width: 8),
          Flexible(child: Text('Refund customer credit')),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Give ${widget.customerName.isEmpty ? 'the customer' : widget.customerName} back money they paid and you still hold. '
              'This is money going out of the account you choose; it is recorded as a refund, not an expense, and no stock moves.',
              style: const TextStyle(fontSize: 13, color: TColors.slate500),
            ),
            const SizedBox(height: 12),
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Available credit: '),
                  TextSpan(
                    text: _money(widget.availableCredit),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              style: const TextStyle(fontSize: 13, color: TColors.slate600),
            ),
            const SizedBox(height: 12),
            filterRow([
              FilterLabel(
                'Amount',
                AppInput(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                  onChanged: (_) => setState(() {}),
                ),
              ),
              FilterLabel(
                'Method',
                AppSelect<String>(
                  value: _method,
                  items: [for (final m in refundMethods) AppSelectItem(value: m, label: m)],
                  onChanged: (v) => setState(() => _method = v ?? _method),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            FilterLabel(
              'Paid from',
              AppSelect<int>(
                value: _account,
                hintText: 'Choose a cash account',
                items: [
                  for (final a in _accounts)
                    AppSelectItem(value: tIntOrNull(a['poultryCashAccountId'])!, label: '${a['accountName']} · ${_money(tNum(a['currentBalance']))}'),
                ],
                onChanged: (v) => setState(() => _account = v),
              ),
            ),
            const SizedBox(height: 10),
            FilterLabel(
              'Reason',
              AppInput(
                controller: _reason,
                minLines: 2,
                maxLines: 4,
                hintText: 'e.g. Sale cancelled, customer asked for the money back',
                onChanged: (_) => setState(() {}),
              ),
            ),
            if (_error != null) ...[const SizedBox(height: 10), TrackerBanner.error(_error!)],
          ],
        ),
      ),
      actions: [
        OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: TColors.amber600),
          onPressed: !_valid || _saving ? null : _save,
          child: Text(_saving ? 'Refunding…' : 'Refund'),
        ),
      ],
    ),
  );
}

/// Customer Credit (customer-credit-panel.tsx), on Poultry Customer Balances:
/// money customers paid that is not on any active sale, beside — never netted
/// into — what they owe. Says nothing when no credit is held.
class CustomerCreditPanel extends StatefulWidget {
  const CustomerCreditPanel({super.key, required this.session, required this.company, required this.canRefund});
  final Session session;
  final Company company;
  final bool canRefund;
  @override
  State<CustomerCreditPanel> createState() => _CustomerCreditPanelState();
}

class _CustomerCreditPanelState extends State<CustomerCreditPanel> {
  List<Map> _rows = [];
  bool _loaded = false;
  FarmMoney _money = const FarmMoney();

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _money = m);
    });
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await widget.session.farmClient.get('/api/Poultry/customer-payments/credit', query: {'farmId': widget.company.farmId});
      if (mounted) setState(() => _rows = rowsOf(res));
    } on ApiException {
      if (mounted) setState(() => _rows = []);
    }
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _refund(Map r) async {
    final name = tStr(r['customerName']);
    final ok = await showRefundCredit(
      context,
      session: widget.session,
      company: widget.company,
      customerId: tIntOrNull(r['customerId']) ?? 0,
      customerName: name,
      availableCredit: tNum(r['availableCredit']),
    );
    if (!ok || !mounted) return;
    trackerToast(context, 'Refund recorded', description: 'Paid back to $name. It shows in Cash Flow as a customer refund.');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _rows.isEmpty) return const SizedBox.shrink();
    final total = _rows.fold<num>(0, (t, r) => t + tNum(r['availableCredit']));
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: TColors.blue200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.savings_outlined, size: 16, color: TColors.blue600),
              const SizedBox(width: 8),
              const Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'Customer credit',
                        style: TextStyle(fontWeight: FontWeight.w600, color: TColors.slate900),
                      ),
                      TextSpan(
                        text: ' — money customers paid that is not on any active sale',
                        style: TextStyle(color: TColors.slate500),
                      ),
                    ],
                  ),
                  style: TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_money(total)} held',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1D4ED8)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final r in _rows)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(color: TColors.slate200),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tStr(r['customerName']),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                        Text.rich(
                          TextSpan(
                            children: [
                              const TextSpan(text: 'Credit '),
                              TextSpan(
                                text: _money(tNum(r['availableCredit'])),
                                style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF1D4ED8)),
                              ),
                              TextSpan(text: ' · Owes ${_money(tNum(r['outstanding']))}'),
                            ],
                          ),
                          style: const TextStyle(fontSize: 12, color: TColors.slate500),
                        ),
                      ],
                    ),
                  ),
                  if (widget.canRefund)
                    OutlinedButton.icon(
                      onPressed: () => _refund(r),
                      icon: const Icon(Icons.payments_outlined, size: 16),
                      label: const Text('Refund'),
                    ),
                ],
              ),
            ),
          const Text(
            'To use credit on a sale, open the sale\'s Pay dialog on the Sales page and choose "Use customer credit". No new money is recorded.',
            style: TextStyle(fontSize: 12, color: TColors.slate500),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ sale lines

/// What was sold inside one or more sales (sale-lines-dialog.tsx), read-only:
/// opened from Customer Balances and Payments Received. Each sale is fetched
/// fresh (GET Sale/{id} carries its lines).
class SaleLinesScreen extends StatefulWidget {
  const SaleLinesScreen({super.key, required this.session, required this.company, required this.saleIds, this.title, this.onOpenSale});
  final Session session;
  final Company company;
  final List<int> saleIds;
  final String? title;

  /// Offered as "Open on Sales page" per sale when given.
  final ValueChanged<int>? onOpenSale;

  @override
  State<SaleLinesScreen> createState() => _SaleLinesScreenState();
}

class _SaleLinesScreenState extends State<SaleLinesScreen> {
  List<Map> _sales = [];
  List<Map> _classes = [];
  bool _loading = true;
  String? _error;
  FarmMoney _money = const FarmMoney();

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _money = m);
    });
    _load();
  }

  Future<void> _load() async {
    final api = widget.session.farmClient;
    final q = {'userId': widget.session.tokens.userId, 'farmId': widget.company.farmId};
    final found = <Map>[];
    for (final id in widget.saleIds) {
      try {
        final r = await api.get('/api/Sale/$id', query: q);
        if (r is Map) found.add(r);
      } on ApiException {
        // A sale that will not load is left out, as the web.
      }
    }
    List<Map> classes = [];
    try {
      classes = rowsOf(
        await api.get('/api/Poultry/egg-sorting/classes', query: {'farmId': widget.company.farmId, 'includeInactive': 'false', 'ensure': 'false'}),
      );
    } on ApiException {
      classes = [];
    }
    if (!mounted) return;
    setState(() {
      _sales = found;
      _classes = classes;
      _loading = false;
      if (found.isEmpty) _error = 'This sale could not be loaded.';
    });
  }

  String _classLabel(Map l) {
    if (!isEggProductName(l['product'])) return tStr(l['size']).isEmpty ? '—' : tStr(l['size']);
    final c = _classes.where((x) => tIntOrNull(x['poultryProductId']) == tIntOrNull(l['eggProductId'])).firstOrNull;
    if (c != null) return c['classKind'] == 'Unsorted' ? 'Unsorted' : tStr(c['name']);
    return tStr(l['size']).isEmpty ? 'Unsorted' : tStr(l['size']);
  }

  Widget _sale(Map s) {
    final lines = saleLinesOf(s);
    final total = tNum(s['totalAmount']);
    final paid = tNum(s['amountPaid'] ?? (s['paid'] == false ? 0 : total));
    final reversed = isReversedSale(s);
    Widget kv(String l, String v, {bool bold = false}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
        Text(v, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w600 : FontWeight.w500)),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                'Sale ${tStr(s['saleGroupNo']).isNotEmpty ? s['saleGroupNo'] : '#${s['saleId']}'}',
                style: const TextStyle(fontWeight: FontWeight.w600, color: TColors.slate900),
              ),
              _postedBadge(reversed),
              if (widget.onOpenSale != null)
                TextButton.icon(
                  onPressed: () => widget.onOpenSale!(tIntOrNull(s['saleId']) ?? 0),
                  icon: const Icon(Icons.open_in_new, size: 15),
                  label: const Text('Open on Sales page'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: TColors.slate50,
              border: Border.all(color: TColors.slate200),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: kv('Date', _shortDate(s['saleDate']))),
                    Expanded(child: kv('Customer', tStr(s['customerName']).isEmpty ? 'Walk-in' : tStr(s['customerName']))),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(child: kv('Paid', _money(paid))),
                    Expanded(child: kv('Balance', reversed ? '—' : _money(max<num>(0, total - paid)), bold: true)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (final l in lines)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(color: TColors.slate200),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text('${l['lineNo']}  ', style: const TextStyle(fontSize: 13, color: TColors.slate500)),
                      Expanded(
                        child: Text(tStr(l['product']), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      ),
                      Text(_money(tNum(l['totalAmount'])), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text('Size / class: ${_classLabel(l)}', style: const TextStyle(fontSize: 12, color: TColors.slate600)),
                      ),
                    ],
                  ),
                  Text('Quantity: ${saleLineQuantityLabel(l)}', style: const TextStyle(fontSize: 12, color: TColors.slate600)),
                  Text(
                    'Unit price: ${_money(tNum(l['unitPrice']))}${isEggProductName(l['product']) ? ' /crate' : ''}',
                    style: const TextStyle(fontSize: 12, color: TColors.slate600),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: TColors.slate50, borderRadius: BorderRadius.circular(6)),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Total', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                ),
                Text(_money(total), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final many = widget.saleIds.length > 1;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? (many ? '${widget.saleIds.length} sales' : 'Sale details'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        children: [
          Text(
            'What was sold on ${many ? 'these sales' : 'this sale'}, line by line.',
            style: const TextStyle(fontSize: 13, color: TColors.slate500),
          ),
          const SizedBox(height: 14),
          if (_loading)
            const Row(
              children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 8),
                Text('Loading sale lines…', style: TextStyle(fontSize: 13, color: TColors.slate500)),
              ],
            )
          else if (_error != null)
            Text(_error!, style: const TextStyle(fontSize: 13, color: TColors.red600))
          else
            for (final s in _sales) _sale(s),
        ],
      ),
    );
  }
}
