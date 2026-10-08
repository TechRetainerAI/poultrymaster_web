// Poultry → Operations → Inventory & Health → Health Records (app/health/page.tsx):
// the Flock / House / Inventory tabs, search and the Filters sheet, striped
// cards and the sortable table, Create / Edit Health Record, and delete.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../shared/business_dates.dart';
import '../money/money_widgets.dart' show formSection, redCancelButton;
import '../sales/balances_logic.dart' show pageSlice;
import '../sales/balances_widgets.dart' show CompactPager;
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull, trackerDate, SortState, SortDir;
import '../trackers/tracker_widgets.dart';

const healthRecordTypes = ['Vaccination', 'Medication', 'Treatment', 'Illness', 'Mortality'];

final _typePrefix = RegExp(r'^\[Type:[^\]]+\]\s*', caseSensitive: false);

/// withTypePrefix: the record type rides at the front of the notes.
String withTypePrefix(String type, String? notes) {
  final clean = (notes ?? '').replaceFirst(_typePrefix, '').trim();
  return '[Type:$type]${clean.isNotEmpty ? ' $clean' : ''}';
}

String parseTypeFromNotes(Object? notes) {
  final m = RegExp(r'^\[Type:([^\]]+)\]', caseSensitive: false).firstMatch(tStr(notes));
  if (m == null) return 'Vaccination';
  return healthRecordTypes.where((t) => t.toLowerCase() == m[1]!.trim().toLowerCase()).firstOrNull ?? 'Vaccination';
}

String stripTypePrefix(Object? notes) => tStr(notes).replaceFirst(_typePrefix, '');

bool isMedicationPhotoReference(Map r) => RegExp(r'^\[Type:\s*MedicationPhoto\]', caseSensitive: false).hasMatch(tStr(r['notes']).trim());

/// The health list, read the way the web normalises it.
Map<String, Object?> normaliseHealth(Map h) {
  Object? pick(String a, String b) => h[a] ?? h[b];
  return {
    'id': pick('id', 'Id'),
    'flockId': tIntOrNull(pick('flockId', 'FlockId')) == 0 ? null : tIntOrNull(pick('flockId', 'FlockId')),
    'houseId': tIntOrNull(pick('houseId', 'HouseId')) == 0 ? null : tIntOrNull(pick('houseId', 'HouseId')),
    'itemId': tIntOrNull(pick('itemId', 'ItemId')) == 0 ? null : tIntOrNull(pick('itemId', 'ItemId')),
    'recordDate': h['recordDate'] ?? h['RecordDate'] ?? h['date'] ?? h['Date'],
    'vaccination': tStr(pick('vaccination', 'Vaccination')).isEmpty ? null : tStr(pick('vaccination', 'Vaccination')),
    'medication': tStr(pick('medication', 'Medication')).isEmpty ? null : tStr(pick('medication', 'Medication')),
    'waterConsumption': tNum(pick('waterConsumption', 'WaterConsumption')) == 0 ? null : tNum(pick('waterConsumption', 'WaterConsumption')),
    'notes': tStr(pick('notes', 'Notes')).isEmpty ? null : tStr(pick('notes', 'Notes')),
  };
}

/// The records a tab owns: exactly one of flock / house / item set, and not a
/// medication-photo reference.
List<Map> healthForTab(List<Map> all, String tab) => [
      for (final r in all)
        if (!isMedicationPhotoReference(r) &&
            switch (tab) {
              'flock' => r['flockId'] != null && r['houseId'] == null && r['itemId'] == null,
              'house' => r['houseId'] != null && r['flockId'] == null && r['itemId'] == null,
              _ => r['itemId'] != null && r['flockId'] == null && r['houseId'] == null,
            })
          r,
    ];

class HealthFilters {
  String search = '', flock = 'ALL', house = 'ALL', item = 'ALL', from = '', to = '';
}

