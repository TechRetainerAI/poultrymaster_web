// Hotel → Restaurant & Bar: Orders (with the POS), Menu, Kitchen and Tables,
// at phone width against a fake API.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/hotel/hotel_restaurant_screens.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/reports/report_export.dart';

import 'support/harness.dart';

final hotel = Company(farmId: 'h1', name: 'Palm Hotel', type: CompanyType.hotel, role: 'Admin');
const tall = Size(360, 5200);

Finder filled(String t) => find.widgetWithText(FilledButton, t);

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).first);
  await tester.pumpAndSettle();
}

/// An AppSelect showing [shown], then one of its options.
Future<void> choose<T>(WidgetTester tester, String shown, String option) async {
  final picker = find.ancestor(of: find.text(shown), matching: find.byType(AppSelect<T>)).first;
  await tester.ensureVisible(picker);
  await tester.pumpAndSettle();
  await tester.tap(picker);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Map body(FakeApi api, String path, [String method = 'POST']) =>
    jsonDecode(api.writes.lastWhere((w) => w.url.path == path && w.method == method).body) as Map;

// The Hotel restaurant endpoints answer with lower-case keys.
FakeApi base() => FakeApi()
  ..gets['/api/Hotel/restaurant/tables'] = [
    {'hotelrestauranttableid': 1, 'tablenumber': 'T1', 'capacity': 4, 'status': 'Available', 'location': 'Terrace'},
    {'hotelrestauranttableid': 2, 'tablenumber': 'T2', 'capacity': 2, 'status': 'Occupied'},
  ]
  ..gets['/api/Hotel/restaurant/menu'] = [
    {'hotelmenuitemid': 10, 'name': 'Jollof Rice', 'category': 'Lunch', 'price': 45, 'isavailable': true},
    {'hotelmenuitemid': 11, 'name': 'Club Beer', 'category': 'Drinks', 'price': 15, 'isavailable': false},
  ]
  ..gets['/api/Hotel/restaurant/orders'] = [
    {'hotelrestaurantorderid': 21, 'tablenumber': 'T2', 'servername': 'Ama Owusu', 'status': 'Placed', 'totalamount': 60,
      'ordertime': '2026-10-27T10:00:00Z'},
    {'hotelrestaurantorderid': 22, 'status': 'Served', 'totalamount': 30, 'ordertime': '2026-10-27T09:00:00Z',
      'deliveredtime': '2026-10-27T09:20:00Z'},
  ]
  ..gets['/api/Hotel/bookings'] = [
    {'hotelBookingId': 5, 'status': 'CheckedIn', 'roomNumber': '104', 'guestFirstName': 'Kofi', 'guestLastName': 'Mensah'},
    {'hotelBookingId': 6, 'status': 'Reserved', 'roomNumber': '105', 'guestFirstName': 'Not', 'guestLastName': 'In'},
  ]
  ..gets['/api/Hotel/staff'] = [
    {'hotelstaffid': 3, 'firstname': 'Ama', 'lastname': 'Owusu', 'department': 'Restaurant', 'role': 'Waiter', 'isactive': true},
    {'hotelstaffid': 4, 'firstname': 'Yaw', 'lastname': 'Boadu', 'department': 'Housekeeping', 'isactive': true},
  ];

void main() {
  final shared = <String>[];
  setUp(() {
    shared.clear();
    ReportExport.sharer = (name, bytes, mime, subject) async => shared.add(name);
  });

  test('the four rows open native screens', () {
    for (final h in ['/hotel-restaurant', '/hotel-menu', '/hotel-kitchen', '/hotel-restaurant-tables']) {
      expect(pageScreens.containsKey(h), isTrue, reason: h);
    }
  });

  testWidgets('Orders: the summary, tables, Active orders, the next-status button', (tester) async {
    final api = base();
    await open(tester, HotelRestaurantOrdersScreen(session: await sessionFor(api), company: hotel), size: tall);
    expect(find.text('Restaurant & Bar'), findsWidgets);
    expect(find.text('30.00'), findsOneWidget, reason: 'served revenue');
    expect(find.text('T1'), findsOneWidget);
    expect(find.text('#21 · T2'), findsOneWidget);
    expect(find.text('#22 · Takeaway'), findsNothing, reason: 'Active hides a served order');
    await tapText(tester, 'All (2)');
    expect(find.text('#22 · Takeaway'), findsOneWidget);

    await tapText(tester, 'Preparing');
    final w = api.writes.lastWhere((w) => w.url.path == '/api/Hotel/restaurant/orders/21/status');
    expect((w.method, (jsonDecode(w.body) as Map)['status'], w.url.queryParameters['farmId']), ('PATCH', 'Preparing', 'h1'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('POS: a walk-in cash order, with change, then the receipt', (tester) async {
    final api = base();
    await open(tester, HotelRestaurantOrdersScreen(session: await sessionFor(api), company: hotel), size: tall);
    await tapText(tester, 'New Order (POS)');
    expect(find.text('New Order — Point of Sale'), findsOneWidget);
    await tester.tap(find.text('Jollof Rice').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jollof Rice').first);
    await tester.pumpAndSettle();
    expect(find.text('Order Items (1)'), findsOneWidget);
    expect(find.text('90.00'), findsWidgets, reason: 'two at 45');

    await choose<String>(tester, 'Takeaway / No table', 'T1 (4 seats)');
    await choose<String>(tester, 'No server', 'Ama Owusu — Waiter');
    expect(find.text('Yaw Boadu'), findsNothing, reason: 'only restaurant staff serve');
    final received = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField)).last;
    await tester.enterText(received, '100');
    await tester.pumpAndSettle();
    expect(find.text('Change: 10.00'), findsOneWidget);

    await tester.tap(filled('Pay & Place Order — 90.00'));
    await tester.pumpAndSettle();
    final b = body(api, '/api/Hotel/restaurant/orders');
    expect((b['tableNumber'], b['serverName'], b['chargeToRoom'], b['paymentMethod'], b['farmId']), ('T1', 'Ama Owusu', false, 'Cash', 'h1'));
    expect(b['items'], [
      {'menuItemId': 10, 'quantity': 2, 'unitPrice': 45},
    ]);
    expect(shared, ['Receipt.pdf']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('POS: a checked-in guest charged to the room', (tester) async {
    final api = base();
    await open(tester, HotelRestaurantOrdersScreen(session: await sessionFor(api), company: hotel), size: tall);
    await tapText(tester, 'New Order (POS)');
    await tester.tap(find.text('Club Beer').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Hotel Guest'));
    await tester.tap(find.text('Hotel Guest'));
    await tester.pumpAndSettle();
    await choose<int>(tester, 'Select guest', 'Room 104 — Kofi Mensah');
    expect(find.text('Room 105 — Not In'), findsNothing, reason: 'only checked-in guests');
    await tester.ensureVisible(find.text('Charge to Room'));
    await tester.tap(find.text('Charge to Room'));
    await tester.pumpAndSettle();
    expect(find.text("15.00 will be added to the guest's room folio"), findsOneWidget);
    await tester.tap(filled('Charge to Room — 15.00'));
    await tester.pumpAndSettle();
    final b = body(api, '/api/Hotel/restaurant/orders');
    expect((b['hotelBookingId'], b['chargeToRoom'], b.containsKey('paymentMethod')), (5, true, false));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Menu: the items, Add, Edit and Delete', (tester) async {
    final api = base();
    await open(tester, HotelMenuScreen(session: await sessionFor(api), company: hotel), size: tall);
    expect(find.text('(2)'), findsOneWidget);
    expect(find.text('Jollof Rice'), findsOneWidget);
    expect(find.text('No'), findsOneWidget, reason: 'Club Beer is not available');

    await tapText(tester, 'Add Item');
    await enter(tester, 'Name *', 'Fried Rice');
    await tester.tap(filled('Add'));
    await tester.pumpAndSettle();
    final add = body(api, '/api/Hotel/restaurant/menu');
    expect((add['name'], add['category'], add['farmId']), ('Fried Rice', 'Lunch', 'h1'));

    await tester.tap(find.byTooltip('Edit').first);
    await tester.pumpAndSettle();
    expect(find.text('Edit Item'), findsOneWidget);
    await tester.tap(filled('Update'));
    await tester.pumpAndSettle();
    expect(body(api, '/api/Hotel/restaurant/menu/10', 'PUT')['name'], 'Jollof Rice');

    await tester.tap(find.byTooltip('Delete').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete').last);
    await tester.pumpAndSettle();
    expect(api.writes.any((w) => w.method == 'DELETE' && w.url.path == '/api/Hotel/restaurant/menu/10'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Kitchen: the columns, the counts, Move to Preparing, All shows Served', (tester) async {
    final api = base();
    await open(
      tester,
      HotelKitchenScreen(session: await sessionFor(api), company: hotel, now: () => DateTime.parse('2026-10-27T10:12:00Z')),
      size: tall,
    );
    expect(find.text('1 active'), findsOneWidget);
    expect(find.text('1 served today'), findsOneWidget);
    expect(find.text('Table T2'), findsOneWidget);
    expect(find.text('12m ago'), findsOneWidget);
    expect(find.text('SERVED'), findsNothing);
    await tapText(tester, 'Move to Preparing');
    expect((jsonDecode(api.writes.last.body) as Map)['status'], 'Preparing');
    await tapText(tester, 'All Orders (2)');
    expect(find.text('SERVED'), findsOneWidget);
    expect(find.textContaining('✓ Served'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tables: the grid and Add Table with a location', (tester) async {
    final api = base()
      ..gets['/api/Hotel/setup/table-locations'] = [
        {'description': 'Terrace'},
        {'description': 'Bar'},
      ];
    await open(tester, HotelTablesScreen(session: await sessionFor(api), company: hotel), size: tall);
    expect(find.text('T1'), findsOneWidget);
    expect(find.text('4 seats'), findsOneWidget);
    expect(find.text('Occupied'), findsOneWidget);

    await tapText(tester, 'Add Table');
    await enter(tester, 'Table Number *', 'B1');
    await choose<String>(tester, 'None', 'Bar');
    await tester.tap(filled('Add'));
    await tester.pumpAndSettle();
    final b = body(api, '/api/Hotel/restaurant/tables');
    expect((b['tableNumber'], b['capacity'], b['location']), ('B1', 4, 'Bar'));
    expect(tester.takeException(), isNull);
  });
}
