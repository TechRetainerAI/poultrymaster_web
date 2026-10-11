// The Raw Materials page's dialogs: the purchase dialog
// (components/raw-materials/poultry-purchase-dialog.tsx), the item dialog with
// its financial treatment, Pay balance, and Recalculate stock
// (components/poultry/recalculate-stock-button.tsx).

import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../shared/business_dates.dart';
import '../delivery/delivery_dialogs.dart' show NumBox;
import '../money/money_widgets.dart' show formSection;
import '../reports/report_format.dart';
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull, loc;
import '../trackers/tracker_widgets.dart';

// ------------------------------------------------------------ vocabulary

const rawMaterialCategories = [
  'FeedIngredient', 'FinishedFeed', 'Packaging', 'Medication', 'Vaccine', 'Bedding', 'Disinfectant', 'Equipment', 'SparePart', 'Fuel', 'Other',
];
String rawCategoryLabel(Object? c) =>
    const {'FeedIngredient': 'Feed Ingredient', 'FinishedFeed': 'Finished Feed', 'SparePart': 'Spare Part'}[tStr(c)] ?? tStr(c);

/// RAW_MATERIAL_UNITS (lib/units.ts).
const rawMaterialUnits = [
  'Bag', 'Sack', 'Tonne', 'Kilogram', 'Gram', 'Litre', 'Millilitre', 'Bottle',
  'Sachet', 'Piece', 'Pack', 'Carton', 'Box', 'Bundle', 'Dozen', 'Crate', 'Unit', 'Other',
];

/// The units, with a stored value the list does not know put first.
List<String> unitOptions([String? current]) {
  final c = (current ?? '').trim();
  return [if (c.isNotEmpty && !rawMaterialUnits.contains(c)) c, ...rawMaterialUnits];
}

const rawPaymentMethods = ['Cash', 'MoMo', 'Bank', 'Credit'];

// lib/poultry/cost-recognition.ts
const expenseWhenPurchased = 'EXPENSE_WHEN_PURCHASED', expenseWhenConsumed = 'EXPENSE_WHEN_CONSUMED';
String methodShortLabel(Object? m) => tStr(m) == expenseWhenConsumed ? 'On use' : 'On purchase';
String methodLabel(Object? m) => tStr(m) == expenseWhenConsumed ? 'Expense when consumed' : 'Expense when purchased';
const methodHelp = {
  expenseWhenPurchased:
      'The purchase cost is recognised in Profit & Loss straight away. Inventory quantity is still tracked, and using the item later does not create another expense.',
  expenseWhenConsumed: 'The purchase is held as inventory value first. The cost reaches Profit & Loss later, as the item is used.',
};
const changeWarning =
    'This applies to new purchases from now on. Purchases already recorded keep the treatment they were created with, so past reports do not change.';
const deferredActiveNote =
    'A deferred purchase holds its cost as inventory value and reaches Profit & Loss as you record usage of the stock. Feed production carries the cost into the feed it makes, so nothing is expensed twice.';
const deferredInventoryTooltip = 'What this stock still owes Profit & Loss. It is charged as you record usage.';
const expensedAtPurchaseTooltip =
    'This stock was charged to Profit & Loss when it was bought. Using it reduces the quantity but adds no new expense.';
const operationalValueTooltip = 'What the stock on hand cost. This is what the inventory is worth, whichever way its cost was recognised.';

String costRecognitionGroup(Object? category) => switch (tStr(category).trim().toUpperCase()) {
      'FEEDINGREDIENT' || 'FINISHEDFEED' || 'GRAIN' => 'Feed',
      'MEDICATION' => 'Medication',
      _ => 'Unconfigured',
    };

typedef FarmCostDefaults = ({String feed, String medication});

String farmDefaultFor(Object? category, FarmCostDefaults d) => switch (costRecognitionGroup(category)) {
      'Feed' => d.feed,
      'Medication' => d.medication,
      _ => expenseWhenPurchased,
    };