List<Map> filterHealth(List<Map> all, String tab, HealthFilters f, SortState sort) {
  var list = healthForTab(all, tab);
  final q = f.search.toLowerCase();
  if (q.isNotEmpty) {
    list = [for (final r in list) if (['vaccination', 'medication', 'notes'].any((k) => tStr(r[k]).toLowerCase().contains(q))) r];
  }
  if (tab == 'flock' && f.flock != 'ALL') list = [for (final r in list) if (tStr(r['flockId']) == f.flock) r];
  if (tab == 'house' && f.house != 'ALL') list = [for (final r in list) if (tStr(r['houseId']) == f.house) r];
  if (tab == 'inventory' && f.item != 'ALL') list = [for (final r in list) if (tStr(r['itemId']) == f.item) r];
  String day(Map r) => tStr(r['recordDate']).split('T').first;
  if (f.from.isNotEmpty) list = [for (final r in list) if (day(r).compareTo(f.from) >= 0) r];
  if (f.to.isNotEmpty) list = [for (final r in list) if (day(r).compareTo(f.to) <= 0) r];
  final key = sort.key;
  if (key != null) {
    num v(Map r) => switch (key) {
          'date' => DateTime.tryParse(tStr(r['recordDate']))?.millisecondsSinceEpoch ?? 0,
          'flock' => tNum(r['flockId']),
          'house' => tNum(r['houseId']),
          _ => tNum(r['itemId']),
        };
    list = [...list]..sort((a, b) => sort.dir == SortDir.desc ? v(b).compareTo(v(a)) : v(a).compareTo(v(b)));
  }
  return list;
}

({String cardTitle, String cardDescription, String emptyTitle, String emptyDescription, String addLabel}) healthCopy(String tab, bool filteredOut) =>
    switch (tab) {
      'flock' => (
          cardTitle: 'Flock health records',
          cardDescription: 'Vaccinations, medications, and treatments scoped to a flock.',
          emptyTitle: filteredOut ? 'No flock records match your filters' : 'No flock health records yet',
          emptyDescription: filteredOut
              ? 'Adjust search, dates, or flock filter, or open House / Inventory if the entry was saved under another type.'
              : 'Track vaccinations and treatments for your flocks. Add your first flock health record to get started.',
          addLabel: 'Add flock health record',
        ),
      'house' => (
          cardTitle: 'House health records',
          cardDescription: 'Health entries tied to a house or barn.',
          emptyTitle: filteredOut ? 'No house records match your filters' : 'No house health records yet',
          emptyDescription: filteredOut
              ? 'Adjust search, dates, or house filter, or check Flock / Inventory for other entries.'
              : 'Record house-level treatments and checks. Add your first house health record to get started.',
          addLabel: 'Add house health record',
        ),
      _ => (
          cardTitle: 'Inventory health records',
          cardDescription: 'Treatments and notes for inventory items (e.g. feed or supplies).',
          emptyTitle: filteredOut ? 'No inventory records match your filters' : 'No inventory health records yet',
          emptyDescription: filteredOut
              ? 'Adjust search, dates, or item filter, or check Flock / House if the entry was saved there.'
              : 'Log medications or issues for inventory items. Add your first inventory health record to get started.',
          addLabel: 'Add inventory health record',
        ),
    };

