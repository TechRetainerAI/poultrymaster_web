// Restaurant → Inventory → Ingredients & Stock (and Record Purchase), as
// `app/restaurant-inventory/page.tsx` with `components/restaurant/purchase-dialog.tsx`:
// the four stats and the low-stock alert; the Ingredients, Waste Log,
// Inventory Value, Purchases and Cost recognition tabs; Add / Edit Ingredient,
// Adjust Stock, Log Waste, Record Purchase and Reverse purchase.
// Deep links: ?purchase=1[&itemId=&qty=], ?tab=…, ?tab=purchases&purchaseId=.

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/reports/report_format.dart' show FarmMoney;
import '../poultry/sales/balances_widgets.dart' show LoadingLine;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/business_dates.dart' show fmtInstant;
import '../shared/company_clock.dart';
import '../shared/reason_select.dart' show ReasonSelect, stockAdjustmentReasons, stockReversalReasons;
import 'restaurant_money_kit.dart';
import 'restaurant_other_select.dart';
import 'restaurant_roles.dart' show restaurantRose;
import 'restaurant_widgets.dart';

// "Other" is not listed: the Other select adds its own, which opens a text box.
const ingredientCategories = ['Proteins', 'Dairy', 'Produce', 'Dry Goods', 'Spices', 'Beverages', 'Frozen', 'Oils & Fats', 'Bakery', 'Sauces'];
const ingredientUnits = ['kg', 'g', 'L', 'mL', 'pcs', 'dozen', 'bag', 'box', 'bottle', 'can', 'bunch'];
const storageAreas = ['Walk-in Cooler', 'Freezer', 'Dry Store', 'Bar', 'Kitchen Counter', 'Pantry'];
const wasteReasons = ['Spoilage', 'PrepWaste', 'Returned', 'Expired', 'Spillage', 'Overproduction'];
const purchasePaymentMethods = ['Cash', 'MoMo', 'Bank', 'Credit'];
const costModeLabels = {'EXPENSE_WHEN_PURCHASED': 'Expense when purchased', 'EXPENSE_WHEN_CONSUMED': 'Expense when consumed'};

/// A number as JavaScript prints it: 3, 2.5.
String jsNum(Object? v) {
  final n = tNum(v);
  return n == n.roundToDouble() ? n.toInt().toString() : '$n';
}

/// The Ingredients tab's filter: the category and a name search.
List<Map> filterIngredients(List<Map> rows, {String category = 'all', String search = ''}) => [
      for (final i in rows)
        if ((category == 'all' || tStr(i['category']) == category) &&
            (search.isEmpty || tStr(i['name']).toLowerCase().contains(search.toLowerCase())))
          i,
    ];

/// The built-in categories plus any in use, sorted.
List<String> ingredientFilterCategories(List<Map> rows) =>
    ({...ingredientCategories, for (final i in rows) if (tStr(i['category']).isNotEmpty) tStr(i['category'])}.toList()..sort());

/// The purchase dialog's arithmetic: unit cost, what is paid (it follows the
/// total, or nothing on Credit, until typed) and the balance.
({num unitCost, num paid, num balance}) purchaseMath({required num quantity, required num total, required String method, num? typedPaid}) {
  final paid = typedPaid ?? (method == 'Credit' ? 0 : total);
  final balance = total - paid > 0 ? total - paid : 0;
  return (unitCost: quantity > 0 ? total / quantity : 0, paid: paid, balance: balance);
}

const _purchaseStatus = {
  'Paid': (TColors.emerald100, TColors.emerald700),
  'Partially Paid': (TColors.amber100, TColors.amber700),
  'Unpaid': (Color(0xFFFEE2E2), Color(0xFFB91C1C)),
  'Reversed': (TColors.slate100, TColors.slate500),
};

class RestaurantInventoryScreen extends StatefulWidget {
  const RestaurantInventoryScreen({
    super.key,
    required this.session,
    required this.company,
    this.tab,
    this.purchaseId,
    this.openPurchase = false,
    this.purchaseItemId,
    this.purchaseQty,
  });
  final Session session;
  final Company company;

  /// `?tab=`; `?purchaseId=` lands on Purchases showing that one purchase.
  final String? tab;
  final int? purchaseId;

  /// `?purchase=1[&itemId=&qty=]`: opens Record Purchase (the menu's row).
  final bool openPurchase;
  final int? purchaseItemId;
  final num? purchaseQty;

  @override
  State<RestaurantInventoryScreen> createState() => _RestaurantInventoryScreenState();
}

