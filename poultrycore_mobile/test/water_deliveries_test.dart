// Water → Operations → Delivery (app/water-driver-returns, its [id] page and
// app/water-driver-report) at phone width: the return maths, the tabs and
// their actions, Load vehicle, Record return with each posting mode, the
// delivery-run page and the driver collection report.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/money/money_routes.dart';
import 'package:poultrycore_mobile/pages/water/water_deliveries_screen.dart';
import 'package:poultrycore_mobile/pages/water/water_driver_return_screen.dart';

import 'support/harness.dart';

final loaded = <String, Object?>{
  'waterVehicleLoadingId': 10, 'loadDate': '2026-10-05T00:00:00', 'status': 'Loaded', 'driverName': 'Kofi', 'waterDriverId': 1,
  'vehicleName': 'Truck A', 'waterVehicleId': 2, 'routeName': 'North', 'waterRouteId': 3, 'bagsLoaded': 100, 'expectedCash': 600,
  'openingCashWithDriver': 50,
};
final reconciled = <String, Object?>{
  'waterVehicleLoadingId': 11, 'loadDate': '2026-10-01T00:00:00', 'status': 'Reconciled', 'driverName': 'Ama', 'waterDriverId': 4,
  'vehicleName': 'Truck B', 'bagsLoaded': 40, 'expectedCash': 240, 'notes': 'early run',
};
final approvedReturn = <String, Object?>{
  'waterDriverReturnId': 21, 'waterVehicleLoadingId': 11, 'returnDate': '2026-10-01T00:00:00', 'status': 'Approved', 'vehicleName': 'Truck B',
  'driverName': 'Ama', 'bagsSold': 40, 'bagsReturned': 0, 'bagsDamaged': 0, 'cashCollected': 200, 'moMoCollected': 0, 'bankCollected': 0,
  'creditSalesAmount': 40, 'shortageAmount': 0, 'salesPostingMode': 'OneCustomer', 'primaryCustomerId': 7, 'cashReturnedByDriver': 0,
};
final cancelledReturn = <String, Object?>{
  'waterDriverReturnId': 22, 'waterVehicleLoadingId': 9, 'returnDate': '2026-09-01T00:00:00', 'status': 'Cancelled', 'bagsSold': 5,
  'cashCollected': 30, 'shortageAmount': 0,
};

