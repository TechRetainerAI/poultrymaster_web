// Poultry → Operations → Production → Egg sorting (app/egg-production):
// the list (search, the Filters sheet, "Sync today's totals to Production
// Records", four tiles, cards, the table with its total row, paging, delete),
// and the Add (new) and Edit ([id]) pages, which also push their pick totals
// into the matching production record.

import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../shared/business_dates.dart';
import '../delivery/delivery_dialogs.dart' show NumBox;
import '../money/money_widgets.dart' show twoUp;
import '../reports/report_routes.dart' show openAppHref;
import '../sales/sales_logic.dart' show salePageSizes, isFlockClosed;
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull, loc, trackerDate, localDateKey, sortRows, toggleSort, SortState, formatEggGradeLabel;
import '../trackers/tracker_widgets.dart';
import 'production_logic.dart';
import 'production_records_screen.dart' show ProdCard;

/// resolveEggProductionFlockName: the API's name unless it is the
/// "Unknown Flock" placeholder, then the flock list, then "Flock #id".
String eggFlockName(Map prod, List<Map> flocks) {
  final fromApi = tStr(prod['flockName']).trim();
  if (fromApi.isNotEmpty && !RegExp(r'^unknown flock$', caseSensitive: false).hasMatch(fromApi)) return fromApi;
  final f = flocks.where((x) => tIntOrNull(x['flockId']) == tIntOrNull(prod['flockId'])).firstOrNull;
  final name = tStr(f?['name']).trim();
  if (name.isNotEmpty) return name;
  return tNum(prod['flockId']) != 0 ? 'Flock #${tStr(prod['flockId'])}' : '—';
}

/// mapEggRow: the fields the web keeps from an egg-production row (the
/// edit page spreads them back into its PUT).
Map<String, Object?> mapEggRow(Map r) {
  final g = tStr(r['eggGrade']).trim();
  return {
    'productionId': tNum(r['productionId']),
    'farmId': tStr(r['farmId']),
    'userId': tStr(r['userId']),
    'flockId': tNum(r['flockId']),
    if (r['flockName'] != null) 'flockName': tStr(r['flockName']),
    'productionDate': tStr(r['productionDate']),
    for (final k in ['eggCount', 'production9AM', 'production12PM', 'production4PM', 'production4thPick', 'production5thPick', 'production6thPick',
        'totalProduction', 'brokenEggs', 'meatyEggs', 'softEggs', 'lostEggs'])
      k: tNum(r[k]),
    'notes': tStr(r['notes']),
    'eggGrade': g.isNotEmpty ? g : null,
    'createdAt': r['createdAt'] != null ? tStr(r['createdAt']) : null,
  };
}

/// This page's pager shows at most five numbers.
List<Object> eggPageNumbers(int page, int totalPages) {
  if (totalPages <= 5) return [for (var i = 1; i <= totalPages; i++) i];
  if (page <= 3) return [1, 2, 3, 4, 'ellipsis', totalPages];
  if (page >= totalPages - 2) return [1, 'ellipsis', for (var i = totalPages - 3; i <= totalPages; i++) i];
  return [1, 'ellipsis', page - 1, page, page + 1, 'ellipsis', totalPages];
}

num _picksTotal(Map r) => tNum(r['production9AM']) + tNum(r['production12PM']) + tNum(r['production4PM']) + tNum(r['production4thPick']);

String _todayKey() => localDateKey(DateTime.now().toUtc().toIso8601String());

/// The production-record body the web's createProductionRecord /
/// updateProductionRecord build: keys left undefined are dropped.
Map<String, Object?> productionRecordPayload(Map<String, Object?> r, {int? id}) {
  final p = <String, Object?>{
    'id': ?id,
    for (final k in ['farmId', 'userId', 'createdBy', 'updatedBy', 'ageInWeeks', 'ageInDays', 'date', 'noOfBirds', 'mortality', 'noOfBirdsLeft', 'feedKg', 'medication', 'production9AM', 'production12PM', 'production4PM'])
      if (r[k] != null) k: r[k],
    'production4thPick': r['production4thPick'] ?? 0,
    'production5thPick': r['production5thPick'] ?? 0,
    'production6thPick': r['production6thPick'] ?? 0,
    'brokenEggs': r['brokenEggs'] ?? 0,
    if (r['totalProduction'] != null) 'totalProduction': r['totalProduction'],
    if (r['flockId'] != null) 'FlockId': r['flockId'],
  };
  final grade = tStr(r['eggGrade']).trim();
  if (id == null || r.containsKey('eggGrade')) p['eggGrade'] = grade.isNotEmpty ? grade : null;
  for (final k in ['meatyEggs', 'softEggs', 'lostEggs', 'notes']) {
    if (id == null || r.containsKey(k)) p[k] = r[k];
  }
  for (final k in [
    'specificFeedUsedId', 'specificFeedUsedName', 'feedUnitCost', 'totalFeedConsumed', 'totalFeedCost', 'specificMedicationUsedId',
    'specificMedicationUsedName', 'medicationUnitCost', 'totalMedicationConsumed', 'totalMedicationCost', 'totalCostOfProduction', 'medications', 'feeds',
  ]) {
    p[k] = r[k];
  }
  return p;
}

class EggSortingScreen extends StatefulWidget {
  const EggSortingScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;
  @override
  State<EggSortingScreen> createState() => _EggSortingScreenState();
}

class _EggSortingScreenState extends State<EggSortingScreen> {
  List<Map> _rows = [], _flocks = [];
  bool _loading = true, _table = false, _syncing = false;
  String _error = '', _syncCheck = '', _syncScope = 'selected';
  final _search = TextEditingController();
  String _searchText = '', _from = '', _to = '', _flock = 'ALL', _grade = 'ALL';
  SortState _sort = (key: null, dir: null);
  int _page = 1, _perPage = 10;
  int _checkSeq = 0;

