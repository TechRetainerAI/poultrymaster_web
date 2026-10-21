import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/expenses/deferred_costs_screen.dart' show qtyFmt;
import '../poultry/money/money_widgets.dart';
import '../poultry/purchase/raw_material_dialogs.dart' show RecalculateStockDialog;
import '../poultry/reports/report_format.dart';
import '../poultry/sales/balances_logic.dart' show pageSlice;
import '../poultry/sales/balances_widgets.dart';
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull, SortState, toggleSort, sortRows;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/business_dates.dart';
import '../shared/company_clock.dart';
import 'water_expenses_screen.dart' show WaterAddSupplierDialog;

/// Water → Operations → Inventory → Raw materials & supplies, as
/// `app/water-raw-materials/page.tsx`: the Items, Purchases and Usage history
/// tabs (`?tab=`, with `?purchaseId=` focusing one purchase from Supplier
/// Balances), New / Edit item, Record / Edit purchase with its production
/// conversion, Pay balance, Delete and Recalculate stock.

const waterRawCategories = ['PackagingRoll', 'SachetFilm', 'OuterBag', 'Chemical', 'Filter', 'UVLamp', 'SparePart', 'Fuel', 'CleaningSupply', 'Other'];
const waterPaymentMethods = ['Cash', 'MoMo', 'Bank', 'Credit'];
const waterRawUnits = [
  'Roll', 'Bag', 'Sachet', 'Bottle', 'Piece', 'Pack', 'Carton', 'Box', 'Bundle', 'Dozen', 'Litre', 'Millilitre', 'Tonne', 'Kilogram', 'Gram',
  'Bale', 'Unit', 'Other',
];
const waterUsageMethods = [('FIFO', 'First bought, first used'), ('LIFO', 'Last bought, first used'), ('HIFO', 'Highest cost, first used')];

String _today() => DateTime.now().toUtc().toIso8601String().substring(0, 10);

/// A number as the web's NumberInput shows it: up to [dp] decimals, no trailing zeros.
String numText(num v, [int dp = 4]) {
  final s = v.toStringAsFixed(dp);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}

/// The unit list with the item's own unit kept in front when it is custom.
List<String> waterUnitOptions(String? current) {
  final c = (current ?? '').trim();
  return c.isNotEmpty && !waterRawUnits.contains(c) ? [c, ...waterRawUnits] : waterRawUnits;
}

/// filterByDateAndSearch for any tab: [dateKey] null skips the date range.
List<Map> filterWaterRows(List<Map> rows, List<String> keys, {String search = '', String? dateKey, String from = '', String to = ''}) {
  final q = search.trim().toLowerCase();
  return rows.where((r) {
    if (dateKey != null) {
      final day = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(tStr(r[dateKey]))?[1];
      if (day != null) {
        if (from.isNotEmpty && day.compareTo(from) < 0) return false;
        if (to.isNotEmpty && day.compareTo(to) > 0) return false;
      }
    }
    return q.isEmpty || keys.any((k) => r[k] != null && '${r[k]}'.toLowerCase().contains(q));
  }).toList();
}

/// Manual stock adjustments shown in Usage history: a decrease reads as a
/// positive "used", an increase as a negative one (a return).
Map<String, Object?> waterAdjustmentAsUsage(Map a) => {
      'waterRawMaterialUsageId': -(tIntOrNull(a['waterRawMaterialAdjustmentId']) ?? 0),
      'waterRawMaterialItemId': a['waterRawMaterialItemId'],
      'itemName': a['itemName'],
      'unitOfMeasure': a['unitOfMeasure'],
      'usedDate': a['adjustedDate'],
      'quantityUsed': -tNum(a['quantity']),
      'expectedQuantityUsed': null,
      'variance': 0,
      'varianceReason':
          'Manual adjustment${tStr(a['movementType']).isNotEmpty ? ' (${tStr(a['movementType'])})' : ''}${tStr(a['note']).isNotEmpty ? ' — ${tStr(a['note'])}' : ''}',
      'unitCost': a['unitCost'],
      'notes': a['note'],
      'createdAt': a['createdAt'],
    };

class WaterRawMaterialsScreen extends StatefulWidget {
  const WaterRawMaterialsScreen({super.key, required this.session, required this.company, this.tab, this.purchaseId});
  final Session session;
  final Company company;

  /// `?tab=` (items, purchases, usage) and `?purchaseId=`.
  final String? tab;
  final int? purchaseId;

  @override
  State<WaterRawMaterialsScreen> createState() => _WaterRawMaterialsScreenState();
}

