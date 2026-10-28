// Hotel → Operations → Rooms & Housekeeping: Rooms (`app/hotel-rooms`, the
// Room Inventory with RoomGrid and RoomStatusBadge), Housekeeping
// (`app/hotel-housekeeping`), HK Schedule (`app/hotel-housekeeping-schedule`)
// and Room Service (`app/hotel-room-service`). Amounts print as plain "0.00",
// as the web's toFixed(2).
// API: /Hotel/rooms (+ /{id}, /{id}/status, /status-summary), /Hotel/setup/
// room-types, /floors, /hk-task-types, /Hotel/housekeeping (+ /{id}/status),
// /Hotel/housekeeping-schedule (+ /bulk, /{id}/status), /Hotel/staff,
// /Hotel/restaurant/orders.

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/money/money_widgets.dart' show MobileCardList, twoUp;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart';
import 'hotel_kit.dart';
import 'hotel_other_select.dart';

Object? _v(Map m, String k) => m[k] ?? m[k.toLowerCase()];
String _dash(Object? v) => tStr(v).isEmpty ? '—' : tStr(v);
String _money(Object? v) => tNum(v).toStringAsFixed(2);

const roomStatuses = ['Available', 'Occupied', 'Reserved', 'Cleaning', 'Maintenance'];

/// RoomStatusBadge (bg, fg) and RoomGrid's tile (bg, border).
const _roomBadge = {
  'Available': (Color(0xFFD1FAE5), Color(0xFF047857)),
  'Occupied': (TColors.violet100, TColors.violet700),
  'Maintenance': (Color(0xFFFEF3C7), Color(0xFFB45309)),
  'Reserved': (Color(0xFFDBEAFE), Color(0xFF1D4ED8)),
  'Cleaning': (Color(0xFFFFEDD5), Color(0xFFC2410C)),
};
const _roomTile = {
  'Available': (Color(0xFFECFDF5), Color(0xFFA7F3D0)),
  'Occupied': (TColors.violet50, TColors.violet200),
  'Maintenance': (Color(0xFFFFFBEB), Color(0xFFFDE68A)),
  'Reserved': (Color(0xFFEFF6FF), Color(0xFFBFDBFE)),
  'Cleaning': (Color(0xFFFFF7ED), Color(0xFFFED7AA)),
};

Widget roomStatusBadge(Object? status) {
  final (bg, fg) = _roomBadge[tStr(status)] ?? (TColors.slate100, TColors.slate700);
  return hotelBadge(tStr(status), bg, fg);
}

Widget _title(IconData icon, String title, {String? count}) => Row(children: [
      Icon(icon, size: 24, color: hotelViolet),
      const SizedBox(width: 10),
      Flexible(child: Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: TColors.slate900))),
      if (count != null) ...[const SizedBox(width: 6), Text(count, style: const TextStyle(fontSize: 13, color: TColors.slate500))],
    ]);

Widget _loadingBox() => const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: CircularProgressIndicator(color: hotelViolet)));

Widget _numberCard(String label, String value, Color color, {VoidCallback? onTap, Color? border}) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: border ?? TColors.slate200), borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color))),
          Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
        ]),
      ),
    );

/// The Rooms filters: status, floor number, room type and the search.
List<Map> filterRooms(List<Map> rooms, {String status = 'all', String floor = 'all', String type = 'all', String search = ''}) {
  final q = search.toLowerCase();
  return [
    for (final r in rooms)
      if ((status == 'all' || tStr(r['status']) == status) &&
          (floor == 'all' || '${tIntOrNull(_v(r, 'floorNumber')) ?? 0}' == floor) &&
          (type == 'all' || tStr(_v(r, 'hotelRoomTypeId')) == type) &&
          (q.isEmpty || tStr(_v(r, 'roomNumber')).toLowerCase().contains(q) || tStr(_v(r, 'roomTypeName')).toLowerCase().contains(q)))
        r,
  ];
}

/// "101" before "1010", "9" before "10": localeCompare with numeric: true.
int _numeric(String a, String b) {
  final re = RegExp(r'(\d+)|(\D+)');
  final x = re.allMatches(a).map((m) => m[0]!).toList(), y = re.allMatches(b).map((m) => m[0]!).toList();
  for (var i = 0; i < x.length && i < y.length; i++) {
    final nx = int.tryParse(x[i]), ny = int.tryParse(y[i]);
    final c = nx != null && ny != null ? nx.compareTo(ny) : x[i].toLowerCase().compareTo(y[i].toLowerCase());
    if (c != 0) return c;
  }
  return x.length.compareTo(y.length);
}

// ======================================================================== Rooms

class HotelRoomsScreen extends StatefulWidget {
  const HotelRoomsScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<HotelRoomsScreen> createState() => _HotelRoomsScreenState();
}

