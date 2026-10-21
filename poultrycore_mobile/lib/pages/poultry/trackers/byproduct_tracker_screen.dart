import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../poultry_links.dart';
import '../reports/report_format.dart';
import 'tracker_logic.dart';
import 'tracker_widgets.dart';

/// Poultry → Trackers → Broken eggs tracker / Dead birds tracker, as
/// `components/poultry/byproduct-tracker.tsx` (one component, two pages,
/// migrations 372-381): byproduct stock is its own ledger, apart from saleable
/// eggs and live birds — what was recorded, sold, disposed, used or adjusted by
/// hand, and what is left, per flock (pooled entries on their own row).
/// Everything comes from GET /Poultry/stock/byproduct-tracker; the flock and
/// movement filters work on the loaded period, and changing the period reloads.

enum ByproductRole { brokenEggs, deadBirds }

class _Copy {
  const _Copy(this.title, this.unit, this.intro, this.generated, this.icon, this.bg, this.fg, this.links);
  final String title;
  final String unit;
  final List<(String, bool)> intro; // (text, bold)
  final String generated;
  final IconData icon;
  final Color bg;
  final Color fg;
  final List<(String, String)> links;
}

const _copy = {
  ByproductRole.brokenEggs: _Copy(
    'Broken eggs tracker',
    'eggs',
    [
      ('Broken eggs from ', false),
      ('production records', true),
      (' and ', false),
      ('egg sorting', true),
      (', and what happened to them: sold, disposed, used or adjusted by hand. They are never counted as saleable eggs.', false),
    ],
    'Broken eggs recorded',
    Icons.egg_outlined,
    TColors.amber100,
    TColors.amber700,
    [
      ('/production-records', 'Production records'),
      ('/poultry-egg-sorting', 'Egg sorting'),
      ('/poultry-stock', 'Stock movements'),
      ('/poultry/reports/byproduct-inventory', 'Byproduct report'),
    ],
  ),
  ByproductRole.deadBirds: _Copy(
    'Dead birds tracker',
    'birds',
    [
      ('Deaths recorded on ', false),
      ('production records', true),
      (' and what happened to the carcasses: sold, disposed or still held. They are never counted as live birds; the Birds tracker shows those.',
          false),
    ],
    'Deaths recorded',
    Icons.flutter_dash,
    TColors.rose100,
    TColors.rose700,
    [
      ('/production-records', 'Production records'),
      ('/birds-left-tracker', 'Birds tracker'),
      ('/poultry-stock', 'Stock movements'),
      ('/poultry/reports/byproduct-inventory', 'Byproduct report'),
    ],
  ),
};

const byproductCategoryLabel = {
  'Generated': 'Recorded',
  'Sold': 'Sold',
  'Disposed': 'Disposed',
  'InternalUse': 'Internal use',
  'ManualIn': 'Added by hand',
  'ManualOut': 'Removed by hand',
  'Reversal': 'Reversal',
};

/// CATEGORY_TONE: (bg, fg, border).
(Color, Color, Color) _categoryTone(String key) => switch (key) {
      'Generated' => (TColors.emerald50, TColors.emerald800, TColors.emerald300),
      'Sold' => (const Color(0xFFEFF6FF), const Color(0xFF1E40AF), TColors.blue300),
      'Disposed' => (TColors.rose50, TColors.rose800, const Color(0xFFFDA4AF)),
      'InternalUse' => (TColors.violet50, TColors.violet800, const Color(0xFFC4B5FD)),
      'ManualIn' => (const Color(0xFFF0FDFA), const Color(0xFF115E59), const Color(0xFF5EEAD4)),
      'ManualOut' => (const Color(0xFFFFF7ED), const Color(0xFF9A3412), const Color(0xFFFDBA74)),
      _ => (TColors.slate50, TColors.slate700, TColors.slate300),
    };

