import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../shared/business_dates.dart';
import '../../shared/company_clock.dart';
import '../money/money_widgets.dart';
import '../reports/report_export.dart';
import '../reports/report_format.dart';
import '../reports/report_routes.dart' show openAppHref;
import '../sales/balances_logic.dart' show pageSlice;
import '../sales/balances_widgets.dart';
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../trackers/tracker_widgets.dart';

/// Poultry → Expenses → Deferred inventory cost, as `app/poultry-deferred-costs/page.tsx`:
/// purchases whose cost reaches Profit & Loss as the stock is used.

const deferredScopes = [
  ('DEFERRED', 'Still to expense', 'Purchases with cost still waiting to reach Profit & Loss'),
  ('RECOGNIZED', 'Fully expensed', 'Purchases that were deferred and are now completely expensed'),
  ('EXCEPTION', 'Needs checking', 'Purchases whose figures do not agree with their usages'),
  ('ALL', 'All purchases', 'Every inventory purchase, however its cost was recognised'),
];

const _categoryLabels = {'FeedIngredient': 'Feed Ingredient', 'FinishedFeed': 'Finished Feed', 'SparePart': 'Spare Part'};
String deferredCategoryLabel(Object? c) => tStr(c).isEmpty ? '—' : _categoryLabels[tStr(c)] ?? tStr(c);

const remainingDeferredTooltip =
    'The part of this purchase still held as stock value. It has not been charged to Profit & Loss yet, and will be as the stock is used.';
const recognizedCostTooltip = 'How much of this purchase has already been charged to Profit & Loss as the stock was used.';
const operationalCostTooltip =
    'The stock this activity actually used up, at what it cost. Some of it may have been charged to Profit & Loss earlier, when it was bought.';
const newlyRecognizedTooltip = 'The part of this usage that is being charged to Profit & Loss now.';
const deferredExceptionTooltip =
    "This purchase's own balance and its recorded usages do not agree on how much has been charged to Profit & Loss. Neither figure should be relied on until it is checked.";
const deferredPageIntro =
    'These purchases have already been recorded and may already have affected cash or supplier balances. What is shown here is stock value that has not yet become an expense -- it moves into Profit & Loss as the stock is used.';
const noSecondPaymentTooltip = 'Charging this to Profit & Loss moves no money. The cash left the business when the stock was bought.';

/// "1,234.5 kg": up to three decimals, thousands grouped, as toLocaleString.
String qtyFmt(Object? n, [Object? unit]) {
  final v = tNum(n);
  var s = v.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
  final neg = s.startsWith('-');
  if (neg) s = s.substring(1);
  final parts = s.split('.');
  final whole = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  final out = '${neg ? '-' : ''}$whole${parts.length > 1 ? '.${parts[1]}' : ''}';
  return tStr(unit).isEmpty ? out : '$out ${tStr(unit)}';
}

String _int(Object? n) => qtyFmt(tNum(n).round());

/// queueNote: how much older stock is used before this cost starts to move.
String? deferredQueueNote(Map p) {
  final ahead = tNum(p['quantityAheadInQueue']);
  if (p['quantityAheadInQueue'] == null || ahead <= 0) return null;
  final unit = tStr(p['productionUnit']).isEmpty ? '' : ' ${tStr(p['productionUnit'])}';
  return '${qtyFmt(ahead)}$unit of older stock is used before this cost starts reaching Profit & Loss (${tStr(p['costingMethod']).isEmpty ? 'FIFO' : tStr(p['costingMethod'])}).';
}

/// deferredStatusTone + RECOGNITION_TONE_CLASS, with Exception in red: (bg, fg, border).
(Color, Color, Color) deferredStatusColors(Object? status) {
  final s = tStr(status);
  if (s == 'Exception') return (const Color(0xFFFEF2F2), const Color(0xFFB91C1C), const Color(0xFFFCA5A5));
  if (s == 'Not yet expensed' || s == 'Partly expensed') return (TColors.amber50, TColors.amber800, TColors.amber300);
  if (s == 'Fully expensed' || s == 'Expensed at purchase') return (const Color(0xFFECFDF5), TColors.emerald800, TColors.emerald300);
  return (const Color(0xFFF9FAFB), const Color(0xFF4B5563), const Color(0xFFD1D5DB));
}

