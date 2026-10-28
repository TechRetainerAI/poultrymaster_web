// Hotel → Setup → Hotel Setup, as `app/hotel-setup/page.tsx`: five tabs worked
// left to right — Floors, Room Types, Amenities, Rooms and Rates — each with
// its count, search and filters, a card per row with Edit and Delete, and the
// web's add / edit dialogs. The web's tables become cards on a phone.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/sales/balances_widgets.dart' show LoadingLine;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart';
import 'hotel_kit.dart';

const _roomStatuses = ['Available', 'Occupied', 'Reserved', 'Cleaning', 'Maintenance'];

/// The web's status badge colours (bg-*-50 text-*-700; anything else amber).
(Color, Color) _statusColors(String s) => switch (s) {
  'Available' => (TColors.emerald50, TColors.emerald700),
  'Occupied' => (TColors.violet50, TColors.violet700),
  'Reserved' => (const Color(0xFFEFF6FF), const Color(0xFF1D4ED8)),
  'Cleaning' => (const Color(0xFFFFF7ED), const Color(0xFFC2410C)),
  _ => (TColors.amber50, TColors.amber700),
};

String _money(Object? v) => tNum(v).toStringAsFixed(2);

class HotelSetupScreen extends StatefulWidget {
  const HotelSetupScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<HotelSetupScreen> createState() => _HotelSetupScreenState();
}

class _HotelSetupScreenState extends State<HotelSetupScreen> {
  bool _loading = true;
  String _tab = 'floors';
  List<Map<String, dynamic>> _categories = [], _beds = [], _roomTypes = [], _floors = [], _amenities = [], _rates = [], _rooms = [];

  // Filters.
  String _rtSearch = '', _rtCat = 'all', _rtBed = 'all';
  String _rmSearch = '', _rmType = 'all', _rmFloor = 'all', _rmStatus = 'all';
  String _flSearch = '';
  String _amSearch = '', _amCat = 'all';
  String _rateSearch = '', _rateType = 'all', _rateStatus = 'all', _rateWeekend = 'all';

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  Map<String, dynamic> get _q => {'farmId': _farmId};

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<List<Map<String, dynamic>>> _list(String path, {bool soft = false}) async {
    try {
      return hotelRows(await _api.get(path, query: _q));
    } catch (_) {
      if (soft) return [];
      rethrow;
    }
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final r = await Future.wait([
        _list('/api/Hotel/setup/room-categories', soft: true),
        _list('/api/Hotel/setup/bed-types', soft: true),
        _list('/api/Hotel/setup/room-types'),
        _list('/api/Hotel/setup/floors'),
        _list('/api/Hotel/setup/amenities'),
        _list('/api/Hotel/room-rates', soft: true),
        _list('/api/Hotel/rooms', soft: true),
      ]);
      _categories = r[0];
      _beds = r[1];
      _roomTypes = r[2];
      _floors = r[3];
      _amenities = r[4];
      _rates = r[5];
      _rooms = r[6];
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed to load setup', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _reload(String path, void Function(List<Map<String, dynamic>>) set) async {
    try {
      final rows = await _list(path);
      if (mounted) setState(() => set(rows));
    } catch (_) {}
  }

  Future<void> _delete(String what, String path, String listPath, void Function(List<Map<String, dynamic>>) set) async {
    final ok = await hotelConfirmDelete(
      context,
      title: 'Delete',
      message: 'Delete $what?',
      onConfirm: () => _api.delete(path, query: _q),
    );
    if (!ok || !mounted) return;
    trackerToast(context, 'Deleted');
    await _reload(listPath, set);
  }

  // ------------------------------------------------------------ filtering
  List<Map<String, dynamic>> get _filteredRoomTypes => [
    for (final rt in _roomTypes)
      if ((_rtSearch.isEmpty ||
              tStr(rt['name']).toLowerCase().contains(_rtSearch.toLowerCase()) ||
              tStr(rt['description']).toLowerCase().contains(_rtSearch.toLowerCase())) &&
          (_rtCat == 'all' || tStr(rt['hotelRoomCategoryId']) == _rtCat) &&
          (_rtBed == 'all' || tStr(rt['hotelBedTypeId']) == _rtBed))
        rt,
  ];

