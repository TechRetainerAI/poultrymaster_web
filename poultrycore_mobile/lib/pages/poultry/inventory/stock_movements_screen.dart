// Poultry → Operations → Inventory & Health → Stock movements
// (app/poultry-stock/page.tsx): every stock increase and decrease — finished
// products and raw materials — with the three stock tools, Export PDF / CSV,
// New movement, the filters, and the phone card list (its `md:hidden` layout).

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../shared/business_dates.dart';
import '../../shared/company_clock.dart';
import '../delivery/delivery_dialogs.dart' show NumBox;
import '../money/money_widgets.dart' show formSection;
import '../purchase/raw_material_dialogs.dart' show RecalculateStockDialog;
import '../purchase/raw_materials_screen.dart' show FieldCard;
import '../reports/report_export.dart';
import '../reports/report_format.dart';
import '../sales/balances_logic.dart' show pageSlice;
import '../sales/balances_widgets.dart' show CompactPager, ListFiltersCard;
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull, loc;
import '../trackers/tracker_widgets.dart';
import 'stock_dialogs.dart';

/// MOVEMENTS: what a manual entry can be, and which way it moves stock.
const stockMovements = [('Increase', 1), ('Adjustment', 1), ('Decrease', -1), ('Damage/Loss', -1)];

(Color, Color) moveTone(String m) => switch (m) {
      'Increase' || 'Restock' => (TColors.green100, TColors.green700),
      'Production' => (TColors.emerald100, TColors.emerald700),
      'Adjustment' || 'Adjust' => (TColors.slate100, TColors.slate700),
      'Decrease' || 'Return' || 'Delivery Return' => (TColors.amber100, TColors.amber700),
      'Sale' => (TColors.blue100, const Color(0xFF1D4ED8)),
      'Damage/Loss' => (TColors.red100, TColors.red700),
      'Delivery Load' => (const Color(0xFFE0E7FF), const Color(0xFF4338CA)),
      _ => (const Color(0xFFF3F4F6), TColors.slate800),
    };

String stockSourceFor(String txnType) => switch (txnType) {
      'Production' => 'Production Record',
      'Sale' => 'Sale',
      'Restock' || 'Increase' => 'Manual / Product Stock Entry',
      _ => 'Stock Page',
    };

num _r2(num v) => double.parse(v.toStringAsFixed(2));

/// Every movement, newest first: product transactions, raw-material
/// purchases, production usage and manual adjustments.
List<Map<String, Object?>> buildStockMoves(List<Map> txns, List<Map> purchases, List<Map> usage, List<Map> adjustments) {
  final out = <Map<String, Object?>>[
    for (final t in txns)
      {
        'key': 'pt${t['poultryStockTransactionId']}',
        'date': tStr(t['createdDate']),
        'item': tStr(t['productName']),
        'parentType': 'Finished Product',
        'movementType': tStr(t['txnType']),
        'qty': tNum(t['quantity']),
        'unitCost': t['unitCost'] == null ? null : tNum(t['unitCost']),
        'total': t['unitCost'] == null ? null : _r2(tNum(t['unitCost']) * tNum(t['quantity']).abs()),
        'source': stockSourceFor(tStr(t['txnType'])),
        'note': t['note'] == null ? null : tStr(t['note']),
      },
    for (final p in purchases)
      {
        'key': 'rp${p['poultryRawMaterialPurchaseId']}',
        'date': tStr(p['purchaseDate']),
        'item': tStr(p['itemName']),
        'parentType': 'Raw Material',
        'movementType': 'Increase',
        'qty': tNum(p['quantity']),
        'unitCost': p['unitCost'] == null ? null : tNum(p['unitCost']),
        'total': p['totalCost'] == null ? null : tNum(p['totalCost']),
        'source': 'Raw Material Purchase',
        'note': p['notes'] == null ? null : tStr(p['notes']),
      },
    for (final u in usage)
      {
        'key': 'ru${u['poultryRawMaterialUsageId']}',
        'date': tStr(u['usedDate']),
        'item': tStr(u['itemName']),
        'parentType': 'Raw Material',
        'movementType': 'Decrease',
        'qty': -tNum(u['quantityUsed']).abs(),
        'unitCost': null,
        'total': null,
        'source': 'Production Usage',
        'note': u['varianceReason'] == null ? null : tStr(u['varianceReason']),
      },
    for (final a in adjustments)
      {
        'key': 'ra${a['poultryRawMaterialAdjustmentId']}',
        'date': tStr(a['adjustedDate']),
        'item': tStr(a['itemName']),
        'parentType': tStr(a['category']) == 'Supplies' ? 'Supplies' : 'Raw Material',
        'movementType': tStr(a['movementType']).isNotEmpty ? tStr(a['movementType']) : (tNum(a['quantity']) >= 0 ? 'Increase' : 'Decrease'),
        'qty': tNum(a['quantity']),
        'unitCost': a['unitCost'] == null ? null : tNum(a['unitCost']),
        'total': a['unitCost'] == null ? null : _r2(tNum(a['unitCost']) * tNum(a['quantity']).abs()),
        'source': 'Manual Adjustment',
        'note': a['note'] == null ? null : tStr(a['note']),
      },
  ];
  out.sort((a, b) => tStr(b['date']).compareTo(tStr(a['date'])));
  return out;
}

