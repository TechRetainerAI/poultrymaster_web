// Poultry → Operations → Delivery, at phone width: the Driver report, the
// Deliveries tabs and actions, Load vehicle, Record driver return, and the
// delivery run page.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/delivery/deliveries_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/delivery/delivery_detail_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/delivery/delivery_logic.dart';
import 'package:poultrycore_mobile/pages/poultry/delivery/driver_report_screen.dart';

import 'support/harness.dart';

final loaded = <String, Object?>{
  'poultryVehicleLoadingId': 7, 'loadDate': '2026-10-05T08:00:00', 'status': 'Loaded', 'driverName': 'Kofi', 'vehicleName': 'Van A',
  'routeName': 'Kumasi', 'poultryDriverId': 1, 'poultryVehicleId': 2, 'poultryRouteId': 3, 'cratesLoaded': 10, 'expectedCash': 500,
  'openingCashWithDriver': 50,
};
final reconciled = <String, Object?>{
  'poultryVehicleLoadingId': 8, 'loadDate': '2026-10-01T08:00:00', 'status': 'Reconciled', 'driverName': 'Ama', 'vehicleName': 'Van B',
  'poultryDriverId': 4, 'poultryVehicleId': 2, 'cratesLoaded': 5, 'expectedCash': 250,
};
final approvedReturn = <String, Object?>{
  'poultryDriverReturnId': 21, 'poultryVehicleLoadingId': 8, 'returnDate': '2026-10-01T17:00:00', 'status': 'Approved', 'vehicleName': 'Van B',
  'driverName': 'Ama', 'cratesSold': 5, 'cratesReturned': 0, 'cratesDamaged': 0, 'cashCollected': 200, 'moMoCollected': 0,
  'creditSalesAmount': 0, 'shortageAmount': 50,
};
final cancelledReturn = <String, Object?>{
  'poultryDriverReturnId': 22, 'poultryVehicleLoadingId': 9, 'returnDate': '2026-09-30T17:00:00', 'status': 'Cancelled', 'cratesSold': 1,
};

FakeApi api() => FakeApi()
  ..gets['/api/Poultry/vehicle-loadings'] = [loaded, reconciled]
  ..gets['/api/Poultry/driver-returns'] = [approvedReturn, cancelledReturn]
  ..gets['/api/Poultry/vehicles'] = [{'poultryVehicleId': 2, 'vehicleName': 'Van A', 'vehicleType': 'Van', 'status': 'Active'}]
  ..gets['/api/Poultry/routes'] = [{'poultryRouteId': 3, 'routeName': 'Kumasi'}]
  ..gets['/api/Poultry/drivers'] = [{'poultryDriverId': 1, 'driverName': 'Kofi', 'isActive': true, 'defaultVehicleId': 2}]
  ..gets['/api/Poultry/products'] = [
    {'poultryProductId': 1, 'name': 'Eggs', 'isActive': true, 'isRawEggProduct': true, 'unitPrice': 50},
    {'poultryProductId': 2, 'name': 'Feed', 'isActive': true, 'productType': 'RawMaterial'},
  ]
  ..gets['/api/Poultry/vehicle-loadings/7/items'] = [
    {'poultryProductId': 1, 'productName': 'Eggs', 'cratesLoaded': 10, 'unitPrice': 50},
  ]
  ..writeAnswers['/api/Poultry/vehicle-loadings'] = {'poultryVehicleLoadingId': 40};

Finder get _list => find.descendant(of: find.byType(Scaffold).last, matching: find.byType(Scrollable)).first;