String _jsNum(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

class HealthRecordsScreen extends StatefulWidget {
  const HealthRecordsScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;
  @override
  State<HealthRecordsScreen> createState() => _HealthRecordsScreenState();
}

class _HealthRecordsScreenState extends State<HealthRecordsScreen> {
  List<Map> _records = [], _flocks = [], _houses = [], _items = [];
  bool _loading = true, _table = false;
  String _error = '', _tab = 'flock';
  final _search = TextEditingController();
  final _f = HealthFilters();
  SortState _sort = (key: null, dir: null);
  int _page = 1, _size = 10;

  ApiClient get _api => widget.session.farmClient;
  String get _userId => widget.session.tokens.userId ?? '';
  Map<String, String> get _ctx => {'userId': _userId, 'farmId': widget.company.farmId};

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
    Future<List<Map>?> get(String path) async {
      try {
        return rowsOf(await _api.get(path, query: _ctx));
      } on ApiException {
        return null;
      }
    }

    String? healthError;
    List<Map>? health;
    try {
      health = rowsOf(await _api.get('/api/Health', query: _ctx));
    } on ApiException catch (e) {
      healthError = e.message.isNotEmpty
          ? e.message
          : 'Could not load health records. If this persists, confirm the API and database are up to date.';
    }
    final r = await Future.wait([get('/api/Flock'), get('/api/House'), get('/api/InventoryItem')]);
    if (!mounted) return;
    setState(() {
      if (r[0] != null) _flocks = r[0]!;
      if (r[1] != null) _houses = r[1]!;
      _items = [
        for (final s in r[2] ?? const <Map>[])
          {
            'id': tIntOrNull(s['itemId'] ?? s['id']) ?? 0,
            'name': tStr(s['name'] ?? s['itemName']).isNotEmpty ? tStr(s['name'] ?? s['itemName']) : 'Item #${tStr(s['itemId'] ?? s['id'])}',
          },
      ];
      if (health != null) _records = [for (final h in health) normaliseHealth(h)];
      if (healthError != null) _error = healthError;
      _loading = false;
    });
  }

  String _flockName(Object? id) {
    if (id == null) return '-';
    final f = _flocks.where((x) => tStr(x['flockId']) == tStr(id)).firstOrNull;
    return tStr(f?['name']).isNotEmpty ? tStr(f?['name']) : 'Flock $id';
  }

  String _houseName(Object? id) {
    if (id == null) return '-';
    final h = _houses.where((x) => tStr(x['houseId']) == tStr(id)).firstOrNull;
    return tStr(h?['name']).isNotEmpty ? tStr(h?['name']) : 'House $id';
  }

  String _itemName(Object? id) {
    if (id == null) return '-';
    final i = _items.where((x) => tStr(x['id']) == tStr(id)).firstOrNull;
    return tStr(i?['name']).isNotEmpty ? tStr(i?['name']) : 'Item $id';
  }

  String _entity(Map r) => switch (_tab) {
        'flock' => _flockName(r['flockId']),
        'house' => _houseName(r['houseId']),
        _ => _itemName(r['itemId']),
      };

  void _clear() => setState(() {
        _search.clear();
        _f
          ..search = ''
          ..flock = 'ALL'
          ..house = 'ALL'
          ..item = 'ALL'
          ..from = ''
          ..to = '';
      });

  Future<void> _openForm([Map? editing]) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => HealthRecordDialog(
        session: widget.session,
        company: widget.company,
        tab: _tab,
        flocks: _flocks,
        houses: _houses,
        items: _items,
        editing: editing,
        onError: (m) => setState(() => _error = m),
      ),
    );
    if (ok == true) _load();
  }

  Future<void> _delete(Map r) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        var busy = false;
        return StatefulBuilder(builder: (ctx, set) => AlertDialog(
              title: const Text('Delete Health Record'),
              content: const Text('Are you sure you want to delete this health record? This action cannot be undone.'),
              actions: [
                TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: const Text('Cancel')),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: TColors.red600),
                  onPressed: busy
                      ? null
                      : () async {
                          set(() => busy = true);
                          try {
                            await _api.delete('/api/Health/${r['id']}?userId=${Uri.encodeQueryComponent(_userId)}'
                                '&farmId=${Uri.encodeQueryComponent(widget.company.farmId)}');
                            if (mounted) trackerToast(context, 'Record deleted', description: 'The health record has been successfully deleted.');
                            _load();
                          } on ApiException catch (e) {
                            if (mounted) {
                              trackerToast(context, 'Delete failed',
                                  description: e.message.isNotEmpty ? e.message : 'Failed to delete health record.', error: true);
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
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        void upd(VoidCallback f) {
          set(f);
          setState(() => _page = 1);
        }

        final (label, value, all, opts, on) = switch (_tab) {
          'flock' => ('Flock', _f.flock, 'All Flocks', [for (final f in _flocks) (tStr(f['flockId']), tStr(f['name']))], (String v) => _f.flock = v),
          'house' => ('House', _f.house, 'All Houses', [for (final h in _houses) (tStr(h['houseId']), tStr(h['name']))], (String v) => _f.house = v),
          _ => ('Item', _f.item, 'All Items', [for (final i in _items) (tStr(i['id']), tStr(i['name']))], (String v) => _f.item = v),
        };
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Filters', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),
            FilterLabel(
              label,
              AppSelect<String>(
                value: value,
                hintText: label,
                items: [AppSelectItem(value: 'ALL', label: all), for (final (v, l) in opts) AppSelectItem(value: v, label: l)],
                onChanged: (v) => upd(() => on(v ?? 'ALL')),
              ),
            ),
            const SizedBox(height: 12),
            filterRow([
              FilterLabel('Date From', FilterDate(value: _f.from, hint: 'Date From', onChanged: (v) => upd(() => _f.from = v))),
              FilterLabel('Date To', FilterDate(value: _f.to, hint: 'Date To', onChanged: (v) => upd(() => _f.to = v))),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    _clear();
                    set(() {});
                  },
                  child: const Text('Clear'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Apply'))),
            ]),
          ]),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/health');
    final rows = filterHealth(_records, _tab, _f, _sort);
    final base = healthForTab(_records, _tab);
    final copy = healthCopy(_tab, base.isNotEmpty && rows.isEmpty);
    final tabIcon = switch (_tab) { 'flock' => Icons.favorite_border, 'house' => Icons.apartment, _ => Icons.inventory_2_outlined };

    Widget tab(String key, IconData icon, String label) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Material(
              color: _tab == key ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => setState(() {
                  _tab = key;
                  _page = 1;
                }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(icon, size: 16, color: TColors.slate700),
                    const SizedBox(width: 4),
                    Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
                  ]),
                ),
              ),
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Health Records')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: TColors.red100, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.favorite_border, size: 20, color: TColors.red600),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Health Records', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: TColors.slate900)),
                  Text('Track vaccinations, medications, and water consumption', style: TextStyle(fontSize: 13, color: TColors.slate600)),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: TColors.blue600, minimumSize: const Size.fromHeight(44)),
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Health Record'),
            ),
            const SizedBox(height: 14),
            if (_error.isNotEmpty) ...[TrackerBanner.error(_error), const SizedBox(height: 12)],
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(color: TColors.slate100, borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                tab('flock', Icons.favorite_border, 'Flock'),
                tab('house', Icons.apartment, 'House'),
                tab('inventory', Icons.inventory_2_outlined, 'Inventory'),
              ]),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
              child: Row(children: [
                Expanded(
                  child: AppInput(
                    controller: _search,
                    hintText: 'Search...',
                    prefixIcon: const Icon(Icons.search, size: 18, color: TColors.slate400),
                    onChanged: (v) => setState(() {
                      _f.search = v;
                      _page = 1;
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(onPressed: _openFilters, icon: const Icon(Icons.filter_list, size: 16), label: const Text('Filters')),
              ]),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const TCard(child: Padding(padding: EdgeInsets.all(20), child: Text('Loading health records...', textAlign: TextAlign.center)))
            else if (rows.isEmpty)
              TCard(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  child: Column(children: [
                    Icon(tabIcon, size: 48, color: TColors.slate400),
                    const SizedBox(height: 14),
                    Text(copy.emptyTitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(copy.emptyDescription, textAlign: TextAlign.center, style: const TextStyle(color: TColors.slate600)),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: TColors.blue600),
                      onPressed: () => _openForm(),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(copy.addLabel),
                    ),
                  ]),
                ),
              )
            else
              TCard(
                title: copy.cardTitle,
                description: copy.cardDescription,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (!_table) ...[
                    // The web's phone cards list every filtered record; paging applies to the table.
                    for (var i = 0; i < rows.length; i++) ...[_card(rows[i], i), const SizedBox(height: 10)],
                    ViewTableButton(onPressed: () => setState(() => _table = true)),
                  ] else ...[
                    TableViewBar(text: 'Table • Scroll → for more', onCards: () => setState(() => _table = false)),
                    _tableView(pageSlice(rows, _page, _size)),
                  ],
                  CompactPager(total: rows.length, page: _page, pageSize: _size, onPage: (x) => setState(() => _page = x), onPageSize: (s) => setState(() {
                        _size = s;
                        _page = 1;
                      })),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String text, IconData icon, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: bg, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Flexible(child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: fg))),
        ]),
      );

  Widget _vaccination(Map r) => _pill(tStr(r['vaccination']), Icons.medication_outlined, const Color(0xFFEFF6FF), const Color(0xFF1D4ED8));
  Widget _medication(Map r) => _pill(tStr(r['medication']), Icons.favorite_border, const Color(0xFFF0FDF4), TColors.green700);

  Widget _card(Map r, int i) {
    final notes = tStr(r['notes']);
    return _HealthCard(
      key: ValueKey('health-${r['id']}-$i'),
      striped: i.isEven,
      header: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(r['recordDate'] != null ? trackerDate(r['recordDate']) : '—', style: const TextStyle(fontWeight: FontWeight.w600, color: TColors.slate900)),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 4, children: [
          TBadge(_entity(r), bg: Colors.white, fg: TColors.slate800, border: TColors.slate200),
          if (tStr(r['vaccination']).isNotEmpty) _vaccination(r),
          if (tStr(r['medication']).isNotEmpty) _medication(r),
        ]),
      ]),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (r['waterConsumption'] != null)
          Text.rich(TextSpan(children: [
            const TextSpan(text: 'Water ', style: TextStyle(color: TColors.slate500)),
            TextSpan(text: '${_jsNum(tNum(r['waterConsumption']))}L', style: const TextStyle(fontWeight: FontWeight.w500)),
          ]), style: const TextStyle(fontSize: 14)),
        if (notes.isNotEmpty)
          Text.rich(TextSpan(children: [
            const TextSpan(text: 'Notes ', style: TextStyle(color: TColors.slate500)),
            TextSpan(text: notes.length > 60 ? '${notes.substring(0, 60)}…' : notes, style: const TextStyle(fontWeight: FontWeight.w500)),
          ]), style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(backgroundColor: Colors.white, minimumSize: const Size.fromHeight(40)),
              onPressed: () => _openForm(r),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Edit'),
            ),
          ),
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
        ]),
      ]),
    );
  }

  /// The web's header sort: asc first, then flips — it never clears.
  void _toggle(String key) => setState(() {
        _sort = _sort.key == key ? (key: key, dir: _sort.dir == SortDir.asc ? SortDir.desc : SortDir.asc) : (key: key, dir: SortDir.asc);
      });

  Widget _tableView(List<Map> rows) {
    final entityKey = switch (_tab) { 'flock' => 'flock', 'house' => 'house', _ => 'item' };
    final entityLabel = switch (_tab) { 'flock' => 'Flock', 'house' => 'House', _ => 'Item' };
    return TrackerTable(
      sort: _sort,
      onSort: _toggle,
      columns: [
        const TCol('Date', sortKey: 'date', width: 110),
        TCol(entityLabel, sortKey: entityKey, width: 130),
        const TCol('Vaccination', width: 150),
        const TCol('Medication', width: 150),
        const TCol('Water (L)', width: 100),
        const TCol('Notes', width: 200),
        const TCol('Actions', width: 100),
      ],
      rows: [
        for (final r in rows)
          [
            cellText(r['recordDate'] != null ? trackerDate(r['recordDate']) : '-'),
            cellText(_entity(r)),
            tStr(r['vaccination']).isNotEmpty ? Align(alignment: Alignment.centerLeft, child: _vaccination(r)) : cellText('-', color: TColors.slate400),
            tStr(r['medication']).isNotEmpty ? Align(alignment: Alignment.centerLeft, child: _medication(r)) : cellText('-', color: TColors.slate400),
            r['waterConsumption'] != null
                ? Row(children: [
                    const Icon(Icons.water_drop_outlined, size: 16, color: Color(0xFF3B82F6)),
                    const SizedBox(width: 4),
                    Text('${_jsNum(tNum(r['waterConsumption']))}L'),
                  ])
                : cellText('-', color: TColors.slate400),
            cellText(
              tStr(r['notes']).isEmpty ? '-' : (tStr(r['notes']).length > 50 ? '${tStr(r['notes']).substring(0, 50)}...' : tStr(r['notes'])),
              color: TColors.slate600,
            ),
            Wrap(alignment: WrapAlignment.end, children: [
              IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _openForm(r)),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline, size: 18, color: TColors.red600),
                onPressed: () => _delete(r),
              ),
            ]),
          ],
      ],
    );
  }
}