class _HotelRoomsScreenState extends State<HotelRoomsScreen> {
  List<Map> _rooms = [], _types = [], _floors = [], _summary = [];
  bool _loading = true;
  String _view = 'grid', _status = 'all', _floor = 'all', _type = 'all';
  final _q = TextEditingController();

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final q = {'farmId': _farmId};
    try {
      final r = await Future.wait([
        _api.get('/api/Hotel/rooms', query: q),
        _api.get('/api/Hotel/setup/room-types', query: q),
        _api.get('/api/Hotel/setup/floors', query: q),
        _api.get('/api/Hotel/rooms/status-summary', query: q),
      ]);
      if (!mounted) return;
      setState(() {
        _rooms = hotelRows(r[0]);
        _types = hotelRows(r[1]);
        _floors = hotelRows(r[2]);
        _summary = hotelRows(r[3]);
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed to load rooms', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  int _count(String s) => tIntOrNull(_summary.where((x) => tStr(_v(x, 'status')) == s).firstOrNull?['roomCount']) ?? 0;

  Future<void> _form([Map? editing]) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _RoomDialog(session: widget.session, company: widget.company, editing: editing, types: _types, floors: _floors),
    );
    if (done == true) _load();
  }

  Future<void> _delete(Map room) async {
    final no = tStr(_v(room, 'roomNumber'));
    final ok = await hotelConfirmDelete(
      context,
      title: 'Delete room $no?',
      message: 'Delete room $no?',
      onConfirm: () => _api.delete('/api/Hotel/rooms/${tStr(_v(room, 'hotelRoomId'))}', query: {'farmId': _farmId}),
    );
    if (!ok || !mounted) return;
    trackerToast(context, 'Room deleted');
    _load();
  }

  Future<void> _setStatus(Map room, String status) async {
    try {
      await _api.patch('/api/Hotel/rooms/${tStr(_v(room, 'hotelRoomId'))}/status', query: {'farmId': _farmId}, body: {'status': status});
      if (mounted) trackerToast(context, 'Room ${tStr(_v(room, 'roomNumber'))} → $status');
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
  }

  Future<void> _detail(Map room) => showDialog<void>(
        context: context,
        builder: (ctx) {
          Widget line(String k, Object? v) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '$k: ', style: const TextStyle(color: TColors.slate500)),
                  TextSpan(text: _dash(v), style: const TextStyle(fontWeight: FontWeight.w700)),
                ]), style: const TextStyle(fontSize: 14)),
              );
          return AlertDialog(
            scrollable: true,
            title: Text('Room ${tStr(_v(room, 'roomNumber'))}'),
            content: SizedBox(
              width: 420,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 4, children: [
                  roomStatusBadge(room['status']),
                  Text('${_money(_v(room, 'baseRate'))}/night', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: TColors.violet700)),
                ]),
                const SizedBox(height: 12),
                line('Type', _v(room, 'roomTypeName')),
                line('Floor', _v(room, 'floorName')),
                line('Bed', _v(room, 'bedType')),
                line('Max Guests', _v(room, 'maxOccupancy')),
                if (tStr(room['description']).isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 4), child: Text(tStr(room['description']), style: const TextStyle(fontSize: 13, color: TColors.slate500))),
                const Divider(height: 24),
                const Text('CHANGE STATUS', style: TextStyle(fontSize: 12, color: TColors.slate500)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final s in roomStatuses)
                    if (s != tStr(room['status']))
                      OutlinedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _setStatus(room, s);
                        },
                        child: Text(s),
                      ),
                ]),
                const Divider(height: 24),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _form(room);
                      },
                      child: const Text('Edit Room'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: TColors.red600),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _delete(room);
                      },
                      child: const Text('Delete'),
                    ),
                  ),
                ]),
              ]),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
          );
        },
      );

  /// RoomGrid: the rooms by floor, numbers in order.
  Widget _grid(List<Map> rooms) {
    if (rooms.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Text('No rooms found. Add rooms in Hotel Setup.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate400)),
      );
    }
    final floors = {for (final r in rooms) tIntOrNull(_v(r, 'floorNumber')) ?? 0}.toList()..sort();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final f in floors) ...[
        () {
          final list = [for (final r in rooms) if ((tIntOrNull(_v(r, 'floorNumber')) ?? 0) == f) r]
            ..sort((a, b) => _numeric(tStr(_v(a, 'roomNumber')), tStr(_v(b, 'roomNumber'))));
          final name = tStr(_v(list.first, 'floorName')).isEmpty ? 'Floor $f' : tStr(_v(list.first, 'floorName'));
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: TColors.slate600)),
            const SizedBox(height: 8),
            twoUp([
              for (final r in list)
                () {
                  final (bg, border) = _roomTile[tStr(r['status'])] ?? (TColors.slate50, TColors.slate200);
                  return InkWell(
                    onTap: () => _detail(r),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(8)),
                      child: Column(children: [
                        Text(tStr(_v(r, 'roomNumber')), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                        Text(tStr(_v(r, 'roomTypeName')), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                        const SizedBox(height: 4),
                        roomStatusBadge(r['status']),
                      ]),
                    ),
                  );
                }(),
            ]),
            const SizedBox(height: 18),
          ]);
        }(),
      ],
    ]);
  }

  Widget _list(List<Map> rooms) {
    if (rooms.isEmpty) {
      return TCard(
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 28),
          child: Text('No rooms match the filters.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate400)),
        ),
      );
    }
    return MobileCardList<Map>(
      striped: true,
      items: rooms,
      keyOf: (r) => tStr(_v(r, 'hotelRoomId')),
      primary: (r) => 'Room ${tStr(_v(r, 'roomNumber'))}',
      onPrimary: _detail,
      secondary: (r) => '${tStr(_v(r, 'roomTypeName'))} · ${_dash(_v(r, 'floorName'))}',
      trailing: (r) => roomStatusBadge(r['status']),
      details: (r) => [('Bed', _dash(_v(r, 'bedType'))), ('Max Guests', _dash(_v(r, 'maxOccupancy'))), ('Rate', _money(_v(r, 'baseRate')))],
      actions: (r) => [
        TextButton(onPressed: () => _form(r), child: const Text('Edit')),
        TextButton(style: TextButton.styleFrom(foregroundColor: TColors.red600), onPressed: () => _delete(r), child: const Text('Delete')),
      ],
      table: (items) => TrackerTable(
        columns: const [
          TCol('Room', width: 80),
          TCol('Type', width: 120),
          TCol('Floor', width: 100),
          TCol('Bed', width: 90),
          TCol('Max Guests', width: 90),
          TCol('Rate', right: true, width: 90),
          TCol('Status', width: 110),
          TCol('Actions', right: true, width: 140),
        ],
        rows: [
          for (final r in items)
            [
              InkWell(onTap: () => _detail(r), child: Text(tStr(_v(r, 'roomNumber')), style: const TextStyle(fontWeight: FontWeight.w700, color: TColors.violet700))),
              cellText(tStr(_v(r, 'roomTypeName'))),
              cellText(_dash(_v(r, 'floorName'))),
              cellText(_dash(_v(r, 'bedType'))),
              cellText(_dash(_v(r, 'maxOccupancy'))),
              cellText(_money(_v(r, 'baseRate')), bold: true),
              Align(alignment: Alignment.centerLeft, child: roomStatusBadge(r['status'])),
              Wrap(alignment: WrapAlignment.end, children: [
                TextButton(onPressed: () => _form(r), child: const Text('Edit')),
                TextButton(style: TextButton.styleFrom(foregroundColor: TColors.red600), onPressed: () => _delete(r), child: const Text('Delete')),
              ]),
            ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/hotel-rooms');
    final filtered = filterRooms(_rooms, status: _status, floor: _floor, type: _type, search: _q.text);
    final rate = _rooms.isEmpty ? 0 : (_count('Occupied') / _rooms.length * 100).round();
    Widget viewButton(String v, IconData icon) => _view == v
        ? IconButton.filled(style: IconButton.styleFrom(backgroundColor: hotelViolet), tooltip: v == 'grid' ? 'Grid' : 'List', onPressed: () {}, icon: Icon(icon, size: 18))
        : IconButton.outlined(tooltip: v == 'grid' ? 'Grid' : 'List', onPressed: () => setState(() => _view = v), icon: Icon(icon, size: 18));
    return Scaffold(
      backgroundColor: TColors.slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Room Inventory')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
          _title(Icons.apartment, 'Room Inventory'),
          const SizedBox(height: 10),
          Row(children: [
            viewButton('grid', Icons.grid_view),
            const SizedBox(width: 6),
            viewButton('list', Icons.view_list),
            const SizedBox(width: 8),
            Expanded(child: hotelAddButton('Add Room', () => _form())),
          ]),
          const SizedBox(height: 12),
          twoUp([
            _numberCard('Total', '${_rooms.length}', TColors.violet700, onTap: () => setState(() => _status = 'all')),
            _numberCard('Available', '${_count('Available')}', const Color(0xFF047857), border: const Color(0xFFA7F3D0), onTap: () => setState(() => _status = 'Available')),
            _numberCard('Occupied', '${_count('Occupied')}', TColors.violet700, border: TColors.violet200, onTap: () => setState(() => _status = 'Occupied')),
            _numberCard('Reserved', '${_count('Reserved')}', const Color(0xFF1D4ED8), border: const Color(0xFFBFDBFE), onTap: () => setState(() => _status = 'Reserved')),
            _numberCard('Cleaning', '${_count('Cleaning')}', const Color(0xFFC2410C), border: const Color(0xFFFED7AA), onTap: () => setState(() => _status = 'Cleaning')),
            _numberCard('Maintenance', '${_count('Maintenance')}', const Color(0xFFB45309), border: const Color(0xFFFDE68A), onTap: () => setState(() => _status = 'Maintenance')),
          ]),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const Expanded(child: Text('Occupancy Rate', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate700))),
                Text('$rate%', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: TColors.violet700)),
              ]),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(value: rate / 100, minHeight: 12, color: hotelViolet, backgroundColor: TColors.slate200),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          AppInput(controller: _q, hintText: 'Search room number...', onChanged: (_) => setState(() {})),
          const SizedBox(height: 8),
          AppSelect<String>(
            value: _status,
            items: [const AppSelectItem(value: 'all', label: 'All statuses'), for (final s in roomStatuses) AppSelectItem(value: s, label: s)],
            onChanged: (v) => setState(() => _status = v ?? 'all'),
          ),
          const SizedBox(height: 8),
          AppSelect<String>(
            value: _floor,
            items: [
              const AppSelectItem(value: 'all', label: 'All floors'),
              for (final f in _floors) AppSelectItem(value: tStr(_v(f, 'floorNumber')), label: tStr(f['name'])),
            ],
            onChanged: (v) => setState(() => _floor = v ?? 'all'),
          ),
          const SizedBox(height: 8),
          AppSelect<String>(
            value: _type,
            items: [
              const AppSelectItem(value: 'all', label: 'All types'),
              for (final t in _types) AppSelectItem(value: tStr(_v(t, 'hotelRoomTypeId')), label: tStr(t['name'])),
            ],
            onChanged: (v) => setState(() => _type = v ?? 'all'),
          ),
          const SizedBox(height: 6),
          Text('${filtered.length} room(s)', style: const TextStyle(fontSize: 13, color: TColors.slate400)),
          const SizedBox(height: 12),
          if (_loading) _loadingBox() else if (_view == 'grid') _grid(filtered) else _list(filtered),
        ]),
      ),
    );
  }
}

