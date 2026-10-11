// Poultry → Operations → Production → Feed Usage (app/feed-usage/page.tsx):
// search and the Filters sheet (dates, flock, month, year), two summary
// tiles, cards and the table, paging, and the Add / Edit dialogs, which also
// write the kilograms into that day's production record.

import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../shared/business_dates.dart';
import '../../shared/company_clock.dart';
import '../sales/sales_logic.dart' show pageNumbers, isFlockClosed;
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull, trackerDate, localDateKey, sortRows, toggleSort, SortState, flockCountsTowardBirdTotals;
import '../trackers/tracker_widgets.dart';
import 'egg_sorting_screen.dart' show productionRecordPayload;
import 'production_record_form.dart' show feedTypes;
import 'production_records_screen.dart' show ProdCard;

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December',
];

/// flockSelectLabel: "Name (Breed) - N birds" plus the lifecycle note.
String feedFlockLabel(Map f) {
  final note = isFlockClosed(f)
      ? ' · Closed'
      : f['hasArrived'] != true
          ? ' · Pending arrival'
          : f['active'] != true
              ? ' · Inactive'
              : '';
  return '${tStr(f['name'])} (${tStr(f['breed'])}) - ${tStr(f['quantity'])} birds$note';
}

String _qty(Object? v) {
  final n = tNum(v);
  return n == n.roundToDouble() ? '${n.toInt()}' : '$n';
}

class FeedUsageScreen extends StatefulWidget {
  const FeedUsageScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;
  @override
  State<FeedUsageScreen> createState() => _FeedUsageScreenState();
}

class _FeedUsageScreenState extends State<FeedUsageScreen> {
  List<Map> _usages = [], _flocks = [];
  bool _loading = true, _table = false;
  String _error = '';
  final _search = TextEditingController();
  String _q = '', _from = '', _to = '', _flock = 'ALL', _month = 'ALL', _year = 'ALL';
  SortState _sort = (key: null, dir: null);
  int _page = 1, _perPage = 10;
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;
  String get _userId => widget.session.tokens.userId ?? '';
  String get _farmId => widget.company.farmId;
  Map<String, String> get _ctx => {'userId': _userId, 'farmId': _farmId};
  bool get _canDelete => (widget.company.role ?? '').toLowerCase() != 'staff';

  @override
  void initState() {
    super.initState();
    CompanyClock.load(widget.session, widget.company).then((c) {
      if (mounted) setState(() => _offset = c.offset);
    });
    _load();
    _loadFlocks();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadFlocks() async {
    if (_userId.isEmpty || _farmId.isEmpty) return;
    try {
      final f = rowsOf(await _api.get('/api/Flock', query: _ctx));
      if (mounted) setState(() => _flocks = f);
    } on ApiException {
      // The list still shows "Flock #id".
    }
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
      final rows = rowsOf(await _api.get('/api/FeedUsage', query: _ctx));
      if (!mounted) return;
      setState(() {
        _usages = rows;
        _page = 1;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message.isNotEmpty ? e.message : 'Failed to load feed usages';
        _loading = false;
      });
    }
  }

  DateTime? _local(Object? v) => DateTime.tryParse(tStr(v))?.toLocal();
  String _dateText(Map u) => fmtDateTime(u['usageDate'], u, _offset);
  String _flockName(Map u) {
    final f = _flocks.where((x) => tIntOrNull(x['flockId']) == tIntOrNull(u['flockId'])).firstOrNull;
    return f != null ? tStr(f['name']) : 'Flock #${tStr(u['flockId'])}';
  }

  List<String> get _years => ({for (final u in _usages) if (_local(u['usageDate']) != null) _local(u['usageDate'])!.year}.toList()
        ..sort((a, b) => b - a))
      .map((y) => '$y')
      .toList();

