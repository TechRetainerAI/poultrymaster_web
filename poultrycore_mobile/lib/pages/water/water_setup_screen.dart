import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/tokens.dart';
import '../../design/ui/buttons.dart';
import '../../design/ui/form_section.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../lookup_loader.dart';
import '../poultry/reports/report_format.dart' show FarmMoney;
import '../shared/search_picker.dart';
import '../web_nav.dart';
import 'water_company_setup_screen.dart';
import 'water_setup_forms.dart';

/// Water → Setup → Company → Setup ("Water company setup"), as
/// `app/water-setup/page.tsx`: one hub, tabbed by setup area. Company edits
/// the profile and the farm's currency; every other area lists its records
/// with the web's columns, deletes inline, adds and edits through the hub's
/// own small forms (Suppliers has none, so Add opens its page), and offers
/// "Open full page".
class WaterSetupScreen extends StatefulWidget {
  const WaterSetupScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<WaterSetupScreen> createState() => _WaterSetupScreenState();
}

typedef _Col = (String header, String Function(Map<String, dynamic> row, FarmMoney money) value);

class _Tab {
  const _Tab({
    required this.key,
    required this.label,
    required this.icon,
    required this.path,
    required this.idKey,
    required this.title,
    required this.columns,
    required this.page,
    this.query = const {},
    this.deleteQuery,
    this.hasForm = true,
  });
  final String key;
  final String label;
  final IconData icon;
  final String path;
  final Map<String, String> query;
  final String idKey;
  final String Function(Map<String, dynamic> row) title;
  final List<_Col> columns;

  /// "Open full page": the entity's own page.
  final NavLink page;

  /// Extra DELETE query (suppliers: deletedBy).
  final Map<String, String> Function(Session s)? deleteQuery;

  /// False when the web has no inline modal (Add opens the full page).
  final bool hasForm;
}

