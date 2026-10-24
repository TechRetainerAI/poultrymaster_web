// Restaurant → Dining → Restaurant Areas, as `app/restaurant-floor-plan/page.tsx`:
// Add Area / Add Table, the status legend with its counts, a tab per area
// (edit and delete beside the open one), the table cards with their quick
// Free / Reserve / Clean actions, and the area and table dialogs.

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/sales/balances_widgets.dart' show LoadingLine;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr;
import '../poultry/trackers/tracker_widgets.dart';
import 'restaurant_money_kit.dart' show rField, rNumberInput, rDialog, rConfirm, rCancel;
import 'restaurant_roles.dart' show restaurantRose;
import 'restaurant_widgets.dart';

/// STATUS_CONFIG: text, background, border, label.
const tableStatusConfig = <String, (Color, Color, Color, String)>{
  'Available': (Color(0xFF15803D), Color(0xFFF0FDF4), Color(0xFF86EFAC), 'Available'),
  'Occupied': (Color(0xFFB91C1C), Color(0xFFFEF2F2), Color(0xFFFCA5A5), 'Occupied'),
  'Reserved': (Color(0xFF1D4ED8), Color(0xFFEFF6FF), Color(0xFF93C5FD), 'Reserved'),
  'NeedsCleaning': (Color(0xFFB45309), Color(0xFFFFFBEB), Color(0xFFFCD34D), 'Needs Cleaning'),
  'OutOfService': (Color(0xFF374151), Color(0xFFF3F4F6), Color(0xFFD1D5DB), 'Out of Service'),
};
const tableShapes = ['Square', 'Round', 'Booth', 'Bar', 'Long'];

class RestaurantFloorPlanScreen extends StatefulWidget {
  const RestaurantFloorPlanScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<RestaurantFloorPlanScreen> createState() => _RestaurantFloorPlanScreenState();
}

class _RestaurantFloorPlanScreenState extends State<RestaurantFloorPlanScreen> {
  bool _loading = true;
  List<Map> _floors = [];
  List<Map> _tables = [];
  int? _activeFloor;

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  Map<String, dynamic> get _q => {'farmId': _farmId};

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  List<Map> _rows(Object? v) => [for (final x in (v is List ? v : const [])) if (x is Map) x];
  int _id(Object? v) => tNum(v).toInt();

  Future<List<Map>> _listFloors() async => _rows(await _api.get('/api/Restaurant/floor/floors', query: _q));
  Future<List<Map>> _listTables() async => _rows(await _api.get('/api/Restaurant/floor/tables', query: {..._q, '_': 1}));

  void _toast(String title, {String? description, bool error = false}) {
    if (mounted) trackerToast(context, title, description: description, error: error);
  }

  String _err(Object e) => e is ApiException ? e.message : '$e';

