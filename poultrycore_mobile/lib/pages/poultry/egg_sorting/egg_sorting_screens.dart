// Poultry → Egg Sorting (app/poultry-egg-sorting/page.tsx), the Sort a pick /
// Sort all available eggs form (components/egg-sorting/sort-eggs-dialog.tsx,
// full screen as on a phone) and Setup → Egg Sorting Settings
// (app/poultry-egg-sorting-settings/page.tsx).
//
//   Sort a pick              — sort right after each collection
//   Sort all available eggs  — collect everything, sort later (oldest first)
// What is left is always read from the production record, never retyped.

import 'dart:math';

import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../shared/business_dates.dart';
import '../../shared/reason_dialog.dart' show showReasonDialog, companyToday;
import '../production/production_logic.dart' show PickSettings, eggsPerCrate, setEggsPerCrate;
import '../production/production_record_form.dart' show ProductionRecordPage;
import '../reports/report_routes.dart' show openAppHref;
import '../sales/balances_logic.dart' show pageSlice;
import '../sales/balances_widgets.dart' show CompactPager, LoadingLine;
import '../sales/payments_received_screen.dart' show fmtDateTimeLike;
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../trackers/tracker_widgets.dart';
import 'egg_sorting_logic.dart';
import 'egg_sorting_widgets.dart';
import '../../shared/reason_select.dart' show stockReversalReasons;

typedef PickLabels = ({String first, String second, String third, String fourth, String fifth, String sixth});

String _ld(Object? d) {
  final s = tStr(d);
  return formatLongDate(s.length >= 10 ? s.substring(0, 10) : s);
}

String _newRequestId() {
  final r = Random();
  String h(int n) => List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
  return '${h(8)}-${h(4)}-4${h(3)}-${h(4)}-${h(12)}';
}

/// poultry.egg-sorting.create / edit / delete: anyone but Staff on the phone.
bool _canWrite(Company c) => (c.role ?? '').toLowerCase() != 'staff';

Widget _stat(String label, String value, {String? sub, String? tone}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(), style: const TextStyle(fontSize: 10.5, letterSpacing: .4, color: TColors.slate500)),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.w600,
                color: tone == 'warn' ? TColors.amber700 : tone == 'good' ? TColors.emerald700 : TColors.slate900)),
        if (sub != null) Text(sub, style: const TextStyle(fontSize: 11, color: TColors.slate500)),
      ]),
    );

Widget _grid(List<Widget> cells, {int perRow = 2}) => Column(children: [
      for (var i = 0; i < cells.length; i += perRow) ...[
        if (i > 0) const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var j = 0; j < perRow; j++) ...[
            if (j > 0) const SizedBox(width: 8),
            Expanded(child: i + j < cells.length ? cells[i + j] : const SizedBox.shrink()),
          ],
        ]),
      ],
    ]);

Widget _statusChip(String status, {bool sold = false}) {
  if (sold) return const TBadge('Sold unsorted', bg: TColors.slate200, fg: TColors.slate700);
  final (bg, fg) = switch (status) {
    'Partial' => (TColors.amber100, TColors.amber800),
    'Complete' => (TColors.emerald100, TColors.emerald800),
    _ => (TColors.slate100, TColors.slate700),
  };
  return TBadge(statusLabel[status] ?? status, bg: bg, fg: fg);
}

const _accents = [Color(0xFFFBBF24), Color(0xFF38BDF8), Color(0xFFA78BFA), Color(0xFF34D399), Color(0xFFFB7185), Color(0xFF2DD4BF)];

// ------------------------------------------------------------------ workspace

class EggSortingWorkspaceScreen extends StatefulWidget {
  const EggSortingWorkspaceScreen({super.key, required this.session, required this.company, this.recordId, this.initialTab});
  final Session session;
  final Company company;

  /// `?record=` (from Production Records): one production record.
  final int? recordId;

  /// ?tab=settings (from Setup).
  final String? initialTab;

  @override
  State<EggSortingWorkspaceScreen> createState() => _EggSortingWorkspaceScreenState();
}

class _EggSortingWorkspaceScreenState extends State<EggSortingWorkspaceScreen> {
  late int? _record = widget.recordId;
  String _from = '', _to = '', _month = 'all';
  String _today = isoDay(DateTime.now());
  String _flock = 'all', _status = 'open';
  final _search = TextEditingController();
  late String _tab = widget.initialTab ?? 'workspace';

  Map? _settings;
  List<Map> _classes = [];
  Map? _summary;
  List<Map>? _picks, _openPicks;
  List<Map> _duplicates = [];
  bool _loading = false;
  String? _error;
  String? _lastDone;
  int _page = 1, _pageSize = 5;

  List<Map>? _sessions;
  String _sessionStatus = 'all';
  int? _openSession;
  int _sPage = 1, _sPageSize = 10;
  PickLabels _labels = const PickSettings().labels;

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  bool get _can => _canWrite(widget.company);
  bool get _sortingOn => _settings?['enableEggSorting'] == true;

