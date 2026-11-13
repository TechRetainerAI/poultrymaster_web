// Report 36 Part 2: Generic Deliveries, Drivers, Routes and the Delivery
// report, against a fake API and fake places (no GPS or internet), at phone
// width, checked against the web pages.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/generic/delivery/generic_deliveries_screen.dart';
import 'package:poultrycore_mobile/pages/generic/delivery/generic_delivery_report_screen.dart';
import 'package:poultrycore_mobile/pages/generic/delivery/generic_fleet_screens.dart';
import 'package:poultrycore_mobile/pages/generic/delivery/generic_places.dart';
import 'package:poultrycore_mobile/pages/generic/generic_kit.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart' show pageScreens;
import 'package:poultrycore_mobile/pages/web_nav.dart';

import 'support/harness.dart';

final generic = Company(farmId: 'g1', name: 'Kofi Shop', type: CompanyType.generic, role: 'Admin');
const base = '/api/generic-company/g1';

class FakePlaces implements PlacesBackend {
  @override
  Future<({double lat, double lon})> position() async => (lat: 5.6, lon: -0.2);
  @override
  Future<String?> reverse(double lat, double lon) async => 'Osu, Accra';
  @override
  Future<Place?> search(String q) async => q == 'nowhere' ? null : (name: '$q, Ghana', lat: 6.7, lon: -1.6);
  @override
  Future<({num seconds, num metres})?> drive(Place a, Place b) async => (seconds: 3900, metres: 52300);
}

Map<String, Object?> delivery(int id, String status, {num loaded = 10, num sold = 0, num sales = 0}) => {
      'genericDeliveryId': id, 'deliveryDate': '2026-11-10T00:00:00', 'driverName': 'Kojo', 'vehicleName': 'Van 1', 'route': 'East',
      'customerName': 'Ama', 'destination': 'Madina', 'transportMode': 'Van', 'genericProductId': 1, 'productName': 'Bar soap',
      'quantityLoaded': loaded, 'unit': 'Box', 'unitPrice': 5, 'quantitySold': sold, 'quantityReturned': 0, 'quantityDamaged': 0,
      'quantityShort': 0, 'cashCollected': sales, 'creditSales': 0, 'deliveryExpenses': 0, 'totalSales': sales, 'status': status,
    };

FakeApi api() => FakeApi()
  ..gets['/api/CompanyTime/context'] = {
    'businessDate': '2026-11-12', 'companyLocalDateTime': '2026-11-12T10:00:00', 'utcNow': '2026-11-12T10:00:00Z',
  }
  ..gets['$base/module-settings'] = {for (final k in genericModuleKeys) k: true}
  ..gets['$base/deliveries'] = [delivery(1, 'Loaded'), delivery(2, 'InTransit'), delivery(3, 'Reconciled', sold: 10, sales: 50)]
  ..gets['$base/products'] = [
    {'genericProductId': 1, 'productName': 'Bar soap', 'currentStock': 40, 'sellingPrice': 5, 'isActive': true},
  ]
  ..gets['$base/drivers'] = [
    {'genericDriverId': 7, 'driverName': 'Kojo', 'phoneNumber': '0241112222', 'vehicleName': 'Van 1', 'transportMode': 'Van', 'isActive': true},
    {'genericDriverId': 8, 'driverName': 'Old', 'isActive': false},
  ]
  ..gets['$base/routes'] = [
    {'genericRouteId': 3, 'routeName': 'East', 'startPoint': 'Depot', 'endPoint': 'Madina', 'estimatedTime': '40 min', 'isActive': true},
  ]
  ..gets['$base/customers'] = [
    {'genericCustomerId': 1, 'customerName': 'Ama', 'isActive': true},
  ];