class StockMoveFilters {
  String search = '', from = '', to = '', item = 'all', parentType = 'all', movement = 'all';
}

List<Map<String, Object?>> filterStockMoves(List<Map<String, Object?>> moves, StockMoveFilters f) {
  final s = f.search.trim().toLowerCase();
  return [
    for (final m in moves)
      if ((() {
        final day = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(tStr(m['date']))?[1];
        if (day != null) {
          if (f.from.isNotEmpty && day.compareTo(f.from) < 0) return false;
          if (f.to.isNotEmpty && day.compareTo(f.to) > 0) return false;
        }
        if (s.isNotEmpty && !['item', 'source', 'note'].any((k) => m[k] != null && tStr(m[k]).toLowerCase().contains(s))) return false;
        if (f.item != 'all' && m['item'] != f.item) return false;
        if (f.parentType != 'all' && m['parentType'] != f.parentType) return false;
        if (f.movement != 'all' && m['movementType'] != f.movement) return false;
        return true;
      })())
        m,
  ];
}

String _signed(num q) => '${q > 0 ? '+' : ''}${loc(q)}';

class StockMovementsScreen extends StatefulWidget {
  const StockMovementsScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;
  @override
  State<StockMovementsScreen> createState() => _StockMovementsScreenState();
}

class _StockMovementsScreenState extends State<StockMovementsScreen> {
  List<Map> _products = [], _rawItems = [];
  List<Map<String, Object?>> _moves = [];
  bool _loading = true;
  final _search = TextEditingController();
  final _f = StockMoveFilters();
  int _page = 1, _size = 10;
  FarmMoney _fmt = const FarmMoney();
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;
  Map<String, String> get _farm => {'farmId': widget.company.farmId};

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _fmt = m);
    });
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
    Future<List<Map>> soft(String path) => _api.get(path, query: _farm).then(rowsOf).catchError((_) => <Map>[]);
    try {
      final r = await Future.wait([
        _api.get('/api/Poultry/products', query: _farm).then(rowsOf),
        soft('/api/Poultry/raw-material-items'),
        _api.get('/api/Poultry/stock/transactions', query: _farm).then(rowsOf),
        soft('/api/Poultry/raw-material-purchases'),
        soft('/api/Poultry/raw-material-usage/history'),
        soft('/api/Poultry/raw-material-adjustments'),
      ]);
      if (!mounted) return;
      setState(() {
        _products = r[0];
        _rawItems = r[1];
        _moves = buildStockMoves(r[2], r[3], r[4], r[5]);
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load stock', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  List<String> _options(String key) => {for (final m in _moves) if (tStr(m[key]).isNotEmpty) tStr(m[key])}.toList()..sort();

  ReportDocument _doc(List<Map<String, Object?>> rows) {
    final totalIn = rows.fold<num>(0, (s, m) => s + (tNum(m['qty']) > 0 ? tNum(m['qty']) : 0));
    final totalOut = rows.fold<num>(0, (s, m) => s + (tNum(m['qty']) < 0 ? -tNum(m['qty']) : 0));
    return ReportDocument(
      title: 'Stock Movements',
      filename: 'poultry-stock-movements',
      farmName: widget.company.name,
      landscape: true,
      fromDate: _f.from.isEmpty ? null : _f.from,
      toDate: _f.to.isEmpty ? null : _f.to,
      currencyLabel: _fmt.code,
      recordLabel: 'stock movements',
      filters: _filtersUsed(),
      sections: [
        ReportSection(
          columns: const [
            ReportColumn('Date'), ReportColumn('Item'), ReportColumn('Parent Type'), ReportColumn('Movement'), ReportColumn('Qty', right: true),
            ReportColumn('Unit Price', right: true), ReportColumn('Total Value', right: true), ReportColumn('Source'), ReportColumn('Note'),
          ],
          rows: _exportRows(rows),
        ),
      ],
      notes: ['Movements: ${loc(rows.length)}', 'Total in: +${loc(totalIn)}', 'Total out: -${loc(totalOut)}'],
    );
  }

  List<(String, String)> _filtersUsed() => [
        if (_f.item != 'all') ('Item', _f.item),
        if (_f.parentType != 'all') ('Parent type', _f.parentType),
        if (_f.movement != 'all') ('Movement', _f.movement),
        if (_f.search.trim().isNotEmpty) ('Search', _f.search.trim()),
      ];

  List<List<String>> _exportRows(List<Map<String, Object?>> rows) => [
        for (final m in rows)
          [
            tStr(m['date']).split('T').first,
            tStr(m['item']),
            tStr(m['parentType']),
            tStr(m['movementType']),
            _signed(tNum(m['qty'])),
            m['unitCost'] != null ? _fmt(tNum(m['unitCost'])) : '—',
            m['total'] != null ? _fmt(tNum(m['total'])) : '—',
            tStr(m['source']),
            m['note'] != null ? tStr(m['note']) : '—',
          ],
      ];

  Future<void> _exportPdf(List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) {
      trackerToast(context, 'Nothing to export', description: 'No stock movements match the current filters.', error: true);
      return;
    }
    try {
      await ReportExport.sharePdf(_doc(rows));
    } catch (_) {
      if (mounted) trackerToast(context, 'PDF export failed', description: 'Could not generate the PDF. Please try again.', error: true);
    }
  }

  Future<void> _exportCsv(List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) {
      trackerToast(context, 'Nothing to export', description: 'No stock movements match the current filters.', error: true);
      return;
    }
    String esc(Object? v) => '"${tStr(v).replaceAll('"', '""')}"';
    const headers = ['Date', 'Item', 'Parent Type', 'Movement', 'Qty', 'Unit Price', 'Total Value', 'Source', 'Note'];
    final lines = [
      headers.map(esc).join(','),
      for (final r in _exportRows(rows)) r.map(esc).join(','),
      '',
      [esc('Movements'), esc(rows.length)].join(','),
      for (final (l, v) in _filtersUsed()) [esc(l), esc(v)].join(','),
      if (_f.from.isNotEmpty || _f.to.isNotEmpty)
        [esc('Period'), esc('${_f.from.isEmpty ? 'start' : _f.from} to ${_f.to.isEmpty ? 'today' : _f.to}')].join(','),
    ];
    await ReportExport.sharer('poultry-stock-movements-${DateTime.now().toUtc().toIso8601String().substring(0, 10)}.csv',
        [0xEF, 0xBB, 0xBF, ...utf8.encode(lines.join('\n'))], 'text/csv', 'Stock Movements');
  }

  Future<void> _tool(Widget dialog) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => dialog);
    if (ok == true) await _load();
  }

  Future<void> _newMovement() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => NewStockMovementDialog(session: widget.session, company: widget.company, products: _products, rawItems: _rawItems),
    );
    if (ok == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-stock');
    final rows = filterStockMoves(_moves, _f);

    Widget toolbar(String label, IconData icon, VoidCallback? onTap, {bool primary = false}) => primary
        ? FilledButton.icon(onPressed: onTap, icon: Icon(icon, size: 16), label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis))
        : OutlinedButton.icon(onPressed: onTap, icon: Icon(icon, size: 16), label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis));

    Widget select(String value, String all, List<String> opts, ValueChanged<String> on) => AppSelect<String>(
          value: value,
          hintText: all,
          items: [AppSelectItem(value: 'all', label: all), for (final o in opts) AppSelectItem(value: o, label: o)],
          onChanged: (v) => setState(() {
            on(v ?? 'all');
            _page = 1;
          }),
        );

    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Stock Movements')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            const Text('Stock Movements', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: TColors.slate900)),
            const Text(
              'All stock increases and decreases — finished products and raw materials. Production, sales, purchases and manual entries.',
              style: TextStyle(fontSize: 13, color: TColors.slate500),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(builder: (context, c) {
              final w = (c.maxWidth - 8) / 2;
              return Wrap(spacing: 8, runSpacing: 8, children: [
                SizedBox(
                    width: w,
                    child: toolbar('Recalculate stock', Icons.refresh,
                        () => _tool(RecalculateStockDialog(session: widget.session, company: widget.company, items: _rawItems)))),
                SizedBox(
                    width: w,
                    child: toolbar('Recalculate product stock', Icons.refresh,
                        () => _tool(ReconcileProductStockDialog(session: widget.session, company: widget.company, products: _products)))),
                SizedBox(
                    width: w,
                    child: toolbar('Set product stock', Icons.fact_check_outlined,
                        () => _tool(SetProductStockDialog(session: widget.session, company: widget.company, products: _products)))),
                SizedBox(width: w, child: toolbar('Export PDF', Icons.download, _loading ? null : () => _exportPdf(rows))),
                SizedBox(width: w, child: toolbar('Export CSV', Icons.download, _loading ? null : () => _exportCsv(rows))),
                SizedBox(width: w, child: toolbar('New movement', Icons.add, _newMovement, primary: true)),
              ]);
            }),
            const SizedBox(height: 14),
            TCard(
              child: _loading
                  ? const Padding(padding: EdgeInsets.all(24), child: Text('Loading…', style: TextStyle(color: TColors.slate500)))
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      ListFiltersCard(
                        search: _search,
                        searchPlaceholder: 'Search item, source or note',
                        onSearch: () => setState(() {
                          _f.search = _search.text;
                          _page = 1;
                        }),
                        from: _f.from,
                        to: _f.to,
                        onDates: (a, b) => setState(() {
                          _f
                            ..from = a
                            ..to = b;
                          _page = 1;
                        }),
                        onClear: () => setState(() {
                          _search.clear();
                          _f
                            ..search = ''
                            ..from = ''
                            ..to = '';
                        }),
                        extras: [
                          select(_f.item, 'All items', _options('item'), (v) => _f.item = v),
                          select(_f.parentType, 'All types', _options('parentType'), (v) => _f.parentType = v),
                          select(_f.movement, 'All movements', _options('movementType'), (v) => _f.movement = v),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (rows.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text('No stock movements yet.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate500)),
                        )
                      else
                        for (final m in pageSlice(rows, _page, _size))
                          FieldCard(
                            title: tStr(m['item']),
                            badge: Builder(builder: (_) {
                              final (bg, fg) = moveTone(tStr(m['movementType']));
                              return TBadge(tStr(m['movementType']), bg: bg, fg: fg);
                            }),
                            fields: [
                              ('Date', fmtDateTime(m['date'], m, _offset), null),
                              ('Type', tStr(m['parentType']), null),
                              ('Qty', _signed(tNum(m['qty'])), tNum(m['qty']) < 0 ? TColors.red600 : TColors.green700),
                              ('Unit price', m['unitCost'] != null ? _fmt(tNum(m['unitCost'])) : '—', null),
                              ('Total', m['total'] != null ? _fmt(tNum(m['total'])) : '—', null),
                              ('Source', tStr(m['source']), null),
                            ],
                            actions: const [],
                          ),
                      CompactPager(total: rows.length, page: _page, pageSize: _size, onPage: (x) => setState(() => _page = x), onPageSize: (s) => setState(() {
                            _size = s;
                            _page = 1;
                          })),
                    ]),
            ),
          ],
        ),
      ),
    );
  }
}