  @override
  void initState() {
    super.initState();
    companyToday(widget.session, widget.company).then((t) {
      if (mounted) setState(() => _today = t);
    });
    PickSettings.load(widget.session, widget.company).then((p) {
      if (mounted) setState(() => _labels = p.labels);
    });
    _loadSetup();
    _load();
    if (_tab == 'sessions') _loadSessions();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadSetup() async {
    try {
      final s = await _api.get('/api/Poultry/egg-sorting/settings', query: {'farmId': _farmId});
      final on = s is Map && s['enableEggSorting'] == true;
      final n = s is Map ? tIntOrNull(s['eggsPerCrate']) : null;
      if (n != null && n > 0) setEggsPerCrate(n);
      final c = await _api.get('/api/Poultry/egg-sorting/classes', query: {'farmId': _farmId, 'includeInactive': 'true', 'ensure': '$on'});
      if (mounted) {
        setState(() {
          _settings = s is Map ? s : null;
          _classes = rowsOf(c);
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message.isNotEmpty ? e.message : 'Could not load egg sorting settings.');
    }
  }

  /// The picks query; record ids repeat as `recordIds=`.
  Future<List<Map>> _getPicks({String? from, String? to, List<int> recordIds = const []}) async {
    final qs = <String>[
      'farmId=${Uri.encodeQueryComponent(_farmId)}',
      if ((from ?? '').isNotEmpty) 'fromDate=$from',
      if ((to ?? '').isNotEmpty) 'toDate=$to',
      for (final id in recordIds) 'recordIds=$id',
    ].join('&');
    return rowsOf(await _api.get('/api/Poultry/egg-sorting/picks?$qs'));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Future.wait([
        _record != null ? _getPicks(recordIds: [_record!]) : _getPicks(from: _from, to: _to),
        _api.get('/api/Poultry/egg-sorting/summary', query: {'farmId': _farmId}),
        _api.get('/api/Poultry/egg-sorting/production-duplicates', query: {'farmId': _farmId}).then(rowsOf).catchError((Object _) => <Map>[]),
      ]);
      final sm = r[1] is Map ? r[1] as Map : const {};
      List<Map>? open = [];
      if (tNum(sm['recordsWithLeft']) > 0 && tStr(sm['oldestLeftDate']).isNotEmpty) {
        try {
          open = await _getPicks(from: tStr(sm['oldestLeftDate']).substring(0, 10), to: tStr(sm['businessDate']).substring(0, 10));
        } on ApiException {
          open = null;
        }
      }
      if (!mounted) return;
      setState(() {
        _picks = r[0] as List<Map>;
        _summary = sm;
        _openPicks = open;
        _duplicates = r[2] as List<Map>;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message.isNotEmpty ? e.message : 'Could not load production.');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadSessions() async {
    try {
      final from = _from.isNotEmpty ? _shift(_from, -30) : null;
      final r = await _api.get('/api/Poultry/egg-sorting/sessions', query: {
        'farmId': _farmId,
        'fromDate': from,
        'toDate': _today,
        'status': _sessionStatus == 'all' ? null : _sessionStatus,
      });
      if (mounted) setState(() => _sessions = rowsOf(r));
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load sortings', description: e.message, error: true);
    }
  }

  static String _shift(String d, int days) {
    final p = DateTime.tryParse(d);
    return p == null ? d : isoDay(p.add(Duration(days: days)));
  }

  // ------------------------------------------------------------ derived

  List<ProductionDay> get _days {
    final sm = _summary;
    final sortable = _openPicks != null && sm != null ? sortableByRecord(groupProductionDays(_openPicks!), tNum(sm['unsortedOnHand'])) : <int, num>{};
    return [for (final d in groupProductionDays(_picks ?? const [])) capToSortable(d, sortable[d.productionRecordId])];
  }

  List<(int, String)> _flocksOf(List<ProductionDay> days) {
    final m = <int, String>{};
    for (final d in days) {
      m[d.flockId] = d.flockName;
    }
    return m.entries.map((e) => (e.key, e.value)).toList()..sort((a, b) => a.$2.compareTo(b.$2));
  }

  List<(String, String)> get _monthOptions {
    final p = _today.split('-').map(int.parse).toList();
    const names = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return [
      for (var i = 0; i < 12; i++)
        () {
          final d = DateTime.utc(p[0], p[1] - i, 1);
          return ('${d.year}-${d.month.toString().padLeft(2, '0')}', '${names[d.month - 1]} ${d.year}');
        }(),
    ];
  }

  void _pickMonth(String v) {
    if (v == 'custom') return;
    setState(() {
      _month = v;
      if (v == 'all') {
        _from = '';
        _to = '';
      } else {
        final p = v.split('-').map(int.parse).toList();
        final last = '$v-${DateTime.utc(p[0], p[1] + 1, 0).day.toString().padLeft(2, '0')}';
        _from = '$v-01';
        _to = last.compareTo(_today) > 0 ? _today : last;
      }
      _page = 1;
    });
    _load();
  }

  // ------------------------------------------------------------ actions

  void _onDone(String message, bool refresh) {
    if (message.isNotEmpty) {
      setState(() => _lastDone = message);
      trackerToast(context, message.startsWith('Draft') ? 'Draft saved' : 'Sorting posted', description: message);
    }
    if (refresh) {
      _load();
      _loadSetup();
      if (_tab == 'sessions') _loadSessions();
    }
  }

  Future<void> _openSort(SortTarget target) async {
    final sizes = [for (final c in _classes) if (c['classKind'] == 'Size') c];
    final res = await Navigator.of(context).push<(String, bool)>(MaterialPageRoute(
      builder: (_) => SortEggsScreen(
        session: widget.session,
        company: widget.company,
        target: target,
        sizes: sizes,
        today: _today,
        labels: _labels,
        canPost: _can,
      ),
    ));
    if (res != null && mounted) _onDone(res.$1, res.$2);
  }

  void _sortAll(ProductionDay day, List<ProductionDay> days) => _openSort(SortTarget(
        mode: 'Combined',
        day: day,
        otherDays: [for (final d in days) if (d.flockId == day.flockId && d.productionRecordId != day.productionRecordId && d.left > 0) d],
      ));

  /// Re-open a draft against fresh availability for its own records.
  Future<void> _editDraft(Map s) async {
    try {
      final ids = [for (final x in (s['scopeRecordIds'] as List? ?? const [])) tIntOrNull(x) ?? 0];
      final ds = groupProductionDays(await _getPicks(recordIds: ids));
      final want = tIntOrNull(s['productionRecordId']) ?? (ids.isEmpty ? null : ids.first);
      final day = ds.where((d) => d.productionRecordId == want).firstOrNull ?? ds.firstOrNull;
      if (day == null) throw ApiException(0, 'The production record behind this draft no longer exists.');
      final byPick = s['sortingMode'] == 'ByPick';
      await _openSort(SortTarget(
        mode: tStr(s['sortingMode']),
        day: day,
        draft: s,
        pick: byPick ? day.picks.where((p) => tIntOrNull(p['pickNumber']) == tIntOrNull(s['pickNumber'])).firstOrNull : null,
        otherDays: [for (final d in ds) if (d.productionRecordId != day.productionRecordId) d],
      ));
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not open the draft', description: e.message, error: true);
    }
  }

  Future<void> _discard(Map s) async {
    try {
      await _api.delete('/api/Poultry/egg-sorting/sessions/${s['sessionId']}?farmId=${Uri.encodeQueryComponent(_farmId)}');
      if (mounted) trackerToast(context, 'Draft ${s['sessionNo']} discarded');
      _loadSessions();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Not discarded', description: e.message, error: true);
    }
  }

  Future<void> _reverse(Map s) async {
    final reason = await showReasonDialog(
      context,
      title: 'Reverse ${s['sessionNo'] ?? 'this sorting'}?',
      options: stockReversalReasons,
      description:
          'The sized eggs go back into Unsorted and the picks can be sorted again. The sorting stays in the history, marked Reversed. If any of its sized eggs were already sold or used, reverse those first.',
      confirmLabel: 'Reverse',
      destructive: true,
    );
    if (reason == null) return;
    try {
      await _api.post('/api/Poultry/egg-sorting/sessions/${s['sessionId']}/reversal', body: {'farmId': _farmId, 'reason': reason});
      if (mounted) {
        trackerToast(context, '${s['sessionNo']} reversed', description: 'The sized eggs went back into Unsorted, and the picks can be sorted again.');
      }
      _loadSessions();
      _load();
      _loadSetup();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Not reversed', description: e.message, error: true);
    }
  }

  void _openProduction(ProductionDay d) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ProductionRecordPage(
          session: widget.session,
          company: widget.company,
          recordId: d.productionRecordId,
          returnTo: _record != null ? '/poultry-egg-sorting?record=$_record' : '/poultry-egg-sorting',
        ),
      ));

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-egg-sorting');
    final sm = _summary;
    final remaining = sm == null ? 0 : min(tNum(sm['productionLeft']), max<num>(0, tNum(sm['unsortedOnHand']).truncate()));

    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Egg Sorting')),
      body: RefreshIndicator(
        onRefresh: () async {
          await _load();
          await _loadSetup();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: TColors.amber100, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.egg_outlined, size: 20, color: TColors.amber700),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Egg Sorting', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: TColors.slate900)),
                  Text(
                    'Sort collected eggs into sizes — one pick at a time, or everything at once. Sorting never creates eggs: it moves them from Unsorted into sizes, and records what was lost.',
                    style: TextStyle(fontSize: 13, color: TColors.slate600),
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => openAppHref(context, widget.session, widget.company, '/egg-tracker', label: 'Egg tracker'),
                  child: const Text('View Egg Tracker'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => openAppHref(context, widget.session, widget.company, '/production-records', label: 'Production Records'),
                  child: const Text('View production'),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            if (_settings != null && !_sortingOn) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: TColors.amber50, border: Border.all(color: TColors.amber200), borderRadius: BorderRadius.circular(10)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Text.rich(
                    TextSpan(children: [
                      TextSpan(text: 'Egg sorting is '),
                      TextSpan(text: 'off', style: TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(
                          text: ' for this farm. Production goes into Unsorted / General eggs, which you can sell directly. Turn sorting on to grade eggs into sizes.'),
                    ]),
                    style: TextStyle(fontSize: 13, color: TColors.amber900),
                  ),
                  if (_can) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton(onPressed: () => setState(() => _tab = 'settings'), child: const Text('Sizes & settings')),
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: 12),
            ],
            if (_duplicates.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFFFF1F2), border: Border.all(color: TColors.rose200), borderRadius: BorderRadius.circular(10)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFF881337)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(
                              text: '${_duplicates.length} flock-day${_duplicates.length == 1 ? ' has' : 's have'} more than one production record',
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          const TextSpan(
                              text: ', from before the one-record-per-day rule. Each record is sorted on its own; merge them in Production Records when you can.'),
                        ]),
                        style: const TextStyle(fontSize: 13, color: Color(0xFF881337)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_duplicates.take(6).map((d) => '${tStr(d['flockName']).isEmpty ? 'Flock ${d['flockId']}' : d['flockName']} — ${_ld(d['productionDate'])} (${d['recordCount']} records)').join(' · ')}'
                        '${_duplicates.length > 6 ? ' …' : ''}',
                        style: const TextStyle(fontSize: 12, color: TColors.rose800),
                      ),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
            ],
            if (sm != null) ...[
              _grid([
                _stat('Unsorted in stock', fmtCount(tNum(sm['unsortedOnHand'])), sub: cratesText(tNum(sm['unsortedOnHand']), eggsPerCrate)),
                _stat('Remaining to sort', fmtCount(remaining),
                    sub: tStr(sm['oldestLeftDate']).isNotEmpty ? 'oldest ${_ld(sm['oldestLeftDate'])}' : null, tone: remaining > 0 ? 'warn' : 'good'),
                _stat('Sorted today', fmtCount(tNum(sm['sortedToday'])),
                    sub: '${sm['sessionsToday'] ?? 0} sorting${tNum(sm['sessionsToday']) == 1 ? '' : 's'}'),
                _stat('Sized eggs created', fmtCount(tNum(sm['sizedCreatedToday'])), sub: 'today'),
                _stat('Sorting loss', fmtCount(tNum(sm['lossToday'])), sub: 'today · ${pct(tNum(sm['lossToday']), tNum(sm['sortedToday']))}'),
                _stat('Sized in stock', fmtCount(tNum(sm['sizedOnHand'])), sub: cratesText(tNum(sm['sizedOnHand']), eggsPerCrate)),
              ]),
              const SizedBox(height: 12),
            ],
            if (_lastDone != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: TColors.emerald50, border: Border.all(color: TColors.emerald200), borderRadius: BorderRadius.circular(10)),
                child: Text(_lastDone!, style: const TextStyle(fontSize: 13, color: TColors.emerald900)),
              ),
              const SizedBox(height: 12),
            ],
            // Phone: a 2 × 2 grid, so every tab is visible without scrolling.
            _grid([
              _tabButton('workspace', 'Workspace', Icons.egg_outlined, const Color(0xFFF59E0B)),
              _tabButton('sessions', 'Sortings', Icons.history, const Color(0xFF0284C7)),
              _tabButton('reports', 'Size reports', Icons.bar_chart, const Color(0xFF7C3AED)),
              _tabButton('settings', 'Sizes & settings', Icons.tune, TColors.emerald600),
            ]),
            const SizedBox(height: 14),
            ...switch (_tab) {
              'sessions' => _sessionsTab(),
              'reports' => [
                  CompositionReport(
                    key: ValueKey('rep-$_flock-$_today'),
                    session: widget.session,
                    company: widget.company,
                    from: _shift(_today, -29),
                    to: _today,
                    flockId: _flock == 'all' ? null : int.tryParse(_flock),
                  ),
                ],
              'settings' => [
                  SizesSettingsPanel(
                    session: widget.session,
                    company: widget.company,
                    settings: _settings,
                    classes: _classes,
                    canEdit: _can,
                    onChanged: _loadSetup,
                  ),
                  if (_unsortedClass != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Unsorted / General eggs on hand: ${fmtCount(tNum(_unsortedClass!['onHand']))} (${cratesText(tNum(_unsortedClass!['onHand']), eggsPerCrate)}). Production always adds to Unsorted.',
                      style: const TextStyle(fontSize: 12, color: TColors.slate500),
                    ),
                  ],
                ],
              _ => _workspaceTab(),
            },
          ],
        ),
      ),
    );
  }

  Map? get _unsortedClass => _classes.where((c) => c['classKind'] == 'Unsorted').firstOrNull;

  Widget _tabButton(String key, String label, IconData icon, Color color) {
    final on = _tab == key;
    return InkWell(
      onTap: () {
        setState(() => _tab = key);
        if (key == 'sessions') _loadSessions();
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: on ? color : Colors.white,
          border: Border.all(color: on ? color : TColors.slate200),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 16, color: on ? Colors.white : TColors.slate700),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: on ? Colors.white : TColors.slate700)),
          ),
        ]),
      ),
    );
  }

  List<Widget> _workspaceTab() {
    final days = _days;
    final flocks = _flocksOf(days);
    final q = _search.text.trim().toLowerCase();
    final shown = [
      for (final d in days)
        if ((_flock == 'all' || '${d.flockId}' == _flock) &&
            (_status == 'all' || (_status == 'open' ? d.left > 0 : d.status == _status)) &&
            (q.isEmpty || '${d.flockName} ${d.batchName ?? ''} ${d.houseName ?? ''}'.toLowerCase().contains(q)))
          d,
    ];
    // "All flocks": one section per flock (newest day first inside each).
    final group = _flock == 'all' && _record == null;
    final ordered = group
        ? ([...shown]..sort((a, b) {
            var c = a.flockName.compareTo(b.flockName);
            if (c != 0) return c;
            c = a.flockId.compareTo(b.flockId);
            return c != 0 ? c : b.productionDate.compareTo(a.productionDate);
          }))
        : shown;
    final totals = <int, ({int days, num saleable, num sorted, num left, int first})>{};
    for (final d in ordered) {
      final t = totals[d.flockId];
      totals[d.flockId] = t == null
          ? (days: 1, saleable: d.saleable, sorted: d.sorted, left: d.left, first: d.productionRecordId)
          : (days: t.days + 1, saleable: t.saleable + d.saleable, sorted: t.sorted + d.sorted, left: t.left + d.left, first: t.first);
    }
    final pageItems = pageSlice(ordered, _page, _pageSize);
    final runs = <(int, List<ProductionDay>)>[];
    for (final d in pageItems) {
      if (runs.isNotEmpty && runs.last.$1 == d.flockId) {
        runs.last.$2.add(d);
      } else {
        runs.add((d.flockId, [d]));
      }
    }

    return [
      if (_record != null)
        _box(Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('Showing one production record (#$_record).', style: const TextStyle(fontSize: 13, color: TColors.slate700)),
          OutlinedButton(
            onPressed: () {
              setState(() => _record = null);
              _load();
            },
            child: const Text('Show all production'),
          ),
        ]))
      else
        _box(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FilterLabel(
            'Month',
            AppSelect<String>(
              value: _month,
              items: [
                const AppSelectItem(value: 'all', label: 'All months'),
                if (_month == 'custom') const AppSelectItem(value: 'custom', label: 'Custom dates'),
                for (final (v, l) in _monthOptions) AppSelectItem(value: v, label: l),
              ],
              onChanged: (v) => _pickMonth(v ?? 'all'),
            ),
          ),
          const SizedBox(height: 10),
          filterRow([
            FilterLabel('Production from', FilterDate(value: _from, hint: 'From', onChanged: (v) {
              setState(() {
                _from = v;
                _month = 'custom';
                _page = 1;
              });
              _load();
            })),
            FilterLabel('Production to', FilterDate(value: _to, hint: 'To', onChanged: (v) {
              setState(() {
                _to = v;
                _month = 'custom';
                _page = 1;
              });
              _load();
            })),
          ]),
          const SizedBox(height: 10),
          filterRow([
            FilterLabel(
              'Flock',
              AppSelect<String>(
                value: _flock,
                items: [
                  const AppSelectItem(value: 'all', label: 'All flocks'),
                  for (final (id, name) in flocks) AppSelectItem(value: '$id', label: name),
                ],
                onChanged: (v) => setState(() {
                  _flock = v ?? 'all';
                  _page = 1;
                }),
              ),
            ),
            FilterLabel(
              'Status',
              AppSelect<String>(
                value: _status,
                items: const [
                  AppSelectItem(value: 'open', label: 'Can be sorted'),
                  AppSelectItem(value: 'all', label: 'All'),
                  AppSelectItem(value: 'NotStarted', label: 'Not started'),
                  AppSelectItem(value: 'Partial', label: 'Partial'),
                  AppSelectItem(value: 'Complete', label: 'Complete'),
                ],
                onChanged: (v) => setState(() {
                  _status = v ?? 'open';
                  _page = 1;
                }),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          FilterLabel(
            'Search',
            AppInput(controller: _search, hintText: 'Flock, batch, house', onChanged: (_) => setState(() => _page = 1)),
          ),
        ])),
      const SizedBox(height: 12),
      if (_error != null) ...[TrackerBanner.error(_error!), const SizedBox(height: 12)],
      if (_loading && _picks == null) const LoadingLine('Loading production…'),
      if (_picks != null && shown.isEmpty)
        _box(Text(
          days.isEmpty
              ? 'No production recorded in this period. Eggs appear here once a production record is saved — sorting never needs one of its own.'
              : _status == 'open'
                  ? 'Nothing left to sort here — every egg was sorted, or sold before it could be. Set Status to All to see these days.'
                  : 'Nothing matches these filters.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: TColors.slate500),
        )),
      if (group)
        for (final (fid, run) in runs) _flockSection(fid, run, totals[fid], flocks, days)
      else
        for (final d in pageItems) ...[_dayCard(d, false, days), const SizedBox(height: 12)],
      if (ordered.isNotEmpty)
        CompactPager(
          total: ordered.length,
          page: _page,
          pageSize: _pageSize,
          onPage: (p) => setState(() => _page = p),
          onPageSize: (s) => setState(() {
            _pageSize = s;
            _page = 1;
          }),
        ),
    ];
  }

  Widget _box(Widget child) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
        child: child,
      );

  Widget _flockSection(int fid, List<ProductionDay> run, ({int days, num saleable, num sorted, num left, int first})? t, List<(int, String)> flocks,
      List<ProductionDay> days) {
    final first = run.first;
    final i = flocks.indexWhere((f) => f.$1 == fid);
    final accent = _accents[(i < 0 ? 0 : i) % _accents.length];
    final continued = t != null && t.first != first.productionRecordId;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: const Color(0xB3F1F5F9), border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
      child: Stack(children: [
        Positioned(left: 0, top: 0, bottom: 0, width: 4, child: ColoredBox(color: accent)),
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 12, height: 12, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: first.flockName),
                      if (continued) const TextSpan(text: '  (continued)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: TColors.slate500)),
                    ]),
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: TColors.slate900),
                  ),
                ),
              ]),
              Text([first.batchName, first.houseName].whereType<String>().join(' · ').isEmpty ? 'Flock' : [first.batchName, first.houseName].whereType<String>().join(' · '),
                  style: const TextStyle(fontSize: 12, color: TColors.slate500)),
              if (t != null) ...[
                const SizedBox(height: 4),
                Wrap(spacing: 12, children: [
                  Text('${t.days} day${t.days == 1 ? '' : 's'}', style: const TextStyle(fontSize: 12, color: TColors.slate600)),
                  Text('Sorted ${fmtCount(t.sorted)} of ${fmtCount(t.saleable)}', style: const TextStyle(fontSize: 12, color: TColors.slate600)),
                  Text(t.left > 0 ? 'Remaining ${fmtCount(t.left)}' : 'All sorted',
                      style: TextStyle(fontSize: 12, color: t.left > 0 ? TColors.amber700 : TColors.emerald700)),
                ]),
              ],
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 0),
            child: Column(children: [for (final d in run) ...[_dayCard(d, true, days), const SizedBox(height: 8)]]),
          ),
        ]),
      ]),
    );
  }

  Widget _dayCard(ProductionDay d, bool grouped, List<ProductionDay> days) {
    final progress = d.saleable > 0 ? min(100, d.sorted / d.saleable * 100) : 0;
    final canSort = _can && _sortingOn;
    return _box(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(grouped ? _ld(d.productionDate) : '${d.flockName} — ${_ld(d.productionDate)}',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: TColors.slate900)),
      Text([d.batchName, d.houseName].whereType<String>().join(' · '), style: const TextStyle(fontSize: 12, color: TColors.slate500)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: () => _openProduction(d), child: const Text('View production'))),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: TColors.emerald600),
            onPressed: !canSort || d.left <= 0 ? null : () => _sortAll(d, days),
            icon: const Icon(Icons.layers_outlined, size: 16),
            label: const Text('Sort all'),
          ),
        ),
      ]),
      const SizedBox(height: 10),
      _grid([
        _stat('Production (saleable)', fmtCount(d.saleable),
            sub: d.collectionLoss != 0 ? '${fmtCount(d.gross)} collected, ${fmtCount(d.collectionLoss)} broken/lost' : cratesText(d.saleable, eggsPerCrate)),
        _stat('Sorted', fmtCount(d.sorted)),
        _stat('Can be sorted', fmtCount(d.left), tone: d.left > 0 ? 'warn' : 'good', sub: d.soldUnsorted != 0 ? '${fmtCount(d.soldUnsorted)} sold unsorted' : null),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Wraps: in a narrow tile the chip goes under the label.
            Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              const Text('PROGRESS', style: TextStyle(fontSize: 10.5, letterSpacing: .4, color: TColors.slate500)),
              _statusChip(d.status, sold: d.soldUnsorted != 0 && d.left <= 0 && d.sorted <= 0),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress / 100,
                minHeight: 8,
                backgroundColor: TColors.slate100,
                color: d.left <= 0 ? TColors.emerald500 : const Color(0xFFF59E0B),
              ),
            ),
            Text('${progress.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 11, color: TColors.slate500)),
          ]),
        ),
      ]),
      const SizedBox(height: 10),
      // Phone: one compact block per pick.
      Container(
        decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
        child: Column(children: [
          for (var i = 0; i < d.picks.length; i++)
            () {
              final p = d.picks[i];
              final left = pickRemaining(p);
              return Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: TColors.slate100))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(
                      child: Text(pickLabel(tIntOrNull(p['pickNumber']) ?? 0, _labels),
                          style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.slate900)),
                    ),
                    _statusChip(pickStatus(p), sold: d.soldUnsorted != 0 && left <= 0 && tNum(p['pickLeft']) > 0),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(child: _mini('Collected', fmtCount(tNum(p['pickGross'])))),
                    Expanded(child: _mini('Sorted', fmtCount(tNum(p['pickSorted'])))),
                    Expanded(child: _mini('Can sort', fmtCount(left), color: left > 0 ? TColors.amber700 : TColors.emerald700)),
                  ]),
                  const SizedBox(height: 6),
                  OutlinedButton(
                    onPressed: !canSort || left <= 0 ? null : () => _openSort(SortTarget(mode: 'ByPick', day: d, pick: p)),
                    child: Text(tNum(p['pickSorted']) > 0 && left > 0 ? 'Continue sorting' : 'Sort pick'),
                  ),
                ]),
              );
            }(),
        ]),
      ),
      if (d.soldUnsorted != 0) ...[
        const SizedBox(height: 6),
        Text(
          "${fmtCount(d.soldUnsorted)} of this day's eggs were sold or used unsorted, so they cannot be sorted. Sold eggs are counted from the oldest days first.",
          style: const TextStyle(fontSize: 12, color: TColors.slate500),
        ),
      ],
      if (d.collectionLoss > 0) ...[
        const SizedBox(height: 6),
        Text(
          'Broken, meaty, soft and lost eggs are recorded for the whole day, not per pick, so the day can be sorted up to its ${fmtCount(d.saleable)} saleable eggs.',
          style: const TextStyle(fontSize: 12, color: TColors.slate500),
        ),
      ],
    ]));
  }

  Widget _mini(String l, String v, {Color? color}) => Column(children: [
        Text(l, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
        Text(v, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color ?? TColors.slate900)),
      ]);

  List<Widget> _sessionsTab() {
    final sessions = _sessions;
    return [
      FilterLabel(
        'Status',
        AppSelect<String>(
          value: _sessionStatus,
          items: const [
            AppSelectItem(value: 'all', label: 'All'),
            AppSelectItem(value: 'Draft', label: 'Drafts'),
            AppSelectItem(value: 'Posted', label: 'Posted'),
            AppSelectItem(value: 'Reversed', label: 'Reversed'),
          ],
          onChanged: (v) {
            setState(() {
              _sessionStatus = v ?? 'all';
              _sPage = 1;
            });
            _loadSessions();
          },
        ),
      ),
      const SizedBox(height: 6),
      Text(_from.isNotEmpty ? 'Last 30 days before ${formatLongDate(_from)} to today.' : 'All sortings.',
          style: const TextStyle(fontSize: 12, color: TColors.slate500)),
      const SizedBox(height: 10),
      if (sessions == null) const LoadingLine('Loading…'),
      if (sessions != null && sessions.isEmpty) const Text('No sortings yet.', style: TextStyle(fontSize: 13, color: TColors.slate500)),
      if (sessions != null && sessions.isNotEmpty)
        Container(
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            for (final s in pageSlice(sessions, _sPage, _sPageSize)) _sessionCard(s),
            CompactPager(
              total: sessions.length,
              page: _sPage,
              pageSize: _sPageSize,
              onPage: (p) => setState(() => _sPage = p),
              onPageSize: (v) => setState(() {
                _sPageSize = v;
                _sPage = 1;
              }),
            ),
          ]),
        ),
    ];
  }

  Widget _sessionCard(Map s) {
    final id = tIntOrNull(s['sessionId']);
    final open = _openSession == id;
    final status = tStr(s['status']);
    final (bg, fg) = switch (status) {
      'Posted' => (TColors.emerald100, TColors.emerald800),
      'Draft' => (TColors.sky100, TColors.sky800),
      _ => (TColors.slate200, TColors.slate700),
    };
    final byPick = s['sortingMode'] == 'ByPick';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: TColors.slate100))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: () => setState(() => _openSession = open ? null : id),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 16),
                  Text(tStr(s['sessionNo']), style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.slate900)),
                ]),
                Text('${tStr(s['flockName']).isEmpty ? 'Flock ${s['flockId']}' : s['flockName']} · sorted ${_ld(s['sortingDate'])}',
                    overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                Text(byPick ? pickShort(tIntOrNull(s['pickNumber']) ?? 0, _labels) : 'All available',
                    style: const TextStyle(fontSize: 12, color: TColors.slate500)),
              ]),
            ),
            TBadge(status, bg: bg, fg: fg),
          ]),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _mini('Sorted', fmtCount(tNum(s['inputQuantity'])))),
          Expanded(child: _mini('Into sizes', fmtCount(tNum(s['outputQuantity'])))),
          Expanded(child: _mini('Loss', fmtCount(tNum(s['lossQuantity'])))),
        ]),
        if (status == 'Draft') ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _can ? () => _editDraft(s) : null,
                icon: const Icon(Icons.edit_outlined, size: 15),
                label: const Text('Open'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: TColors.rose700),
                onPressed: _can ? () => _discard(s) : null,
                icon: const Icon(Icons.delete_outline, size: 15),
                label: const Text('Discard'),
              ),
            ),
          ]),
        ],
        if (status == 'Posted') ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: TColors.rose700),
            onPressed: _can ? () => _reverse(s) : null,
            icon: const Icon(Icons.restart_alt, size: 15),
            label: const Text('Reverse'),
          ),
        ],
        if (open) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: TColors.slate50, borderRadius: BorderRadius.circular(6)),
            child: _sessionDetail(s),
          ),
        ],
      ]),
    );
  }

  /// What a sorting graded, where its eggs came from, and its history.
  Widget _sessionDetail(Map s) {
    const head = TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: .4, color: TColors.slate500);
    final lines = [for (final l in (s['lines'] as List? ?? const [])) if (l is Map) l];
    final sources = [for (final l in (s['sources'] as List? ?? const [])) if (l is Map) l];
    Widget row(String l, String v, {Color? color}) => Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: TColors.slate100))),
          child: Row(children: [
            Expanded(child: Text(l, style: TextStyle(fontSize: 13, color: color))),
            Text(v, style: const TextStyle(fontSize: 13)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('GRADING', style: head),
      for (final l in lines)
        row(lineTypeLabel(l['lineType'], l['sizeName']), '${fmtCount(tNum(l['quantity']))} (${pct(tNum(l['quantity']), tNum(s['inputQuantity']))})',
            color: l['lineType'] != 'SizedOutput' ? TColors.rose800 : null),
      const SizedBox(height: 10),
      const Text('CAME FROM', style: head),
      if (sources.isEmpty) const Text('Allocated when posted.', style: TextStyle(fontSize: 13, color: TColors.slate500)),
      for (final src in sources) row('${_ld(src['productionDate'])} · ${pickShort(tIntOrNull(src['pickNumber']) ?? 0, _labels)}', fmtCount(tNum(src['quantity']))),
      const SizedBox(height: 6),
      Text(
        '${tStr(s['postedAtUtc']).isNotEmpty ? 'Posted ${fmtDateTimeLike(s['postedAtUtc'])} by ${tStr(s['postedBy']).isEmpty ? '—' : s['postedBy']}.' : 'Saved by ${tStr(s['createdBy']).isEmpty ? '—' : s['createdBy']}.'}'
        '${tStr(s['reversedAtUtc']).isNotEmpty ? ' Reversed ${fmtDateTimeLike(s['reversedAtUtc'])} by ${tStr(s['reversedBy']).isEmpty ? '—' : s['reversedBy']}: ${tStr(s['reversalReason'])}' : ''}'
        '${tStr(s['notes']).isNotEmpty ? ' Note: ${s['notes']}' : ''}',
        style: const TextStyle(fontSize: 12, color: TColors.slate500),
      ),
      const SizedBox(height: 10),
      const Text('HISTORY', style: head),
      const SizedBox(height: 4),
      EggSortingAuditList(session: widget.session, company: widget.company, entity: 'Sorting', entityId: tIntOrNull(s['sessionId']), limit: 20, bare: true),
    ]);
  }
}

