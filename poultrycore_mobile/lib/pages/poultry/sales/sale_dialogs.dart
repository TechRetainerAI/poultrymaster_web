// The dialogs the Sales page opens: Record payment, Payment history
// (components/balances/payment-history-dialog.tsx, scoped to one sale) and the
// invoice (components/sales/sale-invoice-document.tsx).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../api/api_client.dart';
import '../../../design/ui/buttons.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../reports/report_export.dart';
import '../reports/report_format.dart';
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull, loc;
import '../trackers/tracker_widgets.dart';
import 'sales_logic.dart';
import 'balances_logic.dart' show BalanceSide;

// ------------------------------------------------------------------ record payment

/// "Record payment" against one sale. Returns true when a payment was posted.
Future<bool> showRecordPayment(BuildContext context, {required Session session, required Company company, required Map sale}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _RecordPaymentDialog(session: session, company: company, sale: sale),
  );
  return ok == true;
}

class _RecordPaymentDialog extends StatefulWidget {
  const _RecordPaymentDialog({required this.session, required this.company, required this.sale});
  final Session session;
  final Company company;
  final Map sale;
  @override
  State<_RecordPaymentDialog> createState() => _RecordPaymentDialogState();
}

class _RecordPaymentDialogState extends State<_RecordPaymentDialog> {
  late final _amount = TextEditingController(
      text: saleOwed(widget.sale) > 0 ? saleOwed(widget.sale).toStringAsFixed(2) : '');
  final _note = TextEditingController();
  String _method = 'Cash';
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _record() async {
    final s = widget.sale;
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      trackerToast(context, 'Enter a valid amount', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.session.farmClient.post('/api/Poultry/payments', body: {
        'saleId': tIntOrNull(s['saleId']),
        'amount': amount,
        'paymentMethod': _method.isEmpty ? null : _method,
        'note': _note.text.isEmpty ? null : _note.text,
        'farmId': widget.company.farmId,
        'createdBy': widget.session.tokens.userId,
      });
      if (!mounted) return;
      trackerToast(context, 'Payment recorded', description: '${amount.toStringAsFixed(2)} received for sale #${s['saleId']}.');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        trackerToast(context, 'Payment failed', description: e.message, error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.sale;
    final customer = tStr(s['customerName']);
    Widget line(String l, String v, {Color? color, bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Text(l, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
            const Spacer(),
            Flexible(
              child: Text(v,
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 13, color: color, fontWeight: bold ? FontWeight.w600 : FontWeight.w500)),
            ),
          ]),
        );
    return AlertDialog(
      title: const Text('Record payment'),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: TColors.slate50,
                border: Border.all(color: TColors.slate200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(children: [
                line('Sale', '#${s['saleId']} · ${customer.isEmpty ? 'Walk-in' : customer}'),
                line('Total', tNum(s['totalAmount']).toStringAsFixed(2)),
                line('Owed', saleOwed(s).toStringAsFixed(2), color: TColors.amber700, bold: true),
              ]),
            ),
            const SizedBox(height: 14),
            FilterLabel(
              'Amount *',
              AppInput(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
              ),
            ),
            const SizedBox(height: 12),
            FilterLabel(
              'Method',
              AppSelect<String>(
                value: _method,
                hintText: 'Select method',
                items: [for (final m in recordPaymentMethods) AppSelectItem(value: m, label: m)],
                onChanged: (v) => setState(() => _method = v ?? _method),
              ),
            ),
            const SizedBox(height: 12),
            FilterLabel('Note', AppInput(controller: _note, hintText: 'Optional')),
          ],
        ),
      ),
      actions: [
        OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: TColors.emerald600),
          onPressed: _saving ? null : _record,
          child: Text(_saving ? 'Saving…' : 'Record payment'),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ payment history

const _sourceLabel = {
  'CustomerBalances': 'Balances',
  'SupplierBalances': 'Balances',
  'SaleEntry': 'Sale',
  'PurchaseEntry': 'Purchase',
};

String _paymentRef(Map row) {
  final n = tStr(row['paymentNumber']).trim();
  if (n.isNotEmpty) return n;
  final id = tStr(row['paymentId']);
  return '#${id.length > 8 ? id.substring(0, 8) : id}';
}

String _shortDate(Object? d) {
  final dt = DateTime.tryParse(tStr(d))?.toLocal();
  if (dt == null) return '—';
  return '${dt.month}/${dt.day}/${dt.year}';
}

/// Payment history (customer side): one sale ([documentId]), one customer
/// ([partyId]), or every customer when both are null. [onReversed] runs after
/// a reversal so the balances refresh.
Future<void> showPaymentHistory(
  BuildContext context, {
  required Session session,
  required Company company,
  int? partyId,
  String? partyName,
  String? documentType,
  int? documentId,
  required bool canReverse,
  required VoidCallback onReversed,
  BalanceSide side = BalanceSide.customer,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .85,
        maxChildSize: .95,
        builder: (ctx, controller) => _PaymentHistory(
          controller: controller,
          session: session,
          company: company,
          partyId: partyId,
          partyName: partyName,
          documentType: documentType,
          documentId: documentId,
          canReverse: canReverse,
          onReversed: onReversed,
          side: side,
        ),
      ),
    );

class _PaymentHistory extends StatefulWidget {
  const _PaymentHistory({
    required this.controller,
    required this.session,
    required this.company,
    this.partyId,
    this.partyName,
    this.documentType,
    this.documentId,
    required this.canReverse,
    required this.onReversed,
    this.side = BalanceSide.customer,
  });
  final BalanceSide side;
  final ScrollController controller;
  final Session session;
  final Company company;
  final int? partyId;
  final String? partyName;
  final String? documentType;
  final int? documentId;
  final bool canReverse;
  final VoidCallback onReversed;
  @override
  State<_PaymentHistory> createState() => _PaymentHistoryState();
}

class _PaymentHistoryState extends State<_PaymentHistory> {
  List<Map> _rows = [];
  bool _loading = true;
  String? _expanded;
  final Map<String, List<Map>> _allocations = {};
  String? _reversing;
  final _reason = TextEditingController();

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _api.get('/api/Poultry/${widget.side.paymentsPath}', query: {
        'farmId': _farmId,
        ...widget.side.paymentQuery(partyId: widget.partyId, documentType: widget.documentType, documentId: widget.documentId),
      });
      if (mounted) setState(() => _rows = rowsOf(res));
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load payments', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggle(Map row) async {
    final id = tStr(row['paymentId']);
    if (_expanded == id) {
      setState(() => _expanded = null);
      return;
    }
    setState(() => _expanded = id);
    if (_allocations.containsKey(id)) return;
    try {
      final res = await _api.get('/api/Poultry/${widget.side.paymentsPath}/${Uri.encodeComponent(id)}', query: {'farmId': _farmId});
      final alloc = res is Map ? rowsOf(res['allocations']) : <Map>[];
      if (mounted) setState(() => _allocations[id] = alloc);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load allocation', description: e.message, error: true);
    }
  }

