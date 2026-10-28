// Hotel → Setup → People → Staff, as `app/hotel-staff/page.tsx`: the count
// line, Add Staff, the status and department filter buttons, a card per staff
// member (department badge, Active / Inactive, salary, what they owe on loans,
// the Employee badge) with Edit, Make employee and Delete, and the Add / Edit
// dialog (Person, Role & Pay, Status).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../design/ui/form_dialog.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/reports/report_routes.dart' show openAppHref;
import '../poultry/sales/balances_widgets.dart' show LoadingLine;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/staff_employee_link.dart';
import 'hotel_kit.dart';

const hotelDepartments = [
  'Front Desk',
  'Housekeeping',
  'Restaurant',
  'Kitchen',
  'Bar',
  'Maintenance',
  'Security',
  'Management',
  'Finance',
  'Laundry',
  'Spa',
  'Other',
];

const hotelStaffRoles = [
  'Receptionist',
  'Front Desk Agent',
  'Night Auditor',
  'Concierge',
  'Cleaner',
  'Room Attendant',
  'Housekeeping Supervisor',
  'Laundry Attendant',
  'Chef',
  'Sous Chef',
  'Cook',
  'Kitchen Porter',
  'Dishwasher',
  'Waiter',
  'Waitress',
  'Server',
  'Bartender',
  'Host/Hostess',
  'Bellboy',
  'Porter',
  'Doorman',
  'Maintenance Technician',
  'Electrician',
  'Plumber',
  'Groundskeeper',
  'Security Guard',
  'Night Watchman',
  'Security Officer',
  'Hotel Manager',
  'General Manager',
  'Assistant Manager',
  'Duty Manager',
  'Supervisor',
  'Front Office Manager',
  'Accountant',
  'HR Officer',
  'Admin Assistant',
  'Housekeeper Supervisor',
  'Spa Therapist',
  'Pool Attendant',
  'Driver',
  'Other',
];

/// DEPT_COLOR (bg-*-100 text-*-700; anything else slate).
(Color, Color) _deptColors(String d) => switch (d) {
  'Front Desk' => (TColors.blue100, const Color(0xFF1D4ED8)),
  'Housekeeping' => (TColors.emerald100, TColors.emerald700),
  'Restaurant' => (TColors.violet100, TColors.violet700),
  'Kitchen' => (const Color(0xFFFFEDD5), const Color(0xFFC2410C)),
  'Bar' => (TColors.amber100, TColors.amber700),
  'Security' => (TColors.red100, TColors.red700),
  'Management' => (const Color(0xFFE0E7FF), const Color(0xFF4338CA)),
  'Finance' => (const Color(0xFFCCFBF1), const Color(0xFF0F766E)),
  'Laundry' => (const Color(0xFFCFFAFE), const Color(0xFF0E7490)),
  'Spa' => (const Color(0xFFFCE7F3), const Color(0xFFBE185D)),
  _ => (TColors.slate100, TColors.slate700),
};

class HotelStaffScreen extends StatefulWidget {
  const HotelStaffScreen({super.key, required this.session, required this.company, this.prefill, this.onCreated});
  final Session session;
  final Company company;

  /// Employees → "Add as staff": the Add Staff dialog opens prefilled from the
  /// employee, and the saved row is handed to [onCreated] to be linked.
  final EmployeePrefill? prefill;
  final Future<void> Function(Object? created)? onCreated;

  @override
  State<HotelStaffScreen> createState() => _HotelStaffScreenState();
}

