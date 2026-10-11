import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/buttons.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../shared/business_dates.dart';
import 'tracker_logic.dart';
import 'tracker_widgets.dart';

/// Poultry → Trackers → Egg tracker, as `app/egg-tracker/page.tsx`.
///
/// The ledger is built from production records (collected in, broken / meaty /
/// soft / lost out), egg sales (out, minus the ones a driver return or
/// delivery generated), this page's own egg adjustments, and the egg
/// product's stock-ledger moves (load-outs, returns, Set stock). "Eggs on
/// hand" is the server's own ledger sum — the same "In stock"
/// /poultry-inventory shows — and any gap is shown as an Unmatched row.
class EggTrackerScreen extends StatefulWidget {
  const EggTrackerScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<EggTrackerScreen> createState() => _EggTrackerScreenState();
}

class _EggTrackerScreenState extends State<EggTrackerScreen> {
  List<Map> _productions = [], _flocks = [], _sales = [], _adjustments = [], _moves = [];
  num? _stockOnHand;
  bool _loading = true;
  bool _refreshing = false;
  String _error = '';

  String _typeFilter = 'ALL';
  final _desc = TextEditingController();
  String _from = '', _to = '';
  SortState _sort = (key: 'date', dir: SortDir.desc);
  int _page = 1;
  int _pageSize = trackerPageSizeDefault;
  bool _table = false;

