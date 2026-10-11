import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/tokens.dart';
import '../../design/ui/buttons.dart';
import '../../design/ui/form_section.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../lookup_loader.dart';

enum WaterDriverMode { existing, created }

/// Water → Setup → Delivery → Drivers → "New employee & driver" and
/// "Existing employee", as the second dialog in `app/water-drivers/page.tsx`.
///
/// A driver always belongs to an employee record. New: create the employee
/// on the Login API (`/Admin/employees`), then make them a driver. Existing:
/// pick an employee who is not already a driver. Either way the driver comes
/// from `POST /api/Water/drivers/from-employee`. Unlike Poultry's, Water's
/// dialog picks a role, a default vehicle and a default route, and has no
/// pay inputs (it sends base pay and commission as null).
class WaterDriverEmployeeScreen extends StatefulWidget {
  const WaterDriverEmployeeScreen({
    super.key,
    required this.session,
    required this.company,
    required this.mode,
    this.drivers = const [],
  });

  final Session session;
  final Company company;
  final WaterDriverMode mode;

  /// The drivers already listed, so the picker can leave them out.
  final List<Map<String, dynamic>> drivers;

  @override
  State<WaterDriverEmployeeScreen> createState() => _WaterDriverEmployeeScreenState();
}

class _WaterDriverEmployeeScreenState extends State<WaterDriverEmployeeScreen> {
  late WaterDriverMode _mode = widget.mode;
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _user = TextEditingController();
  final _password = TextEditingController();
  final _license = TextEditingController();
  String _employeeId = '';
  String _role = 'Driver';
  String? _vehicleId;
  String? _routeId;

  /// Null while loading.
  List<Map<String, dynamic>>? _vehicles;
  List<Map<String, dynamic>>? _routes;

  /// Null while loading.
  List<Map<String, dynamic>>? _employees;
  bool _saving = false;

  bool get _isNew => _mode == WaterDriverMode.created;

  @override
  void initState() {
    super.initState();
    _loadEmployees();
    _loadPickers();
  }

  /// The page's vehicles and routes, for the two Assignment pickers.
  Future<void> _loadPickers() async {
    Future<List<Map<String, dynamic>>> rows(String path) async {
      try {
        final res = await widget.session.farmClient.get(path, query: {'farmId': widget.company.farmId});
        return [
          for (final r in LookupLoader.rowsIn(res))
            if (r is Map) Map<String, dynamic>.from(r),
        ];
      } catch (_) {
        return const [];
      }
    }

    final v = await rows('/api/Water/vehicles');
    final r = await rows('/api/Water/routes');
    if (mounted) setState(() { _vehicles = v; _routes = r; });
  }