class _RoomDialog extends StatefulWidget {
  const _RoomDialog({required this.session, required this.company, required this.editing, required this.types, required this.floors});
  final Session session;
  final Company company;
  final Map? editing;
  final List<Map> types, floors;

  @override
  State<_RoomDialog> createState() => _RoomDialogState();
}

class _RoomDialogState extends State<_RoomDialog> {
  late final Map? e = widget.editing;
  late final _number = TextEditingController(text: tStr(e == null ? null : _v(e!, 'roomNumber')));
  late final _desc = TextEditingController(text: tStr(e?['description']));
  late int _type = e != null
      ? tIntOrNull(_v(e!, 'hotelRoomTypeId')) ?? 0
      : (widget.types.isEmpty ? 0 : tIntOrNull(_v(widget.types.first, 'hotelRoomTypeId')) ?? 0);
  late int? _floor = e != null ? tIntOrNull(_v(e!, 'hotelFloorId')) : (widget.floors.isEmpty ? null : tIntOrNull(_v(widget.floors.first, 'hotelFloorId')));
  bool _saving = false;

  @override
  void dispose() {
    _number.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_number.text.trim().isEmpty) return trackerToast(context, 'Room number is required', error: true);
    setState(() => _saving = true);
    final body = {
      'farmId': widget.company.farmId,
      'roomNumber': _number.text,
      'hotelRoomTypeId': _type,
      'hotelFloorId': _floor,
      'description': _desc.text,
      'isActive': e == null ? true : _v(e!, 'isActive') != false,
    };
    try {
      final api = widget.session.farmClient;
      if (e != null) {
        await api.put('/api/Hotel/rooms/${tStr(_v(e!, 'hotelRoomId'))}', body: body);
        if (mounted) trackerToast(context, 'Room updated');
      } else {
        await api.post('/api/Hotel/rooms', body: body);
        if (mounted) trackerToast(context, 'Room created');
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (x) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Save failed', description: x.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => HotelDialog(
        icon: Icons.meeting_room_outlined,
        title: e != null ? 'Edit Room ${tStr(_v(e!, 'roomNumber'))}' : 'Add Room',
        saveLabel: e != null ? 'Update' : 'Create',
        saving: _saving,
        onSave: _save,
        children: [
          FilterLabel('Room Number *', AppInput(controller: _number, hintText: 'e.g. 101, A1')),
          FilterLabel(
            'Room Type *',
            AppSelect<int>(
              value: _type == 0 ? null : _type,
              items: [
                for (final t in widget.types)
                  AppSelectItem(
                    value: tIntOrNull(_v(t, 'hotelRoomTypeId')) ?? 0,
                    label: '${tStr(t['name'])} — ${tStr(_v(t, 'baseRate'))} (${tStr(_v(t, 'bedType')).isEmpty ? 'Standard' : tStr(_v(t, 'bedType'))})',
                  ),
              ],
              onChanged: (v) => setState(() => _type = v ?? 0),
            ),
          ),
          FilterLabel(
            'Floor',
            AppSelect<int>(
              value: _floor,
              hintText: 'Select floor',
              items: [
                for (final f in widget.floors)
                  AppSelectItem(value: tIntOrNull(_v(f, 'hotelFloorId')) ?? 0, label: '${tStr(f['name'])} (Floor ${tStr(_v(f, 'floorNumber'))})'),
              ],
              onChanged: (v) => setState(() => _floor = v),
            ),
          ),
          FilterLabel('Description', AppInput(controller: _desc, hintText: 'Corner room, ocean view, etc.')),
        ],
      );
}

// ================================================================ Housekeeping

const housekeepingStatuses = ['Pending', 'InProgress', 'Completed', 'Inspected'];
const _hkPriority = {
  'Low': (TColors.slate100, TColors.slate700),
  'Normal': (Color(0xFFDBEAFE), Color(0xFF1D4ED8)),
  'High': (Color(0xFFFEF3C7), Color(0xFFB45309)),
  'Urgent': (Color(0xFFFEE2E2), Color(0xFFB91C1C)),
};

class HotelHousekeepingScreen extends StatefulWidget {
  const HotelHousekeepingScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<HotelHousekeepingScreen> createState() => _HotelHousekeepingScreenState();
}

class _HotelHousekeepingScreenState extends State<HotelHousekeepingScreen> {
  List<Map> _tasks = [];
  bool _loading = true;
  String _filter = 'all';

