// Hotel → Reports at phone width: the catalog, and every report that renders
// through the shared report shell (HOTEL_REPORT_REGISTRY).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/hotel/reports/hotel_report_defs.dart';
import 'package:poultrycore_mobile/pages/hotel/reports/hotel_report_routes.dart';
import 'package:poultrycore_mobile/pages/hotel/reports/hotel_reports_catalog.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';

import 'support/harness.dart';

final hotel = Company(farmId: 'h1', name: 'Palm Hotel', type: CompanyType.hotel, role: 'Admin');
const tallPhone = Size(360, 5200);

FakeApi reportsApi() => FakeApi()
  ..gets['/api/Hotel/setup/profile'] = {'hotelName': 'Golden Palm', 'defaultCurrency': 'GHS', 'city': 'Accra'}
  ..gets['/api/Hotel/reports/performance-kpis'] = {
    'daysCounted': 30, 'availableRoomNights': 600, 'occupiedRoomNights': 420, 'occupancyPct': 70, 'roomRevenue': 0, 'fnbRevenue': 5000,
    'otherRevenue': 500, 'totalRevenue': 60000, 'totalExpenses': 20000, 'grossOperatingProfit': 40000, 'adr': 0, 'revpar': 0,
    'trevpar': 100, 'goppar': 66.67, 'noshowCount': 3,
  }
  ..gets['/api/Hotel/reports/source-of-business'] = [
    {'sourceLabel': 'Walk-in', 'bookingCount': 10, 'roomNights': 25, 'guestCount': 14, 'adr': 200, 'avgLeadDays': 0.5, 'revenueTotal': 5000, 'sharePct': 62.5},
    {'sourceLabel': 'Booking.com', 'bookingCount': 5, 'roomNights': 15, 'guestCount': 8, 'adr': 200, 'avgLeadDays': 12, 'revenueTotal': 3000, 'sharePct': 37.5},
  ]
  ..gets['/api/Hotel/reports/booking-pace'] = [
    {'leadBucket': 'Same day', 'bucketOrder': 0, 'bookingCount': 4, 'roomNights': 6, 'adr': 180, 'revenueTotal': 1080, 'sharePct': 40},
    {'leadBucket': '31-60 days', 'bucketOrder': 4, 'bookingCount': 6, 'roomNights': 18, 'adr': 210, 'revenueTotal': 3780, 'sharePct': 60},
  ]
  ..gets['/api/Hotel/reports/room-type-performance'] = [
    {'typeLabel': 'Deluxe', 'roomsInType': 10, 'bookingCount': 8, 'roomNights': 40, 'occupancyPct': 80, 'adr': 250, 'revpar': 200, 'revenueTotal': 10000},
    {'typeLabel': 'Suite', 'roomsInType': 2, 'bookingCount': 0, 'roomNights': 0, 'occupancyPct': 0, 'adr': 0, 'revpar': 0, 'revenueTotal': 0},
  ]
  ..gets['/api/Hotel/reports/length-of-stay'] = [
    {'losBucket': '1 night', 'bookingCount': 6, 'roomNights': 6, 'adr': 200, 'revenueTotal': 1200, 'sharePct': 30},
    {'losBucket': '2-3 nights', 'bookingCount': 5, 'roomNights': 12, 'adr': 230, 'revenueTotal': 2760, 'sharePct': 70},
  ]
  ..gets['/api/Hotel/reports/cancellations'] = [
    {'sourceLabel': 'Phone', 'cancelledCount': 3, 'bookedCount': 9, 'cancelRatePct': 33.3, 'nightsLost': 6, 'avgLeadDays': 4, 'valueLost': 1200, 'sharePct': 100},
  ]
  ..gets['/api/Hotel/reports/guest-ledger'] = [
    {'invoiceRef': 'INV-7', 'guestLabel': 'Kofi Mensah', 'issuedOn': '2026-06-01T00:00:00', 'dueOn': '2026-06-15T00:00:00', 'totalAmount': 900,
      'paidAmount': 100, 'balanceDue': 800, 'daysOutstanding': 130, 'ageBucket': 'Over 90 days'},
    {'invoiceRef': 'INV-9', 'guestLabel': 'Acme Ltd', 'issuedOn': '2026-10-20T00:00:00', 'totalAmount': 400, 'paidAmount': 0, 'balanceDue': 400,
      'daysOutstanding': 6, 'ageBucket': 'Current'},
  ]
  ..gets['/api/Hotel/reports/ancillary-revenue'] = [
    {'chargeLabel': 'Laundry', 'chargeCount': 12, 'qtyTotal': 30, 'staysTouched': 8, 'avgCharge': 25, 'revenueTotal': 300, 'sharePct': 100},
  ]
  ..gets['/api/Hotel/reports/housekeeping-productivity'] = [
    {'attendantLabel': 'Ama', 'tasksTotal': 40, 'tasksCompleted': 38, 'timedCount': 30, 'avgMinutes': 28, 'fastestMinutes': 15, 'slowestMinutes': 70,
      'roomsPerShift': 17.1, 'inspectedCount': 20},
    {'attendantLabel': 'Esi', 'tasksTotal': 5, 'tasksCompleted': 2, 'timedCount': 0, 'avgMinutes': 0, 'roomsPerShift': 0, 'inspectedCount': 0},
  ]
  ..gets['/api/Hotel/reports/loyalty'] = [
    {'tierLabel': 'Gold', 'memberCount': 12, 'activeMembers': 9, 'pointsBalance': 5400, 'lifetimePoints': 9000, 'earnedInPeriod': 800,
      'redeemedInPeriod': 200, 'sharePct': 25},
  ]
  ..gets['/api/Hotel/employee-loans/staff-report'] = [
    {'hotelStaffId': 1, 'staffName': 'Kwame Asante', 'staffIsActive': true, 'department': 'Front Desk', 'activeLoans': 1, 'outstanding': 450,
      'disbursedInPeriod': 500, 'repaidCashInPeriod': 50, 'repaidPayrollInPeriod': 0, 'interestInPeriod': 0, 'lastRepaymentDate': '2026-10-10'},
  ];

