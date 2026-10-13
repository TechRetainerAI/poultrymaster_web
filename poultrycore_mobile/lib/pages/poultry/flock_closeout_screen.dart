import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../lookup_loader.dart';
import '../shared/business_dates.dart';
import '../shared/iam_permissions.dart';
import 'flock_closeout_logic.dart';
import 'flock_closeout_widgets.dart';
import 'money/money_widgets.dart';
import 'reports/report_format.dart';
import 'sales/balances_logic.dart' show pageSlice;
import 'sales/balances_widgets.dart';
import 'trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import 'trackers/tracker_widgets.dart';

/// Poultry → Tools → Flock Closeout, as `app/flock-closeout/page.tsx`
/// (migrations 338/339): three views over one read, fnflock_lifetimesummary.
///
///   Ready to close  open flocks with birds standing — Close opens the wizard
///   Closed          finished flocks and how they did — Lifetime & reopen
///   Compare         the same rows grouped by batch, breed, supplier, house or flock

const closeoutViewKey = 'poultry.flock-closeout.view';
const closeoutCreateKey = 'poultry.flock-closeout.create';
const closeoutApproveKey = 'poultry.flock-closeout.approve';

String _n(num? v) => v == null ? '—' : fmtNum(v, 3);
String _pct(Object? v) => v == null ? '—' : '${(tNum(v) * 100).toStringAsFixed(2)}%';
String _day(Object? v) {
  final s = tStr(v);
  return s.isEmpty ? '—' : (s.length >= 10 ? s.substring(0, 10) : s);
}

const _orange600 = Color(0xFFEA580C);
const _orange100 = Color(0xFFFFEDD5);
const _blue700 = Color(0xFF1D4ED8);

/// The page's permission keys, read once. Until they arrive the page shows (as
/// the web does while usePermissions loads) and offers no Close or Reopen.
class _Perms {
  const _Perms({this.loaded = false, this.view = true, this.close = false, this.reopen = false});
  final bool loaded, view, close, reopen;
}

Future<_Perms> _loadPerms(Session s, Company c) async {
  final held = await canDoAll(s, c, const [closeoutViewKey, closeoutCreateKey, closeoutApproveKey]);
  return _Perms(
    loaded: true,
    view: held.contains(closeoutViewKey),
    close: held.contains(closeoutCreateKey),
    reopen: held.contains(closeoutApproveKey),
  );
}

Widget _lockedCard() => TCard(
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Column(children: [
          Icon(Icons.lock_outline, size: 24, color: TColors.slate400),
          SizedBox(height: 8),
          Text('You do not have access to Flock Closeout.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate600)),
        ]),
      ),
    );

class FlockCloseoutScreen extends StatefulWidget {
  const FlockCloseoutScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<FlockCloseoutScreen> createState() => _FlockCloseoutScreenState();
}