  ApiClient get _api => widget.session.farmClient;
  String get _userId => widget.session.tokens.userId ?? '';
  String get _farmId => widget.company.farmId;
  Map<String, String> get _ctx => {'userId': _userId, 'farmId': _farmId};
  bool get _canDelete => (widget.company.role ?? '').toLowerCase() != 'staff';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_farmId.isEmpty || _userId.isEmpty) {
      setState(() {
        _error = 'Farm ID or User ID not found';
        _loading = false;
      });
      return;
    }
    List<Map>? rows;
    String? err;
    try {
      rows = rowsOf(await _api.get('/api/EggProduction', query: _ctx));
    } on ApiException catch (e) {
      err = e.message;
    }
    List<Map>? flocks;
    try {
      flocks = rowsOf(await _api.get('/api/Flock', query: _ctx));
    } on ApiException {
      flocks = null;
    }
    if (!mounted) return;
    setState(() {
      if (rows != null) {
        _rows = rows;
      } else {
        _error = err != null && err.isNotEmpty ? err : 'Failed to load egg productions';
      }
      if (flocks != null) _flocks = flocks;
      _loading = false;
    });
    _checkDiscrepancies();
  }

  List<Map> _scopedToday() {
    final today = _todayKey();
    final todays = [for (final p in _rows) if (localDateKey(p['productionDate']) == today) p];
    return _syncScope == 'selected' && _flock != 'ALL' ? [for (final p in todays) if (tStr(p['flockId']) == _flock) p] : todays;
  }

  /// evaluateDiscrepancies: today's egg totals per flock against the
  /// production records for today.
  Future<void> _checkDiscrepancies() async {
    if (_farmId.isEmpty || _userId.isEmpty) return;
    final seq = ++_checkSeq;
    final today = _todayKey();
    final scoped = _scopedToday();
    if (scoped.isEmpty) {
      setState(() => _syncCheck = '');
      return;
    }
    final egg = <int, num>{};
    for (final r in scoped) {
      final fid = tIntOrNull(r['flockId']) ?? 0;
      if (fid == 0) continue;
      egg[fid] = (egg[fid] ?? 0) + _picksTotal(r);
    }
    List<Map> prod = [];
    try {
      prod = rowsOf(await _api.get('/api/ProductionRecord', query: _ctx));
    } on ApiException {
      prod = [];
    }
    if (!mounted || seq != _checkSeq) return;
    final grouped = <int, num>{};
    for (final r in prod) {
      if (localDateKey(r['date']) != today) continue;
      final fid = tIntOrNull(r['flockId']) ?? 0;
      if (fid == 0) continue;
      if (_syncScope == 'selected' && _flock != 'ALL' && '$fid' != _flock) continue;
      grouped[fid] = (grouped[fid] ?? 0) + tNum(r['totalProduction']);
    }
    final mismatches = [
      for (final e in egg.entries)
        if (e.value != (grouped[e.key] ?? 0)) 'Flock #${e.key}: Egg Production ${_n(e.value)} vs Production Records ${_n(grouped[e.key] ?? 0)}',
    ];
    setState(() => _syncCheck = mismatches.isNotEmpty ? 'Discrepancy detected for today. ${mismatches.join(' | ')}' : '');
  }

  String _n(num v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';

  Future<void> _syncToday() async {
    if (_farmId.isEmpty || _userId.isEmpty) {
      trackerToast(context, 'Session issue', description: 'Please log in again.', error: true);
      return;
    }
    final today = _todayKey();
    final scoped = _scopedToday();
    if (scoped.isEmpty) {
      trackerToast(context, 'Nothing to sync', description: 'No egg-production entries found for today in this scope.');
      return;
    }
    setState(() => _syncing = true);
    try {
      final grouped = <int, List<num>>{};
      for (final r in scoped) {
        final fid = tIntOrNull(r['flockId']) ?? 0;
        if (fid == 0) continue;
        final c = grouped[fid] ?? [0, 0, 0, 0, 0];
        c[0] += tNum(r['production9AM']);
        c[1] += tNum(r['production12PM']);
        c[2] += tNum(r['production4PM']);
        c[3] += tNum(r['production4thPick']);
        c[4] += tNum(r['brokenEggs']);
        grouped[fid] = c;
      }
      if (grouped.isEmpty) {
        if (mounted) trackerToast(context, 'Nothing to sync', description: 'No valid flock totals were found for today.');
        return;
      }
      List<Map> existing = [];
      try {
        existing = rowsOf(await _api.get('/api/ProductionRecord', query: _ctx));
      } on ApiException {
        existing = [];
      }
      var updated = 0, created = 0;
      for (final e in grouped.entries) {
        final flockId = e.key, s = e.value;
        final flock = _flocks.where((f) => tIntOrNull(f['flockId']) == flockId).firstOrNull;
        if (flock == null) continue;
        final total = s[0] + s[1] + s[2] + s[3];
        final todayIso = '${today}T00:00:00Z';
        final matched = existing.where((r) => tIntOrNull(r['flockId']) == flockId && localDateKey(r['date']) == today).firstOrNull;
        if (matched != null) {
          final mid = tIntOrNull(matched['id']);
          await _api.put('/api/ProductionRecord/$mid',
              body: productionRecordPayload({
                'farmId': matched['farmId'] ?? _farmId,
                'userId': matched['userId'] ?? _userId,
                'createdBy': matched['createdBy'] ?? _userId,
                'updatedBy': _userId,
                'ageInDays': tNum(matched['ageInDays']),
                'ageInWeeks': tNum(matched['ageInWeeks']),
                'date': matched['date'] ?? todayIso,
                'flockId': flockId,
                'noOfBirds': tNum(matched['noOfBirds']),
                'mortality': tNum(matched['mortality']),
                'noOfBirdsLeft': tNum(matched['noOfBirdsLeft']),
                'feedKg': tNum(matched['feedKg']),
                'medication': tStr(matched['medication']).isNotEmpty ? matched['medication'] : 'None',
                'production9AM': s[0],
                'production12PM': s[1],
                'production4PM': s[2],
                'production4thPick': s[3],
                'brokenEggs': s[4],
                'totalProduction': total,
              }, id: mid));
          updated++;
        } else {
          final startKey = localDateKey(tStr(flock['startDate']).isNotEmpty ? flock['startDate'] : todayIso);
          final start = DateTime.parse('${startKey}T00:00:00Z');
          final ageDays = DateTime.parse(todayIso).difference(start).inMilliseconds ~/ 86400000;
          final days = ageDays < 0 ? 0 : ageDays;
          final birds = tNum(flock['quantity']);
          await _api.post('/api/ProductionRecord',
              body: productionRecordPayload({
                'farmId': _farmId,
                'userId': _userId,
                'createdBy': _userId,
                'updatedBy': _userId,
                'date': todayIso,
                'flockId': flockId,
                'ageInDays': days,
                'ageInWeeks': days ~/ 7,
                'noOfBirds': birds,
                'mortality': 0,
                'noOfBirdsLeft': birds,
                'feedKg': 0,
                'medication': 'None',
                'production9AM': s[0],
                'production12PM': s[1],
                'production4PM': s[2],
                'production4thPick': s[3],
                'brokenEggs': s[4],
                'totalProduction': total,
              }));
          created++;
        }
      }
      if (mounted) trackerToast(context, "Today's totals synced", description: 'Updated $updated and created $created production record(s) for $today.');
    } on ApiException {
      if (mounted) trackerToast(context, 'Sync failed', description: "Could not sync today's totals. Please try again.", error: true);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  List<Map> get _filtered {
    final q = _searchText.toLowerCase();
    return [
      for (final p in _rows)
        if ((q.isEmpty ||
                eggFlockName(p, _flocks).toLowerCase().contains(q) ||
                tStr(p['notes']).toLowerCase().contains(q) ||
                tStr(p['eggGrade']).toLowerCase().contains(q) ||
                formatEggGradeLabel(p['eggGrade']).toLowerCase().contains(q)) &&
            (_grade == 'ALL' || (_grade == eggGradeNone ? tStr(p['eggGrade']).trim().isEmpty : eggGradeFromApi(p['eggGrade']) == _grade)) &&
            (_from.isEmpty || localDateKey(p['productionDate']).compareTo(_from) >= 0) &&
            (_to.isEmpty || localDateKey(p['productionDate']).compareTo(_to) <= 0) &&
            (_flock == 'ALL' || tStr(p['flockId']) == _flock))
          p,
    ];
  }

  List<Map> _sorted(List<Map> rows) => sortRows(rows, _sort, (r, k) => switch (k) {
        'productionDate' => DateTime.tryParse(tStr(r['productionDate'])) ?? DateTime(0),
        'eggGrade' => eggGradeFromApi(r['eggGrade']).toLowerCase(),
        _ => tNum(r[k]),
      });

  Future<void> _openForm([int? id]) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => EggSortingFormPage(session: widget.session, company: widget.company, productionId: id)));
    if (mounted) _load();
  }

  Future<void> _delete(int id) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        var busy = false;
        return StatefulBuilder(builder: (ctx, set) => AlertDialog(
              title: const Text('Delete Production Record'),
              content: const Text(
                  'Are you sure you want to delete this egg production record? This action cannot be undone and the data will be permanently removed.'),
              actions: [
                TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: const Text('Cancel')),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: TColors.red600),
                  onPressed: busy
                      ? null
                      : () async {
                          if (_farmId.isEmpty || _userId.isEmpty) {
                            trackerToast(context, 'Session issue', description: 'We could not confirm your farm or user. Please sign in again.', error: true);
                            return;
                          }
                          set(() => busy = true);
                          try {
                            await _api.delete('/api/EggProduction/$id?userId=${Uri.encodeQueryComponent(_userId)}&farmId=${Uri.encodeQueryComponent(_farmId)}');
                            if (mounted) {
                              trackerToast(context, 'Record deleted', description: 'The egg production record has been successfully deleted.');
                              setState(() => _page = 1);
                            }
                            _load();
                          } on ApiException catch (e) {
                            if (mounted) {
                              trackerToast(context, 'Delete failed',
                                  description: e.message.isNotEmpty ? e.message : 'Something went wrong. Please try again.', error: true);
                            }
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                  child: Text(busy ? 'Deleting...' : 'Delete'),
                ),
              ],
            ));
      },
    );
  }

  Future<void> _openFilters() async {
    var from = _from, to = _to, flock = _flock, grade = _grade;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final changed = from != _from || to != _to || flock != _flock || grade != _grade;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Filters', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 14),
              const Text('Date range', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate700)),
              const SizedBox(height: 10),
              FilterLabel('Start date', FilterDate(value: from, hint: 'Start date', onChanged: (v) => set(() => from = v))),
              const SizedBox(height: 12),
              FilterLabel('End date', FilterDate(value: to, hint: 'End date', onChanged: (v) => set(() => to = v))),
              const SizedBox(height: 14),
              FilterLabel(
                'Flock',
                AppSelect<String>(
                  value: flock,
                  hintText: 'All Flocks',
                  items: [
                    const AppSelectItem(value: 'ALL', label: 'All Flocks'),
                    for (final f in _flocks) AppSelectItem(value: tStr(f['flockId']), label: '${tStr(f['name'])} (${tStr(f['quantity'])} birds)'),
                  ],
                  onChanged: (v) => set(() => flock = v ?? 'ALL'),
                ),
              ),
              const SizedBox(height: 12),
              FilterLabel(
                'Egg size',
                AppSelect<String>(
                  value: grade,
                  hintText: 'All sizes',
                  items: [
                    const AppSelectItem(value: 'ALL', label: 'All sizes'),
                    for (final (v, l) in eggGradeOptions) AppSelectItem(value: v, label: l),
                  ],
                  onChanged: (v) => set(() => grade = v ?? 'ALL'),
                ),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: () {
                      setState(() {
                        _search.clear();
                        _searchText = '';
                        _from = '';
                        _to = '';
                        _flock = 'ALL';
                        _grade = 'ALL';
                      });
                      Navigator.pop(ctx);
                      trackerToast(context, 'Filters cleared');
                      _checkDiscrepancies();
                    },
                    child: const Text('Clear all'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: !changed
                        ? null
                        : () {
                            setState(() {
                              _from = from;
                              _to = to;
                              _flock = flock;
                              _grade = grade;
                              _page = 1;
                            });
                            Navigator.pop(ctx);
                            trackerToast(context, 'Filters applied', description: 'Egg sorting list updated.');
                            _checkDiscrepancies();
                          },
                    child: const Text('Apply'),
                  ),
                ),
              ]),
            ]),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/egg-production');
    final rows = _filtered;
    final sorted = _sorted(rows);
    final totalPages = (sorted.length / _perPage).ceil();
    final page = totalPages == 0 ? 1 : _page.clamp(1, totalPages);
    final start = (page - 1) * _perPage;
    final pageRows = sorted.sublist(start.clamp(0, sorted.length), (start + _perPage).clamp(0, sorted.length));
    final totalEggs = rows.fold<num>(0, (s, p) => s + tNum(p['totalProduction']));
    final totalBroken = rows.fold<num>(0, (s, p) => s + tNum(p['brokenEggs']));
    final avg = rows.isEmpty ? 0 : totalEggs / rows.length;
    final crates = totalEggs ~/ eggsPerCrate, pieces = (totalEggs % eggsPerCrate).toInt();
    final active = [_searchText.isNotEmpty, _from.isNotEmpty, _to.isNotEmpty, _flock != 'ALL', _grade != 'ALL'].where((b) => b).length;

    Widget tile(String label, String value, Color color, {String? sub}) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: .6, color: TColors.slate500)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
            if (sub != null) Text(sub, style: const TextStyle(fontSize: 12, color: TColors.slate400)),
          ]),
        );

    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Egg Sorting')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: const Color(0xFFFEF9C3), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.egg_outlined, size: 20, color: Color(0xFFCA8A04)),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Egg Sorting', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: TColors.slate900)),
                Text('Daily collection by flock (9am / 12pm / 4pm) for the filters below.', style: TextStyle(fontSize: 13, color: TColors.slate600)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: TColors.blue600, minimumSize: const Size.fromHeight(44)),
            onPressed: () => _openForm(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Egg Sorting record'),
          ),
          const SizedBox(height: 16),
          AppInput(
            controller: _search,
            hintText: 'Search by flock or notes...',
            prefixIcon: const Icon(Icons.search, size: 18, color: TColors.slate400),
            onChanged: (v) => setState(() => _searchText = v),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            onPressed: _openFilters,
            icon: const Icon(Icons.filter_list, size: 18),
            label: Row(mainAxisSize: MainAxisSize.min, children: [
              const Flexible(child: Text('Filters', overflow: TextOverflow.ellipsis)),
              if (active > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: const Color(0xFFF97316), borderRadius: BorderRadius.circular(999)),
                  child: Text('$active', style: const TextStyle(fontSize: 12, color: Colors.white)),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 16),
          _syncCard(),
          const SizedBox(height: 16),
          if (_error.isNotEmpty) ...[TrackerBanner.error(_error), const SizedBox(height: 16)],
          if (!_loading) ...[
            twoUp([
              tile('Total Eggs', loc(totalEggs), TColors.emerald600, sub: '${crates}c + ${pieces}p'),
              tile('Crates', loc(crates), TColors.amber600),
              tile('Broken', loc(totalBroken), TColors.red600),
              tile('Avg', avg.toStringAsFixed(2), TColors.slate900),
            ]),
            const SizedBox(height: 16),
          ],
          if (_loading)
            const TCard(child: Padding(padding: EdgeInsets.symmetric(vertical: 36), child: Text('Loading egg production records...', textAlign: TextAlign.center)))
          else if (rows.isEmpty)
            TCard(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(children: [
                  const Icon(Icons.egg_outlined, size: 32, color: TColors.slate400),
                  const SizedBox(height: 12),
                  const Text('No production records found', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: TColors.slate900)),
                  const SizedBox(height: 6),
                  const Text('Get started by creating your first egg production record.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate600)),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: TColors.blue600),
                    onPressed: () => _openForm(),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Egg Sorting record'),
                  ),
                ]),
              ),
            )
          else if (!_table)
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < pageRows.length; i++) ...[_card(pageRows[i], i), const SizedBox(height: 12)],
              if (pageRows.isNotEmpty) ViewTableButton(onPressed: () => setState(() => _table = true)),
            ])
          else
            TCard(
              padding: EdgeInsets.zero,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TableViewBar(text: 'Table • Scroll → for more', onCards: () => setState(() => _table = false)),
                _tableView(pageRows, totalEggs, crates, pieces, totalBroken),
              ]),
            ),
          if (!_loading && rows.isNotEmpty && totalPages > 1) _pagination(sorted.length, page, totalPages, start),
        ]),
      ),
    );
  }

  void _setScope(String? v) {
    setState(() => _syncScope = v ?? 'selected');
    _checkDiscrepancies();
  }

  Widget _syncCard() {
    final disabled = _syncing || _rows.isEmpty || (_syncScope == 'selected' && _flock == 'ALL');
    return TCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("Sync today's totals to Production Records", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: TColors.slate900)),
        const SizedBox(height: 6),
        Text('Only syncs entries for today (${_todayKey()}), as discussed.', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
        const SizedBox(height: 6),
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Text('For egg inventory and the ledger, open ', style: TextStyle(fontSize: 12, color: TColors.slate500)),
          InkWell(
            onTap: () => openAppHref(context, widget.session, widget.company, '/egg-tracker', label: 'Egg tracker'),
            child: const Text('Egg tracker', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: TColors.blue600)),
          ),
          const Text('.', style: TextStyle(fontSize: 12, color: TColors.slate500)),
        ]),
        if (_syncCheck.isNotEmpty) ...[const SizedBox(height: 8), TrackerBanner.error(_syncCheck)],
        const SizedBox(height: 6),
        RadioGroup<String>(
          groupValue: _syncScope,
          onChanged: _setScope,
          child: Wrap(spacing: 16, children: [
            for (final (v, l) in [('selected', 'Selected flock'), ('all', 'All flocks')])
              InkWell(
                onTap: () => _setScope(v),
                child: Row(mainAxisSize: MainAxisSize.min, children: [Radio<String>(value: v), Text(l, style: const TextStyle(fontSize: 14))]),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        FilledButton(onPressed: disabled ? null : _syncToday, child: Text(_syncing ? 'Syncing...' : "Sync Today's Total")),
      ]),
    );
  }

  Widget _card(Map p, int i) {
    Widget kv(String l, String v, Color color) => Text.rich(TextSpan(children: [
          TextSpan(text: '$l ', style: const TextStyle(color: TColors.slate500)),
          TextSpan(text: v, style: TextStyle(fontWeight: FontWeight.w500, color: color)),
        ]), style: const TextStyle(fontSize: 14));
    final broken = tNum(p['brokenEggs']);
    final id = tIntOrNull(p['productionId']) ?? 0;
    return ProdCard(
      key: ValueKey('egg-$id'),
      striped: i.isEven,
      header: Padding(
        padding: const EdgeInsets.only(right: 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text.rich(TextSpan(children: [
            TextSpan(text: trackerDate(p['productionDate']), style: const TextStyle(fontWeight: FontWeight.w600, color: TColors.slate900)),
            const TextSpan(text: '  •  ', style: TextStyle(color: TColors.slate500)),
            TextSpan(text: eggFlockName(p, _flocks), style: const TextStyle(color: TColors.slate600)),
          ]), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(_n(tNum(p['totalProduction'])), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: TColors.emerald600)),
            const Text('eggs', style: TextStyle(fontSize: 12, color: TColors.slate500)),
            TBadge(formatEggGradeLabel(p['eggGrade']), bg: const Color(0xFFF5F3FF), fg: const Color(0xFF6D28D9), border: const Color(0xFFDDD6FE)),
            if (broken > 0) ...[
              const Text('•', style: TextStyle(color: TColors.slate400)),
              Text('${_n(broken)} broken', style: const TextStyle(fontSize: 14, color: TColors.red600)),
            ],
          ]),
        ]),
      ),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LayoutBuilder(builder: (context, c) {
          final w = (c.maxWidth - 8) / 2;
          return Wrap(spacing: 8, runSpacing: 8, children: [
            SizedBox(width: w, child: kv('1st Pick', _n(tNum(p['production9AM'])), Color(0xFF1D4ED8))),
            SizedBox(width: w, child: kv('2nd Pick', _n(tNum(p['production12PM'])), const Color(0xFFC2410C))),
            SizedBox(width: w, child: kv('3rd Pick', _n(tNum(p['production4PM'])), const Color(0xFF7E22CE))),
            SizedBox(width: w, child: kv('4th Pick', _n(tNum(p['production4thPick'])), const Color(0xFF0F766E))),
            SizedBox(width: w, child: kv('Broken', _n(broken), TColors.red600)),
            SizedBox(width: c.maxWidth, child: kv('Size', formatEggGradeLabel(p['eggGrade']), const Color(0xFF5B21B6))),
          ]);
        }),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(backgroundColor: Colors.white, minimumSize: const Size.fromHeight(40)),
              onPressed: () => _openForm(id),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Edit'),
            ),
          ),
          if (_canDelete) ...[
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: TColors.red600,
                  side: const BorderSide(color: TColors.red200),
                  minimumSize: const Size.fromHeight(40),
                ),
                onPressed: () => _delete(id),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Delete'),
              ),
            ),
          ],
        ]),
      ]),
    );
  }

  Widget _tableView(List<Map> pageRows, num totalEggs, int crates, int pieces, num totalBroken) => TrackerTable(
        sort: _sort,
        onSort: (k) => setState(() => _sort = toggleSort(k, _sort)),
        columns: const [
          TCol('Date', sortKey: 'productionDate', width: 100),
          TCol('Flock', sortKey: 'flockId', width: 120),
          TCol('Size', sortKey: 'eggGrade', width: 88),
          TCol('1st Pick', sortKey: 'production9AM', width: 80),
          TCol('2nd Pick', sortKey: 'production12PM', width: 80),
          TCol('3rd Pick', sortKey: 'production4PM', width: 80),
          TCol('4th Pick', sortKey: 'production4thPick', width: 80),
          TCol('Total Production', sortKey: 'totalProduction', width: 120),
          TCol('Broken Eggs', sortKey: 'brokenEggs', width: 120),
          TCol('Actions', width: 120),
        ],
        rows: [
          for (final p in pageRows)
            [
              cellText(trackerDate(p['productionDate']), bold: true),
              cellText(eggFlockName(p, _flocks)),
              cellText(formatEggGradeLabel(p['eggGrade']), color: const Color(0xFF4C1D95)),
              cellText(_n(tNum(p['production9AM']))),
              cellText(_n(tNum(p['production12PM']))),
              cellText(_n(tNum(p['production4PM']))),
              cellText(_n(tNum(p['production4thPick']))),
              cellText(_n(tNum(p['totalProduction']))),
              cellText(_n(tNum(p['brokenEggs']))),
              Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  onPressed: () => _openForm(tIntOrNull(p['productionId'])),
                ),
                if (_canDelete)
                  IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete_outline, size: 16, color: TColors.red600),
                    onPressed: () => _delete(tIntOrNull(p['productionId']) ?? 0),
                  ),
              ]),
            ],
          [
            const SizedBox.shrink(),
            const SizedBox.shrink(),
            cellText('Total', bold: true),
            const SizedBox.shrink(),
            const SizedBox.shrink(),
            const SizedBox.shrink(),
            const SizedBox.shrink(),
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(loc(totalEggs), style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('${crates}c + ${pieces}p', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            ]),
            cellText(_n(totalBroken), bold: true),
            const SizedBox.shrink(),
          ],
        ],
      );

  Widget _pagination(int total, int page, int totalPages, int start) {
    final end = (start + _perPage).clamp(0, total);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(children: [
        Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 6, children: [
          Text('Showing ${start + 1} to $end of $total records', style: const TextStyle(fontSize: 13, color: TColors.slate600)),
          SizedBox(
            width: 120,
            child: AppSelect<int>(
              value: _perPage,
              items: [for (final n in salePageSizes) AppSelectItem(value: n, label: '$n / page')],
              onChanged: (v) => setState(() {
                _perPage = v ?? _perPage;
                _page = 1;
              }),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 2, children: [
          TextButton.icon(
            onPressed: page == 1 ? null : () => setState(() => _page = page - 1),
            icon: const Icon(Icons.chevron_left, size: 18),
            label: const Text('Previous'),
          ),
          for (final p in eggPageNumbers(page, totalPages))
            p == 'ellipsis'
                ? const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('…'))
                : SizedBox(
                    width: 36,
                    height: 36,
                    child: p == page
                        ? OutlinedButton(style: OutlinedButton.styleFrom(padding: EdgeInsets.zero), onPressed: () {}, child: Text('$p'))
                        : TextButton(style: TextButton.styleFrom(padding: EdgeInsets.zero), onPressed: () => setState(() => _page = p as int), child: Text('$p')),
                  ),
          TextButton.icon(
            onPressed: page == totalPages ? null : () => setState(() => _page = page + 1),
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.chevron_right, size: 18),
            label: const Text('Next'),
          ),
        ]),
      ]),
    );
  }
}

