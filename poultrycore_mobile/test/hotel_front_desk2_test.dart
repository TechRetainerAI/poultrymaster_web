// Hotel → Operations → Front Desk, part 2: Check-out, Availability and Guest
// Folio, at phone width against a fake API.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/hotel/hotel_front_desk2_screens.dart';
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

Map body(FakeApi api, String path) => jsonDecode(api.writes.lastWhere((w) => w.url.path == path && w.method == 'POST').body) as Map;

FakeApi base() => FakeApi()
  ..gets['/api/Hotel/bookings'] = [
    {'hotelBookingId': 1, 'bookingRef': 'BK-1', 'guestFirstName': 'Kofi', 'guestLastName': 'Mensah', 'roomTypeName': 'Deluxe', 'hotelRoomId': 11,
      'roomNumber': '101', 'checkInDate': '2026-10-26T00:00:00', 'checkOutDate': '2026-10-28T00:00:00', 'totalAmount': 200, 'status': 'Confirmed'},
    {'hotelBookingId': 2, 'bookingRef': 'BK-2', 'hotelGuestId': 8, 'guestFirstName': 'Esi', 'guestLastName': 'Boateng', 'roomTypeName': 'Deluxe', 'hotelRoomId': 12,
      'roomNumber': '102', 'checkInDate': '2026-10-26T00:00:00', 'checkOutDate': '2026-10-28T00:00:00', 'totalAmount': 200, 'status': 'CheckedIn'},
    {'hotelBookingId': 3, 'bookingRef': 'BK-3', 'guestFirstName': 'Ama', 'guestLastName': 'Owusu', 'roomTypeName': 'Suite', 'hotelRoomId': 13,
      'roomNumber': '103', 'checkInDate': '2026-10-27T00:00:00', 'checkOutDate': '2026-10-28T00:00:00', 'totalAmount': 100, 'status': 'CheckedIn'},
    {'hotelBookingId': 4, 'bookingRef': 'BK-4', 'guestFirstName': 'Yaw', 'guestLastName': 'Asare', 'status': 'CheckedOut'},
  ]
  ..gets['/api/Hotel/billing/payments'] = [
    {'hotelBookingId': 2, 'amount': 150, 'paymentMethod': 'Cash', 'reference': 'PAY-9', 'paymentDate': '2026-10-26T10:00:00'},
    {'hotelbookingid': 3, 'amount': 140, 'paymentmethod': 'Card'},
  ]
  ..gets['/api/Hotel/billing/charges'] = [
    {'totalAmount': 40},
  ]
  ..gets['/api/Hotel/setup/room-types'] = [
    {'hotelRoomTypeId': 3, 'name': 'Deluxe'},
    {'hotelRoomTypeId': 4, 'name': 'Suite'},
  ]
  ..gets['/api/Hotel/availability'] = [
    {'hotelroomid': 11, 'roomnumber': '101', 'status': 'Available', 'roomtypename': 'Deluxe', 'baserate': 100, 'floorname': 'First'},
    {'hotelroomid': 21, 'roomnumber': '201', 'status': 'Available', 'roomtypename': 'Suite', 'baserate': 300},
  ]
  ..gets['/api/Hotel/folio/2'] = {
    'hotel': {'name': 'Palm Hotel', 'address': 'Accra', 'phone': '030', 'email': 'p@h.com'},
    'booking': {'firstname': 'Esi', 'lastname': 'Boateng', 'bookingref': 'BK-2', 'roomnumber': '102', 'roomtypename': 'Deluxe', 'status': 'CheckedIn',
      'checkindate': '2026-10-26', 'checkoutdate': '2026-10-28', 'adults': 1, 'children': 2, 'nightlyrate': 100, 'totalamount': 200},
    'charges': [
      {'chargedate': '2026-10-27', 'chargetype': 'Minibar', 'description': 'Drinks', 'quantity': 2, 'unitprice': 20, 'totalamount': 40},
    ],
    'payments': [
      {'paymentdate': '2026-10-26', 'paymentmethod': 'Cash', 'reference': 'PAY-9', 'amount': 150},
    ],
    'summary': {'roomTotal': 200, 'chargesTotal': 40, 'grandTotal': 240, 'paymentsTotal': 150, 'balance': 90},
  }
  ..gets['/api/Hotel/billing/invoices'] = [
    {'hotelInvoiceId': 1, 'invoiceNumber': 'INV-001', 'issuedDate': '2026-10-27T09:00:00', 'subTotal': 240, 'taxRate': 10, 'taxAmount': 24,
      'discountAmount': 4, 'totalAmount': 260, 'amountPaid': 150, 'balance': 110, 'status': 'PartiallyPaid'},
  ]
  ..gets['/api/Hotel/checkin-history'] = [
    {'hotelcheckinid': 1, 'hotelguestid': 8, 'firstname': 'Esi', 'lastname': 'Boateng', 'roomnumber': '102', 'bookingref': 'BK-2',
      'checkintime': '2026-10-26T12:00:00Z', 'keycardnumber': 'KC-7', 'depositamount': 50},
    {'hotelcheckinid': 2, 'hotelguestid': 9, 'firstname': 'Kwame', 'lastname': 'Ofori', 'roomnumber': '201', 'bookingref': 'BK-9',
      'checkintime': '2026-10-20T12:00:00Z', 'phone': '055'},
  ]
  ..gets['/api/Hotel/checkout-history'] = [
    {'hotelcheckoutid': 1, 'hotelguestid': 8, 'firstname': 'Esi', 'lastname': 'Boateng', 'roomnumber': '102', 'bookingref': 'BK-0',
      'checkouttime': '2026-09-02T10:00:00Z', 'finalbillamount': 320, 'latefee': 20},
  ]
  ..gets['/api/Hotel/guests'] = [
    {'hotelGuestId': 8, 'firstName': 'Esi', 'lastName': 'Boateng', 'phone': '024', 'email': 'e@x.com', 'idType': 'Passport', 'idNumber': 'P9',
      'isVIP': true, 'totalStays': 2, 'createdAt': '2026-01-05T10:00:00Z', 'lastStayDate': '2026-10-26'},
  ];

