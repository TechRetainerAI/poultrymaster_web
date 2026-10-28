// Hotel → Setup → Facilities → Supplies, as `app/hotel-inventory/page.tsx`:
// "Supplies & Inventory" with Record Purchase and Add Item; a card per supply
// (Low when stock is at or under its reorder level); Purchases (migration 334)
// with Reverse; and Cost recognition per category. Add Item's Category and Name
// are HotelOtherSelects; Record Purchase is components/hotel/supply-purchase-dialog.tsx.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../design/ui/form_dialog.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/reports/report_format.dart' show FarmMoney;
import '../poultry/sales/balances_widgets.dart' show LoadingLine;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/reason_select.dart';
import 'hotel_kit.dart';
import 'hotel_other_select.dart';

const _costModeLabels = {'EXPENSE_WHEN_PURCHASED': 'Expense when purchased', 'EXPENSE_WHEN_CONSUMED': 'Expense when consumed'};

const _paymentMethods = ['Cash', 'MoMo', 'Bank', 'Credit'];

/// The page's number, as the web prints `Number(x)`: no trailing ".0".
String _qty(Object? v) {
  final x = tNum(v);
  return x == x.roundToDouble() ? '${x.toInt()}' : '$x';
}

class HotelSuppliesScreen extends StatefulWidget {
  const HotelSuppliesScreen({
    super.key,
    required this.session,
    required this.company,
    this.openPurchase = false,
    this.itemId,
    this.purchaseId,
  });
  final Session session;
  final Company company;

  /// Deep links: ?purchase=1 (&itemId=) opens Record Purchase; ?purchaseId=
  /// shows only that purchase.
  final bool openPurchase;
  final int? itemId, purchaseId;

  @override
  State<HotelSuppliesScreen> createState() => _HotelSuppliesScreenState();
}

