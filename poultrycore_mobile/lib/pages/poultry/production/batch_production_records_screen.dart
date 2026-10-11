// Poultry → Operations → Production → Batch Production
// (app/batch-production-records/page.tsx and [id]/page.tsx): the list with
// search, the Filters sheet (dates, status, batch, month, year), CSV / PDF /
// Email, five stat tiles, striped cards, the table, paging and the
// status-gated actions; and the read-only batch view.

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../shared/business_dates.dart';
import '../../shared/company_clock.dart';
import '../money/money_widgets.dart' show twoUp;
import '../reports/report_export.dart';
import '../sales/sales_logic.dart' show pageNumbers, salePageSizes;
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull, loc, trackerDate, localDateKey, sortRows, toggleSort, SortState;
import '../trackers/tracker_widgets.dart';
import 'batch_production_allocate_screen.dart';
import 'batch_production_form.dart';
import 'batch_production_logic.dart';
import 'production_logic.dart';
import 'production_records_screen.dart' show ProdCard;

const _monthsShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

const _statusColors = <String, (Color, Color, Color)>{
  'PendingAllocation': (TColors.amber100, Color(0xFF92400E), TColors.amber200),
  'Allocated': (TColors.blue100, Color(0xFF1E40AF), Color(0xFFBFDBFE)),
  'Posted': (TColors.emerald100, TColors.emerald800, Color(0xFFA7F3D0)),
  'Reversed': (TColors.slate100, TColors.slate700, TColors.slate200),
  'Draft': (Color(0xFFF3F4F6), Color(0xFF374151), Color(0xFFE5E7EB)),
  'Cancelled': (Color(0xFFFEE2E2), TColors.red700, Color(0xFFFECACA)),
};

Widget batchStatusBadge(Object? status) {
  final c = _statusColors[tStr(status)] ?? (TColors.slate100, TColors.slate700, TColors.slate200);
  return TBadge(batchStatusLabel(status), bg: c.$1, fg: c.$2, border: c.$3);
}

DateTime? _local(Object? v) => DateTime.tryParse(tStr(v))?.toLocal();

/// formatAge: only a specific batch has one age.
String batchFormatAge(Map r) {
  if (tStr(r['batchSelectionType']) != 'SpecificBatch') return 'N/A';
  if (tStr(r['ageDisplay']).trim().isNotEmpty) return tStr(r['ageDisplay']).trim();
  final days = tIntOrNull(r['ageInDays']);
  final weeks = tIntOrNull(r['ageInWeeks']) ?? (days != null ? days ~/ 7 : null);
  if (weeks == null) return 'N/A';
  return '${weeks}w ${days != null ? days % 7 : 0}d';
}

String batchEggPercent(Map r) {
  final b = tNum(r['birdsLeft']), t = tNum(r['totalEggs']);
  return b != 0 ? '${(t / b * 100).toStringAsFixed(1)}%' : '—';
}

String batchMedsLabel(Map r) {
  final n = listOf(r, 'medications').length;
  return n > 0 ? '$n item${n > 1 ? 's' : ''}' : '—';
}

class BatchFilters {
  String search = '', from = '', to = '', status = 'ALL', batch = 'ALL', month = 'ALL', year = 'ALL';
  int get activeCount =>
      [search.isNotEmpty, from.isNotEmpty, to.isNotEmpty, status != 'ALL', batch != 'ALL', month != 'ALL', year != 'ALL'].where((b) => b).length;
}

List<Map> filterBatchRecords(List<Map> records, BatchFilters f, String Function(Map) dateText) {
  final q = f.search.toLowerCase();
  return [
    for (final r in records)
      if ((q.isEmpty ||
              batchNameLabel(r).toLowerCase().contains(q) ||
              batchScopeLabel(r).toLowerCase().contains(q) ||
              (batchStatusLabels[tStr(r['status'])] ?? '').toLowerCase().contains(q) ||
              dateText(r).toLowerCase().contains(q)) &&
          (f.from.isEmpty || localDateKey(r['productionDate']).compareTo(f.from) >= 0) &&
          (f.to.isEmpty || localDateKey(r['productionDate']).compareTo(f.to) <= 0) &&
          (f.status == 'ALL' || tStr(r['status']) == f.status) &&
          (f.batch == 'ALL' || batchFilterKey(r) == f.batch) &&
          (f.month == 'ALL' || (_local(r['productionDate']) != null && monthKey(_local(r['productionDate'])!) == f.month)) &&
          (f.year == 'ALL' || '${_local(r['productionDate'])?.year}' == f.year))
        r,
  ];
}

class BatchProductionRecordsScreen extends StatefulWidget {
  const BatchProductionRecordsScreen({super.key, required this.session, required this.company, this.date});
  final Session session;
  final Company company;

  /// `?date=`: both date filters start on that day.
  final String? date;
  @override
  State<BatchProductionRecordsScreen> createState() => _BatchProductionRecordsScreenState();
}