  List<Map> get _filtered {
    final q = _q.trim().toLowerCase();
    return [
      for (final u in _usages)
        if ((q.isEmpty ||
                tStr(u['feedType']).toLowerCase().contains(q) ||
                tStr(u['flockId']).contains(q) ||
                _qty(u['quantityKg']).contains(q) ||
                _dateText(u).toLowerCase().contains(q)) &&
            (_from.isEmpty || localDateKey(u['usageDate']).compareTo(_from) >= 0) &&
            (_to.isEmpty || localDateKey(u['usageDate']).compareTo(_to) <= 0) &&
            (_flock == 'ALL' || tStr(u['flockId']) == _flock) &&
            (_month == 'ALL' || '${_local(u['usageDate'])?.month}' == _month) &&
            (_year == 'ALL' || '${_local(u['usageDate'])?.year}' == _year))
          u,
    ];
  }

  List<Map> _sorted(List<Map> rows) => sortRows(rows, _sort, (r, k) => switch (k) {
        'date' => DateTime.tryParse(tStr(r['usageDate'])) ?? DateTime(0),
        'quantityKg' => tNum(r['quantityKg']),
        'flockId' => tNum(r['flockId']),
        _ => tStr(r[k]),
      });

  // ------------------------------------------------------------ dialogs

