import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../design/ui/form_dialog.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../pages/shared/companies_screen.dart' show businessTypes;
import '../../pages/shared/employee_form_screen.dart';
import '../../pages/poultry/trackers/tracker_widgets.dart' show FilterLabel;
import '../../pages/web_page_screen.dart';
import '../../state/session.dart';
import 'access_management_panel.dart';

/// Business Office → Administration (`app/business-office/setup/page.tsx`):
/// Organization Profile, Employees & Users and Companies, each the web's panel
/// (organization-profile-panel.tsx, users-permissions-panel.tsx,
/// companies-panel.tsx) on the Login API endpoints those panels call.
class AdministrationScreen extends StatefulWidget {
  const AdministrationScreen({super.key, required this.session, this.initialTab = 'org', this.onCompaniesChanged});
  final Session session;

  /// `?tab=org|users|iam|companies`.
  final String initialTab;

  /// The Business Office list reloads after a company is made, edited or removed.
  final Future<void> Function()? onCompaniesChanged;

  @override
  State<AdministrationScreen> createState() => _AdministrationScreenState();
}

const _slate50 = Color(0xFFF8FAFC);
const _slate100 = Color(0xFFF1F5F9);
const _slate200 = Color(0xFFE2E8F0);
const _slate300 = Color(0xFFCBD5E1);
const _slate400 = Color(0xFF94A3B8);
const _slate500 = Color(0xFF64748B);
const _slate600 = Color(0xFF475569);
const _slate700 = Color(0xFF334155);
const _slate900 = Color(0xFF0F172A);
const _orange50 = Color(0xFFFFF7ED);
const _orange200 = Color(0xFFFED7AA);
const _orange700 = Color(0xFFC2410C);
const _red600 = Color(0xFFDC2626);

/// The tabs: (key, icon, phone label).
const _tabs = [
  ('org', Icons.manage_accounts_outlined, 'Organization'),
  ('users', Icons.group_outlined, 'Employees'),
  ('iam', Icons.key_outlined, 'Access'),
  ('companies', Icons.apartment_outlined, 'Companies'),
];

class _AdministrationScreenState extends State<AdministrationScreen> {
  late String _tab = _tabs.any((t) => t.$1 == widget.initialTab) ? widget.initialTab : 'org';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _slate50,
      appBar: AppBar(title: const Text('Administration')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: [
          const Text(
            'Set up your organization — your organization profile, employees and companies.',
            style: TextStyle(fontSize: 14, color: _slate600),
          ),
          const SizedBox(height: 14),
          // The web's tab list: a 2-up grid on a phone.
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: _slate100, borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                for (var row = 0; row < _tabs.length; row += 2)
                  Row(
                    children: [
                      for (final (key, icon, label) in _tabs.skip(row).take(2))
                        Expanded(
                          child: Material(
                            color: _tab == key ? Colors.white : Colors.transparent,
                            elevation: _tab == key ? 1 : 0,
                            borderRadius: BorderRadius.circular(9),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(9),
                              onTap: () => setState(() => _tab = key),
                              child: SizedBox(
                                height: 40,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(icon, size: 16, color: _tab == key ? _slate900 : _slate500),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        label,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: _tab == key ? _slate900 : _slate500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          switch (_tab) {
            'users' => _EmployeesPanel(session: widget.session),
            'iam' => AccessManagementPanel(session: widget.session),
            'companies' => _CompaniesPanel(session: widget.session, onChanged: widget.onCompaniesChanged),
            _ => _OrganizationPanel(session: widget.session),
          },
        ],
      ),
    );
  }
}

void _toast(BuildContext context, String title, {String? description, bool error = false}) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: error ? const Color(0xFFB91C1C) : null,
        content: Text(description == null || description.isEmpty ? title : '$title. $description'),
      ),
    );

Widget _card({required Widget child, EdgeInsets padding = const EdgeInsets.all(16)}) => Container(
  padding: padding,
  decoration: BoxDecoration(
    color: Colors.white,
    border: Border.all(color: _slate200),
    borderRadius: BorderRadius.circular(14),
    boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 6, offset: Offset(0, 2))],
  ),
  child: child,
);

const _loadingRow = Padding(
  padding: EdgeInsets.all(28),
  child: Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      SizedBox(width: 10),
      Text('Loading…', style: TextStyle(color: _slate500)),
    ],
  ),
);