  Future<void> _loadAll() async {
    try {
      final r = await Future.wait([_listFloors(), _listTables()]);
      _floors = r[0];
      _tables = r[1];
      if (_floors.isNotEmpty && _activeFloor == null) _activeFloor = _id(_floors.first['floorId']);
    } catch (e) {
      _toast('Failed', description: _err(e), error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openFloor([Map? f]) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _FloorDialog(api: _api, farmId: _farmId, floors: _floors, editing: f));
    if (ok != true) return;
    _floors = await _listFloors();
    if (_activeFloor == null && _floors.isNotEmpty) _activeFloor = _id(_floors.first['floorId']);
    if (mounted) setState(() {});
  }

  Future<void> _removeFloor(Map f) async {
    try {
      await _api.delete('/api/Restaurant/floor/floors/${f['floorId']}', query: _q);
      _toast('Deleted');
      _floors = await _listFloors();
      if (mounted) setState(() {});
    } catch (e) {
      _toast('Failed', description: _err(e), error: true);
    }
  }

  Future<void> _openTable([Map? t]) async {
    final ok = await showDialog<bool>(
        context: context, builder: (_) => _TableDialog(api: _api, farmId: _farmId, floors: _floors, activeFloor: _activeFloor, editing: t));
    if (ok != true) return;
    _tables = await _listTables();
    if (mounted) setState(() {});
  }

  Future<void> _removeTable(Map t) async {
    try {
      await _api.delete('/api/Restaurant/floor/tables/${t['tableId']}', query: _q);
      _toast('Deleted');
      _tables = await _listTables();
      if (mounted) setState(() {});
    } catch (e) {
      _toast('Failed', description: _err(e), error: true);
    }
  }

  Future<void> _status(Map t, String status) async {
    try {
      await _api.patch('/api/Restaurant/floor/tables/${t['tableId']}/status', query: {..._q, 'status': status});
      _tables = await _listTables();
      if (mounted) setState(() {});
    } catch (e) {
      _toast('Failed', description: _err(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/restaurant-floor-plan');
    final floorTables = [for (final t in _tables) if (_activeFloor == null || _id(t['floorId']) == _activeFloor) t];
    final active = _activeFloor ?? (_floors.isEmpty ? null : _id(_floors.first['floorId']));
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Restaurant Areas')),
      body: _loading
          ? const Padding(padding: EdgeInsets.all(20), child: LoadingLine('Loading…'))
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
                RPageHeader(
                  icon: Icons.place_outlined,
                  title: 'Restaurant Areas',
                  subtitle: 'Manage your dining areas and table layout. ${_tables.length} tables across ${_floors.length} areas.',
                  actions: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                      onPressed: () => _openFloor(),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Area'),
                    ),
                    roseButton('Add Table', () => _openTable()),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(spacing: 14, runSpacing: 6, children: [
                  for (final e in tableStatusConfig.entries)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(color: e.value.$2, border: Border.all(color: e.value.$3), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(text: '${e.value.$4}: '),
                          TextSpan(
                              text: '${_tables.where((t) => tStr(t['status']) == e.key).length}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        ]),
                        style: const TextStyle(fontSize: 13, color: TColors.slate500),
                      ),
                    ]),
                ]),
                if (_floors.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  RTabs(
                    value: '$active',
                    onChanged: (v) => setState(() => _activeFloor = int.tryParse(v)),
                    tabs: [
                      for (final f in _floors)
                        ('${_id(f['floorId'])}', Icons.layers_outlined, tStr(f['name']), rBadge('${tNum(f['tableCount']).toInt()}')),
                    ],
                  ),
                  for (final f in _floors)
                    if (_id(f['floorId']) == _activeFloor)
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        IconButton(tooltip: 'Edit area', onPressed: () => _openFloor(f), icon: const Icon(Icons.edit_outlined, size: 16)),
                        IconButton(
                            tooltip: 'Delete area', onPressed: () => _removeFloor(f), icon: const Icon(Icons.delete_outline, size: 16, color: Color(0xFFEF4444))),
                      ]),
                ],
                const SizedBox(height: 14),
                TCard(
                  child: floorTables.isEmpty
                      ? REmptyState(
                          icon: Icons.place_outlined,
                          title: _floors.isEmpty ? 'No areas created yet' : 'No tables on this floor',
                          description: _floors.isEmpty ? 'Create areas like Ground Floor, Patio, Rooftop first' : 'Add tables to this area',
                          actionLabel: _floors.isEmpty ? 'Create first area' : 'Add first table',
                          onAction: () => _floors.isEmpty ? _openFloor() : _openTable(),
                        )
                      : twoColumns([for (final t in floorTables) _tableCard(t)], gap: 12),
                ),
              ]),
            ),
    );
  }

  Widget _tableCard(Map t) {
    final status = tStr(t['status']);
    final (fg, bg, border, label) = tableStatusConfig[status] ?? tableStatusConfig['Available']!;
    Widget quick(String text, Color color, VoidCallback onTap, {IconData? icon}) => TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: color, visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
          onPressed: onTap,
          icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 13),
          label: Text(text, style: const TextStyle(fontSize: 12)),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 10),
      decoration: BoxDecoration(color: bg, border: Border.all(color: border, width: 2), borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          IconButton(
            tooltip: 'Edit table',
            visualDensity: VisualDensity.compact,
            onPressed: () => _openTable(t),
            icon: const Icon(Icons.edit_outlined, size: 14),
          ),
          IconButton(
            tooltip: 'Delete table',
            visualDensity: VisualDensity.compact,
            onPressed: () => _removeTable(t),
            icon: const Icon(Icons.delete_outline, size: 14, color: Color(0xFFEF4444)),
          ),
        ]),
        Text(tStr(t['tableNumber']), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
        if (tStr(t['tableName']).isNotEmpty)
          Text(tStr(t['tableName']), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.people_outline, size: 14, color: TColors.slate500),
          const SizedBox(width: 4),
          Text('${tNum(t['capacity']).toInt()}', style: const TextStyle(fontSize: 13, color: TColors.slate500)),
        ]),
        const SizedBox(height: 6),
        rBadge(tStr(t['shape']), bg: Colors.white, border: TColors.slate200),
        const SizedBox(height: 6),
        rBadge(label, bg: bg, fg: fg, border: border),
        const SizedBox(height: 6),
        Wrap(alignment: WrapAlignment.center, children: [
          if (status != 'Available') quick('Free', const Color(0xFF15803D), () => _status(t, 'Available')),
          if (status != 'Reserved' && status != 'Occupied') quick('Reserve', const Color(0xFF1D4ED8), () => _status(t, 'Reserved')),
          if (status == 'NeedsCleaning') quick('Clean', const Color(0xFF15803D), () => _status(t, 'Available'), icon: Icons.check_circle_outline),
        ]),
      ]),
    );
  }
}