class _HotelStaffScreenState extends State<HotelStaffScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _staff = [];
  // What each staff member still owes on loans and advances: (amount, active loans).
  Map<int, (num, int)> _owed = {};
  // Staff id -> the login it is linked to (362).
  Map<int, String> _links = {};
  String _dept = 'all', _status = 'all';

  ApiClient get _api => widget.session.farmClient;
  Map<String, dynamic> get _q => {'farmId': widget.company.farmId};

  @override
  void initState() {
    super.initState();
    _load().then((_) {
      if (widget.prefill != null && mounted) _openForm(prefill: widget.prefill);
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _staff = hotelRows(await _api.get('/api/Hotel/staff', query: _q));
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed to load staff', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
    // Loan balances are extra: if they fail to load, the staff list still works.
    try {
      final r = await _api.get('/api/Hotel/employee-loans/staff-report', query: _q);
      _owed = {
        for (final x in hotelRows(r))
          if (tNum(x['outstanding']) > 0) tIntOrNull(x['hotelStaffId']) ?? 0: (tNum(x['outstanding']), tIntOrNull(x['activeLoans']) ?? 0),
      };
    } catch (_) {
      _owed = {};
    }
    try {
      _links = {for (final l in await getStaffUserLinks(widget.session, widget.company)) l.staffId: l.userId};
    } catch (_) {}
    if (mounted) setState(() {});
  }

  int _id(Map s) => tIntOrNull(s['hotelStaffId']) ?? 0;
  bool _active(Map s) => s['isActive'] == true || s['isActive'] == 'true';
  String _name(Map s) => '${tStr(s['firstName'])} ${tStr(s['lastName'])}'.trim();

  Future<void> _openForm({Map<String, dynamic>? existing, EmployeePrefill? prefill}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _StaffDialog(
        api: _api,
        farmId: widget.company.farmId,
        existing: existing,
        prefill: prefill,
        onCreated: prefill == null ? null : widget.onCreated,
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _makeEmployee(Map<String, dynamic> s) async {
    await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => makeEmployeeScreen(widget.session, widget.company, s, 'hotelStaffId')));
    _load();
  }

  Future<void> _delete(Map s) async {
    final ok = await hotelConfirmDelete(
      context,
      title: 'Remove staff member?',
      message: 'Remove ${_name(s)}? This cannot be undone.',
      onConfirm: () => _api.delete('/api/Hotel/staff/${_id(s)}', query: _q),
    );
    if (!ok || !mounted) return;
    trackerToast(context, 'Staff removed');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/hotel-staff');
    final active = _staff.where(_active).length;
    final inactive = _staff.length - active;
    final deptCounts = <String, int>{};
    for (final s in _staff) {
      deptCounts[tStr(s['department'])] = (deptCounts[tStr(s['department'])] ?? 0) + 1;
    }
    final depts = deptCounts.keys.toList()..sort();
    final rows = [
      for (final s in _staff)
        if ((_dept == 'all' || tStr(s['department']) == _dept) && (_status == 'all' || (_status == 'active') == _active(s))) s,
    ];
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Staff')),
      body: _loading
          ? const Padding(padding: EdgeInsets.all(20), child: LoadingLine('Loading…'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
                children: [
                  HotelPageHeader(
                    icon: Icons.groups_outlined,
                    title: 'Staff',
                    description: '(${_staff.length} total — $active active, $inactive inactive)',
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    style: hotelPrimary.copyWith(minimumSize: const WidgetStatePropertyAll(Size.fromHeight(46))),
                    onPressed: () => _openForm(),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Staff'),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _chip('All (${_staff.length})', _status == 'all', hotelViolet, () => setState(() => _status = 'all')),
                      _chip('Active ($active)', _status == 'active', const Color(0xFF16A34A), () => setState(() => _status = 'active')),
                      _chip('Inactive ($inactive)', _status == 'inactive', TColors.red600, () => setState(() => _status = 'inactive')),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _chip('All Depts', _dept == 'all', hotelViolet, () => setState(() => _dept = 'all')),
                      for (final d in depts) _chip('$d (${deptCounts[d]})', _dept == d, hotelViolet, () => setState(() => _dept = d)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (rows.isEmpty) hotelEmpty('No staff found. Add your hotel workers.', icon: Icons.groups_outlined),
                  for (final s in rows) ...[_row(s), const SizedBox(height: 10)],
                ],
              ),
            ),
    );
  }

  /// The web's filter buttons: filled in [color] when chosen, outline otherwise.
  Widget _chip(String label, bool on, Color color, VoidCallback onTap) => on
      ? FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: color,
            minimumSize: const Size(0, 34),
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          onPressed: onTap,
          child: Text(label, style: const TextStyle(fontSize: 13)),
        )
      : OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 34), padding: const EdgeInsets.symmetric(horizontal: 12)),
          onPressed: onTap,
          child: Text(label, style: const TextStyle(fontSize: 13)),
        );

  Widget _row(Map<String, dynamic> s) {
    final id = _id(s);
    final active = _active(s);
    final dept = tStr(s['department']);
    final (dbg, dfg) = _deptColors(dept);
    final salary = tNum(s['salaryAmount']);
    final owed = _owed[id];
    return HotelRowCard(
      dim: !active,
      lead: CircleAvatar(
        radius: 20,
        backgroundColor: TColors.violet100,
        child: Text(
          _name(s).isEmpty ? '?' : _name(s).characters.first.toUpperCase(),
          style: const TextStyle(fontWeight: FontWeight.w700, color: TColors.violet700),
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
              Text(
                _name(s),
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: TColors.slate900),
              ),
              if (_links.containsKey(id)) employeeBadge(),
            ],
          ),
          const SizedBox(height: 2),
          Text(tStr(s['role']), style: const TextStyle(fontSize: 12.5, color: TColors.slate600)),
          const SizedBox(height: 5),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              hotelBadge(dept, dbg, dfg),
              active ? hotelBadge('Active', TColors.green100, TColors.green700) : hotelBadge('Inactive', TColors.red100, TColors.red700),
            ],
          ),
          const SizedBox(height: 5),
          Wrap(
            spacing: 12,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(tStr(s['phone']).isEmpty ? '-' : tStr(s['phone']), style: const TextStyle(fontSize: 12, color: TColors.slate500)),
              Text(
                'Salary ${salary.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: TColors.slate700),
              ),
              if (owed != null)
                InkWell(
                  onTap: () => openAppHref(
                    context,
                    widget.session,
                    widget.company,
                    '/hotel-employee-loans?staffId=$id',
                    label: 'Employee Loans & Advances',
                  ),
                  child: Text(
                    'Owes ${owed.$1.toStringAsFixed(2)} · ${owed.$2} active',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: TColors.red600),
                  ),
                ),
            ],
          ),
        ],
      ),
      onEdit: () => _openForm(existing: s),
      extra: [
        if (!_links.containsKey(id))
          IconButton(
            tooltip: 'Make employee (give a login)',
            visualDensity: VisualDensity.compact,
            onPressed: () => _makeEmployee(s),
            icon: const Icon(Icons.key_outlined, size: 18),
          ),
      ],
      onDelete: () => _delete(s),
    );
  }
}

