// Generic → Drivers (`app/generic-drivers/page.tsx`) and Generic → Routes
// (`app/generic-routes/page.tsx`): the lists, their Add / Edit dialogs and
// Delete. Routes fill their places from the phone's location or a search and
// work out the travel time and distance, as the web does.

import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../poultry/money/money_widgets.dart';
import '../../poultry/sales/balances_logic.dart' show pageSlice;
import '../../poultry/sales/balances_widgets.dart';
import '../../poultry/sales/credit_widgets.dart' show cardAction;
import '../../poultry/trackers/tracker_logic.dart' show tStr, tIntOrNull;
import '../../poultry/trackers/tracker_widgets.dart';
import '../generic_kit.dart';
import '../generic_products_screen.dart' show genericEmptyCard;
import 'delivery_kit.dart';
import 'generic_places.dart';

import 'package:poultrycore_mobile/design/tone.dart';

String _or(Object? v, [String dash = '—']) => tStr(v).isEmpty ? dash : tStr(v);

/// A list page shell both pages share: load, paginate, add, edit, delete.
abstract class _FleetState<W extends StatefulWidget> extends State<W> {
  Session get session;
  Company get company;
  String get path;
  String get idKey;
  String get noun;

  List<Map> rows = [];
  bool loading = true;
  int page = 1, size = 10;
  ApiClient get api => session.farmClient;
  String get base => '${genericBase(company)}/$path';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final r = rowsOf(await api.get(base));
      if (mounted) setState(() => rows = r);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load ${noun.toLowerCase()}s', description: e.message, error: true);
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> remove(Map r, String name) async {
    if (!await confirmDelete(context, title: 'Delete $name?', description: 'This ${noun.toLowerCase()} will be permanently removed.')) return;
    try {
      await api.delete('$base/${tIntOrNull(r[idKey])}');
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
    load();
  }

  Future<void> openDialog(Widget dialog) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => dialog);
    if (ok == true) load();
  }

  CompactPager pager() => CompactPager(
        total: rows.length,
        page: page,
        pageSize: size,
        onPage: (p) => setState(() => page = p),
        onPageSize: (v) => setState(() {
          size = v;
          page = 1;
        }),
      );

  List<Widget> editDeleteActions(VoidCallback edit, VoidCallback del) => [
        cardAction('Edit', Icons.edit_outlined, edit),
        OutlinedButton.icon(
          onPressed: del,
          style: OutlinedButton.styleFrom(foregroundColor: TColors.red600, side: const BorderSide(color: Tone.line(0xFFFECACA))),
          icon: const Icon(Icons.delete_outline, size: 16),
          label: const Text('Delete'),
        ),
      ];

  Widget iconActions(VoidCallback edit, VoidCallback del) => Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(onPressed: edit, icon: const Icon(Icons.edit_outlined, size: 18, color: TColors.slate600)),
        IconButton(onPressed: del, icon: const Icon(Icons.delete_outline, size: 18, color: TColors.red600)),
      ]);

  Widget page_(String href, String title, IconData icon, String blurb, String addLabel, VoidCallback add, String empty, Widget Function() list) {
    final lead = sidebarLeading(context, session, company, href: href);
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: Text(title)),
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
          dHeader(icon, title, blurb),
          const SizedBox(height: 10),
          FilledButton.icon(key: const ValueKey('fleet-add'), onPressed: add, icon: const Icon(Icons.add, size: 18), label: Text(addLabel)),
          const SizedBox(height: 12),
          if (loading) const LoadingLine('Loading…') else if (rows.isEmpty) genericEmptyCard(empty) else list(),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------ Drivers

class GenericDriversScreen extends StatefulWidget {
  const GenericDriversScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;
  @override
  State<GenericDriversScreen> createState() => _DriversState();
}

class _DriversState extends _FleetState<GenericDriversScreen> {
  @override
  Session get session => widget.session;
  @override
  Company get company => widget.company;
  @override
  String get path => 'drivers';
  @override
  String get idKey => 'genericDriverId';
  @override
  String get noun => 'Driver';

  void _edit([Map? d]) => openDialog(GenericDriverDialog(session: session, company: company, editing: d));

