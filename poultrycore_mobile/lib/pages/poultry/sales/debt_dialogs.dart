// Customer and supplier debts on Poultry Customer / Supplier Balances
// (components/balances/customer-debts-panel.tsx, customer-debt-dialog.tsx and
// their supplier twins, migrations 369 / 370), and the Supplier credit panel
// under Supplier Balances (components/suppliers/supplier-credit-panel.tsx).
//
// A debt is owed without a sale or purchase here: no revenue, no stock, no
// cash. An open debt already shows among the party's open items, so there is
// no separate debts table: Record debt is a header button (owner / admin) and
// Reverse debt is on the debt's row (owner / admin, only while nothing is paid).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/form_dialog.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../poultry_links.dart';
import '../reports/report_format.dart';
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../trackers/tracker_widgets.dart';
import 'balances_logic.dart' show BalanceSide;
import 'credit_widgets.dart';

const customerDebtEntryLabel = {
  'OpeningBalance': 'Opening balance',
  'HistoricalDebt': 'Historical sale / debt',
  'Adjustment': 'Adjustment',
  'Migration': 'Migration',
  'ExternalTransaction': 'External transaction',
  'Other': 'Other',
};

const supplierDebtEntryLabel = {
  'OpeningBalance': 'Opening balance',
  'HistoricalDebt': 'Historical purchase / debt',
  'Adjustment': 'Adjustment',
  'Migration': 'Migration',
  'ExternalTransaction': 'External transaction',
  'Other': 'Other',
};

/// The debt document type on [side]'s open items.
String debtDocumentType(BalanceSide side) => side.isCustomer ? 'CustomerDebt' : 'SupplierDebt';

String _debtsPath(BalanceSide side) => side.isCustomer ? 'customer-debts' : 'supplier-debts';

/// Record customer / supplier debt. Returns true when one was recorded (the
/// toast is shown here).
Future<bool> showRecordDebt(BuildContext context, {required Session session, required Company company, required BalanceSide side}) async {
  final money = await FarmMoney.load(session, company);
  if (!context.mounted) return false;
  final d = await showDialog<Map>(context: context, builder: (_) => _DebtDialog(session: session, company: company, side: side, money: money));
  if (d == null || !context.mounted) return false;
  trackerToast(
    context,
    'Debt recorded',
    description: side.isCustomer
        ? '${tStr(d['debtNumber'])}: ${tStr(d['partyName'])} owes ${money(tNum(d['amount']))} more.'
        : '${tStr(d['debtNumber'])}: you owe ${tStr(d['partyName'])} ${money(tNum(d['amount']))} more.',
  );
  return true;
}

/// Reverse a debt from its row. Returns true when reversed (toast shown here).
Future<bool> reverseDebt(
  BuildContext context, {
  required Session session,
  required Company company,
  required BalanceSide side,
  required Map doc,
  String? partyName,
}) async {
  final money = await FarmMoney.load(session, company);
  if (!context.mounted) return false;
  final number = tStr(doc['reference']).isNotEmpty ? tStr(doc['reference']) : 'debt ${tStr(doc['documentId'])}';
  final total = money(tNum(doc['totalAmount']));
  final party = (partyName ?? '').isNotEmpty ? partyName! : (side.isCustomer ? 'the customer' : 'the supplier');
  final ok = await showReverseWithReason(
    context,
    title: 'Reverse $number?',
    description: side.isCustomer
        ? '${(partyName ?? '').isNotEmpty ? partyName : 'The customer'} will no longer owe $total. The debt stays in the history, marked Reversed. No cash moves.'
        : 'You will no longer owe $party $total. The debt stays in the history, marked Reversed. No cash moves.',
    body: const [],
    action: 'Reverse debt · $total',
    onConfirm: (reason) => session.farmClient.post(
      '/api/Poultry/${_debtsPath(side)}/${tStr(doc['documentId'])}/reverse?farmId=${Uri.encodeQueryComponent(company.farmId)}',
      body: {'farmId': company.farmId, 'reason': reason},
    ),
  );
  if (!ok || !context.mounted) return false;
  trackerToast(context, 'Debt reversed',
      description: side.isCustomer ? '$number for $party is no longer owed.' : '$number to $party is no longer owed.');
  return true;
}

class _DebtDialog extends StatefulWidget {
  const _DebtDialog({required this.session, required this.company, required this.side, required this.money});
  final Session session;
  final Company company;
  final BalanceSide side;
  final FarmMoney money;
  @override
  State<_DebtDialog> createState() => _DebtDialogState();
}