class _HotelSuppliesScreenState extends State<HotelSuppliesScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _items = [], _categories = [], _supplyItems = [], _purchases = [], _costModes = [], _suppliers = [];
  List<Map<String, dynamic>> _accounts = [];
  FarmMoney _money = const FarmMoney();
  late int? _focus = widget.purchaseId;

  ApiClient get _api => widget.session.farmClient;
  Map<String, dynamic> get _q => {'farmId': widget.company.farmId};

  @override
  void initState() {
    super.initState();
    _load().then((_) {
      if (widget.openPurchase && mounted) _openPurchase(itemId: widget.itemId);
    });
  }

  Future<List<Map<String, dynamic>>> _soft(String path) async {
    try {
      return hotelRows(await _api.get(path, query: _q));
    } catch (_) {
      return [];
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _items = hotelAlias(hotelRows(await _api.get('/api/Hotel/inventory', query: _q)), [
        'hotelInventoryItemId',
        'stockOnHand',
        'reorderLevel',
        'unitCost',
        'isActive',
      ]);
      final r = await Future.wait([
        _soft('/api/Hotel/setup/supply-categories'),
        _soft('/api/Hotel/setup/supply-items'),
        _soft('/api/Hotel/supplies/purchases'),
        _soft('/api/Hotel/supplies/cost-recognition'),
        _soft('/api/Hotel/suppliers'),
        _soft('/api/Hotel/finance/cash-accounts'),
      ]);
      _categories = r[0];
      _supplyItems = r[1];
      _purchases = r[2];
      _costModes = r[3];
      _suppliers = r[4];
      // loadHotelCashAccounts: the active ones only.
      _accounts = [
        for (final a in hotelAlias(r[5], ['hotelCashAccountId', 'accountName', 'currentBalance', 'isActive']))
          if (a['isActive'] != false) a,
      ];
      _money = await FarmMoney.load(widget.session, widget.company);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openItem() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _AddItemDialog(
        session: widget.session,
        company: widget.company,
        categories: [for (final c in _categories) tStr(c['description'])],
        supplyItems: _supplyItems,
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _openPurchase({int? itemId}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _PurchaseDialog(
        api: _api,
        farmId: widget.company.farmId,
        items: _items,
        suppliers: _suppliers,
        accounts: _accounts,
        costModes: _costModes,
        money: _money,
        itemId: itemId,
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _reverse(Map<String, dynamic> p) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _ReverseDialog(api: _api, farmId: widget.company.farmId, purchase: p),
    );
    if (done == true) _load();
  }

  Future<void> _setMode(String category, String mode) async {
    try {
      await _api.put(
        '/api/Hotel/supplies/cost-recognition',
        query: _q,
        body: {'farmId': widget.company.farmId, 'category': category, 'costMode': mode},
      );
      _costModes = await _soft('/api/Hotel/supplies/cost-recognition');
      if (mounted) {
        setState(() {});
        trackerToast(context, 'Cost recognition saved');
      }
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/hotel-inventory');
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Supplies')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            Row(
              children: [
                const Icon(Icons.inventory_2_outlined, size: 24, color: hotelViolet),
                const SizedBox(width: 10),
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: 'Supplies & Inventory',
                          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: TColors.slate900),
                        ),
                        TextSpan(
                          text: '  (${_items.length})',
                          style: const TextStyle(fontSize: 13, color: TColors.slate500),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: TColors.violet700,
                      side: const BorderSide(color: Color(0xFFC4B5FD)),
                      minimumSize: const Size.fromHeight(44),
                    ),
                    onPressed: () => _openPurchase(),
                    icon: const Icon(Icons.shopping_cart_outlined, size: 18),
                    label: const Text('Record Purchase'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    style: hotelPrimary.copyWith(minimumSize: const WidgetStatePropertyAll(Size.fromHeight(44))),
                    onPressed: _openItem,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Item'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_loading)
              const LoadingLine('Loading…')
            else ...[
              if (_items.isEmpty) hotelEmpty('No inventory items. Add your hotel supplies.', icon: Icons.inventory_2_outlined),
              for (final i in _items) ...[_itemRow(i), const SizedBox(height: 8)],
              const SizedBox(height: 10),
              _purchasesCard(),
              if (_costModes.isNotEmpty) ...[const SizedBox(height: 14), _costCard()],
            ],
          ],
        ),
      ),
    );
  }

  Widget _itemRow(Map<String, dynamic> i) {
    final stock = tNum(i['stockOnHand']), reorder = tNum(i['reorderLevel']);
    final low = stock <= reorder;
    return HotelRowCard(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                tStr(i['name']),
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: TColors.slate900),
              ),
              hotelBadge(tStr(i['category']), Colors.white, TColors.slate600),
            ],
          ),
          const SizedBox(height: 5),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Stock ${_qty(stock)} ${tStr(i['unit'])}',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: low ? TColors.red600 : TColors.slate800),
                  ),
                  if (low) ...[const SizedBox(width: 6), hotelBadge('Low', TColors.red100, TColors.red700)],
                ],
              ),
              Text('Reorder ${_qty(reorder)}', style: const TextStyle(fontSize: 12.5, color: TColors.slate500)),
              Text('Unit cost ${tNum(i['unitCost']).toStringAsFixed(2)}', style: const TextStyle(fontSize: 12.5, color: TColors.slate500)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _purchasesCard() {
    final shown = [
      for (final p in _purchases)
        if (_focus == null || tIntOrNull(p['purchaseId']) == _focus) p,
    ];
    return HotelCard(
      title: 'Purchases',
      description: 'Each delivery is a cost lot used oldest first. What was not paid now is on Supplier Balances.',
      action: _focus == null ? null : TextButton(onPressed: () => setState(() => _focus = null), child: const Text('Show all')),
      children: [
        if (_purchases.isEmpty) hotelEmpty('No purchases yet. Record a delivery with Record Purchase.'),
        for (final p in shown) _purchaseRow(p),
      ],
    );
  }

  Widget _purchaseRow(Map<String, dynamic> p) {
    final balance = tNum(p['balance']);
    final reversed = tStr(p['status']) == 'Reversed';
    Widget fig(String label, String value, {Color color = TColors.slate800, FontWeight weight = FontWeight.w600}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: TColors.slate500)),
        Text(
          value,
          style: TextStyle(fontSize: 13, fontWeight: weight, color: color, fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        border: Border.all(color: TColors.slate200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'PO-${p['purchaseId']}',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: TColors.slate600),
                    ),
                    Text(
                      tStr(p['itemName']),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: TColors.slate900),
                    ),
                    hotelBadge(reversed ? 'Reversed' : tStr(p['paymentStatus']), Colors.white, TColors.slate600),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${tStr(p['purchaseDate']).length >= 10 ? tStr(p['purchaseDate']).substring(0, 10) : tStr(p['purchaseDate'])}'
                  ' · ${tStr(p['supplierName']).isEmpty ? '—' : tStr(p['supplierName'])}'
                  ' · ${_qty(p['quantity'])} ${tStr(p['unit'])}',
                  style: const TextStyle(fontSize: 12.5, color: TColors.slate500),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  children: [
                    fig('Total', _money(tNum(p['totalCost']))),
                    fig('Paid', _money(tNum(p['amountPaid']) + tNum(p['allocated'])), color: TColors.emerald700),
                    fig(
                      'Balance',
                      _money(balance),
                      color: balance > 0 ? TColors.amber700 : TColors.slate400,
                      weight: balance > 0 ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _costModeLabels[tStr(p['costMode'])] ?? tStr(p['costMode']),
                  style: const TextStyle(fontSize: 12, color: TColors.slate600),
                ),
              ],
            ),
          ),
          if (!reversed)
            IconButton(
              tooltip: 'Reverse purchase',
              visualDensity: VisualDensity.compact,
              onPressed: () => _reverse(p),
              icon: const Icon(Icons.undo, size: 18),
            ),
        ],
      ),
    );
  }

  Widget _costCard() => HotelCard(
    title: 'Cost recognition',
    description:
        'Per category: charge the whole purchase to Profit & Loss when it is bought, or hold it as stock value and charge it '
        'as it is used (Deferred inventory cost). Applies to purchases recorded from now on.',
    children: [
      for (final m in _costModes)
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(color: TColors.slate200),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: tStr(m['category']),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    TextSpan(
                      text: '  (${tIntOrNull(m['itemCount']) ?? 0})',
                      style: const TextStyle(fontSize: 12, color: TColors.slate500),
                    ),
                  ],
                ),
                style: const TextStyle(fontSize: 14, color: TColors.slate900),
              ),
              const SizedBox(height: 6),
              AppSelect<String>(
                value: tStr(m['costMode']),
                items: [for (final e in _costModeLabels.entries) AppSelectItem(value: e.key, label: e.value)],
                onChanged: (v) {
                  if (v != null && v != tStr(m['costMode'])) _setMode(tStr(m['category']), v);
                },
              ),
            ],
          ),
        ),
    ],
  );
}