class NewStockMovementDialog extends StatefulWidget {
  const NewStockMovementDialog({super.key, required this.session, required this.company, required this.products, required this.rawItems});
  final Session session;
  final Company company;
  final List<Map> products, rawItems;
  @override
  State<NewStockMovementDialog> createState() => _NewStockMovementDialogState();
}

class _NewStockMovementDialogState extends State<NewStockMovementDialog> {
  String _target = '', _movement = 'Increase', _note = '';
  num _qty = 0, _unitCost = 0;
  bool _saving = false;

  Future<void> _save() async {
    if (_target.isEmpty) {
      trackerToast(context, 'Pick an item', error: true);
      return;
    }
    if (_qty <= 0) {
      trackerToast(context, 'Quantity must be greater than 0', error: true);
      return;
    }
    final sign = stockMovements.firstWhere((m) => m.$1 == _movement).$2;
    final signed = sign * _qty.abs();
    final kind = _target.split(':').first, id = int.parse(_target.split(':').last);
    setState(() => _saving = true);
    try {
      if (kind == 'r') {
        await widget.session.farmClient.post('/api/Poultry/raw-material-items/$id/adjust', body: {
          'quantity': signed,
          'unitCost': _unitCost == 0 ? null : _unitCost,
          'movementType': _movement,
          'note': _note.isEmpty ? 'Manual stock adjustment' : _note,
          'farmId': widget.company.farmId,
          'createdBy': widget.session.tokens.userId ?? '',
        });
      } else {
        await widget.session.farmClient.post('/api/Poultry/stock/transactions', body: {
          'poultryProductId': id,
          'txnType': _movement,
          'quantity': signed,
          'unitCost': _unitCost == 0 ? null : _unitCost,
          'note': _note.isEmpty ? 'Manual stock entry' : _note,
          'farmId': widget.company.farmId,
        });
      }
      if (!mounted) return;
      trackerToast(context, 'Stock movement added');
      Navigator.pop(context, true);
      return;
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Save failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final products = [for (final p in widget.products) if (p['isActive'] == true) p];
    final raw = [for (final i in widget.rawItems) if (i['isActive'] == true) i];
    Widget cell(String label, Widget child, {String? hint}) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate700)),
            const SizedBox(height: 6),
            child,
            if (hint != null) ...[const SizedBox(height: 4), Text(hint, style: const TextStyle(fontSize: 12, color: TColors.slate500))],
          ]),
        );
    return AlertDialog(
      scrollable: true,
      title: const Text('New stock movement'),
      content: SizedBox(
        width: 440,
        child: formSection('Movement', const Color(0xFF2563EB), [
          cell(
            'Item *',
            AppSelect<String>(
              value: _target.isEmpty ? null : _target,
              hintText: 'Pick a finished product, raw material or supply',
              items: [
                if (products.isNotEmpty) ...[
                  const AppSelectItem(value: '__p', label: 'Finished products', enabled: false),
                  for (final p in products) AppSelectItem(value: 'p:${tIntOrNull(p['poultryProductId'])}', label: tStr(p['name'])),
                ],
                if (raw.isNotEmpty) ...[
                  const AppSelectItem(value: '__r', label: 'Raw materials & supplies', enabled: false),
                  for (final i in raw)
                    AppSelectItem(
                      value: 'r:${tIntOrNull(i['poultryRawMaterialItemId'])}',
                      label: '${tStr(i['itemName'])}${tStr(i['category']).isNotEmpty ? ' — ${tStr(i['category'])}' : ''}',
                    ),
                ],
              ],
              onChanged: (v) => setState(() => _target = v ?? ''),
            ),
          ),
          cell(
            'Movement type',
            AppSelect<String>(
              value: _movement,
              items: [for (final (m, _) in stockMovements) AppSelectItem(value: m, label: m)],
              onChanged: (v) => setState(() => _movement = v ?? _movement),
            ),
          ),
          cell('Quantity', NumBox(value: _qty, decimal: true, onChanged: (v) => _qty = v),
              hint: 'Always enter a positive number; the movement type sets the direction.'),
          cell('Unit cost / value', NumBox(value: _unitCost, decimal: true, onChanged: (v) => _unitCost = v)),
          cell('Note', AppInput(initialValue: _note, onChanged: (v) => _note = v)),
        ]),
      ),
      actions: [
        OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save')),
      ],
    );
  }
}