  List<Map<String, dynamic>> get _filteredRooms => [
    for (final rm in _rooms)
      if ((_rmSearch.isEmpty ||
              tStr(rm['roomNumber']).toLowerCase().contains(_rmSearch.toLowerCase()) ||
              tStr(rm['roomTypeName']).toLowerCase().contains(_rmSearch.toLowerCase())) &&
          (_rmType == 'all' || tStr(rm['hotelRoomTypeId']) == _rmType) &&
          (_rmFloor == 'all' || tStr(rm['hotelFloorId']) == _rmFloor) &&
          (_rmStatus == 'all' || tStr(rm['status']) == _rmStatus))
        rm,
  ];

  List<Map<String, dynamic>> get _filteredFloors => [
    for (final f in _floors)
      if (_flSearch.isEmpty ||
          tStr(f['name']).toLowerCase().contains(_flSearch.toLowerCase()) ||
          tStr(f['floorNumber']).contains(_flSearch))
        f,
  ];

  List<String> get _amenityCategories => {
    for (final a in _amenities)
      if (tStr(a['category']).isNotEmpty) tStr(a['category']),
  }.toList();

  List<Map<String, dynamic>> get _filteredAmenities => [
    for (final a in _amenities)
      if ((_amSearch.isEmpty || tStr(a['name']).toLowerCase().contains(_amSearch.toLowerCase())) &&
          (_amCat == 'all' || tStr(a['category']) == _amCat))
        a,
  ];

  static String _today() => hotelYmd(DateTime.now());

  /// Active (today is inside it), Expired, or Upcoming.
  static String _rateState(Map r) {
    final start = tStr(r['startDate']).padRight(10).substring(0, 10).trim();
    final end = tStr(r['endDate']).padRight(10).substring(0, 10).trim();
    final now = _today();
    if (start.compareTo(now) <= 0 && end.compareTo(now) >= 0) return 'Active';
    return end.compareTo(now) < 0 ? 'Expired' : 'Upcoming';
  }

  List<Map<String, dynamic>> get _filteredRates => [
    for (final r in _rates)
      if ((_rateSearch.isEmpty ||
              tStr(r['rateName']).toLowerCase().contains(_rateSearch.toLowerCase()) ||
              tStr(r['roomTypeName']).toLowerCase().contains(_rateSearch.toLowerCase())) &&
          (_rateType == 'all' || tStr(r['hotelRoomTypeId']) == _rateType) &&
          (_rateWeekend == 'all' || (_rateWeekend == 'weekend') == (r['isWeekend'] == true)) &&
          (_rateStatus == 'all' || _rateState(r).toLowerCase() == _rateStatus))
        r,
  ];