FakeApi api() => FakeApi()
  ..gets['/api/CompanyTime/context'] = {
    'businessDate': '2026-10-06', 'companyLocalDateTime': '2026-10-06T10:00:00', 'utcNow': '2026-10-06T10:00:00Z',
  }
  ..gets['/api/Water/vehicle-loadings'] = [loaded, reconciled]
  ..gets['/api/Water/driver-returns'] = [approvedReturn, cancelledReturn]
  ..gets['/api/Water/vehicles'] = [
    {'waterVehicleId': 2, 'vehicleName': 'Truck A', 'vehicleType': 'Truck', 'status': 'Active'},
    {'waterVehicleId': 5, 'vehicleName': 'Van C', 'vehicleType': 'Van', 'status': 'Active'},
  ]
  ..gets['/api/Water/routes'] = [
    {'waterRouteId': 3, 'routeName': 'North'},
  ]
  ..gets['/api/Water/products'] = [
    {'waterProductId': 7, 'name': 'Sachet 500ml', 'unitPrice': 6, 'productType': 'FinishedGood'},
    {'waterProductId': 8, 'name': 'Film', 'unitPrice': 1, 'productType': 'RawMaterial'},
  ]
  ..gets['/api/Water/drivers'] = [
    {'waterDriverId': 1, 'driverName': 'Kofi', 'isActive': true, 'defaultVehicleId': 5},
    {'waterDriverId': 4, 'driverName': 'Ama', 'isActive': true},
  ]
  ..gets['/api/Water/staff'] = [
    {'waterStaffId': 30, 'firstName': 'Yaw', 'lastName': 'Boat', 'role': 'Loader', 'isActive': true},
  ]
  ..gets['/api/Water/customers'] = [
    {'waterCustomerId': 7, 'name': 'Shop Seven'},
  ]
  ..gets['/api/Water/vehicle-loadings/10/items'] = [
    {'waterVehicleLoadingItemId': 1, 'waterProductId': 7, 'productName': 'Sachet 500ml', 'bagsLoaded': 100, 'unitPrice': 6},
  ]
  ..gets['/api/Water/vehicle-loadings/11/items'] = [
    {'waterVehicleLoadingItemId': 2, 'waterProductId': 7, 'productName': 'Sachet 500ml', 'bagsLoaded': 40, 'unitPrice': 6, 'expectedAmount': 240},
  ]
  ..gets['/api/Water/driver-returns/21/items'] = [
    {'waterDriverReturnItemId': 1, 'waterProductId': 7, 'productName': 'Sachet 500ml', 'bagsLoaded': 40, 'bagsSold': 40, 'bagsReturned': 0,
      'bagsDamaged': 0, 'unitPrice': 6},
  ]
  ..gets['/api/Water/driver-returns/21/customer-sales'] = <Map>[]
  ..gets['/api/Water/driver-returns/21/expenses'] = [
    {'waterDeliveryExpenseId': 1, 'expenseCategory': 'Fuel', 'amount': 20, 'isApproved': true, 'description': 'top-up'},
  ]
  ..gets['/api/Water/reports/driver-collection'] = {
    'totals': [
      {'waterDriverId': 1, 'driverName': 'Kofi', 'deliveryRuns': 3, 'reconciledRuns': 2, 'cashCollected': 900, 'moMoCollected': 100, 'bankCollected': 0,
        'creditSales': 50, 'shortage': 25, 'overage': 0},
    ],
    'detail': [
      {'waterDriverId': 1, 'driverName': 'Kofi', 'waterProductId': 7, 'productName': 'Sachet 500ml', 'bagsLoaded': 300, 'bagsSold': 280,
        'bagsReturned': 15, 'bagsDamaged': 5, 'expectedCash': 1680, 'salesValue': 1680},
    ],
  }
  ..writeAnswers['/api/Water/vehicle-loadings'] = {'waterVehicleLoadingId': 99}
  ..writeAnswers['/api/Water/driver-returns'] = {'waterDriverReturnId': 77};

Finder get _list => find.descendant(of: find.byType(Scaffold).last, matching: find.byType(Scrollable)).first;

Future<void> see(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 50 && f.evaluate().isEmpty; i++) {
    await tester.drag(_list, const Offset(0, -200));
    await tester.pumpAndSettle();
  }
  for (var i = 0; i < 100 && f.evaluate().isEmpty; i++) {
    await tester.drag(_list, const Offset(0, 200));
    await tester.pumpAndSettle();
  }
  Scrollable.ensureVisible(tester.element(f.first), alignment: .5);
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder f) async {
  await see(tester, f);
  await tester.tap(f.first);
  await tester.pumpAndSettle();
}

