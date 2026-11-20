// Poultry → Operations → Production → Feed Usage, as rebuilt on the web for
// migration 389 (app/feed-usage/page.tsx, components/feed-usage/
// record-feed-usage-dialog.tsx, lib/production/feed-usage.ts). Feed comes out of
// inventory: an entry picks the feed from stock and adds it as feed lines to
// each flock's production record for the day -- the one place feed leaves
// stock.
//
// Feed log: every feed line on the farm's production records, whichever screen
// entered it. Entries: what was recorded here, with reversal. The web's table
// rows are cards on a phone.

import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../shared/business_dates.dart';
import '../../shared/company_clock.dart';
import '../../shared/reason_dialog.dart';
import '../../shared/reason_select.dart' show stockReversalReasons;
import '../reports/report_format.dart' show FarmMoney;
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../trackers/tracker_widgets.dart';
import 'production_logic.dart';
import 'package:poultrycore_mobile/design/tone.dart';
import 'production_record_form.dart' show ProductionRecordPage;
import 'production_widgets.dart' show ConsumptionLines;

// ------------------------------------------------------------ feed-usage.ts

String kgText(num n) => '${_trim((n * 1000).round() / 1000)} kg';
String _trim(num n) => n == n.roundToDouble() ? n.toInt().toString() : n.toString();

/// Which screen put a feed line on its record.
String feedSourceLabel(Map r) {
  if (r['recordSource'] == 'Legacy') return 'Old entry (not from stock)';
  if (r['entryId'] != null) return 'Feed Usage';
  if (r['distributionId'] != null) return 'Distribute Feed';
  if (r['recordSource'] == 'BatchAllocation') return 'Batch production';
  return 'Production record';
}

/// splitFeed: [totalKg] across flocks, in grams so the parts sum exactly; a
/// leftover gram goes to the largest remainder, then the most birds.
Map<int, num> splitFeed(num totalKg, List<({int flockId, num? birds})> flocks, String basis) {
  final out = <int, num>{};
  if (!(totalKg > 0) || flocks.isEmpty) {
    for (final f in flocks) {
      out[f.flockId] = 0;
    }
    return out;
  }
  final grams = (totalKg * 1000).round();
  final weights = [for (final f in flocks) basis == 'Equal' ? 1.0 : ((f.birds ?? 0) > 0 ? f.birds!.toDouble() : 0.0)];
  final sumW = weights.fold<double>(0, (a, b) => a + b);
  final w = sumW > 0 ? weights : [for (final _ in flocks) 1.0];
  final total = w.fold<double>(0, (a, b) => a + b);
  final exact = [for (final x in w) grams * x / total];
  final base = [for (final x in exact) x.floor()];
  var left = grams - base.fold<int>(0, (a, b) => a + b);
  final order = [for (var i = 0; i < exact.length; i++) (i: i, rem: exact[i] - base[i], birds: flocks[i].birds ?? 0)]
    ..sort((a, b) {
      final r = b.rem.compareTo(a.rem);
      if (r != 0) return r;
      final bd = b.birds.compareTo(a.birds);
      return bd != 0 ? bd : a.i - b.i;
    });
  for (var k = 0; left > 0; k = (k + 1) % order.length, left--) {
    base[order[k].i]++;
  }
  for (var i = 0; i < flocks.length; i++) {
    out[flocks[i].flockId] = base[i] / 1000;
  }
  return out;
}

/// Sum of kg, rounded to grams so float noise never fails a comparison.
num sumKg(Iterable<num> values) => (values.fold<num>(0, (a, b) => a + (b.isFinite ? b : 0)) * 1000).round() / 1000;

/// What saving will do to a flock's production record, in plain words.
String recordStatusNote(String status) => switch (status) {
      'Recorded' => "Added to this flock's production record for the day.",
      'FeedOnly' => 'This flock already has feed recorded today, but no production yet. The feed is added to it.',
      'None' => 'No production record yet. A feed-only record is made; production for this day still shows as missing until it is filled in.',
      _ => 'This flock has more than one production record for the day. Fix the duplicate before recording feed.',
    };

bool canFeed(Map c) => c['recordStatus'] != 'Duplicate';

/// Batches that have at least one flock expected on the date, in the server's order.
List<({int batchId, String batchName, List<Map> flocks})> batchesFrom(List<Map> candidates) {
  final map = <int, ({int batchId, String batchName, List<Map> flocks})>{};
  for (final c in candidates) {
    final id = tIntOrNull(c['batchId']);
    if (id == null) continue;
    map.putIfAbsent(id, () => (batchId: id, batchName: tStr(c['batchName']).isEmpty ? 'Batch $id' : tStr(c['batchName']), flocks: <Map>[]));
    map[id]!.flocks.add(c);
  }
  return map.values.toList();
}

/// One feed's split across a batch: the reason saving is blocked, or null.
String? splitBlocker(String itemName, num totalKg, List<num> parts) {
  final s = sumKg(parts);
  final t = (totalKg * 1000).round() / 1000;
  if (parts.any((p) => p < 0)) return "$itemName: a flock's share cannot be negative.";
  if ((s - t).abs() > 0.0005) {
    return "$itemName: the flocks' shares add up to ${_trim(s)} kg, not ${_trim(t)} kg. Split all of it before saving.";
  }
  return null;
}

