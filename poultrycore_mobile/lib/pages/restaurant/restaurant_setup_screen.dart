// Restaurant → Menu & Setup → Restaurant Setup, as `app/restaurant-setup/page.tsx`:
// Save Changes in the header, and three tabs — Profile (basic information with
// the remembered Cuisine Type list, service types, contact & location, and
// operations: hours, seating, currency, company time zone, tax and service
// charge), Menu Schedules and Modifiers (groups and their options).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/sales/balances_widgets.dart' show LoadingLine;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/company_timezone_field.dart';
import '../shared/currencies.dart' show currencySymbolFor;
import '../shared/search_picker.dart' show CurrencyPickerField;
import 'restaurant_other_select.dart';
import 'restaurant_roles.dart' show restaurantRose;

const restaurantServiceTypes = ['DineIn', 'Takeaway', 'Delivery', 'DriveThrough'];
const _serviceLabels = {'DineIn': 'Dine-In', 'Takeaway': 'Takeaway', 'Delivery': 'Delivery', 'DriveThrough': 'Drive-Through'};
const _serviceEmoji = {'DineIn': '🍽️', 'Takeaway': '🥡', 'Delivery': '🛵', 'DriveThrough': '🚗'};
const restaurantDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// CUISINE_TYPES ("Other" is the select's own row).
const restaurantCuisineTypes = [
  'Multi-Cuisine', 'Italian', 'Chinese', 'Japanese', 'Indian', 'Mexican', 'Thai',
  'French', 'Mediterranean', 'American', 'African', 'Korean', 'Middle Eastern',
  'Seafood', 'Steakhouse', 'Vegetarian', 'Vegan', 'Fusion',
];

const restaurantScheduleNames = [
  'Breakfast', 'Brunch', 'Lunch', 'Afternoon Tea', 'Happy Hour', 'Dinner', 'Late Night', 'Weekend Special', 'Holiday Menu', 'All Day',
];

const restaurantModifierGroupNames = [
  'Choose Size', 'Extra Toppings', 'Choose Sauce', 'Choose Side', 'Choose Drink', 'Cooking Level', 'Spice Level', 'Choose Protein',
  'Choose Bread', 'Dressing', 'Add-Ons', 'Remove Ingredients', 'Choose Flavor', 'Portion Size', 'Temperature',
];

Widget _label(String text, {bool required = false, IconData? icon}) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        if (icon != null) ...[Icon(icon, size: 14, color: TColors.slate500), const SizedBox(width: 6)],
        Flexible(
          child: Text.rich(TextSpan(children: [
            TextSpan(text: text),
            if (required) const TextSpan(text: ' *', style: TextStyle(color: Color(0xFFF43F5E))),
          ]), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ),
      ]),
    );

/// An `<input type="time">`: HH:mm, picked with the clock.
class RestaurantTimeField extends StatelessWidget {
  const RestaurantTimeField({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () async {
          final parts = value.split(':');
          final picked = await showTimePicker(
            context: context,
            initialTime: TimeOfDay(hour: int.tryParse(parts.first) ?? 0, minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0),
          );
          if (picked != null) {
            onChanged('${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
          }
        },
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
          child: Row(children: [
            Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
            const Icon(Icons.schedule, size: 16, color: TColors.slate400),
          ]),
        ),
      );
}

Widget _numInput(TextEditingController c, {bool decimal = false, ValueChanged<String>? onChanged, Widget? prefix, String? hint}) => AppInput(
      controller: c,
      hintText: hint,
      prefixIcon: prefix,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal, signed: prefix != null),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(decimal ? r'^-?\d*\.?\d*' : r'^\d*'))],
      onChanged: onChanged,
    );

class RestaurantSetupScreen extends StatefulWidget {
  const RestaurantSetupScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<RestaurantSetupScreen> createState() => _RestaurantSetupScreenState();
}

class _RestaurantSetupScreenState extends State<RestaurantSetupScreen> {
  final _cuisine = GlobalKey<RestaurantOtherSelectState>();
  bool _loading = true, _saving = false;
  String _tab = 'profile';
  Map<String, dynamic> _profile = {'restaurantName': ''};
  Set<String> _services = {};
  List<Map> _schedules = [], _groups = [], _modifiers = [];

