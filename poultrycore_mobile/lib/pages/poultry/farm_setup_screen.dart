import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/tokens.dart';
import '../../design/ui/buttons.dart';
import '../../design/ui/form_section.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../list_screen.dart';
import '../record_api.dart';
import '../record_navigation.dart';
import '../registry.dart';
import '../shared/currencies.dart';
import '../shared/search_picker.dart';
import 'company_setup_screen.dart';
import 'poultry_profile_form.dart';

/// Poultry → Setup → Company → Farm Setup ("Poultry farm setup"), as
/// `app/poultry-setup/page.tsx`: one hub, tabbed by setup area. Company
/// edits the profile and the farm's currency; every other area lists its
/// records with the web's columns, deletes inline, and adds or edits through
/// the page's own form — one form per entity, never a second copy.
class FarmSetupScreen extends StatefulWidget {
  const FarmSetupScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<FarmSetupScreen> createState() => _FarmSetupScreenState();
}

/// One column of a tab's table: header, then how a row shows in it.
typedef _Col = (String header, String Function(Map<String, dynamic> row) value);

class _Tab {
  const _Tab(this.key, this.label, this.singular, this.icon, this.specKey, this.title, this.columns);
  final String key;
  final String label;
  final String singular;
  final IconData icon;
  final String specKey;
  final String Function(Map<String, dynamic> row) title;
  final List<_Col> columns;
}

String _dash(Object? v) => v == null || '$v'.isEmpty ? '—' : '$v';
String _yesNo(Object? v) => v == true ? 'Yes' : 'No';

/// The web's tabs, in its order, with its columns.
final _tabs = <_Tab>[
  _Tab('products', 'Products', 'product', Icons.inventory_2_outlined, 'poultry-products', (p) => _dash(p['name']), [
    ('Unit', (p) => _dash(p['unit'])),
    ('Type', (p) => _dash(p['productType'])),
    ('In stock', (p) => '${p['stockOnHand'] ?? 0}'),
    ('Active', (p) => _yesNo(p['isActive'])),
  ]),
  _Tab('customers', 'Customers', 'customer', Icons.people_outline, 'customer', (c) => _dash(c['name']), [
    ('Phone', (c) => _dash(c['contactPhone'])),
    ('Email', (c) => _dash(c['contactEmail'])),
    ('City', (c) => _dash(c['city'])),
  ]),
  _Tab('drivers', 'Drivers', 'driver', Icons.groups_outlined, 'poultry-drivers', (d) => _dash(d['driverName']), [
    ('Phone', (d) => _dash(d['phoneNumber'])),
    ('Licence', (d) => _dash(d['licenseNumber'])),
    ('Commission / crate', (d) => _dash(d['commissionPerCrate'])),
    ('Active', (d) => _yesNo(d['isActive'])),
  ]),
  _Tab('vehicles', 'Vehicles', 'vehicle', Icons.local_shipping_outlined, 'poultry-vehicles', (v) => _dash(v['vehicleName']), [
    ('Reg #', (v) => _dash(v['registrationNumber'])),
    ('Type', (v) => _dash(v['vehicleType'])),
    ('Capacity', (v) => v['capacityCrates'] == null || '${v['capacityCrates']}' == '0' ? '—' : '${v['capacityCrates']} crates'),
    ('Status', (v) => _dash(v['status'])),
  ]),
  _Tab('routes', 'Routes', 'route', Icons.alt_route, 'poultry-routes', (r) => _dash(r['routeName']), [
    ('Area covered', (r) => _dash(r['areaCovered'])),
    ('Expected customers', (r) => _dash(r['expectedCustomers'])),
    ('Expected crates', (r) => _dash(r['expectedCratesSold'])),
  ]),
  _Tab('houses', 'Houses', 'house', Icons.business_outlined, 'house', (h) => _dash(h['houseName'] ?? h['name']), [
    ('Capacity', (h) => _dash(h['capacity'])),
    ('Location', (h) => _dash(h['location'])),
  ]),
  _Tab('flocks', 'Flock groups', 'flock group', Icons.flutter_dash, 'flocks', (f) => _dash(f['name']), [
    ('Breed', (f) => _dash(f['breed'])),
    ('Birds', (f) => _dash(f['quantity'])),
    ('Batch', (f) => _dash(f['batchName'])),
    ('Active', (f) => _yesNo(f['active'])),
  ]),
  _Tab('raw-materials', 'Raw materials & supplies', 'raw material', Icons.inventory_outlined, 'raw-materials',
      (i) => _dash(i['itemName']), [
    ('Category', (i) => _dash(i['category'])),
    ('Unit', (i) => _dash(i['unitOfMeasure'])),
    ('Stock', (i) => '${i['currentQuantity'] ?? 0}'),
    ('Min alert', (i) => _dash(i['minimumStockAlert'])),
    ('Active', (i) => _yesNo(i['isActive'])),
  ]),
  _Tab('suppliers', 'Suppliers', 'supplier', Icons.local_shipping_outlined, 'supplier', (s) => _dash(s['name']), [
    ('Phone', (s) => _dash(s['contactPhone'])),
    ('Email', (s) => _dash(s['contactEmail'])),
    ('City', (s) => _dash(s['city'])),
  ]),
  _Tab('employees', 'Employees', 'employee', Icons.manage_accounts_outlined, 'admin-company-employees',
      (e) {
        final n = '${e['firstName'] ?? ''} ${e['lastName'] ?? ''}'.trim();
        return n.isNotEmpty ? n : _dash(e['userName'] ?? e['email']);
      }, [
    ('Email', (e) => _dash(e['email'])),
    ('Phone', (e) => _dash(e['phoneNumber'])),
    ('Role', (e) => e['isAdmin'] == true ? 'Admin' : e['isStaff'] == true ? 'Staff' : '—'),
  ]),
];

