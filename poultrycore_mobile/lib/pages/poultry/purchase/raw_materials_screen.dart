// Poultry → Raw Materials & Supplies (app/poultry-raw-materials/page.tsx), and
// Operations → Purchase → Record Purchase, which is this page opened with
// `?purchase=1` so the purchase dialog comes up straight away. At phone width
// the web shows the card lists (its `md:hidden` layout), so the app does too.

import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../shared/business_dates.dart';
import '../../shared/company_clock.dart';
import '../reports/report_format.dart';
import '../reports/report_routes.dart' show openAppHref;
import '../sales/balances_logic.dart' show pageSlice;
import '../sales/balances_widgets.dart' show CompactPager, ListFiltersCard;
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull, loc, feedItemKind;
import '../trackers/tracker_widgets.dart';
import 'raw_material_dialogs.dart';

const rawTabs = ['items', 'purchases', 'usage'];

String? _day(Object? raw) => RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(tStr(raw))?[1];

bool _dateAndSearch(Map r, {required String search, required List<String> keys, String from = '', String to = '', String? dateKey}) {
  if (dateKey != null && (from.isNotEmpty || to.isNotEmpty)) {
    final d = _day(r[dateKey]);
    if (d != null) {
      if (from.isNotEmpty && d.compareTo(from) < 0) return false;
      if (to.isNotEmpty && d.compareTo(to) > 0) return false;
    }
  }
  final s = search.trim().toLowerCase();
  if (s.isNotEmpty && !keys.any((k) => r[k] != null && '${r[k]}'.toLowerCase().contains(s))) return false;
  return true;
}

List<Map> filterRawItems(List<Map> items, {String search = '', String category = 'all', String unit = 'all'}) => [
      for (final i in items)
        if (_dateAndSearch(i, search: search, keys: const ['itemName', 'category']) &&
            (category == 'all' || tStr(i['category']) == category) &&
            (unit == 'all' || tStr(i['unitOfMeasure']) == unit || tStr(i['purchaseUnitOfMeasure']) == unit))
          i,
    ];

List<Map> filterRawPurchases(List<Map> rows,
    {String search = '', String from = '', String to = '', String item = 'all', int? focusId}) {
  if (focusId != null) return [for (final p in rows) if (tIntOrNull(p['poultryRawMaterialPurchaseId']) == focusId) p];
  return [
    for (final p in rows)
      if (_dateAndSearch(p, search: search, keys: const ['itemName', 'supplierName'], from: from, to: to, dateKey: 'purchaseDate') &&
          (item == 'all' || tStr(p['poultryRawMaterialItemId']) == item))
        p,
  ];
}

/// Usage history plus manual adjustments, which the web folds in as rows.
List<Map> mergeUsage(List<Map> history, List<Map> adjustments) => [
      ...history,
      for (final a in adjustments)
        {
          'poultryRawMaterialUsageId': -(tIntOrNull(a['poultryRawMaterialAdjustmentId']) ?? 0),
          'poultryRawMaterialItemId': a['poultryRawMaterialItemId'],
          'itemName': a['itemName'],
          'unitOfMeasure': a['unitOfMeasure'],
          'usedDate': a['adjustedDate'],
          'quantityUsed': -tNum(a['quantity']),
          'expectedQuantityUsed': null,
          'variance': 0,
          'varianceReason': 'Manual adjustment${tStr(a['movementType']).isNotEmpty ? ' (${tStr(a['movementType'])})' : ''}'
              '${tStr(a['note']).isNotEmpty ? ' — ${tStr(a['note'])}' : ''}',
          'notes': a['note'],
          'createdAt': a['createdAt'],
        },
    ];

/// The summary: purchases produced on the farm are not spend.
({int items, int active, int low, num purchaseTotal, num paid, num outstanding, int produced}) rawStats(List<Map> items, List<Map> purchases) {
  final spend = [for (final p in purchases) if (tStr(p['feedProductionRole']) != 'Produced') p];
  return (
    items: items.length,
    active: items.where((i) => i['isActive'] == true).length,
    low: items.where((i) => i['isActive'] == true && i['isLowStock'] == true).length,
    purchaseTotal: spend.fold<num>(0, (s, p) => s + tNum(p['totalCost'])),
    paid: spend.fold<num>(0, (s, p) => s + tNum(p['amountPaid'])),
    outstanding: spend.fold<num>(0, (s, p) => s + tNum(p['balance'])),
    produced: purchases.where((p) => tStr(p['feedProductionRole']) == 'Produced').length,
  );
}