class _RestaurantInventoryScreenState extends State<RestaurantInventoryScreen> {
  bool _loading = true;
  List<Map> _ingredients = [], _lowStock = [], _suppliers = [], _waste = [], _wasteSummary = [], _value = [];
  List<Map> _purchases = [], _costModes = [], _accounts = [], _supplierRows = [];
  final _search = TextEditingController();
  String _filterCat = 'all';
  late String _tab = widget.purchaseId != null ? 'purchases' : (widget.tab ?? 'ingredients');
  late int? _purchaseFocus = widget.purchaseId;
  FarmMoney _gh = const FarmMoney();
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  String _r(String path, [Map<String, Object?> q = const {}]) {
    final query = {'farmId': _farmId};
    q.forEach((k, v) {
      if (v != null && '$v' != '') query[k] = '$v';
    });
    return Uri(path: '/api/Restaurant$path', queryParameters: query).toString();
  }

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _gh = m);
    });
    CompanyClock.load(widget.session, widget.company).then((c) {
      if (mounted) setState(() => _offset = c.offset);
    });
    _load(first: true);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<Object?> _soft(Future<Object?> f) async {
    try {
      return await f;
    } on ApiException {
      return const [];
    }
  }

  Future<void> _load({bool first = false}) async {
    setState(() => _loading = true);
    try {
      final r = await Future.wait<Object?>([
        _api.get(_r('/inventory/ingredients', {'_': '1'})),
        _soft(_api.get(_r('/inventory/low-stock'))),
        _soft(_api.get(_r('/inventory/waste', {'_': '1'}))),
        _soft(_api.get(_r('/inventory/waste/summary', {'_': '1'}))),
        _soft(_api.get(_r('/inventory/value'))),
        _soft(_api.get(_r('/setup/suppliers'))),
        _soft(_api.get(_r('/purchases'))),
        _soft(_api.get(_r('/purchases/cost-recognition'))),
        _soft(loadRestaurantAccounts(_api, _farmId)),
      ]);
      if (!mounted) return;
      setState(() {
        _ingredients = rowsOf(r[0]);
        _lowStock = rowsOf(r[1]);
        _waste = rowsOf(r[2]);
        _wasteSummary = rowsOf(r[3]);
        _value = rowsOf(r[4]);
        // listRestaurantSuppliers and listSuppliers read the same route.
        _suppliers = rowsOf(r[5]);
        _supplierRows = rowsOf(r[5]);
        _purchases = rowsOf(r[6]);
        _costModes = rowsOf(r[7]);
        _accounts = rowsOf(r[8]);
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
    if (!mounted) return;
    setState(() => _loading = false);
    if (first && widget.openPurchase) _purchase(itemId: widget.purchaseItemId, quantity: widget.purchaseQty);
  }

  // ------------------------------------------------------------ actions

  Future<void> _ingredient([Map? editing]) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _IngredientDialog(session: widget.session, company: widget.company, editing: editing, suppliers: _suppliers, url: _r),
    );
    if (done == true) _load();
  }

  Future<void> _deleteIngredient(Map i) async {
    try {
      await _api.delete(_r('/inventory/ingredients/${tIntOrNull(i['ingredientId'])}'));
      _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
  }

  Future<void> _adjust(Map i) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _AdjustDialog(api: _api, url: _r, ingredientId: tIntOrNull(i['ingredientId'])!, suppliers: _suppliers),
    );
    if (done == true) _load();
  }

  Future<void> _logWaste() async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _WasteDialog(session: widget.session, company: widget.company, url: _r, ingredients: _ingredients),
    );
    if (done == true) _load();
  }

  Future<void> _purchase({int? itemId, num? quantity}) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => RestaurantPurchaseDialog(
        api: _api,
        url: _r,
        ingredients: _ingredients,
        suppliers: _supplierRows,
        accounts: _accounts,
        costModes: _costModes,
        fmt: _gh,
        itemId: itemId,
        quantity: quantity,
      ),
    );
    if (done == true) _load();
  }

  Future<void> _reversePurchase(Map p) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => RReasonDialog(
        title: 'Reverse purchase',
        description:
            'PO-${p['purchaseId']}: ${jsNum(p['quantity'])} ${tStr(p['unit'])} ${tStr(p['ingredientName'])}. The stock goes back out and anything paid comes back to its account today. Not possible once any of this stock has been used or a supplier payment was applied.',
        options: stockReversalReasons,
        keepLabel: 'Cancel',
        confirmLabel: 'Reverse',
        busyLabel: 'Reverse',
        errorTitle: 'Failed',
        missingReason: ('A reason is required', ''),
        submit: (reason) => _api.post(_r('/purchases/${tIntOrNull(p['purchaseId'])}/reverse'), body: {'reason': reason}),
      ),
    );
    if (done == true) {
      if (mounted) trackerToast(context, 'Purchase reversed');
      _load();
    }
  }

  Future<void> _costMode(String category, String mode) async {
    try {
      await _api.put(_r('/purchases/cost-recognition'), body: {'category': category, 'costMode': mode});
      if (mounted) trackerToast(context, 'Saved', description: '$category: ${costModeLabels[mode]}. Applies to purchases recorded from now on.');
      final cm = rowsOf(await _api.get(_r('/purchases/cost-recognition')));
      if (mounted) setState(() => _costModes = cm);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/restaurant-inventory');
    if (_loading && _ingredients.isEmpty) {
      return Scaffold(
        appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Ingredients & Stock')),
        body: const Center(child: LoadingLine('Loading…')),
      );
    }
    final totalValue = _value.fold<num>(0, (s, v) => s + tNum(v['totalValue']));
    final wasteCost = _wasteSummary.fold<num>(0, (s, w) => s + tNum(w['totalCost']));
    final low = _lowStock.isNotEmpty;
    Widget stat(String label, String value, IconData icon, Color color, Color bg) => TCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color))),
                Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
              ]),
            ),
          ]),
        );

    return Scaffold(
      backgroundColor: TColors.slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Ingredients & Stock')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
          RPageHeader(icon: Icons.inventory_2_outlined, title: 'Inventory & Recipes', subtitle: '${_ingredients.length} ingredients tracked'),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: TColors.rose700, side: const BorderSide(color: TColors.rose200), minimumSize: const Size.fromHeight(44)),
            onPressed: () => _purchase(),
            icon: const Icon(Icons.shopping_cart_outlined, size: 18),
            label: const Text('Record Purchase'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: restaurantRose, minimumSize: const Size.fromHeight(44)),
            onPressed: () => _ingredient(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Ingredient'),
          ),
          const SizedBox(height: 14),
          twoColumns([
            stat('Total Ingredients', '${_ingredients.length}', Icons.inventory_2_outlined, TColors.slate900, TColors.slate100),
            stat('Low Stock', '${_lowStock.length}', Icons.warning_amber_rounded, low ? const Color(0xFFB91C1C) : const Color(0xFF15803D),
                low ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7)),
            stat('Inventory Value', totalValue.toStringAsFixed(0), Icons.attach_money, const Color(0xFF1D4ED8), TColors.blue100),
            stat('Waste Cost', wasteCost.toStringAsFixed(0), Icons.trending_down, TColors.amber700, TColors.amber100),
          ]),
          if (low) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFEF2F2), border: Border.all(color: const Color(0xFFFECACA)), borderRadius: BorderRadius.circular(10)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.warning_amber_rounded, size: 20, color: TColors.red600),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '${_lowStock.length}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(
                          text:
                              ' ingredient${_lowStock.length != 1 ? 's' : ''} below reorder point: ${_lowStock.take(5).map((l) => tStr(l['name'])).join(', ')}${_lowStock.length > 5 ? '...' : ''}'),
                    ]),
                    style: const TextStyle(fontSize: 13, color: Color(0xFF991B1B)),
                  ),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: RTabs(
              value: _tab,
              onChanged: (v) => setState(() => _tab = v),
              tabs: [
                ('ingredients', Icons.inventory_2_outlined, 'Ingredients', rBadge('${_ingredients.length}')),
                ('waste', Icons.trending_down, 'Waste Log', rBadge('${_waste.length}')),
                ('value', Icons.attach_money, 'Inventory Value', null),
                ('purchases', Icons.shopping_cart_outlined, 'Purchases', rBadge('${_purchases.length}')),
                ('costs', Icons.hourglass_empty, 'Cost recognition', null),
              ],
            ),
          ),
          const SizedBox(height: 12),
          switch (_tab) {
            'waste' => _wasteTab(),
            'value' => _valueTab(totalValue),
            'purchases' => _purchasesTab(),
            'costs' => _costsTab(),
            _ => _ingredientsTab(),
          },
        ]),
      ),
    );
  }

  Widget _ingredientsTab() {
    final filtered = filterIngredients(_ingredients, category: _filterCat, search: _search.text);
    return TCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppInput(controller: _search, hintText: 'Search ingredients...', prefixIcon: const Icon(Icons.search, size: 18), onChanged: (_) => setState(() {})),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: AppSelect<String>(
              value: _filterCat,
              items: [
                const AppSelectItem(value: 'all', label: 'All Categories'),
                for (final c in ingredientFilterCategories(_ingredients)) AppSelectItem(value: c, label: c),
              ],
              onChanged: (v) => setState(() => _filterCat = v ?? 'all'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
              onPressed: _logWaste,
              icon: const Icon(Icons.trending_down, size: 16),
              label: const Text('Log Waste'),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        if (filtered.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
            decoration: BoxDecoration(border: Border.all(color: TColors.slate200, width: 2), borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              const Icon(Icons.inventory_2_outlined, size: 44, color: TColors.slate300),
              const SizedBox(height: 10),
              const Text('No ingredients yet', style: TextStyle(fontWeight: FontWeight.w500, color: TColors.slate900)),
              const SizedBox(height: 4),
              const Text('Add your kitchen ingredients to track stock and calculate food costs',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: TColors.slate500)),
              const SizedBox(height: 12),
              roseButton('Add First Ingredient', () => _ingredient()),
            ]),
          )
        else
          for (final i in filtered) _ingredientRow(i),
      ]),
    );
  }

  Widget _ingredientRow(Map i) {
    final low = i['isLow'] == true;
    Widget act(String label, VoidCallback on, {IconData? icon, Color? color}) => Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(34), padding: const EdgeInsets.symmetric(horizontal: 6), foregroundColor: color),
            onPressed: on,
            icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 14),
            label: Text(label, style: const TextStyle(fontSize: 12)),
          ),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: low ? const Color(0xFFFEF2F2) : Colors.white,
        border: Border.all(color: low ? const Color(0xFFFECACA) : TColors.slate200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: low ? const Color(0xFFFEE2E2) : TColors.slate100, borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.inventory_2_outlined, size: 20, color: low ? TColors.red600 : TColors.slate500),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(tStr(i['name']), style: const TextStyle(fontWeight: FontWeight.w600, color: TColors.slate900)),
                if (tStr(i['category']).isNotEmpty) rStatusBadge(tStr(i['category'])),
                if (low) rStatusBadge('Low Stock', bg: const Color(0xFFFEE2E2), fg: const Color(0xFFB91C1C), border: const Color(0xFFFEE2E2)),
                if (tStr(i['storageArea']).isNotEmpty) rStatusBadge(tStr(i['storageArea']), bg: const Color(0xFFEFF6FF)),
              ]),
              const SizedBox(height: 4),
              Wrap(spacing: 12, runSpacing: 2, children: [
                Text.rich(TextSpan(children: [
                  const TextSpan(text: 'Stock: '),
                  TextSpan(text: '${jsNum(i['currentStock'])} ${tStr(i['unit'])}', style: const TextStyle(fontWeight: FontWeight.w700)),
                ]), style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                Text('Cost: ${tNum(i['costPerUnit']).toStringAsFixed(2)}/${tStr(i['unit'])}', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                if (tNum(i['reorderPoint']) > 0) Text('Reorder at: ${jsNum(i['reorderPoint'])}', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                if (tStr(i['supplierName']).isNotEmpty) Text('Supplier: ${tStr(i['supplierName'])}', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
              ]),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text((tNum(i['currentStock']) * tNum(i['costPerUnit'])).toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.w700)),
            const Text('value', style: TextStyle(fontSize: 11, color: TColors.slate500)),
          ]),
        ]),
        const Divider(height: 20, color: TColors.slate100),
        Row(children: [
          act('Purchase', () => _purchase(itemId: tIntOrNull(i['ingredientId']))),
          const SizedBox(width: 4),
          act('Adjust', () => _adjust(i)),
          const SizedBox(width: 4),
          act('Edit', () => _ingredient(i), icon: Icons.edit_outlined),
          const SizedBox(width: 4),
          act('Delete', () => _deleteIngredient(i), icon: Icons.delete_outline, color: TColors.red600),
        ]),
      ]),
    );
  }

  Widget _tabHeader(IconData icon, Color fg, Color bg, String title, String subtitle, {Widget? action}) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Container(
                width: 36, height: 36, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)), child: Icon(icon, size: 20, color: fg)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
              ]),
            ),
          ]),
          if (action != null) ...[const SizedBox(height: 10), action],
          const SizedBox(height: 12),
        ],
      );

  Widget _wasteTab() => TCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _tabHeader(Icons.trending_down, TColors.amber600, TColors.amber100, 'Waste Log', 'Track and analyze kitchen waste',
              action: roseButton('Log Waste', _logWaste)),
          if (_wasteSummary.isNotEmpty) ...[
            for (final w in _wasteSummary)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: TColors.amber50, border: Border.all(color: TColors.amber200), borderRadius: BorderRadius.circular(10)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tNum(w['totalCost']).toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF92400E))),
                  Text('${tStr(w['reason'])} (${jsNum(w['count'])}x)', style: const TextStyle(fontSize: 12, color: TColors.amber600)),
                ]),
              ),
            const SizedBox(height: 8),
          ],
          if (_waste.isEmpty)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('No waste logged yet', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: TColors.slate500)))
          else
            for (final w in _waste.take(20))
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        Text(tStr(w['ingredientName']), style: const TextStyle(fontWeight: FontWeight.w500)),
                        rStatusBadge(tStr(w['reason'])),
                      ]),
                      const SizedBox(height: 2),
                      Text(
                          '${jsNum(w['quantity'])} ${tStr(w['unit'])} | ${fmtInstant(w['createdAt'], _offset)}${tStr(w['loggedBy']).isNotEmpty ? ' by ${tStr(w['loggedBy'])}' : ''}',
                          style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                    ]),
                  ),
                  Text(tNum(w['costAmount']).toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.w700, color: TColors.amber700)),
                ]),
              ),
        ]),
      );

  Widget _valueTab(num total) => TCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _tabHeader(Icons.attach_money, const Color(0xFF2563EB), TColors.blue100, 'Inventory Valuation', 'Total value: ${total.toStringAsFixed(2)}'),
          if (_value.isEmpty)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('No inventory data', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: TColors.slate500)))
          else
            for (final v in _value)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: v['isLow'] == true ? const Color(0xFFFEF2F2) : null,
                  border: Border.all(color: v['isLow'] == true ? const Color(0xFFFECACA) : TColors.slate200),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  if (v['isLow'] == true) ...[const Icon(Icons.warning_amber_rounded, size: 16, color: TColors.red600), const SizedBox(width: 8)],
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        Text(tStr(v['name']), style: const TextStyle(fontWeight: FontWeight.w500)),
                        if (tStr(v['category']).isNotEmpty) rStatusBadge(tStr(v['category'])),
                      ]),
                      Text('${jsNum(v['currentStock'])} ${tStr(v['unit'])} x ${tNum(v['costPerUnit']).toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                    ]),
                  ),
                  Text(tNum(v['totalValue']).toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
              ),
        ]),
      );

  Widget _purchasesTab() {
    final shown = [for (final p in _purchases) if (_purchaseFocus == null || tIntOrNull(p['purchaseId']) == _purchaseFocus) p];
    return TCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _tabHeader(Icons.shopping_cart_outlined, const Color(0xFFE11D48), const Color(0xFFFFE4E6), 'Purchases', 'Stock bought, what it cost and what is still owed',
            action: roseButton('Record Purchase', () => _purchase(), icon: Icons.shopping_cart_outlined)),
        if (_purchaseFocus != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: TColors.rose50, border: Border.all(color: TColors.rose200), borderRadius: BorderRadius.circular(6)),
            child: Row(children: [
              Expanded(child: Text('Showing purchase PO-$_purchaseFocus only', style: const TextStyle(fontSize: 13, color: TColors.rose800))),
              TextButton(onPressed: () => setState(() => _purchaseFocus = null), child: const Text('Show all purchases')),
            ]),
          ),
          const SizedBox(height: 10),
        ],
        if (_purchases.isEmpty)
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('No purchases recorded yet', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: TColors.slate500)))
        else
          for (final p in shown) _purchaseRow(p),
      ]),
    );
  }

  Widget _purchaseRow(Map p) {
    final reversed = p['status'] == 'Reversed';
    final status = reversed ? 'Reversed' : tStr(p['paymentStatus']);
    final (bg, fg) = _purchaseStatus[status] ?? (TColors.slate100, TColors.slate700);
    final balance = tNum(p['balance']);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(tStr(p['ingredientName']), style: const TextStyle(fontWeight: FontWeight.w500)),
                rStatusBadge('PO-${p['purchaseId']}'),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
                  child: Text(status,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: fg, decoration: reversed ? TextDecoration.lineThrough : null)),
                ),
                if (p['costMode'] == 'EXPENSE_WHEN_CONSUMED')
                  rStatusBadge('Expense when consumed', bg: TColors.amber50, fg: TColors.amber700, border: TColors.amber300),
              ]),
              const SizedBox(height: 2),
              Text(
                '${tStr(p['purchaseDate']).length >= 10 ? tStr(p['purchaseDate']).substring(0, 10) : tStr(p['purchaseDate'])} · ${jsNum(p['quantity'])} ${tStr(p['unit'])} × ${_gh(tNum(p['unitCost']))} · ${tStr(p['supplierName']).isEmpty ? 'No supplier' : tStr(p['supplierName'])}'
                '${tStr(p['dueDate']).isNotEmpty && balance > 0 ? ' · due ${tStr(p['dueDate']).substring(0, 10)}' : ''}',
                style: const TextStyle(fontSize: 12, color: TColors.slate500),
              ),
              if (reversed && tStr(p['reversalReason']).isNotEmpty)
                Text('Reversed: ${tStr(p['reversalReason'])}', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            ]),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_gh(tNum(p['totalCost'])), style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('paid ${_gh(tNum(p['amountPaid']) + tNum(p['allocated']))}${balance > 0 ? ' · owed ${_gh(balance)}' : ''}',
                  textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, color: TColors.slate500)),
            ]),
          ),
        ]),
        if (p['status'] == 'Posted')
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(onPressed: () => _reversePurchase(p), icon: const Icon(Icons.undo, size: 14), label: const Text('Reverse')),
          ),
      ]),
    );
  }

  Widget _costsTab() => TCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _tabHeader(
            Icons.hourglass_empty,
            TColors.amber600,
            TColors.amber100,
            'Cost recognition',
            "When each category's purchases reach Profit & Loss. Expense when purchased charges the whole purchase on the day it is bought; expense when consumed holds it as stock value until it is sold, wasted or adjusted out (see Deferred inventory cost). A change applies to purchases recorded from now on.",
          ),
          if (_costModes.isEmpty)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('Give your ingredients a category to choose how it is expensed',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: TColors.slate500)))
          else
            for (final m in _costModes)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(10)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text.rich(TextSpan(children: [
                    TextSpan(text: tStr(m['category']), style: const TextStyle(fontWeight: FontWeight.w500)),
                    TextSpan(
                        text: '  ${jsNum(m['ingredientCount'])} item${tNum(m['ingredientCount']) == 1 ? '' : 's'}',
                        style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                  ])),
                  const SizedBox(height: 8),
                  AppSelect<String>(
                    value: tStr(m['costMode']),
                    items: [for (final e in costModeLabels.entries) AppSelectItem(value: e.key, label: e.value)],
                    onChanged: (v) {
                      if (v != null && v != m['costMode']) _costMode(tStr(m['category']), v);
                    },
                  ),
                ]),
              ),
        ]),
      );
}