Future<void> pick<T>(WidgetTester tester, String shown, String option) async {
  await see(tester, find.text(shown));
  await tester.tap(find.ancestor(of: find.text(shown), matching: find.byType(AppSelect<T>)).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

/// The number field on the row labelled [label] (the return's label-left rows).
Future<void> enterRow(WidgetTester tester, String label, String text) async {
  await see(tester, find.text(label));
  final field = find.descendant(of: find.ancestor(of: find.text(label), matching: find.byType(Row)).first, matching: find.byType(TextFormField));
  await tester.enterText(field.first, text);
  await tester.pumpAndSettle();
}

Future<void> enter(WidgetTester tester, String label, String text) async {
  await see(tester, find.text(label));
  final field = find.descendant(of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first, matching: find.byType(TextFormField));
  await tester.enterText(field.first, text);
  await tester.pumpAndSettle();
}

void clearToasts(WidgetTester tester) =>
    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();

Map lastBody(FakeApi a, String path) => jsonDecode(a.writes.lastWhere((w) => w.url.path == path).body) as Map;

void main() {
  group('return maths', () {
    test('bags, money, float, breakdown checks', () {
      final items = [WaterReturnItem(7, 'Sachet', 100, 90, 8, 2, 6)];
      final m = WaterReturnMaths(
        items: items, loading: loaded, cash: 400, momo: 100, bank: 0, credit: 20, cashReturned: 30,
        breakdown: [], expenses: [WaterExpenseRow(1, amount: 20)], postingMode: 'Detailed',
      );
      expect((m.sold, m.returned, m.damaged, m.loaded, m.bagsOk), (90, 8, 2, 100, true));
      expect((m.expectedCash, m.collected, m.shortage, m.overage), (540, 520, 20, 0));
      expect((m.expensesTotal, m.expectedFloatBack, m.floatBalanced), (20, 30, true));
      expect(m.creditWithoutCustomer, isTrue);
      final row = WaterBreakdownRow(1, cash: 400, momo: 100, credit: 20, items: [WaterBreakdownItem(2, 7, 90, 6)]);
      final m2 = WaterReturnMaths(
        items: items, loading: loaded, cash: 400, momo: 100, bank: 0, credit: 20, cashReturned: 30,
        breakdown: [row], expenses: [], postingMode: 'Detailed',
      );
      expect((m2.breakdownBalanced, m2.detailedCreditUnassigned), (true, true));
      expect(prettyExpenseCategory('ChopMoney'), 'Chop Money');
      expect(waterCurrentReturn([approvedReturn, cancelledReturn, {...cancelledReturn, 'waterVehicleLoadingId': 11, 'waterDriverReturnId': 30}], 11)?['waterDriverReturnId'], 21);
    });
  });

  test('on the sidebar route, the run page by link', () async {
    expect(pageScreens.containsKey('/water-driver-returns'), isTrue);
    expect(pageScreens.containsKey('/water-driver-report'), isTrue);
    expect((moneyScreenForHref('/water-driver-returns/10', await sessionFor(FakeApi()), company) as WaterDeliveryRunScreen).loadingId, 10);
  });

  testWidgets('Deliveries: tabs, figures, Void, Reverse with a reason, Uncancel and admin Delete', (tester) async {
    final a = api();
    await open(tester, WaterDeliveriesScreen(session: await sessionFor(a), company: company), size: phone);
    expect(find.text('Active loads (1)'), findsOneWidget);
    await see(tester, find.text('Kofi · 5 Oct 2026'));
    await see(tester, find.text('Vehicles out'));
    expect(find.text('Total shortages'), findsOneWidget);

    await tap(tester, find.widgetWithText(OutlinedButton, 'Void'));
    expect(find.textContaining('Void delivery Kofi (100 bags, expected GHC 600.00)?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Void delivery'));
    await tester.pumpAndSettle();
    final v = a.writes.last;
    expect((v.url.path, v.url.queryParameters['voidedBy']), ('/api/Water/vehicle-loadings/10/void', 'user-1'));
    clearToasts(tester);

    await tap(tester, find.text('Reconciled (1)'));
    await tap(tester, find.widgetWithText(OutlinedButton, 'Reverse'));
    expect(find.text('Reverse this reconciliation?'), findsOneWidget);
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField)), 'late MoMo');
    await tester.tap(find.widgetWithText(FilledButton, 'Reverse'));
    await tester.pumpAndSettle();
    final r = a.writes.last;
    expect((r.url.path, r.url.queryParameters['reversedBy']), ('/api/Water/driver-returns/21/reverse', 'user-1'));
    expect(jsonDecode(r.body), {'reason': 'late MoMo'});
    expect(find.textContaining('Reconciliation reversed'), findsOneWidget);
    clearToasts(tester);

    await tap(tester, find.text('Returns (2)'));
    await see(tester, find.text('Delivery #9 · Vehicle — · 5 bags sold'));
    await tap(tester, find.widgetWithText(OutlinedButton, 'Uncancel'));
    expect(a.writes.last.url.path, '/api/Water/driver-returns/22/uncancel');
    clearToasts(tester);
    await tap(tester, find.widgetWithText(OutlinedButton, 'Delete'));
    await tester.tap(find.widgetWithText(FilledButton, 'Delete return'));
    await tester.pumpAndSettle();
    expect((a.writes.last.method, a.writes.last.url.path), ('DELETE', '/api/Water/driver-returns/22'));

    await tap(tester, find.text('Setup'));
    expect(find.text('Driver collection report'), findsOneWidget);
  });

  testWidgets('Load vehicle: driver fills the vehicle, assistant, the body, then approve', (tester) async {
    final a = api();
    await open(tester, WaterDeliveriesScreen(session: await sessionFor(a), company: company), size: phone);
    await tap(tester, find.text('Load vehicle'));
    expect(find.text('Create delivery run — load driver'), findsOneWidget);
    await see(tester, find.text('Truck A (Truck)'));
    await pick<int>(tester, 'Kofi', 'Ama');
    await pick<int>(tester, 'Ama', 'Kofi');
    await see(tester, find.text('Van C (Van)'));
    expect(find.text('Film'), findsNothing, reason: 'only finished goods can be loaded');
    await pick<int>(tester, '— none —', 'Yaw Boat · Loader');
    await enter(tester, 'Qty (bags)', '60');
    await enter(tester, 'Opening cash with driver', '50');
    await see(tester, find.text('GHC 360.00'));
    await tap(tester, find.text('Load & approve'));
    final b = lastBody(a, '/api/Water/vehicle-loadings');
    expect((b['waterVehicleId'], b['waterDriverId'], b['assistantStaffId'], b['waterRouteId'], b['openingCashWithDriver'], b['bagsLoaded']),
        (5, 1, 30, 3, 50, 0), reason: "Kofi's default vehicle is Van C");
    expect((b['items'] as List).single, {'waterProductId': 7, 'bagsLoaded': 60, 'unitPrice': 6, 'sachetsPerBag': 30, 'notes': null});
    expect(a.writes.last.url.path, '/api/Water/vehicle-loadings/99/approve');
    expect(find.textContaining('Delivery run loaded — stock moved out'), findsOneWidget);
  });

  testWidgets('Record return: all sold by default, one-customer rule, the body, posting mode, approve', (tester) async {
    final a = api();
    await open(tester, WaterDriverReturnScreen(
      session: await sessionFor(a), company: company, loading: loaded,
      products: [(api().gets['/api/Water/products'] as List).first as Map],
      customers: [(api().gets['/api/Water/customers'] as List).first as Map],
    ), size: phone);
    await see(tester, find.text('✓ Balanced'));
    await see(tester, find.textContaining('✓ Bags balanced'));
    expect(find.textContaining("haven't selected the customer yet"), findsOneWidget);
    await enterRow(tester, 'Returned (bags)', '5');
    await see(tester, find.text('+5'));
    await enterRow(tester, 'Sold (bags)', '95');
    await enterRow(tester, 'Cash', '500');
    await enterRow(tester, 'Credit sales', '70');
    await see(tester, find.textContaining('Unavailable while there are credit sales'));
    await pick<int>(tester, 'Pick a customer', 'Shop Seven');
    await tap(tester, find.textContaining('Step 4 · Delivery expenses', findRichText: true));
    await tap(tester, find.text('Add expense'));
    await enter(tester, 'Amount', '20');
    await see(tester, find.textContaining("doesn't match the expected float of GHC 30.00"));
    await enterRow(tester, 'Cash returned by driver', '30');
    expect(find.textContaining("doesn't match the expected float"), findsNothing);
    await tap(tester, find.text('Approve & Reconcile'));

    final b = lastBody(a, '/api/Water/driver-returns');
    expect((b['bagsSold'], b['bagsReturned'], b['cashCollected'], b['creditSalesAmount'], b['cashReturnedByDriver'], b['approvedDeliveryExpenses']),
        (95, 5, 500, 70, 30, 20));
    expect(b.containsKey('customerSales'), isFalse, reason: 'only the detailed mode sends a breakdown');
    expect((b['expenses'] as List).single, {'expenseCategory': 'Fuel', 'amount': 20, 'description': null, 'isApproved': true});
    expect(lastBody(a, '/api/Water/driver-returns/77/posting-mode'), {'salesPostingMode': 'OneCustomer', 'primaryCustomerId': 7});
    expect(a.writes.last.url.path, '/api/Water/driver-returns/77/approve-reconcile');
    expect(find.textContaining('Return reconciled'), findsOneWidget);
  });

  testWidgets('Record return: the detailed breakdown must match, override, Draft save', (tester) async {
    final a = api();
    await open(tester, WaterDriverReturnScreen(
      session: await sessionFor(a), company: company, loading: loaded,
      products: [(api().gets['/api/Water/products'] as List).first as Map],
      customers: [(api().gets['/api/Water/customers'] as List).first as Map],
    ), size: phone);
    await enterRow(tester, 'Cash', '600');
    await tap(tester, find.text('Detailed customer breakdown'));
    await tap(tester, find.textContaining('Customer sales breakdown', findRichText: true));
    await tap(tester, find.text('Add customer sale'));
    await see(tester, find.text('Customer breakdown does not match the return summary.'));
    await tap(tester, find.text('Record return (Draft)'));
    expect(find.textContaining("Customer breakdown doesn't match summary"), findsOneWidget);
    clearToasts(tester);
    await tap(tester, find.text('Admin override — approve anyway'));
    await tap(tester, find.text('Record return (Draft)'));
    final b = lastBody(a, '/api/Water/driver-returns');
    expect((b['customerSales'] as List).single['waterCustomerId'], isNull);
    expect(lastBody(a, '/api/Water/driver-returns/77/posting-mode')['salesPostingMode'], 'Detailed');
    expect(a.writes.any((w) => w.url.path.endsWith('approve-reconcile')), isFalse);
    expect(find.textContaining('Return recorded as Draft'), findsOneWidget);
  });

  testWidgets('Delivery run page: figures, products, return, money, expenses, audit', (tester) async {
    final a = api();
    await open(tester, WaterDeliveryRunScreen(session: await sessionFor(a), company: company, loadingId: 11), size: phone);
    expect(find.text('Delivery run #11'), findsWidgets);
    expect(find.text('Back to Deliveries'), findsOneWidget);
    await see(tester, find.text('Total loaded (bags)'));
    expect(find.text('GHC 240.00'), findsWidgets);
    await see(tester, find.text('Return reconciliation'));
    await see(tester, find.text('Driver float returned'));
    await see(tester, find.text('Summary-only return — no per-customer breakdown was recorded.'));
    await see(tester, find.text('Delivery expenses (GHC 20.00)'));
    await see(tester, find.text('early run'));
  });

  testWidgets('Driver report: totals, the per-driver strip, the deliveries list', (tester) async {
    final a = api();
    await open(tester, WaterDriverReportScreen(session: await sessionFor(a), company: company), size: phone);
    final q = a.requests.lastWhere((r) => r.url.path == '/api/Water/reports/driver-collection').url.queryParameters;
    expect(q.keys, containsAll(['farmId', 'fromDate', 'toDate']));
    await see(tester, find.text('Delivery runs'));
    expect(find.text('GHC 25.00'), findsWidgets);
    await see(tester, find.text('Kofi · Sachet 500ml'));
    await pick<int>(tester, '— all drivers —', 'Kofi');
    await tap(tester, find.text('Refresh'));
    expect(a.requests.lastWhere((r) => r.url.path == '/api/Water/reports/driver-collection').url.queryParameters['waterDriverId'], '1');
  });
}
