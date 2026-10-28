// Hotel → Dashboard, at phone width against a fake API.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/hotel/hotel_dashboard_charts.dart';
import 'package:poultrycore_mobile/pages/hotel/hotel_dashboard_view.dart';
import 'package:poultrycore_mobile/pages/hotel/hotel_rooms_screens.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';

import 'support/harness.dart';

final hotel = Company(farmId: 'h1', name: 'Palm Hotel', type: CompanyType.hotel, role: 'Admin');
const tall = Size(360, 6000);

final now = DateTime.now();
final today = now.toUtc().toIso8601String().substring(0, 10);

FakeApi base() => FakeApi()
  ..gets['/api/Hotel/rooms/status-summary'] = [
    {'status': 'Available', 'roomCount': 5},
    {'status': 'Occupied', 'roomCount': 3},
    {'status': 'Reserved', 'roomCount': 1},
    {'status': 'Cleaning', 'roomCount': 1},
  ]
  ..gets['/api/Hotel/bookings'] = [
    {'hotelBookingId': 1, 'bookingRef': 'BK-1', 'guestFirstName': 'Esi', 'guestLastName': 'Boateng', 'roomNumber': '102', 'status': 'CheckedIn',
      'totalAmount': 200, 'checkInDate': '2026-10-20', 'checkOutDate': '${today}T00:00:00'},
    {'hotelBookingId': 2, 'bookingRef': 'BK-2', 'guestFirstName': 'Ama', 'guestLastName': 'Owusu', 'roomNumber': '103', 'status': 'CheckedIn',
      'totalAmount': 100, 'checkInDate': '2026-10-20', 'checkOutDate': '2099-01-01'},
    {'hotelBookingId': 3, 'bookingRef': 'BK-3', 'guestFirstName': 'Kofi', 'guestLastName': 'Mensah', 'roomTypeName': 'Suite', 'status': 'Confirmed',
      'totalAmount': 300, 'checkInDate': '${today}T00:00:00', 'checkOutDate': '2099-01-01'},
  ]
  ..gets['/api/Hotel/billing/payments'] = [
    {'hotelBookingId': 1, 'amount': 150, 'paymentMethod': 'Cash', 'reference': 'PAY-1', 'paymentDate': '${today}T09:00:00'},
    {'hotelbookingid': 2, 'amount': 140, 'paymentmethod': 'Card', 'paymentdate': '2026-10-21'},
  ]
  ..gets['/api/Hotel/billing/charges'] = [
    {'totalAmount': 40},
  ]
  ..gets['/api/Hotel/staff'] = [{}, {}, {}]
  ..gets['/api/Hotel/housekeeping'] = [
    {'status': 'Pending'},
  ]
  ..gets['/api/Hotel/maintenance'] = [
    {'status': 'InProgress'},
    {'status': 'Reported'},
  ]
  ..gets['/api/Hotel/restaurant/orders'] = [
    {'status': 'Placed'},
    {'status': 'Served'},
  ]
  ..gets['/api/Hotel/finance/expenses'] = [
    {'amount': 60, 'expenseDate': today},
  ]
  ..gets['/api/Hotel/rooms'] = [];

