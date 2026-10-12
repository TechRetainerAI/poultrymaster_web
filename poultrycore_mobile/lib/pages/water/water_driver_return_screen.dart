import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../poultry/expenses/deferred_costs_screen.dart' show qtyFmt;
import '../poultry/money/money_widgets.dart';
import '../poultry/reports/report_format.dart';
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/business_dates.dart';

/// Record driver return (the web's Record Return dialog on
/// `app/water-driver-returns/page.tsx`): Step 1 bags per product, Step 2
/// money collected and the driver's float, how the sale is posted (one
/// customer / summary / detailed), Step 3 the customer breakdown, Step 4
/// delivery expenses, then Record (Draft) or Approve & Reconcile.

const waterDeliveryExpenseCategories = ['Fuel', 'ChopMoney', 'LoadingBoys', 'Toll', 'Repair', 'PhoneCredit', 'Other'];

/// "ChopMoney" → "Chop Money" (the value stays raw).
String prettyExpenseCategory(String c) => c.replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}');

String _plain(num v) {
  final s = v.toStringAsFixed(3);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}

class WaterReturnItem {
  WaterReturnItem(this.productId, this.name, this.loaded, this.sold, this.returned, this.damaged, this.price);
  int productId;
  String name;
  num loaded, sold, returned, damaged, price;
  num get accounted => sold + returned + damaged;
  bool get balanced => accounted == loaded;
}

class WaterBreakdownItem {
  WaterBreakdownItem(this.key, this.productId, this.qty, this.price);
  final int key;
  int productId;
  num qty, price;
}

class WaterBreakdownRow {
  WaterBreakdownRow(this.key, {this.customerId, this.label = '', this.cash = 0, this.momo = 0, this.bank = 0, this.credit = 0, this.notes = '', List<WaterBreakdownItem>? items})
      : items = items ?? [];
  final int key;
  int? customerId;
  String label, notes;
  num cash, momo, bank, credit;
  final List<WaterBreakdownItem> items;
}

class WaterExpenseRow {
  WaterExpenseRow(this.key, {this.category = 'Fuel', this.amount = 0, this.description = '', this.approved = true});
  final int key;
  String category, description;
  num amount;
  bool approved;
}

/// The return's derived figures, as the web computes them.
class WaterReturnMaths {
  WaterReturnMaths({
    required this.items,
    required this.loading,
    required this.cash,
    required this.momo,
    required this.bank,
    required this.credit,
    required this.cashReturned,
    required this.breakdown,
    required this.expenses,
    required this.postingMode,
  });
  final List<WaterReturnItem> items;
  final Map loading;
  final num cash, momo, bank, credit, cashReturned;
  final List<WaterBreakdownRow> breakdown;
  final List<WaterExpenseRow> expenses;
  final String postingMode;

  num _sum(num Function(WaterReturnItem) f) => items.fold<num>(0, (s, i) => s + f(i));
  num get sold => _sum((i) => i.sold);
  num get returned => _sum((i) => i.returned);
  num get damaged => _sum((i) => i.damaged);
  num get loaded => loading['bagsLoaded'] != null ? tNum(loading['bagsLoaded']) : _sum((i) => i.loaded);
  bool get perItemBalanced => items.every((i) => i.balanced);
  bool get overallBalanced => sold + returned + damaged == loaded;
  bool get bagsOk => perItemBalanced && overallBalanced;

  num get expectedCash {
    final fromItems = _sum((i) => i.sold * i.price);
    return fromItems != 0 ? fromItems : sold * tNum(loading['expectedSellingPricePerBag']);
  }

  num get collected => cash + momo + bank + credit;
  num get shortage => (expectedCash - collected) > 0 ? expectedCash - collected : 0;
  num get overage => (collected - expectedCash) > 0 ? collected - expectedCash : 0;

  num get bdCash => breakdown.fold<num>(0, (s, r) => s + r.cash);
  num get bdMomo => breakdown.fold<num>(0, (s, r) => s + r.momo);
  num get bdBank => breakdown.fold<num>(0, (s, r) => s + r.bank);
  num get bdCredit => breakdown.fold<num>(0, (s, r) => s + r.credit);
  Map<int, num> get bdQty {
    final m = <int, num>{};
    for (final r in breakdown) {
      for (final it in r.items) {
        m[it.productId] = (m[it.productId] ?? 0) + it.qty;
      }
    }
    return m;
  }

  bool get breakdownProvided => breakdown.isNotEmpty;
  bool get paymentsBalance => bdCash == cash && bdMomo == momo && bdBank == bank && bdCredit == credit;
  bool get qtyBalance => items.every((i) => (bdQty[i.productId] ?? 0) == i.sold);
  bool get breakdownBalanced => paymentsBalance && qtyBalance;
  bool get isDetailed => postingMode == 'Detailed';
  bool get creditWithoutCustomer => isDetailed && credit > 0 && !breakdownProvided;
  bool get detailedCreditUnassigned => isDetailed && breakdownProvided && breakdown.any((r) => r.credit > 0 && r.customerId == null);