  @override
  Widget build(BuildContext context) => page_(
        '/generic-drivers', 'Drivers', Icons.groups_2_outlined, 'Manage delivery drivers and their vehicles.', 'Add Driver', _edit,
        'No drivers yet. Click “Add Driver” to get started.',
        () => MobileCardList<Map>(
          items: pageSlice(rows, page, size),
          keyOf: (d) => '${tIntOrNull(d[idKey])}',
          primary: (d) => tStr(d['driverName']),
          secondary: (d) => _or(d['phoneNumber'], 'No phone'),
          trailing: (d) => Padding(padding: const EdgeInsets.only(left: 6), child: activeBadge(d['isActive'] == true)),
          highlights: (d) => [
            if (tStr(d['vehicleName']).isNotEmpty) Highlight('Vehicle', tStr(d['vehicleName']), accent: Accent.blue),
            if (tStr(d['licenseNumber']).isNotEmpty) Highlight('License', tStr(d['licenseNumber']), accent: Accent.slate),
          ],
          details: (d) => [
            ('Phone', _or(d['phoneNumber'])),
            ('License', _or(d['licenseNumber'])),
            ('Vehicle', _or(d['vehicleName'])),
            ('Registration', _or(d['vehicleRegistration'])),
            ('Notes', _or(d['notes'])),
          ],
          actions: (d) => editDeleteActions(() => _edit(d), () => remove(d, tStr(d['driverName']))),
          striped: true,
          stripeBlue: true,
          table: (items) => TrackerTable(
            columns: const [
              TCol('Name', width: 140), TCol('Phone', width: 120), TCol('License', width: 120), TCol('Vehicle', width: 120),
              TCol('Registration', width: 120), TCol('Transport', width: 100), TCol('Status', width: 90), TCol('Actions', right: true, width: 100),
            ],
            rows: [
              for (final d in items)
                [
                  cellText(tStr(d['driverName']), bold: true),
                  cellText(_or(d['phoneNumber'])),
                  cellText(_or(d['licenseNumber'])),
                  cellText(_or(d['vehicleName'])),
                  cellText(_or(d['vehicleRegistration'])),
                  Align(alignment: Alignment.centerLeft, child: TBadge(_or(d['transportMode'], 'Car'), bg: TColors.blue100, fg: const Tone.fg(0xFF1D4ED8))),
                  Align(alignment: Alignment.centerLeft, child: activeBadge(d['isActive'] == true)),
                  Align(alignment: Alignment.centerRight, child: iconActions(() => _edit(d), () => remove(d, tStr(d['driverName'])))),
                ],
            ],
          ),
          pager: pager(),
        ),
      );
}

/// Add Driver / Edit Driver. With [quick] it is the Deliveries page's small
/// "Add Driver" (name, phone, vehicle, transport only). Pops true, or the
/// saved fields as a map when [quick].
class GenericDriverDialog extends StatefulWidget {
  const GenericDriverDialog({super.key, required this.session, required this.company, this.editing, this.quick = false});
  final Session session;
  final Company company;
  final Map? editing;
  final bool quick;
  @override
  State<GenericDriverDialog> createState() => _DriverDialogState();
}

class _DriverDialogState extends State<GenericDriverDialog> {
  late final Map _e = widget.editing ?? const {};
  late final _name = TextEditingController(text: tStr(_e['driverName']));
  late final _phone = TextEditingController(text: tStr(_e['phoneNumber']));
  late final _license = TextEditingController(text: tStr(_e['licenseNumber']));
  late final _vehicle = TextEditingController(text: tStr(_e['vehicleName']));
  late final _reg = TextEditingController(text: tStr(_e['vehicleRegistration']));
  late final _notes = TextEditingController(text: tStr(_e['notes']));
  late String _mode = tStr(_e['transportMode']).isEmpty ? 'Car' : tStr(_e['transportMode']);
  bool _saving = false;

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return trackerToast(context, 'Driver name is required', error: true);
    setState(() => _saving = true);
    final body = widget.quick
        ? {'driverName': _name.text, 'phoneNumber': _phone.text, 'vehicleName': _vehicle.text, 'transportMode': _mode}
        : {
            'driverName': _name.text, 'phoneNumber': _phone.text, 'licenseNumber': _license.text, 'vehicleName': _vehicle.text,
            'vehicleRegistration': _reg.text, 'transportMode': _mode, 'notes': _notes.text,
            if (widget.editing != null) 'isActive': _e['isActive'],
          };
    body['farmId'] = widget.company.farmId;
    final base = '${genericBase(widget.company)}/drivers';
    try {
      if (widget.editing != null) {
        await widget.session.farmClient.put('$base/${tIntOrNull(_e['genericDriverId'])}', body: body);
      } else {
        await widget.session.farmClient.post(base, body: body);
      }
      if (!mounted) return;
      trackerToast(context, widget.quick ? 'Driver "${_name.text}" added' : widget.editing != null ? 'Driver updated' : 'Driver added');
      Navigator.pop(context, widget.quick ? body : true);
      return;
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final fields = [
      dField('Name *', AppInput(key: const ValueKey('driver-name'), controller: _name)),
      dField('Phone', AppInput(key: const ValueKey('driver-phone'), controller: _phone)),
      if (!widget.quick) dField('License number', AppInput(controller: _license)),
      dField('Vehicle', AppInput(key: const ValueKey('driver-vehicle'), controller: _vehicle)),
      if (!widget.quick) dField('Vehicle registration', AppInput(controller: _reg)),
      dField(
        widget.quick ? 'Transport' : 'Transport mode',
        AppSelect<String>(
          key: const ValueKey('driver-mode'),
          value: _mode,
          items: [for (final m in genericTransportModes) AppSelectItem(value: m, label: m)],
          onChanged: (v) => setState(() => _mode = v ?? _mode),
        ),
      ),
      if (!widget.quick) dField('Notes', AppInput(controller: _notes)),
    ];
    return AlertDialog(
      scrollable: true,
      title: Text(widget.editing != null ? 'Edit Driver' : 'Add Driver'),
      content: SizedBox(
        width: widget.quick ? 384 : 512,
        child: widget.quick
            ? Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: fields)
            : formSection('Driver details', const Tone.bg(0xFF4F46E5), fields),
      ),
      actions: dialogButtons(context,
          label: widget.editing != null ? 'Save' : 'Add Driver', saving: _saving, onSave: _save, saveKey: const ValueKey('driver-save')),
    );
  }
}

