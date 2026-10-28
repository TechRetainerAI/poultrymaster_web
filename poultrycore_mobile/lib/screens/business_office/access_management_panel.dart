import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/ui/form_dialog.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../pages/poultry/trackers/tracker_widgets.dart' show FilterLabel;
import '../../pages/shared/reason_select.dart';
import '../../state/session.dart';

/// Business Office → Administration → Access (`components/business-office/iam-panel.tsx`
/// with `iam/roles-view.tsx`, `matrix-view.tsx`, `people-view.tsx`,
/// `security-view.tsx`), on the Farm API `/api/Iam/*` endpoints that
/// `lib/api/iam.ts` calls.
///
/// The Business Office has no active company, so the scope picker says which
/// company is meant; null is "All companies".
class AccessManagementPanel extends StatefulWidget {
  const AccessManagementPanel({super.key, required this.session});
  final Session session;
  @override
  State<AccessManagementPanel> createState() => _AccessManagementPanelState();
}

const _slate50 = Color(0xFFF8FAFC);
const _slate100 = Color(0xFFF1F5F9);
const _slate200 = Color(0xFFE2E8F0);
const _slate300 = Color(0xFFCBD5E1);
const _slate400 = Color(0xFF94A3B8);
const _slate500 = Color(0xFF64748B);
const _slate600 = Color(0xFF475569);
const _slate700 = Color(0xFF334155);
const _slate800 = Color(0xFF1E293B);
const _slate900 = Color(0xFF0F172A);
const _indigo50 = Color(0xFFEEF2FF);
const _indigo100 = Color(0xFFE0E7FF);
const _indigo300 = Color(0xFFA5B4FC);
const _indigo600 = Color(0xFF4F46E5);
const _indigo700 = Color(0xFF4338CA);
const _amber50 = Color(0xFFFFFBEB);
const _amber100 = Color(0xFFFEF3C7);
const _amber200 = Color(0xFFFDE68A);
const _amber400 = Color(0xFFFBBF24);
const _amber500 = Color(0xFFF59E0B);
const _amber600 = Color(0xFFD97706);
const _amber700 = Color(0xFFB45309);
const _amber800 = Color(0xFF92400E);
const _amber900 = Color(0xFF78350F);
const _sky50 = Color(0xFFF0F9FF);
const _sky200 = Color(0xFFBAE6FD);
const _sky900 = Color(0xFF0C4A6E);
const _red50 = Color(0xFFFEF2F2);
const _red100 = Color(0xFFFEE2E2);
const _red200 = Color(0xFFFECACA);
const _red600 = Color(0xFFDC2626);
const _red700 = Color(0xFFB91C1C);
const _emerald50 = Color(0xFFECFDF5);
const _emerald100 = Color(0xFFD1FAE5);
const _emerald200 = Color(0xFFA7F3D0);
const _emerald600 = Color(0xFF059669);
const _emerald700 = Color(0xFF047857);

// ---------------------------------------------------------------- shared.ts

/// Matrix columns, least to most destructive.
const _actions = ['view', 'create', 'edit', 'delete', 'approve', 'export'];
const _actionLabel = {
  'view': 'View', 'create': 'Create', 'edit': 'Edit', 'delete': 'Delete', 'approve': 'Approve', 'export': 'Export',
};
const _moduleLabel = {'poultry': 'Poultry', 'water': 'Water', 'generic': 'Company', 'office': 'Business Office'};
String _moduleForCompanyType(String? type) =>
    const {'Poultry': 'poultry', 'Water': 'water', 'Generic': 'generic'}[type ?? ''] ?? 'poultry';

String _actionText(Object? a) => _actionLabel['$a'] ?? '$a';

/// A picked date → the end of that day, as the ISO instant the API stores.
String? _dateToIso(DateTime? d) =>
    d == null ? null : DateTime(d.year, d.month, d.day, 23, 59, 59).toUtc().toIso8601String();

String _formatDate(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}');
  return d == null ? '' : AppDateField.format(d.toLocal());
}

String _formatDateTime(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}')?.toLocal();
  if (d == null) return '';
  return '${AppDateField.format(d)}, ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

typedef _Row = Map<String, dynamic>;

List<_Row> _rows(Object? v) => [for (final r in (v is List ? v : const [])) if (r is Map) Map<String, dynamic>.from(r)];

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

String _s(Object? v) => v == null ? '' : '$v';

String _personName(Map e) {
  final n = [e['firstName'], e['lastName']].where((x) => _s(x).isNotEmpty).join(' ');
  if (n.isNotEmpty) return n;
  final u = _s(e['userName']);
  if (u.isNotEmpty) return u;
  final m = _s(e['email']);
  return m.isNotEmpty ? m : 'Unnamed';
}

/// One matrix row: a resource, and the catalog entry for each action it has.
class _MatrixRow {
  _MatrixRow(this.group, this.resource, this.label, this.description);
  final String group, resource, label, description;
  final Map<String, _Row> actions = {};
}

/// `buildMatrix`: the catalog for one module folded into group → resource →
/// actions. A missing action means "does not apply", not "not granted".
List<(String, List<_MatrixRow>)> _buildMatrix(List<_Row> catalog, String module) {
  final byResource = <String, _MatrixRow>{};
  for (final p in catalog) {
    if (p['module'] != module) continue;
    final r = byResource.putIfAbsent(_s(p['resource']),
        () => _MatrixRow(_s(p['permissionGroup']), _s(p['resource']), _s(p['resourceLabel']), _s(p['description'])));
    r.actions[_s(p['action'])] = p;
  }
  final groups = <String, List<_MatrixRow>>{};
  for (final r in byResource.values) {
    groups.putIfAbsent(r.group, () => []).add(r);
  }
  return [for (final e in groups.entries) (e.key, e.value)];
}

// ---------------------------------------------------------------- api

/// `getJson`: a read that degrades to null rather than throwing.
Future<Object?> _read(ApiClient c, String path, [Map<String, dynamic>? query]) async {
  try {
    return await c.get(path, query: query);
  } catch (_) {
    return null;
  }
}

/// `mutate`: null on success, otherwise the server's sentence for the admin.
Future<({String? error, Object? body})> _write(Future<dynamic> Function() run) async {
  try {
    return (error: null, body: await run());
  } on ApiException catch (e) {
    final msg = e.message.trim().isNotEmpty
        ? e.message
        : e.statusCode == 403
            ? 'You do not have permission to change access settings.'
            : 'Request failed (${e.statusCode}).';
    return (error: msg, body: null);
  } catch (e) {
    return (error: 'Network error.', body: null);
  }
}

void _toast(BuildContext context, String title, {String? description, bool error = false}) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: error ? _red700 : null,
      content: Text(description == null || description.isEmpty ? title : '$title. $description'),
    ));

Widget _card({required Widget child, EdgeInsets padding = const EdgeInsets.all(16), Color? border, Color? color}) => Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        border: Border.all(color: border ?? _slate200),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: child,
    );

Widget _loadingRow([String text = 'Loading…']) => Padding(
      padding: const EdgeInsets.all(28),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 10),
        Text(text, style: const TextStyle(color: _slate500)),
      ]),
    );

Widget _banner(Color bg, Color border, Color fg, Widget child) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(10)),
      child: DefaultTextStyle.merge(style: TextStyle(fontSize: 13, color: fg, height: 1.35), child: child),
    );

Widget _pill(String text, {Color bg = _slate100, Color fg = _slate700, Color? border}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: border == null ? null : Border.all(color: border),
      ),
      child: Text(text, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: fg)),
    );

Widget _emptyState(IconData icon, String title, String body, {Color iconColor = _slate300}) => _card(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      child: Column(children: [
        Icon(icon, size: 40, color: iconColor),
        const SizedBox(height: 10),
        Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, color: _slate700)),
        const SizedBox(height: 4),
        Text(body, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: _slate500)),
      ]),
    );

ButtonStyle _outline({Color fg = _slate700, Color border = _slate200}) => OutlinedButton.styleFrom(
      backgroundColor: Colors.white,
      foregroundColor: fg,
      side: BorderSide(color: border),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      minimumSize: const Size(0, 36),
      visualDensity: VisualDensity.compact,
    );

Widget _spinner([Color color = Colors.white]) =>
    SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: color));