num _n(Object? v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;
String _dash(Object? v) => v == null || '$v'.isEmpty ? '—' : '$v';
String _yesNo(Object? v) => v == true ? 'Yes' : 'No';
String _name(Map r) => '${r['firstName'] ?? ''} ${r['lastName'] ?? ''}'.trim();

/// The web's tabs, in its order, with its columns.
final _tabs = <_Tab>[
  _Tab(
    key: 'products', label: 'Products', icon: Icons.shopping_bag_outlined,
    path: '/api/Water/products', idKey: 'waterProductId', title: (p) => '${p['name'] ?? ''}',
    page: const NavLink('Products', '/water-products', 'water-products'),
    columns: [
      ('Name', (p, _) => _dash(p['name'])),
      ('Size', (p, _) => p['sizeMl'] != null && p['sizeMl'] != 0 ? '${p['sizeMl']}ml' : '—'),
      ('Unit', (p, _) => _dash(p['unit'])),
      ('Unit price', (p, m) => m(_n(p['unitPrice']))),
      ('Stock', (p, _) => '${p['stockOnHand'] ?? 0}'),
      ('Active', (p, _) => _yesNo(p['isActive'])),
    ],
  ),
  _Tab(
    key: 'customers', label: 'Customers', icon: Icons.people_outline,
    path: '/api/Water/customers', idKey: 'waterCustomerId', title: (c) => '${c['name'] ?? ''}',
    page: const NavLink('Customers', '/water-customers', 'water-customers'),
    columns: [
      ('Name', (c, _) => _dash(c['name'])),
      ('Phone', (c, _) => _dash(c['contactPhone'])),
      ('City', (c, _) => _dash(c['city'])),
      ('Outstanding', (c, m) => m(_n(c['outstandingBalance']))),
    ],
  ),
  _Tab(
    key: 'drivers', label: 'Drivers', icon: Icons.groups_outlined,
    path: '/api/Water/drivers', idKey: 'waterDriverId', title: (d) => '${d['driverName'] ?? ''}',
    page: const NavLink('Drivers', '/water-drivers', 'water-drivers'),
    columns: [
      ('Name', (d, _) => _dash(d['driverName'])),
      ('Phone', (d, _) => _dash(d['phoneNumber'])),
      ('License', (d, _) => _dash(d['licenseNumber'])),
      ('Active', (d, _) => _yesNo(d['isActive'])),
    ],
  ),
  _Tab(
    key: 'vehicles', label: 'Vehicles', icon: Icons.local_shipping_outlined,
    path: '/api/Water/vehicles', idKey: 'waterVehicleId',
    title: (v) => '${v['vehicleName'] ?? v['registrationNumber'] ?? 'Vehicle'}',
    page: const NavLink('Vehicles', '/water-vehicles', 'water-vehicles'),
    columns: [
      ('Name', (v, _) => _dash(v['vehicleName'])),
      ('Reg #', (v, _) => _dash(v['registrationNumber'])),
      ('Type', (v, _) => _dash(v['vehicleType'])),
      ('Capacity', (v, _) => v['capacityBags'] == null || v['capacityBags'] == 0 ? '—' : '${v['capacityBags']} bags'),
      ('Status', (v, _) => _dash(v['status'])),
    ],
  ),
  _Tab(
    key: 'routes', label: 'Routes', icon: Icons.alt_route,
    path: '/api/Water/routes', idKey: 'waterRouteId', title: (r) => '${r['routeName'] ?? ''}',
    page: const NavLink('Routes', '/water-routes', 'water-routes'),
    columns: [
      ('Name', (r, _) => _dash(r['routeName'])),
      ('Area covered', (r, _) => _dash(r['areaCovered'])),
      ('Expected customers', (r, _) => _dash(r['expectedCustomers'])),
      ('Expected bags', (r, _) => _dash(r['expectedBagsSold'])),
    ],
  ),
  _Tab(
    key: 'machines', label: 'Machines', icon: Icons.precision_manufacturing_outlined,
    path: '/api/Water/machines', idKey: 'waterMachineId', title: (m) => '${m['machineName'] ?? ''}',
    page: const NavLink('Machines', '/water-machines', 'water-machines'),
    columns: [
      ('Name', (r, _) => _dash(r['machineName'])),
      ('Type', (r, _) => _dash(r['machineType'])),
      ('Capacity / hr', (r, _) => _dash(r['capacityPerHour'])),
      ('Status', (r, _) => _dash(r['status'])),
    ],
  ),
  _Tab(
    key: 'boreholes', label: 'Boreholes', icon: Icons.water_outlined,
    path: '/api/Water/boreholes', idKey: 'waterBoreholeId', title: (b) => '${b['boreholeName'] ?? ''}',
    page: const NavLink('Boreholes', '/water-boreholes', 'water-boreholes'),
    columns: [
      ('Name', (b, _) => _dash(b['boreholeName'])),
      ('Location', (b, _) => _dash(b['location'])),
      ('Pump', (b, _) => _dash(b['pumpType'])),
      ('Status', (b, _) => _dash(b['status'])),
    ],
  ),
  _Tab(
    key: 'raw-materials', label: 'Raw materials & supplies', icon: Icons.inventory_2_outlined,
    path: '/api/Water/raw-material-items', idKey: 'waterRawMaterialItemId', title: (i) => '${i['itemName'] ?? ''}',
    page: const NavLink('Raw materials & supplies', '/water-raw-materials', 'water-raw-material-purchases'),
    columns: [
      ('Item', (i, _) => _dash(i['itemName'])),
      ('Category', (i, _) => _dash(i['category'])),
      ('Unit', (i, _) => _dash(i['unitOfMeasure'])),
      ('Stock', (i, _) => '${i['currentQuantity'] ?? 0}'),
      ('Min alert', (i, _) => _dash(i['minimumStockAlert'])),
      ('Active', (i, _) => _yesNo(i['isActive'])),
    ],
  ),
  _Tab(
    key: 'suppliers', label: 'Suppliers', icon: Icons.local_shipping_outlined,
    path: '/api/Water/suppliers', query: const {'includeInactive': 'true'},
    idKey: 'waterSupplierId', title: (s) => '${s['supplierName'] ?? ''}',
    page: const NavLink('Suppliers', '/water-suppliers', 'water-suppliers'),
    deleteQuery: (s) => {'deletedBy': s.tokens.userId ?? ''},
    hasForm: false,
    columns: [
      ('Name', (s, _) => _dash(s['supplierName'])),
      ('Type', (s, _) => _dash(s['supplierType'])),
      ('Phone', (s, _) => _dash(s['phone'])),
      ('Email', (s, _) => _dash(s['email'])),
      ('Active', (s, _) => _yesNo(s['isActive'])),
    ],
  ),
  _Tab(
    key: 'staff', label: 'Staff', icon: Icons.groups_outlined,
    path: '/api/Water/staff', idKey: 'waterStaffId', title: _name,
    page: const NavLink('Staff', '/water-staff', 'water-staff'),
    columns: [
      ('Name', (s, _) => _name(s).isEmpty ? '—' : _name(s)),
      ('Role', (s, _) => _dash(s['role'])),
      ('Phone', (s, _) => _dash(s['phoneNumber'])),
      ('Salary type', (s, _) => _dash(s['salaryType'])),
      ('Base pay', (s, m) => m(_n(s['basePay']))),
    ],
  ),
];

const _sky = Color(0xFF0284C7); // sky-600

class _WaterSetupScreenState extends State<WaterSetupScreen> {
  String _tab = 'company';

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/water-setup');
    final tab = _tabs.where((t) => t.key == _tab).firstOrNull;
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Water company setup')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          Text(
            'Everything the daily flow depends on — products, drivers, machines, routes, suppliers, staff. '
            'Add a row here to make it available in production, sales, payroll, etc.',
            style: TextStyle(fontSize: 13, color: tokens.mutedForeground),
          ),
          const SizedBox(height: 14),
          const Text('Choose setup area', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _AreaGrid(
            selected: _tab,
            areas: [
              ('company', 'Company', Icons.attach_money),
              for (final t in _tabs) (t.key, t.label, t.icon),
            ],
            onSelect: (k) => setState(() => _tab = k),
          ),
          const SizedBox(height: 14),
          if (tab == null)
            _CompanyCard(session: widget.session, company: widget.company)
          else
            _SetupSection(key: ValueKey(tab.key), tab: tab, session: widget.session, company: widget.company),
        ],
      ),
    );
  }
}