/// "Add Staff Member", or "Edit" and the person's name. Pops true once saved.
class _StaffDialog extends StatefulWidget {
  const _StaffDialog({required this.api, required this.farmId, this.existing, this.prefill, this.onCreated});
  final ApiClient api;
  final String farmId;
  final Map<String, dynamic>? existing;
  final EmployeePrefill? prefill;
  final Future<void> Function(Object? created)? onCreated;
  @override
  State<_StaffDialog> createState() => _StaffDialogState();
}

class _StaffDialogState extends State<_StaffDialog> {
  late final Map<String, dynamic> _e = widget.existing ?? const {};
  late final _first = TextEditingController(text: widget.prefill?.firstName ?? tStr(_e['firstName']));
  late final _last = TextEditingController(text: widget.prefill?.lastName ?? tStr(_e['lastName']));
  late final _phone = TextEditingController(text: widget.prefill?.phoneNumber ?? tStr(_e['phone']));
  late final _email = TextEditingController(text: widget.prefill?.email ?? tStr(_e['email']));
  late final _salary = TextEditingController(text: widget.existing == null ? '0' : tNum(_e['salaryAmount']).toString());
  late String _dept = widget.existing == null ? 'Front Desk' : tStr(_e['department']);
  late String _role = widget.existing == null ? 'Other' : tStr(_e['role']);
  late DateTime? _hire = widget.existing == null ? DateTime.now() : hotelParseYmd(tStr(_e['hireDate']));
  late bool _active = widget.existing == null || _e['isActive'] != false;
  bool _saving = false;