  ApiClient get _api => widget.session.farmClient;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = hotelRows(await _api.get('/api/Hotel/housekeeping', query: {'farmId': widget.company.farmId}));
      if (mounted) setState(() => _tasks = r);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _change(Map t, String status) async {
    try {
      await _api.patch('/api/Hotel/housekeeping/${tStr(_v(t, 'hotelHousekeepingTaskId'))}/status',
          query: {'farmId': widget.company.farmId}, body: {'status': status});
      if (mounted) trackerToast(context, 'Task updated to $status');
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Update failed', description: e.message, error: true);
    }
  }

  Widget _card(Map t) {
    final (pbg, pfg) = _hkPriority[tStr(t['priority'])] ?? (TColors.slate100, TColors.slate700);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('Room ${tStr(_v(t, 'roomNumber'))}', style: const TextStyle(fontWeight: FontWeight.w700))),
          hotelBadge(tStr(t['priority']), pbg, pfg),
        ]),
        const SizedBox(height: 4),
        Text(tStr(_v(t, 'taskType')), style: const TextStyle(fontSize: 13, color: TColors.slate500)),
        if (tStr(_v(t, 'assignedTo')).isNotEmpty) Text('Assigned: ${tStr(_v(t, 'assignedTo'))}', style: const TextStyle(fontSize: 12, color: TColors.slate400)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final s in housekeepingStatuses)
            if (s != tStr(t['status']))
              OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 32), visualDensity: VisualDensity.compact), onPressed: () => _change(t, s), child: Text(s)),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/hotel-housekeeping');
    final filtered = [for (final t in _tasks) if (_filter == 'all' || t['status'] == _filter) t];
    return Scaffold(
      backgroundColor: TColors.slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Housekeeping')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
          _title(Icons.auto_awesome_outlined, 'Housekeeping'),
          const SizedBox(height: 10),
          AppSelect<String>(
            value: _filter,
            items: [const AppSelectItem(value: 'all', label: 'All'), for (final s in housekeepingStatuses) AppSelectItem(value: s, label: s)],
            onChanged: (v) => setState(() => _filter = v ?? 'all'),
          ),
          const SizedBox(height: 14),
          if (_loading)
            _loadingBox()
          else if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Text('No housekeeping tasks.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate400)),
            )
          else
            for (final s in housekeepingStatuses)
              if (_filter == 'all' || _filter == s) ...[
                () {
                  final col = [for (final t in filtered) if (t['status'] == s) t];
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('${s.toUpperCase()} (${col.length})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: TColors.slate500)),
                    const SizedBox(height: 8),
                    for (final t in col) _card(t),
                    const SizedBox(height: 10),
                  ]);
                }(),
              ],
        ]),
      ),
    );
  }
}