// ------------------------------------------------------------------- Routes

class GenericRoutesScreen extends StatefulWidget {
  const GenericRoutesScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;
  @override
  State<GenericRoutesScreen> createState() => _RoutesState();
}

class _RoutesState extends _FleetState<GenericRoutesScreen> {
  @override
  Session get session => widget.session;
  @override
  Company get company => widget.company;
  @override
  String get path => 'routes';
  @override
  String get idKey => 'genericRouteId';
  @override
  String get noun => 'Route';

  void _edit([Map? r]) => openDialog(GenericRouteDialog(session: session, company: company, editing: r));

  @override
  Widget build(BuildContext context) => page_(
        '/generic-routes', 'Delivery Routes', Icons.place_outlined, 'Manage delivery routes and destinations.', 'Add Route', _edit,
        'No routes yet. Click “Add Route” to get started.',
        () => MobileCardList<Map>(
          items: pageSlice(rows, page, size),
          keyOf: (r) => '${tIntOrNull(r[idKey])}',
          primary: (r) => tStr(r['routeName']),
          secondary: (r) => _or(r['description'], 'No description'),
          trailing: (r) => Padding(padding: const EdgeInsets.only(left: 6), child: activeBadge(r['isActive'] == true)),
          highlights: (r) => [
            if (tStr(r['startPoint']).isNotEmpty) Highlight('From', tStr(r['startPoint']), accent: Accent.blue),
            if (tStr(r['endPoint']).isNotEmpty) Highlight('To', tStr(r['endPoint']), accent: Accent.emerald),
          ],
          details: (r) => [
            ('Start', _or(r['startPoint'])),
            ('End', _or(r['endPoint'])),
            ('Est. time', _or(r['estimatedTime'])),
            ('Notes', _or(r['notes'])),
          ],
          actions: (r) => editDeleteActions(() => _edit(r), () => remove(r, tStr(r['routeName']))),
          striped: true,
          stripeBlue: true,
          table: (items) => TrackerTable(
            columns: const [
              TCol('Route', width: 140), TCol('Description', width: 160), TCol('From', width: 160), TCol('To', width: 160),
              TCol('Est. Time', width: 120), TCol('Status', width: 90), TCol('Actions', right: true, width: 100),
            ],
            rows: [
              for (final r in items)
                [
                  cellText(tStr(r['routeName']), bold: true),
                  cellText(_or(r['description']), color: TColors.slate600),
                  cellText(_or(r['startPoint'])),
                  cellText(_or(r['endPoint'])),
                  cellText(_or(r['estimatedTime'])),
                  Align(alignment: Alignment.centerLeft, child: activeBadge(r['isActive'] == true)),
                  Align(alignment: Alignment.centerRight, child: iconActions(() => _edit(r), () => remove(r, tStr(r['routeName'])))),
                ],
            ],
          ),
          pager: pager(),
        ),
      );
}