const recordStatusLabel = {'Recorded': 'production recorded', 'FeedOnly': 'feed only so far', 'None': 'no record yet', 'Duplicate': 'duplicate records'};
const _statusTone = {
  'Recorded': (Tone(0xFFECFDF5), Tone(0xFF047857)),
  'FeedOnly': (Tone(0xFFFFFBEB), Tone(0xFF92400E)),
  'None': (Tone(0xFFF1F5F9), Tone(0xFF475569)),
  'Duplicate': (Tone(0xFFFFF1F2), Tone(0xFFBE123C)),
};

Widget statusPill(String status) {
  final t = _statusTone[status] ?? _statusTone['None']!;
  return TBadge(recordStatusLabel[status] ?? status, bg: t.$1, fg: t.$2);
}

// ------------------------------------------------------------ the page

class FeedUsageScreen extends StatefulWidget {
  const FeedUsageScreen({super.key, required this.session, required this.company, this.openRecord = false});
  final Session session;
  final Company company;

  /// /feed-usage?record=1 (the old "new" page and quick links): opens the form.
  final bool openRecord;
  @override
  State<FeedUsageScreen> createState() => _FeedUsageScreenState();
}

class _FeedUsageScreenState extends State<FeedUsageScreen> {
  String _tab = 'log';
  String _from = '', _to = '', _today = '';
  String _flock = 'ALL', _search = '';
  List<Map>? _log, _entries;
  String? _error;
  bool _loading = false;
  int? _openEntry;
  final Map<int, List<Map>> _entryLines = {};
  int _logPage = 1, _entryPage = 1;
  FarmMoney _money = const FarmMoney();
  CompanyClock? _clock;

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  bool get _canCreate => true;
  bool get _canDelete => (widget.company.role ?? '').toLowerCase() != 'staff';

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _money = m);
    });
    CompanyClock.load(widget.session, widget.company).then((c) {
      if (!mounted) return;
      // Last 30 days by default, once the company's date is known.
      final t = businessDateAsDateTime(c.today) ?? DateTime.now();
      setState(() {
        _clock = c;
        _today = c.today;
        _to = c.today;
        _from = isoDay(t.subtract(const Duration(days: 29)));
      });
      _load();
      if (widget.openRecord) _record();
    });
  }

  Future<void> _load() async {
    if (_from.isEmpty || _to.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final q = {'farmId': _farmId, 'fromDate': _from, 'toDate': _to};
      final r = await Future.wait([
        _api.get('/api/Poultry/feed-usage-entries/log', query: q),
        _api.get('/api/Poultry/feed-usage-entries', query: q),
      ]);
      if (!mounted) return;
      setState(() {
        _log = rowsOf(r[0]);
        _entries = rowsOf(r[1]);
        _entryLines.clear();
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message.isEmpty ? 'Could not load feed usage.' : e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<(int, String)> get _flocks {
    final m = <int, String>{};
    for (final r in _log ?? const <Map>[]) {
      final id = tIntOrNull(r['flockId']) ?? 0;
      m[id] = tStr(r['flockName']).isEmpty ? 'Flock $id' : tStr(r['flockName']);
    }
    return m.entries.map((e) => (e.key, e.value)).toList()..sort((a, b) => a.$2.compareTo(b.$2));
  }

  List<Map> get _shown {
    final q = _search.trim().toLowerCase();
    return [
      for (final r in _log ?? const <Map>[])
        if ((_flock == 'ALL' || '${r['flockId']}' == _flock) &&
            (q.isEmpty || '${r['flockName'] ?? ''} ${r['itemName'] ?? ''} ${feedSourceLabel(r)}'.toLowerCase().contains(q)))
          r,
    ];
  }

  Future<void> _toggleEntry(int id) async {
    if (_openEntry == id) {
      setState(() => _openEntry = null);
      return;
    }
    setState(() => _openEntry = id);
    if (_entryLines[id] == null) {
      try {
        final res = await _api.get('/api/Poultry/feed-usage-entries/$id/lines', query: {'farmId': _farmId});
        if (mounted) setState(() => _entryLines[id] = rowsOf(res));
      } on ApiException catch (e) {
        if (mounted) trackerToast(context, 'Could not load the entry', description: e.message, error: true);
      }
    }
  }

  Future<void> _reverse(Map e) async {
    final reason = await showReasonDialog(
      context,
      title: 'Reverse this feed usage?',
      options: stockReversalReasons,
      description: "The feed comes off each flock's production record and goes back into stock. A feed-only record left empty is removed. "
          'The entry stays in the history, marked Reversed.',
      confirmLabel: 'Reverse',
      destructive: true,
    );
    if (reason == null || !mounted) return;
    try {
      await _api.post('/api/Poultry/feed-usage-entries/${e['poultryFeedUsageEntryId']}/reversal', body: {'farmId': _farmId, 'reason': reason});
      if (mounted) trackerToast(context, 'Feed usage reversed', description: 'The feed is back in stock.');
      await _load();
    } on ApiException catch (err) {
      if (mounted) trackerToast(context, 'Not reversed', description: err.message, error: true);
    }
  }

  Future<void> _record() async {
    if (_today.isEmpty) return;
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => RecordFeedUsageScreen(session: widget.session, company: widget.company, today: _today),
    ));
    if (saved == true) _load();
  }

  void _openRecord(Object? id) {
    final rid = tIntOrNull(id);
    if (rid == null) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductionRecordPage(session: widget.session, company: widget.company, recordId: rid)));
  }

  Future<void> _pickDate(bool from) async {
    final cur = businessDateAsDateTime(from ? _from : _to) ?? DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: cur,
      firstDate: DateTime(2000),
      lastDate: businessDateAsDateTime(_today) ?? DateTime.now(),
    );
    if (d == null) return;
    setState(() => from ? _from = isoDay(d) : _to = isoDay(d));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/feed-usage');
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Feed Usage')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(key: const ValueKey('feed-usage-list'), padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: TColors.amber100, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.grass, size: 20, color: TColors.amber700),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Feed Usage', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: TColors.slate900)),
                Text("Feed taken from stock for each flock. It also shows on the flock's production record.",
                    style: TextStyle(fontSize: 13, color: TColors.slate600)),
              ]),
            ),
          ]),
          if (_canCreate) ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              key: const ValueKey('feed-usage-record'),
              style: FilledButton.styleFrom(backgroundColor: Tone.button(TColors.emerald600), foregroundColor: Colors.white),
              onPressed: _today.isEmpty ? null : _record,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Record feed usage'),
            ),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: FilterLabel('From', _dateBox(_from, () => _pickDate(true), const ValueKey('feed-usage-from')))),
            const SizedBox(width: 8),
            Expanded(child: FilterLabel('To', _dateBox(_to, () => _pickDate(false), const ValueKey('feed-usage-to')))),
          ]),
          if (_tab == 'log') ...[
            const SizedBox(height: 8),
            FilterLabel(
              'Flock',
              AppSelect<String>(
                key: const ValueKey('feed-usage-flock'),
                value: _flock,
                items: [
                  const AppSelectItem(value: 'ALL', label: 'All flocks'),
                  for (final (id, name) in _flocks) AppSelectItem(value: '$id', label: name),
                ],
                onChanged: (v) => setState(() {
                  _flock = v ?? 'ALL';
                  _logPage = 1;
                }),
              ),
            ),
            const SizedBox(height: 8),
            FilterLabel(
              'Search',
              AppInput(
                key: const ValueKey('feed-usage-search'),
                hintText: 'Flock or feed',
                onChanged: (v) => setState(() {
                  _search = v;
                  _logPage = 1;
                }),
              ),
            ),
          ],
          if (_loading) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator(minHeight: 2)),
          if (_error != null) ...[const SizedBox(height: 12), TrackerBanner.error(_error!)],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: TColors.slate100, borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              Expanded(child: _tabButton('log', 'Feed log')),
              Expanded(child: _tabButton('entries', 'Entries')),
            ]),
          ),
          const SizedBox(height: 14),
          ...(_tab == 'log' ? _logTab() : _entriesTab()),
        ]),
      ),
    );
  }

  Widget _dateBox(String value, VoidCallback onTap, Key key) => OutlinedButton.icon(
        key: key,
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44), alignment: Alignment.centerLeft, backgroundColor: Tone.bg(0xFFFFFFFF)),
        onPressed: onTap,
        icon: const Icon(Icons.calendar_today_outlined, size: 16),
        label: Text(value.isEmpty ? '—' : formatShortDate(value), overflow: TextOverflow.ellipsis),
      );

  Widget _tabButton(String value, String label) {
    final on = _tab == value;
    return InkWell(
      key: ValueKey('feed-usage-tab-$value'),
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => _tab = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: on ? Tone.bg(0xFFFFFFFF) : Colors.transparent, borderRadius: BorderRadius.circular(8)),
        child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: on ? TColors.slate900 : TColors.slate600)),
      ),
    );
  }

  Widget _stat(String label, String value, {bool warn = false}) => Container(
        key: ValueKey('feed-usage-stat-$label'),
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Tone.bg(0xFFFFFFFF), border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: .6, color: TColors.slate500)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: warn ? TColors.amber700 : TColors.slate900)),
        ]),
      );

  List<Widget> _logTab() {
    final shown = _shown;
    final kgTotal = shown.fold<num>(0, (a, r) => a + tNum(r['quantityKg']));
    final cost = shown.fold<num>(0, (a, r) => a + tNum(r['totalCost']));
    final feedOnly = {for (final r in shown) if (r['feedOnly'] == true) r['productionRecordId']}.length;
    const per = 20;
    final pages = (shown.length / per).ceil();
    final page = _logPage.clamp(1, pages < 1 ? 1 : pages);
    final slice = shown.skip((page - 1) * per).take(per).toList();
    return [
      _stat('Feed used', kgText(kgTotal)),
      _stat('Feed cost', _money(cost)),
      _stat('Feed only, production not filled', '$feedOnly', warn: feedOnly > 0),
      const SizedBox(height: 4),
      if (_log == null)
        const Padding(padding: EdgeInsets.all(14), child: Text('Loading…', style: TextStyle(color: TColors.slate500)))
      else if (shown.isEmpty)
        _emptyCard('No feed used in this period.')
      else
        for (final r in slice) _logCard(r),
      if (pages > 1) _pager(page, pages, (p) => setState(() => _logPage = p)),
      const SizedBox(height: 8),
      const Text(
        'To change feed on a day, open its production record, or reverse the Feed Usage entry. Old entries typed in before feed came from stock are shown for reference only.',
        style: TextStyle(fontSize: 12, color: TColors.slate500),
      ),
    ];
  }

  Widget _emptyCard(String text) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Tone.bg(0xFFFFFFFF), border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: const TextStyle(fontSize: 14, color: TColors.slate500)),
      );

  Widget _pager(int page, int pages, ValueChanged<int> go) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(onPressed: page > 1 ? () => go(page - 1) : null, icon: const Icon(Icons.chevron_left)),
        Text('Page $page of $pages', style: const TextStyle(fontSize: 13, color: TColors.slate600)),
        IconButton(onPressed: page < pages ? () => go(page + 1) : null, icon: const Icon(Icons.chevron_right)),
      ]);

  Widget _logCard(Map r) {
    final legacy = r['recordSource'] == 'Legacy';
    final rid = r['productionRecordId'];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Tone.bg(0xFFFFFFFF), border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tStr(r['flockName']).isEmpty ? 'Flock ${r['flockId']}' : tStr(r['flockName']),
                  style: const TextStyle(fontWeight: FontWeight.w600, color: TColors.slate900)),
              Text(formatLongDate(tStr(r['usageDate']).split('T').first), style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(kgText(tNum(r['quantityKg'])), style: const TextStyle(fontWeight: FontWeight.w600, color: TColors.slate900)),
            Text(r['totalCost'] != null ? _money(tNum(r['totalCost'])) : '—', style: const TextStyle(fontSize: 12, color: TColors.slate600)),
          ]),
        ]),
        const SizedBox(height: 6),
        Text('Feed: ${tStr(r['itemName']).isEmpty ? '—' : tStr(r['itemName'])}', style: const TextStyle(fontSize: 13, color: TColors.slate700)),
        Text('Entered from: ${feedSourceLabel(r)}', style: TextStyle(fontSize: 12, color: legacy ? TColors.slate400 : TColors.slate600)),
        if (rid != null) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (r['feedOnly'] == true) const TBadge('Production not filled', bg: Tone.bg(0xFFFFFBEB), fg: Tone.fg(0xFF92400E)),
            InkWell(
              onTap: () => _openRecord(rid),
              child: Text(r['feedOnly'] == true ? 'Fill in production' : 'Open',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Tone.fg(0xFF0369A1))),
            ),
          ]),
        ],
      ]),
    );
  }

  List<Widget> _entriesTab() {
    final entries = _entries;
    const per = 10;
    final all = entries ?? const <Map>[];
    final pages = (all.length / per).ceil();
    final page = _entryPage.clamp(1, pages < 1 ? 1 : pages);
    return [
      if (entries == null)
        const Padding(padding: EdgeInsets.all(14), child: Text('Loading…', style: TextStyle(color: TColors.slate500)))
      else if (entries.isEmpty)
        _emptyCard('Nothing recorded from this page in this period.')
      else
        for (final e in all.skip((page - 1) * per).take(per)) _entryCard(e),
      if (pages > 1) _pager(page, pages, (p) => setState(() => _entryPage = p)),
    ];
  }

  Widget _entryCard(Map e) {
    final id = tIntOrNull(e['poultryFeedUsageEntryId']) ?? 0;
    final open = _openEntry == id;
    final posted = e['status'] == 'Posted';
    final flocks = tIntOrNull(e['flockCount']) ?? 0;
    final feedOnly = tIntOrNull(e['feedOnlyRecords']) ?? 0;
    final when = _clock?.instant(e['postedAtUtc']) ?? tStr(e['postedAtUtc']);
    final lines = _entryLines[id];
    return Container(
      key: ValueKey('feed-usage-entry-$id'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Tone.bg(0xFFFFFFFF), border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: () => _toggleEntry(id),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(open ? Icons.expand_less : Icons.expand_more, size: 18, color: TColors.slate400),
            const SizedBox(width: 6),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  '${formatLongDate(tStr(e['businessDate']).split('T').first)} · '
                  '${e['scope'] == 'Batch' ? '${tStr(e['batchName']).isEmpty ? 'Batch' : tStr(e['batchName'])} ($flocks flocks)' : '1 flock'} · '
                  '${kgText(tNum(e['totalKg']))}${e['totalCost'] != null ? ' · ${_money(tNum(e['totalCost']))}' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.slate900),
                ),
                Text(
                  '#$id · by ${tStr(e['postedBy']).isEmpty ? 'unknown' : tStr(e['postedBy'])} · $when'
                  '${tStr(e['notes']).isNotEmpty ? ' · “${e['notes']}”' : ''}'
                  '${feedOnly > 0 ? ' · made $feedOnly feed-only record${feedOnly == 1 ? '' : 's'}' : ''}',
                  style: const TextStyle(fontSize: 12, color: TColors.slate500),
                ),
                if (e['status'] == 'Reversed')
                  Text(
                    'Reversed by ${tStr(e['reversedBy']).isEmpty ? 'unknown' : tStr(e['reversedBy'])} '
                    '(${_clock?.instant(e['reversedAtUtc']) ?? tStr(e['reversedAtUtc'])}): ${tStr(e['reversalReason'])}',
                    style: const TextStyle(fontSize: 12, color: TColors.rose700),
                  ),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          TBadge(tStr(e['status']), bg: posted ? const Tone.bg(0xFFD1FAE5) : TColors.slate100, fg: posted ? const Tone.fg(0xFF047857) : TColors.slate600),
          if (posted && _canDelete)
            OutlinedButton.icon(
              key: ValueKey('feed-usage-reverse-$id'),
              style: OutlinedButton.styleFrom(backgroundColor: Tone.button(Tone.bg(0xFFFFFFFF)), foregroundColor: TColors.rose700),
              onPressed: () => _reverse(e),
              icon: const Icon(Icons.undo, size: 14),
              label: const Text('Reverse'),
            ),
        ]),
        if (open) ...[
          const SizedBox(height: 8),
          if (lines == null)
            const Text('Loading…', style: TextStyle(fontSize: 12, color: TColors.slate500))
          else
            for (final l in lines)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: TColors.slate100))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('${tStr(l['flockName'])} · ${tStr(l['itemName'])}', style: const TextStyle(fontSize: 13, color: TColors.slate800))),
                    Text(kgText(tNum(l['quantityKg'])), style: const TextStyle(fontSize: 13, color: TColors.slate800)),
                    const SizedBox(width: 8),
                    Text(l['totalCost'] != null ? _money(tNum(l['totalCost'])) : '—', style: const TextStyle(fontSize: 13, color: TColors.slate600)),
                  ]),
                  Wrap(children: [
                    InkWell(
                      onTap: () => _openRecord(l['productionRecordId']),
                      child: Text('#${l['productionRecordId']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Tone.fg(0xFF0369A1))),
                    ),
                    if (l['createdRecord'] == true) const Text(' · made feed-only', style: TextStyle(fontSize: 12, color: TColors.slate500)),
                    if (tStr(l['reversalNote']).isNotEmpty) Text(' · ${l['reversalNote']}', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                  ]),
                ]),
              ),
        ],
      ]),
    );
  }
}