Future<void> see(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 60 && f.evaluate().isEmpty; i++) {
    await tester.drag(_list, const Offset(0, -250));
    await tester.pumpAndSettle();
  }
  for (var i = 0; i < 80 && f.evaluate().isEmpty; i++) {
    await tester.drag(_list, const Offset(0, 250));
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

void clearToasts(WidgetTester tester) => tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();

bool wrote(FakeApi a, String path, [String method = 'POST']) => a.writes.any((w) => w.url.path == path && w.method == method);

Map lastBody(FakeApi a, String path) => jsonDecode(a.writes.lastWhere((w) => w.url.path == path).body) as Map;

void main() {
  test('filters, the return arithmetic and checks, routes', () {
    final f = DeliveryFilters()..driver = '1';
    expect([for (final l in visibleLoadings([loaded, reconciled], f)) l['poultryVehicleLoadingId']], [7]);
    expect(visibleLoadings([loaded, reconciled], DeliveryFilters(), search: 'ama').length, 1);
    expect(visibleLoadings([loaded, reconciled], DeliveryFilters(), from: '2026-10-02').length, 1);
    final g = DeliveryFilters()..driver = '4';
    expect(visibleReturns([approvedReturn, cancelledReturn], [loaded, reconciled], g).length, 1, reason: "matched on its loading's driver");
    expect(prettyCategory('LoadingBoys'), 'Loading Boys');
    expect(deliverableProducts([
      {'isActive': true, 'productType': 'RawMaterial'},
      {'isActive': true},
    ]).length, 1);
    expect(loadProblem(vehicleId: 2, driverId: 0, items: [])!.$1, 'Driver is required');
    expect(loadProblem(vehicleId: 2, driverId: 1, items: [LoadItem(1, crates: 1), LoadItem(1, crates: 2)])!.$1, 'Duplicate product line');

    final items = [ReturnItem(productId: 1, productName: 'Eggs', loaded: 10, sold: 8, returned: 1, damaged: 1, unitPrice: 50)];
    final pay = ReturnPayments()
      ..cash = 300
      ..credit = 50
      ..floatBack = 30;
    final c = ReturnCalc(items: items, pay: pay, breakdown: [], expenses: [ExpenseRow(amount: 20)], detailed: true, loading: loaded);
    expect((c.cratesOk, c.expectedCash, c.collected, c.shortage), (true, 400, 350, 50));
    expect((c.expensesTotal, c.expectedFloatBack, c.floatBalanced, c.creditWithoutCustomer), (20, 30, true, true));
    items.first.damaged = 2;
    expect(c.problem(override: false)!.$1, "Per-product crates don't reconcile");
    expect(pickRunReturn([cancelledReturn, {...approvedReturn, 'poultryVehicleLoadingId': 9}], 9)!['poultryDriverReturnId'], 21);
    expect(pageScreens.containsKey('/poultry-driver-returns') && pageScreens.containsKey('/poultry-driver-report'), isTrue);
  });

  testWidgets('driver report: figures, per-driver totals and the delivery lines', (tester) async {
    final a = FakeApi()
      ..gets['/api/Poultry/drivers'] = [{'poultryDriverId': 1, 'driverName': 'Kofi', 'isActive': true}]
      ..gets['/api/Poultry/reports/driver-collection'] = {
        'totals': [
          {'poultryDriverId': 1, 'driverName': 'Kofi', 'deliveryRuns': 2, 'totalCratesLoaded': 20, 'totalCratesSold': 18,
            'totalCratesReturned': 1, 'totalCratesLost': 1, 'totalExpected': 900, 'totalCollected': 850, 'totalShortage': 50},
        ],
        'detail': [
          {'poultryDriverReturnId': 5, 'driverName': 'Kofi', 'returnDate': '2026-10-02T10:00:00', 'productName': 'Eggs', 'cratesLoaded': 10,
            'cratesSold': 9, 'cratesReturned': 1, 'cratesDamaged': 0, 'expectedAmount': 450},
          {'poultryDriverReturnId': 6, 'returnDate': '2026-10-03T10:00:00', 'productName': 'Eggs', 'cratesLoaded': 10, 'cratesSold': 9,
            'cratesReturned': 0, 'cratesDamaged': 1, 'expectedAmount': 450},
        ],
      };
    await open(tester, DriverReportScreen(session: await sessionFor(a), company: company), size: phone);
    expect(a.requests.last.url.queryParameters.keys, containsAll(['farmId', 'fromDate', 'toDate']));
    expect(find.text('Driver collection report'), findsOneWidget);
    expect(find.text('GHC 50.00'), findsWidgets);
    await see(tester, find.text('2 runs · Collected GHC 850.00'));
    await see(tester, find.text('Unassigned · Eggs'));
    expect(find.text('Kofi · Eggs'), findsOneWidget, reason: 'sorted by driver name');

    await tap(tester, find.byType(AppSelect<int>));
    await tester.tap(find.text('Kofi').last);
    await tester.pumpAndSettle();
    await tap(tester, find.text('Refresh'));
    expect(a.requests.last.url.queryParameters['poultryDriverId'], '1');
  });

  testWidgets('tabs, figures, void, reverse and delete', (tester) async {
    final a = api();
    await open(tester, DeliveriesScreen(session: await sessionFor(a), company: company), size: phone);
    expect(a.writes.first.url.path, '/api/Poultry/products/ensure-defaults');
    expect(find.text('Active loads (1)'), findsOneWidget);
    await see(tester, find.text('Kofi · 5 Oct 2026, 08:00'));

    await tap(tester, find.text('Void'));
    expect(find.textContaining('Void delivery Kofi (10 crates, expected GHC 500.00)?'), findsOneWidget);
    await tester.tap(find.text('Void delivery'));
    await tester.pumpAndSettle();
    expect(wrote(a, '/api/Poultry/vehicle-loadings/7/void'), isTrue);
    clearToasts(tester);

    await tap(tester, find.text('Reconciled (1)'));
    await tap(tester, find.text('Reverse'));
    expect(find.text('Reverse this reconciliation?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Reverse'));
    await tester.pumpAndSettle();
    expect(find.text('Reason for reversal is required.'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'late MoMo');
    await tester.tap(find.widgetWithText(FilledButton, 'Reverse'));
    await tester.pumpAndSettle();
    expect(wrote(a, '/api/Poultry/driver-returns/21/reverse'), isTrue);
    clearToasts(tester);

    await tap(tester, find.text('Returns (2)'));
    await see(tester, find.textContaining('Short GHC 50.00', findRichText: true));
    await tap(tester, find.text('Delete'));
    await tester.tap(find.text('Delete return'));
    await tester.pumpAndSettle();
    expect(wrote(a, '/api/Poultry/driver-returns/22', 'DELETE'), isTrue);

    await tap(tester, find.text('Setup'));
    expect(find.text('1 active · manage drivers, base pay, commissions'), findsOneWidget);
    await see(tester, find.text('Active drivers'));
  });

  testWidgets('load vehicle: create, then approve', (tester) async {
    final a = api();
    await open(tester, DeliveriesScreen(session: await sessionFor(a), company: company), size: phone);
    await tester.tap(find.text('Load vehicle'));
    await tester.pumpAndSettle();
    expect(find.text('Create delivery run — load driver'), findsOneWidget);
    await tap(tester, find.text('Load & approve'));
    expect(find.textContaining('Each line needs a product and a quantity > 0'), findsWidgets);
    clearToasts(tester);
    await see(tester, find.text('Qty (crates)'));
    final qty = find.descendant(of: find.ancestor(of: find.text('Qty (crates)'), matching: find.byType(Column)).first, matching: find.byType(TextField));
    await tester.enterText(qty, '12');
    await tester.pumpAndSettle();
    expect(find.text('GHC 600.00'), findsWidgets, reason: '12 × 50');
    await tap(tester, find.text('Load & approve'));
    final b = lastBody(a, '/api/Poultry/vehicle-loadings');
    expect((b['poultryVehicleId'], b['poultryDriverId'], b['poultryRouteId'], b['createdBy']), (2, 1, 3, 'user-1'));
    expect(((b['items'] as List).single as Map)['cratesLoaded'], 12);
    final ap = a.writes.lastWhere((w) => w.url.path == '/api/Poultry/vehicle-loadings/40/approve');
    expect(ap.url.queryParameters['approvedBy'], 'user-1');
  });

  testWidgets('record return: balanced crates, approve & reconcile body', (tester) async {
    final a = api();
    await open(tester, DeliveriesScreen(session: await sessionFor(a), company: company), size: phone);
    await tap(tester, find.text('Record return'));
    expect(find.textContaining('Record driver return — Kofi / Van A / Kumasi'), findsOneWidget);
    await see(tester, find.text('✓ Crates balanced'));
    expect(find.text('GHC 500.00'), findsWidgets);
    await see(tester, find.text('Cash'));
    final cash = find.descendant(of: find.ancestor(of: find.text('Cash'), matching: find.byType(Row)).first, matching: find.byType(TextField));
    await tester.enterText(cash, '500');
    await tester.pumpAndSettle();
    await tap(tester, find.text('Approve & Reconcile'));
    final b = lastBody(a, '/api/Poultry/driver-returns/approve-reconcile');
    expect((b['poultryVehicleLoadingId'], b['cratesSold'], b['cashCollected'], b['cashReturnedByDriver'], b['salesPostingMode']),
        (7, 10, 500, 50, 'Summary'));
    expect(b.containsKey('customerSales'), isFalse);
    expect(find.textContaining('Return reconciled'), findsOneWidget);
  });

  testWidgets('delivery run page', (tester) async {
    final a = api()
      ..gets['/api/Poultry/vehicle-loadings/8'] = reconciled
      ..gets['/api/Poultry/vehicle-loadings/8/items'] = [
        {'poultryVehicleLoadingItemId': 1, 'poultryProductId': 1, 'productName': 'Eggs', 'cratesLoaded': 5, 'eggsPerCrate': 30, 'unitPrice': 50},
      ]
      ..gets['/api/Poultry/driver-returns/21/customer-sales'] = [
        {'poultryDriverReturnCustomerSaleId': 1, 'customerLabel': 'Shop 1', 'totalAmount': 250, 'creditAmount': 50, 'generatedSaleId': 99},
      ];
    await open(tester, DeliveryDetailScreen(session: await sessionFor(a), company: company, loadingId: 8), size: phone);
    expect(find.text('Delivery run #8'), findsOneWidget);
    expect(find.text('Shortage'), findsOneWidget);
    await see(tester, find.text('Generated sale #99'));
    expect(find.text('Customer sales breakdown (1)'), findsOneWidget);
    await see(tester, find.text('Audit trail'));
    expect(find.text('Loading created'), findsOneWidget);
  });
}