// ------------------------------------------------------------ add / edit

/// app/egg-production/new (productionId null) and app/egg-production/[id].
class EggSortingFormPage extends StatefulWidget {
  const EggSortingFormPage({super.key, required this.session, required this.company, this.productionId});
  final Session session;
  final Company company;
  final int? productionId;
  @override
  State<EggSortingFormPage> createState() => _EggSortingFormPageState();
}

class _EggSortingFormPageState extends State<EggSortingFormPage> {
  bool get _edit => widget.productionId != null;
  late bool _loading = _edit;
  bool _saving = false;
  String _error = '';
  List<Map> _batches = [], _flocks = [];
  PickSettings _picks = const PickSettings();
  String _batch = 'ALL';
  int _flockId = 0;
  String _date = isoDay(DateTime.now().toUtc());
  String _grade = eggGradeNone;
  num _broken = 0;
  final _notes = TextEditingController();
  final _crates = List<num>.filled(6, 0), _loose = List<num>.filled(6, 0);

  /// The loaded record (edit), spread into the PUT like the web's formData.
  Map _record = {};

  /// Edit keeps the record's 5th / 6th picks until those fields change.
  num? _keep5, _keep6;
  int _seed = 0;

  ApiClient get _api => widget.session.farmClient;
  String get _userId => widget.session.tokens.userId ?? '';
  String get _farmId => widget.company.farmId;
  Map<String, String> get _ctx => {'userId': _userId, 'farmId': _farmId};

