import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/buttons.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../shared/business_dates.dart';
import '../reports/report_format.dart';
import '../reports/report_routes.dart';
import 'tracker_logic.dart';
import 'tracker_widgets.dart';

/// Everything the two halves say differently (the web's COPY table).
class _Copy {
  const _Copy({
    required this.href,
    required this.title,
    required this.noun,
    required this.blurb,
    required this.links,
    required this.accentBg,
    required this.accentBorder,
    required this.iconBg,
    required this.iconFg,
    required this.emptyLedger,
    required this.inSource,
    required this.outUse,
    required this.manualAdjustments,
  });
  final String href;
  final String title;
  final String noun;
  final List<InlineSpan> blurb;
  final List<(String, String)> links;
  final Color accentBg, accentBorder, iconBg, iconFg;
  final List<InlineSpan> emptyLedger;
  final String inSource, outUse;
  final bool manualAdjustments;
}

final _copy = {
  FeedKind.finishedFeed: _Copy(
    href: '/feed-tracker',
    title: 'Feed at hand / Feed left',
    noun: 'Feed',
    blurb: [
      b('Feed left'),
      t(' (same idea as feed at hand) is the running difference: '),
      b('IN − OUT'),
      t('. '),
      b('IN'),
      t(' = finished feed bought in or produced by a feed batch; '),
      b('OUT'),
      t(' = feed fed to flocks. Feed ingredients are tracked separately on the Ingredients only tracker.'),
    ],
    links: const [
      ('/poultry-raw-materials', 'Raw Materials (purchases)'),
      ('/feed-usage', 'Feed usage (record OUT)'),
      ('/feed-ingredient-tracker', 'Ingredients only tracker'),
    ],
    accentBg: const Color(0x66ECFDF5),
    accentBorder: TColors.emerald200,
    iconBg: TColors.emerald100,
    iconFg: TColors.emerald800,
    emptyLedger: [
      t('No ledger rows yet. Add items with category '),
      b('Finished Feed'),
      t(' on Raw Materials & Supplies and record their purchases, or produce feed on Feed Production.'),
    ],
    inSource: 'Every movement that added finished feed to stock — purchases, feed produced by a batch, and corrections.',
    outUse: 'Every movement that took finished feed out of stock — what flocks ate, and corrections.',
    manualAdjustments: true,
  ),
  FeedKind.ingredient: _Copy(
    href: '/feed-ingredient-tracker',
    title: 'Ingredients at hand / Ingredients left',
    noun: 'Ingredients',
    blurb: [
      b('Ingredients left'),
      t(' is the running difference: '),
      b('IN − OUT'),
      t('. '),
      b('IN'),
      t(' = ingredients bought into the store; '),
      b('OUT'),
      t(' = ingredients drawn into a feed-production batch, or fed to a flock directly. The finished feed those batches make is tracked on the Feed tracker.'),
    ],
    links: const [
      ('/poultry-raw-materials', 'Raw Materials (purchases)'),
      ('/poultry-feed-production', 'Feed Production (record OUT)'),
      ('/feed-tracker', 'Feed tracker'),
    ],
    accentBg: const Color(0x66FFFBEB),
    accentBorder: TColors.amber200,
    iconBg: TColors.amber100,
    iconFg: TColors.amber800,
    emptyLedger: [
      t('No ledger rows yet. Add items with category '),
      b('Feed Ingredient'),
      t(' on Raw Materials & Supplies and record their purchases; usage appears when a feed batch draws them.'),
    ],
    inSource:
        'Every movement that added ingredients to the store — purchases, ingredients bought during a batch, and corrections.',
    outUse: 'Every movement that took ingredients out — feed-production draws, flock feeding, and corrections.',
    manualAdjustments: false,
  ),
};