class _DebtDialogState extends State<_DebtDialog> {
  List<(int, String)> _parties = [];
  bool _partiesLoaded = false;
  int? _party;
  final _amount = TextEditingController(), _description = TextEditingController();
  final _reference = TextEditingController(), _notes = TextEditingController();
  String _date = localToday();
  String _entryType = 'OpeningBalance';
  bool _saving = false;
  String? _error;

  bool get _customer => widget.side.isCustomer;
  Map<String, String> get _labels => _customer ? customerDebtEntryLabel : supplierDebtEntryLabel;

  @override
  void initState() {
    super.initState();
    final idKey = _customer ? 'customerId' : 'supplierId';
    widget.session.farmClient
        .get(_customer ? '/api/Customer' : '/api/Supplier', query: {'userId': widget.session.tokens.userId ?? '', 'farmId': widget.company.farmId})
        .then((res) {
      final list = <(int, String)>[
        for (final c in rowsOf(res))
          if ((tIntOrNull(c[idKey] ?? c['id']) ?? 0) > 0 && tStr(c['name'] ?? c['customerName']).isNotEmpty)
            (tIntOrNull(c[idKey] ?? c['id'])!, tStr(c['name'] ?? c['customerName'])),
      ]..sort((a, b) => a.$2.compareTo(b.$2));
      if (mounted) setState(() => _parties = list);
    }).catchError((Object _) {}).whenComplete(() {
      if (mounted) setState(() => _partiesLoaded = true);
    });
  }