/// explainLoadFailure: the headline and hint for a failed load.
({String headline, String hint}) explainLoadFailure(String raw, [String subject = 'this page']) {
  final t = raw.toLowerCase();
  if (t.contains('does not exist') || t.contains('undefined function') || t.contains('42883')) {
    return (
      headline: "${subject[0].toUpperCase()}${subject.substring(1)} aren't switched on yet.",
      hint: "This company's database is missing an update this screen needs. Ask whoever looks after your system to apply it — nothing is wrong with your data.",
    );
  }
  if (t.contains('(401)') || t.contains('(403)') || t.contains('unauthor') || t.contains('forbid')) {
    return (headline: 'You do not have permission to view this.', hint: 'Ask an administrator to give you access for this company.');
  }
  if (t.contains('failed to fetch') || t.contains('networkerror') || t.contains('timeout')) {
    return (headline: 'Could not reach the server.', hint: 'Check your connection and try again. Nothing has been changed.');
  }
  return (
    headline: 'Could not load $subject.',
    hint: 'Try again in a moment. If it keeps happening, pass the detail below to whoever looks after your system.',
  );
}

/// The CSV the Export button downloads.
String deferredCsv(List<Map> rows) {
  const head = [
    'Purchase #', 'Purchase Date', 'Item', 'Category', 'Supplier', 'Purchased Qty', 'Unit', 'Remaining Qty', 'Original Cost',
    'Deferred Basis', 'Recognized Cost', 'Remaining Deferred', 'Recognition %', 'Method', 'Status',
  ];
  String esc(Object? v) {
    final s = v == null ? '' : '$v';
    return RegExp(r'[",\n]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  final lines = [
    for (final p in rows)
      [
        p['poultryRawMaterialPurchaseId'],
        tStr(p['purchaseDate']).length >= 10 ? tStr(p['purchaseDate']).substring(0, 10) : '',
        tStr(p['itemName']),
        deferredCategoryLabel(p['category']),
        tStr(p['supplierName']).isNotEmpty ? tStr(p['supplierName']) : (p['isLotProduced'] == true ? 'Produced ${tStr(p['feedProductionBatchNumber'])}' : ''),
        p['purchasedQuantity'], tStr(p['productionUnit']), p['remainingQuantity'], p['operationalCost'], p['deferredTotalCost'],
        p['recognizedCost'], p['deferredRemainingCost'], p['recognitionPercent'], tStr(p['recognitionMethodLabel']), tStr(p['status']),
      ],
  ];
  return [head, ...lines].map((r) => r.map(esc).join(',')).join('\n');
}

class DeferredCostsScreen extends StatefulWidget {
  const DeferredCostsScreen({super.key, required this.session, required this.company, this.itemId, this.scope});
  final Session session;
  final Company company;

  /// `?itemId=` and `?scope=`.
  final int? itemId;
  final String? scope;

  @override
  State<DeferredCostsScreen> createState() => _DeferredCostsScreenState();
}

class _DeferredCostsScreenState extends State<DeferredCostsScreen> {
  Map? _data;
  bool _loading = true;
  String? _error;
  late String _scope = widget.scope ?? 'DEFERRED';
  late int? _itemId = widget.itemId;
  final _search = TextEditingController();
  String _category = 'all', _supplier = 'all', _from = '', _to = '';
  final Set<int> _expanded = {};
  final Map<int, List<Map>> _history = {};
  final Set<int> _historyLoading = {};
  int _page = 1, _pageSize = 10, _lastTotal = -1;
  FarmMoney _gh = const FarmMoney();
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;

  /// The web allows admins and expense/financial roles; the app has no
  /// permission flags, so the Staff role is the one left out.
  bool get _canView => (widget.company.role ?? '').toLowerCase() != 'staff';

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
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_canView) return setState(() => _loading = false);
    setState(() => _loading = true);
    try {
      final res = await _api.get('/api/Poultry/deferred-inventory-costs', query: {
        'farmId': widget.company.farmId,
        'scope': _scope,
        if (_itemId != null) 'itemId': '$_itemId',
        if (_category != 'all') 'category': _category,
        if (_from.isNotEmpty) 'fromDate': _from,
        if (_to.isNotEmpty) 'toDate': _to,
        if (_search.text.trim().isNotEmpty) 'search': _search.text.trim(),
      });
      if (!mounted) return;
      setState(() {
        _data = res is Map ? res : null;
        _error = null;
        _expanded.clear();
        _history.clear();
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _data = null;
          _error = e.message;
        });
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  List<Map> get _purchases => rowsOf(_data?['purchases']);

  Future<void> _toggle(Map p) async {
    final id = tIntOrNull(p['poultryRawMaterialPurchaseId']) ?? 0;
    if (_expanded.contains(id)) return setState(() => _expanded.remove(id));
    setState(() => _expanded.add(id));
    if (_history.containsKey(id)) return;
    setState(() => _historyLoading.add(id));
    try {
      final h = await _api.get('/api/Poultry/deferred-inventory-costs/$id/history', query: {'farmId': widget.company.farmId});
      if (mounted) setState(() => _history[id] = rowsOf(h));
    } on ApiException catch (e) {
      final x = explainLoadFailure(e.message, 'the recognition history');
      if (mounted) trackerToast(context, x.headline, description: x.hint, error: true);
    }
    if (mounted) setState(() => _historyLoading.remove(id));
  }

  Future<void> _export(List<Map> rows) => ReportExport.sharer(
        'deferred-inventory-costs-${DateTime.now().toUtc().toIso8601String().substring(0, 10)}.csv',
        utf8.encode(deferredCsv(rows)),
        'text/csv',
        'Deferred inventory cost',
      );

  void _href(String href, String label) => openAppHref(context, widget.session, widget.company, href, label: label);

  Future<void> _detail(Map p) => showDialog<void>(
        context: context,
        builder: (_) => PurchaseDetailDialog(
          purchase: p,
          rows: _history[tIntOrNull(p['poultryRawMaterialPurchaseId']) ?? 0],
          fmt: _gh,
          offset: _offset,
          onOpenItem: () => _href('/poultry-raw-materials?tab=items&itemId=${tStr(p['poultryRawMaterialItemId'])}', 'Raw materials'),
          onOpenPurchase: () =>
              _href('/poultry-raw-materials?tab=purchases&purchaseId=${tStr(p['poultryRawMaterialPurchaseId'])}', 'Raw materials'),
        ),
      );

  Widget _statusBadge(Map p) {
    final (bg, fg, border) = deferredStatusColors(p['status']);
    return TBadge(tStr(p['status']), bg: bg, fg: fg, border: border);
  }

  Widget _summary(Map s) {
    final ex = tNum(s['exceptions']);
    Widget card(Widget head, String value, Widget sub, {Color bg = Colors.white, Color border = TColors.slate200, Color fg = TColors.slate900, Widget? extra}) =>
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            head,
            const SizedBox(height: 4),
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: fg)),
            sub,
            ?extra,
          ]),
        );
    Widget head(IconData i, String text, Color c, {Color? label, String? tip}) {
      final w = Row(children: [
        Icon(i, size: 15, color: c),
        const SizedBox(width: 4),
        Expanded(child: Text(text.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: label ?? TColors.slate500))),
      ]);
      return tip == null ? w : Tooltip(message: tip, triggerMode: TooltipTriggerMode.tap, child: w);
    }

    final n = tNum(s['deferredPurchases']);
    return twoUp([
      card(
        head(Icons.hourglass_bottom, 'Deferred inventory cost', TColors.amber700, label: TColors.amber700, tip: remainingDeferredTooltip),
        _gh(tNum(s['remainingDeferredCost'])),
        Text('across ${_int(n)} purchase${n == 1 ? '' : 's'}', style: const TextStyle(fontSize: 12, color: TColors.amber700)),
        bg: TColors.amber50,
        border: const Color(0xFFFDE68A),
        fg: TColors.amber900,
        extra: tNum(s['blockedPurchases']) > 0
            ? Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('${_gh(tNum(s['blockedCost']))} of this is queued behind older stock and will not move until that stock is used.',
                    style: const TextStyle(fontSize: 11, color: TColors.amber800)),
              )
            : null,
      ),
      card(
        head(Icons.check_circle_outline, 'Already expensed', TColors.emerald600, tip: recognizedCostTooltip),
        _gh(tNum(s['recognizedCost'])),
        Text('${tNum(s['recognitionPercent']).toStringAsFixed(1)}% of ${_gh(tNum(s['deferredBasis']))} deferred',
            style: const TextStyle(fontSize: 12, color: TColors.slate400)),
      ),
      card(
        head(Icons.inventory_2_outlined, 'Purchases shown', const Color(0xFF2563EB)),
        _int(s['purchaseCount']),
        Text('${_int(s['fullyRecognized'])} fully expensed · ${_int(s['notRecognized'])} not started',
            style: const TextStyle(fontSize: 12, color: TColors.slate400)),
      ),
      card(
        head(Icons.warning_amber_rounded, 'Needs checking', ex > 0 ? TColors.red600 : TColors.slate400, tip: deferredExceptionTooltip),
        _int(ex),
        Text(ex > 0 ? '${_gh(tNum(s['exceptionDrift']).abs())} unexplained' : 'all figures agree',
            style: const TextStyle(fontSize: 12, color: TColors.slate400)),
        bg: ex > 0 ? const Color(0xFFFEF2F2) : Colors.white,
        border: ex > 0 ? const Color(0xFFFECACA) : TColors.slate200,
        fg: ex > 0 ? const Color(0xFFB91C1C) : TColors.slate900,
      ),
    ]);
  }

  Widget _filters(List<Map> all) {
    final cats = {for (final p in all) if (tStr(p['category']).isNotEmpty) tStr(p['category'])}.toList()..sort();
    final sups = {for (final p in all) if (tStr(p['supplierName']).isNotEmpty) tStr(p['supplierName'])}.toList()..sort();
    final period = _from.isNotEmpty && _to.isNotEmpty ? rangeToPeriod(_from, _to) : 'custom';
    final hint = deferredScopes.where((x) => x.$1 == _scope).firstOrNull?.$3;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FilterLabel(
          'Show',
          AppSelect<String>(
            value: _scope,
            items: [for (final (v, l, _) in deferredScopes) AppSelectItem(value: v, label: l)],
            onChanged: (v) {
              setState(() => _scope = v ?? 'DEFERRED');
              _load();
            },
          ),
        ),
        const SizedBox(height: 10),
        FilterLabel(
          'Category',
          AppSelect<String>(
            value: _category,
            items: [const AppSelectItem(value: 'all', label: 'All categories'), for (final c in cats) AppSelectItem(value: c, label: deferredCategoryLabel(c))],
            onChanged: (v) {
              setState(() => _category = v ?? 'all');
              _load();
            },
          ),
        ),
        const SizedBox(height: 10),
        FilterLabel(
          'Supplier',
          AppSelect<String>(
            value: _supplier,
            items: [const AppSelectItem(value: 'all', label: 'All suppliers'), for (final x in sups) AppSelectItem(value: x, label: x)],
            onChanged: (v) => setState(() => _supplier = v ?? 'all'),
          ),
        ),
        const SizedBox(height: 10),
        FilterLabel(
          'Period',
          AppSelect<String>(
            value: period,
            hintText: 'Select period',
            items: [for (final (_, opts) in periodGroups) for (final (k, l) in opts) AppSelectItem(value: k, label: l)],
            onChanged: (k) {
              final r = k == null ? null : periodToRange(k);
              if (r == null) return;
              setState(() {
                _from = r.from;
                _to = r.to;
              });
              _load();
            },
          ),
        ),
        const SizedBox(height: 10),
        filterRow([
          FilterLabel('From', FilterDate(value: _from, hint: 'From', onChanged: (v) {
            setState(() => _from = v);
            _load();
          })),
          FilterLabel('To', FilterDate(value: _to, hint: 'To', onChanged: (v) {
            setState(() => _to = v);
            _load();
          })),
        ]),
        const SizedBox(height: 10),
        FilterLabel('Search', AppInput(controller: _search, hintText: 'Item, supplier or purchase #', onChanged: (_) => _load())),
        if (_itemId != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () {
                setState(() => _itemId = null);
                _load();
              },
              child: const Text('Clear item filter'),
            ),
          ),
        if (hint != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(hint, style: const TextStyle(fontSize: 11, color: TColors.slate500))),
      ]),
    );
  }

  Widget _table(List<Map> items) {
    final open = [for (final p in items) if (_expanded.contains(tIntOrNull(p['poultryRawMaterialPurchaseId']) ?? 0)) p];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TrackerTable(
        columns: const [
          TCol('', width: 36),
          TCol('Purchase', width: 130),
          TCol('Item', width: 140),
          TCol('Supplier', width: 130),
          TCol('Purchased', right: true, width: 110),
          TCol('Remaining', right: true, width: 110),
          TCol('Original cost', right: true, width: 120),
          TCol('Expensed', right: true, width: 110),
          TCol('Deferred inventory cost', right: true, width: 170),
          TCol('Status', width: 150),
          TCol('', width: 48),
        ],
        rows: [
          for (final p in items)
            () {
              final id = tIntOrNull(p['poultryRawMaterialPurchaseId']) ?? 0;
              final never = tNum(p['deferredTotalCost']) <= 0;
              void tog() => _toggle(p);
              final q = deferredQueueNote(p);
              return <Widget>[
                InkWell(
                  onTap: tog,
                  child: Icon(_expanded.contains(id) ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, size: 18, color: TColors.slate400),
                ),
                InkWell(
                  onTap: tog,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text('#$id', style: const TextStyle(fontWeight: FontWeight.w500)),
                    Text(fmtDateTime(p['purchaseDate'], p, _offset), style: const TextStyle(fontSize: 11, color: TColors.slate500)),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(tStr(p['itemName']).isEmpty ? '—' : tStr(p['itemName'])),
                  Text(deferredCategoryLabel(p['category']), style: const TextStyle(fontSize: 11, color: TColors.slate500)),
                ]),
                p['isLotProduced'] == true
                    ? Text(tStr(p['feedProductionBatchNumber']).isEmpty ? 'Produced' : tStr(p['feedProductionBatchNumber']),
                        style: const TextStyle(fontSize: 11, color: Color(0xFF4338CA)))
                    : cellText(tStr(p['supplierName']).isEmpty ? '—' : tStr(p['supplierName'])),
                Align(alignment: Alignment.centerRight, child: Text(qtyFmt(p['purchasedQuantity'], p['productionUnit']))),
                Align(alignment: Alignment.centerRight, child: Text(qtyFmt(p['remainingQuantity'], p['productionUnit']))),
                Align(alignment: Alignment.centerRight, child: Text(_gh(tNum(p['operationalCost'])))),
                Align(
                  alignment: Alignment.centerRight,
                  child: never ? const Text('—', style: TextStyle(color: TColors.slate300)) : Text(_gh(tNum(p['recognizedCost']))),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: never
                      ? const Text('—', style: TextStyle(color: TColors.slate300))
                      : Text(_gh(tNum(p['deferredRemainingCost'])),
                          style: tNum(p['deferredRemainingCost']) > 0 ? const TextStyle(color: TColors.amber700, fontWeight: FontWeight.w500) : null),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  _statusBadge(p),
                  if (!never) Text('${tNum(p['recognitionPercent']).toStringAsFixed(1)}% expensed', style: const TextStyle(fontSize: 11, color: TColors.slate500)),
                  if (tNum(p['deferredRemainingCost']) > 0 && q != null)
                    Tooltip(
                      message: q,
                      child: Text('behind ${qtyFmt(p['quantityAheadInQueue'], p['productionUnit'])}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF0369A1))),
                    ),
                ]),
                IconButton(tooltip: 'Purchase detail', onPressed: () => _detail(p), icon: const Icon(Icons.receipt_long, size: 18, color: TColors.slate500)),
              ];
            }(),
        ],
      ),
      for (final p in open) ...[
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(color: TColors.slate50, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
          child: HistoryPanel(
            purchase: p,
            rows: _history[tIntOrNull(p['poultryRawMaterialPurchaseId']) ?? 0],
            loading: _historyLoading.contains(tIntOrNull(p['poultryRawMaterialPurchaseId']) ?? 0),
            fmt: _gh,
            offset: _offset,
            onOpenExpense: () => _href('/expenses', 'Expenses'),
          ),
        ),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-deferred-costs');
    final all = _purchases;
    final rows = _supplier == 'all' ? all : [for (final p in all) if (tStr(p['supplierName']) == _supplier) p];
    if (rows.length != _lastTotal) {
      _lastTotal = rows.length;
      _page = 1;
    }
    final pageRows = pageSlice(rows, _page, _pageSize);
    final s = _data?['summary'] is Map ? _data!['summary'] as Map : null;

    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Deferred inventory cost')),
      body: !_canView
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Text('You do not have permission to view inventory costs.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate500)),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
                children: [
                  const Text('Deferred inventory cost', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: TColors.slate900)),
                  const Text('Track inventory purchases whose costs are recognized in Profit & Loss as the inventory is consumed.',
                      style: TextStyle(fontSize: 13, color: TColors.slate500)),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: rows.isEmpty ? null : () => _export(rows),
                      icon: const Icon(Icons.download, size: 16),
                      label: const Text('Export CSV'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: const Color(0xFFF0F9FF), border: Border.all(color: const Color(0xFFBAE6FD)), borderRadius: BorderRadius.circular(6)),
                    child: const Text(deferredPageIntro, style: TextStyle(fontSize: 12, color: Color(0xFF0C4A6E))),
                  ),
                  const SizedBox(height: 12),
                  _filters(all),
                  const SizedBox(height: 12),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Row(children: [
                        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 8),
                        Text('Loading…', style: TextStyle(color: TColors.slate500)),
                      ]),
                    )
                  else if (_error != null)
                    _errorCard(_error!)
                  else ...[
                    if (s != null) ...[_summary(s), const SizedBox(height: 12)],
                    if (rows.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
                        child: Text(
                          _scope == 'DEFERRED'
                              ? 'No purchases are holding cost back from Profit & Loss. On a farm that expenses stock when it is bought, this is the expected result.'
                              : 'No purchases match these filters.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 13, color: TColors.slate500),
                        ),
                      )
                    else
                      MobileCardList<Map>(
                        striped: true,
                        items: pageRows,
                        keyOf: (p) => tStr(p['poultryRawMaterialPurchaseId']),
                        primary: (p) => tStr(p['itemName']).isNotEmpty ? tStr(p['itemName']) : 'Purchase #${tStr(p['poultryRawMaterialPurchaseId'])}',
                        secondary: (p) =>
                            '#${tStr(p['poultryRawMaterialPurchaseId'])} · ${fmtDateTime(p['purchaseDate'], p, _offset)} · ${deferredCategoryLabel(p['category'])}',
                        trailing: (p) => Padding(padding: const EdgeInsets.only(left: 6), child: _statusBadge(p)),
                        highlights: (p) {
                          final never = tNum(p['deferredTotalCost']) <= 0;
                          return [
                            Highlight('Awaiting P&L', never ? '—' : _gh(tNum(p['deferredRemainingCost'])), accent: Accent.amber, wide: true),
                            Highlight('Original cost', _gh(tNum(p['operationalCost'])), accent: Accent.blue),
                            Highlight('Expensed', never ? '—' : _gh(tNum(p['recognizedCost'])), accent: Accent.emerald),
                          ];
                        },
                        details: (p) => [
                          (
                            'Supplier',
                            p['isLotProduced'] == true
                                ? (tStr(p['feedProductionBatchNumber']).isEmpty ? 'Produced' : tStr(p['feedProductionBatchNumber']))
                                : (tStr(p['supplierName']).isEmpty ? '—' : tStr(p['supplierName']))
                          ),
                          ('Purchased', qtyFmt(p['purchasedQuantity'], p['productionUnit'])),
                          ('Remaining', qtyFmt(p['remainingQuantity'], p['productionUnit'])),
                          ('Progress', tNum(p['deferredTotalCost']) > 0 ? '${tNum(p['recognitionPercent']).toStringAsFixed(1)}% expensed' : '—'),
                          if (tStr(p['status']) == 'Exception' && tStr(p['exceptionReason']).isNotEmpty) ('Needs checking', tStr(p['exceptionReason'])),
                          if (tNum(p['deferredRemainingCost']) > 0 && deferredQueueNote(p) != null)
                            ('In the queue', 'behind ${qtyFmt(p['quantityAheadInQueue'], p['productionUnit'])}'),
                        ],
                        actions: (p) => [
                          OutlinedButton.icon(onPressed: () => _detail(p), icon: const Icon(Icons.receipt_long, size: 16), label: const Text('Purchase detail')),
                        ],
                        table: _table,
                        pager: CompactPager(
                          total: rows.length,
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
                ],
              ),
            ),
    );
  }

  Widget _errorCard(String error) {
    final x = explainLoadFailure(error, 'deferred inventory costs');
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        const Icon(Icons.warning_amber_rounded, size: 32, color: Color(0xFFF59E0B)),
        const SizedBox(height: 8),
        Text(x.headline, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: TColors.slate900)),
        const SizedBox(height: 4),
        Text(x.hint, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: _load, child: const Text('Try again')),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: Material(type: MaterialType.transparency, child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Technical detail', style: TextStyle(fontSize: 11, color: TColors.slate400)),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                color: TColors.slate50,
                child: Text(error, style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: TColors.slate500)),
              ),
            ],
          )),
        ),
      ]),
    );
  }
}