({String method, String source, String farmDefault}) effectiveCostRecognition(String? override, Object? category, FarmCostDefaults d) {
  final fd = farmDefaultFor(category, d);
  return override != null && override.isNotEmpty
      ? (method: override, source: 'ItemOverride', farmDefault: fd)
      : (method: fd, source: 'FarmDefault', farmDefault: fd);
}

const usageMethodCategories = ['FeedIngredient', 'FinishedFeed', 'Medication'];
const usageMethodOptions = [('FIFO', 'First bought, first used'), ('LIFO', 'Last bought, first used'), ('HIFO', 'Highest cost, first used')];

Widget _cell(String label, Widget child, {String? hint}) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        if (label.isNotEmpty) ...[
          Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate700)),
          const SizedBox(height: 6),
        ],
        child,
        if (hint != null) ...[const SizedBox(height: 4), Text(hint, style: const TextStyle(fontSize: 12, color: TColors.slate500))],
      ]),
    );

Widget _readOnly(String text) => Container(
      height: 44,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: TColors.slate100, border: Border.all(color: TColors.slate300), borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.slate600)),
    );

Widget _switchRow(String title, String hint, bool value, ValueChanged<bool> on) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: TColors.slate50, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate700)),
            Text(hint, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          ]),
        ),
        Switch(value: value, onChanged: on),
      ]),
    );

const _indigo = Color(0xFF4F46E5), _blue = Color(0xFF2563EB), _amber = Color(0xFFD97706), _slate = Color(0xFF475569);
const _emerald = Color(0xFF059669);

// ------------------------------------------------------------ purchase

class RawPurchaseDialog extends StatefulWidget {
  const RawPurchaseDialog({
    super.key,
    required this.session,
    required this.company,
    required this.items,
    required this.cashAccounts,
    required this.money,
    this.editing,
    this.defaultItemId,
    this.defaultQuantity,
    this.defaultCashAccountId,
  });
  final Session session;
  final Company company;
  final List<Map> items, cashAccounts;
  final FarmMoney money;
  final Map? editing;
  final int? defaultItemId, defaultCashAccountId;
  final num? defaultQuantity;
  @override
  State<RawPurchaseDialog> createState() => _RawPurchaseDialogState();
}

class _RawPurchaseDialogState extends State<RawPurchaseDialog> {
  int _item = 0, _account = 0;
  String _supplier = '', _date = DateTime.now().toUtc().toIso8601String().substring(0, 10), _purchaseUnit = '', _prodUnit = '';
  String _method = 'Cash', _receipt = '', _notes = '';
  num _qty = 0, _unitCost = 0, _total = 0, _per = 1, _paid = 0;
  bool _manualProd = false, _manualPurchase = false, _paidTouched = false, _saving = false;