  final _name = TextEditingController();
  final _description = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _country = TextEditingController();
  final _seating = TextEditingController();
  final _tax = TextEditingController();
  final _service = TextEditingController();

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  Map<String, dynamic> get _q => {'farmId': _farmId};

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    for (final c in [_name, _description, _phone, _email, _address, _city, _country, _seating, _tax, _service]) {
      c.dispose();
    }
    super.dispose();
  }

  List<Map> _rows(Object? r) => [for (final x in (r is List ? r : const [])) if (x is Map) x];

  Future<List<Map>> _list(String path) async => _rows(await _api.get(path, query: _q));

  String _n(Object? v) {
    final x = tNum(v);
    return x == x.roundToDouble() ? '${x.toInt()}' : '$x';
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      Map? p;
      try {
        final r = await _api.get('/api/Restaurant/setup/profile', query: _q);
        p = r is Map ? r : null;
      } catch (_) {
        p = null;
      }
      final r = await Future.wait([
        _list('/api/Restaurant/menu/schedules'),
        _list('/api/Restaurant/menu/modifier-groups'),
        _list('/api/Restaurant/menu/modifiers'),
      ]);
      if (p != null) {
        _profile = Map<String, dynamic>.from(p);
        _services = tStr(p['serviceTypes']).split(',').where((s) => s.isNotEmpty).toSet();
      }
      _name.text = tStr(_profile['restaurantName']);
      _description.text = tStr(_profile['description']);
      _phone.text = tStr(_profile['phone']);
      _email.text = tStr(_profile['email']);
      _address.text = tStr(_profile['address']);
      _city.text = tStr(_profile['city']);
      _country.text = tStr(_profile['country']);
      _seating.text = _n(_profile['seatingCapacity']);
      _tax.text = _n(_profile['taxRate']);
      _service.text = _n(_profile['serviceChargeRate']);
      _schedules = r[0];
      _groups = r[1];
      _modifiers = r[2];
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed to load', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _toggleService(String s) => setState(() {
        _services.contains(s) ? _services.remove(s) : _services.add(s);
        _profile['serviceTypes'] = _services.join(',');
      });

  Future<void> _saveProfile() async {
    if (_name.text.trim().isEmpty) return trackerToast(context, 'Restaurant name is required', error: true);
    setState(() => _saving = true);
    final body = {
      ..._profile,
      'restaurantName': _name.text,
      'description': _description.text,
      'phone': _phone.text,
      'email': _email.text,
      'address': _address.text,
      'city': _city.text,
      'country': _country.text,
      'seatingCapacity': int.tryParse(_seating.text) ?? 0,
      'taxRate': double.tryParse(_tax.text) ?? 0,
      'serviceChargeRate': double.tryParse(_service.text) ?? 0,
      'farmId': _farmId,
    };
    try {
      await _api.post('/api/Restaurant/setup/profile', body: body);
      // A cuisine typed under "Other" joins the list once the profile saved.
      await _cuisine.currentState?.remember();
      // Currency is a COMPANY setting: it moves the company's display currency
      // too, but only when the code changed, so a preferred symbol survives.
      try {
        final current = await _api.get('/api/Water/farm-settings', query: _q);
        final picked = tStr(_profile['defaultCurrency']).toUpperCase();
        final now = current is Map ? tStr(current['currencyCode']).toUpperCase() : '';
        if (picked.isNotEmpty && picked != now) {
          await _api.put('/api/Water/farm-settings/currency', query: _q, body: {
            'currencyCode': picked,
            'currencySymbol': currencySymbolFor(picked),
            'showCurrencySymbol': current is Map ? current['showCurrencySymbol'] != false : true,
          });
        }
      } catch (_) {
        if (mounted) {
          trackerToast(context, 'Currency not applied app-wide',
              description: 'The profile saved, but the display currency could not be updated. Set it in Setup > Company.', error: true);
        }
      }
      if (mounted) trackerToast(context, 'Profile saved successfully');
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Save failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  // ------------------------------------------------------------ schedules
  Future<void> _openSchedule([Map? s]) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => _ScheduleDialog(api: _api, farmId: _farmId, existing: s));
    if (saved == true) {
      _schedules = await _list('/api/Restaurant/menu/schedules');
      if (mounted) setState(() {});
    }
  }

  Future<void> _deleteSchedule(Map s) async {
    try {
      await _api.delete('/api/Restaurant/menu/schedules/${s['menuScheduleId']}', query: _q);
      if (mounted) trackerToast(context, 'Schedule deleted');
      _schedules = await _list('/api/Restaurant/menu/schedules');
      if (mounted) setState(() {});
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Delete failed', description: e.message, error: true);
    }
  }

  // ------------------------------------------------------------ modifiers
  Future<void> _openGroup([Map? g]) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => _GroupDialog(api: _api, farmId: _farmId, existing: g));
    if (saved == true) {
      _groups = await _list('/api/Restaurant/menu/modifier-groups');
      if (mounted) setState(() {});
    }
  }

  Future<void> _deleteGroup(Map g) async {
    try {
      await _api.delete('/api/Restaurant/menu/modifier-groups/${g['modifierGroupId']}', query: _q);
      if (mounted) trackerToast(context, 'Group deleted');
      _groups = await _list('/api/Restaurant/menu/modifier-groups');
      _modifiers = await _list('/api/Restaurant/menu/modifiers');
      if (mounted) setState(() {});
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Delete failed', description: e.message, error: true);
    }
  }

  Future<void> _openModifier({Map? m, int? groupId}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ModifierDialog(api: _api, farmId: _farmId, existing: m, groups: _groups, groupId: groupId),
    );
    if (saved == true) {
      _modifiers = await _list('/api/Restaurant/menu/modifiers');
      if (mounted) setState(() {});
    }
  }

  Future<void> _deleteModifier(Map m) async {
    try {
      await _api.delete('/api/Restaurant/menu/modifiers/${m['modifierId']}', query: _q);
      if (mounted) trackerToast(context, 'Modifier deleted');
      _modifiers = await _list('/api/Restaurant/menu/modifiers');
      if (mounted) setState(() {});
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Delete failed', description: e.message, error: true);
    }
  }

  // ------------------------------------------------------------------- UI
  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/restaurant-setup');
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Restaurant Setup')),
      body: _loading
          ? const Padding(padding: EdgeInsets.all(20), child: LoadingLine('Loading…'))
          : ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
              _header(),
              const SizedBox(height: 14),
              _tabs(),
              const SizedBox(height: 12),
              if (_tab == 'profile') ..._profileTab(),
              if (_tab == 'schedules') _schedulesTab(),
              if (_tab == 'modifiers') _modifiersTab(),
            ]),
    );
  }

  Widget _tile(IconData icon, Color bg, Color fg, {double size = 40}) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: size / 2, color: fg),
      );

  Widget _header() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          _tile(Icons.settings_outlined, const Color(0xFFFFE4E6), restaurantRose),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Restaurant Setup', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
              Text('Configure your restaurant profile, menu schedules and modifiers', style: TextStyle(fontSize: 13, color: TColors.slate500)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: restaurantRose, minimumSize: const Size.fromHeight(44)),
          onPressed: _saving ? null : _saveProfile,
          icon: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check_circle_outline, size: 18),
          label: const Text('Save Changes'),
        ),
      ]);

  Widget _tabs() {
    final tabs = [
      ('profile', Icons.storefront_outlined, 'Profile', null),
      ('schedules', Icons.schedule, 'Menu Schedules', _schedules.isEmpty ? null : _schedules.length),
      ('modifiers', Icons.restaurant, 'Modifiers', _groups.isEmpty ? null : _groups.length),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: TColors.slate200),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1))],
      ),
      child: Wrap(spacing: 4, runSpacing: 4, children: [
        for (final (v, icon, label, n) in tabs)
          Material(
            color: _tab == v ? const Color(0xFFFFF1F2) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => setState(() => _tab = v),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 16, color: _tab == v ? const Color(0xFFBE123C) : TColors.slate600),
                  const SizedBox(width: 6),
                  Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: _tab == v ? const Color(0xFFBE123C) : TColors.slate600)),
                  if (n != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: TColors.slate100, borderRadius: BorderRadius.circular(999)),
                      child: Text('$n', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: TColors.slate700)),
                    ),
                  ],
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _section(IconData icon, String title, String description, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(icon, size: 20, color: const Color(0xFFF43F5E)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  Text(description, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            ...children,
          ]),
        ),
      );

  Widget _gap() => const SizedBox(height: 12);

  List<Widget> _profileTab() => [
        _section(Icons.storefront_outlined, 'Basic Information', "Your restaurant's name, cuisine and description", [
          _label('Restaurant Name', required: true),
          AppInput(controller: _name, hintText: 'Enter restaurant name'),
          _gap(),
          _label('Cuisine Type'),
          RestaurantOtherSelect(
            key: _cuisine,
            session: widget.session,
            company: widget.company,
            listKey: 'CuisineType',
            baseOptions: restaurantCuisineTypes,
            value: tStr(_profile['cuisineType']).isEmpty ? null : tStr(_profile['cuisineType']),
            onChanged: (v) => setState(() => _profile['cuisineType'] = v),
            placeholder: 'Select cuisine type',
          ),
          _gap(),
          _label('Description'),
          AppTextarea(controller: _description, hintText: 'Describe your restaurant — this appears on your online ordering page', rows: 3),
        ]),
        _section(Icons.public, 'Service Types', 'Choose how customers can order from your restaurant', [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.6,
            children: [
              for (final s in restaurantServiceTypes)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _toggleService(s),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _services.contains(s) ? const Color(0xFFFFF1F2) : Colors.white,
                      border: Border.all(color: _services.contains(s) ? const Color(0xFFF43F5E) : const Color(0xFFE5E7EB), width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Stack(children: [
                      if (_services.contains(s))
                        const Positioned(top: 6, right: 6, child: Icon(Icons.check_circle_outline, size: 16, color: Color(0xFFF43F5E))),
                      Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(_serviceEmoji[s]!, style: const TextStyle(fontSize: 24)),
                          const SizedBox(height: 6),
                          Text(_serviceLabels[s]!,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: _services.contains(s) ? const Color(0xFFBE123C) : const Color(0xFF4B5563))),
                        ]),
                      ),
                    ]),
                  ),
                ),
            ],
          ),
        ]),
        _section(Icons.place_outlined, 'Contact & Location', 'How customers find and reach your restaurant', [
          _label('Phone', icon: Icons.phone_outlined),
          AppInput(controller: _phone, hintText: '+233 XX XXX XXXX', keyboardType: TextInputType.phone),
          _gap(),
          _label('Email', icon: Icons.mail_outline),
          AppInput(controller: _email, hintText: 'info@restaurant.com', keyboardType: TextInputType.emailAddress),
          _gap(),
          _label('Address'),
          AppInput(controller: _address, hintText: 'Street address'),
          _gap(),
          _label('City'),
          AppInput(controller: _city, hintText: 'City'),
          _gap(),
          _label('Country'),
          AppInput(controller: _country, hintText: 'Country'),
        ]),
        _section(Icons.schedule, 'Operations', 'Operating hours, capacity, and financial settings', [
          _label('Opening Time'),
          RestaurantTimeField(
            value: tStr(_profile['openingTime']).isEmpty ? '08:00' : tStr(_profile['openingTime']),
            onChanged: (v) => setState(() => _profile['openingTime'] = v),
          ),
          _gap(),
          _label('Closing Time'),
          RestaurantTimeField(
            value: tStr(_profile['closingTime']).isEmpty ? '22:00' : tStr(_profile['closingTime']),
            onChanged: (v) => setState(() => _profile['closingTime'] = v),
          ),
          _gap(),
          _label('Seating Capacity', icon: Icons.groups_outlined),
          _numInput(_seating),
          const Divider(height: 28),
          _label('Currency', icon: Icons.attach_money),
          // The same world-currency picker as Poultry; saved to the company too.
          CurrencyPickerField(
            code: tStr(_profile['defaultCurrency']).isEmpty ? 'GHS' : tStr(_profile['defaultCurrency']),
            onChanged: (o) => setState(() => _profile['defaultCurrency'] = o.code),
          ),
          _gap(),
          // The company time zone lives on the company row and saves itself.
          CompanyTimeZoneField(session: widget.session, company: widget.company),
          _gap(),
          _label('Tax Rate (%)'),
          _numInput(_tax, decimal: true),
          _gap(),
          _label('Service Charge (%)'),
          _numInput(_service, decimal: true),
        ]),
      ];

  Widget _cardHead(IconData icon, Color bg, Color fg, String title, String description, String button, VoidCallback onAdd) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          _tile(icon, bg, fg, size: 36),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              Text(description, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: restaurantRose, minimumSize: const Size.fromHeight(44)),
          onPressed: onAdd,
          icon: const Icon(Icons.add, size: 18),
          label: Text(button),
        ),
        const SizedBox(height: 12),
      ]);

  Widget _empty(IconData icon, String title, String body, String button, VoidCallback onTap) => Container(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        decoration: BoxDecoration(border: Border.all(color: TColors.slate200, width: 2), borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          Icon(icon, size: 40, color: const Color(0xFFD1D5DB)),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w500, color: Color(0xFF111827))),
          const SizedBox(height: 4),
          Text(body, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
          const SizedBox(height: 14),
          OutlinedButton.icon(onPressed: onTap, icon: const Icon(Icons.add, size: 18), label: Text(button)),
        ]),
      );

  Widget _badge(String text, {required Color bg, required Color fg, Color? border}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: bg, border: Border.all(color: border ?? bg), borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
      );

  Widget _schedulesTab() => TCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _cardHead(Icons.schedule, const Color(0xFFDBEAFE), const Color(0xFF2563EB), 'Menu Schedules',
              'Define when different menus are available (breakfast, lunch, dinner, happy hour)', 'Add Schedule', () => _openSchedule()),
          if (_schedules.isEmpty)
            _empty(Icons.schedule, 'No menu schedules yet', 'Create schedules like Breakfast (6am-11am), Lunch (11am-3pm), Dinner (5pm-10pm)',
                'Create your first schedule', () => _openSchedule())
          else
            for (final s in _schedules) ...[
              Builder(builder: (_) {
                final active = s['isActive'] != false;
                final days = tStr(s['daysOfWeek']);
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _tile(Icons.schedule, active ? const Color(0xFFDCFCE7) : const Color(0xFFF3F4F6), active ? const Color(0xFF16A34A) : const Color(0xFF9CA3AF)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          Text(tStr(s['name']), style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                          active
                              ? _badge('Active', bg: const Color(0xFFDCFCE7), fg: const Color(0xFF15803D))
                              : _badge('Inactive', bg: TColors.slate100, fg: TColors.slate600),
                        ]),
                        const SizedBox(height: 2),
                        Text('${tStr(s['startTime'])} — ${tStr(s['endTime'])}', style: const TextStyle(fontSize: 13, color: TColors.slate500)),
                        if (days.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(spacing: 4, runSpacing: 4, children: [
                            for (final d in restaurantDays)
                              Container(
                                width: 30,
                                height: 20,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                    color: days.contains(d) ? const Color(0xFFFFE4E6) : const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(4)),
                                child: Text(d,
                                    style: TextStyle(
                                        fontSize: 10, fontWeight: FontWeight.w500, color: days.contains(d) ? const Color(0xFFBE123C) : const Color(0xFF9CA3AF))),
                              ),
                          ]),
                        ],
                      ]),
                    ),
                    IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined, size: 16), onPressed: () => _openSchedule(s)),
                    IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline, size: 16, color: Color(0xFFEF4444)), onPressed: () => _deleteSchedule(s)),
                  ]),
                );
              }),
              const SizedBox(height: 10),
            ],
        ]),
      );

  Widget _modifiersTab() => TCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _cardHead(Icons.restaurant, const Color(0xFFF3E8FF), const Color(0xFF9333EA), 'Modifier Groups',
              'Create groups of options customers can choose when ordering (sizes, toppings, sauces)', 'Add Group', () => _openGroup()),
          if (_groups.isEmpty)
            _empty(Icons.restaurant, 'No modifier groups yet',
                'Create groups like "Choose Size" (Small, Medium, Large) or "Extra Toppings" (Cheese, Mushrooms)', 'Create your first group', () => _openGroup())
          else
            for (final g in _groups) ...[_groupCard(g), const SizedBox(height: 14)],
        ]),
      );

  Widget _groupCard(Map g) {
    final id = tIntOrNull(g['modifierGroupId']) ?? 0;
    final mods = [for (final m in _modifiers) if (tIntOrNull(m['modifierGroupId']) == id) m];
    final active = g['isActive'] != false;
    final required = g['isRequired'] == true;
    final min = tNum(g['minSelections']).toInt(), max = tNum(g['maxSelections']).toInt();
    final description = tStr(g['description']);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: const Color(0xCCF9FAFB),
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          child: Row(children: [
            _tile(Icons.restaurant, active ? const Color(0xFFF3E8FF) : const Color(0xFFE5E7EB), active ? const Color(0xFF9333EA) : const Color(0xFF9CA3AF),
                size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(tStr(g['name']), style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                  required
                      ? _badge('Required', bg: const Color(0xFFFFE4E6), fg: const Color(0xFFBE123C))
                      : _badge('Optional', bg: Colors.white, fg: TColors.slate700, border: TColors.slate200),
                  if (!active) _badge('Inactive', bg: TColors.slate100, fg: TColors.slate600),
                ]),
                const SizedBox(height: 2),
                Text('Select ${min == max ? '$max' : '$min–$max'} option${max != 1 ? 's' : ''}${description.isNotEmpty ? ' · $description' : ''}',
                    style: const TextStyle(fontSize: 12, color: TColors.slate500)),
              ]),
            ),
            IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined, size: 16), onPressed: () => _openGroup(g)),
            IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline, size: 16, color: Color(0xFFEF4444)), onPressed: () => _deleteGroup(g)),
          ]),
        ),
        for (final m in mods) ...[
          const Divider(height: 1, color: TColors.slate200),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 4, 2),
            child: Row(children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: m['isAvailable'] != false ? const Color(0xFF22C55E) : const Color(0xFFD1D5DB), shape: BoxShape.circle),
              ),
              const SizedBox(width: 12),
              Flexible(child: Text(tStr(m['name']), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF374151)))),
              if (m['isDefault'] == true) ...[
                const SizedBox(width: 6),
                _badge('Default', bg: const Color(0xFFEFF6FF), fg: const Color(0xFF2563EB), border: const Color(0xFFBFDBFE)),
              ],
              const Spacer(),
              if (tNum(m['priceAdjustment']) > 0)
                Text('+${tNum(m['priceAdjustment']).toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF16A34A))),
              if (tNum(m['priceAdjustment']) < 0)
                Text(tNum(m['priceAdjustment']).toStringAsFixed(2), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFFDC2626))),
              IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined, size: 14), onPressed: () => _openModifier(m: m)),
              IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline, size: 14, color: Color(0xFFEF4444)), onPressed: () => _deleteModifier(m)),
            ]),
          ),
        ],
        const Divider(height: 1, color: TColors.slate200),
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: restaurantRose),
              onPressed: () => _openModifier(groupId: id),
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Add option', style: TextStyle(fontSize: 12)),
            ),
          ),
        ),
      ]),
    );
  }
}

