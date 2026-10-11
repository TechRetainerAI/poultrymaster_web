// Poultry → Operations → Production → Production Records
// (app/production-records/page.tsx): search and the Filters sheet (dates,
// batch, flock, month, year), CSV / PDF / Email, six stat tiles, striped cards
// with the pick breakdown, the full table with its totals row, paging, and
// Log / Edit / Delete through the production record modal.

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../shared/business_dates.dart';
import '../../shared/company_clock.dart';
import '../reports/dashboard_screen.dart' show latestRecordForFlock, birdsLeftFromRecord, sumLatestBirdsLeftByFlock;
import '../reports/report_export.dart';
import '../money/money_widgets.dart' show twoUp;
import '../sales/sales_logic.dart' show pageNumbers, salePageSizes;
import '../trackers/tracker_logic.dart'
    show tNum, tStr, tIntOrNull, loc, trackerDate, localDateKey, sortRows, toggleSort, SortState, formatEggGradeLabel, flockCountsTowardBirdTotals;
import '../trackers/tracker_widgets.dart';
import 'production_logic.dart';
import 'production_record_form.dart';

class ProductionFilters {
  String search = '', from = '', to = '', batch = 'ALL', flock = 'ALL', month = 'ALL', year = 'ALL';
  int get activeCount => [search.isNotEmpty, from.isNotEmpty, to.isNotEmpty, batch != 'ALL', flock != 'ALL', month != 'ALL', year != 'ALL']
      .where((b) => b)
      .length;
}

DateTime? _local(Object? v) => DateTime.tryParse(tStr(v))?.toLocal();

List<Map> filterProductionRecords(List<Map> records, ProductionFilters f, Map<int, int?> batchOfFlock, String Function(Map) dateText) {
  final q = f.search.toLowerCase();
  return [
    for (final r in records)
      if ((q.isEmpty ||
              tStr(r['flockName']).toLowerCase().contains(q) ||
              tStr(r['medication']).toLowerCase().contains(q) ||
              tStr(r['eggGrade']).toLowerCase().contains(q) ||
              formatEggGradeLabel(r['eggGrade']).toLowerCase().contains(q) ||
              dateText(r).toLowerCase().contains(q)) &&
          (f.from.isEmpty || localDateKey(r['date']).compareTo(f.from) >= 0) &&
          (f.to.isEmpty || localDateKey(r['date']).compareTo(f.to) <= 0) &&
          (f.batch == 'ALL' || (r['flockId'] != null && '${batchOfFlock[tIntOrNull(r['flockId'])]}' == f.batch)) &&
          (f.flock == 'ALL' || tStr(r['flockId']) == f.flock) &&
          (f.month == 'ALL' || (_local(r['date']) != null && monthKey(_local(r['date'])!) == f.month)) &&
          (f.year == 'ALL' || '${_local(r['date'])?.year}' == f.year))
        r,
  ];
}

/// sumLatestBirdsByFlock: the latest record's bird count, per flock.
num sumLatestBirdsByFlock(List<Map> records) {
  final ids = {for (final r in records) if (tIntOrNull(r['flockId']) != null) tIntOrNull(r['flockId'])!};
  return ids.fold<num>(0, (s, id) => s + tNum(latestRecordForFlock(records, id)?['noOfBirds']));
}

/// sumActiveFlocksBirdsLeft: counting flocks only; one with no record yet
/// counts its placed quantity.
num sumActiveFlocksBirdsLeft(List<Map> flocks, List<Map> records) => flocks.where(flockCountsTowardBirdTotals).fold<num>(0, (s, f) {
      final latest = latestRecordForFlock(records, tIntOrNull(f['flockId']) ?? -1);
      return s + (latest == null ? (tNum(f['quantity']) < 0 ? 0 : tNum(f['quantity'])) : birdsLeftFromRecord(latest));
    });

const _monthsShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

class ProductionRecordsScreen extends StatefulWidget {
  const ProductionRecordsScreen({super.key, required this.session, required this.company, this.date});
  final Session session;
  final Company company;

  /// `?date=`: every date filter starts on that day.
  final String? date;
  @override
  State<ProductionRecordsScreen> createState() => _ProductionRecordsScreenState();
}

