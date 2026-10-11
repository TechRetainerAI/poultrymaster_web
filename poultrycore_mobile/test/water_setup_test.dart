// Water → Setup, driven against a fake API at phone width.
//
// Each test opens the real screen, taps the real dropdowns and reads back
// what would be sent, so a dropdown that cannot be opened, lists the wrong
// thing, or loses its value fails here instead of on a phone.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/form_screen.dart';
import 'package:poultrycore_mobile/pages/list_screen.dart';
import 'package:poultrycore_mobile/pages/lookup_loader.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/reports/report_format.dart' show FarmMoney;
import 'package:poultrycore_mobile/pages/registry.dart';
import 'package:poultrycore_mobile/pages/water/water_company_setup_screen.dart';
import 'package:poultrycore_mobile/pages/water/water_driver_employee_screen.dart';
import 'package:poultrycore_mobile/pages/water/water_financial_settings_screen.dart';
import 'package:poultrycore_mobile/pages/water/water_product_screens.dart';
import 'package:poultrycore_mobile/pages/water/water_setup_forms.dart';
import 'package:poultrycore_mobile/pages/water/water_setup_screen.dart';
import 'package:poultrycore_mobile/state/session.dart';

import 'support/harness.dart';

final water = Company(farmId: 'farm-1', name: 'Win Water', type: CompanyType.water);

FormScreen formFor(Session s, String key, {Map<String, dynamic>? existing}) => FormScreen(
      def: formForSpec(key)!,
      title: 'Form',
      company: water,
      session: s,
      spec: PageRegistry.of(key),
      existing: existing,
    );

const truck = {'waterVehicleId': 3, 'vehicleName': 'Truck 1', 'vehicleType': 'Truck', 'status': 'Active'};
const king = {'waterVehicleId': 4, 'vehicleName': 'King A', 'vehicleType': 'MotorKing', 'status': 'Inactive'};