  // ------------------------------------------------------------ dialogs
  Future<void> _openFloor([Map<String, dynamic>? f]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _FloorDialog(api: _api, farmId: _farmId, existing: f, nextNumber: _floors.length + 1),
    );
    if (saved == true) await _reload('/api/Hotel/setup/floors', (r) => _floors = r);
  }

  Future<void> _openRoomType([Map<String, dynamic>? rt]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _RoomTypeDialog(api: _api, farmId: _farmId, existing: rt, categories: _categories, beds: _beds),
    );
    if (saved == true) await _reload('/api/Hotel/setup/room-types', (r) => _roomTypes = r);
  }

  Future<void> _openAmenity([Map<String, dynamic>? a]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _AmenityDialog(api: _api, farmId: _farmId, existing: a),
    );
    if (saved == true) await _reload('/api/Hotel/setup/amenities', (r) => _amenities = r);
  }

  Future<void> _openRoom([Map<String, dynamic>? rm]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _RoomDialog(api: _api, farmId: _farmId, existing: rm, roomTypes: _roomTypes, floors: _floors),
    );
    if (saved == true) await _reload('/api/Hotel/rooms', (r) => _rooms = r);
  }

  Future<void> _openRate() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _RateDialog(api: _api, farmId: _farmId, roomTypes: _roomTypes),
    );
    if (saved == true) await _reload('/api/Hotel/room-rates', (r) => _rates = r);
  }

  // ------------------------------------------------------------------- UI
  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/hotel-setup');
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Hotel Setup')),
      body: _loading
          ? const Padding(padding: EdgeInsets.all(20), child: LoadingLine('Loading…'))
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
                children: [
                  const HotelPageHeader(
                    icon: Icons.settings_outlined,
                    title: 'Hotel Setup',
                    description: 'Work left to right — each step feeds the next',
                  ),
                  const SizedBox(height: 14),
                  _tabs(),
                  const SizedBox(height: 14),
                  switch (_tab) {
                    'room-types' => _roomTypesTab(),
                    'amenities' => _amenitiesTab(),
                    'rooms' => _roomsTab(),
                    'rates' => _ratesTab(),
                    _ => _floorsTab(),
                  },
                ],
              ),
            ),
    );
  }

  Widget _tabs() {
    final tabs = [
      ('floors', Icons.layers_outlined, 'Floors', _floors.length),
      ('room-types', Icons.bed_outlined, 'Room Types', _roomTypes.length),
      ('amenities', Icons.auto_awesome_outlined, 'Amenities', _amenities.length),
      ('rooms', Icons.meeting_room_outlined, 'Rooms', _rooms.length),
      ('rates', Icons.calendar_month_outlined, 'Rates', _rates.length),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: TColors.slate200),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final (key, icon, label, count) in tabs)
            Material(
              color: _tab == key ? TColors.violet50 : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => _tab = key),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 16, color: _tab == key ? TColors.violet700 : TColors.slate500),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _tab == key ? TColors.violet700 : TColors.slate600,
                        ),
                      ),
                      if (count > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(color: TColors.slate100, borderRadius: BorderRadius.circular(999)),
                          child: Text(
                            '$count',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: TColors.slate700),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _title(String text, {Color color = TColors.slate900, FontWeight weight = FontWeight.w600}) => Text(
    text,
    style: TextStyle(fontSize: 14.5, fontWeight: weight, color: color),
  );

  Widget _sub(String text) => Text(text, style: const TextStyle(fontSize: 12.5, color: TColors.slate500));

  Widget _select(String value, String all, List<(String, String)> items, ValueChanged<String> on) => AppSelect<String>(
    value: value,
    items: [
      AppSelectItem(value: 'all', label: all),
      for (final (v, l) in items) AppSelectItem(value: v, label: l),
    ],
    onChanged: (v) => setState(() => on(v ?? 'all')),
  );

  // ------------------------------------------------------------ floors
  Widget _floorsTab() {
    final rows = _filteredFloors;
    return HotelCard(
      title: 'Floors',
      action: hotelAddButton('Add', () => _openFloor()),
      children: [
        HotelFilters(hint: 'Search floor...', onSearch: (v) => setState(() => _flSearch = v), shown: rows.length, total: _floors.length),
        if (rows.isEmpty) hotelEmpty(_floors.isEmpty ? 'No floors yet.' : 'No floors match search.'),
        for (final f in rows)
          HotelRowCard(
            lead: CircleAvatar(
              radius: 17,
              backgroundColor: TColors.violet50,
              child: Text(
                tStr(f['floorNumber']),
                style: const TextStyle(fontWeight: FontWeight.w700, color: TColors.violet700),
              ),
            ),
            body: _title(tStr(f['name'])),
            onEdit: () => _openFloor(f),
            onDelete: () =>
                _delete(tStr(f['name']), '/api/Hotel/setup/floors/${f['hotelFloorId']}', '/api/Hotel/setup/floors', (r) => _floors = r),
          ),
      ],
    );
  }

  // ------------------------------------------------------------ room types
  Widget _roomTypesTab() {
    final rows = _filteredRoomTypes;
    return HotelCard(
      title: 'Room Types',
      action: hotelAddButton('Add', () => _openRoomType()),
      children: [
        HotelFilters(
          hint: 'Search...',
          onSearch: (v) => setState(() => _rtSearch = v),
          selects: [
            _select(_rtCat, 'All categories', [
              for (final c in _categories) (tStr(c['hotelRoomCategoryId']), tStr(c['description'])),
            ], (v) => _rtCat = v),
            _select(_rtBed, 'All bed types', [
              for (final b in _beds) (tStr(b['hotelBedTypeId']), tStr(b['description'])),
            ], (v) => _rtBed = v),
          ],
          shown: rows.length,
          total: _roomTypes.length,
        ),
        if (rows.isEmpty) hotelEmpty(_roomTypes.isEmpty ? 'No room types yet.' : 'No room types match filters.'),
        for (final rt in rows)
          HotelRowCard(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _title(tStr(rt['name'])),
                    hotelBadge(tStr(rt['categoryName']).isEmpty ? '—' : tStr(rt['categoryName']), TColors.violet50, TColors.violet700),
                  ],
                ),
                const SizedBox(height: 3),
                _sub(
                  'Base rate ${_money(rt['baseRate'])} · Max guests ${tStr(rt['maxOccupancy'])} · '
                  '${tStr(rt['bedTypeName']).isNotEmpty
                      ? tStr(rt['bedTypeName'])
                      : tStr(rt['bedType']).isNotEmpty
                      ? tStr(rt['bedType'])
                      : '-'}',
                ),
              ],
            ),
            onEdit: () => _openRoomType(rt),
            onDelete: () => _delete(
              tStr(rt['name']),
              '/api/Hotel/setup/room-types/${rt['hotelRoomTypeId']}',
              '/api/Hotel/setup/room-types',
              (r) => _roomTypes = r,
            ),
          ),
      ],
    );
  }

  // ------------------------------------------------------------ amenities
  Widget _amenitiesTab() {
    final rows = _filteredAmenities;
    return HotelCard(
      title: 'Amenities',
      action: hotelAddButton('Add', () => _openAmenity()),
      children: [
        HotelFilters(
          hint: 'Search amenity...',
          onSearch: (v) => setState(() => _amSearch = v),
          selects: [
            _select(_amCat, 'All categories', [for (final c in _amenityCategories) (c, c)], (v) => _amCat = v),
          ],
          shown: rows.length,
          total: _amenities.length,
        ),
        if (rows.isEmpty) hotelEmpty(_amenities.isEmpty ? 'No amenities yet.' : 'No amenities match filters.'),
        for (final a in rows)
          HotelRowCard(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [_title(tStr(a['name'])), _sub(tStr(a['category']).isEmpty ? '-' : tStr(a['category']))],
            ),
            onEdit: () => _openAmenity(a),
            onDelete: () => _delete(
              tStr(a['name']),
              '/api/Hotel/setup/amenities/${a['hotelAmenityId']}',
              '/api/Hotel/setup/amenities',
              (r) => _amenities = r,
            ),
          ),
      ],
    );
  }

  // ------------------------------------------------------------ rooms
  Widget _roomsTab() {
    final rows = _filteredRooms;
    return HotelCard(
      title: 'Rooms',
      description: 'Add individual rooms and assign them to a room type and floor.',
      action: hotelAddButton('Add Room', () => _openRoom()),
      children: [
        HotelFilters(
          hint: 'Search room...',
          onSearch: (v) => setState(() => _rmSearch = v),
          selects: [
            _select(_rmType, 'All types', [
              for (final rt in _roomTypes) (tStr(rt['hotelRoomTypeId']), tStr(rt['name'])),
            ], (v) => _rmType = v),
            _select(_rmFloor, 'All floors', [for (final f in _floors) (tStr(f['hotelFloorId']), tStr(f['name']))], (v) => _rmFloor = v),
            _select(_rmStatus, 'All statuses', [for (final s in _roomStatuses) (s, s)], (v) => _rmStatus = v),
          ],
          shown: rows.length,
          total: _rooms.length,
        ),
        if (rows.isEmpty)
          hotelEmpty(
            _rooms.isEmpty ? 'No rooms yet. Add room types and floors first, then create rooms.' : 'No rooms match filters.',
            icon: Icons.meeting_room_outlined,
          ),
        for (final rm in rows)
          HotelRowCard(
            lead: Container(
              constraints: const BoxConstraints(minWidth: 44),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(color: TColors.violet50, borderRadius: BorderRadius.circular(10)),
              child: Text(
                tStr(rm['roomNumber']),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800, color: TColors.violet700),
              ),
            ),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _title(tStr(rm['roomTypeName']).isEmpty ? '—' : tStr(rm['roomTypeName'])),
                    hotelBadge(tStr(rm['status']), _statusColors(tStr(rm['status'])).$1, _statusColors(tStr(rm['status'])).$2),
                  ],
                ),
                const SizedBox(height: 3),
                _sub('${tStr(rm['floorName']).isEmpty ? '—' : tStr(rm['floorName'])} · Rate ${_money(rm['baseRate'])}'),
              ],
            ),
            onEdit: () => _openRoom(rm),
            onDelete: () =>
                _delete('room ${tStr(rm['roomNumber'])}', '/api/Hotel/rooms/${rm['hotelRoomId']}', '/api/Hotel/rooms', (r) => _rooms = r),
          ),
      ],
    );
  }

  // ------------------------------------------------------------ rates
  Widget _ratesTab() {
    final rows = _filteredRates;
    return HotelCard(
      title: 'Room Rate Management',
      description: 'Define seasonal rates, weekend rates, and special pricing for each room type.',
      action: hotelAddButton('Add Rate', _openRate),
      children: [
        HotelFilters(
          hint: 'Search rate...',
          onSearch: (v) => setState(() => _rateSearch = v),
          selects: [
            _select(_rateType, 'All types', [
              for (final rt in _roomTypes) (tStr(rt['hotelRoomTypeId']), tStr(rt['name'])),
            ], (v) => _rateType = v),
            _select(_rateStatus, 'All statuses', const [
              ('active', 'Active'),
              ('expired', 'Expired'),
              ('upcoming', 'Upcoming'),
            ], (v) => _rateStatus = v),
            _select(_rateWeekend, 'All days', const [('weekday', 'Weekday'), ('weekend', 'Weekend')], (v) => _rateWeekend = v),
          ],
          shown: rows.length,
          total: _rates.length,
        ),
        if (rows.isEmpty)
          _rates.isEmpty
              ? hotelEmpty(
                  'No custom rates defined. Room types will use their base rate.',
                  icon: Icons.calendar_month_outlined,
                  sub: 'Add seasonal rates, weekend rates, or special pricing to override base rates.',
                )
              : hotelEmpty('No rates match the current filters.', icon: Icons.calendar_month_outlined),
        for (final r in rows) _rateRow(r),
      ],
    );
  }

  Widget _rateRow(Map<String, dynamic> r) {
    final state = _rateState(r);
    final weekend = r['isWeekend'] == true;
    final typeId = tIntOrNull(r['hotelRoomTypeId']);
    final rtName = tStr(r['roomTypeName']).isNotEmpty
        ? tStr(r['roomTypeName'])
        : tStr(_roomTypes.where((rt) => tIntOrNull(rt['hotelRoomTypeId']) == typeId).firstOrNull?['name']).isEmpty
        ? '—'
        : tStr(_roomTypes.firstWhere((rt) => tIntOrNull(rt['hotelRoomTypeId']) == typeId)['name']);
    String d(String k) => tStr(r[k]).length >= 10 ? tStr(r[k]).substring(0, 10) : tStr(r[k]);
    return HotelRowCard(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _title(tStr(r['rateName']))),
              Text(
                _money(r['rate']),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: TColors.violet700),
              ),
            ],
          ),
          const SizedBox(height: 2),
          _sub('$rtName · ${d('startDate')} → ${d('endDate')}'),
          const SizedBox(height: 5),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              weekend
                  ? hotelBadge('Weekend', TColors.amber100, TColors.amber700)
                  : hotelBadge('Weekday', TColors.blue100, const Color(0xFF1D4ED8)),
              switch (state) {
                'Active' => hotelBadge('Active', TColors.emerald100, TColors.emerald700),
                'Expired' => hotelBadge('Expired', TColors.slate100, TColors.slate500),
                _ => hotelBadge('Upcoming', TColors.blue100, const Color(0xFF1D4ED8)),
              },
            ],
          ),
        ],
      ),
      onDelete: () => _delete('this rate', '/api/Hotel/room-rates/${r['hotelRoomRateId']}', '/api/Hotel/room-rates', (x) => _rates = x),
    );
  }
}

