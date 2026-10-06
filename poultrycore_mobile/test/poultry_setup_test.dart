// Poultry → Setup → Production and Delivery, driven against a fake API.
//
// Each test opens the real screen, taps the real dropdowns and reads back
// what would be sent, so a dropdown that cannot be opened, lists the wrong
// thing, or loses its value fails here instead of on a phone.


import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/pages/form_screen.dart';
import 'package:poultrycore_mobile/pages/list_screen.dart';
import 'package:poultrycore_mobile/pages/lookup_loader.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/driver_employee_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/egg_pick_settings_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/feed_formula_form_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/product_screens.dart';
import 'package:poultrycore_mobile/pages/registry.dart';
import 'package:poultrycore_mobile/state/session.dart';

import 'support/harness.dart';

FormScreen formFor(Session s, String key, {Map<String, dynamic>? existing, String title = 'Form'}) =>
    FormScreen(
      def: formForSpec(key)!,
      title: title,
      company: company,
      session: s,
      spec: PageRegistry.of(key),
      existing: existing,
    );

const truck = {
  'poultryVehicleId': 3, 'vehicleName': 'Truck 1', 'vehicleType': 'Truck', 'status': 'Active',
};
const van = {
  'poultryVehicleId': 4, 'vehicleName': 'Van A', 'vehicleType': 'Van', 'status': 'UnderMaintenance',
};