  num get expensesTotal => expenses.fold<num>(0, (s, e) => s + (e.approved ? e.amount : 0));
  num get openingFloat => tNum(loading['openingCashWithDriver']);
  num get expectedFloatBack => (openingFloat - expensesTotal) > 0 ? openingFloat - expensesTotal : 0;
  bool get floatBalanced => (cashReturned - expectedFloatBack).abs() < 0.01;
}

class WaterDriverReturnScreen extends StatefulWidget {
  const WaterDriverReturnScreen({
    super.key,
    required this.session,
    required this.company,
    required this.loading,
    required this.products,
    required this.customers,
    this.existing,
  });
  final Session session;
  final Company company;
  final Map loading;
  final List<Map> products, customers;

  /// The return being continued or edited; it is replaced on save.
  final Map? existing;

  @override
  State<WaterDriverReturnScreen> createState() => _WaterDriverReturnScreenState();
}

class _WaterDriverReturnScreenState extends State<WaterDriverReturnScreen> {
  late final Map l = widget.loading;
  late final Map? e = widget.existing;
  List<WaterReturnItem> _items = [];
  final List<WaterBreakdownRow> _breakdown = [];
  final List<WaterExpenseRow> _expenses = [];
  num _cash = 0, _momo = 0, _bank = 0, _credit = 0;
  late num _cashReturned = tNum(l['openingCashWithDriver']);
  String _notes = '', _postingMode = 'OneCustomer';
  late String _date = tStr(l['loadDate']).isNotEmpty ? tStr(l['loadDate']).split('T').first : DateTime.now().toUtc().toIso8601String().substring(0, 10);
  int? _primaryCustomer;
  bool _breakdownOpen = false, _expensesOpen = false, _override = false, _saving = false, _ready = false;
  int _ver = 0, _seq = 0;
  FarmMoney _gh = const FarmMoney();

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  Map<String, String> get _q => {'farmId': _farmId};

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _gh = m);
    });
    e != null ? _prefill() : _fresh();
  }

  String _productName(int id) => tStr(widget.products.where((p) => tIntOrNull(p['waterProductId']) == id).firstOrNull?['name']);

  /// Defaults: everything sold, nothing back, the float returned whole.
  Future<void> _fresh() async {
    try {
      final items = rowsOf(await _api.get('/api/Water/vehicle-loadings/${tStr(l['waterVehicleLoadingId'])}/items', query: _q));
      _items = items.isNotEmpty
          ? [
              for (final it in items)
                WaterReturnItem(
                  tIntOrNull(it['waterProductId']) ?? 0,
                  tStr(it['productName']).isNotEmpty ? tStr(it['productName']) : (_productName(tIntOrNull(it['waterProductId']) ?? 0).isNotEmpty ? _productName(tIntOrNull(it['waterProductId']) ?? 0) : 'Product #${tStr(it['waterProductId'])}'),
                  tNum(it['bagsLoaded']),
                  tNum(it['bagsLoaded']),
                  0,
                  0,
                  tNum(it['unitPrice']),
                ),
            ]
          : [
              WaterReturnItem(
                tIntOrNull(l['waterProductId']) ?? 0,
                tStr(l['productName']).isNotEmpty ? tStr(l['productName']) : (_productName(tIntOrNull(l['waterProductId']) ?? 0).isNotEmpty ? _productName(tIntOrNull(l['waterProductId']) ?? 0) : 'Product'),
                tNum(l['bagsLoaded']),
                tNum(l['bagsLoaded']),
                0,
                0,
                tNum(l['expectedSellingPricePerBag']),
              ),
            ];
    } on ApiException {
      _items = [];
    }
    if (mounted) {
      setState(() {
        _ready = true;
        _ver++;
      });
    }
  }

  /// Reopen what was recorded: figures, posting choice, breakdown, expenses.
  Future<void> _prefill() async {
    final r = e!;
    _notes = tStr(r['notes']);
    _date = tStr(r['returnDate']).isNotEmpty ? tStr(r['returnDate']).split('T').first : _date;
    final mode = tStr(r['salesPostingMode']);
    _postingMode = const ['Detailed', 'OneCustomer', 'Summary'].contains(mode) ? mode : 'OneCustomer';
    _primaryCustomer = tIntOrNull(r['primaryCustomerId']);
    _cash = tNum(r['cashCollected']);
    _momo = tNum(r['moMoCollected']);
    _bank = tNum(r['bankCollected']);
    _credit = tNum(r['creditSalesAmount']);
    _cashReturned = r['cashReturnedByDriver'] != null ? tNum(r['cashReturnedByDriver']) : tNum(l['openingCashWithDriver']);
    final id = tStr(r['waterDriverReturnId']);
    Future<List<Map>> soft(String leaf) async {
      try {
        return rowsOf(await _api.get('/api/Water/driver-returns/$id/$leaf', query: _q));
      } on ApiException {
        return const [];
      }
    }

    try {
      final items = rowsOf(await _api.get('/api/Water/driver-returns/$id/items', query: _q));
      final sales = await soft('customer-sales');
      final exps = await soft('expenses');
      if (items.isEmpty) return await _fresh();
      _items = [
        for (final it in items)
          WaterReturnItem(
            tIntOrNull(it['waterProductId']) ?? 0,
            tStr(it['productName']).isNotEmpty ? tStr(it['productName']) : (_productName(tIntOrNull(it['waterProductId']) ?? 0).isNotEmpty ? _productName(tIntOrNull(it['waterProductId']) ?? 0) : 'Product #${tStr(it['waterProductId'])}'),
            tNum(it['bagsLoaded']),
            tNum(it['bagsSold']),
            tNum(it['bagsReturned']),
            tNum(it['bagsDamaged']),
            tNum(it['unitPrice']),
          ),
      ];
      if (sales.isNotEmpty) {
        _breakdown.addAll([
          for (final cs in sales)
            WaterBreakdownRow(
              _seq++,
              customerId: tIntOrNull(cs['waterCustomerId']),
              label: tStr(cs['customerLabel']).isNotEmpty ? tStr(cs['customerLabel']) : tStr(cs['customerName']),
              cash: tNum(cs['cashPaid']),
              momo: tNum(cs['moMoPaid']),
              bank: tNum(cs['bankPaid']),
              credit: tNum(cs['creditAmount']),
              notes: tStr(cs['notes']),
              items: [for (final it in rowsOf(cs['items'])) WaterBreakdownItem(_seq++, tIntOrNull(it['waterProductId']) ?? 0, tNum(it['quantity']), tNum(it['unitPrice']))],
            ),
        ]);
        if (_postingMode == 'Detailed') _breakdownOpen = true;
      }
      if (exps.isNotEmpty) {
        _expenses.addAll([
          for (final x in exps)
            WaterExpenseRow(_seq++,
                category: tStr(x['expenseCategory']), amount: tNum(x['amount']), description: tStr(x['description']), approved: x['isApproved'] != false),
        ]);
        _expensesOpen = true;
      }
    } on ApiException {
      return _fresh();
    }
    if (mounted) {
      setState(() {
        _ready = true;
        _ver++;
      });
    }
  }

  WaterReturnMaths get _m => WaterReturnMaths(
        items: _items,
        loading: l,
        cash: _cash,
        momo: _momo,
        bank: _bank,
        credit: _credit,
        cashReturned: _cashReturned,
        breakdown: _breakdown,
        expenses: _expenses,
        postingMode: _postingMode,
      );

  void _setCredit(num v) {
    _credit = v;
    // Summary only is not allowed once there are credit sales.
    if (_postingMode == 'Summary' && _credit > 0) _postingMode = 'OneCustomer';
  }

  Future<void> _save({bool approve = false}) async {
    if (_saving) return;
    final m = _m;
    if (!m.perItemBalanced) {
      return trackerToast(context, "Per-product bags don't reconcile", description: "Each product line's Sold + Returned + Damaged must equal Loaded.", error: true);
    }
    if (!m.overallBalanced) {
      return trackerToast(context, "Totals don't reconcile",
          description: 'Sold(${qtyFmt(m.sold)}) + Returned(${qtyFmt(m.returned)}) + Damaged(${qtyFmt(m.damaged)}) != Loaded(${qtyFmt(m.loaded)})', error: true);
    }
    if (m.isDetailed && m.breakdownProvided && !m.breakdownBalanced && !_override) {
      return trackerToast(context, "Customer breakdown doesn't match summary",
          description: 'Match the totals, click "Use Summary Only", or tick the override.', error: true);
    }
    if (m.detailedCreditUnassigned && !_override) {
      return trackerToast(context, 'Credit not assigned to customers', description: 'Tie each credit amount to a customer, or tick the admin override.', error: true);
    }
    setState(() => _saving = true);
    try {
      final created = await _api.post('/api/Water/driver-returns', body: {
        'waterVehicleLoadingId': tIntOrNull(l['waterVehicleLoadingId']),
        'replaceReturnId': tIntOrNull(e?['waterDriverReturnId']),
        'returnDate': '${_date}T00:00:00.000Z',
        'bagsSold': m.sold,
        'bagsReturned': m.returned,
        'bagsDamaged': m.damaged,
        'missingBags': 0,
        'cashCollected': _cash,
        'moMoCollected': _momo,
        'bankCollected': _bank,
        'creditSalesAmount': _credit,
        'cashReturnedByDriver': _cashReturned,
        'approvedDeliveryExpenses': m.expensesTotal,
        'notes': _notes.isEmpty ? null : _notes,
        'items': [
          for (final it in _items)
            {'waterProductId': it.productId, 'bagsSold': it.sold, 'bagsReturned': it.returned, 'bagsDamaged': it.damaged, 'unitPrice': it.price},
        ],
        if (m.isDetailed && m.breakdownProvided)
          'customerSales': [
            for (final r in _breakdown)
              {
                'waterCustomerId': r.customerId,
                'customerLabel': r.label.isEmpty ? null : r.label,
                'cashPaid': r.cash,
                'moMoPaid': r.momo,
                'bankPaid': r.bank,
                'creditAmount': r.credit,
                'notes': r.notes.isEmpty ? null : r.notes,
                'items': [for (final it in r.items) {'waterProductId': it.productId, 'quantity': it.qty, 'unitPrice': it.price}],
              },
          ],
        if (_expenses.isNotEmpty)
          'expenses': [
            for (final x in _expenses)
              {'expenseCategory': x.category, 'amount': x.amount, 'description': x.description.isEmpty ? null : x.description, 'isApproved': x.approved},
          ],
        'farmId': _farmId,
      });
      final newId = created is Map ? tIntOrNull(created['waterDriverReturnId']) : null;
      if (newId != null) {
        try {
          await _api.post('/api/Water/driver-returns/$newId/posting-mode', query: _q, body: {
            'salesPostingMode': _postingMode,
            'primaryCustomerId': _postingMode == 'OneCustomer' ? _primaryCustomer : null,
          });
        } on ApiException {
          // The row defaults to Detailed server-side.
        }
        if (approve) {
          try {
            await _api.post('/api/Water/driver-returns/$newId/approve-reconcile', query: {..._q, 'approvedBy': widget.session.tokens.userId ?? ''});
          } on ApiException catch (x) {
            if (mounted) trackerToast(context, 'Saved as Draft — approve failed', description: x.message, error: true);
          }
        }
      }
      if (e != null) {
        try {
          await _api.delete('/api/Water/driver-returns/${tStr(e!['waterDriverReturnId'])}', query: _q);
        } on ApiException catch (x) {
          if (mounted) {
            trackerToast(context, "New return saved, but couldn't remove the old one",
                description: 'Old return #${tStr(e!['waterDriverReturnId'])}: ${x.message}', error: true);
          }
        }
      }
      if (!mounted) return;
      trackerToast(
        context,
        approve ? 'Return reconciled' : (e != null ? 'Edited return saved as Draft' : 'Return recorded as Draft'),
        description: approve ? 'Sales, payments, inventory and customer balances updated.' : "Approve from the Returns tab when you're ready to reconcile.",
      );
      Navigator.pop(context, true);
    } on ApiException catch (x) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Return failed', description: x.message, error: true);
    }
  }

  // ------------------------------------------------------------ fields

  Widget _numF(String key, num value, ValueChanged<num> on, {bool decimal = true, double? width}) {
    final f = AppInput(
      key: ValueKey('$_ver-$key'),
      initialValue: _plain(value),
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(decimal ? r'^\d*\.?\d*' : r'^\d*'))],
      onChanged: (t) => setState(() => on(num.tryParse(t) ?? 0)),
    );
    return width == null ? f : SizedBox(width: width, child: f);
  }

  Widget _textF(String key, String value, ValueChanged<String> on, {String? hint, int lines = 1}) => AppInput(
        key: ValueKey('$_ver-$key'),
        initialValue: value,
        hintText: hint,
        minLines: lines,
        maxLines: lines == 1 ? 1 : lines + 3,
        onChanged: (t) => setState(() => on(t)),
      );

  Widget _band(String title, Color color, List<Widget> children, {String? sub}) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            color: color,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
              if (sub != null) Text(sub, style: const TextStyle(fontSize: 12, color: Color(0xFFFFFBEB))),
            ]),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 10), children[i]],
            ]),
          ),
        ]),
      );

  Widget _labelRow(String label, Widget value, {String? hint}) => Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: TColors.slate700)),
            if (hint != null) Text(hint, style: const TextStyle(fontSize: 11, color: TColors.slate500)),
          ]),
        ),
        const SizedBox(width: 10),
        value,
      ]);

  Widget _collapsible(String title, String sub, String right, bool open, VoidCallback toggle, List<Widget> body) => Container(
        decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            onTap: toggle,
            child: Container(
              color: TColors.slate50,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(children: [
                Icon(open ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, size: 18),
                const SizedBox(width: 4),
                Expanded(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                    TextSpan(text: ' $sub', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                  ])),
                ),
                Text(right, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
              ]),
            ),
          ),
          if (open) Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: body)),
        ]),
      );

  AppSelect<int> _productSelect(int value, ValueChanged<int> on) => AppSelect<int>(
        value: value == 0 ? null : value,
        hintText: 'Pick product',
        items: [for (final p in widget.products) AppSelectItem(value: tIntOrNull(p['waterProductId']) ?? 0, label: tStr(p['name']))],
        onChanged: (v) => setState(() => on(v ?? value)),
      );

  num _priceOf(int productId, num fallback) {
    final p = widget.products.where((x) => tIntOrNull(x['waterProductId']) == productId).firstOrNull;
    return p != null && p['unitPrice'] != null ? tNum(p['unitPrice']) : fallback;
  }

  // ------------------------------------------------------------ sections

  Widget _itemCard(WaterReturnItem it, int i) {
    final diff = it.accounted - it.loaded;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: it.balanced ? Colors.white : TColors.amber50,
        border: Border.all(color: it.balanced ? TColors.slate200 : TColors.amber300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(it.name, style: const TextStyle(fontWeight: FontWeight.w600, color: TColors.slate900))),
          Text(it.balanced ? '✓ Balanced' : (diff > 0 ? '+${qtyFmt(diff)}' : qtyFmt(diff)),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: it.balanced ? TColors.emerald600 : TColors.amber700)),
        ]),
        const SizedBox(height: 8),
        _labelRow('Loaded (bags)', SizedBox(width: 120, child: Text(qtyFmt(it.loaded), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w500)))),
        const SizedBox(height: 6),
        _labelRow('Expected', SizedBox(width: 120, child: Text(_gh(it.sold * it.price), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600)))),
        const SizedBox(height: 6),
        _labelRow('Sold (bags)', _numF('sold$i', it.sold, (v) => it.sold = v, decimal: false, width: 120)),
        const SizedBox(height: 6),
        _labelRow('Unit price', _numF('price$i', it.price, (v) => it.price = v, width: 120)),
        const SizedBox(height: 6),
        _labelRow('Returned (bags)', _numF('ret$i', it.returned, (v) => it.returned = v, decimal: false, width: 120)),
        const SizedBox(height: 6),
        _labelRow('Damaged (bags)', _numF('dmg$i', it.damaged, (v) => it.damaged = v, decimal: false, width: 120)),
      ]),
    );
  }

  Widget _breakdownCard(WaterBreakdownRow r, int idx) {
    final lineTotal = r.items.fold<num>(0, (s, it) => s + it.qty * it.price);
    final total = r.cash + r.momo + r.bank + r.credit;
    final mismatch = (lineTotal - total).abs() > 0.01;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('Customer ${idx + 1}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
          IconButton(
            tooltip: 'Remove customer',
            onPressed: () => setState(() => _breakdown.remove(r)),
            icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444)),
          ),
        ]),
        FilterLabel(
          'Customer',
          AppSelect<int>(
            value: r.customerId ?? 0,
            hintText: 'Pick customer',
            items: [
              const AppSelectItem(value: 0, label: '— walk-in / unnamed —'),
              for (final c in widget.customers) AppSelectItem(value: tIntOrNull(c['waterCustomerId']) ?? 0, label: tStr(c['name'])),
            ],
            onChanged: (v) => setState(() => r.customerId = v == null || v == 0 ? null : v),
          ),
        ),
        const SizedBox(height: 8),
        FilterLabel('Or label', _textF('lbl${r.key}', r.label, (t) => r.label = t, hint: 'Walk-in name')),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              color: TColors.slate50,
              padding: const EdgeInsets.only(left: 8),
              child: Row(children: [
                const Expanded(child: Text('Items sold to this customer', style: TextStyle(fontSize: 12))),
                TextButton.icon(
                  onPressed: widget.products.isEmpty
                      ? null
                      : () => setState(() {
                            final first = widget.products.first;
                            r.items.add(WaterBreakdownItem(_seq++, tIntOrNull(first['waterProductId']) ?? 0, 1, tNum(first['unitPrice'])));
                          }),
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text('Add item'),
                ),
              ]),
            ),
            if (r.items.isEmpty)
              const Padding(padding: EdgeInsets.all(8), child: Text('No items yet.', style: TextStyle(fontSize: 12, color: TColors.slate500)))
            else
              for (final it in r.items)
                Container(
                  margin: const EdgeInsets.all(6),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Expanded(
                        child: _productSelect(it.productId, (v) {
                          it.price = _priceOf(v, it.price);
                          it.productId = v;
                          _ver++;
                        }),
                      ),
                      IconButton(
                        tooltip: 'Remove item',
                        onPressed: () => setState(() => r.items.remove(it)),
                        icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444)),
                      ),
                    ]),
                    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Expanded(child: FilterLabel('Qty (bags)', _numF('bq${it.key}', it.qty, (v) => it.qty = v, decimal: false))),
                      const SizedBox(width: 6),
                      Expanded(child: FilterLabel('Price', _numF('bp${it.key}', it.price, (v) => it.price = v))),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          const Text('Total', style: TextStyle(fontSize: 12, color: TColors.slate500)),
                          Text(_gh(it.qty * it.price), style: const TextStyle(fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ]),
                  ]),
                ),
          ]),
        ),
        const SizedBox(height: 8),
        twoUp([
          FilterLabel('Cash paid', _numF('bc${r.key}', r.cash, (v) => r.cash = v)),
          FilterLabel('MoMo paid', _numF('bm${r.key}', r.momo, (v) => r.momo = v)),
          FilterLabel('Bank paid', _numF('bb${r.key}', r.bank, (v) => r.bank = v)),
          FilterLabel('Credit', _numF('bcr${r.key}', r.credit, (v) => r.credit = v)),
        ]),
        const SizedBox(height: 6),
        DefaultTextStyle(
          style: TextStyle(fontSize: 12, color: mismatch ? TColors.amber700 : TColors.slate500),
          child: Wrap(alignment: WrapAlignment.spaceBetween, spacing: 12, children: [
            Text.rich(TextSpan(children: [const TextSpan(text: 'Items total: '), TextSpan(text: _gh(lineTotal), style: const TextStyle(fontWeight: FontWeight.w700))])),
            Text.rich(TextSpan(children: [const TextSpan(text: 'Payments + credit: '), TextSpan(text: _gh(total), style: const TextStyle(fontWeight: FontWeight.w700))])),
          ]),
        ),
      ]),
    );
  }

  Widget _expenseCard(WaterExpenseRow x) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: FilterLabel(
                'Category',
                AppSelect<String>(
                  value: x.category,
                  items: [for (final c in waterDeliveryExpenseCategories) AppSelectItem(value: c, label: prettyExpenseCategory(c))],
                  onChanged: (v) => setState(() => x.category = v ?? x.category),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: FilterLabel('Amount', _numF('ea${x.key}', x.amount, (v) => x.amount = v))),
          ]),
          const SizedBox(height: 8),
          FilterLabel('Description', _textF('ed${x.key}', x.description, (t) => x.description = t)),
          const SizedBox(height: 4),
          Row(children: [
            Checkbox(value: x.approved, onChanged: (v) => setState(() => x.approved = v ?? false)),
            const Expanded(child: Text('Approved', style: TextStyle(fontSize: 13, color: TColors.slate700))),
            OutlinedButton.icon(
              onPressed: () => setState(() => _expenses.remove(x)),
              style: OutlinedButton.styleFrom(foregroundColor: TColors.red600, side: const BorderSide(color: Color(0xFFFECACA))),
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('Remove'),
            ),
          ]),
        ]),
      );

  Widget _radio(String value, String title, String sub, {bool enabled = true, Widget? extra}) => Opacity(
        opacity: enabled ? 1 : .5,
        child: InkWell(
          onTap: enabled ? () => setState(() => _postingMode = value) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(_postingMode == value ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 20, color: const Color(0xFF7C3AED)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  Text(sub, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                  ?extra,
                ]),
              ),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final title = 'Record driver return — ${tStr(l['driverName']).isEmpty ? '—' : tStr(l['driverName'])} / ${tStr(l['vehicleName'])} / ${tStr(l['routeName']).isEmpty ? '—' : tStr(l['routeName'])}';
    if (!_ready) {
      return Scaffold(appBar: AppBar(title: Text(title)), body: const Padding(padding: EdgeInsets.all(24), child: Text('Loading…', style: TextStyle(color: TColors.slate500))));
    }
    final m = _m;
    final summaryStyle = const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: TColors.slate900);
    Widget fig(String k, String v, {Color? color}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          Text(v, style: summaryStyle.copyWith(color: color)),
        ]);
    final bagsColor = m.bagsOk ? TColors.emerald700 : TColors.amber700;
    final approveBlockedByCustomer = _postingMode == 'OneCustomer' && _primaryCustomer == null;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('Record driver return')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: TColors.slate900)),
            const Text(
              'Reconcile bags sold / returned / damaged per product, then enter the payment summary. Optionally add the per-customer breakdown and delivery expenses.',
              style: TextStyle(fontSize: 13, color: TColors.slate500),
            ),
            const SizedBox(height: 12),
            FilterLabel(
              'Return date',
              AppDateField(
                value: businessDateAsDateTime(_date),
                hintText: 'dd/mm/yyyy',
                onChanged: (d) => setState(() => _date = d == null ? _date : isoDay(d)),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: TColors.slate50, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(10)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                twoUp([
                  fig('Loaded', '${qtyFmt(m.loaded)} bags'),
                  fig('Accounted', '${qtyFmt(m.sold + m.returned + m.damaged)} / ${qtyFmt(m.loaded)}', color: bagsColor),
                  fig('Expected cash', _gh(m.expectedCash)),
                  fig('Collected', _gh(m.collected), color: m.shortage > 0 ? TColors.rose600 : (m.overage > 0 ? TColors.green700 : null)),
                ]),
                if (m.shortage > 0 || m.overage > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(spacing: 12, children: [
                      if (m.shortage > 0) Text('Shortage: ${_gh(m.shortage)}', style: const TextStyle(fontSize: 12, color: TColors.rose600)),
                      if (m.overage > 0) Text('Overage: ${_gh(m.overage)}', style: const TextStyle(fontSize: 12, color: TColors.green700)),
                      if (m.expensesTotal > 0) Text('Approved expenses: ${_gh(m.expensesTotal)}', style: const TextStyle(fontSize: 12, color: TColors.slate600)),
                    ]),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
            _band('Step 1 · Reconcile bags per product', TColors.amber600, [for (var i = 0; i < _items.length; i++) _itemCard(_items[i], i)],
                sub: 'Sold + Returned + Damaged must equal Loaded'),
            const SizedBox(height: 12),
            formSection('Step 2 · Money collected', const Color(0xFF16A34A), [
              _labelRow('Cash', _numF('cash', _cash, (v) => _cash = v, width: 120), hint: 'Physical cash the driver collected on the run.'),
              _labelRow('MoMo', _numF('momo', _momo, (v) => _momo = v, width: 120), hint: 'Mobile Money (MTN, Vodafone, AirtelTigo).'),
              _labelRow('Bank', _numF('bank', _bank, (v) => _bank = v, width: 120), hint: 'Bank transfers / cheque deposits received today.'),
              _labelRow('Credit sales', _numF('credit', _credit, _setCredit, width: 120), hint: 'Goods given on credit — to be paid later.'),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(color: TColors.slate50, borderRadius: BorderRadius.circular(6)),
                child: _labelRow(
                  'Unaccounted cash',
                  Text(
                    m.shortage > 0 ? _gh(m.shortage) : (m.overage > 0 ? '+${_gh(m.overage)} over' : _gh(0)),
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: m.shortage > 0 ? TColors.rose600 : (m.overage > 0 ? TColors.amber600 : TColors.slate700)),
                  ),
                  hint: 'Expected sales minus everything collected (cash + MoMo + bank + credit).',
                ),
              ),
              if (!m.floatBalanced)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(color: const Color(0xFFFFF1F2), border: Border.all(color: const Color(0xFFFECDD3)), borderRadius: BorderRadius.circular(6)),
                  child: Text(
                    "Cash returned (${_gh(_cashReturned)}) doesn't match the expected float of ${_gh(m.expectedFloatBack)}${m.expensesTotal > 0 ? ' (opening ${_gh(m.openingFloat)} − approved expenses ${_gh(m.expensesTotal)})' : ' (opening cash ${_gh(m.openingFloat)})'}. You can still save as Draft, but Approve & Reconcile is blocked until it balances.",
                    style: const TextStyle(fontSize: 12, color: Color(0xFF9F1239)),
                  ),
                ),
              const Divider(height: 1),
              _labelRow('Cash returned by driver', _numF('float', _cashReturned, (v) => _cashReturned = v, width: 140),
                  hint: "The driver's float coming back (opening cash, minus any approved cash expenses). Not a sale."),
            ]),
            const SizedBox(height: 12),
            formSection('How should this delivery sale be posted?', const Color(0xFF9333EA), [
              _radio('OneCustomer', 'Post all sales to one customer', 'Posts the entire delivery sale to the customer below.',
                  extra: _postingMode == 'OneCustomer'
                      ? Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: AppSelect<int>(
                            value: _primaryCustomer,
                            hintText: 'Pick a customer',
                            items: [for (final c in widget.customers) AppSelectItem(value: tIntOrNull(c['waterCustomerId']) ?? 0, label: tStr(c['name']))],
                            onChanged: (v) => setState(() => _primaryCustomer = v),
                          ),
                        )
                      : null),
              _radio('Summary', 'Summary only', "Posts to the company's General Delivery Customer. No per-shop tracking.",
                  enabled: _credit <= 0,
                  extra: _credit > 0
                      ? const Text('Unavailable while there are credit sales — pick option 1 or 3.', style: TextStyle(fontSize: 12, color: TColors.amber700))
                      : null),
              _radio('Detailed', 'Detailed customer breakdown',
                  'Record real customer/shop sales one-by-one. The breakdown appears right below when selected.'),
            ]),
            if (_postingMode == 'Detailed') ...[
              const SizedBox(height: 12),
              _collapsible(
                'Customer sales breakdown',
                '— record each customer/shop sale; posts to Sales + Payments on approve',
                '${_breakdown.length} customer${_breakdown.length == 1 ? '' : 's'}',
                _breakdownOpen,
                () => setState(() => _breakdownOpen = !_breakdownOpen),
                [
                  Wrap(spacing: 8, children: [
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _breakdown.add(WaterBreakdownRow(_seq++))),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add customer sale'),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _breakdown.clear();
                        _breakdownOpen = false;
                      }),
                      child: const Text('Use summary only'),
                    ),
                  ]),
                  for (var i = 0; i < _breakdown.length; i++) ...[const SizedBox(height: 8), _breakdownCard(_breakdown[i], i)],
                  if (_breakdown.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: m.breakdownBalanced ? const Color(0xFFECFDF5) : TColors.amber50,
                        border: Border.all(color: m.breakdownBalanced ? const Color(0xFFA7F3D0) : const Color(0xFFFDE68A)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: m.breakdownBalanced
                          ? const Text('✓ Customer breakdown matches the return summary.', style: TextStyle(fontSize: 12, color: TColors.emerald800))
                          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Text('Customer breakdown does not match the return summary.', style: TextStyle(fontSize: 12, color: TColors.amber800)),
                              if (!m.paymentsBalance)
                                Text(
                                  'Cash ${_gh(m.bdCash)} vs ${_gh(_cash)} · MoMo ${_gh(m.bdMomo)} vs ${_gh(_momo)} · Bank ${_gh(m.bdBank)} vs ${_gh(_bank)} · Credit ${_gh(m.bdCredit)} vs ${_gh(_credit)}',
                                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: TColors.amber800),
                                ),
                              if (!m.qtyBalance)
                                const Text("Per-product quantities don't match Sold totals.", style: TextStyle(fontSize: 12, color: TColors.amber800)),
                            ]),
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 12),
            _collapsible('Step 4 · Delivery expenses', '— fuel, toll, loading boys, etc.', _gh(m.expensesTotal), _expensesOpen,
                () => setState(() => _expensesOpen = !_expensesOpen), [
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _expenses.add(WaterExpenseRow(_seq++))),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add expense'),
                ),
              ),
              const SizedBox(height: 8),
              if (_expenses.isEmpty)
                const Text('No expenses logged.', style: TextStyle(fontSize: 12, color: TColors.slate500))
              else
                for (final x in _expenses) ...[_expenseCard(x), const SizedBox(height: 8)],
            ]),
            const SizedBox(height: 12),
            formSection('Notes', TColors.slate600, [FilterLabel('Notes', _textF('notes', _notes, (t) => _notes = t, lines: 3))]),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: m.bagsOk ? const Color(0xFFECFDF5) : const Color(0xFFFFF1F2),
                border: Border.all(color: m.bagsOk ? const Color(0xFFA7F3D0) : const Color(0xFFFECDD3)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: DefaultTextStyle(
                style: TextStyle(fontSize: 13, color: m.bagsOk ? TColors.emerald800 : const Color(0xFF9F1239)),
                child: Wrap(alignment: WrapAlignment.spaceBetween, spacing: 8, runSpacing: 4, children: [
                  Text.rich(TextSpan(children: [
                    TextSpan(text: 'Sold ${qtyFmt(m.sold)} + Returned ${qtyFmt(m.returned)} + Damaged ${qtyFmt(m.damaged)} = '),
                    TextSpan(text: qtyFmt(m.sold + m.returned + m.damaged), style: const TextStyle(fontWeight: FontWeight.w700)),
                    const TextSpan(text: ' of Loaded '),
                    TextSpan(text: qtyFmt(m.loaded), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ])),
                  Text(m.bagsOk ? '✓ Bags balanced' : "✗ Bags don't balance", style: const TextStyle(fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
            if (m.creditWithoutCustomer) ...[
              const SizedBox(height: 8),
              _note('Credit sales are not assigned to customers. Customer balances will not be accurate unless credit is linked to customers via the breakdown.',
                  TColors.amber50, const Color(0xFFFDE68A), TColors.amber800),
            ],
            if (m.detailedCreditUnassigned) ...[
              const SizedBox(height: 8),
              _note('One or more customer rows have credit but no customer selected. Pick a customer or tick the admin override below.',
                  const Color(0xFFFFF1F2), const Color(0xFFFECDD3), const Color(0xFF9F1239)),
            ],
            if ((m.isDetailed && m.breakdownProvided && !m.breakdownBalanced) || m.detailedCreditUnassigned)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _override,
                onChanged: (v) => setState(() => _override = v ?? false),
                title: const Text('Admin override — approve anyway', style: TextStyle(fontSize: 12, color: TColors.slate700)),
              ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: m.shortage > 0 ? const Color(0xFFFFF1F2) : (m.overage > 0 ? TColors.amber50 : TColors.slate50),
                border: Border.all(color: m.shortage > 0 ? const Color(0xFFFECDD3) : (m.overage > 0 ? const Color(0xFFFDE68A) : TColors.slate200)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: twoUp([
                fig('Expected cash', _gh(m.expectedCash)),
                fig('Collected', _gh(m.collected)),
                fig('Shortage', _gh(m.shortage), color: m.shortage > 0 ? TColors.rose600 : TColors.slate400),
                fig('Overage', _gh(m.overage), color: m.overage > 0 ? TColors.green700 : TColors.slate400),
                fig('Approved expenses', _gh(m.expensesTotal)),
              ]),
            ),
            if (!m.bagsOk || approveBlockedByCustomer) ...[
              const SizedBox(height: 8),
              _note(
                'Approve & Reconcile is disabled because ${!m.bagsOk ? "the bag counts don't reconcile yet (each product's Sold + Returned + Damaged must equal Loaded)." : "you chose “Post all sales to one customer” but haven't selected the customer yet — pick one above, or switch the posting option."}',
                TColors.amber50,
                const Color(0xFFFDE68A),
                TColors.amber800,
              ),
            ],
            const SizedBox(height: 14),
            Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
              redCancelButton(_saving ? null : () => Navigator.pop(context, false)),
              OutlinedButton(
                onPressed: _saving || !m.bagsOk ? null : () => _save(),
                child: Text(_saving ? 'Saving…' : 'Record return (Draft)'),
              ),
              FilledButton(
                onPressed: _saving || !m.bagsOk || approveBlockedByCustomer ? null : () => _save(approve: true),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF059669), foregroundColor: Colors.white),
                child: Text(_saving ? 'Working…' : 'Approve & Reconcile'),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _note(String t, Color bg, Color border, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(6)),
        child: Text(t, style: TextStyle(fontSize: 12, color: fg)),
      );
}