// ---------------------------------------------------------------- dialogs

Widget _num(TextEditingController c, {bool decimal = true}) => AppInput(
  controller: c,
  keyboardType: TextInputType.numberWithOptions(decimal: decimal),
  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(decimal ? r'^\d*\.?\d*' : r'^\d*'))],
);

/// Runs a create (POST) or update (PUT) and pops true; a failure stays open.
Future<void> _submit(
  State s,
  ApiClient api, {
  required String path,
  int? id,
  required Map<String, dynamic> body,
  required String done,
  required void Function(bool) busy,
}) async {
  busy(true);
  try {
    if (id != null) {
      await api.put('$path/$id', body: body);
    } else {
      await api.post(path, body: body);
    }
    if (!s.mounted) return;
    trackerToast(s.context, done);
    Navigator.pop(s.context, true);
  } on ApiException catch (e) {
    if (!s.mounted) return;
    busy(false);
    trackerToast(s.context, 'Save failed', description: e.message, error: true);
  }
}

class _FloorDialog extends StatefulWidget {
  const _FloorDialog({required this.api, required this.farmId, required this.nextNumber, this.existing});
  final ApiClient api;
  final String farmId;
  final int nextNumber;
  final Map<String, dynamic>? existing;
  @override
  State<_FloorDialog> createState() => _FloorDialogState();
}

