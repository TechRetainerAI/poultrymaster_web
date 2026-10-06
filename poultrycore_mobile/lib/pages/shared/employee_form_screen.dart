import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/tokens.dart';
import '../../design/ui/buttons.dart';
import '../../design/ui/form_section.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';

/// Users & Permissions → Add / Edit employee, as the web's
/// `components/employees/add-employee-dialog.tsx` and `edit-employee-dialog.tsx`.
///
/// Both talk to the Login API at `/api/Admin/employees` — POST to create, PUT
/// `/{id}` to update. The page's list endpoint (`/Admin/company-employees`)
/// is read-only, which is why the generic form answered 405.
class EmployeeFormScreen extends StatefulWidget {
  const EmployeeFormScreen({
    super.key,
    required this.session,
    required this.company,
    this.existing,
  });

  final Session session;
  final Company company;
  final Map<String, dynamic>? existing;

  @override
  State<EmployeeFormScreen> createState() => _EmployeeFormScreenState();
}

/// lib/employees/permissions.ts — ADMIN_PERMISSION_OPTIONS and defaults.
const _adminOptions = <(String, String, String?)>[
  ('changeGroupInfo', 'Change group info', null),
  ('deleteMessages', 'Delete messages', null),
  ('banUsers', 'Ban users', null),
  ('inviteUsers', 'Invite users via link', null),
  ('pinMessages', 'Pin messages', null),
  ('manageStories', 'Manage stories', '0/3 by default'),
  ('manageVideoChats', 'Manage video chats', null),
  ('remainAnonymous', 'Remain anonymous', null),
  ('addNewAdmins', 'Add new admins', null),
];
const _adminDefaults = {
  'changeGroupInfo': true,
  'deleteMessages': true,
  'banUsers': true,
  'inviteUsers': true,
  'pinMessages': true,
  'manageStories': false,
  'manageVideoChats': true,
  'remainAnonymous': false,
  'addNewAdmins': false,
};

/// STAFF_FEATURE_PERMISSION_OPTIONS, grouped by the module each belongs to.
/// The web shows `core` plus the module of the company being administered
/// (staffPermissionOptionsForCompanyType), so a Water company never sees the
/// Poultry switches and the other way round.
const _coreOptions = <(String, String, String?)>[
  ('canEnterSales', 'Enter Sales', null),
  ('canEnterExpenses', 'Enter Expenses', null),
  ('canViewCashLedger', 'View Cash Ledger', null),
  ('canSeeEmployees', 'See Employees', null),
  ('canViewReports', 'View reports', null),
  ('canViewFinancial', 'View Financial (Cash, Payments umbrella)', null),
  ('canViewCustomers', 'View Customers', null),
  ('canViewActivityLog', 'View Activity Log', null),
  ('canViewSettings', 'View Settings', null),
];

const _moduleOptions = <CompanyType, List<(String, String, String?)>>{
  CompanyType.poultry: [
    ('canViewFeedProduction', 'View Feed Production', null),
    ('canManageFeedProduction', 'Manage Feed Production (produce, post, reverse)', null),
    ('canViewFeedProductionCost', 'View Feed Production Costs', null),
  ],
  CompanyType.water: [
    ('canViewWaterProduction', 'View Water Production',
        'Production, Batch Production, Products, Machines, Boreholes'),
    ('canViewWaterDeliveries', 'View Deliveries',
        'Driver returns, Drivers, Vehicles, Routes, Driver collection report'),
    ('canViewWaterInventory', 'View Water Inventory',
        'Stock movement, Inventory, Raw materials, Damages & loss, Production losses'),
    ('canViewInternalUse', 'View Internal Use',
        'Stock consumed internally — staff welfare, owner use, donations, samples, testing'),
    ('canViewWaterMaintenance', 'View Maintenance', null),
    ('canViewWaterPayroll', 'View Water Payroll', null),
    ('canViewWaterSetup', 'View Water Setup', 'Setup and Company Setup'),
  ],
  CompanyType.restaurant: [
    ('canViewRestaurantPOS', 'View POS & Orders', 'Point of sale, create and manage orders'),
    ('canViewRestaurantKDS', 'View Kitchen Display', 'Kitchen display system, order bumping'),
    ('canViewRestaurantMenu', 'View Menu Management', 'Menu items, categories, modifiers, combos'),
    ('canViewRestaurantFloorPlan', 'View Floor Plan & Tables', 'Table layout, status, seating'),
    ('canViewRestaurantReservations', 'View Reservations & Waitlist', 'Bookings, waitlist, no-show tracking'),
    ('canViewRestaurantOnlineOrders', 'View Online Ordering', 'QR codes, promo codes, online order settings'),
    ('canViewRestaurantDelivery', 'View Delivery Management',
        'Drivers, dispatch, delivery zones, third-party platforms'),
    ('canViewRestaurantStaff', 'View Restaurant Staff', 'Staff roster, roles, attendance'),
    ('canViewRestaurantSetup', 'View Restaurant Setup',
        'Profile, schedules, modifier groups, configuration'),
  ],
};

