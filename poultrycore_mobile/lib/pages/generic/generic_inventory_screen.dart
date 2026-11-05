// Generic → Catalog → Inventory, as `app/generic-inventory/page.tsx`: stock on
// hand for every product, read-only. Changes go through Stock adjustments.

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/money/money_widgets.dart';
import '../poultry/reports/report_format.dart' show FarmMoney;
import '../poultry/reports/report_routes.dart' show openAppHref;
import '../poultry/sales/balances_widgets.dart';
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart';
import 'generic_kit.dart';
import 'package:poultrycore_mobile/design/tone.dart';
import 'generic_products_screen.dart' show genericEmptyCard, genericQty;

/// The row's status: "na" (not tracked), "out", "low" or "ok".
String genericStockStatus(Map p) {
  if (p['trackInventory'] != true) return 'na';
  final stock = tNum(p['currentStock']), min = tNum(p['minimumStockAlert']);
  if (stock <= 0) return 'out';
  if (min > 0 && stock <= min) return 'low';
  return 'ok';
}

/// The status filter's value: "Not tracked" counts as in stock.
String _statusKey(Map p) => genericStockStatus(p) == 'na' ? 'ok' : genericStockStatus(p);

Widget _toneBadge(Map p) {
  final (label, bg, fg) = switch (genericStockStatus(p)) {
    'na' => ('Not tracked', TColors.emerald100, TColors.emerald700),
    'out' => ('Out of stock', TColors.rose100, TColors.rose700),
    'low' => ('Low stock', TColors.amber100, TColors.amber700),
    _ => ('In stock', TColors.emerald100, TColors.emerald700),
  };
  return TBadge(label, bg: bg, fg: fg);
}

/// The page's filters: search (name, SKU, barcode, category), category, status.
List<Map> filterGenericInventory(List<Map> rows, {String search = '', String category = 'all', String status = 'all'}) {
  final q = search.trim().toLowerCase();
  return rows.where((p) {
    if (q.isNotEmpty && !['productName', 'sku', 'barcode', 'categoryName'].any((k) => tStr(p[k]).toLowerCase().contains(q))) return false;
    if (category != 'all' && tStr(p['categoryName']) != category) return false;
    if (status != 'all' && _statusKey(p) != status) return false;
    return true;
  }).toList();
}

class GenericInventoryScreen extends StatefulWidget {
  const GenericInventoryScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<GenericInventoryScreen> createState() => _GenericInventoryScreenState();
}

class _GenericInventoryScreenState extends State<GenericInventoryScreen> {
  List<Map> _rows = [];
  bool _loading = true;
  String? _error;
  final _search = TextEditingController();
  String _category = 'all', _status = 'all';
  FarmMoney _fmt = const FarmMoney();