class RawMaterialsScreen extends StatefulWidget {
  const RawMaterialsScreen({
    super.key,
    required this.session,
    required this.company,
    this.openPurchase = false,
    this.purchaseItemId,
    this.purchaseQty,
    this.tab,
    this.focusPurchaseId,
  });
  final Session session;
  final Company company;

  /// `?purchase=1[&itemId=N][&qty=X]`: the purchase dialog opens once loaded.
  final bool openPurchase;
  final int? purchaseItemId;
  final num? purchaseQty;

  /// `?tab=items|purchases|usage`.
  final String? tab;

  /// `?purchaseId=`: the purchases list narrowed to one purchase.
  final int? focusPurchaseId;

  @override
  State<RawMaterialsScreen> createState() => _RawMaterialsScreenState();
}

class _RawMaterialsScreenState extends State<RawMaterialsScreen> {
  List<Map> _items = [], _purchases = [], _accounts = [], _usage = [];
  Map? _valuation;
  bool _loading = true, _usageLoaded = false;
  late String _tab = rawTabs.contains(widget.tab) ? widget.tab! : 'items';
  final _search = TextEditingController();
  String _from = '', _to = '', _itemFilter = 'all', _category = 'all', _unit = 'all';
  late int? _focus = widget.focusPurchaseId;
  int _iPage = 1, _iSize = 10, _pPage = 1, _pSize = 10, _uPage = 1, _uSize = 10;
  FarmCostDefaults _defaults = (feed: expenseWhenPurchased, medication: expenseWhenPurchased);
  FarmMoney _fmt = const FarmMoney();
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;
  Map<String, String> get _q => {'farmId': widget.company.farmId};

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _fmt = m);
    });
    CompanyClock.load(widget.session, widget.company).then((c) {
      if (mounted) setState(() => _offset = c.offset);
    });
    _api.get('/api/Poultry/financial-settings/cost-recognition', query: _q).then((s) {
      if (mounted && s is Map) {
        setState(() => _defaults = (
              feed: tStr(s['feedCostRecognitionMethod']).isEmpty ? expenseWhenPurchased : tStr(s['feedCostRecognitionMethod']),
              medication: tStr(s['medicationCostRecognitionMethod']).isEmpty ? expenseWhenPurchased : tStr(s['medicationCostRecognitionMethod']),
            ));
      }
    }).catchError((_) {});
    _load().then((_) {
      if (widget.openPurchase && mounted) _openPurchase(itemId: widget.purchaseItemId, qty: widget.purchaseQty);
    });
    if (_tab == 'usage') _loadUsage();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await Future.wait<Object?>([
        _api.get('/api/Poultry/raw-material-items', query: _q),
        _api.get('/api/Poultry/raw-material-purchases', query: _q),
        _api.get('/api/Poultry/cash-accounts', query: _q).catchError((_) => <Map>[]),
        _api.get('/api/Poultry/inventory-valuation', query: _q).then<Object?>((v) => v).catchError((_) => null),
      ]);
      if (!mounted) return;
      setState(() {
        _items = rowsOf(r[0]);
        _purchases = rowsOf(r[1]);
        _accounts = [for (final a in rowsOf(r[2])) if (a['isActive'] == true) a];
        _valuation = r[3] is Map ? r[3] as Map : null;
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load raw materials', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadUsage() async {
    if (_usageLoaded) return;
    try {
      final r = await Future.wait([
        _api.get('/api/Poultry/raw-material-usage/history', query: _q).then(rowsOf),
        _api.get('/api/Poultry/raw-material-adjustments', query: _q).then(rowsOf).catchError((_) => <Map>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _usage = mergeUsage(r[0], r[1]);
        _usageLoaded = true;
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load usage history', description: e.message, error: true);
    }
  }

  /// The "Main Cash Account" if there is one, else the first.
  int? get _defaultCashAccountId {
    final main = _accounts.where((a) => tStr(a['accountName']).trim().toLowerCase() == 'main cash account').firstOrNull;
    return tIntOrNull((main ?? _accounts.firstOrNull)?['poultryCashAccountId']);
  }

  void _href(String href, String label) => openAppHref(context, widget.session, widget.company, href, label: label);

  // ------------------------------------------------------------ actions

  Future<void> _openPurchase({Map? editing, int? itemId, num? qty}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => RawPurchaseDialog(
        session: widget.session,
        company: widget.company,
        items: _items,
        cashAccounts: _accounts,
        money: _fmt,
        editing: editing,
        defaultItemId: itemId,
        defaultQuantity: qty,
        defaultCashAccountId: _defaultCashAccountId,
      ),
    );
    if (ok == true) _load();
  }

  Future<void> _openItem([Map? editing]) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => RawItemDialog(session: widget.session, company: widget.company, editing: editing, farmDefaults: _defaults),
    );
    if (ok == true) _load();
  }

  Future<void> _recalculate() async {
    final ran = await showDialog<bool>(
      context: context,
      builder: (_) => RecalculateStockDialog(session: widget.session, company: widget.company, items: _items),
    );
    if (ran == true) _load();
  }

  Future<void> _pay(Map p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => RawPayBalanceDialog(session: widget.session, company: widget.company, purchase: p, money: _fmt),
    );
    if (ok == true) _load();
  }

  /// ConfirmDeleteDialog: the page's own toast, then the dialog's "Deleted"
  /// (the web shows one toast at a time, so "Deleted" is what is seen).
  Future<void> _confirmDelete(String title, String description, String path, String done) async {
    final yes = await confirmDelete(context, title: title, description: description);
    if (!yes || !mounted) return;
    try {
      await _api.delete('$path?farmId=${Uri.encodeQueryComponent(widget.company.farmId)}');
      if (mounted) trackerToast(context, done);
      await _load();
      if (mounted) trackerToast(context, 'Deleted');
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Delete failed', description: e.message, error: true);
    }
  }

  void _deleteItem(Map i) => _confirmDelete('Remove item?',
      'Remove "${tStr(i['itemName'])}"? If it has purchase/usage history it will be deactivated instead.',
      '/api/Poultry/raw-material-items/${i['poultryRawMaterialItemId']}', 'Item removed');

  void _deletePurchase(Map p) => _confirmDelete('Delete purchase?', 'This will reverse the stock it added.',
      '/api/Poultry/raw-material-purchases/${p['poultryRawMaterialPurchaseId']}', 'Purchase removed');

  void _selectTab(String t) {
    setState(() => _tab = t);
    if (t == 'usage') _loadUsage();
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-raw-materials');
    final s = rawStats(_items, _purchases);
    final fmt = _fmt;

    Widget toolbar(String label, IconData icon, VoidCallback onTap, {bool primary = false}) => primary
        ? FilledButton.icon(onPressed: onTap, icon: Icon(icon, size: 16), label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis))
        : OutlinedButton.icon(onPressed: onTap, icon: Icon(icon, size: 16), label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis));

    Widget tile({required IconData icon, required Color iconColor, required String label, required String value, required String sub, Color? valueColor, bool warn = false}) =>
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: warn ? TColors.amber50 : Colors.white,
            border: Border.all(color: warn ? TColors.amber200 : TColors.slate200),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label.toUpperCase(),
                    overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: .4, color: TColors.slate500)),
              ),
            ]),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: valueColor ?? TColors.slate900)),
            ),
            Text(sub, style: const TextStyle(fontSize: 12, color: TColors.slate400)),
          ]),
        );

    Widget tabButton(String key, IconData icon, String label, String? count) => Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Material(
            color: _tab == key ? TColors.blue600 : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _selectTab(key),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 16, color: _tab == key ? Colors.white : TColors.slate600),
                  const SizedBox(width: 6),
                  Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _tab == key ? Colors.white : TColors.slate600)),
                  if (count != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: _tab == key ? Colors.white24 : TColors.slate100, borderRadius: BorderRadius.circular(999)),
                      child: Text(count,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _tab == key ? Colors.white : TColors.slate600)),
                    ),
                  ],
                ]),
              ),
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Raw Materials & Supplies')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            const Text('Raw Materials & Supplies', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: TColors.slate900)),
            const Text('Track feed inputs, packaging, medication and other supplies — purchases, costing and usage.',
                style: TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 12),
            LayoutBuilder(builder: (context, c) {
              final w = (c.maxWidth - 8) / 2;
              return Wrap(spacing: 8, runSpacing: 8, children: [
                SizedBox(width: w, child: toolbar('Recalculate stock', Icons.refresh, _recalculate)),
                SizedBox(width: w, child: toolbar('New Item', Icons.add, () => _openItem())),
                SizedBox(width: w, child: toolbar('Produce Feed', Icons.factory_outlined, () => _href('/poultry-feed-production', 'Feed Production'))),
                SizedBox(width: w, child: toolbar('Record Purchase', Icons.shopping_cart_outlined, () => _openPurchase(), primary: true)),
              ]);
            }),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(padding: EdgeInsets.all(24), child: Text('Loading…', style: TextStyle(color: TColors.slate500)))
            else ...[
              LayoutBuilder(builder: (context, c) {
                final w = (c.maxWidth - 12) / 2;
                return Wrap(spacing: 12, runSpacing: 12, children: [
                  SizedBox(
                    width: w,
                    child: tile(icon: Icons.inventory_2_outlined, iconColor: TColors.blue600, label: 'Active Items', value: loc(s.active), sub: 'of ${loc(s.items)} total'),
                  ),
                  SizedBox(
                    width: w,
                    child: tile(
                      icon: Icons.warning_amber_outlined,
                      iconColor: s.low > 0 ? TColors.amber600 : TColors.slate400,
                      label: 'Low Stock',
                      value: loc(s.low),
                      sub: s.low > 0 ? 'need restocking' : 'all stocked',
                      valueColor: s.low > 0 ? TColors.amber700 : null,
                      warn: s.low > 0,
                    ),
                  ),
                  SizedBox(
                    width: w,
                    child: tile(
                      icon: Icons.shopping_cart_outlined,
                      iconColor: TColors.emerald600,
                      label: 'Purchases Value',
                      value: fmt(s.purchaseTotal),
                      sub: 'Paid ${fmt(s.paid)}${s.produced > 0 ? ' · excludes ${s.produced} produced feed ${s.produced == 1 ? 'lot' : 'lots'}' : ''}',
                    ),
                  ),
                  SizedBox(
                    width: w,
                    child: tile(
                      icon: Icons.account_balance_wallet_outlined,
                      iconColor: s.outstanding > 0 ? TColors.red600 : TColors.slate400,
                      label: 'Outstanding',
                      value: fmt(s.outstanding),
                      sub: 'owed to suppliers',
                      valueColor: s.outstanding > 0 ? TColors.red600 : TColors.emerald700,
                    ),
                  ),
                ]);
              }),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    tabButton('items', Icons.inventory_2_outlined, 'Items', loc(_items.length)),
                    tabButton('purchases', Icons.shopping_cart_outlined, 'Purchases', loc(_purchases.length)),
                    tabButton('usage', Icons.account_balance_wallet_outlined, 'Usage History', _usageLoaded ? loc(_usage.length) : null),
                  ]),
                ),
              ),
              const SizedBox(height: 14),
              TCard(
                child: switch (_tab) {
                  'purchases' => _purchasesTab(),
                  'usage' => _usageTab(),
                  _ => _itemsTab(),
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _heading(String title, String sub) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: TColors.slate900)),
          Text(sub, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
        ]),
      );

  Widget _itemFilterDropdown() => AppSelect<String>(
        value: _itemFilter,
        hintText: 'All items',
        items: [
          const AppSelectItem(value: 'all', label: 'All items'),
          for (final i in _items) AppSelectItem(value: tStr(i['poultryRawMaterialItemId']), label: tStr(i['itemName'])),
        ],
        onChanged: (v) => setState(() {
          _itemFilter = v ?? 'all';
          _pPage = _uPage = 1;
        }),
      );

  Widget _statusBadge(Map i) => i['isActive'] != true
      ? const TBadge('Inactive', bg: TColors.slate100, fg: TColors.slate800)
      : i['isLowStock'] == true
          ? const TBadge('Low stock', bg: TColors.amber100, fg: TColors.amber700)
          : const TBadge('OK', bg: TColors.green100, fg: TColors.green700);

  Widget _empty(String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(t, textAlign: TextAlign.center, style: const TextStyle(color: TColors.slate500)),
      );

  Widget _iconBtn(String? tip, IconData icon, VoidCallback onTap, {Color? color}) => IconButton(
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        icon: Icon(icon, size: 18, color: color),
        onPressed: onTap,
      );

  Widget _itemsTab() {
    final fmt = _fmt;
    final v = _valuation;
    final summary = v?['summary'] is Map ? v!['summary'] as Map : const {};
    final findings = rowsOf(v?['auditFindings']);
    final units = <String>{
      for (final i in _items) ...[
        if (tStr(i['unitOfMeasure']).isNotEmpty) tStr(i['unitOfMeasure']),
        if (tStr(i['purchaseUnitOfMeasure']).isNotEmpty) tStr(i['purchaseUnitOfMeasure']),
      ],
    }.toList()
      ..sort();
    final rows = filterRawItems(_items, search: _search.text, category: _category, unit: _unit);
    final deferred = tNum(summary['deferredValue']);

    Widget box({required Color bg, required Color border, required String label, required Color labelColor, required String value, required Color valueColor, required String sub, required Color subColor, String? tip, VoidCallback? onTap}) {
      final child = Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(6)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(), style: TextStyle(fontSize: 11, letterSpacing: .4, color: labelColor)),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: valueColor)),
          Text(sub, style: TextStyle(fontSize: 11, color: subColor)),
        ]),
      );
      final tapped = onTap == null ? child : InkWell(onTap: onTap, child: child);
      return Padding(padding: const EdgeInsets.only(bottom: 8), child: tip == null ? tapped : Tooltip(message: tip, child: tapped));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _heading('Inventory Items', 'Feed, packaging, medication and other stock-tracked supplies.'),
      if (v != null) ...[
        box(
          bg: TColors.slate50,
          border: TColors.slate200,
          label: 'Stock value',
          labelColor: TColors.slate500,
          value: fmt(tNum(summary['operationalValue'])),
          valueColor: TColors.slate900,
          sub: '${tStr(summary['itemsWithStock'])} item(s) in stock',
          subColor: TColors.slate500,
          tip: operationalValueTooltip,
        ),
        box(
          bg: TColors.amber50,
          border: TColors.amber200,
          label: 'Deferred inventory cost',
          labelColor: TColors.amber700,
          value: fmt(deferred),
          valueColor: TColors.amber900,
          sub: deferred > 0 ? '${tStr(summary['itemsDeferring'])} item(s) expense on use · view purchases' : 'Every item is expensed at purchase',
          subColor: TColors.amber700,
          tip: deferred > 0 ? 'See the purchases this is waiting on' : deferredInventoryTooltip,
          onTap: deferred > 0 ? () => _href('/poultry-deferred-costs', 'Deferred inventory cost') : null,
        ),
        box(
          bg: Colors.white,
          border: TColors.slate200,
          label: 'Cost layers',
          labelColor: TColors.slate500,
          value: loc(tNum(summary['openLots'])),
          valueColor: TColors.slate900,
          sub: '${loc(tNum(summary['deferredLots']))} still deferring',
          subColor: TColors.slate500,
        ),
        if (findings.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: TColors.amber50, border: Border.all(color: TColors.amber300), borderRadius: BorderRadius.circular(6)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.warning_amber_outlined, size: 16, color: TColors.amber600),
              const SizedBox(width: 8),
              Expanded(
                child: DefaultTextStyle.merge(
                  style: const TextStyle(fontSize: 12, color: TColors.amber900),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${findings.length} stock costing issue(s) found', style: const TextStyle(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    for (final f in findings.take(5))
                      Text.rich(TextSpan(children: [
                        TextSpan(text: tStr(f['severity']), style: const TextStyle(fontWeight: FontWeight.w500)),
                        TextSpan(text: '${tStr(f['itemName']).isNotEmpty ? ' · ${tStr(f['itemName'])}' : ''} — ${tStr(f['detail'])}'),
                      ])),
                    if (findings.length > 5) Text('…and ${findings.length - 5} more.'),
                  ]),
                ),
              ),
            ]),
          ),
      ],
      ListFiltersCard(
        search: _search,
        searchPlaceholder: 'Search item or category',
        onSearch: () => setState(() => _iPage = _pPage = _uPage = 1),
        from: '',
        to: '',
        onDates: (_, _) {},
        onClear: () => setState(() => _search.clear()),
        searchOnly: true,
        extras: [
          AppSelect<String>(
            value: _category,
            hintText: 'All categories',
            items: [
              const AppSelectItem(value: 'all', label: 'All categories'),
              for (final c in rawMaterialCategories) AppSelectItem(value: c, label: rawCategoryLabel(c)),
            ],
            onChanged: (x) => setState(() {
              _category = x ?? 'all';
              _iPage = 1;
            }),
          ),
          AppSelect<String>(
            value: _unit,
            hintText: 'All units',
            items: [const AppSelectItem(value: 'all', label: 'All units'), for (final u in units) AppSelectItem(value: u, label: u)],
            onChanged: (x) => setState(() {
              _unit = x ?? 'all';
              _iPage = 1;
            }),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (rows.isEmpty)
        _empty('No items yet.')
      else
        for (final i in pageSlice(rows, _iPage, _iSize))
          FieldCard(
            title: tStr(i['itemName']),
            badge: _statusBadge(i),
            fields: [
              ('Category', rawCategoryLabel(i['category']), null),
              ('Purchase Unit', tStr(i['purchaseUnitOfMeasure']).isEmpty ? '—' : tStr(i['purchaseUnitOfMeasure']), null),
              ('Production Unit', tStr(i['unitOfMeasure']).isEmpty ? '—' : tStr(i['unitOfMeasure']), null),
              ('In stock', loc(tNum(i['currentQuantity'])), null),
              ('Min alert', loc(tNum(i['minimumStockAlert'])), null),
              ('Cost recognised',
                  '${methodShortLabel(i['effectiveCostRecognitionMethod'])}${tStr(i['costRecognitionSource']) == 'ItemOverride' ? ' (override)' : ''}', null),
            ],
            actions: [
              if (feedItemKind(i['category']) != null)
                _iconBtn("Track this item's movements", Icons.history, () => _href('/feed-inventory-tracker?itemId=${i['poultryRawMaterialItemId']}', 'Feed inventory tracker'),
                    color: TColors.amber700),
              _iconBtn(null, Icons.edit_outlined, () => _openItem(i)),
              _iconBtn(null, Icons.delete_outline, () => _deleteItem(i), color: TColors.red600),
            ],
          ),
      CompactPager(total: rows.length, page: _iPage, pageSize: _iSize, onPage: (p) => setState(() => _iPage = p), onPageSize: (s) => setState(() {
            _iSize = s;
            _iPage = 1;
          })),
    ]);
  }

  ListFiltersCard _datedFilters(String placeholder) => ListFiltersCard(
        search: _search,
        searchPlaceholder: placeholder,
        onSearch: () => setState(() => _iPage = _pPage = _uPage = 1),
        from: _from,
        to: _to,
        onDates: (f, t) => setState(() {
          _from = f;
          _to = t;
          _pPage = _uPage = 1;
        }),
        onClear: () => setState(() {
          _search.clear();
          _from = _to = '';
        }),
        extras: [_itemFilterDropdown()],
      );

  Widget _productionBadge(Map p) {
    final produced = tStr(p['feedProductionRole']) == 'Produced';
    final label = '${produced ? 'Produced' : 'Bought for production'}'
        '${tStr(p['feedProductionBatchNumber']).isNotEmpty ? ' · ${tStr(p['feedProductionBatchNumber'])}' : ''}';
    return TBadge(label,
        bg: Colors.white, fg: produced ? TColors.emerald700 : const Color(0xFF4338CA), border: produced ? TColors.emerald300 : const Color(0xFFA5B4FC));
  }

  Widget _purchasesTab() {
    final fmt = _fmt;
    final rows = filterRawPurchases(_purchases, search: _search.text, from: _from, to: _to, item: _itemFilter, focusId: _focus);
    final focusSupplier = _focus == null
        ? null
        : tStr(_purchases.where((p) => tIntOrNull(p['poultryRawMaterialPurchaseId']) == _focus).firstOrNull?['supplierName']);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _heading('Purchase History',
          'Stock received, costing, and supplier part payments. Feed produced on the farm appears here too, tagged with its batch.'),
      if (_focus != null)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: const Color(0xFFF0F9FF), border: Border.all(color: const Color(0xFFBAE6FD)), borderRadius: BorderRadius.circular(6)),
          child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text.rich(TextSpan(children: [
              const TextSpan(text: 'Showing purchase '),
              TextSpan(text: '#$_focus', style: const TextStyle(fontWeight: FontWeight.w700)),
              const TextSpan(text: ' only'),
              if ((focusSupplier ?? '').isNotEmpty) ...[
                const TextSpan(text: ' — '),
                TextSpan(text: focusSupplier, style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
              const TextSpan(text: '.'),
            ]), style: const TextStyle(fontSize: 14, color: Color(0xFF0C4A6E))),
            TextButton(onPressed: () => setState(() => _focus = null), child: const Text('Show all purchases')),
          ]),
        ),
      _datedFilters('Search item or supplier'),
      const SizedBox(height: 12),
      if (rows.isEmpty)
        _empty(_focus != null ? 'Purchase #$_focus is not in this list.' : 'No purchases yet.')
      else
        for (final p in pageSlice(rows, _pPage, _pSize))
          FieldCard(
            title: tStr(p['itemName']),
            badge: tStr(p['feedProductionRole']).isNotEmpty
                ? _productionBadge(p)
                : Text(fmtDateTime(p['purchaseDate'], p, _offset), style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            fields: [
              ('Supplier', tStr(p['supplierName']).isEmpty ? '—' : tStr(p['supplierName']), null),
              ('Purchase Qty', '${loc(tNum(p['quantity']))} ${tStr(p['unitOfMeasure'])}', null),
              ('Production Qty',
                  p['productionQuantity'] != null ? '${loc(tNum(p['productionQuantity']))} ${tStr(p['productionUnit'])}'.trim() : '—', null),
              ('Unit Price', fmt(tNum(p['unitCost'])), null),
              ('Total', fmt(tNum(p['totalCost'])), null),
              ('Paid', fmt(tNum(p['amountPaid'])), null),
              ('Balance', tNum(p['balance']) > 0 ? fmt(tNum(p['balance'])) : fmt(0), tNum(p['balance']) > 0 ? TColors.amber600 : null),
            ],
            actions: tIntOrNull(p['sourceFeedProductionBatchId']) != null
                ? [
                    _iconBtn('Open the feed production batch', Icons.factory_outlined,
                        () => _href('/poultry-feed-production/${p['sourceFeedProductionBatchId']}', 'Feed Production'),
                        color: const Color(0xFF4F46E5)),
                  ]
                : [
                    if (tNum(p['balance']) > 0) _iconBtn('Pay balance', Icons.account_balance_wallet_outlined, () => _pay(p), color: TColors.emerald600),
                    _iconBtn(null, Icons.edit_outlined, () => _openPurchase(editing: p)),
                    _iconBtn(null, Icons.delete_outline, () => _deletePurchase(p), color: TColors.red600),
                  ],
          ),
      CompactPager(total: rows.length, page: _pPage, pageSize: _pSize, onPage: (x) => setState(() => _pPage = x), onPageSize: (s) => setState(() {
            _pSize = s;
            _pPage = 1;
          })),
    ]);
  }

  Widget _usageTab() {
    final rows = [
      for (final u in _usage)
        if (_dateAndSearch(u, search: _search.text, keys: const ['itemName'], from: _from, to: _to, dateKey: 'usedDate') &&
            (_itemFilter == 'all' || tStr(u['poultryRawMaterialItemId']) == _itemFilter))
          u,
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _heading('Usage History',
          'Stock consumed when production batches are recorded, including ingredients mixed into feed. Stock adjustments show here too.'),
      _datedFilters('Search item'),
      const SizedBox(height: 12),
      if (rows.isEmpty)
        _empty('No usage recorded yet.')
      else
        for (final u in pageSlice(rows, _uPage, _uSize))
          FieldCard(
            title: tStr(u['itemName']),
            badge: tIntOrNull(u['poultryFeedProductionBatchId']) != null
                ? TBadge('Feed production${tStr(u['feedProductionBatchNumber']).isNotEmpty ? ' · ${tStr(u['feedProductionBatchNumber'])}' : ''}',
                    bg: Colors.white, fg: const Color(0xFF4338CA), border: const Color(0xFFA5B4FC))
                : Text(fmtDateTime(u['usedDate'], u, _offset), style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            fields: [
              ('Used', '${loc(tNum(u['quantityUsed']))} ${tStr(u['unitOfMeasure'])}', null),
              ('Expected', u['expectedQuantityUsed'] == null ? '—' : loc(tNum(u['expectedQuantityUsed'])), null),
              ('Variance', loc(tNum(u['variance'])), null),
              ('Reason',
                  tStr(u['varianceReason']).isNotEmpty
                      ? tStr(u['varianceReason'])
                      : (tStr(u['feedProductionFeedName']).isNotEmpty ? 'Mixed into ${tStr(u['feedProductionFeedName'])}' : '—'),
                  null),
            ],
            actions: tIntOrNull(u['poultryFeedProductionBatchId']) != null
                ? [
                    _iconBtn('Open the feed production batch', Icons.factory_outlined,
                        () => _href('/poultry-feed-production/${u['poultryFeedProductionBatchId']}', 'Feed Production'),
                        color: const Color(0xFF4F46E5)),
                  ]
                : const [],
          ),
      CompactPager(total: rows.length, page: _uPage, pageSize: _uSize, onPage: (x) => setState(() => _uPage = x), onPageSize: (s) => setState(() {
            _uSize = s;
            _uPage = 1;
          })),
    ]);
  }
}