/// HistoryPanel: every usage that drew on one purchase.
class HistoryPanel extends StatelessWidget {
  const HistoryPanel({
    super.key,
    required this.purchase,
    required this.rows,
    required this.loading,
    required this.fmt,
    required this.offset,
    required this.onOpenExpense,
  });
  final Map purchase;
  final List<Map>? rows;
  final bool loading;
  final FarmMoney fmt;
  final Duration offset;
  final VoidCallback onOpenExpense;

  @override
  Widget build(BuildContext context) {
    final p = purchase;
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Row(children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 8),
          Text('Loading recognition history…', style: TextStyle(fontSize: 13, color: TColors.slate500)),
        ]),
      );
    }
    final r = rows;
    if (r == null || r.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Nothing has drawn on this purchase yet${tNum(p['deferredRemainingCost']) > 0 ? ' — its ${fmt(tNum(p['deferredRemainingCost']))} is still held as stock value.' : '.'}',
          style: const TextStyle(fontSize: 13, color: TColors.slate500),
        ),
      );
    }
    final live = [for (final x in r) if (x['isReversed'] != true) x];
    final totalRec = live.fold<num>(0, (s, x) => s + tNum(x['recognizedCost']));
    final totalOp = live.fold<num>(0, (s, x) => s + tNum(x['operationalCost']));
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Recognition history — what moved this purchase’s cost into Profit & Loss',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: TColors.slate600)),
        const SizedBox(height: 6),
        TrackerTable(
          columns: const [
            TCol('Date', width: 140),
            TCol('Source', width: 140),
            TCol('Qty drawn', right: true, width: 110),
            TCol('Unit cost', right: true, width: 100),
            TCol('Stock used', right: true, width: 110),
            TCol('Expensed', right: true, width: 110),
            TCol('Outcome', width: 160),
          ],
          rows: [
            for (final x in r)
              [
                cellText(fmtDateTime(x['usedDate'], x, offset)),
                Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(tStr(x['sourceLabel'])),
                  Text(tStr(x['sourceType']), style: const TextStyle(fontSize: 11, color: TColors.slate500)),
                ]),
                Align(alignment: Alignment.centerRight, child: Text(qtyFmt(x['quantityDrawn'], x['productionUnit']))),
                Align(alignment: Alignment.centerRight, child: Text(fmt(tNum(x['unitCostAtDraw'])))),
                Tooltip(message: operationalCostTooltip, child: Align(alignment: Alignment.centerRight, child: Text(fmt(tNum(x['operationalCost']))))),
                Align(
                  alignment: Alignment.centerRight,
                  child: tNum(x['recognizedCost']) > 0
                      ? Text(fmt(tNum(x['recognizedCost'])), style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.emerald700))
                      : const Text('—', style: TextStyle(color: TColors.slate300)),
                ),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(
                    child: Text(tStr(x['recognitionOutcome']),
                        style: TextStyle(color: x['isReversed'] == true || tNum(x['recognizedCost']) <= 0 ? TColors.slate500 : TColors.emerald700)),
                  ),
                  if (x['expenseId'] != null && x['isReversed'] != true)
                    IconButton(
                      tooltip: 'Expense #${tStr(x['expenseId'])} — $noSecondPaymentTooltip',
                      onPressed: onOpenExpense,
                      icon: const Icon(Icons.open_in_new, size: 14, color: TColors.slate400),
                    ),
                ]),
              ],
          ],
          footer: [
            Text('Live usages (${live.length})', style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.slate600)),
            const SizedBox.shrink(),
            const SizedBox.shrink(),
            const SizedBox.shrink(),
            Align(alignment: Alignment.centerRight, child: Text(fmt(totalOp), style: const TextStyle(fontWeight: FontWeight.w500))),
            Align(alignment: Alignment.centerRight, child: Text(fmt(totalRec), style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.emerald700))),
            const SizedBox.shrink(),
          ],
        ),
        if (tStr(p['status']) == 'Exception' && tStr(p['exceptionReason']).isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFFEF2F2), border: Border.all(color: const Color(0xFFFECACA)), borderRadius: BorderRadius.circular(6)),
            child: Text(tStr(p['exceptionReason']), style: const TextStyle(fontSize: 12, color: Color(0xFF7F1D1D))),
          ),
        ],
      ]),
    );
  }
}

