// Restaurant → Dashboard (2026-10-21): the web's dashboard drawn natively, the
// Home tab for a Restaurant company, against a fake API at 360 px.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_dashboard_view.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_orders_screen.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_pos_screen.dart';

import 'support/harness.dart';

final rest = Company(farmId: 'farm-1', name: 'Rose Bistro', type: CompanyType.restaurant, role: 'Admin');
const tall = Size(360, 3000);

String nowIso({int minus = 0}) => DateTime.now().subtract(Duration(minutes: minus)).toUtc().toIso8601String();

FakeApi dashboardApi() => FakeApi()
  ..gets['/api/Restaurant/orders'] = [
    {'orderId': 1, 'orderNumber': 'ORD-1', 'orderType': 'DineIn', 'status': 'Preparing', 'tableNumber': '4', 'totalAmount': 40,
      'paymentStatus': 'Unpaid', 'createdAt': nowIso(minus: 5)},
    {'orderId': 2, 'orderNumber': 'ORD-2', 'orderType': 'Takeaway', 'status': 'Completed', 'totalAmount': 25, 'paymentStatus': 'Paid',
      'createdAt': nowIso(minus: 30)},
    {'orderId': 3, 'orderNumber': 'ORD-3', 'orderType': 'Delivery', 'status': 'Completed', 'totalAmount': 99, 'paymentStatus': 'Paid',
      'createdAt': '2020-01-01T10:00:00Z'},
  ]
  ..gets['/api/Restaurant/menu/items'] = [
    {'menuItemId': 1, 'name': 'Jollof', 'isAvailable': true},
    {'menuItemId': 2, 'name': 'Banku', 'isAvailable': false},
  ]
  ..gets['/api/Restaurant/floor/tables'] = [
    {'tableId': 1, 'status': 'Occupied'},
    {'tableId': 2, 'status': 'Available'},
    {'tableId': 3, 'status': 'Available'},
  ]
  ..gets['/api/Restaurant/kds/stats'] = {'pendingCount': 2, 'preparingCount': 1, 'readyCount': 0, 'longestWaitMinutes': 12.6}
  ..gets['/api/Restaurant/delivery/stats'] = {'availableDrivers': 3, 'activeCount': 1, 'deliveredCount': 7}
  ..gets['/api/Restaurant/reservations/waitlist/stats'] = {'waitingCount': 2, 'notifiedCount': 1, 'avgWaitMins': 9.8, 'totalCovers': 6}
  ..gets['/api/Restaurant/reservations'] = [
    {'reservationId': 1},
    {'reservationId': 2},
  ];

void main() {
  test('the route and the figures', () {
    expect(pageScreens.containsKey('/restaurant-dashboard'), isTrue);
    final now = DateTime.now();
    final f = RestaurantDashboardFigures([
      {'status': 'Placed', 'createdAt': now.toUtc().toIso8601String(), 'paymentStatus': 'Unpaid', 'totalAmount': 10},
      {'status': 'Completed', 'createdAt': now.toUtc().toIso8601String(), 'paymentStatus': 'Paid', 'totalAmount': 30},
      {'status': 'Refunded', 'createdAt': '2020-01-01', 'paymentStatus': 'Paid', 'totalAmount': 50},
    ], [
      {'isAvailable': false},
      {'isAvailable': true},
    ], [
      {'status': 'Occupied'},
      {'status': 'Available'},
    ], now: now);
    expect((f.active.length, f.todayOrders, f.todayRevenue, f.occupied, f.available, f.tableCount, f.unavailableItems), (1, 2, 30, 1, 1, 2, 1));
    expect(restaurantQuickActions.map((a) => a.$2),
        ['New Order', 'View Orders', 'Kitchen', 'Reservations', 'Floor Plan', 'Menu Items', 'Online Orders', 'Delivery']);
    for (final a in restaurantQuickActions) {
      expect(pageScreens.containsKey(a.$1), isTrue, reason: a.$1);
    }
  });

  testWidgets('figures, kitchen, delivery, waitlist, quick actions, the 86 alert and recent orders', (tester) async {
    final api = dashboardApi();
    await open(tester, RestaurantDashboardScreen(session: await sessionFor(api), company: rest), size: tall);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.textContaining('Rose Bistro — '), findsOneWidget);
    expect(find.text('1'), findsWidgets, reason: 'one active order');
    expect(find.text('25'), findsOneWidget, reason: "today's paid revenue");
    expect(find.text('2 orders today'), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);
    expect(find.text('2 available'), findsOneWidget);
    expect(find.text('Preparing'), findsWidgets);
    expect(find.text('Longest wait: 12min'), findsOneWidget);
    expect(find.text('Drivers Free'), findsOneWidget);
    expect(find.text('Avg Wait'), findsOneWidget);
    expect(find.text('9min'), findsOneWidget);
    expect(find.textContaining("currently 86'd", findRichText: true), findsOneWidget);
    expect(find.text('ORD-1'), findsOneWidget);
    expect(find.text('ORD-2'), findsNothing, reason: 'completed orders are not recent active orders');
    final res = api.requests.lastWhere((r) => r.url.path == '/api/Restaurant/reservations').url.queryParameters;
    expect(res['date'], isNotNull);

    // A recent order opens All Orders; Open POS opens the POS.
    await tester.tap(find.text('ORD-1'));
    await tester.pumpAndSettle();
    expect(find.byType(RestaurantOrdersScreen), findsOneWidget);
    Navigator.of(tester.element(find.byType(RestaurantOrdersScreen))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open POS'));
    await tester.pumpAndSettle();
    expect(find.byType(RestaurantPosScreen), findsOneWidget);
  });

  testWidgets('a failing section shows empty and is named in one toast', (tester) async {
    final api = dashboardApi()
      ..statuses['/api/Restaurant/kds/stats'] = 500
      ..statuses['/api/Restaurant/delivery/stats'] = 500
      ..gets['/api/Restaurant/orders'] = []
      ..gets['/api/Restaurant/menu/items'] = []
      ..gets['/api/Restaurant/reservations/waitlist/stats'] = {'waitingCount': 0};
    await open(tester, RestaurantDashboardScreen(session: await sessionFor(api), company: rest), size: tall);
    expect(find.textContaining('Kitchen, Delivery -- these show as empty', findRichText: true), findsOneWidget);
    expect(find.text('No kitchen data'), findsOneWidget);
    expect(find.text('No delivery data'), findsOneWidget);
    expect(find.text('No guests waiting'), findsOneWidget);
    expect(find.text('No active orders'), findsOneWidget);
    expect(find.textContaining("86'd", findRichText: true), findsNothing);
  });
}