// ------------------------------------------------------------ Record feed usage

/// RecordFeedUsageDialog, as a full-screen form: feed picked from stock for
/// one flock or a whole batch; a batch total split By birds, Equally or By
/// hand before it can be saved.
class RecordFeedUsageScreen extends StatefulWidget {
  const RecordFeedUsageScreen({super.key, required this.session, required this.company, required this.today});
  final Session session;
  final Company company;

  /// The company's business date: the default, and the latest date allowed.
  final String today;
  @override
  State<RecordFeedUsageScreen> createState() => _RecordFeedUsageScreenState();
}

class _RecordFeedUsageScreenState extends State<RecordFeedUsageScreen> {
  late String _date = widget.today;
  String _scope = 'Flock';
  String _flockId = '', _batchId = '';
  final List<ConsumptionLine> _lines = [ConsumptionLine()];
  int _seed = 0;
  String _basis = 'Birds';

  /// Manual split: flockId -> itemId -> text.
  final Map<int, Map<int, TextEditingController>> _manual = {};
  final _notes = TextEditingController();
  List<Map>? _candidates;
  bool _loadingCands = false, _saving = false;
  List<Map> _rawItems = [], _purchases = [];
  String? _error;

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;

  @override
  void initState() {
    super.initState();
    _loadStock();
    _loadCandidates();
  }

