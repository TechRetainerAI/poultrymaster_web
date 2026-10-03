import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api/api_client.dart';
import '../../design/tokens.dart';
import '../../design/ui/buttons.dart';
import '../../design/ui/form_section.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../lookup_loader.dart';
import '../web_page_screen.dart';

/// Setup → Company → Companies ("My companies"), as `app/companies/page.tsx`.
/// Shared by every company type: the owner's companies with the active one
/// called out, Switch, and "New company".
class CompaniesScreen extends StatefulWidget {
  const CompaniesScreen({super.key, required this.session, required this.company});
  final Session session;

  /// The company the app is in now — the "Active" one.
  final Company company;

  @override
  State<CompaniesScreen> createState() => _CompaniesScreenState();
}

/// One business on offer (lib/companies/business-types.ts). Several map to
/// the same company type and differ only by the Generic template.
class BusinessType {
  const BusinessType(this.id, this.label, this.description, this.companyType, [this.industryTemplate]);
  final String id;
  final String label;
  final String description;
  final String companyType;

  /// Set only for Generic-based types, which go through the setup wizard.
  final String? industryTemplate;
}

const businessTypes = [
  BusinessType('water', 'Water production', 'Sachet or bottled water — production, distribution, drivers', 'Water'),
  BusinessType('poultry', 'Poultry farm', 'Flocks, houses, egg production, feed', 'Poultry'),
  BusinessType('hotel', 'Hotel', 'Rooms, bookings, front desk', 'Hotel'),
  BusinessType('restaurant', 'Restaurant', 'POS, menu, kitchen, delivery', 'Restaurant'),
  BusinessType('saas', 'SaaS / software company', 'Customers on recurring plans', 'Generic', 'SaaS'),
  BusinessType('gym', 'Gym / fitness centre', 'Members on monthly or annual memberships', 'Generic', 'Gym'),
  BusinessType('school', 'School', 'Students, termly fees, fee notes', 'Generic', 'School'),
  BusinessType('cleaning', 'Cleaning service', 'Clients on service contracts', 'Generic', 'CleaningService'),
  BusinessType('security', 'Security service', 'Clients on service contracts', 'Generic', 'SecurityService'),
  BusinessType('agency', 'Agency', 'Clients on monthly retainers', 'Generic', 'Agency'),
  BusinessType('retainer', 'Retainer business', 'Any business billing a fixed amount each period', 'Generic', 'RetainerBusiness'),
  BusinessType('membership', 'Membership organisation', 'Members paying dues', 'Generic', 'MembershipBusiness'),
  BusinessType('retail', 'Shop / retail', 'Stock, counter sales, suppliers', 'Generic', 'Retail'),
  BusinessType('other', 'Other small business', 'Salon, pharmacy, workshop — sales, expenses and cash', 'Generic', 'Other'),
];

/// CompanyIcon: the same mark and colour wherever a company is named.
Widget companyIcon(String type) {
  final (icon, color) = switch (type) {
    'Water' => (Icons.water_drop_outlined, const Color(0xFF0EA5E9)), // sky-500
    'Poultry' => (Icons.flutter_dash, const Color(0xFFF97316)), // orange-500
    'Restaurant' => (Icons.restaurant, const Color(0xFFE11D48)), // rose-600
    'Hotel' => (Icons.business_outlined, const Color(0xFFA855F7)), // purple-500
    _ => (Icons.business_outlined, const Color(0xFFF97316)),
  };
  return Icon(icon, size: 20, color: color);
}

class _CompaniesScreenState extends State<CompaniesScreen> {
  List<Map<String, dynamic>>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await widget.session.loginClient.get('/api/Companies/mine');
      if (!mounted) return;
      setState(() {
        _error = null;
        _rows = [
          for (final r in LookupLoader.rowsIn(res))
            if (r is Map) Map<String, dynamic>.from(r),
        ];
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = 'Could not load companies. ${e.message}');
    }
  }

  static String _created(Object? v) {
    final d = DateTime.tryParse('${v ?? ''}');
    return d == null ? '—' : DateFormat('d MMM yyyy, HH:mm').format(d.toLocal());
  }

  Future<void> _switchTo(Map<String, dynamic> row) async {
    final target = Company.fromJson(row);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await widget.session.setActive(target);
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text('Switch failed. ${widget.session.error ?? ''}')));
      return;
    }
    // Every screen open was built for the old company; start again from the
    // new one's dashboard.
    nav.popUntil((r) => r.isFirst);
    messenger.showSnackBar(SnackBar(content: Text('Switched to ${target.name}'), duration: const Duration(seconds: 2)));
  }

  Future<void> _create() async {
    final created = await Navigator.of(context).push<_Created>(MaterialPageRoute(
      builder: (_) => _NewCompanyScreen(session: widget.session),
    ));
    if (created == null || !mounted) return;
    await _load();
    await widget.session.loadCompanies();
    // A template business needs setting up before it is useful: switch into it
    // and hand over to the wizard, as the web does.
    final t = created.type;
    if (t.industryTemplate != null && created.farmId != null && mounted) {
      final company = Company.fromJson({'farmId': created.farmId, 'name': created.name, 'type': t.companyType});
      final nav = Navigator.of(context);
      if (await widget.session.setActive(company)) {
        nav.popUntil((r) => r.isFirst);
        nav.push(MaterialPageRoute(
          builder: (_) => WebPageScreen(
            label: 'Set up ${created.name}',
            href: '/generic-setup/wizard?industry=${Uri.encodeComponent(t.industryTemplate!)}',
            company: company,
            session: widget.session,
          ),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/companies');
    final rows = _rows;
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('My companies')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            AppButton(label: 'New company', icon: Icons.add, fullWidth: true, onPressed: _create),
            const SizedBox(height: 10),
            Text(
              'One login, multiple businesses. Create a poultry farm or a water business — switch between '
              'them anytime using the company switcher at the top of the page.',
              style: TextStyle(fontSize: 13, color: tokens.mutedForeground),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))
            else if (rows == null)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else if (rows.isEmpty)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No companies yet.')))
            else
              for (final r in rows) ...[
                _CompanyCard(
                  row: r,
                  active: '${r['farmId'] ?? r['id']}' == widget.company.farmId,
                  created: _created(r['createdAt']),
                  onSwitch: () => _switchTo(r),
                ),
                const SizedBox(height: 8),
              ],
          ],
        ),
      ),
    );
  }
}

