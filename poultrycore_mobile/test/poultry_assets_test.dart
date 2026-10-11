// Poultry → Expenses → Capital Investments/Assets: the rules, then the register
// and the investment page at phone width — every dialog and its request body.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/expenses/asset_detail_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/expenses/asset_logic.dart';
import 'package:poultrycore_mobile/pages/poultry/expenses/assets_screen.dart';

import 'support/harness.dart';

final house = <String, Object?>{
  'poultryCapitalAssetId': 1, 'assetNumber': 'CA-0001', 'assetName': 'Poultry House 4', 'poultryAssetCategoryId': 2,
  'categoryName': 'Buildings', 'location': 'North block', 'status': 'Active', 'acquisitionDate': '2026-01-10T00:00:00',
  'createdAt': '2026-01-10T09:00:00Z', 'acquisitionCost': 10000, 'additionalCost': 2000, 'totalCapitalizedCost': 12000,
  'residualValue': 0, 'depreciableAmount': 12000, 'usefulLifeMonths': 120, 'monthlyDepreciation': 100,
  'accumulatedDepreciation': 0, 'currentBookValue': 12000, 'remainingDepreciable': 12000, 'depreciationEntries': 0,
  'inServiceDate': '2026-02-01T00:00:00', 'supplierName': 'BuildCo', 'createdBy': 'Ama', 'costEntries': 2,
};

final mixer = <String, Object?>{
  'poultryCapitalAssetId': 2, 'assetNumber': 'CA-0002', 'assetName': 'Feed mixer', 'poultryAssetCategoryId': 3,
  'categoryName': 'Machinery', 'status': 'Active', 'acquisitionDate': '2025-06-01T00:00:00', 'acquisitionCost': 5000,
  'additionalCost': 0, 'totalCapitalizedCost': 5000, 'residualValue': 500, 'usefulLifeMonths': 60, 'monthlyDepreciation': 75,
  'accumulatedDepreciation': 900, 'currentBookValue': 4100, 'depreciationEntries': 12,
};

final fullHouse = {
  ...house,
  'costs': [
    {'poultryCapitalAssetCostId': 11, 'costDate': '2026-01-10T00:00:00', 'description': 'Building', 'sourceType': 'Acquisition',
      'amount': 10000, 'status': 'Posted', 'paymentStatus': 'Paid', 'paymentMethod': 'Cash', 'expenseId': 501},
    {'poultryCapitalAssetCostId': 12, 'costDate': '2026-03-02T00:00:00', 'description': 'Roofing sheets', 'costCategory': 'Materials',
      'sourceType': 'AdditionalCost', 'amount': 2000, 'status': 'Posted', 'paymentStatus': 'Partial', 'balance': 500,
      'supplierName': 'Roofs Ltd'},
    {'poultryCapitalAssetCostId': 13, 'costDate': '2026-03-05T00:00:00', 'description': 'Wrong one', 'sourceType': 'AdditionalCost',
      'amount': 300, 'status': 'Reversed', 'reversalReason': 'Duplicate', 'reversedBy': 'Kofi'},
  ],
  'depreciation': [
    {'poultryAssetDepreciationId': 31, 'periodStart': '2026-02-01', 'amount': 100, 'sourceType': 'Monthly', 'status': 'Posted',
      'accumulatedAfter': 100, 'bookValueAfter': 11900, 'expenseId': 601},
  ],
};