// ------------------------------------------------------------------ sort eggs

/// What a sort starts from: a pick (ByPick) or a day and its flock's other
/// open days (Combined), or a draft being reopened.
class SortTarget {
  const SortTarget({required this.mode, required this.day, this.pick, this.otherDays = const [], this.draft});
  final String mode; // ByPick | Combined
  final ProductionDay day;
  final Map? pick;
  final List<ProductionDay> otherDays;
  final Map? draft;
}

/// Sort a pick / Sort all available eggs. The user enters only how the eggs
/// graded — sizes and losses — so a sorting always balances. Pops (message,
/// refresh).
class SortEggsScreen extends StatefulWidget {
  const SortEggsScreen({
    super.key,
    required this.session,
    required this.company,
    required this.target,
    required this.sizes,
    required this.today,
    required this.labels,
    required this.canPost,
  });
  final Session session;
  final Company company;
  final SortTarget target;
  final List<Map> sizes;
  final String today;
  final PickLabels labels;
  final bool canPost;

  @override
  State<SortEggsScreen> createState() => _SortEggsScreenState();
}

class _SortEggsScreenState extends State<SortEggsScreen> {
  SortTarget get t => widget.target;
  late String _date;
  late Set<int> _scope;
  final Map<String, TextEditingController> _qty = {};
  final _notes = TextEditingController();
  final String _requestId = _newRequestId();
  String? _busy;