/// PurchaseDetailDialog: the purchase, its cost recognition, and the history
/// when it has been loaded.
class PurchaseDetailDialog extends StatelessWidget {
  const PurchaseDetailDialog({
    super.key,
    required this.purchase,
    required this.rows,
    required this.fmt,
    required this.offset,
    required this.onOpenItem,
    required this.onOpenPurchase,
  });
  final Map purchase;
  final List<Map>? rows;
  final FarmMoney fmt;
  final Duration offset;
  final VoidCallback onOpenItem, onOpenPurchase;

  @override
  Widget build(BuildContext context) {
    final p = purchase;
    final never = tNum(p['deferredTotalCost']) <= 0;
    Widget row(String k, String v, {String? hint}) {
      final w = Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Flexible(child: Text(k, style: const TextStyle(fontSize: 13, color: TColors.slate500))),
          const SizedBox(width: 16),
          Expanded(child: Text(v, textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, color: TColors.slate900))),
        ]),
      );
      return hint == null ? w : Tooltip(message: hint, triggerMode: TooltipTriggerMode.longPress, child: w);
    }

    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(t.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: .4, color: TColors.slate500)),
        );
    final pct = tNum(p['recognitionPercent']);
    final r = rows;
    return AlertDialog(
      scrollable: true,
      title: Text('Purchase #${tStr(p['poultryRawMaterialPurchaseId'])}'),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          label('Purchase'),
          row('Item', tStr(p['itemName']).isEmpty ? '—' : tStr(p['itemName'])),
          row('Category', deferredCategoryLabel(p['category'])),
          row('Purchase date', tStr(p['purchaseDate']).length >= 10 ? tStr(p['purchaseDate']).substring(0, 10) : '—'),
          row(
            p['isLotProduced'] == true ? 'Produced by' : 'Supplier',
            p['isLotProduced'] == true
                ? (tStr(p['feedProductionBatchNumber']).isEmpty ? 'Feed production' : tStr(p['feedProductionBatchNumber']))
                : (tStr(p['supplierName']).isEmpty ? '—' : tStr(p['supplierName'])),
          ),
          row('Original quantity', qtyFmt(p['purchasedQuantity'], p['productionUnit'])),
          row('Original cost', fmt(tNum(p['operationalCost']))),
          row('Recognition', tStr(p['recognitionMethodLabel']).isEmpty ? '—' : tStr(p['recognitionMethodLabel'])),
          const Divider(height: 20),
          label('Cost recognition'),
          row('Quantity used', qtyFmt(p['consumedQuantity'], p['productionUnit'])),
          row('Quantity remaining', qtyFmt(p['remainingQuantity'], p['productionUnit'])),
          if (never)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'This purchase was charged to Profit & Loss when it was bought, so none of its cost is waiting. Using the stock reduces the quantity but adds no new expense.',
                style: TextStyle(fontSize: 12, color: TColors.slate500),
              ),
            )
          else ...[
            row('Deferred to begin with', fmt(tNum(p['deferredTotalCost']))),
            row('Expensed so far', fmt(tNum(p['recognizedCost'])), hint: recognizedCostTooltip),
            row('Still to expense', fmt(tNum(p['deferredRemainingCost'])), hint: remainingDeferredTooltip),
            row('Progress', '${pct.toStringAsFixed(2)}%'),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: (pct.clamp(0, 100)) / 100,
                minHeight: 6,
                backgroundColor: TColors.slate200,
                color: const Color(0xFF10B981),
              ),
            ),
          ],
          if (tStr(p['status']) == 'Exception') ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFFEF2F2), border: Border.all(color: const Color(0xFFFECACA)), borderRadius: BorderRadius.circular(6)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Needs checking', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF7F1D1D))),
                Text(tStr(p['exceptionReason']), style: const TextStyle(fontSize: 12, color: Color(0xFF7F1D1D))),
                const SizedBox(height: 4),
                Text('Lot balance says ${fmt(tNum(p['recognizedCost']))}; its usages say ${fmt(tNum(p['allocatedRecognizedCost']))}.',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7F1D1D))),
              ]),
            ),
          ],
          if (r != null && r.isNotEmpty) ...[
            const Divider(height: 20),
            label('Recognition history (${r.length})'),
            for (final x in r)
              Opacity(
                opacity: x['isReversed'] == true ? .6 : 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: DefaultTextStyle(
                    style: TextStyle(fontSize: 12, decoration: x['isReversed'] == true ? TextDecoration.lineThrough : null, color: TColors.slate700),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(fmtDateTime(x['usedDate'], x, offset), style: const TextStyle(color: TColors.slate500)),
                          Text(tStr(x['sourceLabel']), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ]),
                      ),
                      const SizedBox(width: 6),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(qtyFmt(x['quantityDrawn'], x['productionUnit']), style: const TextStyle(color: TColors.slate500)),
                        Text(tNum(x['recognizedCost']) > 0 ? fmt(tNum(x['recognizedCost'])) : '—', style: const TextStyle(color: TColors.emerald700)),
                      ]),
                    ]),
                  ),
                ),
              ),
          ],
        ]),
      ),
      actions: [
        OutlinedButton(
          onPressed: () {
            Navigator.pop(context);
            onOpenPurchase();
          },
          child: const Text('Open purchase'),
        ),
        OutlinedButton(
          onPressed: () {
            Navigator.pop(context);
            onOpenItem();
          },
          child: const Text('Open item'),
        ),
      ],
    );
  }
}