  Future<void> _openForm([int? id]) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _FeedUsageDialog(session: widget.session, company: widget.company, feedUsageId: id),
    );
    if (ok == true) _load();
  }

  Future<void> _delete(int id) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        var busy = false;
        return StatefulBuilder(builder: (ctx, set) => AlertDialog(
              title: const Text('Delete Feed Usage Record'),
              content: const Text('Are you sure you want to delete this feed usage record? This action cannot be undone.'),
              actions: [
                TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: const Text('Cancel')),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: TColors.red600),
                  onPressed: busy
                      ? null
                      : () async {
                          if (_userId.isEmpty || _farmId.isEmpty) {
                            trackerToast(context, 'Session issue', description: 'We could not confirm your farm or user. Please sign in again.', error: true);
                            return;
                          }
                          set(() => busy = true);
                          try {
                            await _api.delete('/api/FeedUsage/$id?userId=${Uri.encodeQueryComponent(_userId)}&farmId=${Uri.encodeQueryComponent(_farmId)}');
                            if (mounted) trackerToast(context, 'Record deleted', description: 'The feed usage record has been successfully deleted.');
                            _load();
                          } on ApiException catch (e) {
                            if (mounted) {
                              trackerToast(context, 'Delete failed', description: e.message.isNotEmpty ? e.message : 'Something went wrong.', error: true);
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
    var from = _from, to = _to, flock = _flock, month = _month, year = _year;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final changed = from != _from || to != _to || flock != _flock || month != _month || year != _year;
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
                  hintText: 'Flock',
                  items: [
                    const AppSelectItem(value: 'ALL', label: 'All Flocks'),
                    for (final f in _flocks) AppSelectItem(value: tStr(f['flockId']), label: tStr(f['name'])),
                  ],
                  onChanged: (v) => set(() => flock = v ?? 'ALL'),
                ),
              ),
              const SizedBox(height: 12),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: FilterLabel(
                    'Month',
                    AppSelect<String>(
                      value: month,
                      hintText: 'Month',
                      items: [
                        const AppSelectItem(value: 'ALL', label: 'All Months'),
                        for (var i = 0; i < 12; i++) AppSelectItem(value: '${i + 1}', label: _months[i]),
                      ],
                      onChanged: (v) => set(() => month = v ?? 'ALL'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilterLabel(
                    'Year',
                    AppSelect<String>(
                      value: year,
                      hintText: 'Year',
                      items: [const AppSelectItem(value: 'ALL', label: 'All Years'), for (final y in _years) AppSelectItem(value: y, label: y)],
                      onChanged: (v) => set(() => year = v ?? 'ALL'),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: () {
                      setState(() {
                        _search.clear();
                        _q = '';
                        _from = '';
                        _to = '';
                        _flock = 'ALL';
                        _month = 'ALL';
                        _year = 'ALL';
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
                              _from = from;
                              _to = to;
                              _flock = flock;
                              _month = month;
                              _year = year;
                              _page = 1;
                            });
                            Navigator.pop(ctx);
                            trackerToast(context, 'Filters applied', description: 'Feed usage list updated.');
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
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/feed-usage');
    final rows = _filtered;
    final sorted = _sorted(rows);
    final totalPages = (sorted.length / _perPage).ceil();
    final page = totalPages == 0 ? 1 : _page.clamp(1, totalPages);
    final start = (page - 1) * _perPage;
    final pageRows = sorted.sublist(start.clamp(0, sorted.length), (start + _perPage).clamp(0, sorted.length));
    final totalKg = rows.fold<num>(0, (s, u) => s + tNum(u['quantityKg']));
    final active = [_q.isNotEmpty, _from.isNotEmpty, _to.isNotEmpty, _flock != 'ALL', _month != 'ALL', _year != 'ALL'].where((b) => b).length;

    Widget tile(String label, String value, Color color) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
              Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: color)),
            ]),
          ),
        );

    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Feed Usage')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: TColors.amber100, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.inventory_2_outlined, size: 20, color: TColors.amber600),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Feed Usage', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: TColors.slate900)),
                Text('Monitor feed consumption and costs', style: TextStyle(color: TColors.slate600)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: TColors.blue600, minimumSize: const Size.fromHeight(44)),
            onPressed: () => _openForm(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Usage'),
          ),
          const SizedBox(height: 16),
          AppInput(
            controller: _search,
            hintText: 'Search feed usage...',
            prefixIcon: const Icon(Icons.search, size: 18, color: TColors.slate400),
            onChanged: (v) => setState(() {
              _q = v;
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
          const SizedBox(height: 16),
          Row(children: [
            tile('Total Records', '${rows.length}', TColors.slate900),
            const SizedBox(width: 12),
            tile('Total Feed (kg)', '${totalKg.toStringAsFixed(2)} kg', const Color(0xFFB45309)),
          ]),
          const SizedBox(height: 16),
          if (_error.isNotEmpty) ...[TrackerBanner.error(_error), const SizedBox(height: 16)],
          if (_loading)
            const TCard(child: Padding(padding: EdgeInsets.symmetric(vertical: 36), child: Text('Loading feed usage records...', textAlign: TextAlign.center)))
          else if (sorted.isEmpty)
            TCard(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(children: [
                  const Icon(Icons.inventory_2_outlined, size: 32, color: TColors.slate400),
                  const SizedBox(height: 12),
                  const Text('No feed usage records found', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: TColors.slate900)),
                  const SizedBox(height: 6),
                  Text(
                    _q.isNotEmpty || _from.isNotEmpty || _to.isNotEmpty || _flock != 'ALL'
                        ? 'No records match your current filters.'
                        : 'Get started by adding your first feed usage record',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: TColors.slate600),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: TColors.blue600),
                    onPressed: () => _openForm(),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Your First Record'),
                  ),
                ]),
              ),
            )
          else if (!_table)
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < pageRows.length; i++) ...[_card(pageRows[i], i), const SizedBox(height: 12)],
              ViewTableButton(onPressed: () => setState(() => _table = true)),
            ])
          else
            TCard(
              padding: EdgeInsets.zero,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TableViewBar(text: 'Table • Scroll → for more', onCards: () => setState(() => _table = false)),
                TrackerTable(
                  sort: _sort,
                  onSort: (k) => setState(() => _sort = toggleSort(k, _sort)),
                  columns: const [
                    TCol('Date', sortKey: 'date', width: 120),
                    TCol('Flock', sortKey: 'flockId', width: 110),
                    TCol('Feed Type', sortKey: 'feedType', width: 150),
                    TCol('Quantity (kg)', sortKey: 'quantityKg', width: 120),
                    TCol('Actions', width: 100),
                  ],
                  rows: [
                    for (final u in pageRows)
                      [
                        Row(children: [
                          const Icon(Icons.calendar_today_outlined, size: 14, color: TColors.blue600),
                          const SizedBox(width: 6),
                          Flexible(child: Text(trackerDate(u['usageDate']), style: const TextStyle(fontWeight: FontWeight.w500))),
                        ]),
                        cellText(_flockName(u), color: TColors.slate600),
                        Row(children: [
                          const Icon(Icons.inventory_2_outlined, size: 14, color: TColors.amber600),
                          const SizedBox(width: 6),
                          Flexible(child: Text(tStr(u['feedType']), style: const TextStyle(fontWeight: FontWeight.w500))),
                        ]),
                        cellText('${_qty(u['quantityKg'])} kg', bold: true, color: TColors.blue600),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined, size: 16), onPressed: () => _openForm(tIntOrNull(u['feedUsageId']))),
                          if (_canDelete)
                            IconButton(
                              tooltip: 'Delete',
                              icon: const Icon(Icons.delete_outline, size: 16, color: TColors.red600),
                              onPressed: () => _delete(tIntOrNull(u['feedUsageId']) ?? 0),
                            ),
                        ]),
                      ],
                  ],
                ),
              ]),
            ),
          if (!_loading && sorted.isNotEmpty) _pagination(sorted.length, page, totalPages, start),
        ]),
      ),
    );
  }

  Widget _card(Map u, int i) {
    final id = tIntOrNull(u['feedUsageId']) ?? 0;
    return ProdCard(
      key: ValueKey('feed-$id'),
      striped: i.isEven,
      header: Padding(
        padding: const EdgeInsets.only(right: 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text.rich(TextSpan(children: [
            TextSpan(text: trackerDate(u['usageDate']), style: const TextStyle(fontWeight: FontWeight.w600, color: TColors.slate900)),
            const TextSpan(text: '  •  ', style: TextStyle(color: TColors.slate500)),
            TextSpan(text: _flockName(u), style: const TextStyle(color: TColors.slate600)),
          ]), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('${_qty(u['quantityKg'])} kg', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: TColors.amber600)),
            Text(tStr(u['feedType']), style: const TextStyle(fontSize: 14, color: TColors.slate600)),
          ]),
        ]),
      ),
      body: Row(children: [
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
    );
  }

  Widget _pagination(int total, int page, int totalPages, int start) {
    final end = (start + _perPage).clamp(0, total);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(children: [
        Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 6, children: [
          Text('Showing ${start + 1} to $end of $total records', style: const TextStyle(fontSize: 13, color: TColors.slate600)),
          SizedBox(
            width: 120,
            child: AppSelect<int>(
              value: _perPage,
              items: [for (final n in const [5, 10, 15, 25, 50]) AppSelectItem(value: n, label: '$n / page')],
              onChanged: (v) => setState(() {
                _perPage = v ?? _perPage;
                _page = 1;
              }),
            ),
          ),
        ]),
        if (totalPages > 1) ...[
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
                          : TextButton(style: TextButton.styleFrom(padding: EdgeInsets.zero), onPressed: () => setState(() => _page = p as int), child: Text('$p')),
                    ),
            TextButton.icon(
              onPressed: page == totalPages ? null : () => setState(() => _page = page + 1),
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.chevron_right, size: 18),
              label: const Text('Next'),
            ),
          ]),
        ],
      ]),
    );
  }
}

