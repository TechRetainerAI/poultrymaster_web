// Restaurant → Delivery & Online → Drivers & Dispatch, as
// `app/restaurant-delivery/page.tsx`: five stat cards; the Deliveries tab
// (orders awaiting a driver, then the assignments with their status steps);
// Drivers, Zones and Third-Party tabs; and the driver, zone, platform and
// dispatch dialogs.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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

const driverStatusColors = <String, Color>{
  'Available': Color(0xFF22C55E),
  'OnDelivery': Color(0xFF3B82F6),
  'OffDuty': Color(0xFF6B7280),
  'Suspended': Color(0xFFEF4444),
};
const assignmentStatusColors = <String, Color>{
  'Pending': Color(0xFFEAB308),
  'Assigned': Color(0xFF3B82F6),
  'PickedUp': Color(0xFF6366F1),
  'EnRoute': Color(0xFFA855F7),
  'Delivered': Color(0xFF22C55E),
  'Failed': Color(0xFFEF4444),
  'Cancelled': Color(0xFF6B7280),
};
const deliveryVehicles = ['Motorcycle', 'Car', 'Bicycle', 'Van'];

/// Delivery orders that still need a driver: not finished, and not already on
/// an assignment.
List<Map> pendingDeliveryOrders(List<Map> orders, List<Map> assignments) {
  final assigned = {for (final a in assignments) tNum(a['orderId']).toInt()};
  return [
    for (final o in orders)
      if (tStr(o['orderType']) == 'Delivery' &&
          !const ['Completed', 'Cancelled', 'Refunded'].contains(tStr(o['status'])) &&
          !assigned.contains(tNum(o['orderId']).toInt()))
        o,
  ];
}

String _num(Object? v) {
  final n = tNum(v);
  return n == n.roundToDouble() ? n.toInt().toString() : n.toString();
}

/// parseFloat(v) || fallback, parseInt(v) || fallback.
num _float(String v, num fallback) {
  final n = double.tryParse(v.trim());
  return n == null || n == 0 ? fallback : (n == n.roundToDouble() ? n.toInt() : n);
}

int _int(String v, int fallback) {
  final m = RegExp(r'^\s*(-?\d+)').firstMatch(v);
  final n = m == null ? null : int.tryParse(m.group(1)!);
  return n == null || n == 0 ? fallback : n;
}

Widget _solidBadge(String text, Color color) => rBadge(text, bg: color, fg: Colors.white);

class RestaurantDeliveryScreen extends StatefulWidget {
  const RestaurantDeliveryScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<RestaurantDeliveryScreen> createState() => _RestaurantDeliveryScreenState();
}

class _RestaurantDeliveryScreenState extends State<RestaurantDeliveryScreen> {
  bool _loading = true;
  String _tab = 'deliveries';
  List<Map> _drivers = [];
  List<Map> _zones = [];
  List<Map> _assignments = [];
  Map? _stats;
  List<Map> _platforms = [];
  List<Map> _pending = [];
  String _filter = 'active';

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  Map<String, dynamic> get _q => {'farmId': _farmId};

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  List<Map> _rows(Object? v) => [for (final x in (v is List ? v : const [])) if (x is Map) x];
  Future<Object?> _safe(Future<Object?> f, Object? fallback) => f.catchError((Object _) => fallback);

  Future<List<Map>> _listDrivers() async => _rows(await _api.get('/api/Restaurant/delivery/drivers', query: {..._q, '_': 1}));
  Future<Map?> _getStats() async {
    final s = await _api.get('/api/Restaurant/delivery/stats', query: {..._q, '_': 1});
    return s is Map ? s : null;
  }

  Future<void> _loadAll() async {
    final r = await Future.wait([
      _safe(_api.get('/api/Restaurant/delivery/drivers', query: {..._q, '_': 1}), const []),
      _safe(_api.get('/api/Restaurant/delivery/zones', query: _q), const []),
      _safe(_api.get('/api/Restaurant/delivery/assignments', query: {..._q, '_': 1}), const []),
      _safe(_api.get('/api/Restaurant/delivery/stats', query: {..._q, '_': 1}), null),
      _safe(_api.get('/api/Restaurant/delivery/platforms', query: _q), const []),
      _safe(_api.get('/api/Restaurant/orders', query: {..._q, '_': 1}), const []),
    ]);
    _drivers = _rows(r[0]);
    _zones = _rows(r[1]);
    _assignments = _rows(r[2]);
    _stats = r[3] is Map ? r[3] as Map : null;
    _platforms = _rows(r[4]);
    _pending = pendingDeliveryOrders(_rows(r[5]), _assignments);
    if (mounted) setState(() => _loading = false);
  }