/// The web's card-tile tabs: two to a row on a phone, the active one sky.
class _AreaGrid extends StatelessWidget {
  const _AreaGrid({required this.selected, required this.areas, required this.onSelect});
  final String selected;
  final List<(String, String, IconData)> areas;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - 8) / 2;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (key, label, icon) in areas)
            SizedBox(
              width: w,
              child: Material(
                color: key == selected ? const Color(0xFFF0F9FF) : tokens.card, // sky-50
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: key == selected ? const Color(0xFF0EA5E9) : tokens.border),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onSelect(key),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(icon, size: 17, color: key == selected ? const Color(0xFF0369A1) : tokens.mutedForeground),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: key == selected ? FontWeight.w600 : FontWeight.w400,
                                color: key == selected ? const Color(0xFF0369A1) : null, // sky-700
                              )),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }
}

/// One setup area: count, Open full page, Add, and the rows with Edit and
/// Delete.
class _SetupSection extends StatefulWidget {
  const _SetupSection({super.key, required this.tab, required this.session, required this.company});
  final _Tab tab;
  final Session session;
  final Company company;

  @override
  State<_SetupSection> createState() => _SetupSectionState();
}

class _SetupSectionState extends State<_SetupSection> {
  List<Map<String, dynamic>>? _rows;
  FarmMoney _money = const FarmMoney();