/// The Add Feed Usage / Edit Feed Usage dialog.
class _FeedUsageDialog extends StatefulWidget {
  const _FeedUsageDialog({required this.session, required this.company, this.feedUsageId});
  final Session session;
  final Company company;
  final int? feedUsageId;
  @override
  State<_FeedUsageDialog> createState() => _FeedUsageDialogState();
}

class _FeedUsageDialogState extends State<_FeedUsageDialog> {
  bool get _edit => widget.feedUsageId != null;
  bool _flocksLoading = true, _saving = false;
  late bool _fetching = _edit;
  String _error = '', _flockId = '', _feedType = '';
  String _date = isoDay(DateTime.now().toUtc());
  final _qty = TextEditingController();
  List<Map> _flocks = [];

  ApiClient get _api => widget.session.farmClient;
  String get _userId => widget.session.tokens.userId ?? '';
  String get _farmId => widget.company.farmId;
  Map<String, String> get _ctx => {'userId': _userId, 'farmId': _farmId};

  @override
  void initState() {
    super.initState();
    _loadFlocks();
    if (_edit) _loadRecord();
  }

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  Future<void> _loadFlocks() async {
    List<Map> f = [];
    if (_userId.isNotEmpty && _farmId.isNotEmpty) {
      try {
        f = rowsOf(await _api.get('/api/Flock', query: _ctx));
      } on ApiException {
        f = [];
      }
    }
    if (mounted) {
      setState(() {
        _flocks = f;
        _flocksLoading = false;
      });
    }
  }