class _FloorDialogState extends State<_FloorDialog> {
  late final _number = TextEditingController(
    text: widget.existing != null ? tStr(widget.existing!['floorNumber']) : '${widget.nextNumber}',
  );
  late final _name = TextEditingController(text: widget.existing != null ? tStr(widget.existing!['name']) : 'Floor ${widget.nextNumber}');
  bool _saving = false;

  @override
  Widget build(BuildContext context) => HotelDialog(
    icon: Icons.layers_outlined,
    title: widget.existing != null ? 'Edit Floor' : 'Add Floor',
    saveLabel: widget.existing != null ? 'Update' : 'Create',
    saving: _saving,
    onSave: () => _submit(
      this,
      widget.api,
      path: '/api/Hotel/setup/floors',
      id: widget.existing == null ? null : tIntOrNull(widget.existing!['hotelFloorId']),
      body: {'floorNumber': int.tryParse(_number.text) ?? 0, 'name': _name.text, 'farmId': widget.farmId},
      done: widget.existing != null ? 'Floor updated' : 'Floor created',
      busy: (b) => setState(() => _saving = b),
    ),
    children: [
      FilterLabel('Floor Number', _num(_number, decimal: false)),
      FilterLabel('Name', AppInput(controller: _name, hintText: 'e.g. Ground Floor')),
    ],
  );
}

