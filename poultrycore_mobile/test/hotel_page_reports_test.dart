// Hotel → Reports: the sixteen reports that own their pages on the web
// (app/hotel-reports/<slug>/page.tsx), at phone width against a fake API.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/hotel/reports/hotel_page_report_defs.dart';
import 'package:poultrycore_mobile/pages/hotel/reports/hotel_report_routes.dart';
import 'package:poultrycore_mobile/pages/hotel/reports/hotel_reports_catalog.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/restaurant/reports/restaurant_report_kit.dart' show isoDay;

import 'support/harness.dart';

final hotel = Company(farmId: 'h1', name: 'Palm Hotel', type: CompanyType.hotel, role: 'Admin');
const tallPhone = Size(360, 6000);
final today = isoDay(DateTime.now());
const old = '2020-01-05';

FakeApi pageApi() => FakeApi()
  ..gets['/api/Hotel/setup/profile'] = {'hotelName': 'Golden Palm', 'defaultCurrency': 'GHS'}
  ..gets['/api/Hotel/reports/daily-closings'] = [
    {'closingdate': '${today}T00:00:00', 'totalrevenue': 1000, 'totalexpenses': 400, 'occupancyrate': 75, 'roomsoccupied': 15, 'totalrooms': 20,
      'adr': 66.67, 'revpar': 50},
    {'closingdate': '${old}T00:00:00', 'totalrevenue': 9999, 'totalexpenses': 1},
  ]
  ..gets['/api/Hotel/finance/expenses'] = [
    {'expenseDate': today, 'category': 'Utilities', 'description': 'Power', 'amount': 300},
    {'expenseDate': today, 'category': 'Utilities', 'description': 'Water', 'vendor': 'GWCL', 'amount': 100},
    {'expenseDate': today, 'description': 'Misc', 'amount': 50},
    {'expenseDate': old, 'category': 'Old', 'amount': 5000},
  ]
  ..gets['/api/Hotel/billing/payments'] = [
    {'paymentDate': today, 'hotelBookingId': 31, 'amount': 300, 'paymentMethod': 'Cash', 'receivedBy': 'Esi'},
    {'paymentDate': today, 'hotelBookingId': 32, 'amount': 200, 'paymentMethod': 'MoMo'},
  ]
  ..gets['/api/Hotel/bookings'] = [
    {'hotelBookingId': 31, 'hotelGuestId': 7, 'bookingRef': 'BK-31', 'guestFirstName': 'Kofi', 'guestLastName': 'Mensah', 'roomNumber': '101',
      'checkInDate': today, 'checkOutDate': isoDay(DateTime.now().add(const Duration(days: 3))), 'nightlyRate': 300, 'totalAmount': 900,
      'status': 'CheckedIn'},
    {'hotelBookingId': 32, 'hotelGuestId': 7, 'bookingRef': 'BK-32', 'guestFirstName': 'Kofi', 'guestLastName': 'Mensah', 'roomNumber': '102',
      'checkInDate': old, 'checkOutDate': today, 'totalAmount': 400, 'status': 'Cancelled'},
  ]
  ..gets['/api/Hotel/payroll-runs'] = [
    {'periodStart': '2026-09-01', 'periodEnd': '2026-09-30', 'status': 'Paid', 'totalGross': 5000, 'totalDeductions': 500, 'totalNet': 4500,
      'cashAccountName': 'Bank'},
  ]
  ..gets['/api/Hotel/finance/cash-accounts'] = [
    {'hotelcashaccountid': 5, 'accountname': 'Front desk till', 'currentbalance': 1200, 'purpose': 'Sales'},
    {'hotelcashaccountid': 6, 'accountname': 'Bank', 'currentbalance': 9000},
  ]
  ..gets['/api/Hotel/finance/cash-transactions'] = [
    {'hotelcashaccountid': 5, 'accountname': 'Front desk till', 'txntype': 'Credit', 'amount': 300, 'balanceafter': 1200, 'sourcetype': 'Payment',
      'txndate': today, 'reference': 'P-1'},
    {'hotelcashaccountid': 6, 'accountname': 'Bank', 'txntype': 'Debit', 'amount': 100, 'balanceafter': 9000,
      'sourcetype': 'EmployeeLoanAdvance', 'txndate': today},
  ]
  ..gets['/api/Hotel/guests'] = [
    {'hotelGuestId': 7, 'firstName': 'Kofi', 'lastName': 'Mensah', 'email': 'k@x.com', 'isVIP': true},
    {'hotelGuestId': 8, 'firstName': 'Ama', 'lastName': 'Owusu'},
  ]
  ..gets['/api/Hotel/restaurant/orders'] = [
    {'hotelRestaurantOrderId': 9, 'orderTime': '${today}T12:00:00', 'tableNumber': 'T4', 'subTotal': 70, 'totalAmount': 80, 'status': 'Served'},
  ]
  ..gets['/api/Hotel/restaurant/menu'] = [
    {'name': 'Jollof', 'category': 'Mains', 'price': 50, 'isAvailable': true},
    {'name': 'Beer', 'category': 'Bar', 'price': 20, 'isAvailable': false},
  ]
  ..gets['/api/Hotel/maintenance'] = [
    {'createdAt': '${today}T08:00:00', 'roomNumber': '101', 'assetDescription': 'AC', 'issueDescription': 'Leaking', 'priority': 'High',
      'status': 'InProgress', 'estimatedCost': 250},
  ]
  ..gets['/api/Hotel/housekeeping'] = [
    {'createdAt': '${today}T07:00:00', 'roomNumber': '101', 'taskType': 'Cleaning', 'status': 'Pending'},
    {'createdAt': '${today}T07:30:00', 'roomNumber': '102', 'taskType': 'Turndown', 'status': 'Completed'},
  ]
  ..gets['/api/Hotel/inventory'] = [
    {'name': 'Soap', 'category': 'Amenities', 'unit': 'pcs', 'stockOnHand': 4, 'reorderLevel': 10, 'unitCost': 2.5},
    {'name': 'Towel', 'category': 'Linen', 'unit': 'pcs', 'stockOnHand': 40, 'reorderLevel': 10, 'unitCost': 30},
  ]
  ..gets['/api/Hotel/staff'] = [
    {'firstName': 'Esi'},
    {'firstName': 'Kwame'},
  ];