// ------------------------------------------------------------------ Ingredient

class _IngredientDialog extends StatefulWidget {
  const _IngredientDialog({required this.session, required this.company, required this.editing, required this.suppliers, required this.url});
  final Session session;
  final Company company;
  final Map? editing;
  final List<Map> suppliers;
  final String Function(String, [Map<String, Object?>]) url;
  @override
  State<_IngredientDialog> createState() => _IngredientDialogState();
}

class _IngredientDialogState extends State<_IngredientDialog> {
  late final Map? _e = widget.editing;
  final _categoryKey = GlobalKey<RestaurantOtherSelectState>();
  late final _name = TextEditingController(text: tStr(_e?['name']));
  late String? _category = _e != null ? (tStr(_e['category']).isEmpty ? null : tStr(_e['category'])) : 'Produce';
  late String _unit = _e != null && tStr(_e['unit']).isNotEmpty ? tStr(_e['unit']) : 'kg';
  late final _cost = TextEditingController(text: jsNum(_e?['costPerUnit']));
  final _opening = TextEditingController(text: '0');
  late final _reorder = TextEditingController(text: jsNum(_e?['reorderPoint']));
  late String? _storage = tStr(_e?['storageArea']).isEmpty ? null : tStr(_e?['storageArea']);
  late String _supplier = tStr(_e?['supplierName']).isEmpty ? '__none__' : tStr(_e?['supplierName']);
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _cost, _opening, _reorder]) {
      c.dispose();
    }
    super.dispose();
  }

  num _n(TextEditingController c) => num.tryParse(c.text.trim()) ?? 0;

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return trackerToast(context, 'Name required', error: true);
    setState(() => _saving = true);
    final e = _e;
    final body = <String, Object?>{
      'name': _name.text,
      'category': _category,
      'unit': _unit,
      'costPerUnit': _n(_cost),
      if (e == null) 'currentStock': _n(_opening),
      if (e != null) 'parLevel': e['parLevel'],
      'reorderPoint': _n(_reorder),
      'supplierName': _supplier == '__none__' ? '' : _supplier,
      if (e != null) 'expiryDays': e['expiryDays'],
      'storageArea': _storage,
      if (e != null) 'isActive': e['isActive'],
      if (e != null) 'notes': e['notes'],
      'farmId': widget.company.farmId,
    };
    final api = widget.session.farmClient;
    try {
      if (e != null) {
        await api.put('/api/Restaurant/inventory/ingredients/${tIntOrNull(e['ingredientId'])}', body: body);
      } else {
        await api.post('/api/Restaurant/inventory/ingredients', body: body);
      }
      // A typed category joins the list only once the ingredient saved.
      await _categoryKey.currentState?.remember();
      if (!mounted) return;
      trackerToast(context, e != null ? 'Updated' : 'Ingredient added');
      Navigator.pop(context, true);
    } on ApiException catch (err) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Failed', description: err.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => rDialog(
        title: _e != null ? 'Edit Ingredient' : 'Add Ingredient',
        description: 'Track raw materials and supplies',
        children: [
          rField('Name', AppInput(controller: _name), required: true),
          rField(
            'Category',
            RestaurantOtherSelect(
              key: _categoryKey,
              session: widget.session,
              company: widget.company,
              listKey: 'IngredientCategory',
              baseOptions: ingredientCategories,
              value: _category,
              onChanged: (v) => setState(() => _category = v),
              placeholder: 'Select',
            ),
          ),
          rField(
            'Unit',
            AppSelect<String>(
              value: _unit,
              items: [for (final u in ingredientUnits) AppSelectItem(value: u, label: u)],
              onChanged: (v) => setState(() => _unit = v ?? 'kg'),
            ),
          ),
          rField('Cost per Unit', rNumberInput(_cost)),
          if (_e == null) rField('Opening Stock', rNumberInput(_opening)),
          rField('Reorder Point', rNumberInput(_reorder)),
          rField(
            'Storage Area',
            AppSelect<String>(
              value: _storage,
              hintText: 'Select',
              items: [for (final s in storageAreas) AppSelectItem(value: s, label: s)],
              onChanged: (v) => setState(() => _storage = v),
            ),
          ),
          rField(
            'Supplier',
            AppSelect<String>(
              value: _supplier,
              hintText: 'Select supplier',
              items: [
                const AppSelectItem(value: '__none__', label: 'None'),
                for (final s in widget.suppliers)
                  AppSelectItem(value: tStr(s['name']), label: '${tStr(s['name'])}${tStr(s['category']).isNotEmpty ? ' (${tStr(s['category'])})' : ''}'),
              ],
              onChanged: (v) => setState(() => _supplier = v ?? '__none__'),
            ),
          ),
        ],
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          rConfirm(_e != null ? 'Update' : 'Add Ingredient', _saving ? null : _save),
        ],
      );
}