  /// loadAssignments: Active and All read everything (Active then drops the
  /// finished ones); Pending and Delivered ask the server for that status.
  Future<void> _loadAssignments() async {
    final status = _filter == 'active' || _filter == 'all' ? null : _filter;
    final r = await Future.wait([
      _safe(_api.get('/api/Restaurant/delivery/assignments', query: {..._q, '_': 1, 'status': ?status}), const []),
      _safe(_api.get('/api/Restaurant/orders', query: {..._q, '_': 1}), const []),
    ]);
    final list = _rows(r[0]);
    _assignments = _filter == 'active'
        ? [for (final a in list) if (!const ['Delivered', 'Failed', 'Cancelled'].contains(tStr(a['status']))) a]
        : list;
    _pending = pendingDeliveryOrders(_rows(r[1]), list);
    if (mounted) setState(() {});
  }

  void _toast(String title, {String? description, bool error = false}) {
    if (mounted) trackerToast(context, title, description: description, error: error);
  }

  String _err(Object e) => e is ApiException ? e.message : '$e';

  Future<void> _refreshDriversAndStats() async {
    _drivers = await _listDrivers();
    _stats = await _getStats();
    if (mounted) setState(() {});
  }

  Future<void> _driverStatus(Map d, String status) async {
    try {
      await _api.patch('/api/Restaurant/delivery/drivers/${d['driverId']}/status', query: _q, body: {'status': status});
      await _refreshDriversAndStats();
      _toast('Driver $status');
    } catch (e) {
      _toast('Failed', description: _err(e), error: true);
    }
  }

  Future<void> _delDriver(Map d) async {
    try {
      await _api.delete('/api/Restaurant/delivery/drivers/${d['driverId']}', query: _q);
      await _refreshDriversAndStats();
    } catch (e) {
      _toast('Failed', description: _err(e), error: true);
    }
  }

  Future<void> _delZone(Map z) async {
    try {
      await _api.delete('/api/Restaurant/delivery/zones/${z['deliveryZoneId']}', query: _q);
      _zones = _rows(await _api.get('/api/Restaurant/delivery/zones', query: _q));
      if (mounted) setState(() {});
    } catch (e) {
      _toast('Failed', description: _err(e), error: true);
    }
  }

  Future<void> _delPlat(Map p) async {
    try {
      await _api.delete('/api/Restaurant/delivery/platforms/${p['platformId']}', query: _q);
      _platforms = _rows(await _api.get('/api/Restaurant/delivery/platforms', query: _q));
      if (mounted) setState(() {});
    } catch (e) {
      _toast('Failed', description: _err(e), error: true);
    }
  }

  Future<void> _assignStatus(Map a, String status) async {
    try {
      await _api.patch('/api/Restaurant/delivery/assignments/${a['deliveryAssignmentId']}/status', query: _q, body: {'status': status});
      await _loadAssignments();
      await _refreshDriversAndStats();
      _toast('Delivery $status');
    } catch (e) {
      _toast('Failed', description: _err(e), error: true);
    }
  }