// --------------------------------------------------------------- dialogs

// A Wrap, so the two buttons stack rather than overflow on a narrow phone.
Widget _actions(BuildContext context, String confirm, VoidCallback onSave) => Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
      OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
      FilledButton(style: FilledButton.styleFrom(backgroundColor: restaurantRose), onPressed: onSave, child: Text(confirm)),
    ]);

/// Add Menu Schedule.
class _ScheduleDialog extends StatefulWidget {
  const _ScheduleDialog({required this.api, required this.farmId, this.existing});
  final ApiClient api;
  final String farmId;
  final Map? existing;
  @override
  State<_ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends State<_ScheduleDialog> {
  late final Map? s = widget.existing;
  late String _name = tStr(s?['name']);
  late String _start = s == null ? '06:00' : tStr(s!['startTime']);
  late String _end = s == null ? '11:00' : tStr(s!['endTime']);
  late final Set<String> _days = s == null ? restaurantDays.toSet() : tStr(s!['daysOfWeek']).split(',').where((d) => d.isNotEmpty).toSet();
  // The web sends daysOfWeek only once a day is toggled (or as it was on edit).
  late String? _daysValue = s == null ? null : s!['daysOfWeek'] as String?;

  Future<void> _save() async {
    if (_name.trim().isEmpty) return trackerToast(context, 'Schedule name required', error: true);
    final body = {
      'name': _name,
      'startTime': _start,
      'endTime': _end,
      if (_daysValue != null || s != null) 'daysOfWeek': _daysValue,
      'isActive': s == null ? true : s!['isActive'],
      'farmId': widget.farmId,
    };
    try {
      if (s != null) {
        await widget.api.put('/api/Restaurant/menu/schedules/${s!['menuScheduleId']}', body: body);
      } else {
        await widget.api.post('/api/Restaurant/menu/schedules', body: body);
      }
      if (!mounted) return;
      trackerToast(context, s != null ? 'Schedule updated' : 'Schedule created');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: Text(s != null ? 'Edit Schedule' : 'Add Menu Schedule'),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Define when this menu period is available', style: TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 14),
            _label('Schedule Name', required: true),
            AppSelect<String>(
              value: restaurantScheduleNames.contains(_name) ? _name : null,
              hintText: _name.isNotEmpty ? _name : 'Select a schedule',
              items: [for (final n in restaurantScheduleNames) AppSelectItem(value: n, label: n)],
              onChanged: (v) => setState(() => _name = v ?? _name),
            ),
            const SizedBox(height: 12),
            _label('Start Time'),
            RestaurantTimeField(value: _start, onChanged: (v) => setState(() => _start = v)),
            const SizedBox(height: 12),
            _label('End Time'),
            RestaurantTimeField(value: _end, onChanged: (v) => setState(() => _end = v)),
            const SizedBox(height: 12),
            _label('Available Days'),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final d in restaurantDays)
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() {
                    _days.contains(d) ? _days.remove(d) : _days.add(d);
                    _daysValue = [for (final x in restaurantDays) if (_days.contains(x)) x].join(',');
                  }),
                  child: Container(
                    width: 40,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: _days.contains(d) ? const Color(0xFFF43F5E) : const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(8)),
                    child: Text(d, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _days.contains(d) ? Colors.white : const Color(0xFF6B7280))),
                  ),
                ),
            ]),
            const SizedBox(height: 18),
            _actions(context, s != null ? 'Update' : 'Create Schedule', _save),
          ]),
        ),
      );
}

