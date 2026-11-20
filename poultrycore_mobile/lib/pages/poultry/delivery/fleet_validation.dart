// Validation for the delivery setup forms: Vehicles, Drivers and Routes, as
// the web's lib/distribution/fleet-validation.ts.
//
// Tester reports (2026-11-03) found these forms only checked that a name was
// entered: three vehicles shared registration 12345, a motorbike was saved as
// Diesel with room for 1,000 crates, and drivers went in with numeric names,
// bad phone numbers, two-character licences and no vehicle.
//
// Every check returns the sentence to show, or null when the value is fine.

import '../trackers/tracker_logic.dart' show tNum, tStr;

// ---- Vehicle type rules ------------------------------------------------------

const vehicleTypes = ['Truck', 'Van', 'Pickup', 'Tricycle', 'Motorbike', 'Other'];

const _allFuels = ['Petrol', 'Diesel', 'Electric', 'Hybrid', 'LPG / Gas'];

/// Fuels a vehicle of each type can realistically run on.
const fuelsByType = {
  'Truck': ['Diesel', 'Petrol', 'Electric', 'Hybrid'],
  'Van': ['Petrol', 'Diesel', 'Electric', 'Hybrid', 'LPG / Gas'],
  'Pickup': ['Petrol', 'Diesel', 'Electric', 'Hybrid'],
  'Tricycle': ['Petrol', 'Electric'],
  'Motorbike': ['Petrol', 'Electric'],
  'Other': _allFuels,
};

/// Most crates of eggs a vehicle of each type can carry. Generous on purpose:
/// this stops typos (a motorbike with 1,000 crates), not a farm that loads heavily.
const maxCratesByType = {'Motorbike': 40, 'Tricycle': 200, 'Pickup': 400, 'Van': 600, 'Truck': 5000, 'Other': 5000};

List<String> fuelsFor(String? type) => fuelsByType[(type == null || type.isEmpty) ? 'Other' : type] ?? _allFuels;

int maxCratesFor(String? type) => maxCratesByType[(type == null || type.isEmpty) ? 'Other' : type] ?? maxCratesByType['Other']!;

String _article(String word) => RegExp(r'^[aeiou]', caseSensitive: false).hasMatch(word) ? 'an' : 'a';
String _capArticle(String word) {
  final a = _article(word);
  return '${a[0].toUpperCase()}${a.substring(1)}';
}

String _en(num n) {
  final s = n.truncate().abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '${n < 0 ? '-' : ''}$b';
}

// ---- Field checks --------------------------------------------------------------

bool _hasLetter(String s) => RegExp(r'\p{L}', unicode: true).hasMatch(s);

/// "GR 1234-20", "gr1234 20" and "GR-1234-20" are the same plate.
String normalizeRegistration(String? s) => (s ?? '').toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

String? checkRegistration(String? value) {
  final v = (value ?? '').trim();
  if (v.isEmpty) return "Enter the vehicle's registration number.";
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9 \-/]*$').hasMatch(v)) return 'Registration number can only use letters, numbers, spaces, - and /.';
  final compact = normalizeRegistration(v);
  if (compact.length < 4 || compact.length > 15) return 'Registration number should be 4 to 15 letters and numbers, e.g. GR 1234-20.';
  if (!RegExp(r'\d').hasMatch(compact)) return 'Registration number should include numbers, e.g. GR 1234-20.';
  return null;
}

/// A person's name: letters, spaces and . ' - only, at least two letters.
String? checkPersonName(String? value, [String what = 'Driver name']) {
  final v = (value ?? '').trim();
  if (v.isEmpty) return '$what is required.';
  if (RegExp(r'\d').hasMatch(v)) return '$what cannot contain numbers.';
  if (!RegExp(r"^\p{L}[\p{L} .'\-]*$", unicode: true).hasMatch(v)) return '$what can only use letters, spaces, apostrophes and hyphens.';
  if (RegExp(r'\p{L}', unicode: true).allMatches(v).length < 2) return '$what is too short.';
  return null;
}