// ------------------------------------------------------------------ Adjust

class _AdjustDialog extends StatefulWidget {
  const _AdjustDialog({required this.api, required this.url, required this.ingredientId, required this.suppliers});
  final ApiClient api;
  final String Function(String, [Map<String, Object?>]) url;
  final int ingredientId;
  final List<Map> suppliers;
  @override
  State<_AdjustDialog> createState() => _AdjustDialogState();
}

class _AdjustDialogState extends State<_AdjustDialog> {
  String _type = 'AdjustmentIn';
  final _qty = TextEditingController(text: '0');
  String _reason = '';
  bool _saving = false;

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final q = num.tryParse(_qty.text.trim()) ?? 0;
    if (q == 0) return;
    setState(() => _saving = true);
    try {
      await widget.api.post(widget.url('/inventory/ingredients/${widget.ingredientId}/adjust'),
          body: {'quantity': q, 'movementType': _type, 'reason': _reason});
      if (!mounted) return;
      trackerToast(context, 'Stock adjusted');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Failed', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => rDialog(
        title: 'Adjust Stock',
        description: 'Correct a count or record stock removed. A delivery from a supplier is recorded with Record Purchase, so it carries its cost.',
        children: [
          rField(
            'Type',
            AppSelect<String>(
              value: _type,
              items: const [
                AppSelectItem(value: 'AdjustmentIn', label: 'Adjustment In (+)'),
                AppSelectItem(value: 'AdjustmentOut', label: 'Adjustment Out (-)'),
                AppSelectItem(value: 'TransferOut', label: 'Transfer Out (-)'),
              ],
              onChanged: (v) => setState(() {
                _type = v ?? 'AdjustmentIn';
              }),
            ),
          ),
          rField('Quantity', rNumberInput(_qty)),
          if (_type == 'TransferOut')
            rField(
              'Destination *',
              AppSelect<String>(
                value: _reason.isEmpty ? '__none__' : _reason,
                hintText: 'Where is it going?',
                items: [
                  const AppSelectItem(value: '__none__', label: 'Select destination'),
                  for (final s in widget.suppliers) AppSelectItem(value: 'To: ${tStr(s['name'])}', label: tStr(s['name'])),
                  const AppSelectItem(value: 'To: Another branch', label: 'Another branch'),
                  const AppSelectItem(value: 'To: Donation', label: 'Donation'),
                  const AppSelectItem(value: 'To: Return to supplier', label: 'Return to supplier'),
                  const AppSelectItem(value: 'To: Other', label: 'Other'),
                ],
                onChanged: (v) => setState(() => _reason = v == null || v == '__none__' ? '' : v),
              ),
            )
          else
            rField('Reason', ReasonSelect(options: stockAdjustmentReasons, value: _reason, onChanged: (v) => setState(() => _reason = v))),
        ],
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          rConfirm('Apply', _saving ? null : _apply),
        ],
      );
}