Future<void> openReport(WidgetTester tester, FakeApi api, String slug) async {
  await open(tester, hotelReportScreen(await sessionFor(api), hotel, slug)!, size: tallPhone);
}

void main() {
  test('the catalog: 27 reports in six groups; each registry slug is routed', () {
    expect(allHotelReports.length, 27);
    expect([for (final g in hotelReportGroups) g.label],
        ['Financial', 'Operations', 'Restaurant & Bar', 'Periodic Reports', 'Housekeeping & Inventory', 'Revenue Management']);
    expect(hotelReportDefs.length, 11);
    expect(pageScreens.containsKey('/hotel-reports'), isTrue);
    for (final slug in hotelReportDefs.keys) {
      expect(findHotelReport(slug), isNotNull, reason: slug);
      expect(pageScreens.containsKey('/hotel-reports/$slug'), isTrue, reason: slug);
    }
  });

  testWidgets('catalog page: header, groups, New badges', (tester) async {
    await open(tester, HotelReportsCatalogScreen(session: await sessionFor(FakeApi()), company: hotel), size: tallPhone);
    expect(find.textContaining('27 reports'), findsOneWidget);
    for (final t in ['FINANCIAL', 'OPERATIONS', 'RESTAURANT & BAR', 'PERIODIC REPORTS', 'HOUSEKEEPING & INVENTORY', 'REVENUE MANAGEMENT']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text('New'), findsNWidgets(11));
    await tester.tap(find.text('Source of Business'));
    await tester.pumpAndSettle();
    expect(find.text('Room nights and revenue by booking channel, with lead time'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  for (final slug in hotelReportDefs.keys) {
    testWidgets('$slug renders at phone width', (tester) async {
      await openReport(tester, reportsApi(), slug);
      expect(find.text('All reports'), findsOneWidget);
      expect(find.text(findHotelReport(slug)!.report.title), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Performance & KPIs: the split warning, the derived rows, the currency', (tester) async {
    await openReport(tester, reportsApi(), 'performance-kpis');
    expect(find.textContaining('recorded a total revenue figure but no room revenue'), findsOneWidget);
    expect(find.text('Gross operating profit'), findsWidgets);
    expect(find.text('GHS 40,000.00'), findsWidgets);
    expect(find.text('GOPPAR — operating profit / available rooms'), findsOneWidget);
  });

  testWidgets('Guest Ledger: no date filter, ageing buckets, totals', (tester) async {
    await openReport(tester, reportsApi(), 'guest-ledger');
    expect(find.text('This report shows the current position, so it has no date filter.'), findsOneWidget);
    expect(find.text('Over 90 days (1)'), findsOneWidget);
    expect(find.text('GHS 1,200.00'), findsOneWidget, reason: 'total owed');
  });

  testWidgets('a range preset reloads the report for the new dates', (tester) async {
    final api = reportsApi();
    await openReport(tester, api, 'source-of-business');
    await tester.tap(find.text('7 days'));
    await tester.pumpAndSettle();
    final last = api.requests.lastWhere((r) => r.url.path == '/api/Hotel/reports/source-of-business');
    expect(DateTime.parse(last.url.queryParameters['to']!).difference(DateTime.parse(last.url.queryParameters['from']!)).inDays, 6);
    expect(last.url.queryParameters['farmId'], 'h1');
  });
}