  bool get _edit => widget.existing != null;

  Future<void> _save() async {
    if (_first.text.trim().isEmpty || _last.text.trim().isEmpty) return trackerToast(context, 'Name is required', error: true);
    if (_role.isEmpty || _dept.isEmpty) return trackerToast(context, 'Role and Department are required', error: true);
    setState(() => _saving = true);
    final body = {
      'firstName': _first.text,
      'lastName': _last.text,
      'email': _email.text,
      'phone': _phone.text,
      'role': _role,
      'department': _dept,
      'salaryAmount': double.tryParse(_salary.text) ?? 0,
      'hireDate': _hire == null ? '' : hotelYmd(_hire!),
      'isActive': _active,
      'farmId': widget.farmId,
    };
    try {
      if (_edit) {
        await widget.api.put('/api/Hotel/staff/${_e['hotelStaffId']}', body: body);
        if (mounted) trackerToast(context, 'Staff updated');
      } else {
        // From an employee: they already have a login, so the create must not
        // make a second one from the email; link that login instead.
        final created = await widget.api.post('/api/Hotel/staff', body: {...body, 'skipLogin': widget.prefill != null});
        if (mounted) trackerToast(context, 'Staff member added');
        await widget.onCreated?.call(created);
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Save failed', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      scrollable: true,
      title: FormDialogTitle(
        icon: _edit ? Icons.edit_outlined : Icons.person_add_alt,
        color: FormColor.purple,
        text: _edit ? 'Edit ${tStr(_e['firstName'])} ${tStr(_e['lastName'])}' : 'Add Staff Member',
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TintedSection(
              title: 'Person',
              color: FormColor.blue,
              children: [
                FilterLabel('First Name *', AppInput(controller: _first, hintText: 'e.g. Ama')),
                FilterLabel('Last Name *', AppInput(controller: _last, hintText: 'e.g. Mensah')),
                FilterLabel('Phone', AppInput(controller: _phone, hintText: '0241234567', keyboardType: TextInputType.phone)),
                FilterLabel('Email', AppInput(controller: _email, hintText: 'ama@hotel.com', keyboardType: TextInputType.emailAddress)),
              ],
            ),
            const SizedBox(height: 12),
            TintedSection(
              title: 'Role & Pay',
              color: FormColor.amber,
              children: [
                FilterLabel(
                  'Department *',
                  AppSelect<String>(
                    value: _dept,
                    items: [for (final d in hotelDepartments) AppSelectItem(value: d, label: d)],
                    onChanged: (v) => setState(() => _dept = v ?? _dept),
                  ),
                ),
                FilterLabel(
                  'Role *',
                  AppSelect<String>(
                    value: _role,
                    items: [for (final r in hotelStaffRoles) AppSelectItem(value: r, label: r)],
                    onChanged: (v) => setState(() => _role = v ?? _role),
                  ),
                ),
                FilterLabel(
                  'Monthly Salary',
                  AppInput(
                    controller: _salary,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                  ),
                ),
                FilterLabel('Hire Date', AppDateField(value: _hire, onChanged: (d) => setState(() => _hire = d))),
              ],
            ),
            const SizedBox(height: 12),
            TintedSection(
              title: 'Status',
              color: FormColor.slate,
              children: [
                AppSwitchRow(
                  label: 'Active',
                  description: _active ? 'Active — employee is on payroll' : 'Inactive — employee will not appear in payroll runs',
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        FormDialogFooter(
          onCancel: () => Navigator.pop(context),
          cancelDisabled: _saving,
          children: [
            FilledButton(
              style: hotelPrimary,
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(_edit ? 'Update' : 'Add Staff'),
            ),
          ],
        ),
      ],
    ),
  );
}