FakeApi api() => FakeApi()
  ..gets['/api/CompanyTime/context'] = {
    'businessDate': '2026-10-06', 'companyLocalDateTime': '2026-10-06T10:00:00', 'utcNow': '2026-10-06T10:00:00Z',
  }
  ..gets['/api/Poultry/assets'] = [house, mixer]
  ..gets['/api/Poultry/assets/categories'] = [
    {'poultryAssetCategoryId': 2, 'categoryName': 'Buildings', 'defaultUsefulLifeMonths': 240},
    {'poultryAssetCategoryId': 3, 'categoryName': 'Machinery', 'defaultUsefulLifeMonths': 60},
  ]
  ..gets['/api/Poultry/assets/summary'] = {
    'totalAssetCost': 17000, 'accumulatedDepreciation': 900, 'currentBookValue': 16100, 'addedInPeriod': 2000, 'addedCount': 1,
    'activeAssets': 2, 'draftAssets': 0, 'fullyDepreciated': 0,
  }
  ..gets['/api/Poultry/asset-depreciation/due'] = [
    {'poultryCapitalAssetId': 1, 'assetName': 'Poultry House 4', 'nextPeriod': '2026-02-01', 'monthsDue': 8, 'amountDue': 800},
  ]
  ..gets['/api/Poultry/cash-accounts'] = [
    {'poultryCashAccountId': 5, 'accountName': 'Main Cash', 'isActive': true},
    {'poultryCashAccountId': 6, 'accountName': 'Old Till', 'isActive': false},
  ]
  ..gets['/api/Poultry/assets/1'] = fullHouse
  ..writeAnswers['/api/Poultry/asset-depreciation/generate'] = {'entriesCreated': 8, 'assetsProcessed': 1, 'totalAmount': 800};

Finder get _list => find.descendant(of: find.byType(Scaffold).last, matching: find.byType(Scrollable)).first;

Future<void> see(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
    await tester.drag(_list, const Offset(0, -200));
    await tester.pumpAndSettle();
  }
  for (var i = 0; i < 80 && f.evaluate().isEmpty; i++) {
    await tester.drag(_list, const Offset(0, 200));
    await tester.pumpAndSettle();
  }
  Scrollable.ensureVisible(tester.element(f.first), alignment: .5);
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder f) async {
  await see(tester, f);
  await tester.tap(f.first);
  await tester.pumpAndSettle();
}

Finder inDialog(Finder f) => find.descendant(of: find.byType(AlertDialog), matching: f);

