import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import 'tracker_logic.dart';
import 'tracker_widgets.dart';

/// Poultry → Trackers → Birds tracker, as `app/birds-left-tracker/page.tsx`.
///
/// One IN per flock (birds placed). Only mortality on production records and
/// bird sales (product not eggs; bird / chicken / broiler / layer / cull /
/// live / poultry / hen / rooster) create OUT rows. The "By flock" table
/// compares that arithmetic with the latest production record's birds left.
class BirdsTrackerScreen extends StatefulWidget {
  const BirdsTrackerScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<BirdsTrackerScreen> createState() => _BirdsTrackerScreenState();
}

class _BirdsTrackerScreenState extends State<BirdsTrackerScreen> {
  List<Map> _flocks = [], _records = [], _sales = [];
  bool _loading = true;
  bool _refreshing = false;
  String _error = '';

  String _flockFilter = 'ALL';
  String _typeFilter = 'ALL';
  String _from = '', _to = '';
  SortState _sort = (key: 'date', dir: SortDir.desc);
  int _page = 1;
  int _pageSize = trackerPageSizeDefault;
  bool _ledgerTable = false;
  bool _flockTable = false;

  ApiClient get _api => widget.session.farmClient;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = widget.session.tokens.userId;
    final farmId = widget.company.farmId;
    if (userId == null || userId.isEmpty || farmId.isEmpty) {
      setState(() {
        _error = 'Farm ID or User ID not found';
        _loading = false;
        _refreshing = false;
      });
      return;
    }
    final q = {'userId': userId, 'farmId': farmId};
    Future<(List<Map>, String?)> safe(String p) async {
      try {
        return (rowsOf(await _api.get(p, query: q)), null);
      } on ApiException catch (e) {
        return (<Map>[], e.message);
      }
    }