  @override
  void dispose() {
    for (final c in [_first, _last, _phone, _email, _user, _password, _license]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Drivers already on the farm: given by the list page, or loaded here
  /// when the screen is opened from the page's main button.
  late List<Map<String, dynamic>> _drivers = widget.drivers;

  Future<void> _loadEmployees() async {
    if (_drivers.isEmpty) {
      try {
        final res = await widget.session.farmClient.get('/api/Water/drivers/list-for-farm',
            query: {'farmId': widget.company.farmId});
        _drivers = [
          for (final d in LookupLoader.rowsIn(res))
            if (d is Map) Map<String, dynamic>.from(d),
        ];
      } catch (_) {}
    }
    try {
      final res = await widget.session.loginClient.get('/api/Admin/employees');
      if (!mounted) return;
      setState(() => _employees = [
            for (final e in LookupLoader.rowsIn(res))
              if (e is Map) Map<String, dynamic>.from(e),
          ]);
    } catch (_) {
      // Best-effort, as on the web: "New employee" still works without it.
      if (mounted) setState(() => _employees = const []);
    }
  }

  /// Only employees who are not already drivers.
  List<Map<String, dynamic>> get _available {
    final taken = {
      for (final d in _drivers)
        if (d['employeeUserId'] != null) '${d['employeeUserId']}',
    };
    return [for (final e in _employees ?? const []) if (!taken.contains('${e['id']}')) e];
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  /// The web's dedup warning: an employee matching by phone, email,
  /// username or full name already exists.
  Future<bool> _confirmIfDuplicate(String fn, String ln) async {
    final phone = _phone.text.trim();
    final email = _email.text.trim().toLowerCase();
    final user = _user.text.trim().toLowerCase();
    Map<String, dynamic>? dup;
    for (final e in _employees ?? const <Map<String, dynamic>>[]) {
      final ep = '${e['phoneNumber'] ?? ''}'.trim();
      final ee = '${e['email'] ?? ''}'.trim().toLowerCase();
      final eu = '${e['userName'] ?? ''}'.trim().toLowerCase();
      final en = '${e['firstName'] ?? ''} ${e['lastName'] ?? ''}'.trim().toLowerCase();
      if ((phone.isNotEmpty && ep == phone) ||
          (email.isNotEmpty && ee == email) ||
          (eu.isNotEmpty && eu == user) ||
          en == '$fn $ln'.toLowerCase()) {
        dup = e;
        break;
      }
    }
    if (dup == null) return true;
    final who = '${dup['firstName']} ${dup['lastName']} · ${dup['phoneNumber'] ?? dup['email']}';
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Possible duplicate'),
        content: Text('An employee that looks like this already exists ($who). Create a new one anyway?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create anyway')),
        ],
      ),
    );
    return go ?? false;
  }

  Future<void> _save() async {
    var employeeId = _employeeId;
    final login = widget.session.loginClient;
    final farm = widget.session.farmClient;

    if (_isNew) {
      final fn = _first.text.trim(), ln = _last.text.trim();
      if (fn.isEmpty || ln.isEmpty) return _snack('First and last name are required');
      if (_user.text.trim().isEmpty || !RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(_user.text.trim())) {
        return _snack('Username required (letters, digits, underscore)');
      }
      if (_password.text.length < 4) return _snack('Password must be at least 4 characters');
      if (!await _confirmIfDuplicate(fn, ln)) return;
      setState(() => _saving = true);
      try {
        final res = await login.post('/api/Admin/employees', body: {
          'FirstName': fn,
          'LastName': ln,
          'PhoneNumber': _phone.text.trim(),
          // Login-only accounts get a placeholder address, as on the web.
          'Email': _email.text.trim().isEmpty ? '${_user.text.trim()}@noemail.local' : _email.text.trim(),
          'UserName': _user.text.trim(),
          'Password': _password.text,
          'FarmId': widget.company.farmId,
          'FarmName': widget.company.name,
          'IsAdmin': false,
        });
        final id = res is Map ? (res['id'] ?? (res['data'] is Map ? res['data']['id'] : null)) : null;
        if (id == null) {
          if (mounted) setState(() => _saving = false);
          return _snack('Could not create employee');
        }
        employeeId = '$id';
      } on ApiException catch (e) {
        if (mounted) setState(() => _saving = false);
        return _snack('Could not create employee. ${e.message}');
      }
    } else {
      if (employeeId.isEmpty) return _snack('Pick an employee');
      setState(() => _saving = true);
    }

    try {
      // The web's empForm starts basePay / commissionPerBag at 0 and notes
      // at "", has no inputs for them, and sends `|| null`: always null.
      await farm.post('/api/Water/drivers/from-employee', body: {
        'farmId': widget.company.farmId,
        'employeeUserId': employeeId,
        'role': _role,
        'licenseNumber': _license.text.trim().isEmpty ? null : _license.text.trim(),
        'defaultVehicleId': _vehicleId == null ? null : int.tryParse(_vehicleId!),
        'defaultRouteId': _routeId == null ? null : int.tryParse(_routeId!),
        'basePay': null,
        'commissionPerBag': null,
        'notes': null,
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _saving = false);
      return _snack('Could not save driver. ${e.message}');
    }

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(
        content: Text(_isNew ? 'Employee created & made a driver' : 'Employee assigned as driver')));
    // Email the new employee their login, only when a real address was given.
    if (_isNew) {
      final to = _email.text.trim();
      if (to.isEmpty) {
        messenger.showSnackBar(const SnackBar(
            content: Text('No email on file. Add an email to send this employee their login details.')));
      } else {
        try {
          await farm.post('/api/Email/send-credentials', body: {
            'Email': to,
            'UserName': _user.text.trim(),
            'Password': _password.text,
            'FarmName': widget.company.name,
          });
          messenger.showSnackBar(SnackBar(content: Text('Credentials emailed to $to.')));
        } catch (_) {
          messenger.showSnackBar(SnackBar(content: Text("Couldn't email credentials (to $to).")));
        }
      }
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final available = _available;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_isNew ? 'New employee & driver' : 'Add existing employee as driver',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            Text('A driver always belongs to an employee record',
                style: TextStyle(fontSize: 11.5, color: tokens.mutedForeground)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
        children: [
          Text(
            'A driver always belongs to an employee record — pick an existing one or create a new employee here.',
            style: TextStyle(fontSize: 12.5, color: tokens.mutedForeground),
          ),
          const SizedBox(height: 12),
          SegmentedButton<WaterDriverMode>(
            segments: const [
              ButtonSegment(value: WaterDriverMode.existing, label: Text('Existing employee')),
              ButtonSegment(value: WaterDriverMode.created, label: Text('New employee')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 12),
          if (_isNew) ...[
            FormSection(title: 'New employee details', color: SectionColor.indigo, children: [
              AppField(label: 'First name', required: true, child: AppInput(controller: _first)),
              AppField(label: 'Last name', required: true, child: AppInput(controller: _last)),
              AppField(label: 'Phone', child: AppInput(controller: _phone, keyboardType: TextInputType.phone)),
              AppField(label: 'Email', child: AppInput(controller: _email, hintText: 'optional')),
              AppField(label: 'Username', required: true, child: AppInput(controller: _user)),
              AppField(label: 'Password', required: true,
                  child: AppInput(controller: _password, obscureText: true)),
            ]),
            const SizedBox(height: 12),
          ],
          FormSection(
            title: _isNew ? 'Driver role' : 'Employee & role',
            color: SectionColor.indigo,
            children: [
              if (!_isNew)
                AppField(
                  label: 'Employee',
                  required: true,
                  full: true,
                  child: AppSelect<String>(
                    value: _employeeId.isEmpty ? null : _employeeId,
                    enabled: _employees != null && available.isNotEmpty,
                    hintText: _employees == null
                        ? 'Loading…'
                        : (_employees!.isEmpty
                            ? 'No employees found — use “New employee”.'
                            : available.isEmpty
                                ? 'Every employee is already a driver — use “New employee”.'
                                : 'Select an employee'),
                    items: [
                      for (final e in available)
                        AppSelectItem(
                          value: '${e['id']}',
                          label: '${e['firstName'] ?? ''} ${e['lastName'] ?? ''} — '
                              '${'${e['phoneNumber'] ?? ''}'.isNotEmpty ? e['phoneNumber'] : e['email'] ?? ''}',
                        ),
                    ],
                    onChanged: (v) => setState(() => _employeeId = v ?? ''),
                  ),
                ),
              AppField(
                label: 'Role',
                child: AppSelect<String>(
                  value: _role,
                  items: const [
                    AppSelectItem(value: 'Driver', label: 'Driver'),
                    AppSelectItem(value: 'MotorKingRider', label: 'Motor King Rider'),
                  ],
                  onChanged: (v) => setState(() => _role = v ?? 'Driver'),
                ),
              ),
              AppField(label: 'License number', child: AppInput(controller: _license)),
            ],
          ),
          const SizedBox(height: 12),
          FormSection(title: 'Assignment & pay', color: SectionColor.amber, children: [
            AppField(
              label: 'Default vehicle',
              child: AppSelect<String>(
                value: _vehicleId,
                enabled: _vehicles != null,
                hintText: _vehicles == null ? 'Loading…' : '(none)',
                items: [
                  for (final v in _vehicles ?? const <Map<String, dynamic>>[])
                    AppSelectItem(value: '${v['waterVehicleId']}', label: '${v['vehicleName'] ?? ''}'),
                ],
                onChanged: (v) => setState(() => _vehicleId = v),
              ),
            ),
            AppField(
              label: 'Default route',
              child: AppSelect<String>(
                value: _routeId,
                enabled: _routes != null,
                hintText: _routes == null ? 'Loading…' : '(none)',
                items: [
                  for (final r in _routes ?? const <Map<String, dynamic>>[])
                    AppSelectItem(value: '${r['waterRouteId']}', label: '${r['routeName'] ?? ''}'),
                ],
                onChanged: (v) => setState(() => _routeId = v),
              ),
            ),
          ]),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Cancel',
                  variant: AppButtonVariant.outline,
                  size: AppButtonSize.lg,
                  fullWidth: true,
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppButton(
                  label: _isNew ? 'Create & make driver' : 'Assign as driver',
                  size: AppButtonSize.lg,
                  fullWidth: true,
                  busy: _saving,
                  onPressed: _saving ? null : _save,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