class _FlockCloseoutScreenState extends State<FlockCloseoutScreen> {
  late final _api = FlockCloseoutApi(widget.session, widget.company);
  List<Map> _rows = [];
  bool _loading = true;
  String _tab = 'open';
  final _search = TextEditingController();
  String _groupBy = 'batch';
  String _compareScope = 'closed';
  _Perms _perms = const _Perms();
  int _openPage = 1, _openSize = 10, _closedPage = 1, _closedSize = 10;
  FarmMoney _money = const FarmMoney();

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _money = m);
    });
    _loadPerms(widget.session, widget.company).then((p) {
      if (mounted) setState(() => _perms = p);
    });
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _m(Object? v) => v == null ? '—' : _money(tNum(v));

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _api.lifetime();
      if (mounted) setState(() => _rows = rowsOf(res));
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load flocks', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Other pages read flocks through a cache; a close or reopen must not leave
  /// them offering a flock that just changed state.
  void _refresh() {
    LookupLoader.clear();
    _load();
  }

  bool _matches(Map r) {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [r['flockName'], r['breed'], r['batchCode'], r['batchName'], r['houseName']].any((v) => tStr(v).toLowerCase().contains(q));
  }

  bool _isOpen(Map r) => r['status'] == 'Active' || r['status'] == 'Inactive';
  int _id(Map r) => tIntOrNull(r['flockId']) ?? 0;

  void _openLifetimePage(int flockId) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FlockLifetimeScreen(session: widget.session, company: widget.company, flockId: flockId),
    ));
    _refresh();
  }

  void _close(int flockId) => showFlockCloseoutWizard(context,
      session: widget.session, company: widget.company, flockId: flockId, onClosed: _refresh);

  void _lifetimeDialog(int flockId) => showFlockLifetimeDialog(context,
      session: widget.session,
      company: widget.company,
      flockId: flockId,
      canReopen: _perms.reopen,
      onReopened: _refresh,
      onOpenPage: () => _openLifetimePage(flockId));

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/flock-closeout');
    final open = _rows.where(_isOpen).toList();
    final closedAll = _rows.where((r) => r['status'] == 'Closed').toList();
    final standing = open.fold<num>(0, (a, r) => a + tNum(r['finalBirds']));

    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Flock Closeout')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: _perms.loaded && !_perms.view
              ? [_lockedCard()]
              : [
                  Row(children: [
                    const Icon(Icons.flag_outlined, size: 22, color: _orange600),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Flock Closeout', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: TColors.slate900)),
                    ),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _refresh,
                      icon: _loading
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.refresh, size: 16),
                      label: const Text('Refresh'),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  const Text(
                    "End a flock's life: account for every bird still standing, sell, cull or transfer the last of them, and free its house. Closed flocks keep their full history and their lifetime performance.",
                    style: TextStyle(fontSize: 13, color: TColors.slate600),
                  ),
                  const SizedBox(height: 14),
                  LayoutBuilder(builder: (context, c) {
                    final half = (c.maxWidth - 12) / 2;
                    return Wrap(spacing: 12, runSpacing: 12, children: [
                      SizedBox(width: half, child: _kpi('Open flocks', _n(open.length))),
                      SizedBox(width: half, child: _kpi('Birds standing in them', _n(standing), color: _blue700)),
                      SizedBox(width: c.maxWidth, child: _kpi('Closed flocks', _n(closedAll.length))),
                    ]);
                  }),
                  const SizedBox(height: 14),
                  _tabsList(),
                  if (_tab != 'compare') ...[
                    const SizedBox(height: 12),
                    ListFiltersCard(
                      search: _search,
                      searchPlaceholder: 'Search flock, breed, batch or house',
                      onSearch: () => setState(() {
                        _openPage = 1;
                        _closedPage = 1;
                      }),
                      from: '',
                      to: '',
                      onDates: (_, _) {},
                      onClear: () => setState(() {
                        _search.clear();
                        _openPage = 1;
                        _closedPage = 1;
                      }),
                      searchOnly: true,
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (_tab == 'open') _openTab(open.where(_matches).toList()),
                  if (_tab == 'closed')
                    _closedTab(closedAll.where(_matches).toList()..sort((a, b) => tStr(b['closedDate']).compareTo(tStr(a['closedDate'])))),
                  if (_tab == 'compare') ..._compareTab(),
                ],
        ),
      ),
    );
  }

  Widget _kpi(String label, String value, {Color color = TColors.slate900}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: color)),
        ]),
      );

  /// The web's TabsList: a slate pill holding the three triggers.
  Widget _tabsList() {
    const tabs = [('open', 'Ready to close'), ('closed', 'Closed'), ('compare', 'Compare')];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: TColors.slate100, borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        for (final (v, l) in tabs)
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => setState(() => _tab = v),
              child: Container(
                constraints: const BoxConstraints(minHeight: 40),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _tab == v ? Colors.white : null,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: _tab == v ? const [BoxShadow(color: Color(0x14000000), blurRadius: 2, offset: Offset(0, 1))] : null,
                ),
                child: Text(l,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _tab == v ? TColors.slate900 : TColors.slate500)),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _state(String text) => TCard(
        padding: const EdgeInsets.all(24),
        child: Center(child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: TColors.slate500))),
      );

  Widget get _loadingCard => TCard(
        padding: const EdgeInsets.all(20),
        child: const LoadingLine('Loading…'),
      );

  Widget _link(String text, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Text(text, style: const TextStyle(color: _blue700, fontWeight: FontWeight.w500)),
      );

  Widget _right(String text, {Color? color, bool bold = false}) => Align(
        alignment: Alignment.centerRight,
        child: Text(text, style: TextStyle(color: color, fontWeight: bold ? FontWeight.w600 : null)),
      );

  // ---------------------------------------------------------------- open

  Widget _openTab(List<Map> rows) {
    if (_loading) return _loadingCard;
    if (rows.isEmpty) return _state('No open flocks with birds on the farm.');
    final pageRows = pageSlice(rows, _openPage, _openSize);
    return MobileCardList<Map>(
      items: pageRows,
      keyOf: (r) => '${r['flockId']}',
      primary: (r) => tStr(r['flockName']),
      secondary: (r) {
        final parts = [tStr(r['batchCode']), tStr(r['houseName'])].where((s) => s.isNotEmpty).join(' · ');
        return parts.isEmpty ? '—' : parts;
      },
      trailing: (r) => r['status'] == 'Inactive'
          ? const Padding(padding: EdgeInsets.only(right: 4), child: TBadge('Inactive', bg: TColors.slate100, fg: TColors.slate900))
          : null,
      highlights: (r) => [
        Highlight('Birds standing', _n(tNum(r['finalBirds'])), accent: Accent.blue),
        Highlight('Days', _n(tNum(r['daysInProduction']))),
      ],
      details: (r) => [
        ('Breed', tStr(r['breed']).isEmpty ? '—' : tStr(r['breed'])),
        ('Started', _day(r['startDate'])),
        ('Placed', _n(tNum(r['originallyPlaced']))),
        ('Mortality', '${_n(tNum(r['recordedMortality']))} (${_pct(r['trackedMortalityRate'])})'),
      ],
      actions: (r) => [
        OutlinedButton.icon(
          onPressed: () => _openLifetimePage(_id(r)),
          icon: const Icon(Icons.bar_chart, size: 16),
          label: const Text('Lifetime'),
        ),
        if (_perms.close)
          FilledButton.icon(
            onPressed: () => _close(_id(r)),
            icon: const Icon(Icons.flag_outlined, size: 16),
            label: const Text('Close flock'),
          ),
      ],
      table: (items) => TrackerTable(
        columns: const [
          TCol('Flock', width: 170),
          TCol('Batch'),
          TCol('House'),
          TCol('Started'),
          TCol('Placed', right: true, width: 90),
          TCol('Mortality', right: true, width: 130),
          TCol('Birds standing', right: true, width: 120),
          TCol('Actions', right: true, width: 150),
        ],
        rows: [
          for (final r in items)
            [
              Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                _link(tStr(r['flockName']), () => _openLifetimePage(_id(r))),
                if (r['status'] == 'Inactive') const TBadge('Inactive', bg: TColors.slate100, fg: TColors.slate900),
              ]),
              cellText(tStr(r['batchCode']).isEmpty ? '—' : tStr(r['batchCode'])),
              cellText(tStr(r['houseName']).isEmpty ? '—' : tStr(r['houseName'])),
              cellText(_day(r['startDate'])),
              _right(_n(tNum(r['originallyPlaced']))),
              _right('${_n(tNum(r['recordedMortality']))} (${_pct(r['trackedMortalityRate'])})'),
              _right(_n(tNum(r['finalBirds'])), color: _blue700, bold: true),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                IconButton(
                  tooltip: 'Lifetime performance',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.bar_chart, size: 18),
                  onPressed: () => _lifetimeDialog(_id(r)),
                ),
                if (_perms.close)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: () => _close(_id(r)),
                    icon: const Icon(Icons.flag_outlined, size: 16),
                    label: const Text('Close'),
                  ),
              ]),
            ],
        ],
      ),
      pager: CompactPager(
        total: rows.length,
        page: _openPage,
        pageSize: _openSize,
        onPage: (p) => setState(() => _openPage = p),
        onPageSize: (s) => setState(() {
          _openSize = s;
          _openPage = 1;
        }),
      ),
    );
  }

  // -------------------------------------------------------------- closed

  Widget _closedTab(List<Map> rows) {
    if (_loading) return _loadingCard;
    if (rows.isEmpty) return _state('No flock has been closed yet.');
    final pageRows = pageSlice(rows, _closedPage, _closedSize);
    Color profitColor(Map r) => tNum(r['profit']) >= 0 ? TColors.emerald700 : TColors.rose700;
    return MobileCardList<Map>(
      items: pageRows,
      keyOf: (r) => '${r['flockId']}',
      primary: (r) => tStr(r['flockName']),
      secondary: (r) => 'Closed ${_day(r['closedDate'])}${tStr(r['houseName']).isNotEmpty ? ' · ${tStr(r['houseName'])}' : ''}',
      highlights: (r) => [
        Highlight('Profit', _m(r['profit']), accent: tNum(r['profit']) >= 0 ? Accent.emerald : Accent.rose),
        Highlight('Per bird', _m(r['profitPerOriginalBird'])),
      ],
      details: (r) => [
        ('Batch', tStr(r['batchCode']).isEmpty ? '—' : tStr(r['batchCode'])),
        ('Placed', _n(tNum(r['originallyPlaced']))),
        ('Mortality', _pct(r['trackedMortalityRate'])),
        ('Eggs', _n(tNum(r['totalEggs']))),
        ('Revenue', _m(r['totalRevenue'])),
        ('Cost', _m(r['totalCost'])),
      ],
      actions: (r) => [
        OutlinedButton.icon(
          onPressed: () => _openLifetimePage(_id(r)),
          icon: const Icon(Icons.bar_chart, size: 16),
          label: Text('Lifetime${_perms.reopen ? ' & reopen' : ''}'),
        ),
      ],
      table: (items) => TrackerTable(
        columns: const [
          TCol('Flock', width: 170),
          TCol('Closed'),
          TCol('Batch'),
          TCol('Placed', right: true, width: 90),
          TCol('Mortality', right: true, width: 100),
          TCol('Eggs', right: true, width: 100),
          TCol('Revenue', right: true, width: 130),
          TCol('Cost', right: true, width: 130),
          TCol('Profit', right: true, width: 130),
          TCol('Per bird', right: true, width: 110),
          TCol('Actions', right: true, width: 190),
        ],
        rows: [
          for (final r in items)
            [
              _link(tStr(r['flockName']), () => _openLifetimePage(_id(r))),
              cellText(_day(r['closedDate'])),
              cellText(tStr(r['batchCode']).isEmpty ? '—' : tStr(r['batchCode'])),
              _right(_n(tNum(r['originallyPlaced']))),
              _right(_pct(r['trackedMortalityRate'])),
              _right(_n(tNum(r['totalEggs']))),
              _right(_m(r['totalRevenue'])),
              _right(_m(r['totalCost'])),
              _right(_m(r['profit']), color: profitColor(r), bold: true),
              _right(_m(r['profitPerOriginalBird'])),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: () => _lifetimeDialog(_id(r)),
                  icon: const Icon(Icons.bar_chart, size: 16),
                  label: Text(_perms.reopen ? 'Lifetime & reopen' : 'Lifetime'),
                ),
              ),
            ],
        ],
      ),
      pager: CompactPager(
        total: rows.length,
        page: _closedPage,
        pageSize: _closedSize,
        onPage: (p) => setState(() => _closedPage = p),
        onPageSize: (s) => setState(() {
          _closedSize = s;
          _closedPage = 1;
        }),
      ),
    );
  }

  // ------------------------------------------------------------- compare

  List<Widget> _compareTab() {
    final groups = groupLifetimeSummaries(
      _rows.where((r) => _compareScope == 'all' || r['status'] == 'Closed').toList(),
      _groupBy,
    )..sort((a, b) => b.profit.compareTo(a.profit));
    String feed(LifetimeGroup g) => g.feedKgPerDozenEggs == null ? '—' : '${g.feedKgPerDozenEggs!.toStringAsFixed(3)} kg';
    final groupLabel = lifetimeGroupOptions.firstWhere((o) => o.$1 == _groupBy).$2;
    return [
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        const Text('Compare by', style: TextStyle(fontSize: 13, color: TColors.slate600)),
        SizedBox(
          width: 160,
          child: AppSelect<String>(
            value: _groupBy,
            items: [for (final (v, l) in lifetimeGroupOptions) AppSelectItem(value: v, label: l)],
            onChanged: (v) => setState(() => _groupBy = v ?? _groupBy),
          ),
        ),
        SizedBox(
          width: 200,
          child: AppSelect<String>(
            value: _compareScope,
            items: const [
              AppSelectItem(value: 'closed', label: 'Closed flocks only'),
              AppSelectItem(value: 'all', label: 'Include open flocks'),
            ],
            onChanged: (v) => setState(() => _compareScope = v ?? _compareScope),
          ),
        ),
      ]),
      const SizedBox(height: 10),
      const Text(
        "Ratios are worked out from each group's totals, not averaged across flocks, so a large flock counts for more than a small one. Closed flocks give the fairest comparison: an open flock's story is not finished.",
        style: TextStyle(fontSize: 12, color: TColors.slate500),
      ),
      const SizedBox(height: 10),
      if (_loading)
        _loadingCard
      else if (groups.isEmpty)
        _state(_compareScope == 'closed' ? 'Close a flock to start comparing.' : 'No flocks yet.')
      else
        MobileCardList<LifetimeGroup>(
          items: groups,
          keyOf: (g) => g.key,
          primary: (g) => g.label,
          secondary: (g) => '${_n(g.flocks)} flock${g.flocks == 1 ? '' : 's'} · ${_n(g.originallyPlaced)} birds placed',
          highlights: (g) => [
            Highlight('Profit per bird', _m(g.profitPerOriginalBird),
                accent: (g.profitPerOriginalBird ?? 0) >= 0 ? Accent.emerald : Accent.rose),
            Highlight('Mortality', _pct(g.trackedMortalityRate)),
          ],
          details: (g) => [
            ('Revenue', _m(g.totalRevenue)),
            ('Cost', _m(g.totalCost)),
            ('Profit', _m(g.profit)),
            ('Eggs', _n(g.totalEggs)),
            ('Feed / dozen', feed(g)),
            ('Revenue per bird', _m(g.revenuePerOriginalBird)),
          ],
          table: (items) => TrackerTable(
            columns: [
              TCol(groupLabel, width: 160),
              const TCol('Flocks', right: true, width: 80),
              const TCol('Placed', right: true, width: 90),
              const TCol('Mortality', right: true, width: 100),
              const TCol('Eggs', right: true, width: 100),
              const TCol('Feed / dozen', right: true, width: 110),
              const TCol('Revenue', right: true, width: 130),
              const TCol('Cost', right: true, width: 130),
              const TCol('Profit', right: true, width: 130),
              const TCol('Profit / bird', right: true, width: 110),
              const TCol('Revenue / bird', right: true, width: 120),
            ],
            rows: [
              for (final g in items)
                [
                  cellText(g.label, bold: true),
                  _right(_n(g.flocks)),
                  _right(_n(g.originallyPlaced)),
                  _right(_pct(g.trackedMortalityRate)),
                  _right(_n(g.totalEggs)),
                  _right(feed(g)),
                  _right(_m(g.totalRevenue)),
                  _right(_m(g.totalCost)),
                  _right(_m(g.profit), color: g.profit >= 0 ? TColors.emerald700 : TColors.rose700, bold: true),
                  _right(_m(g.profitPerOriginalBird)),
                  _right(_m(g.revenuePerOriginalBird)),
                ],
            ],
          ),
        ),
    ];
  }
}

