import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/tokens.dart';
import '../../design/ui/buttons.dart';
import '../../design/ui/form_section.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../lookup_loader.dart';

/// Water → Setup → People → Staff → New / Edit, as the web's dialog in
/// `app/water-staff/page.tsx`.
///
/// Its own screen because of the driver rule: when the role is Driver the
/// form shows License number and Assigned vehicle, and on save mirrors them
/// into the matching `/Water/drivers` row (matched by name + phone), because
/// Vehicle Loading, Driver Returns and the reports still pick drivers from
/// there. Staff has no license column of its own — the license lives only
/// on the driver row, and is read back from it when editing.
class WaterStaffFormScreen extends StatefulWidget {
  const WaterStaffFormScreen({
    super.key,
    required this.session,
    required this.company,
    this.existing,
  });

  final Session session;
  final Company company;
  final Map<String, dynamic>? existing;

  @override
  State<WaterStaffFormScreen> createState() => _WaterStaffFormScreenState();
}

/// ROLES in app/water-staff/page.tsx.
const waterStaffRoles = [
  'MachineOperator', 'PackagingWorker', 'Loader', 'Driver', 'MotorKingRider',
  'Salesperson', 'FactoryManager', 'Accountant', 'Cleaner', 'Security', 'Other',
];
const _salaryTypes = ['Daily', 'Weekly', 'Monthly', 'Commission', 'Mixed'];