// ------------------------------------------------------------------ Waste

class _WasteDialog extends StatefulWidget {
  const _WasteDialog({required this.session, required this.company, required this.url, required this.ingredients});
  final Session session;
  final Company company;
  final String Function(String, [Map<String, Object?>]) url;
  final List<Map> ingredients;
  @override
  State<_WasteDialog> createState() => _WasteDialogState();
}

class _WasteDialogState extends State<_WasteDialog> {
  final _reasonKey = GlobalKey<RestaurantOtherSelectState>();
  int? _ingredientId;
  final _qty = TextEditingController(text: '0');
  final _notes = TextEditingController();
  String _reason = 'Spoilage';
  bool _saving = false;

  Map? get _ing => widget.ingredients.where((i) => tIntOrNull(i['ingredientId']) == _ingredientId).firstOrNull;

  @override
  void dispose() {
    _qty.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _log() async {
    final ing = _ing;
    final q = num.tryParse(_qty.text.trim()) ?? 0;
    if (ing == null) return trackerToast(context, 'Name required', error: true);
    if (q <= 0) return trackerToast(context, 'Quantity must be greater than 0', error: true);
    setState(() => _saving = true);
    try {
      await widget.session.farmClient.post('/api/Restaurant/inventory/waste', body: {
        'ingredientId': tIntOrNull(ing['ingredientId']),
        'ingredientName': tStr(ing['name']),
        'quantity': q,
        'unit': tStr(ing['unit']),
        // Recalculated from the ingredient's cost.
        'costAmount': tNum(ing['costPerUnit']) * q,
        'reason': _reason,
        if (_notes.text.isNotEmpty) 'notes': _notes.text,
        'farmId': widget.company.farmId,
      });
      await _reasonKey.currentState?.remember();
      if (!mounted) return;
      trackerToast(context, 'Waste logged');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Failed', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => rDialog(
        title: 'Log Waste',
        description: 'Record spoilage, prep waste, or expired items',
        children: [
          rField(
            'Ingredient',
            AppSelect<int>(
              value: _ingredientId,
              hintText: 'Select ingredient',
              items: [
                for (final i in widget.ingredients)
                  AppSelectItem(value: tIntOrNull(i['ingredientId'])!, label: '${tStr(i['name'])} (${jsNum(i['currentStock'])} ${tStr(i['unit'])})'),
              ],
              onChanged: (v) => setState(() => _ingredientId = v),
            ),
          ),
          rField('Quantity', rNumberInput(_qty)),
          rField(
            'Reason',
            RestaurantOtherSelect(
              key: _reasonKey,
              session: widget.session,
              company: widget.company,
              listKey: 'WasteReason',
              baseOptions: wasteReasons,
              value: _reason,
              onChanged: (v) => setState(() => _reason = (v ?? '').isEmpty ? 'Spoilage' : v!),
              placeholder: 'Select a reason',
            ),
          ),
          rField('Notes', AppInput(controller: _notes)),
        ],
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          rConfirm('Log Waste', _saving ? null : _log),
        ],
      );
}

// ------------------------------------------------------------------ Record Purchase

/// `components/restaurant/purchase-dialog.tsx`: the stock is added as a FIFO
/// lot, only the amount paid now leaves the chosen account, and any balance is
/// owed to the supplier.
class RestaurantPurchaseDialog extends StatefulWidget {
  const RestaurantPurchaseDialog({
    super.key,
    required this.api,
    required this.url,
    required this.ingredients,
    required this.suppliers,
    required this.accounts,
    required this.costModes,
    required this.fmt,
    this.itemId,
    this.quantity,
  });
  final ApiClient api;
  final String Function(String, [Map<String, Object?>]) url;
  final List<Map> ingredients, suppliers, accounts, costModes;
  final FarmMoney fmt;
  final int? itemId;
  final num? quantity;
  @override
  State<RestaurantPurchaseDialog> createState() => _RestaurantPurchaseDialogState();
}

class _RestaurantPurchaseDialogState extends State<RestaurantPurchaseDialog> {
  late int? _ingredientId = widget.itemId;
  int? _supplierId;
  String _date = rTodayIso();
  String _method = 'Cash';
  late final _qty = TextEditingController(text: widget.quantity != null ? jsNum(widget.quantity) : '0');
  final _total = TextEditingController(text: '0');
  final _paid = TextEditingController();
  bool _paidTouched = false;
  late int? _account = tIntOrNull(
      (widget.accounts.where((a) => a['isActive'] == true && a['defaultFor'] == 'Cash').firstOrNull ??
          widget.accounts.where((a) => a['isActive'] == true).firstOrNull)?['cashAccountId']);
  String _due = '';
  final _notes = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_qty, _total, _paid, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Map? get _item => widget.ingredients.where((i) => tIntOrNull(i['ingredientId']) == _ingredientId).firstOrNull;
  num _n(TextEditingController c) => num.tryParse(c.text.trim()) ?? 0;
  ({num unitCost, num paid, num balance}) get _m =>
      purchaseMath(quantity: _n(_qty), total: _n(_total), method: _method, typedPaid: _paidTouched ? _n(_paid) : null);
  String get _mode =>
      tStr(widget.costModes.where((m) => tStr(m['category']).toLowerCase() == tStr(_item?['category']).toLowerCase()).firstOrNull?['costMode'])
          .ifEmptyThen('EXPENSE_WHEN_PURCHASED');

