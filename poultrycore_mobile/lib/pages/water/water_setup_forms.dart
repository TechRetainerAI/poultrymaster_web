import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/tokens.dart';
import '../../design/ui/buttons.dart';
import '../../design/ui/form_section.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../lookup_loader.dart';

// The Water Setup hub's own add/edit forms, as
// `components/water-setup/inline-modals.tsx`. They are deliberately smaller
// than the full pages' forms and carry their own option lists — Machine type
// "Sachet machine", Staff role "Operator" — so they are copied as they are,
// not swapped for the pages' forms. Each payload is the modal's save() body.

enum HubKind { text, textarea, number, decimal, select, vehicle, toggle }

class HubField {
  const HubField(this.key, this.label, this.kind,
      {this.full = false, this.required = false, this.placeholder, this.options = const [], this.toggleText});
  final String key;
  final String label;
  final HubKind kind;
  final bool full;
  final bool required;
  final String? placeholder;

  /// (value, label) for selects.
  final List<(String, String)> options;

  /// The text beside a toggle ("Active product").
  final String? toggleText;
}

class HubSection {
  const HubSection(this.title, this.color, this.fields, {this.columns = 2});
  final String title;
  final SectionColor color;
  final List<HubField> fields;
  final int columns;
}

class HubForm {
  const HubForm({
    required this.singular,
    required this.path,
    required this.idKey,
    required this.defaults,
    required this.sections,
    required this.requiredCheck,
    required this.payload,
    this.description,
    this.extraOnCreate = const {},
  });

  /// "product" → "New product" / "Edit product", "Product added".
  final String singular;

  /// `/api/Water/products`.
  final String path;

  /// `waterProductId`, sent on update as the api helper does.
  final String idKey;

  /// The modal's empty form; also which row keys an edit reads.
  final Map<String, Object?> defaults;
  final List<HubSection> sections;

  /// The toast when the required fields are missing, or null when fine.
  final String? Function(Map<String, Object?> v) requiredCheck;

  /// The save() body, before farmId (and the id on update).
  final Map<String, Object?> Function(Map<String, Object?> v) payload;
  final String? description;

  /// What the api helper adds on create only (createWaterStaff: isActive).
  final Map<String, Object?> extraOnCreate;
}

String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// `x || null`: blank text and zero numbers go as null.
Object? _orNull(Object? v) => v == null || v == '' || v == 0 ? null : v;

const _statuses3 = [('Active', 'Active'), ('Inactive', 'Inactive'), ('UnderMaintenance', 'Under maintenance')];
const _notes = HubSection('Notes', SectionColor.slate, [HubField('notes', 'Notes', HubKind.textarea)], columns: 1);