  List<Map> get _activeSizes => [for (final s in widget.sizes) if (s['classKind'] == 'Size' && s['isActive'] == true) s]
    ..sort((a, b) {
      final o = tNum(a['sortOrder']).compareTo(tNum(b['sortOrder']));
      return o != 0 ? o : tStr(a['name']).compareTo(tStr(b['name']));
    });

  List<ProductionDay> get _allDays {
    final seen = <int, ProductionDay>{};
    for (final d in [t.day, ...t.otherDays]) {
      seen[d.productionRecordId] = d;
    }
    return seen.values.toList()..sort((a, b) => a.productionDate.compareTo(b.productionDate));
  }

  @override
  void initState() {
    super.initState();
    final d = t.draft;
    final dd = tStr(d?['sortingDate']);
    _date = dd.length >= 10 ? dd.substring(0, 10) : (t.day.productionDate.compareTo(widget.today) > 0 ? t.day.productionDate : widget.today);
    final scope = [for (final x in (d?['scopeRecordIds'] as List? ?? const [])) tIntOrNull(x) ?? 0];
    _scope = scope.isNotEmpty ? scope.toSet() : {t.day.productionRecordId};
    for (final l in (d?['lines'] as List? ?? const [])) {
      if (l is! Map) continue;
      final key = l['lineType'] == 'SizedOutput' ? 'size:${l['eggSizeId']}' : 'loss:${l['lineType']}';
      _ctl(key).text = '${tIntOrNull(l['quantity']) ?? ''}';
    }
    _notes.text = tStr(d?['notes']);
  }