  Future<void> _openDriver([Map? d]) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _DriverDialog(api: _api, farmId: _farmId, editing: d));
    if (ok == true) await _refreshDriversAndStats();
  }

  Future<void> _openZone([Map? z]) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _ZoneDialog(api: _api, farmId: _farmId, editing: z));
    if (ok == true) {
      _zones = _rows(await _api.get('/api/Restaurant/delivery/zones', query: _q));
      if (mounted) setState(() {});
    }
  }

  Future<void> _openPlat([Map? p]) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _PlatformDialog(api: _api, farmId: _farmId, editing: p));
    if (ok == true) {
      _platforms = _rows(await _api.get('/api/Restaurant/delivery/platforms', query: _q));
      if (mounted) setState(() {});
    }
  }

  Future<void> _dispatch([Map? order]) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _DispatchDialog(
        api: _api,
        farmId: _farmId,
        orders: order == null ? [..._pending] : [order],
        preselected: order == null ? null : tNum(order['orderId']).toInt(),
        drivers: _drivers,
      ),
    );
    if (ok == true) {
      await _loadAssignments();
      await _refreshDriversAndStats();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/restaurant-delivery');
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Delivery Management')),
      body: _loading
          ? const Padding(padding: EdgeInsets.all(20), child: LoadingLine('Loading…'))
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
                const RPageHeader(icon: Icons.local_shipping_outlined, title: 'Delivery Management', subtitle: 'Drivers, zones, dispatch and third-party platforms'),
                if (_stats != null) ...[const SizedBox(height: 14), _statsGrid(_stats!)],
                const SizedBox(height: 14),
                RTabs(
                  value: _tab,
                  onChanged: (v) => setState(() => _tab = v),
                  tabs: [
                    ('deliveries', Icons.local_shipping_outlined, 'Deliveries',
                        _pending.isEmpty ? null : rBadge('${_pending.length}', bg: const Color(0xFFF59E0B), fg: Colors.white)),
                    ('drivers', Icons.people_outline, 'Drivers (${_drivers.length})', null),
                    ('zones', Icons.place_outlined, 'Zones (${_zones.length})', null),
                    ('platforms', Icons.inventory_2_outlined, 'Third-Party (${_platforms.length})', null),
                  ],
                ),
                const SizedBox(height: 14),
                ...switch (_tab) {
                  'drivers' => [_driversTab()],
                  'zones' => [_zonesTab()],
                  'platforms' => [_platformsTab()],
                  _ => _deliveriesTab(),
                },
              ]),
            ),
    );
  }

  Widget _statsGrid(Map s) {
    final avg = tNum(s['avgDeliveryMins']);
    final cells = [
      ('Available Drivers', '${tNum(s['availableDrivers']).toInt()}', const Color(0xFF16A34A)),
      ('On Delivery', '${tNum(s['onDeliveryDrivers']).toInt()}', const Color(0xFF2563EB)),
      ('Active', '${tNum(s['activeCount']).toInt()}', const Color(0xFF9333EA)),
      ('Delivered Today', '${tNum(s['deliveredCount']).toInt()}', const Color(0xFF4B5563)),
      ('Avg Time', avg == 0 ? '—' : '${avg.toStringAsFixed(0)}m', const Color(0xFFEA580C)),
    ];
    return twoColumns([
      for (final (label, value, color) in cells)
        TCard(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(children: [
            Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color)),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          ]),
        ),
    ]);
  }

  Widget _sectionTitle(IconData? icon, String title, {Widget? action}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
          Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
          ?action,
        ]),
      );

  Widget _darkButton(String label, VoidCallback onTap, {IconData icon = Icons.add}) => FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F172A)),
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label),
      );

  Widget _rowBox(Widget child) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
        child: child,
      );

  String _time(Object? v) {
    final d = DateTime.tryParse(tStr(v));
    return d == null ? '' : DateFormat.jms().format(d.toLocal());
  }

  List<Widget> _deliveriesTab() => [
        if (_pending.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB), border: Border.all(color: const Color(0xFFFDE68A)), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const Icon(Icons.inventory_2_outlined, size: 20, color: Color(0xFFD97706)),
                const SizedBox(width: 8),
                Expanded(
                    child: Text('Awaiting Driver Assignment (${_pending.length})',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
              ]),
              const SizedBox(height: 10),
              for (final o in _pending)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: Colors.white, border: Border.all(color: const Color(0xFFFDE68A)), borderRadius: BorderRadius.circular(8)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text(tStr(o['orderNumber']), style: const TextStyle(fontWeight: FontWeight.w700)),
                      _solidBadge('Needs Driver', const Color(0xFFF59E0B)),
                    ]),
                    Text(
                        '${tStr(o['customerName']).isEmpty ? 'Guest' : tStr(o['customerName'])} | ${tNum(o['totalAmount']).toStringAsFixed(2)} | ${_time(o['createdAt'])}',
                        style: const TextStyle(fontSize: 13, color: TColors.slate500)),
                    if (tStr(o['notes']).isNotEmpty)
                      Row(children: [
                        const Icon(Icons.place_outlined, size: 12, color: TColors.slate500),
                        const SizedBox(width: 2),
                        Flexible(child: Text(tStr(o['notes']), style: const TextStyle(fontSize: 12, color: TColors.slate500))),
                      ]),
                    const SizedBox(height: 8),
                    roseButton('Assign Driver', () => _dispatch(o), icon: Icons.local_shipping_outlined),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: 14),
        ],
        TCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _sectionTitle(null, 'Delivery Assignments'),
            Row(children: [
              Expanded(
                child: AppSelect<String>(
                  value: _filter,
                  items: const [
                    AppSelectItem(value: 'active', label: 'Active'),
                    AppSelectItem(value: 'all', label: 'All'),
                    AppSelectItem(value: 'Pending', label: 'Pending'),
                    AppSelectItem(value: 'Delivered', label: 'Delivered'),
                  ],
                  onChanged: (v) {
                    setState(() => _filter = v ?? 'active');
                    _loadAssignments();
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Refresh',
                onPressed: () async {
                  await _loadAssignments();
                  _stats = await _getStats();
                  if (mounted) setState(() {});
                },
                icon: const Icon(Icons.refresh, size: 18),
              ),
            ]),
            const SizedBox(height: 8),
            roseButton('Dispatch Driver', () => _dispatch(), icon: Icons.local_shipping_outlined),
            const SizedBox(height: 12),
            if (_assignments.isEmpty && _pending.isEmpty)
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('No deliveries.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: TColors.slate500)))
            else if (_assignments.isEmpty)
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('No assigned deliveries yet. Assign drivers to the orders above.',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: TColors.slate500)))
            else
              for (final a in _assignments) _assignmentRow(a),
          ]),
        ),
      ];

  Widget _assignmentRow(Map a) {
    final status = tStr(a['status']);
    final driver = tStr(a['driverName']).isEmpty ? 'Unassigned' : tStr(a['driverName']);
    final meta = StringBuffer('Driver: $driver ');
    if (tStr(a['driverPhone']).isNotEmpty) meta.write('(${tStr(a['driverPhone'])})');
    if (tNum(a['estimatedMins']) != 0) meta.write(' | Est: ${_num(a['estimatedMins'])}m');
    if (tNum(a['actualMins']) != 0) meta.write(' | Actual: ${_num(a['actualMins'])}m');
    if (tNum(a['rating']) != 0) meta.write(' | ★${_num(a['rating'])}/5');
    final btn = <Widget>[
      if (status == 'Assigned') _stepButton('Picked Up', () => _assignStatus(a, 'PickedUp')),
      if (status == 'PickedUp') _stepButton('En Route', () => _assignStatus(a, 'EnRoute')),
      if (status == 'EnRoute') _stepButton('Delivered', () => _assignStatus(a, 'Delivered'), color: const Color(0xFF16A34A)),
      if (const ['Assigned', 'PickedUp', 'EnRoute'].contains(status))
        _stepButton('Failed', () => _assignStatus(a, 'Failed'), color: const Color(0xFFDC2626)),
    ];
    return _rowBox(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(tStr(a['orderNumber']), style: const TextStyle(fontWeight: FontWeight.w700)),
        _solidBadge(status, assignmentStatusColors[status] ?? const Color(0xFF6B7280)),
      ]),
      Text(meta.toString(), style: const TextStyle(fontSize: 13, color: TColors.slate500)),
      if (tStr(a['deliveryAddress']).isNotEmpty)
        Row(children: [
          const Icon(Icons.place_outlined, size: 12, color: TColors.slate500),
          const SizedBox(width: 2),
          Flexible(child: Text(tStr(a['deliveryAddress']), style: const TextStyle(fontSize: 12, color: TColors.slate500))),
        ]),
      if (btn.isNotEmpty) ...[const SizedBox(height: 8), Wrap(spacing: 6, runSpacing: 6, children: btn)],
    ]));
  }

  Widget _stepButton(String label, VoidCallback onTap, {Color color = const Color(0xFF0F172A)}) =>
      FilledButton(style: FilledButton.styleFrom(backgroundColor: color, visualDensity: VisualDensity.compact), onPressed: onTap, child: Text(label));

  Widget _driversTab() => TCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _sectionTitle(Icons.people_outline, 'Drivers', action: _darkButton('Add Driver', () => _openDriver())),
          if (_drivers.isEmpty)
            const Text('No drivers.', style: TextStyle(fontSize: 13, color: TColors.slate500))
          else
            for (final d in _drivers) _driverRow(d),
        ]),
      );

  Widget _driverRow(Map d) {
    final status = tStr(d['status']);
    final active = tNum(d['activeDeliveries']).toInt();
    final meta = StringBuffer(tStr(d['phone']));
    if (tStr(d['vehiclePlate']).isNotEmpty) meta.write(' | ${tStr(d['vehiclePlate'])}');
    meta.write(' | Deliveries: ${tNum(d['totalDeliveries']).toInt()}');
    if (active > 0) meta.write(' ($active active)');
    if (tNum(d['avgRating']) != 0) meta.write(' | ★${tNum(d['avgRating']).toStringAsFixed(1)}');
    return _rowBox(Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('${tStr(d['firstName'])} ${tStr(d['lastName'])}', style: const TextStyle(fontWeight: FontWeight.w600)),
            _solidBadge(status, driverStatusColors[status] ?? const Color(0xFF6B7280)),
            rBadge(tStr(d['vehicleType']), bg: Colors.white, border: TColors.slate200),
          ]),
          Text(meta.toString(), style: const TextStyle(fontSize: 13, color: TColors.slate500)),
          if (status == 'OffDuty' || status == 'Available') ...[
            const SizedBox(height: 6),
            OutlinedButton(
              style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () => _driverStatus(d, status == 'OffDuty' ? 'Available' : 'OffDuty'),
              child: Text(status == 'OffDuty' ? 'Clock In' : 'Clock Out'),
            ),
          ],
        ]),
      ),
      IconButton(tooltip: 'Edit driver', onPressed: () => _openDriver(d), icon: const Icon(Icons.edit_outlined, size: 18)),
      IconButton(tooltip: 'Delete driver', onPressed: () => _delDriver(d), icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444))),
    ]));
  }

  Widget _zonesTab() => TCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _sectionTitle(Icons.place_outlined, 'Delivery Zones', action: _darkButton('Add Zone', () => _openZone())),
          if (_zones.isEmpty)
            const Text('No zones configured.', style: TextStyle(fontSize: 13, color: TColors.slate500))
          else
            for (final z in _zones)
              _rowBox(Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tStr(z['name']), style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                        '${_num(z['minDistanceKm'])}-${_num(z['maxDistanceKm'])} km | Fee: ${tNum(z['deliveryFee']).toStringAsFixed(2)} | Est: ${_num(z['estimatedMins'])}min',
                        style: const TextStyle(fontSize: 13, color: TColors.slate500)),
                  ]),
                ),
                z['isActive'] != false ? _solidBadge('Active', const Color(0xFF0F172A)) : rBadge('Inactive'),
                IconButton(tooltip: 'Edit zone', onPressed: () => _openZone(z), icon: const Icon(Icons.edit_outlined, size: 18)),
                IconButton(tooltip: 'Delete zone', onPressed: () => _delZone(z), icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444))),
              ])),
        ]),
      );

  Widget _platformsTab() => TCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _sectionTitle(Icons.inventory_2_outlined, 'Third-Party Platforms', action: _darkButton('Add Platform', () => _openPlat())),
          if (_platforms.isEmpty)
            const Text('No platforms configured. Add Uber Eats, Glovo, etc.', style: TextStyle(fontSize: 13, color: TColors.slate500))
          else
            for (final p in _platforms)
              _rowBox(Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text(tStr(p['name']), style: const TextStyle(fontWeight: FontWeight.w600)),
                      p['isEnabled'] == true ? _solidBadge('Enabled', const Color(0xFF0F172A)) : rBadge('Disabled'),
                    ]),
                    Text(
                        'Commission: ${_num(p['commissionRate'])}% | Orders: ${tNum(p['orderCount']).toInt()} | Revenue: ${tNum(p['totalRevenue']).toStringAsFixed(2)}'
                        '${p['autoAccept'] == true ? ' | Auto-accept' : ''}',
                        style: const TextStyle(fontSize: 13, color: TColors.slate500)),
                  ]),
                ),
                IconButton(tooltip: 'Edit platform', onPressed: () => _openPlat(p), icon: const Icon(Icons.edit_outlined, size: 18)),
                IconButton(tooltip: 'Delete platform', onPressed: () => _delPlat(p), icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444))),
              ])),
        ]),
      );
}

