// Hotel → Operations → Front Desk: Bookings (with the calendar), Guests (with
// loyalty) and Check-in, at phone width against a fake API.

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/hotel/hotel_front_desk_screens.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/reports/report_export.dart';

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

/// [enter] for a label that also shows on the page behind the dialog.
Future<void> enterLast(WidgetTester tester, String label, String text) async {
  final field = find.descendant(of: find.ancestor(of: find.text(label).last, matching: find.byType(Column)).first, matching: find.byType(TextFormField));
  await tester.enterText(field.first, text);
  await tester.pump();
}

Map body(FakeApi api, String path, [String method = 'POST']) =>
    jsonDecode(api.writes.lastWhere((w) => w.url.path == path && w.method == method).body) as Map;

String ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

final _today = DateTime.now();
final _in = ymd(_today), _out = ymd(_today.add(const Duration(days: 2)));

FakeApi base() => FakeApi()
  ..gets['/api/Hotel/bookings'] = [
    {'hotelBookingId': 1, 'bookingRef': 'BK-1', 'hotelGuestId': 7, 'guestFirstName': 'Kofi', 'guestLastName': 'Mensah', 'hotelRoomTypeId': 3,
      'roomTypeName': 'Deluxe', 'hotelRoomId': 11, 'roomNumber': '101', 'checkInDate': '${_in}T00:00:00', 'checkOutDate': '${_out}T00:00:00',
      'nightlyRate': 100, 'totalAmount': 200, 'adults': 2, 'children': 1, 'numberOfGuests': 3, 'source': 'Phone', 'status': 'Confirmed',
      'createdAt': '2026-10-20T09:00:00Z'},
    {'hotelBookingId': 2, 'bookingRef': 'BK-2', 'hotelGuestId': 8, 'guestFirstName': 'Esi', 'guestLastName': 'Boateng', 'hotelRoomTypeId': 3,
      'roomTypeName': 'Deluxe', 'hotelRoomId': 12, 'roomNumber': '102', 'checkInDate': '${_in}T00:00:00', 'checkOutDate': '${_out}T00:00:00',
      'nightlyRate': 100, 'totalAmount': 200, 'adults': 1, 'children': 0, 'source': 'WalkIn', 'status': 'CheckedIn'},
  ]
  ..gets['/api/Hotel/guests'] = [
    {'hotelGuestId': 7, 'firstName': 'Kofi', 'lastName': 'Mensah', 'phone': '024', 'email': 'k@x.com', 'idType': 'Passport', 'idNumber': 'P1',
      'isVIP': true, 'totalStays': 3, 'lastStayDate': '2026-09-01'},
    {'hotelGuestId': 8, 'firstName': 'Esi', 'lastName': 'Boateng', 'isVIP': false, 'totalStays': 0},
  ]
  ..gets['/api/Hotel/setup/room-types'] = [
    {'hotelRoomTypeId': 3, 'name': 'Deluxe', 'baseRate': 100},
    {'hotelRoomTypeId': 4, 'name': 'Suite', 'baseRate': 300},
  ]
  ..gets['/api/Hotel/rooms'] = [
    {'hotelRoomId': 11, 'roomNumber': '101', 'hotelRoomTypeId': 3, 'roomTypeName': 'Deluxe', 'status': 'Available', 'floorName': 'First'},
    {'hotelRoomId': 12, 'roomNumber': '102', 'hotelRoomTypeId': 3, 'roomTypeName': 'Deluxe', 'status': 'Occupied', 'floorName': 'First'},
    {'hotelRoomId': 13, 'roomNumber': '103', 'hotelRoomTypeId': 4, 'roomTypeName': 'Suite', 'status': 'Available', 'floorName': 'First'},
  ]
  ..gets['/api/Hotel/setup/profile'] = {'hotelName': 'Palm Hotel', 'phone': '030', 'checkInTime': '15:00'}
  ..gets['/api/Hotel/billing/payments'] = [
    {'hotelBookingId': 2, 'amount': 150},
    {'hotelbookingid': 1, 'amount': 50},
  ]
  ..gets['/api/Hotel/billing/charges'] = [
    {'totalAmount': 40},
  ]
  ..gets['/api/Hotel/setup/id-types'] = [
    {'description': 'Passport'},
    {'description': 'Ghana Card'},
  ];