/// Poultry → Trackers → Feed tracker (`kind: finishedFeed`, /feed-tracker) and
/// Ingredients only tracker (`kind: ingredient`, /feed-ingredient-tracker): one
/// screen, as the web's `components/poultry/feed-stock-tracker.tsx` is one
/// component, so the two halves cannot drift apart.
///
/// Built from the raw-material store — purchases in (in STOCK units), usage
/// out, adjustments either way — so its balance is the stock on Raw Materials
/// & Supplies. Only finished feed carries the whole-farm kg correction tool.
class FeedStockTrackerScreen extends StatefulWidget {
  const FeedStockTrackerScreen({super.key, required this.session, required this.company, required this.kind});
  final Session session;
  final Company company;
  final FeedKind kind;

  @override
  State<FeedStockTrackerScreen> createState() => _FeedStockTrackerScreenState();
}

class _FeedStockTrackerScreenState extends State<FeedStockTrackerScreen> {
  List<Map> _items = [], _purchases = [], _usage = [], _rmAdj = [], _feedAdj = [];
  bool _loading = true;
  bool _refreshing = false;
  String _error = '';
  FarmMoney _money = const FarmMoney();

  String _typeFilter = 'ALL';
  final _desc = TextEditingController();
  String _from = '', _to = '';
  SortState _sort = (key: 'date', dir: SortDir.desc);
  int _page = 1;
  int _pageSize = trackerPageSizeDefault;
  bool _table = false;

  FeedLedger? _ledger;