/// Add Modifier Group.
class _GroupDialog extends StatefulWidget {
  const _GroupDialog({required this.api, required this.farmId, this.existing});
  final ApiClient api;
  final String farmId;
  final Map? existing;
  @override
  State<_GroupDialog> createState() => _GroupDialogState();
}

class _GroupDialogState extends State<_GroupDialog> {
  late final Map? g = widget.existing;
  late String _name = tStr(g?['name']);
  late final _description = TextEditingController(text: tStr(g?['description']));
  late bool _required = g?['isRequired'] == true;
  late final _min = TextEditingController(text: '${tNum(g?['minSelections']).toInt()}');
  late final _max = TextEditingController(text: g == null ? '1' : '${tNum(g!['maxSelections']).toInt()}');

  @override
  void dispose() {
    for (final c in [_description, _min, _max]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.trim().isEmpty) return trackerToast(context, 'Group name required', error: true);
    final max = int.tryParse(_max.text) ?? 0;
    final body = {
      'name': _name,
      if (g != null || _description.text.isNotEmpty) 'description': _description.text,
      'isRequired': _required,
      'minSelections': int.tryParse(_min.text) ?? 0,
      'maxSelections': max == 0 ? 1 : max,
      'isActive': g == null ? true : g!['isActive'],
      'farmId': widget.farmId,
    };
    try {
      if (g != null) {
        await widget.api.put('/api/Restaurant/menu/modifier-groups/${g!['modifierGroupId']}', body: body);
      } else {
        await widget.api.post('/api/Restaurant/menu/modifier-groups', body: body);
      }
      if (!mounted) return;
      trackerToast(context, g != null ? 'Group updated' : 'Group created');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: Text(g != null ? 'Edit Modifier Group' : 'Add Modifier Group'),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('A group of options customers can choose from when ordering', style: TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 14),
            _label('Group Name', required: true),
            AppSelect<String>(
              value: restaurantModifierGroupNames.contains(_name) ? _name : null,
              hintText: _name.isNotEmpty ? _name : 'Select a modifier group',
              items: [for (final n in restaurantModifierGroupNames) AppSelectItem(value: n, label: n)],
              onChanged: (v) => setState(() => _name = v ?? _name),
            ),
            const SizedBox(height: 12),
            _label('Description'),
            AppInput(controller: _description, hintText: 'Brief description (optional)'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFF9FAFB), borderRadius: BorderRadius.circular(8)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const Expanded(child: Text('Customer must select', style: TextStyle(fontSize: 14))),
                  Switch(value: _required, activeThumbColor: Colors.white, activeTrackColor: const Color(0xFFF43F5E), onChanged: (v) => setState(() => _required = v)),
                ]),
                const SizedBox(height: 8),
                const Text('Min selections', style: TextStyle(fontSize: 12, color: TColors.slate500)),
                const SizedBox(height: 4),
                _numInput(_min),
                const SizedBox(height: 8),
                const Text('Max selections', style: TextStyle(fontSize: 12, color: TColors.slate500)),
                const SizedBox(height: 4),
                _numInput(_max),
              ]),
            ),
            const SizedBox(height: 18),
            _actions(context, g != null ? 'Update' : 'Create Group', _save),
          ]),
        ),
      );
}