void main() {
  final shared = <String>[];
  setUp(() {
    shared.clear();
    ReportExport.sharer = (name, bytes, mime, subject) async => shared.add(name);
  });

  test('the three rows open native screens; filters, nights, the booking ref, the tiers', () {
    for (final h in ['/hotel-bookings', '/hotel-guests', '/hotel-check-in']) {
      expect(pageScreens.containsKey(h), isTrue, reason: h);
    }
    final rows = [
      {'guestFirstName': 'Kofi', 'guestLastName': 'Mensah', 'bookingRef': 'BK-1', 'roomNumber': '101', 'status': 'Confirmed'},
      {'guestFirstName': 'Esi', 'bookingRef': 'BK-2', 'status': 'CheckedIn'},
    ];
    expect(filterBookings(rows, status: 'CheckedIn').single['bookingRef'], 'BK-2');
    expect(filterBookings(rows, search: '101').single['bookingRef'], 'BK-1');
    expect(filterBookings(rows, search: 'mensah').length, 1);
    expect(bookingNights('2026-10-01', '2026-10-04'), 3);
    expect(bookingNights('2026-10-01', '2026-10-01'), 1);
    expect(newBookingRef(DateTime.utc(2026, 10, 28), math.Random(1)), matches(RegExp(r'^BK-20261028-\d{3}$')));
    expect([nextLoyaltyTier('Bronze'), nextLoyaltyTier('Gold'), nextLoyaltyTier('Platinum')], ['Silver', 'Platinum', null]);
  });

  testWidgets('Bookings: filters, New Booking, the receipt, Cancel', (tester) async {
    final api = base();
    await open(tester, HotelBookingsScreen(session: await sessionFor(api), company: hotel), size: tall);
    expect(find.text('Confirmed (1)'), findsOneWidget);
    await tapText(tester, 'Checked In (1)');
    expect(find.text('Kofi Mensah'), findsNothing);
    await tapText(tester, 'All (2)');

    await tapText(tester, 'New Booking');
    await choose<int>(tester, 'Deluxe', 'Suite');
    await choose<int>(tester, 'Assign later', '103');
    expect(find.text('300'), findsWidgets, reason: 'the rate follows the room type; one night by default');
    await tester.tap(filled('Create'));
    await tester.pumpAndSettle();
    final b = body(api, '/api/Hotel/bookings');
    expect((b['hotelGuestId'], b['hotelRoomTypeId'], b['hotelRoomId'], b['nightlyRate'], b['totalAmount'], b['status'], b['source'], b['numberOfGuests']),
        (7, 4, 13, 300, 300, 'Confirmed', 'WalkIn', 1));
    expect(b['bookingRef'], matches(RegExp(r'^BK-\d{8}-\d{3}$')));

    await tester.tap(find.byTooltip('Print Receipt').first);
    await tester.pumpAndSettle();
    expect(find.text('BOOKING CONFIRMATION'), findsOneWidget);
    expect(find.text('2 Adults, 1 Child'), findsOneWidget);
    expect(find.textContaining('Check-in time: 15:00'), findsOneWidget);
    await tester.tap(filled('Print'));
    await tester.pumpAndSettle();
    expect(shared, ['Booking_BK-1.pdf']);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Cancel booking'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete').last);
    await tester.pumpAndSettle();
    expect(api.writes.any((w) => w.url.path == '/api/Hotel/bookings/1/cancel'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Bookings: ?edit= opens the booking; the calendar moves a bar by holding and dragging', (tester) async {
    final api = base();
    await open(tester, HotelBookingsScreen(session: await sessionFor(api), company: hotel, editId: 1), size: tall);
    expect(find.text('Edit Booking BK-1'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel').last);
    await tester.pumpAndSettle();

    await tapText(tester, 'Calendar View');
    expect(find.text('Hold and drag to move/resize'), findsOneWidget);
    final bar = find.text('Kofi Mensah').last;
    await tester.ensureVisible(bar);
    await tester.pumpAndSettle();
    final g = await tester.startGesture(tester.getCenter(bar));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await g.moveBy(const Offset(HotelBookingCalendar.dayWidth * 2, 0));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    final put = body(api, '/api/Hotel/bookings/1', 'PUT');
    expect((put['checkInDate'], put['checkOutDate'], put['hotelRoomId'], put['totalAmount']),
        (ymd(_today.add(const Duration(days: 2))), ymd(_today.add(const Duration(days: 4))), 11, 200));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Guests: counts, VIP filter, Add Guest, the profile with loyalty points', (tester) async {
    final api = base()
      ..gets['/api/Hotel/loyalty/guest/7'] = {'hotelloyaltymemberid': 5, 'hotelguestid': 7, 'tier': 'Silver', 'membershipnumber': 'M-5', 'totalpoints': 2500, 'lifetimepoints': 2500}
      ..gets['/api/Hotel/loyalty/5/transactions'] = [
        {'transactiontype': 'Earn', 'points': 500, 'description': 'Stay bonus'},
      ];
    await open(tester, HotelGuestsScreen(session: await sessionFor(api), company: hotel), size: tall);
    expect(find.text('200'), findsOneWidget, reason: 'total revenue from payments');
    await tapText(tester, '★ VIP Only');
    expect(find.text('Esi Boateng'), findsNothing);
    await tapText(tester, '★ VIP Only');

    await tapText(tester, 'Add Guest');
    await tester.tap(filled('Create'));
    await tester.pumpAndSettle();
    expect(find.text('Name is required'), findsOneWidget);
    await enter(tester, 'First Name *', 'Ama');
    await enter(tester, 'Last Name *', 'Owusu');
    await choose<String>(tester, 'None', 'Ghana Card');
    await tester.tap(filled('Create'));
    await tester.pumpAndSettle();
    final g = body(api, '/api/Hotel/guests');
    expect((g['firstName'], g['lastName'], g['idType'], g['isVIP']), ('Ama', 'Owusu', 'Ghana Card', false));

    await tester.tap(find.byTooltip('View').first);
    await tester.pumpAndSettle();
    expect(find.text('Guest Profile'), findsOneWidget);
    expect(find.text('2,500'), findsOneWidget);
    expect(find.text('5,000 for Gold'), findsOneWidget);
    expect(find.text('+500 pts'), findsOneWidget);
    expect(find.text('50.00'), findsOneWidget, reason: 'lifetime value from this guest\'s payments');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Redeem'));
    await tester.pumpAndSettle();
    await enterLast(tester, 'Points', '3000');
    await tester.pumpAndSettle();
    expect(find.text('Insufficient points (available: 2500)'), findsOneWidget);
    await enterLast(tester, 'Points', '200');
    await tester.pumpAndSettle();
    await tester.tap(filled('Redeem'));
    await tester.pumpAndSettle();
    final p = body(api, '/api/Hotel/loyalty/points');
    expect((p['hotelLoyaltyMemberId'], p['transactionType'], p['points'], p['description']), (5, 'Redeem', 200, 'Redeem points'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Check-in: counts, awaiting, in-house balances, Check In', (tester) async {
    final api = base();
    await open(tester, HotelCheckInScreen(session: await sessionFor(api), company: hotel), size: tall);
    expect(find.text('Front Desk'), findsOneWidget);
    expect(find.text('90.00'), findsOneWidget, reason: '200 room + 40 extras - 150 paid');
    expect(find.text('Guests: 2 adults, 1 children'), findsOneWidget);

    await tapText(tester, 'In-House Guests (1)');
    expect(find.text('Owes 90.00'), findsOneWidget);
    await tapText(tester, 'Awaiting Check-in (1)');

    await tester.tap(filled('Check In'));
    await tester.pumpAndSettle();
    expect(find.text('Check In: Kofi Mensah'), findsOneWidget);
    await enterLast(tester, 'Deposit Amount', '50');
    await tester.pumpAndSettle();
    expect(find.textContaining('will be recorded automatically', findRichText: true), findsOneWidget);
    await tester.tap(filled('Confirm Check-in'));
    await tester.pumpAndSettle();
    final c = body(api, '/api/Hotel/front-desk/check-in');
    expect((c['hotelBookingId'], c['hotelRoomId'], c['depositAmount'], c['depositMethod']), (1, 11, 50, 'Cash'));
    expect(tester.takeException(), isNull);
  });
}
