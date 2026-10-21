// Deferred Inventory Cost → Manual entries (migration 371), against a fake API,
// at phone width.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/pages/lookup_loader.dart';
import 'package:poultrycore_mobile/pages/poultry/expenses/manual_deferred_cost_panel.dart';

import 'support/harness.dart';

const root = '/api/Poultry/deferred-inventory-costs';

FakeApi deferredApi() => FakeApi()
  ..gets['$root/manual'] = [
    {
      'entryId': 3, 'entryNumber': 'MDC-00003', 'poultryRawMaterialItemId': 5, 'itemName': 'Maize', 'unitOfMeasure': 'kg',
      'entryType': 'OpeningDeferredCost', 'amount': 300, 'quantity': 100, 'effectiveDate': '2026-10-01', 'recognised': 120,
      'remaining': 180, 'reason': 'Opening stock cost', 'status': 'Posted',
    },
  ]
  ..gets['$root/uncovered-stock'] = [
    {'poultryRawMaterialItemId': 6, 'itemName': 'Soya', 'unitOfMeasure': 'kg', 'currentQuantity': 50, 'uncoveredQuantity': 40},
  ]
  ..writeAnswers['$root/manual'] = {'entryId': 4, 'entryNumber': 'MDC-00004'}
  ..writeAnswers['$root/manual/3/reverse'] = {'reversedAmount': 180};

Future<void> openPanel(WidgetTester tester, FakeApi api) async {
  final session = await sessionFor(api);
  await open(
    tester,
    Scaffold(body: ListView(padding: const EdgeInsets.all(14), children: [ManualDeferredCostPanel(session: session, company: company)])),
    size: const Size(360, 2400),
  );
}

void main() {
  setUp(LookupLoader.clear);

  testWidgets('manual entries: waiting total, an entry recorded with its reason, one reversed', (tester) async {
    final api = deferredApi();
    await openPanel(tester, api);
    expect(find.text('GHC 180.00 waiting'), findsOneWidget);

    await tester.tap(find.text('Manual deferred cost entry'));
    await tester.pumpAndSettle();
    await pick(tester, 'Choose the item', 'Soya · 40 kg not covered');
    await enter(tester, 'Cost *', '80');
    await reasonPick(tester, 'Opening stock cost');
    await tester.tap(find.widgetWithText(FilledButton, 'Record entry'));
    await tester.pumpAndSettle();
    final b = api.lastBody('$root/manual');
    expect((b['poultryRawMaterialItemId'], b['amount'], b['quantity'], b['entryType'], b['reason']), (6, 80, 40, 'OpeningDeferredCost', 'Opening stock cost'));

    await tester.ensureVisible(find.text('Reverse').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reverse').first);
    await tester.pumpAndSettle();
    expect(find.text('Reverse MDC-00003?'), findsOneWidget);
    await reasonPick(tester, 'Wrong amount');
    await tester.tap(find.widgetWithText(FilledButton, 'Reverse'));
    await tester.pumpAndSettle();
    expect(api.lastBody('$root/manual/3/reverse')['reason'], 'Wrong amount');
    expect(find.textContaining('MDC-00003: GHC 180.00 not yet recognised was taken back.'), findsOneWidget);
  });
}
