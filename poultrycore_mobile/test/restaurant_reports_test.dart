// Restaurant → Reports (2026-10-20): the catalog, the shell (date modes,
// View PDF / CSV / Email) and every one of the 34 reports, against a fake API
// at phone width.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/reports/report_export.dart';
import 'package:poultrycore_mobile/pages/restaurant/reports/restaurant_report_routes.dart';
import 'package:poultrycore_mobile/pages/restaurant/reports/restaurant_reports_catalog.dart';

import 'support/harness.dart';

final rest = Company(farmId: 'farm-1', name: 'Rose Bistro', type: CompanyType.restaurant, role: 'Admin');
const tall = Size(390, 5000);

FakeApi api() => FakeApi()..gets['/api/Restaurant/setup/profile'] = {'restaurantName': 'Rose Bistro', 'defaultCurrency': 'GHS', 'city': 'Accra'};

Future<void> openReport(WidgetTester tester, FakeApi a, String slug) async {
  final s = await sessionFor(a);
  await open(tester, Builder(builder: (_) => restaurantReportScreen(s, rest, slug)!), size: tall);
}

void main() {
  test('catalog: 34 reports in six groups, a route for every slug and the old ones', () {
    expect(allRestaurantReports.length, 34);
    expect([for (final g in restaurantReportGroups) g.label], ['Money', 'Cash & Ledger', 'Sales', 'Menu & Food', 'Operations', 'Guests & Channels']);
    for (final r in allRestaurantReports) {
      expect(restaurantReportRegistry.containsKey(r.slug), isTrue, reason: r.slug);
      expect(pageScreens.containsKey('/restaurant-reports/${r.slug}'), isTrue, reason: r.slug);
    }
    expect(pageScreens.containsKey('/restaurant-reports'), isTrue);
    expect(pageScreens.containsKey('/restaurant-reports/overview'), isTrue, reason: 'legacy slugs still land');
  });

  testWidgets('catalog opens a report', (tester) async {
    final a = api();
    await open(tester, RestaurantReportsCatalogScreen(session: await sessionFor(a), company: rest), size: tall);
    expect(find.text('34 reports. Every one takes a date range, previews as a PDF before you download it, and exports to CSV.'), findsOneWidget);
    await tester.tap(find.text('Top Selling Items'));
    await tester.pumpAndSettle();
    expect(find.text('Best sellers by revenue, quantity and order count'), findsOneWidget);
    expect(a.requests.any((r) => r.url.path == '/api/Restaurant/reports/sales-by-item' && r.url.queryParameters['from'] != null), isTrue);
  });

  testWidgets('every report opens empty, and exports are disabled', (tester) async {
    for (final r in allRestaurantReports) {
      final a = api();
      await openReport(tester, a, r.slug);
      expect(tester.takeException(), isNull, reason: r.slug);
      expect(find.text(r.title), findsWidgets, reason: r.slug);
      final csv = tester.widget<OutlinedButton>(find.ancestor(of: find.text('CSV'), matching: find.byType(OutlinedButton)));
      expect(csv.onPressed, isNull, reason: '${r.slug}: nothing to export');
      if (r.dateMode == 'none') expect(find.text('This report shows the current position, so it has no date filter.'), findsOneWidget);
    }
  });

  testWidgets('P&L: tiles, statement, ratios and the expense table', (tester) async {
    final a = api()
      ..gets['/api/Restaurant/reports/pnl'] = {
        'revenue': 1000, 'cogs': 300, 'grossProfit': 700, 'grossMarginPct': 70, 'expensesTotal': 200, 'netProfit': 500, 'netMarginPct': 50,
        'foodCostPct': 30, 'tipsTotal': 40, 'orderCount': 25,
      }
      ..gets['/api/Restaurant/reports/pnl-expenses'] = [
        {'expenseCategory': 'Rent', 'entryCount': 1, 'expenseTotal': 200, 'sharePct': 100},
      ];
    await openReport(tester, a, 'pnl');
    expect(find.text('GHS 700.00 (70.0%)'), findsOneWidget);
    expect(find.text('- GHS 300.00'), findsOneWidget);
    expect(find.text('Rent'), findsOneWidget);
    expect(find.text('30.0%'), findsOneWidget, reason: 'food cost ratio badge');
  });

  testWidgets('Daily Sales: single day with a stepper; the derived rows; CSV and email', (tester) async {
    final shared = <(String, List<int>)>[];
    ReportExport.sharer = (name, bytes, mime, subject) async => shared.add((name, bytes));
    final a = api()
      ..gets['/api/Restaurant/reports/daily-sales'] = {
        'totalRevenue': 450, 'netRevenue': 400, 'totalOrders': 9, 'completedOrders': 8, 'avgTicket': 56.25, 'totalCovers': 20, 'cashAmount': 300,
      };
    await openReport(tester, a, 'daily-sales');
    expect(find.text('8 of 9'), findsOneWidget);
    expect(find.text('Mobile money'), findsOneWidget, reason: 'the day in full');
    final first = a.requests.lastWhere((r) => r.url.path == '/api/Restaurant/reports/daily-sales').url.queryParameters['date']!;
    await tester.tap(find.byTooltip('Previous day'));
    await tester.pumpAndSettle();
    final prev = a.requests.lastWhere((r) => r.url.path == '/api/Restaurant/reports/daily-sales').url.queryParameters['date']!;
    expect(DateTime.parse(first).difference(DateTime.parse(prev)).inDays, 1);

    await tester.tap(find.text('CSV'));
    await tester.pumpAndSettle();
    final csv = utf8.decode(shared.last.$2.skip(3).toList());
    expect(shared.last.$1, 'daily-sales-$prev.csv');
    expect(csv, contains('"Daily Sales","$prev"'));
    expect(csv, contains('"Revenue","GHS 450.00"'));
    expect(csv, contains('"Metric","Value"'));

    await tester.tap(find.text('Email'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'owner@example.com, accountant@example.com'), 'boss@x.com');
    await tester.tap(find.text('CSV spreadsheet', findRichText: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    final w = a.writes.last;
    expect(w.url.path, '/api/Email/Report');
    expect(find.textContaining('CSV sent to boss@x.com.', findRichText: true), findsOneWidget);
  });

  testWidgets('Revenue Trend: presets reload the range', (tester) async {
    final a = api()
      ..gets['/api/Restaurant/reports/revenue-trend'] = [
        {'reportDate': '2026-10-01T00:00:00', 'orderCount': 4, 'totalRevenue': 200, 'avgTicket': 50},
      ];
    await openReport(tester, a, 'revenue-trend');
    expect(find.text('2026-10-01 — GHS 200.00'), findsOneWidget);
    await tester.tap(find.text('7 days'));
    await tester.pumpAndSettle();
    final q = a.requests.lastWhere((r) => r.url.path == '/api/Restaurant/reports/revenue-trend').url.queryParameters;
    expect(DateTime.parse(q['to']!).difference(DateTime.parse(q['from']!)).inDays, 6);
  });

  testWidgets('Cash Movement: days from the cash flow, net coloured', (tester) async {
    final a = api()
      ..gets['/api/Restaurant/cash-flow'] = {
        'summary': {'openingCash': 100, 'moneyIn': 300, 'moneyOut': 50, 'netCashFlow': 250, 'closingCash': 350},
        'rows': [
          {'transactionDate': '2026-10-02', 'amount': 300},
          {'transactionDate': '2026-10-03', 'amount': -50},
        ],
      };
    await openReport(tester, a, 'cash-movement');
    expect(find.text('GHS 400.00'), findsOneWidget, reason: 'cash at end of the first day');
    expect(find.text('GHS 350.00'), findsWidgets);
    expect(a.requests.any((r) => r.url.path == '/api/Restaurant/cash-flow' && r.url.queryParameters['fromDate'] != null), isTrue);
  });

  testWidgets('the panel reports draw with data at phone width', (tester) async {
    final a = api()
      ..gets['/api/Restaurant/cash-flow'] = {
        'summary': {'openingCash': 100, 'moneyIn': 300, 'moneyOut': 50, 'netCashFlow': 250, 'closingCash': 350, 'operatingIn': 300, 'operatingOut': 50},
        'rows': [
          {'transactionDate': '2026-10-02', 'amount': 300, 'category': 'Sale', 'flowGroup': 'Operating', 'accountName': 'Main till'},
          {'transactionDate': '2026-10-03', 'amount': -50, 'category': 'Expense', 'flowGroup': 'Operating'},
        ],
      }
      ..gets['/api/Restaurant/finance/ledger/period'] = [
        {'cashAccountId': 1, 'name': 'Main till with a very long account name', 'accountType': 'Till', 'isActive': true, 'openingBalance': 100,
          'moneyIn': 300, 'moneyOut': 50, 'transfersIn': 0, 'transfersOut': 0, 'closingBalance': 350, 'currentBalance': 350, 'ledgerBalance': 350},
      ]
      ..gets['/api/Restaurant/finance/transfers'] = [
        {'transferId': 1, 'transferDate': '2026-10-02', 'transferNumber': 'TR-1', 'fromAccountName': 'Till', 'toAccountName': 'Bank', 'amount': 20, 'status': 'Posted'},
      ]
      ..gets['/api/Restaurant/finance/loans'] = [
        {'loanId': 1, 'loanNumber': 'LN-1', 'lenderName': 'Bank', 'principal': 1000, 'amountReceived': 1000, 'principalRepaid': 100,
          'outstandingPrincipal': 900, 'interestPaid': 10, 'feesPaid': 0, 'status': 'Active', 'loanDate': '2026-10-01'},
      ]
      ..gets['/api/Restaurant/finance/reports/profit-vs-cash'] = [
        {'lineKey': 'net_profit', 'label': 'Net profit', 'amount': 500, 'kind': 'start'},
        {'lineKey': 'stock', 'label': 'Stock bought but not yet used', 'amount': -120, 'kind': 'adjust', 'explanation': 'Paid now, expensed when used'},
        {'lineKey': 'net_cash', 'label': 'Net cash flow', 'amount': 380, 'kind': 'result'},
      ]
      ..gets['/api/Restaurant/finance/reports/takings-by-account'] = [
        {'accountName': 'Main till', 'accountType': 'Till', 'paymentMethod': 'Cash', 'paymentCount': 3, 'takings': 300, 'tips': 10, 'refunds': 0, 'netTotal': 310},
      ]
      ..gets['/api/Restaurant/reports/menu-engineering'] = [
        {'itemLabel': 'Jollof', 'categoryLabel': 'Mains', 'qtySold': 40, 'unitMargin': 30, 'revenueTotal': 2000, 'menuClass': 'Star'},
      ]
      ..gets['/api/Restaurant/reports/kitchen-performance'] = [
        {'stationName': 'Grill', 'itemsMade': 10, 'avgQueueMins': 4, 'avgPrepMins': 14, 'avgTicketMins': 18, 'overTargetCount': 3},
      ];
    for (final slug in ['cash-flow-detail', 'cash-accounts', 'money-movement', 'profit-vs-cash', 'takings-by-account', 'menu-engineering', 'kitchen-performance']) {
      await openReport(tester, a, slug);
      expect(tester.takeException(), isNull, reason: slug);
    }
    expect(find.text('18m'), findsWidgets, reason: 'the tile and the red Avg ticket cell');
  });
}