/// "Add Supply Item". Pops true once added.
class _AddItemDialog extends StatefulWidget {
  const _AddItemDialog({required this.session, required this.company, required this.categories, required this.supplyItems});
  final Session session;
  final Company company;
  final List<String> categories;
  final List<Map<String, dynamic>> supplyItems;
  @override
  State<_AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<_AddItemDialog> {
  final _categoryOther = GlobalKey<HotelOtherSelectState>();
  final _nameOther = GlobalKey<HotelOtherSelectState>();
  String _category = '', _name = '';
  final _unit = TextEditingController(text: 'pcs');
  final _stock = TextEditingController(text: '0');
  final _reorder = TextEditingController(text: '10');
  final _cost = TextEditingController(text: '0');
  bool _saving = false;

  /// The item list follows the chosen category.
  List<String> get _names => [
    for (final si in widget.supplyItems)
      if (_category.isEmpty || tStr(si['category']) == _category) tStr(si['description']),
  ];

  Future<void> _save() async {
    if (_name.trim().isEmpty) return trackerToast(context, 'Name required', error: true);
    if (_category.isEmpty) return trackerToast(context, 'Category required', error: true);
    setState(() => _saving = true);
    try {
      await widget.session.farmClient.post(
        '/api/Hotel/inventory',
        body: {
          'name': _name,
          'category': _category,
          'unit': _unit.text,
          'stockOnHand': double.tryParse(_stock.text) ?? 0,
          'reorderLevel': double.tryParse(_reorder.text) ?? 0,
          'unitCost': double.tryParse(_cost.text) ?? 0,
          'farmId': widget.company.farmId,
        },
      );
      // Before closing: closing drops the fields that hold what was typed.
      await _categoryOther.currentState?.remember();
      await _nameOther.currentState?.remember();
      if (!mounted) return;
      trackerToast(context, 'Item added');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Failed', description: e.message, error: true);
    }
  }

  Widget _num(String label, TextEditingController c, {bool decimal = false}) => FilterLabel(
    label,
    AppInput(
      controller: c,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(decimal ? r'^\d*\.?\d*' : r'^\d*'))],
    ),
  );

  @override
  Widget build(BuildContext context) => HotelDialog(
    icon: Icons.inventory_2_outlined,
    title: 'Add Supply Item',
    saveLabel: 'Add',
    saving: _saving,
    onSave: _save,
    children: [
      FilterLabel(
        'Category *',
        HotelOtherSelect(
          key: _categoryOther,
          session: widget.session,
          company: widget.company,
          listKey: 'SupplyCategory',
          baseOptions: widget.categories,
          value: _category,
          // A new category clears the name: the item list is filtered by it.
          onChanged: (v) => setState(() {
            _category = v ?? '';
            _name = '';
          }),
          placeholder: 'Select category',
          includeNone: true,
          noneLabel: 'Select category',
          otherLabel: 'Other (type category)',
        ),
      ),
      FilterLabel(
        'Name *',
        HotelOtherSelect(
          key: _nameOther,
          session: widget.session,
          company: widget.company,
          listKey: 'SupplyItemName',
          baseOptions: _names,
          value: _name,
          onChanged: (v) => setState(() => _name = v ?? ''),
          placeholder: 'Select item',
          includeNone: true,
          noneLabel: 'Select item',
          otherLabel: 'Other (type name)',
        ),
      ),
      FilterLabel('Unit', AppInput(controller: _unit, hintText: 'pcs, kg, litres')),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _num('Stock', _stock, decimal: true)),
          const SizedBox(width: 8),
          Expanded(child: _num('Reorder Level', _reorder, decimal: true)),
        ],
      ),
      _num('Unit Cost', _cost, decimal: true),
    ],
  );
}

