// Hotel → Operations → Rooms & Housekeeping: Rooms, Housekeeping, HK Schedule
// and Room Service, at phone width against a fake API.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/hotel/hotel_rooms_screens.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';

import 'support/harness.dart';

final hotel = Company(farmId: 'h1', name: 'Palm Hotel', type: CompanyType.hotel, role: 'Admin');
const tall = Size(360, 5600);

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

Map body(FakeApi api, String path, [String method = 'POST']) =>
    jsonDecode(api.writes.lastWhere((w) => w.url.path == path && w.method == method).body) as Map;

final _rooms = [
  {'hotelRoomId': 1, 'roomNumber': '102', 'hotelRoomTypeId': 7, 'roomTypeName': 'Deluxe', 'status': 'Occupied', 'floorNumber': 1, 'floorName': 'First Floor',
    'hotelFloorId': 3, 'baseRate': 250, 'bedType': 'King', 'maxOccupancy': 2, 'isActive': true},
  {'hotelRoomId': 2, 'roomNumber': '10', 'hotelRoomTypeId': 8, 'roomTypeName': 'Standard', 'status': 'Available', 'floorNumber': 1, 'floorName': 'First Floor',
    'hotelFloorId': 3, 'baseRate': 120, 'isActive': true},
  {'hotelRoomId': 3, 'roomNumber': '201', 'hotelRoomTypeId': 7, 'roomTypeName': 'Deluxe', 'status': 'Cleaning', 'floorNumber': 2, 'floorName': 'Second Floor',
    'hotelFloorId': 4, 'baseRate': 250, 'isActive': true},
];