class _RoomTypeDialog extends StatefulWidget {
  const _RoomTypeDialog({required this.api, required this.farmId, required this.categories, required this.beds, this.existing});
  final ApiClient api;
  final String farmId;
  final List<Map<String, dynamic>> categories, beds;
  final Map<String, dynamic>? existing;
  @override
  State<_RoomTypeDialog> createState() => _RoomTypeDialogState();
}

class _RoomTypeDialogState extends State<_RoomTypeDialog> {
  late final Map<String, dynamic> _e = widget.existing ?? const {};
  late int? _category = tIntOrNull(_e['hotelRoomCategoryId']);
  late int? _bed = tIntOrNull(_e['hotelBedTypeId']);
  late final _name = TextEditingController(text: tStr(_e['name']));
  late final _rate = TextEditingController(text: widget.existing == null ? '0' : tStr(_e['baseRate']));
  late final _max = TextEditingController(text: widget.existing == null ? '2' : tStr(_e['maxOccupancy']));
  late final _desc = TextEditingController(text: tStr(_e['description']));
  bool _saving = false;

  @override
  Widget build(BuildContext context) => HotelDialog(
    icon: Icons.bed_outlined,
    title: widget.existing != null ? 'Edit Room Type' : 'Add Room Type',
    saveLabel: widget.existing != null ? 'Update' : 'Create',
    saving: _saving,
    onSave: () => _submit(
      this,
      widget.api,
      path: '/api/Hotel/setup/room-types',
      id: widget.existing == null ? null : tIntOrNull(_e['hotelRoomTypeId']),
      body: {
        ..._e,
        'name': _name.text,
        'baseRate': double.tryParse(_rate.text) ?? 0,
        'maxOccupancy': int.tryParse(_max.text) ?? 0,
        'hotelRoomCategoryId': _category,
        'hotelBedTypeId': _bed,
        'description': _desc.text,
        'farmId': widget.farmId,
      },
      done: widget.existing != null ? 'Room type updated' : 'Room type created',
      busy: (b) => setState(() => _saving = b),
    ),
    children: [
      FilterLabel(
        'Category *',
        AppSelect<int>(
          value: _category,
          hintText: 'Select a room category',
          items: [
            for (final c in widget.categories)
              AppSelectItem(value: tIntOrNull(c['hotelRoomCategoryId']) ?? 0, label: '${tStr(c['description'])} (${tStr(c['code'])})'),
          ],
          onChanged: (v) => setState(() => _category = v),
        ),
      ),
      FilterLabel('Name', AppInput(controller: _name, hintText: 'e.g. Deluxe Double')),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: FilterLabel('Base Rate', _num(_rate))),
          const SizedBox(width: 10),
          Expanded(child: FilterLabel('Max Occupancy', _num(_max, decimal: false))),
        ],
      ),
      FilterLabel(
        'Bed Type',
        AppSelect<int>(
          value: _bed,
          hintText: 'Select a bed type',
          items: [for (final b in widget.beds) AppSelectItem(value: tIntOrNull(b['hotelBedTypeId']) ?? 0, label: tStr(b['description']))],
          onChanged: (v) => setState(() => _bed = v),
        ),
      ),
      FilterLabel('Description', AppInput(controller: _desc)),
    ],
  );
}

