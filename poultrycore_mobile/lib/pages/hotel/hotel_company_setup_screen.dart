// Hotel → Setup → Company Setup, as `app/hotel-company-setup/page.tsx`: the
// header with "Set up" once a profile exists and Save Changes, then Basic
// Information, Contact & Location, Operations, and Currency & Charges (with the
// company time zone, which saves on its own).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/sales/balances_widgets.dart' show LoadingLine;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr;
import '../poultry/trackers/tracker_widgets.dart';
import '../restaurant/restaurant_setup_screen.dart' show RestaurantTimeField;
import '../shared/company_timezone_field.dart';
import '../shared/currencies.dart' show currencySymbolFor;
import '../shared/search_picker.dart' show CurrencyPickerField;
import 'hotel_kit.dart';

class HotelCompanySetupScreen extends StatefulWidget {
  const HotelCompanySetupScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<HotelCompanySetupScreen> createState() => _HotelCompanySetupScreenState();
}

class _HotelCompanySetupScreenState extends State<HotelCompanySetupScreen> {
  bool _loading = true, _saving = false, _isSetUp = false;
  Map<String, dynamic> _profile = {'hotelName': ''};
  String _checkIn = '14:00', _checkOut = '12:00', _currency = 'GHS';

  final _name = TextEditingController();
  final _stars = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _country = TextEditingController();
  final _tax = TextEditingController(text: '0');
  final _service = TextEditingController(text: '0');