  Map<String, String> get _farm => {'farmId': widget.company.farmId};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final t = widget.tab;
    try {
      _money = await FarmMoney.load(widget.session, widget.company);
      final res = await widget.session.farmClient.get(t.path, query: {..._farm, ...t.query});
      if (!mounted) return;
      setState(() => _rows = [
            for (final r in LookupLoader.rowsIn(res))
              if (r is Map) Map<String, dynamic>.from(r),
          ]);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _rows = const []);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not load ${t.label.toLowerCase()}. ${e.message}')));
    }
  }

  Future<void> _openPage() async {
    final nav = Navigator.of(context);
    openNavLink(nav, widget.tab.page, widget.session, widget.company);
  }

  Future<void> _form([Map<String, dynamic>? row]) async {
    final t = widget.tab;
    final def = hubForms[t.key];
    if (!t.hasForm || def == null) return _openPage();
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => WaterHubFormScreen(session: widget.session, company: widget.company, form: def, row: row),
    ));
    if (saved == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final t = widget.tab;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${t.label.toLowerCase()}?'),
        content: Text('${t.title(row)} will be permanently removed. Records that reference it may stop resolving.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.session.farmClient.delete('${t.path}/${row[t.idKey]}',
          query: {..._farm, ...?t.deleteQuery?.call(widget.session)});
      messenger.showSnackBar(SnackBar(content: Text('${t.label} deleted · ${t.title(row)}')));
      _load();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Delete failed. ${e.message}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final t = widget.tab;
    final rows = _rows;
    final noun = t.label.toLowerCase();
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Icon(t.icon, size: 20, color: _sky),
                  const SizedBox(width: 8),
                  Expanded(child: Text(t.label, style: const TextStyle(fontWeight: FontWeight.w600))),
                  if (rows != null) AppBadge(label: '${rows.length}'),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: AppButton(
                      label: 'Open full page',
                      icon: Icons.edit_outlined,
                      variant: AppButtonVariant.outline,
                      size: AppButtonSize.sm,
                      fullWidth: true,
                      onPressed: _openPage,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppButton(
                      label: 'Add $noun',
                      icon: Icons.add,
                      size: AppButtonSize.sm,
                      fullWidth: true,
                      onPressed: () => _form(),
                    ),
                  ),
                ]),
              ],
            ),
          ),
          Divider(height: 1, color: tokens.border),
          if (rows == null)
            const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
          else if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'No $noun yet. Click Add $noun above to create your first one.',
                textAlign: TextAlign.center,
                style: TextStyle(color: tokens.mutedForeground),
              ),
            )
          else
            for (final r in rows) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(t.title(r), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    for (final (header, value) in t.columns)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(children: [
                          SizedBox(
                            width: 140,
                            child: Text(header, style: TextStyle(fontSize: 12.5, color: tokens.mutedForeground)),
                          ),
                          Expanded(child: Text(value(r, _money), style: const TextStyle(fontSize: 13))),
                        ]),
                      ),
                    const SizedBox(height: 8),
                    Row(children: [
                      // Suppliers has no inline form, so no Edit, as on the web.
                      if (t.hasForm) ...[
                        Expanded(
                          child: AppButton(
                            label: 'Edit',
                            icon: Icons.edit_outlined,
                            variant: AppButtonVariant.outline,
                            size: AppButtonSize.sm,
                            fullWidth: true,
                            onPressed: () => _form(r),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: AppButton(
                          label: 'Delete',
                          icon: Icons.delete_outline,
                          variant: AppButtonVariant.outline,
                          size: AppButtonSize.sm,
                          fullWidth: true,
                          onPressed: () => _delete(r),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
              Divider(height: 1, color: tokens.border),
            ],
        ],
      ),
    );
  }
}