/// Add / Edit Driver.
class _DriverDialog extends StatefulWidget {
  const _DriverDialog({required this.api, required this.farmId, this.editing});
  final ApiClient api;
  final String farmId;
  final Map? editing;
  @override
  State<_DriverDialog> createState() => _DriverDialogState();
}

class _DriverDialogState extends State<_DriverDialog> {
  late final Map<String, Object?> _f;
  late final Map<String, TextEditingController> _c;
  static const _text = ['firstName', 'lastName', 'phone', 'email', 'vehiclePlate', 'licenseNumber'];

  @override
  void initState() {
    super.initState();
    final d = widget.editing;
    _f = d == null
        ? {'firstName': '', 'lastName': '', 'phone': '', 'vehicleType': 'Motorcycle'}
        : {for (final k in const [..._text, 'vehicleType', 'isActive', 'notes']) k: d[k]};
    _c = {for (final k in _text) k: TextEditingController(text: tStr(_f[k]))};
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    for (final k in _text) {
      if (_f.containsKey(k) || _c[k]!.text.isNotEmpty) _f[k] = _c[k]!.text;
    }
    if (tStr(_f['firstName']).trim().isEmpty || tStr(_f['phone']).trim().isEmpty) {
      trackerToast(context, 'Name and phone required', error: true);
      return;
    }
    final d = widget.editing;
    final body = {..._f, 'farmId': widget.farmId};
    try {
      if (d != null) {
        await widget.api.put('/api/Restaurant/delivery/drivers/${d['driverId']}', body: body);
      } else {
        await widget.api.post('/api/Restaurant/delivery/drivers', body: body);
      }
      if (!mounted) return;
      trackerToast(context, d != null ? 'Driver updated' : 'Driver added');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e is ApiException ? e.message : '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) => rDialog(
        title: widget.editing != null ? 'Edit Driver' : 'Add Driver',
        description: 'Manage delivery driver details',
        children: [
          rField('First Name', AppInput(controller: _c['firstName']), required: true),
          rField('Last Name', AppInput(controller: _c['lastName']), required: true),
          rField('Phone', AppInput(controller: _c['phone'], keyboardType: TextInputType.phone), required: true),
          rField('Email', AppInput(controller: _c['email'], keyboardType: TextInputType.emailAddress)),
          rField(
            'Vehicle',
            AppSelect<String>(
              value: tStr(_f['vehicleType']).isEmpty ? 'Motorcycle' : tStr(_f['vehicleType']),
              items: [for (final v in deliveryVehicles) AppSelectItem(value: v, label: v)],
              onChanged: (v) => setState(() => _f['vehicleType'] = v),
            ),
          ),
          rField('Plate', AppInput(controller: _c['vehiclePlate'])),
          rField('License', AppInput(controller: _c['licenseNumber'])),
        ],
        actions: [rCancel(context, 'Cancel'), rConfirm(widget.editing != null ? 'Update' : 'Add Driver', _save)],
      );
}

/// Add / Edit Zone.
class _ZoneDialog extends StatefulWidget {
  const _ZoneDialog({required this.api, required this.farmId, this.editing});
  final ApiClient api;
  final String farmId;
  final Map? editing;
  @override
  State<_ZoneDialog> createState() => _ZoneDialogState();
}

class _ZoneDialogState extends State<_ZoneDialog> {
  late final Map<String, Object?> _f;
  late final TextEditingController _name, _min, _max, _fee, _mins;