  void _toast(String t, [String? d]) => trackerToast(context, t, description: d, error: true);

  Future<void> _save() async {
    final m = _m;
    final total = _n(_total), qty = _n(_qty);
    if (_ingredientId == null) return _toast('Pick an ingredient or supply');
    if (qty <= 0) return _toast('Quantity must be greater than 0');
    if (m.paid > total) return _toast('Amount paid cannot be more than the total cost');
    if (m.balance > 0 && _supplierId == null) {
      return _toast('Choose the supplier', 'Part of this purchase is still owed; Supplier Balances needs to know to whom.');
    }
    if (m.paid > 0 && _account == null) return _toast('Choose the cash account this was paid from');
    setState(() => _saving = true);
    try {
      await widget.api.post(widget.url('/purchases'), body: {
        'ingredientId': _ingredientId,
        'quantity': qty,
        'totalCost': total,
        'purchaseDate': _date.isEmpty ? null : _date,
        'supplierId': _supplierId,
        'paymentMethod': _method,
        'amountPaid': m.paid,
        'cashAccountId': m.paid > 0 ? _account : null,
        'dueDate': m.balance > 0 && _due.isNotEmpty ? _due : null,
        'notes': _notes.text.isEmpty ? null : _notes.text,
      });
      if (!mounted) return;
      trackerToast(context, 'Purchase recorded');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Save failed', e.message);
    }
  }