final hubForms = <String, HubForm>{
  'products': HubForm(
    singular: 'product',
    path: '/api/Water/products',
    idKey: 'waterProductId',
    description: 'Finished good or raw material the company makes/sells.',
    defaults: {
      'name': '', 'sku': '', 'sizeMl': 0, 'unit': 'bag', 'unitPrice': 0,
      'isActive': true, 'productType': 'FinishedGood', 'notes': '',
    },
    sections: const [
      HubSection('Basics', SectionColor.indigo, [
        HubField('name', 'Name', HubKind.text, full: true, required: true),
        HubField('sku', 'SKU', HubKind.text),
        HubField('sizeMl', 'Size (mL)', HubKind.number),
        HubField('unit', 'Unit', HubKind.text),
        HubField('unitPrice', 'Unit price', HubKind.decimal),
        HubField('productType', 'Type', HubKind.select, options: [
          ('FinishedGood', 'Finished good'),
          ('RawMaterial', 'Raw material'),
          ('PackagingMaterial', 'Packaging material'),
          ('Other', 'Other'),
        ]),
        HubField('isActive', 'Active', HubKind.toggle, full: true, toggleText: 'Active product'),
      ]),
      _notes,
    ],
    requiredCheck: (v) => '${v['name']}'.trim().isEmpty ? 'Name is required' : null,
    payload: (v) => {
      'name': '${v['name']}'.trim(),
      'sku': _orNull(v['sku']),
      'sizeMl': _orNull(v['sizeMl']),
      'unit': _orNull(v['unit']),
      'unitPrice': v['unitPrice'],
      'isActive': v['isActive'],
      'productType': v['productType'],
      'notes': _orNull(v['notes']),
    },
  ),
  'customers': HubForm(
    singular: 'customer',
    path: '/api/Water/customers',
    idKey: 'waterCustomerId',
    defaults: {'name': '', 'contactPhone': '', 'contactEmail': '', 'address': '', 'city': '', 'notes': ''},
    sections: const [
      HubSection('Contact', SectionColor.indigo, [
        HubField('name', 'Name', HubKind.text, full: true, required: true),
        HubField('contactPhone', 'Phone', HubKind.text),
        HubField('contactEmail', 'Email', HubKind.text),
        HubField('city', 'City', HubKind.text),
        HubField('address', 'Address', HubKind.text),
      ]),
      _notes,
    ],
    requiredCheck: (v) => '${v['name']}'.trim().isEmpty ? 'Name required' : null,
    payload: (v) => {
      ...v,
      'contactPhone': _orNull(v['contactPhone']),
      'contactEmail': _orNull(v['contactEmail']),
      'address': _orNull(v['address']),
      'city': _orNull(v['city']),
      'notes': _orNull(v['notes']),
    },
  ),
  'drivers': HubForm(
    singular: 'driver',
    path: '/api/Water/drivers',
    idKey: 'waterDriverId',
    defaults: {
      'driverName': '', 'phoneNumber': '', 'licenseNumber': '',
      'defaultVehicleId': null, 'isActive': true, 'notes': '',
    },
    sections: const [
      HubSection('Identity', SectionColor.indigo, [
        HubField('driverName', 'Driver name', HubKind.text, full: true, required: true),
        HubField('phoneNumber', 'Phone', HubKind.text),
        HubField('licenseNumber', 'License #', HubKind.text),
      ]),
      HubSection('Assignment', SectionColor.blue, [
        HubField('defaultVehicleId', 'Assigned vehicle', HubKind.vehicle, full: true, placeholder: '(none)'),
        HubField('isActive', 'Active', HubKind.toggle, full: true, toggleText: 'Active driver'),
      ]),
      _notes,
    ],
    requiredCheck: (v) => '${v['driverName']}'.trim().isEmpty ? 'Driver name required' : null,
    payload: (v) => {
      ...v,
      'phoneNumber': _orNull(v['phoneNumber']),
      'licenseNumber': _orNull(v['licenseNumber']),
      'notes': _orNull(v['notes']),
    },
  ),
  'vehicles': HubForm(
    singular: 'vehicle',
    path: '/api/Water/vehicles',
    idKey: 'waterVehicleId',
    defaults: {
      'vehicleName': '', 'vehicleType': 'Truck', 'registrationNumber': '',
      'capacityBags': 0, 'fuelType': '', 'status': 'Active', 'notes': '',
    },
    sections: const [
      HubSection('Vehicle', SectionColor.indigo, [
        HubField('vehicleName', 'Name', HubKind.text, full: true, required: true),
        HubField('vehicleType', 'Type', HubKind.select, options: [
          ('Truck', 'Truck'), ('Pickup', 'Pickup'), ('MotorKing', 'Motor King'), ('Van', 'Van'), ('Other', 'Other'),
        ]),
        HubField('registrationNumber', 'Registration #', HubKind.text),
        HubField('capacityBags', 'Capacity (bags)', HubKind.number),
        HubField('fuelType', 'Fuel type', HubKind.text),
        HubField('status', 'Status', HubKind.select, options: _statuses3),
      ]),
      _notes,
    ],
    requiredCheck: (v) => '${v['vehicleName']}'.trim().isEmpty ? 'Vehicle name required' : null,
    payload: (v) => {
      ...v,
      'registrationNumber': _orNull(v['registrationNumber']),
      'fuelType': _orNull(v['fuelType']),
      'capacityBags': _orNull(v['capacityBags']),
      'notes': _orNull(v['notes']),
    },
  ),
  'routes': HubForm(
    singular: 'route',
    path: '/api/Water/routes',
    idKey: 'waterRouteId',
    defaults: {
      'routeName': '', 'areaCovered': '', 'defaultDriverStaffId': null,
      'defaultVehicleId': null, 'expectedCustomers': 0, 'expectedBagsSold': 0, 'notes': '',
    },
    sections: const [
      HubSection('Route', SectionColor.indigo, [
        HubField('routeName', 'Name', HubKind.text, full: true, required: true),
        HubField('areaCovered', 'Area covered', HubKind.text, full: true),
        HubField('defaultVehicleId', 'Default vehicle', HubKind.vehicle, full: true, placeholder: '(none)'),
        HubField('expectedCustomers', 'Expected customers', HubKind.number),
        HubField('expectedBagsSold', 'Expected bags', HubKind.number),
      ]),
      _notes,
    ],
    requiredCheck: (v) => '${v['routeName']}'.trim().isEmpty ? 'Route name required' : null,
    payload: (v) => {
      ...v,
      'areaCovered': _orNull(v['areaCovered']),
      'expectedCustomers': _orNull(v['expectedCustomers']),
      'expectedBagsSold': _orNull(v['expectedBagsSold']),
      'notes': _orNull(v['notes']),
    },
  ),
  'machines': HubForm(
    singular: 'machine',
    path: '/api/Water/machines',
    idKey: 'waterMachineId',
    defaults: {
      'machineName': '', 'machineNumber': '', 'machineType': 'SachetMachine',
      'manufacturer': '', 'capacityPerHour': 0, 'status': 'Active', 'notes': '',
    },
    sections: const [
      HubSection('Machine', SectionColor.indigo, [
        HubField('machineName', 'Name', HubKind.text, full: true, required: true),
        HubField('machineNumber', 'Machine #', HubKind.text),
        HubField('machineType', 'Type', HubKind.select, options: [
          ('SachetMachine', 'Sachet machine'),
          ('BottleMachine', 'Bottle machine'),
          ('DispenserFiller', 'Dispenser filler'),
          ('Other', 'Other'),
        ]),
        HubField('manufacturer', 'Manufacturer', HubKind.text),
        HubField('capacityPerHour', 'Capacity / hour', HubKind.number),
        HubField('status', 'Status', HubKind.select, options: _statuses3),
      ]),
      _notes,
    ],
    requiredCheck: (v) => '${v['machineName']}'.trim().isEmpty ? 'Machine name required' : null,
    payload: (v) => {
      ...v,
      'machineNumber': _orNull(v['machineNumber']),
      'manufacturer': _orNull(v['manufacturer']),
      'capacityPerHour': _orNull(v['capacityPerHour']),
      'notes': _orNull(v['notes']),
    },
  ),
  'boreholes': HubForm(
    singular: 'borehole',
    path: '/api/Water/boreholes',
    idKey: 'waterBoreholeId',
    defaults: {
      'boreholeName': '', 'location': '', 'pumpType': '', 'pumpCapacity': '',
      'tankCapacity': '', 'waterTreatmentMethod': '', 'filtrationSystem': '',
      'uvSterilizationAvailable': false, 'status': 'Active', 'notes': '',
    },
    sections: const [
      HubSection('Borehole', SectionColor.indigo, [
        HubField('boreholeName', 'Name', HubKind.text, full: true, required: true),
        HubField('location', 'Location', HubKind.text, full: true),
        HubField('pumpType', 'Pump type', HubKind.text),
        HubField('pumpCapacity', 'Pump capacity', HubKind.text, placeholder: 'e.g. 5000 L/hr'),
        HubField('tankCapacity', 'Tank capacity', HubKind.text, placeholder: 'e.g. 10000 L'),
        HubField('waterTreatmentMethod', 'Treatment method', HubKind.text),
        HubField('filtrationSystem', 'Filtration system', HubKind.text),
        HubField('uvSterilizationAvailable', 'UV sterilization?', HubKind.toggle,
            full: true, toggleText: 'Has UV sterilization'),
        HubField('status', 'Status', HubKind.select, options: [('Active', 'Active'), ('Inactive', 'Inactive')]),
      ]),
      _notes,
    ],
    requiredCheck: (v) => '${v['boreholeName']}'.trim().isEmpty ? 'Borehole name required' : null,
    payload: (v) => {
      ...v,
      for (final k in ['location', 'pumpType', 'pumpCapacity', 'tankCapacity', 'waterTreatmentMethod',
        'filtrationSystem', 'notes'])
        k: _orNull(v[k]),
    },
  ),
  'raw-materials': HubForm(
    singular: 'raw material',
    path: '/api/Water/raw-material-items',
    idKey: 'waterRawMaterialItemId',
    defaults: {
      'itemName': '', 'category': 'Packaging', 'unitOfMeasure': 'rolls',
      'minimumStockAlert': 0, 'isActive': true, 'notes': '',
    },
    sections: const [
      HubSection('Material', SectionColor.indigo, [
        HubField('itemName', 'Name', HubKind.text, full: true, required: true),
        HubField('category', 'Category', HubKind.select, options: [
          ('Packaging', 'Packaging'), ('Chemical', 'Chemical'), ('Bottle', 'Bottle'),
          ('Cap', 'Cap'), ('Label', 'Label'), ('Other', 'Other'),
        ]),
        HubField('unitOfMeasure', 'Unit of measure', HubKind.text),
        HubField('minimumStockAlert', 'Min stock alert', HubKind.decimal),
        HubField('isActive', 'Active', HubKind.toggle, full: true, toggleText: 'Active material'),
      ]),
      _notes,
    ],
    requiredCheck: (v) => '${v['itemName']}'.trim().isEmpty ? 'Item name required' : null,
    payload: (v) => {
      ...v,
      'unitOfMeasure': _orNull(v['unitOfMeasure']),
      'minimumStockAlert': _orNull(v['minimumStockAlert']),
      'notes': _orNull(v['notes']),
    },
  ),
  'staff': HubForm(
    singular: 'staff',
    path: '/api/Water/staff',
    idKey: 'waterStaffId',
    extraOnCreate: {'isActive': true},
    defaults: {
      'firstName': '', 'lastName': '', 'phoneNumber': '', 'email': '',
      'role': 'Operator', 'salaryType': 'Monthly', 'basePay': 0, 'commissionRate': 0,
      'isActive': true, 'notes': '',
    },
    sections: const [
      HubSection('Identity', SectionColor.indigo, [
        HubField('firstName', 'First name', HubKind.text, required: true),
        HubField('lastName', 'Last name', HubKind.text, required: true),
        HubField('phoneNumber', 'Phone', HubKind.text),
        HubField('email', 'Email', HubKind.text),
        HubField('role', 'Role', HubKind.select, options: [
          ('Operator', 'Operator'), ('Driver', 'Driver'), ('Sales', 'Sales'),
          ('Manager', 'Manager'), ('Cashier', 'Cashier'), ('Other', 'Other'),
        ]),
      ]),
      HubSection('Compensation', SectionColor.blue, [
        HubField('salaryType', 'Salary type', HubKind.select, options: [
          ('Monthly', 'Monthly'), ('Daily', 'Daily'), ('Commission', 'Commission'), ('Mixed', 'Mixed'),
        ]),
        HubField('basePay', 'Base pay', HubKind.decimal),
        HubField('commissionRate', 'Commission rate (%)', HubKind.decimal),
        HubField('isActive', 'Active', HubKind.toggle, full: true, toggleText: 'Active staff'),
      ]),
      _notes,
    ],
    requiredCheck: (v) =>
        '${v['firstName']}'.trim().isEmpty || '${v['lastName']}'.trim().isEmpty ? 'First + last name required' : null,
    payload: (v) => {
      ...v,
      'phoneNumber': _orNull(v['phoneNumber']),
      'email': _orNull(v['email']),
      'commissionRate': _orNull(v['commissionRate']),
      'notes': _orNull(v['notes']),
    },
  ),
};