/// FieldCard: a title with a badge, a two-column "Label: value" grid, and the
/// row's actions under a rule.
class FieldCard extends StatelessWidget {
  const FieldCard({super.key, required this.title, required this.badge, required this.fields, required this.actions});
  final String title;
  final Widget badge;
  final List<(String, String, Color?)> fields;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.slate900))),
            const SizedBox(width: 8),
            Flexible(child: badge),
          ]),
          const SizedBox(height: 8),
          LayoutBuilder(builder: (context, c) {
            final w = (c.maxWidth - 12) / 2;
            return Wrap(spacing: 12, runSpacing: 4, children: [
              for (final (l, v, color) in fields)
                SizedBox(
                  width: w,
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '$l: ', style: const TextStyle(color: TColors.slate500)),
                      TextSpan(text: v, style: TextStyle(color: color, fontWeight: color != null ? FontWeight.w500 : null)),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
            ]);
          }),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(height: 1, color: TColors.slate200),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
          ],
        ]),
      );
}

/// `/poultry-raw-materials?purchase=1|tab=|purchaseId=`.
Widget? rawMaterialsScreenForHref(String href, Session s, Company c) {
  final uri = Uri.tryParse(href);
  if (uri == null || uri.path != '/poultry-raw-materials' || uri.query.isEmpty) return null;
  final q = uri.queryParameters;
  final qty = num.tryParse(q['qty'] ?? '');
  final pid = int.tryParse(q['purchaseId'] ?? '');
  return RawMaterialsScreen(
    session: s,
    company: c,
    openPurchase: q['purchase'] == '1',
    purchaseItemId: int.tryParse(q['itemId'] ?? ''),
    purchaseQty: qty != null && qty > 0 ? qty : null,
    tab: q['tab'],
    focusPurchaseId: pid != null && pid > 0 ? pid : null,
  );
}
