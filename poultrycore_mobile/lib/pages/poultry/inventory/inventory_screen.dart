// Poultry → Operations → Inventory & Health → Inventory
// (app/poultry-inventory/page.tsx): finished products and raw materials in one
// place — search, the three stock tools, four figures, filters, Export PDF /
// Email Report, and the Finished products / Raw materials tabs.

import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../money/money_widgets.dart';
import '../purchase/raw_material_dialogs.dart' show RecalculateStockDialog;
import '../reports/report_export.dart';
import '../reports/report_format.dart';
import '../reports/report_routes.dart' show openAppHref;
import '../sales/balances_logic.dart' show pageSlice;
import '../sales/balances_widgets.dart' show CompactPager;
import '../trackers/tracker_logic.dart' show tNum, tStr, loc, feedItemKind;
import '../trackers/tracker_widgets.dart';
import 'stock_dialogs.dart';

/// ok · low · out · inactive.
typedef StockTone = String;

({String label, StockTone tone}) productStockStatus(Map p) {
  if (p['isActive'] != true) return (label: 'Inactive', tone: 'inactive');
  if (tNum(p['stockOnHand']) <= 0) return (label: 'Out of stock', tone: 'out');
  return (label: 'In stock', tone: 'ok');
}

({String label, StockTone tone}) rawStockStatus(Map r) {
  if (r['isActive'] != true) return (label: 'Inactive', tone: 'inactive');
  final s = tNum(r['currentQuantity']), min = tNum(r['minimumStockAlert']);
  if (s <= 0) return (label: 'Out of stock', tone: 'out');
  if (r['isLowStock'] == true || (min > 0 && s <= min)) return (label: 'Low stock', tone: 'low');
  return (label: 'In stock', tone: 'ok');
}

/// "N crates + loose" for 30 eggs or more.
String? crateEquivalent(num eggs) {
  if (eggs < 30) return null;
  final crates = eggs ~/ 30, loose = eggs % 30;
  return '${loc(crates)} crate${crates == 1 ? '' : 's'}${loose != 0 ? ' + ${loc(loose)}' : ''}';
}

({String href, String label}) productLink(Map p) {
  final id = tStr(p['poultryProductId']);
  if (p['isRawEggProduct'] == true) return (href: '/egg-tracker?inventoryItemId=$id', label: 'Egg Tracker');
  if (p['isBirdProduct'] == true) return (href: '/birds-left-tracker?inventoryItemId=$id', label: 'Birds Tracker');
  return (href: '/poultry-stock?productId=$id', label: 'View Stock');
}

({String href, String label}) rawLink(Map r) {
  final id = tStr(r['poultryRawMaterialItemId']);
  if (feedItemKind(r['category']) != null) return (href: '/feed-inventory-tracker?itemId=$id', label: 'Feed Tracker');
  final c = tStr(r['category']);
  if (c == 'Medication' || c == 'Vaccine') return (href: '/medication-tracker?inventoryItemId=$id', label: 'Medication Tracker');
  return (href: '/poultry-stock?rawId=$id', label: 'View Details');
}

class InventoryFilters {
  String q = '', category = 'ALL', status = 'ALL', from = '', to = '';
  bool get any => q.isNotEmpty || category != 'ALL' || status != 'ALL' || from.isNotEmpty || to.isNotEmpty;
}

bool _matchesQ(String q, List<Object?> fields) {
  final t = q.trim().toLowerCase();
  return t.isEmpty || fields.any((f) => tStr(f).toLowerCase().contains(t));
}

bool _matchesDate(InventoryFilters f, Object? iso) {
  final s = tStr(iso);
  final day = s.length >= 10 ? s.substring(0, 10) : '';
  if (f.from.isNotEmpty && (day.isEmpty || day.compareTo(f.from) < 0)) return false;
  if (f.to.isNotEmpty && (day.isEmpty || day.compareTo(f.to) > 0)) return false;
  return true;
}

bool _matchesStatus(String status, StockTone tone) => status == 'ALL' || status == tone;

List<Map> filterInventoryProducts(List<Map> products, InventoryFilters f) => [
      for (final p in products)
        if (_matchesQ(f.q, [p['name'], p['sku'], p['productType'], p['unit']]) &&
            (f.category == 'ALL' || tStr(p['productType']) == f.category) &&
            _matchesStatus(f.status, productStockStatus(p).tone) &&
            _matchesDate(f, p['createdDate']))
          p,
    ]..sort((a, b) => tStr(a['name']).compareTo(tStr(b['name'])));