void main() {
  test('the route, the long date', () {
    expect(pageScreens.containsKey('/hotel-dashboard'), isTrue);
    expect(hotelLongDate(DateTime(2026, 10, 28)), 'Wednesday 28 October 2026');
  });

  testWidgets('Dashboard: the three card rows, the four panels, a card link', (tester) async {
    final api = base();
    await open(
      tester,
      Scaffold(body: HotelDashboardView(session: await sessionFor(api), company: hotel, now: () => now, autoRefresh: false)),
      size: tall,
    );
    expect(find.textContaining('Palm Hotel — '), findsOneWidget);
    expect(find.text('Auto-refreshes every 30s'), findsOneWidget);
    expect(find.text('10'), findsOneWidget, reason: 'total rooms');
    expect(find.text('30%'), findsNWidgets(3), reason: 'the occupancy card, the room-mix centre, and Occupied in its key');
    expect(find.text('150.00'), findsNWidgets(3), reason: "today's revenue, the payment in Recent Payments, and Cash in How guests pay");
    expect(find.text('1 payment(s)'), findsOneWidget);
    expect(find.text('60.00'), findsNWidgets(2), reason: "today's expenses, and the 14-day expenses total in Money in & out");
    // Esi: 200 + 40 − 150 = 90; Ama: 100 + 40 − 140 = 0.
    expect(find.text('90.00'), findsOneWidget);
    expect(find.text('1 guest(s) owe'), findsOneWidget);
    expect(find.text('Owes 90.00'), findsNWidgets(2), reason: 'in-house and departing');
    expect(find.text('Paid'), findsOneWidget);
    expect(find.text('In-House Guests (2)'), findsOneWidget);
    expect(find.text('Expected Arrivals (1)'), findsOneWidget);
    expect(find.text('Suite | Unassigned'), findsOneWidget);
    expect(find.text('Expected Departures (1)'), findsOneWidget);
    expect(find.text('Cash | $today'), findsOneWidget);
    expect(find.text('3 staff members registered'), findsOneWidget);

    await tester.tap(find.text('Total Rooms'));
    await tester.pumpAndSettle();
    expect(find.byType(HotelRoomsScreen), findsOneWidget);
  });

  testWidgets('Dashboard: an empty hotel', (tester) async {
    await open(tester, Scaffold(body: HotelDashboardView(session: await sessionFor(FakeApi()), company: hotel, autoRefresh: false)), size: tall);
    expect(find.text('No guests currently checked in'), findsOneWidget);
    expect(find.text('No arrivals today'), findsOneWidget);
    expect(find.text('No departures today'), findsOneWidget);
    expect(find.text('No payments yet'), findsOneWidget);
  });

  testWidgets('/hotel-dashboard as a page refreshes itself every 30 seconds', (tester) async {
    final api = base();
    await open(tester, HotelDashboardScreen(session: await sessionFor(api), company: hotel), size: tall);
    int loads() => api.requests.where((r) => r.url.path == '/api/Hotel/rooms/status-summary').length;
    expect(loads(), 1);
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(loads(), 2);
    expect(find.text('In-House Guests (2)'), findsOneWidget, reason: 'the figures stay on screen');
  });
  test('the chart figures: room mix, money by day, movements ahead, payment mix', () {
    final mix = roomMix([
      {'status': 'Occupied', 'roomCount': 3},
      {'status': 'Available', 'roomCount': 5},
      {'status': 'OutOfOrder', 'roomCount': 2},
    ]);
    expect([for (final s in mix) (s.label, s.value)],
        [('Available', 5), ('Occupied', 3), ('Reserved', 0), ('Cleaning', 0), ('Maintenance', 0), ('Other', 2)]);
    expect(mix[0].color, chartBlue, reason: 'colour follows the status, not its size');

    final money = dailyMoney(
      [
        {'amount': 100, 'paymentDate': '2026-10-28T09:00:00'},
        {'amount': 50, 'paymentdate': '2026-10-27'},
        {'amount': 999, 'paymentDate': '2026-10-01'},
      ],
      [
        {'amount': 30, 'expenseDate': '2026-10-28'},
      ],
      '2026-10-28',
    );
    expect(money.length, 14);
    expect((money.first.day, money.last.day), ('2026-10-15', '2026-10-28'));
    expect((money.last.revenue, money.last.expenses, money[12].revenue), (100, 30, 50));

    final moves = movementsAhead([
      {'status': 'Confirmed', 'checkInDate': '2026-10-28', 'checkOutDate': '2026-10-30'},
      {'status': 'CheckedIn', 'checkInDate': '2026-10-20', 'checkOutDate': '2026-10-29T00:00:00'},
      {'status': 'Cancelled', 'checkInDate': '2026-10-28', 'checkOutDate': '2026-10-29'},
    ], '2026-10-28');
    expect([for (final m in moves.take(3)) (m.arrivals, m.departures)], [(1, 0), (0, 1), (0, 1)]);
    expect(moves.length, 7);

    final pay = paymentMix([
      {'amount': 100, 'paymentMethod': 'Cash', 'paymentDate': '2026-10-28'},
      {'amount': 40, 'paymentmethod': 'MobileMoney', 'paymentdate': '2026-10-20'},
      {'amount': 10, 'paymentMethod': 'Voucher', 'paymentDate': '2026-10-27'},
      {'amount': 500, 'paymentMethod': 'Card', 'paymentDate': '2026-08-01'},
    ], '2026-10-28');
    expect([for (final s in pay) (s.label, s.value)], [('Cash', 100), ('Mobile Money', 40), ('Other', 10)]);
    expect(compactMoney(1250), '1.3k');
    expect(compactMoney(25000), '25k');
  });

  testWidgets('Insights: the four charts, a tapped slice, a tapped day', (tester) async {
    final api = base();
    await open(
      tester,
      Scaffold(body: HotelDashboardView(session: await sessionFor(api), company: hotel, now: () => now, autoRefresh: false)),
      size: tall,
    );
    for (final t in ['INSIGHTS', 'Room mix', 'Money in & out', 'Arrivals & departures', 'How guests pay']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text('occupied'), findsOneWidget);
    expect(find.text('of 10 rooms'), findsOneWidget);

    await tester.tap(find.text('Cleaning').last);
    await tester.pumpAndSettle();
    expect(find.text('cleaning'), findsOneWidget, reason: 'the middle now reads the tapped status');

    final columns = find.byType(PairedColumns).first;
    await tester.ensureVisible(columns);
    await tester.pumpAndSettle();
    final box = tester.getRect(find.descendant(of: columns, matching: find.byType(CustomPaint)).last);
    await tester.tapAt(Offset(box.right - 8, box.center.dy));
    await tester.pumpAndSettle();
    expect(find.textContaining('net +90.00'), findsOneWidget, reason: "today: 150 in, 60 out");
    expect(find.text('Cash'), findsOneWidget);
  });
}