  Future<void> _reverse(Map row) async {
    if (_reason.text.trim().isEmpty) {
      trackerToast(context, 'A reason is required',
          description: 'Say why this payment is being reversed — it is written to the audit trail.', error: true);
      return;
    }
    final money = await FarmMoney.load(widget.session, widget.company);
    try {
      await _api.post('/api/Poultry/${widget.side.paymentsPath}/${Uri.encodeComponent(tStr(row['paymentId']))}/reverse', body: {
        'farmId': _farmId,
        'reason': _reason.text.trim(),
        'reversedBy': widget.session.tokens.userId,
      });
      if (!mounted) return;
      trackerToast(context, 'Payment reversed', description: '${money(tNum(row['totalAmount']))} put back on the balance.');
      setState(() {
        _reversing = null;
        _reason.clear();
      });
      await _load();
      widget.onReversed();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not reverse payment', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final party = (widget.partyName ?? '').isNotEmpty ? widget.partyName! : (widget.side.isCustomer ? 'All customers' : 'All suppliers');
    final scope = widget.documentId != null ? ' · ${widget.documentType ?? ''} #${widget.documentId}' : '';
    return FutureBuilder<FarmMoney>(
      future: FarmMoney.load(widget.session, widget.company),
      builder: (context, snap) {
        final fmt = snap.data ?? const FarmMoney();
        return ListView(
          controller: widget.controller,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            const Text('Payment history', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('$party$scope',
                style: const TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Row(children: [
                        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 8),
                        Text('Loading…', style: TextStyle(color: TColors.slate500)),
                      ]),
                    )
                  : _rows.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: Text('No payments recorded yet.', style: TextStyle(color: TColors.slate500))),
                        )
                      : Column(children: [
                          for (var i = 0; i < _rows.length; i++) ...[
                            if (i > 0) const Divider(height: 1, color: TColors.slate100),
                            _card(_rows[i], fmt),
                          ],
                        ]),
            ),
            const SizedBox(height: 14),
            AppButton(label: 'Close', fullWidth: true, onPressed: () => Navigator.pop(context)),
          ],
        );
      },
    );
  }

  Widget _card(Map row, FarmMoney fmt) {
    final id = tStr(row['paymentId']);
    final reversed = row['status'] == 'Reversed';
    final open = _expanded == id;
    final count = tIntOrNull(row['allocationCount']) ?? 0;
    final sm = const TextStyle(fontSize: 12, color: TColors.slate500);
    return Container(
      decoration: BoxDecoration(
        color: open ? const Color(0xB3C7D2FE) : reversed ? const Color(0xB3FFE4E6) : null,
        border: Border(
          left: BorderSide(
              color: open ? const Color(0xFF4F46E5) : reversed ? const Color(0xFFFB7185) : Colors.transparent, width: 4),
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => _toggle(row),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(fmt(tNum(row['totalAmount'])),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: reversed ? TColors.slate400 : TColors.slate900,
                          decoration: reversed ? TextDecoration.lineThrough : null,
                        )),
                    reversed
                        ? const TBadge('Reversed', bg: TColors.rose50, fg: TColors.rose700, border: TColors.rose200)
                        : const TBadge('Posted', bg: TColors.emerald50, fg: TColors.emerald700, border: TColors.emerald200),
                  ]),
                  const SizedBox(height: 4),
                  Text('${_shortDate(row['paymentDate'])} · ${tStr(row['paymentMethod']).isEmpty ? '—' : row['paymentMethod']} · '
                      '$count item${count == 1 ? '' : 's'}', style: sm),
                ]),
              ),
              Icon(open ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, size: 18, color: TColors.slate400),
            ]),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: Text(_paymentRef(row), style: sm, overflow: TextOverflow.ellipsis)),
            Expanded(
              child: Text('Source: ${tStr(row['sourceType']).isEmpty ? '—' : (_sourceLabel[row['sourceType']] ?? row['sourceType'])}',
                  textAlign: TextAlign.right, style: sm, overflow: TextOverflow.ellipsis),
            ),
          ]),
          Text('Ref: ${tStr(row['reference']).isEmpty ? '—' : row['reference']}', style: sm, overflow: TextOverflow.ellipsis),
          if (reversed && tStr(row['reversalReason']).isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
                'Reversed${tStr(row['reversedBy']).isNotEmpty ? ' by ${row['reversedBy']}' : ''}'
                '${tStr(row['reversedAt']).isNotEmpty ? ' on ${_shortDate(row['reversedAt'])}' : ''}: ${row['reversalReason']}',
                style: sm),
          ],
          if (widget.canReverse && !reversed && _reversing != id) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(backgroundColor: Colors.white, minimumSize: const Size.fromHeight(40)),
              onPressed: () => setState(() {
                _reversing = id;
                _reason.clear();
              }),
              icon: const Icon(Icons.undo, size: 16),
              label: const Text('Reverse'),
            ),
          ],
          if (_reversing == id) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: TColors.amber50, borderRadius: BorderRadius.circular(8)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                FilterLabel('Why is this being reversed?', AppInput(controller: _reason, hintText: 'e.g. entered twice')),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: TColors.red600),
                      onPressed: () => _reverse(row),
                      child: const Text('Reverse payment'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: TextButton(onPressed: () => setState(() => _reversing = null), child: const Text('Cancel'))),
                ]),
                const SizedBox(height: 8),
                Text(
                    'The balance goes back onto the ${widget.side.isCustomer ? 'sales' : 'purchases'} it was applied to and the cash movement is undone. The payment is kept and marked reversed, never deleted.',
                    style: const TextStyle(fontSize: 12, color: TColors.slate500)),
              ]),
            ),
          ],
          if (open) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: TColors.slate50, borderRadius: BorderRadius.circular(8)),
              child: !_allocations.containsKey(id)
                  ? const Row(children: [
                      SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 8),
                      Flexible(child: Text('Loading allocation…', style: TextStyle(fontSize: 13, color: TColors.slate500))),
                    ])
                  : Column(children: [for (final a in _allocations[id]!) _allocation(a, fmt)]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _allocation(Map a, FarmMoney fmt) {
    const sm = TextStyle(fontSize: 12, color: TColors.slate500);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: TColors.slate200),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text('${a['reference'] ?? a['documentId']}',
                overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          ),
          Text(fmt(tNum(a['amountApplied'])), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
        if (tStr(a['label']).isNotEmpty) Text(tStr(a['label']), style: sm, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: Text(_shortDate(a['documentDate']), style: sm)),
          Expanded(child: Text('Total ${fmt(tNum(a['documentTotal']))}', textAlign: TextAlign.right, style: sm)),
        ]),
        Row(children: [
          Expanded(child: Text('Before ${fmt(tNum(a['balanceBefore']))}', style: sm)),
          Expanded(child: Text('After ${fmt(tNum(a['balanceAfter']))}', textAlign: TextAlign.right, style: sm)),
        ]),
      ]),
    );
  }
}