  @override
  void initState() {
    super.initState();
    final z = widget.editing;
    _f = z == null
        ? {'name': '', 'minDistanceKm': 0, 'maxDistanceKm': 5, 'deliveryFee': 0, 'estimatedMins': 30, 'isActive': true}
        : {for (final k in const ['name', 'minDistanceKm', 'maxDistanceKm', 'deliveryFee', 'estimatedMins', 'isActive']) k: z[k]};
    String or(Object? v, Object d) => tNum(v) == 0 ? '$d' : _num(v);
    _name = TextEditingController(text: tStr(_f['name']));
    _min = TextEditingController(text: or(_f['minDistanceKm'], 0));
    _max = TextEditingController(text: or(_f['maxDistanceKm'], 5));
    _fee = TextEditingController(text: or(_f['deliveryFee'], 0));
    _mins = TextEditingController(text: or(_f['estimatedMins'], 30));
  }

  @override
  void dispose() {
    for (final c in [_name, _min, _max, _fee, _mins]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      trackerToast(context, 'Zone name required', error: true);
      return;
    }
    final z = widget.editing;
    final body = {
      ..._f,
      'name': _name.text,
      'minDistanceKm': _float(_min.text, 0),
      'maxDistanceKm': _float(_max.text, 5),
      'deliveryFee': _float(_fee.text, 0),
      'estimatedMins': _int(_mins.text, 30),
      'farmId': widget.farmId,
    };
    try {
      if (z != null) {
        await widget.api.put('/api/Restaurant/delivery/zones/${z['deliveryZoneId']}', body: body);
      } else {
        await widget.api.post('/api/Restaurant/delivery/zones', body: body);
      }
      if (!mounted) return;
      trackerToast(context, z != null ? 'Zone updated' : 'Zone created');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e is ApiException ? e.message : '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) => rDialog(
        title: widget.editing != null ? 'Edit Zone' : 'Add Zone',
        description: 'Configure delivery zone',
        children: [
          rField('Name', AppInput(controller: _name, hintText: 'e.g. Zone A - 0-3km'), required: true),
          twoColumns([
            rField('Min Distance (km)', rNumberInput(_min)),
            rField('Max Distance (km)', rNumberInput(_max)),
            rField('Delivery Fee', rNumberInput(_fee)),
            rField('Est. Minutes', rNumberInput(_mins)),
          ], gap: 10),
        ],
        actions: [rCancel(context, 'Cancel'), rConfirm(widget.editing != null ? 'Update' : 'Create', _save)],
      );
}

/// Add / Edit Platform.
class _PlatformDialog extends StatefulWidget {
  const _PlatformDialog({required this.api, required this.farmId, this.editing});
  final ApiClient api;
  final String farmId;
  final Map? editing;
  @override
  State<_PlatformDialog> createState() => _PlatformDialogState();
}

class _PlatformDialogState extends State<_PlatformDialog> {
  late final Map<String, Object?> _f;
  late final TextEditingController _name, _store, _commission;