  @override
  void dispose() {
    _notes.dispose();
    for (final m in _manual.values) {
      for (final c in m.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _loadStock() async {
    Future<List<Map>> list(String path) async {
      try {
        return rowsOf(await _api.get(path, query: {'farmId': _farmId}));
      } on ApiException {
        return [];
      }
    }

    final r = await Future.wait([list('/api/Poultry/raw-material-items'), list('/api/Poultry/raw-material-purchases')]);
    if (mounted) {
      setState(() {
        _rawItems = r[0];
        _purchases = r[1];
      });
    }
  }

  Future<void> _loadCandidates() async {
    setState(() => _loadingCands = true);
    try {
      final res = await _api.get('/api/Poultry/feed-usage-entries/candidates', query: {'farmId': _farmId, 'businessDate': _date});
      if (mounted) setState(() => _candidates = rowsOf(res));
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _candidates = [];
          _error = e.message.isEmpty ? 'Could not load the flocks.' : e.message;
        });
      }
    } finally {
      if (mounted) setState(() => _loadingCands = false);
    }
  }

  /// Only finished feed can be picked -- an ingredient reaches a flock through a feed batch.
  List<Map> get _feedItems => [for (final i in _rawItems) if (isFinishedFeedCategory(i['category'])) i];
  LinesComputed get _computed => computeLines(_lines, _feedItems, _purchases, const {}, LineKeys.feed);