    final r = await Future.wait([safe('/api/Flock'), safe('/api/ProductionRecord'), safe('/api/Sale')]);
    if (!mounted) return;
    setState(() {
      _flocks = r[0].$1;
      _records = r[1].$1;
      _error = r[1].$2 == null ? '' : 'Failed to fetch production records: ${r[1].$2}';
      _sales = r[2].$1;
      _loading = false;
      _refreshing = false;
    });
  }

  void _refresh() {
    setState(() => _refreshing = true);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/birds-left-tracker');
    return Scaffold(
      appBar: AppBar(
        leading: lead.leading,
        leadingWidth: lead.width,
        title: const Text('Birds tracker'),
        actions: [RefreshAction(busy: _refreshing || _loading, onPressed: _refresh)],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            TrackerHeader(
              icon: Icons.flutter_dash,
              iconBg: TColors.sky100,
              iconFg: TColors.sky700,
              title: 'Birds left tracker',
              blurbSpans: [
                t('One '),
                b('IN'),
                t(' per flock (birds placed at purchase). Only '),
                b('mortality'),
                t(' (production records) and '),
                b('bird sales'),
                t(' create '),
                b('OUT'),
                t(' rows and reduce the count.'),
              ],
              links: const [('/flocks', 'Flocks'), ('/production-records', 'Production records'), ('/sales', 'Sales')],
              session: widget.session,
              company: widget.company,
            ),
            const SizedBox(height: 16),
            if (_error.isNotEmpty) ...[TrackerBanner.error(_error), const SizedBox(height: 12)],
            if (_loading) const TrackerLoading('Loading birds left…') else ..._content(),
          ],
        ),
      ),
    );
  }

  List<Widget> _content() {
    final summaries = summarizeBirdsLeftByFlock(
        [for (final f in _flocks) if (flockCountsTowardBirdTotals(f)) f], _records, _sales);
    final ledger = buildBirdsLeftLedger(_flocks, _records, _sales);
    final totalPlaced = summaries.fold<num>(0, (s, r) => s + r.placedIn);
    final totalLeft = summaries.fold<num>(0, (s, r) => s + r.birdsLeftCalculated);
    // Whole-ledger totals — the headline does not move with the filters.
    num lin = 0, lout = 0;
    for (final r in ledger) {
      if (r.type == 'IN') {
        lin += r.quantity;
      } else {
        lout += r.quantity;
      }
    }
    return [
      TileGrid(boxed: true, [
        TileData('Total birds placed (all flocks)', loc(totalPlaced), color: TColors.emerald700),
        TileData('Birds left (placed − deaths − bird sales)', loc(totalLeft), color: TColors.sky700),
        TileData('Total IN (ledger)', loc(lin), color: TColors.emerald600),
        TileData('Total OUT (deaths + bird sales)', loc(lout), color: TColors.red600),
      ]),
      const SizedBox(height: 16),
      _byFlock(summaries),
      const SizedBox(height: 16),
      _ledgerCard(ledger),
    ];
  }

  Widget _byFlock(List<FlockBirdsSummary> summaries) {
    num placed = 0, mort = 0, sold = 0, left = 0;
    for (final r in summaries) {
      placed += r.placedIn;
      mort += r.totalMortalityOut;
      sold += r.totalBirdSalesOut;
      left += r.birdsLeftCalculated;
    }
    final flocksLabel = '${loc(summaries.length)} ${summaries.length == 1 ? 'flock' : 'flocks'}';
    Widget kv(String l, String v, Color c, {bool bold = false}) => Text.rich(
          TextSpan(children: [
            TextSpan(text: '$l ', style: const TextStyle(color: TColors.slate500)),
            TextSpan(text: v, style: TextStyle(color: c, fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
          ]),
          style: const TextStyle(fontSize: 13),
        );

    return TCard(
      title: 'By flock',
      description: 'Compare calculated balance with the latest “birds left” on production records.',
      child: !_flockTable
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (summaries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Text('No flocks yet.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate500)),
                  )
                else ...[
                  for (var i = 0; i < summaries.length; i++) ...[
                    LedgerScorecard(
                      key: ValueKey('flock-${summaries[i].flockId}'),
                      index: i,
                      title: summaries[i].flockName,
                      boxes: [
                        ScoreBox('Placed (in)', loc(summaries[i].placedIn), ScoreTone.emerald),
                        ScoreBox('Birds left', loc(summaries[i].birdsLeftCalculated), ScoreTone.sky),
                      ],
                      details: [
                        ('Deaths OUT', Text(loc(summaries[i].totalMortalityOut), style: const TextStyle(color: TColors.red700))),
                        ('Sales OUT', Text(loc(summaries[i].totalBirdSalesOut), style: const TextStyle(color: TColors.amber800))),
                        (
                          'From last log',
                          Text(summaries[i].birdsLeftFromLatestLog != null ? loc(summaries[i].birdsLeftFromLatestLog!) : '—',
                              style: const TextStyle(color: TColors.slate700))
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                  // The table's footer row, which the cards would otherwise drop.
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: TColors.slate100,
                      border: Border.all(color: TColors.slate300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('TOTAL — ${flocksLabel.toUpperCase()}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: TColors.slate600)),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(child: kv('Placed', loc(placed), TColors.slate900, bold: true)),
                          Expanded(child: kv('Birds left', loc(left), TColors.sky800, bold: true)),
                        ]),
                        const SizedBox(height: 4),
                        Row(children: [
                          Expanded(child: kv('Deaths', loc(mort), TColors.red700, bold: true)),
                          Expanded(child: kv('Sales', loc(sold), TColors.amber800, bold: true)),
                        ]),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                ViewTableButton(onPressed: () => setState(() => _flockTable = true)),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TableViewBar(onCards: () => setState(() => _flockTable = false)),
                TrackerTable(
                  emptyText: 'No flocks yet.',
                  columns: const [
                    TCol('Flock', width: 140),
                    TCol('Placed (IN)', right: true, width: 100),
                    TCol('Deaths OUT', right: true, width: 100),
                    TCol('Sales OUT', right: true, width: 100),
                    TCol('Birds left', right: true, width: 100),
                    TCol('From last log', right: true, width: 110),
                  ],
                  rows: [
                    for (final r in summaries)
                      [
                        cellText(r.flockName, bold: true),
                        cellText(loc(r.placedIn)),
                        cellText(loc(r.totalMortalityOut), color: TColors.red700),
                        cellText(loc(r.totalBirdSalesOut), color: TColors.amber800),
                        cellText(loc(r.birdsLeftCalculated), color: TColors.sky800, bold: true),
                        cellText(r.birdsLeftFromLatestLog != null ? loc(r.birdsLeftFromLatestLog!) : '—',
                            color: TColors.slate600),
                      ],
                  ],
                  footer: summaries.isEmpty
                      ? null
                      : [
                          Text.rich(TextSpan(children: [
                            const TextSpan(text: 'Total', style: TextStyle(fontWeight: FontWeight.w500)),
                            TextSpan(text: ' ($flocksLabel)', style: const TextStyle(color: TColors.slate500)),
                          ])),
                          cellText(loc(placed), bold: true),
                          cellText(loc(mort), color: TColors.red700, bold: true),
                          cellText(loc(sold), color: TColors.amber800, bold: true),
                          cellText(loc(left), color: TColors.sky800, bold: true),
                          const SizedBox(),
                        ],
                ),
              ],
            ),
    );
  }

  Widget _ledgerCard(List<BirdsLedgerRow> ledger) {
    var list = [...ledger];
    if (_flockFilter != 'ALL') {
      final fid = int.tryParse(_flockFilter);
      list = list.where((r) => r.flockId == fid).toList();
    }
    if (_typeFilter != 'ALL') list = list.where((r) => r.type == _typeFilter).toList();
    if (_from.isNotEmpty) list = list.where((r) => r.date.compareTo(_from) >= 0).toList();
    if (_to.isNotEmpty) list = list.where((r) => r.date.compareTo(_to) <= 0).toList();
    final sorted = sortRows(list, _sort, (r, k) => switch (k) {
          'date' => r.date,
          'quantity' => r.quantity,
          'flockId' => r.flockId,
          _ => null,
        });
    final inT = sorted.where((r) => r.type == 'IN').fold<num>(0, (s, r) => s + r.quantity);
    final outT = sorted.where((r) => r.type == 'OUT').fold<num>(0, (s, r) => s + r.quantity);
    final net = inT - outT;
    final active = _flockFilter != 'ALL' || _typeFilter != 'ALL' || _from.isNotEmpty || _to.isNotEmpty;
    final pageRows = pageOf(sorted, _page, _pageSize);

    return TCard(
      title: 'Ledger (IN / OUT)',
      description: 'Bird sales are detected when the product name is not eggs (e.g. chicken, broiler, live bird).',
      headerExtra: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          children: [
            AppSelect<String>(
              value: _flockFilter,
              hintText: 'Flock',
              items: [
                const AppSelectItem(value: 'ALL', label: 'All flocks'),
                for (final f in _flocks)
                  AppSelectItem(
                    value: '${tIntOrNull(f['flockId'])}',
                    label: tStr(f['name']).isNotEmpty ? tStr(f['name']) : 'Flock #${f['flockId']}',
                  ),
              ],
              onChanged: (v) => setState(() {
                _flockFilter = v ?? 'ALL';
                _page = 1;
              }),
            ),
            const SizedBox(height: 8),
            AppSelect<String>(
              value: _typeFilter,
              hintText: 'Type',
              items: const [
                AppSelectItem(value: 'ALL', label: 'All types'),
                AppSelectItem(value: 'IN', label: 'IN only'),
                AppSelectItem(value: 'OUT', label: 'OUT only'),
              ],
              onChanged: (v) => setState(() {
                _typeFilter = v ?? 'ALL';
                _page = 1;
              }),
            ),
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
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (pageRows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Text('No ledger rows match these filters.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: TColors.slate600)),
            )
          else if (!_ledgerTable) ...[
            for (var i = 0; i < pageRows.length; i++) ...[
              LedgerScorecard(
                key: ValueKey(pageRows[i].id),
                index: i,
                title: trackerDate(pageRows[i].date),
                badge: pageRows[i].category,
                boxes: [
                  ScoreBox('In', pageRows[i].type == 'IN' ? loc(pageRows[i].quantity) : '—', ScoreTone.emerald),
                  ScoreBox('Out', pageRows[i].type == 'OUT' ? loc(pageRows[i].quantity) : '—', ScoreTone.red),
                ],
                details: [
                  ('Flock', Text(pageRows[i].flockName)),
                  ('Description', Text(pageRows[i].description)),
                ],
              ),
              const SizedBox(height: 10),
            ],
            ViewTableButton(onPressed: () => setState(() => _ledgerTable = true)),
          ] else ...[
            TableViewBar(onCards: () => setState(() => _ledgerTable = false)),
            TrackerTable(
              sort: _sort,
              onSort: (k) => setState(() => _sort = toggleSort(k, _sort)),
              columns: const [
                TCol('Date', sortKey: 'date', width: 100),
                TCol('Type', width: 70),
                TCol('Category', width: 100),
                TCol('Flock', width: 130),
                TCol('Qty', sortKey: 'quantity', right: true, width: 90),
                TCol('Description', width: 240),
              ],
              rows: [
                for (final r in pageRows)
                  [
                    cellText(trackerDate(r.date)),
                    TBadge(r.type,
                        bg: r.type == 'IN' ? TColors.emerald100 : TColors.red50,
                        fg: r.type == 'IN' ? TColors.emerald900 : TColors.red800),
                    cellText(r.category),
                    cellText(r.flockName, bold: true),
                    cellText('${r.type == 'OUT' ? '−' : '+'}${loc(r.quantity)}', bold: true),
                    cellText(r.description, color: TColors.slate600),
                  ],
              ],
              footer: [
                Text.rich(TextSpan(children: [
                  TextSpan(text: active ? 'Filtered total' : 'Total', style: const TextStyle(fontWeight: FontWeight.w500)),
                  TextSpan(
                      text: ' (${loc(sorted.length)} ${sorted.length == 1 ? 'row' : 'rows'})',
                      style: const TextStyle(color: TColors.slate500)),
                ])),
                const SizedBox(),
                const SizedBox(),
                const SizedBox(),
                cellText('${net >= 0 ? '+' : '−'}${loc(net.abs())}', bold: true),
                Text.rich(TextSpan(children: [
                  TextSpan(text: '+${loc(inT)} in', style: const TextStyle(color: TColors.emerald700)),
                  const TextSpan(text: ' · '),
                  TextSpan(text: '−${loc(outT)} out', style: const TextStyle(color: TColors.red700)),
                ])),
              ],
            ),
          ],
          if (sorted.isNotEmpty)
            TrackerPager(
              total: sorted.length,
              page: _page,
              pageSize: _pageSize,
              rowsLabel: true,
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
}