List<(String, String, String?)> _staffOptionsFor(CompanyType type) =>
    [..._coreOptions, ...?_moduleOptions[type]];

/// DEFAULT_STAFF_FEATURE_PERMISSIONS. Every key the web carries is sent, not
/// only the Poultry ones shown, so saving never wipes another module's flags.
const _staffDefaults = {
  'canEnterSales': true, 'canEnterExpenses': true, 'canViewCashLedger': true,
  'canSeeEmployees': false, 'canViewReports': true, 'canViewFinancial': true,
  'canViewCustomers': true, 'canViewActivityLog': true, 'canViewSettings': true,
  'canViewFeedProduction': true, 'canManageFeedProduction': true,
  'canViewFeedProductionCost': true, 'canViewWaterProduction': true,
  'canViewWaterDeliveries': true, 'canViewWaterInventory': true,
  'canViewInternalUse': true, 'canViewWaterMaintenance': true,
  'canViewWaterPayroll': true, 'canViewWaterSetup': true,
  'canViewHotelRooms': true, 'canViewHotelBookings': true,
  'canViewHotelHousekeeping': true, 'canViewHotelBilling': true,
  'canViewHotelRestaurant': true, 'canViewHotelStaff': true,
  'canViewHotelPayroll': true, 'canViewHotelInventory': true,
  'canViewHotelMaintenance': true, 'canViewHotelSetup': true,
  'canViewRestaurantPOS': true, 'canViewRestaurantKDS': true,
  'canViewRestaurantMenu': true, 'canViewRestaurantFloorPlan': true,
  'canViewRestaurantReservations': true, 'canViewRestaurantOnlineOrders': true,
  'canViewRestaurantDelivery': true, 'canViewRestaurantStaff': true,
  'canViewRestaurantSetup': true,
};