  @override
  void dispose() {
    for (final c in [_amount, _description, _reference, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  num get _value => ((num.tryParse(_amount.text) ?? 0) * 100).round() / 100;
  bool get _valid => _party != null && _value > 0 && _date.isNotEmpty && _description.text.trim().isNotEmpty;
  String get _partyName => _parties.where((c) => c.$1 == _party).firstOrNull?.$2 ?? '';

  Future<void> _save() async {
    if (!_valid || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final farmId = widget.company.farmId;
    try {
      final res = await widget.session.farmClient.post('/api/Poultry/${_debtsPath(widget.side)}?farmId=${Uri.encodeQueryComponent(farmId)}', body: {
        _customer ? 'customerId' : 'supplierId': _party,
        'amount': _value,
        'debtDate': _date,
        'entryType': _entryType,
        'description': _description.text.trim(),
        'reference': _reference.text.trim().isEmpty ? null : _reference.text.trim(),
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'farmId': farmId,
      });
      if (mounted) {
        Navigator.pop(context, {'partyName': _partyName, 'amount': _value, 'debtNumber': res is Map ? tStr(res['debtNumber']) : ''});
      }
      return;
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final word = _customer ? 'customer' : 'supplier';
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: FormDialogTitle(icon: Icons.report_outlined, color: FormColor.amber, text: 'Record $word debt'),
        content: SizedBox(
          width: 672,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _customer
                    ? 'Money a customer already owes that is not on any sale here, e.g. eggs supplied before you started using the '
                        'system. It is added to what they owe and can be paid like a sale. It is not a sale: no revenue, no stock and no cash.'
                    : 'Money you already owe a supplier that is not on any purchase here, e.g. maize bought before you started using the '
                        'system. It is added to what you owe them and is paid like a purchase. It is not a purchase: no stock, no expense and no cash.',
                style: const TextStyle(fontSize: 13, color: TColors.slate500),
              ),
              const SizedBox(height: 16),
              TintedSection(title: _customer ? 'Customer & Date' : 'Supplier & Date', color: FormColor.blue, children: [
                FormPair(
                  stackOnMobile: true,
                  FilterLabel(
                    _customer ? 'Customer *' : 'Supplier *',
                    AppSelect<int>(
                      value: _party,
                      hintText: _parties.isNotEmpty || _partiesLoaded ? 'Choose the $word' : 'Loading ${word}s…',
                      items: [for (final (id, name) in _parties) AppSelectItem(value: id, label: name)],
                      onChanged: (v) => setState(() => _party = v),
                    ),
                  ),
                  FilterLabel('Owed from *', FilterDate(value: _date, hint: 'Date', onChanged: (v) => setState(() => _date = v))),
                ),
              ]),
              const SizedBox(height: 16),
              TintedSection(title: 'Debt', color: FormColor.amber, children: [
                FormPair(
                  FilterLabel(
                    'Amount owed *',
                    AppInput(
                      controller: _amount,
                      hintText: '0.00',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  FilterLabel(
                    'Why is it owed *',
                    AppSelect<String>(
                      value: _entryType,
                      items: [for (final e in _labels.entries) AppSelectItem(value: e.key, label: e.value)],
                      onChanged: (v) => setState(() => _entryType = v ?? _entryType),
                    ),
                  ),
                ),
                FilterLabel(
                  'Description *',
                  AppInput(
                    controller: _description,
                    hintText: _customer ? 'e.g. Eggs supplied before we started using the system' : 'e.g. Maize bought before we started using the system',
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                FilterLabel('Reference', AppInput(controller: _reference, hintText: 'Optional, e.g. old ledger page or invoice')),
              ]),
              const SizedBox(height: 16),
              TintedSection(title: 'Notes', color: FormColor.slate, children: [
                AppInput(controller: _notes, hintText: 'Optional', minLines: 2, maxLines: 4),
              ]),
              if (_value > 0 && _partyName.isNotEmpty) ...[
                const SizedBox(height: 12),
                summaryBox(tone: FormColor.amber, _customer
                    ? [
                        TextSpan(text: '$_partyName will owe '),
                        TextSpan(text: widget.money(_value), style: boldSpan),
                        const TextSpan(text: ' more. No cash moves and sales are not affected.'),
                      ]
                    : [
                        TextSpan(text: 'You will owe $_partyName '),
                        TextSpan(text: widget.money(_value), style: boldSpan),
                        const TextSpan(text: ' more. No cash moves and stock is not affected.'),
                      ]),
              ],
              if (_error != null) ...[const SizedBox(height: 10), TrackerBanner.error(_error!)],
            ],
          ),
        ),
        actions: [
          FormDialogFooter(onCancel: () => Navigator.pop(context), cancelDisabled: _saving, children: [
            FilledButton(
              style: formPrimary(FormColor.amber),
              onPressed: !_valid || _saving ? null : _save,
              child: Text(_saving ? 'Recording…' : _value > 0 ? 'Record debt · ${widget.money(_value)}' : 'Record debt'),
            ),
          ]),
        ],
      ),
    );
  }
}

/// Supplier credit (370), under the table on Poultry Supplier Balances: money
/// suppliers hold for us, beside (never netted into) what we owe. Says nothing
/// when no supplier holds any.
class SupplierCreditPanel extends StatefulWidget {
  const SupplierCreditPanel({super.key, required this.session, required this.company});
  final Session session;
  final Company company;
  @override
  State<SupplierCreditPanel> createState() => _SupplierCreditPanelState();
}

class _SupplierCreditPanelState extends State<SupplierCreditPanel> {
  List<Map> _rows = [];
  bool _loaded = false;
  FarmMoney _money = const FarmMoney();

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _money = m);
    });
    widget.session.farmClient.get('/api/Poultry/supplier-credits', query: {'farmId': widget.company.farmId}).then((res) {
      if (mounted) setState(() => _rows = [for (final r in rowsOf(res)) if (tNum(r['availableCredit']) > 0) r]);
    }).catchError((Object _) {
      if (mounted) setState(() => _rows = []);
    }).whenComplete(() {
      if (mounted) setState(() => _loaded = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _rows.isEmpty) return const SizedBox.shrink();
    final total = _rows.fold<num>(0, (t, r) => t + tNum(r['availableCredit']));
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.blue200), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.savings_outlined, size: 16, color: TColors.blue600),
          const SizedBox(width: 8),
          const Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: 'Supplier credit', style: TextStyle(fontWeight: FontWeight.w600, color: TColors.slate900)),
                TextSpan(text: ' — money suppliers are holding for us, not on any purchase', style: TextStyle(color: TColors.slate500)),
              ]),
              style: TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${_money(total)} held', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: creditBlue700)),
            InkWell(
              onTap: () => openPoultryHref(context, widget.session, widget.company, '/supplier-credits', label: 'Supplier Credits'),
              child: const Text('Open Supplier Credits', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: creditBlue700)),
            ),
          ]),
        ]),
        const SizedBox(height: 10),
        for (final r in _rows)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tStr(r['supplierName']), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              Text.rich(
                TextSpan(children: [
                  const TextSpan(text: 'Credit '),
                  TextSpan(text: _money(tNum(r['availableCredit'])), style: const TextStyle(fontWeight: FontWeight.w600, color: creditBlue700)),
                  TextSpan(text: ' · We owe ${_money(tNum(r['owed']))}'),
                ]),
                style: const TextStyle(fontSize: 12, color: TColors.slate500),
              ),
            ]),
          ),
        const Text(
          'To use credit on a purchase or get it refunded, open Supplier Credits. No new money is recorded when credit is applied.',
          style: TextStyle(fontSize: 12, color: TColors.slate500),
        ),
      ]),
    );
  }
}
