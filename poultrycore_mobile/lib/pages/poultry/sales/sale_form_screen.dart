import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../shared/business_dates.dart';
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull, loc;
import '../trackers/tracker_widgets.dart';
import 'sales_logic.dart';

/// "Create New Sale" / "Edit Sale", as the two dialogs of `app/sales/page.tsx`.
/// The two differ exactly as the web's do: Create says "Paid now / Pay later
/// (pending)", has the Egg Size field and REQUIRES a cash account (preselecting
/// the Main Cash Account); Edit says "Paid / Pending (owed)", has no Egg Size
/// field and allows "None (no cash movement)".
///
/// Pops `true` after a successful save.
class SaleFormScreen extends StatefulWidget {
  const SaleFormScreen({
    super.key,
    required this.session,
    required this.company,
    required this.flocks,
    required this.customers,
    required this.cashAccounts,
    required this.products,
    this.editing,
  });
  final Session session;
  final Company company;
  final List<Map> flocks;
  final List<Map> customers;

  /// Active accounts only, as the page keeps them.
  final List<Map> cashAccounts;
  final List<Map> products;
  final Map? editing;

  @override
  State<SaleFormScreen> createState() => _SaleFormScreenState();
}

/// The default account a new sale is received into: "Main Cash Account", else
/// the first active one.
int? defaultCashAccountId(List<Map> accounts) {
  final main = accounts.where((a) => tStr(a['accountName']).trim().toLowerCase() == 'main cash account').firstOrNull;
  return tIntOrNull((main ?? accounts.firstOrNull)?['poultryCashAccountId']);
}

class _SaleFormScreenState extends State<SaleFormScreen> {
  late final SaleForm f;
  bool _saving = false;
  final _other = TextEditingController();
  final _otherCustomer = TextEditingController();
  final _crates = TextEditingController();
  final _loose = TextEditingController();
  final _qty = TextEditingController();
  final _price = TextEditingController();
  final _override = TextEditingController();
  final _size = TextEditingController();
  final _desc = TextEditingController();