/// Add / Edit Area.
class _FloorDialog extends StatefulWidget {
  const _FloorDialog({required this.api, required this.farmId, required this.floors, this.editing});
  final ApiClient api;
  final String farmId;
  final List<Map> floors;
  final Map? editing;
  @override
  State<_FloorDialog> createState() => _FloorDialogState();
}

class _FloorDialogState extends State<_FloorDialog> {
  late final _name = TextEditingController(text: tStr(widget.editing?['name']));
  late final _desc = TextEditingController(text: tStr(widget.editing?['description']));

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text;
    if (name.trim().isEmpty) {
      trackerToast(context, 'Name required', error: true);
      return;
    }
    final e = widget.editing;
    final dup = widget.floors.any((f) =>
        tStr(f['name']).toLowerCase() == name.trim().toLowerCase() && (e == null || tNum(f['floorId']) != tNum(e['floorId'])));
    if (dup) {
      trackerToast(context, 'Duplicate name', description: 'An area named "$name" already exists.', error: true);
      return;
    }
    final body = {
      'name': name,
      'floorNumber': e == null ? widget.floors.length : e['floorNumber'],
      if (e != null || _desc.text.isNotEmpty) 'description': _desc.text,
      'isActive': e == null ? true : e['isActive'],
      'farmId': widget.farmId,
    };
    try {
      if (e != null) {
        await widget.api.put('/api/Restaurant/floor/floors/${e['floorId']}', body: body);
      } else {
        await widget.api.post('/api/Restaurant/floor/floors', body: body);
      }
      if (!mounted) return;
      trackerToast(context, e != null ? 'Updated' : 'Created');
      Navigator.pop(context, true);
    } catch (err) {
      if (mounted) trackerToast(context, 'Failed', description: err is ApiException ? err.message : '$err', error: true);
    }
  }

  @override
  Widget build(BuildContext context) => rDialog(
        title: widget.editing != null ? 'Edit Area' : 'Add Area',
        description: 'Create a section of your restaurant (e.g. Ground Floor, Patio)',
        children: [
          rField('Area Name', AppInput(controller: _name, hintText: 'e.g. Ground Floor, Rooftop'), required: true),
          rField('Description', AppInput(controller: _desc, hintText: 'Optional description')),
        ],
        actions: [rCancel(context, 'Cancel'), rConfirm(widget.editing != null ? 'Update' : 'Create Area', _save)],
      );
}