/// Add Route / Edit Route. With [quick] it is the Deliveries page's small
/// "Add Route" (name, start, end only); it pops the saved fields.
class GenericRouteDialog extends StatefulWidget {
  const GenericRouteDialog({super.key, required this.session, required this.company, this.editing, this.quick = false});
  final Session session;
  final Company company;
  final Map? editing;
  final bool quick;
  @override
  State<GenericRouteDialog> createState() => _RouteDialogState();
}

class _RouteDialogState extends State<GenericRouteDialog> {
  late final Map _e = widget.editing ?? const {};
  late final _name = TextEditingController(text: tStr(_e['routeName']));
  late final _desc = TextEditingController(text: tStr(_e['description']));
  late final _start = TextEditingController(text: tStr(_e['startPoint']));
  late final _end = TextEditingController(text: tStr(_e['endPoint']));
  late final _time = TextEditingController(text: tStr(_e['estimatedTime']));
  late final _notes = TextEditingController(text: tStr(_e['notes']));
  Place? _from, _to;
  String _distance = '';
  bool _saving = false, _locating = false;

  Future<void> _placed(bool start, Place p) async {
    setState(() => start ? _from = p : _to = p);
    if (_from == null || _to == null) return;
    final t = await GenericPlaces.travel(_from!, _to!);
    if (t != null && mounted) {
      setState(() {
        _time.text = t.time;
        _distance = t.km;
      });
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return trackerToast(context, 'Route name is required', error: true);
    setState(() => _saving = true);
    final body = <String, Object?>{
      'routeName': _name.text,
      'startPoint': _start.text,
      'endPoint': _end.text,
      if (!widget.quick) ...{'description': _desc.text, 'estimatedTime': _time.text, 'notes': _notes.text},
      if (widget.editing != null) 'isActive': _e['isActive'],
      'farmId': widget.company.farmId,
    };
    final base = '${genericBase(widget.company)}/routes';
    try {
      if (widget.editing != null) {
        await widget.session.farmClient.put('$base/${tIntOrNull(_e['genericRouteId'])}', body: body);
      } else {
        await widget.session.farmClient.post(base, body: body);
      }
      if (!mounted) return;
      trackerToast(context, widget.quick ? 'Route "${_name.text}" added' : widget.editing != null ? 'Route updated' : 'Route added');
      Navigator.pop(context, widget.quick ? body : true);
      return;
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    void busy(bool b) => setState(() => _locating = b);
    final fields = widget.quick
        ? [
            dField('Route name *', AppInput(key: const ValueKey('route-name'), controller: _name)),
            dField('Start point', AppInput(key: const ValueKey('route-start'), controller: _start)),
            dField('End point', AppInput(key: const ValueKey('route-end'), controller: _end)),
          ]
        : [
            dField('Route name *', AppInput(key: const ValueKey('route-name'), controller: _name)),
            dField('Description', AppInput(controller: _desc)),
            dField('Start point (your location)',
                PlaceField(controller: _start, hint: 'Where the route starts', keyPrefix: 'route-start', busy: _locating, onBusy: busy, onPlace: (p) => _placed(true, p))),
            dField(
                'End point (destination)',
                PlaceField(
                    controller: _end,
                    hint: 'Type destination name, city or address',
                    keyPrefix: 'route-end',
                    gpsFirst: false,
                    busy: _locating,
                    onBusy: busy,
                    onPlace: (p) => _placed(false, p))),
            dField(
              'Estimated time',
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                AppInput(key: const ValueKey('route-time'), controller: _time, hintText: 'e.g. 2 hours'),
                if (_from != null && _to != null && _time.text.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('Auto-calculated from GPS coordinates', style: TextStyle(fontSize: 12, color: Tone.fg(0xFF059669))),
                  ),
              ]),
            ),
            if (_distance.isNotEmpty) dField('Distance', AppInput(key: ValueKey('route-distance-$_distance'), initialValue: _distance, enabled: false)),
            dField('Notes', AppInput(controller: _notes)),
          ];
    return AlertDialog(
      scrollable: true,
      title: Text(widget.editing != null ? 'Edit Route' : 'Add Route'),
      content: SizedBox(
        width: widget.quick ? 384 : 512,
        child: widget.quick
            ? Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: fields)
            : formSection('Route details', const Tone.bg(0xFF4F46E5), fields),
      ),
      actions: dialogButtons(context,
          label: widget.editing != null ? 'Save' : 'Add Route', saving: _saving, onSave: _save, saveKey: const ValueKey('route-save')),
    );
  }
}