// ================================================================= HK Schedule

const _schedTone = {
  'Scheduled': (Color(0xFFDBEAFE), Color(0xFF1D4ED8)),
  'InProgress': (Color(0xFFFEF3C7), Color(0xFFB45309)),
  'Completed': (Color(0xFFD1FAE5), Color(0xFF047857)),
  'Skipped': (TColors.slate100, TColors.slate700),
};

/// The Time column: minutes between start and end, "In progress..." when only started.
String hkScheduleElapsed(Map s) {
  final a = DateTime.tryParse(tStr(s['starttime'])), b = DateTime.tryParse(tStr(s['endtime']));
  if (a != null && b != null) return '${(b.difference(a).inSeconds / 60).round()} min';
  return a != null ? 'In progress...' : '—';
}

class HotelHKScheduleScreen extends StatefulWidget {
  const HotelHKScheduleScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<HotelHKScheduleScreen> createState() => _HotelHKScheduleScreenState();
}

class _HotelHKScheduleScreenState extends State<HotelHKScheduleScreen> {
  List<Map> _items = [], _rooms = [], _types = [], _staff = [];
  bool _loading = true, _bulking = false;
  String _date = DateTime.now().toUtc().toIso8601String().substring(0, 10);

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final q = {'farmId': _farmId};
    Future<Object?> soft(String p) async {
      try {
        return await _api.get(p, query: q);
      } on ApiException {
        return const [];
      }
    }