  /// One total per feed (two lines of the same feed are one draw).
  List<({int itemId, String name, num qty})> get _feedTotals {
    final m = <int, ({int itemId, String name, num qty})>{};
    for (final r in _computed.rows) {
      if (r.item == null || !(r.qty > 0)) continue;
      final id = tIntOrNull(r.item!['poultryRawMaterialItemId']) ?? 0;
      final cur = m[id];
      m[id] = (itemId: id, name: tStr(r.item!['itemName']), qty: sumKg([cur?.qty ?? 0, r.qty]));
    }
    return m.values.toList();
  }

  List<({int batchId, String batchName, List<Map> flocks})> get _batches => batchesFrom(_candidates ?? const []);
  Map? get _flock => (_candidates ?? const <Map>[]).where((c) => '${c['flockId']}' == _flockId).firstOrNull;
  ({int batchId, String batchName, List<Map> flocks})? get _batch => _batches.where((b) => '${b.batchId}' == _batchId).firstOrNull;
  List<Map> get _batchFlocks => [for (final f in _batch?.flocks ?? const <Map>[]) if (canFeed(f)) f];

  TextEditingController _manualCtl(int flockId, int itemId) =>
      (_manual[flockId] ??= {}).putIfAbsent(itemId, () => TextEditingController());