/// The Company tab: business profile, owner, production defaults and the
/// farm's currency. Sets the company up the first time.
class _CompanyCard extends StatefulWidget {
  const _CompanyCard({required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<_CompanyCard> createState() => _CompanyCardState();
}

const _businessTypes = ['Sachet', 'Bottled', 'Both'];
const _sources = <(String, String)>[
  ('Borehole', 'Borehole'),
  ('GhanaWater', 'Ghana Water'),
  ('Tanker', 'Tanker'),
  ('Mixed', 'Mixed'),
];

String _normalise(String? raw, List<String> allowed, String fallback) =>
    allowed.where((o) => o.toLowerCase() == (raw ?? '').toLowerCase()).firstOrNull ?? fallback;

class _CompanyCardState extends State<_CompanyCard> {
  final _brand = TextEditingController();
  final _site = TextEditingController();
  final _location = TextEditingController();
  final _owner = TextEditingController();
  final _phone = TextEditingController();
  final _sachets = TextEditingController(text: '30');
  final _notes = TextEditingController();
  final _symbol = TextEditingController(text: 'GHC');
  String _business = 'Sachet';
  String _source = 'Borehole';
  String _code = 'GHS';
  bool _showSymbol = true;
  bool _hasProfile = false;
  bool _loading = true;
  bool _saving = false;

  String get _farm => Uri.encodeComponent(widget.company.farmId);

  @override
  void initState() {
    super.initState();
    _symbol.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    for (final c in [_brand, _site, _location, _owner, _phone, _sachets, _notes, _symbol]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    Map? settings;
    Map? prof;
    try {
      final s = await widget.session.farmClient.get('/api/Water/farm-settings?farmId=$_farm');
      if (s is Map) settings = s;
    } catch (_) {}
    try {
      final p = await widget.session.farmClient.get('/api/Water/company?farmId=$_farm');
      if (p is Map) prof = p;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      if (settings != null) {
        _code = '${settings['currencyCode'] ?? 'GHS'}';
        _symbol.text = '${settings['currencySymbol'] ?? 'GHC'}';
        _showSymbol = settings['showCurrencySymbol'] != false;
      }
      if (prof != null) {
        _hasProfile = true;
        _brand.text = '${prof['brandName'] ?? ''}';
        _business = '${prof['businessType'] ?? 'WaterProduction'}';
        _source = '${prof['waterSourceType'] ?? 'Borehole'}';
        _site.text = '${prof['productionSiteAddress'] ?? ''}';
        _location.text = '${prof['mainLocation'] ?? ''}';
        _owner.text = '${prof['ownerName'] ?? ''}';
        _phone.text = '${prof['phoneNumber'] ?? ''}';
        _sachets.text = '${prof['defaultBagSachetCount'] ?? 30}';
        _notes.text = '${prof['notes'] ?? ''}';
      }
      _loading = false;
    });
  }

  String? _orNull(TextEditingController c) => c.text.isEmpty ? null : c.text;

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final wasSetUp = _hasProfile;
    final client = widget.session.farmClient;
    try {
      final payload = {
        'brandName': _orNull(_brand),
        'businessType': _normalise(_business, _businessTypes, 'Sachet'),
        'waterSourceType': _normalise(_source, [for (final s in _sources) s.$1], 'Borehole'),
        'productionSiteAddress': _orNull(_site),
        'mainLocation': _orNull(_location),
        'ownerName': _orNull(_owner),
        'phoneNumber': _orNull(_phone),
        'defaultCurrency': _code.trim().isEmpty ? 'GHS' : _code.trim(),
        'defaultBagSachetCount': (int.tryParse(_sachets.text.trim()) ?? 0) == 0 ? 30 : int.parse(_sachets.text.trim()),
        'notes': _orNull(_notes),
      };
      if (_hasProfile) {
        await client.put('/api/Water/company?farmId=$_farm', body: payload);
      } else {
        await client.post('/api/Water/company/setup', body: {...payload, 'farmId': widget.company.farmId});
        if (mounted) setState(() => _hasProfile = true);
      }
      await client.put('/api/Water/farm-settings/currency?farmId=$_farm', body: {
        'currencyCode': _code.trim().isEmpty ? 'GHS' : _code.trim(),
        'currencySymbol': _symbol.text.trim().isEmpty ? 'GHC' : _symbol.text.trim(),
        'showCurrencySymbol': _showSymbol,
      });
      FarmMoney.clearCache();
      messenger.showSnackBar(SnackBar(content: Text(wasSetUp ? 'Company settings saved.' : 'Water company set up.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not save. ${e.message}')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Row(children: [
        const Icon(Icons.settings_outlined, size: 20, color: _sky),
        const SizedBox(width: 8),
        const Flexible(child: Text('Company', style: TextStyle(fontWeight: FontWeight.w600))),
        if (_hasProfile && !_loading) ...[const SizedBox(width: 8), const AppBadge(label: 'Set up')],
        const Spacer(),
        AppButton(
          label: 'Open full page',
          icon: Icons.edit_outlined,
          variant: AppButtonVariant.outline,
          size: AppButtonSize.sm,
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => WaterCompanySetupScreen(session: widget.session, company: widget.company),
          )),
        ),
      ]),
    );
    if (_loading) {
      return AppCard(
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          header,
          Divider(height: 1, color: tokens.border),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 8),
              Text('Loading company settings…', style: TextStyle(color: tokens.mutedForeground)),
            ]),
          ),
        ]),
      );
    }
    final hint = TextStyle(fontSize: 12, color: tokens.mutedForeground);
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Divider(height: 1, color: tokens.border),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FormSection(title: 'Business profile', color: SectionColor.indigo, children: [
                  AppField(label: 'Brand name', full: true, child: AppInput(controller: _brand)),
                  AppField(
                    label: 'Business type',
                    required: true,
                    child: AppSelect<String>(
                      value: _normalise(_business, _businessTypes, 'Sachet'),
                      hintText: 'Pick business type',
                      items: [for (final b in _businessTypes) AppSelectItem(value: b, label: b)],
                      onChanged: (v) => setState(() => _business = v ?? _business),
                    ),
                  ),
                  AppField(
                    label: 'Water source',
                    required: true,
                    child: AppSelect<String>(
                      value: _normalise(_source, [for (final s in _sources) s.$1], 'Borehole'),
                      hintText: 'Pick water source',
                      items: [for (final (v, l) in _sources) AppSelectItem(value: v, label: l)],
                      onChanged: (v) => setState(() => _source = v ?? _source),
                    ),
                  ),
                  AppField(label: 'Production site address', full: true, child: AppInput(controller: _site)),
                  AppField(label: 'Main location / town', full: true, child: AppInput(controller: _location)),
                ]),
                const SizedBox(height: 12),
                FormSection(title: 'Owner', color: SectionColor.blue, children: [
                  AppField(label: 'Owner name', child: AppInput(controller: _owner)),
                  AppField(label: 'Phone', child: AppInput(controller: _phone, keyboardType: TextInputType.phone)),
                ]),
                const SizedBox(height: 12),
                FormSection(title: 'Production defaults', color: SectionColor.green, children: [
                  AppField(
                    label: 'Sachets per bag',
                    hint: 'Used as default when recording production.',
                    child: AppNumberInput(controller: _sachets),
                  ),
                ]),
                const SizedBox(height: 12),
                FormSection(title: 'Currency settings', color: SectionColor.amber, children: [
                  AppField(
                    label: 'Currency',
                    hint: 'Every ISO 4217 currency — search by code, name or symbol.',
                    child: CurrencyPickerField(
                      code: _code,
                      // Picking fills the standard symbol; the field stays
                      // editable, since many write "GHC" rather than "₵".
                      onChanged: (o) => setState(() {
                        _code = o.code;
                        _symbol.text = o.symbol;
                      }),
                    ),
                  ),
                  AppField(
                    label: 'Currency symbol',
                    hint: 'Prefix rendered before amounts. e.g. GHC, ₵, \$, ₦.',
                    child: AppInput(controller: _symbol),
                  ),
                  AppField(
                    label: 'Show currency symbol on pages',
                    full: true,
                    child: AppSwitchRow(
                      label: 'When off, amounts render as bare numbers (e.g. 1,234.50).',
                      value: _showSymbol,
                      onChanged: (v) => setState(() => _showSymbol = v),
                    ),
                  ),
                  AppField(
                    label: '',
                    full: true,
                    child: Text('Preview: ${_showSymbol ? '${_symbol.text} ' : ''}1,234.50', style: hint),
                  ),
                ]),
                const SizedBox(height: 12),
                FormSection(title: 'Notes', color: SectionColor.slate, columns: 1, children: [
                  AppField(label: 'Notes', full: true, child: AppTextarea(controller: _notes)),
                ]),
                const SizedBox(height: 14),
                AppButton(
                  label: _saving ? 'Saving…' : _hasProfile ? 'Save settings' : 'Set up Water Company',
                  icon: Icons.save_outlined,
                  size: AppButtonSize.lg,
                  fullWidth: true,
                  busy: _saving,
                  onPressed: _saving ? null : _save,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
