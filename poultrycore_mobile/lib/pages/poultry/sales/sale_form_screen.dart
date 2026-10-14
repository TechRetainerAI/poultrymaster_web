import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../shared/business_dates.dart';
import '../reports/report_format.dart';
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../trackers/tracker_widgets.dart';
import 'sales_logic.dart';

export 'sales_logic.dart' show defaultCashAccountId;

/// What a saved sale hands back to the Sales page: enough to offer the
/// customer's credit after a Correct Sale re-entry saved on credit.
class SaleSaved {
  const SaleSaved({required this.saleId, required this.label, required this.total, required this.paidNow, required this.customerName});
  final int? saleId;
  final String label;
  final num total;
  final bool paidNow;
  final String customerName;
}

/// The reversed sale a Correct Sale form replaces.
class SaleCorrection {
  const SaleCorrection({required this.sale, required this.creditKept});
  final Map sale;
  final num creditKept;
  int get saleId => tIntOrNull(sale['saleId']) ?? 0;
  String get label => multiLines(sale).isNotEmpty ? (tStr(sale['saleGroupNo']).isEmpty ? '#$saleId' : tStr(sale['saleGroupNo'])) : '#$saleId';
}

/// "New sale" — the Add Sale dialog of `app/sales/page.tsx` since the sale-lines
/// redesign (358/360): Customer & Date, an Items table with a line per product
/// or egg size, the sale total with its override, Paid now / Part payment /
/// Pay later, and Notes. With [correcting] it is the Correct Sale re-entry:
/// pre-filled from the reversed sale and linked to it.
///
/// Pops a [SaleSaved] after a successful save.
class SaleFormScreen extends StatefulWidget {
  const SaleFormScreen({
    super.key,
    required this.session,
    required this.company,
    required this.flocks,
    required this.customers,
    required this.cashAccounts,
    required this.products,
    this.eggClasses = const [],
    this.eggsPerCrate = 30,
    this.correcting,
  });
  final Session session;
  final Company company;
  final List<Map> flocks;
  final List<Map> customers;

  /// Active accounts only, as the page keeps them.
  final List<Map> cashAccounts;
  final List<Map> products;

  /// Unsorted / General plus the farm's sizes (341); empty when the farm does not sort.
  final List<Map> eggClasses;
  final int eggsPerCrate;
  final SaleCorrection? correcting;

  @override
  State<SaleFormScreen> createState() => _SaleFormScreenState();
}

String _newRequestKey() {
  final r = Random();
  String h(int n) => List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
  return '${h(8)}-${h(4)}-4${h(3)}-${h(4)}-${h(12)}';
}

class _SaleFormScreenState extends State<SaleFormScreen> {
  late final SaleForm f;
  bool _saving = false;

  /// 358: one key per form, so a retry of the same form cannot post twice.
  final String _requestKey = _newRequestKey();
  final Map<String, TextEditingController> _ctl = {};
  final _otherCustomer = TextEditingController();
  final _override = TextEditingController();
  final _partPaid = TextEditingController();
  final _desc = TextEditingController();
  FarmMoney _money = const FarmMoney();