class _HealthCard extends StatefulWidget {
  const _HealthCard({super.key, required this.striped, required this.header, required this.body});
  final bool striped;
  final Widget header, body;
  @override
  State<_HealthCard> createState() => _HealthCardState();
}

class _HealthCardState extends State<_HealthCard> {
  bool _open = true;
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: widget.striped ? TColors.amber100 : Colors.white,
          border: Border.all(color: widget.striped ? TColors.amber300 : TColors.slate200),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: widget.header),
              Icon(_open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: TColors.slate400),
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

/// Create / Edit Health Record. The tab decides which of flock, house or
/// item the record belongs to; the others are sent as null.
class HealthRecordDialog extends StatefulWidget {
  const HealthRecordDialog({
    super.key,
    required this.session,
    required this.company,
    required this.tab,
    required this.flocks,
    required this.houses,
    required this.items,
    this.editing,
    required this.onError,
  });
  final Session session;
  final Company company;
  final String tab;
  final List<Map> flocks, houses, items;
  final Map? editing;

  /// The web shows a failed save in the page's error banner.
  final ValueChanged<String> onError;
  @override
  State<HealthRecordDialog> createState() => _HealthRecordDialogState();
}

class _HealthRecordDialogState extends State<HealthRecordDialog> {
  late final Map? _e = widget.editing;
  late int? _flock = tIntOrNull(_e?['flockId']), _house = tIntOrNull(_e?['houseId']), _item = tIntOrNull(_e?['itemId']);
  late String _date = _e != null && tStr(_e['recordDate']).isNotEmpty
      ? tStr(_e['recordDate']).split('T').first
      : DateTime.now().toUtc().toIso8601String().substring(0, 10);
  late String _type = _e == null ? 'Vaccination' : parseTypeFromNotes(_e['notes']);
  late final _name = TextEditingController(text: tStr(_e?['vaccination']));
  late final _treatment = TextEditingController(text: tStr(_e?['medication']));
  late final _dosage = TextEditingController(text: _e?['waterConsumption'] == null ? '' : _jsNum(tNum(_e?['waterConsumption'])));
  late final _notes = TextEditingController(text: _e == null ? '' : stripTypePrefix(_e['notes']));
  bool _saving = false;