/// One hub form, add (no [row]) or edit.
class WaterHubFormScreen extends StatefulWidget {
  const WaterHubFormScreen({super.key, required this.session, required this.company, required this.form, this.row});
  final Session session;
  final Company company;
  final HubForm form;
  final Map<String, dynamic>? row;

  @override
  State<WaterHubFormScreen> createState() => _WaterHubFormScreenState();
}

class _WaterHubFormScreenState extends State<WaterHubFormScreen> {
  late final Map<String, Object?> _v;
  final Map<String, TextEditingController> _ctl = {};
  List<Map<String, dynamic>>? _vehicles;
  bool _busy = false;

  HubForm get _f => widget.form;

  @override
  void initState() {
    super.initState();
    final row = widget.row;
    // The modal's useEffect: each key from the row, else the default.
    _v = {
      for (final MapEntry(:key, :value) in _f.defaults.entries)
        key: row == null ? value : (row[key] ?? value),
    };
    for (final s in _f.sections) {
      for (final f in s.fields) {
        if (f.kind == HubKind.text || f.kind == HubKind.textarea || f.kind == HubKind.number || f.kind == HubKind.decimal) {
          _ctl[f.key] = TextEditingController(text: _v[f.key] == null ? '' : '${_v[f.key]}');
        }
      }
    }
    if (_f.sections.any((s) => s.fields.any((f) => f.kind == HubKind.vehicle))) _loadVehicles();
  }

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadVehicles() async {
    try {
      final res = await widget.session.farmClient.get('/api/Water/vehicles', query: {'farmId': widget.company.farmId});
      if (!mounted) return;
      setState(() => _vehicles = [
            for (final r in LookupLoader.rowsIn(res))
              if (r is Map) Map<String, dynamic>.from(r),
          ]);
    } catch (_) {
      if (mounted) setState(() => _vehicles = const []);
    }
  }

