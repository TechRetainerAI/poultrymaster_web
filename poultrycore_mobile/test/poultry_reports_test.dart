// Poultry → Reports: the shared report engine and the catalogue, driven
// against a fake API at phone width.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/pages/lookup_loader.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/poultry/reports/dashboard_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/reports/poultry_report_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/reports/profit_loss_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/reports/report_export.dart';
import 'package:poultrycore_mobile/pages/poultry/reports/report_format.dart';
import 'package:poultrycore_mobile/pages/poultry/reports/reports_catalog_screen.dart';

import 'support/harness.dart';

final _list = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;

Future<void> _see(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 250, scrollable: _list);
  await tester.pumpAndSettle();
}

Map<String, dynamic> flockRow(int i, {int eggs = 100}) => {
      'flockId': i, 'flockName': 'Flock $i', 'flockAgeWeeks': 20 + i, 'birdsPlaced': 1000, 'currentBirds': 950,
      'totalEggs': eggs, 'averageDailyEggs': 10, 'peakDailyEggs': 30, 'brokenEggs': 2, 'productionPercent': 81.25,
      'feedConsumedKg': 50.5, 'deaths': 1, 'status': 'Active',
    };

void main() {
  setUp(() {
    LookupLoader.clear();
    FarmMoney.clearCache();
  });

  group('formatting', () {
    test('periods, money and labels follow the web', () {
      final today = DateTime(2026, 10, 2); // a Friday
      expect(periodToRange('thisWeek', today), (from: '2026-09-28', to: '2026-10-04'));
      expect(periodToRange('lastQuarter', today), (from: '2026-07-01', to: '2026-09-30'));
      expect(periodToRange('lastMonth', today), (from: '2026-09-01', to: '2026-09-30'));
      expect(rangeToPeriod('2026-09-03', '2026-10-02', today), 'last30');
      expect(rangeToPeriod('2026-09-04', '2026-10-02', today), 'custom');
      expect(const FarmMoney()(1234.5), 'GHC 1,234.50');
      expect(const FarmMoney(showSymbol: false)(-12), '-12.00');
      expect(categoryLabel('OwnerInjection'), 'Owner injection');
      expect(categoryLabel('SomeNewSource'), 'Some New Source');
      expect(categoryLabel('Feed'), 'Feed');
      expect(flowGroupLabel('FinancingIn'), 'Capital received');
      expect(ReportExport.latin('A — B → GH₵ 5'), 'A - B -> GHC 5');
    });

    test('cash flow analysis reads like the web', () {
      String fmt(num n) => 'GHC ${fixed2(n)}';
      final items = buildCashFlowAnalysis({
        'moneyIn': 1000, 'moneyOut': 1500, 'netCashFlow': -500, 'cashAtHand': 3000, 'daysInPeriod': 30,
        'operatingIn': 1000, 'operatingOut': 1500, 'financingIn': 0, 'financingOut': 0,
        'moneyOutByCategory': [
          {'label': 'Feed', 'amount': 900, 'sharePercent': 60},
          {'label': 'Payroll', 'amount': 400, 'sharePercent': 26.7},
          {'label': 'Other', 'amount': 200, 'sharePercent': 13.3},
        ],
      }, fmt);
      expect(items.first.title, 'Spent GHC 500.00 more than came in');
      expect(items.map((i) => i.id), containsAll(['operating-shortfall', 'top-outflow', 'runway']));
      expect(items.firstWhere((i) => i.id == 'top-outflow').tone, 'watch');
      expect(items.firstWhere((i) => i.id == 'runway').title, 'About 180 days of cash at this rate');
    });
  });

  group('report screen', () {
    testWidgets('cards, notices, sortable cards, totals, pagination, flock filter, exports', (tester) async {
      final shared = <(String, List<int>, String)>[];
      ReportExport.sharer = (name, bytes, mime, subject) async => shared.add((name, bytes, mime));
      final api = FakeApi()
        ..gets['/api/Water/farm-settings'] = {'currencyCode': 'GHS', 'currencySymbol': 'GH₵', 'showCurrencySymbol': true}
        ..gets['/api/Flock'] = [
          {'flockId': 1, 'name': 'Flock 1'},
          {'flockId': 2, 'name': 'Flock 2'},
        ]
        ..gets['/api/poultry/reports/flock-production-summary'] = {
          'summary': {
            'activeFlocks': 12, 'bestProducingFlock': 'Flock 3', 'lowestProducingFlock': null, 'totalEggs': 1200,
            'averageEggsPerFlock': 100, 'averageProductionPercent': 80.5,
          },
          'rows': [for (var i = 1; i <= 12; i++) flockRow(i, eggs: 100 + i)],
          'warnings': ['Feed is not recorded for 2 flocks.'],
          'notes': ['Ages are as of the end date.'],
        };
      await open(tester, PoultryReportScreen(session: await sessionFor(api), company: company, slug: 'flock-production-summary'),
          size: phone);

      expect(find.text('Poultry Flock Production Summary Report'), findsWidgets);
      expect(find.textContaining('GHS (GH₵)', findRichText: true), findsOneWidget);
      final call = api.requests.lastWhere((r) => r.url.path == '/api/poultry/reports/flock-production-summary');
      expect(call.url.queryParameters['datePreset'], 'last30');
      expect(call.url.queryParameters.containsKey('flockId'), isFalse);

      await _see(tester, find.text('Feed is not recorded for 2 flocks.'));
      expect(find.text('Ages are as of the end date.'), findsOneWidget);
      await _see(tester, find.text('80.5%'));
      expect(find.text('Flock 3'), findsWidgets);
      expect(find.text('—'), findsWidgets, reason: 'a null text card');

      // Cards: first value in the strip, then each column.
      await _see(tester, find.text('#1'));
      expect(find.text('Flock 1'), findsWidgets);
      expect(find.text('81.3%'), findsWidgets, reason: 'pct is toFixed(1)');
      expect(find.text('#11'), findsNothing, reason: '10 per page');
      await _see(tester, find.text('Total — 12 flocks'));
      expect(find.text('12,000'), findsOneWidget, reason: 'birds placed summed');
      expect(find.text('Showing 1–10 of 12'), findsOneWidget);
      await tester.tap(find.text('2').last);
      await tester.pumpAndSettle();
      expect(find.text('Showing 11–12 of 12'), findsOneWidget);

      // Sort by Total eggs, descending: Flock 12 first.
      await tester.drag(_list, const Offset(0, 6000));
      await tester.pumpAndSettle();
      await _see(tester, find.text('No sorting'));
      await tester.tap(find.text('No sorting'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Total eggs').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Asc'));
      await tester.pumpAndSettle();
      await _see(tester, find.text('#1'));
      final firstCard = find.ancestor(of: find.text('#1'), matching: find.byType(Row)).first;
      expect(find.descendant(of: firstCard, matching: find.text('Flock 12')), findsOneWidget);

      // Flock filter re-fetches with flockId.
      await tester.drag(_list, const Offset(0, 6000));
      await tester.pumpAndSettle();
      await _see(tester, find.text('All flocks'));
      await tester.tap(find.text('All flocks'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Flock 2').last);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(api.requests.last.url.queryParameters['flockId'], '2');

      // Exports.
      await tester.drag(_list, const Offset(0, 6000));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CSV'));
      await tester.pumpAndSettle();
      final csv = utf8.decode(shared.last.$2.sublist(3));
      expect(shared.last.$1, startsWith('poultry-flock-production-summary-'));
      expect(csv, contains('"Poultry Flock Production Summary Report"'));
      expect(csv, contains('"Flock","Age (wks)","Birds placed"'));
      expect(csv, contains('"Total — 12 flocks"'));

      await tester.tap(find.text('PDF'));
      await tester.pumpAndSettle();
      expect(shared.last.$3, 'application/pdf');
      expect(String.fromCharCodes(shared.last.$2.take(4)), '%PDF');

      await tester.tap(find.text('Email'));
      await tester.pumpAndSettle();
      expect(find.text('Email “Poultry Flock Production Summary Report”'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).last, 'owner@farm.com, bad');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid email address'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).last, 'owner@farm.com; acc@farm.com');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      final mail = api.writes.lastWhere((w) => w.url.path == '/api/Email/Report');
      final body = utf8.decode(mail.bodyBytes, allowMalformed: true);
      expect(body, contains('owner@farm.com,acc@farm.com'));
      expect(body, contains('Poultry Flock Production Summary Report'));
      expect(body, contains('%PDF'));
      // Queued behind the "valid address" message.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Report emailed. Sent to 2 recipients.'), findsOneWidget);
    });

    testWidgets('P&L by flock shows Revenue / Expenses cards per flock, no table', (tester) async {
      final api = FakeApi()
        ..gets['/api/poultry/reports/profit-loss-by-flock'] = {
          'summary': {'totalRevenue': 5000, 'totalExpenses': 3000, 'netProfit': -10, 'mostProfitableFlock': 'A'},
          'rows': [
            {
              'flockName': 'A', 'eggRevenue': 5000, 'feedCost': 2000, 'medicineVaccineCost': 100, 'laborCost': 500,
              'otherExpenses': 400, 'totalRevenue': 5000, 'totalCost': 3000, 'netProfit': 2000, 'profitPerEgg': 0.5,
              'status': 'Profit',
            },
          ],
        };
      await open(tester, PoultryReportScreen(session: await sessionFor(api), company: company, slug: 'profit-loss-by-flock'),
          size: phone);
      await _see(tester, find.text('REVENUE DETAILS'));
      expect(find.text('GHC 5,000.00'), findsWidgets);
      await _see(tester, find.text('EXPENSES DETAILS'));
      expect(find.text('GHC 3,000.00'), findsWidgets, reason: 'Total cost headlines the expenses card');
      expect(find.text('Net profit'), findsNothing, reason: 'net profit stays in the KPI strip only');
      expect(find.text('No sorting'), findsNothing, reason: 'no table');
      expect(find.text('Revenue breakdown'), findsNothing, reason: 'hidden under tableAsCards');
    });

    testWidgets('cash flow detail: analysis and breakdown bars', (tester) async {
      final api = FakeApi()
        ..gets['/api/poultry/reports/cash-flow-detail'] = {
          'summary': {
            'openingBalance': 100, 'moneyIn': 1000, 'moneyOut': 400, 'cashAtHand': 700, 'netCashFlow': 600,
            'operatingIn': 1000, 'operatingOut': 400, 'daysInPeriod': 30,
            'moneyInByCategory': [{'label': 'Sale', 'amount': 1000, 'sharePercent': 100}],
            'moneyOutByCategory': [{'label': 'Expense', 'amount': 400, 'sharePercent': 100}],
          },
          'rows': [
            {'date': '2026-09-30T00:00:00', 'flowGroup': 'OperatingIn', 'category': 'CustomerPayment', 'inflow': 1000, 'outflow': 0, 'runningBalance': 1100},
          ],
        };
      await open(tester, PoultryReportScreen(session: await sessionFor(api), company: company, slug: 'cash-flow-detail'),
          size: phone);
      await _see(tester, find.text('Operating income'));
      expect(find.text('Customer payments'), findsOneWidget);
      await _see(tester, find.text('Cash positive — you kept GHC 600.00'));
      await _see(tester, find.text('Money in by source'));
      expect(find.text('Sales'), findsOneWidget, reason: 'bucket labels go through categoryLabel');
      await _see(tester, find.text('Money out by category'));
      expect(find.text('Expenses paid'), findsOneWidget);
    });

    testWidgets('egg sales offers customers; expense summary gathers categories', (tester) async {
      final api = FakeApi()
        ..gets['/api/Customer'] = [{'name': 'Kofi'}, {'name': 'Ama'}, {'name': 'Kofi'}]
        ..gets['/api/poultry/reports/expense-summary'] = {
          'summary': {'totalExpenses': 10},
          'rows': [
            {'date': '2026-09-01', 'category': 'Feed', 'amount': 5},
            {'date': '2026-09-02', 'category': 'Labor', 'amount': 5},
          ],
        };
      await open(tester, PoultryReportScreen(session: await sessionFor(api), company: company, slug: 'expense-summary'),
          size: phone);
      await _see(tester, find.text('All categories'));
      await tester.tap(find.text('All categories'));
      await tester.pumpAndSettle();
      expect(find.text('Feed'), findsWidgets);
      await tester.tap(find.text('Labor').last);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(api.requests.last.url.queryParameters['category'], 'Labor');
      await _see(tester, find.text('Supplier / payee'));

      api.gets['/api/poultry/reports/egg-sales'] = {'summary': {}, 'rows': []};
      await open(tester, PoultryReportScreen(session: await sessionFor(api), company: company, slug: 'egg-sales'), size: phone);
      await _see(tester, find.text('All customers'));
      await tester.tap(find.text('All customers'));
      await tester.pumpAndSettle();
      expect(find.text('Ama'), findsOneWidget);
      expect(find.text('Kofi'), findsOneWidget, reason: 'deduplicated');
      await tester.tap(find.text('Ama'));
      await tester.pumpAndSettle();
      await _see(tester, find.text('No data for this selection'));
    });

    testWidgets('a period choice sets both dates', (tester) async {
      final api = FakeApi()..gets['/api/poultry/reports/mortality'] = {'summary': {}, 'rows': []};
      await open(tester, PoultryReportScreen(session: await sessionFor(api), company: company, slug: 'mortality'), size: phone);
      await _see(tester, find.text('Last 30 Days  ·  Month'));
      await tester.tap(find.text('Last 30 Days  ·  Month'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All Time  ·  Other').last);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      final q = api.requests.last.url.queryParameters;
      expect(q['startDate'], '2000-01-01');
      expect(q['datePreset'], 'allTime');
    });
  });

  testWidgets('catalogue: four sections, 35 reports, opens a native report', (tester) async {
    final api = FakeApi()..gets['/api/poultry/reports/mortality'] = {'summary': {}, 'rows': []};
    await open(tester, PoultryReportsCatalogScreen(session: await sessionFor(api), company: company), size: phone);
    expect(find.text('35 reports in 4 sections — each with its own filters, summary cards and PDF export.'), findsOneWidget);
    await _see(tester, find.text('Mortality'));
    await tester.tap(find.text('Mortality'));
    await tester.pumpAndSettle();
    expect(find.text('Poultry Mortality Report'), findsWidgets);
  });

  testWidgets('P&L: tiles with formulas, bands, drilldown with filter, excluded panels, CSV and email', (tester) async {
    final shared = <(String, List<int>, String)>[];
    ReportExport.sharer = (name, bytes, mime, subject) async => shared.add((name, bytes, mime));
    Map line(String section, String key, String label, num amount, int order, {int entries = 0}) =>
        {'section': section, 'lineKey': key, 'lineLabel': label, 'amount': amount, 'sortOrder': order, 'entryCount': entries};
    final api = FakeApi()
      ..gets['/api/Poultry/profit-loss'] = {
        'totalRevenue': 1000, 'totalDirectCosts': 1200, 'grossProfit': -200, 'grossMarginPercent': -20,
        'totalOperatingExpenses': 100, 'operatingProfit': -300, 'totalOtherCosts': 50, 'netProfit': -350,
        'netMarginPercent': -35, 'status': 'Loss', 'netOwnerFunding': 500, 'netBorrowing': 0, 'totalCapitalInvestments': 900,
        'feedRecognitionMethod': 'EXPENSE_WHEN_CONSUMED', 'medicationRecognitionMethod': null, 'hasItemOverrides': true,
        'legacyExpenses': 2, 'classifiedExpenses': 8,
        'lines': [
          line('Revenue', 'EggSales', 'Egg Sales', 1000, 1, entries: 3),
          line('DirectCost', 'Feed', 'Feed', 1000, 1),
          line('DirectCost', 'Medication', 'Medication', 200, 2),
          line('OperatingExpense', 'Utilities', 'Utilities', 100, 1, entries: 2),
          line('OtherCost', 'Depreciation', 'Depreciation', 50, 1),
          line('Financing', 'OwnerContributions', 'Owner contributions', 500, 1),
          line('CapitalInvestment', 'Buildings', 'Buildings', 900, 1),
        ],
      }
      ..gets['/api/Poultry/profit-loss/expenses'] = [
        {'expenseDate': '2026-09-02T00:00:00', 'description': 'ECG bill', 'supplierName': 'ECG', 'amount': 60},
        {'expenseDate': '2026-09-20T00:00:00', 'description': 'Water', 'supplierName': 'GWCL', 'amount': 40, 'isLegacy': true},
      ];
    final c = Company(farmId: 'farm-1', name: 'Test Farm', type: CompanyType.poultry, email: 'boss@farm.com');
    await open(tester, ProfitLossScreen(session: await sessionFor(api), company: c), size: phone);

    await _see(tester, find.text('NET LOSS'));
    expect(find.text('GHC -350.00'), findsOneWidget);
    expect(find.text('GHC 1,350.00'), findsOneWidget, reason: 'total expenses = direct + operating + other');
    expect(find.text('-20% of sales'), findsOneWidget);
    expect(find.textContaining('(-200.00) − 100.00', findRichText: true), findsOneWidget, reason: 'negative terms bracketed');
    await _see(tester, find.textContaining('Expense when consumed (farm default)', findRichText: true));
    expect(find.text('Some item overrides active'), findsOneWidget);

    await _see(tester, find.text('DIRECT PRODUCTION COSTS'));
    expect(find.text('(GHC 1,200.00)'), findsOneWidget, reason: 'costs in brackets');
    await _see(tester, find.text('2 entries'));
    await tester.ensureVisible(find.text('Utilities'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Utilities'));
    await tester.pumpAndSettle();
    expect(find.text('Running cost'), findsOneWidget);
    expect(find.text('2 SEP 2026'), findsOneWidget);
    expect(find.text('Placed by category (legacy record)'), findsOneWidget);
    expect(find.text('2 records'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'gwcl');
    await tester.pump();
    expect(find.text('1 of 2 records'), findsOneWidget);
    expect(find.text('filtered · GHC 100.00 in full'), findsOneWidget);
    expect(api.requests.lastWhere((r) => r.url.path.endsWith('/expenses')).url.queryParameters['lineKey'], 'Utilities');
    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();

    await _see(tester, find.text('Owner Contributions & Draws'));
    expect(find.text('EXCLUDED FROM PROFIT'), findsWidgets);
    await _see(tester, find.text('View Capital Investments/Assets'));
    await _see(tester, find.text(profitVsCashTitle));
    await _see(tester, find.textContaining('2 of 10 cost records'));

    await tester.drag(_list, const Offset(0, 8000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CSV'));
    await tester.pumpAndSettle();
    final csv = utf8.decode(shared.last.$2);
    expect(shared.last.$1, 'poultry-profit-loss.csv');
    expect(csv.split('\n').first, '"Kind","Line","Amount"');
    expect(csv, contains('"Result","GROSS PROFIT","-200.00"'));
    expect(csv, contains('"Excluded","Owner contributions","500.00"'));

    await tester.tap(find.text('Email'));
    await tester.pumpAndSettle();
    final mail = utf8.decode(api.writes.lastWhere((w) => w.url.path == '/api/Email/Report').bodyBytes, allowMalformed: true);
    expect(mail, contains('boss@farm.com'));
    expect(find.text('Report sent. boss@farm.com'), findsOneWidget);
  });

  testWidgets('Money → Profit & Loss: page header, no back button, no letterhead', (tester) async {
    expect(pageScreens.containsKey('/poultry-profit-loss'), isTrue);
    final api = FakeApi()
      ..gets['/api/Poultry/profit-loss'] = {
        'totalRevenue': 1000, 'totalDirectCosts': 400, 'grossProfit': 600, 'totalOperatingExpenses': 100,
        'operatingProfit': 500, 'totalOtherCosts': 0, 'netProfit': 500, 'status': 'Profit',
        'lines': [
          {'section': 'Revenue', 'lineKey': 'EggSales', 'lineLabel': 'Egg Sales', 'amount': 1000, 'sortOrder': 1},
        ],
      }
      ..gets['/api/Poultry/profit-loss/expenses'] = [];
    final c = Company(farmId: 'farm-1', name: 'Test Farm', type: CompanyType.poultry, email: 'boss@farm.com');
    await open(tester, ProfitLossScreen(session: await sessionFor(api), company: c, page: true), size: phone);

    expect(find.text('Did the business make money from its operations this period?'), findsOneWidget);
    expect(find.text('Poultry reports'), findsNothing);
    expect(find.text('TEST FARM'), findsNothing, reason: 'the Money page has no letterhead');
    await _see(tester, find.text('NET PROFIT'));
    expect(find.text('GHC 500.00'), findsWidgets);
  });

  group('dashboards', () {
    FakeApi dashApi() => FakeApi()
      ..gets['/api/Flock'] = [
        {'flockId': 1, 'name': 'Layers A'},
        {'flockId': 2, 'name': 'Layers B'},
      ]
      ..gets['/api/ProductionRecord'] = [
        {'id': 1, 'flockId': 1, 'flockName': 'Layers A', 'date': '2026-09-01T00:00:00', 'production9AM': 20, 'production12PM': 10,
          'production4PM': 5, 'production4thPick': 0, 'totalProduction': 35, 'mortality': 1, 'feedKg': 10,
          'noOfBirds': 100, 'noOfBirdsLeft': 99, 'createdDate': '2026-09-01T09:15:00Z'},
        {'id': 2, 'flockId': 1, 'flockName': 'Layers A', 'date': '2026-09-02T00:00:00', 'production9AM': 30, 'production12PM': 0,
          'production4PM': 0, 'production4thPick': 0, 'totalProduction': 30, 'mortality': 0, 'feedKg': 10,
          'noOfBirds': 99, 'noOfBirdsLeft': 99},
        {'id': 3, 'flockId': 2, 'flockName': 'Layers B', 'date': '2026-09-02T00:00:00', 'totalProduction': 10, 'mortality': 2,
          'noOfBirds': 50, 'noOfBirdsLeft': 48},
      ]
      ..gets['/api/Sale'] = [
        {'saleDate': '2026-09-02T00:00:00', 'flockId': 1, 'product': 'Crate', 'quantity': 2, 'totalAmount': 100, 'customerName': 'Ama'},
        {'saleDate': '2026-09-02T00:00:00', 'flockId': 1, 'product': 'Crate', 'quantity': 1, 'totalAmount': 50},
      ]
      ..gets['/api/Expense'] = [
        {'expenseDate': '2026-09-01T00:00:00', 'category': 'Feed', 'amount': 80, 'plSection': 'DirectCost'},
        {'expenseDate': '2026-09-02T00:00:00', 'category': 'Equipment', 'amount': 1000, 'plSection': 'Excluded'},
      ];

    testWidgets('production: cards, picks, crates, totals; filter sheet narrows by flock', (tester) async {
      final api = dashApi();
      await open(tester, PoultryDashboardScreen(session: await sessionFor(api), company: company, view: 'production'), size: phone);
      expect(find.text('75'), findsWidgets, reason: 'total eggs');
      expect(find.text('2 (+15 loose)'), findsOneWidget);
      expect(find.text('25'), findsWidgets, reason: 'avg daily = 75 / 3 records');
      expect(find.text('BIRDS LEFT (SUM PER FLOCK)'), findsOneWidget);
      expect(find.text('147'), findsOneWidget, reason: '99 + 48, latest per flock');
      await _see(tester, find.text('1 Sep 2026, 09:15'));
      expect(find.text('1 + 5'), findsOneWidget, reason: '35 eggs = 1 crate + 5');
      await _see(tester, find.text('3 days'));

      await tester.drag(_list, const Offset(0, 4000));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All Flocks').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Layers B').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(find.text('BIRDS LEFT (SELECTED FLOCK)'), findsOneWidget);
      expect(find.text('48'), findsOneWidget);
    });

    testWidgets('financial keeps capital purchases out; daily and more read the same data', (tester) async {
      final api = dashApi();
      await open(tester, PoultryDashboardScreen(session: await sessionFor(api), company: company, view: 'financial'), size: phone);
      expect(find.text('REVENUE (2 TXN)'), findsOneWidget);
      expect(find.text('GHC 80.00'), findsWidgets, reason: 'the Excluded equipment is not an expense');
      expect(find.text('GHC 70.00'), findsWidgets, reason: 'net = 150 - 80');

      await open(tester, PoultryDashboardScreen(session: await sessionFor(api), company: company, view: 'daily'), size: phone);
      expect(find.text('40 · Sep 2'), findsOneWidget, reason: 'best egg day');
      expect(find.text('GHC 1,000.00 · Sep 2'), findsOneWidget, reason: 'the daily table counts every expense');
      await _see(tester, find.text('▼ Review costs').first);

      await open(tester, PoultryDashboardScreen(session: await sessionFor(api), company: company, view: 'insights'), size: phone);
      expect(find.text('GHC 150.00 · Crate'), findsOneWidget);
      expect(find.text('GHC 1,000.00 · Equipment'), findsOneWidget);
      await _see(tester, find.text('Flock Performance Report'));
    });

    testWidgets('/reports: tabs switch the view; search narrows sales', (tester) async {
      final api = dashApi();
      await open(tester, ReportsTabsScreen(session: await sessionFor(api), company: company), size: phone);
      expect(find.text('Daily Egg Production'), findsOneWidget);
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(find.text('Sales by Product Report'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextFormField, 'Search...'), 'ama');
      await tester.pumpAndSettle();
      expect(find.text('GHC 100.00 · Crate'), findsOneWidget);
    });
  });
}