Future<void> openReport(WidgetTester tester, FakeApi api, String slug) async {
  await open(tester, hotelReportScreen(await sessionFor(api), hotel, slug)!, size: tallPhone);
}

void main() {
  test('every own-page report is in the catalog and opens a native screen', () {
    expect(hotelPageReportDefs.length, 16);
    for (final slug in hotelPageReportDefs.keys) {
      expect(findHotelReport(slug), isNotNull, reason: slug);
      expect(pageScreens.containsKey('/hotel-reports/$slug'), isTrue, reason: slug);
    }
  });

  testWidgets('each one renders at phone width, with data and with none', (tester) async {
    for (final slug in hotelPageReportDefs.keys) {
      await openReport(tester, pageApi(), slug);
      expect(tester.takeException(), isNull, reason: slug);
      expect(find.text('Could not load report'), findsNothing, reason: slug);
      await openReport(tester, FakeApi(), slug);
      expect(tester.takeException(), isNull, reason: '$slug (empty)');
    }
  });

  testWidgets('Revenue Summary: the period only, tiles, chart and closings', (tester) async {
    await openReport(tester, pageApi(), 'revenue-summary');
    expect(find.text('GHS 1,000.00'), findsNWidgets(2), reason: 'the tile and the chart bar');
    expect(find.text('GHS 600.00'), findsOneWidget, reason: 'net profit');
    expect(find.text('75.0%'), findsWidgets);
    expect(find.text('Revenue vs Expenses'), findsOneWidget);
    expect(find.text('Daily Closings (1)'), findsOneWidget);
    expect(find.text('15/20'), findsOneWidget);
    // From / To only, as the web page: no preset buttons.
    expect(find.text('7 days'), findsNothing);
  });

  testWidgets('Expense Report: category table, largest first', (tester) async {
    await openReport(tester, pageApi(), 'expense-report');
    expect(find.text('By Category'), findsOneWidget);
    expect(find.text('Uncategorized'), findsOneWidget);
    expect(find.text('Expense Details (3)'), findsOneWidget);
    expect(find.text('GHS 450.00'), findsOneWidget);
    expect(find.text('GWCL'), findsOneWidget);
  });

  testWidgets('Billing: methods and the booking each payment belongs to', (tester) async {
    await openReport(tester, pageApi(), 'billing-report');
    expect(find.text('By Payment Method'), findsOneWidget);
    expect(find.text('GHS 500.00'), findsOneWidget);
    expect(find.text('BK-31'), findsOneWidget);
    expect(find.text('Kofi Mensah'), findsNWidgets(2));
  });

  testWidgets('Cash Flow: account and source filters narrow the log', (tester) async {
    final api = pageApi();
    await openReport(tester, api, 'cash-flow-report');
    expect(find.text('Transaction Log (2)'), findsOneWidget);
    expect(find.text('By Account'), findsOneWidget);
    expect(find.text('Staff loans'), findsWidgets, reason: 'loan movements are one group');
    await pick(tester, 'All Accounts', 'Bank');
    expect(find.text('Transaction Log (1)'), findsOneWidget);
    await pick(tester, 'Bank', 'All Accounts');
    await pick(tester, 'All Sources', 'Payments');
    expect(find.text('Transaction Log (1)'), findsOneWidget);
    expect(find.text('+300.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Payroll and Guest have no date filter; repeat guests counted', (tester) async {
    await openReport(tester, pageApi(), 'payroll-report');
    expect(find.text('From'), findsNothing);
    expect(find.text('Payroll Runs (1)'), findsOneWidget);
    expect(find.text('Paid'), findsOneWidget);
    await openReport(tester, pageApi(), 'guest-report');
    expect(find.text('Guest List (2)'), findsOneWidget);
    expect(find.text('VIP'), findsWidgets);
    expect(find.text('Repeat Guests'), findsOneWidget);
  });

  testWidgets('Daily Report: three tables for the chosen day', (tester) async {
    await openReport(tester, pageApi(), 'daily-report');
    expect(find.text('Check-ins (1)'), findsOneWidget);
    expect(find.text('Check-outs (1)'), findsOneWidget);
    expect(find.text('Payments (2)'), findsOneWidget);
    expect(find.text('Previous day'), findsNothing);
  });

  testWidgets('Weekly and Monthly: their own period pickers and totals', (tester) async {
    await openReport(tester, pageApi(), 'weekly-report');
    expect(find.text('Daily Breakdown'), findsOneWidget);
    expect(find.text('Total'), findsOneWidget);
    expect(find.textContaining('to '), findsWidgets);
    await openReport(tester, pageApi(), 'monthly-report');
    expect(find.text('Week-by-Week Breakdown'), findsOneWidget);
    expect(find.text('Staff Count'), findsOneWidget);
    final months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    expect(find.text(months[DateTime.now().month - 1]), findsOneWidget);
  });

  testWidgets('Inventory flags low stock; Menu counts the unavailable', (tester) async {
    await openReport(tester, pageApi(), 'inventory-report');
    expect(find.text('Inventory Items (2)'), findsOneWidget);
    expect(find.text('GHS 1,210.00'), findsOneWidget);
    await openReport(tester, pageApi(), 'menu-performance');
    expect(find.text('Menu Items (2)'), findsOneWidget);
    expect(find.text('Unavailable'), findsOneWidget);
  });
}