/// "New purchase" (supply-purchase-dialog.tsx). Pops true once recorded.
class _PurchaseDialog extends StatefulWidget {
  const _PurchaseDialog({
    required this.api,
    required this.farmId,
    required this.items,
    required this.suppliers,
    required this.accounts,
    required this.costModes,
    required this.money,
    this.itemId,
  });
  final ApiClient api;
  final String farmId;
  final List<Map<String, dynamic>> items, suppliers, accounts, costModes;
  final FarmMoney money;
  final int? itemId;
  @override
  State<_PurchaseDialog> createState() => _PurchaseDialogState();
}

class _PurchaseDialogState extends State<_PurchaseDialog> {
  late int _itemId = widget.itemId ?? 0;
  int _supplierId = 0;
  late int _accountId = widget.accounts.isEmpty ? 0 : tIntOrNull(widget.accounts.first['hotelCashAccountId']) ?? 0;
  DateTime? _date = DateTime.now(), _due;
  String _method = 'Cash';
  final _quantity = TextEditingController(text: '0');
  final _total = TextEditingController(text: '0');
  final _paidText = TextEditingController(text: '0');
  final _notes = TextEditingController();
  // Until an amount is typed, "Amount paid" follows the total (nothing, on Credit).
  bool _paidTouched = false, _saving = false;

  Map<String, dynamic>? get _item => widget.items.where((i) => tIntOrNull(i['hotelInventoryItemId']) == _itemId).firstOrNull;
  num get _qty => double.tryParse(_quantity.text) ?? 0;
  num get _totalCost => double.tryParse(_total.text) ?? 0;
  bool get _credit => _method == 'Credit';
  num get _paid => _paidTouched ? (double.tryParse(_paidText.text) ?? 0) : (_credit ? 0 : _totalCost);
  num get _balance => (_totalCost - _paid) < 0 ? 0 : _totalCost - _paid;
  String get _mode =>
      tStr(
        widget.costModes.where((m) => tStr(m['category']).toLowerCase() == tStr(_item?['category']).toLowerCase()).firstOrNull?['costMode'],
      ).isEmpty
      ? 'EXPENSE_WHEN_PURCHASED'
      : tStr(widget.costModes.firstWhere((m) => tStr(m['category']).toLowerCase() == tStr(_item?['category']).toLowerCase())['costMode']);

  void _syncPaid() {
    if (!_paidTouched) _paidText.text = _qtyText(_paid);
  }

  static String _qtyText(num n) => n == n.roundToDouble() ? '${n.toInt()}' : '$n';