/// Ghana numbers in either form (0241234567 or +233241234567), or any
/// international number with a leading +. Spaces and dashes are fine.
String? checkPhone(String? value, [bool required = true]) {
  final v = (value ?? '').trim();
  if (v.isEmpty) return required ? "Enter the driver's phone number." : null;
  if (!RegExp(r'^\+?[\d\s\-()]+$').hasMatch(v)) return 'Phone number can only contain digits, spaces, dashes and a leading +.';
  final digits = v.replaceAll(RegExp(r'\D'), '');
  final ok = (RegExp(r'^0\d{9}$').hasMatch(digits) && !v.startsWith('+')) ||
      RegExp(r'^233\d{9}$').hasMatch(digits) ||
      (v.startsWith('+') && digits.length >= 8 && digits.length <= 15 && !digits.startsWith('233'));
  return ok ? null : 'Enter a valid phone number, e.g. 024 123 4567 or +233 24 123 4567.';
}

String normalizePhone(String? s) {
  final d = (s ?? '').replaceAll(RegExp(r'\D'), '');
  if (RegExp(r'^0\d{9}$').hasMatch(d)) return '233${d.substring(1)}';
  return d;
}

/// A driver's licence number: 6 to 20 letters/numbers, must include a number.
String? checkLicense(String? value) {
  final v = (value ?? '').trim();
  if (v.isEmpty) return "Enter the driver's licence number.";
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9 \-/]*$').hasMatch(v)) return 'Licence number can only use letters, numbers, spaces, - and /.';
  final compact = v.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  if (compact.length < 6) return 'Licence number looks incomplete. Enter the full number from the licence card.';
  if (compact.length > 20) return 'Licence number is too long. Check it against the licence card.';
  if (!RegExp(r'\d').hasMatch(compact)) return 'Licence number should include numbers. Check it against the licence card.';
  return null;
}

String? _checkWholeNumber(num? value, String label) {
  if (value == null) return null;
  if (!value.isFinite || value < 0) return '$label cannot be negative.';
  if (value != value.truncate()) return '$label must be a whole number.';
  return null;
}

num? _numOrNull(Object? v) => v == null || '$v'.trim().isEmpty ? null : num.tryParse('$v');
int? _idOf(Object? v) => v == null ? null : int.tryParse('$v');

// ---- Whole-form checks (first problem wins, in the order the form shows fields)

/// [form] / [others] are the API's rows (vehicleName, registrationNumber, ...);
/// [id] is the record being edited, null for a new one.
String? validateVehicle(Map form, List<Map> others, {int? id}) {
  final name = tStr(form['vehicleName']).trim();
  if (name.isEmpty) return 'Vehicle name is required.';
  if (!_hasLetter(name)) return 'Vehicle name should include letters, e.g. Truck 1.';

  final regError = checkRegistration(tStr(form['registrationNumber']));
  if (regError != null) return regError;
  final reg = normalizeRegistration(tStr(form['registrationNumber']));
  final clash = others.where((o) => _idOf(o['poultryVehicleId']) != id && normalizeRegistration(tStr(o['registrationNumber'])) == reg).firstOrNull;
  if (clash != null) return 'Registration number ${tStr(form['registrationNumber']).trim()} is already used by ${tStr(clash['vehicleName'])}.';

  final type = tStr(form['vehicleType']).isEmpty ? 'Other' : tStr(form['vehicleType']);
  final fuel = tStr(form['fuelType']);
  if (fuel.isNotEmpty && !fuelsFor(type).contains(fuel)) {
    return '${_capArticle(type)} ${type.toLowerCase()} cannot run on $fuel. Choose ${fuelsFor(type).join(' or ')}.';
  }

  final cap = _numOrNull(form['capacityCrates']);
  if (cap == null) return 'Enter how many crates this vehicle can carry.';
  final capError = _checkWholeNumber(cap, 'Capacity');
  if (capError != null) return capError;
  if (cap == 0) return 'Capacity must be at least 1 crate.';
  final max = maxCratesFor(type);
  if (cap > max) return '${_capArticle(type)} ${type.toLowerCase()} cannot carry ${_en(cap)} crates. The most allowed is ${_en(max)}.';
  return null;
}

