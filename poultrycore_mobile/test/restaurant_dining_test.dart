// Restaurant → Dining (2026-10-21): Restaurant Areas and Reservations &
// Waitlist, against a fake API at 360 px.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_floor_plan_screen.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_reservations_screen.dart';

import 'support/harness.dart';

final rest = Company(farmId: 'farm-1', name: 'Rose Bistro', type: CompanyType.restaurant, role: 'Admin');
const tall = Size(360, 3200);

Finder filled(String t) => find.widgetWithText(FilledButton, t);

Future<void> enterUnder(WidgetTester tester, String label, String text) async {
  final l = find.byWidgetPredicate((w) => w is Text && RegExp('^${RegExp.escape(label)}' r'( \*)?$').hasMatch(w.data ?? w.textSpan?.toPlainText() ?? ''));
  final box = find.descendant(of: find.ancestor(of: l.last, matching: find.byType(Column)).first, matching: find.byType(EditableText));
  await tester.enterText(box.first, text);
  await tester.pump();
}

/// Opens the dropdown showing [shown] (its last match) and picks [option].
Future<void> pickLast(WidgetTester tester, String shown, String option) async {
  await tester.ensureVisible(find.text(shown).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(shown).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

void main() {
  test('routes and the day stepper', () {
    for (final h in ['/restaurant-floor-plan', '/restaurant-reservations']) {
      expect(pageScreens.containsKey(h), isTrue, reason: h);
    }
    expect(shiftDay('2026-03-01', -1), '2026-02-28');
    expect(shiftDay('2026-12-31', 1), '2027-01-01');
  });

  testWidgets('Restaurant Areas: legend, area tabs, quick status, add area (duplicate check), add and edit a table', (tester) async {
    final api = FakeApi()
      ..gets['/api/Restaurant/floor/floors'] = [
        {'floorId': 1, 'name': 'Ground Floor', 'floorNumber': 0, 'tableCount': 2, 'isActive': true},
        {'floorId': 2, 'name': 'Patio', 'floorNumber': 1, 'tableCount': 1, 'isActive': true},
      ]
      ..gets['/api/Restaurant/floor/tables'] = [
        {'tableId': 10, 'floorId': 1, 'tableNumber': 'A1', 'tableName': 'Window', 'capacity': 4, 'shape': 'Round', 'status': 'Available', 'isActive': true},
        {'tableId': 11, 'floorId': 1, 'tableNumber': 'A2', 'capacity': 2, 'shape': 'Square', 'status': 'NeedsCleaning', 'isActive': true},
        {'tableId': 12, 'floorId': 2, 'tableNumber': 'P1', 'capacity': 6, 'shape': 'Long', 'status': 'Occupied', 'isActive': true},
      ];
    await open(tester, RestaurantFloorPlanScreen(session: await sessionFor(api), company: rest), size: tall);
    expect(find.textContaining('3 tables across 2 areas'), findsOneWidget);
    expect(find.text('Needs Cleaning: ', findRichText: true), findsNothing);
    expect(find.textContaining('Needs Cleaning: 1', findRichText: true), findsOneWidget);
    expect(find.text('A1'), findsOneWidget);
    expect(find.text('P1'), findsNothing, reason: 'only the open area');

    // Needs Cleaning offers Free, Reserve and Clean; Clean frees it.
    await tester.tap(find.text('Clean'));
    await tester.pumpAndSettle();
    final w = api.writes.last;
    expect((w.method, w.url.path, w.url.queryParameters['status']), ('PATCH', '/api/Restaurant/floor/tables/11/status', 'Available'));

    // The Patio tab.
    await tester.tap(find.text('Patio'));
    await tester.pumpAndSettle();
    expect(find.text('P1'), findsOneWidget);
    expect(find.text('Reserve'), findsNothing, reason: 'an occupied table cannot be reserved');

    // Add Area refuses a duplicate name, then saves a new one.
    await tester.tap(find.text('Add Area'));
    await tester.pumpAndSettle();
    await enterUnder(tester, 'Area Name', 'patio ');
    await tester.tap(filled('Create Area'));
    await tester.pumpAndSettle();
    expect(find.textContaining('An area named "patio " already exists.', findRichText: true), findsOneWidget);
    await enterUnder(tester, 'Area Name', 'Rooftop');
    await enterUnder(tester, 'Description', 'Upstairs');
    await tester.tap(filled('Create Area'));
    await tester.pumpAndSettle();
    final f = api.lastBody('/api/Restaurant/floor/floors');
    expect((f['name'], f['floorNumber'], f['description'], f['isActive'], f['farmId']), ('Rooftop', 2, 'Upstairs', true, 'farm-1'));

    // Add Table lands in the open area.
    await tester.tap(filled('Add Table'));
    await tester.pumpAndSettle();
    await tester.tap(filled('Add Table').last);
    await tester.pumpAndSettle();
    expect(find.text('Number required'), findsOneWidget);
    await enterUnder(tester, 'Table Number', 'P2');
    await enterUnder(tester, 'Capacity', '8');
    await pickLast(tester, 'Square', 'Booth');
    await tester.tap(filled('Add Table').last);
    await tester.pumpAndSettle();
    final t = api.lastBody('/api/Restaurant/floor/tables');
    expect((t['tableNumber'], t['capacity'], t['shape'], t['floorId'], t['farmId']), ('P2', 8, 'Booth', 2, 'farm-1'));

    // Edit moves P1 to Unassigned; delete the area.
    await tester.tap(find.byTooltip('Edit table'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Table'), findsOneWidget);
    await pickLast(tester, 'Patio', 'Unassigned');
    await tester.tap(filled('Update'));
    await tester.pumpAndSettle();
    final u = api.lastBody('/api/Restaurant/floor/tables/12', 'PUT');
    expect((u['tableNumber'], u['floorId'], u['capacity'], u['shape']), ('P1', null, 6, 'Long'));
    await tester.tap(find.byTooltip('Delete area'));
    await tester.pumpAndSettle();
    expect(api.writes.any((w) => w.method == 'DELETE' && w.url.path == '/api/Restaurant/floor/floors/2'), isTrue);
  });

  testWidgets('Reservations: the day, status steps, a new VIP booking with an occasion and a found table; waitlist', (tester) async {
    final api = FakeApi()
      ..gets['/api/Restaurant/floor/tables'] = [
        {'tableId': 10, 'tableNumber': 'A1', 'capacity': 4, 'status': 'Available'},
        {'tableId': 11, 'tableNumber': 'A2', 'capacity': 2, 'status': 'Occupied'},
      ]
      ..gets['/api/Restaurant/reservations'] = [
        {'reservationId': 5, 'reservationDate': '2026-10-21T00:00:00', 'reservationTime': '18:30', 'endTime': '20:00', 'partySize': 3,
          'guestName': 'Akosua', 'guestPhone': '055', 'status': 'Pending', 'isVip': true, 'occasion': 'Birthday', 'specialRequests': 'High chair',
          'tableId': 10, 'tableNumber': 'A1'},
      ]
      ..gets['/api/Restaurant/reservations/stats'] = {'totalCount': 1, 'confirmedCount': 0, 'seatedCount': 0, 'totalCovers': 3, 'noShowCount': 1}
      ..gets['/api/Restaurant/reservations/waitlist'] = [
        {'waitlistId': 7, 'guestName': 'Yaw', 'partySize': 2, 'status': 'Waiting', 'actualWaitMins': 12.7, 'quotedWaitMins': 15},
        {'waitlistId': 8, 'guestName': 'Gone', 'partySize': 2, 'status': 'Seated'},
      ]
      ..gets['/api/Restaurant/reservations/waitlist/stats'] = {'waitingCount': 1, 'notifiedCount': 0, 'avgWaitMins': 12.7, 'longestWaitMins': 40}
      ..gets['/api/Restaurant/reservations/auto-assign-table'] = [
        {'tableId': 10, 'tableNumber': 'A1', 'capacity': 4},
      ]
      ..gets['/api/Restaurant/custom-options'] = [];
    await open(tester, RestaurantReservationsScreen(session: await sessionFor(api), company: rest), size: tall);
    expect(find.text('Akosua'), findsOneWidget);
    expect(find.text('★ VIP'), findsOneWidget);
    expect(find.text('to 20:00'), findsOneWidget);
    expect(find.text('Table A1'), findsOneWidget);
    expect(find.text('No-Show', findRichText: true), findsWidgets);

    // The next day asks the server for it.
    await tester.tap(find.byTooltip('Next day'));
    await tester.pumpAndSettle();
    final dates = [for (final r in api.requests) if (r.url.path == '/api/Restaurant/reservations') r.url.queryParameters['date']];
    expect(dates.toSet().length, 2);

    // Pending → Confirm.
    await tester.tap(filled('Confirm'));
    await tester.pumpAndSettle();
    expect(api.lastBody('/api/Restaurant/reservations/5/status', 'PATCH'), {'status': 'Confirmed'});

    // New reservation: name required, then a VIP booking with an occasion and a found table.
    await tester.tap(filled('New Reservation'));
    await tester.pumpAndSettle();
    await tester.tap(filled('Create Reservation'));
    await tester.pumpAndSettle();
    expect(find.text('Guest name required'), findsOneWidget);
    await enterUnder(tester, 'Guest Name', 'Kwame');
    await enterUnder(tester, 'Party Size', '4');
    await pickLast(tester, 'None', 'Anniversary');
    await tester.tap(find.text('Find'));
    await tester.pumpAndSettle();
    final q = api.requests.lastWhere((r) => r.url.path == '/api/Restaurant/reservations/auto-assign-table').url.queryParameters;
    expect((q['partySize'], q['time']), ('4', '19:00'));
    await tester.tap(find.text('TA1 (4)'));
    await tester.pumpAndSettle();
    expect(find.text('Table A1 (4)'), findsOneWidget);
    await tester.tap(find.text('VIP Guest'));
    await tester.pump();
    await tester.tap(filled('Create Reservation'));
    await tester.pumpAndSettle();
    final b = api.lastBody('/api/Restaurant/reservations');
    expect((b['guestName'], b['partySize'], b['occasion'], b['tableId'], b['tableNumber'], b['isVip'], b['source'], b['reservationTime'], b['farmId']),
        ('Kwame', 4, 'Anniversary', 10, 'A1', true, 'Phone', '19:00', 'farm-1'));

    // Edit keeps the booking's fields.
    await tester.tap(find.byTooltip('Edit reservation'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Reservation'), findsOneWidget);
    await tester.tap(filled('Update'));
    await tester.pumpAndSettle();
    final e = api.lastBody('/api/Restaurant/reservations/5', 'PUT');
    expect((e['guestName'], e['reservationDate'], e['occasion'], e['isVip'], e['specialRequests']), ('Akosua', '2026-10-21', 'Birthday', true, 'High chair'));

    // Waitlist: only waiting / notified guests; notify, seat at a free table, add.
    await tester.tap(find.text('Waitlist'));
    await tester.pumpAndSettle();
    expect(find.text('Yaw'), findsOneWidget);
    expect(find.text('Gone'), findsNothing);
    expect(find.text('12m'), findsOneWidget);
    expect(find.text('(quoted 15m)'), findsOneWidget);
    expect(find.text('Max: 40m'), findsOneWidget);
    await tester.tap(filled('Notify'));
    await tester.pumpAndSettle();
    expect(api.lastBody('/api/Restaurant/reservations/waitlist/7/status', 'PATCH'), {'status': 'Notified'});
    await tester.tap(find.byWidgetPredicate((w) => w.runtimeType.toString().startsWith('AppSelect<int>')).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Table A1').last);
    await tester.pumpAndSettle();
    expect(api.lastBody('/api/Restaurant/reservations/waitlist/7/status', 'PATCH'), {'status': 'Seated', 'tableId': 10, 'tableNumber': 'A1'});
    await tester.tap(filled('Add to Waitlist'));
    await tester.pumpAndSettle();
    await enterUnder(tester, 'Guest Name', 'Esi');
    await enterUnder(tester, 'Est. Wait (min)', '25');
    await tester.tap(filled('Add to Waitlist').last);
    await tester.pumpAndSettle();
    final wl = api.lastBody('/api/Restaurant/reservations/waitlist');
    expect((wl['guestName'], wl['partySize'], wl['estimatedWaitMins'], wl['farmId']), ('Esi', 2, 25, 'farm-1'));
  });
}
