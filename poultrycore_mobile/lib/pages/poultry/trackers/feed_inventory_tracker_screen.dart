import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/buttons.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../reports/report_format.dart';
import '../reports/report_routes.dart';
import 'tracker_logic.dart';
import 'tracker_widgets.dart';

const _kindLabel = {FeedKind.ingredient: 'Feed ingredients', FeedKind.finishedFeed: 'Finished feed'};

/// The "All ..." entry in the item picker; never collides with a real id.
const _allItems = -1;

/// Poultry → Trackers → Feed inventory tracker, as
/// `app/feed-inventory-tracker/page.tsx`: ONE item (or one half rolled up) is
/// the page's subject, a hero card carries its position for the period, and
/// the chronological ledger sits underneath. The arithmetic is
/// `buildFeedItemMovements` / `buildFeedItemPositions`, the same identity
/// migration 175 maintains stock with. [initialItemId] is the web's ?itemId=
/// deep link (the Track link on Raw Materials).
class FeedInventoryTrackerScreen extends StatefulWidget {
  const FeedInventoryTrackerScreen({super.key, required this.session, required this.company, this.initialItemId});
  final Session session;
  final Company company;
  final int? initialItemId;

  @override
  State<FeedInventoryTrackerScreen> createState() => _FeedInventoryTrackerScreenState();
}

class _FeedInventoryTrackerScreenState extends State<FeedInventoryTrackerScreen> {
  late DateRange _default = defaultReportRange('last30');
  late String _from = _default.from;
  late String _to = _default.to;

  List<Map> _items = [], _purchases = [], _usages = [], _adjustments = [];
  Map<int, List<FeedItemMovement>> _moves = {};

  // Finished feed leads; the deep link still wins.
  FeedKind _kind = FeedKind.finishedFeed;
  int? _selection;
  bool _appliedQueryItem = false;

  bool _loading = true;
  bool _refreshing = false;
  String _error = '';
  FarmMoney _money = const FarmMoney();

  String _typeFilter = 'ALL';
  final _desc = TextEditingController();
  int _page = 1;
  int _pageSize = trackerPageSizeDefault;
  SortState _sort = (key: 'timestamp', dir: SortDir.desc);
  bool _table = false;

  ApiClient get _api => widget.session.farmClient;

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
    final fq = {'farmId': widget.company.farmId};
    Future<List<Map>> soft(String p) async {
      try {
        return rowsOf(await _api.get(p, query: fq));
      } on ApiException {
        return [];
      }
    }