/// Scrolls the visible list until [finder] is built.
Future<void> see(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    LookupLoader.clear();
    FarmMoney.clearCache();
  });

  group('Delivery', () {
    testWidgets('Vehicles: the web types and statuses, no attendance values', (tester) async {
      final api = FakeApi();
      await open(tester, formFor(await sessionFor(api), 'water-vehicles'), size: phone);
      await pick(tester, 'Truck', 'MotorKing');
      await tester.tap(find.text('Active'));
      await tester.pumpAndSettle();
      expect(find.text('Present'), findsNothing);
      await tester.tap(find.text('UnderMaintenance').last);
      await tester.pumpAndSettle();
      await enter(tester, 'Vehicle name', 'King 2');
      await enter(tester, 'Capacity (bags)', '40');
      await see(tester, find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final body = api.lastBody('/api/Water/vehicles');
      expect(body['vehicleType'], 'MotorKing');
      expect(body['status'], 'UnderMaintenance');
      expect(body['capacityBags'], 40);
      expect(body['waterVehicleId'], 0);
    });

    testWidgets('Routes: Default vehicle as the web words it; edit keeps the default driver', (tester) async {
      final api = FakeApi()..gets['/api/Water/vehicles'] = [truck, king];
      await open(
          tester,
          formFor(await sessionFor(api), 'water-routes', existing: {
            'waterRouteId': 9, 'routeName': 'East', 'defaultVehicleId': 3, 'defaultDriverStaffId': 12,
          }),
          size: phone);
      expect(find.text('Truck 1 (Truck)'), findsOneWidget);
      await pick(tester, 'Truck 1 (Truck)', 'King A (MotorKing) — Inactive');
      await enter(tester, 'Expected bags/day', '300');
      await see(tester, find.text('Update'));
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      final body = api.lastBody('/api/Water/routes/9', 'PUT');
      expect(body['defaultVehicleId'], 4);
      expect(body['expectedBagsSold'], 300);
      expect(body['defaultDriverStaffId'], 12, reason: 'the web sends it back on update');
      expect(body['waterRouteId'], 9);
    });

    testWidgets('Drivers edit: Assigned vehicle saves as assignedWaterVehicleId', (tester) async {
      final api = FakeApi()..gets['/api/Water/vehicles'] = [truck, king];
      final s = await sessionFor(api);
      await open(
          tester,
          customForms['water-drivers']!(s, water, {
            'waterDriverId': 5, 'driverName': 'Kofi', 'assignedWaterVehicleId': null, 'isActive': true,
          }),
          size: phone);
      await pick(tester, '(none)', 'Truck 1 (Truck)');
      await see(tester, find.text('Update'));
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      final body = api.lastBody('/api/Water/drivers/5', 'PUT');
      expect(body['assignedWaterVehicleId'], 3);
      expect(body['waterDriverId'], 5);
    });

    testWidgets('Existing employee: role, default vehicle and route reach from-employee', (tester) async {
      final api = FakeApi()
        ..gets['/api/Admin/employees'] = [
          {'id': 'u1', 'firstName': 'Ama', 'lastName': 'Mensah', 'phoneNumber': '0241'},
          {'id': 'u2', 'firstName': 'Yaw', 'lastName': 'Boateng', 'phoneNumber': '0242'},
        ]
        ..gets['/api/Water/vehicles'] = [truck]
        ..gets['/api/Water/routes'] = [
          {'waterRouteId': 7, 'routeName': 'Kumasi East'},
        ];
      final s = await sessionFor(api);
      await open(
          tester,
          WaterDriverEmployeeScreen(
            session: s, company: water, mode: WaterDriverMode.existing,
            drivers: const [{'employeeUserId': 'u1'}],
          ),
          size: phone);
      await tester.tap(find.text('Select an employee'));
      await tester.pumpAndSettle();
      expect(find.text('Ama Mensah — 0241'), findsNothing);
      await tester.tap(find.text('Yaw Boateng — 0242').last);
      await tester.pumpAndSettle();
      await pick(tester, 'Driver', 'Motor King Rider');
      await see(tester, find.text('Assign as driver'));
      await tester.tap(find.text('(none)').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Truck 1').last);
      await tester.pumpAndSettle();
      await pick(tester, '(none)', 'Kumasi East');
      await tester.tap(find.text('Assign as driver'));
      await tester.pumpAndSettle();
      final body = api.lastBody('/api/Water/drivers/from-employee');
      expect(body['employeeUserId'], 'u2');
      expect(body['role'], 'MotorKingRider');
      expect(body['defaultVehicleId'], 3);
      expect(body['defaultRouteId'], 7);
      expect(body['basePay'], isNull);
      expect(body['commissionPerBag'], isNull);
    });
  });

  group('Products', () {
    testWidgets('labels follow the packaging unit; the body is derived as the web does', (tester) async {
      final api = FakeApi()..writeAnswers['/api/Water/products'] = {'waterProductId': 21, 'name': 'Pure 500'};
      await open(tester, WaterProductFormScreen(session: await sessionFor(api), company: water), size: phone);
      await enter(tester, 'Name', 'Pure 500');
      await see(tester, find.text('Units per Bag'));
      await pick(tester, 'Bag', 'Crate');
      expect(find.text('Units per Crate'), findsOneWidget);
      expect(find.text('Selling price per Crate'), findsOneWidget);
      // Default sales unit offers the inventory and packaging units only.
      await tester.tap(find.text('Select…').first);
      await tester.pumpAndSettle();
      expect(find.text('Sachet'), findsWidgets);
      await tester.tap(find.text('Sachet').last);
      await tester.pumpAndSettle();
      await enter(tester, 'Selling price per Sachet', '0.5');
      await see(tester, find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final body = api.lastBody('/api/Water/products');
      expect(body['packagingUnit'], 'Crate');
      expect(body['defaultSalesUnit'], 'Sachet');
      expect(body['unitPrice'], 0.5, reason: 'sells by unit, so the unit price is the sachet price');
      expect(body['isSachetProduct'], isTrue, reason: '30 per package');
      expect(body['baseUnit'], 'Sachet');
      expect(body.containsKey('sizeMl'), isFalse, reason: 'undefined in the web form');
      // Finished good → the recipe nudge.
      expect(find.text('Product created successfully'), findsOneWidget);
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.text('host'), findsOneWidget);
    });

    testWidgets('Restock posts a Restock transaction', (tester) async {
      final api = FakeApi();
      await open(
          tester,
          WaterProductStockScreen(
              session: await sessionFor(api), company: water, product: const {'waterProductId': 21, 'name': 'Pure'}),
          size: phone);
      await enter(tester, 'Quantity', '12');
      await tester.tap(find.text('Add stock'));
      await tester.pumpAndSettle();
      final body = api.lastBody('/api/Water/stock/transactions');
      expect(body['txnType'], 'Restock');
      expect(body['quantity'], 12);
      expect(body['note'], 'Restocked 12');
      expect(body['unitCost'], isNull);
    });

    testWidgets('Product Details: recipe rows pick active materials and save per output unit', (tester) async {
      final api = FakeApi()
        ..gets['/api/Water/products/21'] = {
          'waterProductId': 21, 'name': 'Pure 500', 'productType': 'FinishedGood', 'unitPrice': 5,
          'stockOnHand': 1200, 'isActive': true,
        }
        ..gets['/api/Water/raw-material-items'] = [
          {'waterRawMaterialItemId': 1, 'itemName': 'Film', 'unitOfMeasure': 'roll', 'isActive': true, 'currentQuantity': 3},
          {'waterRawMaterialItemId': 2, 'itemName': 'Bag', 'unitOfMeasure': 'pcs', 'isActive': true},
          {'waterRawMaterialItemId': 3, 'itemName': 'Old', 'unitOfMeasure': 'kg', 'isActive': false},
        ]
        ..gets['/api/Water/products/21/recipe'] = null;
      await open(
          tester, WaterProductDetailsScreen(session: await sessionFor(api), company: water, productId: 21),
          size: phone);
      expect(find.text('Pure 500'), findsWidgets);
      expect(find.text('1,200'), findsWidgets);
      await tester.tap(find.text('Production recipe').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add material'));
      await tester.pumpAndSettle();
      // First unused active material, alphabetically: Bag.
      expect(find.text('Bag (pcs)'), findsOneWidget);
      await tester.tap(find.text('Bag (pcs)'));
      await tester.pumpAndSettle();
      expect(find.text('Old (kg)'), findsNothing, reason: 'inactive materials are not offered');
      await tester.tap(find.text('Film (roll)').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save recipe'));
      await tester.pumpAndSettle();
      final body = api.lastBody('/api/Water/products/21/recipe', 'PUT');
      expect(body['recipeName'], 'Default');
      final items = body['items'] as List;
      expect(items.single['waterRawMaterialItemId'], 1);
      expect(items.single['outputUnit'], 'bag');
      final put = api.writes.last;
      expect(put.url.queryParameters['updatedBy'], 'user-1');
    });
  });

  group('Company', () {
    testWidgets('Company Setup: first save sets up with the normalised dropdowns', (tester) async {
      final api = FakeApi()
        ..statuses['/api/Water/company'] = 404
        ..gets['/api/Water/farm-settings'] = {'currencyCode': 'GHS', 'currencySymbol': 'GHC', 'showCurrencySymbol': true};
      await open(tester, WaterCompanySetupScreen(session: await sessionFor(api), company: water), size: phone);
      await pick(tester, 'Sachet', 'Both');
      await pick(tester, 'Borehole', 'Ghana Water');
      await see(tester, find.text('Set up Water Company'));
      await tester.tap(find.text('Set up Water Company'));
      await tester.pumpAndSettle();
      final body = api.lastBody('/api/Water/company/setup');
      expect(body['businessType'], 'Both');
      expect(body['waterSourceType'], 'GhanaWater');
      expect(body['defaultBagSachetCount'], 30);
    });

    testWidgets('Financial Settings: deferral locked; item override goes On purchase', (tester) async {
      final api = FakeApi()
        ..gets['/api/Water/financial-settings/cost-recognition'] = {
          'packagingCostRecognitionMethod': 'EXPENSE_WHEN_PURCHASED',
          'treatmentCostRecognitionMethod': 'EXPENSE_WHEN_PURCHASED',
          'isConfigured': false, 'deferralAvailable': false,
        }
        ..gets['/api/Water/financial-settings/items'] = [
          {
            'waterRawMaterialItemId': 8, 'itemName': 'Diesel', 'category': 'Fuel', 'isActive': true,
            'costRecognitionOverride': null, 'effectiveCostRecognitionMethod': 'EXPENSE_WHEN_PURCHASED',
            'costRecognitionSource': 'FarmDefault', 'costRecognitionCategoryGroup': 'Unconfigured',
          },
        ];
      await open(tester, WaterFinancialSettingsScreen(session: await sessionFor(api), company: water), size: phone);
      expect(find.text('Expense-when-consumed is not available yet'), findsOneWidget);
      // The deferred option is shown, disabled with its reason.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.textContaining('Not available yet'), findsWidgets);
      expect(find.text('Discard'), findsNothing, reason: 'nothing changed, so no Save/Discard');
      await see(tester, find.text('Show all 1'));
      await tester.tap(find.text('Show all 1'));
      await tester.pumpAndSettle();
      await see(tester, find.text('On purchase').last);
      await tester.tap(find.text('On purchase').last);
      await tester.pumpAndSettle();
      final body = api.lastBody('/api/Water/financial-settings/items/8/cost-recognition', 'PUT');
      expect(body['costRecognitionOverride'], 'EXPENSE_WHEN_PURCHASED');
    });

    testWidgets('Setup hub: Machines tab adds through its own form', (tester) async {
      final api = FakeApi()..statuses['/api/Water/company'] = 404;
      final s = await sessionFor(api);
      await open(tester, WaterSetupScreen(session: s, company: water), size: phone);
      expect(find.text('Business profile'), findsOneWidget);
      await see(tester, find.text('Machines'));
      await tester.tap(find.text('Machines'));
      await tester.pumpAndSettle();
      await see(tester, find.text('Add machines'));
      await tester.tap(find.text('Add machines'));
      await tester.pumpAndSettle();
      expect(find.text('New machine'), findsOneWidget);
      await enter(tester, 'Name', 'Filler 1');
      await pick(tester, 'Sachet machine', 'Bottle machine');
      await pick(tester, 'Active', 'Under maintenance');
      await see(tester, find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final body = api.lastBody('/api/Water/machines');
      expect(body['machineName'], 'Filler 1');
      expect(body['machineType'], 'BottleMachine');
      expect(body['status'], 'UnderMaintenance');
      expect(body['capacityPerHour'], isNull, reason: '0 || null');
    });

    testWidgets('Setup hub: Staff form uses the hub roles and adds isActive on create', (tester) async {
      final api = FakeApi();
      await open(
          tester, WaterHubFormScreen(session: await sessionFor(api), company: water, form: hubForms['staff']!),
          size: phone);
      await enter(tester, 'First name', 'Esi');
      await enter(tester, 'Last name', 'Owusu');
      await pick(tester, 'Operator', 'Cashier');
      await pick(tester, 'Monthly', 'Daily');
      await see(tester, find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final body = api.lastBody('/api/Water/staff');
      expect(body['role'], 'Cashier');
      expect(body['salaryType'], 'Daily');
      expect(body['isActive'], isTrue);
      expect(body['commissionRate'], isNull);
    });
  });

  group('Lists', () {
    testWidgets('Staff list shows the full name; Customers list reads the real fields', (tester) async {
      final api = FakeApi()
        ..gets['/api/Water/staff'] = [
          {'waterStaffId': 1, 'firstName': 'Esi', 'lastName': 'Owusu', 'role': 'Driver', 'basePay': 900, 'isActive': true},
        ]
        ..gets['/api/Water/customers'] = [
          {'waterCustomerId': 2, 'name': 'Mama Ama', 'contactPhone': '0200', 'city': 'Kumasi', 'outstandingBalance': 15},
        ];
      final s = await sessionFor(api);
      await open(tester, ListScreen(spec: PageRegistry.of('water-staff')!, session: s, company: water), size: phone);
      expect(find.text('Esi Owusu'), findsWidgets);
      await open(tester, ListScreen(spec: PageRegistry.of('water-customers')!, session: s, company: water), size: phone);
      expect(find.text('Mama Ama'), findsWidgets);
      expect(find.textContaining('Kumasi', findRichText: true), findsWidgets);
    });
  });
}
