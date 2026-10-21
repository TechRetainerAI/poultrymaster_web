// The 17 Oct dev pull on Products (372-374), Previous closings (365) and the
// Closing report's byproduct sections (375), against a fake API, at phone width.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/pages/lookup_loader.dart';
import 'package:poultrycore_mobile/pages/poultry/daily_closing_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/poultry_extras.dart';
import 'package:poultrycore_mobile/pages/poultry/product_screens.dart';
import 'package:poultrycore_mobile/pages/poultry/reports/closing_reports.dart';

import 'support/harness.dart';

const tallPhone = Size(360, 2400);

Future<void> shown(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f.first);
  await tester.pumpAndSettle();
}

void main() {
  setUp(LookupLoader.clear);

  test('system products: no Delete, no Add stock', () {
    final broken = <String, dynamic>{'poultryProductId': 9, 'name': 'Broken Eggs'};
    final eggs = <String, dynamic>{'poultryProductId': 1, 'name': 'Eggs'};
    expect(poultryDeleteGuards['poultry-products']!(broken), isFalse);
    expect(poultryDeleteGuards['poultry-products']!(eggs), isTrue);
    final addStock = poultryRecordExtras['poultry-products']!.firstWhere((x) => x.label == 'Add stock');
    expect(addStock.when!(broken), isFalse);
    expect(addStock.when!(eggs), isTrue);
  });

  testWidgets('Add stock: a manual movement with a reason, the date and a request key', (tester) async {
    final api = FakeApi()..writeAnswers['/api/Poultry/stock/manual-movements'] = {'movementId': 8, 'movementNo': 'MSM-00008'};
    await open(tester,
        ProductStockScreen(session: await sessionFor(api), company: company, product: {'poultryProductId': 1, 'name': 'Eggs'}),
        size: tallPhone);
    await enter(tester, 'Quantity', '12');
    await tester.tap(find.text('Add stock').last);
    await tester.pumpAndSettle();
    expect(find.text('Choose the reason'), findsWidgets);
    expect(api.writes, isEmpty);
    await pick(tester, 'Choose the reason', 'Opening Inventory');
    await tester.tap(find.text('Add stock').last);
    await tester.pumpAndSettle();
    final b = api.lastBody('/api/Poultry/stock/manual-movements');
    expect((b['poultryProductId'], b['movementType'], b['quantity'], b['reason']), (1, 'Increase', 12, 'Opening Inventory'));
    expect(b['effectiveDate'], isNotEmpty);
    expect(b['requestKey'], isNotEmpty);
  });

  testWidgets('a system product: fixed name and unit, and Offer in Add Sale saves the setting', (tester) async {
    final api = FakeApi()..gets['/api/Poultry/stock/byproduct-settings'] = {'brokenEggsInSales': true, 'deadBirdsInSales': false};
    await open(
      tester,
      ProductFormScreen(
        session: await sessionFor(api),
        company: company,
        existing: {'poultryProductId': 9, 'name': 'Dead Birds', 'unit': 'Piece', 'unitPrice': 5, 'productType': 'FinishedGood'},
      ),
      size: tallPhone,
    );
    expect(find.textContaining('A system product'), findsOneWidget);
    expect(find.textContaining('Off for farms that dispose of mortality'), findsOneWidget);
    final name = tester.widget<TextField>(find.descendant(of: find.byType(TextFormField).first, matching: find.byType(TextField)));
    expect(name.enabled, isFalse);
    await tester.tap(find.text('Offer in Add Sale'));
    await tester.pumpAndSettle();
    await shown(tester, find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(api.writes.any((w) => w.method == 'PUT' && w.url.path == '/api/Poultry/products/9'), isTrue);
    expect(api.lastBody('/api/Poultry/stock/byproduct-settings', 'PUT')['deadBirdsInSales'], isTrue);
  });

  testWidgets('Previous closings: every figure, a missing one as a dash', (tester) async {
    final api = FakeApi()
      ..gets['/api/Poultry/daily-closings/day'] = {'businessDate': '2026-10-02', 'closing': null, 'live': null, 'atClose': null, 'history': []}
      ..gets['/api/Poultry/daily-closings/history'] = [
        {
          'poultryDailyClosingId': 4, 'closingDate': '2026-09-30', 'status': 'Approved', 'isClosed': true, 'closedBy': 'ama',
          'revenue': 900, 'creditSales': 100, 'expenses': 50, 'netCashFlow': 30, 'salesCount': 4, 'cashSales': 800,
          'paymentsReceived': 60, 'moneyIn': 860, 'moneyOut': 830, 'openingCash': 200, 'closingCash': 230, 'cashDifference': 0,
          'eggsProduced': 3400, 'eggsDamaged': 12, 'mortality': 2, 'feedKg': 41.5, 'blockingCount': 0, 'warningCount': 1,
          'reopenCount': 0,
        },
      ];
    await open(tester, DailyClosingScreen(session: await sessionFor(api), company: adminCompany), size: tallPhone);
    await tester.tap(find.text('Previous closings'));
    await tester.pumpAndSettle();
    for (final t in ['Credit sales', 'Expenses', 'Sales recorded', 'Cash sales', 'Payments received', 'Damaged eggs', 'Mortality', 'Feed used']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text('1 warning'), findsOneWidget, reason: 'checks');
    expect(find.text('41.5 kg'), findsOneWidget);
    expect(find.textContaining('A closed day shows its figures as closed'), findsOneWidget);
  });

  testWidgets('Closing report: the byproduct sections from the byproduct report', (tester) async {
    final api = FakeApi()
      ..gets['/api/Poultry/closing-report'] = {'TotalSales': 1500}
      ..gets['/api/poultry/reports/byproduct-inventory'] = {
        'summary': {'brokenEggsGenerated': 37, 'deadBirdsDisposed': 4, 'byproductRevenue': 25},
      };
    await open(tester, ClosingByCategoryScreen(session: await sessionFor(api), company: company), size: const Size(360, 5000));
    expect(find.text('Broken Egg Byproducts'), findsOneWidget);
    expect(find.text('Mortality / Dead Bird Disposition'), findsOneWidget);
    expect(find.text('37'), findsOneWidget);
    expect(find.text('4'), findsWidgets);
    final q = api.requests.lastWhere((r) => r.url.path == '/api/poultry/reports/byproduct-inventory').url.queryParameters;
    expect(q['startDate'], isNotEmpty);
  });
}