  @override
  void dispose() {
    for (final c in [..._qty.values, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _ctl(String key) => _qty.putIfAbsent(key, () => TextEditingController());

  num get _available => t.mode == 'ByPick'
      ? max<num>(0, tNum(t.pick?['available']))
      : _allDays.where((d) => _scope.contains(d.productionRecordId)).fold<num>(0, (s, d) => s + max<num>(0, d.left));

  List<SortingLine> get _lines => [
        for (final s in _activeSizes)
          SortingLine(key: 'size:${s['eggSizeId']}', lineType: 'SizedOutput', eggSizeId: tIntOrNull(s['eggSizeId']), text: _ctl('size:${s['eggSizeId']}').text),
        for (final (k, _) in lossTypes) SortingLine(key: 'loss:$k', lineType: k, text: _ctl('loss:$k').text),
      ];

  Future<void> _submit(bool post) async {
    setState(() => _busy = post ? 'post' : 'draft');
    final bal = sortingBalance(_available, _lines);
    final api = widget.session.farmClient;
    final farmId = widget.company.farmId;
    final body = {
      'sortingMode': t.mode,
      'sortingDate': _date,
      'productionRecordIds': t.mode == 'ByPick' ? [t.day.productionRecordId] : _scope.toList(),
      'pickNumber': t.mode == 'ByPick' ? tIntOrNull(t.pick?['pickNumber']) : null,
      'lines': toApiLines(_lines),
      'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      'clientRequestId': t.draft != null ? null : _requestId,
      'post': post,
      'farmId': farmId,
    };
    try {
      final sid = tIntOrNull(t.draft?['sessionId']);
      if (sid != null) {
        await api.put('/api/Poultry/egg-sorting/sessions/$sid', body: body);
      } else {
        await api.post('/api/Poultry/egg-sorting/sessions', body: body);
      }
      if (!mounted) return;
      Navigator.pop(
        context,
        (
          post
              ? '${fmtCount(bal.input)} eggs sorted: ${fmtCount(bal.sized)} into sizes${bal.loss != 0 ? ', ${fmtCount(bal.loss)} lost' : ''}.'
              : 'Draft saved. It moves no stock until you post it.',
          true,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      final conflict = e.statusCode == 409;
      trackerToast(context, conflict ? 'Not enough eggs left' : post ? 'Not posted' : 'Not saved', description: e.message, error: true);
      setState(() => _busy = null);
      if (conflict) Navigator.pop(context, ('', true));
    }
  }

  Widget _fact(String label, String value, {String? sub, bool strong = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 10.5, letterSpacing: .4, color: TColors.slate500)),
          Text(value, style: TextStyle(fontWeight: strong ? FontWeight.w700 : FontWeight.w600)),
          if (sub != null) Text(sub, style: const TextStyle(fontSize: 11, color: TColors.slate500)),
        ]),
      );

  Widget _tally(String label, String value, {bool strong = false, String? tone}) => Text.rich(TextSpan(children: [
        TextSpan(text: '$label ', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
        TextSpan(
          text: value,
          style: TextStyle(
            fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
            color: tone == 'bad' ? TColors.rose700 : tone == 'good' ? TColors.emerald700 : TColors.slate900,
          ),
        ),
      ]));

  @override
  Widget build(BuildContext context) {
    final day = t.day, pick = t.pick;
    final lines = _lines;
    final bal = sortingBalance(_available, lines);
    final blocker = sortingBlocker(bal);
    final scoped = _allDays.where((d) => _scope.contains(d.productionRecordId)).map((d) => d.productionDate).toList()..sort();
    final earliest = scoped.isNotEmpty ? scoped.first : day.productionDate;
    final dateProblem = _date.compareTo(widget.today) > 0
        ? 'The sorting date cannot be in the future.'
        : _date.compareTo(earliest) < 0
            ? 'Eggs cannot be sorted before they were collected.'
            : null;
    final sizes = _activeSizes;
    final title = t.mode == 'ByPick' ? 'Sort ${pick != null ? pickLabel(tIntOrNull(pick['pickNumber']) ?? 0, widget.labels) : 'pick'}' : 'Sort all available eggs';

    return PopScope(
      canPop: _busy == null,
      child: Scaffold(
        appBar: AppBar(title: Text('$title${t.draft != null ? ' — draft ${t.draft!['sessionNo']}' : ''}')),
        // Totals and buttons pinned to the bottom while the sizes scroll.
        bottomNavigationBar: SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: TColors.slate200))),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: TColors.slate50, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
                child: Wrap(spacing: 14, runSpacing: 2, children: [
                  _tally('Available', fmtCount(bal.available)),
                  _tally('Into sizes', fmtCount(bal.sized)),
                  _tally('Loss', fmtCount(bal.loss)),
                  _tally('Sorted now', fmtCount(bal.input), strong: true),
                  _tally('Left unsorted after', fmtCount(bal.remainingAfter),
                      tone: bal.remainingAfter < 0 ? 'bad' : bal.remainingAfter == 0 && bal.input > 0 ? 'good' : null),
                ]),
              ),
              if (blocker != null && bal.input > 0) Text(blocker, style: const TextStyle(fontSize: 13, color: TColors.rose700)),
              if (blocker == null && bal.remainingAfter > 0)
                Text('Partial sorting: ${fmtCount(bal.remainingAfter)} eggs stay unsorted and can be sorted later.',
                    style: const TextStyle(fontSize: 12, color: TColors.slate500)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: _busy != null ? null : () => Navigator.pop(context), child: const Text('Cancel'))),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy != null || dateProblem != null || bal.invalidLines > 0 || (t.mode == 'Combined' && _scope.isEmpty)
                        ? null
                        : () => _submit(false),
                    child: Text(_busy == 'draft' ? 'Saving…' : 'Save draft'),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: TColors.emerald600),
                    onPressed: !widget.canPost || _busy != null || blocker != null || dateProblem != null || sizes.isEmpty ? null : () => _submit(true),
                    child: Text(_busy == 'post' ? 'Posting…' : 'Post sorting'),
                  ),
                ),
              ]),
            ]),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
          children: [
            Text('${day.flockName}${day.batchName != null ? ' · ${day.batchName}' : ''}${day.houseName != null ? ' · ${day.houseName}' : ''}',
                style: const TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 12),
            if (t.mode == 'ByPick' && pick != null)
              _grid([
                _fact('Production date', _ld(day.productionDate)),
                _fact('Collected', fmtCount(tNum(pick['pickGross'])), sub: cratesText(tNum(pick['pickGross']), eggsPerCrate)),
                _fact('Already sorted', fmtCount(tNum(pick['pickSorted']))),
                _fact('Left to sort', fmtCount(tNum(pick['available'])), sub: cratesText(tNum(pick['available']), eggsPerCrate), strong: true),
              ])
            else
              _daysBox(),
            const SizedBox(height: 12),
            FilterLabel(
              'Sorting date',
              AppDateField(value: businessDateAsDateTime(_date), onChanged: (d) => setState(() => _date = d == null ? '' : isoDay(d))),
            ),
            if (dateProblem != null) Text(dateProblem, style: const TextStyle(fontSize: 12, color: TColors.rose700)),
            const SizedBox(height: 10),
            FilterLabel('Notes', AppInput(controller: _notes, hintText: 'Optional')),
            const SizedBox(height: 12),
            if (sizes.isEmpty) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: TColors.amber50, border: Border.all(color: TColors.amber200), borderRadius: BorderRadius.circular(6)),
                child: const Text('No active egg sizes. Add them under Sizes & settings first.', style: TextStyle(fontSize: 13, color: TColors.amber900)),
              ),
              const SizedBox(height: 12),
            ],
            // One size (then each loss) per row: the box to type in on the right.
            Container(
              decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                  color: TColors.slate50,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: const Text('EGG SIZE / GRADE', style: TextStyle(fontSize: 11, letterSpacing: .4, color: TColors.slate500)),
                ),
                for (var i = 0; i < lines.length; i++) _lineRow(lines[i], i == sizes.length, bal, sizes),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _daysBox() {
    final all = _allDays;
    final openIds = [for (final d in all) if (d.left > 0) d.productionRecordId];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0x99FFFBEB), border: Border.all(color: TColors.amber300, width: 2), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Days to sort together', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: TColors.amber800)),
        const Text('Tick two or more days to sort them in one go.', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: TColors.amber700)),
        if (all.length > 1) ...[
          const SizedBox(height: 6),
          Row(children: [
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFF59E0B), minimumSize: const Size(0, 32)),
              onPressed: openIds.every(_scope.contains) ? null : () => setState(() => _scope = openIds.toSet()),
              child: const Text('Select all'),
            ),
            const SizedBox(width: 6),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 32)),
              onPressed: _scope.isEmpty ? null : () => setState(() => _scope = {}),
              child: const Text('Clear'),
            ),
          ]),
        ],
        const SizedBox(height: 8),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(border: Border.all(color: TColors.amber200), borderRadius: BorderRadius.circular(8)),
          child: Column(children: [
            for (final d in all)
              Opacity(
                opacity: d.left <= 0 ? .6 : 1,
                // Material, not a coloured box: a ListTile paints on its Material.
                child: Material(
                  color: _scope.contains(d.productionRecordId) ? const Color(0xFFFEF3C7) : Colors.white,
                  child: CheckboxListTile(
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _scope.contains(d.productionRecordId),
                    onChanged: d.left <= 0 && !_scope.contains(d.productionRecordId)
                        ? null
                        : (v) => setState(() => v == true ? _scope.add(d.productionRecordId) : _scope.remove(d.productionRecordId)),
                    title: Text(_ld(d.productionDate), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                    subtitle: Text(
                      [
                        for (final p in d.picks)
                          if (tNum(p['available']) > 0) '${pickShort(tIntOrNull(p['pickNumber']) ?? 0, widget.labels)} ${fmtCount(tNum(p['available']))}',
                      ].join(' · ').ifEmpty('nothing left'),
                      style: const TextStyle(fontSize: 12),
                    ),
                    secondary: Text(fmtCount(d.left), style: const TextStyle(fontWeight: FontWeight.w500)),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: '${_scope.length} of ${all.length}', style: const TextStyle(fontWeight: FontWeight.w700, color: TColors.amber800)),
            TextSpan(text: ' day${all.length == 1 ? '' : 's'} ticked · '),
            TextSpan(text: fmtCount(_available), style: const TextStyle(fontWeight: FontWeight.w700, color: TColors.amber800)),
            const TextSpan(text: ' eggs to sort. The sizes you enter below cover every ticked day; the oldest eggs are used first.'),
          ]),
          style: const TextStyle(fontSize: 12, color: TColors.slate600),
        ),
      ]),
    );
  }

  Widget _lineRow(SortingLine l, bool firstLoss, SortingBalance bal, List<Map> sizes) {
    final n = int.tryParse(l.text) ?? 0;
    final loss = l.lineType != 'SizedOutput';
    final name = loss
        ? lossTypes.where((x) => x.$1 == l.lineType).map((x) => x.$2).first
        : tStr(sizes.where((s) => tIntOrNull(s['eggSizeId']) == l.eggSizeId).firstOrNull?['name']);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: loss ? const Color(0x80FFF1F2) : null,
        border: Border(top: BorderSide(color: firstLoss ? TColors.slate300 : TColors.slate100, width: firstLoss ? 2 : 1)),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: TextStyle(fontWeight: FontWeight.w500, color: loss ? TColors.rose800 : TColors.slate900)),
            Text.rich(
              TextSpan(children: [
                if (loss) const TextSpan(text: 'loss — not stocked · ', style: TextStyle(color: TColors.rose700)),
                TextSpan(text: n != 0 ? '${cratesText(n, eggsPerCrate)} · ${pct(n, bal.input)}' : '—'),
              ]),
              style: const TextStyle(fontSize: 11, color: TColors.slate500),
            ),
          ]),
        ),
        SizedBox(
          width: 96,
          child: AppInput(
            key: ValueKey('eggs-${l.key}'),
            controller: _ctl(l.key),
            hintText: '0',
            keyboardType: TextInputType.number,
            onChanged: (v) {
              final digits = v.replaceAll(RegExp(r'[^\d]'), '');
              if (digits != v) _ctl(l.key).text = digits;
              setState(() {});
            },
          ),
        ),
      ]),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

