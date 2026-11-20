// Hotel → Operations → Guest Services: Guest Log, Requests and Lost & Found,
// at phone width against a fake API.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/hotel/hotel_guest_service_screens.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';

import 'support/harness.dart';

final hotel = Company(farmId: 'h1', name: 'Palm Hotel', type: CompanyType.hotel, role: 'Admin');
const tall = Size(360, 4600);

Finder filled(String t) => find.widgetWithText(FilledButton, t);

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).first);
  await tester.pumpAndSettle();
}

Future<void> choose<T>(WidgetTester tester, String shown, String option) async {
  final picker = find.ancestor(of: find.text(shown), matching: find.byType(AppSelect<T>)).first;
  await tester.ensureVisible(picker);
  await tester.pumpAndSettle();
  await tester.tap(picker);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

/// [enter] for a label that also shows on the page behind the dialog.
Future<void> enterLast(WidgetTester tester, String label, String text) async {
  final field = find.descendant(
    of: find.ancestor(of: find.text(label).last, matching: find.byType(Column)).first,
    matching: find.byType(TextFormField),
  );
  await tester.enterText(field.first, text);
  await tester.pump();
}

Map body(FakeApi api, String path, [String method = 'POST']) =>
    jsonDecode(api.writes.lastWhere((w) => w.url.path == path && w.method == method).body) as Map;

final _staff = [
  {'hotelstaffid': 3, 'firstname': 'Ama', 'lastname': 'Owusu', 'role': 'Concierge', 'department': 'Front Office', 'isactive': true},
  {'hotelstaffid': 4, 'firstname': 'Gone', 'lastname': 'Away', 'role': 'Porter', 'isactive': false},
];

void main() {
  test('the three rows open native screens; the filters', () {
    for (final h in ['/hotel-communications', '/hotel-guest-requests', '/hotel-lost-found']) {
      expect(pageScreens.containsKey(h), isTrue, reason: h);
    }
    final log = [
      {'firstname': 'Kofi', 'lastname': 'Mensah', 'subject': 'Noise', 'status': 'Open', 'roomnumber': '104'},
      {'firstname': 'Esi', 'lastname': 'B', 'message': 'Late checkout', 'status': 'Resolved'},
    ];
    expect(filterGuestLog(log, status: 'Open').length, 1);
    expect(filterGuestLog(log, search: 'checkout').single['firstname'], 'Esi');
    expect(filterGuestLog(log, search: '104').single['firstname'], 'Kofi');
    expect(filterGuestRequests([
      {'requesttype': 'Towels', 'status': 'Pending'},
      {'requesttype': 'Taxi', 'status': 'Completed'},
    ], search: 'taxi').single['status'], 'Completed');
    expect(filterLostFound([
      {'itemdescription': 'Phone', 'status': 'Found'},
      {'itemdescription': 'Ring', 'category': 'Jewelry', 'status': 'Stored'},
    ], status: 'Stored').single['itemdescription'], 'Ring');
  });

  testWidgets('Guest Log: counts, filters, status steps, Log Entry', (tester) async {
    final api = FakeApi()
      ..gets['/api/Hotel/communications'] = [
        {'hotelguestcommid': 1, 'firstname': 'Kofi', 'lastname': 'Mensah', 'roomnumber': '104', 'commtype': 'Complaint', 'subject': 'Noise',
          'priority': 'High', 'status': 'Open', 'createdat': '2026-10-26T09:00:00'},
        {'hotelguestcommid': 2, 'firstname': 'Esi', 'lastname': 'Boateng', 'commtype': 'Note', 'message': 'Prefers a quiet room',
          'priority': 'Normal', 'status': 'Resolved', 'createdat': '2026-10-25T09:00:00'},
      ]
      ..gets['/api/Hotel/guests'] = [
        {'hotelGuestId': 7, 'firstName': 'Kofi', 'lastName': 'Mensah'},
        {'hotelGuestId': 8, 'firstName': 'Esi', 'lastName': 'Boateng'},
      ]
      ..gets['/api/Hotel/setup/comm-subjects'] = [
        {'description': 'Noise'},
      ]
      ..gets['/api/Hotel/staff'] = _staff;
    await open(tester, HotelGuestLogScreen(session: await sessionFor(api), company: hotel), size: tall);
    expect(find.text('Guest Communication Log'), findsOneWidget);
    expect(find.text('Kofi Mensah'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Open'));
    await tester.pumpAndSettle();
    expect(find.text('Esi Boateng'), findsNothing);

    await tester.tap(find.byTooltip('Start'));
    await tester.pumpAndSettle();
    final w = api.writes.lastWhere((w) => w.url.path == '/api/Hotel/communications/1/status');
    expect(w.method, 'PATCH');
    expect(jsonDecode(w.body), {'farmId': 'h1', 'status': 'InProgress'});

    await tapText(tester, 'Log Entry');
    await choose<String>(tester, 'Normal', 'Urgent');
    await choose<String>(tester, 'Unassigned', 'Ama Owusu — Concierge');
    expect(find.textContaining('Gone Away'), findsNothing, reason: 'inactive staff are left out');
    await tester.tap(filled('Log'));
    await tester.pumpAndSettle();
    expect(find.text('Message required'), findsOneWidget);
    await enter(tester, 'Message *', 'Asked for extra pillows');
    await tester.tap(filled('Log'));
    await tester.pumpAndSettle();
    final b = body(api, '/api/Hotel/communications');
    expect((b['hotelGuestId'], b['commType'], b['priority'], b['assignedTo'], b['message'], b['farmId']),
        (7, 'Note', 'Urgent', 'Ama Owusu', 'Asked for extra pillows', 'h1'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Requests: the cards filter, the details, a new request with booking and staff', (tester) async {
    final api = FakeApi()
      ..gets['/api/Hotel/guest-requests'] = [
        {'hotelguestrequestid': 5, 'firstname': 'Kofi', 'lastname': 'Mensah', 'roomnumber': '104', 'requesttype': 'Towels', 'status': 'Pending',
          'description': 'Two more towels', 'bookingref': 'BK-9', 'createdat': '2026-10-26T09:00:00'},
        {'hotelguestrequestid': 6, 'requesttype': 'Taxi', 'status': 'Completed', 'createdat': '2026-10-25T09:00:00'},
      ]
      ..gets['/api/Hotel/bookings'] = [
        {'hotelBookingId': 9, 'status': 'CheckedIn', 'hotelRoomId': 40, 'roomNumber': '104', 'guestFirstName': 'Kofi', 'guestLastName': 'Mensah'},
        {'hotelBookingId': 10, 'status': 'CheckedOut', 'roomNumber': '105', 'guestFirstName': 'Old', 'guestLastName': 'Guest'},
      ]
      ..gets['/api/Hotel/rooms'] = [
        {'hotelRoomId': 40, 'roomNumber': '104'},
      ]
      ..gets['/api/Hotel/setup/request-types'] = [
        {'description': 'Towels'},
        {'description': 'Wake-up call'},
      ]
      ..gets['/api/Hotel/staff'] = _staff;
    await open(tester, HotelGuestRequestsScreen(session: await sessionFor(api), company: hotel), size: tall);
    expect(find.text('2 total requests'), findsOneWidget);
    await tapText(tester, 'Completed');
    expect(find.text('Kofi Mensah'), findsNothing);
    await tapText(tester, 'All');

    await tapText(tester, 'Details');
    expect(find.text('BK-9'), findsOneWidget);
    expect(find.text('Two more towels'), findsWidgets);
    await tester.tap(filled('Start'));
    await tester.pumpAndSettle();
    expect((jsonDecode(api.writes.last.body) as Map)['status'], 'InProgress');

    await tapText(tester, 'New Request');
    expect(find.text('Old Guest - 105'), findsNothing);
    await choose<int>(tester, 'None', 'Kofi Mensah - 104');
    expect(find.text('Room 104'), findsOneWidget, reason: 'the booking fills the room');
    await tester.tap(filled('Create'));
    await tester.pumpAndSettle();
    expect(find.text('Select a request type'), findsWidgets);
    await choose<String>(tester, 'Select type', 'Wake-up call');
    await choose<String>(tester, 'Unassigned', 'Other (type name)');
    await enter(tester, 'Staff Name', 'Night porter');
    await tester.tap(filled('Create'));
    await tester.pumpAndSettle();
    final b = body(api, '/api/Hotel/guest-requests');
    expect((b['hotelBookingId'], b['hotelRoomId'], b['requestType'], b['assignedTo'], b['scheduledTime']), (9, 40, 'Wake-up call', 'Night porter', ''));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Lost & Found: actions by status, Claim with a name, Log Item', (tester) async {
    final api = FakeApi()
      ..gets['/api/Hotel/lost-and-found'] = [
        {'hotellostandfoundid': 1, 'itemdescription': 'Black phone', 'roomnumber': '104', 'category': 'Electronics', 'status': 'Found', 'founddate': '2026-10-26'},
        {'hotellostandfoundid': 2, 'itemdescription': 'Gold ring', 'category': 'Jewelry', 'status': 'Stored', 'founddate': '2026-10-20'},
      ]
      ..gets['/api/Hotel/rooms'] = [
        {'hotelRoomId': 40, 'roomNumber': '104'},
      ];
    await open(tester, HotelLostFoundScreen(session: await sessionFor(api), company: hotel), size: tall);
    expect(find.text('Black phone'), findsOneWidget);
    expect(find.text('Store'), findsOneWidget);
    expect(find.text('Dispose'), findsOneWidget);
    expect(find.text('Claim'), findsNWidgets(2));

    await tapText(tester, 'Claim');
    expect(find.text('Mark Item as Claimed'), findsOneWidget);
    await tester.tap(filled('Confirm Claimed'));
    await tester.pumpAndSettle();
    expect(find.text('Enter name'), findsOneWidget);
    await enter(tester, 'Claimed By *', 'Kofi Mensah');
    await tester.tap(filled('Confirm Claimed'));
    await tester.pumpAndSettle();
    expect(jsonDecode(api.writes.last.body), {'farmId': 'h1', 'status': 'Claimed', 'claimedBy': 'Kofi Mensah'});
    expect(api.writes.last.url.path, '/api/Hotel/lost-and-found/1/status');

    await tapText(tester, 'Log Item');
    await enter(tester, 'Item Description *', 'Blue umbrella');
    await choose<int>(tester, 'None', 'Room 104');
    await enterLast(tester, 'Found By', 'Housekeeping');
    await tester.tap(filled('Log Item').last);
    await tester.pumpAndSettle();
    final b = body(api, '/api/Hotel/lost-and-found');
    expect((b['itemDescription'], b['hotelRoomId'], b['foundBy'], (b['foundDate'] as String).length), ('Blue umbrella', 40, 'Housekeeping', 10));
    expect(tester.takeException(), isNull);
  });
}