  Widget _readOnly(String v) => Container(
        height: 44,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: TColors.slate100, border: Border.all(color: TColors.slate300), borderRadius: BorderRadius.circular(8)),
        child: Text(v, style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.slate600)),
      );

  Widget _section(String title, Color band, List<Widget> children) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            color: band,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 12), children[i]],
            ]),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final gh = widget.fmt;
    final m = _m;
    final unit = tStr(_item?['unit']).isEmpty ? 'unit' : tStr(_item?['unit']);
    final mode = _mode;
    // Until typed, Amount paid follows the total (nothing on Credit).
    if (!_paidTouched && _paid.text != jsNum(m.paid)) _paid.text = jsNum(m.paid);
    return PopScope(
      canPop: !_saving,
      child: rDialog(
        title: 'New purchase',
        children: [
          _section('Item, Supplier & Date', const Color(0xFF4F46E5), [
            rField(
              'Ingredient or supply *',
              AppSelect<int>(
                value: _ingredientId,
                hintText: 'Pick item',
                items: [
                  for (final i in widget.ingredients)
                    if (i['isActive'] != false)
                      AppSelectItem(
                          value: tIntOrNull(i['ingredientId'])!,
                          label:
                              '${tStr(i['name'])}${tStr(i['unit']).isNotEmpty ? ' (${tStr(i['unit'])})' : ''}${tStr(i['category']).isNotEmpty ? ' · ${tStr(i['category'])}' : ''}'),
                ],
                onChanged: (v) => setState(() => _ingredientId = v),
              ),
            ),
            rField(
              'Supplier',
              AppSelect<int>(
                value: _supplierId ?? 0,
                items: [
                  const AppSelectItem(value: 0, label: 'Not linked to a supplier'),
                  for (final s in widget.suppliers)
                    if (s['isactive'] != false)
                      AppSelectItem(
                          value: tIntOrNull(s['restaurantsupplierid'])!,
                          label: '${tStr(s['name'])}${tStr(s['category']).isNotEmpty ? ' (${tStr(s['category'])})' : ''}'),
                ],
                onChanged: (v) => setState(() => _supplierId = v == null || v == 0 ? null : v),
              ),
            ),
            rField('Purchase date', rDateInput(_date, (v) => setState(() => _date = v), max: rTodayIso())),
            rField(
              'Payment method',
              AppSelect<String>(
                value: _method,
                items: [for (final x in purchasePaymentMethods) AppSelectItem(value: x, label: x)],
                onChanged: (v) => setState(() => _method = v ?? 'Cash'),
              ),
            ),
          ]),
          _section('Purchase Quantity & Costing', const Color(0xFF2563EB), [
            rField('Purchase quantity ($unit) *', rNumberInput(_qty, onChanged: () => setState(() {}))),
            rField('Total purchase cost *', rNumberInput(_total, onChanged: () => setState(() {}))),
            rField('Purchase unit cost (auto)', _readOnly('${gh(m.unitCost)} per $unit')),
            rField('Cost recognition', _readOnly(_item != null ? costModeLabels[mode] ?? mode : '—')),
            Text(
              mode == 'EXPENSE_WHEN_CONSUMED'
                  ? '${tStr(_item?['category']).isEmpty ? 'This category' : tStr(_item?['category'])} is expensed when consumed: the cost is held as stock value and reaches Profit & Loss as the stock is sold, wasted or adjusted out.'
                  : 'Expensed when purchased: the whole cost reaches Profit & Loss on the purchase date, and using the stock adds no second expense.',
              style: const TextStyle(fontSize: 12, color: TColors.slate500),
            ),
          ]),
          _section('Payment', TColors.amber600, [
            rField(
              'Amount paid',
              AppInput(
                controller: _paid,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() => _paidTouched = true),
              ),
            ),
            rField(
              'Pay from cash account',
              AppSelect<int>(
                value: m.paid <= 0 ? null : _account,
                enabled: m.paid > 0,
                hintText: m.paid <= 0 ? 'None (no cash movement)' : 'Choose an account',
                items: [
                  for (final a in widget.accounts)
                    if (a['isActive'] == true)
                      AppSelectItem(value: tIntOrNull(a['cashAccountId'])!, label: '${tStr(a['name'])} (${gh(tNum(a['currentBalance']))})'),
                ],
                onChanged: (v) => setState(() => _account = v),
              ),
            ),
            rField('Balance (auto)', _readOnly(gh(m.balance))),
            rField(
              'Due date',
              IgnorePointer(
                ignoring: m.balance <= 0,
                child: Opacity(opacity: m.balance <= 0 ? .5 : 1, child: rDateInput(_due, (v) => setState(() => _due = v))),
              ),
            ),
            const Text(
              'The cash account is charged only for the amount paid now. Any balance is owed to the supplier and appears on Supplier Balances.',
              style: TextStyle(fontSize: 12, color: TColors.slate500),
            ),
          ]),
          _section('Notes', TColors.slate600, [
            rField('Notes', AppInput(controller: _notes, hintText: 'Optional notes about this purchase', minLines: 3, maxLines: 5)),
          ]),
        ],
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          rConfirm(_saving ? 'Saving…' : 'Save', _saving ? null : _save),
        ],
      ),
    );
  }
}

extension on String {
  String ifEmptyThen(String other) => isEmpty ? other : this;
}