  Map? _itemOf(int id) => widget.items.where((i) => tIntOrNull(i['poultryRawMaterialItemId']) == id).firstOrNull;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _paidTouched = e != null;
    if (e != null) {
      _item = tIntOrNull(e['poultryRawMaterialItemId']) ?? 0;
      _supplier = tStr(e['supplierName']);
      final d = tStr(e['purchaseDate']).split('T').first;
      if (d.isNotEmpty) _date = d;
      _qty = tNum(e['quantity']);
      _unitCost = tNum(e['unitCost']);
      _total = tNum(e['totalCost']);
      _purchaseUnit = tStr(e['unitOfMeasure']);
      _prodUnit = tStr(e['productionUnit']);
      _per = e['productionUnitsPerPurchaseUnit'] != null ? tNum(e['productionUnitsPerPurchaseUnit']) : 1;
      _method = tStr(e['paymentMethod']).isEmpty ? 'Cash' : tStr(e['paymentMethod']);
      _account = tIntOrNull(e['poultryCashAccountId']) ?? 0;
      _paid = tNum(e['amountPaid']);
      _receipt = tStr(e['receiptUrl']);
      _notes = tStr(e['notes']);
    } else {
      final seed = widget.defaultItemId != null ? _itemOf(widget.defaultItemId!) : null;
      _account = widget.defaultCashAccountId ?? 0;
      _item = tIntOrNull(seed?['poultryRawMaterialItemId']) ?? 0;
      _purchaseUnit = tStr(seed?['purchaseUnitOfMeasure']).isNotEmpty ? tStr(seed?['purchaseUnitOfMeasure']) : tStr(seed?['unitOfMeasure']);
      _prodUnit = tStr(seed?['unitOfMeasure']);
      _qty = (widget.defaultQuantity ?? 0) > 0 ? widget.defaultQuantity! : 0;
      _autoPaid();
    }
  }

  /// Until the user types an amount, it follows the total (nothing on Credit).
  void _autoPaid() {
    if (_paidTouched) return;
    _paid = _method == 'Credit' ? 0 : double.parse(_total.toStringAsFixed(2));
  }

  void _set(VoidCallback f) => setState(() {
        f();
        _autoPaid();
      });

  Future<void> _save() async {
    if (_saving) return;
    if (_item == 0) {
      trackerToast(context, 'Pick a raw material item', error: true);
      return;
    }
    if (_qty <= 0) {
      trackerToast(context, 'Quantity must be greater than 0', error: true);
      return;
    }
    final total = _total > 0 ? _total : _qty * _unitCost;
    final payload = <String, Object?>{
      'poultryRawMaterialItemId': _item,
      'supplierName': _supplier.isEmpty ? null : _supplier,
      'purchaseDate': _date,
      'quantity': _qty,
      'unitCost': _qty > 0 ? double.parse((total / _qty).toStringAsFixed(4)) : _unitCost,
      'totalCost': total,
      'productionUnit': _prodUnit.isEmpty ? null : _prodUnit,
      'productionUnitsPerPurchaseUnit': _per == 0 ? null : _per,
      'paymentMethod': _method,
      'poultryCashAccountId': _account == 0 ? null : _account,
      'amountPaid': _paid,
      'receiptUrl': _receipt.isEmpty ? null : _receipt,
      'notes': _notes.isEmpty ? null : _notes,
      'farmId': widget.company.farmId,
    };
    setState(() => _saving = true);
    final e = widget.editing;
    try {
      if (e != null) {
        final id = tStr(e['poultryRawMaterialPurchaseId']);
        await widget.session.farmClient.put('/api/Poultry/raw-material-purchases/$id', body: {...payload, 'poultryRawMaterialPurchaseId': int.tryParse(id)});
      } else {
        await widget.session.farmClient.post('/api/Poultry/raw-material-purchases',
            body: {...payload, 'createdBy': widget.session.tokens.userId ?? ''});
      }
      if (!mounted) return;
      trackerToast(context, e != null ? 'Purchase updated' : 'Purchase recorded');
      Navigator.pop(context, true);
      return;
    } on ApiException catch (ex) {
      if (mounted) trackerToast(context, 'Save failed', description: ex.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final fmt = widget.money;
    final qty = _qty;
    final total = _total;
    final unitCost = qty > 0 ? total / qty : 0;
    final prodQty = qty * _per;
    final prodUnitCost = prodQty > 0 ? total / prodQty : 0;
    final sel = _itemOf(_item);
    final pLabel = _purchaseUnit.isNotEmpty ? _purchaseUnit : (tStr(sel?['unitOfMeasure']).isNotEmpty ? tStr(sel?['unitOfMeasure']) : 'unit');
    double r(num v, int d) => double.parse(v.toStringAsFixed(d));

    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.close), onPressed: _saving ? null : () => Navigator.pop(context, false)),
          title: Text(widget.editing != null ? 'Edit purchase' : 'New raw material purchase'),
        ),
        body: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
          formSection('Item, Supplier & Date', _indigo, [
            _cell(
              'Raw material item *',
              AppSelect<int>(
                value: _item == 0 ? null : _item,
                hintText: 'Pick item',
                items: [
                  for (final i in widget.items)
                    if (i['isActive'] == true)
                      AppSelectItem(
                        value: tIntOrNull(i['poultryRawMaterialItemId']) ?? 0,
                        label: '${tStr(i['itemName'])}${tStr(i['unitOfMeasure']).isNotEmpty ? ' (${tStr(i['unitOfMeasure'])})' : ''}',
                      ),
                ],
                onChanged: (v) => _set(() {
                  _item = v ?? 0;
                  final it = _itemOf(_item);
                  final pu = tStr(it?['purchaseUnitOfMeasure']).isNotEmpty ? tStr(it?['purchaseUnitOfMeasure']) : tStr(it?['unitOfMeasure']);
                  if (pu.isNotEmpty) _purchaseUnit = pu;
                  if (tStr(it?['unitOfMeasure']).isNotEmpty) _prodUnit = tStr(it?['unitOfMeasure']);
                }),
              ),
            ),
            _cell('Supplier', AppInput(initialValue: _supplier, hintText: 'Supplier name', onChanged: (v) => _supplier = v)),
            _cell(
              'Purchase date',
              AppDateField(value: businessDateAsDateTime(_date), onChanged: (v) => setState(() => _date = v == null ? '' : isoDay(v))),
            ),
            _cell(
              'Payment method',
              AppSelect<String>(
                value: _method,
                items: [for (final m in rawPaymentMethods) AppSelectItem(value: m, label: m)],
                onChanged: (v) => _set(() => _method = v ?? _method),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          formSection('Purchase Quantity & Production Costing', _blue, [
            _cell(
              'Purchase unit *',
              AppSelect<String>(
                value: _purchaseUnit.isEmpty ? null : _purchaseUnit,
                hintText: 'Pick unit',
                items: [for (final u in unitOptions(_purchaseUnit)) AppSelectItem(value: u, label: u)],
                onChanged: (v) => setState(() => _purchaseUnit = v ?? ''),
              ),
            ),
            _cell('Purchase quantity ($pLabel) *', NumBox(value: _qty, decimal: true, onChanged: (v) => _set(() => _qty = v))),
            _switchRow('Enter purchase unit cost manually', 'Turn off the auto-calculation and type the purchase unit cost yourself.',
                _manualPurchase, (v) => setState(() => _manualPurchase = v)),
            _cell('Total purchase cost *',
                NumBox(value: r(total, 2), decimal: true, enabled: !_manualPurchase, onChanged: (v) => _set(() => _total = v))),
            if (_manualPurchase)
              _cell(
                'Purchase unit cost (per $pLabel)',
                NumBox(value: r(unitCost, 4), decimal: true, onChanged: (c) => _set(() {
                      if (qty > 0) _total = r(c * qty, 2);
                    })),
                hint: 'Manual — sets the total for you',
              )
            else
              _cell('Purchase unit cost (auto)', _readOnly('${fmt(unitCost)} per $pLabel')),
          ]),
          const SizedBox(height: 12),
          formSection('Production Conversion', _indigo, [
            _switchRow('Enter production cost manually', 'Turn off the auto-calculation and type the production-level unit cost yourself.',
                _manualProd, (v) => setState(() => _manualProd = v)),
            _cell(
              'Production unit',
              AppSelect<String>(
                value: _prodUnit.isEmpty ? null : _prodUnit,
                hintText: 'Pick unit',
                items: [for (final u in unitOptions(_prodUnit)) AppSelectItem(value: u, label: u)],
                onChanged: (v) => setState(() => _prodUnit = v ?? ''),
              ),
            ),
            _cell('Production units per purchase unit', NumBox(value: _per, decimal: true, onChanged: (v) => setState(() => _per = v))),
            _cell(
              'Production-level quantity',
              NumBox(value: r(prodQty, 4), decimal: true, onChanged: (v) => setState(() {
                    if (qty > 0) _per = r(v / qty, 8);
                  })),
              hint: 'Editable — sets units per purchase unit',
            ),
            if (_manualProd)
              _cell(
                'Production-level unit cost',
                NumBox(value: r(prodUnitCost, 4), decimal: true, onChanged: (c) => setState(() {
                      if (c > 0 && qty > 0 && total > 0) _per = r(total / (c * qty), 8);
                    })),
                hint: 'Manual — sets the conversion for you',
              )
            else
              _cell('Production-level unit cost (auto)', _readOnly('${fmt(prodUnitCost)}${_prodUnit.isNotEmpty ? ' per $_prodUnit' : ''}')),
            const Text.rich(
              TextSpan(children: [
                TextSpan(text: 'If you buy and use the same unit, set '),
                TextSpan(text: 'Production units per purchase unit = 1', style: TextStyle(fontWeight: FontWeight.w500)),
                TextSpan(text: ' — the production figures then match the purchase figures.'),
              ]),
              style: TextStyle(fontSize: 12, color: TColors.slate500),
            ),
          ]),
          const SizedBox(height: 12),
          formSection('Payment', _amber, [
            _cell('Amount paid', NumBox(value: _paid, decimal: true, onChanged: (v) => setState(() {
                  _paidTouched = true;
                  _paid = v;
                }))),
            _cell(
              'Pay from cash account',
              AppSelect<int>(
                value: _account,
                hintText: 'None (no cash movement)',
                items: [
                  const AppSelectItem(value: 0, label: 'None (no cash movement)'),
                  for (final a in widget.cashAccounts)
                    AppSelectItem(
                      value: tIntOrNull(a['poultryCashAccountId']) ?? 0,
                      label: '${tStr(a['accountName'])} (${fmt(tNum(a['currentBalance']))})',
                    ),
                ],
                onChanged: (v) => setState(() => _account = v ?? 0),
              ),
            ),
            _cell('Balance (auto)', _readOnly(fmt((total - _paid) > 0 ? total - _paid : 0))),
            const Text("Choosing a cash account posts a cash-out for the amount paid and reduces that account's balance.",
                style: TextStyle(fontSize: 12, color: TColors.slate500)),
          ]),
          const SizedBox(height: 12),
          formSection('Notes', _slate, [
            _cell('Notes', AppInput(initialValue: _notes, minLines: 3, maxLines: 5, hintText: 'Optional notes about this purchase', onChanged: (v) => _notes = v)),
          ]),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
            const SizedBox(width: 8),
            FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save')),
          ]),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------ item

class RawItemDialog extends StatefulWidget {
  const RawItemDialog({super.key, required this.session, required this.company, this.editing, required this.farmDefaults});
  final Session session;
  final Company company;
  final Map? editing;
  final FarmCostDefaults farmDefaults;
  @override
  State<RawItemDialog> createState() => _RawItemDialogState();
}

class _RawItemDialogState extends State<RawItemDialog> {
  late final Map? _e = widget.editing;
  late final _name = TextEditingController(text: tStr(_e?['itemName']));
  late String _category = _e == null ? 'FeedIngredient' : tStr(_e['category']);
  late String _unit = tStr(_e?['unitOfMeasure']), _purchaseUnit = tStr(_e?['purchaseUnitOfMeasure']);
  late num _minAlert = tNum(_e?['minimumStockAlert']);
  late final bool _active = _e == null ? true : _e['isActive'] == true;
  late String? _notes = _e?['notes'] == null ? null : tStr(_e?['notes']);
  late String _usage = tStr(_e?['usageMethod']).isEmpty ? 'FIFO' : tStr(_e?['usageMethod']);
  late String? _override = tStr(_e?['costRecognitionOverride']).isEmpty ? null : tStr(_e?['costRecognitionOverride']);
  late final String? _origUsage = _e == null ? null : _usage;
  late final String? _origOverride = _override;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      trackerToast(context, 'Item name is required', error: true);
      return;
    }
    setState(() => _saving = true);
    final body = <String, Object?>{
      'itemName': _name.text,
      'category': _category,
      'unitOfMeasure': _unit,
      'purchaseUnitOfMeasure': _purchaseUnit.trim().isEmpty ? null : _purchaseUnit.trim(),
      'minimumStockAlert': _minAlert,
      'isActive': _active,
      'notes': _notes,
      'usageMethod': _usage,
      'costRecognitionOverride': _override,
      'setCostRecognitionOverride': true,
      'farmId': widget.company.farmId,
    };
    try {
      if (_e != null) {
        final id = tIntOrNull(_e['poultryRawMaterialItemId']);
        await widget.session.farmClient.put('/api/Poultry/raw-material-items/$id', body: {...body, 'poultryRawMaterialItemId': id});
      } else {
        await widget.session.farmClient.post('/api/Poultry/raw-material-items', body: body);
      }
      if (!mounted) return;
      trackerToast(context, _e != null ? 'Item updated' : 'Item added');
      Navigator.pop(context, true);
      return;
    } on ApiException catch (ex) {
      if (mounted) trackerToast(context, 'Save failed', description: ex.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  Widget _radioCard(bool selected, VoidCallback onTap, String title, String hint) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: selected ? TColors.emerald50 : Colors.white,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: selected ? TColors.emerald600 : TColors.slate200),
            borderRadius: BorderRadius.circular(6),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 18, color: TColors.emerald600),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: TColors.slate800)),
                    Text(hint, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      );

  Widget _warn(Widget text) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: TColors.amber50, border: Border.all(color: TColors.amber300), borderRadius: BorderRadius.circular(6)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.warning_amber_outlined, size: 16, color: TColors.amber600),
          const SizedBox(width: 8),
          Expanded(child: DefaultTextStyle.merge(style: const TextStyle(fontSize: 12, color: TColors.amber800), child: text)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final group = costRecognitionGroup(_category);
    final eff = effectiveCostRecognition(_override, _category, widget.farmDefaults);
    final usageChanged = _e != null && _origUsage != null && _usage != _origUsage;
    final overrideChanged = _e != null && _override != _origOverride;
    final choices = <(String?, String)>[(null, 'Use farm default'), (expenseWhenPurchased, methodLabel(expenseWhenPurchased)), (expenseWhenConsumed, methodLabel(expenseWhenConsumed))];

    return AlertDialog(
      scrollable: true,
      title: Text(_e != null ? 'Edit item' : 'New raw material item'),
      content: SizedBox(
        width: 520,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          formSection('Item details', _blue, [
            _cell('Item name *', AppInput(controller: _name)),
            _cell(
              'Category *',
              AppSelect<String>(
                value: _category,
                items: [for (final c in rawMaterialCategories) AppSelectItem(value: c, label: rawCategoryLabel(c))],
                onChanged: (v) => setState(() => _category = v ?? _category),
              ),
            ),
            _cell(
              'Production unit of measure',
              AppSelect<String>(
                value: _unit.isEmpty ? null : _unit,
                hintText: 'Pick unit',
                items: [for (final u in unitOptions(_unit)) AppSelectItem(value: u, label: u)],
                onChanged: (v) => setState(() => _unit = v ?? ''),
              ),
              hint: "How it's stocked & consumed",
            ),
            _cell(
              'Purchase unit of measure',
              AppSelect<String>(
                value: _purchaseUnit.isEmpty ? null : _purchaseUnit,
                hintText: 'Same as production unit',
                items: [for (final u in unitOptions(_purchaseUnit)) AppSelectItem(value: u, label: u)],
                onChanged: (v) => setState(() => _purchaseUnit = v ?? ''),
              ),
              hint: "How it's bought — defaults to the production unit",
            ),
            _cell('Low-stock alert at', NumBox(value: _minAlert, decimal: true, onChanged: (v) => _minAlert = v)),
            if (usageMethodCategories.contains(_category))
              _cell(
                'Order of item usage',
                Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final (v, hint) in usageMethodOptions) _radioCard(_usage == v, () => setState(() => _usage = v), v, hint),
                  if (usageChanged)
                    _warn(const Text.rich(TextSpan(children: [
                      TextSpan(text: 'This is a big change.', style: TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(
                          text: " It won't touch anything already recorded as used — but from now on, this item will draw from a different "
                              'batch first. If this item already has purchases or usage history, double-check this is really what you want before saving.'),
                    ]))),
                  const SizedBox(height: 4),
                  const Text('Decides which purchase batch gets used first when this item is picked as "used" on a production record.',
                      style: TextStyle(fontSize: 12, color: TColors.slate500)),
                ]),
              ),
            _cell('Notes', AppInput(initialValue: _notes ?? '', minLines: 3, maxLines: 5, hintText: 'Optional notes about this item',
                onChanged: (v) => _notes = v.isEmpty ? null : v)),
          ]),
          const SizedBox(height: 12),
          formSection('Financial treatment', _emerald, [
            _cell(
              'Cost recognition',
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final (v, label) in choices)
                  _radioCard(
                    _override == v,
                    () => setState(() => _override = v),
                    label,
                    v == null
                        ? (group == 'Unconfigured'
                            ? '${rawCategoryLabel(_category)} does not follow either farm setting, so this stays on ${methodLabel(expenseWhenPurchased).toLowerCase()}.'
                            : 'The farm setting for ${group == 'Feed' ? 'feed & raw materials' : 'medication'} — currently ${methodLabel(eff.farmDefault).toLowerCase()}.')
                        : methodHelp[v]!,
                  ),
                const SizedBox(height: 4),
                Text.rich(TextSpan(children: [
                  const TextSpan(text: 'Effective for this item: '),
                  TextSpan(text: methodLabel(eff.method), style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: eff.source == 'ItemOverride' ? ' (overriding the farm default)' : ' (from the farm default)'),
                ]), style: const TextStyle(fontSize: 12, color: TColors.slate600)),
                if (overrideChanged) _warn(const Text(changeWarning)),
                if (eff.method == expenseWhenConsumed) _warn(const Text(deferredActiveNote)),
              ]),
            ),
          ]),
        ]),
      ),
      actions: [
        OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save')),
      ],
    );
  }
}