  EggLedger? _ledger;

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _desc.dispose();
    super.dispose();
  }

  Future<List<Map>> _list(String path, Map<String, dynamic> q) async => rowsOf(await _api.get(path, query: q));

  Future<void> _load() async {
    final userId = widget.session.tokens.userId;
    if (userId == null || userId.isEmpty || _farmId.isEmpty) {
      setState(() {
        _error = 'Farm ID or User ID not found';
        _loading = false;
        _refreshing = false;
      });
      return;
    }
    final uq = {'userId': userId, 'farmId': _farmId};
    final fq = {'farmId': _farmId};
    // Each read stands alone, as the web's wrappers return a result object
    // rather than rejecting the whole Promise.all.
    Future<(List<Map>, String?)> safe(String path, Map<String, dynamic> q) async {
      try {
        return (await _list(path, q), null);
      } on ApiException catch (e) {
        return (<Map>[], e.message);
      }
    }

    final results = await Future.wait([
      safe('/api/EggProduction', uq),
      safe('/api/Flock', uq),
      safe('/api/Sale', uq),
      safe('/api/EggInventoryAdjustment', fq),
      safe('/api/Poultry/products', fq),
      safe('/api/Poultry/stock/transactions', fq),
    ]);
    if (!mounted) return;
    final (eggs, eggErr) = results[0];
    final products = results[4].$1;
    final eggProducts = [for (final p in products) if (isEggProduct(p)) p];
    final eggIds = {for (final p in eggProducts) tIntOrNull(p['poultryProductId'])};
    setState(() {
      _productions = eggs;
      _error = eggErr == null ? '' : 'Failed to load egg production ($eggErr)';
      _flocks = results[1].$1;
      _sales = results[2].$1;
      _adjustments = results[3].$1;
      _moves = [for (final t in results[5].$1) if (eggIds.contains(tIntOrNull(t['poultryProductId']))) t];
      _stockOnHand = eggProducts.isNotEmpty ? eggProducts.fold<num>(0, (s, p) => s + tNum(p['stockOnHand'])) : null;
      _ledger = buildEggStockLedger(_productions, _sales, _flocks, _adjustments, _moves, _stockOnHand);
      _loading = false;
      _refreshing = false;
    });
  }

  void _refresh() {
    setState(() => _refreshing = true);
    _load();
  }

  // ------------------------------------------------------------ derived

  List<StockLedgerRow> get _all => _ledger?.rows ?? const [];

  List<StockLedgerRow> get _filtered {
    var list = [..._all];
    if (_typeFilter != 'ALL') list = list.where((r) => r.type == _typeFilter).toList();
    final q = _desc.text.trim().toLowerCase();
    if (q.isNotEmpty) list = list.where((r) => r.description.toLowerCase().contains(q)).toList();
    if (_from.isNotEmpty) list = list.where((r) => localDateKey(r.date).compareTo(_from) >= 0).toList();
    if (_to.isNotEmpty) list = list.where((r) => localDateKey(r.date).compareTo(_to) <= 0).toList();
    return list;
  }

  List<StockLedgerRow> get _sorted => sortRows(_filtered, _sort, (r, k) => switch (k) {
        // The ledger's own sequence: a day's rows share a date.
        'date' => r.seq,
        'type' => r.type,
        'description' => r.description,
        'in' => r.inQty,
        'out' => r.outQty,
        _ => null,
      });

  bool get _filtersActive => _typeFilter != 'ALL' || _desc.text.trim().isNotEmpty || _from.isNotEmpty || _to.isNotEmpty;

  void _clearFilters() {
    setState(() {
      _typeFilter = 'ALL';
      _desc.clear();
      _from = '';
      _to = '';
      _sort = (key: 'date', dir: SortDir.desc);
      _page = 1;
    });
  }

  // ------------------------------------------------------------ adjustments

  int? _adjId(StockLedgerRow r) => r.sortKey.startsWith('eggadj_') ? int.tryParse(r.sortKey.substring(7)) : null;

  Future<void> _openAdjustment([StockLedgerRow? row]) async {
    Map? existing;
    if (row != null) {
      final id = _adjId(row);
      existing = _adjustments.where((a) => tIntOrNull(a['adjustmentId']) == id).firstOrNull;
      if (existing == null) return;
    }
    final today = isoDay(DateTime.now());
    final form = existing == null
        ? AdjustmentForm('Correction', today, '', '')
        : AdjustmentForm(
            tStr(existing['adjustmentType']).isEmpty ? 'Correction' : tStr(existing['adjustmentType']),
            tStr(existing['adjustmentDate']).length >= 10 ? tStr(existing['adjustmentDate']).substring(0, 10) : today,
            jsNum(tNum(existing['eggDelta'])),
            tStr(existing['description']),
          );
    if (!adjustmentTypes.any((t) => t.$1 == form.type)) form.type = 'Correction';
    final editingId = existing == null ? null : tIntOrNull(existing['adjustmentId']);
    await showDialog<void>(
      context: context,
      builder: (_) => AdjustmentDialog(
        title: editingId != null ? 'Edit egg adjustment' : 'Egg inventory adjustment',
        description:
            'Add or remove eggs without creating a production record. Positive count adds to on-hand; negative subtracts.',
        deltaLabel: 'Egg change (whole eggs)',
        deltaHint: 'e.g. 50 or -20',
        decimal: false,
        initial: form,
        editing: editingId != null,
        onSave: (f) => _save(f, editingId),
      ),
    );
  }

  Future<bool> _save(AdjustmentForm f, int? editingId) async {
    final delta = int.tryParse(f.delta.trim());
    if (delta == null || delta == 0) {
      trackerToast(context, 'Check the form',
          description:
              'Enter egg change as a whole number — positive adds eggs, negative removes. Zero is not allowed.',
          error: true);
      return false;
    }
    final userId = widget.session.tokens.userId;
    if (userId == null || userId.isEmpty) {
      trackerToast(context, 'Session issue', description: 'Sign in again to continue.', error: true);
      return false;
    }
    final body = {
      'UserId': userId,
      'FarmId': _farmId,
      'AdjustmentDate': f.date.isNotEmpty ? adjustmentIso(f.date) : DateTime.now().toUtc().toIso8601String(),
      'AdjustmentType': f.type,
      'EggDelta': delta,
      'Description': f.description.trim().isEmpty ? null : f.description.trim(),
    };
    try {
      if (editingId != null) {
        await _api.put('/api/EggInventoryAdjustment/$editingId', body: {'AdjustmentId': editingId, ...body});
        if (mounted) trackerToast(context, 'Adjustment updated');
      } else {
        await _api.post('/api/EggInventoryAdjustment', body: body);
        if (mounted) trackerToast(context, 'Adjustment added');
      }
    } on ApiException catch (e) {
      if (mounted) {
        trackerToast(context, editingId != null ? 'Update failed' : 'Save failed',
            description: e.message.isNotEmpty
                ? e.message
                : (editingId != null ? 'Could not update adjustment' : 'Could not save adjustment'),
            error: true);
      }
      return false;
    }
    _load();
    return true;
  }

  Future<void> _delete(StockLedgerRow row) async {
    final id = _adjId(row);
    if (id == null) return;
    final ok = await confirmDelete(context,
        title: 'Delete egg inventory adjustment?',
        description: 'This adjustment will be permanently removed from the ledger.');
    if (!ok || !mounted) return;
    try {
      await _api.delete('/api/EggInventoryAdjustment/$id?farmId=${Uri.encodeQueryComponent(_farmId)}');
      if (mounted) trackerToast(context, 'Adjustment removed');
      _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Delete failed', description: e.message, error: true);
    }
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/egg-tracker');
    return Scaffold(
      appBar: AppBar(
        leading: lead.leading,
        leadingWidth: lead.width,
        title: const Text('Egg tracker'),
        actions: [RefreshAction(busy: _refreshing || _loading, onPressed: _refresh)],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            TrackerHeader(
              icon: Icons.bar_chart,
              iconBg: TColors.amber100,
              iconFg: TColors.amber700,
              title: 'Egg tracker',
              blurb:
                  'Ledger from egg sorting production, egg sales, and optional manual adjustments (like Cash at hand).',
              session: widget.session,
              company: widget.company,
            ),
            const SizedBox(height: 16),
            if (_error.isNotEmpty) ...[TrackerBanner.error(_error), const SizedBox(height: 12)],
            if (_loading)
              const TrackerLoading('Loading egg tracker…')
            else ...[
              _summaryCard(),
              const SizedBox(height: 16),
              ..._breakdown(),
              _ledgerCard(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _summaryCard() {
    final l = _ledger!;
    final rows = l.rows;
    num sumIn(bool Function(StockLedgerRow) w) => rows.where(w).fold<num>(0, (s, r) => s + r.inQty);
    num sumOut(bool Function(StockLedgerRow) w) => rows.where(w).fold<num>(0, (s, r) => s + r.outQty);
    final adjust = RegExp('adjust', caseSensitive: false);
    final onHand = l.currentEggsAtHand;
    return TCard(
      bg: const Color(0x80FFFBEB),
      border: TColors.amber200,
      eyebrow: 'Egg tracker',
      titleWidget: const Text('Estimated egg inventory',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: TColors.slate800)),
      trailing: AppButton(
        label: 'Add adjustment',
        icon: Icons.add,
        size: AppButtonSize.sm,
        onPressed: () => _openAdjustment(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TileGrid([
            TileData('Eggs on hand', loc(onHand.round()),
                color: onHand < 0 ? TColors.red600 : TColors.slate900,
                suffix: 'eggs',
                action: CopyButton(
                  value: '${onHand.round()}',
                  label: 'Copy egg count',
                  toastText: 'Egg count copied to clipboard',
                )),
            TileData('Egg produced', loc(sumIn((r) => r.type == 'Production')), color: TColors.sky700),
            TileData('Egg sales (units)', loc(sumOut((r) => r.type == 'Sale')), color: TColors.amber800),
            TileData('Last ledger event', rows.isEmpty ? '—' : trackerDate(l.lastUpdatedIso), color: TColors.slate600),
            TileData('Eggs in (adjustments)', loc(sumIn((r) => adjust.hasMatch(r.type))), color: TColors.emerald700),
            TileData('Eggs out (adjustments)', loc(sumOut((r) => adjust.hasMatch(r.type))), color: TColors.rose600),
            TileData('Total eggs in', loc(sumIn((_) => true)), color: TColors.emerald600),
            TileData('Total eggs out', loc(sumOut((_) => true)), color: TColors.red600),
          ]),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(children: [
              t('Production adds good eggs; broken eggs and egg sales reduce the total. Use '),
              b('Add adjustment'),
              t(' to align counts after a stocktake (requires DB migration 012 on the API database).'),
            ]),
            style: const TextStyle(fontSize: 12, color: TColors.slate500),
          ),
          if (onHand < 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: TColors.amber100,
                border: Border.all(color: TColors.amber200),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'A negative count often means more egg sales were logged than production — confirm dates, production rows, or add an adjustment.',
                style: TextStyle(fontSize: 12, color: TColors.amber900),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _breakdown() {
    final rows = _all;
    final inBy = groupLedgerByType(rows, true, eggMoveLabels);
    final outBy = groupLedgerByType(rows, false, eggMoveLabels);
    if (inBy.isEmpty && outBy.isEmpty) return const [];
    final totalIn = rows.fold<num>(0, (s, r) => s + r.inQty);
    final totalOut = rows.fold<num>(0, (s, r) => s + r.outQty);
    return [
      BreakdownSection(cards: [
        FlowBreakdownCard(
          title: 'Eggs in by source',
          inDirection: true,
          buckets: inBy,
          total: totalIn,
          fmt: (n) => loc(n),
          description:
              'Every movement that added eggs to stock — the whole ledger, so it breaks down the totals above rather than the filtered table below.',
          emptyText: 'No eggs have come in yet.',
        ),
        FlowBreakdownCard(
          title: 'Eggs out by use',
          inDirection: false,
          buckets: outBy,
          total: totalOut,
          fmt: (n) => loc(n),
          description:
              'Every movement that took eggs out of stock — sales, internal use, load-outs and the non-saleable ones.',
          emptyText: 'No eggs have gone out yet.',
        ),
      ]),
      const SizedBox(height: 6),
    ];
  }

  Widget _ledgerCard() {
    final types = {for (final r in _all) r.type}.toList()..sort();
    final sorted = _sorted;
    final pageRows = pageOf(sorted, _page, _pageSize);
    final inTotal = sorted.fold<num>(0, (s, r) => s + r.inQty);
    final outTotal = sorted.fold<num>(0, (s, r) => s + r.outQty);

    return TCard(
      title: 'Egg inventory ledger',
      description: 'Chronological ledger; filter the table below',
      headerExtra: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          children: [
            AppSelect<String>(
              value: _typeFilter,
              hintText: 'Type',
              items: [
                const AppSelectItem(value: 'ALL', label: 'All types'),
                for (final t in types) AppSelectItem(value: t, label: t),
              ],
              onChanged: (v) => setState(() {
                _typeFilter = v ?? 'ALL';
                _page = 1;
              }),
            ),
            const SizedBox(height: 8),
            AppInput(
              controller: _desc,
              hintText: 'Description…',
              onChanged: (_) => setState(() => _page = 1),
            ),
            const SizedBox(height: 8),
            filterRow([
              FilterDate(value: _from, hint: 'From', onChanged: (v) => setState(() {
                    _from = v;
                    _page = 1;
                  })),
              FilterDate(value: _to, hint: 'To', onChanged: (v) => setState(() {
                    _to = v;
                    _page = 1;
                  })),
            ]),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: AppButton(
                label: 'Reset ledger filters',
                variant: AppButtonVariant.outline,
                size: AppButtonSize.sm,
                onPressed: _clearFilters,
              ),
            ),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (sorted.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Text('No ledger rows yet. Add egg production and egg sales (product name contains "egg").',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: TColors.slate600)),
            )
          else if (!_table) ...[
            for (var i = 0; i < pageRows.length; i++) ...[
              _scorecard(pageRows[i], i),
              const SizedBox(height: 10),
            ],
            ViewTableButton(onPressed: () => setState(() => _table = true)),
          ] else ...[
            TableViewBar(text: 'Table view • Scroll for more', onCards: () => setState(() => _table = false)),
            TrackerTable(
              sort: _sort,
              onSort: (k) => setState(() {
                _sort = toggleSort(k, _sort);
                _page = 1;
              }),
              columns: const [
                TCol('Date', sortKey: 'date', width: 100),
                TCol('Type', sortKey: 'type', width: 110),
                TCol('Description', sortKey: 'description', width: 220),
                TCol('In', sortKey: 'in', right: true, width: 80),
                TCol('Out', sortKey: 'out', right: true, width: 80),
                TCol('Actions', right: true, width: 100),
              ],
              rows: [
                for (final r in pageRows)
                  [
                    cellText(r.date.isEmpty ? '—' : trackerDate(r.date), bold: true),
                    cellText(r.type),
                    cellText(r.description),
                    cellText(r.inQty > 0 ? loc(r.inQty) : '—', color: TColors.emerald600),
                    cellText(r.outQty > 0 ? loc(r.outQty) : '—', color: TColors.red600),
                    r.type == 'Adjustment'
                        ? rowActions(onEdit: () => _openAdjustment(r), onDelete: () => _delete(r))
                        : const Text('—', style: TextStyle(color: TColors.slate300)),
                  ],
              ],
              footer: [
                Text.rich(TextSpan(children: [
                  TextSpan(
                      text: _filtersActive ? 'Filtered total' : 'Total',
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  TextSpan(
                      text: ' (${loc(sorted.length)} ${sorted.length == 1 ? 'row' : 'rows'})',
                      style: const TextStyle(color: TColors.slate500)),
                ])),
                const SizedBox(),
                const SizedBox(),
                cellText(loc(inTotal), color: TColors.emerald700, bold: true),
                cellText(loc(outTotal), color: TColors.red700, bold: true),
                const SizedBox(),
              ],
            ),
          ],
          if (sorted.isNotEmpty)
            TrackerPager(
              total: sorted.length,
              page: _page,
              pageSize: _pageSize,
              onPage: (p) => setState(() => _page = p),
              onPageSize: (s) => setState(() {
                _pageSize = s;
                _page = 1;
              }),
            ),
        ],
      ),
    );
  }

  Widget _scorecard(StockLedgerRow r, int i) {
    final isAdj = r.type == 'Adjustment';
    return LedgerScorecard(
      key: ValueKey(r.sortKey),
      index: i,
      title: r.date.isEmpty ? '—' : trackerDate(r.date),
      badge: r.type,
      boxes: [
        ScoreBox('In', r.inQty > 0 ? loc(r.inQty) : '—', ScoreTone.emerald),
        ScoreBox('Out', r.outQty > 0 ? loc(r.outQty) : '—', ScoreTone.red),
      ],
      details: [('Description', Text(r.description))],
      // Only adjustments can be edited or removed here; every other row
      // belongs to the record that posted it.
      actions: isAdj
          ? [
              scoreAction('Edit', Icons.edit_outlined, () => _openAdjustment(r)),
              scoreAction('Delete', Icons.delete_outline, () => _delete(r), danger: true),
            ]
          : const [],
    );
  }
}