/// Where a movement came from, in words.
const byproductSourceLabel = {
  'Broken Egg Prod': 'Production record',
  'Broken Egg Disposal': 'Disposed at once (production record)',
  'Sorting Breakage': 'Egg sorting',
  'Breakage In': 'Unrecorded breakage',
  'Mortality In': 'Production record',
  'Mortality Disposal': 'Disposed at once (production record)',
  'Hist Mortality In': 'Historical mortality',
  'Hist Mortality Disp': 'Historical mortality, disposed',
  'Disposal': 'Disposal',
  'Sale': 'Sale',
  'Sale Reversal': 'Sale reversed',
  'InternalUse': 'Internal use',
};

const _pooled = '__pooled__';
String _flockKey(Object? id) => tIntOrNull(id) == null ? _pooled : '${tIntOrNull(id)}';
String _flockLabel(Map r) =>
    tIntOrNull(r['flockId']) == null ? 'Pooled (no flock)' : (tStr(r['flockName']).isEmpty ? 'Flock ${r['flockId']}' : tStr(r['flockName']));

/// A movement against its category's usual direction is a correction: a record
/// edited down or deleted (Recorded, negative), or a disposal taken back
/// (Disposed, positive).
bool isByproductCorrection(Map m) =>
    (m['category'] == 'Generated' && tNum(m['quantity']) < 0) || (m['category'] == 'Disposed' && tNum(m['quantity']) > 0);

String byproductCategoryText(Map m) =>
    isByproductCorrection(m) ? 'Correction' : (byproductCategoryLabel[tStr(m['category'])] ?? tStr(m['category']));

Widget _categoryBadge(Map m) {
  final (bg, fg, border) = _categoryTone(isByproductCorrection(m) ? 'Correction' : tStr(m['category']));
  return TBadge(byproductCategoryText(m), bg: bg, fg: fg, border: border);
}

/// The running balance from the period's [opening], oldest first, over the
/// chosen flock's movements; filtered to [category] and returned newest first.
List<(Map, num)> byproductLedger(List<Map> movements, num opening, {String flock = 'ALL', String category = 'ALL'}) {
  final moves = [
    for (final m in movements)
      if (flock == 'ALL' || _flockKey(m['flockId']) == flock) m,
  ]..sort((a, b) {
      final c = tStr(a['date']).compareTo(tStr(b['date']));
      return c != 0 ? c : tNum(a['txnId']).compareTo(tNum(b['txnId']));
    });
  var bal = opening;
  final rows = <(Map, num)>[];
  for (final m in moves) {
    bal += tNum(m['quantity']);
    rows.add((m, bal));
  }
  return [
    for (final r in rows.reversed)
      if (category == 'ALL' || r.$1['category'] == category) r,
  ];
}

class ByproductTrackerScreen extends StatefulWidget {
  const ByproductTrackerScreen({super.key, required this.session, required this.company, required this.role});
  final Session session;
  final Company company;
  final ByproductRole role;

  @override
  State<ByproductTrackerScreen> createState() => _ByproductTrackerScreenState();
}

class _ByproductTrackerScreenState extends State<ByproductTrackerScreen> {
  String _period = 'last30';
  String _from = periodToRange('last30')!.from, _to = periodToRange('last30')!.to;
  Map? _data;
  bool _loading = true, _refreshing = false;
  String _error = '';
  String _flockFilter = 'ALL', _categoryFilter = 'ALL';
  bool _flockTable = false, _ledgerTable = false;
  int _page = 1, _pageSize = trackerPageSizeDefault;
  FarmMoney _money = const FarmMoney();