// ------------------------------------------------------------ pay balance

class RawPayBalanceDialog extends StatefulWidget {
  const RawPayBalanceDialog({super.key, required this.session, required this.company, required this.purchase, required this.money});
  final Session session;
  final Company company;
  final Map purchase;
  final FarmMoney money;
  @override
  State<RawPayBalanceDialog> createState() => _RawPayBalanceDialogState();
}

class _RawPayBalanceDialogState extends State<RawPayBalanceDialog> {
  late num _amount = tNum(widget.purchase['balance']);
  String _method = 'Cash', _date = DateTime.now().toUtc().toIso8601String().substring(0, 10);
  bool _saving = false;

  Future<void> _submit() async {
    final outstanding = tNum(widget.purchase['balance']);
    if (_amount <= 0) {
      trackerToast(context, 'Enter an amount greater than 0', error: true);
      return;
    }
    if (_amount > outstanding) {
      trackerToast(context, 'Amount exceeds the outstanding balance (${widget.money(outstanding)})', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.session.farmClient.post('/api/Poultry/raw-material-purchases/${widget.purchase['poultryRawMaterialPurchaseId']}/pay-balance', body: {
        'farmId': widget.company.farmId,
        'amount': _amount,
        'paymentMethod': _method,
        'paymentDate': _date.isEmpty ? null : _date,
        'createdBy': widget.session.tokens.userId ?? '',
      });
      if (!mounted) return;
      trackerToast(context, 'Balance payment recorded');
      Navigator.pop(context, true);
      return;
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not record payment', description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: const Text('Pay balance'),
        content: SizedBox(
          width: 420,
          child: formSection('Outstanding: ${widget.money(tNum(widget.purchase['balance']))}', _emerald, [
            _cell('Amount', NumBox(value: _amount, decimal: true, onChanged: (v) => _amount = v)),
            _cell(
              'Method',
              AppSelect<String>(
                value: _method,
                items: [for (final m in rawPaymentMethods) if (m != 'Credit') AppSelectItem(value: m, label: m)],
                onChanged: (v) => setState(() => _method = v ?? _method),
              ),
            ),
            _cell('Date', AppDateField(value: businessDateAsDateTime(_date), onChanged: (v) => setState(() => _date = v == null ? '' : isoDay(v)))),
          ]),
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: _saving ? null : _submit, child: Text(_saving ? 'Saving…' : 'Record payment')),
        ],
      );
}

// ------------------------------------------------------------ recalculate stock

class RecalculateStockDialog extends StatefulWidget {
  const RecalculateStockDialog({super.key, required this.session, required this.company, required this.items});
  final Session session;
  final Company company;
  final List<Map> items;
  @override
  State<RecalculateStockDialog> createState() => _RecalculateStockDialogState();
}

class _RecalculateStockDialogState extends State<RecalculateStockDialog> {
  String _target = 'all';
  bool _busy = false, _ran = false;
  List<Map>? _result;

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      final r = await widget.session.farmClient.post('/api/Poultry/raw-material-items/recalculate-stock',
          body: const {}, query: {'farmId': widget.company.farmId, if (_target != 'all') 'itemId': _target});
      final rows = rowsOf(r);
      final changed = [for (final x in rows) if (tNum(x['delta']) != 0) x];
      if (!mounted) return;
      setState(() => _result = changed);
      _ran = true;
      trackerToast(context, 'Stock recalculated', description: '${rows.length} item(s) checked, ${changed.length} updated.');
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Recalculate failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final res = _result;
    return AlertDialog(
      scrollable: true,
      title: const Text('Recalculate raw-material stock'),
      content: SizedBox(
        width: 480,
        child: res == null
            ? Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text.rich(
                  TextSpan(children: [
                    TextSpan(text: 'Recompute stock from history —'),
                    TextSpan(
                        text: ' total purchased (in production units) − used in production + manual adjustments',
                        style: TextStyle(fontWeight: FontWeight.w500)),
                    TextSpan(text: ', floored at 0. Finished products are not affected.'),
                  ]),
                  style: TextStyle(fontSize: 14, color: TColors.slate600),
                ),
                const SizedBox(height: 12),
                FilterLabel(
                  'Item to recalculate',
                  AppSelect<String>(
                    value: _target,
                    items: [
                      const AppSelectItem(value: 'all', label: 'All raw materials & supplies'),
                      for (final i in widget.items)
                        if (i['isActive'] == true)
                          AppSelectItem(
                            value: tStr(i['poultryRawMaterialItemId']),
                            label: '${tStr(i['itemName'])}${tStr(i['category']).isNotEmpty ? ' — ${tStr(i['category'])}' : ''}',
                          ),
                    ],
                    onChanged: (v) => setState(() => _target = v ?? 'all'),
                  ),
                ),
              ])
            : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (res.isEmpty)
                  const Text('Everything already matched — no stock figures needed changing.', style: TextStyle(fontSize: 14, color: TColors.slate600))
                else ...[
                  Text('${res.length} item(s) updated:', style: const TextStyle(fontSize: 14, color: TColors.slate600)),
                  const SizedBox(height: 8),
                  TrackerTable(
                    columns: const [TCol('Item', width: 170), TCol('Was', right: true, width: 80), TCol('Now', right: true, width: 80), TCol('Change', right: true, width: 80)],
                    rows: [
                      for (final x in res)
                        [
                          Text.rich(TextSpan(children: [
                            TextSpan(text: tStr(x['itemName']), style: const TextStyle(fontWeight: FontWeight.w500)),
                            if (tStr(x['category']).isNotEmpty) TextSpan(text: ' — ${tStr(x['category'])}', style: const TextStyle(color: TColors.slate400)),
                          ])),
                          cellText(loc(tNum(x['oldQuantity']))),
                          cellText(loc(tNum(x['newQuantity']))),
                          cellText('${tNum(x['delta']) > 0 ? '+' : ''}${loc(tNum(x['delta']))}',
                              color: tNum(x['delta']) < 0 ? TColors.red600 : TColors.green700),
                        ],
                    ],
                  ),
                ],
              ]),
      ),
      actions: res == null
          ? [
              OutlinedButton(onPressed: () => Navigator.pop(context, _ran), child: const Text('Cancel')),
              FilledButton(onPressed: _busy ? null : _run, child: Text(_busy ? 'Working…' : 'Recalculate')),
            ]
          : [
              OutlinedButton(onPressed: () => setState(() => _result = null), child: const Text('Recalculate again')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Done')),
            ],
    );
  }
}