/// A segmented tab strip that wraps on a phone, as the web's TabsList does.
Widget _tabStrip(List<(String, IconData, String, Widget?)> tabs, String current, ValueChanged<String> onTap) => Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: _slate100, borderRadius: BorderRadius.circular(12)),
      child: Wrap(spacing: 4, runSpacing: 4, children: [
        for (final (key, icon, label, badge) in tabs)
          Material(
            color: current == key ? Colors.white : Colors.transparent,
            elevation: current == key ? 1 : 0,
            borderRadius: BorderRadius.circular(9),
            child: InkWell(
              borderRadius: BorderRadius.circular(9),
              onTap: () => onTap(key),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 16, color: current == key ? _slate900 : _slate500),
                  const SizedBox(width: 6),
                  Text(label,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: current == key ? _slate900 : _slate500)),
                  if (badge != null) ...[const SizedBox(width: 6), badge],
                ]),
              ),
            ),
          ),
      ]),
    );

// ---------------------------------------------------------------- shell

class _AccessManagementPanelState extends State<AccessManagementPanel> {
  String? _scope; // farmId, or null for All companies
  bool _loading = true, _permsLoaded = false;
  List<_Row>? _catalog;
  List<_Row> _roles = [], _employees = [];
  bool _rolesUnavailable = false;
  int? _selectedRoleId;
  String _module = 'poultry';
  String _tab = 'roles';
  Set<String> _granted = {};

  Session get _s => widget.session;
  ApiClient get _api => _s.farmClient;
  List<Company> get _companies => _s.myCompanies;
  Company? get _scopeCompany => _companies.where((c) => c.farmId == _scope).firstOrNull;
  String? get _scopeType => _scopeCompany?.type.wire;

  bool _can(String key) => _granted.contains(key);

  @override
  void initState() {
    super.initState();
    _loadPermissions();
    _load();
  }

  /// `usePermissions().can("office.access.*")` with no company open: while the
  /// API does not enforce IAM an admin holds every key; otherwise only grants count.
  Future<void> _loadPermissions() async {
    const keys = ['office.access.view', 'office.access.create', 'office.access.edit', 'office.access.delete'];
    final status = await _read(_api, '/api/Iam/status');
    final eff = await _read(_api, '/api/Iam/effective-permissions');
    final enforced = status is Map && status['enforced'] == true;
    final isAdmin = _companies.any((c) => c.isAdmin);
    Set<String> held;
    if (!enforced && isAdmin) {
      held = keys.toSet();
    } else {
      final grants = eff is Map ? eff['grants'] : null;
      held = {
        for (final k in keys)
          if (grants is List && grants.any((g) => g is Map && g['permissionKey'] == k)) k,
      };
    }
    if (mounted) {
      setState(() {
        _granted = held;
        _permsLoaded = true;
      });
    }
  }

  Map<String, dynamic>? get _scopeQuery => _scope == null ? null : {'farmId': _scope};

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      _read(_api, '/api/Iam/catalog'),
      _read(_api, '/api/Iam/roles', _scopeQuery),
      _read(_s.loginClient, '/api/Admin/organization/employees'),
    ]);
    if (!mounted) return;
    final cat = results[0];
    final rs = results[1];
    final emp = results[2];
    setState(() {
      _catalog = cat is List ? _rows(cat) : null;
      _roles = _rows(rs);
      _rolesUnavailable = rs is! List;
      _employees = _rows(emp is Map ? emp['data'] : emp);
      if (_roles.isNotEmpty) _selectedRoleId ??= _int(_roles.first['roleId']);
      _loading = false;
    });
  }

  /// Reload roles after a create/edit/delete, without re-fetching the catalog.
  Future<void> _reloadRoles() async {
    final rs = await _read(_api, '/api/Iam/roles', _scopeQuery);
    if (!mounted) return;
    setState(() {
      _roles = _rows(rs);
      _rolesUnavailable = rs is! List;
    });
  }

  void _setScope(String? v) {
    setState(() {
      _scope = v;
      // Picking a company moves the matrix to that company's module.
      if (_scopeType != null) _module = _moduleForCompanyType(_scopeType);
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_permsLoaded && !_can('office.access.view')) {
      return _emptyState(Icons.gpp_maybe_outlined, 'You do not have access to this section',
          'Managing roles and permissions requires the Access Management permission.');
    }
    if (_loading) return _loadingRow('Loading access data…');
    if (_catalog == null) {
      return _emptyState(
        Icons.gpp_maybe_outlined,
        'Access management is not set up on this database yet',
        'Apply 199_IamFoundation.sql, 200_IamPhase1Reads.sql and 201_IamPhase2Writes.sql, then restart the API.',
        iconColor: _amber400,
      );
    }
    final canCreate = _can('office.access.create'), canEdit = _can('office.access.edit'), canDelete = _can('office.access.delete');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Roles, what each one can do, and who holds them.', style: TextStyle(fontSize: 14, color: _slate600)),
      const SizedBox(height: 12),
      // The scope picker: the Business Office has no active company, so this
      // is where you say which one you mean.
      Row(children: [
        const Icon(Icons.apartment_outlined, size: 18, color: _slate400),
        const SizedBox(width: 8),
        Expanded(
          child: AppSelect<String>(
            value: _scope ?? '__all__',
            items: [
              const AppSelectItem(value: '__all__', label: 'All companies'),
              for (final c in _companies) AppSelectItem(value: c.farmId, label: c.name),
            ],
            onChanged: (v) => _setScope(v == null || v == '__all__' ? null : v),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      if (_rolesUnavailable) ...[
        _banner(
            _amber50,
            _amber200,
            _amber900,
            const Text('Roles could not be loaded. If the database has 199_IamFoundation.sql but not '
                '200_IamPhase1Reads.sql, nobody holds the Access Management permission yet — apply it and restart the API.')),
        const SizedBox(height: 12),
      ],
      _banner(
        _sky50,
        _sky200,
        _sky900,
        const Text.rich(TextSpan(children: [
          TextSpan(text: 'Roles set here '),
          TextSpan(text: 'add', style: TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: ' to what someone can already do — they cannot take access away. Existing staff permissions under '),
          TextSpan(text: 'Employees & Users', style: TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: ' still apply, and the API does not enforce these roles yet, so treat this as how access '),
          TextSpan(text: 'should', style: TextStyle(fontStyle: FontStyle.italic)),
          TextSpan(text: ' look rather than a lock.'),
        ])),
      ),
      const SizedBox(height: 14),
      _tabStrip([
        ('roles', Icons.key_outlined, 'Roles', null),
        ('matrix', Icons.check, 'Permission Matrix', null),
        ('people', Icons.group_outlined, 'People', null),
        ('security', Icons.verified_user_outlined, 'Security', null),
      ], _tab, (k) => setState(() => _tab = k)),
      const SizedBox(height: 14),
      switch (_tab) {
        'matrix' => _MatrixView(
            key: ValueKey('matrix-$_scope'),
            api: _api,
            catalog: _catalog!,
            roles: _roles,
            selectedRoleId: _selectedRoleId,
            onSelectRole: (id) => setState(() => _selectedRoleId = id),
            module: _module,
            onModuleChange: (m) => setState(() => _module = m),
            farmId: _scope,
            canEdit: canEdit,
            onChanged: _reloadRoles,
          ),
        'people' => _PeopleView(
            key: ValueKey('people-$_scope'),
            api: _api,
            catalog: _catalog!,
            roles: _roles,
            employees: _employees,
            companies: _companies,
            farmId: _scope,
            farmName: _scopeCompany?.name,
            companyType: _scopeType,
            canEdit: canEdit,
          ),
        'security' => _SecurityView(key: ValueKey('security-$_scope'), api: _api, farmId: _scope, canEdit: canEdit),
        _ => _RolesView(
            api: _api,
            roles: _roles,
            selectedRoleId: _selectedRoleId,
            onSelect: (id) => setState(() => _selectedRoleId = id),
            farmId: _scope,
            canCreate: canCreate,
            canEdit: canEdit,
            canDelete: canDelete,
            onChanged: _reloadRoles,
          ),
      },
    ]);
  }

}


// ---------------------------------------------------------------- roles

const _companyTypeOptions = [
  ('any', 'Any company type'),
  ('Poultry', 'Poultry only'),
  ('Water', 'Water only'),
  ('Generic', 'Company only'),
];

class _RolesView extends StatelessWidget {
  const _RolesView({
    required this.api,
    required this.roles,
    required this.selectedRoleId,
    required this.onSelect,
    required this.farmId,
    required this.canCreate,
    required this.canEdit,
    required this.canDelete,
    required this.onChanged,
  });
  final ApiClient api;
  final List<_Row> roles;
  final int? selectedRoleId;
  final ValueChanged<int> onSelect;
  final String? farmId;
  final bool canCreate, canEdit, canDelete;
  final Future<void> Function() onChanged;

  Future<void> _openEditor(BuildContext context, {_Row? edit, _Row? duplicate}) async {
    final roleId = await showDialog<int>(
      context: context,
      builder: (_) => _RoleDialog(api: api, farmId: farmId, edit: edit, duplicate: duplicate),
    );
    if (roleId == null) return;
    await onChanged();
    if (roleId > 0) onSelect(roleId);
  }

  Future<void> _delete(BuildContext context, _Row r) async {
    final name = _s(r['name']);
    var deleting = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const FormDialogTitle(icon: Icons.delete_outline, color: FormColor.red, text: 'Delete role'),
          content: SizedBox(
            width: 420,
            child: Text(
              'Delete $name? This cannot be undone. If anyone still holds the role, remove it from them first — '
              'the delete will be refused until then.',
              style: const TextStyle(fontSize: 14, color: _slate600),
            ),
          ),
          actions: [
            FormDialogFooter(onCancel: () => Navigator.pop(ctx), cancelDisabled: deleting, children: [
              FilledButton(
                style: formPrimary(FormColor.red),
                onPressed: deleting
                    ? null
                    : () async {
                        setLocal(() => deleting = true);
                        final res = await _write(() => api.delete('/api/Iam/roles/${r['roleId']}',
                            query: farmId == null ? null : {'farmId': farmId}));
                        if (!ctx.mounted) return;
                        if (res.error != null) {
                          // The server refuses while anyone holds the role and says
                          // how many — that sentence is the useful part.
                          setLocal(() => deleting = false);
                          _toast(ctx, 'Could not delete role', description: res.error, error: true);
                          return;
                        }
                        Navigator.pop(ctx, true);
                      },
                child: Text(deleting ? 'Deleting…' : 'Delete'),
              ),
            ]),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    _toast(context, 'Role deleted', description: name);
    await onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: _slate900, minimumSize: const Size.fromHeight(46)),
        onPressed: canCreate ? () => _openEditor(context) : null,
        icon: const Icon(Icons.add, size: 18),
        label: const Text('New role'),
      ),
      const SizedBox(height: 12),
      for (final r in roles) ...[_roleCard(context, r), const SizedBox(height: 10)],
    ]);
  }

  Widget _roleCard(BuildContext context, _Row r) {
    final id = _int(r['roleId']);
    final selected = selectedRoleId == id;
    final isSystem = r['isSystem'] == true, isSuper = r['isSuperuser'] == true;
    final count = _int(r['permissionCount']);
    final type = _s(r['companyType']);
    final desc = _s(r['description']);
    return Material(
      color: selected ? _indigo50 : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => onSelect(id),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: selected ? _indigo300 : _slate200, width: selected ? 1.5 : 1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              if (isSuper) ...[const Icon(Icons.workspace_premium, size: 18, color: _amber500), const SizedBox(width: 6)],
              Expanded(
                child: Text(_s(r['name']),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _slate900)),
              ),
              const SizedBox(width: 8),
              isSystem ? _pill('Built-in') : _pill('Custom', bg: _indigo100, fg: _indigo700),
            ]),
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(desc, style: const TextStyle(fontSize: 12.5, color: _slate500)),
            ],
            const SizedBox(height: 8),
            Wrap(spacing: 12, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(isSuper ? 'Every permission' : '$count permissions', style: const TextStyle(fontSize: 12.5, color: _slate600)),
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.group_outlined, size: 14, color: _slate500),
                const SizedBox(width: 3),
                Text('${_int(r['assignedUserCount'])}', style: const TextStyle(fontSize: 12.5, color: _slate500)),
              ]),
              if (type.isNotEmpty) _pill('$type only', bg: Colors.white, border: _slate200),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              OutlinedButton.icon(
                style: _outline(),
                onPressed: canCreate ? () => _openEditor(context, duplicate: r) : null,
                icon: const Icon(Icons.copy, size: 15),
                label: const Text('Duplicate'),
              ),
              if (!isSystem) ...[
                const SizedBox(width: 6),
                IconButton.outlined(
                  tooltip: 'Rename role',
                  style: IconButton.styleFrom(backgroundColor: Colors.white, side: const BorderSide(color: _slate200)),
                  onPressed: canEdit ? () => _openEditor(context, edit: r) : null,
                  icon: const Icon(Icons.edit_outlined, size: 17),
                ),
                const SizedBox(width: 2),
                IconButton.outlined(
                  tooltip: 'Delete role',
                  style: IconButton.styleFrom(
                      backgroundColor: Colors.white, foregroundColor: _red600, side: const BorderSide(color: _red200)),
                  onPressed: canDelete ? () => _delete(context, r) : null,
                  icon: const Icon(Icons.delete_outline, size: 17),
                ),
              ],
            ]),
          ]),
        ),
      ),
    );
  }
}

