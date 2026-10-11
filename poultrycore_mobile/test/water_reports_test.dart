// Water → Reports, driven against a fake API at phone width: the catalogue,
// the shared report kit (range, filters, tiles, cards), every dropdown, and
// the bespoke pages (cash, daily summary, operational, P&L).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/lookup_loader.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/reports/report_format.dart' show FarmMoney;
import 'package:poultrycore_mobile/pages/shared/business_dates.dart';
import 'package:poultrycore_mobile/pages/water/reports/water_report_routes.dart';
import 'package:poultrycore_mobile/pages/water/reports/water_reports_catalog_screen.dart';

import 'support/harness.dart';

final water = Company(farmId: 'farm-1', name: 'Win Water', type: CompanyType.water);
final today = isoDay(DateTime.now());

Future<void> see(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 250, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

Uri lastGet(FakeApi api, String path) => api.requests.lastWhere((r) => r.method == 'GET' && r.url.path == path).url;

Future<void> openReport(WidgetTester tester, FakeApi api, String slug) async =>
    open(tester, waterReportBySlug[slug]!(await sessionFor(api), water), size: phone);

void main() {
  setUp(() {
    LookupLoader.clear();
    FarmMoney.clearCache();
  });

  test('every catalogue report has a native screen and a page route', () {
    final slugs = [for (final g in waterReportGroups) for (final r in g.reports) r.slug];
    expect(slugs.length, 27);
    for (final s in slugs) {
      expect(waterReportBySlug.containsKey(s), isTrue, reason: s);
      expect(pageScreens.containsKey('/water-reports/$s'), isTrue, reason: s);
    }
    expect(pageScreens.containsKey('/water-reports'), isTrue);
  });

  testWidgets('every report opens at phone width with no data, and with a row', (tester) async {
    final row = {
      'waterSaleId': 1, 'saleDate': today, 'productionDate': today, 'purchaseDate': today, 'createdDate': today,
      'closingDate': today, 'loadDate': today, 'lossDate': today, 'usedDate': today, 'expenseDate': today,
      'name': 'Thing', 'itemName': 'Thing', 'driverName': 'Kojo', 'routeName': 'East', 'supplierName': 'Acme',
      'customerName': 'Ama', 'categoryName': 'Fuel', 'status': 'Approved', 'quantity': 3, 'totalAmount': 10,
      'bagsProduced': 5, 'waterProductId': 1, 'waterVehicleId': 1, 'waterVehicleLoadingId': 1, 'vehicleName': 'Truck',
      'waterCustomerId': 1, 'waterDriverId': 1,
    };
    for (final withData in [false, true]) {
      final api = FakeApi();
      if (withData) {
        for (final p in [
          '/api/Water/sales', '/api/Water/production-batches', '/api/Water/raw-material-purchases', '/api/Water/stock/transactions',
          '/api/Water/daily-closings', '/api/Water/vehicle-loadings', '/api/Water/driver-returns', '/api/Water/loss-records',
          '/api/Water/production-losses', '/api/Water/expenses', '/api/Water/products', '/api/Water/raw-material-items',
          '/api/Water/vehicles', '/api/Water/customers', '/api/Water/reports/expense-by-category',
          '/api/Water/reports/supplier-activity', '/api/Water/reports/driver-reconciliation',
          '/api/Water/reports/route-profitability', '/api/Water/reports/raw-material-variance',
          '/api/Water/raw-material-usage/history', '/api/Water/reports/top-customers',
        ]) {
          api.gets[p] = [row];
        }
      }
      final s = await sessionFor(api);
      for (final e in waterReportBySlug.entries) {
        await open(tester, e.value(s, water), size: phone);
        expect(tester.takeException(), isNull, reason: '${e.key} (data: $withData)');
      }
    }
  });

  testWidgets('catalogue: four groups, 27 reports, and a row opens its report', (tester) async {
    final api = FakeApi()
      ..gets['/api/Water/sales'] = [
        {'waterSaleId': 7, 'saleDate': '${today}T09:00:00', 'customerName': 'Ama', 'totalAmount': 100, 'amountPaid': 60, 'status': 'Posted'},
      ];
    await open(tester, WaterReportsCatalogScreen(session: await sessionFor(api), company: water), size: phone);
    expect(find.text('27 reports — each with its own filters, summary cards and PDF export.'), findsOneWidget);
    expect(find.text('FINANCIAL'), findsOneWidget);
    await see(tester, find.text('Sales Report'));
    await tester.tap(find.text('Sales Report'));
    await tester.pumpAndSettle();
    expect(find.text('WIN WATER'), findsOneWidget);
    expect(find.text('Ama'), findsOneWidget);
  });

  testWidgets('Sales Report: client-side range filter, tiles and the card', (tester) async {
    final api = FakeApi()
      ..gets['/api/Water/sales'] = [
        {'waterSaleId': 7, 'saleDate': '${today}T09:00:00', 'customerName': 'Ama', 'totalAmount': 100, 'amountPaid': 60, 'status': 'Posted'},
        {'waterSaleId': 8, 'saleDate': '2020-01-01', 'customerName': 'Old', 'totalAmount': 50, 'amountPaid': 50},
      ];
    await openReport(tester, api, 'sales-report');
    expect(find.text('Ama'), findsOneWidget, reason: 'Customer, in the two-up grid');
    expect(find.text(today), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('2020-01-01'), findsNothing, reason: 'outside the last 30 days');
    expect(find.text('SALES COUNT'), findsOneWidget);
    expect(find.text('GHC 40.00'), findsWidgets, reason: 'outstanding tile and balance cell');
    expect(find.text('Manual'), findsOneWidget, reason: 'sourceType ?? "Manual"');
  });

  testWidgets('Payments Received: reversed left out, By method roll-up, from/to sent', (tester) async {
    final api = FakeApi()
      ..gets['/api/Water/customer-payments'] = [
        {'paymentId': 'abcdef123456', 'paymentDate': today, 'partyName': 'Ama', 'allocationCount': 2, 'paymentMethod': 'MoMo', 'totalAmount': 30},
        {'paymentId': 'x2', 'paymentNumber': 'PAY-2', 'paymentDate': today, 'partyName': 'Kofi', 'paymentMethod': 'Cash', 'totalAmount': 50},
        {'paymentId': 'x3', 'paymentDate': today, 'partyName': 'Gone', 'paymentMethod': 'Cash', 'totalAmount': 999, 'status': 'Reversed'},
      ];
    await openReport(tester, api, 'payments-received');
    final q = lastGet(api, '/api/Water/customer-payments').queryParameters;
    expect(q['from'], isNotNull);
    expect(q['to'], today);
    expect(find.text('BY METHOD'), findsOneWidget);
    expect(find.text('Gone'), findsNothing);
    await see(tester, find.text('#abcdef12'));
    expect(find.text('2 sales'), findsOneWidget);
    expect(find.text('PAY-2'), findsOneWidget);
  });

  testWidgets('Customer Sales History: picks a customer, then loads sales and payments', (tester) async {
    final api = FakeApi()
      ..gets['/api/Water/customers'] = [
        {'waterCustomerId': 4, 'name': 'Mama Ama'},
      ]
      ..gets['/api/Water/sales'] = [
        {'waterSaleId': 11, 'waterCustomerId': 4, 'saleDate': today, 'totalAmount': 80, 'amountPaid': 30, 'status': 'Posted'},
      ]
      ..gets['/api/Water/payments/by-sale/11'] = [
        {'paymentDate': today, 'amount': 30, 'paymentMethod': 'Cash'},
      ];
    await openReport(tester, api, 'customer-history');
    expect(find.text('Pick a customer above to load their history.'), findsOneWidget);
    await see(tester, find.text('Pick customer…'));
    await pick(tester, 'Pick customer…', 'Mama Ama');
    expect(find.textContaining('Customer: ', findRichText: true), findsWidgets);
    await see(tester, find.text('$today · Cash · GHC 30.00'));
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await tester.pumpAndSettle();
    expect(find.textContaining('Customer = Mama Ama', findRichText: true), findsOneWidget);
  });

  testWidgets('Top Customers: Show dropdown sends topN; Clear filters puts it back', (tester) async {
    final api = FakeApi()..gets['/api/Water/reports/top-customers'] = [];
    await openReport(tester, api, 'top-customers');
    expect(lastGet(api, '/api/Water/reports/top-customers').queryParameters['topN'], '10');
    await see(tester, find.text('Top 10'));
    await pick(tester, 'Top 10', 'Top 20');
    expect(lastGet(api, '/api/Water/reports/top-customers').queryParameters['topN'], '20');
    expect(find.text('No customer sales in this period.'), findsOneWidget);
    await see(tester, find.text('Clear filters'));
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(lastGet(api, '/api/Water/reports/top-customers').queryParameters['topN'], '10');
  });

  testWidgets('Driver Collection: driver dropdown sends waterDriverId; both sections render', (tester) async {
    final api = FakeApi()
      ..gets['/api/Water/drivers'] = [
        {'waterDriverId': 3, 'driverName': 'Kojo'},
      ]
      ..gets['/api/Water/reports/driver-collection'] = {
        'totals': [
          {'waterDriverId': 3, 'driverName': 'Kojo', 'deliveryRuns': 2, 'reconciledRuns': 1, 'cashCollected': 100},
        ],
        'detail': [
          {'driverName': 'Kojo', 'productName': 'Sachet 500', 'bagsLoaded': 40},
        ],
      };
    await openReport(tester, api, 'driver-collection');
    expect(lastGet(api, '/api/Water/reports/driver-collection').queryParameters.containsKey('waterDriverId'), isFalse);
    await see(tester, find.text('All drivers'));
    await pick(tester, 'All drivers', 'Kojo');
    expect(lastGet(api, '/api/Water/reports/driver-collection').queryParameters['waterDriverId'], '3');
    await see(tester, find.text('TOTALS BY DRIVER'));
    await see(tester, find.text('DETAIL BY PRODUCT'));
    expect(find.text('Sachet 500'), findsOneWidget);
  });

  testWidgets('Inventory: point-in-time, Low and Out worked out as the web does', (tester) async {
    final api = FakeApi()
      ..gets['/api/Water/products'] = [
        {'name': 'Sachet', 'stockOnHand': 0, 'unitPrice': 5},
      ]
      ..gets['/api/Water/raw-material-items'] = [
        {'itemName': 'Film', 'currentQuantity': 2, 'minimumStockAlert': 5, 'unitOfMeasure': 'roll'},
      ];
    await openReport(tester, api, 'inventory-report');
    expect(find.text('Period'), findsNothing);
    expect(find.text('Out'), findsOneWidget);
    expect(find.text('Low'), findsOneWidget);
  });

  testWidgets('Cash Movement: newest first, running balance from opening cash', (tester) async {
    final api = FakeApi()
      ..gets['/api/Water/cash-flow'] = {
        'summary': {'openingCash': 100, 'moneyIn': 50, 'moneyOut': 20, 'netCashFlow': 30, 'closingCash': 130},
        'rows': [
          {'id': 1, 'rowSource': 'Receipt', 'sourceId': 9, 'flowGroup': 'OperatingIn', 'category': 'Sales', 'transactionDate': '2026-10-01', 'amount': 50},
          {'id': 2, 'rowSource': 'Expense', 'sourceId': 4, 'flowGroup': 'OperatingOut', 'category': 'Fuel', 'transactionDate': '2026-10-02', 'amount': -20},
        ],
      };
    await openReport(tester, api, 'cash-movement');
    expect(find.text('OPENING CASH BALANCE'), findsOneWidget);
    await see(tester, find.text('Expense #4'));
    // The newest row (the expense) carries the closing running balance.
    expect(find.text('GHC 130.00'), findsWidgets);
    expect(find.text('Payment · sale #9'), findsOneWidget);
  });

  testWidgets('Cash Flow Detail: breakdown panels and the Every movement list', (tester) async {
    final api = FakeApi()
      ..gets['/api/Water/cash-flow'] = {
        'summary': {'openingCash': 0, 'moneyIn': 50, 'moneyOut': 0, 'operatingIn': 50, 'closingCash': 50},
        'rows': [
          {'id': 1, 'rowSource': 'Receipt', 'sourceId': 9, 'flowGroup': 'OperatingIn', 'category': 'Sales', 'transactionDate': today, 'amount': 50},
        ],
      };
    await openReport(tester, api, 'cash-flow-detail');
    await see(tester, find.text('Money in by source'));
    expect(find.text('Nothing was paid out during this period.'), findsOneWidget);
    await see(tester, find.text('EVERY MOVEMENT'));
  });

  testWidgets('Cash Account Report and Money Movement read the Water endpoints', (tester) async {
    final api = FakeApi();
    await openReport(tester, api, 'cash-accounts');
    expect(api.requests.any((r) => r.url.path == '/api/Water/cash-accounts'), isTrue);
    expect(api.requests.any((r) => r.url.path.startsWith('/api/Poultry')), isFalse);
    await openReport(tester, api, 'money-movement');
    expect(api.requests.any((r) => r.url.path == '/api/Water/owner-money'), isTrue);
    expect(find.textContaining("company's own accounts", findRichText: true), findsWidgets);
  });

  testWidgets("Daily Business Summary: income from the day's closing", (tester) async {
    final api = FakeApi()
      ..gets['/api/Water/daily-closings'] = [
        {'closingDate': '${today}T00:00:00', 'status': 'Approved', 'totalIncome': 500, 'bagsSold': 40},
      ]
      ..gets['/api/Water/expenses'] = [
        {'expenseDate': today, 'status': 'Approved', 'categoryName': 'Fuel', 'amount': 25},
      ];
    await openReport(tester, api, 'daily-summary');
    expect(find.text('GHC 500.00'), findsOneWidget);
    expect(find.text("Income figures are taken from the day's closing (storefront + delivery sales combined)."), findsOneWidget);
    await see(tester, find.text('Fuel'));
    expect(find.text('Approved'), findsOneWidget, reason: 'closing status card');
  });

  testWidgets('Operational dashboard: tabs with counts, and 30d reloads', (tester) async {
    final api = FakeApi()
      ..gets['/api/Water/reports/period-pnl'] = {'periodStart': '2026-10-01', 'periodEnd': '2026-10-08', 'netProfit': -5, 'profitMarginPct': -2}
      ..gets['/api/Water/reports/route-profitability'] = [
        {'routeName': 'East', 'totalBagsLoaded': 10},
      ];
    await openReport(tester, api, 'operational');
    expect(find.text('Route profitability (1)'), findsOneWidget);
    expect(find.text('-2.0%'), findsOneWidget);
    await tester.tap(find.text('30d'));
    await tester.pumpAndSettle();
    expect(lastGet(api, '/api/Water/reports/period-pnl').queryParameters['fromDate'],
        isoDay(DateTime.now().subtract(const Duration(days: 30))));
    await tester.ensureVisible(find.text('Route profitability (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Route profitability (1)'));
    await tester.pumpAndSettle();
    expect(find.text('East'), findsOneWidget);
  });

  testWidgets('Profit & Loss: statement bands, and a line opens its drilldown with a filter', (tester) async {
    final api = FakeApi()
      ..gets['/api/Water/profit-loss'] = {
        'summary': {'totalRevenue': 100, 'grossProfit': 60, 'operatingProfit': 50, 'netProfit': 40, 'entryCount': 3},
        'lines': [
          {'section': 'Revenue', 'lineKey': 'Storefront', 'lineLabel': 'Storefront sales', 'amount': 100, 'entryCount': 2},
          {'section': 'DirectCost', 'lineKey': 'RawMaterials', 'lineLabel': 'Raw materials', 'amount': 40, 'entryCount': 1},
        ],
      }
      ..gets['/api/Water/profit-loss/detail'] = [
        {'entryDate': '2026-10-02', 'reference': 'S-1', 'party': 'Ama', 'amount': 60},
        {'entryDate': '2026-10-03', 'reference': 'S-2', 'party': 'Kofi', 'amount': 40},
      ];
    await openReport(tester, api, 'profit-loss');
    expect(find.text('REVENUE'), findsWidgets);
    await see(tester, find.text('Storefront sales'));
    await tester.tap(find.text('Storefront sales'));
    await tester.pumpAndSettle();
    expect(lastGet(api, '/api/Water/profit-loss/detail').queryParameters['kind'], 'revenue');
    expect(find.text('2 record(s)'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'kofi');
    await tester.pumpAndSettle();
    expect(find.text('1 record(s)'), findsOneWidget);
    expect(find.text('filtered · GHC 100.00 in full'), findsOneWidget);
  });
}