  @override
  void initState() {
    super.initState();
    final p = widget.editing;
    _f = p == null
        ? {'name': '', 'commissionRate': 0, 'isEnabled': false}
        : {for (final k in const ['name', 'apiKey', 'apiSecret', 'storeId', 'commissionRate', 'autoAccept', 'isEnabled']) k: p[k]};
    _name = TextEditingController(text: tStr(_f['name']));
    _store = TextEditingController(text: tStr(_f['storeId']));
    _commission = TextEditingController(text: _num(_f['commissionRate']));
  }

  @override
  void dispose() {
    for (final c in [_name, _store, _commission]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      trackerToast(context, 'Platform name required', error: true);
      return;
    }
    final p = widget.editing;
    final body = {
      ..._f,
      'name': _name.text,
      if (_f.containsKey('storeId') || _store.text.isNotEmpty) 'storeId': _store.text,
      'commissionRate': _float(_commission.text, 0),
      'farmId': widget.farmId,
    };
    try {
      if (p != null) {
        await widget.api.put('/api/Restaurant/delivery/platforms/${p['platformId']}', body: body);
      } else {
        await widget.api.post('/api/Restaurant/delivery/platforms', body: body);
      }
      if (!mounted) return;
      trackerToast(context, p != null ? 'Platform updated' : 'Platform added');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e is ApiException ? e.message : '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) => rDialog(
        title: widget.editing != null ? 'Edit Platform' : 'Add Platform',
        description: 'Third-party delivery platform',
        children: [
          rField('Platform Name', AppInput(controller: _name, hintText: 'e.g. Uber Eats, Glovo'), required: true),
          rField('Store ID', AppInput(controller: _store)),
          rField('Commission %', rNumberInput(_commission)),
          AppCheckbox(value: _f['isEnabled'] == true, onChanged: (v) => setState(() => _f['isEnabled'] = v), label: 'Enabled'),
          AppCheckbox(value: _f['autoAccept'] == true, onChanged: (v) => setState(() => _f['autoAccept'] = v), label: 'Auto-Accept Orders'),
        ],
        actions: [rCancel(context, 'Cancel'), rConfirm(widget.editing != null ? 'Update' : 'Add Platform', _save)],
      );
}

/// Dispatch Driver: one pending delivery order and one Available driver.
class _DispatchDialog extends StatefulWidget {
  const _DispatchDialog({required this.api, required this.farmId, required this.orders, required this.drivers, this.preselected});
  final ApiClient api;
  final String farmId;
  final List<Map> orders;
  final List<Map> drivers;
  final int? preselected;
  @override
  State<_DispatchDialog> createState() => _DispatchDialogState();
}

class _DispatchDialogState extends State<_DispatchDialog> {
  late int? _order = widget.preselected;
  int? _driver;

