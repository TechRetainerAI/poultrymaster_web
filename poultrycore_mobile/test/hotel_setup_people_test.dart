// Hotel → Setup → Hotel (Company Setup, Hotel Setup) and People (Staff, Users
// & Permissions), at phone width against a fake API.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/hotel/hotel_company_setup_screen.dart';
import 'package:poultrycore_mobile/pages/hotel/hotel_setup_screen.dart';
import 'package:poultrycore_mobile/pages/hotel/hotel_staff_screen.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/shared/employee_form_screen.dart';
import 'package:poultrycore_mobile/pages/shared/staff_employee_link.dart';

import 'support/harness.dart';

final hotel = Company(farmId: 'h1', name: 'Palm Hotel', type: CompanyType.hotel, role: 'Admin');

/// Phone width, tall enough that a whole tab is built.
const tallPhone = Size(360, 2600);

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

Future<void> tapTip(WidgetTester tester, String tip) async {
  await tester.ensureVisible(find.byTooltip(tip).first);
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip(tip).first);
  await tester.pumpAndSettle();
}

/// [pick] for a dropdown inside the open dialog.
Future<void> pickIn(WidgetTester tester, String shown, String option) async {
  final f = find.descendant(of: find.byType(AlertDialog), matching: find.text(shown)).first;
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Map<String, dynamic> lastWrite(FakeApi api, String path, String method) =>
    jsonDecode(api.writes.lastWhere((w) => w.url.path == path && w.method == method).body) as Map<String, dynamic>;

FakeApi setupApi() => FakeApi()
  ..gets['/api/Hotel/setup/room-categories'] = [
    {'hotelRoomCategoryId': 1, 'code': 'STD', 'description': 'Standard'},
    {'hotelRoomCategoryId': 2, 'code': 'DLX', 'description': 'Deluxe'},
  ]
  ..gets['/api/Hotel/setup/bed-types'] = [
    {'hotelBedTypeId': 5, 'description': 'Queen'},
  ]
  ..gets['/api/Hotel/setup/room-types'] = [
    {'hotelRoomTypeId': 10, 'name': 'Deluxe Double', 'baseRate': 200, 'maxOccupancy': 2, 'hotelRoomCategoryId': 2, 'categoryName': 'Deluxe',
      'hotelBedTypeId': 5, 'bedTypeName': 'Queen'},
    {'hotelRoomTypeId': 11, 'name': 'Standard Single', 'baseRate': 120, 'maxOccupancy': 1, 'hotelRoomCategoryId': 1, 'categoryName': 'Standard'},
  ]
  ..gets['/api/Hotel/setup/floors'] = [
    {'hotelFloorId': 1, 'floorNumber': 1, 'name': 'Ground Floor'},
    {'hotelFloorId': 2, 'floorNumber': 2, 'name': 'First Floor'},
  ]
  ..gets['/api/Hotel/setup/amenities'] = [
    {'hotelAmenityId': 3, 'name': 'WiFi', 'category': 'Technology'},
    {'hotelAmenityId': 4, 'name': 'Air Conditioning', 'category': 'Comfort'},
  ]
  ..gets['/api/Hotel/rooms'] = [
    {'hotelRoomId': 100, 'roomNumber': '101', 'hotelRoomTypeId': 10, 'roomTypeName': 'Deluxe Double', 'hotelFloorId': 1, 'floorName': 'Ground Floor',
      'status': 'Available', 'baseRate': 200, 'isActive': true},
    {'hotelRoomId': 101, 'roomNumber': '201', 'hotelRoomTypeId': 11, 'roomTypeName': 'Standard Single', 'hotelFloorId': 2, 'floorName': 'First Floor',
      'status': 'Cleaning', 'baseRate': 120, 'isActive': true},
  ]
  ..gets['/api/Hotel/room-rates'] = [
    {'hotelRoomRateId': 7, 'hotelRoomTypeId': 10, 'roomTypeName': 'Deluxe Double', 'rateName': 'Christmas', 'rate': 260,
      'startDate': '2020-12-20T00:00:00', 'endDate': '2020-12-31T00:00:00', 'isWeekend': false},
  ];

FakeApi staffApi() => FakeApi()
  ..gets['/api/Hotel/staff'] = [
    {'hotelStaffId': 1, 'firstName': 'Ama', 'lastName': 'Mensah', 'role': 'Receptionist', 'department': 'Front Desk', 'phone': '0241234567',
      'salaryAmount': 1500, 'hireDate': '2026-01-05T00:00:00', 'isActive': true},
    {'hotelStaffId': 2, 'firstName': 'Kofi', 'lastName': 'Boateng', 'role': 'Cleaner', 'department': 'Housekeeping', 'phone': '',
      'salaryAmount': 900, 'isActive': false},
  ]
  ..gets['/api/Hotel/employee-loans/staff-report'] = [
    {'hotelStaffId': 1, 'outstanding': 250, 'activeLoans': 1},
  ]
  ..gets['/api/StaffUserLink'] = [
    {'staffId': 2, 'userId': 'u-2'},
  ];

void main() {
  test('the four Setup → Hotel / People rows open native screens; Hotel staff link to employees', () {
    for (final h in ['/hotel-company-setup', '/hotel-setup', '/hotel-staff']) {
      expect(pageScreens.containsKey(h), isTrue, reason: h);
    }
    expect(staffPagePath(CompanyType.hotel), '/hotel-staff');
  });

  group('Company Setup', () {
    testWidgets('loads the profile, saves it, and moves the company currency', (tester) async {
      final api = FakeApi()
        ..gets['/api/Hotel/setup/profile'] = {
          'hotelProfileId': 1, 'hotelName': 'Golden Palm', 'starRating': 4, 'city': 'Accra', 'checkInTime': '14:00', 'checkOutTime': '11:00',
          'defaultCurrency': 'GHS', 'taxRate': 12.5, 'serviceChargeRate': 10,
        }
        ..gets['/api/Water/farm-settings'] = {'currencyCode': 'USD', 'showCurrencySymbol': true};
      await open(tester, HotelCompanySetupScreen(session: await sessionFor(api), company: hotel), size: tallPhone);
      expect(find.text('Hotel Company Setup'), findsOneWidget);
      expect(find.text('Set up'), findsOneWidget);
      for (final t in ['Basic Information', 'Contact & Location', 'Operations', 'Currency & Charges', '11:00']) {
        expect(find.text(t), findsWidgets, reason: t);
      }
      await enter(tester, 'Hotel Name *', 'Golden Palm Hotel');
      await tapText(tester, 'Save Changes');
      final body = lastWrite(api, '/api/Hotel/setup/profile', 'POST');
      expect((body['hotelName'], body['starRating'], body['checkOutTime'], body['taxRate'], body['farmId']),
          ('Golden Palm Hotel', 4, '11:00', 12.5, 'h1'));
      expect(lastWrite(api, '/api/Water/farm-settings/currency', 'PUT')['currencyCode'], 'GHS');
      expect(find.textContaining('Profile saved'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a new hotel: no "Set up", and the name is required', (tester) async {
      final api = FakeApi()..statuses['/api/Hotel/setup/profile'] = 404;
      await open(tester, HotelCompanySetupScreen(session: await sessionFor(api), company: hotel), size: tallPhone);
      expect(find.text('Set up'), findsNothing);
      expect(find.text('14:00'), findsOneWidget);
      await tapText(tester, 'Save Changes');
      expect(find.textContaining('Hotel name is required'), findsOneWidget);
      expect(api.writes, isEmpty);
    });
  });

  group('Hotel Setup', () {
    testWidgets('tabs with counts; Floors add and delete', (tester) async {
      final api = setupApi();
      await open(tester, HotelSetupScreen(session: await sessionFor(api), company: hotel), size: tallPhone);
      expect(find.text('Work left to right — each step feeds the next'), findsOneWidget);
      for (final t in ['Floors', 'Room Types', 'Amenities', 'Rooms', 'Rates']) {
        expect(find.text(t), findsWidgets, reason: t);
      }
      expect(find.text('Ground Floor'), findsOneWidget);
      expect(find.text('2 of 2'), findsOneWidget);

      await tapText(tester, 'Add');
      expect(find.text('Add Floor'), findsOneWidget);
      expect(find.text('Floor 3'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();
      expect(lastWrite(api, '/api/Hotel/setup/floors', 'POST'), {'floorNumber': 3, 'name': 'Floor 3', 'farmId': 'h1'});

      await tapTip(tester, 'Delete');
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(api.writes.any((w) => w.method == 'DELETE' && w.url.path == '/api/Hotel/setup/floors/1'), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Room Types: filter by category, edit saves the picks', (tester) async {
      final api = setupApi();
      await open(tester, HotelSetupScreen(session: await sessionFor(api), company: hotel), size: tallPhone);
      await tapText(tester, 'Room Types');
      expect(find.text('Deluxe Double'), findsOneWidget);
      await pick(tester, 'All categories', 'Standard');
      expect(find.text('Deluxe Double'), findsNothing);
      expect(find.text('1 of 2'), findsOneWidget);
      await pick(tester, 'Standard', 'All categories');

      await tapTip(tester, 'Edit');
      expect(find.text('Edit Room Type'), findsOneWidget);
      await enter(tester, 'Base Rate', '220');
      await tester.tap(find.widgetWithText(FilledButton, 'Update'));
      await tester.pumpAndSettle();
      final b = lastWrite(api, '/api/Hotel/setup/room-types/10', 'PUT');
      expect((b['baseRate'], b['hotelRoomCategoryId'], b['hotelBedTypeId']), (220.0, 2, 5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Amenities and Rooms: add with the web defaults; status filter', (tester) async {
      final api = setupApi();
      await open(tester, HotelSetupScreen(session: await sessionFor(api), company: hotel), size: tallPhone);
      await tapText(tester, 'Amenities');
      expect(find.text('Technology'), findsWidgets);
      await tapText(tester, 'Add');
      await enter(tester, 'Name', 'Minibar');
      await enter(tester, 'Category', 'Comfort');
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();
      expect(lastWrite(api, '/api/Hotel/setup/amenities', 'POST'), {'name': 'Minibar', 'category': 'Comfort', 'farmId': 'h1'});

      await tapText(tester, 'Rooms');
      expect(find.text('Cleaning'), findsWidgets);
      await pick(tester, 'All statuses', 'Available');
      expect(find.text('201'), findsNothing);
      await tapText(tester, 'Add Room');
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Room number is required'), findsOneWidget);
      await enter(tester, 'Room Number *', '301');
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();
      final r = lastWrite(api, '/api/Hotel/rooms', 'POST');
      expect((r['roomNumber'], r['hotelRoomTypeId'], r['hotelFloorId'], r['isActive']), ('301', 10, 1, true));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Rates: Expired badge, required fields, the vs-base line', (tester) async {
      final api = setupApi();
      await open(tester, HotelSetupScreen(session: await sessionFor(api), company: hotel), size: tallPhone);
      await tapText(tester, 'Rates');
      expect(find.text('Christmas'), findsOneWidget);
      expect(find.text('Expired'), findsWidgets);
      expect(find.text('Weekday'), findsWidgets);
      await tapText(tester, 'Add Rate');
      await enter(tester, 'Rate *', '250');
      expect(find.text('+25.0% vs base rate (200.00) — premium of 50.00/night'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Please fill all required fields'), findsOneWidget);
      expect(api.writes.where((w) => w.url.path == '/api/Hotel/room-rates'), isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  group('Staff', () {
    testWidgets('counts, filters, owes, badge; add and edit', (tester) async {
      final api = staffApi();
      await open(tester, HotelStaffScreen(session: await sessionFor(api), company: hotel), size: tallPhone);
      expect(find.text('(2 total — 1 active, 1 inactive)'), findsOneWidget);
      expect(find.text('Owes 250.00 · 1 active'), findsOneWidget);
      expect(find.text('Employee'), findsOneWidget);
      // Make employee is offered only to the one without a login.
      expect(find.byTooltip('Make employee (give a login)'), findsOneWidget);

      await tapText(tester, 'Inactive (1)');
      expect(find.text('Ama Mensah'), findsNothing);
      await tapText(tester, 'All (2)');
      await tapText(tester, 'Front Desk (1)');
      expect(find.text('Kofi Boateng'), findsNothing);
      await tapText(tester, 'All Depts');

      await tapText(tester, 'Add Staff');
      expect(find.text('Add Staff Member'), findsOneWidget);
      await enter(tester, 'First Name *', 'Esi');
      await enter(tester, 'Last Name *', 'Owusu');
      await pickIn(tester, 'Front Desk', 'Kitchen');
      await pickIn(tester, 'Other', 'Chef');
      await tester.tap(find.widgetWithText(FilledButton, 'Add Staff').last);
      await tester.pumpAndSettle();
      final b = lastWrite(api, '/api/Hotel/staff', 'POST');
      expect((b['firstName'], b['department'], b['role'], b['isActive'], b['skipLogin'], b['farmId']),
          ('Esi', 'Kitchen', 'Chef', true, false, 'h1'));

      await tapTip(tester, 'Edit');
      expect(find.text('Edit Ama Mensah'), findsOneWidget);
      await tester.tap(find.byType(Switch).last);
      await tester.pumpAndSettle();
      expect(find.text('Inactive — employee will not appear in payroll runs'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Update'));
      await tester.pumpAndSettle();
      final u = lastWrite(api, '/api/Hotel/staff/1', 'PUT');
      expect((u['isActive'], u['hireDate'], u['salaryAmount']), (false, '2026-01-05', 1500.0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('delete asks first, then removes', (tester) async {
      final api = staffApi();
      await open(tester, HotelStaffScreen(session: await sessionFor(api), company: hotel), size: tallPhone);
      await tapTip(tester, 'Delete');
      expect(find.text('Remove staff member?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(api.writes.any((w) => w.method == 'DELETE' && w.url.path == '/api/Hotel/staff/1'), isTrue);
    });

    testWidgets('from an employee: the dialog opens prefilled and skips the login', (tester) async {
      final api = staffApi()..writeAnswers['/api/Hotel/staff'] = {'hotelStaffId': 9};
      Object? created;
      await open(
        tester,
        HotelStaffScreen(
          session: await sessionFor(api),
          company: hotel,
          prefill: const EmployeePrefill(firstName: 'Yaw', lastName: 'Darko', email: 'yaw@palm.test'),
          onCreated: (c) async => created = c,
        ),
        size: tallPhone,
      );
      expect(find.text('Add Staff Member'), findsOneWidget);
      expect(find.text('Yaw'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Add Staff').last);
      await tester.pumpAndSettle();
      expect(lastWrite(api, '/api/Hotel/staff', 'POST')['skipLogin'], true);
      expect(created, {'hotelStaffId': 9});
    });
  });

  testWidgets('Users & Permissions: a Hotel employee gets the Hotel switches, not Water or Restaurant', (tester) async {
    await open(tester, EmployeeFormScreen(session: await sessionFor(FakeApi()), company: hotel), size: const Size(360, 4000));
    await tapText(tester, 'Select Staff Permissions');
    for (final t in ['Enter Sales', 'View Hotel Rooms', 'View Hotel Bookings', 'View Housekeeping', 'View Hotel Supplies', 'View Hotel Setup']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text('View Water Production'), findsNothing);
    expect(find.text('View POS & Orders'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