List<Map> filterInventoryRaw(List<Map> items, InventoryFilters f) => [
      for (final r in items)
        if (_matchesQ(f.q, [r['itemName'], r['category'], r['unitOfMeasure']]) &&
            (f.category == 'ALL' || tStr(r['category']) == f.category) &&
            _matchesStatus(f.status, rawStockStatus(r).tone) &&
            _matchesDate(f, r['createdAt']))
          r,
    ]..sort((a, b) => tStr(a['itemName']).compareTo(tStr(b['itemName'])));

Widget toneBadge(({String label, StockTone tone}) s) => switch (s.tone) {
      'inactive' => TBadge(s.label, bg: TColors.slate100, fg: TColors.slate800),
      'out' => TBadge(s.label, bg: TColors.rose100, fg: TColors.rose700),
      'low' => TBadge('⚠ ${s.label}', bg: TColors.amber100, fg: TColors.amber700),
      _ => TBadge(s.label, bg: TColors.emerald100, fg: TColors.emerald700),
    };

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  List<Map> _products = [], _items = [];
  bool _loading = true, _emailing = false;
  String _tab = 'products';
  final _f = InventoryFilters();
  final _q = TextEditingController();
  int _pPage = 1, _pSize = 10, _rPage = 1, _rSize = 10;
  FarmMoney _fmt = const FarmMoney();

  ApiClient get _api => widget.session.farmClient;
  Map<String, String> get _farm => {'farmId': widget.company.farmId};

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _fmt = m);
    });
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      try {
        await _api.post('/api/Poultry/products/ensure-defaults', query: _farm);
      } on ApiException {
        // best effort, as on the web
      }
      final r = await Future.wait([
        _api.get('/api/Poultry/products', query: _farm).then(rowsOf),
        _api.get('/api/Poultry/raw-material-items', query: _farm).then(rowsOf),
      ]);
      if (mounted) {
        setState(() {
          _products = r[0];
          _items = r[1];
        });
      }
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load inventory', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _reloadProducts() async {
    try {
      final r = await _api.get('/api/Poultry/products', query: _farm);
      if (mounted) setState(() => _products = rowsOf(r));
    } on ApiException {
      // keep what is shown
    }
  }

  Future<void> _reloadItems() async {
    try {
      final r = await _api.get('/api/Poultry/raw-material-items', query: _farm);
      if (mounted) setState(() => _items = rowsOf(r));
    } on ApiException {
      // keep what is shown
    }
  }

  List<String> get _categories => {
        for (final p in _products) if (tStr(p['productType']).isNotEmpty) tStr(p['productType']),
        for (final i in _items) if (tStr(i['category']).isNotEmpty) tStr(i['category']),
      }.toList()
        ..sort();

  ({int total, int low, int out, num finished}) get _counts {
    var low = 0, out = 0;
    for (final t in [for (final p in _products) productStockStatus(p).tone, for (final r in _items) rawStockStatus(r).tone]) {
      if (t == 'low') low++;
      if (t == 'out') out++;
    }
    return (total: _products.length + _items.length, low: low, out: out, finished: _products.fold<num>(0, (s, p) => s + tNum(p['stockOnHand'])));
  }

  ReportDocument _doc(List<Map> products, List<Map> raw) => ReportDocument(
        title: 'Inventory Report',
        filename: 'poultry-inventory',
        farmName: widget.company.name,
        sections: [
          ReportSection(
            columns: const [
              ReportColumn('Item'), ReportColumn('Parent Type'), ReportColumn('Type / Category'), ReportColumn('Size'),
              ReportColumn('Unit'), ReportColumn('Unit price', right: true), ReportColumn('In stock', right: true), ReportColumn('Status'),
            ],
            rows: [
              for (final p in products)
                [
                  tStr(p['name']), 'Finished Product', tStr(p['productType']), tStr(p['size']), tStr(p['unit']),
                  _fmt(tNum(p['unitPrice'])), loc(tNum(p['stockOnHand'])), productStockStatus(p).label,
                ],
              for (final r in raw)
                [tStr(r['itemName']), 'Raw Material', tStr(r['category']), '', tStr(r['unitOfMeasure']), '', loc(tNum(r['currentQuantity'])), rawStockStatus(r).label],
            ],
          ),
        ],
        notes: ['Items: ${products.length + raw.length}'],
      );

  Future<void> _exportPdf(List<Map> products, List<Map> raw) async {
    if (products.isEmpty && raw.isEmpty) {
      trackerToast(context, 'Nothing to export', description: 'No inventory items match the current filters.', error: true);
      return;
    }
    try {
      await ReportExport.sharePdf(_doc(products, raw));
    } catch (_) {
      if (mounted) trackerToast(context, 'PDF export failed', description: 'Could not generate PDF. Please try again.', error: true);
    }
  }

  Future<void> _email(List<Map> products, List<Map> raw) async {
    if (products.isEmpty && raw.isEmpty) {
      trackerToast(context, 'Nothing to email', description: 'No inventory items match the current filters.', error: true);
      return;
    }
    final to = (widget.session.tokens.username ?? '').trim();
    if (to.isEmpty || !to.contains('@')) {
      trackerToast(context, 'Email failed',
          description: 'No recipient email found. Sign in with an email address or pass an explicit `to`.', error: true);
      return;
    }
    setState(() => _emailing = true);
    try {
      await ReportExport.email(_api, _doc(products, raw), [to]);
      if (mounted) trackerToast(context, 'Report emailed', description: 'Sent to $to.');
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Email failed', description: e.message.isNotEmpty ? e.message : 'Could not send report.', error: true);
    }
    if (mounted) setState(() => _emailing = false);
  }

  void _href(String href, String label) => openAppHref(context, widget.session, widget.company, href, label: label);

  Future<void> _tool(Widget dialog, Future<void> Function() reload) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => dialog);
    if (ok == true) await reload();
  }

  void _reset() => setState(() {
        _q.clear();
        _f
          ..q = ''
          ..category = 'ALL'
          ..status = 'ALL'
          ..from = ''
          ..to = '';
        _pPage = _rPage = 1;
      });

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-inventory');
    final products = filterInventoryProducts(_products, _f);
    final raw = filterInventoryRaw(_items, _f);
    final c = _counts;

    Widget stat(String label, String value, IconData icon, (Color, Color) tone) => TCard(
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: tone.$1, borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 20, color: tone.$2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900)),
                ),
              ]),
            ),
          ]),
        );

    Widget tab(String key, IconData icon, String label, int count) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Material(
              color: _tab == key ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => setState(() => _tab = key),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(icon, size: 16, color: TColors.slate700),
                    const SizedBox(width: 6),
                    Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                    const SizedBox(width: 6),
                    TBadge('$count', bg: TColors.slate100, fg: TColors.slate800),
                  ]),
                ),
              ),
            ),
          ),
        );

    final orange = (const Color(0xFFFFEDD5), const Color(0xFFC2410C));
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Poultry inventory')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: orange.$1, borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.inventory_2_outlined, size: 24, color: orange.$2),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Poultry inventory', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900)),
                Text('Finished products and raw materials in one place.', style: TextStyle(fontSize: 13, color: TColors.slate600)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          AppInput(
            controller: _q,
            hintText: 'Search by name, SKU, category…',
            prefixIcon: const Icon(Icons.search, size: 18, color: TColors.slate400),
            onChanged: (v) => setState(() {
              _f.q = v;
              _pPage = _rPage = 1;
            }),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              onPressed: () => _tool(RecalculateStockDialog(session: widget.session, company: widget.company, items: _items), _reloadItems),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Recalculate stock'),
            ),
            OutlinedButton.icon(
              onPressed: () => _tool(ReconcileProductStockDialog(session: widget.session, company: widget.company, products: _products), _reloadProducts),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Recalculate product stock'),
            ),
            OutlinedButton.icon(
              onPressed: () => _tool(SetProductStockDialog(session: widget.session, company: widget.company, products: _products), _reloadProducts),
              icon: const Icon(Icons.fact_check_outlined, size: 16),
              label: const Text('Set product stock'),
            ),
          ]),
          const SizedBox(height: 14),
          twoUp([
            stat('Total items', _loading ? '…' : '${c.total}', Icons.inventory_2_outlined, orange),
            stat('Low stock', _loading ? '…' : '${c.low}', Icons.warning_amber_outlined, (TColors.amber100, TColors.amber700)),
            stat('Out of stock', _loading ? '…' : '${c.out}', Icons.error_outline, (TColors.rose100, TColors.rose700)),
            stat('Total finished stock', _loading ? '…' : loc(c.finished), Icons.layers_outlined, (TColors.emerald100, TColors.emerald700)),
          ]),
          const SizedBox(height: 14),
          TCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AppSelect<String>(
                value: _f.category,
                hintText: 'Type / Category',
                items: [const AppSelectItem(value: 'ALL', label: 'All categories'), for (final x in _categories) AppSelectItem(value: x, label: x)],
                onChanged: (v) => setState(() {
                  _f.category = v ?? 'ALL';
                  _pPage = _rPage = 1;
                }),
              ),
              const SizedBox(height: 8),
              AppSelect<String>(
                value: _f.status,
                hintText: 'Status',
                items: const [
                  AppSelectItem(value: 'ALL', label: 'All statuses'),
                  AppSelectItem(value: 'ok', label: 'In stock'),
                  AppSelectItem(value: 'low', label: 'Low stock'),
                  AppSelectItem(value: 'out', label: 'Out of stock'),
                  AppSelectItem(value: 'inactive', label: 'Inactive'),
                ],
                onChanged: (v) => setState(() {
                  _f.status = v ?? 'ALL';
                  _pPage = _rPage = 1;
                }),
              ),
              const SizedBox(height: 8),
              FilterDate(value: _f.from, hint: 'Date added from', onChanged: (v) => setState(() => _f.from = v)),
              const SizedBox(height: 8),
              FilterDate(value: _f.to, hint: 'Date added to', onChanged: (v) => setState(() => _f.to = v)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(onPressed: () => _exportPdf(products, raw), icon: const Icon(Icons.download, size: 16), label: const Text('Export PDF')),
                OutlinedButton.icon(
                  onPressed: _emailing ? null : () => _email(products, raw),
                  icon: _emailing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.mail_outline, size: 16),
                  label: const Text('Email Report'),
                ),
                OutlinedButton.icon(onPressed: _reset, icon: const Icon(Icons.refresh, size: 16), label: const Text('Reset')),
              ]),
            ]),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(color: TColors.slate100, borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              tab('products', Icons.shopping_bag_outlined, 'Finished products', products.length),
              tab('raw', Icons.inventory_2_outlined, 'Raw materials', raw.length),
            ]),
          ),
          const SizedBox(height: 12),
          if (_tab == 'products') _productsTab(products) else _rawTab(raw),
        ],
      ),
    );
  }

  Widget _tabHeader(String text, String button, String href, String label) => Container(
        padding: const EdgeInsets.all(12),
        color: TColors.slate50,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(text, style: const TextStyle(fontSize: 13, color: TColors.slate600)),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: () => _href(href, label), icon: const Icon(Icons.open_in_new, size: 16), label: Text(button)),
        ]),
      );

  Widget _empty(String t) => Padding(
        padding: const EdgeInsets.all(28),
        child: Text(t, textAlign: TextAlign.center, style: const TextStyle(color: TColors.slate500)),
      );

  Widget _productsTab(List<Map> rows) => TCard(
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _tabHeader(
            'Eggs and packaged products: stock = SUM(PoultryStockTransactions), the same ledger the Egg Tracker balances. Birds: birds left in your flocks.',
            'Manage products',
            '/poultry-products',
            'Products',
          ),
          if (_loading)
            _empty('Loading…')
          else if (rows.isEmpty)
            _empty(_f.any ? 'No products match your filters.' : 'No products yet.')
          else
            Padding(
              padding: const EdgeInsets.all(12),
              child: MobileCardList<Map>(
                items: pageSlice(rows, _pPage, _pSize),
                keyOf: (p) => tStr(p['poultryProductId']),
                primary: (p) => tStr(p['name']),
                secondaryBuilder: (p) => Align(alignment: Alignment.centerLeft, child: toneBadge(productStockStatus(p))),
                details: (p) {
                  final stock = tNum(p['stockOnHand']);
                  final crates = p['isRawEggProduct'] == true ? crateEquivalent(stock) : null;
                  return [
                    ('Type', tStr(p['productType']).isEmpty ? '—' : tStr(p['productType'])),
                    ('SKU', tStr(p['sku']).isEmpty ? '—' : tStr(p['sku'])),
                    ('Size', tStr(p['size']).isEmpty ? '—' : tStr(p['size'])),
                    ('Unit', tStr(p['unit']).isEmpty ? '—' : tStr(p['unit'])),
                    ('Unit price', _fmt(tNum(p['unitPrice']))),
                    ('In stock', crates != null ? '${loc(stock)} ($crates)' : loc(stock)),
                    ('Details', productLink(p).label),
                  ];
                },
                detailTap: (p, label) => label == 'Details' ? () => _href(productLink(p).href, productLink(p).label) : null,
                pager: CompactPager(total: rows.length, page: _pPage, pageSize: _pSize, onPage: (x) => setState(() => _pPage = x), onPageSize: (s) => setState(() {
                      _pSize = s;
                      _pPage = 1;
                    })),
                table: (items) => TrackerTable(
                  columns: const [
                    TCol('Item', width: 130), TCol('Type', width: 110), TCol('SKU', width: 90), TCol('Size', width: 80), TCol('Unit', width: 80),
                    TCol('Unit price', right: true, width: 110), TCol('In stock', right: true, width: 120), TCol('Status', width: 120), TCol('Details', width: 120),
                  ],
                  rows: [
                    for (final p in items)
                      [
                        cellText(tStr(p['name']), bold: true),
                        cellText(tStr(p['productType']).isEmpty ? '—' : tStr(p['productType'])),
                        cellText(tStr(p['sku']).isEmpty ? '—' : tStr(p['sku']), color: TColors.slate600),
                        cellText(tStr(p['size']).isEmpty ? '—' : tStr(p['size'])),
                        cellText(tStr(p['unit']).isEmpty ? '—' : tStr(p['unit'])),
                        cellText(_fmt(tNum(p['unitPrice']))),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                          Text(loc(tNum(p['stockOnHand'])), style: const TextStyle(fontWeight: FontWeight.w600)),
                          if (p['isRawEggProduct'] == true && crateEquivalent(tNum(p['stockOnHand'])) != null)
                            Text(crateEquivalent(tNum(p['stockOnHand']))!, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                        ]),
                        Align(alignment: Alignment.centerLeft, child: toneBadge(productStockStatus(p))),
                        InkWell(
                          onTap: () => _href(productLink(p).href, productLink(p).label),
                          child: Text(productLink(p).label, style: const TextStyle(fontSize: 13, color: TColors.blue600)),
                        ),
                      ],
                  ],
                ),
              ),
            ),
        ]),
      );

  Widget _rawTab(List<Map> rows) => TCard(
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _tabHeader('Feed ingredients, medication, vaccines. Stock updated by purchases + production usage.', 'Manage raw materials',
              '/poultry-raw-materials', 'Raw Materials'),
          if (_loading)
            _empty('Loading…')
          else if (rows.isEmpty)
            _empty(_f.any ? 'No raw materials match your filters.' : 'No raw materials yet.')
          else
            Padding(
              padding: const EdgeInsets.all(12),
              child: MobileCardList<Map>(
                items: pageSlice(rows, _rPage, _rSize),
                keyOf: (r) => tStr(r['poultryRawMaterialItemId']),
                primary: (r) => tStr(r['itemName']),
                secondaryBuilder: (r) => Align(alignment: Alignment.centerLeft, child: toneBadge(rawStockStatus(r))),
                details: (r) => [
                  ('Category', tStr(r['category']).isEmpty ? '—' : tStr(r['category'])),
                  ('Unit', tStr(r['unitOfMeasure']).isEmpty ? '—' : tStr(r['unitOfMeasure'])),
                  ('In stock', loc(tNum(r['currentQuantity']))),
                  ('Min alert', loc(tNum(r['minimumStockAlert']))),
                  ('Details', rawLink(r).label),
                ],
                detailTap: (r, label) => label == 'Details' ? () => _href(rawLink(r).href, rawLink(r).label) : null,
                pager: CompactPager(total: rows.length, page: _rPage, pageSize: _rSize, onPage: (x) => setState(() => _rPage = x), onPageSize: (s) => setState(() {
                      _rSize = s;
                      _rPage = 1;
                    })),
                table: (items) => TrackerTable(
                  columns: const [
                    TCol('Item', width: 130), TCol('Category', width: 120), TCol('Unit', width: 90), TCol('In stock', right: true, width: 100),
                    TCol('Min alert', right: true, width: 90), TCol('Status', width: 120), TCol('Details', width: 140),
                  ],
                  rows: [
                    for (final r in items)
                      [
                        cellText(tStr(r['itemName']), bold: true),
                        cellText(tStr(r['category']).isEmpty ? '—' : tStr(r['category'])),
                        cellText(tStr(r['unitOfMeasure']).isEmpty ? '—' : tStr(r['unitOfMeasure'])),
                        cellText(loc(tNum(r['currentQuantity'])), bold: true),
                        cellText(loc(tNum(r['minimumStockAlert'])), color: TColors.slate500),
                        Align(alignment: Alignment.centerLeft, child: toneBadge(rawStockStatus(r))),
                        InkWell(
                          onTap: () => _href(rawLink(r).href, rawLink(r).label),
                          child: Text(rawLink(r).label, style: const TextStyle(fontSize: 13, color: TColors.blue600)),
                        ),
                      ],
                  ],
                ),
              ),
            ),
        ]),
      );
}
