// Report 35 Part 5, the rest of A5 (9 Nov web pull): Vehicles / Drivers /
// Routes checks and the Home Quick Actions, checked against the web. The rule
// tests are the web's own, ported one for one from
// lib/distribution/fleet-validation.test.ts; the screens run at phone width.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/pages/poultry/delivery/fleet_validation.dart';
import 'package:poultrycore_mobile/pages/poultry/driver_employee_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/flock_form_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/poultry_quick_actions.dart';

import 'poultry_setup_test.dart' as setup;
import 'support/harness.dart';

const truck = {'poultryVehicleId': 1, 'vehicleName': 'Truck 1', 'vehicleType': 'Truck', 'registrationNumber': 'GR 1234-20', 'capacityCrates': 800, 'fuelType': 'Diesel'};

Map<String, Object?> _with(Map m, Map<String, Object?> o) => {...m, ...o};

void main() {
  // ------------------------------------------------- fleet-validation.test.ts
  group('validateVehicle (the web\'s cases)', () {
    test('accepts a sensible vehicle', () {
      expect(validateVehicle(_with(truck, {'registrationNumber': 'AS 555-21'}), [truck]), isNull);
    });
    test('rejects a registration number already in use, however it is spaced', () {
      expect(validateVehicle(_with(truck, {'vehicleName': 'Van', 'registrationNumber': 'gr1234 20'}), [truck]), contains('already used by Truck 1'));
    });
    test('lets a vehicle keep its own registration number on edit', () {
      expect(validateVehicle(truck, [truck], id: 1), isNull);
    });
    test('rejects a diesel motorbike', () {
      expect(
        validateVehicle({'vehicleName': 'Bike', 'vehicleType': 'Motorbike', 'registrationNumber': 'M 22-19', 'capacityCrates': 10, 'fuelType': 'Diesel'}, []),
        contains('A motorbike cannot run on Diesel'),
      );
    });
    test('rejects a motorbike carrying 1,000 crates', () {
      expect(
        validateVehicle({'vehicleName': 'Bike', 'vehicleType': 'Motorbike', 'registrationNumber': 'M 22-19', 'capacityCrates': 1000, 'fuelType': 'Petrol'}, []),
        'A motorbike cannot carry 1,000 crates. The most allowed is 40.',
      );
    });
    test('requires a registration number and capacity', () {
      expect(validateVehicle(_with(truck, {'registrationNumber': ''}), []), contains('registration number'));
      expect(validateVehicle(_with(truck, {'capacityCrates': null}), []), contains('how many crates'));
    });
  });

  group('driver fields (the web\'s cases)', () {
    test('rejects numeric names', () {
      expect(checkPersonName('12345'), contains('cannot contain numbers'));
      expect(checkPersonName('Kofi Mensah'), isNull);
      expect(checkPersonName("Ama O'Neil-Boateng"), isNull);
    });
    test('accepts Ghana numbers in both forms and rejects junk', () {
      expect(checkPhone('024 123 4567'), isNull);
      expect(checkPhone('+233 24 123 4567'), isNull);
      expect(checkPhone('+44 7700 900123'), isNull);
      expect(checkPhone('123'), contains('valid phone'));
      expect(checkPhone('02412345678'), contains('valid phone'));
      expect(checkPhone('abc'), contains('digits'));
    });
    test('rejects an incomplete licence', () {
      expect(checkLicense('12'), contains('incomplete'));
      expect(checkLicense('ABCDEFG'), contains('numbers'));
      expect(checkLicense('GHA-12345678'), isNull);
    });
    test('requires a default vehicle, and says how when there are none', () {
      final d = {'driverName': 'Kofi Mensah', 'phoneNumber': '0241234567', 'licenseNumber': 'GHA-12345678', 'defaultVehicleId': null};
      expect(validateDriver(d, others: [], vehicleCount: 2), "Choose the driver's default vehicle.");
      expect(validateDriver(d, others: [], vehicleCount: 0), contains('Add a vehicle on the Vehicles page first'));
      expect(validateDriver(_with(d, {'defaultVehicleId': 1}), others: [], vehicleCount: 1), isNull);
    });
    test('rejects a phone number another driver already has, in either form', () {
      final other = {'poultryDriverId': 9, 'driverName': 'Yaw', 'phoneNumber': '+233 24 123 4567', 'licenseNumber': 'X1234567'};
      final d = {'driverName': 'Kofi Mensah', 'phoneNumber': '0241234567', 'licenseNumber': 'GHA-12345678', 'defaultVehicleId': 1};
      expect(validateDriver(d, others: [other], vehicleCount: 1), contains('already belongs to driver Yaw'));
    });
  });

  group('validateRoute (the web\'s cases)', () {
    const vehicles = [{'poultryVehicleId': 1, 'vehicleName': 'Bike', 'capacityCrates': 30}];
    const r = {'routeName': 'Kumasi East', 'areaCovered': 'Asafo, Adum', 'defaultVehicleId': 1, 'expectedCustomers': 12, 'expectedCratesSold': 20};
    test('accepts a sensible route', () {
      expect(validateRoute(r, others: [], vehicles: vehicles), isNull);
    });
    test('rejects numeric names, a missing area and duplicate names', () {
      expect(validateRoute(_with(r, {'routeName': '123'}), others: [], vehicles: vehicles), contains('include letters'));
      expect(validateRoute(_with(r, {'areaCovered': ''}), others: [], vehicles: vehicles), contains('area this route covers'));
      expect(validateRoute(r, others: [{'poultryRouteId': 5, 'routeName': 'kumasi east'}], vehicles: vehicles), contains('already a route'));
    });
    test('rejects more crates a day than the vehicle can carry', () {
      expect(validateRoute(_with(r, {'expectedCratesSold': 100}), others: [], vehicles: vehicles), contains('carries at most 30 crates'));
    });
  });

  // -------------------------------------------------------------- the forms
  testWidgets('Vehicles: fuel follows the type; a used registration is refused before sending', (tester) async {
    final api = FakeApi()..gets['/api/Poultry/vehicles'] = [truck];
    await open(tester, setup.formFor(await sessionFor(api), 'poultry-vehicles'), size: phone);
    await setup.see(tester, find.text('Choose fuel'));
    await tester.tap(find.text('Choose fuel'));
    await tester.pumpAndSettle();
    expect(find.text('LPG / Gas'), findsNothing, reason: 'a truck cannot run on gas');
    await tester.tap(find.text('Diesel').last);
    await tester.pumpAndSettle();
    await pick(tester, 'Truck', 'Motorbike');
    expect(find.text('Diesel'), findsNothing, reason: 'a fuel the new type cannot use is cleared');

    await enter(tester, 'Vehicle name', 'Bike 2');
    await enter(tester, 'Registration #', 'gr1234 20');
    await enter(tester, 'Capacity (crates)', '10');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Check the vehicle details — Registration number gr1234 20 is already used by Truck 1.'), findsOneWidget);
    expect(api.writes, isEmpty);
  });

  testWidgets('Drivers: a bad licence is caught before any employee is created', (tester) async {
    final api = FakeApi();
    await open(tester, DriverEmployeeScreen(session: await sessionFor(api), company: company, mode: DriverEmployeeMode.created), size: phone);
    await enter(tester, 'First name', 'Kojo');
    await enter(tester, 'Last name', 'Asante');
    await enter(tester, 'Phone', '024 123 4567');
    await enter(tester, 'License number', '12');
    await enter(tester, 'Username', 'kojo_a');
    await enter(tester, 'Password', 'secret1');
    await setup.see(tester, find.text('Create & make driver'));
    await tester.tap(find.text('Create & make driver'));
    await tester.pumpAndSettle();
    expect(find.text('Check the licence number — Licence number looks incomplete. Enter the full number from the licence card.'), findsOneWidget);
    expect(api.writes, isEmpty);

    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();
    await tester.pumpAndSettle();
    await enter(tester, 'License number', 'GHA-12345678');
    await enter(tester, 'First name', 'K0jo');
    await setup.see(tester, find.text('Create & make driver'));
    await tester.tap(find.text('Create & make driver'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Check the name — First name cannot contain numbers.'), findsOneWidget);
    expect(api.writes, isEmpty);
  });

  // --------------------------------------------------------- Quick Actions
  testWidgets('Home Quick Actions: the web\'s eight buttons, in its order', (tester) async {
    final api = FakeApi()
      ..gets['/api/MainFlockBatch'] = []
      ..gets['/api/House'] = []
      ..gets['/api/Flock'] = [];
    await open(tester, Scaffold(body: ListView(children: [PoultryQuickActions(session: await sessionFor(api), company: company)])), size: phone);
    expect(find.text('Quick Actions'), findsOneWidget);
    final labels = [for (final a in poultryQuickActions) a.$1];
    expect(labels, ['Log Production', 'Record Sale', 'Update Expenses', 'Add Flock', 'Flock Purchases', 'Record Purchase', 'Houses', 'Support Videos']);
    for (final l in labels) {
      expect(find.text(l), findsOneWidget, reason: l);
    }
    await tester.ensureVisible(find.byKey(const ValueKey('quick-/flocks/new')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quick-/flocks/new')));
    await tester.pumpAndSettle();
    expect(find.byType(FlockFormScreen), findsOneWidget, reason: 'Add Flock opens the flock form');
  });
}