  Future<void> _save() async {
    if (_itemId == 0) return trackerToast(context, 'Pick a supply item', error: true);
    if (_qty <= 0) return trackerToast(context, 'Quantity must be greater than 0', error: true);
    if (_paid > _totalCost) return trackerToast(context, 'Amount paid cannot be more than the total cost', error: true);
    if (_balance > 0 && _supplierId == 0) {
      return trackerToast(
        context,
        'Choose the supplier',
        description: 'Part of this purchase is still owed; Supplier Balances needs to know to whom.',
        error: true,
      );
    }
    if (_paid > 0 && _accountId == 0) return trackerToast(context, 'Choose the cash account this was paid from', error: true);
    setState(() => _saving = true);
    try {
      await widget.api.post(
        '/api/Hotel/supplies/purchases',
        query: {'farmId': widget.farmId},
        body: {
          'itemId': _itemId,
          'quantity': _qty,
          'totalCost': _totalCost,
          'purchaseDate': _date == null ? null : hotelYmd(_date!),
          'supplierId': _supplierId == 0 ? null : _supplierId,
          'paymentMethod': _method,
          'amountPaid': _paid,
          'cashAccountId': _paid > 0 && _accountId != 0 ? _accountId : null,
          'dueDate': _balance > 0 && _due != null ? hotelYmd(_due!) : null,
          'notes': _notes.text.isEmpty ? null : _notes.text,
          'farmId': widget.farmId,
        },
      );
      if (!mounted) return;
      trackerToast(context, 'Purchase recorded');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Save failed', description: e.message, error: true);
    }
  }