class _CompanyCard extends StatelessWidget {
  const _CompanyCard({required this.row, required this.active, required this.created, required this.onSwitch});
  final Map<String, dynamic> row;
  final bool active;
  final String created;
  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final type = '${row['type'] ?? ''}';
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              companyIcon(type),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${row['name'] ?? row['farmName'] ?? ''}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              if (active)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1FAE5), // emerald-100
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text('✓ Active',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF047857))),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text('$type · ${row['role'] ?? ''}', style: TextStyle(fontSize: 13, color: tokens.mutedForeground)),
          const SizedBox(height: 4),
          Text('Created  $created', style: TextStyle(fontSize: 12, color: tokens.mutedForeground)),
          const SizedBox(height: 10),
          if (active)
            Text('You are working in this company.', style: TextStyle(fontSize: 12, color: tokens.mutedForeground))
          else
            AppButton(
              label: 'Switch to this company',
              variant: AppButtonVariant.outline,
              fullWidth: true,
              onPressed: onSwitch,
            ),
        ],
      ),
    );
  }
}

class _Created {
  const _Created(this.type, this.name, this.farmId);
  final BusinessType type;
  final String name;
  final String? farmId;
}

/// "Create new company" — the web's dialog.
class _NewCompanyScreen extends StatefulWidget {
  const _NewCompanyScreen({required this.session});
  final Session session;

  @override
  State<_NewCompanyScreen> createState() => _NewCompanyScreenState();
}

class _NewCompanyScreenState extends State<_NewCompanyScreen> {
  String _typeId = 'water';
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  bool _saving = false;

  BusinessType get _type => businessTypes.firstWhere((t) => t.id == _typeId);

  @override
  void dispose() {
    for (final c in [_name, _email, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _create() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_name.text.trim().isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Name required')));
      return;
    }
    setState(() => _saving = true);
    final name = _name.text.trim();
    try {
      final res = await widget.session.loginClient.post('/api/Companies', body: {
        'Name': name,
        'Type': _type.companyType,
        'Email': _email.text.trim().isEmpty ? null : _email.text.trim(),
        'PhoneNumber': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      });
      messenger.showSnackBar(SnackBar(content: Text('Created $name')));
      // The web emails a confirmation to the company email, or else the
      // owner's account email. The app keeps no account email, so it sends
      // only when one was typed here.
      final to = _email.text.trim();
      if (to.isNotEmpty) {
        try {
          await widget.session.farmClient.post('/api/Email/send-welcome', body: {
            'Email': to,
            'CompanyName': name,
            'CompanyType': _type.companyType,
          });
          messenger.showSnackBar(SnackBar(content: Text('Confirmation emailed to $to.')));
        } catch (_) {
          messenger.showSnackBar(const SnackBar(content: Text("Couldn't email confirmation.")));
        }
      }
      if (!mounted) return;
      final farmId = res is Map ? '${res['farmId'] ?? res['id'] ?? ''}' : '';
      Navigator.of(context).pop(_Created(_type, name, farmId.isEmpty ? null : farmId));
    } on ApiException catch (e) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('Create failed. ${e.message}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Scaffold(
      appBar: AppBar(title: const Text('Create new company')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
        children: [
          FormSection(title: 'Company', color: SectionColor.indigo, columns: 1, children: [
            AppField(
              label: 'Type',
              full: true,
              hint: _type.industryTemplate != null
                  ? "We'll set up the right menus and starter categories for this, and you can change any of it later."
                  : _type.description,
              child: AppSelect<String>(
                value: _typeId,
                items: [for (final t in businessTypes) AppSelectItem(value: t.id, label: t.label)],
                onChanged: (v) => setState(() => _typeId = v ?? _typeId),
              ),
            ),
            AppField(label: 'Company name', required: true, full: true,
                child: AppInput(controller: _name, hintText: 'e.g. Cool Spring Water Co.')),
            AppField(label: 'Contact email', full: true,
                child: AppInput(controller: _email, keyboardType: TextInputType.emailAddress)),
            AppField(label: 'Phone', full: true,
                child: AppInput(controller: _phone, keyboardType: TextInputType.phone)),
          ]),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Cancel',
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.lg,
                  fullWidth: true,
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppButton(
                  label: _saving ? 'Creating…' : 'Create',
                  size: AppButtonSize.lg,
                  fullWidth: true,
                  busy: _saving,
                  onPressed: _saving ? null : _create,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('${_type.label}: ${_type.description}', style: TextStyle(fontSize: 12, color: tokens.mutedForeground)),
        ],
      ),
    );
  }
}