  /// Each feed's share per flock: computed for Birds / Equal, typed for Manual.
  Map<int, Map<int, num>> _shares(List<({int itemId, String name, num qty})> totals) {
    final flocks = _batchFlocks;
    return {
      for (final f in totals)
        f.itemId: _basis == 'Manual'
            ? {for (final b in flocks) tIntOrNull(b['flockId']) ?? 0: num.tryParse(_manual[tIntOrNull(b['flockId'])]?[f.itemId]?.text ?? '') ?? 0}
            : splitFeed(f.qty, [for (final b in flocks) (flockId: tIntOrNull(b['flockId']) ?? 0, birds: b['birds'] == null ? null : tNum(b['birds']))], _basis),
    };
  }

  /// Switching to "By hand" starts from the bird split, so nobody types it all.
  void _chooseBasis(String b) {
    if (b == 'Manual' && _basis != 'Manual') {
      final totals = _feedTotals;
      final shares = _shares(totals);
      for (final f in totals) {
        for (final bf in _batchFlocks) {
          final id = tIntOrNull(bf['flockId']) ?? 0;
          _manualCtl(id, f.itemId).text = _trim(shares[f.itemId]?[id] ?? 0);
        }
      }
    }
    setState(() => _basis = b);
  }

  String? _blocker(List<({int itemId, String name, num qty})> totals, Map<int, Map<int, num>> shares) {
    if (_date.isEmpty) return 'Choose the date.';
    if (_date.compareTo(widget.today) > 0) return 'You cannot record feed for a future date.';
    if (_scope == 'Flock') {
      final f = _flock;
      if (f == null) return 'Choose the flock.';
      if (!canFeed(f)) return recordStatusNote(tStr(f['recordStatus']));
    } else {
      if (_batch == null) return 'Choose the batch.';
      if (_batchFlocks.isEmpty) return 'No flock in this batch can be fed on this date.';
    }
    if (totals.isEmpty) return 'Add the feed used: pick a feed and enter how much.';
    final short = _computed.firstShortfall;
    if (short != null) return 'Not enough ${tStr(short.item?['itemName'])} in stock: only ${_trim(short.preview.covered)} available.';
    if (_scope == 'Batch') {
      for (final f in totals) {
        final b = splitBlocker(f.name, f.qty, [for (final bf in _batchFlocks) shares[f.itemId]?[tIntOrNull(bf['flockId'])] ?? 0]);
        if (b != null) return b;
      }
    }
    return null;
  }

