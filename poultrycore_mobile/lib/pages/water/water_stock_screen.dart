import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/expenses/deferred_costs_screen.dart' show qtyFmt;
import '../poultry/inventory/stock_dialogs.dart' show SetProductStockDialog, ReconcileProductStockDialog;
import '../poultry/money/money_widgets.dart';
import '../poultry/purchase/raw_material_dialogs.dart' show RecalculateStockDialog;
import '../poultry/reports/report_format.dart';
import '../poultry/reports/report_routes.dart' show openAppHref;
import '../poultry/sales/balances_logic.dart' show pageSlice;
import '../poultry/sales/balances_widgets.dart';
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull, SortState, toggleSort, sortRows;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/business_dates.dart';
import '../shared/company_clock.dart';

/// Water → Operations → Inventory → Stock movement (`app/water-stock/page.tsx`)
/// and Inventory (`app/water-inventory/page.tsx`), with the three stock tools
/// both pages carry: Recalculate stock, Recalculate product stock and Set
/// product stock (the app's shared dialogs on their Water setting).

/// Stock typed in by hand uses these types; everything else is system-generated.
const waterManualTxnTypes = ['Restock', 'Adjust', 'Return', 'Manual', 'Opening'];
bool isWaterManualTxn(Object? t) => waterManualTxnTypes.contains(tStr(t).trim());

/// filterByDateAndSearch on createdDate (product, type, note), then the source.
List<Map> filterWaterStockTxns(List<Map> rows, {String search = '', String from = '', String to = '', String source = 'all'}) {
  final q = search.trim().toLowerCase();
  return rows.where((t) {
    final day = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(tStr(t['createdDate']))?[1];
    if (day != null) {
      if (from.isNotEmpty && day.compareTo(from) < 0) return false;
      if (to.isNotEmpty && day.compareTo(to) > 0) return false;
    }
    if (q.isNotEmpty && !['productName', 'txnType', 'note'].any((k) => t[k] != null && '${t[k]}'.toLowerCase().contains(q))) return false;
    if (source == 'manual') return isWaterManualTxn(t['txnType']);
    if (source == 'system') return !isWaterManualTxn(t['txnType']);
    return true;
  }).toList();
}

/// "+5" / "-3" / "0".
String signedQty(num q) => q > 0 ? '+${qtyFmt(q)}' : qtyFmt(q);

/// The three stock tools, as toolbar buttons.
List<Widget> waterStockTools(BuildContext context, Session session, Company company,
        {required List<Map> rawItems, required List<Map> products, required Future<void> Function() onDone}) =>
    [
      OutlinedButton.icon(
        onPressed: () async {
          final ran = await showDialog<bool>(context: context, builder: (_) => RecalculateStockDialog(session: session, company: company, items: rawItems, water: true));
          if (ran == true) await onDone();
        },
        icon: const Icon(Icons.refresh, size: 16),
        label: const Text('Recalculate stock'),
      ),
      OutlinedButton.icon(
        onPressed: () async {
          final ran = await showDialog<bool>(context: context, builder: (_) => ReconcileProductStockDialog(session: session, company: company, products: products, water: true));
          if (ran == true) await onDone();
        },
        icon: const Icon(Icons.refresh, size: 16),
        label: const Text('Recalculate product stock'),
      ),
      OutlinedButton.icon(
        onPressed: () async {
          final ok = await showDialog<bool>(context: context, builder: (_) => SetProductStockDialog(session: session, company: company, products: products, water: true));
          if (ok == true) await onDone();
        },
        icon: const Icon(Icons.fact_check_outlined, size: 16),
        label: const Text('Set product stock'),
      ),
    ];

// ------------------------------------------------------------ stock movement

class WaterStockMovementScreen extends StatefulWidget {
  const WaterStockMovementScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<WaterStockMovementScreen> createState() => _WaterStockMovementScreenState();
}