  Future<void> _assign() async {
    final o = widget.orders.where((x) => tNum(x['orderId']).toInt() == _order).firstOrNull;
    final d = widget.drivers.where((x) => tNum(x['driverId']).toInt() == _driver).firstOrNull;
    if (o == null || d == null) {
      trackerToast(context, 'Select both order and driver', error: true);
      return;
    }
    try {
      // createDeliveryAssignment(orderId, orderNumber, driverId, order.notes):
      // the order's notes go in as the delivery address.
      await widget.api.post('/api/Restaurant/delivery/assignments', query: {'farmId': widget.farmId}, body: {
        'orderId': o['orderId'],
        'orderNumber': o['orderNumber'],
        'driverId': d['driverId'],
        if (tStr(o['notes']).isNotEmpty) 'deliveryAddress': o['notes'],
        'deliveryFee': 0,
      });
      if (!mounted) return;
      trackerToast(context, 'Driver assigned', description: '${tStr(d['firstName'])} assigned to ${tStr(o['orderNumber'])}');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e is ApiException ? e.message : '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = [for (final d in widget.drivers) if (tStr(d['status']) == 'Available') d];
    return rDialog(
      title: 'Dispatch Driver',
      description: 'Assign a driver to a delivery order',
      children: [
        rField(
          'Select Delivery Order',
          widget.orders.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text('No pending delivery orders to assign.', style: TextStyle(fontSize: 13, color: TColors.slate500)))
              : AppSelect<int>(
                  value: _order,
                  hintText: 'Choose an order...',
                  items: [
                    for (final o in widget.orders)
                      AppSelectItem(
                        value: tNum(o['orderId']).toInt(),
                        label:
                            '${tStr(o['orderNumber'])} — ${tStr(o['customerName']).isEmpty ? 'Guest' : tStr(o['customerName'])} (${tNum(o['totalAmount']).toStringAsFixed(2)})',
                      ),
                  ],
                  onChanged: (v) => setState(() => _order = v),
                ),
        ),
        rField(
          'Select Driver',
          available.isEmpty
              ? AppSelect<int>(
                  value: null,
                  hintText: 'Choose a driver...',
                  items: const [AppSelectItem(value: -1, label: 'No available drivers', enabled: false)],
                  onChanged: (_) {},
                )
              : AppSelect<int>(
                  value: _driver,
                  hintText: 'Choose a driver...',
                  items: [
                    for (final d in available)
                      AppSelectItem(
                          value: tNum(d['driverId']).toInt(),
                          label: '${tStr(d['firstName'])} ${tStr(d['lastName'])} (${tStr(d['vehicleType'])})'),
                  ],
                  onChanged: (v) => setState(() => _driver = v),
                ),
        ),
      ],
      actions: [
        rCancel(context, 'Cancel'),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: restaurantRose),
          onPressed: _order == null || _driver == null ? null : _assign,
          icon: const Icon(Icons.local_shipping_outlined, size: 16),
          label: const Text('Assign Driver'),
        ),
      ],
    );
  }
}