    setState(() => _error = '');
    try {
      // The whole history: an opening balance is the sum of everything before
      // the window, so the window cannot be pushed down to the endpoints.
      final r = await Future.wait([
        _api.get('/api/Poultry/raw-material-items', query: fq).then(rowsOf),
        soft('/api/Poultry/raw-material-purchases'),
        soft('/api/Poultry/raw-material-usage/history'),
        soft('/api/Poultry/raw-material-adjustments'),
      ]);
      if (!mounted) return;
      setState(() {
        _items = r[0];
        _purchases = r[1];
        _usages = r[2];
        _adjustments = r[3];
        _moves = buildFeedItemMovements(_items, _purchases, _usages, _adjustments);
        _pickSelection();
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) {
      setState(() {
        _loading = false;
        _refreshing = false;
      });
    }
  }

  void _refresh() {
    setState(() => _refreshing = true);
    _load();
  }

  // ------------------------------------------------------------ derived

  List<FeedItemPosition> get _positions => buildFeedItemPositions(_items, _moves, _from, _to);
  List<FeedItemPosition> _ofKind(List<FeedItemPosition> ps) => [for (final p in ps) if (p.kind == _kind) p];

  /// Preselect from the deep link, else the item with the most movement in
  /// the period — an empty ledger is a poor landing. "All" survives.
  void _pickSelection() {
    final positions = _positions;
    if (positions.isEmpty) return;
    if (!_appliedQueryItem) {
      _appliedQueryItem = true;
      final match = positions.where((p) => p.itemId == widget.initialItemId).firstOrNull;
      if (match != null) {
        _kind = match.kind;
        _selection = match.itemId;
        return;
      }
    }
    if (_selection == _allItems) return;
    final ofKind = _ofKind(positions);
    if (_selection != null && ofKind.any((p) => p.itemId == _selection)) return;
    final busiest = [...ofKind]..sort((a, b) => b.movementCount - a.movementCount);
    _selection = busiest.firstOrNull?.itemId;
  }

  void _clearFilters() {
    setState(() {
      _typeFilter = 'ALL';
      _desc.clear();
      _default = defaultReportRange('last30');
      _from = _default.from;
      _to = _default.to;
      _page = 1;
    });
  }

  String qty(num n) => loc(n, 3);

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/feed-inventory-tracker');
    return Scaffold(
      appBar: AppBar(
        leading: lead.leading,
        leadingWidth: lead.width,
        title: const Text('Feed inventory tracker'),
        actions: [RefreshAction(busy: _refreshing || _loading, onPressed: _refresh)],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            TrackerHeader(
              icon: Icons.history,
              iconBg: TColors.amber100,
              iconFg: TColors.amber700,
              title: 'Feed inventory tracker',
              blurb:
                  "Ledger from purchases, feed production, flock consumption and adjustments — every movement behind one ingredient's or finished feed's stock figure.",
              session: widget.session,
              company: widget.company,
            ),
            const SizedBox(height: 16),
            if (_error.isNotEmpty) ...[TrackerBanner.error(_error), const SizedBox(height: 12)],
            ..._body(),
          ],
        ),
      ),
    );
  }

  Widget _rawMaterialsLink(String text, {Color color = TColors.amber900}) => InkWell(
        onTap: () => openAppHref(context, widget.session, widget.company, '/poultry-raw-materials',
            label: 'Raw Materials & Supplies'),
        child: Text(text,
            style:
                TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w500, decoration: TextDecoration.underline)),
      );

  WidgetSpan _span(Widget w) =>
      WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, child: w);

  List<Widget> _body() {
    if (_loading) return const [TrackerLoading('Loading feed inventory…')];
    final positions = _positions;
    if (positions.isEmpty) {
      return [
        TCard(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Text.rich(
              TextSpan(children: [
                t('No feed items yet. Add items with category '),
                b('Feed Ingredient'),
                t(' or '),
                b('Finished Feed'),
                t(' on '),
                _span(_rawMaterialsLink('Raw Materials & Supplies', color: TColors.amber700)),
                t(' to start tracking them.'),
              ]),
              textAlign: TextAlign.center,
              style: const TextStyle(color: TColors.slate600),
            ),
          ),
        ),
      ];
    }

    final ofKind = _ofKind(positions);
    final counts = {
      FeedKind.ingredient: positions.where((p) => p.kind == FeedKind.ingredient).length,
      FeedKind.finishedFeed: positions.where((p) => p.kind == FeedKind.finishedFeed).length,
    };
    final isAll = _selection == _allItems;
    final selected = (_selection != null && !isAll) ? positions.where((p) => p.itemId == _selection).firstOrNull : null;
    final unitTotals = summariseFeedPositions(ofKind);
    final driftItems = unitTotals.fold<int>(0, (n, x) => n + x.driftItems);
    final moves = isAll ? unitTotals.fold<int>(0, (n, x) => n + x.movementCount) : selected?.movementCount;

    return [
      // The page's SUBJECT: kind + item.
      TCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<FeedKind>(
              showSelectedIcon: false,
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                backgroundColor: WidgetStateProperty.resolveWith(
                    (s) => s.contains(WidgetState.selected) ? TColors.amber600 : null),
                foregroundColor: WidgetStateProperty.resolveWith(
                    (s) => s.contains(WidgetState.selected) ? Colors.white : TColors.slate600),
              ),
              segments: [
                for (final k in const [FeedKind.finishedFeed, FeedKind.ingredient])
                  ButtonSegment(value: k, label: Text('${_kindLabel[k]}  ${counts[k]}')),
              ],
              selected: {_kind},
              onSelectionChanged: (s) {
                final k = s.first;
                if (k == _kind) return;
                setState(() {
                  _kind = k;
                  // Dropped so this half's busiest item is picked; "All" is kept.
                  if (_selection != _allItems) _selection = null;
                  _page = 1;
                  _pickSelection();
                });
              },
            ),
            const SizedBox(height: 10),
            AppSelect<int>(
              value: _selection,
              hintText: 'Pick ${_kind == FeedKind.ingredient ? 'an ingredient' : 'a finished feed'}',
              items: [
                if (ofKind.isNotEmpty)
                  AppSelectItem(value: _allItems, label: 'All ${_kindLabel[_kind]!.toLowerCase()} (${ofKind.length})'),
                for (final p in ofKind)
                  AppSelectItem(value: p.itemId, label: '${p.itemName}${p.isActive ? '' : ' (inactive)'}'),
              ],
              onChanged: (v) => setState(() {
                _selection = v;
                _page = 1;
              }),
            ),
            if (moves != null) ...[
              const SizedBox(height: 6),
              Text(moves == 1 ? '1 movement in this period' : '${loc(moves)} movements in this period',
                  style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            ],
          ],
        ),
      ),
      const SizedBox(height: 12),
      if (ofKind.isEmpty) ...[
        TrackerBanner.info(
            'No ${_kindLabel[_kind]!.toLowerCase()} on this company yet. Items are picked up from their category on Raw Materials & Supplies.'),
        const SizedBox(height: 12),
      ],
      if (isAll && driftItems > 0) ...[
        TrackerBanner.warn('', spans: [
          t(driftItems == 1
              ? '1 of these items is recorded at a stock figure that disagrees with its own'
              : '$driftItems of these items are recorded at stock figures that disagree with their own'),
          t(' purchases, usage and adjustments, so '),
          b('In stock now'),
          t(' and '),
          b('Closing'),
          t(' below will not meet. Pick the item to see the difference, or run '),
          b('Recalculate stock'),
          t(' on '),
          _span(_rawMaterialsLink('Raw Materials & Supplies')),
          t('.'),
        ]),
        const SizedBox(height: 12),
      ],
      if (selected != null && selected.drift != 0) ...[
        TrackerBanner.warn('', spans: [
          b(selected.itemName),
          t(' is recorded as '),
          b('${qty(selected.onRecord)}${selected.unit.isNotEmpty ? ' ${selected.unit}' : ''}'),
          t(' in stock, but its purchases, usage and adjustments add up to '),
          b(qty(selected.derivedNow)),
          t(' — a difference of ${qty(selected.drift.abs())}. Run '),
          b('Recalculate stock'),
          t(' on '),
          _span(_rawMaterialsLink('Raw Materials & Supplies')),
          t(' to bring the stored figure back in line with its own movements.'),
        ]),
        const SizedBox(height: 12),
      ],
      isAll ? _rollupCard(ofKind, unitTotals) : _heroCard(selected),
      const SizedBox(height: 16),
      _ledgerCard(ofKind, selected, isAll),
    ];
  }

  Widget _rollupCard(List<FeedItemPosition> ofKind, List<FeedUnitTotals> unitTotals) {
    return TCard(
      bg: const Color(0x80FFFBEB),
      border: TColors.amber200,
      eyebrow: 'Stock for the selected period',
      titleWidget: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Icon(Icons.grass, size: 16, color: TColors.amber700),
          Text('All ${_kindLabel[_kind]!.toLowerCase()}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: TColors.slate800)),
          TBadge('${ofKind.length} ${ofKind.length == 1 ? 'item' : 'items'}',
              bg: Colors.white, fg: TColors.slate700, border: TColors.slate200),
        ],
      ),
      child: unitTotals.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Nothing to total yet.', style: TextStyle(fontSize: 13, color: TColors.slate600)),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TrackerTable(
                  columns: const [
                    TCol('Unit', width: 100),
                    TCol('Items', right: true, width: 60),
                    TCol('Opening', right: true, width: 90),
                    TCol('In', right: true, width: 90),
                    TCol('Out', right: true, width: 90),
                    TCol('Closing', right: true, width: 100),
                    TCol('In stock now', right: true, width: 110),
                  ],
                  rows: [
                    for (final x in unitTotals)
                      [
                        cellText(x.unit.isEmpty ? 'No unit set' : x.unit, bold: true),
                        cellText('${x.items}', color: TColors.slate600),
                        cellText(qty(x.opening)),
                        cellText(qty(x.inQty), color: TColors.emerald700),
                        cellText(qty(x.outQty), color: TColors.rose700),
                        cellText(qty(x.closing), bold: true, color: x.closing < 0 ? TColors.red600 : TColors.slate900),
                        cellText(qty(x.onRecord)),
                      ],
                  ],
                ),
                if (unitTotals.length > 1) ...[
                  const SizedBox(height: 10),
                  Text(
                    'One line per stocking unit: these items are held in ${unitTotals.length} different units, and a bag is not a kilogram — adding the lines together would give a figure with no unit, so they are kept apart.',
                    style: const TextStyle(fontSize: 11, color: TColors.slate600),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _heroCard(FeedItemPosition? s) {
    final unitBit = s != null && s.unit.isNotEmpty ? ' (${s.unit.toLowerCase()})' : '';
    final isLow = s != null && s.minimumStockAlert > 0 && s.closing <= s.minimumStockAlert;
    return TCard(
      bg: const Color(0x80FFFBEB),
      border: TColors.amber200,
      eyebrow: 'Stock for the selected period',
      titleWidget: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Icon(Icons.grass, size: 16, color: TColors.amber700),
          Text(s?.itemName ?? 'Pick an item',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: TColors.slate800)),
          if (s != null) TBadge(_kindLabel[s.kind]!, bg: Colors.white, fg: TColors.slate700, border: TColors.slate200),
          if (isLow) const TBadge('Low stock', bg: TColors.rose100, fg: TColors.rose800),
        ],
      ),
      child: TileGrid([
        TileData('Closing$unitBit', s == null ? '—' : qty(s.closing),
            color: (s?.closing ?? 0) < 0 ? TColors.red600 : TColors.slate900,
            sub: s != null && s.minimumStockAlert > 0 ? 'alert at ${qty(s.minimumStockAlert)}' : null),
        TileData('Opening', s == null ? '—' : qty(s.opening)),
        TileData('In', s == null ? '—' : qty(s.inQty), color: TColors.emerald700),
        TileData('Out', s == null ? '—' : qty(s.outQty), color: TColors.rose700),
        // What the item holds NOW — every other screen's number.
        TileData('In stock now', s == null ? '—' : qty(s.onRecord),
            sub: s == null ? null : (s.lastMovementDate != null ? 'last moved ${s.lastMovementDate}' : 'never moved')),
      ]),
    );
  }

  Widget _ledgerCard(List<FeedItemPosition> ofKind, FeedItemPosition? selected, bool isAll) {
    List<FeedItemMovement> decorate(FeedItemPosition p) => [
          for (final m in _moves[p.itemId] ?? const <FeedItemMovement>[])
            m
              ..itemName = p.itemName
              ..unit = p.unit,
        ];
    final movements = isAll ? [for (final p in ofKind) ...decorate(p)] : (selected != null ? decorate(selected) : <FeedItemMovement>[]);
    final windowRows = [
      for (final m in movements)
        if ((_from.isEmpty || m.date.compareTo(_from) >= 0) && (_to.isEmpty || m.date.compareTo(_to) <= 0)) m,
    ];
    final types = {for (final m in windowRows) if (m.label.isNotEmpty) m.label}.toList()..sort();
    final q = _desc.text.trim().toLowerCase();
    final ledgerRows = [
      for (final m in windowRows)
        if ((_typeFilter == 'ALL' || m.label == _typeFilter) &&
            (q.isEmpty || m.description.toLowerCase().contains(q) || m.label.toLowerCase().contains(q)))
          m,
    ];
    // One item: Date sorts on its own ledger order. Across items the
    // sequences are not comparable, so the roll-up uses the timestamp.
    final sorted = sortRows(ledgerRows, _sort, (r, k) => switch (k) {
          'timestamp' => isAll ? r.timestamp : r.seq,
          'itemName' => r.itemName,
          'label' => r.label,
          'description' => r.description,
          'inQty' => r.inQty,
          'outQty' => r.outQty,
          'cost' => r.cost,
          _ => null,
        });
    num tin = 0, tout = 0, tcost = 0;
    for (final r in sorted) {
      tin += r.inQty;
      tout += r.outQty;
      if (r.reversed != true) tcost += r.cost ?? 0;
    }
    final ledgerUnits = <String>[];
    for (final r in sorted) {
      final u = r.unit.trim();
      if (u.isNotEmpty && !ledgerUnits.contains(u)) ledgerUnits.add(u);
    }
    final mixed = ledgerUnits.length > 1;
    final pageRows = pageOf(sorted, _page, _pageSize);
    final period = rangeToPeriod(_from, _to);

    return TCard(
      title: 'Stock ledger',
      description: 'Chronological ledger; filter the table below',
      headerExtra: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          children: [
            AppSelect<String>(
              value: period,
              items: [
                for (final (group, opts) in periodGroups)
                  for (final (k, l) in opts) AppSelectItem(value: k, label: '$l  ·  $group'),
              ],
              onChanged: (k) {
                final r = k == null ? null : periodToRange(k);
                if (r != null) {
                  setState(() {
                    _from = r.from;
                    _to = r.to;
                    _page = 1;
                  });
                }
              },
            ),
            const SizedBox(height: 8),
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
              FilterDate(value: _from, hint: 'From', onChanged: (v) => setState(() => _from = v)),
              FilterDate(value: _to, hint: 'To', onChanged: (v) => setState(() => _to = v)),
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
          if (_selection == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Text('Pick an item to see its movements.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: TColors.slate600)),
            )
          else if (sorted.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Text(
                windowRows.isEmpty
                    ? 'No movements for ${isAll ? 'these items' : 'this item'} in the selected period.'
                    : 'No ledger rows match those filters.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: TColors.slate600),
              ),
            )
          else ...[
            if (!_table) ...[
              for (var i = 0; i < pageRows.length; i++) ...[
                _scorecard(pageRows[i], i, isAll),
                const SizedBox(height: 10),
              ],
              ViewTableButton(onPressed: () => setState(() => _table = true)),
            ] else ...[
              TableViewBar(onCards: () => setState(() => _table = false)),
              TrackerTable(
                sort: _sort,
                onSort: (k) => setState(() => _sort = toggleSort(k, _sort)),
                columns: [
                  const TCol('Date', sortKey: 'timestamp', width: 100),
                  if (isAll) const TCol('Item', sortKey: 'itemName', width: 140),
                  const TCol('Type', sortKey: 'label', width: 150),
                  const TCol('Description', sortKey: 'description', width: 260),
                  const TCol('In', sortKey: 'inQty', right: true, width: 90),
                  const TCol('Out', sortKey: 'outQty', right: true, width: 90),
                  TCol(isAll ? 'Item balance' : 'Balance', right: true, width: 110),
                  const TCol('Cost', sortKey: 'cost', right: true, width: 110),
                ],
                rows: [
                  for (final r in pageRows)
                    [
                      cellText(r.date.isEmpty ? '—' : r.date, bold: true),
                      if (isAll) cellText(r.itemName),
                      cellText(r.label),
                      cellText(r.description),
                      cellText(r.inQty > 0 ? qty(r.inQty) : '—', color: TColors.emerald600),
                      cellText(r.outQty > 0 ? qty(r.outQty) : '—', color: TColors.red600),
                      cellText(qty(r.balance), bold: true),
                      _costCell(r),
                    ],
                ],
                footer: [
                  Text.rich(TextSpan(children: [
                    const TextSpan(text: 'Totals', style: TextStyle(fontWeight: FontWeight.w500)),
                    TextSpan(
                        text:
                            ' (${loc(sorted.length)}${sorted.length == 1 ? ' movement' : ' movements'}${mixed ? ' · ${ledgerUnits.join(', ')} — not totalled' : ''})',
                        style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                  ])),
                  if (isAll) const SizedBox(),
                  const SizedBox(),
                  const SizedBox(),
                  cellText(mixed ? '—' : (tin > 0 ? qty(tin) : '—'), color: TColors.emerald700, bold: true),
                  cellText(mixed ? '—' : (tout > 0 ? qty(tout) : '—'), color: TColors.red600, bold: true),
                  // Balance is a running position; summing it means nothing.
                  const SizedBox(),
                  cellText(tcost > 0 ? _money(tcost) : '—', bold: true),
                ],
              ),
            ],
            // The footer totals, repeated as a strip under the cards.
            if (!_table)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: TColors.slate50,
                  border: Border.all(color: TColors.slate200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Totals (${loc(sorted.length)}${sorted.length == 1 ? ' movement' : ' movements'})',
                          style: const TextStyle(fontSize: 12, color: TColors.slate600)),
                    ),
                    if (mixed)
                      Text('${ledgerUnits.join(', ')} — not totalled',
                          style: const TextStyle(fontSize: 12, color: TColors.slate500))
                    else ...[
                      Text('In ${tin > 0 ? qty(tin) : '—'}',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600, color: TColors.emerald700)),
                      const SizedBox(width: 12),
                      Text('Out ${tout > 0 ? qty(tout) : '—'}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: TColors.red600)),
                    ],
                  ],
                ),
              ),
            TrackerPager(
              total: sorted.length,
              page: _page,
              pageSize: _pageSize,
              showingLine: false,
              onPage: (p) => setState(() => _page = p),
              onPageSize: (s) => setState(() {
                _pageSize = s;
                _page = 1;
              }),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'In covers purchases and feed produced by a feed-production batch; Out covers feed fed to flocks and ingredients drawn into feed production. Reversed draws keep their row and are matched by a reversal adjustment, so the pair nets to zero. Cost is shown on Out rows only, and the total excludes reversed draws.'
            '${isAll ? " Across all items, Item balance is each row's OWN item running balance, not a combined one — consecutive rows can belong to different items." : ''}'
            '${mixed ? ' These rows span more than one stocking unit, so the In and Out columns are not totalled; pick a single item, or filter, to get a total that means something.' : ''}',
            style: const TextStyle(fontSize: 11, color: TColors.slate500),
          ),
        ],
      ),
    );
  }

  Widget _costCell(FeedItemMovement r) {
    if (r.cost == null) return const Text('—');
    final text = Text(_money(r.cost),
        style: TextStyle(
          color: r.reversed == true ? TColors.slate400 : null,
          decoration: r.reversed == true ? TextDecoration.lineThrough : null,
        ));
    if (r.productionRecordId == null) return text;
    return Tooltip(
      message: recognizedCostNote(r.recognized ?? 0, r.cost!),
      child: InkWell(
        onTap: () => showCostBreakdown(context,
            session: widget.session,
            company: widget.company,
            productionRecordId: r.productionRecordId!,
            money: _money,
            title: 'Feed cost breakdown'),
        child: Text(_money(r.cost),
            style: TextStyle(
              color: r.reversed == true ? TColors.slate400 : null,
              decoration: TextDecoration.underline,
              decorationStyle: TextDecorationStyle.dotted,
            )),
      ),
    );
  }

  Widget _scorecard(FeedItemMovement r, int i, bool isAll) => LedgerScorecard(
        key: ValueKey(r.key),
        index: i,
        title: r.date.isEmpty ? '—' : r.date,
        badge: isAll ? '${r.itemName} · ${r.label}' : r.label,
        trailing: Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Text(qty(r.balance), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ),
        boxes: [
          ScoreBox('In', r.inQty > 0 ? qty(r.inQty) : '—', ScoreTone.emerald),
          ScoreBox('Out', r.outQty > 0 ? qty(r.outQty) : '—', ScoreTone.red),
          ScoreBox('Balance', qty(r.balance), ScoreTone.violet, wide: true),
        ],
        details: [
          ('Description', Text(r.description)),
          if (r.cost != null) ('Cost', Text('${_money(r.cost)}${r.reversed == true ? ' (reversed)' : ''}')),
        ],
      );
}