  ApiClient get _api => widget.session.farmClient;
  Map<String, dynamic> get _q => {'farmId': widget.company.farmId};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _stars, _phone, _email, _address, _city, _country, _tax, _service]) {
      c.dispose();
    }
    super.dispose();
  }

  String _n(Object? v) {
    final x = tNum(v);
    return x == x.roundToDouble() ? '${x.toInt()}' : '$x';
  }

  Future<void> _load() async {
    // A hotel that has never been set up has no profile row yet: the API
    // answers 404, which is expected here rather than an error worth showing.
    try {
      final p = await _api.get('/api/Hotel/setup/profile', query: _q);
      if (p is Map && p.isNotEmpty) {
        _profile = Map<String, dynamic>.from(p);
        _isSetUp = true;
      }
    } catch (_) {}
    _name.text = tStr(_profile['hotelName']);
    _stars.text = _profile['starRating'] == null ? '' : _n(_profile['starRating']);
    _phone.text = tStr(_profile['phone']);
    _email.text = tStr(_profile['email']);
    _address.text = tStr(_profile['address']);
    _city.text = tStr(_profile['city']);
    _country.text = tStr(_profile['country']);
    if (tStr(_profile['checkInTime']).isNotEmpty) _checkIn = tStr(_profile['checkInTime']);
    if (tStr(_profile['checkOutTime']).isNotEmpty) _checkOut = tStr(_profile['checkOutTime']);
    if (tStr(_profile['defaultCurrency']).isNotEmpty) _currency = tStr(_profile['defaultCurrency']);
    _tax.text = _n(_profile['taxRate']);
    _service.text = _n(_profile['serviceChargeRate']);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return trackerToast(context, 'Hotel name is required', error: true);
    setState(() => _saving = true);
    final body = {
      ..._profile,
      'hotelName': _name.text,
      'starRating': _stars.text.trim().isEmpty ? null : int.tryParse(_stars.text.trim()),
      'phone': _phone.text,
      'email': _email.text,
      'address': _address.text,
      'city': _city.text,
      'country': _country.text,
      'checkInTime': _checkIn,
      'checkOutTime': _checkOut,
      'defaultCurrency': _currency,
      'taxRate': double.tryParse(_tax.text) ?? 0,
      'serviceChargeRate': double.tryParse(_service.text) ?? 0,
      'farmId': widget.company.farmId,
    };
    try {
      await _api.post('/api/Hotel/setup/profile', body: body);
      setState(() => _isSetUp = true);
      // Currency is a COMPANY setting: it moves the company's display currency
      // too, but only when the code changed, so a preferred symbol survives.
      try {
        final current = await _api.get('/api/Water/farm-settings', query: _q);
        final picked = _currency.toUpperCase();
        final now = current is Map ? tStr(current['currencyCode']).toUpperCase() : '';
        if (picked.isNotEmpty && picked != now) {
          await _api.put(
            '/api/Water/farm-settings/currency',
            query: _q,
            body: {
              'currencyCode': picked,
              'currencySymbol': currencySymbolFor(picked),
              'showCurrencySymbol': current is Map ? current['showCurrencySymbol'] != false : true,
            },
          );
        }
      } catch (_) {
        if (mounted) {
          trackerToast(
            context,
            'Currency not applied app-wide',
            description: 'The profile saved, but the display currency could not be updated. Set it in Setup > Company.',
            error: true,
          );
        }
      }
      if (mounted) trackerToast(context, 'Profile saved');
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Save failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  Widget _field(String label, Widget input) => FilterLabel(label, input);

  Widget _text(TextEditingController c, {String? hint, TextInputType? keyboard}) =>
      AppInput(controller: c, hintText: hint, keyboardType: keyboard);

  Widget _number(TextEditingController c, {bool decimal = true, String? hint}) => AppInput(
    controller: c,
    hintText: hint,
    keyboardType: TextInputType.numberWithOptions(decimal: decimal),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(decimal ? r'^\d*\.?\d*' : r'^\d*'))],
  );

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/hotel-company-setup');
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Company Setup')),
      body: _loading
          ? const Padding(padding: EdgeInsets.all(20), child: LoadingLine('Loading…'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
              children: [
                HotelPageHeader(
                  icon: Icons.settings_outlined,
                  title: 'Hotel Company Setup',
                  description: "Your hotel's identity, contact details, service hours and charges",
                  badge: _isSetUp
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: TColors.green100, borderRadius: BorderRadius.circular(999)),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_outline, size: 13, color: TColors.green700),
                              SizedBox(width: 4),
                              Text('Set up', style: TextStyle(fontSize: 12, color: TColors.green700)),
                            ],
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  style: hotelPrimary.copyWith(minimumSize: const WidgetStatePropertyAll(Size.fromHeight(46))),
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Save Changes'),
                ),
                const SizedBox(height: 14),
                HotelCard(
                  icon: Icons.apartment_outlined,
                  title: 'Basic Information',
                  description: 'The name guests see on bookings, invoices and emails',
                  children: [
                    _field('Hotel Name *', _text(_name, hint: 'e.g. Golden Palm Hotel')),
                    _field('Star Rating', _number(_stars, decimal: false, hint: '1 – 5')),
                  ],
                ),
                const SizedBox(height: 14),
                HotelCard(
                  icon: Icons.place_outlined,
                  title: 'Contact & Location',
                  description: 'How guests reach you, and where you are',
                  children: [
                    _field('Phone', _text(_phone, keyboard: TextInputType.phone)),
                    _field('Email', _text(_email, keyboard: TextInputType.emailAddress)),
                    _field('Address', _text(_address)),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _field('City', _text(_city))),
                        const SizedBox(width: 10),
                        Expanded(child: _field('Country', _text(_country))),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                HotelCard(
                  icon: Icons.schedule,
                  title: 'Operations',
                  description: 'Standard check-in and check-out times for new bookings',
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _field(
                            'Check-in Time',
                            RestaurantTimeField(value: _checkIn, onChanged: (v) => setState(() => _checkIn = v)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _field(
                            'Check-out Time',
                            RestaurantTimeField(value: _checkOut, onChanged: (v) => setState(() => _checkOut = v)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                HotelCard(
                  icon: Icons.paid_outlined,
                  title: 'Currency & Charges',
                  description: 'The currency rates are quoted in, and the percentages added to a bill',
                  children: [
                    _field('Currency', CurrencyPickerField(code: _currency, onChanged: (o) => setState(() => _currency = o.code))),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _field('Tax Rate (%)', _number(_tax))),
                        const SizedBox(width: 10),
                        Expanded(child: _field('Service Charge (%)', _number(_service))),
                      ],
                    ),
                    // The company time zone lives on the company row and saves itself.
                    CompanyTimeZoneField(session: widget.session, company: widget.company),
                  ],
                ),
              ],
            ),
    );
  }
}