    try {
      final r = await Future.wait([
        _api.get('/api/Hotel/housekeeping-schedule', query: {...q, 'date': _date}),
        _api.get('/api/Hotel/rooms', query: q),
        soft('/api/Hotel/setup/hk-task-types'),
        soft('/api/Hotel/staff'),
      ]);
      if (!mounted) return;
      setState(() {
        _items = hotelRows(r[0]);
        _rooms = hotelRows(r[1]);
        _types = hotelRows(r[2]);
        _staff = [
          for (final s in hotelRows(r[3]))
            if (_v(s, 'isActive') == true && tStr(_v(s, 'department')).toLowerCase().contains('housekeeping')) s,
        ];
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _bulk() async {
    setState(() => _bulking = true);
    try {
      final r = await _api.post('/api/Hotel/housekeeping-schedule/bulk', body: {'farmId': _farmId, 'scheduleDate': _date, 'taskType': 'Daily Cleaning'});
      if (mounted) {
        trackerToast(context, '${tStr(r is Map ? r['created'] : 0)} room(s) scheduled out of ${tStr(r is Map ? r['totalRooms'] : 0)} occupied');
      }
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _bulking = false);
  }

  Future<void> _add() async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _ScheduleDialog(
        session: widget.session,
        company: widget.company,
        date: _date,
        rooms: _rooms,
        types: [for (final t in _types) tStr(t['description'])],
        staff: _staff,
      ),
    );
    if (done == true) _load();
  }

  Future<void> _set(Map s, String status) async {
    try {
      await _api.patch('/api/Hotel/housekeeping-schedule/${tStr(s['hotelschedid'])}/status', body: {'farmId': _farmId, 'status': status});
      if (mounted) trackerToast(context, 'Status → $status');
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
  }

  List<Widget> _actions(Map s) {
    final st = tStr(s['status']);
    return [
      if (st == 'Scheduled') ...[
        IconButton(tooltip: 'Start', onPressed: () => _set(s, 'InProgress'), icon: const Icon(Icons.play_arrow, size: 18, color: Color(0xFF2563EB))),
        IconButton(tooltip: 'Skip', onPressed: () => _set(s, 'Skipped'), icon: const Icon(Icons.skip_next, size: 18, color: TColors.slate500)),
      ],
      if (st == 'InProgress')
        IconButton(tooltip: 'Complete', onPressed: () => _set(s, 'Completed'), icon: const Icon(Icons.check_circle_outline, size: 18, color: Color(0xFF059669))),
    ];
  }

  Widget _priority(Object? p) => switch (tStr(p)) {
        'High' => hotelBadge('High', const Color(0xFFFEF2F2), const Color(0xFFB91C1C)),
        'Normal' => hotelBadge('Normal', const Color(0xFFEFF6FF), const Color(0xFF1D4ED8)),
        final x => hotelBadge(x, TColors.slate50, TColors.slate700),
      };

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/hotel-housekeeping-schedule');
    int n(String s) => _items.where((i) => i['status'] == s).length;
    return Scaffold(
      backgroundColor: TColors.slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('HK Schedule')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
          HotelPageHeader(icon: Icons.event_available, title: 'Housekeeping Schedule', description: '${_items.length} entries for $_date'),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                onPressed: _bulking ? null : _bulk,
                icon: _bulking
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.groups_outlined, size: 16),
                label: const Text('Schedule All Occupied', overflow: TextOverflow.ellipsis),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: hotelAddButton('Add', _add)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            const Text('Date:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(width: 10),
            Expanded(
              child: AppDateField(
                value: hotelParseYmd(_date),
                hintText: 'dd/mm/yyyy',
                onChanged: (d) {
                  if (d == null) return;
                  setState(() => _date = hotelYmd(d));
                  _load();
                },
              ),
            ),
          ]),
          const SizedBox(height: 12),
          twoUp([
            _numberCard('Scheduled', '${n('Scheduled')}', const Color(0xFF1D4ED8)),
            _numberCard('In Progress', '${n('InProgress')}', const Color(0xFFB45309)),
            _numberCard('Completed', '${n('Completed')}', const Color(0xFF047857)),
            _numberCard('Skipped', '${n('Skipped')}', TColors.slate500),
          ]),
          const SizedBox(height: 12),
          if (_loading)
            _loadingBox()
          else if (_items.isEmpty)
            TCard(
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 28, horizontal: 12),
                child: Text('No schedule for this date. Click "Schedule All Occupied" to create today\'s roster.',
                    textAlign: TextAlign.center, style: TextStyle(color: TColors.slate400)),
              ),
            )
          else
            MobileCardList<Map>(
              striped: true,
              items: _items,
              keyOf: (s) => tStr(s['hotelschedid']),
              primary: (s) => 'Room ${tStr(s['roomnumber'])}',
              secondary: (s) => '${_dash(s['floorname'])} · ${_dash(s['roomtypename'])}',
              trailing: (s) {
                final (bg, fg) = _schedTone[tStr(s['status'])] ?? (TColors.slate100, TColors.slate700);
                return hotelBadge(tStr(s['status']), bg, fg);
              },
              details: (s) => [
                ('Task', tStr(s['tasktype'])),
                ('Assigned', _dash(s['assignedto'])),
                ('Priority', tStr(s['priority'])),
                ('Time', hkScheduleElapsed(s)),
              ],
              actions: _actions,
              table: (items) => TrackerTable(
                columns: const [
                  TCol('Room', width: 70),
                  TCol('Floor', width: 100),
                  TCol('Type', width: 110),
                  TCol('Task', width: 130),
                  TCol('Assigned', width: 120),
                  TCol('Priority', width: 90),
                  TCol('Status', width: 100),
                  TCol('Time', width: 100),
                  TCol('Actions', right: true, width: 110),
                ],
                rows: [
                  for (final s in items)
                    () {
                      final (bg, fg) = _schedTone[tStr(s['status'])] ?? (TColors.slate100, TColors.slate700);
                      return <Widget>[
                        Text(tStr(s['roomnumber']), style: const TextStyle(fontWeight: FontWeight.w600, color: TColors.violet700)),
                        cellText(_dash(s['floorname'])),
                        cellText(_dash(s['roomtypename'])),
                        Align(alignment: Alignment.centerLeft, child: hotelBadge(tStr(s['tasktype']), TColors.violet50, TColors.violet700)),
                        cellText(_dash(s['assignedto'])),
                        Align(alignment: Alignment.centerLeft, child: _priority(s['priority'])),
                        Align(alignment: Alignment.centerLeft, child: hotelBadge(tStr(s['status']), bg, fg)),
                        cellText(hkScheduleElapsed(s)),
                        Wrap(alignment: WrapAlignment.end, children: _actions(s)),
                      ];
                    }(),
                ],
              ),
            ),
        ]),
      ),
    );
  }
}