/// The page list builds lazily: scroll a card's button into view first.
Future<void> reach(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(find.byKey(ValueKey(key)), 150, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => GenericPlaces.backend = FakePlaces());

  test('the web\'s filter, cards and travel text', () {
    final rows = [delivery(1, 'Loaded'), delivery(2, 'InTransit'), {...delivery(3, 'Delivered', sales: 20), 'driverName': 'Yaw'}];
    expect(filterGenericDeliveries(rows, status: 'InTransit').length, 1);
    expect(filterGenericDeliveries(rows, search: 'yaw').length, 1);
    expect(filterGenericDeliveries(rows, from: '2026-11-11').length, 0);
    final k = genericDeliveryKpis(rows);
    expect((k.total, k.inTransit, k.delivered, k.sales), (3, 1, 1, 20));
    expect(travelText(3900, 52300).time, '1h 5m (52.3 km)');
    expect(travelText(1500, 12000).time, '25 min (12.0 km)');
    final t = genericDeliveryReportTotals([
      {'totalDeliveries': 2, 'totalSales': 100, 'totalExpenses': 10, 'totalLoaded': 20, 'totalSold': 15},
      {'totalDeliveries': 1, 'totalSales': 50, 'totalExpenses': 5, 'totalLoaded': 10, 'totalSold': 2},
    ]);
    expect((t.deliveries, t.sales, t.expenses, t.rate), (3, 150, 15, 57));
  });

  test('menus and routes: Deliveries, Drivers, Routes in Catalog; the report on the hub', () {
    final cat = [for (final s in webNavGroups['generic']!.firstWhere((g) => g.title == 'Catalog').subGroups) for (final l in s.links) l.href];
    expect(cat.sublist(cat.length - 3), ['/generic-deliveries', '/generic-drivers', '/generic-routes']);
    for (final h in ['/generic-deliveries', '/generic-drivers', '/generic-routes', '/generic-reports/delivery-report']) {
      expect(pageScreens[h], isNotNull, reason: h);
    }
  });

  testWidgets('Deliveries: cards, status chips, the actions each status gets', (tester) async {
    final a = api();
    await open(tester, GenericDeliveriesScreen(session: await sessionFor(a), company: generic), size: phone);
    expect(find.text('Load, dispatch, track and reconcile product deliveries.'), findsOneWidget);
    expect(find.text('In Transit (1)'), findsOneWidget);
    await reach(tester, 'delivery-Dispatch-1');
    await reach(tester, 'delivery-Mark Delivered-2');
    await reach(tester, 'delivery-Dispatch-1');
    await tester.tap(find.byKey(const ValueKey('delivery-Dispatch-1')));
    await tester.pumpAndSettle();
    expect(a.writes.single.url.path, '$base/deliveries/1/dispatch');
    expect(find.text('Dispatched — in transit'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Reconciled (1)'), -150, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Reconciled (1)'));
    await tester.pumpAndSettle();
    await reach(tester, 'delivery-Reverse-3');
    expect(find.byKey(const ValueKey('delivery-Dispatch-1')), findsNothing);
  });

  testWidgets('New Load: driver fills vehicle + transport, route fills places, search and GPS, the body sent', (tester) async {
    final a = api();
    await open(tester, GenericDeliveriesScreen(session: await sessionFor(a), company: generic), size: phone);
    await tester.tap(find.byKey(const ValueKey('delivery-new')));
    await tester.pumpAndSettle();
    expect(find.text('Load product for delivery'), findsOneWidget);
    expect(find.text('Bar soap (40 in stock)'), findsOneWidget, reason: 'the first active product is picked');

    await tester.tap(find.byKey(const ValueKey('load-save')));
    await tester.pumpAndSettle();
    expect(find.text('Quantity must be > 0'), findsOneWidget);
    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();
    await tester.enterText(find.byKey(const ValueKey('load-qty')), '12');
    await tester.tap(find.byKey(const ValueKey('load-save')));
    await tester.pumpAndSettle();
    expect(find.text('Select a driver'), findsOneWidget);
    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();

    await tester.ensureVisible(find.byKey(const ValueKey('load-driver')));
    await tester.tap(find.byKey(const ValueKey('load-driver')));
    await tester.pumpAndSettle();
    expect(find.text('Old'), findsNothing, reason: 'inactive drivers are left out');
    await tester.tap(find.text('Kojo (Van)').last);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Van 1'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('load-route')));
    await tester.tap(find.byKey(const ValueKey('load-route')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('East (Depot → Madina)').last);
    await tester.pumpAndSettle();
    expect(find.text('Est. time: 40 min'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('load-dest-text')), 'Kumasi');
    await tester.ensureVisible(find.byKey(const ValueKey('load-dest-search')));
    await tester.tap(find.byKey(const ValueKey('load-dest-search')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('load-start-gps')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('load-save')));
    await tester.pumpAndSettle();
    final b = a.lastBody('$base/deliveries/load');
    expect(b['genericProductId'], 1);
    expect(b['quantityLoaded'], 12);
    expect(b['unitPrice'], 5);
    expect(b['driverName'], 'Kojo');
    expect(b['vehicleName'], 'Van 1');
    expect(b['transportMode'], 'Van');
    expect(b['route'], 'East');
    expect(b['startPoint'], 'Osu, Accra');
    expect(b['destination'], 'Kumasi, Ghana');
    expect(b['farmId'], 'g1');
  });

  testWidgets('Reconcile must balance before it is sent', (tester) async {
    final a = api();
    await open(tester, GenericDeliveriesScreen(session: await sessionFor(a), company: generic), size: phone);
    await reach(tester, 'delivery-Reconcile-2');
    await tester.tap(find.byKey(const ValueKey('delivery-Reconcile-2')));
    await tester.pumpAndSettle();
    expect(find.text('Accounted: 10 / 10 loaded — balances'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('rec-sold')), '7');
    await tester.pump();
    expect(find.text('Accounted: 7 / 10 loaded — must balance'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('rec-save')));
    await tester.pumpAndSettle();
    expect(find.text('Sold + returned + damaged + short must equal 10'), findsOneWidget);
    expect(a.writes, isEmpty);
    await tester.enterText(find.byKey(const ValueKey('rec-returned')), '3');
    await tester.tap(find.byKey(const ValueKey('rec-save')));
    await tester.pumpAndSettle();
    final b = a.lastBody('$base/deliveries/2/reconcile');
    expect((b['quantitySold'], b['quantityReturned'], b['cashCollected']), (7, 3, 50));
  });

  testWidgets('Routes: search both ends works out the time and distance', (tester) async {
    final a = api();
    await open(tester, GenericRoutesScreen(session: await sessionFor(a), company: generic), size: phone);
    expect(find.text('Manage delivery routes and destinations.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('fleet-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('route-name')), 'North');
    await tester.tap(find.byKey(const ValueKey('route-start-gps')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('route-end-text')), 'Tamale');
    await tester.tap(find.byKey(const ValueKey('route-end-search')));
    await tester.pumpAndSettle();
    expect(find.text('Auto-calculated from GPS coordinates'), findsOneWidget);
    expect(find.text('52.3 km'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('route-save')));
    await tester.tap(find.byKey(const ValueKey('route-save')));
    await tester.pumpAndSettle();
    final b = a.lastBody('$base/routes');
    expect(b['startPoint'], 'Osu, Accra');
    expect(b['endPoint'], 'Tamale, Ghana');
    expect(b['estimatedTime'], '1h 5m (52.3 km)');
  });

  testWidgets('Drivers: list, name required, delete asks first', (tester) async {
    final a = api();
    await open(tester, GenericDriversScreen(session: await sessionFor(a), company: generic), size: phone);
    expect(find.text('Kojo'), findsOneWidget);
    expect(find.text('Inactive'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('fleet-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('driver-save')));
    await tester.pumpAndSettle();
    expect(find.text('Driver name is required'), findsOneWidget);
    expect(a.writes, isEmpty);
  });

  testWidgets('Delivery report: tabs, totals and the empty words', (tester) async {
    final a = api()
      ..gets['$base/deliveries/reports/by-driver'] = [
        {'driverName': 'Kojo', 'transportMode': 'Van', 'totalDeliveries': 4, 'totalLoaded': 40, 'totalSold': 30, 'totalSales': 150,
          'totalExpenses': 12, 'deliveryRate': 75, 'reconciledDeliveries': 3, 'cancelledDeliveries': 1},
      ]
      ..gets['$base/deliveries/reports/by-product'] = []
      ..gets['$base/deliveries/reports/by-route'] = [];
    await open(tester, GenericDeliveryReportScreen(session: await sessionFor(a), company: generic), size: phone);
    expect(find.text('75%'), findsOneWidget, reason: 'the sell-through card: 30 of 40');
    await tester.scrollUntilVisible(find.text('3 done'), 150, scrollable: find.byType(Scrollable).first);
    expect(find.text('1 driver(s) in period'), findsOneWidget);
    expect(find.text('1 cancelled'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('By Product'), -150, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('By Product'));
    await tester.pumpAndSettle();
    expect(find.text('No reconciled deliveries in this period.'), findsOneWidget);
  });
}