class _EmployeeFormScreenState extends State<EmployeeFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _phone = TextEditingController();
  final _user = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _title = TextEditingController();

  bool _isAdmin = false;
  final _admin = Map<String, bool>.of(_adminDefaults);
  final _staff = Map<String, bool>.of(_staffDefaults);
  bool _showStaff = false;

  bool _loading = false;
  bool _saving = false;
  String? _error;
  String? _createdDate;

  bool get _editing => widget.existing != null;
  String? get _id => widget.existing?['id']?.toString();

  @override
  void initState() {
    super.initState();
    final row = widget.existing;
    if (row != null) {
      _seed(row);
      _loadFull();
    }
  }

  /// The list row lacks the permission maps; the web reads the single
  /// employee for them, so this does too.
  Future<void> _loadFull() async {
    final id = _id;
    if (id == null) return;
    setState(() => _loading = true);
    try {
      final res = await widget.session.loginClient.get('/api/Admin/employees/$id');
      final data = res is Map && res['data'] is Map ? res['data'] : res;
      if (data is Map && mounted) _seed(Map<String, dynamic>.from(data));
    } on ApiException catch (e) {
      if (mounted) _error = e.message;
    } catch (_) {
      // The row already filled the profile; permissions stay at defaults.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static bool? _bool(Object? v) {
    if (v is bool) return v;
    if (v is String) {
      final s = v.trim().toLowerCase();
      if (s == 'true') return true;
      if (s == 'false') return false;
    }
    return null;
  }

  /// resolveEmployeePermissions: camelCase or PascalCase, featurePermissions
  /// or featureAccess, unknown keys keep their defaults.
  void _seed(Map<String, dynamic> d) {
    String s(String k) => '${d[k] ?? ''}';
    _first.text = s('firstName');
    _last.text = s('lastName');
    _phone.text = s('phoneNumber');
    _email.text = s('email');
    _user.text = s('userName');
    _createdDate = d['createdDate']?.toString();
    _isAdmin = _bool(d['isAdmin']) ?? _isAdmin;
    _title.text = '${d['adminTitle'] ?? _title.text}';
    final adm = d['permissions'];
    if (adm is Map) {
      for (final k in _admin.keys.toList()) {
        final b = _bool(adm[k] ?? adm[k[0].toUpperCase() + k.substring(1)]);
        if (b != null) _admin[k] = b;
      }
    }
    final feat = d['featurePermissions'] ?? d['featureAccess'];
    if (feat is Map) {
      for (final k in _staff.keys.toList()) {
        final b = _bool(feat[k] ?? feat[k[0].toUpperCase() + k.substring(1)]);
        if (b != null) _staff[k] = b;
      }
    }
  }

  @override
  void dispose() {
    for (final c in [_first, _last, _phone, _user, _email, _password, _confirm, _title]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fail(String msg) {
    setState(() => _error = msg);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) {
      _fail(_editing
          ? 'First name, last name, email, and phone number are required.'
          : 'First name, last name, phone number, and email are required.');
      return;
    }
    if (!_editing) {
      if (_password.text != _confirm.text) return _fail('Passwords do not match');
      if (_password.text.length < 4) {
        return _fail('Password must be at least 4 characters long');
      }
      if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(_user.text)) {
        return _fail('Username can only contain letters, digits, and underscores');
      }
    }

    setState(() => _saving = true);
    final common = {
      'FirstName': _first.text.trim(),
      'LastName': _last.text.trim(),
      'PhoneNumber': _phone.text.trim(),
      'Email': _email.text.trim(),
      'IsAdmin': _isAdmin,
      'AdminTitle': _isAdmin && _title.text.trim().isNotEmpty ? _title.text.trim() : null,
      'Permissions': _isAdmin ? _admin : null,
      'FeaturePermissions': _staff,
      'FeatureAccess': _staff,
    };
    final client = widget.session.loginClient;
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (_editing) {
        await client.put('/api/Admin/employees/$_id', body: {'Id': _id, ...common});
        if (!mounted) return;
        Navigator.of(context).pop(true);
        messenger.showSnackBar(const SnackBar(content: Text('Employee updated successfully.')));
        return;
      }
      await client.post('/api/Admin/employees', body: {
        ...common,
        'UserName': _user.text.trim(),
        'Password': _password.text,
        'FarmId': widget.company.farmId,
        'FarmName': widget.company.name,
      });
      messenger.showSnackBar(const SnackBar(content: Text('Employee created successfully.')));
      // The web emails the new login details straight after creating.
      final to = _email.text.trim();
      try {
        await widget.session.farmClient.post('/api/Email/send-credentials', body: {
          'Email': to,
          'UserName': _user.text.trim(),
          'Password': _password.text,
          'FarmName': widget.company.name,
        });
        messenger.showSnackBar(SnackBar(content: Text('Login details sent to $to.')));
      } on ApiException catch (e) {
        messenger.showSnackBar(SnackBar(content: Text("Couldn't email credentials: ${e.message}")));
      } catch (_) {
        messenger.showSnackBar(const SnackBar(content: Text("Couldn't email credentials.")));
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save: $e';
      });
    }
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
            Text(_editing ? 'Edit Employee' : 'Add New Employee',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            Text(
              _editing
                  ? 'Update employee profile and access permissions'
                  : 'Create a staff member or configure an admin with custom permissions',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: tokens.mutedForeground),
            ),
          ],
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) ...[
              _ErrorBox(message: _error!),
              const SizedBox(height: 12),
            ],
            FormSection(title: 'Personal Information', color: SectionColor.indigo, children: [
              AppField(label: 'First Name', required: true,
                  child: AppInput(controller: _first, hintText: 'John', validator: _req)),
              AppField(label: 'Last Name', required: true,
                  child: AppInput(controller: _last, hintText: 'Doe', validator: _req)),
              if (!_editing)
                AppField(label: 'Phone Number', required: true,
                    child: AppInput(controller: _phone, hintText: '+233 533431086',
                        keyboardType: TextInputType.phone, validator: _req)),
            ]),
            const SizedBox(height: 12),
            if (_editing) ...[
              FormSection(title: 'Contact Information', color: SectionColor.blue, children: [
                AppField(label: 'Email Address', required: true,
                    child: AppInput(controller: _email, hintText: 'john@example.com',
                        keyboardType: TextInputType.emailAddress, validator: _req)),
                AppField(label: 'Phone Number', required: true,
                    child: AppInput(controller: _phone, hintText: '+1 (555) 123-4567',
                        keyboardType: TextInputType.phone, validator: _req)),
              ]),
              const SizedBox(height: 12),
              FormSection(title: 'Account Information', color: SectionColor.slate, columns: 1, children: [
                AppField(label: 'Username', full: true,
                    child: Text(_user.text.isEmpty ? 'Not set' : '@${_user.text}')),
                AppField(label: 'Employee ID', full: true,
                    child: Text(_id ?? '—', style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
                if (_createdDate != null)
                  AppField(label: 'Created', full: true, child: Text(_createdDate!.split('T').first)),
              ]),
            ] else
              FormSection(title: 'Account Information', color: SectionColor.green, children: [
                AppField(label: 'Username', required: true,
                    hint: 'Letters, digits, underscores',
                    child: AppInput(controller: _user, hintText: 'james_quayson', validator: _req)),
                AppField(label: 'Email', required: true,
                    child: AppInput(controller: _email, hintText: 'employee@example.com',
                        keyboardType: TextInputType.emailAddress, validator: _req)),
                AppField(label: 'Password', required: true, hint: 'Min 4 characters',
                    child: AppInput(controller: _password, hintText: 'At least 4 characters',
                        obscureText: true, validator: _req)),
                AppField(label: 'Confirm Password', required: true,
                    child: AppInput(controller: _confirm, hintText: 'Re-enter password',
                        obscureText: true, validator: _req)),
              ]),
            const SizedBox(height: 12),
            _adminSection(),
            const SizedBox(height: 12),
            _staffSection(),
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
                    label: _editing
                        ? 'Save Changes'
                        : _isAdmin
                            ? 'Create Admin'
                            : 'Create Employee',
                    size: AppButtonSize.lg,
                    fullWidth: true,
                    busy: _saving,
                    onPressed: _saving || _loading ? null : _save,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _adminSection() {
    final name = _first.text.isNotEmpty
        ? _first.text
        : _user.text.isNotEmpty
            ? _user.text
            : 'New admin';
    return FormSection(title: 'Admin Access', color: SectionColor.sky, columns: 1, children: [
      AppField(
        label: '',
        full: true,
        child: AppSwitchRow(
          label: _editing ? 'Grant administrator access' : 'Create as administrator',
          description: _editing
              ? 'Turn on to configure admin-only actions for this employee.'
              : 'Enable this to assign granular admin permissions.',
          value: _isAdmin,
          onChanged: (v) => setState(() => _isAdmin = v),
        ),
      ),
      if (_isAdmin) ...[
        if (!_editing)
          AppField(
            label: '',
            full: true,
            child: _Note(
              title: name,
              body: 'Configure what this admin can do. Permissions can be updated later.',
            ),
          ),
        AppField(
          label: 'Custom title (optional)',
          full: true,
          hint: _editing ? null : 'Shown instead of the default admin label.',
          child: AppInput(controller: _title, hintText: 'admin'),
        ),
        AppField(
          label: 'What can this admin do?',
          full: true,
          child: _ToggleList(children: [
            for (final (key, label, hint) in _adminOptions)
              AppSwitchRow(
                label: label,
                description: hint,
                value: _admin[key] ?? false,
                onChanged: (v) => setState(() => _admin[key] = v),
              ),
          ]),
        ),
      ],
    ]);
  }

  Widget _staffSection() {
    final tokens = context.tokens;
    return FormSection(title: 'Staff Page Access', color: SectionColor.slate, columns: 1, children: [
      AppField(
        label: '',
        full: true,
        child: Text(
          _editing
              ? 'Set exactly what this employee can access.'
              : 'Set exactly what employees can access.',
          style: TextStyle(fontSize: 12, color: tokens.mutedForeground),
        ),
      ),
      AppField(
        label: '',
        full: true,
        child: OutlinedButton(
          onPressed: () => setState(() => _showStaff = !_showStaff),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
          child: Row(
            children: [
              const Expanded(child: Text('Select Staff Permissions')),
              AnimatedRotation(
                turns: _showStaff ? .5 : 0,
                duration: const Duration(milliseconds: 150),
                child: const Icon(Icons.expand_more, size: 18),
              ),
            ],
          ),
        ),
      ),
      if (_showStaff)
        AppField(
          label: '',
          full: true,
          child: _ToggleList(children: [
            for (final (key, label, hint) in _staffOptionsFor(widget.company.type))
              AppSwitchRow(
                label: label,
                description: hint,
                value: _staff[key] ?? false,
                onChanged: (v) => setState(() => _staff[key] = v),
              ),
          ]),
        ),
    ]);
  }
}

/// `rounded-lg border divide-y` around a list of switches.
class _ToggleList extends StatelessWidget {
  const _ToggleList({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(Dim.radiusMd),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, color: tokens.border),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              child: children[i],
            ),
          ],
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x99ECFEFF), // cyan-50/60
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(Dim.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(body, style: TextStyle(fontSize: 12, color: tokens.mutedForeground)),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: error.withValues(alpha: .08),
        border: Border.all(color: error.withValues(alpha: .4)),
        borderRadius: BorderRadius.circular(Dim.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: error),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: TextStyle(color: error, fontSize: 13))),
        ],
      ),
    );
  }
}