  _Copy get copy => _copy[widget.kind]!;
  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _money = m);
    });
    _load();
  }

  @override
  void dispose() {
    _desc.dispose();
    super.dispose();
  }

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
    final fq = {'farmId': _farmId};
    Future<List<Map>?> get(String path) async {
      try {
        return rowsOf(await _api.get(path, query: fq));
      } on ApiException {
        return null;
      }
    }

    final r = await Future.wait([
      // Manual kg corrections are a whole-farm FINISHED feed figure.
      copy.manualAdjustments ? get('/api/FeedInventoryAdjustment') : Future.value(<Map>[]),
      get('/api/Poultry/raw-material-items'),
      get('/api/Poultry/raw-material-purchases'),
      get('/api/Poultry/raw-material-usage/history'),
      get('/api/Poultry/raw-material-adjustments'),
    ]);
    if (!mounted) return;
    setState(() {
      // Items decide which movements are in scope, so a failure there is an
      // error, not an empty page.
      if (r[1] == null) {
        _items = [];
        _error = 'Could not load the raw-material store. Check the connection and refresh.';
      } else {
        _items = r[1]!;
        _error = '';
      }
      _feedAdj = r[0] ?? [];
      _purchases = r[2] ?? [];
      _usage = r[3] ?? [];
      _rmAdj = r[4] ?? [];
      _ledger = buildFeedStockLedger(
        kind: widget.kind,
        items: _items,
        purchases: _purchases,
        usages: _usage,
        adjustments: _rmAdj,
        manualAdjustments: _feedAdj,
      );
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

  List<String> get _scopeUnits {
    final seen = <String>[];
    for (final i in _items) {
      if (feedItemKind(i['category']) != widget.kind) continue;
      final u = tStr(i['unitOfMeasure']).trim();
      if (u.isNotEmpty && !seen.contains(u)) seen.add(u);
    }
    return seen;
  }

  String? get _unitLabel => _scopeUnits.length == 1 ? _scopeUnits.first : null;
  String get _unitBit => _unitLabel != null ? ' (${_unitLabel!.toLowerCase()})' : '';

  List<StockLedgerRow> get _sorted {
    var list = [..._all];
    if (_typeFilter != 'ALL') list = list.where((r) => r.type == _typeFilter).toList();
    final q = _desc.text.trim().toLowerCase();
    if (q.isNotEmpty) list = list.where((r) => r.description.toLowerCase().contains(q)).toList();
    if (_from.isNotEmpty) list = list.where((r) => localDateKey(r.date).compareTo(_from) >= 0).toList();
    if (_to.isNotEmpty) list = list.where((r) => localDateKey(r.date).compareTo(_to) <= 0).toList();
    return sortRows(list, _sort, (r, k) => switch (k) {
          'date' => r.seq,
          'type' => r.type,
          'description' => r.description,
          'in' => r.inQty,
          'out' => r.outQty,
          'balance' => r.balance,
          'recognized' => r.recognized,
          _ => null,
        });
  }

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
    trackerToast(context, 'Filters cleared');
  }

  String q1(num n) => loc(n, 1);
  String q2(num n) => loc(n, 2);

  // ------------------------------------------------------------ adjustments

  int? _adjId(StockLedgerRow r) => r.sortKey.startsWith('feedadj_') ? int.tryParse(r.sortKey.substring(8)) : null;

  Future<void> _openAdjustment([StockLedgerRow? row]) async {
    Map? existing;
    if (row != null) {
      final id = _adjId(row);
      existing = _feedAdj.where((a) => tIntOrNull(a['adjustmentId']) == id).firstOrNull;
      if (existing == null) return;
    }
    final today = isoDay(DateTime.now());
    final form = existing == null
        ? AdjustmentForm('Correction', today, '', '')
        : AdjustmentForm(
            tStr(existing['adjustmentType']),
            tStr(existing['adjustmentDate']).length >= 10 ? tStr(existing['adjustmentDate']).substring(0, 10) : today,
            jsNum(tNum(existing['feedDeltaKg'])),
            tStr(existing['description']),
          );
    if (!adjustmentTypes.any((t) => t.$1 == form.type)) form.type = 'Correction';
    final editingId = existing == null ? null : tIntOrNull(existing['adjustmentId']);
    await showDialog<void>(
      context: context,
      builder: (_) => AdjustmentDialog(
        title: editingId != null ? 'Edit feed adjustment' : 'Feed inventory adjustment',
        description:
            'Adjust kg on hand without changing inventory items or feed usage records. Positive adds kg; negative subtracts.',
        deltaLabel: 'Feed change (kg)',
        deltaHint: 'e.g. 100 or -25.5',
        decimal: true,
        initial: form,
        editing: editingId != null,
        onSave: (f) => _save(f, editingId),
      ),
    );
  }

  Future<bool> _save(AdjustmentForm f, int? editingId) async {
    final delta = double.tryParse(f.delta.trim().replaceFirst(',', '.'));
    if (delta == null || !delta.isFinite || delta == 0) {
      trackerToast(context, 'Check the form',
          description:
              'Enter feed change in kg — positive adds to on-hand feed, negative subtracts. Use decimals if needed; zero is not allowed.',
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
      'FeedDeltaKg': delta,
      'Description': f.description.trim().isEmpty ? null : f.description.trim(),
    };
    try {
      if (editingId != null) {
        await _api.put('/api/FeedInventoryAdjustment/$editingId', body: {'AdjustmentId': editingId, ...body});
        if (mounted) trackerToast(context, 'Adjustment updated');
      } else {
        await _api.post('/api/FeedInventoryAdjustment', body: body);
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
        title: 'Delete feed inventory adjustment?',
        description: 'This adjustment will be permanently removed from the ledger.');
    if (!ok || !mounted) return;
    try {
      await _api.delete('/api/FeedInventoryAdjustment/$id?farmId=${Uri.encodeQueryComponent(_farmId)}');
      if (mounted) trackerToast(context, 'Adjustment removed');
      _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Delete failed', description: e.message, error: true);
    }
  }

  void _breakdown(int productionRecordId) => showCostBreakdown(context,
      session: widget.session,
      company: widget.company,
      productionRecordId: productionRecordId,
      money: _money,
      title: 'Feed cost breakdown');

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: copy.href);
    final units = _scopeUnits;
    return Scaffold(
      appBar: AppBar(
        leading: lead.leading,
        leadingWidth: lead.width,
        title: Text(widget.kind == FeedKind.finishedFeed ? 'Feed tracker' : 'Ingredients only tracker'),
        actions: [RefreshAction(busy: _refreshing || _loading, onPressed: _refresh)],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            TrackerHeader(
              icon: Icons.grass,
              iconBg: copy.iconBg,
              iconFg: copy.iconFg,
              title: copy.title,
              blurbSpans: copy.blurb,
              links: copy.links,
              session: widget.session,
              company: widget.company,
            ),
            const SizedBox(height: 16),
            if (_error.isNotEmpty) ...[TrackerBanner.error(_error), const SizedBox(height: 12)],
            // One total cannot be in two units.
            if (!_loading && units.length > 1) ...[
              TrackerBanner.warn('', spans: [
                t('These items are stocked in more than one unit (${units.join(', ')}), so the totals below add quantities that are not the same size. For figures kept apart by unit, use the '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: InkWell(
                    onTap: () => openAppHref(context, widget.session, widget.company, '/feed-inventory-tracker',
                        label: 'Feed inventory tracker'),
                    child: const Text('feed inventory tracker',
                        style: TextStyle(
                            fontSize: 13,
                            color: TColors.amber900,
                            fontWeight: FontWeight.w500,
                            decoration: TextDecoration.underline)),
                  ),
                ),
                t('.'),
              ]),
              const SizedBox(height: 12),
            ],
            if (_loading)
              TrackerLoading('Loading ${copy.noun.toLowerCase()} left…')
            else ...[
              _summaryCard(),
              const SizedBox(height: 16),
              ..._breakdownCards(),
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
    final atHand = l.atHand;
    final noun = copy.noun;
    return TCard(
      bg: copy.accentBg,
      border: copy.accentBorder,
      eyebrow: '$noun left · $noun at hand',
      titleWidget: Text('IN − OUT = ${_unitLabel != null ? '${_unitLabel!.toLowerCase()} on hand' : 'on hand'}',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: TColors.slate800)),
      trailing: copy.manualAdjustments
          ? AppButton(
              label: 'Add adjustment',
              icon: Icons.add,
              variant: AppButtonVariant.outline,
              size: AppButtonSize.sm,
              onPressed: () => _openAdjustment(),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TileGrid([
            TileData('$noun left / at hand$_unitBit', q1(atHand),
                color: atHand < 0 ? TColors.red600 : TColors.slate900,
                action: CopyButton(
                  value: jsNum(((atHand + 2.220446049250313e-16) * 100).round() / 100),
                  label: 'Copy ${noun.toLowerCase()} left',
                  toastText: '$noun left / at hand$_unitBit copied to clipboard',
                )),
            TileData('$noun purchased$_unitBit', q1(sumIn((r) => r.type == 'Purchase IN')), color: TColors.sky700),
            TileData('$noun used$_unitBit', q1(sumOut((r) => r.type == 'Usage OUT')), color: TColors.amber800),
            TileData('Last ledger event', rows.isEmpty ? '—' : trackerDate(l.lastUpdatedIso),
                color: TColors.slate600, sub: rows.isEmpty ? '—' : trackerTime(l.lastUpdatedIso)),
            TileData('$noun in (adjustments)', q1(sumIn((r) => adjust.hasMatch(r.type))), color: TColors.emerald700),
            TileData('$noun out (adjustments)', q1(sumOut((r) => adjust.hasMatch(r.type))), color: TColors.rose600),
            TileData('Total IN (ledger)', q1(l.totalIn), color: TColors.emerald800),
            TileData('Total OUT (ledger)', q1(l.totalOut), color: TColors.slate800),
          ]),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(children: [
              t('Built from the same three movements that maintain stock on Raw Materials & Supplies — purchases in, usage out, adjustments either way — so this balance and that page agree. Purchases are counted in the unit the item is STOCKED in, not the unit it was bought in.'),
              if (copy.manualAdjustments) ...[
                t(' Use '),
                b('Add adjustment'),
                t(' to align the figure after a stocktake (requires DB migration 014 on the farm API database).'),
              ],
            ]),
            style: const TextStyle(fontSize: 12, color: TColors.slate500),
          ),
          if (atHand < 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: TColors.amber100,
                border: Border.all(color: TColors.amber200),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text.rich(
                TextSpan(children: [
                  t('Negative balance usually means more usage was logged than purchases — check the purchase and usage dates, or run '),
                  b('Recalculate stock'),
                  t(' on Raw Materials & Supplies.'),
                ]),
                style: const TextStyle(fontSize: 12, color: TColors.amber900),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _breakdownCards() {
    final rows = _all;
    final l = _ledger!;
    final noun = copy.noun;
    final inBySource = groupLedgerByType(rows, true, feedMoveLabels);
    final outByUse = groupLedgerByType(rows, false, feedMoveLabels);
    if (inBySource.isEmpty && outByUse.isEmpty) return const [];
    String keyOf(StockLedgerRow r) => r.itemName ?? 'Not item-specific';
    final leftByItem = groupLedgerByNet(rows, keyOf);
    final leftTotal = leftByItem.fold<num>(0, (s, bk) => s + bk.amount);
    return [
      BreakdownSection(cards: [
        FlowBreakdownCard(
          title: '$noun left by item',
          inDirection: true,
          buckets: leftByItem,
          total: leftTotal,
          fmt: q1,
          description:
              'What is still on hand, item by item — everything in minus everything out. Items with none left are not listed.',
          emptyText: 'No ${noun.toLowerCase()} left on any item.',
        ),
        FlowBreakdownCard(
          title: '$noun in by item',
          inDirection: true,
          buckets: groupLedgerBy(rows, true, keyOf),
          total: l.totalIn,
          fmt: q1,
          description: '$noun in, grouped by which item it was.',
          emptyText: 'No ${noun.toLowerCase()} has come in yet.',
        ),
        FlowBreakdownCard(
          title: '$noun out by item',
          inDirection: false,
          buckets: groupLedgerBy(rows, false, keyOf),
          total: l.totalOut,
          fmt: q1,
          description: '$noun out, grouped by which item it was — what is actually being used, and how fast.',
          emptyText: 'No ${noun.toLowerCase()} has gone out yet.',
        ),
        FlowBreakdownCard(
          title: '$noun in by source',
          inDirection: true,
          buckets: inBySource,
          total: l.totalIn,
          fmt: q1,
          description: copy.inSource,
          emptyText: 'No ${noun.toLowerCase()} has come in yet.',
        ),
        FlowBreakdownCard(
          title: '$noun out by use',
          inDirection: false,
          buckets: outByUse,
          total: l.totalOut,
          fmt: q1,
          description: copy.outUse,
          emptyText: 'No ${noun.toLowerCase()} has gone out yet.',
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
    // Only live rows: a reversed usage's money was already taken back.
    final recTotal = sorted.fold<num>(0, (s, r) => s + (r.reversed == true ? 0 : (r.recognized ?? 0)));
    final unitBit = _unitBit;

    return TCard(
      title: '${copy.noun} stock ledger',
      descriptionSpans: [
        t('Purchases in, consumption out, straight from the raw-material store — so this balance matches the stock on Raw Materials & Supplies. For one item at a time, with its own opening and closing, use the '),
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: InkWell(
            onTap: () => openAppHref(context, widget.session, widget.company, '/feed-inventory-tracker',
                label: 'Feed inventory tracker'),
            child: const Text('feed inventory tracker',
                style: TextStyle(fontSize: 12.5, color: TColors.slate500, decoration: TextDecoration.underline)),
          ),
        ),
        t('. Filter the table below.'),
      ],
      headerExtra: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          children: [
            AppSelect<String>(
              value: _typeFilter,
              hintText: 'Type',
              items: [
                const AppSelectItem(value: 'ALL', label: 'All types'),
                for (final ty in types) AppSelectItem(value: ty, label: ty),
              ],
              onChanged: (v) => setState(() {
                _typeFilter = v ?? 'ALL';
                _page = 1;
              }),
            ),
            const SizedBox(height: 8),
            AppInput(controller: _desc, hintText: 'Description…', onChanged: (_) => setState(() => _page = 1)),
            const SizedBox(height: 8),
            filterRow([
              FilterDate(value: _from, hint: 'From date', onChanged: (v) => setState(() {
                    _from = v;
                    _page = 1;
                  })),
              FilterDate(value: _to, hint: 'To date', onChanged: (v) => setState(() {
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
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Text.rich(TextSpan(children: copy.emptyLedger),
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: TColors.slate600)),
            )
          else if (!_table) ...[
            for (var i = 0; i < pageRows.length; i++) ...[
              _scorecard(pageRows[i], i, unitBit),
              const SizedBox(height: 10),
            ],
            ViewTableButton(onPressed: () => setState(() => _table = true)),
          ] else ...[
            TableViewBar(onCards: () => setState(() => _table = false)),
            TrackerTable(
              sort: _sort,
              onSort: (k) => setState(() {
                _sort = toggleSort(k, _sort);
                _page = 1;
              }),
              columns: [
                const TCol('Date', sortKey: 'date', width: 100),
                const TCol('Type', sortKey: 'type', width: 110),
                const TCol('Description', sortKey: 'description', width: 260),
                TCol('In$unitBit', sortKey: 'in', right: true, width: 90),
                TCol('Out$unitBit', sortKey: 'out', right: true, width: 90),
                TCol('Balance$unitBit', sortKey: 'balance', right: true, width: 110),
                const TCol('Cost recognised', sortKey: 'recognized', right: true, width: 170),
                if (copy.manualAdjustments) const TCol('Actions', right: true, width: 100),
              ],
              rows: [
                for (final r in pageRows)
                  [
                    cellText(trackerDate(r.date), bold: true),
                    cellText(r.type),
                    cellText(r.description),
                    cellText(r.inQty > 0 ? q2(r.inQty) : '—', color: TColors.emerald600),
                    cellText(r.outQty > 0 ? q2(r.outQty) : '—', color: TColors.red600),
                    cellText(q2(r.balance), bold: true),
                    RecognizedCostCell(
                      cost: r.cost,
                      recognized: r.recognized,
                      reversed: r.reversed == true,
                      money: _money,
                      onBreakdown: r.productionRecordId == null ? null : () => _breakdown(r.productionRecordId!),
                    ),
                    if (copy.manualAdjustments)
                      r.sortKey.startsWith('feedadj_')
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
                cellText(q2(inTotal), color: TColors.emerald700, bold: true),
                cellText(q2(outTotal), color: TColors.red700, bold: true),
                const SizedBox(),
                cellText(_money(recTotal), color: TColors.amber700, bold: true),
                if (copy.manualAdjustments) const SizedBox(),
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

  Widget _scorecard(StockLedgerRow r, int i, String unitBit) {
    final isAdj = r.sortKey.startsWith('feedadj_');
    final unit = _unitLabel;
    return LedgerScorecard(
      key: ValueKey(r.sortKey),
      index: i,
      title: trackerDate(r.date),
      badge: r.type,
      boxes: [
        ScoreBox('In$unitBit', r.inQty > 0 ? q2(r.inQty) : '—', ScoreTone.emerald),
        ScoreBox('Out$unitBit', r.outQty > 0 ? q2(r.outQty) : '—', ScoreTone.red),
      ],
      details: [
        ('Description', Text(r.description)),
        ('Balance', Text('${q2(r.balance)}${unit != null ? ' ${unit.toLowerCase()}' : ''}')),
      ],
      actions: isAdj
          ? [
              scoreAction('Edit', Icons.edit_outlined, () => _openAdjustment(r)),
              scoreAction('Delete', Icons.delete_outline, () => _delete(r), danger: true),
            ]
          : const [],
    );
  }
}