class _AmenityDialog extends StatefulWidget {
  const _AmenityDialog({required this.api, required this.farmId, this.existing});
  final ApiClient api;
  final String farmId;
  final Map<String, dynamic>? existing;
  @override
  State<_AmenityDialog> createState() => _AmenityDialogState();
}

class _AmenityDialogState extends State<_AmenityDialog> {
  late final _name = TextEditingController(text: tStr(widget.existing?['name']));
  late final _category = TextEditingController(text: tStr(widget.existing?['category']));
  bool _saving = false;

  @override
  Widget build(BuildContext context) => HotelDialog(
    icon: Icons.auto_awesome_outlined,
    title: widget.existing != null ? 'Edit Amenity' : 'Add Amenity',
    saveLabel: widget.existing != null ? 'Update' : 'Create',
    saving: _saving,
    onSave: () => _submit(
      this,
      widget.api,
      path: '/api/Hotel/setup/amenities',
      id: widget.existing == null ? null : tIntOrNull(widget.existing!['hotelAmenityId']),
      body: {'name': _name.text, 'category': _category.text, 'farmId': widget.farmId},
      done: widget.existing != null ? 'Amenity updated' : 'Amenity created',
      busy: (b) => setState(() => _saving = b),
    ),
    children: [
      FilterLabel('Name', AppInput(controller: _name, hintText: 'e.g. WiFi, Air Conditioning')),
      FilterLabel('Category', AppInput(controller: _category, hintText: 'e.g. Technology, Comfort')),
    ],
  );
}

class _RoomDialog extends StatefulWidget {
  const _RoomDialog({required this.api, required this.farmId, required this.roomTypes, required this.floors, this.existing});
  final ApiClient api;
  final String farmId;
  final List<Map<String, dynamic>> roomTypes, floors;
  final Map<String, dynamic>? existing;
  @override
  State<_RoomDialog> createState() => _RoomDialogState();
}

class _RoomDialogState extends State<_RoomDialog> {
  late final Map<String, dynamic>? _e = widget.existing;
  late final _number = TextEditingController(text: tStr(_e?['roomNumber']));
  late final _desc = TextEditingController(text: tStr(_e?['description']));
  // A new room starts on the first room type and the first floor, as the web does.
  late int _type = _e != null
      ? tIntOrNull(_e['hotelRoomTypeId']) ?? 0
      : (widget.roomTypes.isEmpty ? 0 : tIntOrNull(widget.roomTypes.first['hotelRoomTypeId']) ?? 0);
  late int? _floor = _e != null
      ? tIntOrNull(_e['hotelFloorId'])
      : (widget.floors.isEmpty ? null : tIntOrNull(widget.floors.first['hotelFloorId']));
  bool _saving = false;

  void _save() {
    if (_number.text.trim().isEmpty) return trackerToast(context, 'Room number is required', error: true);
    _submit(
      this,
      widget.api,
      path: '/api/Hotel/rooms',
      id: _e == null ? null : tIntOrNull(_e['hotelRoomId']),
      body: {
        'roomNumber': _number.text,
        'hotelRoomTypeId': _type,
        'hotelFloorId': _floor,
        'description': _desc.text,
        'isActive': _e == null ? true : _e['isActive'] != false,
        'farmId': widget.farmId,
      },
      done: _e != null ? 'Room updated' : 'Room created',
      busy: (b) => setState(() => _saving = b),
    );
  }

  @override
  Widget build(BuildContext context) => HotelDialog(
    icon: Icons.meeting_room_outlined,
    title: _e != null ? 'Edit Room ${tStr(_e['roomNumber'])}' : 'Add Room',
    saveLabel: _e != null ? 'Update' : 'Create',
    saving: _saving,
    onSave: _save,
    children: [
      FilterLabel('Room Number *', AppInput(controller: _number, hintText: 'e.g. 101, A1')),
      FilterLabel(
        'Room Type *',
        AppSelect<int>(
          value: _type,
          items: [
            for (final rt in widget.roomTypes)
              AppSelectItem(value: tIntOrNull(rt['hotelRoomTypeId']) ?? 0, label: '${tStr(rt['name'])} — ${_money(rt['baseRate'])}'),
          ],
          onChanged: (v) => setState(() => _type = v ?? _type),
        ),
      ),
      FilterLabel(
        'Floor',
        AppSelect<int>(
          value: _floor,
          hintText: 'Select floor',
          items: [
            for (final f in widget.floors)
              AppSelectItem(value: tIntOrNull(f['hotelFloorId']) ?? 0, label: '${tStr(f['name'])} (Floor ${tStr(f['floorNumber'])})'),
          ],
          onChanged: (v) => setState(() => _floor = v),
        ),
      ),
      FilterLabel('Description', AppInput(controller: _desc, hintText: 'Corner room, ocean view, etc.')),
    ],
  );
}