  List<Map> get _classes => widget.eggClasses;
  int get _epc => widget.eggsPerCrate;

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _money = m);
    });
    final fix = widget.correcting;
    if (fix != null) {
      f = SaleForm.correctionOf(fix.sale, creditKept: fix.creditKept, defaultAccount: defaultCashAccountId(widget.cashAccounts), eggsPerCrate: _epc);
      final names = [for (final c in widget.customers) tStr(c['name'])];
      if (f.customerName.isNotEmpty && !names.contains(f.customerName)) {
        f.showNewCustomerInput = true;
        _otherCustomer.text = f.customerName;
      }
    } else {
      f = SaleForm(eggsPerCrate: _epc)
        ..saleDate = isoDay(DateTime.now().toUtc())
        ..cashAccountId = defaultCashAccountId(widget.cashAccounts);
      // A new egg sale with no price yet starts at its class's price.
      final p = classPrice(_classes, null);
      if (p != null) f.first.unitPrice = p;
    }
    _desc.text = f.saleDescription;
  }

  @override
  void dispose() {
    for (final c in [..._ctl.values, _otherCustomer, _override, _partPaid, _desc]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _jsNum(num n) => n == n.roundToDouble() ? n.toInt().toString() : '$n';

  /// A line field's controller, created with the line's current value.
  TextEditingController _c(SaleItem l, String field, num value) =>
      _ctl.putIfAbsent('${l.key}:$field', () => TextEditingController(text: _jsNum(value)));

  /// Code changed a line's numbers (a product switch, a class price): show them.
  void _sync(SaleItem l) {
    for (final (field, v) in [('crates', l.crates), ('loose', l.loose), ('qty', l.quantity), ('price', l.unitPrice)]) {
      final c = _ctl['${l.key}:$field'];
      if (c != null && num.tryParse(c.text) != v) c.text = _jsNum(v);
    }
  }

  void _toast(String msg) => trackerToast(context, 'Almost there', description: msg);

  Future<void> _save() async {
    if (_saving) return;
    final userId = widget.session.tokens.userId;
    final farmId = widget.company.farmId;
    if (userId == null || userId.isEmpty || farmId.isEmpty) {
      trackerToast(context, 'Session issue', description: 'We could not confirm your farm or user. Please sign in again.', error: true);
      return;
    }
    final sp = f.firstStockProduct(widget.products);
    final msg = f.validate(available: f.firstAvailable(widget.products), stockUnits: stockUnitLabel(sp));
    if (msg != null) return _toast(msg);
    if (f.cashAccountId == null) {
      trackerToast(context, 'Cash account required', description: 'Choose which cash account this sale is received into.', error: true);
      return;
    }
    final part = f.validatePart();
    if (part != null) return _toast(part);
    if (f.postsAsGroup) {
      final g = f.validateGroup(_classes, widget.products);
      if (g != null) return _toast(g);
    }
    setState(() => _saving = true);
    try {
      final saved = f.postsAsGroup ? await _saveGroup(farmId, userId) : await _saveOne(farmId, userId);
      if (saved != null && mounted) Navigator.pop(context, saved);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Several lines (egg sizes and/or other products), or a part payment: one
  /// sale number, one payment, all or nothing.
  Future<SaleSaved?> _saveGroup(String farmId, String userId) async {
    final api = widget.session.farmClient;
    try {
      final res = await api.post(
        '/api/Sale/group',
        body: f.groupBody(farmId, userId, correctsSaleId: widget.correcting?.saleId, requestKey: _requestKey),
      );
      final data = res is Map ? res : const {};
      final saleCount = tIntOrNull(data['saleCount']) ?? 1;
      final groupNo = tStr(data['saleGroupNo']);
      final groupTotal = tNum(data['totalAmount']);
      final paidNow = f.partPaidAmount ?? 0;
      final partNote = f.partPayment ? ' Paid ${_money(paidNow)}, owed ${_money(max<num>(0, groupTotal - paidNow))}.' : '';
      if (!mounted) return null;
      if (saleCount > 1) {
        trackerToast(context, '$saleCount sales created: $groupNo', description: 'One sale per product, as each product is its own sale.$partNote');
      } else {
        final n = f.items.length;
        trackerToast(context, 'Sale $groupNo created', description: '$n line${n > 1 ? 's' : ''}, one sale.$partNote');
      }
      final ids = data['saleIds'];
      final firstId = tIntOrNull(data['saleId']) ?? (ids is List && ids.isNotEmpty ? tIntOrNull(ids.first) : null);
      return SaleSaved(
        saleId: firstId,
        label: groupNo.isNotEmpty ? groupNo : (firstId != null ? '#$firstId' : ''),
        total: groupTotal,
        paidNow: !f.partPayment && f.paid,
        customerName: f.customerName,
      );
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Sale not saved', description: e.message.isNotEmpty ? e.message : 'Failed to create sale', error: true);
      return null;
    }
  }

  Future<SaleSaved?> _saveOne(String farmId, String userId) async {
    final api = widget.session.farmClient;
    final body = f.createBody(farmId, userId, correctsSaleId: widget.correcting?.saleId);
    final total = tNum(body['totalAmount']);
    try {
      final res = await api.post('/api/Sale', body: body);
      final newId = res is Map ? tIntOrNull(res['saleId']) : null;
      // "Paid now" settles the sale. The API already records it as a payment;
      // only record one here if that did not happen (an older API).
      final alreadyPaid = res is Map && tNum(res['amountPaid']) >= total;
      if (f.paid && total > 0 && newId != null && !alreadyPaid) {
        try {
          await api.post(
            '/api/Poultry/payments',
            body: {
              'saleId': newId,
              'amount': total,
              'paymentMethod': f.paymentMethod.isEmpty ? 'Cash' : f.paymentMethod,
              'farmId': farmId,
              'createdBy': userId,
            },
          );
        } on ApiException catch (e) {
          if (mounted) {
            trackerToast(
              context,
              'Sale created — payment not recorded',
              description: e.message.isNotEmpty ? e.message : "Use the sale's Pay action to record it manually.",
              error: true,
            );
          }
        }
      }
      if (!mounted) return null;
      final fix = widget.correcting;
      trackerToast(context, 'Success', description: fix != null ? 'Corrected sale saved (replaces #${fix.saleId}).' : 'Sale created successfully');
      return SaleSaved(saleId: newId, label: newId != null ? '#$newId' : '', total: total, paidNow: f.paid, customerName: f.customerName);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Error', description: e.message.isNotEmpty ? e.message : 'Failed to create sale', error: true);
      return null;
    }
  }

  // ------------------------------------------------------------ build

  Widget _section(String title, Color band, Color bg, Color border, List<Widget> children, {Widget? trailing}) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: bg,
      border: Border.all(color: border),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: band,
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: trailing == null ? 8 : 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 12), children[i]],
            ],
          ),
        ),
      ],
    ),
  );

  Widget _label(String text, Widget child, {Widget? trailing, Color color = TColors.slate900}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Flexible(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: color),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 6), trailing],
        ],
      ),
      const SizedBox(height: 6),
      child,
    ],
  );

  Widget _num(TextEditingController c, ValueChanged<String> on, {bool decimal = false, String hint = '0'}) => AppInput(
    controller: c,
    hintText: hint,
    keyboardType: TextInputType.numberWithOptions(decimal: decimal),
    inputFormatters: [FilteringTextInputFormatter.allow(decimal ? RegExp(r'^\d*\.?\d*') : RegExp(r'^\d*'))],
    onChanged: on,
  );

  Widget _small(String text, {Color color = TColors.slate500}) => Text(text, style: TextStyle(fontSize: 12, color: color));

  Widget _checkLine(bool value, ValueChanged<bool> on, Widget text) => InkWell(
    onTap: () => on(!value),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(value: value, onChanged: (v) => on(v == true)),
        ),
        const SizedBox(width: 6),
        Expanded(child: text),
      ],
    ),
  );

  /// StockCheckNotice: the stock under line 1, and the override when it is short.
  Widget _stockNotice() {
    final avail = f.firstAvailable(widget.products);
    if (avail == null) return const SizedBox.shrink();
    final short = f.firstShortfall(widget.products);
    final units = stockUnitLabel(f.firstStockProduct(widget.products));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'In stock: '),
              TextSpan(
                text: thousands(avail),
                style: const TextStyle(fontWeight: FontWeight.w700, color: TColors.slate700),
              ),
              TextSpan(text: ' $units'),
            ],
          ),
          style: const TextStyle(fontSize: 12, color: TColors.slate500),
        ),
        if (short > 0) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: TColors.red50,
              border: Border.all(color: TColors.red300),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Only ${thousands(avail)} $units in stock — this sale is ${thousands(short)} more than you have.',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: TColors.red700),
                ),
                const SizedBox(height: 6),
                _checkLine(
                  f.overrideStock,
                  (v) => setState(() => f.overrideStock = v),
                  const Text(
                    'Sell it anyway. Stock goes negative until the missing production, or a stock correction, is recorded.',
                    style: TextStyle(fontSize: 12, color: TColors.red700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// One line of the Items table (SaleItemRow), as a card: amber edge for eggs,
  /// sky for anything else.
  Widget _line(int index, SaleItem l, ({num available, String units, bool short})? stock) {
    final egg = l.isEggs;
    final first = index == 1;
    final edge = egg ? const Color(0xFFF59E0B) : const Color(0xFF0EA5E9);
    final shown = [
      for (final c in _classes)
        if (c['classKind'] == 'Unsorted' || c['isActive'] == true || tIntOrNull(c['poultryProductId']) == l.eggProductId) c,
    ];
    final eggs = l.eggs(_epc);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: egg ? TColors.amber200 : const Color(0xFFBAE6FD)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Stack(
            children: [
              // The coloured left edge (a rounded border must be one colour).
              Positioned(left: 0, top: 0, bottom: 0, width: 4, child: ColoredBox(color: edge)),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: _label(
                            'Product',
                            color: TColors.slate500,
                            AppSelect<String>(
                              key: ValueKey('${l.key}:product'),
                              value: l.selectValue,
                              items: [for (final o in saleProductOptions) AppSelectItem(value: o, label: o)],
                              onChanged: (v) {
                                if (v == null) return;
                                setState(() {
                                  f.setProduct(l, v == 'Other' ? '' : v, _classes);
                                  _sync(l);
                                });
                              },
                            ),
                          ),
                        ),
                        if (f.hasExtraLines)
                          IconButton(
                            tooltip: 'Remove line',
                            icon: const Icon(Icons.close, size: 18, color: Color(0xFFEF4444)),
                            onPressed: () => setState(() => f.removeLine(l)),
                          ),
                      ],
                    ),
                    if (l.selectValue == 'Other') ...[
                      const SizedBox(height: 8),
                      AppInput(
                        key: ValueKey('${l.key}:other'),
                        initialValue: l.product,
                        hintText: 'Product name',
                        onChanged: (v) => setState(() {
                          f.setProduct(l, v, _classes);
                          _sync(l);
                        }),
                      ),
                    ],
                    const SizedBox(height: 10),
                    _label(
                      'Egg size',
                      color: TColors.slate500,
                      !egg
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Text('—', style: TextStyle(color: TColors.slate400)),
                            )
                          : hasEggSizes(_classes)
                          ? AppSelect<int>(
                              key: ValueKey('${l.key}:class'),
                              value: l.eggProductId ?? 0,
                              items: [
                                for (final c in shown)
                                  AppSelectItem(
                                    value: c['classKind'] == 'Unsorted' ? 0 : tIntOrNull(c['poultryProductId'])!,
                                    label:
                                        '${c['classKind'] == 'Unsorted' ? 'Unsorted / General' : c['name']} · stock '
                                        '${thousands(max<num>(0, tNum(c['onHand']).truncate()))}',
                                  ),
                              ],
                              onChanged: (v) => setState(() {
                                f.setClass(l, v == null || v == 0 ? null : v, _classes);
                                _sync(l);
                              }),
                            )
                          : first
                          // The web's <datalist>: free text, with suggestions.
                          ? Autocomplete<String>(
                              initialValue: TextEditingValue(text: l.size ?? ''),
                              optionsBuilder: (v) => eggSizeSuggestions.where((s) => s.toLowerCase().contains(v.text.toLowerCase())),
                              onSelected: (v) => setState(() => l.size = v),
                              fieldViewBuilder: (context, controller, focus, onSubmit) => TextFormField(
                                controller: controller,
                                focusNode: focus,
                                decoration: const InputDecoration(hintText: 'Optional, e.g. Large'),
                                onChanged: (v) => l.size = v,
                              ),
                            )
                          : const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Text('Unsorted', style: TextStyle(color: TColors.slate500)),
                            ),
                    ),
                    const SizedBox(height: 10),
                    if (egg)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _num(_c(l, 'crates', l.crates), (v) => setState(() => l.crates = int.tryParse(v) ?? 0)),
                                _small('crates ($_epc)'),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [_num(_c(l, 'loose', l.loose), (v) => setState(() => l.loose = int.tryParse(v) ?? 0)), _small('loose eggs')],
                            ),
                          ),
                        ],
                      )
                    else
                      _label(
                        'Quantity',
                        color: TColors.slate500,
                        _num(_c(l, 'qty', l.quantity), (v) => setState(() => l.quantity = num.tryParse(v) ?? 0), decimal: true),
                      ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: _label(
                            'Unit price',
                            color: TColors.slate500,
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _num(
                                  _c(l, 'price', l.unitPrice),
                                  (v) => setState(() => l.unitPrice = num.tryParse(v) ?? 0),
                                  decimal: true,
                                  hint: '0.00',
                                ),
                                if (egg)
                                  const Text(
                                    'per crate',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(fontSize: 11, color: TColors.slate500),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text('Line total', style: TextStyle(fontSize: 12, color: TColors.slate500)),
                            const SizedBox(height: 6),
                            Text(
                              l.total(_epc).toStringAsFixed(2),
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: TColors.emerald700),
                            ),
                            if (egg) const SizedBox(height: 16),
                          ],
                        ),
                      ],
                    ),
                    if (egg && eggs > 0) ...[
                      const SizedBox(height: 6),
                      _small(
                        '${l.crates} crate${l.crates == 1 ? '' : 's'}${l.loose > 0 ? ' + ${l.loose} loose' : ''} = ${thousands(eggs)} eggs'
                        '${l.loose > 0 ? ' — loose eggs charged pro rata' : ''}',
                      ),
                    ],
                    if (first) ...[const SizedBox(height: 6), _stockNotice()],
                    if (!first && stock != null) ...[
                      const SizedBox(height: 6),
                      Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(text: 'In stock: '),
                            TextSpan(
                              text: thousands(stock.available),
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            TextSpan(text: ' ${stock.units}${stock.short ? ' — not enough' : ''}'),
                          ],
                        ),
                        style: TextStyle(fontSize: 12, color: stock.short ? TColors.rose700 : TColors.slate500),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        Positioned(
          left: -8,
          top: -8,
          child: Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: edge, shape: BoxShape.circle),
            child: Text(
              '$index',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _statusChoice(String label, bool on, Color color, VoidCallback onTap) => Expanded(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? color : Colors.white,
          border: Border.all(color: on ? color : TColors.slate200, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: on ? Colors.white : TColors.slate600),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final fix = widget.correcting;
    final customerValue = f.showNewCustomerInput ? '__OTHER__' : (f.customerName.isEmpty ? null : f.customerName);
    final customerNames = <String>[];
    for (final c in widget.customers) {
      final n = tStr(c['name']);
      if (n.isNotEmpty && !customerNames.contains(n)) customerNames.add(n);
    }
    final showCustomerValue = customerValue == null || customerValue == '__OTHER__' || customerNames.contains(customerValue) ? customerValue : null;
    final stock = f.extraLineStock(_classes, widget.products);
    final anyShort = stock.any((x) => x?.short == true);
    final total = f.allLinesAmount;
    final partPaid = f.partPaidAmount ?? 0;
    final paidNowOn = f.paid && !f.partPayment;
    final payLaterOn = !f.paid && !f.partPayment;
    final otherProducts = [for (final l in f.extra) l.product];

    return Scaffold(
      appBar: AppBar(title: Text(fix != null ? 'Corrected sale (replaces ${fix.label})' : 'New sale')),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: TColors.slate200)),
          ),
          // Pinned while the form scrolls; Cancel under Record sale, as the web's phone layout.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: TColors.blue600, minimumSize: const Size.fromHeight(44)),
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving…' : 'Record sale · ${_money(total)}'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: TColors.red600,
                  side: const BorderSide(color: TColors.red200),
                  minimumSize: const Size.fromHeight(44),
                ),
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        children: [
          Text(
            fix != null
                ? 'Filled in from the reversed sale. Fix what was wrong and save: this becomes a new sale linked to it.'
                : 'Add a line for each product or egg size sold. Several lines are saved as one sale.',
            style: const TextStyle(fontSize: 13, color: TColors.slate500),
          ),
          if (fix != null && fix.creditKept > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(6)),
              child: Text(
                '${_money(fix.creditKept)} from the reversed sale is held as customer credit. '
                'Save this as Pay later and you will be offered to apply it -- no new money is recorded.',
                style: const TextStyle(fontSize: 13, color: Color(0xFF1E40AF)),
              ),
            ),
          ],
          const SizedBox(height: 14),
          _section('Customer & Date', TColors.blue600, const Color(0x66EFF6FF), TColors.blue200, [
            _label(
              'Customer *',
              trailing: const Tooltip(
                triggerMode: TooltipTriggerMode.tap,
                message: 'If you cannot find the customer, please go to the customer page and create the Customer first',
                child: Icon(Icons.info_outline, size: 16, color: TColors.slate400),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                ],
              ),
            ),
            _label(
              'Sale date *',
              AppDateField(value: businessDateAsDateTime(f.saleDate), onChanged: (d) => setState(() => f.saleDate = d == null ? '' : isoDay(d))),
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
                      enabled: !closedFlockBlocksSale(fl, f.first.product, null, otherProducts),
                    ),
                ],
                onChanged: (v) => setState(() => f.flockId = v),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          _section(
            'Items',
            const Color(0xFFF59E0B),
            const Color(0x66FFFBEB),
            TColors.amber200,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                  decoration: BoxDecoration(color: const Color(0x40FFFFFF), borderRadius: BorderRadius.circular(999)),
                  child: Text('${f.items.length}', style: const TextStyle(fontSize: 12, color: Colors.white)),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: TColors.amber700,
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed: () => setState(() => f.addLine(_classes)),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add line'),
                ),
              ],
            ),
            [
              for (var i = 0; i < f.items.length; i++) _line(i + 1, f.items[i], i == 0 ? null : stock[i - 1]),
              if (anyShort && f.firstShortfall(widget.products) == 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: TColors.red50,
                    border: Border.all(color: TColors.red300),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: _checkLine(
                    f.overrideStock,
                    (v) => setState(() => f.overrideStock = v),
                    const Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'A line asks for more than is in stock.',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(text: ' Sell it anyway — stock goes negative until the missing production, or a stock correction, is recorded.'),
                        ],
                      ),
                      style: TextStyle(fontSize: 12, color: TColors.red700),
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: TColors.emerald50,
                  border: Border.all(color: TColors.emerald200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _label(
                      'Override Total Sale Amount',
                      color: TColors.emerald800,
                      _num(_override, (v) => setState(() => f.overrideAmount = v.isEmpty ? null : num.tryParse(v)), decimal: true, hint: 'Optional'),
                    ),
                    if (f.hasExtraLines) ...[
                      const SizedBox(height: 6),
                      _small(
                        f.hasOverride
                            ? 'The override is shared across the lines in proportion to their amounts.'
                            : f.saleProductCount > 1
                            ? '${f.saleProductCount} different products: saved as ${f.saleProductCount} sales, one per product, in one go.'
                            : 'Saved as one sale number with ${f.items.length} lines and one payment.',
                        color: TColors.emerald800,
                      ),
                    ],
                    const SizedBox(height: 10),
                    const Text(
                      'SALE TOTAL',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .5, color: TColors.emerald700),
                    ),
                    Text(
                      _money(total),
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: TColors.emerald700),
                    ),
                    if (f.hasOverride && (total - f.calculatedSaleTotal).abs() >= 0.005)
                      Text(
                        'calculated ${_money(f.calculatedSaleTotal)}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 12, color: TColors.emerald800),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _section('Payment', const Color(0xFF16A34A), const Color(0x66F0FDF4), const Color(0xFFBBF7D0), [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Payment status', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _statusChoice(
                      'Paid now',
                      paidNowOn,
                      const Color(0xFF16A34A),
                      () => setState(() {
                        f.partPayment = false;
                        f.paid = true;
                      }),
                    ),
                    const SizedBox(width: 8),
                    _statusChoice(
                      'Part payment',
                      f.partPayment,
                      TColors.blue600,
                      () => setState(() {
                        f.partPayment = true;
                        f.paid = false;
                      }),
                    ),
                    const SizedBox(width: 8),
                    _statusChoice(
                      'Pay later',
                      payLaterOn,
                      const Color(0xFFF59E0B),
                      () => setState(() {
                        f.partPayment = false;
                        f.paid = false;
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _small(
                  f.partPayment
                      ? 'Records what the customer paid now as a payment; the rest stays owed on Customer Balances.'
                      : !f.paid
                      ? 'Records the full amount as owed — record payments later.'
                      : 'Records the sale as fully paid and posts a cash-in.',
                  color: TColors.slate600,
                ),
                if (f.partPayment) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      border: Border.all(color: TColors.blue200),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _label(
                          'Amount paid now *',
                          color: const Color(0xFF1E40AF),
                          _num(_partPaid, (v) => setState(() => f.partPaidAmount = v.isEmpty ? null : num.tryParse(v)), decimal: true, hint: '0.00'),
                        ),
                        const SizedBox(height: 8),
                        Text.rich(
                          TextSpan(
                            children: [
                              const TextSpan(text: 'Still owed: '),
                              TextSpan(
                                text: _money(max<num>(0, total - partPaid)),
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              if (partPaid >= total && total > 0)
                                const TextSpan(
                                  text: '  covers the whole sale — choose Paid now',
                                  style: TextStyle(fontSize: 12, color: TColors.red600),
                                ),
                            ],
                          ),
                          style: const TextStyle(fontSize: 13, color: TColors.blue900),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            _label(
              'Payment method *',
              AppSelect<String>(
                value: f.paymentMethod.isEmpty || !salePaymentMethods.contains(f.paymentMethod) ? null : f.paymentMethod,
                hintText: 'Select payment method',
                items: [for (final m in salePaymentMethods) AppSelectItem(value: m, label: m)],
                onChanged: (v) => setState(() => f.paymentMethod = v ?? ''),
              ),
            ),
            _label(
              'Receive into cash account *',
              AppSelect<int?>(
                value: widget.cashAccounts.any((a) => tIntOrNull(a['poultryCashAccountId']) == f.cashAccountId) ? f.cashAccountId : null,
                hintText: 'Select a cash account',
                items: [
                  for (final a in widget.cashAccounts)
                    AppSelectItem<int?>(
                      value: tIntOrNull(a['poultryCashAccountId']),
                      label: '${a['accountName']} (${tNum(a['currentBalance']).toStringAsFixed(2)})',
                    ),
                ],
                onChanged: (v) => setState(() => f.cashAccountId = v),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: TColors.slate50,
              border: Border.all(color: TColors.slate200),
              borderRadius: BorderRadius.circular(12),
            ),
            child: _label('Notes', AppInput(controller: _desc, hintText: 'Optional', onChanged: (v) => f.saleDescription = v)),
          ),
        ],
      ),
    );
  }
}