/// Add / Edit Table.
class _TableDialog extends StatefulWidget {
  const _TableDialog({required this.api, required this.farmId, required this.floors, required this.activeFloor, this.editing});
  final ApiClient api;
  final String farmId;
  final List<Map> floors;
  final int? activeFloor;
  final Map? editing;
  @override
  State<_TableDialog> createState() => _TableDialogState();
}

class _TableDialogState extends State<_TableDialog> {
  late final _number = TextEditingController(text: tStr(widget.editing?['tableNumber']));
  late final _name = TextEditingController(text: tStr(widget.editing?['tableName']));
  late final _capacity = TextEditingController(text: '${widget.editing == null ? 4 : tNum(widget.editing!['capacity']).toInt()}');
  late String _shape = tStr(widget.editing?['shape']).isEmpty ? 'Square' : tStr(widget.editing?['shape']);
  late int? _floor = widget.editing == null ? widget.activeFloor : (widget.editing!['floorId'] == null ? null : tNum(widget.editing!['floorId']).toInt());

  @override
  void dispose() {
    for (final c in [_number, _name, _capacity]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_number.text.trim().isEmpty) {
      trackerToast(context, 'Number required', error: true);
      return;
    }
    final e = widget.editing;
    final cap = int.tryParse(RegExp(r'^\s*(\d+)').firstMatch(_capacity.text)?.group(1) ?? '') ?? 0;
    final body = {
      'floorId': _floor,
      'tableNumber': _number.text,
      if (e != null || _name.text.isNotEmpty) 'tableName': _name.text,
      'capacity': cap == 0 ? 4 : cap,
      'shape': _shape,
      'isActive': e == null ? true : e['isActive'],
      'farmId': widget.farmId,
    };
    try {
      if (e != null) {
        await widget.api.put('/api/Restaurant/floor/tables/${e['tableId']}', body: body);
      } else {
        await widget.api.post('/api/Restaurant/floor/tables', body: body);
      }
      if (!mounted) return;
      trackerToast(context, e != null ? 'Updated' : 'Created');
      Navigator.pop(context, true);
    } catch (err) {
      if (mounted) trackerToast(context, 'Failed', description: err is ApiException ? err.message : '$err', error: true);
    }
  }

  @override
  Widget build(BuildContext context) => rDialog(
        title: widget.editing != null ? 'Edit Table' : 'Add Table',
        description: 'Configure table number, capacity and type',
        children: [
          rField('Table Number', AppInput(controller: _number, hintText: 'e.g. 1, A1'), required: true),
          rField('Display Name', AppInput(controller: _name, hintText: 'e.g. Window Seat')),
          rField('Capacity', rNumberInput(_capacity)),
          rField(
            'Shape',
            AppSelect<String>(
              value: _shape,
              items: [for (final s in tableShapes) AppSelectItem(value: s, label: s)],
              onChanged: (v) => setState(() => _shape = v ?? 'Square'),
            ),
          ),
          rField(
            'Area',
            AppSelect<int>(
              value: _floor ?? -1,
              items: [
                const AppSelectItem(value: -1, label: 'Unassigned'),
                for (final f in widget.floors) AppSelectItem(value: tNum(f['floorId']).toInt(), label: tStr(f['name'])),
              ],
              onChanged: (v) => setState(() => _floor = v == null || v == -1 ? null : v),
            ),
          ),
        ],
        actions: [rCancel(context, 'Cancel'), rConfirm(widget.editing != null ? 'Update' : 'Add Table', _save, color: restaurantRose)],
      );
}