  ApiClient get _api => widget.session.farmClient;

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
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = rowsOf(await _api.get('${genericBase(widget.company)}/products'));
      if (mounted) setState(() => _rows = r);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _open(String href, String label) => openAppHref(context, widget.session, widget.company, href, label: label);

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/generic-inventory');
    final tracked = _rows.where((p) => p['trackInventory'] == true);
    final low = tracked.where((p) => genericStockStatus(p) == 'low').length;
    final out = tracked.where((p) => genericStockStatus(p) == 'out').length;
    final value = tracked.fold<num>(0, (s, p) => s + tNum(p['currentStock']) * tNum(p['costPrice']));
    final categories = {for (final p in _rows) if (tStr(p['categoryName']).isNotEmpty) tStr(p['categoryName'])}.toList()..sort();
    final visible = filterGenericInventory(_rows, search: _search.text, category: _category, status: _status);
    // StatCard: a tinted icon, the label, the figure ("…" while loading).
    Widget stat(String label, String v, IconData icon, Color bg, Color fg) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Tone.bg(0xFFFFFFFF), border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 20, color: fg),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                Text(_loading ? '…' : v,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: TColors.slate900)),
              ]),
            ),
          ]),
        );

    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Inventory')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            const Row(children: [
              Icon(Icons.inventory_2_outlined, size: 24, color: genericIndigo),
              SizedBox(width: 8),
              Expanded(child: Text('Inventory', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900))),
            ]),
            const Text('Stock-on-hand for every tracked product. Adjustments via Stock Adjustments page.',
                style: TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: () => _open('/generic-stock-adjustments', 'Stock adjustments'), child: const Text('Stock adjustments')),
            const SizedBox(height: 14),
            twoUp([
              stat('Total products', '${_rows.length}', Icons.inventory_2_outlined, const Tone(0xFFE0E7FF), const Tone(0xFF4338CA)),
              stat('Low stock', '$low', Icons.warning_amber_rounded, TColors.amber100, TColors.amber700),
              stat('Out of stock', '$out', Icons.error_outline, TColors.rose100, TColors.rose700),
              stat('Stock value (cost)', _fmt(value), Icons.inventory_2_outlined, TColors.emerald100, TColors.emerald700),
            ]),
            const SizedBox(height: 14),
            ListFiltersCard(
              search: _search,
              searchPlaceholder: 'Search by name, SKU, barcode, category…',
              searchOnly: true,
              onSearch: () => setState(() {}),
              from: '',
              to: '',
              onDates: (_, _) {},
              onClear: () => setState(_search.clear),
              extras: [
                AppSelect<String>(
                  value: _category,
                  items: [
                    const AppSelectItem(value: 'all', label: 'All categories'),
                    for (final c in categories) AppSelectItem(value: c, label: c),
                  ],
                  onChanged: (v) => setState(() => _category = v ?? 'all'),
                ),
                AppSelect<String>(
                  value: _status,
                  items: const [
                    AppSelectItem(value: 'all', label: 'All status'),
                    AppSelectItem(value: 'ok', label: 'In stock'),
                    AppSelectItem(value: 'low', label: 'Low stock'),
                    AppSelectItem(value: 'out', label: 'Out of stock'),
                  ],
                  onChanged: (v) => setState(() => _status = v ?? 'all'),
                ),
                if (_category != 'all' || _status != 'all')
                  TextButton(
                    onPressed: () => setState(() {
                      _category = 'all';
                      _status = 'all';
                    }),
                    child: const Text('Reset extras'),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: TColors.rose50, border: Border.all(color: TColors.rose200), borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Icons.error_outline, size: 16, color: TColors.rose700),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: const TextStyle(fontSize: 13, color: TColors.rose700))),
                ]),
              ),
            if (_error != null) const SizedBox(height: 14),
            if (_loading)
              const LoadingLine('Loading…')
            else if (visible.isEmpty)
              genericEmptyCard(
                '',
                child: _rows.isEmpty
                    ? Wrap(alignment: WrapAlignment.center, children: [
                        const Text('No products yet. ', style: TextStyle(color: TColors.slate500)),
                        InkWell(
                          onTap: () => _open('/generic-products', 'Products'),
                          child: const Text('Add your first product', style: TextStyle(color: genericIndigo, decoration: TextDecoration.underline)),
                        ),
                        const Text('.', style: TextStyle(color: TColors.slate500)),
                      ])
                    : const Text('No products match your filters.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate500)),
              )
            else
              MobileCardList<Map>(
                items: visible,
                keyOf: (p) => '${tIntOrNull(p['genericProductId'])}',
                primary: (p) => tStr(p['productName']),
                secondary: (p) => [tStr(p['sku']), tStr(p['categoryName'])].where((x) => x.isNotEmpty).join(' · '),
                trailing: (p) => Padding(padding: const EdgeInsets.only(left: 6), child: _toneBadge(p)),
                details: (p) {
                  final t = p['trackInventory'] == true;
                  return [
                    ('SKU', tStr(p['sku']).isEmpty ? '—' : tStr(p['sku'])),
                    ('Category', tStr(p['categoryName']).isEmpty ? '—' : tStr(p['categoryName'])),
                    ('Unit', tStr(p['unitOfMeasure']).isEmpty ? '—' : tStr(p['unitOfMeasure'])),
                    ('Cost', _fmt(tNum(p['costPrice']))),
                    ('Selling', _fmt(tNum(p['sellingPrice']))),
                    ('Stock', t ? genericQty(p['currentStock']) : 'n/a'),
                    ('Min alert', t ? genericQty(p['minimumStockAlert']) : '—'),
                  ];
                },
                table: (items) => TrackerTable(
                  columns: const [
                    TCol('Product', width: 170), TCol('SKU', width: 100), TCol('Category', width: 120), TCol('Unit', width: 80),
                    TCol('Cost', right: true, width: 110), TCol('Selling', right: true, width: 110), TCol('Stock', right: true, width: 90),
                    TCol('Min alert', right: true, width: 90), TCol('Status', width: 110),
                  ],
                  rows: [
                    for (final p in items)
                      [
                        Text(tStr(p['productName']), style: const TextStyle(fontWeight: FontWeight.w500)),
                        cellText(tStr(p['sku']).isEmpty ? '—' : tStr(p['sku'])),
                        cellText(tStr(p['categoryName']).isEmpty ? '—' : tStr(p['categoryName'])),
                        cellText(tStr(p['unitOfMeasure']).isEmpty ? '—' : tStr(p['unitOfMeasure'])),
                        Align(alignment: Alignment.centerRight, child: Text(_fmt(tNum(p['costPrice'])))),
                        Align(alignment: Alignment.centerRight, child: Text(_fmt(tNum(p['sellingPrice'])))),
                        Align(alignment: Alignment.centerRight, child: Text(p['trackInventory'] == true ? genericQty(p['currentStock']) : 'n/a')),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(p['trackInventory'] == true ? genericQty(p['minimumStockAlert']) : '—'),
                        ),
                        Align(alignment: Alignment.centerLeft, child: _toneBadge(p)),
                      ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