class _WaterStaffFormScreenState extends State<WaterStaffFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _basePay = TextEditingController(text: '0');
  final _commission = TextEditingController();
  final _license = TextEditingController();
  final _notes = TextEditingController();

  String _role = 'MachineOperator';
  String _salaryType = 'Monthly';
  bool _isActive = true;
  String _vehicleId = '';

  List<AppSelectItem<String>>? _vehicles;
  List<Map<String, dynamic>> _drivers = const [];
  bool _saving = false;

  Map<String, dynamic>? get _row => widget.existing;
  bool get _editing => _row != null;

  @override
  void initState() {
    super.initState();
    final r = _row;
    if (r != null) {
      String s(String k) => r[k] == null ? '' : '${r[k]}';
      _first.text = s('firstName');
      _last.text = s('lastName');
      _phone.text = s('phoneNumber');
      _email.text = s('email');
      _role = waterStaffRoles.contains(s('role')) ? s('role') : 'Other';
      _salaryType = _salaryTypes.contains(s('salaryType')) ? s('salaryType') : 'Monthly';
      _basePay.text = s('basePay').isEmpty ? '0' : s('basePay');
      _commission.text = s('commissionRate');
      _isActive = r['isActive'] != false;
      _vehicleId = s('assignedWaterVehicleId') == '0' ? '' : s('assignedWaterVehicleId');
      _notes.text = s('notes');
    }
    _load();
  }

  @override
  void dispose() {
    for (final c in [_first, _last, _phone, _email, _basePay, _commission, _license, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _list(String path) async {
    final res = await widget.session.farmClient.get(path, query: {'farmId': widget.company.farmId});
    return [
      for (final r in LookupLoader.rowsIn(res))
        if (r is Map) Map<String, dynamic>.from(r),
    ];
  }

  Future<void> _load() async {
    Future<List<Map<String, dynamic>>> safe(String p) =>
        _list(p).catchError((_) => <Map<String, dynamic>>[]);
    final r = await Future.wait([safe('/api/Water/vehicles'), safe('/api/Water/drivers')]);
    if (!mounted) return;
    setState(() {
      _vehicles = [
        for (final v in r[0])
          if (v['waterVehicleId'] != null)
            AppSelectItem(
              value: '${v['waterVehicleId']}',
              // "{name} ({type})", plus " — {status}" when not Active.
              label: '${v['vehicleName'] ?? ''} (${v['vehicleType'] ?? ''})'
                  '${'${v['status'] ?? 'Active'}' != 'Active' ? ' — ${v['status']}' : ''}',
            ),
      ];
      _drivers = r[1];
      // Prefill the license from the mirrored driver row, if any.
      if (_editing) {
        final match = _matchingDriver();
        _license.text = '${match?['licenseNumber'] ?? ''}';
      }
    });
  }

  /// findMatchingDriver: exact name (and phone when both have one), or the
  /// phone alone when a driver was added before the merge with no name match.
  Map<String, dynamic>? _matchingDriver() {
    final full = '${_first.text} ${_last.text}'.trim().toLowerCase();
    final phone = _phone.text.trim();
    for (final d in _drivers) {
      final dn = '${d['driverName'] ?? ''}'.trim().toLowerCase();
      final dp = '${d['phoneNumber'] ?? ''}'.trim();
      if (dn == full && (phone.isEmpty || dp.isEmpty || dp == phone)) return d;
      if (phone.isNotEmpty && dp == phone) return d;
    }
    return null;
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _save() async {
    if (_first.text.trim().isEmpty || _last.text.trim().isEmpty) {
      _formKey.currentState?.validate();
      return _snack('Name required');
    }
    setState(() => _saving = true);
    final client = widget.session.farmClient;
    final farmId = widget.company.farmId;
    final vehicle = int.tryParse(_vehicleId);
    final body = <String, dynamic>{
      'farmId': farmId,
      'firstName': _first.text.trim(),
      'lastName': _last.text.trim(),
      'phoneNumber': _phone.text.trim(),
      'email': _email.text.trim(),
      'role': _role,
      'salaryType': _salaryType,
      'basePay': double.tryParse(_basePay.text.trim()) ?? 0,
      'commissionRate': double.tryParse(_commission.text.trim()),
      'assignedWaterVehicleId': vehicle,
      'assignedWaterRouteId': _row?['assignedWaterRouteId'],
      'isActive': _isActive,
      'notes': _notes.text.trim(),
    };
    try {
      if (_editing) {
        final id = _row!['waterStaffId'];
        await client.put('/api/Water/staff/$id', body: {...body, 'waterStaffId': id});
      } else {
        await client.post('/api/Water/staff', body: body);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      return _snack('Save failed. ${e.message}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      return _snack('Save failed. $e');
    }

    // The staff row is saved. A driver sync failure is reported, not fatal:
    // opening the staff member again and saving retries it.
    if (_role == 'Driver') {
      final match = _matchingDriver();
      final driver = <String, dynamic>{
        'farmId': farmId,
        'driverName': '${_first.text} ${_last.text}'.trim(),
        'phoneNumber': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'licenseNumber': _license.text.trim().isEmpty ? null : _license.text.trim(),
        'defaultVehicleId': vehicle,
        'isActive': _isActive,
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      };
      try {
        if (match != null) {
          final id = match['waterDriverId'];
          await client.put('/api/Water/drivers/$id', body: {...driver, 'waterDriverId': id});
        } else {
          await client.post('/api/Water/drivers', body: driver);
        }
      } catch (_) {
        if (mounted) {
          _snack('Staff saved, but driver sync failed. Open the staff member again and Save to retry.');
        }
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
    _snack(_editing ? 'Staff updated' : 'Staff added');
  }

  String? _req(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_editing ? 'Edit staff' : 'New staff',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            Text(widget.company.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: tokens.mutedForeground)),
          ],
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
          children: [
            FormSection(title: 'Identity', color: SectionColor.indigo, children: [
              AppField(label: 'First name', required: true,
                  child: AppInput(controller: _first, validator: _req)),
              AppField(label: 'Last name', required: true,
                  child: AppInput(controller: _last, validator: _req)),
              AppField(label: 'Phone',
                  child: AppInput(controller: _phone, keyboardType: TextInputType.phone)),
              AppField(label: 'Email',
                  child: AppInput(controller: _email, keyboardType: TextInputType.emailAddress)),
            ]),
            const SizedBox(height: 12),
            FormSection(title: 'Role & Pay', color: SectionColor.amber, children: [
              AppField(
                label: 'Role',
                child: AppSelect<String>(
                  value: _role,
                  items: [for (final r in waterStaffRoles) AppSelectItem(value: r, label: r)],
                  onChanged: (v) => setState(() => _role = v ?? _role),
                ),
              ),
              AppField(
                label: 'Salary type',
                child: AppSelect<String>(
                  value: _salaryType,
                  items: [for (final t in _salaryTypes) AppSelectItem(value: t, label: t)],
                  onChanged: (v) => setState(() => _salaryType = v ?? _salaryType),
                ),
              ),
              AppField(label: 'Base pay',
                  child: AppNumberInput(controller: _basePay, allowDecimal: true)),
              AppField(label: 'Commission rate (per bag / %)',
                  child: AppNumberInput(controller: _commission, allowDecimal: true)),
              AppField(
                label: 'Active',
                full: true,
                child: AppSwitchRow(
                  label: _isActive ? 'Active' : 'Inactive',
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                ),
              ),
            ]),
            if (_role == 'Driver') ...[
              const SizedBox(height: 12),
              FormSection(title: 'Driver details', color: SectionColor.blue, children: [
                AppField(label: 'License number',
                    child: AppInput(controller: _license, hintText: 'e.g. DVLA-0000-2026')),
                AppField(
                  label: 'Assigned vehicle',
                  child: AppSelect<String>(
                    value: _vehicles == null ? null : _vehicleId,
                    enabled: _vehicles != null,
                    hintText: _vehicles == null ? 'Loading…' : '(none)',
                    items: [
                      const AppSelectItem(value: '', label: '(none)'),
                      ...?_vehicles,
                    ],
                    onChanged: (v) => setState(() => _vehicleId = v ?? ''),
                  ),
                ),
              ]),
            ],
            const SizedBox(height: 12),
            FormSection(title: 'Notes', color: SectionColor.slate, columns: 1, children: [
              AppField(label: 'Notes', full: true, child: AppInput(controller: _notes)),
            ]),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Cancel',
                    variant: AppButtonVariant.destructive,
                    size: AppButtonSize.lg,
                    fullWidth: true,
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    label: 'Save',
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
      ),
    );
  }
}