// ---------------------------------------------------------------- organization

/// ORG_CURRENCIES.
const _orgCurrencies = [('GHS', 'GH₵', 'Ghana Cedi'), ('USD', r'$', 'US Dollar')];

class _OrganizationPanel extends StatefulWidget {
  const _OrganizationPanel({required this.session});
  final Session session;
  @override
  State<_OrganizationPanel> createState() => _OrganizationPanelState();
}

class _OrganizationPanelState extends State<_OrganizationPanel> {
  bool _loading = true, _saving = false, _savingCode = false, _editingCode = false, _copied = false;
  String _orgCode = '', _currency = '';
  final _name = TextEditingController(), _first = TextEditingController(), _last = TextEditingController();
  final _email = TextEditingController(), _phone = TextEditingController(), _country = TextEditingController();
  final _code = TextEditingController();

  ApiClient get _api => widget.session.loginClient;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _first, _last, _email, _phone, _country, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await _api.get('/api/Admin/organization/profile');
      final d = res is Map ? res : const {};
      String s(String k) => '${d[k] ?? ''}';
      _name.text = s('businessOfficeName');
      _first.text = s('firstName');
      _last.text = s('lastName');
      _email.text = s('email');
      _phone.text = s('phoneNumber');
      _currency = s('businessOfficeCurrency');
      _country.text = s('businessOfficeCountry');
      var code = s('organizationCode');
      if (code.isEmpty) code = widget.session.tokens.rememberedOrgCode ?? '';
      _orgCode = code.toUpperCase();
    } on ApiException catch (e) {
      if (mounted) _toast(context, 'Could not load organization profile', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _api.put(
        '/api/Admin/organization/profile',
        body: {
          'firstName': _first.text,
          'lastName': _last.text,
          'phoneNumber': _phone.text,
          'businessOfficeName': _name.text,
          'businessOfficeCurrency': _currency,
          'businessOfficeCountry': _country.text,
        },
      );
      if (mounted) _toast(context, 'Organization profile saved');
    } on ApiException catch (e) {
      if (mounted) _toast(context, 'Save failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _saveCode() async {
    final code = _code.text.trim().toUpperCase();
    if (code.length < 4) {
      _toast(context, 'Code must be at least 4 characters', error: true);
      return;
    }
    setState(() => _savingCode = true);
    try {
      final res = await _api.post('/api/Admin/organization/code', body: {'Code': code});
      final saved = ('${res is Map ? res['organizationCode'] ?? code : code}').toUpperCase();
      setState(() {
        _orgCode = saved;
        _code.clear();
        _editingCode = false;
      });
      if (mounted) _toast(context, 'Organization code updated', description: saved);
    } on ApiException catch (e) {
      if (mounted) _toast(context, "Couldn't save code", description: e.message, error: true);
    }
    if (mounted) setState(() => _savingCode = false);
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _orgCode));
    setState(() => _copied = true);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Widget _field(String label, TextEditingController c, {String? hint, TextInputType? keyboard}) =>
      FilterLabel(label, AppInput(controller: c, hintText: hint, keyboardType: keyboard));

  @override
  Widget build(BuildContext context) {
    if (_loading) return _loadingRow;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The code staff enter at login to join this organisation.
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _orange50,
              border: Border.all(color: _orange200),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ORGANIZATION CODE',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: .5, color: _orange700),
                          ),
                          if (_orgCode.isNotEmpty && !_editingCode) ...[
                            const SizedBox(height: 4),
                            Text(
                              _orgCode,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 21,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 4,
                                color: _slate900,
                              ),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            'Share this with staff — they enter it at login to join your organization.'
                            '${_orgCode.isEmpty && !_editingCode ? ' No code yet — tap Set code to create one (4–30 letters/numbers).' : ''}',
                            style: const TextStyle(fontSize: 12, color: _slate500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (!_editingCode) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (_orgCode.isNotEmpty)
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(backgroundColor: Colors.white),
                          onPressed: _copy,
                          icon: Icon(
                            _copied ? Icons.check : Icons.copy,
                            size: 16,
                            color: _copied ? const Color(0xFF059669) : null,
                          ),
                          label: Text(_copied ? 'Copied' : 'Copy'),
                        ),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: _slate900),
                        onPressed: () => setState(() {
                          _code.clear();
                          _editingCode = true;
                        }),
                        child: Text(_orgCode.isNotEmpty ? 'Update' : 'Set code'),
                      ),
                    ],
                  ),
                ] else ...[
                  const SizedBox(height: 10),
                  if (_orgCode.isNotEmpty)
                    Text(
                      'Enter a new code. Staff will need the new code to join — the current one ($_orgCode) stops working.',
                      style: const TextStyle(fontSize: 12, color: Color(0xFFB45309)),
                    ),
                  const SizedBox(height: 8),
                  AppInput(
                    controller: _code,
                    hintText: 'Enter new code',
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(30),
                      TextInputFormatter.withFunction((o, n) => n.copyWith(text: n.text.toUpperCase())),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: _slate900),
                          onPressed: _savingCode ? null : _saveCode,
                          child: _savingCode
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('Save new code'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(backgroundColor: Colors.white),
                        onPressed: () => setState(() {
                          _editingCode = false;
                          _code.clear();
                        }),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          _field('Organization / Business Office name', _name),
          const SizedBox(height: 12),
          FormPair(_field('Owner first name', _first), _field('Owner last name', _last)),
          const SizedBox(height: 12),
          _field('Email', _email, keyboard: TextInputType.emailAddress),
          const SizedBox(height: 12),
          _field('Phone', _phone, keyboard: TextInputType.phone),
          const SizedBox(height: 12),
          FilterLabel(
            'Default currency',
            AppSelect<String>(
              // A legacy value outside the list shows the placeholder until re-picked.
              value: _orgCurrencies.any((c) => c.$1 == _currency) ? _currency : null,
              hintText: 'Select currency',
              items: [
                for (final (code, symbol, label) in _orgCurrencies) AppSelectItem(value: code, label: '$symbol — $label ($code)'),
              ],
              onChanged: (v) => setState(() => _currency = v ?? _currency),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Used where no single company is in view — e.g. the Business Office company cards.',
            style: TextStyle(fontSize: 12, color: _slate500),
          ),
          const SizedBox(height: 12),
          _field('Country', _country, hint: 'e.g. Ghana'),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _slate900, minimumSize: const Size(150, 44)),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save changes'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- employees

/// TYPE_BADGE.
(Color, Color) _typeBadge(String type) => switch (type) {
  'Poultry' => (const Color(0xFFFEF3C7), const Color(0xFFB45309)),
  'Water' => (const Color(0xFFDBEAFE), const Color(0xFF1D4ED8)),
  _ => (_slate100, _slate700),
};

class _EmployeesPanel extends StatefulWidget {
  const _EmployeesPanel({required this.session});
  final Session session;
  @override
  State<_EmployeesPanel> createState() => _EmployeesPanelState();
}

class _EmployeesPanelState extends State<_EmployeesPanel> {
  bool _loading = true;
  List<Map<String, dynamic>> _employees = [];
  String _query = '';

  Session get _s => widget.session;
  List<Company> get _companies => _s.myCompanies;

  /// The org-wide pages need a company to hang off; none is open here.
  Company get _neutral => Company(farmId: '', name: _s.organisationName ?? 'Business Office', type: CompanyType.unknown);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _s.loginClient.get('/api/Admin/organization/employees');
      final rows = res is List ? res : (res is Map && res['data'] is List ? res['data'] as List : const []);
      _employees = [
        for (final r in rows)
          if (r is Map) Map<String, dynamic>.from(r),
      ];
    } on ApiException catch (e) {
      if (mounted) _toast(context, 'Could not load employees', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  static String _fullName(Map e) {
    final n = [e['firstName'], e['lastName']].where((x) => '${x ?? ''}'.isNotEmpty).join(' ');
    return n.isNotEmpty ? n : '${e['userName'] ?? ''}';
  }

  static String _displayName(Map e) {
    final n = _fullName(e);
    return n.isNotEmpty ? n : '${e['email'] ?? 'this employee'}';
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) _load();
  }

  Future<void> _delete(Map e) async {
    var deleting = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const FormDialogTitle(icon: Icons.delete_outline, color: FormColor.red, text: 'Delete employee'),
          content: SizedBox(
            width: 420,
            child: Text(
              'Delete ${_displayName(e)}? They lose access to every company in the organization and can no longer sign in. This cannot be undone.',
              style: const TextStyle(fontSize: 14, color: _slate600),
            ),
          ),
          actions: [
            FormDialogFooter(
              onCancel: () => Navigator.pop(ctx),
              cancelDisabled: deleting,
              children: [
                FilledButton(
                  style: formPrimary(FormColor.red),
                  onPressed: deleting
                      ? null
                      : () async {
                          setLocal(() => deleting = true);
                          try {
                            await _s.loginClient.delete('/api/Admin/employees/${e['id']}');
                            if (ctx.mounted) Navigator.pop(ctx, true);
                          } on ApiException {
                            if (ctx.mounted) Navigator.pop(ctx, false);
                          }
                        },
                  child: Text(deleting ? 'Deleting…' : 'Delete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (!mounted || ok == null) return;
    if (ok) {
      setState(
        () => _employees = [
          for (final x in _employees)
            if (x['id'] != e['id']) x,
        ],
      );
      _toast(context, 'Employee deleted', description: '${_displayName(e)} has been removed.');
    } else {
      _toast(context, 'Delete failed', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? _employees
        : [
            for (final e in _employees)
              if ([
                e['firstName'],
                e['lastName'],
                e['email'],
                e['userName'],
                e['farmName'],
              ].any((v) => '${v ?? ''}'.toLowerCase().contains(q)))
                e,
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Everyone in your organization. Grant each person access to the companies they work in.',
          style: TextStyle(fontSize: 14, color: _slate600),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: _slate900, minimumSize: const Size.fromHeight(46)),
          onPressed: () => _open(EmployeeFormScreen(session: _s, company: _neutral, boCompanies: _companies)),
          icon: const Icon(Icons.person_add_alt, size: 18),
          label: const Text('Add employee'),
        ),
        const SizedBox(height: 12),
        AppSearchField(hintText: 'Search employees…', onChanged: (v) => setState(() => _query = v)),
        const SizedBox(height: 14),
        if (_loading)
          _loadingRow
        else if (filtered.isEmpty)
          _card(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
            child: const Column(
              children: [
                Icon(Icons.verified_user_outlined, size: 40, color: _slate300),
                SizedBox(height: 10),
                Text(
                  'No employees yet',
                  style: TextStyle(fontWeight: FontWeight.w600, color: _slate700),
                ),
                SizedBox(height: 2),
                Text(
                  'Add your first employee, then assign them to companies.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: _slate500),
                ),
              ],
            ),
          )
        else
          for (final e in filtered) ...[_employeeCard(e), const SizedBox(height: 12)],
      ],
    );
  }

  Widget _employeeCard(Map<String, dynamic> e) {
    final companies = [
      for (final c in (e['companies'] is List ? e['companies'] as List : const []))
        if (c is Map) c,
    ];
    final n = companies.length;
    final isAdmin = e['isAdmin'] == true;
    final email = '${e['email'] ?? ''}';
    Widget action(String label, IconData icon, VoidCallback onTap, {bool danger = false}) => Expanded(
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: danger ? _red600 : _slate700,
          side: BorderSide(color: danger ? const Color(0xFFFECACA) : _slate200),
          minimumSize: const Size.fromHeight(40),
          padding: const EdgeInsets.symmetric(horizontal: 6),
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label),
      ),
    );
    return _card(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 19,
                backgroundColor: const Color(0xFFEEF2FF),
                child: Text(
                  (_fullName(e).isEmpty ? '?' : _fullName(e).characters.first).toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF4F46E5)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _fullName(e),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _slate900),
                    ),
                    Text(
                      email.isNotEmpty ? email : 'No email on file',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: email.isNotEmpty ? _slate500 : _slate400),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: isAdmin ? const Color(0xFFFFEDD5) : _slate100,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  isAdmin ? ('${e['adminTitle'] ?? ''}'.isEmpty ? 'Admin' : '${e['adminTitle']}') : 'Staff',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: isAdmin ? _orange700 : _slate700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: n == 0 ? _slate50 : const Color(0xFFF5F3FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Company access',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: n == 0 ? _slate500 : const Color(0xFF6D28D9)),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  n == 0 ? 'None' : '$n ${n == 1 ? 'company' : 'companies'}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: n == 0 ? _slate600 : const Color(0xFF6D28D9),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text('Username: ${e['userName'] ?? '—'}', style: const TextStyle(fontSize: 12.5, color: _slate500)),
          const SizedBox(height: 8),
          const Text('Companies', style: TextStyle(fontSize: 12, color: _slate500)),
          const SizedBox(height: 4),
          if (companies.isEmpty)
            const Text('No companies', style: TextStyle(fontSize: 12, color: _slate400))
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in companies)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: _typeBadge('${c['type']}').$1, borderRadius: BorderRadius.circular(5)),
                    child: Text('${c['name'] ?? ''}', style: TextStyle(fontSize: 11.5, color: _typeBadge('${c['type']}').$2)),
                  ),
              ],
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              action(
                'Edit',
                Icons.edit_outlined,
                () => _open(EmployeeFormScreen(session: _s, company: _neutral, existing: e, boCompanies: _companies)),
              ),
              const SizedBox(width: 8),
              action(
                'Access',
                Icons.apartment_outlined,
                () => _open(
                  EmployeeFormScreen(session: _s, company: _neutral, existing: e, boCompanies: _companies, accessOnly: true),
                ),
              ),
              const SizedBox(width: 8),
              action('Delete', Icons.delete_outline, () => _delete(e), danger: true),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- companies

/// COMPANY_TYPES: every type a business type can be, in list order.
final _companyTypes = <String>{for (final t in businessTypes) t.companyType}.toList();

class _CompaniesPanel extends StatefulWidget {
  const _CompaniesPanel({required this.session, this.onChanged});
  final Session session;
  final Future<void> Function()? onChanged;
  @override
  State<_CompaniesPanel> createState() => _CompaniesPanelState();
}

class _CompaniesPanelState extends State<_CompaniesPanel> {
  String _query = '', _typeFilter = 'all';
  String? _openingId;

  Session get _s => widget.session;
  List<Company> get _companies => _s.myCompanies;
  bool get _isAdmin => _companies.any((c) => (c.role ?? '').toLowerCase() != 'staff');
  bool get _canCreate {
    final me = _s.tokens.userId;
    return _isAdmin || (me != null && _companies.any((c) => c.ownerUserId == me));
  }

  Future<void> _changed() async {
    await _s.loadCompanies();
    await widget.onChanged?.call();
    if (mounted) setState(() {});
  }

  Future<void> _open(Company c) async {
    setState(() => _openingId = c.farmId);
    final nav = Navigator.of(context);
    final ok = await _s.setActive(c);
    if (!mounted) return;
    if (ok) {
      nav.popUntil((r) => r.isFirst);
    } else {
      setState(() => _openingId = null);
      _toast(context, "Couldn't open company", description: _s.error, error: true);
    }
  }

  Future<void> _create() async {
    final made = await showDialog<String>(
      context: context,
      builder: (_) => _CompanyDialog(session: _s),
    );
    if (made == null || !mounted) return;
    final [name, farmId, companyType, industry] = made.split('\n');
    _toast(context, 'Created $name');
    await _changed();
    // A business type with a template is set up before it is useful: switch
    // into it and hand over to the setup wizard, as the web does.
    if (industry.isNotEmpty && farmId.isNotEmpty && mounted) {
      final nav = Navigator.of(context);
      _s.pendingScreen = (s, company) => WebPageScreen(
        label: 'Set up $name',
        href: '/generic-setup/wizard?industry=${Uri.encodeQueryComponent(industry)}',
        company: company,
        session: s,
      );
      if (await _s.setActive(Company(farmId: farmId, name: name, type: companyTypeFrom(companyType)))) {
        nav.popUntil((r) => r.isFirst);
      } else {
        _s.pendingScreen = null;
      }
    }
  }

  Future<void> _edit(Company c) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CompanyDialog(session: _s, editing: c),
    );
    if (saved != true || !mounted) return;
    _toast(context, 'Company updated');
    await _changed();
  }

  Future<void> _delete(Company c) async {
    var deleting = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: FormDialogTitle(icon: Icons.delete_outline, color: FormColor.red, text: 'Delete company — ${c.name}'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'This removes '),
                      TextSpan(
                        text: c.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const TextSpan(
                        text:
                            ' from your Business Office. Its records are kept and it can be restored later, but it will '
                            'disappear from the app and no one will be able to open it.',
                      ),
                    ],
                  ),
                  style: const TextStyle(fontSize: 14, color: _slate600),
                ),
                const SizedBox(height: 8),
                const Text('Only the company owner can delete it.', style: TextStyle(fontSize: 12, color: _slate400)),
              ],
            ),
          ),
          actions: [
            FormDialogFooter(
              onCancel: () => Navigator.pop(ctx),
              cancelDisabled: deleting,
              children: [
                FilledButton(
                  style: formPrimary(FormColor.red),
                  onPressed: deleting
                      ? null
                      : () async {
                          setLocal(() => deleting = true);
                          try {
                            await _s.loginClient.delete('/api/Companies/${Uri.encodeComponent(c.farmId)}');
                            if (ctx.mounted) Navigator.pop(ctx, true);
                          } on ApiException catch (e) {
                            if (ctx.mounted) Navigator.pop(ctx, false);
                            if (mounted) _toast(context, 'Delete failed', description: e.message, error: true);
                          }
                        },
                  child: Text(deleting ? 'Deleting…' : 'Delete company'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    _toast(context, 'Deleted ${c.name}');
    await _changed();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final visible = [
      for (final c in _companies)
        if ((_typeFilter == 'all' || c.type.wire == _typeFilter) &&
            (q.isEmpty || '${c.name} ${c.type.wire} ${c.role ?? ''}'.toLowerCase().contains(q)))
          c,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'All companies in your Business Office. Open one to work inside it.',
          style: TextStyle(fontSize: 14, color: _slate600),
        ),
        if (_canCreate) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _slate900, minimumSize: const Size.fromHeight(46)),
            onPressed: _create,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New company'),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: AppSearchField(hintText: 'Search companies…', onChanged: (v) => setState(() => _query = v)),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 150,
              child: AppSelect<String>(
                value: _typeFilter,
                items: [
                  const AppSelectItem(value: 'all', label: 'All types'),
                  for (final t in _companyTypes) AppSelectItem(value: t, label: t),
                ],
                onChanged: (v) => setState(() => _typeFilter = v ?? 'all'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_companies.isEmpty)
          _card(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
            child: Column(
              children: [
                const Icon(Icons.apartment_outlined, size: 40, color: _slate300),
                const SizedBox(height: 10),
                Text(
                  _canCreate
                      ? 'Create your first company to get started.'
                      : "You don't currently have access to any company. Contact your Business Office administrator.",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _slate600),
                ),
              ],
            ),
          )
        else if (visible.isEmpty)
          _card(
            padding: const EdgeInsets.all(28),
            child: const Text(
              'No companies match your search.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _slate500),
            ),
          )
        else
          for (final c in visible) ...[_companyCard(c), const SizedBox(height: 12)],
      ],
    );
  }

  Widget _companyCard(Company c) {
    final (strip, bg, fg) = switch (c.type) {
      CompanyType.water => (const Color(0xFF38BDF8), const Color(0xFFE0F2FE), const Color(0xFF0369A1)),
      CompanyType.poultry => (const Color(0xFFFB923C), const Color(0xFFFFEDD5), _orange700),
      CompanyType.generic => (const Color(0xFFA78BFA), const Color(0xFFEDE9FE), const Color(0xFF6D28D9)),
      _ => (_slate300, _slate100, _slate700),
    };
    final icon = switch (c.type) {
      CompanyType.water => Icons.water_drop_outlined,
      CompanyType.poultry => Icons.flutter_dash,
      CompanyType.generic => Icons.shopping_bag_outlined,
      _ => Icons.apartment_outlined,
    };
    final opening = _openingId == c.farmId;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _slate200),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 4, color: strip),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
                      child: Icon(icon, size: 20, color: fg),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                          Text('Role: ${c.role ?? '—'}', style: const TextStyle(fontSize: 12, color: _slate500)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
                      child: Text(
                        c.type.wire,
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: fg),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: _slate900, minimumSize: const Size.fromHeight(40)),
                        onPressed: opening || _openingId != null ? null : () => _open(c),
                        child: Text(opening ? 'Opening…' : 'Open →'),
                      ),
                    ),
                    if (_isAdmin) ...[
                      const SizedBox(width: 6),
                      IconButton.outlined(
                        tooltip: 'Edit company',
                        onPressed: () => _edit(c),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                      ),
                      const SizedBox(width: 2),
                      IconButton.outlined(
                        tooltip: 'Delete company',
                        style: IconButton.styleFrom(
                          foregroundColor: _red600,
                          side: const BorderSide(color: Color(0xFFFECACA)),
                        ),
                        onPressed: () => _delete(c),
                        icon: const Icon(Icons.delete_outline, size: 18),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Create new company" / "Edit company — name" (type is fixed after creation).
/// Create pops the new name; edit pops true.
class _CompanyDialog extends StatefulWidget {
  const _CompanyDialog({required this.session, this.editing});
  final Session session;
  final Company? editing;
  @override
  State<_CompanyDialog> createState() => _CompanyDialogState();
}

class _CompanyDialogState extends State<_CompanyDialog> {
  String _typeId = 'water';
  late final _name = TextEditingController(text: widget.editing?.name ?? '');
  late final _email = TextEditingController(text: widget.editing?.email ?? '');
  late final _phone = TextEditingController(text: widget.editing?.phoneNumber ?? '');
  bool _saving = false;
  String? _createdFarmId;

  bool get _edit => widget.editing != null;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _toast(context, 'Company name is required', error: true);
      return;
    }
    setState(() => _saving = true);
    final client = widget.session.loginClient;
    final email = _email.text.trim().isEmpty ? null : _email.text.trim();
    final phone = _phone.text.trim().isEmpty ? null : _phone.text.trim();
    try {
      if (_edit) {
        await client.put(
          '/api/Companies/${Uri.encodeComponent(widget.editing!.farmId)}',
          body: {'Name': name, 'Email': email, 'PhoneNumber': phone},
        );
        if (mounted) Navigator.pop(context, true);
        return;
      }
      final type = businessTypes.firstWhere((t) => t.id == _typeId);
      final res = await client.post(
        '/api/Companies',
        body: {'Name': name, 'Type': type.companyType, 'Email': email, 'PhoneNumber': phone},
      );
      _createdFarmId = res is Map ? '${res['farmId'] ?? res['id'] ?? ''}' : '';
      if (email != null) {
        try {
          await widget.session.farmClient.post(
            '/api/Email/send-welcome',
            body: {'Email': email, 'CompanyName': name, 'CompanyType': type.companyType},
          );
        } catch (_) {}
      }
      if (mounted) Navigator.pop(context, '$name\n${_createdFarmId ?? ''}\n${type.companyType}\n${type.industryTemplate ?? ''}');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast(context, _edit ? 'Update failed' : 'Create failed', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = businessTypes.firstWhere((t) => t.id == _typeId);
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: FormDialogTitle(
          icon: _edit ? Icons.edit_outlined : Icons.apartment_outlined,
          color: FormColor.amber,
          text: _edit ? 'Edit company — ${widget.editing!.name}' : 'Create new company',
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_edit) ...[
                FilterLabel(
                  'Company type',
                  AppInput(controller: TextEditingController(text: widget.editing!.type.wire), enabled: false),
                ),
                const SizedBox(height: 4),
                const Text("Company type can't be changed after creation.", style: TextStyle(fontSize: 12, color: _slate400)),
              ] else ...[
                FilterLabel(
                  'Business type *',
                  AppSelect<String>(
                    value: _typeId,
                    items: [for (final t in businessTypes) AppSelectItem(value: t.id, label: t.label)],
                    onChanged: (v) => setState(() => _typeId = v ?? _typeId),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  type.industryTemplate != null
                      ? "We'll set up the right menus and starter categories for this, and you can change any of it later."
                      : type.description,
                  style: const TextStyle(fontSize: 12, color: _slate500),
                ),
              ],
              const SizedBox(height: 12),
              FilterLabel('Company name *', AppInput(controller: _name, hintText: 'e.g. Great Favour Water Co.')),
              const SizedBox(height: 12),
              FilterLabel('Contact email', AppInput(controller: _email, keyboardType: TextInputType.emailAddress)),
              const SizedBox(height: 12),
              FilterLabel('Phone', AppInput(controller: _phone, keyboardType: TextInputType.phone)),
            ],
          ),
        ),
        actions: [
          FormDialogFooter(
            onCancel: () => Navigator.pop(context),
            cancelDisabled: _saving,
            children: [
              FilledButton(
                style: formPrimary(FormColor.amber),
                onPressed: _saving ? null : _save,
                child: Text(_saving ? (_edit ? 'Saving…' : 'Creating…') : (_edit ? 'Save changes' : 'Create')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