/// New / Rename / Duplicate role. Pops the saved role id (0 when the server
/// returned none), or null when closed.
class _RoleDialog extends StatefulWidget {
  const _RoleDialog({required this.api, required this.farmId, this.edit, this.duplicate});
  final ApiClient api;
  final String? farmId;
  final _Row? edit, duplicate;
  @override
  State<_RoleDialog> createState() => _RoleDialogState();
}

class _RoleDialogState extends State<_RoleDialog> {
  late final _Row? _from = widget.edit ?? widget.duplicate;
  late final _name = TextEditingController(
      text: widget.duplicate != null ? '${_s(widget.duplicate!['name'])} (copy)' : _s(widget.edit?['name']));
  late final _desc = TextEditingController(text: _s(_from?['description']));
  late String _type = _s(_from?['companyType']).isEmpty ? 'any' : _s(_from?['companyType']);
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _toast(context, 'Name required', description: 'Give the role a name.', error: true);
      return;
    }
    setState(() => _saving = true);
    final res = await _write(() => widget.api.post('/api/Iam/roles',
        query: widget.farmId == null ? null : {'farmId': widget.farmId},
        body: {
          'roleId': widget.edit == null ? null : _int(widget.edit!['roleId']),
          'name': name,
          'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
          'companyType': _type == 'any' ? null : _type,
          'copyFromRoleId': widget.duplicate == null ? null : _int(widget.duplicate!['roleId']),
        }));
    if (!mounted) return;
    if (res.error != null) {
      setState(() => _saving = false);
      _toast(context, 'Could not save role', description: res.error, error: true);
      return;
    }
    _toast(context, widget.edit != null ? 'Role updated' : 'Role created',
        description: widget.duplicate != null ? 'Permissions were copied from the original.' : name);
    final body = res.body;
    Navigator.pop(context, body is Map ? _int(body['roleId']) : 0);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.edit != null ? 'Rename role' : widget.duplicate != null ? 'Duplicate role' : 'New role';
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: FormDialogTitle(
            icon: widget.duplicate != null ? Icons.copy : Icons.key_outlined, color: FormColor.purple, text: title),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FilterLabel('Name', AppInput(controller: _name, hintText: 'e.g. Feed Store Manager')),
            const SizedBox(height: 12),
            FilterLabel('Description', AppTextarea(controller: _desc, hintText: 'What this role is for.')),
            const SizedBox(height: 12),
            FilterLabel(
              'Offer this role for',
              AppSelect<String>(
                value: _type,
                items: [for (final (v, l) in _companyTypeOptions) AppSelectItem(value: v, label: l)],
                onChanged: (v) => setState(() => _type = v ?? 'any'),
              ),
            ),
            const SizedBox(height: 4),
            const Text('Restricting the type keeps the role out of pickers where it makes no sense.',
                style: TextStyle(fontSize: 12, color: _slate500)),
            if (widget.duplicate != null) ...[
              const SizedBox(height: 10),
              const Text(
                  'Permissions will be copied from the original. You can change them in the Permission Matrix afterwards.',
                  style: TextStyle(fontSize: 12, color: _slate500)),
            ],
          ]),
        ),
        actions: [
          FormDialogFooter(onCancel: () => Navigator.pop(context), cancelDisabled: _saving, children: [
            FilledButton(
              style: formPrimary(FormColor.purple),
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ]),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- matrix

class _MatrixView extends StatefulWidget {
  const _MatrixView({
    super.key,
    required this.api,
    required this.catalog,
    required this.roles,
    required this.selectedRoleId,
    required this.onSelectRole,
    required this.module,
    required this.onModuleChange,
    required this.farmId,
    required this.canEdit,
    required this.onChanged,
  });
  final ApiClient api;
  final List<_Row> catalog, roles;
  final int? selectedRoleId;
  final ValueChanged<int> onSelectRole;
  final String module;
  final ValueChanged<String> onModuleChange;
  final String? farmId;
  final bool canEdit;
  final Future<void> Function() onChanged;
  @override
  State<_MatrixView> createState() => _MatrixViewState();
}

class _MatrixViewState extends State<_MatrixView> {
  Set<String> _saved = {}, _draft = {};
  bool _loading = false, _saving = false;

  _Row? get _role => widget.roles.where((r) => _int(r['roleId']) == widget.selectedRoleId).firstOrNull;

  /// A superuser role holds everything by definition, so nothing to edit.
  bool get _editable => widget.canEdit && _role != null && _role!['isSystem'] != true && _role!['isSuperuser'] != true;

  bool get _dirty => _draft.length != _saved.length || _draft.any((k) => !_saved.contains(k));

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_MatrixView old) {
    super.didUpdateWidget(old);
    if (old.selectedRoleId != widget.selectedRoleId || old.farmId != widget.farmId) _load();
  }

  Future<void> _load() async {
    final id = widget.selectedRoleId;
    if (id == null) {
      setState(() => _saved = _draft = {});
      return;
    }
    setState(() => _loading = true);
    final keys = await _read(widget.api, '/api/Iam/roles/$id/permissions', widget.farmId == null ? null : {'farmId': widget.farmId});
    if (!mounted || id != widget.selectedRoleId) return;
    final set = {for (final k in (keys is List ? keys : const [])) '$k'};
    setState(() {
      _saved = set;
      _draft = {...set};
      _loading = false;
    });
  }

  void _setMany(Iterable<String> keys, bool on) => setState(() {
        _draft = {..._draft};
        for (final k in keys) {
          on ? _draft.add(k) : _draft.remove(k);
        }
      });

  Future<void> _save() async {
    final id = widget.selectedRoleId;
    if (id == null) return;
    setState(() => _saving = true);
    // The draft holds every module's keys, not just the one on screen.
    final res = await _write(() => widget.api.put('/api/Iam/roles/$id/permissions',
        query: widget.farmId == null ? null : {'farmId': widget.farmId}, body: {'permissionKeys': _draft.toList()}));
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.error != null) {
      _toast(context, 'Could not save permissions', description: res.error, error: true);
      return;
    }
    setState(() => _saved = {..._draft});
    _toast(context, 'Permissions saved', description: _s(_role?['name']));
    await widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final matrix = _buildMatrix(widget.catalog, widget.module);
    final role = _role;
    List<String> columnKeys(String a) => [
          for (final (_, rows) in matrix)
            for (final r in rows)
              if (r.actions[a] != null) _s(r.actions[a]!['permissionKey']),
        ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSelect<int>(
        value: widget.selectedRoleId,
        hintText: 'Choose a role',
        items: [for (final r in widget.roles) AppSelectItem(value: _int(r['roleId']), label: _s(r['name']))],
        onChanged: (v) {
          if (v != null) widget.onSelectRole(v);
        },
      ),
      const SizedBox(height: 10),
      AppSelect<String>(
        value: widget.module,
        items: [for (final e in _moduleLabel.entries) AppSelectItem(value: e.key, label: e.value)],
        onChanged: (v) {
          if (v != null) widget.onModuleChange(v);
        },
      ),
      if (role?['isSuperuser'] == true) ...[
        const SizedBox(height: 10),
        _banner(_amber50, _amber200, _amber700,
            const Text('Superuser — holds everything, including permissions added in future', style: TextStyle(fontSize: 12.5))),
      ] else if (role?['isSystem'] == true) ...[
        const SizedBox(height: 10),
        _banner(
          _slate100,
          _slate200,
          _slate600,
          const Row(children: [
            Icon(Icons.lock_outline, size: 14, color: _slate600),
            SizedBox(width: 6),
            Expanded(child: Text('Built-in role — duplicate it to make an editable copy', style: TextStyle(fontSize: 12.5))),
          ]),
        ),
      ],
      if (_dirty && _editable) ...[
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              style: _outline(),
              onPressed: _saving ? null : () => setState(() => _draft = {..._saved}),
              icon: const Icon(Icons.restart_alt, size: 16),
              label: const Text('Reset'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _slate900, minimumSize: const Size(0, 36)),
              onPressed: _saving ? null : _save,
              icon: _saving ? _spinner() : const Icon(Icons.save_outlined, size: 16),
              label: Text(_saving ? 'Saving…' : 'Save changes'),
            ),
          ),
        ]),
      ],
      const SizedBox(height: 12),
      if (_loading)
        _card(child: _loadingRow())
      else ...[
        // The column headers' select-all, as one row of chips on a phone.
        if (_editable)
          _card(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('GRANT ON EVERYTHING VISIBLE',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .5, color: _slate500)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final a in _actions)
                  if (columnKeys(a).isNotEmpty)
                    () {
                      final keys = columnKeys(a);
                      final all = keys.every(_draft.contains);
                      return FilterChip(
                        label: Text(_actionLabel[a]!),
                        selected: all,
                        showCheckmark: true,
                        selectedColor: _indigo100,
                        onSelected: (on) => _setMany(keys, on),
                      );
                    }(),
              ]),
            ]),
          ),
        if (_editable) const SizedBox(height: 10),
        for (final (group, rows) in matrix) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
            child: Text(group.toUpperCase(),
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: .5, color: _slate500)),
          ),
          _card(
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (final (i, row) in rows.indexed) ...[
                if (i > 0) const Divider(height: 1, color: _slate100),
                _matrixRow(row),
              ],
            ]),
          ),
          const SizedBox(height: 8),
        ],
      ],
      const SizedBox(height: 4),
      Text(
        'Amber marks a destructive or sensitive permission — deleting, approving, or seeing cost figures. '
        '· means the action does not apply to that resource.'
        '${_editable ? ' The row checkbox and the chips above apply to everything currently visible in this module.' : ''}',
        style: const TextStyle(fontSize: 12, color: _slate400),
      ),
    ]);
  }

  Widget _matrixRow(_MatrixRow row) {
    final rowKeys = [for (final p in row.actions.values) _s(p['permissionKey'])];
    final allRow = rowKeys.every(_draft.contains);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_editable) ...[
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: allRow,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                onChanged: (c) => _setMany(rowKeys, c == true),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(row.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _slate900)),
              if (row.description.isNotEmpty) Text(row.description, style: const TextStyle(fontSize: 12, color: _slate500)),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [for (final a in _actions) _cell(row, a)]),
      ]),
    );
  }

  /// One action: a toggle when editable, a tick or a dash when not, and "·"
  /// where the action does not apply to this resource.
  Widget _cell(_MatrixRow row, String a) {
    final perm = row.actions[a];
    final label = _actionLabel[a]!;
    if (perm == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(color: _slate50, borderRadius: BorderRadius.circular(8)),
        child: Text('$label ·', style: const TextStyle(fontSize: 12, color: _slate300)),
      );
    }
    final key = _s(perm['permissionKey']);
    final on = _draft.contains(key);
    final danger = perm['isDangerous'] == true;
    final onColor = danger ? _amber600 : _emerald600;
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: on ? (danger ? _amber100 : _emerald100) : Colors.white,
        border: Border.all(color: on ? onColor : _slate200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(on ? Icons.check : (_editable ? Icons.check_box_outline_blank : Icons.remove),
            size: 14, color: on ? onColor : _slate300),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: on ? _slate800 : _slate500)),
      ]),
    );
    if (!_editable) return Semantics(label: '${row.label}: $label', child: child);
    return Semantics(
      label: '${row.label}: $label',
      child: InkWell(key: ValueKey('iam-$key'), borderRadius: BorderRadius.circular(8), onTap: () => _setMany([key], !on), child: child),
    );
  }
}