class _WaterStockMovementScreenState extends State<WaterStockMovementScreen> {
  List<Map> _txns = [], _products = [], _rawItems = [];
  bool _loading = true;
  final _search = TextEditingController();
  String _from = '', _to = '', _source = 'all';
  int? _productId;
  SortState _sort = (key: null, dir: null);
  int _page = 1, _pageSize = 10, _lastTotal = -1;
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;

  @override
  void initState() {
    super.initState();
    CompanyClock.load(widget.session, widget.company).then((c) {
      if (mounted) setState(() => _offset = c.offset);
    });
    _load();
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
        _api.get('/api/Water/stock/transactions', query: {...q, if (_productId != null) 'productId': '$_productId'}),
        _api.get('/api/Water/products', query: q),
        _api.get('/api/Water/raw-material-items', query: q).catchError((_) => const <Map>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _txns = rowsOf(r[0]);
        _products = rowsOf(r[1]);
        _rawItems = rowsOf(r[2]);
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load stock', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  String _when(Map t) => fmtInstant(t['createdDate'], _offset);

  Widget _sourceBadge(Map t) => isWaterManualTxn(t['txnType'])
      ? const TBadge('Manual', bg: TColors.blue100, fg: Color(0xFF1D4ED8))
      : const TBadge('System', bg: Colors.white, fg: TColors.slate700, border: TColors.slate300);

  Future<void> _newEntry() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => WaterStockEntryDialog(session: widget.session, company: widget.company, products: _products, rawItems: _rawItems),
    );
    if (ok == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/water-stock');
    final visible = filterWaterStockTxns(_txns, search: _search.text, from: _from, to: _to, source: _source);
    final sorted = sortRows(visible, _sort, (Map t, String k) {
      if (k == 'createdDate') return tStr(t['createdDate']);
      if (k == 'quantity' || k == 'unitCost') return tNum(t[k]);
      return t[k];
    });
    if (sorted.length != _lastTotal) {
      _lastTotal = sorted.length;
      _page = 1;
    }
    final pageRows = pageSlice(sorted, _page, _pageSize);
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Stock movement')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            const Row(children: [
              Icon(Icons.inventory_2_outlined, color: Color(0xFF0284C7)),
              SizedBox(width: 8),
              Flexible(child: Text('Stock movement', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900))),
            ]),
            const SizedBox(height: 10),
            AppSelect<int>(
              value: _productId ?? 0,
              hintText: 'All products',
              items: [
                const AppSelectItem(value: 0, label: 'All products'),
                for (final p in _products) AppSelectItem(value: tIntOrNull(p['waterProductId']) ?? 0, label: tStr(p['name'])),
              ],
              onChanged: (v) {
                setState(() => _productId = v == null || v == 0 ? null : v);
                _load();
              },
            ),
            const SizedBox(height: 8),
            AppSelect<String>(
              value: _source,
              items: const [
                AppSelectItem(value: 'all', label: 'All entries'),
                AppSelectItem(value: 'manual', label: 'Manual only'),
                AppSelectItem(value: 'system', label: 'System only'),
              ],
              onChanged: (v) => setState(() => _source = v ?? 'all'),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ...waterStockTools(context, widget.session, widget.company, rawItems: _rawItems, products: _products, onDone: _load),
              FilledButton.icon(onPressed: _newEntry, icon: const Icon(Icons.add, size: 16), label: const Text('New entry')),
            ]),
            const SizedBox(height: 12),
            ListFiltersCard(
              search: _search,
              searchPlaceholder: 'Search product, type or note',
              onSearch: () => setState(() {}),
              from: _from,
              to: _to,
              onDates: (f, t) => setState(() {
                _from = f;
                _to = t;
              }),
              onClear: () => setState(() {
                _search.clear();
                _from = '';
                _to = '';
              }),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(padding: EdgeInsets.all(16), child: LoadingLine('Loading…'))
            else if (_txns.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
                child: const Text('No stock movement recorded yet.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate500)),
              )
            else
              MobileCardList<Map>(
                striped: true,
                items: pageRows,
                keyOf: (t) => tStr(t['stockTxnId']),
                primary: (t) => tStr(t['productName']),
                secondaryBuilder: (t) => Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('${_when(t)} · ${tStr(t['txnType'])} · '),
                  Text('${signedQty(tNum(t['quantity']))} qty',
                      style: TextStyle(fontWeight: FontWeight.w500, color: tNum(t['quantity']) < 0 ? const Color(0xFFE11D48) : TColors.emerald600)),
                ]),
                highlights: (t) => [
                  Highlight('Qty', signedQty(tNum(t['quantity'])), accent: tNum(t['quantity']) < 0 ? Accent.rose : Accent.emerald),
                  Highlight('Unit cost', t['unitCost'] == null ? '—' : tNum(t['unitCost']).toStringAsFixed(2), accent: Accent.blue),
                ],
                details: (t) => [
                  ('Date', _when(t)),
                  ('Type', tStr(t['txnType'])),
                  ('Source', isWaterManualTxn(t['txnType']) ? 'Manual' : 'System'),
                  ('Note', tStr(t['note']).isEmpty ? '—' : tStr(t['note'])),
                ],
                detailColor: (t, label) => label == 'Source' && isWaterManualTxn(t['txnType']) ? const Color(0xFF1D4ED8) : null,
                table: (items) => TrackerTable(
                  sort: _sort,
                  onSort: (k) => setState(() => _sort = toggleSort(k, _sort)),
                  columns: const [
                    TCol('Date', sortKey: 'createdDate', width: 150), TCol('Product', sortKey: 'productName', width: 140),
                    TCol('Type', sortKey: 'txnType', width: 120), TCol('Source', sortKey: 'txnType', width: 90),
                    TCol('Qty', sortKey: 'quantity', right: true, width: 80), TCol('Unit cost', sortKey: 'unitCost', right: true, width: 90),
                    TCol('Note', sortKey: 'note', width: 180),
                  ],
                  rows: [
                    for (final t in items)
                      [
                        cellText(_when(t)),
                        cellText(tStr(t['productName'])),
                        cellText(tStr(t['txnType'])),
                        Align(alignment: Alignment.centerLeft, child: _sourceBadge(t)),
                        Align(
                          alignment: Alignment.centerRight,
                          child: cellText(signedQty(tNum(t['quantity'])), color: tNum(t['quantity']) < 0 ? const Color(0xFFE11D48) : TColors.emerald600),
                        ),
                        Align(alignment: Alignment.centerRight, child: cellText(t['unitCost'] == null ? '—' : tNum(t['unitCost']).toStringAsFixed(2))),
                        cellText(tStr(t['note']).isEmpty ? '—' : tStr(t['note']), color: TColors.slate500),
                      ],
                  ],
                ),
                pager: CompactPager(
                  total: sorted.length,
                  page: _page,
                  pageSize: _pageSize,
                  onPage: (p) => setState(() => _page = p),
                  onPageSize: (v) => setState(() {
                    _pageSize = v;
                    _page = 1;
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// New stock entry: a finished product (a stock transaction) or a raw
/// material / supply (adjusted directly).
class WaterStockEntryDialog extends StatefulWidget {
  const WaterStockEntryDialog({super.key, required this.session, required this.company, required this.products, required this.rawItems});
  final Session session;
  final Company company;
  final List<Map> products, rawItems;

  @override
  State<WaterStockEntryDialog> createState() => _WaterStockEntryDialogState();
}

class _WaterStockEntryDialogState extends State<WaterStockEntryDialog> {
  String _target = '', _type = 'Restock';
  final _qty = TextEditingController(), _cost = TextEditingController(), _note = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_qty, _cost, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_target.isEmpty) return trackerToast(context, 'Pick an item', error: true);
    final q = int.tryParse(_qty.text) ?? 0;
    if (q == 0) return trackerToast(context, 'Quantity must be non-zero', error: true);
    // Adjust is signed; Restock and Return are units IN.
    final signed = _type == 'Adjust' ? q : q.abs();
    final parts = _target.split(':');
    final id = int.parse(parts[1]);
    final cost = _cost.text.isEmpty ? null : num.tryParse(_cost.text);
    setState(() => _saving = true);
    try {
      final api = widget.session.farmClient;
      if (parts[0] == 'r') {
        await api.post('/api/Water/raw-material-items/$id/adjust', body: {
          'quantity': signed,
          'unitCost': cost,
          'movementType': _type,
          'note': _note.text.isEmpty ? 'Manual stock adjustment' : _note.text,
          'farmId': widget.company.farmId,
          'createdBy': widget.session.tokens.userId,
        });
      } else {
        await api.post('/api/Water/stock/transactions', body: {
          'waterProductId': id,
          'txnType': _type,
          'quantity': signed,
          'unitCost': cost,
          'note': _note.text.isEmpty ? null : _note.text,
          'farmId': widget.company.farmId,
          'createdBy': widget.session.tokens.userId,
        });
      }
      if (!mounted) return;
      trackerToast(context, 'Stock updated');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Failed', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final raw = [for (final i in widget.rawItems) if (i['isActive'] == true) i];
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: const Row(children: [
          Icon(Icons.inventory_2_outlined, size: 20, color: Color(0xFF0284C7)),
          SizedBox(width: 8),
          Flexible(child: Text('New stock entry')),
        ]),
        content: SizedBox(
          width: 560,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Manually record a restock, adjustment, or return. Shows as a “Manual” entry on the list.',
                style: TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 12),
            formSection('Stock entry', const Color(0xFF0284C7), [
              FilterLabel(
                'Item *',
                AppSelect<String>(
                  value: _target.isEmpty ? null : _target,
                  hintText: 'Pick a finished product, raw material or supply…',
                  items: [
                    if (widget.products.isNotEmpty) ...[
                      const AppSelectItem(value: 'h:p', label: 'Finished products', enabled: false),
                      for (final p in widget.products) AppSelectItem(value: 'p:${tStr(p['waterProductId'])}', label: tStr(p['name'])),
                    ],
                    if (raw.isNotEmpty) ...[
                      const AppSelectItem(value: 'h:r', label: 'Raw materials & supplies', enabled: false),
                      for (final i in raw)
                        AppSelectItem(
                          value: 'r:${tStr(i['waterRawMaterialItemId'])}',
                          label: '${tStr(i['itemName'])}${tStr(i['category']).isNotEmpty ? ' — ${tStr(i['category'])}' : ''}',
                        ),
                    ],
                  ],
                  onChanged: (v) => setState(() => _target = v ?? ''),
                ),
              ),
              FilterLabel(
                'Type',
                AppSelect<String>(
                  value: _type,
                  items: const [
                    AppSelectItem(value: 'Restock', label: 'Restock (add stock)'),
                    AppSelectItem(value: 'Adjust', label: 'Adjust (signed)'),
                    AppSelectItem(value: 'Return', label: 'Return (add back)'),
                  ],
                  onChanged: (v) => setState(() => _type = v ?? 'Restock'),
                ),
              ),
              FilterLabel(
                'Quantity ${_type == 'Adjust' ? '(signed)' : ''}',
                AppInput(
                  controller: _qty,
                  keyboardType: const TextInputType.numberWithOptions(signed: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*'))],
                ),
              ),
              FilterLabel(
                'Unit cost (optional, for restocks)',
                AppInput(
                  controller: _cost,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                ),
              ),
              FilterLabel('Note', AppInput(controller: _note)),
            ]),
          ]),
        ),
        actions: [
          OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save entry')),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ inventory

/// Anything at or below this many units is "low stock" for a finished product;
/// raw materials use their own minimumStockAlert.
const waterLowStockFinished = 50;

/// (label, tone) for a finished product: tone is ok / low / out.
(String, String) waterProductStatus(Map p) {
  final s = tNum(p['stockOnHand']);
  if (s <= 0) return ('Out of stock', 'out');
  if (s <= waterLowStockFinished) return ('Low stock', 'low');
  return ('In stock', 'ok');
}

(String, String) waterRawStatus(Map r) {
  final s = tNum(r['currentQuantity']);
  final min = tNum(r['minimumStockAlert']);
  if (s <= 0) return ('Out of stock', 'out');
  if (min > 0 && s <= min) return ('Low stock', 'low');
  return ('In stock', 'ok');
}

Widget waterToneBadge((String, String) st) => switch (st.$2) {
      'out' => TBadge(st.$1, bg: const Color(0xFFFFE4E6), fg: const Color(0xFFBE123C)),
      'low' => TBadge(st.$1, bg: TColors.amber100, fg: TColors.amber700),
      _ => TBadge(st.$1, bg: TColors.emerald100, fg: TColors.emerald700),
    };

/// Sachet count: a sachet product (by flag or by unit "sachet") × sachets per bag.
num? waterSachetCount(Map p) {
  final isSachet = p['isSachetProduct'] == true || tStr(p['unit']).trim().toLowerCase() == 'sachet';
  return isSachet ? tNum(p['stockOnHand']) * (p['sachetsPerBag'] == null ? 30 : tNum(p['sachetsPerBag'])) : null;
}

class WaterInventoryScreen extends StatefulWidget {
  const WaterInventoryScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<WaterInventoryScreen> createState() => _WaterInventoryScreenState();
}

class _WaterInventoryScreenState extends State<WaterInventoryScreen> {
  List<Map> _products = [], _raw = [];
  bool _loading = true;
  final _q = TextEditingController();
  String _tab = 'products';
  int _pPage = 1, _pSize = 10, _rPage = 1, _rSize = 10;
  FarmMoney _gh = const FarmMoney();

  ApiClient get _api => widget.session.farmClient;

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _gh = m);
    });
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final q = {'farmId': widget.company.farmId};
    try {
      final r = await Future.wait([_api.get('/api/Water/products', query: q), _api.get('/api/Water/raw-material-items', query: q)]);
      if (!mounted) return;
      setState(() {
        _products = rowsOf(r[0]);
        _raw = rowsOf(r[1]);
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load inventory', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  bool _m(Object? s) => _q.text.isEmpty || tStr(s).toLowerCase().contains(_q.text.toLowerCase());

  void _href(String href, String label) => openAppHref(context, widget.session, widget.company, href, label: label);

  Widget _stat(String label, String value, IconData icon, Color bg, Color fg) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)), child: Icon(icon, size: 20, color: fg)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
              Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900)),
            ]),
          ),
        ]),
      );

  Widget _tabButton(String key, String label, IconData icon, int count) {
    final on = _tab == key;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tab = key),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(color: on ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(6)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 16, color: TColors.slate700),
            const SizedBox(width: 4),
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
            const SizedBox(width: 6),
            TBadge('$count', bg: TColors.slate200, fg: TColors.slate700),
          ]),
        ),
      ),
    );
  }

  Widget _panel(String intro, String manage, VoidCallback onManage, Widget body) => Container(
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(color: TColors.slate50, border: Border(bottom: BorderSide(color: TColors.slate200))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(intro, style: const TextStyle(fontSize: 13, color: TColors.slate600)),
              const SizedBox(height: 8),
              OutlinedButton.icon(onPressed: onManage, icon: const Icon(Icons.open_in_new, size: 16), label: Text(manage)),
            ]),
          ),
          body,
        ]),
      );

  Widget _empty(String t) => Padding(padding: const EdgeInsets.all(32), child: Text(t, textAlign: TextAlign.center, style: const TextStyle(color: TColors.slate500)));

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/water-inventory');
    final products = [for (final p in _products) if (_m(p['name']) || _m(p['sku']) || _m(p['unit'])) p];
    final raw = [for (final r in _raw) if (_m(r['itemName']) || _m(r['category']) || _m(r['unitOfMeasure'])) r];
    var low = 0, out = 0;
    for (final t in [for (final p in _products) waterProductStatus(p).$2, for (final r in _raw) waterRawStatus(r).$2]) {
      if (t == 'low') low++;
      if (t == 'out') out++;
    }
    String count(int n) => _loading ? '…' : '$n';
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Water inventory')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFFE0F2FE), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.inventory_2_outlined, color: Color(0xFF0369A1)),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Water inventory', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900)),
                  Text('Finished products and raw materials in one place.', style: TextStyle(fontSize: 13, color: TColors.slate600)),
                ]),
              ),
            ]),
            const SizedBox(height: 10),
            AppInput(
              controller: _q,
              hintText: 'Search by name, SKU, category…',
              prefixIcon: const Icon(Icons.search, size: 18, color: TColors.slate400),
              onChanged: (_) => setState(() {
                _pPage = 1;
                _rPage = 1;
              }),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: waterStockTools(context, widget.session, widget.company, rawItems: _raw, products: _products, onDone: _load)),
            const SizedBox(height: 12),
            twoUp([
              _stat('Total items', count(_products.length + _raw.length), Icons.inventory_2_outlined, const Color(0xFFE0F2FE), const Color(0xFF0369A1)),
              _stat('Low stock', count(low), Icons.warning_amber_rounded, TColors.amber100, TColors.amber700),
              _stat('Out of stock', count(out), Icons.error_outline, const Color(0xFFFFE4E6), const Color(0xFFBE123C)),
            ]),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: TColors.slate100, borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                _tabButton('products', 'Finished products', Icons.shopping_bag_outlined, products.length),
                _tabButton('raw', 'Raw materials', Icons.inbox_outlined, raw.length),
              ]),
            ),
            const SizedBox(height: 12),
            if (_tab == 'products')
              _panel(
                'Sachets, bottles, dispensers. Stock = SUM(WaterStockTransactions).',
                'Manage products',
                () => _href('/water-products', 'Products'),
                _loading
                    ? const Padding(padding: EdgeInsets.all(16), child: LoadingLine('Loading…'))
                    : products.isEmpty
                        ? _empty(_q.text.isNotEmpty ? 'No products match your search.' : 'No products yet.')
                        : MobileCardList<Map>(
                            striped: true,
                            items: pageSlice(products, _pPage, _pSize),
                            keyOf: (p) => tStr(p['waterProductId']),
                            primary: (p) => tStr(p['name']),
                            secondaryBuilder: (p) => Align(alignment: Alignment.centerLeft, child: waterToneBadge(waterProductStatus(p))),
                            highlights: (p) => [
                              Highlight('Unit price', _gh(tNum(p['unitPrice'])), accent: Accent.blue),
                              Highlight('Stock (Bags)', qtyFmt(p['stockOnHand']), accent: Accent.emerald),
                            ],
                            details: (p) => [
                              ('SKU', tStr(p['sku']).isEmpty ? '—' : tStr(p['sku'])),
                              ('Size', tNum(p['sizeMl']) != 0 ? '${tStr(p['sizeMl'])} ${tStr(p['sizeUnit']).isEmpty ? 'ml' : tStr(p['sizeUnit'])}' : '—'),
                              ('Unit', tStr(p['unit']).isEmpty ? '—' : tStr(p['unit'])),
                              ('Stock (Sachets)', waterSachetCount(p) == null ? '—' : qtyFmt(waterSachetCount(p))),
                            ],
                            table: (items) => TrackerTable(
                              columns: const [
                                TCol('Name', width: 140), TCol('SKU', width: 90), TCol('Size', width: 80), TCol('Unit', width: 70),
                                TCol('Unit price', right: true, width: 100), TCol('Stock (Bags)', right: true, width: 100),
                                TCol('Stock (Sachets)', right: true, width: 110), TCol('Status', width: 110), TCol('Track', right: true, width: 60),
                              ],
                              rows: [
                                for (final p in items)
                                  [
                                    cellText(tStr(p['name']), bold: true),
                                    cellText(tStr(p['sku']).isEmpty ? '—' : tStr(p['sku']), color: TColors.slate600),
                                    cellText(tNum(p['sizeMl']) != 0 ? '${tStr(p['sizeMl'])} ${tStr(p['sizeUnit']).isEmpty ? 'ml' : tStr(p['sizeUnit'])}' : '—'),
                                    cellText(tStr(p['unit']).isEmpty ? '—' : tStr(p['unit'])),
                                    Align(alignment: Alignment.centerRight, child: cellText(_gh(tNum(p['unitPrice'])))),
                                    Align(alignment: Alignment.centerRight, child: cellText(qtyFmt(p['stockOnHand']), bold: true)),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: cellText(waterSachetCount(p) == null ? '—' : qtyFmt(waterSachetCount(p)), color: TColors.slate600),
                                    ),
                                    Align(alignment: Alignment.centerLeft, child: waterToneBadge(waterProductStatus(p))),
                                    IconButton(
                                      tooltip: 'Track this product',
                                      onPressed: () => _href('/water-inventory-tracker?productId=${tStr(p['waterProductId'])}', 'Inventory tracker'),
                                      icon: const Icon(Icons.history, size: 18, color: Color(0xFF0369A1)),
                                    ),
                                  ],
                              ],
                            ),
                            pager: CompactPager(
                              total: products.length,
                              page: _pPage,
                              pageSize: _pSize,
                              onPage: (v) => setState(() => _pPage = v),
                              onPageSize: (v) => setState(() {
                                _pSize = v;
                                _pPage = 1;
                              }),
                            ),
                          ),
              )
            else
              _panel(
                'Sachet rolls, caps, labels. Stock updated by raw-material purchases + production usage.',
                'Manage raw materials',
                () => _href('/water-raw-materials', 'Raw materials & supplies'),
                _loading
                    ? const Padding(padding: EdgeInsets.all(16), child: LoadingLine('Loading…'))
                    : raw.isEmpty
                        ? _empty(_q.text.isNotEmpty ? 'No raw materials match your search.' : 'No raw materials yet.')
                        : MobileCardList<Map>(
                            striped: true,
                            items: pageSlice(raw, _rPage, _rSize),
                            keyOf: (r) => tStr(r['waterRawMaterialItemId']),
                            primary: (r) => tStr(r['itemName']),
                            secondaryBuilder: (r) => Align(alignment: Alignment.centerLeft, child: waterToneBadge(waterRawStatus(r))),
                            highlights: (r) => [
                              Highlight('Stock', qtyFmt(r['currentQuantity']), accent: Accent.emerald),
                              Highlight('Min alert', qtyFmt(r['minimumStockAlert']), accent: Accent.blue),
                            ],
                            details: (r) => [
                              ('Category', tStr(r['category']).isEmpty ? '—' : tStr(r['category'])),
                              ('Unit', tStr(r['unitOfMeasure']).isEmpty ? '—' : tStr(r['unitOfMeasure'])),
                            ],
                            table: (items) => TrackerTable(
                              columns: const [
                                TCol('Item', width: 150), TCol('Category', width: 120), TCol('Unit', width: 80),
                                TCol('Stock', right: true, width: 90), TCol('Min alert', right: true, width: 90), TCol('Status', width: 110),
                              ],
                              rows: [
                                for (final r in items)
                                  [
                                    cellText(tStr(r['itemName']), bold: true),
                                    cellText(tStr(r['category']).isEmpty ? '—' : tStr(r['category'])),
                                    cellText(tStr(r['unitOfMeasure']).isEmpty ? '—' : tStr(r['unitOfMeasure'])),
                                    Align(alignment: Alignment.centerRight, child: cellText(qtyFmt(r['currentQuantity']), bold: true)),
                                    Align(alignment: Alignment.centerRight, child: cellText(qtyFmt(r['minimumStockAlert']), color: TColors.slate500)),
                                    Align(alignment: Alignment.centerLeft, child: waterToneBadge(waterRawStatus(r))),
                                  ],
                              ],
                            ),
                            pager: CompactPager(
                              total: raw.length,
                              page: _rPage,
                              pageSize: _rSize,
                              onPage: (v) => setState(() => _rPage = v),
                              onPageSize: (v) => setState(() {
                                _rSize = v;
                                _rPage = 1;
                              }),
                            ),
                          ),
              ),
          ],
        ),
      ),
    );
  }
}