class _WaterRawMaterialsScreenState extends State<WaterRawMaterialsScreen> {
  List<Map> _items = [], _purchases = [], _accounts = [], _usage = [];
  bool _loading = true, _usageLoaded = false, _usageLoading = false;
  late String _tab = const ['items', 'purchases', 'usage'].contains(widget.tab) ? widget.tab! : 'items';
  late int? _focus = widget.purchaseId;
  final _search = TextEditingController();
  String _from = '', _to = '', _itemFilter = 'all', _category = 'all', _unit = 'all';
  SortState _itemsSort = (key: null, dir: null), _purchasesSort = (key: null, dir: null), _usageSort = (key: null, dir: null);
  int _page = 1, _pageSize = 10;
  FarmMoney _gh = const FarmMoney();
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _gh = m);
    });
    CompanyClock.load(widget.session, widget.company).then((c) {
      if (mounted) setState(() => _offset = c.offset);
    });
    _load();
    if (_tab == 'usage') _loadUsage();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final q = {'farmId': _farmId};
    try {
      final r = await Future.wait([
        _api.get('/api/Water/raw-material-items', query: q),
        _api.get('/api/Water/raw-material-purchases', query: q),
        _api.get('/api/Water/cash-accounts', query: q),
      ]);
      if (!mounted) return;
      setState(() {
        _items = rowsOf(r[0]);
        _purchases = rowsOf(r[1]);
        _accounts = rowsOf(r[2]);
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load raw materials', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadUsage() async {
    if (_usageLoaded) return;
    setState(() => _usageLoading = true);
    final q = {'farmId': _farmId};
    try {
      final r = await Future.wait([
        _api.get('/api/Water/raw-material-usage/history', query: q),
        _api.get('/api/Water/raw-material-adjustments', query: q).catchError((_) => const <Map>[]),
      ]);
      if (mounted) setState(() => _usage = [...rowsOf(r[0]), for (final a in rowsOf(r[1])) waterAdjustmentAsUsage(a)]);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, "Couldn't load usage history", description: e.message, error: true);
    }
    if (mounted) {
      setState(() {
        _usageLoading = false;
        _usageLoaded = true;
      });
    }
  }

  void _selectTab(String t) {
    setState(() {
      _tab = t;
      _page = 1;
    });
    if (t == 'usage') _loadUsage();
  }

  String _itemName(Map row) {
    if (tStr(row['itemName']).isNotEmpty) return tStr(row['itemName']);
    final it = _items.where((i) => tIntOrNull(i['waterRawMaterialItemId']) == tIntOrNull(row['waterRawMaterialItemId'])).firstOrNull;
    return tStr(it?['itemName']).isEmpty ? '—' : tStr(it?['itemName']);
  }

  num _total(Map p) => p['totalCost'] != null ? tNum(p['totalCost']) : tNum(p['quantity']) * tNum(p['unitCost']);

  Future<void> _dialog(Widget d) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => d);
    if (ok == true) await _load();
  }

  Future<void> _itemDialog([Map? item]) => _dialog(_ItemDialog(session: widget.session, company: widget.company, item: item));

  Future<void> _purchaseDialog([Map? p]) =>
      _dialog(_PurchaseDialog(session: widget.session, company: widget.company, items: _items, accounts: _accounts, purchase: p, fmt: _gh));

  Future<void> _deleteItem(Map it) async {
    final ok = await confirmDelete(context,
        title: 'Deactivate raw material item?',
        description:
            '"${tStr(it['itemName'])}" will be hidden from new purchases. Existing purchases and usage history stay intact. You can reactivate it later by editing and ticking Active.',
        confirmLabel: 'Deactivate');
    if (!ok) return;
    try {
      await _api.delete('/api/Water/raw-material-items/${tStr(it['waterRawMaterialItemId'])}', query: {'farmId': _farmId});
      if (mounted) trackerToast(context, 'Item deactivated');
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Delete failed', description: e.message, error: true);
    }
  }

  Future<void> _deletePurchase(Map p) async {
    final it = _items.where((i) => tIntOrNull(i['waterRawMaterialItemId']) == tIntOrNull(p['waterRawMaterialItemId'])).firstOrNull;
    final unit = tStr(it?['unitOfMeasure']).isEmpty ? 'units' : tStr(it?['unitOfMeasure']);
    final name = tStr(p['itemName']).isNotEmpty ? tStr(p['itemName']) : (tStr(it?['itemName']).isNotEmpty ? tStr(it?['itemName']) : 'this item');
    final ok = await confirmDelete(context,
        title: 'Delete purchase?',
        description:
            'This will subtract ${tStr(p['quantity'])} $unit of "$name" from current stock. If some has already been used in production, the delete will fail — reverse those usages first.');
    if (!ok) return;
    try {
      await _api.delete('/api/Water/raw-material-purchases/${tStr(p['waterRawMaterialPurchaseId'])}', query: {'farmId': _farmId});
      if (mounted) trackerToast(context, 'Purchase deleted');
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Delete failed', description: e.message, error: true);
    }
  }

  Future<void> _payBalance(Map p) => _dialog(_PayBalanceDialog(session: widget.session, company: widget.company, purchase: p, fmt: _gh));

  Widget _itemSelect() => AppSelect<String>(
        value: _itemFilter,
        hintText: 'All items',
        items: [
          const AppSelectItem(value: 'all', label: 'All items'),
          for (final i in _items) AppSelectItem(value: tStr(i['waterRawMaterialItemId']), label: tStr(i['itemName'])),
        ],
        onChanged: (v) => setState(() {
          _itemFilter = v ?? 'all';
          _page = 1;
        }),
      );

  List<Map> _byItem(List<Map> rows) => _itemFilter == 'all' ? rows : [for (final r in rows) if (tStr(r['waterRawMaterialItemId']) == _itemFilter) r];

  ListFiltersCard _filters(String placeholder, {bool searchOnly = false, List<Widget> extras = const []}) => ListFiltersCard(
        search: _search,
        searchPlaceholder: placeholder,
        searchOnly: searchOnly,
        onSearch: () => setState(() => _page = 1),
        from: _from,
        to: _to,
        onDates: (f, t) => setState(() {
          _from = f;
          _to = t;
          _page = 1;
        }),
        onClear: () => setState(() {
          _search.clear();
          _from = '';
          _to = '';
        }),
        extras: extras,
      );

  CompactPager _pager(int total) => CompactPager(
        total: total,
        page: _page,
        pageSize: _pageSize,
        onPage: (p) => setState(() => _page = p),
        onPageSize: (v) => setState(() {
          _pageSize = v;
          _page = 1;
        }),
      );

  Widget _box(Widget child) => Container(
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
        child: child,
      );

  Widget _empty(String t) => Padding(padding: const EdgeInsets.all(32), child: Text(t, textAlign: TextAlign.center, style: const TextStyle(color: TColors.slate500)));

  Widget _activeBadge(Map it) => it['isActive'] == true
      ? const TBadge('Active', bg: Color(0xFFDCFCE7), fg: Color(0xFF15803D))
      : const TBadge('Inactive', bg: Colors.white, fg: TColors.slate700, border: TColors.slate300);

  Widget _outline(String s) => TBadge(s, bg: Colors.white, fg: TColors.slate700, border: TColors.slate300);

  List<Widget> _itemsTab() {
    final units = <String>{for (final i in _items) ...[if (tStr(i['unitOfMeasure']).isNotEmpty) tStr(i['unitOfMeasure']), if (tStr(i['purchaseUnitOfMeasure']).isNotEmpty) tStr(i['purchaseUnitOfMeasure'])]}.toList()
      ..sort();
    var rows = filterWaterRows(_items, const ['itemName', 'category'], search: _search.text);
    if (_category != 'all') rows = [for (final i in rows) if (tStr(i['category']) == _category) i];
    if (_unit != 'all') rows = [for (final i in rows) if (tStr(i['unitOfMeasure']) == _unit || tStr(i['purchaseUnitOfMeasure']) == _unit) i];
    final sorted = sortRows(rows, _itemsSort, (Map i, String k) => i[k]);
    final low = [for (final i in _items) if (i['isActive'] == true && tNum(i['currentQuantity']) <= tNum(i['minimumStockAlert'])) i];
    bool isLow(Map i) => tNum(i['currentQuantity']) <= tNum(i['minimumStockAlert']);
    return [
      _filters('Search item or category', searchOnly: true, extras: [
        AppSelect<String>(
          value: _category,
          hintText: 'All categories',
          items: [const AppSelectItem(value: 'all', label: 'All categories'), for (final c in waterRawCategories) AppSelectItem(value: c, label: c)],
          onChanged: (v) => setState(() => _category = v ?? 'all'),
        ),
        AppSelect<String>(
          value: _unit,
          hintText: 'All units',
          items: [const AppSelectItem(value: 'all', label: 'All units'), for (final u in units) AppSelectItem(value: u, label: u)],
          onChanged: (v) => setState(() => _unit = v ?? 'all'),
        ),
      ]),
      if (low.isNotEmpty) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: TColors.amber50, border: Border.all(color: const Color(0xFFFDE68A)), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Low-stock items (${low.length})', style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.amber900)),
            const SizedBox(height: 4),
            Text(low.map((i) => '${tStr(i['itemName'])} (${qtyFmt(i['currentQuantity'])} / min ${qtyFmt(i['minimumStockAlert'])})').join(' · '),
                style: const TextStyle(fontSize: 13, color: TColors.slate700)),
          ]),
        ),
      ],
      const SizedBox(height: 12),
      _box(_loading
          ? const Padding(padding: EdgeInsets.all(16), child: LoadingLine('Loading…'))
          : _items.isEmpty
              ? _empty('No raw material items yet.')
              : MobileCardList<Map>(
                  striped: true,
                  items: pageSlice(sorted, _page, _pageSize),
                  keyOf: (i) => tStr(i['waterRawMaterialItemId']),
                  primary: (i) => tStr(i['itemName']),
                  secondaryBuilder: (i) => Wrap(spacing: 6, children: [_outline(tStr(i['category'])), _activeBadge(i)]),
                  highlights: (i) => [
                    Highlight('Current', qtyFmt(i['currentQuantity']), accent: isLow(i) ? Accent.rose : Accent.emerald),
                    Highlight('Min alert', qtyFmt(i['minimumStockAlert']), accent: Accent.blue),
                  ],
                  details: (i) => [
                    ('Category', tStr(i['category'])),
                    ('Purchase Unit', tStr(i['purchaseUnitOfMeasure']).isEmpty ? '—' : tStr(i['purchaseUnitOfMeasure'])),
                    ('Production Unit', tStr(i['unitOfMeasure']).isEmpty ? '—' : tStr(i['unitOfMeasure'])),
                    ('Status', i['isActive'] == true ? 'Active' : 'Inactive'),
                  ],
                  actions: (i) => [
                    OutlinedButton.icon(onPressed: () => _itemDialog(i), icon: const Icon(Icons.edit_outlined, size: 16), label: const Text('Edit')),
                    OutlinedButton.icon(
                      onPressed: () => _deleteItem(i),
                      style: OutlinedButton.styleFrom(foregroundColor: TColors.red600, side: const BorderSide(color: Color(0xFFFECACA))),
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('Delete'),
                    ),
                  ],
                  table: (page) => TrackerTable(
                    sort: _itemsSort,
                    onSort: (k) => setState(() => _itemsSort = toggleSort(k, _itemsSort)),
                    columns: const [
                      TCol('Name', sortKey: 'itemName', width: 150), TCol('Category', sortKey: 'category', width: 120),
                      TCol('Purchase Unit', sortKey: 'purchaseUnitOfMeasure', width: 110), TCol('Production Unit', sortKey: 'unitOfMeasure', width: 120),
                      TCol('Current', sortKey: 'currentQuantity', right: true, width: 90), TCol('Min alert', sortKey: 'minimumStockAlert', right: true, width: 90),
                      TCol('Status', sortKey: 'isActive', width: 90), TCol('Actions', right: true, width: 100),
                    ],
                    rows: [
                      for (final i in page)
                        [
                          cellText(tStr(i['itemName']), bold: true),
                          Align(alignment: Alignment.centerLeft, child: _outline(tStr(i['category']))),
                          cellText(tStr(i['purchaseUnitOfMeasure']).isEmpty ? '—' : tStr(i['purchaseUnitOfMeasure'])),
                          cellText(tStr(i['unitOfMeasure']).isEmpty ? '—' : tStr(i['unitOfMeasure'])),
                          Align(
                            alignment: Alignment.centerRight,
                            child: cellText(qtyFmt(i['currentQuantity']), color: isLow(i) ? const Color(0xFFE11D48) : null, bold: isLow(i)),
                          ),
                          Align(alignment: Alignment.centerRight, child: cellText(qtyFmt(i['minimumStockAlert']))),
                          Align(alignment: Alignment.centerLeft, child: _activeBadge(i)),
                          Wrap(alignment: WrapAlignment.end, children: [
                            IconButton(tooltip: 'Edit', onPressed: () => _itemDialog(i), icon: const Icon(Icons.edit_outlined, size: 18)),
                            IconButton(tooltip: 'Delete', onPressed: () => _deleteItem(i), icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444))),
                          ]),
                        ],
                    ],
                  ),
                  pager: _pager(sorted.length),
                )),
    ];
  }

  List<Widget> _purchasesTab() {
    final rows = _focus != null
        ? [for (final p in _purchases) if (tIntOrNull(p['waterRawMaterialPurchaseId']) == _focus) p]
        : _byItem(filterWaterRows(_purchases, const ['itemName', 'supplierName'], search: _search.text, dateKey: 'purchaseDate', from: _from, to: _to));
    final sorted = sortRows(rows, _purchasesSort, (Map p, String k) => p[k]);
    final focusSupplier = _focus == null ? null : _purchases.where((p) => tIntOrNull(p['waterRawMaterialPurchaseId']) == _focus).firstOrNull?['supplierName'];
    String prodLevel(Map p) => p['productionQuantity'] != null ? '${qtyFmt(p['productionQuantity'])} ${tStr(p['productionUnit'])}'.trim() : '—';
    List<Widget> actions(Map p) => [
          if (tNum(p['balance']) > 0)
            OutlinedButton.icon(
              onPressed: () => _payBalance(p),
              style: OutlinedButton.styleFrom(foregroundColor: TColors.emerald700, side: const BorderSide(color: TColors.emerald300)),
              icon: const Icon(Icons.account_balance_wallet_outlined, size: 16),
              label: const Text('Pay balance'),
            ),
          OutlinedButton.icon(onPressed: () => _purchaseDialog(p), icon: const Icon(Icons.edit_outlined, size: 16), label: const Text('Edit')),
          OutlinedButton.icon(
            onPressed: () => _deletePurchase(p),
            style: OutlinedButton.styleFrom(foregroundColor: TColors.red600, side: const BorderSide(color: Color(0xFFFECACA))),
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('Delete'),
          ),
        ];
    return [
      if (_focus != null) ...[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: const Color(0xFFF0F9FF), border: Border.all(color: const Color(0xFFBAE6FD)), borderRadius: BorderRadius.circular(6)),
          child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Showing purchase '),
                TextSpan(text: '#$_focus', style: const TextStyle(fontWeight: FontWeight.w700)),
                const TextSpan(text: ' only'),
                if (tStr(focusSupplier).isNotEmpty) ...[
                  const TextSpan(text: ' — '),
                  TextSpan(text: tStr(focusSupplier), style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
                const TextSpan(text: '.'),
              ]),
              style: const TextStyle(fontSize: 13, color: Color(0xFF0C4A6E)),
            ),
            TextButton(onPressed: () => setState(() => _focus = null), child: const Text('Show all purchases')),
          ]),
        ),
        const SizedBox(height: 12),
      ],
      _filters('Search item or supplier', extras: [_itemSelect()]),
      const SizedBox(height: 12),
      _box(rows.isEmpty
          ? _empty(_focus != null ? 'Purchase #$_focus is not in this list.' : 'No purchases recorded yet.')
          : MobileCardList<Map>(
              striped: true,
              items: pageSlice(sorted, _page, _pageSize),
              keyOf: (p) => tStr(p['waterRawMaterialPurchaseId']),
              primary: _itemName,
              secondary: (p) => '${fmtDateTime(p['purchaseDate'], p, _offset)} · ${_gh(_total(p))}',
              highlights: (p) => [
                Highlight('Total', _gh(_total(p)), accent: Accent.violet),
                Highlight('Balance', _gh(tNum(p['balance'])), accent: tNum(p['balance']) > 0 ? Accent.rose : Accent.emerald),
              ],
              details: (p) => [
                ('Date', fmtDateTime(p['purchaseDate'], p, _offset)),
                ('Item', _itemName(p)),
                ('Supplier', tStr(p['supplierName']).isEmpty ? '—' : tStr(p['supplierName'])),
                ('Purchase Qty', tStr(p['quantity'])),
                ('Production Level Qty', prodLevel(p)),
                ('Unit Price', _gh(tNum(p['unitCost']))),
                ('Method', tStr(p['paymentMethod']).isEmpty ? '—' : tStr(p['paymentMethod'])),
                (
                  'Production',
                  tStr(p['productionUnit']).isNotEmpty
                      ? '${qtyFmt(p['productionQuantity'])} ${tStr(p['productionUnit'])}${tNum(p['productionUnitCost']) != 0 ? ' @ ${_gh(tNum(p['productionUnitCost']))}' : ''}'
                      : '—'
                ),
              ],
              actions: actions,
              table: (page) => TrackerTable(
                sort: _purchasesSort,
                onSort: (k) => setState(() => _purchasesSort = toggleSort(k, _purchasesSort)),
                columns: const [
                  TCol('Date', sortKey: 'purchaseDate', width: 120), TCol('Item', sortKey: 'itemName', width: 130), TCol('Supplier', sortKey: 'supplierName', width: 120),
                  TCol('Purchase Qty', sortKey: 'quantity', right: true, width: 100), TCol('Production Level Qty', sortKey: 'productionQuantity', right: true, width: 150),
                  TCol('Unit Price', sortKey: 'unitCost', right: true, width: 100), TCol('Total', sortKey: 'totalCost', right: true, width: 110),
                  TCol('Method', sortKey: 'paymentMethod', width: 80), TCol('Balance', sortKey: 'balance', right: true, width: 100),
                  TCol('Actions', right: true, width: 140),
                ],
                rows: [
                  for (final p in page)
                    [
                      cellText(fmtDateTime(p['purchaseDate'], p, _offset)),
                      cellText(_itemName(p)),
                      cellText(tStr(p['supplierName']).isEmpty ? '—' : tStr(p['supplierName'])),
                      Align(alignment: Alignment.centerRight, child: cellText(tStr(p['quantity']))),
                      Align(alignment: Alignment.centerRight, child: cellText(prodLevel(p))),
                      Align(alignment: Alignment.centerRight, child: cellText(_gh(tNum(p['unitCost'])))),
                      Align(alignment: Alignment.centerRight, child: cellText(_gh(_total(p)))),
                      cellText(tStr(p['paymentMethod']).isEmpty ? '—' : tStr(p['paymentMethod'])),
                      Align(
                        alignment: Alignment.centerRight,
                        child: cellText(_gh(tNum(p['balance'])), color: tNum(p['balance']) > 0 ? const Color(0xFFE11D48) : null),
                      ),
                      Wrap(alignment: WrapAlignment.end, children: [
                        if (tNum(p['balance']) > 0)
                          IconButton(
                            tooltip: 'Pay balance',
                            onPressed: () => _payBalance(p),
                            icon: const Icon(Icons.account_balance_wallet_outlined, size: 18, color: TColors.emerald700),
                          ),
                        IconButton(tooltip: 'Edit', onPressed: () => _purchaseDialog(p), icon: const Icon(Icons.edit_outlined, size: 18)),
                        IconButton(tooltip: 'Delete', onPressed: () => _deletePurchase(p), icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444))),
                      ]),
                    ],
                ],
              ),
              pager: _pager(sorted.length),
            )),
    ];
  }

  List<Widget> _usageTab() {
    final rows = _byItem(filterWaterRows(_usage, const ['itemName'], search: _search.text, dateKey: 'usedDate', from: _from, to: _to));
    final sorted = sortRows(rows, _usageSort, (Map u, String k) => u[k]);
    return [
      _filters('Search item', extras: [_itemSelect()]),
      const SizedBox(height: 12),
      _box(_usageLoading && !_usageLoaded
          ? const Padding(padding: EdgeInsets.all(16), child: LoadingLine('Loading usage…'))
          : _usage.isEmpty
              ? _empty('No usage recorded yet. Raw materials & supplies are consumed when production records are approved.')
              : MobileCardList<Map>(
                  striped: true,
                  items: pageSlice(sorted, _page, _pageSize),
                  keyOf: (u) => tStr(u['waterRawMaterialUsageId']),
                  primary: (u) => tStr(u['itemName']).isEmpty ? '—' : tStr(u['itemName']),
                  secondary: (u) => '${fmtDateTime(u['usedDate'], u, _offset)} · ${qtyFmt(u['quantityUsed'])} ${tStr(u['unitOfMeasure'])}',
                  highlights: (u) => [
                    Highlight('Qty used', qtyFmt(u['quantityUsed']), accent: Accent.blue),
                    Highlight('Cost', tNum(u['totalCost']) != 0 ? _gh(tNum(u['totalCost'])) : '—', accent: Accent.violet),
                  ],
                  details: (u) => [
                    ('Date', fmtDateTime(u['usedDate'], u, _offset)),
                    ('Material', tStr(u['itemName']).isEmpty ? '—' : tStr(u['itemName'])),
                    ('Unit', tStr(u['unitOfMeasure']).isEmpty ? '—' : tStr(u['unitOfMeasure'])),
                    ('Source batch', tStr(u['batchNumber']).isEmpty ? '—' : tStr(u['batchNumber'])),
                    ('Finished product', tStr(u['finishedProductName']).isEmpty ? '—' : tStr(u['finishedProductName'])),
                  ],
                  table: (page) => TrackerTable(
                    sort: _usageSort,
                    onSort: (k) => setState(() => _usageSort = toggleSort(k, _usageSort)),
                    columns: const [
                      TCol('Date', sortKey: 'usedDate', width: 120), TCol('Material', sortKey: 'itemName', width: 130),
                      TCol('Qty used', sortKey: 'quantityUsed', right: true, width: 90), TCol('Unit', sortKey: 'unitOfMeasure', width: 80),
                      TCol('Cost', sortKey: 'totalCost', right: true, width: 100), TCol('Source batch', sortKey: 'batchNumber', width: 120),
                      TCol('Finished product', sortKey: 'finishedProductName', width: 130),
                    ],
                    rows: [
                      for (final u in page)
                        [
                          cellText(fmtDateTime(u['usedDate'], u, _offset)),
                          cellText(tStr(u['itemName']).isEmpty ? '—' : tStr(u['itemName']), bold: true),
                          Align(alignment: Alignment.centerRight, child: cellText(qtyFmt(u['quantityUsed']))),
                          cellText(tStr(u['unitOfMeasure']).isEmpty ? '—' : tStr(u['unitOfMeasure'])),
                          Align(alignment: Alignment.centerRight, child: cellText(tNum(u['totalCost']) != 0 ? _gh(tNum(u['totalCost'])) : '—')),
                          cellText(tStr(u['batchNumber']).isEmpty ? '—' : tStr(u['batchNumber']), color: TColors.slate600),
                          cellText(tStr(u['finishedProductName']).isEmpty ? '—' : tStr(u['finishedProductName']), color: TColors.slate600),
                        ],
                    ],
                  ),
                  pager: _pager(sorted.length),
                )),
    ];
  }

  Widget _tabButton(String key, String label) {
    final on = _tab == key;
    return Expanded(
      child: InkWell(
        onTap: () => _selectTab(key),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(color: on ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(6)),
          child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: on ? TColors.slate900 : TColors.slate500)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/water-supply-purchases');
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Inventory & supply purchases')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            const Row(children: [
              Icon(Icons.inbox_outlined, color: Color(0xFF0284C7)),
              SizedBox(width: 8),
              Flexible(child: Text('Inventory & supply purchases', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900))),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                onPressed: () => _dialog(RecalculateStockDialog(session: widget.session, company: widget.company, items: _items, water: true)),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Recalculate stock'),
              ),
              OutlinedButton.icon(onPressed: () => _itemDialog(), icon: const Icon(Icons.add, size: 16), label: const Text('New item')),
              FilledButton.icon(onPressed: () => _purchaseDialog(), icon: const Icon(Icons.shopping_cart_outlined, size: 16), label: const Text('Record purchase')),
            ]),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: TColors.slate100, borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                _tabButton('items', 'Items (${_items.length})'),
                _tabButton('purchases', 'Purchases (${_purchases.length})'),
                _tabButton('usage', 'Usage history'),
              ]),
            ),
            const SizedBox(height: 12),
            ...switch (_tab) {
              'purchases' => _purchasesTab(),
              'usage' => _usageTab(),
              _ => _itemsTab(),
            },
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ dialogs

