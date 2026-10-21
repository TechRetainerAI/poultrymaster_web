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
import '../../shared/reason_select.dart' show stockReversalReasons;
import '../reports/report_export.dart';
import '../reports/report_format.dart';
import '../sales/balances_logic.dart' show pageSlice;
import '../sales/balances_widgets.dart' show CompactPager, ListFiltersCard;
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull, loc;
import '../trackers/tracker_widgets.dart';
import '../sales/credit_widgets.dart' show showReverseWithReason;
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
      'Bird Adjustment' => (const Color(0xFFEDE9FE), const Color(0xFF6D28D9)),
      'Sale Reversal' => (const Color(0xFFE0F2FE), TColors.sky800),
      'Bird Sale' => (TColors.blue100, const Color(0xFF1D4ED8)),
      'Sorting In' => (const Color(0xFFCCFBF1), const Color(0xFF115E59)),
      'Sorting Out' => (const Color(0xFFFFEDD5), const Color(0xFF9A3412)),
      'Egg Loss' => (TColors.red100, TColors.red700),
      'Internal Use' => (TColors.amber100, TColors.amber800),
      // 372: byproduct stock (Broken Eggs / Dead Birds); 373: manual movements.
      'Broken Egg Prod' || 'Mortality In' || 'Sorting Breakage' || 'Breakage In' || 'Hist Mortality In' =>
        (TColors.rose100, TColors.rose800),
      'Broken Egg Disposal' || 'Mortality Disposal' || 'Disposal' || 'Hist Mortality Disp' => (const Color(0xFFE7E5E4), const Color(0xFF292524)),
      // Sorting Reversal, Opening and any type not listed: dark text on grey.
      _ => (TColors.slate200, TColors.slate800),
    };

/// "flock" value for a batch's birds not yet placed in any flock.
const unplacedFlock = 'unplaced';

/// Live birds (never Dead Birds, which is its own stock).
bool isBirdStockProduct(Map p) => (p['isBirdProduct'] == true || p['name'] == 'Birds') && p['name'] != 'Dead Birds';

String stockSourceFor(String txnType) => switch (txnType) {
      'Production' => 'Production Record',
      // 372: byproducts generated (and disposed at once) by a production record / egg sorting
      'Broken Egg Prod' || 'Mortality In' => 'Production Record',
      'Broken Egg Disposal' || 'Mortality Disposal' => 'Production Record (disposed immediately)',
      'Sorting Breakage' => 'Egg Sorting',
      'Sale' => 'Sale',
      'Restock' || 'Increase' => 'Manual / Product Stock Entry',
      _ => 'Stock Page',
    };

num _r2(num v) => double.parse(v.toStringAsFixed(2));

String batchFlockLabel(Object? batch, Object? flock) => [tStr(batch), tStr(flock)].where((x) => x.isNotEmpty).join(' / ');