void main() {
  final shared = <String>[];
  setUp(() {
    shared.clear();
    ReportExport.sharer = (name, bytes, mime, subject) async => shared.add(name);
  });

  test('the three rows open native screens; the balance filter', () {
    for (final h in ['/hotel-check-out', '/hotel-availability', '/hotel-guest-folio', '/hotel-billing', '/hotel-invoices', '/hotel-stay-history']) {
      expect(pageScreens.containsKey(h), isTrue, reason: h);
    }
    GuestBill bill(String name, num balance) =>
        (booking: {'guestFirstName': name, 'bookingRef': 'R-$name', 'roomNumber': '1'}, payments: <Map>[], roomBill: 0, extraCharges: 0, grandTotal: 0, totalPaid: 0, balance: balance);
    final bills = [bill('Esi', 90), bill('Ama', 0)];
    expect(filterGuestBills(bills, balance: 'owes').single.booking['guestFirstName'], 'Esi');
    expect(filterGuestBills(bills, balance: 'paid').single.booking['guestFirstName'], 'Ama');
    expect(filterGuestBills(bills, search: 'r-ama').length, 1);
    final stays = [
      {'firstname': 'Esi', 'lastname': 'Boateng', 'bookingref': 'BK-2', 'roomnumber': '102'},
      {'firstname': 'Kwame', 'bookingref': 'BK-9', 'roomnumber': '201'},
    ];
    expect(filterStayHistory(stays, 'boateng').single['bookingref'], 'BK-2');
    expect(filterStayHistory(stays, '201').single['bookingref'], 'BK-9');
    expect(hotelInvoiceStatusLabel('PartiallyPaid'), 'Partially paid');
  });

  testWidgets('Check-out: bills, filters, Pay, the balance guard, Confirm', (tester) async {
    final api = base();
    await open(tester, HotelCheckOutScreen(session: await sessionFor(api), company: hotel), size: tall);
    expect(find.text('Esi Boateng'), findsOneWidget);
    expect(find.text('Kofi Mensah'), findsNothing, reason: 'only checked-in guests');
    expect(find.text('90.00'), findsWidgets, reason: '200 room + 40 extras - 150 paid');
    expect(find.text('Pay 90.00'), findsOneWidget);
    expect(find.textContaining('via Cash', findRichText: true), findsOneWidget);
    await tapText(tester, 'Paid (1)');
    expect(find.text('Esi Boateng'), findsNothing);
    await tapText(tester, 'All (2)');

    await tapText(tester, 'Pay 90.00');
    expect(find.text('A payment reference code will be generated automatically.'), findsOneWidget);
    await choose<String>(tester, 'Cash', 'Mobile Money');
    await tester.tap(filled('Record Payment'));
    await tester.pumpAndSettle();
    final p = body(api, '/api/Hotel/billing/payments');
    expect((p['hotelBookingId'], p['amount'], p['paymentMethod'], p['farmId']), (2, 90, 'MobileMoney', 'h1'));

    await tester.tap(filled('Check Out').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Guest must settle this balance'), findsOneWidget);
    await tester.tap(filled('Confirm Check-out'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Guest has an outstanding balance — Balance of 90.00'), findsOneWidget);
    expect(api.writes.where((w) => w.url.path == '/api/Hotel/front-desk/check-out'), isEmpty);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(filled('Check Out').last);
    await tester.pumpAndSettle();
    expect(find.text('Balance settled. Ready for checkout.'), findsOneWidget);
    await tester.tap(filled('Confirm Check-out'));
    await tester.pumpAndSettle();
    final c = body(api, '/api/Hotel/front-desk/check-out');
    expect((c['hotelBookingId'], c['hotelRoomId'], c['lateFee'], c['damageCharges'], c['keyReturned']), (3, 13, 0, 0, true));
  });

  testWidgets('Availability: date guard, search, floors, Book Now', (tester) async {
    final api = base();
    await open(tester, HotelAvailabilityScreen(session: await sessionFor(api), company: hotel), size: tall);
    await choose<String>(tester, 'All Types', 'Suite');
    await tester.tap(filled('Search'));
    await tester.pumpAndSettle();
    final q = api.requests.lastWhere((r) => r.url.path == '/api/Hotel/availability').url.queryParameters;
    expect(q['roomTypeId'], '4');
    expect(q['checkOut']!.compareTo(q['checkIn']!) > 0, isTrue);
    expect(find.text('2 room(s) available'), findsOneWidget);
    expect(find.text('First'), findsOneWidget);
    expect(find.text('Unassigned'), findsOneWidget);
    expect(find.text('300.00 /night'), findsOneWidget);
    await tester.tap(filled('Book Now').first);
    await tester.pumpAndSettle();
    expect(find.byType(HotelBookingsScreen), findsOneWidget);
  });

  testWidgets('Guest Folio: pick a booking, the statement, Print', (tester) async {
    final api = base();
    await open(tester, HotelGuestFolioScreen(session: await sessionFor(api), company: hotel), size: tall);
    expect(find.text('Select a booking above to view the guest folio.'), findsOneWidget);
    await choose<int>(tester, 'Pick a booking...', 'BK-2 — Esi Boateng (CheckedIn)');
    expect(find.text('Esi Boateng'), findsOneWidget);
    expect(find.text('1 adults, 2 children'), findsOneWidget);
    expect(find.text('Minibar'), findsOneWidget);
    expect(find.text('PAY-9'), findsOneWidget);
    expect(find.text('240.00'), findsOneWidget);
    expect(find.text('90.00'), findsOneWidget);
    await tester.tap(find.text('Print Folio'));
    await tester.pumpAndSettle();
    expect(shared, ['Folio_BK-2.pdf']);
  });
  testWidgets('Billing: active stays, the bill, Add Charge, Record Payment, Generate Invoice', (tester) async {
    final api = base();
    await open(tester, HotelBillingScreen(session: await sessionFor(api), company: hotel), size: tall);
    expect(find.text('Kofi Mensah'), findsOneWidget, reason: 'confirmed stays are billed too');
    expect(find.text('Yaw Asare'), findsNothing);
    expect(find.text('Owes 90.00'), findsOneWidget);
    expect(find.text('Select a guest to view their bill'), findsOneWidget);
    await tapText(tester, 'Esi Boateng');
    expect(find.text('Room Total'), findsOneWidget);
    expect(find.text('Payments Received'), findsOneWidget);
    expect(find.text('90.00'), findsWidgets);

    await tester.tap(filled('Add Charge'));
    await tester.pumpAndSettle();
    await tester.tap(filled('Add Charge').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Description required'), findsOneWidget);
    await choose<String>(tester, 'Room', 'Minibar');
    await tester.enterText(find.widgetWithText(TextFormField, 'e.g. Minibar drinks, Room service dinner'), 'Drinks');
    final fields = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField));
    await tester.enterText(fields.at(1), '3');
    await tester.enterText(fields.at(2), '12.5');
    await tester.pump();
    expect(find.text('Charge Total: 37.50'), findsOneWidget);
    await tester.tap(filled('Add Charge').last);
    await tester.pumpAndSettle();
    final c = body(api, '/api/Hotel/billing/charges');
    expect((c['hotelBookingId'], c['chargeType'], c['description'], c['quantity'], c['unitPrice'], c['totalAmount']), (2, 'Minibar', 'Drinks', 3, 12.5, 37.5));

    await tapText(tester, 'Record Payment');
    expect(find.text('Already Paid'), findsOneWidget);
    final pf = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField));
    await tester.enterText(pf.at(1), 'MM-55');
    await tester.tap(filled('Record Payment'));
    await tester.pumpAndSettle();
    final p = body(api, '/api/Hotel/billing/payments');
    expect((p['hotelBookingId'], p['amount'], p['paymentMethod'], p['reference'], p.containsKey('notes')), (2, 90, 'Cash', 'MM-55', false));

    await tapText(tester, 'Generate Invoice');
    expect(body(api, '/api/Hotel/billing/invoices/generate'), {'hotelBookingId': 2, 'farmId': 'h1'});
    expect(find.text('Invoice generated'), findsOneWidget);
  });

  testWidgets('Invoices: the list, the preview, Print Invoice', (tester) async {
    final api = base();
    await open(tester, HotelInvoicesScreen(session: await sessionFor(api), company: hotel), size: tall);
    expect(find.text('INV-001'), findsOneWidget);
    expect(find.text('Partially paid'), findsOneWidget);
    expect(find.text('110.00'), findsOneWidget);
    await tester.tap(find.text('Print'));
    await tester.pumpAndSettle();
    expect(find.text('Invoice Preview'), findsOneWidget);
    expect(find.text('Tax (10%)'), findsOneWidget);
    expect(find.text('-4.00'), findsOneWidget);
    expect(find.text('Total Due'), findsOneWidget);
    await tester.tap(filled('Print Invoice'));
    await tester.pumpAndSettle();
    expect(shared, ['Invoice_INV-001.pdf']);
  });

  testWidgets('Stay History: tabs, search, the guest dialog', (tester) async {
    final api = base();
    await open(tester, HotelStayHistoryScreen(session: await sessionFor(api), company: hotel), size: tall);
    expect(find.text('Check-ins (2)'), findsOneWidget);
    expect(find.text('KC-7'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'kwame');
    await tester.pump();
    expect(find.text('Check-ins (1)'), findsOneWidget);
    await tapText(tester, 'Kwame Ofori');
    expect(find.text('055'), findsOneWidget, reason: 'built from the row when the guest is not on the list');
    expect(find.text('0 stay(s)'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '');
    await tester.pump();

    await tapText(tester, 'Check-outs (1)');
    expect(find.text('320.00'), findsOneWidget);
    await tapText(tester, 'Esi Boateng');
    expect(find.text('2 stay(s)'), findsOneWidget);
    expect(find.text('Passport'), findsOneWidget);
    expect(find.text('BOOKING HISTORY (1)'), findsOneWidget);
    expect(find.text('CHECK-IN HISTORY (1)'), findsOneWidget);
    expect(find.text('CHECK-OUT HISTORY (1)'), findsOneWidget);
    expect(find.text('Last stay: 26/10/2026'), findsOneWidget);
  });
}