void main() {
  test('the four rows open native screens; the room filters; the elapsed time', () {
    for (final h in ['/hotel-rooms', '/hotel-housekeeping', '/hotel-housekeeping-schedule', '/hotel-room-service']) {
      expect(pageScreens.containsKey(h), isTrue, reason: h);
    }
    expect(filterRooms(_rooms, status: 'Occupied').single['roomNumber'], '102');
    expect(filterRooms(_rooms, floor: '2').single['roomNumber'], '201');
    expect(filterRooms(_rooms, type: '8').single['roomNumber'], '10');
    expect(filterRooms(_rooms, search: 'deluxe').length, 2);
    expect(hkScheduleElapsed({'starttime': '2026-10-28T09:00:00', 'endtime': '2026-10-28T09:25:00'}), '25 min');
    expect(hkScheduleElapsed({'starttime': '2026-10-28T09:00:00'}), 'In progress...');
    expect(hkScheduleElapsed({}), '—');
  });

  testWidgets('Rooms: counts, occupancy, the grid by floor, details with a status change, Add Room', (tester) async {
    final api = FakeApi()
      ..gets['/api/Hotel/rooms'] = _rooms
      ..gets['/api/Hotel/setup/room-types'] = [
        {'hotelRoomTypeId': 7, 'name': 'Deluxe', 'baseRate': 250, 'bedType': 'King'},
        {'hotelRoomTypeId': 8, 'name': 'Standard', 'baseRate': 120},
      ]
      ..gets['/api/Hotel/setup/floors'] = [
        {'hotelFloorId': 3, 'floorNumber': 1, 'name': 'First Floor'},
        {'hotelFloorId': 4, 'floorNumber': 2, 'name': 'Second Floor'},
      ]
      ..gets['/api/Hotel/rooms/status-summary'] = [
        {'status': 'Occupied', 'roomCount': 1},
        {'status': 'Available', 'roomCount': 1},
        {'status': 'Cleaning', 'roomCount': 1},
      ];
    await open(tester, HotelRoomsScreen(session: await sessionFor(api), company: hotel), size: tall);
    expect(find.text('33%'), findsOneWidget, reason: '1 of 3 occupied');
    expect(find.text('Second Floor'), findsOneWidget);
    expect(find.text('3 room(s)'), findsOneWidget);
    // Numeric order: 10 before 102.
    expect(tester.getTopLeft(find.text('10')).dy <= tester.getTopLeft(find.text('102')).dy, isTrue);

    await tester.tap(find.text('Cleaning').first);
    await tester.pumpAndSettle();
    expect(find.text('1 room(s)'), findsOneWidget);
    await tester.tap(find.text('Total'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('102'));
    await tester.pumpAndSettle();
    expect(find.text('250.00/night'), findsOneWidget);
    expect(find.textContaining('King', findRichText: true), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Maintenance'));
    await tester.pumpAndSettle();
    final w = api.writes.lastWhere((w) => w.url.path == '/api/Hotel/rooms/1/status');
    expect((w.method, (jsonDecode(w.body) as Map)['status'], w.url.queryParameters['farmId']), ('PATCH', 'Maintenance', 'h1'));

    await tapText(tester, 'Add Room');
    await tester.tap(filled('Create'));
    await tester.pumpAndSettle();
    expect(find.text('Room number is required'), findsOneWidget);
    await enter(tester, 'Room Number *', '301');
    await tester.tap(filled('Create'));
    await tester.pumpAndSettle();
    final b = body(api, '/api/Hotel/rooms');
    expect((b['roomNumber'], b['hotelRoomTypeId'], b['hotelFloorId'], b['isActive']), ('301', 7, 3, true));

    await tester.tap(find.byTooltip('List'));
    await tester.pumpAndSettle();
    expect(find.text('Room 102'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Housekeeping: columns by status, the filter, move a task', (tester) async {
    final api = FakeApi()
      ..gets['/api/Hotel/housekeeping'] = [
        {'hotelHousekeepingTaskId': 11, 'roomNumber': '102', 'taskType': 'Checkout Clean', 'priority': 'Urgent', 'status': 'Pending', 'assignedTo': 'Ama'},
        {'hotelHousekeepingTaskId': 12, 'roomNumber': '201', 'taskType': 'Daily', 'priority': 'Normal', 'status': 'Completed'},
      ];
    await open(tester, HotelHousekeepingScreen(session: await sessionFor(api), company: hotel), size: tall);
    expect(find.text('PENDING (1)'), findsOneWidget);
    expect(find.text('INSPECTED (0)'), findsOneWidget);
    expect(find.text('Assigned: Ama'), findsOneWidget);
    await choose<String>(tester, 'All', 'Completed');
    expect(find.text('PENDING (1)'), findsNothing);
    expect(find.text('COMPLETED (1)'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Inspected'));
    await tester.pumpAndSettle();
    final w = api.writes.last;
    expect((w.url.path, w.method, (jsonDecode(w.body) as Map)['status']), ('/api/Hotel/housekeeping/12/status', 'PATCH', 'Inspected'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('HK Schedule: the date, counts, Schedule All Occupied, Start / Skip / Complete, Add', (tester) async {
    final api = FakeApi()
      ..gets['/api/Hotel/housekeeping-schedule'] = [
        {'hotelschedid': 21, 'roomnumber': '102', 'floorname': 'First Floor', 'tasktype': 'Daily Cleaning', 'priority': 'High', 'status': 'Scheduled'},
        {'hotelschedid': 22, 'roomnumber': '201', 'tasktype': 'Turndown', 'priority': 'Normal', 'status': 'InProgress', 'starttime': '2026-10-28T09:00:00'},
      ]
      ..gets['/api/Hotel/rooms'] = _rooms
      ..gets['/api/Hotel/setup/hk-task-types'] = [
        {'description': 'Daily Cleaning'},
        {'description': 'Turndown'},
      ]
      ..gets['/api/Hotel/staff'] = [
        {'hotelstaffid': 3, 'firstname': 'Ama', 'lastname': 'Owusu', 'role': 'Attendant', 'department': 'Housekeeping', 'isactive': true},
        {'hotelstaffid': 4, 'firstname': 'Kojo', 'lastname': 'Asare', 'role': 'Chef', 'department': 'Kitchen', 'isactive': true},
      ]
      ..writeAnswers['/api/Hotel/housekeeping-schedule/bulk'] = {'created': 2, 'totalRooms': 3};
    await open(tester, HotelHKScheduleScreen(session: await sessionFor(api), company: hotel), size: tall);
    final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    expect(api.requests.firstWhere((r) => r.url.path == '/api/Hotel/housekeeping-schedule').url.queryParameters['date'], today);
    expect(find.text('2 entries for $today'), findsOneWidget);
    expect(find.text('In progress...'), findsOneWidget);

    await tapText(tester, 'Schedule All Occupied');
    expect(body(api, '/api/Hotel/housekeeping-schedule/bulk'), {'farmId': 'h1', 'scheduleDate': today, 'taskType': 'Daily Cleaning'});

    await tester.tap(find.byTooltip('Skip'));
    await tester.pumpAndSettle();
    expect((jsonDecode(api.writes.last.body) as Map)['status'], 'Skipped');
    await tester.tap(find.byTooltip('Complete'));
    await tester.pumpAndSettle();
    expect(api.writes.last.url.path, '/api/Hotel/housekeeping-schedule/22/status');

    await tapText(tester, 'Add');
    await tester.tap(filled('Schedule'));
    await tester.pumpAndSettle();
    expect(find.text('Select a room'), findsOneWidget);
    await choose<int>(tester, '-- Select --', 'Room 201 (Cleaning)');
    await choose<String>(tester, 'Select task', 'Turndown');
    await choose<String>(tester, 'Unassigned', 'Ama Owusu — Attendant (Housekeeping)');
    expect(find.textContaining('Kojo'), findsNothing, reason: 'only housekeeping staff');
    await tester.tap(filled('Schedule'));
    await tester.pumpAndSettle();
    final b = body(api, '/api/Hotel/housekeeping-schedule');
    expect((b['hotelRoomId'], b['taskType'], b['assignedTo'], b['scheduleDate']), (3, 'Turndown', 'Ama Owusu', today));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Room Service: the orders with their room and amount', (tester) async {
    final api = FakeApi()
      ..gets['/api/Hotel/restaurant/orders'] = [
        {'hotelrestaurantorderid': 31, 'servername': 'Ama', 'status': 'Delivered', 'totalamount': 42.5, 'ordertime': '2026-10-28T08:00:00Z'},
      ];
    await open(tester, HotelRoomServiceScreen(session: await sessionFor(api), company: hotel), size: tall);
    expect(find.text('Room Service Orders'), findsOneWidget);
    expect(find.text('(1)'), findsOneWidget);
    expect(find.text('Room'), findsWidgets);
    expect(find.text('Delivered'), findsOneWidget);
    expect(find.text('42.50'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