/// Every movement, newest first: product transactions, raw-material
/// purchases, production usage and manual adjustments. [manual] (373, the
/// MSM-… headers) gives a manual movement its number, reason and reversal.
List<Map<String, Object?>> buildStockMoves(List<Map> txns, List<Map> purchases, List<Map> usage, List<Map> adjustments,
    [List<Map> manual = const []]) {
  final byId = {for (final m in manual) tIntOrNull(m['movementId']): m};
  final rawHeader = {for (final m in manual) if (m['rawAdjustmentId'] != null) tIntOrNull(m['rawAdjustmentId']): m};
  const noProv = {'batchFlock': '', 'reason': null, 'manualMovementId': null, 'isReversal': false};
  final out = <Map<String, Object?>>[
    for (final t in txns)
      {
        'batchFlock': batchFlockLabel(t['batchCode'], t['flockName']),
        'reason': t['reason'] == null ? null : tStr(t['reason']),
        'manualMovementId': tIntOrNull(t['manualMovementId']),
        'isReversal': t['manualReversal'] == true,
        'key': 'pt${t['poultryStockTransactionId']}',
        'date': tStr(t['createdDate']),
        'item': tStr(t['productName']),
        'parentType': 'Finished Product',
        'movementType': tStr(t['txnType']),
        'qty': tNum(t['quantity']),
        'unitCost': t['unitCost'] == null ? null : tNum(t['unitCost']),
        'total': t['unitCost'] == null ? null : _r2(tNum(t['unitCost']) * tNum(t['quantity']).abs()),
        'source': t['manualMovementId'] != null
            ? '${t['manualReversal'] == true ? 'Reversal of ' : 'Manual movement '}${tStr(byId[tIntOrNull(t['manualMovementId'])]?['movementNo'])}'.trim()
            : stockSourceFor(tStr(t['txnType'])),
        'note': t['note'] == null ? null : tStr(t['note']),
      },
    for (final p in purchases)
      {
        ...noProv,
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
        ...noProv,
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
        'batchFlock': '',
        'reason': rawHeader[tIntOrNull(a['poultryRawMaterialAdjustmentId'])]?['reason'] ??
            (a['movementType'] == 'Reversal' ? 'Reversal' : null),
        'manualMovementId': tIntOrNull(rawHeader[tIntOrNull(a['poultryRawMaterialAdjustmentId'])]?['movementId']),
        'isReversal': a['movementType'] == 'Reversal',
        'key': 'ra${a['poultryRawMaterialAdjustmentId']}',
        'date': tStr(a['adjustedDate']),
        'item': tStr(a['itemName']),
        'parentType': tStr(a['category']) == 'Supplies' ? 'Supplies' : 'Raw Material',
        'movementType': tStr(a['movementType']).isNotEmpty ? tStr(a['movementType']) : (tNum(a['quantity']) >= 0 ? 'Increase' : 'Decrease'),
        'qty': tNum(a['quantity']),
        'unitCost': a['unitCost'] == null ? null : tNum(a['unitCost']),
        'total': a['unitCost'] == null ? null : _r2(tNum(a['unitCost']) * tNum(a['quantity']).abs()),
        'source': rawHeader[tIntOrNull(a['poultryRawMaterialAdjustmentId'])] != null
            ? 'Manual movement ${tStr(rawHeader[tIntOrNull(a['poultryRawMaterialAdjustmentId'])]!['movementNo'])}'
            : (a['movementType'] == 'Reversal' ? 'Manual movement reversal' : 'Manual Adjustment'),
        'note': a['note'] == null ? null : tStr(a['note']),
      },
  ];
  out.sort((a, b) => tStr(b['date']).compareTo(tStr(a['date'])));
  return out;
}