class _RateDialog extends StatefulWidget {
  const _RateDialog({required this.api, required this.farmId, required this.roomTypes});
  final ApiClient api;
  final String farmId;
  final List<Map<String, dynamic>> roomTypes;
  @override
  State<_RateDialog> createState() => _RateDialogState();
}

class _RateDialogState extends State<_RateDialog> {
  final _name = TextEditingController();
  final _rate = TextEditingController(text: '0');
  late int _type = widget.roomTypes.isEmpty ? 0 : tIntOrNull(widget.roomTypes.first['hotelRoomTypeId']) ?? 0;
  DateTime? _start, _end;
  bool _weekend = false, _saving = false;

  void _save() {
    if (_name.text.trim().isEmpty || _start == null || _end == null || _type == 0) {
      return trackerToast(context, 'Please fill all required fields', error: true);
    }
    _submit(
      this,
      widget.api,
      path: '/api/Hotel/room-rates',
      body: {
        'hotelRoomTypeId': _type,
        'rateName': _name.text,
        'rate': double.tryParse(_rate.text) ?? 0,
        'startDate': hotelYmd(_start!),
        'endDate': hotelYmd(_end!),
        'isWeekend': _weekend,
        'farmId': widget.farmId,
      },
      done: 'Rate created',
      busy: (b) => setState(() => _saving = b),
    );
  }

  /// "+12.5% vs base rate (200.00) — premium of 25.00/night".
  Widget? _compare() {
    final rate = double.tryParse(_rate.text) ?? 0;
    if (_type <= 0 || rate <= 0) return null;
    final base = tNum(widget.roomTypes.where((rt) => tIntOrNull(rt['hotelRoomTypeId']) == _type).firstOrNull?['baseRate']).toDouble();
    final diff = rate - base;
    final pct = base > 0 ? (diff / base * 100).toStringAsFixed(1) : '0';
    final up = diff >= 0;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: up ? TColors.amber50 : TColors.emerald50, borderRadius: BorderRadius.circular(6)),
      child: Text(
        '${up ? '+$pct%' : '$pct%'} vs base rate (${base.toStringAsFixed(2)}) — ${up ? 'premium' : 'discount'} of ${diff.abs().toStringAsFixed(2)}/night',
        style: TextStyle(fontSize: 12, color: up ? TColors.amber700 : TColors.emerald700),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => HotelDialog(
    icon: Icons.calendar_month_outlined,
    title: 'Add Rate',
    saveLabel: 'Create',
    saving: _saving,
    onSave: _save,
    children: [
      FilterLabel('Rate Name *', AppInput(controller: _name, hintText: 'e.g. Peak Season, Holiday Rate, Weekend Special')),
      FilterLabel(
        'Room Type *',
        AppSelect<int>(
          value: _type == 0 ? null : _type,
          items: [
            for (final rt in widget.roomTypes)
              AppSelectItem(value: tIntOrNull(rt['hotelRoomTypeId']) ?? 0, label: '${tStr(rt['name'])} (Base: ${_money(rt['baseRate'])})'),
          ],
          onChanged: (v) => setState(() => _type = v ?? _type),
        ),
      ),
      FilterLabel(
        'Rate *',
        AppInput(
          controller: _rate,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
          onChanged: (_) => setState(() {}),
        ),
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: FilterLabel('Start Date *', AppDateField(value: _start, onChanged: (d) => setState(() => _start = d))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilterLabel('End Date *', AppDateField(value: _end, onChanged: (d) => setState(() => _end = d))),
          ),
        ],
      ),
      AppCheckbox(value: _weekend, label: 'Weekend rate (applies Fri-Sun only)', onChanged: (v) => setState(() => _weekend = v)),
      ?_compare(),
    ],
  );
}