  void _collect() {
    for (final s in _f.sections) {
      for (final f in s.fields) {
        final c = _ctl[f.key];
        if (c == null) continue;
        final t = c.text.trim();
        _v[f.key] = switch (f.kind) {
          // Number(e.target.value) || 0, as the modals' NumberInputs do.
          HubKind.number => int.tryParse(t) ?? num.tryParse(t)?.round() ?? 0,
          HubKind.decimal => num.tryParse(t) ?? 0,
          _ => c.text,
        };
      }
    }
  }

  Future<void> _save() async {
    _collect();
    final messenger = ScaffoldMessenger.of(context);
    final missing = _f.requiredCheck(_v);
    if (missing != null) {
      messenger.showSnackBar(SnackBar(content: Text(missing)));
      return;
    }
    setState(() => _busy = true);
    final client = widget.session.farmClient;
    final body = {..._f.payload(_v), 'farmId': widget.company.farmId};
    try {
      final row = widget.row;
      if (row != null) {
        final id = row[_f.idKey];
        await client.put('${_f.path}/$id', body: {...body, _f.idKey: id});
      } else {
        await client.post(_f.path, body: {...body, ..._f.extraOnCreate});
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
      messenger.showSnackBar(SnackBar(content: Text('${_cap(_f.singular)} ${row != null ? 'updated' : 'added'}')));
    } on ApiException catch (e) {
      if (mounted) setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text('Save failed. ${e.message}')));
    }
  }

  Widget _control(HubField f) {
    switch (f.kind) {
      case HubKind.text:
        return AppInput(controller: _ctl[f.key], hintText: f.placeholder);
      case HubKind.textarea:
        return AppTextarea(controller: _ctl[f.key]);
      case HubKind.number:
        return AppNumberInput(controller: _ctl[f.key]);
      case HubKind.decimal:
        return AppNumberInput(controller: _ctl[f.key], allowDecimal: true);
      case HubKind.select:
        final cur = '${_v[f.key] ?? ''}';
        return AppSelect<String>(
          value: cur.isEmpty ? null : cur,
          items: [
            for (final (v, l) in f.options) AppSelectItem(value: v, label: l),
            // A value saved before this list existed still shows.
            if (cur.isNotEmpty && !f.options.any((o) => o.$1 == cur)) AppSelectItem(value: cur, label: cur),
          ],
          onChanged: (v) => setState(() => _v[f.key] = v),
        );
      case HubKind.vehicle:
        final cur = _v[f.key] == null ? null : '${_v[f.key]}';
        final list = _vehicles ?? const <Map<String, dynamic>>[];
        return AppSelect<String>(
          value: list.any((v) => '${v['waterVehicleId']}' == cur) ? cur : null,
          enabled: _vehicles != null,
          hintText: _vehicles == null ? 'Loading…' : (f.placeholder ?? 'Select…'),
          items: [
            for (final v in list)
              AppSelectItem(value: '${v['waterVehicleId']}', label: '${v['vehicleName'] ?? ''}'),
          ],
          onChanged: (v) => setState(() => _v[f.key] = v == null ? null : int.tryParse(v)),
        );
      case HubKind.toggle:
        return AppSwitchRow(
          label: f.toggleText ?? f.label,
          value: _v[f.key] == true,
          onChanged: (v) => setState(() => _v[f.key] = v),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final editing = widget.row != null;
    final title = '${editing ? 'Edit' : 'New'} ${_f.singular}';
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            if (_f.description != null)
              Text(_f.description!, style: TextStyle(fontSize: 11.5, color: tokens.mutedForeground)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
        children: [
          for (final s in _f.sections) ...[
            FormSection(title: s.title, color: s.color, columns: s.columns, children: [
              for (final f in s.fields)
                AppField(label: f.label, required: f.required, full: f.full || s.columns == 1, child: _control(f)),
            ]),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: AppButton(
                label: 'Cancel',
                variant: AppButtonVariant.outline,
                size: AppButtonSize.lg,
                fullWidth: true,
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppButton(
                label: _busy ? 'Saving…' : 'Save',
                size: AppButtonSize.lg,
                fullWidth: true,
                busy: _busy,
                onPressed: _busy ? null : _save,
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