  Widget _ro(String text) => Container(
    height: 44,
    alignment: Alignment.centerLeft,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: TColors.slate100,
      border: Border.all(color: TColors.slate300),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate600),
    ),
  );

  Widget _numInput(TextEditingController c, {ValueChanged<String>? onChanged, bool enabled = true}) => AppInput(
    controller: c,
    enabled: enabled,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
    onChanged: onChanged,
  );

  @override
  Widget build(BuildContext context) {
    final unit = tStr(_item?['unit']).isEmpty ? 'unit' : tStr(_item?['unit']);
    final unitCost = _qty > 0 ? _totalCost / _qty : 0;
    final fmt = widget.money;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: const FormDialogTitle(icon: Icons.shopping_cart_outlined, color: FormColor.purple, text: 'New purchase'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TintedSection(
                title: 'Item, Supplier & Date',
                color: FormColor.blue,
                children: [
                  FilterLabel(
                    'Supply item *',
                    AppSelect<int>(
                      value: _itemId == 0 ? null : _itemId,
                      hintText: 'Pick item',
                      items: [
                        for (final i in widget.items)
                          if (i['isActive'] != false)
                            AppSelectItem(
                              value: tIntOrNull(i['hotelInventoryItemId']) ?? 0,
                              label:
                                  '${tStr(i['name'])}${tStr(i['unit']).isEmpty ? '' : ' (${tStr(i['unit'])})'}'
                                  '${tStr(i['category']).isEmpty ? '' : ' · ${tStr(i['category'])}'}',
                            ),
                      ],
                      onChanged: (v) => setState(() => _itemId = v ?? 0),
                    ),
                  ),
                  FilterLabel(
                    'Supplier',
                    AppSelect<int>(
                      value: _supplierId,
                      items: [
                        const AppSelectItem(value: 0, label: 'Not linked to a supplier'),
                        for (final s in widget.suppliers)
                          if (s['isActive'] != false)
                            AppSelectItem(value: tIntOrNull(s['hotelSupplierId']) ?? 0, label: tStr(s['supplierName'])),
                      ],
                      onChanged: (v) => setState(() => _supplierId = v ?? 0),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: FilterLabel(
                          'Purchase date',
                          AppDateField(value: _date, lastDate: DateTime.now(), onChanged: (d) => setState(() => _date = d)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilterLabel(
                          'Payment method',
                          AppSelect<String>(
                            value: _method,
                            items: [for (final m in _paymentMethods) AppSelectItem(value: m, label: m)],
                            onChanged: (v) => setState(() {
                              _method = v ?? _method;
                              _syncPaid();
                            }),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TintedSection(
                title: 'Purchase Quantity & Costing',
                color: FormColor.sky,
                children: [
                  FilterLabel('Purchase quantity ($unit) *', _numInput(_quantity, onChanged: (_) => setState(() {}))),
                  FilterLabel(
                    'Total purchase cost *',
                    _numInput(
                      _total,
                      onChanged: (_) => setState(() {
                        _syncPaid();
                      }),
                    ),
                  ),
                  FilterLabel('Purchase unit cost (auto)', _ro('${fmt(unitCost)} per $unit')),
                  FilterLabel('Cost recognition', _ro(_item == null ? '—' : _costModeLabels[_mode]!)),
                  Text(
                    _mode == 'EXPENSE_WHEN_CONSUMED'
                        ? '${tStr(_item?['category']).isEmpty ? 'This category' : tStr(_item?['category'])} is expensed when consumed: the cost is '
                              'held as stock value and reaches Profit & Loss as the stock is used (Internal Use).'
                        : 'Expensed when purchased: the whole cost reaches Profit & Loss on the purchase date, and using the stock adds no second expense.',
                    style: const TextStyle(fontSize: 12, color: TColors.slate500),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TintedSection(
                title: 'Payment',
                color: FormColor.amber,
                children: [
                  FilterLabel(
                    'Amount paid',
                    _numInput(
                      _paidText,
                      onChanged: (_) => setState(() {
                        _paidTouched = true;
                      }),
                    ),
                  ),
                  FilterLabel(
                    'Pay from cash account',
                    AppSelect<int>(
                      value: _accountId == 0 ? null : _accountId,
                      enabled: _paid > 0,
                      hintText: _paid <= 0 ? 'None (no cash movement)' : 'Choose an account',
                      items: [
                        for (final a in widget.accounts)
                          AppSelectItem(
                            value: tIntOrNull(a['hotelCashAccountId']) ?? 0,
                            label: '${tStr(a['accountName'])} (${fmt(tNum(a['currentBalance']))})',
                          ),
                      ],
                      onChanged: (v) => setState(() => _accountId = v ?? 0),
                    ),
                  ),
                  FilterLabel('Balance (auto)', _ro(fmt(_balance))),
                  FilterLabel('Due date', AppDateField(value: _due, enabled: _balance > 0, onChanged: (d) => setState(() => _due = d))),
                  const Text(
                    'The cash account is charged only for the amount paid now. Any balance is owed to the supplier and appears on Supplier Balances.',
                    style: TextStyle(fontSize: 12, color: TColors.slate500),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TintedSection(
                title: 'Notes',
                color: FormColor.slate,
                children: [FilterLabel('Notes', AppTextarea(controller: _notes, hintText: 'Optional notes about this purchase'))],
              ),
            ],
          ),
        ),
        actions: [
          FormDialogFooter(
            onCancel: () => Navigator.pop(context),
            cancelDisabled: _saving,
            children: [
              FilledButton(
                style: hotelPrimary,
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Reverse purchase": a reason from STOCK_REVERSAL_REASONS. Pops true once done.
class _ReverseDialog extends StatefulWidget {
  const _ReverseDialog({required this.api, required this.farmId, required this.purchase});
  final ApiClient api;
  final String farmId;
  final Map<String, dynamic> purchase;
  @override
  State<_ReverseDialog> createState() => _ReverseDialogState();
}

class _ReverseDialogState extends State<_ReverseDialog> {
  String _reason = '';
  bool _busy = false;

  Future<void> _reverse() async {
    setState(() => _busy = true);
    try {
      await widget.api.post(
        '/api/Hotel/supplies/purchases/${widget.purchase['purchaseId']}/reverse',
        query: {'farmId': widget.farmId},
        body: {'farmId': widget.farmId, 'reason': _reason.trim()},
      );
      if (!mounted) return;
      trackerToast(context, 'Purchase reversed');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      trackerToast(context, 'Failed', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      scrollable: true,
      title: const FormDialogTitle(icon: Icons.undo, color: FormColor.red, text: 'Reverse purchase'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'PO-${widget.purchase['purchaseId']} · ${tStr(widget.purchase['itemName'])}. The stock goes back out and any cash paid comes back today.',
              style: const TextStyle(fontSize: 14, color: TColors.slate600),
            ),
            const SizedBox(height: 12),
            FilterLabel(
              'Why is this being reversed? *',
              ReasonSelect(options: stockReversalReasons, value: _reason, onChanged: (v) => setState(() => _reason = v)),
            ),
          ],
        ),
      ),
      actions: [
        FormDialogFooter(
          onCancel: () => Navigator.pop(context),
          cancelDisabled: _busy,
          children: [
            FilledButton(
              style: formPrimary(FormColor.red),
              onPressed: _busy || _reason.trim().isEmpty ? null : _reverse,
              child: Text(_busy ? 'Reversing…' : 'Reverse'),
            ),
          ],
        ),
      ],
    ),
  );
}
