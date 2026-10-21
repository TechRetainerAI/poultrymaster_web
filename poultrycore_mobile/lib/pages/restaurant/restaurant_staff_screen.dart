// Restaurant → Menu & Setup → Staff, as `app/restaurant-staff/page.tsx`: the
// header with its count, the role cards (tap one to filter), Roles &
// Permissions (tap a role for its Permissions dialog), and Team Members with
// search, the role picker, the Employee badge (362), what each person owes on
// loans (326), and Edit / Make employee / Delete on every row.

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/reports/report_routes.dart' show openAppHref;
import '../poultry/sales/balances_widgets.dart' show LoadingLine;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/staff_employee_link.dart';
import 'restaurant_roles.dart';
import 'restaurant_staff_form_screen.dart';

/// Each role's tile and badge colours (RESTAURANT_ROLES `color`: bg-*-100 text-*-700).
const restaurantRoleColors = <String, (Color, Color)>{
  'Owner': (Color(0xFFF3E8FF), Color(0xFF7E22CE)),
  'Manager': (Color(0xFFDBEAFE), Color(0xFF1D4ED8)),
  'HeadChef': (Color(0xFFFEF3C7), Color(0xFFB45309)),
  'Chef': (Color(0xFFFFEDD5), Color(0xFFC2410C)),
  'Waiter': (Color(0xFFDCFCE7), Color(0xFF15803D)),
  'Cashier': (Color(0xFFD1FAE5), Color(0xFF047857)),
  'Host': (Color(0xFFFCE7F3), Color(0xFFBE185D)),
  'Bartender': (Color(0xFFE0E7FF), Color(0xFF4338CA)),
  'Driver': (Color(0xFFE0F2FE), Color(0xFF0369A1)),
  'Other': (Color(0xFFF3F4F6), Color(0xFF374151)),
};

(Color, Color) _colorsOf(String role) => restaurantRoleColors[role] ?? restaurantRoleColors['Other']!;

class RestaurantStaffScreen extends StatefulWidget {
  const RestaurantStaffScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<RestaurantStaffScreen> createState() => _RestaurantStaffScreenState();
}