void main() {
  setUp(LookupLoader.clear);

  group('Routes', () {
    testWidgets('Default vehicle lists vehicles as the web words them, and saves the id as a number',
        (tester) async {
      final api = FakeApi()..gets['/api/Poultry/vehicles'] = [truck, van];
      await open(tester, formFor(await sessionFor(api), 'poultry-routes'));

      await enter(tester, 'Route name', 'Kumasi East');
      await pick(tester, '(none)', 'Truck 1 (Truck)');
      expect(find.text('Truck 1 (Truck)'), findsOneWidget, reason: 'the choice stays shown');

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final body = api.lastBody('/api/Poultry/routes');
      expect(body['routeName'], 'Kumasi East');
      expect(body['defaultVehicleId'], 3);
      expect(body['farmId'], 'farm-1');
    });

    testWidgets('a vehicle that is not Active says so, as on the web', (tester) async {
      final api = FakeApi()..gets['/api/Poultry/vehicles'] = [truck, van];
      await open(tester, formFor(await sessionFor(api), 'poultry-routes'));
      await tester.tap(find.text('(none)').first);
      await tester.pumpAndSettle();
      expect(find.text('Van A (Van) — UnderMaintenance'), findsWidgets);
    });

    testWidgets('no vehicles: the field says what to do, not "type it on the web"', (tester) async {
      final api = FakeApi();
      await open(tester, formFor(await sessionFor(api), 'poultry-routes'));
      expect(find.text('No vehicles. Add one on the Vehicles page first.'), findsOneWidget);
      expect(find.text('Type it on the web'), findsNothing);
    });

    testWidgets('a vehicle created after the list was first loaded is pickable', (tester) async {
      // The reported bug: the empty list was cached for the whole session.
      final api = FakeApi();
      final s = await sessionFor(api);
      await open(tester, formFor(s, 'poultry-routes'));
      expect(find.text('No vehicles. Add one on the Vehicles page first.'), findsOneWidget);

      api.gets['/api/Poultry/vehicles'] = [truck];
      await s.farmClient.post('/api/Poultry/vehicles', body: {'vehicleName': 'Truck 1'});

      await open(tester, formFor(s, 'poultry-routes'));
      await pick(tester, '(none)', 'Truck 1 (Truck)');
      expect(find.text('Truck 1 (Truck)'), findsOneWidget);
    });

    testWidgets('editing shows the saved vehicle once the list arrives', (tester) async {
      final api = FakeApi()..gets['/api/Poultry/vehicles'] = [truck, van];
      await open(tester, formFor(await sessionFor(api), 'poultry-routes', existing: {
        'poultryRouteId': 9, 'routeName': 'East', 'defaultVehicleId': 4,
      }));
      expect(find.text('Van A (Van) — UnderMaintenance'), findsOneWidget);
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      final body = api.lastBody('/api/Poultry/routes/9', 'PUT');
      expect(body['poultryRouteId'], 9);
      expect(body['defaultVehicleId'], 4);
    });
  });

  group('Lists', () {
    testWidgets('Routes list shows the default vehicle by name, as the web table does',
        (tester) async {
      final api = FakeApi()
        ..gets['/api/Poultry/vehicles'] = [truck]
        ..gets['/api/Poultry/routes'] = [
          {'poultryRouteId': 9, 'routeName': 'Kumasi East', 'areaCovered': 'Suame', 'defaultVehicleId': 3},
        ];
      final s = await sessionFor(api);
      await open(tester, ListScreen(spec: PageRegistry.of('poultry-routes')!, session: s, company: company));
      expect(find.text('Kumasi East'), findsWidgets);
      // The card renders "Default vehicle  Truck 1" as one rich text.
      expect(find.textContaining('Default vehicle  Truck 1', findRichText: true), findsOneWidget);
    });
  });

  group('Vehicles', () {
    testWidgets('Type and Status start at the web defaults and offer the web lists', (tester) async {
      final api = FakeApi();
      await open(tester, formFor(await sessionFor(api), 'poultry-vehicles'));
      expect(find.text('Truck'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      await tester.tap(find.text('Active'));
      await tester.pumpAndSettle();
      expect(find.text('UnderMaintenance'), findsWidgets);
      expect(find.text('Present'), findsNothing, reason: 'attendance values are gone');
      await tester.tap(find.text('UnderMaintenance').last);
      await tester.pumpAndSettle();
      await pick(tester, 'Truck', 'Motorbike');

      await enter(tester, 'Vehicle name', 'Bike 2');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final body = api.lastBody('/api/Poultry/vehicles');
      expect(body['vehicleType'], 'Motorbike');
      expect(body['status'], 'UnderMaintenance');
      expect(body['poultryVehicleId'], 0);
    });
  });

  group('Drivers', () {
    testWidgets('edit: vehicle and route show the saved choices and can be changed', (tester) async {
      final api = FakeApi()
        ..gets['/api/Poultry/vehicles'] = [truck, van]
        ..gets['/api/Poultry/routes'] = [
          {'poultryRouteId': 7, 'routeName': 'Kumasi East'},
          {'poultryRouteId': 8, 'routeName': 'Accra North'},
        ];
      final s = await sessionFor(api);
      await open(tester, customForms['poultry-drivers']!(s, company, {
        'poultryDriverId': 5, 'driverName': 'Kofi', 'defaultVehicleId': 3, 'defaultRouteId': 7,
        'isActive': true,
      }));
      expect(find.text('Truck 1 (Truck)'), findsOneWidget);
      expect(find.text('Kumasi East'), findsOneWidget);

      await pick(tester, 'Kumasi East', 'Accra North');
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      final body = api.lastBody('/api/Poultry/drivers/5', 'PUT');
      expect(body['defaultRouteId'], 8);
      expect(body['defaultVehicleId'], 3);
      expect(body['poultryDriverId'], 5);
    });

    testWidgets('existing employee: the picker leaves out people who are already drivers',
        (tester) async {
      final api = FakeApi()
        ..gets['/api/Admin/employees'] = [
          {'id': 'u1', 'firstName': 'Ama', 'lastName': 'Mensah', 'phoneNumber': '0241'},
          {'id': 'u2', 'firstName': 'Yaw', 'lastName': 'Boateng', 'phoneNumber': '0242'},
        ];
      final s = await sessionFor(api);
      await open(tester, DriverEmployeeScreen(
        session: s, company: company, mode: DriverEmployeeMode.existing,
        drivers: const [{'employeeUserId': 'u1'}],
      ));
      await tester.tap(find.text('Select an employee'));
      await tester.pumpAndSettle();
      expect(find.text('Ama Mensah — 0241'), findsNothing);
      await tester.tap(find.text('Yaw Boateng — 0242').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Assign as driver'));
      await tester.pumpAndSettle();
      final body = api.lastBody('/api/Poultry/drivers/from-employee');
      expect(body['employeeUserId'], 'u2');
      expect(body['phoneNumber'], '0242');
    });

    testWidgets('new employee & driver creates the employee, then the driver', (tester) async {
      final api = FakeApi();
      final s = await sessionFor(api);
      await open(tester, DriverEmployeeScreen(session: s, company: company, mode: DriverEmployeeMode.created));
      await enter(tester, 'First name', 'Kojo');
      await enter(tester, 'Last name', 'Asante');
      await enter(tester, 'Username', 'kojo_a');
      await enter(tester, 'Password', 'secret1');
      await tester.tap(find.text('Create & make driver'));
      await tester.pumpAndSettle();
      final emp = api.lastBody('/api/Admin/employees');
      expect(emp['UserName'], 'kojo_a');
      expect(emp['Email'], 'kojo_a@noemail.local');
      expect(api.lastBody('/api/Poultry/drivers/from-employee')['employeeUserId'], 'new-user-1');
    });
  });

  group('Products', () {
    testWidgets('raw egg = Yes turns "Requires recipe setup?" to No, visibly', (tester) async {
      final api = FakeApi();
      await open(tester, ProductFormScreen(session: await sessionFor(api), company: company));
      expect(find.text('Yes'), findsOneWidget, reason: 'recipe setup starts on');
      await pick(tester, 'No', 'Yes');
      // Both selects now read Yes / No: raw egg Yes, recipe No.
      expect(find.text('Yes'), findsOneWidget);
      expect(find.text('No'), findsOneWidget);

      await pick(tester, 'Pick unit', 'Crate');
      await enter(tester, 'Name', 'Eggs (crate)');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final body = api.lastBody('/api/Poultry/products');
      expect(body['isRawEggProduct'], true);
      expect(body['requiresRecipeSetup'], false);
      expect(body['unit'], 'Crate');
    });

    testWidgets('recipe: raw materials are pickable and saved per output unit', (tester) async {
      final api = FakeApi()
        ..gets['/api/Poultry/raw-material-items'] = [
          {'poultryRawMaterialItemId': 11, 'itemName': 'Egg tray', 'isActive': true},
          {'poultryRawMaterialItemId': 12, 'itemName': 'Old label', 'isActive': false},
        ]
        ..gets['/api/Poultry/products/2/recipe'] = {'recipeName': '', 'items': []};
      await open(tester, ProductRecipeScreen(
        session: await sessionFor(api), company: company,
        product: const {'poultryProductId': 2, 'name': 'Eggs'},
      ));
      await tester.tap(find.text('Add material'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Raw material'));
      await tester.pumpAndSettle();
      expect(find.text('Old label'), findsNothing, reason: 'inactive items are hidden, as on the web');
      await tester.tap(find.text('Egg tray').last);
      await tester.pumpAndSettle();
      await enter(tester, 'Qty per unit', '1');
      await tester.tap(find.text('Save recipe'));
      await tester.pumpAndSettle();
      final body = api.lastBody('/api/Poultry/products/2/recipe', 'PUT');
      expect((body['items'] as List).single['poultryRawMaterialItemId'], 11);
    });
  });

  group('Feed Formulas', () {
    testWidgets('finished feeds and ingredients come from the right categories', (tester) async {
      final api = FakeApi()
        ..gets['/api/Poultry/raw-material-items'] = [
          {'poultryRawMaterialItemId': 1, 'itemName': 'Layer Mash', 'category': 'Finished Feed', 'isActive': true},
          {'poultryRawMaterialItemId': 2, 'itemName': 'Maize', 'category': 'Feed Ingredient', 'unitOfMeasure': 'Kilogram', 'isActive': true},
          {'poultryRawMaterialItemId': 3, 'itemName': 'Vaccine', 'category': 'Medication', 'isActive': true},
        ];
      await open(tester, FeedFormulaFormScreen(session: await sessionFor(api), company: company));

      await pick(tester, 'Any finished feed (reusable)', 'Layer Mash');
      await tester.tap(find.text('Pick ingredient'));
      await tester.pumpAndSettle();
      expect(find.text('Vaccine'), findsNothing);
      expect(find.text('Layer Mash'), findsOneWidget, reason: 'a finished feed is not an ingredient');
      await tester.tap(find.text('Maize').last);
      await tester.pumpAndSettle();
      await enter(tester, 'Percent', '60');
      expect(find.textContaining('Percentage total: 60% (should be 100%)'), findsOneWidget);
      await enter(tester, 'Formula name', 'Layer Mash Formula');
      await tester.tap(find.text('Save Formula'));
      await tester.pumpAndSettle();
      final body = api.lastBody('/api/Poultry/feed-formulas');
      expect(body['finishedFeedItemId'], 1);
      final line = (body['lines'] as List).single as Map;
      expect(line['ingredientItemId'], 2);
      expect(line['percentage'], 60);
      expect(line['unitOfMeasure'], 'Kilogram');
    });
  });

  group('Egg Pick Times', () {
    testWidgets('loads the saved times and saves the switches', (tester) async {
      final api = FakeApi()
        ..gets['/api/FarmProductionSettings'] = {
          'firstPickTime': '08:30:00', 'secondPickTime': '12:00:00', 'thirdPickTime': '16:00:00',
          'fourthPickTime': '18:00:00', 'fifthPickTime': null, 'sixthPickTime': null,
          'enableFourthPick': false,
        };
      await open(tester, EggPickSettingsScreen(session: await sessionFor(api), company: company));
      expect(find.text('8:30 AM'), findsOneWidget);
      expect(find.text('Not set — falls back to the default.'), findsNWidgets(2));
      await tester.tap(find.byType(Switch).first);
      await tester.pump();
      await tester.tap(find.text('Save settings'));
      await tester.pumpAndSettle();
      final body = api.lastBody('/api/FarmProductionSettings', 'PUT');
      expect(body['FirstPickTime'], '08:30');
      expect(body['FifthPickTime'], null);
      expect(body['EnableFourthPick'], true);
    });
  });
}