/// Add Modifier Option.
class _ModifierDialog extends StatefulWidget {
  const _ModifierDialog({required this.api, required this.farmId, this.existing, required this.groups, this.groupId});
  final ApiClient api;
  final String farmId;
  final Map? existing;
  final List<Map> groups;

  /// "Add option" under a group opens on that group.
  final int? groupId;
  @override
  State<_ModifierDialog> createState() => _ModifierDialogState();
}

class _ModifierDialogState extends State<_ModifierDialog> {
  late final Map? m = widget.existing;
  late int _group = tIntOrNull(m?['modifierGroupId']) ??
      widget.groupId ??
      (widget.groups.isEmpty ? 0 : tIntOrNull(widget.groups.first['modifierGroupId']) ?? 0);
  late final _name = TextEditingController(text: tStr(m?['name']));
  late final _price = TextEditingController(text: m == null ? '0' : '${tNum(m!['priceAdjustment'])}');
  late bool _default = m?['isDefault'] == true;
  late bool _available = m == null ? true : m!['isAvailable'] != false;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return trackerToast(context, 'Modifier name required', error: true);
    final body = {
      'modifierGroupId': _group,
      'name': _name.text,
      'priceAdjustment': double.tryParse(_price.text) ?? 0,
      'isDefault': _default,
      'isAvailable': _available,
      'farmId': widget.farmId,
    };
    try {
      if (m != null) {
        await widget.api.put('/api/Restaurant/menu/modifiers/${m!['modifierId']}', body: body);
      } else {
        await widget.api.post('/api/Restaurant/menu/modifiers', body: body);
      }
      if (!mounted) return;
      trackerToast(context, m != null ? 'Modifier updated' : 'Modifier created');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: Text(m != null ? 'Edit Modifier' : 'Add Modifier Option'),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('An individual option within a modifier group', style: TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 14),
            _label('Group'),
            AppSelect<int>(
              value: widget.groups.any((x) => tIntOrNull(x['modifierGroupId']) == _group) ? _group : null,
              items: [for (final x in widget.groups) AppSelectItem(value: tIntOrNull(x['modifierGroupId']) ?? 0, label: tStr(x['name']))],
              onChanged: (v) => setState(() => _group = v ?? _group),
            ),
            const SizedBox(height: 12),
            _label('Option Name', required: true),
            AppInput(controller: _name, hintText: 'e.g. Large, Extra Cheese, Spicy'),
            const SizedBox(height: 12),
            _label('Price Adjustment'),
            _numInput(_price, decimal: true, prefix: const Icon(Icons.attach_money, size: 16), hint: '0.00'),
            const SizedBox(height: 4),
            const Text('Use positive for extra charge, negative for discount, 0 for no change', style: TextStyle(fontSize: 12, color: TColors.slate500)),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: restaurantRose,
              value: _default,
              title: const Text('Pre-selected by default', style: TextStyle(fontSize: 14)),
              onChanged: (v) => setState(() => _default = v ?? false),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: restaurantRose,
              value: _available,
              title: const Text('Available', style: TextStyle(fontSize: 14)),
              onChanged: (v) => setState(() => _available = v ?? true),
            ),
            const SizedBox(height: 12),
            _actions(context, m != null ? 'Update' : 'Add Option', _save),
          ]),
        ),
      );
}