class _BatchProductionRecordsScreenState extends State<BatchProductionRecordsScreen> {
  List<Map> _records = [];
  bool _loading = true, _table = false, _emailing = false;
  String _error = '';
  final _search = TextEditingController();
  late final _f = BatchFilters()
    ..from = widget.date ?? ''
    ..to = widget.date ?? '';
  SortState _sort = (key: null, dir: null);
  int _page = 1, _perPage = 10;
  PickSettings _picks = const PickSettings();
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;
  String get _userId => widget.session.tokens.userId ?? '';
  String get _farmId => widget.company.farmId;
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
    if (_userId.isEmpty || _farmId.isEmpty) {
      setState(() {
        _error = 'User context not found. Please log in again.';
        _loading = false;
      });
      return;
    }
    try {
      final rows = rowsOf(await _api.get('/api/ProductionBatchRecord', query: {'userId': _userId, 'farmId': _farmId}));
      if (!mounted) return;
      setState(() {
        _records = rows;
        _error = '';
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message.isNotEmpty ? e.message : 'Failed to load records';
        _loading = false;
      });
    }
  }

  String _dateText(Map r) => fmtDateTime(r['productionDate'], r, _offset);
  List<Map> get _filtered => filterBatchRecords(_records, _f, _dateText);

  List<String> get _months =>
      ({for (final r in _records) if (_local(r['productionDate']) != null) monthKey(_local(r['productionDate'])!)}.toList()..sort()).reversed.toList();
  List<String> get _years =>
      ({for (final r in _records) if (_local(r['productionDate']) != null) '${_local(r['productionDate'])!.year}'}.toList()..sort()).reversed.toList();

  /// Batches present in the loaded records, by their stable filter key.
  List<(String, String)> get _distinctBatches {
    final m = <String, String>{};
    for (final r in _records) {
      m.putIfAbsent(batchFilterKey(r), () => batchNameLabel(r));
    }
    return [for (final e in m.entries) (e.key, e.value)]..sort((a, b) => a.$2.compareTo(b.$2));
  }

  num _sum(List<Map> rows, String k) => rows.fold<num>(0, (s, r) => s + tNum(r[k]));

  List<Map> _sorted(List<Map> rows) => sortRows(rows, _sort, (r, k) => switch (k) {
        'date' => tStr(r['productionDate']),
        'batchName' => batchNameLabel(r).toLowerCase(),
        'age' => tNum(r['ageInDays']),
        'eggPercent' => tNum(r['birdsLeft']) != 0 ? tNum(r['totalEggs']) / tNum(r['birdsLeft']) * 100 : 0,
        'meds' => listOf(r, 'medications').length,
        'status' => batchStatusLabel(r['status']),
        _ => tNum(r[k]),
      });

  // ------------------------------------------------------------ actions

  Future<void> _openForm([int? id]) async {
    final ok = await showBatchProductionRecordModal(context, session: widget.session, company: widget.company, recordId: id);
    if (ok == true) _load();
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) _load();
  }

  void _allocate(Map r) => _push(BatchAllocateScreen(session: widget.session, company: widget.company, batchId: tIntOrNull(r['id']) ?? 0));
  void _view(Map r) => _push(BatchProductionDetailScreen(session: widget.session, company: widget.company, batchId: tIntOrNull(r['id']) ?? 0));

  Future<void> _confirm(Map r, String type) async {
    final posted = tStr(r['status']) == 'Posted';
    final (title, description, action) = switch (type) {
      'delete' => (
          'Delete Batch Record',
          'Are you sure you want to delete this batch production record? This action cannot be undone.',
          'Delete'
        ),
      'post' => ('Post Allocation', 'Posting creates flock-level production records and applies bird/inventory side-effects. Continue?', 'Post'),
      'repost' => (
          'Repost Allocation',
          'Reposting creates fresh flock-level production records and re-applies bird/inventory side-effects. Continue?',
          'Repost'
        ),
      'reverse' => ('Reverse Batch', 'Reversing deletes the generated flock records and their side-effects. Continue?', 'Reverse'),
      'deleteAllocation' => (
          posted ? 'Delete Posted Allocation?' : 'Delete Allocation?',
          posted
              ? 'This allocation has created flock-level production records and updated inventory. Deleting it will reverse egg production, feed usage, bird mortality and all other inventory effects, remove the generated flock records, and record reversal stock movements. The batch record itself stays available for re-allocation. This cannot be undone automatically.'
              : 'This removes the allocation rows. No inventory has been affected yet, so nothing is reversed. The batch record stays available and returns to Pending Allocation.',
          posted ? 'Delete and Reverse' : 'Delete Allocation'
        ),
      _ => ('Cancel Batch', 'This marks the batch as cancelled. Continue?', 'Cancel batch'),
    };
    final id = r['id'];
    final farm = Uri.encodeQueryComponent(_farmId), user = Uri.encodeQueryComponent(_userId);
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        var busy = false;
        return StatefulBuilder(builder: (ctx, set) => AlertDialog(
              title: Text(title),
              content: Text(description),
              actions: [
                TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: const Text('Cancel')),
                FilledButton(
                  style: type == 'delete' ? FilledButton.styleFrom(backgroundColor: TColors.red600) : null,
                  onPressed: busy
                      ? null
                      : () async {
                          if (_userId.isEmpty || _farmId.isEmpty) {
                            trackerToast(context, 'Session issue', description: 'We could not confirm your farm or user. Please sign in again.', error: true);
                            return;
                          }
                          set(() => busy = true);
                          String message;
                          try {
                            switch (type) {
                              case 'delete':
                                await _api.delete('/api/ProductionBatchRecord/$id?userId=$user&farmId=$farm');
                                message = 'Batch production record deleted';
                              case 'post' || 'repost':
                                await _api.post('/api/ProductionBatchRecord/$id/post', query: {'farmId': _farmId}, body: {'userId': _userId});
                                message = 'Batch allocation posted';
                              case 'reverse':
                                await _api.post('/api/ProductionBatchRecord/$id/reverse', query: {'farmId': _farmId}, body: {'userId': _userId});
                                message = 'Batch reversed';
                              case 'deleteAllocation':
                                await _api.delete('/api/ProductionBatchRecord/$id/allocation?farmId=$farm&userId=$user');
                                message = 'Allocation deleted';
                              default:
                                await _api.post('/api/ProductionBatchRecord/$id/status',
                                    query: {'farmId': _farmId}, body: {'status': 'Cancelled', 'userId': _userId});
                                message = 'Status set to Cancelled';
                            }
                            if (mounted) trackerToast(context, 'Done', description: message);
                            await _load();
                          } on ApiException catch (e) {
                            if (mounted) {
                              trackerToast(context, 'Action failed',
                                  description: e.message.isNotEmpty ? e.message : 'Something went wrong. Please try again.', error: true);
                            }
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                  child: busy
                      ? const Row(mainAxisSize: MainAxisSize.min, children: [
                          SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                          SizedBox(width: 8),
                          Text('Working...'),
                        ])
                      : Text(action),
                ),
              ],
            ));
      },
    );
  }

  /// renderActions: the row's buttons, by status.
  List<Widget> _actions(Map r) {
    Widget b(String label, VoidCallback onTap, [Color? color]) => TextButton(
          style: TextButton.styleFrom(foregroundColor: color, visualDensity: VisualDensity.compact),
          onPressed: onTap,
          child: Text(label),
        );
    const blue = TColors.blue600, red = TColors.red600, slate = TColors.slate500;
    final id = tIntOrNull(r['id']);
    return switch (tStr(r['status'])) {
      'Draft' => [
          b('Edit', () => _openForm(id)),
          if (_canDelete) b('Delete', () => _confirm(r, 'delete'), red),
          b('Cancel', () => _confirm(r, 'cancel'), slate),
        ],
      'PendingAllocation' => [
          b('Edit', () => _openForm(id)),
          b('Allocation', () => _allocate(r), blue),
          if (_canDelete) b('Delete', () => _confirm(r, 'delete'), red),
          b('Cancel', () => _confirm(r, 'cancel'), slate),
        ],
      'Allocated' => [
          b('Allocation', () => _allocate(r), blue),
          b('Post', () => _confirm(r, 'post'), TColors.emerald600),
          b('Delete Allocation', () => _confirm(r, 'deleteAllocation'), red),
          b('Cancel', () => _confirm(r, 'cancel'), slate),
        ],
      'Posted' => [
          b('View', () => _view(r)),
          b('Reverse', () => _confirm(r, 'reverse'), TColors.amber600),
          if (_canDelete) b('Delete Allocation', () => _confirm(r, 'deleteAllocation'), red),
        ],
      'Reversed' => [
          b('View', () => _view(r)),
          b('Edit Allocation', () => _allocate(r), blue),
          b('Repost', () => _confirm(r, 'repost'), TColors.emerald600),
          if (_canDelete) b('Delete Allocation', () => _confirm(r, 'deleteAllocation'), red),
        ],
      'Cancelled' => [b('View', () => _view(r))],
      _ => const <Widget>[],
    };
  }

  // ------------------------------------------------------------ exports

  ({num eggs, int crates, int pieces, num feed, num deaths, int pending, int posted}) _totals(List<Map> rows) {
    final eggs = _sum(rows, 'totalEggs');
    return (
      eggs: eggs,
      crates: eggs ~/ eggsPerCrate,
      pieces: (eggs % eggsPerCrate).toInt(),
      feed: _sum(rows, 'feedKg'),
      deaths: _sum(rows, 'deaths'),
      pending: rows.where((r) => tStr(r['status']) == 'PendingAllocation').length,
      posted: rows.where((r) => tStr(r['status']) == 'Posted').length,
    );
  }

  String _n(num v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';
  String get _stamp => DateTime.now().toUtc().toIso8601String().substring(0, 10);

  ReportDocument _doc(List<Map> rows) {
    final t = _totals(rows);
    final fourth = _picks.enableFourth;
    return ReportDocument(
      title: 'Batch Production Report',
      filename: 'batch-production-$_stamp',
      farmName: widget.company.name.isNotEmpty ? widget.company.name : 'Farm',
      landscape: true,
      subtitle: 'Batches: ${rows.length}  |  Total Eggs: ${loc(t.eggs)} (${t.crates} crates + ${t.pieces} pcs)  |  Feed: ${t.feed.toStringAsFixed(2)} kg  |  '
          'Deaths: ${_n(t.deaths)}  |  Pending: ${t.pending}  |  Posted: ${t.posted}',
      sections: [
        ReportSection(
          columns: [
            for (final h in ['Date', 'Batch', 'Age', '1st', '2nd', '3rd', if (fourth) '4th', 'Broken', 'Total', 'Egg%', 'Feed(kg)', 'Birds', 'Deaths', 'Left', 'Meds', 'Status'])
              ReportColumn(h),
          ],
          rows: [
            for (final r in rows)
              [
                _dateText(r),
                batchNameLabel(r),
                batchFormatAge(r),
                _n(tNum(r['firstPickTotal'])),
                _n(tNum(r['secondPickTotal'])),
                _n(tNum(r['thirdPickTotal'])),
                if (fourth) _n(tNum(r['fourthPickTotal'])),
                _n(tNum(r['brokenEggs'])),
                _n(tNum(r['totalEggs'])),
                batchEggPercent(r),
                tNum(r['feedKg']).toStringAsFixed(2),
                r['birdsLeft'] == null ? '—' : _n(tNum(r['birdsLeft'])),
                _n(tNum(r['deaths'])),
                r['birdsLeft'] == null ? '—' : _n(tNum(r['birdsLeft'])),
                '${listOf(r, 'medications').length}',
                batchStatusLabel(r['status']),
              ],
          ],
        ),
      ],
    );
  }

  Future<void> _exportCsv(List<Map> rows) {
    final fourth = _picks.enableFourth;
    final headers = [
      'Date', 'Batch Name', 'Scope', 'Age', '1st Pick', '2nd Pick', '3rd Pick', if (fourth) '4th Pick',
      'Broken', 'Total', 'Egg%', 'Feed', 'Birds', 'Deaths', 'Left', 'Meds', 'Status',
    ];
    String cell(Object? v) {
      final s = v is num ? _n(v) : tStr(v);
      return v is String && s.contains(',') ? '"$s"' : s;
    }

    final lines = [
      headers.map(cell).join(','),
      for (final r in rows)
        [
          _dateText(r),
          batchNameLabel(r),
          batchScopeLabel(r),
          batchFormatAge(r),
          tNum(r['firstPickTotal']),
          tNum(r['secondPickTotal']),
          tNum(r['thirdPickTotal']),
          if (fourth) tNum(r['fourthPickTotal']),
          tNum(r['brokenEggs']),
          tNum(r['totalEggs']),
          batchEggPercent(r),
          tNum(r['feedKg']),
          r['birdsLeft'] == null ? '' : tNum(r['birdsLeft']),
          tNum(r['deaths']),
          r['birdsLeft'] == null ? '' : tNum(r['birdsLeft']),
          listOf(r, 'medications').length,
          batchStatusLabel(r['status']),
        ].map(cell).join(','),
    ];
    return ReportExport.sharer('batch-production-$_stamp.csv', utf8.encode(lines.join('\n')), 'text/csv', 'Batch Production');
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
    var from = _f.from, to = _f.to, status = _f.status, batch = _f.batch, month = _f.month, year = _f.year;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final changed = from != _f.from || to != _f.to || status != _f.status || batch != _f.batch || month != _f.month || year != _f.year;
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
                'Status',
                AppSelect<String>(
                  value: status,
                  hintText: 'All Statuses',
                  items: [
                    const AppSelectItem(value: 'ALL', label: 'All Statuses'),
                    for (final s in batchStatuses) AppSelectItem(value: s, label: batchStatusLabels[s]!),
                  ],
                  onChanged: (v) => set(() => status = v ?? 'ALL'),
                ),
              ),
              const SizedBox(height: 12),
              FilterLabel(
                'Batch',
                AppSelect<String>(
                  value: batch,
                  hintText: 'All Batches',
                  items: [
                    const AppSelectItem(value: 'ALL', label: 'All Batches'),
                    for (final (k, l) in _distinctBatches) AppSelectItem(value: k, label: l),
                  ],
                  onChanged: (v) => set(() => batch = v ?? 'ALL'),
                ),
              ),
              const SizedBox(height: 12),
              FilterLabel(
                'Month',
                AppSelect<String>(
                  value: month,
                  hintText: 'All months',
                  items: [
                    const AppSelectItem(value: 'ALL', label: 'All Months'),
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
                  items: [const AppSelectItem(value: 'ALL', label: 'All'), for (final y in _years) AppSelectItem(value: y, label: y)],
                  onChanged: (v) => set(() => year = v ?? 'ALL'),
                ),
              ),
              const SizedBox(height: 10),
              const Text('Choose options, then tap Apply.', style: TextStyle(fontSize: 12, color: TColors.slate500)),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: () {
                      setState(() {
                        _search.clear();
                        _f
                          ..search = ''
                          ..from = ''
                          ..to = ''
                          ..status = 'ALL'
                          ..batch = 'ALL'
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
                                ..status = status
                                ..batch = batch
                                ..month = month
                                ..year = year;
                              _page = 1;
                            });
                            Navigator.pop(ctx);
                            trackerToast(context, 'Filters applied', description: 'Batch list updated.');
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
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/batch-production-records');
    final rows = _filtered;
    final sorted = _sorted(rows);
    final totalPages = sorted.isEmpty ? 1 : (sorted.length + _perPage - 1) ~/ _perPage;
    final page = _page.clamp(1, totalPages);
    final start = (page - 1) * _perPage;
    final pageRows = sorted.sublist(start.clamp(0, sorted.length), (start + _perPage).clamp(0, sorted.length));
    final t = _totals(rows);
    final active = _f.activeCount;

    Widget tile(String label, String value, {Color? color, String? sub}) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label.toUpperCase(),
                overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: .6, color: TColors.slate500)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color ?? TColors.slate900)),
            if (sub != null) Text(sub, style: const TextStyle(fontSize: 12, color: TColors.slate400)),
          ]),
        );

    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Batch Production Records')),
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
                child: const Icon(Icons.layers_outlined, size: 20, color: TColors.emerald600),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Batch Production Records',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: TColors.slate900)),
                  Text('Log batch-level production and allocate totals across flocks', style: TextStyle(fontSize: 13, color: TColors.slate600)),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: TColors.emerald600, minimumSize: const Size.fromHeight(44)),
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Log Batch Production'),
            ),
            const SizedBox(height: 14),
            if (_error.isNotEmpty) ...[TrackerBanner.error(_error), const SizedBox(height: 12)],
            AppInput(
              controller: _search,
              hintText: 'Search batches...',
              prefixIcon: const Icon(Icons.search, size: 18, color: TColors.slate400),
              onChanged: (v) => setState(() {
                _f.search = v;
                _page = 1;
              }),
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
                tile('Total Batches', loc(rows.length)),
                tile('Total Eggs', loc(t.eggs), color: TColors.emerald600, sub: '${t.crates}c + ${t.pieces}p'),
                tile('Pending Allocation', loc(t.pending), color: TColors.amber600),
                tile('Posted', loc(t.posted), color: TColors.emerald700),
                tile('Feed (kg)', t.feed.toStringAsFixed(2), sub: 'Deaths: ${loc(t.deaths)}'),
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
                                const Text('No batch records found', style: TextStyle(color: TColors.slate500)),
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
                          _tableView(pageRows),
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
    Widget tile(String label, String value, Color bg, Color border, Color fg) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .4, color: fg)),
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: fg)),
          ]),
        );
    Widget kv(String l, String v, {Color? color}) => Text.rich(TextSpan(children: [
          TextSpan(text: '$l ', style: const TextStyle(color: TColors.slate500)),
          TextSpan(text: v, style: TextStyle(fontWeight: FontWeight.w500, color: color)),
        ]), style: const TextStyle(fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis);
    final deaths = tNum(r['deaths']);
    final picks = [
      ('1st Pick', 'firstPickTotal', TColors.blue600),
      ('2nd Pick', 'secondPickTotal', const Color(0xFFC2410C)),
      ('3rd Pick', 'thirdPickTotal', const Color(0xFF7E22CE)),
      if (_picks.enableFourth) ('4th Pick', 'fourthPickTotal', const Color(0xFF0F766E)),
      ('Broken', 'brokenEggs', TColors.red700),
    ];
    return ProdCard(
      key: ValueKey('batch-${r['id']}'),
      striped: i.isEven,
      header: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(right: 24),
          child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(trackerDate(r['productionDate']), style: const TextStyle(fontWeight: FontWeight.w600, color: TColors.slate900)),
            const Text('•', style: TextStyle(color: TColors.slate500)),
            Text(batchNameLabel(r), style: const TextStyle(color: TColors.slate600)),
            batchStatusBadge(r['status']),
          ]),
        ),
        Text(batchScopeLabel(r), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: tile('Eggs', loc(tNum(r['totalEggs'])), TColors.emerald100, TColors.emerald300, TColors.emerald800)),
          const SizedBox(width: 8),
          Expanded(
            child: tile('Birds Left', r['birdsLeft'] != null ? loc(tNum(r['birdsLeft'])) : '—', TColors.blue100, TColors.blue300, const Color(0xFF1E40AF)),
          ),
        ]),
      ]),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LayoutBuilder(builder: (context, c) {
          final w = (c.maxWidth - 8) / 2;
          return Wrap(spacing: 8, runSpacing: 6, children: [
            for (final (l, k, color) in picks) SizedBox(width: w, child: kv(l, _n(tNum(r[k])), color: color)),
            SizedBox(width: w, child: kv('Egg %', batchEggPercent(r))),
            SizedBox(width: w, child: kv('Feed', '${tNum(r['feedKg']).toStringAsFixed(2)} kg')),
            SizedBox(width: w, child: kv('Deaths', _n(deaths), color: deaths > 0 ? TColors.red600 : null)),
            SizedBox(width: w, child: kv('Age', batchFormatAge(r))),
            SizedBox(width: w, child: kv('Meds', batchMedsLabel(r))),
          ]);
        }),
        const SizedBox(height: 8),
        Wrap(spacing: 4, runSpacing: 4, children: _actions(r)),
      ]),
    );
  }

  Widget _tableView(List<Map> pageRows) {
    final fourth = _picks.enableFourth;
    return TrackerTable(
      sort: _sort,
      onSort: (k) => setState(() => _sort = toggleSort(k, _sort)),
      columns: [
        const TCol('Date', sortKey: 'date', width: 100),
        const TCol('Batch Name', sortKey: 'batchName', width: 180),
        const TCol('Age', sortKey: 'age', width: 90),
        const TCol('1st Pick', sortKey: 'firstPickTotal', right: true, width: 80),
        const TCol('2nd Pick', sortKey: 'secondPickTotal', right: true, width: 80),
        const TCol('3rd Pick', sortKey: 'thirdPickTotal', right: true, width: 80),
        if (fourth) const TCol('4th Pick', sortKey: 'fourthPickTotal', right: true, width: 80),
        const TCol('Broken', sortKey: 'brokenEggs', right: true, width: 80),
        const TCol('Total', sortKey: 'totalEggs', right: true, width: 80),
        const TCol('Egg%', sortKey: 'eggPercent', right: true, width: 80),
        const TCol('Feed', sortKey: 'feedKg', right: true, width: 80),
        const TCol('Birds', sortKey: 'birdsLeft', right: true, width: 80),
        const TCol('Deaths', sortKey: 'deaths', right: true, width: 72),
        const TCol('Left', sortKey: 'birdsLeft', right: true, width: 70),
        const TCol('Meds', sortKey: 'meds', width: 90),
        const TCol('Status', sortKey: 'status', width: 140),
        const TCol('Actions', width: 260),
      ],
      emptyText: 'No batch records found for the selected filters.',
      rows: [
        for (final r in pageRows)
          [
            cellText(trackerDate(r['productionDate'])),
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(batchNameLabel(r), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.slate800)),
              Text(batchScopeLabel(r), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            ]),
            cellText(batchFormatAge(r)),
            cellText(_n(tNum(r['firstPickTotal'])), color: TColors.blue600),
            cellText(_n(tNum(r['secondPickTotal'])), color: const Color(0xFFC2410C)),
            cellText(_n(tNum(r['thirdPickTotal'])), color: const Color(0xFF7E22CE)),
            if (fourth) cellText(_n(tNum(r['fourthPickTotal'])), color: const Color(0xFF0F766E)),
            cellText(_n(tNum(r['brokenEggs'])), color: TColors.red700),
            cellText(_n(tNum(r['totalEggs'])), bold: true),
            cellText(batchEggPercent(r)),
            cellText(tNum(r['feedKg']).toStringAsFixed(2)),
            cellText(r['birdsLeft'] == null ? '—' : _n(tNum(r['birdsLeft']))),
            Align(
              alignment: Alignment.centerRight,
              child: TBadge(_n(tNum(r['deaths'])),
                  bg: tNum(r['deaths']) > 0 ? TColors.red50 : TColors.slate50, fg: tNum(r['deaths']) > 0 ? TColors.red700 : TColors.slate600),
            ),
            cellText(r['birdsLeft'] == null ? '—' : _n(tNum(r['birdsLeft']))),
            cellText(batchMedsLabel(r)),
            Align(alignment: Alignment.centerLeft, child: batchStatusBadge(r['status'])),
            Wrap(children: _actions(r)),
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

// ------------------------------------------------------------ the batch view

/// app/batch-production-records/[id]: batch totals, the feed & medication
/// lines, the allocation table and notes, with Allocation / Repost / Reverse /
/// Delete Allocation by status.
class BatchProductionDetailScreen extends StatefulWidget {
  const BatchProductionDetailScreen({super.key, required this.session, required this.company, required this.batchId});
  final Session session;
  final Company company;
  final int batchId;
  @override
  State<BatchProductionDetailScreen> createState() => _BatchProductionDetailScreenState();
}

class _BatchProductionDetailScreenState extends State<BatchProductionDetailScreen> {
  Map? _batch;
  bool _loading = true, _busy = false;
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;
  String get _userId => widget.session.tokens.userId ?? '';
  String get _farmId => widget.company.farmId;

  @override
  void initState() {
    super.initState();
    CompanyClock.load(widget.session, widget.company).then((c) {
      if (mounted) setState(() => _offset = c.offset);
    });
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await _api.get('/api/ProductionBatchRecord/${widget.batchId}', query: {'farmId': _farmId});
      if (r is Map && mounted) setState(() => _batch = r);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load record', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _run(Future<void> Function() call, String okTitle, String okText, String failTitle) async {
    setState(() => _busy = true);
    try {
      await call();
      if (!mounted) return;
      setState(() => _busy = false);
      trackerToast(context, okTitle, description: okText);
      _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      trackerToast(context, failTitle, description: e.message, error: true);
    }
  }

  Future<void> _reverse() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text('Reverse this posted batch? The generated flock records, inventory and bird changes will be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(
      () => _api.post('/api/ProductionBatchRecord/${widget.batchId}/reverse', query: {'farmId': _farmId}, body: {'userId': _userId}),
      'Batch reversed',
      'You can edit the allocation and repost it.',
      'Reverse failed',
    );
  }

  Future<void> _repost() => _run(
        () => _api.post('/api/ProductionBatchRecord/${widget.batchId}/post', query: {'farmId': _farmId}, body: {'userId': _userId}),
        'Allocation reposted',
        'Fresh flock records, inventory and bird counts have been created.',
        'Repost failed',
      );

  Future<void> _deleteAllocation() async {
    final posted = tStr(_batch?['status']) == 'Posted';
    const s = TextStyle(fontSize: 14, color: TColors.slate600);
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) => AlertDialog(
            title: Text(posted ? 'Delete Posted Allocation?' : 'Delete Allocation?'),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: posted
                ? const [
                    Text('This allocation has already created flock-level production records and updated inventory.', style: s),
                    SizedBox(height: 8),
                    Text(
                        'Deleting it will reverse egg production, feed usage, bird mortality, medication usage, and all other related inventory effects. The generated flock-level production records will be removed and reversal stock movements recorded.',
                        style: s),
                    SizedBox(height: 8),
                    Text(
                        'The parent batch production record will remain available so it can be edited and allocated again. This action cannot be undone automatically.',
                        style: s),
                  ]
                : const [
                    Text('This will remove the allocation rows for this batch.', style: s),
                    SizedBox(height: 8),
                    Text(
                        'No inventory has been affected yet, so nothing will be reversed. The batch record itself stays available and returns to Pending Allocation so you can allocate it again.',
                        style: s),
                  ]),
            actions: [
              OutlinedButton(onPressed: _busy ? null : () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: TColors.red600),
                onPressed: _busy
                    ? null
                    : () async {
                        set(() => _busy = true);
                        setState(() {});
                        String? err;
                        try {
                          await _api.delete('/api/ProductionBatchRecord/${widget.batchId}/allocation'
                              '?farmId=${Uri.encodeQueryComponent(_farmId)}&userId=${Uri.encodeQueryComponent(_userId)}');
                        } on ApiException catch (e) {
                          err = e.message;
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (!mounted) return;
                        setState(() => _busy = false);
                        if (err == null) {
                          trackerToast(context, 'Allocation deleted',
                              description: posted
                                  ? 'Inventory and bird effects were reversed. The batch is back to Pending Allocation.'
                                  : 'The batch is back to Pending Allocation.');
                          _load();
                        } else {
                          trackerToast(context, 'Delete failed', description: err, error: true);
                        }
                      },
                child: Text(posted ? 'Delete and Reverse Allocation' : 'Delete Allocation'),
              ),
            ],
          )),
    );
  }

  Future<void> _allocate() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BatchAllocateScreen(session: widget.session, company: widget.company, batchId: widget.batchId),
    ));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final b = _batch;
    final status = tStr(b?['status']);
    final allocations = b == null ? <Map>[] : listOf(b, 'allocations');
    final canAllocate = b != null && const ['PendingAllocation', 'Allocated', 'Reversed'].contains(status);
    final canRepost = b != null && status == 'Reversed' && allocations.isNotEmpty;
    final hasAllocation = b != null && allocations.isNotEmpty && status != 'PendingAllocation';
    final fifth = tNum(b?['fifthPickTotal']) > 0, sixth = tNum(b?['sixthPickTotal']) > 0;
    String n(Object? v) {
      final x = tNum(v);
      return x == x.roundToDouble() ? '${x.toInt()}' : '$x';
    }

    Widget field(String l, String v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w500)),
        ]);
    Widget card(String title, Widget child) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: TCard(title: title, child: child),
        );

    return Scaffold(
      appBar: AppBar(
        leading: TextButton.icon(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back, size: 16),
          label: const Text('Back'),
        ),
        leadingWidth: 96,
        title: Text(b == null ? '' : batchNameLabel(b)),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
        if (b != null) ...[
          Text(batchNameLabel(b), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          Text(batchScopeLabel(b), style: const TextStyle(fontSize: 14, color: TColors.slate500)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            TBadge(batchStatusLabel(status), bg: Colors.white, fg: TColors.slate800, border: TColors.slate200),
            if (canAllocate)
              FilledButton.icon(
                onPressed: _allocate,
                icon: const Icon(Icons.balance, size: 16),
                label: Text(status == 'Reversed' ? 'Edit Allocation' : 'Allocation'),
              ),
            if (canRepost) FilledButton.icon(onPressed: _busy ? null : _repost, icon: const Icon(Icons.send, size: 16), label: const Text('Repost')),
            if (status == 'Posted')
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: TColors.red600),
                onPressed: _busy ? null : _reverse,
                icon: const Icon(Icons.undo, size: 16),
                label: const Text('Reverse'),
              ),
            if (hasAllocation)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: TColors.red600, side: const BorderSide(color: TColors.red200)),
                onPressed: _busy ? null : _deleteAllocation,
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Delete Allocation'),
              ),
          ]),
          const SizedBox(height: 16),
        ],
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 64),
            child: Text('Loading…', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: TColors.slate500)),
          ),
        if (!_loading && b != null) ...[
          card(
            'Batch totals',
            LayoutBuilder(builder: (context, c) {
              final w = (c.maxWidth - 16) / 2;
              return Wrap(spacing: 16, runSpacing: 16, children: [
                for (final (l, v) in [
                  ('Date', fmtDateTime(b['productionDate'], b, _offset)),
                  ('Age', tStr(b['batchSelectionType']) == 'SpecificBatch' ? (tStr(b['ageDisplay']).isNotEmpty ? tStr(b['ageDisplay']) : '—') : 'N/A'),
                  ('1st Pick', n(b['firstPickTotal'])),
                  ('2nd Pick', n(b['secondPickTotal'])),
                  ('3rd Pick', n(b['thirdPickTotal'])),
                  ('4th Pick', n(b['fourthPickTotal'])),
                  if (fifth) ('5th Pick', n(b['fifthPickTotal'])),
                  if (sixth) ('6th Pick', n(b['sixthPickTotal'])),
                  ('Broken', n(b['brokenEggs'])),
                  ('Meaty', n(b['meatyEggs'])),
                  ('Soft', n(b['softEggs'])),
                  ('Lost', n(b['lostEggs'])),
                  ('Total Eggs', n(b['totalEggs'])),
                  ('Deaths', n(b['deaths'])),
                  ('Feed (kg)', n(b['feedKg'])),
                  ('Birds Left', b['birdsLeft'] == null ? '—' : n(b['birdsLeft'])),
                  ('Feed Cost', tNum(b['totalFeedCost']).toStringAsFixed(2)),
                  ('Med Cost', tNum(b['totalMedicationCost']).toStringAsFixed(2)),
                  ('Total Cost', tNum(b['totalCostOfProduction']).toStringAsFixed(2)),
                ])
                  SizedBox(width: w, child: field(l, v)),
              ]);
            }),
          ),
          if (listOf(b, 'feeds').isNotEmpty || listOf(b, 'medications').isNotEmpty)
            card(
              'Feed & medication lines',
              Column(children: [
                for (final (lines, tag) in [(listOf(b, 'feeds'), 'feed'), (listOf(b, 'medications'), 'med')])
                  for (final f in lines)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: TColors.slate200))),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          child: Text('${tStr(f['itemName']).isNotEmpty ? tStr(f['itemName']) : 'Item ${tStr(f['itemId'])}'} ($tag)',
                              style: const TextStyle(fontSize: 14)),
                        ),
                        const SizedBox(width: 8),
                        Text('${n(f['qty'])} @ ${tNum(f['unitCost']).toStringAsFixed(2)} = ${tNum(f['totalCost']).toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 14)),
                      ]),
                    ),
              ]),
            ),
          if (allocations.isNotEmpty)
            card(
              'Allocation (${allocations.length} flocks)',
              TrackerTable(
                columns: [
                  const TCol('Flock', width: 140),
                  const TCol('1st', right: true, width: 60),
                  const TCol('2nd', right: true, width: 60),
                  const TCol('3rd', right: true, width: 60),
                  const TCol('4th', right: true, width: 60),
                  if (fifth) const TCol('5th', right: true, width: 60),
                  if (sixth) const TCol('6th', right: true, width: 60),
                  const TCol('Broken', right: true, width: 70),
                  const TCol('Total', right: true, width: 70),
                  const TCol('Deaths', right: true, width: 70),
                  const TCol('Egg %', right: true, width: 70),
                ],
                rows: [
                  for (final a in allocations)
                    [
                      cellText(tStr(a['flockName']).isNotEmpty ? tStr(a['flockName']) : 'Flock ${tStr(a['flockId'])}', bold: true),
                      cellText(n(a['firstPickEggs'])),
                      cellText(n(a['secondPickEggs'])),
                      cellText(n(a['thirdPickEggs'])),
                      cellText(n(a['fourthPickEggs'])),
                      if (fifth) cellText(n(a['fifthPickEggs'])),
                      if (sixth) cellText(n(a['sixthPickEggs'])),
                      cellText(n(a['brokenEggs'])),
                      cellText(n(a['totalEggs']), bold: true),
                      cellText(n(a['deaths'])),
                      cellText('${tNum(a['eggPercentage']).toStringAsFixed(1)}%', color: TColors.slate500),
                    ],
                ],
              ),
            ),
          if (tStr(b['notes']).isNotEmpty) card('Notes', Text(tStr(b['notes']), style: const TextStyle(fontSize: 14))),
        ],
      ]),
    );
  }
}

