import 'package:flutter/material.dart';

import '../../design/ui/form_section.dart';
import '../../design/ui/inputs.dart';

/// POULTRY_BUSINESS_TYPES, POULTRY_HOUSING_SYSTEMS and their labels.
const poultryBusinessTypes = ['Layers', 'Broilers', 'Both'];
const poultryHousing = {
  'DeepLitter': 'Deep litter',
  'BatteryCage': 'Battery cage',
  'FreeRange': 'Free range',
  'Mixed': 'Mixed',
};

/// The poultry company profile's business details, shared by Company Setup
/// and the Farm Setup hub's Company tab — the web shows the same fields on
/// both, so there is one copy here.
class PoultryProfileForm {
  final brand = TextEditingController();
  final site = TextEditingController();
  final town = TextEditingController();
  final owner = TextEditingController();
  final phone = TextEditingController();
  final email = TextEditingController();
  final crate = TextEditingController(text: '30');
  final capacity = TextEditingController();
  final hours = TextEditingController();
  final notes = TextEditingController();
  String businessType = 'Layers';
  String housingSystem = 'DeepLitter';
  String currency = 'GHC';

  /// The saved profile; null until the company is set up (the API 404s).
  Map? profile;

  bool get isSetUp => profile != null;

  void dispose() {
    for (final c in [brand, site, town, owner, phone, email, crate, capacity, hours, notes]) {
      c.dispose();
    }
  }

  /// A stored value matched case-insensitively, as the web's selects do, so
  /// an older lowercase row still shows and saves correctly.
  static String match(Object? v, Iterable<String> options, String fallback) =>
      options.where((o) => o.toLowerCase() == '${v ?? ''}'.toLowerCase()).firstOrNull ?? fallback;

  void fill(Map p) {
    profile = p;
    String s(String k) => p[k] == null ? '' : '${p[k]}';
    brand.text = s('brandName');
    businessType = match(p['businessType'], poultryBusinessTypes, 'Layers');
    housingSystem = match(p['housingSystem'], poultryHousing.keys, 'DeepLitter');
    site.text = s('farmSiteAddress');
    town.text = s('mainLocation');
    owner.text = s('ownerName');
    phone.text = s('phoneNumber');
    email.text = s('email');
    currency = s('defaultCurrency').isEmpty ? 'GHC' : s('defaultCurrency');
    crate.text = s('defaultCrateEggCount').isEmpty ? '30' : s('defaultCrateEggCount');
    capacity.text = s('totalCapacity');
    hours.text = s('operatingHours');
    notes.text = s('notes');
  }

  /// What is sent, normalised as the web normalises it.
  Map<String, dynamic> payload() {
    final c = int.tryParse(crate.text.trim()) ?? 30;
    return {
      'brandName': brand.text.trim(),
      'businessType': businessType,
      'farmSiteAddress': site.text.trim(),
      'mainLocation': town.text.trim(),
      'housingSystem': housingSystem,
      'defaultCurrency': currency.trim().isEmpty ? 'GHC' : currency.trim(),
      'defaultCrateEggCount': c < 1 ? 30 : c,
      // An empty capacity box means "not stated", not zero.
      'totalCapacity': int.tryParse(capacity.text.trim()),
      'operatingHours': hours.text.trim(),
      'ownerName': owner.text.trim(),
      'phoneNumber': phone.text.trim(),
      'email': email.text.trim(),
      'notes': notes.text.trim(),
    };
  }

  /// The business-detail fields in the web's order. [between] goes after
  /// Email — Company Setup puts the currency and timezone there.
  List<Widget> fields(void Function(VoidCallback) setState, {List<Widget> between = const []}) => [
        AppField(label: 'Farm / brand name', full: true,
            child: AppInput(controller: brand, hintText: 'e.g. Gyimah Farm')),
        AppField(
          label: 'Business type',
          required: true,
          child: AppSelect<String>(
            value: businessType,
            hintText: 'Pick business type',
            items: [for (final t in poultryBusinessTypes) AppSelectItem(value: t, label: t)],
            onChanged: (v) => setState(() => businessType = v ?? businessType),
          ),
        ),
        AppField(
          label: 'Housing system',
          required: true,
          child: AppSelect<String>(
            value: housingSystem,
            hintText: 'Pick housing system',
            items: [for (final e in poultryHousing.entries) AppSelectItem(value: e.key, label: e.value)],
            onChanged: (v) => setState(() => housingSystem = v ?? housingSystem),
          ),
        ),
        AppField(label: 'Farm site address', full: true, child: AppInput(controller: site)),
        AppField(label: 'Main location / town', child: AppInput(controller: town)),
        AppField(label: 'Owner name', child: AppInput(controller: owner)),
        AppField(label: 'Phone',
            child: AppInput(controller: phone, hintText: '+233...', keyboardType: TextInputType.phone)),
        AppField(label: 'Email', child: AppInput(controller: email, keyboardType: TextInputType.emailAddress)),
        ...between,
        AppField(
          label: 'Eggs per crate',
          hint: 'Used to convert crates to eggs when a vehicle is loaded and a driver return is reconciled.',
          child: AppNumberInput(controller: crate),
        ),
        AppField(label: 'Total capacity (birds)', child: AppNumberInput(controller: capacity, hintText: '')),
        AppField(label: 'Operating hours', child: AppInput(controller: hours, hintText: 'e.g. 6:00 AM – 6:00 PM')),
        AppField(label: 'Notes', full: true, child: AppTextarea(controller: notes)),
      ];
}