class _ProductionRecordsScreenState extends State<ProductionRecordsScreen> {
  List<Map> _records = [], _flocks = [], _batches = [];
  bool _loading = true, _table = false, _emailing = false;
  String _error = '';
  final _search = TextEditingController();
  late final _f = ProductionFilters()
    ..from = widget.date ?? ''
    ..to = widget.date ?? '';
  SortState _sort = (key: null, dir: null);
  int _page = 1, _perPage = 10;
  PickSettings _picks = const PickSettings();
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;
  String get _userId => widget.session.tokens.userId ?? '';
  Map<String, String> get _ctx => {'userId': _userId, 'farmId': widget.company.farmId};
  bool get _canDelete => (widget.company.role ?? '').toLowerCase() != 'staff';

  @override
  void initState() {
    super.initState();
    PickSettings.load(widget.session, widget.company).then((p) {
      if (mounted) setState(() => _picks = p);
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
    Future<List<Map>?> get(String path) async {
      try {
        return rowsOf(await _api.get(path, query: _ctx));
      } on ApiException {
        return null;
      }
    }

    String? err;
    List<Map>? recs;
    try {
      recs = rowsOf(await _api.get('/api/ProductionRecord', query: _ctx));
    } on ApiException catch (e) {
      err = e.message.isNotEmpty ? e.message : 'Failed to load records';
    }
    final r = await Future.wait([get('/api/Flock'), get('/api/MainFlockBatch')]);
    if (!mounted) return;
    setState(() {
      if (recs != null) {
        _records = recs;
        _error = '';
      } else {
        _error = err ?? 'Failed to load records';
      }
      if (r[0] != null) _flocks = r[0]!;
      if (r[1] != null) _batches = r[1]!;
      _loading = false;
    });
  }

  Map<int, int?> get _batchOfFlock => {for (final f in _flocks) tIntOrNull(f['flockId']) ?? 0: tIntOrNull(f['batchId'])};

  String _batchLabel(Object? id) {
    final b = _batches.where((x) => tStr(x['batchId']) == tStr(id)).firstOrNull;
    if (b == null) return 'Batch #$id';
    return tStr(b['batchName']).isNotEmpty ? tStr(b['batchName']) : (tStr(b['batchCode']).isNotEmpty ? tStr(b['batchCode']) : 'Batch #$id');
  }

  String _flockLabel(Map r) {
    if (r['flockId'] == null) return '-';
    final f = _flocks.where((x) => tStr(x['flockId']) == tStr(r['flockId'])).firstOrNull;
    final name = tStr(f?['name']).isNotEmpty ? tStr(f?['name']) : tStr(r['flockName']);
    return name.isNotEmpty ? name : 'Flock #${r['flockId']}';
  }

  String _batchOf(Map r) {
    if (r['flockId'] == null) return '-';
    final bid = _batchOfFlock[tIntOrNull(r['flockId'])];
    return bid == null ? '-' : _batchLabel(bid);
  }

  String _dateText(Map r) => fmtDateTime(r['date'], r, _offset);

  List<Map> get _filtered => filterProductionRecords(_records, _f, _batchOfFlock, _dateText);

  List<String> get _months => ({for (final r in _records) if (_local(r['date']) != null) monthKey(_local(r['date'])!)}.toList()..sort()).reversed.toList();
  List<String> get _years => ({for (final r in _records) if (_local(r['date']) != null) '${_local(r['date'])!.year}'}.toList()..sort()).reversed.toList();

  num _sum(List<Map> rows, String k) => rows.fold<num>(0, (s, r) => s + tNum(r[k]));

  List<Map> _sorted(List<Map> rows) => sortRows(rows, _sort, (r, k) => switch (k) {
        'date' => tStr(r['date']),
        'flockId' => tNum(r['flockId']),
        'batchName' => _batchOf(r).toLowerCase(),
        'age' => tNum(r['ageInDays']),
        'eggGrade' => eggGradeFromApi(r['eggGrade']).toLowerCase(),
        'eggPercent' => eggPercent(r) ?? 0,
        'left' => tNum(r['noOfBirds']) - tNum(r['mortality']),
        'medication' => tStr(r['medication']),
        _ => tNum(r[k]),
      });

  // ------------------------------------------------------------ actions

  Future<void> _openForm([Map? record]) async {
    final ok = await showProductionRecordModal(context, session: widget.session, company: widget.company, record: record);
    if (ok == true) _load();
  }

  Future<void> _delete(Map r) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        var busy = false;
        return StatefulBuilder(builder: (ctx, set) => AlertDialog(
              title: const Text('Delete Production Record'),
              content: const Text('Are you sure you want to delete this production record? This action cannot be undone.'),
              actions: [
                TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: const Text('Cancel')),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: TColors.red600),
                  onPressed: busy
                      ? null
                      : () async {
                          set(() => busy = true);
                          try {
                            await _api.delete('/api/ProductionRecord/${r['id']}?userId=${Uri.encodeQueryComponent(_userId)}'
                                '&farmId=${Uri.encodeQueryComponent(widget.company.farmId)}');
                            if (mounted) trackerToast(context, 'Record deleted', description: 'The production record has been successfully deleted.');
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

  ({num eggs, int crates, int pieces, num feed, num deaths, num deathsAll, num placed, num left}) _totals(List<Map> rows) {
    final eligible = {for (final f in _flocks) if (flockCountsTowardBirdTotals(f)) tIntOrNull(f['flockId'])};
    final eggs = _sum(rows, 'totalProduction');
    return (
      eggs: eggs,
      crates: eggs ~/ eggsPerCrate,
      pieces: (eggs % eggsPerCrate).toInt(),
      feed: _sum(rows, 'feedKg'),
      deaths: rows.where((r) => eligible.contains(tIntOrNull(r['flockId']))).fold<num>(0, (s, r) => s + tNum(r['mortality'])),
      deathsAll: _sum(_records, 'mortality'),
      placed: _flocks.where(flockCountsTowardBirdTotals).fold<num>(0, (s, f) => s + tNum(f['quantity'])),
      left: sumActiveFlocksBirdsLeft(_flocks, _records),
    );
  }

  ReportDocument _doc(List<Map> rows) {
    final t = _totals(rows);
    final extra = _picks.extraColumns;
    String n(num v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';
    return ReportDocument(
      title: 'Egg Production Report',
      filename: 'production-${DateTime.now().toUtc().toIso8601String().substring(0, 10)}',
      farmName: widget.company.name.isNotEmpty ? widget.company.name : 'Farm',
      landscape: true,
      subtitle: 'Records: ${rows.length}  |  Total Eggs: ${loc(t.eggs)} (${t.crates} crates + ${t.pieces} pcs)  |  Feed: ${t.feed.toStringAsFixed(2)} kg  |  '
          'Deaths (active flocks): ${n(t.deaths)}  |  Deaths (all logs): ${n(t.deathsAll)}  |  Placed birds: ${n(t.placed)}  |  Birds left: ${n(t.left)}',
      sections: [
        ReportSection(
          columns: [
            const ReportColumn('Date'), const ReportColumn('Flock'), const ReportColumn('Batch'), const ReportColumn('Age'),
            const ReportColumn('1st Pick'), const ReportColumn('2nd Pick'), const ReportColumn('3rd Pick'),
            for (final (h, _) in extra) ReportColumn(h),
            const ReportColumn('Total'), const ReportColumn('Size'), const ReportColumn('Egg%'), const ReportColumn('Feed(kg)'),
            const ReportColumn('Birds'), const ReportColumn('Deaths'), const ReportColumn('Left'), const ReportColumn('Medication'),
          ],
          rows: [
            for (final r in rows)
              [
                _dateText(r),
                r['flockId'] != null ? '#${r['flockId']}' : '-',
                _batchOf(r),
                formatProductionAge(r),
                n(tNum(r['production9AM'])),
                n(tNum(r['production12PM'])),
                n(tNum(r['production4PM'])),
                for (final (_, k) in extra) n(tNum(r[k])),
                n(tNum(r['totalProduction'])),
                formatEggGradeLabel(r['eggGrade']),
                eggPercent(r) == null ? '-' : '${eggPercent(r)!.toStringAsFixed(1)}%',
                tNum(r['feedKg']).toStringAsFixed(2),
                n(tNum(r['noOfBirds'])),
                n(tNum(r['mortality'])),
                n(tNum(r['noOfBirds']) - tNum(r['mortality'])),
                tStr(r['medication']).isEmpty ? '-' : tStr(r['medication']),
              ],
          ],
          totals: [
            'TOTALS', '', '', '',
            n(_sum(rows, 'production9AM')), n(_sum(rows, 'production12PM')), n(_sum(rows, 'production4PM')),
            for (final (_, k) in extra) n(_sum(rows, k)),
            '${n(t.eggs)} (${t.crates}c+${t.pieces}p)', '', '', t.feed.toStringAsFixed(2),
            n(sumLatestBirdsByFlock(rows)), n(t.deaths), n(sumLatestBirdsLeftByFlock(rows)), '',
          ],
        ),
      ],
    );
  }

  Future<void> _exportCsv(List<Map> rows) {
    final extra = _picks.extraColumns;
    final headers = [
      'Date', 'FlockId', 'Batch', 'Age', '1st Pick', '2nd Pick', '3rd Pick', for (final (h, _) in extra) h,
      'Total', 'Size', 'EggPercent', 'FeedKg', 'Birds', 'Deaths', 'Left', 'Medication',
    ];
    String cell(Object? v) {
      final s = v is num ? (v == v.roundToDouble() ? '${v.toInt()}' : '$v') : tStr(v);
      return v is String && s.contains(',') ? '"$s"' : s;
    }

    final lines = [
      headers.map(cell).join(','),
      for (final r in rows)
        [
          _dateText(r),
          tStr(r['flockId']),
          _batchOf(r),
          formatProductionAge(r),
          tNum(r['production9AM']),
          tNum(r['production12PM']),
          tNum(r['production4PM']),
          for (final (_, k) in extra) tNum(r[k]),
          tNum(r['totalProduction']),
          tStr(r['eggGrade']),
          eggPercent(r) == null ? '' : eggPercent(r)!.toStringAsFixed(1),
          tNum(r['feedKg']),
          tNum(r['noOfBirds']),
          tNum(r['mortality']),
          tNum(r['noOfBirds']) - tNum(r['mortality']),
          tStr(r['medication']),
        ].map(cell).join(','),
    ];
    return ReportExport.sharer('production-${DateTime.now().toUtc().toIso8601String().substring(0, 10)}.csv', utf8.encode(lines.join('\n')),
        'text/csv', 'Production Records');
  }

  Future<void> _exportPdf(List<Map> rows) async {
    if (rows.isEmpty) {
      trackerToast(context, 'Nothing to export', description: 'Adjust your filters and try again.', error: true);
      return;
    }
    await ReportExport.sharePdf(_doc(rows));
  }

  Future<void> _email(List<Map> rows) async {
    if (rows.isEmpty) {
      trackerToast(context, 'Nothing to email', description: 'Adjust your filters and try again.', error: true);
      return;
    }
    final to = (widget.session.tokens.username ?? '').trim();
    if (to.isEmpty || !to.contains('@')) {
      trackerToast(context, 'No recipient email', description: 'Sign in with an email address to receive the report.', error: true);
      return;
    }
    setState(() => _emailing = true);
    try {
      await ReportExport.email(_api, _doc(rows), [to]);
      if (mounted) trackerToast(context, 'Report emailed', description: 'Sent to $to.');
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Email failed', description: e.message.isNotEmpty ? e.message : 'Unknown error.', error: true);
    }
    if (mounted) setState(() => _emailing = false);
  }

  // ------------------------------------------------------------ filters sheet

  Future<void> _openFilters() async {
    var from = _f.from, to = _f.to, batch = _f.batch, flock = _f.flock, month = _f.month, year = _f.year;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final changed = from != _f.from || to != _f.to || batch != _f.batch || flock != _f.flock || month != _f.month || year != _f.year;
        final flocks = [for (final fl in _flocks) if (batch == 'ALL' || tStr(fl['batchId']) == batch) fl];
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
                'Batch',
                AppSelect<String>(
                  value: batch,
                  hintText: 'All Batches',
                  items: [
                    const AppSelectItem(value: 'ALL', label: 'All Batches'),
                    for (final b in _batches) if (b['batchId'] != null) AppSelectItem(value: tStr(b['batchId']), label: _batchLabel(b['batchId'])),
                  ],
                  onChanged: (v) => set(() {
                    batch = v ?? 'ALL';
                    if (batch != 'ALL' && flock != 'ALL' && !_flocks.any((fl) => tStr(fl['flockId']) == flock && tStr(fl['batchId']) == batch)) {
                      flock = 'ALL';
                    }
                  }),
                ),
              ),
              const SizedBox(height: 12),
              FilterLabel(
                'Flock',
                AppSelect<String>(
                  value: flock,
                  hintText: 'All Flocks',
                  items: [
                    const AppSelectItem(value: 'ALL', label: 'All Flocks'),
                    for (final fl in flocks) AppSelectItem(value: tStr(fl['flockId']), label: '${tStr(fl['name'])} (${tStr(fl['quantity'])} birds)'),
                  ],
                  onChanged: (v) => set(() => flock = v ?? 'ALL'),
                ),
              ),
              const SizedBox(height: 12),
              FilterLabel(
                'Month',
                AppSelect<String>(
                  value: month,
                  hintText: 'All months',
                  items: [
                    const AppSelectItem(value: 'ALL', label: 'All months'),
                    for (final m in _months) AppSelectItem(value: m, label: '${_monthsShort[int.parse(m.substring(5)) - 1]} ${m.substring(0, 4)}'),
                  ],
                  onChanged: (v) => set(() => month = v ?? 'ALL'),
                ),
              ),
              const SizedBox(height: 12),
              FilterLabel(
                'Year',
                AppSelect<String>(
                  value: year,
                  hintText: 'All years',
                  items: [const AppSelectItem(value: 'ALL', label: 'All years'), for (final y in _years) AppSelectItem(value: y, label: y)],
                  onChanged: (v) => set(() => year = v ?? 'ALL'),
                ),
              ),
              const SizedBox(height: 10),
              const Text('Choose options, then tap Apply. Month/year filter records that fall in that calendar month/year.',
                  style: TextStyle(fontSize: 12, color: TColors.slate500)),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: () {
                      setState(() {
                        _f
                          ..from = ''
                          ..to = ''
                          ..batch = 'ALL'
                          ..flock = 'ALL'
                          ..month = 'ALL'
                          ..year = 'ALL';
                        _page = 1;
                      });
                      Navigator.pop(ctx);
                      trackerToast(context, 'Filters cleared');
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
                              _f
                                ..from = from
                                ..to = to
                                ..batch = batch
                                ..flock = flock
                                ..month = month
                                ..year = year;
                              _page = 1;
                            });
                            Navigator.pop(ctx);
                            trackerToast(context, 'Filters applied', description: 'Production list updated.');
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

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/production-records');
    final rows = _filtered;
    final sorted = _sorted(rows);
    final totalPages = sorted.isEmpty ? 1 : (sorted.length + _perPage - 1) ~/ _perPage;
    final page = _page.clamp(1, totalPages);
    final start = (page - 1) * _perPage;
    final pageRows = sorted.sublist(start.clamp(0, sorted.length), (start + _perPage).clamp(0, sorted.length));
    final t = _totals(rows);
    final active = _f.activeCount;

    Widget tile(String label, String value, {Color? color, String? suffix, Widget? note, Widget? right}) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(label.toUpperCase(),
                    overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: .6, color: TColors.slate500)),
              ),
              if (note != null)
                Tooltip(
                  richMessage: WidgetSpan(child: SizedBox(width: 240, child: note)),
                  triggerMode: TooltipTriggerMode.tap,
                  showDuration: const Duration(seconds: 8),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(Icons.info_outline, size: 14, color: TColors.slate400, semanticLabel: 'What "$label" means'),
                  ),
                ),
            ]),
            const SizedBox(height: 2),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 6, children: [
                  Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color ?? TColors.slate900)),
                  if (suffix != null) Text(suffix, style: const TextStyle(fontSize: 12, color: TColors.slate400)),
                ]),
              ),
              ?right,
            ]),
          ]),
        );
    const noteStyle = TextStyle(fontSize: 12, color: Colors.white);

    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Production Records')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 28),
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: TColors.emerald100, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.description_outlined, size: 20, color: TColors.emerald600),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Production Records', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: TColors.slate900)),
                  Text('Track daily egg production and performance metrics', style: TextStyle(fontSize: 13, color: TColors.slate600)),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: TColors.emerald600, minimumSize: const Size.fromHeight(44)),
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Log Production'),
            ),
            const SizedBox(height: 14),
            if (_error.isNotEmpty) ...[TrackerBanner.error(_error), const SizedBox(height: 12)],
            AppInput(
              controller: _search,
              hintText: 'Search records...',
              prefixIcon: const Icon(Icons.search, size: 18, color: TColors.slate400),
              onChanged: (v) => setState(() {
                _f.search = v;
                _page = 1;
              }),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
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
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)), onPressed: () => _exportCsv(rows), child: const Text('CSV')),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)), onPressed: () => _exportPdf(rows), child: const Text('PDF')),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                  onPressed: _emailing ? null : () => _email(rows),
                  icon: const Icon(Icons.mail_outline, size: 16),
                  label: const Text('Email'),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            if (!_loading) ...[
              twoUp([
                tile('Total Eggs', loc(t.eggs), color: TColors.emerald600, suffix: '${t.crates}c + ${t.pieces}p'),
                tile('Avg / Record', loc(rows.isEmpty ? 0 : (t.eggs / rows.length).round())),
                tile('Feed (kg)', t.feed.toStringAsFixed(2)),
                tile(
                  'Recorded Mortality',
                  loc(t.deaths),
                  color: TColors.red600,
                  note: Text.rich(
                    TextSpan(children: [
                      const TextSpan(text: 'Mortality recorded here during the selected period, in '),
                      const TextSpan(text: 'active flocks', style: TextStyle(fontWeight: FontWeight.w700)),
                      const TextSpan(text: '. '),
                      const TextSpan(text: 'All logs', style: TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(
                          text: ' counts every day ever logged, including flocks that have since closed. Losses from before this farm started being '
                              'tracked are held separately as the opening position and are not counted here. Placed − left is '
                              '${loc((t.placed - t.left) < 0 ? 0 : t.placed - t.left)}.'),
                    ]),
                    style: noteStyle,
                  ),
                  right: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    const Text('ALL LOGS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: TColors.slate500)),
                    Text(loc(t.deathsAll), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: TColors.slate800)),
                  ]),
                ),
                tile('Overall Total Birds', loc(t.placed), note: const Text('Birds placed when each flock was created.', style: noteStyle)),
                tile('Total Birds Left', loc(t.left),
                    color: TColors.emerald700,
                    note: const Text('Latest count still alive per flock, taken from your last entry for each.', style: noteStyle)),
              ]),
              const SizedBox(height: 14),
            ],
            if (_loading)
              const TCard(child: LinearProgressIndicator())
            else
              TCard(
                padding: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: !_table
                      ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          if (pageRows.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 40),
                              child: Column(children: [
                                const Text('No records found', style: TextStyle(color: TColors.slate500)),
                                const SizedBox(height: 12),
                                FilledButton(onPressed: () => _openForm(), child: const Text('Log one now')),
                              ]),
                            )
                          else ...[
                            for (var i = 0; i < pageRows.length; i++) ...[_card(pageRows[i], i), const SizedBox(height: 10)],
                            ViewTableButton(onPressed: () => setState(() => _table = true)),
                          ],
                        ])
                      : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          TableViewBar(text: 'Table view • Scroll → for more', onCards: () => setState(() => _table = false)),
                          _tableView(pageRows, rows),
                        ]),
                ),
              ),
            if (!_loading && rows.isNotEmpty) _pagination(sorted.length, page, totalPages, start),
          ],
        ),
      ),
    );
  }

  Widget _card(Map r, int i) {
    Widget tile(String label, String value, Color bg, Color border, Color fg, {bool wide = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .4, color: fg)),
            Text(value,
                maxLines: wide ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: wide ? 14 : 20, fontWeight: wide ? FontWeight.w500 : FontWeight.w800, color: fg)),
          ]),
        );
    Widget kv(String l, String v, {Color? color}) => Text.rich(TextSpan(children: [
          TextSpan(text: '$l ', style: const TextStyle(color: TColors.slate500)),
          TextSpan(text: v, style: TextStyle(fontWeight: FontWeight.w500, color: color)),
        ]), style: const TextStyle(fontSize: 14));
    final med = tStr(r['medication']);
    final mortality = tNum(r['mortality']);
    final picks = [
      ('1st Pick', 'production9AM', TColors.blue600),
      ('2nd Pick', 'production12PM', const Color(0xFFC2410C)),
      ('3rd Pick', 'production4PM', const Color(0xFF7E22CE)),
      for (final (h, k) in _picks.extraColumns) (h, k, const Color(0xFF0F766E)),
    ];
    return ProdCard(
      key: ValueKey('rec-${r['id']}'),
      striped: i.isEven,
      header: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.only(right: 24), child: Text.rich(TextSpan(children: [
          TextSpan(text: trackerDate(r['date']), style: const TextStyle(fontWeight: FontWeight.w600, color: TColors.slate900)),
          const TextSpan(text: '  •  ', style: TextStyle(color: TColors.slate500)),
          TextSpan(text: _flockLabel(r), style: const TextStyle(color: TColors.slate600)),
        ]), maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (_batchOf(r) != '-')
          Text('Batch: ${_batchOf(r)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: tile('Eggs', loc(tNum(r['totalProduction'])), TColors.emerald100, TColors.emerald300, TColors.emerald800)),
          const SizedBox(width: 8),
          Expanded(
              child: tile('Birds Left', loc(tNum(r['noOfBirds']) - mortality), TColors.blue100, TColors.blue300, const Color(0xFF1E40AF))),
        ]),
        if (med.isNotEmpty && med != '-') ...[
          const SizedBox(height: 8),
          tile('Medication', med, TColors.violet100, const Color(0xFFC4B5FD), const Color(0xFF4C1D95), wide: true),
        ],
      ]),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LayoutBuilder(builder: (context, c) {
          final w = (c.maxWidth - 8) / 2;
          return Wrap(spacing: 8, runSpacing: 6, children: [
            for (final (l, k, color) in picks) SizedBox(width: w, child: kv(l, loc(tNum(r[k])), color: color)),
            SizedBox(width: w, child: kv('Feed', '${tNum(r['feedKg']).toStringAsFixed(2)} kg')),
            SizedBox(width: w, child: kv('Deaths', loc(mortality), color: mortality > 0 ? TColors.red600 : null)),
            SizedBox(width: c.maxWidth, child: kv('Age', formatProductionAge(r))),
          ]);
        }),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(backgroundColor: Colors.white, minimumSize: const Size.fromHeight(40)),
              onPressed: () => _openForm(r),
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
                onPressed: () => _delete(r),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Delete'),
              ),
            ),
          ],
        ]),
      ]),
    );
  }

  Widget _tableView(List<Map> pageRows, List<Map> filtered) {
    final extra = _picks.extraColumns;
    Widget withCrates(num v, Color color) => Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
          Text(loc(v), style: TextStyle(fontWeight: FontWeight.w600, color: color)),
          Text('${v ~/ eggsPerCrate}c + ${(v % eggsPerCrate).toInt()}p', style: TextStyle(fontSize: 11, color: color)),
        ]);
    final t = _totals(filtered);
    final columns = [
      const TCol('Date', sortKey: 'date', width: 100),
      const TCol('Flock', sortKey: 'flockId', width: 120),
      const TCol('Batch', sortKey: 'batchName', width: 120),
      const TCol('Age', sortKey: 'age', width: 190),
      const TCol('1st Pick', sortKey: 'production9AM', right: true, width: 90),
      const TCol('2nd Pick', sortKey: 'production12PM', right: true, width: 90),
      const TCol('3rd Pick', sortKey: 'production4PM', right: true, width: 90),
      for (final (h, k) in extra) TCol(h, sortKey: k, right: true, width: 90),
      const TCol('Brokens', sortKey: 'brokenEggs', right: true, width: 90),
      const TCol('Total', sortKey: 'totalProduction', right: true, width: 100),
      const TCol('Egg%', sortKey: 'eggPercent', right: true, width: 80),
      const TCol('Feed', sortKey: 'feedKg', right: true, width: 80),
      const TCol('Birds', sortKey: 'noOfBirds', right: true, width: 80),
      const TCol('Deaths', sortKey: 'mortality', right: true, width: 80),
      const TCol('Left', sortKey: 'left', right: true, width: 80),
      const TCol('Meds', sortKey: 'medication', width: 110),
      const TCol('Actions', width: 180),
    ];
    return TrackerTable(
      sort: _sort,
      onSort: (k) => setState(() => _sort = toggleSort(k, _sort)),
      columns: columns,
      emptyText: 'No records found for the selected filters.',
      rows: [
        for (final r in pageRows)
          [
            cellText(trackerDate(r['date'])),
            cellText(_flockLabel(r), bold: true),
            cellText(_batchOf(r), color: TColors.slate600),
            cellText(formatProductionAge(r)),
            cellText(loc(tNum(r['production9AM'])), color: TColors.blue600),
            cellText(loc(tNum(r['production12PM'])), color: const Color(0xFFC2410C)),
            cellText(loc(tNum(r['production4PM'])), color: const Color(0xFF7E22CE)),
            for (final (_, k) in extra) cellText(loc(tNum(r[k])), color: const Color(0xFF0F766E)),
            cellText(loc(tNum(r['brokenEggs'])), color: TColors.red700),
            cellText(loc(tNum(r['totalProduction'])), bold: true),
            cellText(eggPercent(r) == null ? '-' : '${eggPercent(r)!.toStringAsFixed(1)}%'),
            cellText(tNum(r['feedKg']).toStringAsFixed(2)),
            cellText(loc(tNum(r['noOfBirds']))),
            Align(
              alignment: Alignment.centerRight,
              child: TBadge(loc(tNum(r['mortality'])),
                  bg: tNum(r['mortality']) > 0 ? TColors.red50 : TColors.slate50, fg: tNum(r['mortality']) > 0 ? TColors.red700 : TColors.slate600),
            ),
            cellText(loc(tNum(r['noOfBirds']) - tNum(r['mortality']))),
            cellText(tStr(r['medication']).isEmpty ? '-' : tStr(r['medication'])),
            Wrap(children: [
              TextButton(onPressed: () => _openForm(r), child: const Text('Edit')),
              if (_canDelete)
                TextButton(style: TextButton.styleFrom(foregroundColor: TColors.red600), onPressed: () => _delete(r), child: const Text('Delete')),
            ]),
          ],
        if (filtered.isNotEmpty)
          [
            cellText('Totals', bold: true),
            const SizedBox.shrink(),
            const SizedBox.shrink(),
            const SizedBox.shrink(),
            withCrates(_sum(filtered, 'production9AM'), const Color(0xFF1E40AF)),
            withCrates(_sum(filtered, 'production12PM'), const Color(0xFF9A3412)),
            withCrates(_sum(filtered, 'production4PM'), const Color(0xFF6B21A8)),
            for (final (_, k) in extra) withCrates(_sum(filtered, k), const Color(0xFF115E59)),
            withCrates(_sum(filtered, 'brokenEggs'), TColors.red700),
            withCrates(t.eggs, TColors.emerald700),
            const SizedBox.shrink(),
            cellText(t.feed.toStringAsFixed(2), bold: true),
            cellText(loc(sumLatestBirdsByFlock(filtered)), bold: true),
            cellText(loc(t.deaths), bold: true, color: TColors.red700),
            cellText(loc(sumLatestBirdsLeftByFlock(filtered)), bold: true, color: TColors.emerald700),
            const SizedBox.shrink(),
            const SizedBox.shrink(),
          ],
      ],
    );
  }

  Widget _pagination(int total, int page, int totalPages, int start) {
    final end = (start + _perPage).clamp(0, total);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
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
          for (final p in pageNumbers(page, totalPages))
            p == 'ellipsis'
                ? const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('…'))
                : SizedBox(
                    width: 36,
                    height: 36,
                    child: p == page
                        ? OutlinedButton(style: OutlinedButton.styleFrom(padding: EdgeInsets.zero), onPressed: () {}, child: Text('$p'))
                        : TextButton(
                            style: TextButton.styleFrom(padding: EdgeInsets.zero),
                            onPressed: () => setState(() => _page = p as int),
                            child: Text('$p'),
                          ),
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

class ProdCard extends StatefulWidget {
  const ProdCard({super.key, required this.striped, required this.header, required this.body});
  final bool striped;
  final Widget header, body;
  @override
  State<ProdCard> createState() => ProdCardState();
}

class ProdCardState extends State<ProdCard> {
  bool _open = true;
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: widget.striped ? TColors.amber100 : Colors.white,
          border: Border.all(color: widget.striped ? TColors.amber300 : TColors.slate200),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Stack(children: [
              Padding(padding: const EdgeInsets.only(right: 0), child: widget.header),
              Positioned(
                right: 0,
                top: 0,
                child: Icon(_open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 18, color: TColors.slate400),
              ),
            ]),
          ),
          if (_open) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: TColors.slate100),
            const SizedBox(height: 12),
            widget.body,
          ],
        ]),
      );
}

/// `/production-records?date=…`, `/production-records/new…` and `/production-records/{id}`.
Widget? productionScreenForHref(String href, Session s, Company c) {
  final uri = Uri.tryParse(href);
  if (uri == null) return null;
  if (uri.path == '/production-records' && uri.query.isNotEmpty) {
    return ProductionRecordsScreen(session: s, company: c, date: toBusinessDate(uri.queryParameters['date']));
  }
  return productionRecordScreenForHref(href, s, c);
}