/// `app/flock-closeout/[flockId]/page.tsx`: one flock's lifetime performance,
/// closeout history and Reopen, with Close flock while it is open.
class FlockLifetimeScreen extends StatefulWidget {
  const FlockLifetimeScreen({super.key, required this.session, required this.company, required this.flockId});
  final Session session;
  final Company company;
  final int flockId;

  @override
  State<FlockLifetimeScreen> createState() => _FlockLifetimeScreenState();
}

class _FlockLifetimeScreenState extends State<FlockLifetimeScreen> {
  _Perms _perms = const _Perms();
  Map? _summary;
  int _reloadKey = 0;

  @override
  void initState() {
    super.initState();
    _loadPerms(widget.session, widget.company).then((p) {
      if (mounted) setState(() => _perms = p);
    });
  }

  void _refresh() {
    LookupLoader.clear();
    setState(() => _reloadKey += 1);
  }

  bool get _isOpenFlock => _summary?['status'] == 'Active' || _summary?['status'] == 'Inactive';

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/flock-closeout');
    final name = tStr(_summary?['flockName']);
    final validId = widget.flockId > 0;
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: Text(name.isEmpty ? 'Flock' : name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: TColors.slate600),
              onPressed: () {
                final nav = Navigator.of(context);
                if (nav.canPop()) {
                  nav.pop();
                } else {
                  nav.pushReplacement(MaterialPageRoute(
                    builder: (_) => FlockCloseoutScreen(session: widget.session, company: widget.company),
                  ));
                }
              },
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('Back to Flock Closeout'),
            ),
          ),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: _orange100, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.bar_chart, size: 20, color: _orange600),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name.isEmpty ? 'Flock' : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: TColors.slate900)),
                const SizedBox(height: 2),
                const Text('Lifetime performance — everything this flock produced, earned and cost.',
                    style: TextStyle(fontSize: 13, color: TColors.slate500)),
              ]),
            ),
          ]),
          if (_isOpenFlock && _perms.close) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () => showFlockCloseoutWizard(context,
                    session: widget.session, company: widget.company, flockId: widget.flockId, onClosed: _refresh),
                icon: const Icon(Icons.flag_outlined, size: 16),
                label: const Text('Close flock'),
              ),
            ),
          ],
          const SizedBox(height: 20),
          if (_perms.loaded && !_perms.view)
            _lockedCard()
          else if (!validId)
            TCard(
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text('That is not a valid flock.', style: TextStyle(color: TColors.slate600))),
              ),
            )
          else
            FlockLifetimeView(
              key: ValueKey(_reloadKey),
              session: widget.session,
              company: widget.company,
              flockId: widget.flockId,
              page: true,
              canReopen: _perms.reopen,
              onReopened: _refresh,
              onLoaded: (s) => setState(() => _summary = s),
            ),
        ],
      ),
    );
  }
}