// ---------------------------------------------------------------- people

class _PeopleView extends StatefulWidget {
  const _PeopleView({
    super.key,
    required this.api,
    required this.catalog,
    required this.roles,
    required this.employees,
    required this.companies,
    required this.farmId,
    required this.farmName,
    required this.companyType,
    required this.canEdit,
  });
  final ApiClient api;
  final List<_Row> catalog, roles, employees;
  final List<Company> companies;
  final String? farmId, farmName, companyType;
  final bool canEdit;
  @override
  State<_PeopleView> createState() => _PeopleViewState();
}

class _PeopleViewState extends State<_PeopleView> {
  String _query = '';
  String? _selectedId;
  List<_Row> _userRoles = [], _overrides = [], _grants = [], _sessions = [];
  bool _loading = false, _busy = false;

  Map<String, dynamic>? get _farmQuery => widget.farmId == null ? null : {'farmId': widget.farmId};
  _Row? get _selected => widget.employees.where((e) => _s(e['id']) == _selectedId).firstOrNull;

  Future<void> _load() async {
    final id = _selectedId;
    if (id == null) return;
    setState(() => _loading = true);
    final q = {'userId': id, 'farmId': widget.farmId};
    final r = await Future.wait([
      _read(widget.api, '/api/Iam/user-roles', q),
      _read(widget.api, '/api/Iam/overrides', q),
      _read(widget.api, '/api/Iam/effective-permissions', q),
      _read(widget.api, '/api/Iam/sessions', {'userId': id}),
    ]);
    if (!mounted || id != _selectedId) return;
    setState(() {
      _userRoles = _rows(r[0]);
      _overrides = _rows(r[1]);
      _grants = _rows(r[2] is Map ? (r[2] as Map)['grants'] : null);
      _sessions = _rows(r[3]);
      _loading = false;
    });
  }