// ------------------------------------------------------------------ invoice

String _invoiceDate(Object? d) {
  final dt = DateTime.tryParse(tStr(d));
  if (dt == null) return '—';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${m[dt.month - 1]} ${dt.day}, ${dt.year}';
}

/// The "Sale invoice" dialog: the tax invoice and its Print invoice button.
class SaleInvoiceScreen extends StatelessWidget {
  const SaleInvoiceScreen({super.key, required this.sale, required this.farmName, required this.money, required this.flockLabel});
  final Map sale;
  final String farmName;
  final FarmMoney money;
  final String flockLabel;

  static const _accent = Color(0xFF0D4A42);
  static const _accentSoft = Color(0xFFE9F5F2);
  static const _muted = Color(0xFF5C6578);
  static const _line = Color(0xFFE8ECF2);

  ({num total, num paid, num owed, String status}) get _figures {
    final total = tNum(sale['totalAmount']);
    final paid = salePaid(sale);
    final owed = (total - paid) > 0 ? total - paid : 0;
    return (total: total, paid: paid, owed: owed, status: owed <= 0 ? 'Paid' : paid > 0 ? 'Part paid' : 'Unpaid');
  }

  Future<void> _print() async {
    final f = _figures;
    final inv = saleInvoiceNumber(sale['saleId']);
    final isEggs = isEggProductName(sale['product']);
    final qty = tNum(sale['quantity']);
    final l = ReportExport.latin;
    final doc = pw.Document();
    const accent = PdfColor.fromInt(0xFF0D4A42);
    const soft = PdfColor.fromInt(0xFFE9F5F2);
    const muted = PdfColor.fromInt(0xFF5C6578);
    pw.Widget label(String s) =>
        pw.Text(s.toUpperCase(), style: const pw.TextStyle(fontSize: 7, color: muted, letterSpacing: 1.2));
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Container(
          color: accent,
          padding: const pw.EdgeInsets.all(20),
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(l(farmName), style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text('TAX INVOICE', style: const pw.TextStyle(fontSize: 8, color: PdfColors.white, letterSpacing: 2)),
              pw.Text(inv, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
              pw.Text(f.status.toUpperCase(), style: const pw.TextStyle(fontSize: 8, color: PdfColors.white)),
            ]),
          ]),
        ),
        pw.SizedBox(height: 14),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(flex: 16, child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            label('Billed to'),
            pw.Text(l(tStr(sale['customerName'])), style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            if (tStr(sale['saleDescription']).isNotEmpty) pw.Text(l(tStr(sale['saleDescription'])), style: const pw.TextStyle(fontSize: 9, color: muted)),
          ])),
          pw.Expanded(flex: 10, child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            label('Invoice date'),
            pw.Text(_invoiceDate(sale['saleDate']), style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Text('Recorded ${_invoiceDate(sale['createdDate'])}', style: const pw.TextStyle(fontSize: 9, color: muted)),
          ])),
          pw.Expanded(flex: 10, child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            label('Payment'),
            pw.Text(l(tStr(sale['paymentMethod'])), style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Text(l('Flock: $flockLabel'), style: const pw.TextStyle(fontSize: 9, color: muted)),
          ])),
        ]),
        pw.SizedBox(height: 16),
        pw.Table(
          border: pw.TableBorder.all(color: const PdfColor.fromInt(0xFFE8ECF2)),
          columnWidths: {0: const pw.FlexColumnWidth(3), 1: const pw.FlexColumnWidth(1), 2: const pw.FlexColumnWidth(1.4), 3: const pw.FlexColumnWidth(1.4)},
          children: [
            pw.TableRow(decoration: const pw.BoxDecoration(color: soft), children: [
              for (final h in ['DESCRIPTION', 'QTY', 'UNIT PRICE', 'AMOUNT'])
                pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(h, textAlign: h == 'DESCRIPTION' ? pw.TextAlign.left : pw.TextAlign.right, style: pw.TextStyle(fontSize: 7, color: accent, fontWeight: pw.FontWeight.bold))),
            ]),
            pw.TableRow(children: [
              pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(l(tStr(sale['product'])), style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                if (isEggs && qty > 0) pw.Text('${(qty / 30).floor()} crates + ${(qty % 30).toInt()} loose', style: const pw.TextStyle(fontSize: 8, color: muted)),
              ])),
              pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(jsQty(qty), textAlign: pw.TextAlign.right)),
              pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(l(money(tNum(sale['unitPrice']))), textAlign: pw.TextAlign.right)),
              pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(l(money(f.total)), textAlign: pw.TextAlign.right, style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
            ]),
          ],
        ),
        pw.SizedBox(height: 16),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(child: pw.Text('Thank you for your business. If you have questions about this invoice, quote invoice number $inv.', style: const pw.TextStyle(fontSize: 9, color: muted))),
          pw.SizedBox(width: 20),
          pw.SizedBox(width: 200, child: pw.Column(children: [
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Subtotal'), pw.Text(l(money(f.total)))]),
            if (f.paid > 0) pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Amount paid'), pw.Text(l('-${money(f.paid)}'))]),
            pw.SizedBox(height: 6),
            pw.Container(
              color: f.owed <= 0 ? const PdfColor.fromInt(0xFFECFDF5) : soft,
              padding: const pw.EdgeInsets.all(10),
              child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text(f.owed <= 0 ? 'PAID IN FULL' : 'BALANCE DUE', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: accent)),
                pw.Text(l(money(f.owed)), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: accent)),
              ]),
            ),
          ])),
        ]),
        pw.SizedBox(height: 20),
        pw.Text('This document was generated electronically and is valid without a signature.', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 8, color: muted)),
      ]),
    ));
    await ReportExport.sharer('$inv.pdf', await doc.save(), 'application/pdf', 'Invoice $inv');
  }

  static String jsQty(num n) => n == n.roundToDouble() ? n.toInt().toString() : '$n';

  @override
  Widget build(BuildContext context) {
    final f = _figures;
    final inv = saleInvoiceNumber(sale['saleId']);
    final isEggs = isEggProductName(sale['product']);
    final qty = tNum(sale['quantity']);
    final (badgeBg, badgeFg, badgeBorder) = f.owed <= 0
        ? (const Color(0xFFECFDF5), const Color(0xFF047857), const Color(0xFFA7F3D0))
        : f.paid > 0
            ? (const Color(0xFFEFF6FF), const Color(0xFF1D4ED8), const Color(0xFFBFDBFE))
            : (const Color(0xFFFFFBEB), const Color(0xFFB45309), const Color(0xFFFDE68A));
    Widget label(String s) => Text(s.toUpperCase(),
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: _muted));
    Widget metaCell(String l, String strong, String? sub) => Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: _line))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            label(l),
            const SizedBox(height: 4),
            Text(strong, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            if (sub != null) Text(sub, style: const TextStyle(fontSize: 12.5, color: _muted)),
          ]),
        );
    Widget numRow(String l, String v, {bool strong = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: _line))),
          child: Row(children: [
            label(l),
            const Spacer(),
            Text(v, style: TextStyle(fontWeight: strong ? FontWeight.w600 : FontWeight.w400)),
          ]),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Sale invoice')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          SizedBox(
            height: 44,
            child: FilledButton.icon(onPressed: _print, icon: const Icon(Icons.print_outlined, size: 18), label: const Text('Print invoice')),
          ),
          const SizedBox(height: 14),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: _line),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xFF0D4A42), Color(0xFF14655A), Color(0xFF1C8574)]),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(farmName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                  const SizedBox(height: 12),
                  const Text('TAX INVOICE',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 2.5, color: Color(0xB8FFFFFF))),
                  Text(inv, style: const TextStyle(fontFamily: 'monospace', fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: badgeBg, border: Border.all(color: badgeBorder), borderRadius: BorderRadius.circular(999)),
                    child: Text(f.status.toUpperCase(),
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: .6, color: badgeFg)),
                  ),
                ]),
              ),
              Container(
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _line))),
                child: Column(children: [
                  Container(
                    decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.transparent))),
                    child: metaCell('Billed to', tStr(sale['customerName']),
                        tStr(sale['saleDescription']).isNotEmpty ? tStr(sale['saleDescription']) : null),
                  ),
                  metaCell('Invoice date', _invoiceDate(sale['saleDate']), 'Recorded ${_invoiceDate(sale['createdDate'])}'),
                  metaCell('Payment', tStr(sale['paymentMethod']), 'Flock: $flockLabel'),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Container(
                    decoration: BoxDecoration(border: Border.all(color: _line), borderRadius: BorderRadius.circular(10)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(tStr(sale['product']), style: const TextStyle(fontWeight: FontWeight.w600)),
                          if (isEggs && qty > 0)
                            Text('${(qty / 30).floor()} crates + ${(qty % 30).toInt()} loose',
                                style: const TextStyle(fontSize: 12, color: _muted)),
                        ]),
                      ),
                      numRow('Qty', jsQty(qty)),
                      numRow('Unit price', money(tNum(sale['unitPrice']))),
                      numRow('Amount', money(f.total), strong: true),
                    ]),
                  ),
                  const SizedBox(height: 18),
                  // What's owed first on a phone, as the web's mobile layout.
                  Row(children: [
                    const Text('Subtotal', style: TextStyle(color: _muted)),
                    const Spacer(),
                    Text(money(f.total), style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                  if (f.paid > 0) ...[
                    const SizedBox(height: 6),
                    Row(children: [
                      const Expanded(child: Text('Amount paid', style: TextStyle(color: _muted))),
                      Text('-${money(f.paid)}', style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF047857))),
                    ]),
                  ],
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: f.owed <= 0 ? const Color(0xFFECFDF5) : _accentSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      Expanded(child: Text(f.owed <= 0 ? 'PAID IN FULL' : 'BALANCE DUE',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                              color: f.owed <= 0 ? const Color(0xFF047857) : _accent))),
                      Text(money(f.owed),
                          style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: f.owed <= 0 ? const Color(0xFF047857) : _accent)),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  Text.rich(
                    TextSpan(children: [
                      const TextSpan(
                          text: 'Thank you for your business. If you have questions about this invoice, quote invoice number '),
                      TextSpan(text: inv, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0C1222))),
                      const TextSpan(text: '.'),
                    ]),
                    style: const TextStyle(fontSize: 12.5, color: _muted),
                  ),
                  const SizedBox(height: 18),
                  const Divider(color: _line),
                  const Text('This document was generated electronically and is valid without a signature.',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: _muted)),
                ]),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

/// A count as the web prints it (toLocaleString).
String saleQty(num n) => loc(n);