class _RestaurantStaffScreenState extends State<RestaurantStaffScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _staff = [];
  // What each staff member still owes on loans and advances (326).
  Map<int, num> _owed = {};
  // Staff id -> the login it is linked to (362).
  Map<int, String> _links = {};
  String _search = '';
  String _role = 'all';

  ApiClient get _api => widget.session.farmClient;
  Map<String, dynamic> get _q => {'farmId': widget.company.farmId};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await _api.get('/api/Restaurant/staff', query: _q);
      _staff = [for (final s in (r is List ? r : const [])) if (s is Map) Map<String, dynamic>.from(s)];
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed to load', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
    // Loan balances are extra: if they cannot load, the staff list still works.
    try {
      final r = await _api.get('/api/Restaurant/staff-loans/staff-report', query: _q);
      _owed = {
        for (final x in (r is List ? r : const []))
          if (x is Map && tNum(x['outstanding']) > 0) tIntOrNull(x['restaurantStaffId']) ?? 0: tNum(x['outstanding']),
      };
    } catch (_) {
      _owed = {};
    }
    // The badges are a nicety: if the link API is down the page still works.
    try {
      _links = {for (final l in await getStaffUserLinks(widget.session, widget.company)) l.staffId: l.userId};
    } catch (_) {}
    if (mounted) setState(() {});
  }

  int _id(Map s) => tIntOrNull(s['restaurantStaffId']) ?? 0;

  Future<void> _openForm([Map<String, dynamic>? s]) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => RestaurantStaffFormScreen(session: widget.session, company: widget.company, existing: s),
    ));
    if (changed == true) _load();
  }

  Future<void> _makeEmployee(Map<String, dynamic> s) async {
    await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => makeEmployeeScreen(widget.session, widget.company, s, 'restaurantStaffId'),
    ));
    _load();
  }

  // The web deletes straight away, with no confirmation.
  Future<void> _remove(Map s) async {
    try {
      await _api.delete('/api/Restaurant/staff/${_id(s)}', query: _q);
      if (mounted) trackerToast(context, 'Staff removed');
      _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
  }

  List<Map<String, dynamic>> get _filtered => [
        for (final s in _staff)
          if ((_role == 'all' || tStr(s['role']) == _role) &&
              (_search.isEmpty || '${tStr(s['firstName'])} ${tStr(s['lastName'])}'.toLowerCase().contains(_search.toLowerCase())))
            s,
      ];

  int _count(String role) => _staff.where((s) => tStr(s['role']) == role).length;

  void _permissions(RestaurantRole r) {
    final n = _count(r.value);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Text(r.icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Expanded(child: Text('${r.label} — Permissions')),
        ]),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(r.description, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
              const SizedBox(height: 12),
              for (final p in restaurantPermissionAreas) ...[
                Builder(builder: (_) {
                  final has = r.permissions.contains(p);
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: has ? const Color(0xFFF0FDF4) : const Color(0xFFF9FAFB), borderRadius: BorderRadius.circular(8)),
                    child: Row(children: [
                      Expanded(child: Text(p, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF374151)))),
                      Icon(has ? Icons.check_circle_outline : Icons.cancel_outlined, size: 16, color: has ? const Color(0xFF16A34A) : const Color(0xFF9CA3AF)),
                      const SizedBox(width: 4),
                      Text(has ? 'Allowed' : 'No access',
                          style: TextStyle(fontSize: 12, fontWeight: has ? FontWeight.w500 : null, color: has ? const Color(0xFF16A34A) : const Color(0xFF9CA3AF))),
                    ]),
                  );
                }),
                const SizedBox(height: 8),
              ],
              const Divider(),
              Text.rich(TextSpan(children: [
                TextSpan(text: '$n', style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: ' team member${n != 1 ? 's' : ''} with this role'),
              ]), style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            ]),
          ),
        ),
        actions: [OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/restaurant-staff');
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Staff')),
      body: _loading
          ? const Padding(padding: EdgeInsets.all(20), child: LoadingLine('Loading…'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
                _header(),
                const SizedBox(height: 14),
                _roleCards(),
                _rolesCard(),
                const SizedBox(height: 14),
                _teamCard(),
              ]),
            ),
    );
  }

  Widget _iconTile(IconData icon, Color bg, Color fg, {double size = 40}) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: size / 2, color: fg),
      );

  Widget _header() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          _iconTile(Icons.manage_accounts_outlined, const Color(0xFFFFE4E6), restaurantRose),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Staff', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
              Text('${_staff.length} team members across ${{for (final s in _staff) tStr(s['role'])}.length} roles',
                  style: const TextStyle(fontSize: 13, color: TColors.slate500)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: restaurantRose, minimumSize: const Size.fromHeight(44)),
          onPressed: () => _openForm(),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Staff'),
        ),
      ]);

  // Only roles somebody holds; tapping one filters the list (tap again to clear).
  Widget _roleCards() {
    final held = [for (final r in restaurantRoles) if (_count(r.value) > 0) r];
    if (held.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.6,
        children: [
          for (final r in held)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _role = _role == r.value ? 'all' : r.value),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Text(r.icon, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${_count(r.value)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      Text(r.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                    ]),
                  ),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _cardHead(IconData icon, Color bg, Color fg, String title, String description) => Row(children: [
        _iconTile(icon, bg, fg, size: 36),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            Text(description, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
          ]),
        ),
      ]);

  Widget _smallBadge(String text, {Color bg = Colors.transparent, Color fg = TColors.slate600, Color? border}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(color: bg, border: Border.all(color: border ?? Colors.transparent), borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: fg)),
      );

  Widget _rolesCard() => TCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _cardHead(Icons.shield_outlined, const Color(0xFFF3E8FF), const Color(0xFF9333EA), 'Roles & Permissions',
              'Each role has predefined access to restaurant modules'),
          const SizedBox(height: 12),
          for (final r in restaurantRoles) ...[
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _permissions(r),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _role == r.value ? const Color(0x80FFF1F2) : null,
                  border: Border.all(color: _role == r.value ? const Color(0xFFFDA4AF) : TColors.slate200),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.icon, style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Flexible(child: Text(r.label, style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF111827)))),
                        const SizedBox(width: 6),
                        _smallBadge('${_count(r.value)}', bg: TColors.slate100),
                      ]),
                      const SizedBox(height: 2),
                      Text(r.description, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                      if (r.permissions.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(spacing: 4, runSpacing: 4, children: [
                          for (final p in r.permissions.take(3)) _smallBadge(p, border: TColors.slate200),
                          if (r.permissions.length > 3) _smallBadge('+${r.permissions.length - 3}', border: TColors.slate200),
                        ]),
                      ],
                    ]),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ]),
      );

  Widget _teamCard() {
    final rows = _filtered;
    return TCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _cardHead(Icons.groups_outlined, const Color(0xFFDCFCE7), const Color(0xFF16A34A), 'Team Members',
            '${rows.length} staff ${_role != 'all' ? '($_role)' : ''}'),
        const SizedBox(height: 12),
        AppInput(hintText: 'Search staff...', prefixIcon: const Icon(Icons.search, size: 18), onChanged: (v) => setState(() => _search = v)),
        const SizedBox(height: 8),
        AppSelect<String>(
          value: _role,
          items: [
            const AppSelectItem(value: 'all', label: 'All Roles'),
            for (final r in restaurantRoles) AppSelectItem(value: r.value, label: '${r.icon} ${r.label}'),
          ],
          onChanged: (v) => setState(() => _role = v ?? 'all'),
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
            decoration: BoxDecoration(border: Border.all(color: TColors.slate200, width: 2), borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              const Icon(Icons.groups_outlined, size: 48, color: Color(0xFFD1D5DB)),
              const SizedBox(height: 12),
              Text(_search.isNotEmpty || _role != 'all' ? 'No staff match' : 'No staff members yet',
                  style: const TextStyle(fontWeight: FontWeight.w500, color: Color(0xFF111827))),
              const SizedBox(height: 4),
              const Text('Add your team members and assign their roles',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: TColors.slate500)),
              if (_search.isEmpty && _role == 'all') ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: restaurantRose),
                  onPressed: () => _openForm(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add First Member'),
                ),
              ],
            ]),
          )
        else
          for (final s in rows) ...[_row(s), const SizedBox(height: 8)],
      ]),
    );
  }

  Widget _row(Map<String, dynamic> s) {
    final role = tStr(s['role']);
    final cfg = restaurantRoles.where((r) => r.value == role).firstOrNull;
    final (bg, fg) = _colorsOf(cfg == null ? 'Other' : role);
    final id = _id(s);
    final basePay = tNum(s['basePay']);
    final email = tStr(s['email']);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
            child: Text(cfg?.icon ?? '👤', style: const TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('${tStr(s['firstName'])} ${tStr(s['lastName'])}', style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                _smallBadge(cfg?.label ?? role, bg: bg, fg: fg),
                if (s['isActive'] == false) _smallBadge('Inactive', bg: TColors.slate100),
                if (_links.containsKey(id)) employeeBadge(),
              ]),
              const SizedBox(height: 4),
              Wrap(spacing: 12, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.phone_outlined, size: 12, color: TColors.slate500),
                  const SizedBox(width: 4),
                  Text(tStr(s['phone']), style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                ]),
                if (email.isNotEmpty)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.mail_outline, size: 12, color: TColors.slate500),
                    const SizedBox(width: 4),
                    Text(email, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                  ]),
                if (basePay > 0)
                  Text('${basePay.toStringAsFixed(0)}/${tStr(s['salaryType'])}', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                if (_owed.containsKey(id))
                  InkWell(
                    onTap: () => openAppHref(context, widget.session, widget.company, '/restaurant-staff-loans?staffId=$id',
                        label: 'Employee Loans & Advances'),
                    child: Text('owes ${_owed[id]!.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFFDC2626))),
                  ),
              ]),
            ]),
          ),
        ]),
        // Always shown: the web's hover-only row buttons are visible on touch.
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _openForm(s)),
          if (!_links.containsKey(id))
            IconButton(tooltip: 'Make employee (give a login)', icon: const Icon(Icons.key_outlined, size: 18), onPressed: () => _makeEmployee(s)),
          IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444)), onPressed: () => _remove(s)),
        ]),
      ]),
    );
  }
}