  Future<void> _save() async {
    final totals = _feedTotals;
    final shares = _shares(totals);
    final blocker = _blocker(totals, shares);
    if (blocker != null) {
      setState(() => _error = blocker);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final flock = _flock;
    final payload = _scope == 'Flock'
        ? [for (final f in totals) {'flockId': tIntOrNull(flock!['flockId']), 'itemId': f.itemId, 'qty': f.qty, 'birds': flock['birds']}]
        : [
            for (final bf in _batchFlocks)
              for (final f in totals)
                if ((shares[f.itemId]?[tIntOrNull(bf['flockId'])] ?? 0) > 0)
                  {'flockId': tIntOrNull(bf['flockId']), 'itemId': f.itemId, 'qty': shares[f.itemId]![tIntOrNull(bf['flockId'])], 'birds': bf['birds']},
          ];
    try {
      await _api.post('/api/Poultry/feed-usage-entries', body: {
        'farmId': _farmId,
        'businessDate': _date,
        'scope': _scope,
        'batchId': _scope == 'Batch' ? _batch!.batchId : null,
        'splitBasis': _scope == 'Batch' ? _basis : null,
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'lines': payload,
      });
      final created = _scope == 'Flock'
          ? (flock!['recordStatus'] == 'None' ? 1 : 0)
          : _batchFlocks.where((b) => b['recordStatus'] == 'None').length;
      if (!mounted) return;
      trackerToast(
        context,
        'Feed usage recorded',
        description: created > 0
            ? 'Taken from stock. $created flock${created == 1 ? ' has' : 's have'} no production for this day yet. Fill it in from Production Records.'
            : 'Taken from stock and added to the production record.',
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      final insufficient = e.statusCode == 409;
      final msg = e.message.isEmpty ? (insufficient ? 'Not enough feed in stock.' : 'Could not record the feed.') : e.message;
      if (!mounted) return;
      setState(() => _error = msg);
      trackerToast(context, insufficient ? 'Not enough feed in stock' : 'Feed was not recorded', description: msg, error: true);
      if (insufficient) _loadStock();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: businessDateAsDateTime(_date) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: businessDateAsDateTime(widget.today) ?? DateTime.now(),
    );
    if (d == null) return;
    setState(() => _date = isoDay(d));
    _loadCandidates();
  }

  @override
  Widget build(BuildContext context) {
    final computed = _computed;
    final totals = _feedTotals;
    final shares = _shares(totals);
    final blocker = _blocker(totals, shares);
    final flock = _flock;
    final batch = _batch;
    return Scaffold(
      appBar: AppBar(title: const Text('Record feed usage')),
      body: ListView(key: const ValueKey('record-feed-usage-list'), padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
        const Text("Pick the feed from your stock. It is taken out of inventory and added to the flock's production record for the day.",
            style: TextStyle(fontSize: 13, color: TColors.slate600)),
        const SizedBox(height: 14),
        FilterLabel(
          'Date',
          OutlinedButton.icon(
            key: const ValueKey('rfu-date'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44), alignment: Alignment.centerLeft, backgroundColor: Tone.bg(0xFFFFFFFF)),
            onPressed: _saving ? null : _pickDate,
            icon: const Icon(Icons.calendar_today_outlined, size: 16),
            label: Text(formatLongDate(_date)),
          ),
        ),
        const SizedBox(height: 12),
        FilterLabel(
          'Feed for',
          Row(children: [
            for (final (s, label) in const [('Flock', 'One flock'), ('Batch', 'A whole batch')]) ...[
              Expanded(child: _choice(label, _scope == s, () => setState(() => _scope = s), ValueKey('rfu-scope-$s'))),
              if (s == 'Flock') const SizedBox(width: 8),
            ],
          ]),
        ),
        const SizedBox(height: 12),
        if (_scope == 'Flock') ...[
          FilterLabel(
            'Flock',
            AppSelect<String>(
              key: const ValueKey('rfu-flock'),
              value: _flockId.isEmpty ? null : _flockId,
              hintText: _loadingCands ? 'Loading flocks…' : 'Choose the flock',
              enabled: !_loadingCands,
              items: [
                for (final c in _candidates ?? const <Map>[])
                  AppSelectItem(
                    value: '${c['flockId']}',
                    label: '${tStr(c['flockName'])}${tStr(c['houseName']).isNotEmpty ? ' · ${c['houseName']}' : ''} · ${recordStatusLabel[c['recordStatus']] ?? ''}',
                    enabled: canFeed(c),
                  ),
              ],
              onChanged: (v) => setState(() => _flockId = v ?? ''),
            ),
          ),
          if (_candidates != null && _candidates!.isEmpty)
            const Text('No active flocks on this date.', style: TextStyle(fontSize: 12, color: TColors.slate400)),
          if (flock != null) ...[
            const SizedBox(height: 4),
            Text(
              '${recordStatusNote(tStr(flock['recordStatus']))}${tStr(flock['feedLines']).isNotEmpty ? ' Feed already on it: ${flock['feedLines']}.' : ''}',
              style: TextStyle(
                fontSize: 12,
                color: flock['recordStatus'] == 'None' || flock['recordStatus'] == 'FeedOnly' ? const Tone.fg(0xFF92400E) : TColors.slate500,
              ),
            ),
          ],
        ] else ...[
          FilterLabel(
            'Batch',
            AppSelect<String>(
              key: const ValueKey('rfu-batch'),
              value: _batchId.isEmpty ? null : _batchId,
              hintText: _loadingCands ? 'Loading batches…' : 'Choose the batch',
              enabled: !_loadingCands,
              items: [
                for (final b in _batches) AppSelectItem(value: '${b.batchId}', label: '${b.batchName} · ${b.flocks.length} flock${b.flocks.length == 1 ? '' : 's'}'),
              ],
              onChanged: (v) => setState(() => _batchId = v ?? ''),
            ),
          ),
          if (_candidates != null && _batches.isEmpty)
            const Text('No batches with active flocks on this date.', style: TextStyle(fontSize: 12, color: TColors.slate400)),
        ],
        const SizedBox(height: 14),
        const Text('Feed used', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: TColors.slate900)),
        const SizedBox(height: 6),
        ConsumptionLines(
          lines: _lines,
          computed: computed,
          items: _feedItems,
          itemLabel: 'Specific Feed Used',
          placeholder: 'Select feed from inventory',
          emptyText: 'No feed lines. Click Add line to draw a feed from inventory.',
          noItemsText: 'No active Finished Feed items in Raw Materials.',
          removeLabel: 'Remove feed line',
          seed: _seed,
          onAdd: () => setState(() {
            _lines.add(ConsumptionLine());
            _seed++;
          }),
          onRemove: (i) => setState(() {
            if (_lines.length == 1) {
              _lines[0] = ConsumptionLine();
            } else {
              _lines.removeAt(i);
            }
            _seed++;
          }),
          onChanged: () => setState(() {}),
        ),
        if (totals.isNotEmpty)
          Text.rich(TextSpan(style: const TextStyle(fontSize: 14, color: TColors.slate600), children: [
            const TextSpan(text: 'Total: '),
            TextSpan(text: kgText(computed.totalConsumed), style: const TextStyle(fontWeight: FontWeight.w600)),
            const TextSpan(text: ' · cost '),
            TextSpan(text: computed.totalCost.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.w600)),
          ])),
        if (_scope == 'Batch' && batch != null && totals.isNotEmpty) ...[const SizedBox(height: 12), _splitPanel(batch, totals, shares)],
        const SizedBox(height: 12),
        FilterLabel('Notes (optional)', AppInput(key: const ValueKey('rfu-notes'), controller: _notes, hintText: 'e.g. Morning feeding')),
        if (_error != null || blocker != null) ...[
          const SizedBox(height: 10),
          Text(_error ?? blocker!, key: const ValueKey('rfu-message'), style: TextStyle(fontSize: 14, color: _error != null ? TColors.rose700 : TColors.slate500)),
        ],
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
          child: Row(children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(backgroundColor: Tone.button(Tone.bg(0xFFFFFFFF)), foregroundColor: TColors.slate800),
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton(
                key: const ValueKey('rfu-save'),
                style: FilledButton.styleFrom(backgroundColor: Tone.button(TColors.emerald600), foregroundColor: Colors.white),
                onPressed: _saving || blocker != null ? null : _save,
                child: Text(_saving ? 'Saving…' : 'Record feed usage'),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _choice(String label, bool on, VoidCallback onTap, Key key) => on
      ? FilledButton(key: key, onPressed: onTap, child: Text(label))
      : OutlinedButton(key: key, style: OutlinedButton.styleFrom(backgroundColor: Tone.button(Tone.bg(0xFFFFFFFF))), onPressed: onTap, child: Text(label));

  Widget _splitPanel(({int batchId, String batchName, List<Map> flocks}) batch, List<({int itemId, String name, num qty})> totals, Map<int, Map<int, num>> shares) {
    final feedable = _batchFlocks;
    return Container(
      key: const ValueKey('rfu-split'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Tone.bg(0x80F0F9FF), border: Border.all(color: const Tone.line(0xFFBAE6FD)), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Split across the flocks', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: TColors.slate900)),
        const Text('Every kilogram must go to a flock before you can save.', style: TextStyle(fontSize: 12, color: TColors.slate600)),
        const SizedBox(height: 8),
        // Wraps on a narrow phone: three buttons in a row overflow it.
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final (k, label) in const [('Birds', 'By birds'), ('Equal', 'Equally'), ('Manual', 'By hand')])
            _choice(label, _basis == k, () => _chooseBasis(k), ValueKey('rfu-basis-$k')),
        ]),
        const SizedBox(height: 8),
        for (final bf in batch.flocks)
          Opacity(
            opacity: canFeed(bf) ? 1 : .5,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: Tone.line(0xFFE0F2FE)))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(tStr(bf['flockName']), style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.slate900)),
                const SizedBox(height: 2),
                Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('${bf['birds'] ?? '—'} birds', style: const TextStyle(fontSize: 12, color: TColors.slate600)),
                  statusPill(tStr(bf['recordStatus'])),
                ]),
                for (final f in totals)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(children: [
                      Expanded(child: Text('${f.name} (kg)', style: const TextStyle(fontSize: 12, color: TColors.slate500))),
                      if (!canFeed(bf))
                        const Text('—')
                      else if (_basis == 'Manual')
                        SizedBox(
                          width: 120,
                          child: AppInput(
                            key: ValueKey('rfu-manual-${bf['flockId']}-${f.itemId}'),
                            controller: _manualCtl(tIntOrNull(bf['flockId']) ?? 0, f.itemId),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (_) => setState(() {}),
                          ),
                        )
                      else
                        Text(_trim(shares[f.itemId]?[tIntOrNull(bf['flockId'])] ?? 0), style: const TextStyle(fontWeight: FontWeight.w500)),
                    ]),
                  ),
              ]),
            ),
          ),
        Container(
          padding: const EdgeInsets.only(top: 8),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Tone.line(0xFFBAE6FD)))),
          child: Column(children: [
            for (final f in totals)
              (() {
                final s = sumKg([for (final bf in feedable) shares[f.itemId]?[tIntOrNull(bf['flockId'])] ?? 0]);
                final off = (s - f.qty).abs() > 0.0005;
                return Row(children: [
                  Expanded(child: Text('Total ${f.name}', style: const TextStyle(fontWeight: FontWeight.w600))),
                  Text('${_trim(s)} / ${_trim(f.qty)}',
                      key: ValueKey('rfu-total-${f.itemId}'), style: TextStyle(fontWeight: FontWeight.w600, color: off ? TColors.rose700 : TColors.slate900)),
                ]);
              })(),
          ]),
        ),
        if (feedable.any((b) => b['recordStatus'] == 'None')) ...[
          const SizedBox(height: 6),
          const Text('Flocks with no record yet get a feed-only record. Their production for this day still shows as missing until it is filled in.',
              style: TextStyle(fontSize: 12, color: Tone.fg(0xFF92400E))),
        ],
      ]),
    );
  }
}