  @override
  void initState() {
    super.initState();
    PickSettings.load(widget.session, widget.company).then((p) {
      if (mounted) setState(() => _picks = p);
    });
    _load();
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_farmId.isEmpty || _userId.isEmpty) {
      if (_edit) {
        setState(() {
          _error = 'Farm ID or User ID not found';
          _loading = false;
        });
      }
      return;
    }
    Future<List<Map>?> list(String path) async {
      try {
        return rowsOf(await _api.get(path, query: _ctx));
      } on ApiException {
        return null;
      }
    }

    Object? rec;
    String? recErr;
    final lists = Future.wait([list('/api/MainFlockBatch'), list('/api/Flock')]);
    if (_edit) {
      try {
        rec = await _api.get('/api/EggProduction/${widget.productionId}', query: _ctx);
      } on ApiException catch (e) {
        recErr = e.message;
      }
    }
    final r = await lists;
    if (!mounted) return;
    setState(() {
      if (r[0] != null) _batches = r[0]!;
      if (r[1] != null) _flocks = r[1]!;
      if (_edit) {
        if (rec is Map) {
          _hydrate(rec);
        } else {
          _error = recErr != null && recErr.isNotEmpty ? recErr : 'Failed to load production data';
        }
        _loading = false;
      }
    });
  }

  void _hydrate(Map e) {
    _record = e;
    var matched = tIntOrNull(e['flockId']) ?? 0;
    final name = tStr(e['flockName']).toLowerCase();
    if (name.isNotEmpty && _flocks.isNotEmpty) {
      final m = _flocks.where((f) => tStr(f['name']).toLowerCase() == name || tIntOrNull(f['flockId']) == tIntOrNull(e['flockId'])).firstOrNull;
      if (m != null) matched = tIntOrNull(m['flockId']) ?? matched;
    }
    final direct = _flocks.where((f) => tIntOrNull(f['flockId']) == tIntOrNull(e['flockId'])).firstOrNull;
    if (direct != null) matched = tIntOrNull(direct['flockId']) ?? matched;
    _flockId = matched;
    _date = tStr(e['productionDate']).split('T').first;
    _grade = eggGradeFromApi(e['eggGrade']);
    _broken = tNum(e['brokenEggs']);
    _notes.text = tStr(e['notes']);
    final picks = [e['production9AM'], e['production12PM'], e['production4PM'], e['production4thPick']];
    for (var i = 0; i < 4; i++) {
      final v = tNum(picks[i]).toInt();
      _crates[i] = v ~/ eggsPerCrate;
      _loose[i] = v % eggsPerCrate;
    }
    _keep5 = tNum(e['production5thPick']);
    _keep6 = tNum(e['production6thPick']);
    _seed++;
  }

  int _pick(int i) => (_crates[i] * eggsPerCrate + _loose[i]).toInt();
  num get _p5 => _keep5 ?? _pick(4);
  num get _p6 => _keep6 ?? _pick(5);
  num get _total => _pick(0) + _pick(1) + _pick(2) + _pick(3) + _p5 + _p6;

  /// What the browser's own checks (required, min, max) refuse before the
  /// submit handler runs.
  String? _nativeCheck() {
    if (_date.isEmpty) return 'Please fill out this field.';
    final today = isoDay(DateTime.now().toUtc());
    if (!_edit && _date.compareTo(today) > 0) return 'Value must be $today or earlier.';
    if (_broken < 0) return 'Value must be greater than or equal to 0.';
    for (var i = 0; i < 6; i++) {
      if (_crates[i] < 0 || _loose[i] < 0) return 'Value must be greater than or equal to 0.';
      if (_loose[i] > 29) return 'Value must be less than or equal to 29.';
    }
    return null;
  }

  Future<void> _submit() async {
    final native = _nativeCheck();
    if (native != null) {
      setState(() => _error = native);
      return;
    }
    if (_farmId.isEmpty || _userId.isEmpty) {
      setState(() => _error = 'Farm ID or User ID not found');
      return;
    }
    if (_flockId <= 0) {
      setState(() => _error = 'Choose which flock this egg record is for.');
      return;
    }
    final p = [_pick(0), _pick(1), _pick(2), _pick(3), _p5, _p6];
    if (_edit) {
      for (final (i, name) in [(0, '1st'), (1, '2nd'), (2, '3rd')]) {
        if (p[i] < 0) {
          setState(() => _error = '$name Pick must be a non-negative number.');
          return;
        }
      }
    }
    setState(() {
      _saving = true;
      _error = '';
    });
    final total = _total;
    final grade = eggGradeToApi(_grade);
    final form = <String, Object?>{
      'flockId': _flockId,
      'productionDate': _date,
      'eggCount': total,
      'production9AM': p[0],
      'production12PM': p[1],
      'production4PM': p[2],
      'production4thPick': p[3],
      'production5thPick': p[4],
      'production6thPick': p[5],
      'brokenEggs': _broken,
      'notes': _notes.text,
      'totalProduction': total,
      'farmId': _farmId,
      'userId': _userId,
      'eggGrade': grade,
    };
    try {
      if (_edit) {
        await _api.put('/api/EggProduction/${widget.productionId}', body: {...mapEggRow(_record), ...form});
      } else {
        await _api.post('/api/EggProduction', body: {
          ...form,
          'specificFeedUsedId': null,
          'specificFeedUsedName': null,
          'feedUnitCost': null,
          'totalFeedConsumed': null,
          'totalFeedCost': null,
          'specificMedicationUsedId': null,
          'specificMedicationUsedName': null,
          'medicationUnitCost': null,
          'totalMedicationConsumed': null,
          'totalMedicationCost': null,
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message.isNotEmpty ? e.message : (_edit ? 'Failed to update egg production' : 'An unknown error occurred');
        _saving = false;
      });
      return;
    }
    await _syncProductionRecord(p, total, grade);
    if (mounted) Navigator.of(context).pop(true);
  }

  /// Push the picks into that day's production record for the flock (edit
  /// only updates; add also creates one when there is none).
  Future<void> _syncProductionRecord(List<num> p, num total, String? grade) async {
    try {
      final records = rowsOf(await _api.get('/api/ProductionRecord', query: _ctx));
      List<Map>? flocks;
      try {
        flocks = rowsOf(await _api.get('/api/Flock', query: _ctx));
      } on ApiException {
        flocks = null;
      }
      final flock = flocks?.where((f) => tIntOrNull(f['flockId']) == _flockId || tIntOrNull(f['batchId']) == _flockId).firstOrNull;
      String utcDay(Object? v) => DateTime.tryParse(tStr(v))?.toUtc().toIso8601String().split('T').first ?? '';
      final match = records
          .where((pr) =>
              (tIntOrNull(pr['flockId']) == _flockId || (flock != null && tIntOrNull(pr['flockId']) == tIntOrNull(flock['flockId']))) &&
              utcDay(pr['date']) == _date)
          .firstOrNull;
      if (match != null) {
        final id = tIntOrNull(match['id']);
        await _api.put('/api/ProductionRecord/$id',
            body: productionRecordPayload({
              'production9AM': p[0],
              'production12PM': p[1],
              'production4PM': p[2],
              'production4thPick': p[3],
              'production5thPick': p[4],
              'production6thPick': p[5],
              'totalProduction': total,
              'eggGrade': grade,
            }, id: id));
      } else if (!_edit && flock != null) {
        final s = tStr(flock['startDate']).split('T').first.split('-').map(int.tryParse).toList();
        final d = _date.split('-').map(int.tryParse).toList();
        var days = 0;
        if (s.length == 3 && d.length == 3 && !s.contains(null) && !d.contains(null)) {
          final diff = DateTime.utc(d[0]!, d[1]!, d[2]!).difference(DateTime.utc(s[0]!, s[1]!, s[2]!)).inDays;
          days = diff < 0 ? 0 : diff;
        }
        await _api.post('/api/ProductionRecord',
            body: productionRecordPayload({
              'farmId': _farmId,
              'userId': _userId,
              'createdBy': _userId,
              'updatedBy': _userId,
              'ageInWeeks': days ~/ 7,
              'ageInDays': days,
              'date': '${_date}T00:00:00Z',
              'noOfBirds': tNum(flock['quantity']),
              'mortality': 0,
              'noOfBirdsLeft': tNum(flock['quantity']),
              'feedKg': 0,
              'medication': 'None',
              'production9AM': p[0],
              'production12PM': p[1],
              'production4PM': p[2],
              'production4thPick': p[3],
              'production5thPick': p[4],
              'production6thPick': p[5],
              'totalProduction': total,
              'flockId': tIntOrNull(flock['flockId']) ?? _flockId,
              'eggGrade': grade,
            }));
      }
    } on ApiException {
      // The web logs the sync error and still leaves the page.
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _saving;
    final labels = _picks.labels;
    final total = _total;
    final flockOptions = [
      for (final f in _flocks)
        if (_edit
            ? (tIntOrNull(f['flockId']) == _flockId && _flockId != 0) || !isFlockClosed(f)
            : f['hasArrived'] == true && !isFlockClosed(f) && (_batch == 'ALL' || tStr(f['batchId']) == _batch))
          f,
    ];
    const colors = [
      (Color(0xFFEFF6FF), Color(0xFFBFDBFE), Color(0xFF1E40AF), Color(0xFF1D4ED8), TColors.blue600),
      (Color(0xFFFFF7ED), Color(0xFFFED7AA), Color(0xFF9A3412), Color(0xFFC2410C), Color(0xFFEA580C)),
      (Color(0xFFFAF5FF), Color(0xFFE9D5FF), Color(0xFF6B21A8), Color(0xFF7E22CE), Color(0xFF9333EA)),
      (Color(0xFFF0FDFA), Color(0xFF99F6E4), Color(0xFF115E59), Color(0xFF0F766E), Color(0xFF0D9488)),
      (Color(0xFFF0FDFA), Color(0xFF99F6E4), Color(0xFF115E59), Color(0xFF0F766E), Color(0xFF0D9488)),
      (Color(0xFFF0FDFA), Color(0xFF99F6E4), Color(0xFF115E59), Color(0xFF0F766E), Color(0xFF0D9488)),
    ];
    final pickRows = <(int, String)>[
      (0, labels.first),
      (1, labels.second),
      (2, labels.third),
      if (_picks.enableFourth || _pick(3) > 0) (3, labels.fourth),
      if (_picks.enableFifth || _pick(4) > 0) (4, labels.fifth),
      if (_picks.enableSixth || _pick(5) > 0) (5, labels.sixth),
    ];
    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(t, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate700)),
        );

    return Scaffold(
      appBar: AppBar(title: Text(_edit ? 'Edit Production Record' : 'Add New Egg Sorting Record')),
      body: _loading
          ? const Padding(padding: EdgeInsets.all(24), child: LinearProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
              Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: const Color(0xFFFEF9C3), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.egg_outlined, size: 20, color: Color(0xFFCA8A04)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_edit ? 'Edit Production Record' : 'Add New Egg Sorting Record',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: TColors.slate900)),
                    Text(_edit ? 'Update the egg production details below' : 'Enter the egg production details below',
                        style: const TextStyle(color: TColors.slate600)),
                  ]),
                ),
              ]),
              const SizedBox(height: 16),
              if (_error.isNotEmpty) ...[TrackerBanner.error(_error), const SizedBox(height: 16)],
              TCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Text('Production Details', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: TColors.slate900)),
                  const SizedBox(height: 14),
                  if (!_edit) ...[
                    label('Batch'),
                    AppSelect<String>(
                      value: _batch,
                      hintText: 'All batches',
                      enabled: !busy,
                      items: [
                        const AppSelectItem(value: 'ALL', label: 'All batches'),
                        for (final b in _batches)
                          AppSelectItem(
                            value: tStr(b['batchId']),
                            label: tStr(b['batchName']).isNotEmpty
                                ? tStr(b['batchName'])
                                : (tStr(b['batchCode']).isNotEmpty ? tStr(b['batchCode']) : 'Batch #${tStr(b['batchId'])}'),
                          ),
                      ],
                      onChanged: (v) => setState(() {
                        _batch = v ?? 'ALL';
                        if (_batch != 'ALL' && _flockId != 0) {
                          final fb = _flocks.where((f) => tIntOrNull(f['flockId']) == _flockId).firstOrNull;
                          if (fb == null || tStr(fb['batchId']) != _batch) _flockId = 0;
                        }
                      }),
                    ),
                    const SizedBox(height: 4),
                    const Text('Filters flocks below.', style: TextStyle(fontSize: 12, color: TColors.slate500)),
                    const SizedBox(height: 16),
                  ],
                  label('Flock *'),
                  AppSelect<String>(
                    value: _flockId == 0 ? null : '$_flockId',
                    hintText: 'Select a flock',
                    enabled: !busy,
                    items: [for (final f in flockOptions) AppSelectItem(value: tStr(f['flockId']), label: tStr(f['name']))],
                    onChanged: (v) => setState(() => _flockId = int.tryParse(v ?? '') ?? 0),
                  ),
                  const SizedBox(height: 16),
                  label('Production Date *'),
                  AppDateField(
                    value: businessDateAsDateTime(_date),
                    enabled: !busy,
                    lastDate: _edit ? null : businessDateAsDateTime(isoDay(DateTime.now().toUtc())),
                    onChanged: (v) => setState(() => _date = v == null ? '' : isoDay(v)),
                  ),
                  const SizedBox(height: 16),
                  label('Total Eggs Collected'),
                  NumBox(key: ValueKey('egg-total-$total'), value: total, onChanged: (_) {}, enabled: false),
                  const SizedBox(height: 16),
                  label('Broken Eggs'),
                  NumBox(key: ValueKey('egg-broken-$_seed'), value: _broken, enabled: !busy, onChanged: (v) => setState(() => _broken = v)),
                  const SizedBox(height: 16),
                  label('Egg size (slot / sort)'),
                  AppSelect<String>(
                    value: _grade,
                    hintText: 'Select grade',
                    enabled: !busy,
                    items: [for (final (v, l) in eggGradeOptions) AppSelectItem(value: v, label: l)],
                    onChanged: (v) => setState(() => _grade = v ?? eggGradeNone),
                  ),
                  const SizedBox(height: 4),
                  const Text('One grade per record. For another grade the same day, add a separate production row.',
                      style: TextStyle(fontSize: 12, color: TColors.slate500)),
                  const SizedBox(height: 16),
                  for (final (i, l) in pickRows) ...[
                    _pickBox(i, l, colors[i], busy),
                    const SizedBox(height: 12),
                  ],
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: TColors.emerald50, border: Border.all(color: const Color(0xFFA7F3D0)), borderRadius: BorderRadius.circular(8)),
                    child: Row(children: [
                      const Expanded(child: Text('Total Eggs', style: TextStyle(fontWeight: FontWeight.w600, color: TColors.emerald800))),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('${loc(total)} eggs', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: TColors.emerald700)),
                        Text('${total ~/ eggsPerCrate} crates + ${(total % eggsPerCrate).toInt()} pieces',
                            style: const TextStyle(fontSize: 12, color: TColors.emerald600)),
                      ]),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  label('Notes'),
                  AppInput(controller: _notes, minLines: 3, maxLines: 5, enabled: !busy),
                ]),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: TColors.red600, minimumSize: const Size.fromHeight(44)),
                    onPressed: busy ? null : () => Navigator.of(context).maybePop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: TColors.blue600, minimumSize: const Size.fromHeight(44)),
                    onPressed: busy ? null : _submit,
                    child: Text(_edit ? (_saving ? 'Updating...' : 'Update Record') : (_saving ? 'Creating...' : 'Create Record')),
                  ),
                ),
              ]),
            ]),
    );
  }

  Widget _pickBox(int i, String title, (Color, Color, Color, Color, Color) c, bool busy) {
    final total = _pick(i);
    void set(VoidCallback f) => setState(() {
          f();
          if (i == 4 || i == 5) {
            _keep5 = null;
            _keep6 = null;
          }
        });
    return Container(
      key: ValueKey('egg-pick-$i'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.$1, border: Border.all(color: c.$2), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('$title — Crates × $eggsPerCrate + Loose Eggs', style: TextStyle(fontWeight: FontWeight.w600, color: c.$3)),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Crates', style: TextStyle(fontSize: 12)),
              NumBox(key: ValueKey('egg-c$i-$_seed'), value: _crates[i], enabled: !busy, onChanged: (v) => set(() => _crates[i] = v.toInt())),
            ]),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Loose Eggs', style: TextStyle(fontSize: 12)),
              NumBox(key: ValueKey('egg-l$i-$_seed'), value: _loose[i], enabled: !busy, onChanged: (v) => set(() => _loose[i] = v.toInt())),
            ]),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Total', style: TextStyle(fontSize: 12)),
              Container(
                height: 40,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
                child: Text(loc(total), style: TextStyle(fontWeight: FontWeight.w700, color: c.$4)),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 6),
        Text('${_n(_crates[i])} crates × $eggsPerCrate + ${_n(_loose[i])} loose = ${loc(total)} eggs', style: TextStyle(fontSize: 12, color: c.$5)),
      ]),
    );
  }

  String _n(num v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';
}

/// `/egg-production/new` and `/egg-production/{id}`.
Widget? eggSortingScreenForHref(String href, Session s, Company c) {
  final uri = Uri.tryParse(href);
  if (uri == null) return null;
  if (uri.path == '/egg-production/new') return EggSortingFormPage(session: s, company: c);
  final m = RegExp(r'^/egg-production/(\d+)$').firstMatch(uri.path);
  if (m != null) return EggSortingFormPage(session: s, company: c, productionId: int.parse(m[1]!));
  return null;
}