  Future<void> _run(Future<dynamic> Function() call, String failTitle, String okTitle, {String? okDescription}) async {
    setState(() => _busy = true);
    final res = await _write(call);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.error != null) {
      _toast(context, failTitle, description: res.error, error: true);
      return;
    }
    _toast(context, okTitle, description: okDescription);
    await _load();
  }

  Future<void> _assign() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _AssignDialog(
        api: widget.api,
        userId: _selectedId!,
        // A Water-only role has no business in a Poultry company.
        roles: [
          for (final r in widget.roles)
            if (_s(r['companyType']).isEmpty || widget.companyType == null || r['companyType'] == widget.companyType) r,
        ],
        companies: widget.companies,
        initialScope: widget.farmId,
      ),
    );
    if (ok == true && mounted) await _load();
  }

  Future<void> _addOverride() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _OverrideDialog(api: widget.api, userId: _selectedId!, farmId: widget.farmId, catalog: widget.catalog),
    );
    if (ok == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.employees
        : [
            for (final e in widget.employees)
              if ([e['firstName'], e['lastName'], e['email'], e['userName']].any((v) => _s(v).toLowerCase().contains(q))) e,
          ];
    final selected = _selected;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSearchField(hintText: 'Search people…', onChanged: (v) => setState(() => _query = v)),
      const SizedBox(height: 10),
      _card(
        padding: EdgeInsets.zero,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 300),
          child: filtered.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No people found.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: _slate500)),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, color: _slate100),
                  itemBuilder: (_, i) {
                    final e = filtered[i];
                    final id = _s(e['id']);
                    final on = id == _selectedId;
                    final sub = _s(e['email']).isNotEmpty ? _s(e['email']) : _s(e['userName']);
                    return Material(
                      color: on ? _indigo50 : Colors.white,
                      child: InkWell(
                        onTap: () {
                          setState(() => _selectedId = id);
                          _load();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                          child: Row(children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: on ? _indigo100 : _slate100,
                              child: Text(_personName(e).characters.first.toUpperCase(),
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: on ? _indigo600 : _slate600)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(_personName(e),
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _slate900)),
                                if (sub.isNotEmpty)
                                  Text(sub, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: _slate500)),
                              ]),
                            ),
                            if (on) const Icon(Icons.chevron_right, size: 18, color: _indigo600),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
      const SizedBox(height: 14),
      if (selected == null)
        _emptyState(
          Icons.group_outlined,
          'Choose someone to see and change what they can do',
          widget.farmName != null
              ? 'Access is shown for ${widget.farmName}.'
              : 'Showing access that applies across every company. Pick a company above to see access granted only there.',
        )
      else if (_loading)
        _loadingRow()
      else
        ..._details(selected),
    ]);
  }

  /// The title with its button on the right, or underneath when both do not fit.
  Widget _sectionHead(String title, Widget? action) => Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 6,
        children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _slate900)),
          ?action,
        ],
      );

  Widget _removeButton(String tooltip, VoidCallback onTap) => IconButton(
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        color: _slate400,
        onPressed: widget.canEdit && !_busy ? onTap : null,
        icon: const Icon(Icons.close, size: 18),
      );

  List<Widget> _details(_Row selected) {
    final farmQ = _farmQuery;
    // Effective permissions folded into module → group, each carrying its source.
    final meta = {for (final p in widget.catalog) _s(p['permissionKey']): p};
    final byModule = <String, Map<String, List<(String, String, String, String)>>>{};
    for (final g in _grants) {
      final p = meta[_s(g['permissionKey'])];
      if (p == null) continue;
      byModule
          .putIfAbsent(_s(p['module']), () => {})
          .putIfAbsent(_s(p['permissionGroup']), () => [])
          .add((_s(g['permissionKey']), _s(p['resourceLabel']), _s(p['action']), _s(g['source'])));
    }
    return [
      _card(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_personName(selected), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _slate900)),
          Text(_s(selected['email']).isNotEmpty ? _s(selected['email']) : _s(selected['userName']),
              style: const TextStyle(fontSize: 12.5, color: _slate500)),
        ]),
      ),
      const SizedBox(height: 12),
      // ---- Roles
      _card(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _sectionHead(
            widget.farmName != null ? 'Roles in ${widget.farmName}' : 'Roles across all companies',
            OutlinedButton.icon(
              style: _outline(),
              onPressed: widget.canEdit && !_busy ? _assign : null,
              icon: const Icon(Icons.add, size: 15),
              label: const Text('Assign role'),
            ),
          ),
          const SizedBox(height: 10),
          if (_userRoles.isEmpty)
            const Text('No roles assigned. They currently work from the staff permissions set under Employees & Users.',
                style: TextStyle(fontSize: 13, color: _slate500))
          else
            for (final r in _userRoles)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.only(left: 12),
                decoration: BoxDecoration(border: Border.all(color: _slate200), borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  if (r['isSuperuser'] == true) ...[
                    const Icon(Icons.workspace_premium, size: 15, color: _amber500),
                    const SizedBox(width: 5),
                  ],
                  Expanded(
                    child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text(_s(r['name']), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: _slate800)),
                      if (r['isOrgWide'] == true) _pill('All companies', bg: Colors.white, border: _slate200),
                      if (_s(r['expiresAt']).isNotEmpty) _pill('Until ${_formatDate(r['expiresAt'])}'),
                    ]),
                  ),
                  _removeButton(
                    'Remove ${_s(r['name'])}',
                    () => _run(() => widget.api.delete('/api/Iam/assignments/${r['id']}', query: farmQ), 'Could not remove role',
                        'Role removed',
                        okDescription: _s(r['name'])),
                  ),
                ]),
              ),
        ]),
      ),
      const SizedBox(height: 12),
      // ---- Overrides
      _card(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _sectionHead(
            'Exceptions',
            OutlinedButton.icon(
              style: _outline(),
              onPressed: widget.canEdit && !_busy ? _addOverride : null,
              icon: const Icon(Icons.add, size: 15),
              label: const Text('Add exception'),
            ),
          ),
          const SizedBox(height: 10),
          if (_overrides.isEmpty)
            const Text('No exceptions. Everything this person can do comes from their roles.',
                style: TextStyle(fontSize: 13, color: _slate500))
          else
            for (final o in _overrides) _overrideRow(o, farmQ),
        ]),
      ),
      const SizedBox(height: 12),
      // ---- Sessions
      _card(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _sectionHead(
            'Signed in on',
            _sessions.isEmpty
                ? null
                : OutlinedButton.icon(
                    style: _outline(fg: _red600, border: _red200),
                    onPressed: widget.canEdit && !_busy
                        ? () => _run(
                            () => widget.api.post('/api/Iam/sessions/revoke-all', query: farmQ, body: {'userId': _selectedId}),
                            'Could not sign them out',
                            'Signed out everywhere',
                            okDescription: 'Their existing sign-ins have been ended.')
                        : null,
                    icon: const Icon(Icons.logout, size: 15),
                    label: const Text('Sign out everywhere'),
                  ),
          ),
          const SizedBox(height: 10),
          if (_sessions.isEmpty)
            const Text('No sign-ins recorded. Sessions start being tracked once the API has been updated.',
                style: TextStyle(fontSize: 13, color: _slate500))
          else
            for (final s in _sessions)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.only(left: 12),
                decoration: BoxDecoration(border: Border.all(color: _slate200), borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  const Icon(Icons.computer_outlined, size: 17, color: _slate400),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_s(s['device']).isNotEmpty ? _s(s['device']) : 'Unknown device',
                          overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, color: _slate800)),
                      Text(
                          '${_s(s['ipAddress']).isNotEmpty ? _s(s['ipAddress']) : 'unknown address'} · last seen ${_formatDateTime(s['lastSeenAt'])}',
                          style: const TextStyle(fontSize: 12, color: _slate500)),
                    ]),
                  ),
                  _removeButton(
                    'End this session',
                    () => _run(
                        () => widget.api.delete('/api/Iam/sessions/${Uri.encodeComponent(_s(s['sessionId']))}', query: farmQ),
                        'Could not end session',
                        'Session ended',
                        okDescription: _s(s['device'])),
                  ),
                ]),
              ),
          const SizedBox(height: 6),
          const Text(
              'Signing someone out everywhere also stops tokens they already hold — once the API has permission enforcement switched on.',
              style: TextStyle(fontSize: 12, color: _slate400)),
        ]),
      ),
      const SizedBox(height: 12),
      // ---- Effective
      if (byModule.isEmpty)
        _card(
          padding: const EdgeInsets.all(24),
          child: const Text('No IAM permissions in this company yet.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: _slate500)),
        )
      else
        for (final m in byModule.entries) ...[
          _card(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(_moduleLabel[m.key] ?? m.key,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: _slate900)),
              for (final g in m.value.entries) ...[
                const SizedBox(height: 10),
                Text(g.key.toUpperCase(),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .5, color: _slate500)),
                const SizedBox(height: 5),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final (key, label, action, source) in g.value)
                    Tooltip(
                      message: '$key — from $source',
                      triggerMode: TooltipTriggerMode.tap,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: _slate100, borderRadius: BorderRadius.circular(6)),
                        child: Text('$label: ${_actionText(action)}', style: const TextStyle(fontSize: 11.5, color: _slate700)),
                      ),
                    ),
                ]),
              ],
            ]),
          ),
          const SizedBox(height: 10),
        ],
      const Text('Tap a permission to see its key and which role granted it.', style: TextStyle(fontSize: 12, color: _slate400)),
    ];
  }

  Widget _overrideRow(_Row o, Map<String, dynamic>? farmQ) {
    final expired = o['hasExpired'] == true, deny = o['effect'] == 'Deny';
    final (bg, border) = expired ? (_slate50, _slate200) : deny ? (_red50, _red200) : (_emerald50, _emerald200);
    return Opacity(
      opacity: expired ? .7 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(12, 10, 0, 10),
        decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(10)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(deny ? Icons.remove_moderator_outlined : Icons.verified_user_outlined,
              size: 17, color: deny ? _red600 : _emerald600),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${deny ? 'Deny' : 'Allow'} · ${_s(o['resourceLabel'])}: ${_actionText(o['action'])}',
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: _slate800)),
              if (_s(o['reason']).isNotEmpty) Text(_s(o['reason']), style: const TextStyle(fontSize: 12, color: _slate600)),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (o['isOrgWide'] == true) _pill('All companies', bg: Colors.white, border: _slate200),
                if (_s(o['expiresAt']).isNotEmpty) _pill('${expired ? 'Expired' : 'Until'} ${_formatDate(o['expiresAt'])}'),
                if (expired)
                  const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.warning_amber_rounded, size: 13, color: _amber700),
                    SizedBox(width: 3),
                    Text('No longer in effect', style: TextStyle(fontSize: 11, color: _amber700)),
                  ]),
              ]),
            ]),
          ),
          _removeButton(
            'Remove exception',
            () => _run(() => widget.api.delete('/api/Iam/overrides/${o['id']}', query: farmQ), 'Could not remove override',
                'Override removed'),
          ),
        ]),
      ),
    );
  }
}