Future<void> tapIn(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, String shown, String option) async {
  await tapIn(tester, find.ancestor(of: inDialog(find.text(shown)), matching: find.byType(AppSelect<String>)).first);
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Future<void> enterIn(WidgetTester tester, String label, String text) async {
  final field = find.descendant(
    of: find.ancestor(of: inDialog(find.text(label)), matching: find.byType(Column)).first,
    matching: find.byType(TextFormField),
  );
  await tester.enterText(field.first, text);
  await tester.pump();
}

void clearToasts(WidgetTester tester) =>
    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();

Map<String, dynamic> body(FakeApi a, String path, [String method = 'POST']) =>
    jsonDecode(a.writes.lastWhere((w) => w.url.path == path && w.method == method).body) as Map<String, dynamic>;

void main() {
  group('asset rules', () {
    test('status words, cost types, months', () {
      expect(assetStatusLabel('Draft'), 'Not in service');
      expect(assetStatusLabel('FullyDepreciated'), 'Fully depreciated');
      expect(costTypeLabel({'sourceType': 'OriginalCostCorrection'}), 'Original cost correction');
      expect(costTypeLabel({'sourceType': 'AdditionalCost', 'costCategory': ' '}), 'Additional cost');
      expect(costReversible({'sourceType': 'Acquisition', 'status': 'Posted'}), isFalse);
      expect(costReversible({'sourceType': 'AdditionalCost', 'status': 'Posted'}), isTrue);
      expect(fmtMonthYear('2026-09-01T00:00:00'), 'Sep 2026');
    });

    test('the correction preview', () {
      final p = previewCorrection(
          acquisitionCost: 5000, additionalCost: 0, residualValue: 500, usefulLifeMonths: 60, accumulatedDepreciation: 900, newAcquisitionCost: 4000)!;
      expect(p.difference, -1000);
      expect(p.newTotal, 4000);
      expect(p.newDepreciable, 3500);
      expect(p.newMonthly, 58.33);
      expect(p.newBookValue, 3100);
      expect(p.newRemaining, 2600);
      expect(previewCorrection(
          acquisitionCost: 5000, additionalCost: 0, residualValue: 500, usefulLifeMonths: 60, accumulatedDepreciation: 0, newAcquisitionCost: 5000), isNull);
      expect(previewCorrection(
          acquisitionCost: 5000, additionalCost: 0, residualValue: 500, usefulLifeMonths: 60, accumulatedDepreciation: 0, newAcquisitionCost: 400)!
          .residualTooHigh, isTrue);
    });

    test('search, status and category; what a new investment will record', () {
      expect([for (final a in filterAssets([house, mixer], search: 'north')) a['assetNumber']], ['CA-0001']);
      expect([for (final a in filterAssets([house, mixer], category: '3')) a['assetNumber']], ['CA-0002']);
      final p = newAssetPreview('12000', '', '120', '0');
      expect((p.paid, p.owing, p.monthly), (12000, 0, 100));
      final q = newAssetPreview('12000', '2000', '', '0');
      expect((q.paid, q.owing, q.monthly), (2000, 10000, 0));
    });
  });

  test('on the sidebar route, and the investment page by link', () {
    expect(pageScreens.containsKey('/poultry-assets'), isTrue);
  });

  testWidgets('figures, cards, filters, the history panel with its three tabs', (tester) async {
    final a = api();
    await open(tester, AssetsScreen(session: await sessionFor(a), company: company), size: phone);

    expect(find.text('GHC 17,000.00'), findsOneWidget);
    expect(find.text('8 due'), findsOneWidget);
    expect(find.text('1 asset(s) acquired'), findsOneWidget);
    await see(tester, find.text('Poultry House 4'));
    expect(find.text('CA-0001 · Buildings · North block'), findsOneWidget);
    expect(find.text('120 months · GHC 100.00/month'), findsOneWidget);
    expect(find.text('Reverse'), findsOneWidget, reason: 'the mixer has depreciation, so it cannot be reversed');

    await tap(tester, find.text('Where these figures came from'));
    await see(tester, find.text('WHAT IT IS WORTH NOW'));
    expect(find.textContaining('GHC 12,000.00 total capitalised cost − GHC 0.00 depreciation charged', findRichText: true), findsOneWidget);
    await tap(tester, find.textContaining('Cost history'));
    await see(tester, find.text('Roofing sheets'));
    expect(find.text('GHC 500.00 owed'), findsOneWidget);
    expect(find.textContaining('Reversed by Kofi'), findsOneWidget);
    await tap(tester, find.textContaining('Depreciation history'));
    await see(tester, find.text('Feb 2026'));
    expect(find.text('Expense #601'), findsOneWidget);
    await tap(tester, find.text('Hide history'));

    await see(tester, find.text('All statuses'));
    await tester.tap(find.text('All statuses'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('In service').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('All categories'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Machinery').last);
    await tester.pumpAndSettle();
    expect(find.text('Poultry House 4'), findsNothing);
    await see(tester, find.text('Feed mixer'));

    await tap(tester, find.text('View table format'));
    await see(tester, find.text('Capitalised cost'));
  });

  testWidgets('New investment: the preview and the body', (tester) async {
    final a = api();
    await open(tester, AssetsScreen(session: await sessionFor(a), company: company), size: phone);
    await tap(tester, find.text('New investment'));
    await tapIn(tester, inDialog(find.text('Record investment')));
    expect(find.textContaining('Name the investment'), findsOneWidget);
    clearToasts(tester);

    await enterIn(tester, 'Investment name', 'Layer cages');
    await choose(tester, 'Choose a category', 'Machinery');
    expect(find.text('Machinery usually 60 months'), findsOneWidget);
    await enterIn(tester, 'Cost', '6000');
    await enterIn(tester, 'Amount paid now', '1000');
    await choose(tester, 'Cash account', 'Main Cash');
    await tester.pumpAndSettle();
    expect(find.textContaining('owed to the supplier GHC 5,000.00', findRichText: true), findsOneWidget);
    expect(find.textContaining('GHC 100.00 a month for 60 months', findRichText: true), findsOneWidget);
    expect(find.textContaining('No in-service date'), findsOneWidget);
    await tapIn(tester, inDialog(find.text('Record investment')));

    final b = body(a, '/api/Poultry/assets');
    expect(b['assetName'], 'Layer cages');
    expect(b['assetCategoryId'], 3);
    expect(b['amount'], 6000);
    expect(b['amountPaid'], 1000);
    expect(b['usefulLifeMonths'], 60);
    expect(b['cashAccountId'], 5);
    expect(b['paymentMethod'], 'Cash');
    expect(b['inServiceDate'], isNull);
    expect(b['createdBy'], 'user-1');
    expect(find.textContaining('Investment recorded'), findsOneWidget);
  });

  testWidgets('Add cost (and the expense route), Edit, Dispose, Reverse', (tester) async {
    final a = api();
    await open(tester, AssetsScreen(session: await sessionFor(a), company: company), size: phone);

    await tap(tester, find.text('Add cost'));
    await choose(tester, 'Capitalise to this investment', 'Record as an operating expense');
    expect(find.text('Go to Expenses'), findsOneWidget);
    await tapIn(tester, inDialog(find.text('Back to capitalising')));
    await enterIn(tester, 'Amount', '750');
    await enterIn(tester, 'What it was for', 'Gutters');
    await choose(tester, 'Cash', 'Credit');
    await tapIn(tester, inDialog(find.widgetWithText(FilledButton, 'Add cost')));
    final c = body(a, '/api/Poultry/assets/1/costs');
    expect((c['amount'], c['description'], c['paymentMethod'], c['amountPaid']), (750, 'Gutters', 'Credit', null));
    clearToasts(tester);

    await tap(tester, find.text('Edit'));
    expect(find.text('Edit Poultry House 4'), findsOneWidget);
    await enterIn(tester, 'Location', 'South block');
    await tapIn(tester, inDialog(find.text('Save')));
    final e = body(a, '/api/Poultry/assets/1', 'PUT');
    expect((e['location'], e['setFinancials'], e['usefulLifeMonths'], e['updatedBy']), ('South block', true, 120, 'user-1'));
    clearToasts(tester);

    await tap(tester, find.text('Dispose'));
    expect(find.textContaining('Its book value today is GHC 12,000.00'), findsOneWidget);
    await enterIn(tester, 'Proceeds', '3000');
    await tapIn(tester, inDialog(find.widgetWithText(FilledButton, 'Dispose')));
    expect(body(a, '/api/Poultry/assets/1/dispose')['proceeds'], 3000);
    clearToasts(tester);

    await tap(tester, find.widgetWithText(OutlinedButton, 'Reverse'));
    await tapIn(tester, inDialog(find.widgetWithText(FilledButton, 'Reverse')));
    expect(find.textContaining('A reason is required'), findsOneWidget);
    clearToasts(tester);
    await enterIn(tester, 'Reason', 'Wrong company');
    await tapIn(tester, inDialog(find.widgetWithText(FilledButton, 'Reverse')));
    expect(body(a, '/api/Poultry/assets/1/reverse'), {'farmId': 'farm-1', 'reason': 'Wrong company', 'createdBy': 'user-1'});
  });

  testWidgets('Correct cost, reverse a cost (DELETE with a body), post depreciation', (tester) async {
    final a = api();
    await open(tester, AssetsScreen(session: await sessionFor(a), company: company), size: phone);

    await see(tester, find.text('Feed mixer'));
    await tester.ensureVisible(find.text('Correct cost').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Correct cost').last);
    await tester.pumpAndSettle();
    expect(find.text('Correct the original cost of Feed mixer'), findsOneWidget);
    await enterIn(tester, 'Corrected original acquisition cost', '4000');
    await tester.pumpAndSettle();
    expect(find.text('−GHC 1,000.00'), findsOneWidget);
    expect(find.textContaining('12 month(s) of depreciation have already been posted'), findsOneWidget);
    expect(tester.widget<FilledButton>(inDialog(find.widgetWithText(FilledButton, 'Record correction'))).onPressed, isNull,
        reason: 'a reason is required');
    await enterIn(tester, 'Reason *', 'Invoice was 4,000');
    await tester.pumpAndSettle();
    await tapIn(tester, inDialog(find.widgetWithText(FilledButton, 'Record correction')));
    final k = body(a, '/api/Poultry/assets/2/original-cost', 'PUT');
    expect((k['newAmount'], k['reason']), (4000, 'Invoice was 4,000'));
    clearToasts(tester);

    await tap(tester, find.text('Where these figures came from'));
    await tap(tester, find.textContaining('Cost history'));
    await see(tester, find.byTooltip('Reverse this cost'));
    await tester.tap(find.byTooltip('Reverse this cost'));
    await tester.pumpAndSettle();
    expect(find.textContaining("the investment's value falls by GHC 2,000.00"), findsOneWidget);
    await tapIn(tester, inDialog(find.widgetWithText(FilledButton, 'Reverse cost')));
    expect(find.text('Reason is required.'), findsOneWidget);
    await tester.enterText(inDialog(find.byType(TextFormField)), 'Wrong investment');
    await tapIn(tester, inDialog(find.widgetWithText(FilledButton, 'Reverse cost')));
    final d = a.writes.lastWhere((w) => w.method == 'DELETE');
    expect(d.url.path, '/api/Poultry/assets/1/costs/12');
    expect(jsonDecode(d.body), {'farmId': 'farm-1', 'reason': 'Wrong investment', 'createdBy': 'user-1'});
    clearToasts(tester);

    await tap(tester, find.text('Depreciation'));
    expect(find.text('8 month(s) across 1 asset(s) will be charged to Profit & Loss.'), findsOneWidget);
    await tapIn(tester, inDialog(find.text('Post depreciation')));
    expect(a.writes.last.url.path, '/api/Poultry/asset-depreciation/generate');
    expect(find.textContaining('8 month(s) across 1 asset(s), GHC 800.00 charged to Profit & Loss. No cash moved.'), findsOneWidget);
  });

  testWidgets('the investment page: three cards, histories, reverse a charge', (tester) async {
    final a = api();
    await open(tester, AssetDetailScreen(session: await sessionFor(a), company: company, assetId: 1), size: phone);
    expect(find.text('Back to Capital Investments'), findsOneWidget);
    expect(find.text('In service'), findsWidgets);
    await see(tester, find.text('SOURCE & AUDIT'));
    expect(find.text('BuildCo'), findsOneWidget);
    await see(tester, find.text('1 reversed cost entry is kept on the record and excluded from the total.'));
    await see(tester, find.byTooltip('Reverse this charge'));
    await tester.tap(find.byTooltip('Reverse this charge'));
    await tester.pumpAndSettle();
    await tapIn(tester, inDialog(find.widgetWithText(FilledButton, 'Reverse')));
    expect(find.textContaining('A reason is required'), findsOneWidget);
    clearToasts(tester);
    await tester.enterText(inDialog(find.byType(TextFormField)), 'Wrong month');
    await tapIn(tester, inDialog(find.widgetWithText(FilledButton, 'Reverse')));
    expect(body(a, '/api/Poultry/asset-depreciation/31/reverse')['reason'], 'Wrong month');
    expect(find.textContaining('Depreciation reversed'), findsOneWidget);
  });
}