  String get _userId => widget.session.tokens.userId ?? '';

  @override
  void dispose() {
    for (final c in [_name, _treatment, _dosage, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final tab = widget.tab;
    final hasTarget = switch (tab) { 'flock' => (_flock ?? 0) != 0, 'house' => (_house ?? 0) != 0, _ => (_item ?? 0) != 0 };
    if (!hasTarget || _date.isEmpty) {
      final hint = switch (tab) { 'flock' => 'Choose a flock', 'house' => 'Choose a house', _ => 'Choose an inventory item' };
      trackerToast(context, 'Almost there', description: '$hint for this record, and pick the record date — both are needed before saving.');
      return;
    }
    final water = num.tryParse(_dosage.text);
    final body = <String, Object?>{
      'UserId': _userId,
      'FarmId': widget.company.farmId,
      'FlockId': tab == 'flock' ? _flock : null,
      'HouseId': tab == 'house' ? _house : null,
      'ItemId': tab == 'inventory' ? _item : null,
      'RecordDate': _date,
      'Vaccination': _name.text.isEmpty ? null : _name.text,
      'Medication': _treatment.text.isEmpty ? null : _treatment.text,
      'WaterConsumption': water == null || water == 0 ? null : water,
      'Notes': withTypePrefix(_type, _notes.text),
    };
    setState(() => _saving = true);
    try {
      final id = _e?['id'];
      if (id != null) {
        await widget.session.farmClient.put('/api/Health/$id', body: {'Id': id, ...body});
      } else {
        await widget.session.farmClient.post('/api/Health', body: body);
      }
      if (mounted) Navigator.pop(context, true);
      return;
    } on ApiException catch (ex) {
      widget.onError(ex.message.isNotEmpty ? ex.message : (_e != null ? 'Failed to update health record' : 'Failed to create health record'));
    }
    if (mounted) setState(() => _saving = false);
  }

  Widget _cell(String label, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate700)),
          const SizedBox(height: 6),
          child,
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final tab = widget.tab;
    final keep = tIntOrNull(_e?['flockId']);
    final openFlocks = [
      for (final f in widget.flocks)
        if (tStr(f['closedDate']).isEmpty || (keep != null && tIntOrNull(f['flockId']) == keep)) f,
    ];
    return AlertDialog(
      scrollable: true,
      title: Text(_e != null ? 'Edit Health Record' : 'Create Health Record'),
      content: SizedBox(
        width: 640,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            _e != null
                ? 'Update the health record information'
                : 'Record daily health information for your ${tab == 'flock' ? 'flocks' : tab == 'house' ? 'houses' : 'inventory items'}',
            style: const TextStyle(fontSize: 13, color: TColors.slate500),
          ),
          const SizedBox(height: 12),
          formSection('Record Details', TColors.blue600, [
            if (tab == 'flock')
              _cell(
                'Flock *',
                AppSelect<int>(
                  value: _flock == 0 ? null : _flock,
                  hintText: 'Select flock',
                  items: [for (final f in openFlocks) AppSelectItem(value: tIntOrNull(f['flockId']) ?? 0, label: tStr(f['name']))],
                  onChanged: (v) => setState(() {
                    _flock = v;
                    _house = null;
                    _item = null;
                  }),
                ),
              ),
            if (tab == 'house')
              _cell(
                'House *',
                AppSelect<int>(
                  value: _house == 0 ? null : _house,
                  hintText: 'Select house',
                  items: [for (final h in widget.houses) AppSelectItem(value: tIntOrNull(h['houseId']) ?? 0, label: tStr(h['name']))],
                  onChanged: (v) => setState(() {
                    _house = v;
                    _flock = null;
                    _item = null;
                  }),
                ),
              ),
            if (tab == 'inventory')
              _cell(
                'Inventory Item *',
                AppSelect<int>(
                  value: _item == 0 ? null : _item,
                  hintText: 'Select item',
                  items: [for (final i in widget.items) AppSelectItem(value: tIntOrNull(i['id']) ?? 0, label: tStr(i['name']))],
                  onChanged: (v) => setState(() {
                    _item = v;
                    _flock = null;
                    _house = null;
                  }),
                ),
              ),
            _cell('Date *', AppDateField(value: businessDateAsDateTime(_date), onChanged: (v) => setState(() => _date = v == null ? '' : isoDay(v)))),
            _cell(
              'Type *',
              AppSelect<String>(
                value: _type,
                hintText: 'Select type',
                items: [for (final t in healthRecordTypes) AppSelectItem(value: t, label: t)],
                onChanged: (v) => setState(() => _type = v ?? _type),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          formSection('Treatment Details', const Color(0xFF16A34A), [
            _cell('Name', AppInput(controller: _name, hintText: 'Medication/vaccine name')),
            _cell('Treatment', AppInput(controller: _treatment, hintText: 'Disease or condition treated')),
            _cell(
              'Dosage',
              AppInput(
                controller: _dosage,
                hintText: 'e.g., 1ml per bird',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              ),
            ),
          ]),
          const SizedBox(height: 12),
          _cell('Notes', AppInput(controller: _notes, minLines: 3, maxLines: 5, hintText: 'Additional notes about health status')),
        ]),
      ),
      actions: [
        redCancelButton(_saving ? null : () => Navigator.pop(context, false)),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_e != null ? 'Update Record' : 'Create Record')),
      ],
    );
  }
}