String? validateDriver(Map form, {required List<Map> others, required int vehicleCount, int? id}) {
  final nameError = checkPersonName(tStr(form['driverName']));
  if (nameError != null) return nameError;

  final phoneError = checkPhone(tStr(form['phoneNumber']));
  if (phoneError != null) return phoneError;
  final phone = normalizePhone(tStr(form['phoneNumber']));
  final phoneClash = others
      .where((o) => _idOf(o['poultryDriverId']) != id && tStr(o['phoneNumber']).isNotEmpty && normalizePhone(tStr(o['phoneNumber'])) == phone)
      .firstOrNull;
  if (phoneClash != null) return 'Phone number ${tStr(form['phoneNumber']).trim()} already belongs to driver ${tStr(phoneClash['driverName'])}.';

  final licError = checkLicense(tStr(form['licenseNumber']));
  if (licError != null) return licError;
  final lic = normalizeRegistration(tStr(form['licenseNumber']));
  final licClash = others
      .where((o) => _idOf(o['poultryDriverId']) != id && tStr(o['licenseNumber']).isNotEmpty && normalizeRegistration(tStr(o['licenseNumber'])) == lic)
      .firstOrNull;
  if (licClash != null) return 'Licence number ${tStr(form['licenseNumber']).trim()} already belongs to driver ${tStr(licClash['driverName'])}.';

  if ((_idOf(form['defaultVehicleId']) ?? 0) == 0) {
    return vehicleCount == 0
        ? "Add a vehicle on the Vehicles page first, then choose it as this driver's default vehicle."
        : "Choose the driver's default vehicle.";
  }
  return null;
}

String? validateRoute(Map form, {required List<Map> others, required List<Map> vehicles, int? id}) {
  final name = tStr(form['routeName']).trim();
  if (name.isEmpty) return 'Route name is required.';
  if (!_hasLetter(name)) return 'Route name should include letters, e.g. Kumasi East.';
  final clash = others.where((o) => _idOf(o['poultryRouteId']) != id && tStr(o['routeName']).trim().toLowerCase() == name.toLowerCase()).firstOrNull;
  if (clash != null) return 'There is already a route called ${tStr(clash['routeName'])}.';

  final area = tStr(form['areaCovered']).trim();
  if (area.isEmpty) return 'Enter the area this route covers, e.g. Asafo, Adum, Bantama.';
  if (!_hasLetter(area)) return 'Area covered should name places, not just numbers.';

  final vehicleId = _idOf(form['defaultVehicleId']) ?? 0;
  if (vehicleId == 0) {
    return vehicles.isEmpty
        ? "Add a vehicle on the Vehicles page first, then choose it as this route's default vehicle."
        : 'Choose the vehicle that usually runs this route.';
  }

  final custError = _checkWholeNumber(_numOrNull(form['expectedCustomers']), 'Expected customers');
  if (custError != null) return custError;
  final crates = _numOrNull(form['expectedCratesSold']);
  final crateError = _checkWholeNumber(crates, 'Expected crates/day');
  if (crateError != null) return crateError;

  final v = vehicles.where((x) => _idOf(x['poultryVehicleId']) == vehicleId).firstOrNull;
  final cap = v == null ? 0 : tNum(v['capacityCrates']);
  if (cap > 0 && crates != null && crates > 0 && crates > cap) {
    return '${tStr(v!['vehicleName'])} carries at most ${_en(cap)} crates, but this route expects ${_en(crates)} a day. '
        'Lower the number or choose a bigger vehicle.';
  }
  return null;
}