class _ItemDialog extends StatefulWidget {
  const _ItemDialog({required this.session, required this.company, this.item});
  final Session session;
  final Company company;
  final Map? item;

  @override
  State<_ItemDialog> createState() => _ItemDialogState();
}

class _ItemDialogState extends State<_ItemDialog> {
  late final Map? it = widget.item;
  late final _name = TextEditingController(text: tStr(it?['itemName']));
  late final _min = TextEditingController(text: it == null ? '0' : numText(tNum(it!['minimumStockAlert'])));
  late final _notes = TextEditingController(text: tStr(it?['notes']));
  late String _category = it == null ? 'PackagingRoll' : tStr(it!['category']);
  late String _unit = tStr(it?['unitOfMeasure']);
  late String _purchaseUnit = tStr(it?['purchaseUnitOfMeasure']);
  late String _method = tStr(it?['usageMethod']).isEmpty ? 'FIFO' : tStr(it?['usageMethod']);

  @override
  void dispose() {
    for (final c in [_name, _min, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return trackerToast(context, 'Item name required', error: true);
    final body = <String, Object?>{
      'itemName': _name.text,
      'category': _category,
      'unitOfMeasure': _unit.isEmpty ? null : _unit,
      // Blank purchase unit → null so the backend defaults it to the production unit.
      'purchaseUnitOfMeasure': _purchaseUnit.trim().isEmpty ? null : _purchaseUnit.trim(),
      'minimumStockAlert': num.tryParse(_min.text) ?? 0,
      'isActive': it == null ? true : it!['isActive'] == true,
      'notes': _notes.text.isEmpty ? null : _notes.text,
      'usageMethod': _method,
      'farmId': widget.company.farmId,
    };
    try {
      final api = widget.session.farmClient;
      if (it != null) {
        final id = tIntOrNull(it!['waterRawMaterialItemId']);
        await api.put('/api/Water/raw-material-items/$id', body: {...body, 'waterRawMaterialItemId': id});
        if (mounted) trackerToast(context, 'Item updated');
      } else {
        await api.post('/api/Water/raw-material-items', body: body);
        if (mounted) trackerToast(context, 'Item added');
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Save failed', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: Row(children: [
          Icon(it != null ? Icons.edit_outlined : Icons.inbox_outlined, size: 20, color: const Color(0xFF2563EB)),
          const SizedBox(width: 8),
          Flexible(child: Text(it != null ? 'Edit item' : 'New item')),
        ]),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text(
              'Track production materials, packaging items, spare parts, fuel kept in stock, cleaning supplies, and other stock-tracked supplies.',
              style: TextStyle(fontSize: 13, color: TColors.slate500),
            ),
            const SizedBox(height: 12),
            formSection('Basics', const Color(0xFF4F46E5), [
              FilterLabel('Item name *', AppInput(controller: _name)),
              FilterLabel(
                'Category',
                AppSelect<String>(
                  value: _category,
                  items: [for (final c in waterRawCategories) AppSelectItem(value: c, label: c)],
                  onChanged: (v) => setState(() => _category = v ?? _category),
                ),
              ),
              FilterLabel(
                'Production unit of measure',
                AppSelect<String>(
                  value: _unit.isEmpty ? null : _unit,
                  hintText: 'Pick a unit',
                  items: [for (final u in waterUnitOptions(_unit)) AppSelectItem(value: u, label: u)],
                  onChanged: (v) => setState(() => _unit = v ?? ''),
                ),
              ),
              FilterLabel(
                'Purchase unit of measure',
                AppSelect<String>(
                  value: _purchaseUnit.isEmpty ? '__same__' : _purchaseUnit,
                  items: [
                    const AppSelectItem(value: '__same__', label: 'Same as production unit'),
                    for (final u in waterUnitOptions(_purchaseUnit)) AppSelectItem(value: u, label: u),
                  ],
                  onChanged: (v) => setState(() => _purchaseUnit = v == null || v == '__same__' ? '' : v),
                ),
              ),
              FilterLabel(
                'Minimum stock alert',
                AppInput(
                  controller: _min,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                ),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Order of item usage', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: TColors.slate700)),
                const SizedBox(height: 6),
                for (final (v, hint) in waterUsageMethods)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: InkWell(
                      onTap: () => setState(() => _method = v),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _method == v ? const Color(0xFFF0F9FF) : null,
                          border: Border.all(color: _method == v ? const Color(0xFF0284C7) : TColors.slate200),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(children: [
                          Icon(_method == v ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 18, color: const Color(0xFF0284C7)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: TColors.slate800)),
                              Text(hint, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                  ),
                const Text('Decides which purchase batch a production run consumes, and the price it is costed at',
                    style: TextStyle(fontSize: 11, color: TColors.slate500)),
              ]),
            ]),
            const SizedBox(height: 12),
            formSection('Notes', TColors.slate600, [FilterLabel('Notes', AppInput(controller: _notes))]),
          ]),
        ),
        actions: [
          redCancelButton(() => Navigator.pop(context, false)),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      );
}

/// Record raw material purchase / Edit purchase.
class _PurchaseDialog extends StatefulWidget {
  const _PurchaseDialog({required this.session, required this.company, required this.items, required this.accounts, required this.fmt, this.purchase});
  final Session session;
  final Company company;
  final List<Map> items, accounts;
  final FarmMoney fmt;
  final Map? purchase;

