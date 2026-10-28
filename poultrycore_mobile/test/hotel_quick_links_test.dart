// Hotel → Quick Links: Daily Closing, Night Audit and Shift Handover, at phone
// width against a fake API.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/hotel/hotel_quick_links_screens.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';

import 'support/harness.dart';

final hotel = Company(farmId: 'h1', name: 'Palm Hotel', type: CompanyType.hotel, role: 'Admin');
const tall = Size(360, 6000);

Finder filled(String t) => find.widgetWithText(FilledButton, t);

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).first);
  await tester.pumpAndSettle();
}

Future<void> choose<T>(WidgetTester tester, String shown, String option) async {
  final picker = find.ancestor(of: find.text(shown).last, matching: find.byType(AppSelect<T>)).first;
  await tester.ensureVisible(picker);
  await tester.pumpAndSettle();
  await tester.tap(picker);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Map body(FakeApi api, String path) => jsonDecode(api.writes.lastWhere((w) => w.url.path == path && w.method == 'POST').body) as Map;

final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);

FakeApi base() => FakeApi()
  ..gets['/api/Hotel/rooms/status-summary'] = [
    {'status': 'Occupied', 'roomCount': 3},
    {'status': 'Available', 'roomcount': 5},
    {'status': 'Maintenance', 'roomCount': 2},
  ]
  ..gets['/api/Hotel/bookings'] = [
    {'hotelBookingId': 1, 'status': 'CheckedIn', 'totalAmount': 300, 'checkInDate': '2026-10-20', 'checkOutDate': '${today}T00:00:00'},
    {'hotelBookingId': 2, 'status': 'CheckedIn', 'totalAmount': 100, 'checkInDate': '2026-10-20', 'checkOutDate': '2099-01-01'},
    {'hotelBookingId': 3, 'status': 'Confirmed', 'totalAmount': 80, 'checkInDate': '${today}T00:00:00', 'checkOutDate': '2099-01-01'},
  ]
  ..gets['/api/Hotel/billing/payments'] = [
    {'hotelBookingId': 1, 'amount': 200, 'paymentDate': '${today}T09:00:00'},
    {'hotelbookingid': 2, 'amount': 100, 'paymentdate': '2026-01-01'},
    {'hotelBookingId': 9, 'amount': 50, 'paymentDate': '${today}T10:00:00', 'status': 'Void'},
  ]
  ..gets['/api/Hotel/finance/expenses'] = [
    {'amount': 75, 'expenseDate': today},
    {'amount': 999, 'expenseDate': '2026-01-01'},
  ]
  ..gets['/api/Hotel/housekeeping'] = [
    {'status': 'Pending'},
    {'status': 'Done'},
  ]
  ..gets['/api/Hotel/maintenance'] = [
    {'status': 'Open'},
    {'status': 'Closed'},
  ]
  ..gets['/api/Hotel/reports/daily-closings'] = [
    {'hotelDailyClosingId': 1, 'closingDate': '2026-10-25T00:00:00', 'totalRevenue': 500, 'totalExpenses': 120, 'occupancyRate': 30, 'roomsOccupied': 3,
      'totalRooms': 10, 'adr': 166.67, 'revPar': 50, 'notes': 'Quiet day'},
    {'hoteldailyclosingid': 2, 'closingdate': '2026-10-26', 'totalrevenue': 100, 'totalexpenses': 300, 'occupancyrate': 10, 'roomsoccupied': 1, 'totalrooms': 10},
  ]
  ..gets['/api/Hotel/night-audit'] = [
    {'hotelnightauditid': 1, 'auditdate': '2026-10-26T23:00:00', 'occupiedrooms': 4, 'totalrooms': 10, 'occupancyrate': 40, 'totalrevenue': 800,
      'totalexpenses': 200, 'outstandingbalances': 150, 'checkincount': 2, 'checkoutcount': 1, 'noshowcount': 1, 'pendinghousetasks': 3,
      'openmaintenance': 1, 'roomchargesposted': 4, 'status': 'Completed', 'issues': 'Outstanding balances; 3 pending tasks'},
  ]
  ..gets['/api/Hotel/shift-handovers'] = [
    {'hotelshifthandoverid': 5, 'shiftdate': '2026-10-27', 'shifttype': 'Night', 'status': 'Submitted', 'handoverby': 'Ama Owusu', 'handoverto': 'Kofi Mensah',
      'keymessages': 'Room 101 late checkout', 'pendingitems': 'Fix TV in 204', 'cashbalance': 450},
    {'hotelshifthandoverid': 4, 'shiftdate': '2026-10-26', 'shifttype': 'Morning', 'status': 'Acknowledged', 'handoverby': 'Kofi Mensah',
      'receivedby': 'Ama Owusu', 'acknowledgedat': '2026-10-26T15:00:00Z'},
  ]
  ..gets['/api/Hotel/staff'] = [
    {'hotelStaffId': 1, 'firstName': 'Ama', 'lastName': 'Owusu', 'role': 'Receptionist', 'isActive': true},
    {'hotelStaffId': 2, 'firstName': 'Kofi', 'lastName': 'Mensah', 'role': 'Manager', 'isActive': true},
    {'hotelStaffId': 3, 'firstName': 'Gone', 'lastName': 'Away', 'role': 'Porter', 'isActive': false},
  ];