  bool get _isEdit => widget.editing != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      f = SaleForm.fromSale(widget.editing!);
    } else {
      f = SaleForm()
        ..saleDate = isoDay(DateTime.now().toUtc())
        ..cashAccountId = defaultCashAccountId(widget.cashAccounts);
    }
    _other.text = f.productOther;
    _crates.text = '${f.crates}';
    _loose.text = '${f.looseEggs}';
    _qty.text = _jsNum(f.quantity);
    _price.text = _jsNum(f.unitPrice);
    _size.text = f.size ?? '';
    _desc.text = f.saleDescription;
  }

  @override
  void dispose() {
    for (final c in [_other, _otherCustomer, _crates, _loose, _qty, _price, _override, _size, _desc]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _jsNum(num n) => n == n.roundToDouble() ? n.toInt().toString() : '$n';

  Map? get _stockProduct => saleStockProduct(widget.products, f.product);
  num? get _available => availableStock(_stockProduct, widget.editing);
  num get _shortfall => stockShortfall(_available, f.quantity);
  String get _units => stockUnitLabel(_stockProduct);

  Future<void> _save() async {
    final userId = widget.session.tokens.userId;
    final farmId = widget.company.farmId;
    if (userId == null || userId.isEmpty || farmId.isEmpty) {
      trackerToast(context, 'Session issue',
          description: 'We could not confirm your farm or user. Please sign in again.', error: true);
      return;
    }
    final msg = f.validate(available: _available, stockUnits: _units);
    if (msg != null) {
      trackerToast(context, 'Almost there', description: msg);
      return;
    }
    if (!_isEdit && f.cashAccountId == null) {
      trackerToast(context, 'Cash account required',
          description: 'Choose which cash account this sale is received into.', error: true);
      return;
    }
    setState(() => _saving = true);
    final api = widget.session.farmClient;
    try {
      if (_isEdit) {
        await api.put('/api/Sale/${widget.editing!['saleId']}', body: f.updateBody(farmId, userId));
        if (!mounted) return;
        trackerToast(context, 'Success', description: 'Sale updated successfully');
      } else {
        final body = f.createBody(farmId, userId);
        final res = await api.post('/api/Sale', body: body);
        final newId = res is Map ? tIntOrNull(res['saleId']) : null;
        // "Paid now" settles the sale: the create posts the cash-in but leaves
        // AmountPaid at 0, so the full payment is recorded straight after.
        final total = tNum(body['totalAmount']);
        if (f.paid && total > 0 && newId != null) {
          try {
            await api.post('/api/Poultry/payments', body: {
              'saleId': newId,
              'amount': total,
              'paymentMethod': f.paymentMethod.isEmpty ? 'Cash' : f.paymentMethod,
              'farmId': farmId,
              'createdBy': userId,
            });
          } on ApiException catch (e) {
            if (mounted) {
              trackerToast(context, 'Sale created — payment not recorded',
                  description: e.message.isNotEmpty ? e.message : "Use the sale's Pay action to record it manually.",
                  error: true);
            }
          }
        }
        if (!mounted) return;
        trackerToast(context, 'Success', description: 'Sale created successfully');
      }
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Error',
          description: e.message.isNotEmpty ? e.message : (_isEdit ? 'Failed to update sale' : 'Failed to create sale'),
          error: true);
    }
  }

  // ------------------------------------------------------------ build

  Widget _section(String title, Color band, Color bg, List<Widget> children, {Color border = TColors.slate200}) =>
      Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            color: band,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 14), children[i]],
            ]),
          ),
        ]),
      );

  Widget _label(String text, Widget child, {Widget? trailing}) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Flexible(
                child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: TColors.slate900))),
            if (trailing != null) ...[const SizedBox(width: 6), trailing],
          ]),
          const SizedBox(height: 6),
          child,
        ],
      );

  Widget _num(TextEditingController c, ValueChanged<String> on, {bool decimal = false, String hint = '0', bool enabled = true}) =>
      AppInput(
        controller: c,
        hintText: hint,
        enabled: enabled,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        inputFormatters: [FilteringTextInputFormatter.allow(decimal ? RegExp(r'^\d*\.?\d*') : RegExp(r'^\d*'))],
        onChanged: on,
      );

  Widget _stockNotice() {
    final avail = _available;
    if (avail == null) return const SizedBox.shrink();
    final short = _shortfall;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text.rich(TextSpan(children: [
        const TextSpan(text: 'In stock: '),
        TextSpan(text: loc(avail), style: const TextStyle(fontWeight: FontWeight.w700, color: TColors.slate700)),
        TextSpan(text: ' $_units'),
      ]), style: const TextStyle(fontSize: 12, color: TColors.slate500)),
      if (short > 0) ...[
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: TColors.red50,
            border: Border.all(color: TColors.red300),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Only ${loc(avail)} $_units in stock — this sale is ${loc(short)} more than you have.',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: TColors.red700)),
            const SizedBox(height: 6),
            InkWell(
              onTap: () => setState(() => f.overrideStock = !f.overrideStock),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: f.overrideStock,
                    onChanged: (v) => setState(() => f.overrideStock = v == true),
                  ),
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Sell it anyway. Stock goes negative until the missing production, or a stock correction, is recorded.',
                    style: TextStyle(fontSize: 12, color: TColors.red700),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ],
    ]);
  }

  Widget _radio(String label, bool value) => InkWell(
        onTap: () => setState(() => f.paid = value),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Radio<bool>(value: value, visualDensity: VisualDensity.compact),
          Flexible(child: Text(label, style: const TextStyle(fontSize: 13))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final isEggs = f.isEggs;
    final sel = f.productSelectValue;
    final customerValue = f.showNewCustomerInput ? '__OTHER__' : (f.customerName.isEmpty ? null : f.customerName);
    final customerNames = <String>[];
    for (final c in widget.customers) {
      final n = tStr(c['name']);
      if (n.isNotEmpty && !customerNames.contains(n)) customerNames.add(n);
    }
    // A name not in the list (typed as "Other" earlier) shows an empty box, as
    // the web's Select does; the sale keeps the name.
    final showCustomerValue =
        customerValue == null || customerValue == '__OTHER__' || customerNames.contains(customerValue) ? customerValue : null;
    final accountItems = [
      if (_isEdit) const AppSelectItem<int?>(value: null, label: 'None (no cash movement)'),
      for (final a in widget.cashAccounts)
        AppSelectItem<int?>(
          value: tIntOrNull(a['poultryCashAccountId']),
          label: '${a['accountName']} (${tNum(a['currentBalance']).toStringAsFixed(2)})',
        ),
    ];
    final calcLoose = f.crates * 30 + f.looseEggs;

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit Sale' : 'Create New Sale')),
      body: ListView(
        // Room under the buttons so a toast never sits on top of Create Sale.
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 96),
        children: [
          Text(_isEdit ? 'Update the sale record details' : "Add a new sale record to track your farm's revenue",
              style: const TextStyle(fontSize: 13, color: TColors.slate500)),
          const SizedBox(height: 14),
          _section('Sale Details', const Color(0xFF2563EB), TColors.slate50, [
            _label(
              'Sale Date *',
              AppDateField(
                value: businessDateAsDateTime(f.saleDate),
                onChanged: (d) => setState(() => f.saleDate = d == null ? '' : isoDay(d)),
              ),
            ),
            _label(
              'Product *',
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                AppSelect<String>(
                  value: sel,
                  hintText: 'Select product',
                  items: [for (final o in saleProductOptions) AppSelectItem(value: o, label: o)],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      f.selectProduct(v);
                      _other.text = f.productOther;
                      _crates.text = '${f.crates}';
                      _loose.text = '${f.looseEggs}';
                    });
                  },
                ),
                if (sel == 'Other') ...[
                  const SizedBox(height: 8),
                  AppInput(
                    controller: _other,
                    hintText: 'Enter product name',
                    onChanged: (v) => setState(() {
                      f.productOther = v;
                      f.product = v;
                    }),
                  ),
                ],
              ]),
            ),
            _label(
              'Customer Name *',
              trailing: const Tooltip(
                triggerMode: TooltipTriggerMode.tap,
                message: 'If you cannot find the customer, please go to the customer page and create the Customer first',
                child: Icon(Icons.info_outline, size: 16, color: TColors.slate400),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                AppSelect<String>(
                  value: showCustomerValue,
                  hintText: 'Select a customer',
                  items: [
                    for (final n in customerNames) AppSelectItem(value: n, label: n),
                    const AppSelectItem(value: '__OTHER__', label: 'Other Customer'),
                  ],
                  onChanged: (v) => setState(() {
                    if (v == '__OTHER__') {
                      f.showNewCustomerInput = true;
                      f.otherCustomerName = '';
                      _otherCustomer.clear();
                      f.customerName = '';
                    } else {
                      f.showNewCustomerInput = false;
                      f.otherCustomerName = '';
                      f.customerName = v ?? '';
                    }
                  }),
                ),
                if (f.showNewCustomerInput) ...[
                  const SizedBox(height: 8),
                  AppInput(
                    controller: _otherCustomer,
                    hintText: 'Enter other customer name',
                    onChanged: (v) => setState(() {
                      f.otherCustomerName = v;
                      f.customerName = v;
                    }),
                  ),
                ],
              ]),
            ),
            _label(
              'Flock',
              AppSelect<int?>(
                value: f.flockId,
                hintText: 'Select a flock',
                items: [
                  const AppSelectItem<int?>(value: 0, label: 'All flocks'),
                  for (final fl in widget.flocks)
                    AppSelectItem<int?>(
                      value: tIntOrNull(fl['flockId']),
                      label: '${fl['name']} (${fl['quantity']} birds)${isFlockClosed(fl) ? ' · Closed' : ''}',
                      enabled: !closedFlockBlocksSale(fl, f.product, widget.editing),
                    ),
                ],
                onChanged: (v) => setState(() => f.flockId = v),
              ),
            ),
          ]),
          if (isEggs) ...[
            const SizedBox(height: 16),
            _section(
              'Egg Quantity (Crates × 30 + Loose Eggs)',
              const Color(0xFFF59E0B),
              TColors.amber50,
              border: TColors.amber200,
              [
                _label('Crates (30 eggs)', _num(_crates, (v) => setState(() => f.setCrates(int.tryParse(v) ?? 0)))),
                _label(
                  'Loose Eggs',
                  _num(_loose, (v) {
                    var l = int.tryParse(v) ?? 0;
                    setState(() => f.setLoose(l));
                  }),
                ),
                _label(
                  'Total Eggs',
                  Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: TColors.slate200),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(loc(calcLoose),
                        style: const TextStyle(fontWeight: FontWeight.w700, color: TColors.amber700)),
                  ),
                ),
                Text('Calculation: ${f.crates} crates × 30 + ${f.looseEggs} loose = ${loc(calcLoose)} eggs',
                    style: const TextStyle(fontSize: 12, color: TColors.amber600)),
                _stockNotice(),
              ],
            ),
          ],
          const SizedBox(height: 16),
          _section('Pricing', const Color(0xFF16A34A), TColors.slate50, [
            _label(
              isEggs ? 'Quantity (In crates) *' : 'Quantity *',
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                isEggs
                    ? AppInput(
                        key: ValueKey('eggqty${f.quantity}'),
                        initialValue: eggCratesEquivalent(f.quantity),
                        enabled: false,
                      )
                    : _num(_qty, (v) => setState(() => f.quantity = num.tryParse(v) ?? 0)),
                const SizedBox(height: 6),
                if (isEggs)
                  Text('${loc(f.quantity)} eggs total, from the crates and loose eggs above',
                      style: const TextStyle(fontSize: 12, color: TColors.slate500))
                else
                  _stockNotice(),
              ]),
            ),
            _label(
              isEggs ? 'Unit Price Per Crate *' : 'Unit Price *',
              _num(_price, (v) => setState(() => f.unitPrice = num.tryParse(v) ?? 0), decimal: true, hint: '0.00'),
            ),
            _label(
              'Calculated Amount',
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                AppInput(key: ValueKey('calc${f.calculated}'), initialValue: _jsNum(f.calculated), enabled: false),
                if (isEggs && f.crates + f.looseEggs > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${f.crates} crate${f.crates == 1 ? '' : 's'}${f.looseEggs > 0 ? ' + ${f.looseEggs} loose' : ''} priced as '
                    '${((f.crates * 30 + f.looseEggs) / 30).toStringAsFixed(2)} crates'
                    '${f.looseEggs > 0 ? ' — loose eggs charged pro rata' : ''}.',
                    style: const TextStyle(fontSize: 12, color: TColors.slate500),
                  ),
                ],
              ]),
            ),
            _label(
              'Override Amount',
              _num(_override, (v) => setState(() => f.overrideAmount = v.isEmpty ? null : num.tryParse(v)),
                  decimal: true, hint: 'Leave empty to use calculated'),
            ),
            _label(
              'Payment Method *',
              AppSelect<String>(
                value: f.paymentMethod.isEmpty || !salePaymentMethods.contains(f.paymentMethod) ? null : f.paymentMethod,
                hintText: 'Select payment method',
                items: [for (final m in salePaymentMethods) AppSelectItem(value: m, label: m)],
                onChanged: (v) => setState(() => f.paymentMethod = v ?? ''),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: TColors.slate200),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Payment status', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                RadioGroup<bool>(
                  groupValue: f.paid,
                  onChanged: (v) => setState(() => f.paid = v ?? true),
                  child: Wrap(spacing: 8, children: [
                    _radio(_isEdit ? 'Paid' : 'Paid now', true),
                    _radio(_isEdit ? 'Pending (owed)' : 'Pay later (pending)', false),
                  ]),
                ),
                Text(
                  _isEdit
                      ? 'Choose “Pending” if this sale is still owed by the customer.'
                      : (f.paid == false
                          ? 'Records the full amount as owed — record payments later.'
                          : 'Records the sale as fully paid and posts a cash-in.'),
                  style: const TextStyle(fontSize: 12, color: TColors.slate500),
                ),
              ]),
            ),
            if (!_isEdit)
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: TColors.slate200),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Text('Egg Size (optional)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  // The web's <datalist>: free text, with suggestions.
                  Autocomplete<String>(
                    initialValue: TextEditingValue(text: f.size ?? ''),
                    optionsBuilder: (v) => eggSizeSuggestions
                        .where((s) => s.toLowerCase().contains(v.text.toLowerCase())),
                    onSelected: (v) => setState(() => f.size = v),
                    fieldViewBuilder: (context, controller, focus, onSubmit) => TextFormField(
                      controller: controller,
                      focusNode: focus,
                      decoration: const InputDecoration(hintText: 'e.g. Inside, Tee, Serum'),
                      onChanged: (v) => f.size = v,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text('Used by the weekly report’s “Egg Sales by Size” card.',
                      style: TextStyle(fontSize: 12, color: TColors.slate500)),
                ]),
              ),
            _label(
              _isEdit ? 'Receive into cash account' : 'Receive into cash account *',
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                AppSelect<int?>(
                  value: accountItems.any((i) => i.value == f.cashAccountId) ? f.cashAccountId : null,
                  hintText: 'Select a cash account',
                  items: accountItems,
                  onChanged: (v) => setState(() => f.cashAccountId = v),
                ),
                const SizedBox(height: 6),
                const Text('Posts a cash-in and increases the account balance when the sale is marked paid.',
                    style: TextStyle(fontSize: 12, color: TColors.slate500)),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          _label(
            'Description',
            AppInput(
              controller: _desc,
              minLines: 3,
              maxLines: 6,
              hintText: 'Additional notes about this sale',
              onChanged: (v) => f.saleDescription = v,
            ),
          ),
          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: TColors.red600, minimumSize: const Size.fromHeight(44)),
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: TColors.blue600, minimumSize: const Size.fromHeight(44)),
            onPressed: _saving ? null : _save,
            child: Text(_isEdit ? 'Update Sale' : 'Create Sale'),
          ),
        ],
      ),
    );
  }
}