class _ScheduleDialog extends StatefulWidget {
  const _ScheduleDialog({required this.session, required this.company, required this.date, required this.rooms, required this.types, required this.staff});
  final Session session;
  final Company company;
  final String date;
  final List<Map> rooms, staff;
  final List<String> types;

  @override
  State<_ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends State<_ScheduleDialog> {
  int _room = 0;
  String _type = '', _priority = 'Normal', _assignedSel = '';
  final _custom = TextEditingController(), _notes = TextEditingController();
  final _typeOther = GlobalKey<HotelOtherSelectState>();
  bool _saving = false;

  @override
  void dispose() {
    _custom.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_room == 0) return trackerToast(context, 'Select a room', error: true);
    if (_type.isEmpty) return trackerToast(context, 'Select a task type', error: true);
    setState(() => _saving = true);
    try {
      await widget.session.farmClient.post('/api/Hotel/housekeeping-schedule', body: {
        'farmId': widget.company.farmId,
        'scheduleDate': widget.date,
        'hotelRoomId': _room,
        'assignedTo': _assignedSel == '__other__' ? _custom.text : _assignedSel,
        'taskType': _type,
        'priority': _priority,
        'notes': _notes.text,
      });
      await _typeOther.currentState?.remember();
      if (!mounted) return;
      trackerToast(context, 'Scheduled');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Failed', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => HotelDialog(
        icon: Icons.event_available,
        title: 'Add Schedule Entry',
        saveLabel: 'Schedule',
        saving: _saving,
        onSave: _save,
        children: [
          FilterLabel(
            'Room *',
            AppSelect<int>(
              value: _room,
              items: [
                const AppSelectItem(value: 0, label: '-- Select --'),
                for (final r in widget.rooms)
                  AppSelectItem(value: tIntOrNull(_v(r, 'hotelRoomId')) ?? 0, label: 'Room ${tStr(_v(r, 'roomNumber'))} (${tStr(r['status'])})'),
              ],
              onChanged: (v) => setState(() => _room = v ?? 0),
            ),
          ),
          FilterLabel(
            'Task Type *',
            HotelOtherSelect(
              key: _typeOther,
              session: widget.session,
              company: widget.company,
              listKey: 'HKTaskType',
              baseOptions: widget.types,
              value: _type,
              onChanged: (v) => setState(() => _type = v ?? ''),
              placeholder: 'Select task',
              includeNone: true,
              noneLabel: 'Select task',
              otherLabel: 'Other (type task)',
            ),
          ),
          FilterLabel(
            'Priority',
            AppSelect<String>(
              value: _priority,
              items: const [
                AppSelectItem(value: 'Low', label: 'Low'),
                AppSelectItem(value: 'Normal', label: 'Normal'),
                AppSelectItem(value: 'High', label: 'High'),
              ],
              onChanged: (v) => setState(() => _priority = v ?? 'Normal'),
            ),
          ),
          FilterLabel(
            'Assigned To',
            AppSelect<String>(
              value: _assignedSel,
              hintText: 'Select staff',
              items: [
                const AppSelectItem(value: '', label: 'Unassigned'),
                for (final s in widget.staff)
                  () {
                    final name = '${tStr(_v(s, 'firstName'))} ${tStr(_v(s, 'lastName'))}';
                    final dept = tStr(s['department']);
                    return AppSelectItem(value: name, label: '$name — ${tStr(s['role'])}${dept.isNotEmpty ? ' ($dept)' : ''}');
                  }(),
                const AppSelectItem(value: '__other__', label: 'Other (type name)'),
              ],
              onChanged: (v) => setState(() {
                _assignedSel = v ?? '';
                if (_assignedSel != '__other__') _custom.clear();
              }),
            ),
          ),
          if (_assignedSel == '__other__') FilterLabel('Staff Name', AppInput(controller: _custom, hintText: 'Type staff name')),
          FilterLabel('Notes', AppInput(controller: _notes, hintText: 'Special instructions')),
        ],
      );
}

// ================================================================ Room Service

const _serviceTone = {
  'Placed': (Color(0xFFDBEAFE), Color(0xFF1D4ED8)),
  'Preparing': (Color(0xFFFEF3C7), Color(0xFFB45309)),
  'Ready': (Color(0xFFD1FAE5), Color(0xFF047857)),
  'Delivered': (TColors.slate100, TColors.slate700),
  'Served': (TColors.slate100, TColors.slate700),
  'Cancelled': (Color(0xFFFEE2E2), Color(0xFFB91C1C)),
};

class HotelRoomServiceScreen extends StatefulWidget {
  const HotelRoomServiceScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<HotelRoomServiceScreen> createState() => _HotelRoomServiceScreenState();
}

class _HotelRoomServiceScreenState extends State<HotelRoomServiceScreen> {
  List<Map> _orders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = hotelRows(await widget.session.farmClient.get('/api/Hotel/restaurant/orders', query: {'farmId': widget.company.farmId}));
      if (mounted) setState(() => _orders = r);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  String _time(Map o) {
    final d = DateTime.tryParse(tStr(_v(o, 'orderTime')))?.toLocal();
    if (d == null) return 'Invalid Date';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.day}/${d.month}/${d.year}, ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  Widget _status(Map o) {
    final (bg, fg) = _serviceTone[tStr(o['status'])] ?? (TColors.slate100, TColors.slate700);
    return hotelBadge(tStr(o['status']), bg, fg);
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/hotel-room-service');
    return Scaffold(
      backgroundColor: TColors.slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Room Service')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
          _title(Icons.shopping_cart_outlined, 'Room Service Orders', count: '(${_orders.length})'),
          const SizedBox(height: 14),
          if (_loading)
            _loadingBox()
          else if (_orders.isEmpty)
            TCard(
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Text('No room service orders yet.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate400)),
              ),
            )
          else
            MobileCardList<Map>(
              striped: true,
              items: _orders,
              keyOf: (o) => tStr(_v(o, 'hotelRestaurantOrderId')),
              primary: (o) => tStr(_v(o, 'tableNumber')).isEmpty ? 'Room' : tStr(_v(o, 'tableNumber')),
              secondary: _time,
              trailing: _status,
              details: (o) => [
                ('Server', tStr(_v(o, 'serverName')).isEmpty ? '-' : tStr(_v(o, 'serverName'))),
                ('Amount', _money(_v(o, 'totalAmount'))),
              ],
              table: (items) => TrackerTable(
                columns: const [
                  TCol('Time', width: 170),
                  TCol('Table/Room', width: 110),
                  TCol('Server', width: 130),
                  TCol('Status', width: 100),
                  TCol('Amount', right: true, width: 100),
                ],
                rows: [
                  for (final o in items)
                    [
                      cellText(_time(o)),
                      cellText(tStr(_v(o, 'tableNumber')).isEmpty ? 'Room' : tStr(_v(o, 'tableNumber'))),
                      cellText(tStr(_v(o, 'serverName')).isEmpty ? '-' : tStr(_v(o, 'serverName'))),
                      Align(alignment: Alignment.centerLeft, child: _status(o)),
                      cellText(_money(_v(o, 'totalAmount')), bold: true),
                    ],
                ],
              ),
            ),
        ]),
      ),
    );
  }
}