void main() {
  test('routes, the live day, the audit preview, the date wording', () {
    for (final h in ['/hotel-daily-closing', '/hotel-night-audit', '/hotel-shift-handover']) {
      expect(pageScreens.containsKey(h), isTrue, reason: h);
    }
    final api = base();
    List<Map> rows(String p) => (api.gets[p] as List).cast<Map>();
    final day = hotelLiveDay(
      roomStatus: rows('/api/Hotel/rooms/status-summary'),
      bookings: rows('/api/Hotel/bookings'),
      payments: rows('/api/Hotel/billing/payments'),
      expenses: rows('/api/Hotel/finance/expenses'),
      today: today,
    );
    expect((day.totalRooms, day.occupied, day.available, day.revenue, day.expenses, day.arrivals, day.departures, day.checkedIn), (10, 3, 5, 200, 75, 1, 1, 2));
    final p = hotelAuditPreview(
      roomStatus: rows('/api/Hotel/rooms/status-summary'),
      bookings: rows('/api/Hotel/bookings'),
      payments: rows('/api/Hotel/billing/payments'),
      expenses: rows('/api/Hotel/finance/expenses'),
      housekeeping: rows('/api/Hotel/housekeeping'),
      maintenance: rows('/api/Hotel/maintenance'),
      today: today,
    );
    expect(p.day.revenue, 250, reason: 'the audit counts a voided payment; the closing does not');
    expect((p.outstanding, p.pendingHousekeeping, p.openMaintenance, hotelAuditIssues(p)), (100, 1, 1, 4));
    expect(hotelNiceDate('2026-10-28'), 'Wed, 28 Oct 2026');
    expect(hotelClosingOf({'closingdate': '2026-10-26', 'totalrevenue': 100, 'totalexpenses': 300}).net, -200);
  });

  testWidgets('Daily Closing: today, closed days, Open closing, New closing', (tester) async {
    final api = base();
    await open(tester, HotelDailyClosingScreen(session: await sessionFor(api), company: hotel), size: tall);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('3/10'), findsWidgets);
    expect(find.textContaining('30%', findRichText: true), findsOneWidget);
    expect(find.textContaining('Arrivals / departures 1 / 1', findRichText: true), findsOneWidget);
    expect(find.text('Mon, 26 Oct 2026'), findsOneWidget);
    expect(find.text('Quiet day'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Open closing').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Closing — '), findsOneWidget);
    expect(find.text('ROOMS'), findsOneWidget);
    await tester.tap(filled('Close this day').last);
    await tester.pumpAndSettle();
    expect(find.text('New daily closing'), findsOneWidget);
    expect(find.text('Today as it stands:'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Optional notes about the day'), 'Busy');
    await tester.tap(filled('Close the day'));
    await tester.pumpAndSettle();
    expect(body(api, '/api/Hotel/reports/daily-closings'), {'closingDate': today, 'notes': 'Busy', 'farmId': 'h1'});
    expect(find.textContaining('Day closed successfully'), findsOneWidget);

    await tapText(tester, 'View table format');
    expect(find.text('RevPAR'), findsOneWidget);
  });

  testWidgets('Night Audit: cards, alerts, history detail, Run Audit', (tester) async {
    final api = base()..writeAnswers['/api/Hotel/night-audit'] = {'roomchargesposted': 2};
    await open(tester, HotelNightAuditScreen(session: await sessionFor(api), company: hotel), size: tall);
    expect(find.text('30% occupancy'), findsOneWidget);
    expect(find.text('Issues Found'), findsOneWidget);
    expect(find.text('Pre-Audit Alerts'), findsOneWidget);
    expect(find.textContaining('potential no-shows', findRichText: true), findsOneWidget);
    expect(find.textContaining('pending check-outs for today', findRichText: true), findsOneWidget);

    await tapText(tester, '2026-10-26');
    expect(find.text('Audit Details — 2026-10-26'), findsOneWidget);
    expect(find.text('600.00'), findsOneWidget);
    expect(find.text('Room Charges Posted'), findsOneWidget);
    expect(find.text('Outstanding balances; 3 pending tasks'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Close'));
    await tester.pumpAndSettle();

    await tester.tap(filled('Run Night Audit'));
    await tester.pumpAndSettle();
    expect(find.text('4 issue(s) will be recorded'), findsOneWidget);
    await tester.tap(filled('Run Audit'));
    await tester.pumpAndSettle();
    expect(body(api, '/api/Hotel/night-audit'), {'closingDate': today, 'farmId': 'h1'});
    expect(find.textContaining('2 room charge(s) auto-posted'), findsOneWidget);
  });

  testWidgets('Shift Handover: cards, Acknowledge, New Handover', (tester) async {
    final api = base();
    await open(tester, HotelShiftHandoverScreen(session: await sessionFor(api), company: hotel), size: tall);
    expect(find.text('Night Shift'), findsOneWidget);
    expect(find.text('Fix TV in 204'), findsOneWidget);
    expect(find.textContaining('Cash Balance: 450.00', findRichText: true), findsOneWidget);
    expect(find.textContaining('Acknowledged at'), findsOneWidget);

    await tester.tap(filled('Acknowledge'));
    await tester.pumpAndSettle();
    expect(find.textContaining('shift handover from', findRichText: true), findsOneWidget);
    await tester.tap(filled('Acknowledge').last);
    await tester.pumpAndSettle();
    final ack = api.writes.lastWhere((w) => w.url.path == '/api/Hotel/shift-handovers/5/acknowledge');
    expect((jsonDecode(ack.body) as Map)['farmId'], 'h1');

    await tapText(tester, 'New Handover');
    await choose<String>(tester, 'Night', 'Morning');
    final by = find.descendant(of: find.byType(AlertDialog), matching: find.byType(AppSelect<String>)).at(1);
    await tester.tap(by);
    await tester.pumpAndSettle();
    expect(find.text('Gone Away — Porter'), findsNothing, reason: 'inactive staff are left out');
    await tester.tap(find.text('Ama Owusu — Receptionist').last);
    await tester.pumpAndSettle();
    final to = find.descendant(of: find.byType(AlertDialog), matching: find.byType(AppSelect<String>)).at(2);
    await tester.tap(to);
    await tester.pumpAndSettle();
    expect(find.text('Ama Owusu — Receptionist'), findsOneWidget, reason: 'the outgoing person is not offered again');
    await tester.tap(find.text('Kofi Mensah — Manager').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Cash on hand at end of shift'), '320.5');
    await tester.tap(filled('Submit Handover'));
    await tester.pumpAndSettle();
    final b = body(api, '/api/Hotel/shift-handovers');
    expect((b['shiftType'], b['handoverBy'], b['handoverTo'], b['cashBalance'], b['shiftDate'], b['farmId']), ('Morning', 'Ama Owusu', 'Kofi Mensah', 320.5, today, 'h1'));
  });

  testWidgets('Shift Handover: Handover By is required', (tester) async {
    final api = base();
    await open(tester, HotelShiftHandoverScreen(session: await sessionFor(api), company: hotel), size: tall);
    await tapText(tester, 'New Handover');
    final by = find.descendant(of: find.byType(AlertDialog), matching: find.byType(AppSelect<String>)).at(1);
    await tester.tap(by);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select staff').last);
    await tester.pumpAndSettle();
    await tester.tap(filled('Submit Handover'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Handover by is required'), findsOneWidget);
    expect(api.writes.where((w) => w.url.path == '/api/Hotel/shift-handovers'), isEmpty);
  });
}