/// "Assign a role". Pops true once assigned.
class _AssignDialog extends StatefulWidget {
  const _AssignDialog({
    required this.api,
    required this.userId,
    required this.roles,
    required this.companies,
    required this.initialScope,
  });
  final ApiClient api;
  final String userId;
  final List<_Row> roles;
  final List<Company> companies;
  final String? initialScope;
  @override
  State<_AssignDialog> createState() => _AssignDialogState();
}

class _AssignDialogState extends State<_AssignDialog> {
  int? _roleId;
  // Seeded from the company being viewed, but chosen independently.
  late String _scope = widget.initialScope ?? '__all__';
  DateTime? _expires;
  bool _busy = false;

  Future<void> _assign() async {
    if (_roleId == null) {
      _toast(context, 'Choose a role', error: true);
      return;
    }
    setState(() => _busy = true);
    final res = await _write(() => widget.api.post('/api/Iam/assignments', body: {
          'userId': widget.userId,
          'roleId': _roleId,
          // A null farmId is what the resolver treats as "every company".
          'farmId': _scope == '__all__' ? null : _scope,
          'expiresAt': _dateToIso(_expires),
        }));
    if (!mounted) return;
    if (res.error != null) {
      setState(() => _busy = false);
      _toast(context, 'Could not assign role', description: res.error, error: true);
      return;
    }
    _toast(context, 'Role assigned');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: AlertDialog(
          scrollable: true,
          title: const FormDialogTitle(icon: Icons.key_outlined, color: FormColor.purple, text: 'Assign a role'),
          content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              FilterLabel(
                'Role',
                AppSelect<int>(
                  value: _roleId,
                  hintText: 'Choose a role',
                  items: [for (final r in widget.roles) AppSelectItem(value: _int(r['roleId']), label: _s(r['name']))],
                  onChanged: (v) => setState(() => _roleId = v),
                ),
              ),
              const SizedBox(height: 12),
              FilterLabel(
                'Applies to',
                AppSelect<String>(
                  value: _scope,
                  items: [
                    const AppSelectItem(value: '__all__', label: 'Every company in the organization'),
                    for (final c in widget.companies) AppSelectItem(value: c.farmId, label: '${c.name} only'),
                  ],
                  onChanged: (v) => setState(() => _scope = v ?? '__all__'),
                ),
              ),
              if (widget.companies.isEmpty) ...[
                const SizedBox(height: 4),
                const Text('No companies found, so only an organization-wide assignment is possible.',
                    style: TextStyle(fontSize: 12, color: _amber700)),
              ],
              const SizedBox(height: 12),
              FilterLabel('Expires (optional)', AppDateField(value: _expires, onChanged: (d) => setState(() => _expires = d))),
              const SizedBox(height: 4),
              const Text('Use this for cover — the role stops applying on its own, with nobody having to remember.',
                  style: TextStyle(fontSize: 12, color: _slate500)),
            ]),
          ),
          actions: [
            FormDialogFooter(onCancel: () => Navigator.pop(context), cancelDisabled: _busy, children: [
              FilledButton(
                style: formPrimary(FormColor.purple),
                onPressed: _busy ? null : _assign,
                child: Text(_busy ? 'Assigning…' : 'Assign'),
              ),
            ]),
          ],
        ),
      );
}

/// "Add an exception". Pops true once saved.
class _OverrideDialog extends StatefulWidget {
  const _OverrideDialog({required this.api, required this.userId, required this.farmId, required this.catalog});
  final ApiClient api;
  final String userId;
  final String? farmId;
  final List<_Row> catalog;
  @override
  State<_OverrideDialog> createState() => _OverrideDialogState();
}