class StockMoveFilters {
  String search = '', from = '', to = '', item = 'all', parentType = 'all', movement = 'all', flock = 'all', reason = 'all';
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
        if (f.flock != 'all' && m['batchFlock'] != f.flock) return false;
        if (f.reason != 'all' && m['reason'] != f.reason) return false;
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
  List<Map> _products = [], _rawItems = [], _manual = [];
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
        soft('/api/Poultry/stock/manual-movements'),
      ]);
      if (!mounted) return;
      setState(() {
        _products = r[0];
        _rawItems = r[1];
        _manual = r[6];
        _moves = buildStockMoves(r[2], r[3], r[4], r[5], r[6]);
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
            ReportColumn('Date'), ReportColumn('Item'), ReportColumn('Parent Type'), ReportColumn('Movement'), ReportColumn('Batch / Flock'),
            ReportColumn('Reason'), ReportColumn('Qty', right: true),
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
        if (_f.flock != 'all') ('Batch / flock', _f.flock),
        if (_f.reason != 'all') ('Reason', _f.reason),
        if (_f.search.trim().isNotEmpty) ('Search', _f.search.trim()),
      ];

  List<List<String>> _exportRows(List<Map<String, Object?>> rows) => [
        for (final m in rows)
          [
            tStr(m['date']).split('T').first,
            tStr(m['item']),
            tStr(m['parentType']),
            tStr(m['movementType']),
            tStr(m['batchFlock']).isEmpty ? '—' : tStr(m['batchFlock']),
            m['reason'] == null ? '—' : tStr(m['reason']),
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
    const headers = ['Date', 'Item', 'Parent Type', 'Movement', 'Batch / Flock', 'Reason', 'Qty', 'Unit Price', 'Total Value', 'Source', 'Note'];
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

  /// usePermissions().isAdmin: anyone who is not plain staff.
  bool get _isAdmin => (widget.company.role ?? '').toLowerCase() != 'staff';

  /// The posted manual movement a row belongs to (not its reversal), for Reverse.
  Map? _reversible(Map m) {
    final id = tIntOrNull(m['manualMovementId']);
    if (!_isAdmin || id == null || m['isReversal'] == true) return null;
    final h = _manual.where((x) => tIntOrNull(x['movementId']) == id).firstOrNull;
    return h != null && h['status'] == 'Posted' ? h : null;
  }

  /// 373: reversal appends the opposite; the original stays in the list.
  Future<void> _reverse(Map h) async {
    final q = tNum(h['quantity']);
    final where = batchFlockLabel(h['batchCode'], h['flockName']);
    final date = tStr(h['effectiveDate']);
    final ok = await showReverseWithReason(
      context,
      title: 'Reverse ${tStr(h['movementNo'])}',
      description: '${tStr(h['itemName'])}: ${q > 0 ? '+' : ''}${loc(q)} · ${tStr(h['reason'])} · '
          '${date.length >= 10 ? date.substring(0, 10) : date}${where.isNotEmpty ? ' · $where' : ''}',
      body: [
        Text(
          'The opposite is posted today and the original stays in the list.'
          '${h['itemKind'] == 'Birds' ? " The flock's count goes back, and any Dead Birds it made come off." : ''}'
          '${h['convertedToBroken'] == true ? ' The Broken Eggs it made come off.' : ''}',
          style: const TextStyle(fontSize: 13, color: TColors.slate500),
        ),
      ],
      action: 'Reverse',
      reasons: stockReversalReasons,
      onConfirm: (reason) => _api.post('/api/Poultry/stock/manual-movements/${tStr(h['movementId'])}/reverse',
          body: {'farmId': widget.company.farmId, 'reason': reason, 'reversedBy': widget.session.tokens.userId}),
    );
    if (!ok || !mounted) return;
    trackerToast(context, '${tStr(h['movementNo'])} reversed');
    await _load();
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
                          if (_options('batchFlock').isNotEmpty)
                            select(_f.flock, 'All batches / flocks', _options('batchFlock'), (v) => _f.flock = v),
                          if (_options('reason').isNotEmpty) select(_f.reason, 'All reasons', _options('reason'), (v) => _f.reason = v),
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
                              if (tStr(m['batchFlock']).isNotEmpty) ('Batch / Flock', tStr(m['batchFlock']), null),
                              if (m['reason'] != null) ('Reason', tStr(m['reason']), null),
                            ],
                            actions: [
                              if (_reversible(m) != null)
                                IconButton(
                                  tooltip: 'Reverse ${tStr(_reversible(m)!['movementNo'])}',
                                  onPressed: () => _reverse(_reversible(m)!),
                                  icon: const Icon(Icons.undo, size: 18, color: TColors.slate600),
                                ),
                            ],
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

/// MANUAL_MOVEMENT_REASONS: the reasons the server accepts (373).
const manualMovementReasons = [
  'Opening Inventory', 'Opening Bird Count', 'Historical Mortality', 'Historical Production',
  'Stock Count Correction', 'Unrecorded Breakage', 'Cull', 'Historical Sale / Use', 'Disposal',
  'Transfer Adjustment', 'Migration', 'Data Correction', 'Damage', 'Loss', 'Other',
];

/// reasonsFor: the reasons that fit the item and direction (the server applies
/// the same rules). [kind] is birds / product / raw.
List<String> manualReasonsFor(String kind, int sign, String? role, bool isEgg) => [
      for (final r in manualMovementReasons)
        if (switch (r) {
          'Historical Mortality' => (kind == 'birds' && sign < 0) || (role == 'DeadBirds' && sign > 0),
          'Cull' => kind == 'birds' && sign < 0,
          'Opening Bird Count' => kind == 'birds' && sign > 0,
          'Opening Inventory' => kind != 'birds' && sign > 0,
          'Disposal' => kind != 'birds' && sign < 0,
          'Unrecorded Breakage' => (isEgg && sign < 0) || (role == 'BrokenEggs' && sign > 0),
          _ => true,
        })
          r,
    ];

const _none = 'none';

String _today() {
  final d = DateTime.now();
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

String _requestKey() {
  final r = DateTime.now().microsecondsSinceEpoch;
  return 'msm-$r-${Object().hashCode.toRadixString(36)}';
}

/// 373: the Stock page's "New movement". Every movement entered by hand goes
/// through one server call that checks batch → flock, the effective date and
/// the reason, and posts to whichever stock owns the item. The "now → after"
/// figures come from the server's preview; posting checks again.
class NewStockMovementDialog extends StatefulWidget {
  const NewStockMovementDialog({super.key, required this.session, required this.company, required this.products, required this.rawItems});
  final Session session;
  final Company company;
  final List<Map> products, rawItems;
  @override
  State<NewStockMovementDialog> createState() => _NewStockMovementDialogState();
}

class _NewStockMovementDialogState extends State<NewStockMovementDialog> {
  String _target = '', _movement = 'Increase', _note = '', _reason = '', _disposition = 'Keep';
  String _batchId = '', _flockId = '', _date = _today();
  num _qty = 0, _unitCost = 0;
  bool _saving = false;
  final String _key = _requestKey();
  List<Map>? _options;
  Map? _preview;
  int _previewSeq = 0;

  @override
  void initState() {
    super.initState();
    widget.session.farmClient.get('/api/Poultry/stock/birds/options', query: {'farmId': widget.company.farmId}).then((res) {
      if (mounted) setState(() => _options = rowsOf(res));
    }).catchError((Object e) {
      if (mounted) trackerToast(context, 'Could not load batches and flocks', description: e is ApiException ? e.message : null, error: true);
    });
  }

  String get _tKind => _target.split(':').first;
  int? get _tId => _target.isEmpty ? null : int.tryParse(_target.split(':').last);
  Map? get _product => _tKind == 'p' ? widget.products.where((p) => tIntOrNull(p['poultryProductId']) == _tId).firstOrNull : null;

  /// birds / product / raw, or null before an item is picked.
  String? get _kind => _target.isEmpty
      ? null
      : _tKind == 'r'
          ? 'raw'
          : (_product != null && isBirdStockProduct(_product!) ? 'birds' : 'product');
  int get _sign => stockMovements.firstWhere((m) => m.$1 == _movement, orElse: () => ('Increase', 1)).$2;
  num get _q => _qty.abs();
  String? get _role =>
      _preview?['systemRole'] as String? ?? (_product?['name'] == 'Broken Eggs' ? 'BrokenEggs' : (_product?['name'] == 'Dead Birds' ? 'DeadBirds' : null));
  bool get _isEgg => _preview?['isEgg'] == true;
  int? get _batchNum => _batchId.isEmpty || _batchId == _none ? null : int.tryParse(_batchId);
  int? get _flockNum => _flockId.isEmpty || _flockId == unplacedFlock || _flockId == _none ? null : int.tryParse(_flockId);
  List<String> get _reasons => _kind == null ? const [] : manualReasonsFor(_kind!, _sign, _role, _isEgg);
  bool get _histMortality => _kind == 'birds' && _reason == 'Historical Mortality';
  String get _maxDate => tStr(_preview?['businessDate']).isNotEmpty ? tStr(_preview?['businessDate']).substring(0, 10) : _today();

  List<Map> get _batches {
    final seen = <int, Map>{};
    for (final o in _options ?? const <Map>[]) {
      seen.putIfAbsent(tIntOrNull(o['batchId']) ?? 0, () => o);
    }
    return seen.values.toList();
  }

  List<Map> get _flocks => [
        for (final o in _options ?? const <Map>[])
          if (o['flockId'] != null && (_batchId.isEmpty || _batchId == _none || '${o['batchId']}' == _batchId)) o,
      ];
  Map? get _pickedBatch => _batches.where((b) => '${b['batchId']}' == _batchId).firstOrNull;
  Map? get _pickedFlock => (_options ?? const <Map>[]).where((o) => o['flockId'] != null && '${o['flockId']}' == _flockId).firstOrNull;

  /// The server's figures for what is picked now.
  Future<void> _loadPreview() async {
    final kind = _kind;
    final seq = ++_previewSeq;
    if (kind == null) {
      setState(() => _preview = null);
      return;
    }
    try {
      final res = await widget.session.farmClient.get('/api/Poultry/stock/manual-movements/preview', query: {
        'farmId': widget.company.farmId,
        if (kind != 'raw' && _tId != null) 'productId': '$_tId',
        if (kind == 'raw' && _tId != null) 'rawItemId': '$_tId',
        if (_flockId == unplacedFlock && _batchNum != null) 'batchId': '$_batchNum',
        if (_flockNum != null) 'flockId': '$_flockNum',
      });
      if (mounted && seq == _previewSeq) setState(() => _preview = res is Map ? res : null);
    } on ApiException {
      if (mounted && seq == _previewSeq) setState(() => _preview = null);
    }
  }

  /// A reason that no longer fits (item or direction changed) is cleared.
  void _fitReason() {
    if (_reason.isNotEmpty && !_reasons.contains(_reason)) _reason = '';
  }

  List<({String label, num? now, num? after, bool bad})> get _impact {
    final p = _preview, kind = _kind;
    final out = <({String label, num? now, num? after, bool bad})>[];
    if (p == null || kind == null || _q <= 0) return out;
    final signed = _sign * _q;
    num? n(Object? v) => v == null ? null : tNum(v);
    if (kind == 'birds') {
      final here = _flockId == unplacedFlock ? n(p['unplacedBirds']) : n(p['flockLiveBirds']);
      if (_flockId.isNotEmpty) {
        out.add((
          label: _flockId == unplacedFlock
              ? 'Batch ${tStr(_pickedBatch?['batchCode'])} birds not in a flock'
              : '${tStr(_pickedFlock?['flockName']).isEmpty ? 'Flock' : tStr(_pickedFlock?['flockName'])} birds',
          now: here,
          after: here == null ? null : here + signed,
          bad: here != null && here + signed < 0,
        ));
      }
      if (_flockId != unplacedFlock) {
        out.add((label: 'Farm live birds', now: tNum(p['farmLiveBirds']), after: tNum(p['farmLiveBirds']) + signed, bad: false));
      }
      if (_histMortality) {
        out.add((
          label: _disposition == 'Keep' ? 'Dead Birds on hand' : 'Dead Birds on hand (generated and disposed)',
          now: tNum(p['deadBirdsOnHand']),
          after: tNum(p['deadBirdsOnHand']) + (_disposition == 'Keep' ? _q : 0),
          bad: false,
        ));
      }
    } else {
      final now = tNum(p['itemOnHand']);
      final name = kind == 'raw'
          ? tStr(widget.rawItems.where((i) => tIntOrNull(i['poultryRawMaterialItemId']) == _tId).firstOrNull?['itemName'])
          : tStr(_product?['name']);
      out.add((label: '${name.isEmpty ? 'Item' : name} on hand', now: now, after: now + signed, bad: (_role != null || kind == 'raw') && now + signed < 0));
      if (_reason == 'Unrecorded Breakage' && _isEgg && _sign < 0) {
        out.add((label: 'Broken Eggs on hand', now: tNum(p['brokenEggsOnHand']), after: tNum(p['brokenEggsOnHand']) + _q, bad: false));
      }
    }
    return out;
  }

  void _toast(String title, [String? description]) => trackerToast(context, title, description: description, error: true);

  Future<void> _save() async {
    final kind = _kind;
    if (kind == null) return _toast('Pick an item');
    if (_q <= 0) return _toast('Quantity must be greater than 0');
    if (_reason.isEmpty) return _toast('Choose the reason');
    if (_date.isEmpty) return _toast('Enter the effective date');
    if (_date.compareTo(_maxDate) > 0) return _toast('The effective date is in the future');
    if (_reason == 'Other' && _note.trim().isEmpty) return _toast('Say what happened', 'Reason "Other" needs a note.');
    if (kind == 'birds') {
      if (_batchNum == null) return _toast('Choose the batch');
      if (_flockId.isEmpty) return _toast('Choose the flock', 'Or "Not placed in a flock" for the batch\'s birds that are not in any flock yet.');
      if (_q != _q.roundToDouble()) return _toast('Birds are whole numbers');
    }
    final bad = _impact.where((i) => i.bad).firstOrNull;
    if (bad != null) return _toast('Not enough stock', '${bad.label}: only ${bad.now == null ? '—' : loc(bad.now!)}.');
    setState(() => _saving = true);
    try {
      final res = await widget.session.farmClient.post('/api/Poultry/stock/manual-movements', body: {
        'poultryProductId': kind == 'raw' ? null : _tId,
        'rawMaterialItemId': kind == 'raw' ? _tId : null,
        'movementType': _movement,
        'quantity': _q,
        'unitCost': kind == 'birds' || _unitCost == 0 ? null : _unitCost,
        'batchId': kind == 'raw' ? null : _batchNum,
        'flockId': kind == 'raw' ? null : _flockNum,
        'effectiveDate': _date,
        'reason': _reason,
        'disposition': _histMortality ? _disposition : null,
        'note': _note.trim().isEmpty ? null : _note.trim(),
        'requestKey': _key,
        'farmId': widget.company.farmId,
        'createdBy': widget.session.tokens.userId,
      });
      if (!mounted) return;
      final r = res is Map ? res : const {};
      trackerToast(context, '${tStr(r['movementNo'])} posted', description: r['repeated'] == true ? 'This movement was already saved.' : null);
      Navigator.pop(context, true);
      return;
    } on ApiException catch (e) {
      if (mounted) _toast('Save failed', e.message);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final products = [for (final p in widget.products) if (p['isActive'] == true) p];
    final raw = [for (final i in widget.rawItems) if (i['isActive'] == true) i];
    final kind = _kind;
    final impact = _impact;
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
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          formSection('Movement', const Color(0xFF2563EB), [
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
                onChanged: (v) {
                  setState(() {
                    _target = v ?? '';
                    _batchId = '';
                    _flockId = '';
                    _reason = '';
                    _preview = null;
                  });
                  _loadPreview();
                },
              ),
            ),
            cell(
              'Movement type *',
              AppSelect<String>(
                value: _movement,
                items: [for (final (m, _) in stockMovements) AppSelectItem(value: m, label: m)],
                onChanged: (v) => setState(() {
                  _movement = v ?? _movement;
                  _fitReason();
                }),
              ),
            ),
            cell(
              'Reason *',
              AppSelect<String>(
                key: ValueKey('reason-$_target-$_movement'),
                value: _reason.isEmpty ? null : _reason,
                enabled: kind != null,
                hintText: kind != null ? 'Choose the reason' : 'Pick the item first',
                items: [for (final r in _reasons) AppSelectItem(value: r, label: r)],
                onChanged: (v) => setState(() => _reason = v ?? ''),
              ),
            ),
            cell(kind == 'birds' ? 'Birds *' : 'Quantity *',
                NumBox(key: ValueKey('qty-${kind == 'birds'}'), value: _qty, decimal: kind != 'birds', onChanged: (v) => setState(() => _qty = v)),
                hint: 'Always positive; the movement type sets the direction.'),
            if (kind != 'birds') cell('Unit cost / value', NumBox(value: _unitCost, decimal: true, onChanged: (v) => _unitCost = v)),
            if (kind != null && kind != 'raw') ...[
              cell(
                kind == 'birds' ? 'Batch *' : 'Batch',
                AppSelect<String>(
                  value: _batchId.isEmpty ? null : _batchId,
                  hintText: _options != null ? (kind == 'birds' ? 'Choose the batch' : 'No batch') : 'Loading batches...',
                  items: [
                    if (kind != 'birds') const AppSelectItem(value: _none, label: 'No batch'),
                    for (final b in _batches)
                      AppSelectItem(
                        value: '${b['batchId']}',
                        label: '${tStr(b['batchCode'])}${tStr(b['batchName']).isNotEmpty ? ' — ${tStr(b['batchName'])}' : ''}',
                      ),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _batchId = v ?? '';
                      _flockId = '';
                    });
                    _loadPreview();
                  },
                ),
                hint: kind == 'birds' ? 'Birds are counted per flock.' : 'Optional: where this stock came from.',
              ),
              cell(
                kind == 'birds' ? 'Flock *' : 'Flock',
                AppSelect<String>(
                  key: ValueKey('flock-$_batchId'),
                  value: _flockId.isEmpty ? null : _flockId,
                  enabled: kind != 'birds' || _batchNum != null,
                  hintText: kind == 'birds' ? (_batchNum != null ? 'Choose the flock' : 'Choose the batch first') : 'No flock',
                  items: [
                    if (kind != 'birds') const AppSelectItem(value: _none, label: 'No flock'),
                    for (final f in _flocks)
                      () {
                        final why = kind == 'birds'
                            ? (f['isClosed'] == true ? 'closed' : (f['hasProductionRecord'] != true ? 'no production record yet' : null))
                            : null;
                        return AppSelectItem(
                          value: '${f['flockId']}',
                          label: '${tStr(f['flockName'])}${kind == 'birds' ? ' · ${why ?? '${loc(tNum(f['liveBirds']))} birds'}' : ''}',
                          enabled: why == null,
                        );
                      }(),
                    if (kind == 'birds' && _pickedBatch != null)
                      AppSelectItem(value: unplacedFlock, label: 'Not placed in a flock · ${loc(tNum(_pickedBatch!['unplacedBirds']))} birds'),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _flockId = v ?? '';
                      // Picking a flock fills in its batch.
                      final f = (_options ?? const <Map>[]).where((o) => o['flockId'] != null && '${o['flockId']}' == _flockId).firstOrNull;
                      if (f != null) _batchId = '${f['batchId']}';
                    });
                    _loadPreview();
                  },
                ),
              ),
            ],
            cell('Effective date *', FilterDate(value: _date, hint: 'Date', onChanged: (v) => setState(() => _date = v)),
                hint: 'When it happened, not when you are entering it.'),
            if (_histMortality)
              cell(
                'Dead birds',
                AppSelect<String>(
                  value: _disposition,
                  items: const [
                    AppSelectItem(value: 'Keep', label: 'Keep in Dead Bird inventory'),
                    AppSelectItem(value: 'Disposed', label: 'Already disposed'),
                  ],
                  onChanged: (v) => setState(() => _disposition = v ?? _disposition),
                ),
              ),
            cell(_reason == 'Other' ? 'Note *' : 'Note',
                AppInput(initialValue: _note, hintText: 'Anything that explains it further', onChanged: (v) => setState(() => _note = v))),
          ]),
          if (impact.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: TColors.slate50, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('IMPACT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .5, color: TColors.slate500)),
                const SizedBox(height: 4),
                for (final i in impact)
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Text(i.label, style: const TextStyle(fontSize: 13, color: TColors.slate600))),
                    const SizedBox(width: 8),
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(text: '${i.now == null ? '—' : loc(i.now!)} → '),
                        TextSpan(
                          text: i.after == null ? '—' : loc(i.after!),
                          style: TextStyle(fontWeight: FontWeight.w600, color: i.bad ? TColors.red600 : null),
                        ),
                      ]),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ]),
                if (kind == 'birds' && _flockId.isNotEmpty && _flockId != unplacedFlock)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      "The flock's latest production record takes the corrected count. No production record is created and no day's deaths change.",
                      style: TextStyle(fontSize: 12, color: TColors.slate500),
                    ),
                  ),
                if (_reason == 'Unrecorded Breakage' && _isEgg && _sign < 0)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('The eggs are not lost: they move to Broken Eggs.', style: TextStyle(fontSize: 12, color: TColors.slate500)),
                  ),
              ]),
            ),
          ],
        ]),
      ),
      actions: [
        OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save')),
      ],
    );
  }
}