// ------------------------------------------------------------------ settings page

/// Setup → Production → Egg Sorting Settings: the same panel as the
/// workspace's "Sizes & settings" tab, without the workspace around it.
class EggSortingSettingsScreen extends StatefulWidget {
  const EggSortingSettingsScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;
  @override
  State<EggSortingSettingsScreen> createState() => _EggSortingSettingsScreenState();
}

class _EggSortingSettingsScreenState extends State<EggSortingSettingsScreen> {
  Map? _settings;
  List<Map> _classes = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = widget.session.farmClient;
    try {
      setState(() => _error = null);
      final s = await api.get('/api/Poultry/egg-sorting/settings', query: {'farmId': widget.company.farmId});
      final on = s is Map && s['enableEggSorting'] == true;
      final c = await api.get('/api/Poultry/egg-sorting/classes', query: {'farmId': widget.company.farmId, 'includeInactive': 'true', 'ensure': '$on'});
      if (mounted) {
        setState(() {
          _settings = s is Map ? s : null;
          _classes = rowsOf(c);
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message.isNotEmpty ? e.message : 'Could not load egg sorting settings.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-egg-sorting-settings');
    final unsorted = _classes.where((c) => c['classKind'] == 'Unsorted').firstOrNull;
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Egg Sorting Settings')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: TColors.amber100, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.settings_outlined, size: 20, color: TColors.amber700),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Egg Sorting Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: TColors.slate900)),
                  Text('Turn egg sorting on or off, and set the egg sizes and their prices.', style: TextStyle(fontSize: 13, color: TColors.slate600)),
                ]),
              ),
            ]),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => EggSortingWorkspaceScreen(session: widget.session, company: widget.company),
              )),
              child: const Text('Open Egg Sorting'),
            ),
            const SizedBox(height: 14),
            if (_error != null) ...[TrackerBanner.error(_error!), const SizedBox(height: 12)],
            SizesSettingsPanel(
              session: widget.session,
              company: widget.company,
              settings: _settings,
              classes: _classes,
              canEdit: _canWrite(widget.company),
              onChanged: _load,
            ),
            if (unsorted != null) ...[
              const SizedBox(height: 10),
              Text(
                'Unsorted / General eggs on hand: ${fmtCount(tNum(unsorted['onHand']))} (${cratesText(tNum(unsorted['onHand']), eggsPerCrate)}). Production always adds to Unsorted.',
                style: const TextStyle(fontSize: 12, color: TColors.slate500),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// `/poultry-egg-sorting?record=&tab=` and `/poultry-egg-sorting-settings`.
Widget? eggSortingWorkspaceForHref(String href, Session s, Company c) {
  final uri = Uri.tryParse(href);
  if (uri == null) return null;
  if (uri.path == '/poultry-egg-sorting-settings') return EggSortingSettingsScreen(session: s, company: c);
  if (uri.path != '/poultry-egg-sorting') return null;
  final rec = int.tryParse(uri.queryParameters['record'] ?? '');
  return EggSortingWorkspaceScreen(session: s, company: c, recordId: rec != null && rec > 0 ? rec : null, initialTab: uri.queryParameters['tab']);
}