  @override
  State<_PurchaseDialog> createState() => _PurchaseDialogState();
}

class _PurchaseDialogState extends State<_PurchaseDialog> {
  late final Map? p = widget.purchase;
  late int _itemId;
  int? _supplierId, _accountId;
  late String _date, _method, _purchaseUnit, _productionUnit;
  num _qty = 0, _total = 0, _unitCost = 0, _per = 1, _paid = 0;
  bool _manualCost = false, _manualProd = false, _saving = false;
  List<Map> _suppliers = [];
  bool _suppliersLoading = true;
  late final TextEditingController _qtyC, _totalC, _costC, _perC, _prodQtyC, _prodCostC, _paidC;
  late final TextEditingController _receipt, _notes;

  @override
  void initState() {
    super.initState();
    if (p != null) {
      final x = p!;
      _itemId = tIntOrNull(x['waterRawMaterialItemId']) ?? 0;
      _supplierId = tIntOrNull(x['supplierId']);
      _date = tStr(x['purchaseDate']).split('T').first;
      _qty = tNum(x['quantity']);
      _unitCost = tNum(x['unitCost']);
      _method = tStr(x['paymentMethod']).isEmpty ? 'Cash' : tStr(x['paymentMethod']);
      _paid = tNum(x['amountPaid']);
      _accountId = tIntOrNull(x['waterCashAccountId']);
      _total = num.parse((x['totalCost'] != null ? tNum(x['totalCost']) : _qty * _unitCost).toStringAsFixed(2));
      _purchaseUnit = tStr(_item?['unitOfMeasure']);
      _productionUnit = tStr(x['productionUnit']);
      _per = x['productionUnitsPerPurchaseUnit'] == null ? 1 : tNum(x['productionUnitsPerPurchaseUnit']);
    } else {
      final it0 = widget.items.firstOrNull;
      _itemId = tIntOrNull(it0?['waterRawMaterialItemId']) ?? 0;
      _date = _today();
      _method = 'Cash';
      _purchaseUnit = tStr(it0?['unitOfMeasure']);
      _productionUnit = tStr(it0?['unitOfMeasure']);
    }
    _qtyC = TextEditingController(text: numText(_qty, 3));
    _totalC = TextEditingController(text: numText(_total, 2));
    _costC = TextEditingController(text: numText(_qty > 0 ? _total / _qty : 0));
    _perC = TextEditingController(text: numText(_per));
    _prodQtyC = TextEditingController(text: numText(_qty * _per));
    _prodCostC = TextEditingController(text: numText(_qty * _per > 0 ? _total / (_qty * _per) : 0));
    _paidC = TextEditingController(text: numText(_paid, 2));
    _receipt = TextEditingController(text: tStr(p?['receiptUrl']));
    _notes = TextEditingController(text: tStr(p?['notes']));
    _loadSuppliers();
  }

