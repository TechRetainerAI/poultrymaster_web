// Poultry → Inventory & Supply Purchases (app/poultry-supply-purchases/page.tsx,
// formerly Raw Materials & Supplies at /poultry-raw-materials, which now
// redirects here), and Operations → Purchase → Record Purchase, which is this
// page opened with `?purchase=1`. At phone width the web shows the card lists
// (its `md:hidden` layout), so the app does too.

import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../feed_formula_form_screen.dart' show ensureDefaultFeedFormulas;
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

/// [stock]: all | low (active and low) | inactive.
List<Map> filterRawItems(List<Map> items, {String search = '', String category = 'all', String unit = 'all', String stock = 'all'}) => [
      for (final i in items)
        if (_dateAndSearch(i, search: search, keys: const ['itemName', 'category']) &&
            (category == 'all' || tStr(i['category']) == category) &&
            (unit == 'all' || tStr(i['unitOfMeasure']) == unit || tStr(i['purchaseUnitOfMeasure']) == unit) &&
            (stock != 'low' || (i['isActive'] == true && i['isLowStock'] == true)) &&
            (stock != 'inactive' || i['isActive'] != true))
          i,
    ];

/// [pay]: all | unpaid (not reversed, balance owed) | paid.
List<Map> filterRawPurchases(List<Map> rows,
    {String search = '', String from = '', String to = '', String item = 'all', int? focusId, String pay = 'all'}) {
  if (focusId != null) return [for (final p in rows) if (tIntOrNull(p['poultryRawMaterialPurchaseId']) == focusId) p];
  return [
    for (final p in rows)
      if (_dateAndSearch(p, search: search, keys: const ['itemName', 'supplierName'], from: from, to: to, dateKey: 'purchaseDate') &&
          (item == 'all' || tStr(p['poultryRawMaterialItemId']) == item) &&
          (pay != 'unpaid' || (p['isReversed'] != true && tNum(p['balance']) > 0)) &&
          (pay != 'paid' || tNum(p['balance']) <= 0))
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

/// The summary: purchases produced on the farm are not spend, and a reversed
/// receipt's lot (345) stays in the history but was never spend.
({int items, int active, int low, num purchaseTotal, num paid, num outstanding, int produced}) rawStats(List<Map> items, List<Map> purchases) {
  final spend = [for (final p in purchases) if (tStr(p['feedProductionRole']) != 'Produced' && p['isReversed'] != true) p];
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

  /// Quick filter chips (and the tappable Low stock / Outstanding cards).
  String _stockFilter = 'all', _payFilter = 'all';
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

  /// 385: the default feeds and ingredients, once per page visit (and once
  /// per farm on the server).
  bool _feedDefaultsDone = false;

  Future<void> _load() async {
    setState(() => _loading = true);
    if (!_feedDefaultsDone) {
      _feedDefaultsDone = true;
      await ensureDefaultFeedFormulas(widget.session, widget.company).catchError((_) => (0, 0));
    }
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
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-supply-purchases');
    final s = rawStats(_items, _purchases);
    final fmt = _fmt;
    final v = _valuation;
    final summary = v?['summary'] is Map ? v!['summary'] as Map : const {};
    final findings = rowsOf(v?['auditFindings']);
    final deferred = tNum(summary['deferredValue']);

    Widget kpi({required IconData icon, required Color iconColor, required String label, required String value, Widget? sub, String? tone, VoidCallback? onTap, String? tip}) {
      final card = Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: tone == 'warn' ? TColors.amber200 : tone == 'bad' ? TColors.red200 : TColors.slate200),
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
            child: Text(value,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: tone == 'warn' ? TColors.amber700 : tone == 'bad' ? TColors.red600 : tone == 'good' ? TColors.emerald700 : TColors.slate900)),
          ),
          if (sub != null) DefaultTextStyle.merge(style: const TextStyle(fontSize: 12, color: TColors.slate500), child: sub),
        ]),
      );
      final tapped = onTap == null ? card : InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12), child: card);
      return tip == null ? tapped : Tooltip(message: tip, child: tapped);
    }

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
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Inventory & Supply Purchases')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            const Text('Inventory & Supply Purchases', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: TColors.slate900)),
            const Text('Feed inputs, packaging, medication and other supplies — what you hold, what you bought, what was used.',
                style: TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 12),
            // One clear primary action; Receive invoice, Produce feed and
            // Recalculate stock are occasional jobs, under More.
            Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: () => _openItem(), icon: const Icon(Icons.add, size: 16), label: const Text('New Item'))),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(onPressed: () => _openPurchase(), icon: const Icon(Icons.shopping_cart_outlined, size: 16), label: const Text('Record Purchase')),
              ),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                tooltip: 'More actions',
                icon: const Icon(Icons.more_horiz),
                onSelected: (k) => switch (k) {
                  'receive' => _href('/poultry-purchase-receipts?receive=1', 'Receive Purchase'),
                  'feed' => _href('/poultry-feed-production', 'Feed Production'),
                  _ => _recalculate(),
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'receive', child: ListTile(dense: true, leading: Icon(Icons.inventory_outlined), title: Text('Receive invoice'))),
                  PopupMenuItem(value: 'feed', child: ListTile(dense: true, leading: Icon(Icons.factory_outlined), title: Text('Produce feed'))),
                  PopupMenuItem(value: 'recalc', child: ListTile(dense: true, leading: Icon(Icons.refresh), title: Text('Recalculate stock'))),
                ],
              ),
            ]),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(padding: EdgeInsets.all(24), child: Text('Loading…', style: TextStyle(color: TColors.slate500)))
            else ...[
              // One summary row; Low stock and Outstanding open the list
              // already filtered to them.
              _pairs([
                kpi(
                  icon: Icons.inventory_2_outlined,
                  iconColor: TColors.blue600,
                  label: 'Stock value',
                  value: v != null ? fmt(tNum(summary['operationalValue'])) : loc(s.active),
                  tip: v != null ? operationalValueTooltip : null,
                  sub: v != null
                      ? Wrap(children: [
                          Text('${tStr(summary['itemsWithStock'])} item${tNum(summary['itemsWithStock']) == 1 ? '' : 's'} in stock'),
                          if (deferred > 0) ...[
                            const Text(' · '),
                            InkWell(
                              onTap: () => _href('/poultry-deferred-costs', 'Deferred inventory cost'),
                              child: Text('${fmt(deferred)} deferred',
                                  style: const TextStyle(color: TColors.amber700, decoration: TextDecoration.underline)),
                            ),
                          ],
                        ])
                      : Text('active of ${loc(s.items)} items'),
                ),
                kpi(
                  icon: Icons.warning_amber_outlined,
                  iconColor: s.low > 0 ? TColors.amber600 : TColors.slate400,
                  label: 'Low stock',
                  value: loc(s.low),
                  tone: s.low > 0 ? 'warn' : null,
                  sub: Text(s.low > 0 ? 'need restocking · view' : 'all stocked'),
                  onTap: s.low > 0
                      ? () {
                          setState(() => _stockFilter = 'low');
                          _selectTab('items');
                        }
                      : null,
                ),
                kpi(
                  icon: Icons.shopping_cart_outlined,
                  iconColor: TColors.emerald600,
                  label: 'Purchases',
                  value: fmt(s.purchaseTotal),
                  sub: Text('Paid ${fmt(s.paid)}'),
                  tip: s.produced > 0 ? 'Excludes ${s.produced} feed lot(s) produced on the farm: their cost is the ingredients, already counted.' : null,
                ),
                kpi(
                  icon: Icons.account_balance_wallet_outlined,
                  iconColor: s.outstanding > 0 ? TColors.red600 : TColors.slate400,
                  label: 'Outstanding',
                  value: fmt(s.outstanding),
                  tone: s.outstanding > 0 ? 'bad' : 'good',
                  sub: Text(s.outstanding > 0 ? 'owed to suppliers · view' : 'nothing owed'),
                  onTap: s.outstanding > 0
                      ? () {
                          setState(() => _payFilter = 'unpaid');
                          _selectTab('purchases');
                        }
                      : null,
                ),
              ]),
              // The costing audit is silent when healthy, so anything here is
              // worth reading. Reported, never silently repaired.
              if (findings.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: TColors.amber50, border: Border.all(color: TColors.amber300), borderRadius: BorderRadius.circular(8)),
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
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    tabButton('items', Icons.inventory_2_outlined, 'Items', loc(_items.length)),
                    tabButton('purchases', Icons.shopping_cart_outlined, 'Purchases', loc(_purchases.length)),
                    tabButton('usage', Icons.history, 'Usage', _usageLoaded ? loc(_usage.length) : null),
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

  /// Two to a row.
  Widget _pairs(List<Widget> cells) => Column(children: [
        for (var i = 0; i < cells.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: cells[i]),
              const SizedBox(width: 10),
              Expanded(child: i + 1 < cells.length ? cells[i + 1] : const SizedBox.shrink()),
            ]),
          ),
        ],
      ]);

  /// Quick filter chip with a count.
  Widget _chip(String label, bool active, VoidCallback onTap, int count, {String? tone}) => Padding(
        padding: const EdgeInsets.only(right: 6, bottom: 6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: active ? TColors.blue600 : Colors.white,
              border: Border.all(color: active ? TColors.blue600 : TColors.slate200),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: active ? Colors.white : TColors.slate600)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: active
                      ? Colors.white24
                      : tone == 'warn' && count > 0
                          ? TColors.amber100
                          : tone == 'bad' && count > 0
                              ? TColors.red100
                              : TColors.slate100,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(loc(count),
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: active
                            ? Colors.white
                            : tone == 'warn' && count > 0
                                ? TColors.amber800
                                : tone == 'bad' && count > 0
                                    ? TColors.red700
                                    : TColors.slate600)),
              ),
            ]),
          ),
        ),
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

  /// In stock / Low stock / Inactive.
  Widget _statusBadge(Map i) => i['isActive'] != true
      ? const TBadge('Inactive', bg: TColors.slate100, fg: TColors.slate800)
      : i['isLowStock'] == true
          ? const TBadge('Low stock', bg: TColors.amber100, fg: TColors.amber800)
          : const TBadge('In stock', bg: TColors.emerald50, fg: TColors.emerald700);

  /// Paid / Part paid / Unpaid, with what is still owed.
  Widget _paymentPill(Map p) {
    if (tStr(p['feedProductionRole']) == 'Produced') return const Text('Produced', style: TextStyle(fontSize: 12, color: TColors.slate400));
    if (p['isReversed'] == true) return const Text('Reversed', style: TextStyle(fontSize: 12, color: TColors.slate400));
    final balance = tNum(p['balance']), paid = tNum(p['amountPaid']);
    if (balance <= 0) return const TBadge('Paid', bg: TColors.emerald50, fg: TColors.emerald700);
    return Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
      paid > 0
          ? const TBadge('Part paid', bg: TColors.amber100, fg: TColors.amber800)
          : const TBadge('Unpaid', bg: TColors.red50, fg: TColors.red700),
      Text('${_fmt(balance)} due', style: const TextStyle(fontSize: 11, color: TColors.slate500)),
    ]);
  }

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

  /// Purchase unit → production unit, or the one unit when they are the same.
  static String unitsText(Map i) {
    final prod = tStr(i['unitOfMeasure']), buy = tStr(i['purchaseUnitOfMeasure']);
    if (prod.isEmpty && buy.isEmpty) return '—';
    if (buy.isEmpty || buy == prod) return prod.isNotEmpty ? prod : buy;
    return '$buy → $prod';
  }

  List<Widget> _itemActions(Map i) => [
        // Feed items only: the tracker reads the two feed categories.
        if (feedItemKind(i['category']) != null)
          _iconBtn('Track movements', Icons.history, () => _href('/feed-inventory-tracker?itemId=${i['poultryRawMaterialItemId']}', 'Feed inventory tracker'),
              color: TColors.amber700),
        _iconBtn('Buy more', Icons.shopping_cart_outlined, () => _openPurchase(itemId: tIntOrNull(i['poultryRawMaterialItemId'])), color: TColors.blue600),
        _iconBtn('Edit item', Icons.edit_outlined, () => _openItem(i)),
        _iconBtn('Delete item', Icons.delete_outline, () => _deleteItem(i), color: TColors.red600),
      ];

  Widget _itemsTab() {
    final fmt = _fmt;
    final s = rawStats(_items, _purchases);
    final byItem = {
      for (final x in rowsOf(_valuation?['items'])) tIntOrNull(x['poultryRawMaterialItemId']): x,
    };
    final units = <String>{
      for (final i in _items) ...[
        if (tStr(i['unitOfMeasure']).isNotEmpty) tStr(i['unitOfMeasure']),
        if (tStr(i['purchaseUnitOfMeasure']).isNotEmpty) tStr(i['purchaseUnitOfMeasure']),
      ],
    }.toList()
      ..sort();
    final rows = filterRawItems(_items, search: _search.text, category: _category, unit: _unit, stock: _stockFilter);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(children: [
        _chip('All', _stockFilter == 'all', () => setState(() => _stockFilter = 'all'), _items.length),
        _chip('Low stock', _stockFilter == 'low', () => setState(() => _stockFilter = 'low'), s.low, tone: 'warn'),
        _chip('Inactive', _stockFilter == 'inactive', () => setState(() => _stockFilter = 'inactive'), s.items - s.active),
      ]),
      const SizedBox(height: 6),
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
        _empty(_items.isEmpty ? 'No items yet — add one with New Item.' : 'No items match these filters.')
      else
        for (final i in pageSlice(rows, _iPage, _iSize))
          FieldCard(
            title: tStr(i['itemName']),
            badge: _statusBadge(i),
            fields: [
              ('Category', rawCategoryLabel(i['category']), null),
              ('Units', unitsText(i), null),
              ('In stock', '${loc(tNum(i['currentQuantity']))} ${tStr(i['unitOfMeasure'])}'.trim(), i['isActive'] == true && i['isLowStock'] == true ? TColors.amber700 : null),
              ('Min alert', loc(tNum(i['minimumStockAlert'])), null),
              ('Cost', '${methodShortLabel(i['effectiveCostRecognitionMethod'])}${tStr(i['costRecognitionSource']) == 'ItemOverride' ? ' (override)' : ''}', null),
              ('Stock value', byItem[tIntOrNull(i['poultryRawMaterialItemId'])] != null ? fmt(tNum(byItem[tIntOrNull(i['poultryRawMaterialItemId'])]!['operationalValue'])) : '—', null),
            ],
            actions: _itemActions(i),
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
    final label = '${produced ? 'Produced' : 'For production'}'
        '${tStr(p['feedProductionBatchNumber']).isNotEmpty ? ' · ${tStr(p['feedProductionBatchNumber'])}' : ''}';
    return TBadge(label,
        bg: Colors.white, fg: produced ? TColors.emerald700 : const Color(0xFF4338CA), border: produced ? TColors.emerald300 : const Color(0xFFA5B4FC));
  }

  /// 345: the receipt a lot came in on, and whether that receipt was reversed.
  Widget _receiptBadges(Map p) => Wrap(spacing: 4, children: [
        if (tStr(p['receiptNumber']).isNotEmpty) TBadge(tStr(p['receiptNumber']), bg: Colors.white, fg: TColors.emerald700, border: TColors.emerald300),
        if (p['isReversed'] == true) const TBadge('Reversed', bg: Colors.white, fg: TColors.slate500, border: TColors.slate300),
      ]);

  /// A feed-production lot belongs to its batch; a receipt's lot is changed
  /// through its receipt; anything else is edited here.
  List<Widget> _purchaseActions(Map p) {
    if (tIntOrNull(p['sourceFeedProductionBatchId']) != null) {
      return [
        _iconBtn('Open feed production batch', Icons.factory_outlined,
            () => _href('/poultry-feed-production/${p['sourceFeedProductionBatchId']}', 'Feed Production'),
            color: const Color(0xFF4F46E5)),
      ];
    }
    final hasBalance = tNum(p['balance']) > 0;
    if (tIntOrNull(p['poultryPurchaseReceiptId']) != null || p['isReversed'] == true) {
      return [
        if (p['isReversed'] != true && hasBalance) _iconBtn('Pay balance', Icons.account_balance_wallet_outlined, () => _pay(p), color: TColors.emerald600),
        if (tIntOrNull(p['poultryPurchaseReceiptId']) != null)
          _iconBtn('Open receipt ${tStr(p['receiptNumber'])}'.trim(), Icons.inventory_outlined, () => _href('/poultry-purchase-receipts', 'Receive Purchase'),
              color: TColors.emerald600),
      ];
    }
    return [
      if (hasBalance) _iconBtn('Pay balance', Icons.account_balance_wallet_outlined, () => _pay(p), color: TColors.emerald600),
      _iconBtn('Edit purchase', Icons.edit_outlined, () => _openPurchase(editing: p)),
      _iconBtn('Delete purchase', Icons.delete_outline, () => _deletePurchase(p), color: TColors.red600),
    ];
  }

  Widget _purchasesTab() {
    final fmt = _fmt;
    final rows = filterRawPurchases(_purchases, search: _search.text, from: _from, to: _to, item: _itemFilter, focusId: _focus, pay: _payFilter);
    final unpaid = _purchases.where((p) => p['isReversed'] != true && tNum(p['balance']) > 0).length;
    final focusSupplier = _focus == null
        ? null
        : tStr(_purchases.where((p) => tIntOrNull(p['poultryRawMaterialPurchaseId']) == _focus).firstOrNull?['supplierName']);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
        )
      else ...[
        Wrap(children: [
          _chip('All', _payFilter == 'all', () => setState(() => _payFilter = 'all'), _purchases.length),
          _chip('Unpaid', _payFilter == 'unpaid', () => setState(() => _payFilter = 'unpaid'), unpaid, tone: 'bad'),
          _chip('Paid', _payFilter == 'paid', () => setState(() => _payFilter = 'paid'), _purchases.length - unpaid),
        ]),
        const SizedBox(height: 6),
      ],
      _datedFilters('Search item or supplier'),
      const SizedBox(height: 12),
      if (rows.isEmpty)
        _empty(_focus != null
            ? 'Purchase #$_focus is not in this list.'
            : _purchases.isEmpty
                ? 'No purchases yet — record one with Record Purchase.'
                : 'No purchases match these filters.')
      else
        for (final p in pageSlice(rows, _pPage, _pSize))
          FieldCard(
            title: tStr(p['itemName']),
            badge: _paymentPill(p),
            fields: [
              ('Date', fmtDateTime(p['purchaseDate'], p, _offset), null),
              ('Supplier', tStr(p['supplierName']).isEmpty ? '—' : tStr(p['supplierName']), null),
              ('Quantity', '${loc(tNum(p['quantity']))} ${tStr(p['unitOfMeasure'])}'.trim(), null),
              ('Unit price', fmt(tNum(p['unitCost'])), null),
              ('Total', fmt(tNum(p['totalCost'])), null),
            ],
            extra: [
              if (tStr(p['feedProductionRole']).isNotEmpty) ('Feed', _productionBadge(p)),
              if (tStr(p['receiptNumber']).isNotEmpty || p['isReversed'] == true) ('Receipt', _receiptBadges(p)),
            ],
            actions: _purchaseActions(p),
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
      const Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: Text('Stock used by production and feed mixing, plus manual stock adjustments.', style: TextStyle(fontSize: 12, color: TColors.slate500)),
      ),
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

/// FieldCard: a title with a badge, a two-column "Label: value" grid (plus any
/// widget fields), and the row's actions under a rule.
class FieldCard extends StatelessWidget {
  const FieldCard({super.key, required this.title, required this.badge, required this.fields, required this.actions, this.extra = const []});
  final String title;
  final Widget badge;
  final List<(String, String, Color?)> fields;

  /// Fields whose value is a widget (badges).
  final List<(String, Widget)> extra;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.slate900))),
            const SizedBox(width: 8),
            Flexible(child: Align(alignment: Alignment.centerRight, child: badge)),
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
              for (final (l, w2) in extra)
                SizedBox(
                  width: w,
                  child: Row(children: [
                    Text('$l: ', style: const TextStyle(fontSize: 13, color: TColors.slate500)),
                    Flexible(child: w2),
                  ]),
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

/// `/poultry-supply-purchases?purchase=1|tab=|purchaseId=`, and the old
/// `/poultry-raw-materials` address, which the web redirects here with its query.
Widget? rawMaterialsScreenForHref(String href, Session s, Company c) {
  final uri = Uri.tryParse(href);
  if (uri == null || (uri.path != '/poultry-supply-purchases' && uri.path != '/poultry-raw-materials')) return null;
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