  _Copy get copy => _copy[widget.role]!;
  String get _href => widget.role == ByproductRole.brokenEggs ? '/broken-eggs-tracker' : '/dead-birds-tracker';
  ApiClient get _api => widget.session.farmClient;

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _money = m);
    });
    _load();
  }

  Future<void> _load({bool soft = false}) async {
    if (_from.isEmpty || _to.isEmpty) return;
    setState(() {
      soft ? _refreshing = true : _loading = true;
      _error = '';
    });
    try {
      final res = await _api.get('/api/Poultry/stock/byproduct-tracker', query: {
        'farmId': widget.company.farmId,
        'role': widget.role == ByproductRole.brokenEggs ? 'BrokenEggs' : 'DeadBirds',
        'fromDate': _from,
        'toDate': _to,
      });
      if (mounted) setState(() => _data = res is Map ? res : null);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message.isEmpty ? 'Could not load the tracker.' : e.message);
    }
    if (mounted) {
      setState(() {
        _loading = false;
        _refreshing = false;
      });
    }
  }

  void _pickPeriod(String p) {
    final r = p == 'allTime' ? (from: '2000-01-01', to: periodToRange('today')!.to) : periodToRange(p);
    setState(() {
      _period = p;
      if (r != null) {
        _from = r.from;
        _to = r.to;
      }
      _page = 1;
    });
    if (r != null) _load();
  }

  List<Map> get _flockRows => rowsOf(_data?['flocks']);
  List<Map> get _movements => rowsOf(_data?['movements']);

  List<(String, String)> get _flockOptions {
    final seen = <String, String>{};
    for (final r in _flockRows) {
      seen[_flockKey(r['flockId'])] = _flockLabel(r);
    }
    for (final m in _movements) {
      seen.putIfAbsent(_flockKey(m['flockId']), () => _flockLabel(m));
    }
    final list = [for (final e in seen.entries) (e.key, e.value)];
    list.sort((a, b) => a.$1 == _pooled ? 1 : (b.$1 == _pooled ? -1 : a.$2.compareTo(b.$2)));
    return list;
  }

  /// First and last movement per flock in the period.
  Map<String, (String, String)> get _flockDates {
    final m = <String, (String, String)>{};
    for (final mv in _movements) {
      final k = _flockKey(mv['flockId']);
      final d = tStr(mv['date']);
      final cur = m[k];
      m[k] = cur == null ? (d, d) : (d.compareTo(cur.$1) < 0 ? d : cur.$1, d.compareTo(cur.$2) > 0 ? d : cur.$2);
    }
    return m;
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: _href);
    return Scaffold(
      appBar: AppBar(
        leading: lead.leading,
        leadingWidth: lead.width,
        title: Text(copy.title),
        actions: [RefreshAction(busy: _refreshing || _loading, onPressed: () => _load(soft: true))],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(soft: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            TrackerHeader(
              icon: copy.icon,
              iconBg: copy.bg,
              iconFg: copy.fg,
              title: copy.title,
              blurbSpans: [for (final (s, bold) in copy.intro) bold ? b(s) : t(s)],
              links: copy.links,
              session: widget.session,
              company: widget.company,
            ),
            const SizedBox(height: 16),
            _filters(),
            const SizedBox(height: 16),
            if (_error.isNotEmpty) ...[TrackerBanner.error(_error), const SizedBox(height: 12)],
            if (_loading) TrackerLoading('Loading ${copy.title.toLowerCase()}…') else ..._content(),
          ],
        ),
      ),
    );
  }

  Widget _filters() => TCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FilterLabel(
            'Period',
            AppSelect<String>(
              value: _period,
              items: [for (final (_, opts) in periodGroups) for (final (k, l) in opts) AppSelectItem(value: k, label: l)],
              onChanged: (v) {
                if (v != null) _pickPeriod(v);
              },
            ),
          ),
          const SizedBox(height: 8),
          filterRow([
            FilterLabel(
              'From',
              FilterDate(
                value: _from,
                hint: 'From',
                onChanged: (v) {
                  setState(() {
                    _period = 'custom';
                    _from = v;
                    _page = 1;
                  });
                  _load();
                },
              ),
            ),
            FilterLabel(
              'To',
              FilterDate(
                value: _to,
                hint: 'To',
                onChanged: (v) {
                  setState(() {
                    _period = 'custom';
                    _to = v;
                    _page = 1;
                  });
                  _load();
                },
              ),
            ),
          ]),
          const SizedBox(height: 8),
          FilterLabel(
            'Flock',
            AppSelect<String>(
              value: _flockFilter,
              items: [
                const AppSelectItem(value: 'ALL', label: 'All flocks'),
                for (final (k, l) in _flockOptions) AppSelectItem(value: k, label: l),
              ],
              onChanged: (v) => setState(() {
                _flockFilter = v ?? 'ALL';
                _page = 1;
              }),
            ),
          ),
          const SizedBox(height: 8),
          FilterLabel(
            'Movement',
            AppSelect<String>(
              value: _categoryFilter,
              items: [
                const AppSelectItem(value: 'ALL', label: 'All movements'),
                for (final e in byproductCategoryLabel.entries) AppSelectItem(value: e.key, label: e.value),
              ],
              onChanged: (v) => setState(() {
                _categoryFilter = v ?? 'ALL';
                _page = 1;
              }),
            ),
          ),
        ]),
      );

  List<Widget> _content() {
    final flocks = [
      for (final r in _flockRows)
        if (_flockFilter == 'ALL' || _flockKey(r['flockId']) == _flockFilter) r,
    ];
    num sum(String k) => flocks.fold<num>(0, (s, r) => s + tNum(r[k]));
    final opening = sum('opening'), generated = sum('generated'), sold = sum('sold'), disposed = sum('disposed');
    final internalUse = sum('internalUse'), manualIn = sum('manualIn'), manualOut = sum('manualOut');
    final reversals = sum('reversals'), closing = sum('closing'), revenue = sum('revenue');
    final otherOut = internalUse + manualOut;
    final ledger = byproductLedger(_movements, opening, flock: _flockFilter, category: _categoryFilter);
    return [
      TileGrid(boxed: true, [
        TileData('On hand now', loc(tNum(_data?['onHand'])), color: TColors.sky700, sub: 'All flocks, today'),
        TileData(copy.generated, loc(generated), color: TColors.emerald700, sub: 'In the period'),
        TileData('Sold', loc(sold), color: const Color(0xFF1D4ED8), sub: revenue != 0 ? '${_money(revenue)} revenue' : 'In the period'),
        TileData('Disposed', loc(disposed), color: TColors.rose700, sub: 'In the period'),
        TileData(
          'Left at end of period',
          loc(closing),
          sub: 'Opening ${loc(opening)}${manualIn != 0 ? ' · added ${loc(manualIn)}' : ''}'
              '${otherOut != 0 ? ' · other out ${loc(otherOut)}' : ''}${reversals != 0 ? ' · reversals ${loc(reversals)}' : ''}',
        ),
      ]),
      const SizedBox(height: 16),
      _byFlock(flocks, (
        opening: opening,
        generated: generated,
        manualIn: manualIn,
        sold: sold,
        disposed: disposed,
        internalUse: internalUse,
        manualOut: manualOut,
        reversals: reversals,
        closing: closing,
        revenue: revenue,
      )),
      const SizedBox(height: 16),
      _movementsCard(ledger),
    ];
  }

  Widget _byFlock(
    List<Map> flocks,
    ({num opening, num generated, num manualIn, num sold, num disposed, num internalUse, num manualOut, num reversals, num closing, num revenue}) tot,
  ) {
    final dates = _flockDates;
    String first(Map r) => dates[_flockKey(r['flockId'])] == null ? '—' : trackerDate(dates[_flockKey(r['flockId'])]!.$1);
    String last(Map r) => dates[_flockKey(r['flockId'])] == null ? '—' : trackerDate(dates[_flockKey(r['flockId'])]!.$2);
    return TCard(
      title: 'By flock',
      description: '${trackerDate(_from)} – ${trackerDate(_to)}. First / Last are the flock\'s first and last movement in the period. '
          'Opening + recorded + added − sold − disposed − used − removed ± reversals = left, for the period. '
          'Entries with no flock (e.g. egg sorting, pooled stock) sit on their own row.',
      child: !_flockTable
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (flocks.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Text('Nothing in this period.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: TColors.slate500)),
                )
              else
                for (var i = 0; i < flocks.length; i++) ...[
                  LedgerScorecard(
                    key: ValueKey('bp-flock-${_flockKey(flocks[i]['flockId'])}'),
                    index: i,
                    title: '${_flockLabel(flocks[i])}${tStr(flocks[i]['batchCode']).isEmpty ? '' : ' · ${tStr(flocks[i]['batchCode'])}'}',
                    boxes: [
                      ScoreBox('Recorded', loc(tNum(flocks[i]['generated'])), ScoreTone.emerald),
                      ScoreBox('Left', loc(tNum(flocks[i]['closing'])), ScoreTone.sky),
                    ],
                    details: [
                      (
                        'Movements',
                        Text(dates[_flockKey(flocks[i]['flockId'])] == null
                            ? 'No movements in the period'
                            : '${first(flocks[i])} – ${last(flocks[i])}'),
                      ),
                      ('Opening', Text(loc(tNum(flocks[i]['opening'])))),
                      ('Sold', Text(loc(tNum(flocks[i]['sold'])), style: const TextStyle(color: Color(0xFF1D4ED8)))),
                      ('Disposed', Text(loc(tNum(flocks[i]['disposed'])), style: const TextStyle(color: TColors.rose700))),
                      (
                        'Other ±',
                        Text(loc(tNum(flocks[i]['manualIn']) - tNum(flocks[i]['manualOut']) - tNum(flocks[i]['internalUse']) + tNum(flocks[i]['reversals']))),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
              ViewTableButton(onPressed: () => setState(() => _flockTable = true)),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TableViewBar(onCards: () => setState(() => _flockTable = false)),
              TrackerTable(
                emptyText: 'Nothing in this period.',
                columns: const [
                  TCol('Flock', width: 140),
                  TCol('Batch', width: 90),
                  TCol('First', width: 90),
                  TCol('Last', width: 90),
                  TCol('Opening', right: true, width: 80),
                  TCol('Recorded', right: true, width: 85),
                  TCol('Added', right: true, width: 75),
                  TCol('Sold', right: true, width: 75),
                  TCol('Disposed', right: true, width: 80),
                  TCol('Used', right: true, width: 70),
                  TCol('Removed', right: true, width: 80),
                  TCol('Reversals', right: true, width: 85),
                  TCol('Left', right: true, width: 75),
                  TCol('Revenue', right: true, width: 110),
                ],
                rows: [
                  for (final r in flocks)
                    [
                      cellText(_flockLabel(r), bold: tIntOrNull(r['flockId']) != null, color: tIntOrNull(r['flockId']) == null ? TColors.slate600 : null),
                      cellText(tStr(r['batchCode']).isEmpty ? '—' : tStr(r['batchCode']), color: TColors.slate600),
                      cellText(first(r), color: TColors.slate600),
                      cellText(last(r), color: TColors.slate600),
                      cellText(loc(tNum(r['opening']))),
                      cellText(loc(tNum(r['generated'])), color: TColors.emerald700),
                      cellText(loc(tNum(r['manualIn']))),
                      cellText(loc(tNum(r['sold'])), color: const Color(0xFF1D4ED8)),
                      cellText(loc(tNum(r['disposed'])), color: TColors.rose700),
                      cellText(loc(tNum(r['internalUse']))),
                      cellText(loc(tNum(r['manualOut']))),
                      cellText(loc(tNum(r['reversals']))),
                      cellText(loc(tNum(r['closing'])), bold: true),
                      cellText(tNum(r['revenue']) != 0 ? _money(tNum(r['revenue'])) : '—'),
                    ],
                ],
                footer: flocks.length > 1
                    ? [
                        cellText('Total', bold: true),
                        const SizedBox(),
                        const SizedBox(),
                        const SizedBox(),
                        cellText(loc(tot.opening)),
                        cellText(loc(tot.generated)),
                        cellText(loc(tot.manualIn)),
                        cellText(loc(tot.sold)),
                        cellText(loc(tot.disposed)),
                        cellText(loc(tot.internalUse)),
                        cellText(loc(tot.manualOut)),
                        cellText(loc(tot.reversals)),
                        cellText(loc(tot.closing), bold: true),
                        cellText(tot.revenue != 0 ? _money(tot.revenue) : '—'),
                      ]
                    : null,
              ),
            ]),
    );
  }

  Widget _reference(Map m) {
    if (tStr(m['movementNo']).isNotEmpty) return Text(tStr(m['movementNo']));
    final saleId = tIntOrNull(m['saleId']);
    if (saleId == null || saleId == 0) return const Text('—');
    return InkWell(
      onTap: () => openPoultryHref(context, widget.session, widget.company, '/sales?saleId=$saleId', label: 'Sales'),
      child: Text('Sale #$saleId', style: const TextStyle(color: TColors.blue600)),
    );
  }

  Widget _movementsCard(List<(Map, num)> ledger) {
    final inT = ledger.fold<num>(0, (s, r) => s + (tNum(r.$1['quantity']) > 0 ? tNum(r.$1['quantity']) : 0));
    final outT = ledger.fold<num>(0, (s, r) => s + (tNum(r.$1['quantity']) < 0 ? -tNum(r.$1['quantity']) : 0));
    final pageRows = pageOf(ledger, _page, _pageSize);
    String source(Map m) => byproductSourceLabel[tStr(m['txnType'])] ?? tStr(m['txnType']);
    return TCard(
      title: 'Movements',
      description: 'Every ${copy.unit == 'eggs' ? 'broken egg' : 'dead bird'} movement in the period, newest first, with the '
          'running balance. In ${loc(inT)} · Out ${loc(outT)}.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (pageRows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Text('No movements in this period.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: TColors.slate500)),
          )
        else if (!_ledgerTable) ...[
          for (var i = 0; i < pageRows.length; i++) ...[
            () {
              final (m, bal) = pageRows[i];
              final q = tNum(m['quantity']);
              return LedgerScorecard(
                key: ValueKey('bp-move-${tStr(m['txnId'])}'),
                index: i,
                title: '${trackerDate(m['date'])} · ${source(m)}',
                badge: byproductCategoryText(m),
                boxes: [
                  ScoreBox(q >= 0 ? 'In' : 'Out', '${q >= 0 ? '+' : '−'}${loc(q.abs())}', q >= 0 ? ScoreTone.emerald : ScoreTone.red),
                  ScoreBox('Balance', loc(bal), ScoreTone.slate),
                ],
                details: [
                  ('Flock', Text(_flockLabel(m))),
                  if (tStr(m['movementNo']).isNotEmpty || (tIntOrNull(m['saleId']) ?? 0) != 0) ('Reference', _reference(m)),
                  if (tStr(m['note']).isNotEmpty) ('Note', Text(tStr(m['note']), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
              );
            }(),
            const SizedBox(height: 10),
          ],
          ViewTableButton(onPressed: () => setState(() => _ledgerTable = true)),
        ] else ...[
          TableViewBar(onCards: () => setState(() => _ledgerTable = false)),
          TrackerTable(
            columns: const [
              TCol('Date', width: 90),
              TCol('Movement', width: 130),
              TCol('From', width: 170),
              TCol('Flock', width: 140),
              TCol('In', right: true, width: 70),
              TCol('Out', right: true, width: 70),
              TCol('Balance', right: true, width: 80),
              TCol('Reference', width: 110),
              TCol('Note', width: 200),
            ],
            rows: [
              for (final (m, bal) in pageRows)
                [
                  cellText(trackerDate(m['date'])),
                  _categoryBadge(m),
                  cellText(source(m), color: TColors.slate600),
                  cellText(
                    '${_flockLabel(m)}${tStr(m['batchCode']).isEmpty ? '' : ' ${tStr(m['batchCode'])}'}',
                    color: tIntOrNull(m['flockId']) == null ? TColors.slate500 : null,
                  ),
                  cellText(tNum(m['quantity']) > 0 ? loc(tNum(m['quantity'])) : '', color: TColors.emerald700),
                  cellText(tNum(m['quantity']) < 0 ? loc(-tNum(m['quantity'])) : '', color: TColors.rose700),
                  cellText(loc(bal), bold: true),
                  _reference(m),
                  cellText(tStr(m['note']), color: TColors.slate500),
                ],
            ],
          ),
        ],
        if (ledger.isNotEmpty)
          TrackerPager(
            total: ledger.length,
            page: _page,
            pageSize: _pageSize,
            rowsLabel: true,
            onPage: (p) => setState(() => _page = p),
            onPageSize: (s) => setState(() {
              _pageSize = s;
              _page = 1;
            }),
          ),
      ]),
    );
  }
}