  @override
  void dispose() {
    for (final c in [_qtyC, _totalC, _costC, _perC, _prodQtyC, _prodCostC, _paidC, _receipt, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Map? get _item => widget.items.where((i) => tIntOrNull(i['waterRawMaterialItemId']) == _itemId).firstOrNull;
  bool get _editing => p != null;

  Future<void> _loadSuppliers() async {
    try {
      final r = rowsOf(await widget.session.farmClient.get('/api/Water/suppliers', query: {'farmId': widget.company.farmId}));
      if (mounted) setState(() => _suppliers = r);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load suppliers', description: e.message, error: true);
    }
    if (mounted) setState(() => _suppliersLoading = false);
  }

  Future<void> _addSupplier() async {
    final created = await showDialog<Map>(
      context: context,
      builder: (_) => WaterAddSupplierDialog(session: widget.session, company: widget.company, defaultType: 'Raw Material Supplier'),
    );
    if (created == null || !mounted) return;
    setState(() {
      _suppliers = [..._suppliers, created]..sort((a, b) => tStr(a['supplierName']).compareTo(tStr(b['supplierName'])));
      _supplierId = tIntOrNull(created['waterSupplierId']);
    });
  }

  // --- the derived figures, kept in step as the web's setters do
  void _syncDerived({bool cost = true, bool prodQty = true, bool prodCost = true}) {
    if (cost) _costC.text = numText(_qty > 0 ? _total / _qty : 0);
    if (prodQty) _prodQtyC.text = numText(_qty * _per);
    if (prodCost) _prodCostC.text = numText(_qty * _per > 0 ? _total / (_qty * _per) : 0);
  }

  void _onQty(String t) => setState(() {
        _qty = num.tryParse(t) ?? 0;
        _unitCost = _qty > 0 ? num.parse((_total / _qty).toStringAsFixed(4)) : 0;
        _syncDerived();
      });

  void _onTotal(String t) => setState(() {
        _total = num.tryParse(t) ?? 0;
        _unitCost = _qty > 0 ? num.parse((_total / _qty).toStringAsFixed(4)) : 0;
        _syncDerived();
      });

  void _onManualCost(String t) => setState(() {
        final c = num.tryParse(t) ?? 0;
        if (_qty > 0) _total = num.parse((c * _qty).toStringAsFixed(2));
        _unitCost = c;
        _totalC.text = numText(_total, 2);
        _syncDerived(cost: false);
      });

  void _onPer(String t) => setState(() {
        _per = num.tryParse(t) ?? 0;
        _syncDerived(cost: false);
      });

  void _onProdQty(String t) => setState(() {
        final v = num.tryParse(t) ?? 0;
        if (_qty > 0) _per = num.parse((v / _qty).toStringAsFixed(8));
        _perC.text = numText(_per, 8);
        _syncDerived(cost: false, prodQty: false);
      });

  void _onProdCost(String t) => setState(() {
        final c = num.tryParse(t) ?? 0;
        if (c > 0 && _qty > 0 && _total > 0) _per = num.parse((_total / (c * _qty)).toStringAsFixed(8));
        _perC.text = numText(_per, 8);
        _syncDerived(cost: false, prodCost: false);
      });

  Future<void> _save() async {
    if (_saving) return;
    if (_itemId == 0) return trackerToast(context, 'Pick an item', error: true);
    if (_qty <= 0) return trackerToast(context, 'Purchase quantity must be > 0', error: true);
    if (_total <= 0) return trackerToast(context, 'Total purchase cost must be > 0', error: true);
    if (_method != 'Credit' && _paid > 0 && _accountId == null) return trackerToast(context, 'Pick the cash account to pay from', error: true);
    setState(() => _saving = true);
    final total = num.parse(_total.toStringAsFixed(2));
    final body = <String, Object?>{
      'purchaseDate': _date,
      'quantity': _qty,
      'unitCost': _unitCost != 0 ? _unitCost : (_qty > 0 ? total / _qty : 0),
      'totalCost': total,
      'paymentMethod': _method,
      'amountPaid': _paid,
      'waterCashAccountId': _method == 'Credit' ? null : _accountId,
      'receiptUrl': _receipt.text.isEmpty ? null : _receipt.text,
      'notes': _notes.text.isEmpty ? null : _notes.text,
      'supplierId': _supplierId,
      'productionUnit': _productionUnit.trim().isEmpty ? null : _productionUnit.trim(),
      'productionUnitsPerPurchaseUnit': _per > 0 ? _per : null,
      'farmId': widget.company.farmId,
    };
    try {
      final api = widget.session.farmClient;
      if (_editing) {
        final id = tIntOrNull(p!['waterRawMaterialPurchaseId']);
        await api.put('/api/Water/raw-material-purchases/$id', body: {...body, 'waterRawMaterialPurchaseId': id});
        if (mounted) trackerToast(context, 'Purchase updated — stock adjusted');
      } else {
        await api.post('/api/Water/raw-material-purchases', body: {...body, 'waterRawMaterialItemId': _itemId});
        if (mounted) trackerToast(context, 'Purchase recorded — stock updated');
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Save failed', description: e.message, error: true);
    }
  }

  Widget _num(TextEditingController c, ValueChanged<String> on, {bool enabled = true}) => AppInput(
        controller: c,
        enabled: enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
        onChanged: on,
      );

  Widget _readOnly(String v) => Container(
        height: 44,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: TColors.slate100, border: Border.all(color: TColors.slate300), borderRadius: BorderRadius.circular(6)),
        child: Text(v, style: const TextStyle(color: TColors.slate600, fontWeight: FontWeight.w500)),
      );

  Widget _hinted(String label, Widget f, String hint) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FilterLabel(label, f),
        Padding(padding: const EdgeInsets.only(top: 4), child: Text(hint, style: const TextStyle(fontSize: 11, color: TColors.slate500))),
      ]);

  Widget _switchRow(String title, String sub, bool v, ValueChanged<bool> on) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: TColors.slate50, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: TColors.slate700)),
              Text(sub, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            ]),
          ),
          Switch(value: v, onChanged: on),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final fmt = widget.fmt;
    final unitCost = _qty > 0 ? _total / _qty : 0;
    final prodQty = _qty * _per;
    final prodUnitCost = prodQty > 0 ? _total / prodQty : 0;
    final active = [for (final a in widget.accounts) if (a['isActive'] == true) a];
    final pickable = [for (final i in widget.items) if (i['isActive'] == true || tIntOrNull(i['waterRawMaterialItemId']) == _itemId) i];
    final needAccount = _method != 'Credit' && _paid > 0;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: Row(children: [
          Icon(_editing ? Icons.edit_outlined : Icons.shopping_cart_outlined, size: 20, color: const Color(0xFF2563EB)),
          const SizedBox(width: 8),
          Flexible(child: Text(_editing ? 'Edit purchase' : 'Record raw material purchase')),
        ]),
        content: SizedBox(
          width: 640,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Log an inventory & supply purchase to update stock and create the linked expense.',
                style: TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 12),
            formSection('Item, Supplier & Date', const Color(0xFF4F46E5), [
              FilterLabel(
                'Item${_editing ? ' (fixed — delete and recreate to change item)' : ''}',
                AppSelect<int>(
                  value: _itemId == 0 ? null : _itemId,
                  hintText: 'Pick item',
                  enabled: !_editing,
                  items: [
                    for (final i in pickable)
                      AppSelectItem(
                        value: tIntOrNull(i['waterRawMaterialItemId']) ?? 0,
                        label: '${tStr(i['itemName'])} (${tStr(i['unitOfMeasure']).isEmpty ? '—' : tStr(i['unitOfMeasure'])})',
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    _itemId = v ?? 0;
                    final it = _item;
                    final pu = tStr(it?['purchaseUnitOfMeasure']).isNotEmpty ? tStr(it?['purchaseUnitOfMeasure']) : tStr(it?['unitOfMeasure']);
                    if (pu.isNotEmpty) _purchaseUnit = pu;
                    if (tStr(it?['unitOfMeasure']).isNotEmpty) _productionUnit = tStr(it?['unitOfMeasure']);
                  }),
                ),
              ),
              FilterLabel(
                'Supplier',
                AppSelect<int>(
                  value: _supplierId ?? -1,
                  hintText: _suppliersLoading ? 'Loading suppliers…' : 'Select supplier…',
                  enabled: !_suppliersLoading,
                  items: [
                    const AppSelectItem(value: -1, label: 'No supplier / Other'),
                    for (final s in _suppliers)
                      AppSelectItem(
                        value: tIntOrNull(s['waterSupplierId']) ?? 0,
                        label: '${tStr(s['supplierName'])}${tStr(s['supplierType']).isNotEmpty ? ' · ${tStr(s['supplierType'])}' : ''}',
                      ),
                    const AppSelectItem(value: -2, label: '+ Add new supplier…'),
                  ],
                  onChanged: (v) {
                    if (v == -2) {
                      _addSupplier();
                      return;
                    }
                    setState(() => _supplierId = v == null || v == -1 ? null : v);
                  },
                ),
              ),
              FilterLabel(
                'Date',
                AppDateField(
                  value: businessDateAsDateTime(_date),
                  hintText: 'dd/mm/yyyy',
                  onChanged: (d) => setState(() => _date = d == null ? _date : isoDay(d)),
                ),
              ),
              FilterLabel(
                'Payment method',
                AppSelect<String>(
                  value: _method,
                  items: [for (final m in waterPaymentMethods) AppSelectItem(value: m, label: m)],
                  onChanged: (v) => setState(() => _method = v ?? 'Cash'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            formSection('Purchase Quantity & Production Costing', const Color(0xFF2563EB), [
              FilterLabel(
                'Purchase unit *',
                AppSelect<String>(
                  value: _purchaseUnit.isEmpty ? null : _purchaseUnit,
                  hintText: 'Pick unit',
                  items: [for (final u in waterUnitOptions(_purchaseUnit)) AppSelectItem(value: u, label: u)],
                  onChanged: (v) => setState(() => _purchaseUnit = v ?? ''),
                ),
              ),
              FilterLabel('Purchase quantity${_purchaseUnit.isNotEmpty ? ' ($_purchaseUnit)' : ''} *', _num(_qtyC, _onQty)),
              _switchRow('Enter purchase unit cost manually', 'Turn off the auto-calculation and type the purchase unit cost yourself.', _manualCost,
                  (v) => setState(() => _manualCost = v)),
              FilterLabel('Total purchase cost *', _num(_totalC, _onTotal, enabled: !_manualCost)),
              if (_manualCost)
                _hinted('Purchase unit cost${_purchaseUnit.isNotEmpty ? ' (per $_purchaseUnit)' : ''}', _num(_costC, _onManualCost), 'Manual — sets the total for you')
              else
                FilterLabel('Purchase unit cost (auto)', _readOnly('${fmt(unitCost)}${_purchaseUnit.isNotEmpty ? ' per $_purchaseUnit' : ''}')),
            ]),
            const SizedBox(height: 12),
            formSection('Production Conversion', const Color(0xFF4F46E5), [
              _switchRow('Enter production cost manually', 'Turn off the auto-calculation and type the production-level unit cost yourself.', _manualProd,
                  (v) => setState(() => _manualProd = v)),
              FilterLabel(
                'Production unit *',
                AppSelect<String>(
                  value: _productionUnit.isEmpty ? null : _productionUnit,
                  hintText: 'Pick unit',
                  items: [for (final u in waterUnitOptions(_productionUnit)) AppSelectItem(value: u, label: u)],
                  onChanged: (v) => setState(() => _productionUnit = v ?? ''),
                ),
              ),
              FilterLabel('Production units per purchase unit *', _num(_perC, _onPer)),
              _hinted('Production-level quantity', _num(_prodQtyC, _onProdQty), 'Editable — sets units per purchase unit'),
              if (_manualProd)
                _hinted('Production-level unit cost${_productionUnit.isNotEmpty ? ' (per $_productionUnit)' : ''}', _num(_prodCostC, _onProdCost),
                    'Manual — sets the conversion for you')
              else
                FilterLabel('Production-level unit cost (auto)', _readOnly('${fmt(prodUnitCost)}${_productionUnit.isNotEmpty ? ' per $_productionUnit' : ''}')),
              const Text.rich(
                TextSpan(children: [
                  TextSpan(text: 'If you buy and use the same unit, set '),
                  TextSpan(text: 'Production units per purchase unit = 1', style: TextStyle(fontWeight: FontWeight.w500)),
                  TextSpan(text: ' — the production figures then match the purchase figures. These values are saved with the purchase.'),
                ]),
                style: TextStyle(fontSize: 12, color: TColors.slate500),
              ),
            ]),
            const SizedBox(height: 12),
            formSection('Payment', TColors.amber600, [
              FilterLabel('Amount paid', _num(_paidC, (t) => setState(() => _paid = num.tryParse(t) ?? 0))),
              FilterLabel(
                'Cash account${needAccount ? ' *' : ''}',
                AppSelect<int>(
                  value: _method == 'Credit' ? null : _accountId,
                  hintText: _method == 'Credit' ? '(not required for credit)' : 'Pick account',
                  enabled: _method != 'Credit',
                  items: active.isEmpty
                      ? const [AppSelectItem(value: -1, label: 'No cash accounts — add one on Cash & Accounts.', enabled: false)]
                      : [
                          for (final a in active)
                            AppSelectItem(
                              value: tIntOrNull(a['waterCashAccountId']) ?? 0,
                              label: '${tStr(a['accountName'])} (${tNum(a['currentBalance']).toStringAsFixed(2)})',
                            ),
                        ],
                  onChanged: (v) => setState(() => _accountId = v),
                ),
              ),
              FilterLabel('Receipt URL', AppInput(controller: _receipt)),
            ]),
            const SizedBox(height: 12),
            formSection('Notes', TColors.slate600, [FilterLabel('Notes', AppInput(controller: _notes))]),
            const Divider(height: 20),
            Text.rich(TextSpan(children: [
              const TextSpan(text: 'Total: ', style: TextStyle(color: TColors.slate500)),
              TextSpan(text: fmt(_total), style: const TextStyle(fontWeight: FontWeight.w600)),
              const TextSpan(text: ' · '),
              const TextSpan(text: 'Balance: ', style: TextStyle(color: TColors.slate500)),
              TextSpan(text: fmt((_total - _paid).clamp(0, double.infinity)), style: const TextStyle(fontWeight: FontWeight.w600)),
            ])),
          ]),
        ),
        actions: [
          redCancelButton(_saving ? null : () => Navigator.pop(context, false)),
          FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : (_editing ? 'Save changes' : 'Record purchase'))),
        ],
      ),
    );
  }
}