  Future<void> _loadRecord() async {
    if (_userId.isEmpty || _farmId.isEmpty) {
      setState(() {
        _error = 'User context not found.';
        _fetching = false;
      });
      return;
    }
    try {
      final u = await _api.get('/api/FeedUsage/${widget.feedUsageId}', query: _ctx);
      if (!mounted) return;
      if (u is Map) {
        setState(() {
          _flockId = tStr(u['flockId']);
          _date = tStr(u['usageDate']).split('T').first;
          _feedType = tStr(u['feedType']);
          _qty.text = _qtyText(u['quantityKg']);
        });
      } else {
        setState(() => _error = 'Feed usage not found');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message.isNotEmpty ? e.message : 'Failed to load record');
    }
    if (mounted) setState(() => _fetching = false);
  }

  String _qtyText(Object? v) {
    final n = tNum(v);
    return n == n.roundToDouble() ? '${n.toInt()}' : '$n';
  }

  void _guide(String error, String text) {
    setState(() => _error = error);
    trackerToast(context, 'Almost there', description: text);
  }

  Future<void> _submit() async {
    if (_date.isEmpty) {
      setState(() => _error = 'Please fill out this field.');
      return;
    }
    if (_qty.text.trim().isEmpty) {
      setState(() => _error = 'Please fill out this field.');
      return;
    }
    if ((num.tryParse(_qty.text.trim()) ?? 0) < 0) {
      setState(() => _error = 'Value must be greater than or equal to 0.');
      return;
    }
    setState(() => _error = '');
    if (_userId.isEmpty || _farmId.isEmpty) {
      setState(() => _error = 'User context not found.');
      trackerToast(context, 'Session issue', description: 'We could not confirm your farm or user. Please sign in again.', error: true);
      return;
    }
    if (_flockId.isEmpty) return _guide('Choose a flock', 'Pick which flock this feed was used for from the Flock list.');
    if (_feedType.isEmpty) return _guide('Choose a feed type', 'Select the feed type (starter, grower, etc.) so records stay accurate.');
    final qty = num.tryParse(_qty.text.trim()) ?? 0;
    if (qty <= 0) return _guide('Enter quantity', 'Enter how many kilograms were used — use a number greater than zero.');
    setState(() => _saving = true);
    final flockId = int.tryParse(_flockId) ?? 0;
    final body = {
      'FarmId': _farmId,
      'UserId': _userId,
      'FeedUsageId': _edit ? widget.feedUsageId : 0,
      'FlockId': flockId,
      'UsageDate': '${_date}T00:00:00Z',
      'FeedType': _feedType,
      'QuantityKg': qty,
    };
    try {
      if (_edit) {
        await _api.put('/api/FeedUsage/${widget.feedUsageId}', body: body);
      } else {
        await _api.post('/api/FeedUsage', body: body);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message.isNotEmpty ? e.message : (_edit ? 'Failed to update feed usage' : 'Failed to create feed usage');
        _saving = false;
      });
      return;
    }
    await _syncProductionRecord(flockId, qty);
    if (!mounted) return;
    trackerToast(context, 'Success!', description: _edit ? 'Feed usage updated successfully.' : 'Feed usage recorded successfully.');
    Navigator.pop(context, true);
  }

  /// Put the kilograms into that day's production record for the flock;
  /// Add also creates one when there is none.
  Future<void> _syncProductionRecord(int flockId, num qty) async {
    try {
      final records = rowsOf(await _api.get('/api/ProductionRecord', query: _ctx));
      String utcDay(Object? v) => DateTime.tryParse(tStr(v))?.toUtc().toIso8601String().split('T').first ?? '';
      final match = records.where((pr) => tIntOrNull(pr['flockId']) == flockId && utcDay(pr['date']) == _date).firstOrNull;
      if (match != null) {
        final id = tIntOrNull(match['id']);
        await _api.put('/api/ProductionRecord/$id', body: productionRecordPayload({'feedKg': qty}, id: id));
      } else if (!_edit) {
        final flock = _flocks.where((f) => tIntOrNull(f['flockId']) == flockId).firstOrNull;
        if (flock == null) return;
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
              'feedKg': qty,
              'medication': 'None',
              'production9AM': 0,
              'production12PM': 0,
              'production4PM': 0,
              'totalProduction': 0,
              'flockId': flockId,
            }));
      }
    } on ApiException {
      // The web logs the sync error and still reports success.
    }
  }

  Widget _section(String title, Color color, List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            color: color,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
          ),
          Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)),
        ]),
      );

  Widget _label(String t) =>
      Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(t, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate700)));

  @override
  Widget build(BuildContext context) {
    final options = [for (final f in _flocks) if (flockCountsTowardBirdTotals(f)) f];
    return AlertDialog(
      title: Row(children: [
        Icon(_edit ? Icons.edit_outlined : Icons.inventory_2_outlined, size: 20, color: _edit ? TColors.blue600 : TColors.amber600),
        const SizedBox(width: 8),
        Flexible(child: Text(_edit ? 'Edit Feed Usage' : 'Add Feed Usage')),
      ]),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(_edit ? 'Update feed consumption record' : 'Record feed consumption for a flock', style: const TextStyle(fontSize: 14, color: TColors.slate500)),
            const SizedBox(height: 12),
            if (_error.isNotEmpty) ...[TrackerBanner.error(_error), const SizedBox(height: 12)],
            if (_fetching)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Column(children: [CircularProgressIndicator(), SizedBox(height: 8), Text('Loading record...', style: TextStyle(color: TColors.slate600))]),
              )
            else ...[
              _section('Flock & Date', const Color(0xFF4F46E5), [
                _label('Select Flock *'),
                AppSelect<String>(
                  value: _flockId.isEmpty ? null : _flockId,
                  hintText: _flocksLoading ? 'Loading...' : 'Select a flock',
                  enabled: !_flocksLoading && !_saving,
                  items: [for (final f in options) AppSelectItem(value: tStr(f['flockId']), label: feedFlockLabel(f))],
                  onChanged: (v) => setState(() => _flockId = v ?? ''),
                ),
                const SizedBox(height: 12),
                _label('Usage Date *'),
                AppDateField(value: businessDateAsDateTime(_date), enabled: !_saving, onChanged: (v) => setState(() => _date = v == null ? '' : isoDay(v))),
              ]),
              _section('Feed Details', const Color(0xFFF59E0B), [
                _label('Feed Type *'),
                AppSelect<String>(
                  value: _feedType.isEmpty ? null : _feedType,
                  hintText: 'Select feed type',
                  enabled: !_saving,
                  items: [for (final t in feedTypes) AppSelectItem(value: t, label: t)],
                  onChanged: (v) => setState(() => _feedType = v ?? ''),
                ),
                const SizedBox(height: 12),
                _label('Quantity (kg) *'),
                AppInput(
                  controller: _qty,
                  hintText: 'e.g., 25.5',
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ]),
            ],
          ]),
        ),
      ),
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: TColors.red600),
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        if (!_fetching)
          FilledButton.icon(
            onPressed: _saving || _flocksLoading ? null : _submit,
            icon: Icon(_edit ? Icons.edit_outlined : Icons.inventory_2_outlined, size: 16),
            label: Text(_edit ? (_saving ? 'Saving...' : 'Save Changes') : (_saving ? 'Recording...' : 'Record Usage')),
          ),
      ],
    );
  }
}