// ------------------------------------------------------------ links

/// `/batch-production-records?date=`, `/new?…`, `/{id}`, `/{id}/edit` and
/// `/{id}/allocate?returnTo=`.
Widget? batchProductionScreenForHref(String href, Session s, Company c) {
  final uri = Uri.tryParse(href);
  if (uri == null) return null;
  final q = uri.queryParameters;
  if (uri.path == '/batch-production-records' && uri.query.isNotEmpty) {
    return BatchProductionRecordsScreen(session: s, company: c, date: toBusinessDate(q['date']));
  }
  if (uri.path == '/batch-production-records/new') {
    return BatchProductionRecordPage(session: s, company: c, prefill: parseMissingProductionPrefill(q));
  }
  final m = RegExp(r'^/batch-production-records/([^/]+)(/edit|/allocate)?$').firstMatch(uri.path);
  if (m == null) return null;
  final id = int.tryParse(m[1]!);
  switch (m[2]) {
    case '/edit':
      return id != null && id > 0
          ? BatchProductionRecordPage(session: s, company: c, recordId: id)
          : BatchProductionRecordPage(session: s, company: c, invalidId: true);
    case '/allocate':
      return id == null ? null : BatchAllocateScreen(session: s, company: c, batchId: id, returnTo: safeReturnPath(q['returnTo']));
    default:
      return id == null ? null : BatchProductionDetailScreen(session: s, company: c, batchId: id);
  }
}