class _PayBalanceDialog extends StatefulWidget {
  const _PayBalanceDialog({required this.session, required this.company, required this.purchase, required this.fmt});
  final Session session;
  final Company company;
  final Map purchase;
  final FarmMoney fmt;

  @override
  State<_PayBalanceDialog> createState() => _PayBalanceDialogState();
}

class _PayBalanceDialogState extends State<_PayBalanceDialog> {
  late final num _outstanding = tNum(widget.purchase['balance']);
  late final _amount = TextEditingController(text: numText(_outstanding, 2));
  String _method = 'Cash', _date = _today();
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = num.tryParse(_amount.text) ?? 0;
    if (amount <= 0) return trackerToast(context, 'Enter an amount greater than 0', error: true);
    if (amount > _outstanding) return trackerToast(context, 'Amount exceeds the outstanding balance (${widget.fmt(_outstanding)})', error: true);
    setState(() => _saving = true);
    try {
      await widget.session.farmClient.post('/api/Water/raw-material-purchases/${tStr(widget.purchase['waterRawMaterialPurchaseId'])}/pay-balance', body: {
        'farmId': widget.company.farmId,
        'amount': amount,
        'paymentMethod': _method,
        'paymentDate': _date,
      });
      if (!mounted) return;
      trackerToast(context, 'Balance payment recorded', description: 'An expense was posted for the amount paid.');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Could not record payment', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.purchase;
    final total = p['totalCost'] != null ? tNum(p['totalCost']) : tNum(p['quantity']) * tNum(p['unitCost']);
    return AlertDialog(
      scrollable: true,
      title: const Row(children: [
        Icon(Icons.account_balance_wallet_outlined, size: 20, color: TColors.emerald600),
        SizedBox(width: 8),
        Flexible(child: Text('Pay balance')),
      ]),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            '${tStr(p['itemName']).isEmpty ? 'Purchase' : tStr(p['itemName'])} — outstanding ${widget.fmt(_outstanding)} of ${widget.fmt(total)}. This records an expense for the amount paid.',
            style: const TextStyle(fontSize: 13, color: TColors.slate500),
          ),
          const SizedBox(height: 12),
          formSection('Payment', TColors.amber600, [
            FilterLabel(
              'Amount paid *',
              AppInput(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
              ),
            ),
            FilterLabel(
              'Payment method',
              AppSelect<String>(
                value: _method,
                items: [for (final m in waterPaymentMethods) if (m != 'Credit') AppSelectItem(value: m, label: m)],
                onChanged: (v) => setState(() => _method = v ?? 'Cash'),
              ),
            ),
            FilterLabel(
              'Payment date',
              AppDateField(
                value: businessDateAsDateTime(_date),
                hintText: 'dd/mm/yyyy',
                onChanged: (d) => setState(() => _date = d == null ? _date : isoDay(d)),
              ),
            ),
          ]),
        ]),
      ),
      actions: [
        OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _submit, child: Text(_saving ? 'Saving…' : 'Record payment')),
      ],
    );
  }
}