const _amber = Color(0xFFD97706); // amber-600

class _FarmSetupScreenState extends State<FarmSetupScreen> {
  String _tab = 'company';

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-setup');
    final tab = _tabs.where((t) => t.key == _tab).firstOrNull;
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Poultry farm setup')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          Text(
            'Everything the daily flow depends on — products, drivers, houses, flock groups, suppliers, '
            'staff. Add a row here to make it available in production, sales, deliveries and payroll.',
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

/// The web's tab triggers: two to a row on a phone, the active one amber.
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
                color: key == selected ? const Color(0xFFFFFBEB) : tokens.card, // amber-50
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: key == selected ? _amber : tokens.border),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onSelect(key),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(icon, size: 17, color: key == selected ? _amber : tokens.mutedForeground),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: key == selected ? FontWeight.w600 : FontWeight.w400,
                                color: key == selected ? const Color(0xFFB45309) : null, // amber-700
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
/// Delete. Edit and Add open the page's own form.
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
  String? _error;

  RecordApi? get _api {
    final spec = PageRegistry.of(widget.tab.specKey);
    return spec == null ? null : RecordApi(widget.session, spec, widget.company);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = _api;
    if (api == null) return;
    try {
      final rows = await api.list();
      if (mounted) setState(() => _rows = rows);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _rows = const [];
          _error = 'Could not load ${widget.tab.label.toLowerCase()}. ${e.message}';
        });
      }
    }
  }

  Future<void> _form([Map<String, dynamic>? row]) async {
    final spec = PageRegistry.of(widget.tab.specKey)!;
    final opened = openRecordForm(context, session: widget.session, company: widget.company, spec: spec, row: row);
    if (opened == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Open the full page to change this.')));
      return;
    }
    if (await opened == true) _load();
  }

  Future<void> _openPage() async {
    final spec = PageRegistry.of(widget.tab.specKey)!;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ListScreen(spec: spec, session: widget.session, company: widget.company),
    ));
    _load();
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final t = widget.tab;
    final api = _api!;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${t.singular}?'),
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
    final id = api.idIn(row);
    if (id == null) return;
    try {
      await api.remove(id);
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
                  Icon(t.icon, size: 20, color: _amber),
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
                      label: 'Add ${t.singular}',
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
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            )
          else if (rows == null)
            const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
          else if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'No ${t.label.toLowerCase()} yet. Tap Add ${t.singular} above to create your first one.',
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
                          Expanded(child: Text(value(r), style: const TextStyle(fontSize: 13))),
                        ]),
                      ),
                    const SizedBox(height: 8),
                    Row(children: [
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

/// The Company tab: the profile plus the farm's currency (code, symbol,
/// whether amounts show it). Sets the company up the first time.
class _CompanyCard extends StatefulWidget {
  const _CompanyCard({required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<_CompanyCard> createState() => _CompanyCardState();
}

class _CompanyCardState extends State<_CompanyCard> {
  final _form = PoultryProfileForm();
  final _symbol = TextEditingController(text: 'GHC');
  String _code = 'GHS';
  bool _showSymbol = true;
  bool _loading = true;
  bool _saving = false;

  String get _farm => Uri.encodeComponent(widget.company.farmId);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _form.dispose();
    _symbol.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    Map? settings;
    try {
      final s = await widget.session.farmClient.get('/api/Water/farm-settings?farmId=$_farm');
      if (s is Map) settings = s;
    } catch (_) {}
    try {
      await loadPoultryProfile(widget.session, widget.company, _form);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      if (settings != null) {
        _code = '${settings['currencyCode'] ?? 'GHS'}';
        _symbol.text = '${settings['currencySymbol'] ?? _code}';
        _showSymbol = settings['showCurrencySymbol'] != false;
      } else if (_form.isSetUp && _form.currency.isNotEmpty) {
        // A company set up before the Farms row carried a currency: seed the
        // picker from the profile, as the web does.
        _code = _form.currency.toUpperCase();
        _symbol.text = currencySymbolFor(_code);
      }
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final wasNew = !_form.isSetUp;
    try {
      // The Currency section is the single control; the profile mirrors it.
      final payload = {..._form.payload(), 'defaultCurrency': _code};
      await savePoultryProfile(widget.session, widget.company, _form, payload);
      await widget.session.farmClient.put('/api/Water/farm-settings/currency?farmId=$_farm', body: {
        'currencyCode': _code,
        'currencySymbol': _symbol.text.trim(),
        'showCurrencySymbol': _showSymbol,
      });
      messenger.showSnackBar(SnackBar(
          content: Text(wasNew ? 'Poultry Company set up. Default cash accounts seeded.' : 'Company settings saved')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Save failed. ${e.message}')));
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
        const Icon(Icons.business_outlined, size: 20, color: _amber),
        const SizedBox(width: 8),
        const Text('Company', style: TextStyle(fontWeight: FontWeight.w600)),
        if (_form.isSetUp) ...[const SizedBox(width: 8), const AppBadge(label: 'Set up')],
        const Spacer(),
        AppButton(
          label: 'Open full page',
          icon: Icons.edit_outlined,
          variant: AppButtonVariant.outline,
          size: AppButtonSize.sm,
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => PoultryCompanySetupScreen(session: widget.session, company: widget.company),
          )),
        ),
      ]),
    );
    if (_loading) {
      return AppCard(
        padding: EdgeInsets.zero,
        child: Column(children: [header, const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())]),
      );
    }
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
                FormSection(title: 'Business details', color: SectionColor.amber, children: _form.fields(setState)),
                const SizedBox(height: 12),
                FormSection(title: 'Currency', color: SectionColor.amber, children: [
                  AppField(
                    label: 'Currency',
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
                  AppField(label: 'Symbol', child: AppInput(controller: _symbol, hintText: 'GHC')),
                  AppField(
                    label: '',
                    full: true,
                    child: AppSwitchRow(
                      label: 'Show symbol on amounts',
                      value: _showSymbol,
                      onChanged: (v) => setState(() => _showSymbol = v),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                AppButton(
                  label: _saving ? 'Saving…' : _form.isSetUp ? 'Save changes' : 'Set up Poultry Company',
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