class _OverrideDialogState extends State<_OverrideDialog> {
  String _search = '', _key = '', _effect = 'Allow', _reason = '';
  DateTime? _expires;
  bool _busy = false;

  Future<void> _save() async {
    if (_key.isEmpty) {
      _toast(context, 'Choose a permission', error: true);
      return;
    }
    if (_reason.trim().isEmpty) {
      _toast(context, 'Reason required', description: 'Say why this exception exists.', error: true);
      return;
    }
    setState(() => _busy = true);
    final res = await _write(() => widget.api.post('/api/Iam/overrides', body: {
          'userId': widget.userId,
          'farmId': widget.farmId,
          'permissionKey': _key,
          'effect': _effect,
          'reason': _reason.trim(),
          'expiresAt': _dateToIso(_expires),
        }));
    if (!mounted) return;
    if (res.error != null) {
      setState(() => _busy = false);
      _toast(context, 'Could not save override', description: res.error, error: true);
      return;
    }
    _toast(context, 'Override saved');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.trim().toLowerCase();
    final options = (q.isEmpty
            ? widget.catalog
            : [
                for (final p in widget.catalog)
                  if (_s(p['permissionKey']).toLowerCase().contains(q) || _s(p['resourceLabel']).toLowerCase().contains(q)) p,
              ])
        .take(60)
        .toList();
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        scrollable: true,
        title: const FormDialogTitle(icon: Icons.tune, color: FormColor.purple, text: 'Add an exception'),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FilterLabel('Permission', AppSearchField(hintText: 'Search permissions…', onChanged: (v) => setState(() => _search = v))),
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(border: Border.all(color: _slate200), borderRadius: BorderRadius.circular(10)),
              clipBehavior: Clip.antiAlias,
              child: options.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No matching permissions.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: _slate500)),
                    )
                  : SingleChildScrollView(
                      child: Column(children: [
                        for (final (i, p) in options.indexed) ...[
                          if (i > 0) const Divider(height: 1, color: _slate100),
                          Material(
                            color: _key == _s(p['permissionKey']) ? _indigo50 : Colors.white,
                            child: InkWell(
                              onTap: () => setState(() => _key = _s(p['permissionKey'])),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                child: Row(children: [
                                  Expanded(
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text('${_s(p['resourceLabel'])}: ${_actionText(p['action'])}',
                                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: _slate800)),
                                      Text('${_moduleLabel[p['module']] ?? _s(p['module'])} · ${_s(p['permissionKey'])}',
                                          style: const TextStyle(fontSize: 11, color: _slate500)),
                                    ]),
                                  ),
                                  if (_key == _s(p['permissionKey'])) const Icon(Icons.check, size: 16, color: _indigo600),
                                ]),
                              ),
                            ),
                          ),
                        ],
                      ]),
                    ),
            ),
            const SizedBox(height: 12),
            FilterLabel(
              'Effect',
              AppSelect<String>(
                value: _effect,
                items: const [
                  AppSelectItem(value: 'Allow', label: 'Allow — grant this on top of their roles'),
                  AppSelectItem(value: 'Deny', label: 'Deny — take this away'),
                ],
                onChanged: (v) => setState(() => _effect = v ?? 'Allow'),
              ),
            ),
            if (_effect == 'Deny') ...[
              const SizedBox(height: 4),
              const Text(
                  'While access management is still additive, a Deny only removes what IAM granted — it cannot take away '
                  'a permission the older staff settings already allow.',
                  style: TextStyle(fontSize: 12, color: _amber700)),
            ],
            const SizedBox(height: 12),
            FilterLabel(
                'Reason', ReasonSelect(options: permissionOverrideReasons, value: _reason, onChanged: (v) => setState(() => _reason = v))),
            const SizedBox(height: 4),
            const Text('Required. Whoever reviews access next needs to tell a deliberate exception from an accident.',
                style: TextStyle(fontSize: 12, color: _slate500)),
            const SizedBox(height: 12),
            FilterLabel('Expires (optional)', AppDateField(value: _expires, onChanged: (d) => setState(() => _expires = d))),
          ]),
        ),
        actions: [
          FormDialogFooter(onCancel: () => Navigator.pop(context), cancelDisabled: _busy, children: [
            FilledButton(
              style: formPrimary(FormColor.purple),
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Saving…' : 'Save exception'),
            ),
          ]),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- security

const _auditWindows = [('30', 'Last 30 days'), ('90', 'Last 90 days'), ('365', 'Last year')];

class _SecurityView extends StatefulWidget {
  const _SecurityView({super.key, required this.api, required this.farmId, required this.canEdit});
  final ApiClient api;
  final String? farmId;
  final bool canEdit;
  @override
  State<_SecurityView> createState() => _SecurityViewState();
}

class _SecurityViewState extends State<_SecurityView> {
  _Row? _policy, _draft;
  List<_Row> _review = [], _audit = [];
  String? _reviewBusy;
  String _auditDays = '90', _tab = 'review';
  bool _loading = true, _savingPolicy = false;
  final _numbers = <String, TextEditingController>{};

  Map<String, dynamic>? get _farmQuery => widget.farmId == null ? null : {'farmId': widget.farmId};

  @override
  void initState() {
    super.initState();
    _load();
    _loadAudit();
  }

  @override
  void dispose() {
    for (final c in _numbers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final r = await Future.wait([_read(widget.api, '/api/Iam/policy', _farmQuery), _read(widget.api, '/api/Iam/access-review', _farmQuery)]);
    if (!mounted) return;
    setState(() {
      _policy = r[0] is Map ? Map<String, dynamic>.from(r[0] as Map) : null;
      _resetDraft();
      _review = _rows(r[1]);
      _loading = false;
    });
  }

  Future<void> _loadAudit() async {
    final a = await _read(widget.api, '/api/Iam/access-audit', {'days': _auditDays});
    if (mounted) setState(() => _audit = _rows(a));
  }

  void _resetDraft() {
    _draft = _policy == null ? null : {..._policy!};
    for (final e in _numbers.entries) {
      e.value.text = _s(_draft?[e.key]);
    }
  }

  bool get _policyDirty =>
      _policy != null && _draft != null && _policy!.keys.any((k) => '${_policy![k]}' != '${_draft![k]}');

  Future<void> _savePolicy() async {
    setState(() => _savingPolicy = true);
    final res = await _write(() => widget.api.put('/api/Iam/policy', query: _farmQuery, body: _draft));
    if (!mounted) return;
    setState(() => _savingPolicy = false);
    if (res.error != null) {
      _toast(context, 'Could not save policy', description: res.error, error: true);
      return;
    }
    setState(() => _policy = {..._draft!});
    _toast(context, 'Security policy saved');
  }

  Future<void> _doReview(_Row row, String decision) async {
    final id = _s(row['userId']);
    setState(() => _reviewBusy = id);
    final res = await _write(
        () => widget.api.post('/api/Iam/access-review', query: _farmQuery, body: {'userId': id, 'decision': decision}));
    if (!mounted) return;
    if (res.error != null) {
      setState(() => _reviewBusy = null);
      _toast(context, 'Could not record review', description: res.error, error: true);
      return;
    }
    _toast(context, decision == 'Confirmed' ? 'Access confirmed' : 'Flagged for follow-up', description: _personName(row));
    final r = await _read(widget.api, '/api/Iam/access-review', _farmQuery);
    if (mounted) {
      setState(() {
        _review = _rows(r);
        _reviewBusy = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return _loadingRow();
    final attention = _review.where((r) => r['isDormant'] == true || r['reviewIsStale'] == true).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _tabStrip([
        (
          'review',
          Icons.assignment_turned_in_outlined,
          'Access Review',
          attention > 0 ? _pill('$attention', bg: _amber100, fg: _amber800) : null,
        ),
        ('policy', Icons.verified_user_outlined, 'Policy', null),
        ('history', Icons.history, 'Change History', null),
      ], _tab, (k) => setState(() => _tab = k)),
      const SizedBox(height: 14),
      ...switch (_tab) {
        'policy' => _policyTab(),
        'history' => _historyTab(),
        _ => _reviewTab(),
      },
    ]);
  }

  List<Widget> _reviewTab() => [
        Text(
          'Confirm that everyone here still needs the access they have. A confirmation goes stale after '
          '${_policy?['accessReviewDays'] ?? 180} days, and someone who has not signed in for '
          '${_policy?['dormantAfterDays'] ?? 90} days is flagged as dormant.',
          style: const TextStyle(fontSize: 13.5, color: _slate600),
        ),
        const SizedBox(height: 12),
        if (_review.isEmpty)
          _card(
            padding: const EdgeInsets.all(24),
            child: const Text('Nobody to review.', textAlign: TextAlign.center, style: TextStyle(color: _slate500)),
          )
        else
          for (final r in _review) ...[_reviewCard(r), const SizedBox(height: 10)],
      ];

  Widget _reviewCard(_Row r) {
    final roles = _int(r['roleCount']), overrides = _int(r['overrideCount']);
    final dormant = r['isDormant'] == true, stale = r['reviewIsStale'] == true, flagged = r['lastDecision'] == 'Flagged';
    final busy = _reviewBusy == _s(r['userId']);
    Widget cell(String label, Widget value) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label.toUpperCase(),
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: .4, color: _slate400)),
            const SizedBox(height: 2),
            value,
          ]),
        );
    Widget flag(IconData icon, String text, Color color) => Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 3),
            Flexible(child: Text(text, style: TextStyle(fontSize: 12, color: color))),
          ]),
        );
    const never = Text('Never', style: TextStyle(fontSize: 12.5, color: _slate400));
    return _card(
      padding: const EdgeInsets.all(14),
      color: dormant || stale ? const Color(0x66FFFBEB) : null,
      border: dormant || stale ? _amber200 : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(_personName(r), style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: _slate900)),
        Text(_s(r['email']).isNotEmpty ? _s(r['email']) : _s(r['userName']), style: const TextStyle(fontSize: 12, color: _slate500)),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: '$roles role${roles == 1 ? '' : 's'}'),
            if (overrides > 0) TextSpan(text: ' · $overrides exception${overrides == 1 ? '' : 's'}'),
            if (roles == 0 && overrides == 0) const TextSpan(text: ' — none', style: TextStyle(color: _slate400)),
          ]),
          style: const TextStyle(fontSize: 12.5, color: _slate600),
        ),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          cell(
            'Last seen',
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _s(r['lastSeenAt']).isNotEmpty ? Text(_formatDate(r['lastSeenAt']), style: const TextStyle(fontSize: 12.5)) : never,
              if (dormant) flag(Icons.schedule, 'Dormant', _amber700),
            ]),
          ),
          cell(
            'Last reviewed',
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _s(r['lastReviewedAt']).isNotEmpty ? Text(_formatDate(r['lastReviewedAt']), style: const TextStyle(fontSize: 12.5)) : never,
              if (flagged) flag(Icons.flag_outlined, 'Flagged', _red700),
              if (stale && !flagged) flag(Icons.warning_amber_rounded, 'Needs review', _amber700),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              style: _outline(),
              onPressed: !widget.canEdit || busy ? null : () => _doReview(r, 'Confirmed'),
              icon: busy ? _spinner(_slate500) : const Icon(Icons.check, size: 15),
              label: const Text('Still needed'),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            style: _outline(fg: _amber700, border: _amber200),
            onPressed: !widget.canEdit || busy ? null : () => _doReview(r, 'Flagged'),
            icon: const Icon(Icons.flag_outlined, size: 15),
            label: const Text('Flag'),
          ),
        ]),
      ]),
    );
  }

  TextEditingController _num(String key) =>
      _numbers.putIfAbsent(key, () => TextEditingController(text: _s(_draft?[key])));

  Widget _numberField(String key, String label, {String? help}) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FilterLabel(
          label,
          AppNumberInput(
            controller: _num(key),
            onChanged: (v) => setState(() => _draft![key] = int.tryParse(v) ?? 0),
          ),
        ),
        if (help != null) ...[const SizedBox(height: 3), Text(help, style: const TextStyle(fontSize: 12, color: _slate500))],
      ]);

  Widget _switch(String key, String label, {String? description}) => AppSwitchRow(
        label: label,
        description: description,
        value: _draft![key] == true,
        onChanged: (v) => setState(() => _draft![key] = v),
      );

  List<Widget> _policyTab() => [
        _banner(
            _sky50,
            _sky200,
            _sky900,
            const Text('These rules are recorded here, but passwords are checked when someone registers or changes their '
                'password — which happens in the sign-in service. Until that is wired up, treat the password settings as '
                'the policy you intend rather than one already being applied.')),
        const SizedBox(height: 12),
        if (_draft == null)
          _card(
            padding: const EdgeInsets.all(24),
            child: const Text('Security policy is unavailable. Apply 203_IamPhase4Governance.sql.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: _slate500)),
          )
        else ...[
          _card(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Passwords', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _slate900)),
              const SizedBox(height: 12),
              FormPair(_numberField('passwordMinLength', 'Minimum length'),
                  _numberField('passwordExpiryDays', 'Expires after (days)', help: '0 means never.')),
              const SizedBox(height: 10),
              _switch('passwordRequireUpper', 'Require a capital letter'),
              _switch('passwordRequireDigit', 'Require a number'),
              _switch('passwordRequireSymbol', 'Require a symbol'),
            ]),
          ),
          const SizedBox(height: 12),
          _card(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Sessions and review', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _slate900)),
              const SizedBox(height: 12),
              _numberField('sessionIdleMinutes', 'Sign out after inactivity (minutes)', help: '0 means no idle timeout.'),
              const SizedBox(height: 12),
              _numberField('sessionMaxHours', 'Maximum session length (hours)', help: '0 means no cap.'),
              const SizedBox(height: 12),
              _numberField('dormantAfterDays', 'Treat as dormant after (days)'),
              const SizedBox(height: 12),
              _numberField('accessReviewDays', 'Access review stays fresh for (days)'),
              const SizedBox(height: 10),
              _switch('requireMfaForAdmins', 'Require two-factor sign-in for admins',
                  description: 'Recorded as intent; two-factor is not built yet.'),
            ]),
          ),
          if (_policyDirty) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  style: _outline(),
                  onPressed: _savingPolicy ? null : () => setState(_resetDraft),
                  child: const Text('Reset'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: _slate900, minimumSize: const Size(0, 40)),
                  onPressed: !widget.canEdit || _savingPolicy ? null : _savePolicy,
                  icon: _savingPolicy ? _spinner() : const Icon(Icons.save_outlined, size: 16),
                  label: Text(_savingPolicy ? 'Saving…' : 'Save policy'),
                ),
              ),
            ]),
          ],
        ],
      ];

  List<Widget> _historyTab() => [
        const Text('Every change to who can do what, recorded by the database itself.',
            style: TextStyle(fontSize: 13.5, color: _slate600)),
        const SizedBox(height: 10),
        AppSelect<String>(
          value: _auditDays,
          items: [for (final (v, l) in _auditWindows) AppSelectItem(value: v, label: l)],
          onChanged: (v) {
            setState(() => _auditDays = v ?? '90');
            _loadAudit();
          },
        ),
        const SizedBox(height: 12),
        if (_audit.isEmpty)
          _card(
            padding: const EdgeInsets.all(24),
            child: const Text('No access changes recorded in this period.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: _slate500)),
          )
        else
          _card(
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (final (i, a) in _audit.indexed) ...[
                if (i > 0) const Divider(height: 1, color: _slate100),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    switch (_s(a['operation'])) {
                      'Delete' => _pill('Delete', bg: _red100, fg: _red700),
                      'Insert' => _pill('Insert', bg: _emerald100, fg: _emerald700),
                      final op => _pill(op),
                    },
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_s(a['detail']), style: const TextStyle(fontSize: 13.5, color: _slate800)),
                        const SizedBox(height: 2),
                        Text(_auditByline(a), style: const TextStyle(fontSize: 12, color: _slate500)),
                      ]),
                    ),
                  ]),
                ),
              ],
            ]),
          ),
      ];

  static String _auditByline(_Row a) {
    final subject = _s(a['subjectName']).trim().isNotEmpty
        ? _s(a['subjectName']).trim()
        : _s(a['subjectId']).isNotEmpty
            ? _s(a['subjectId'])
            : 'unknown';
    final actor = _s(a['actorName']).trim().isNotEmpty ? _s(a['actorName']).trim() : _s(a['actorId']);
    return [subject, if (actor.isNotEmpty) 'by $actor', _formatDateTime(a['occurredAt'])].join(' · ');
  }
}
