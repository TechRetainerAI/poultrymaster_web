// Restaurant → Expenses (2026-10-21, last set): Employee Loans & Advances,
// Deferred inventory cost and Capital Investments/Assets as the web pages,
// against a fake API at phone width.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/expenses/asset_logic.dart';
import 'package:poultrycore_mobile/pages/poultry/expenses/assets_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/expenses/deferred_costs_screen.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_staff_loans_screen.dart';

import 'support/harness.dart' hide enter;

final rest = Company(farmId: 'farm-1', name: 'Rose Bistro', type: CompanyType.restaurant, role: 'Admin');
const tall = Size(390, 4000);

Finder filled(String t) => find.widgetWithText(FilledButton, t);

Future<void> see(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f.last);
  await tester.pumpAndSettle();
}

/// The box under [label] (the last one on screen); a required label carries " *".
Future<void> enter(WidgetTester tester, String label, String text) async {
  final re = RegExp('^${RegExp.escape(label)}' r'( \*)?$');
  final l = find.byWidgetPredicate((w) => w is Text && re.hasMatch(w.data ?? w.textSpan?.toPlainText() ?? ''));
  await see(tester, l);
  final box = find.descendant(of: find.ancestor(of: l.last, matching: find.byType(Column)).first, matching: find.byType(TextFormField));
  await tester.enterText(box.first, text);
  await tester.pump();
}

void main() {
  test('routes, the loan filters, the Restaurant asset rail and the deferred row names', () {
    for (final h in ['/restaurant-staff-loans', '/restaurant-deferred-costs', '/restaurant-assets']) {
      expect(pageScreens.containsKey(h), isTrue, reason: h);
    }
    final loans = [
      {'staffLoanId': 1, 'status': 'Draft', 'restaurantStaffId': 5, 'staffName': 'Ama K', 'loanNumber': 'SL-1'},
      {'staffLoanId': 2, 'status': 'Active', 'restaurantStaffId': 6, 'staffName': 'Kofi', 'loanNumber': 'SL-2'},
      {'staffLoanId': 3, 'status': 'Reversed', 'restaurantStaffId': 5, 'staffName': 'Ama K', 'loanNumber': 'SL-3'},
    ];
    expect([for (final l in filterStaffLoans(loans)) l['staffLoanId']], [1, 2]);
    expect([for (final l in filterStaffLoans(loans, tab: 'CLOSED')) l['staffLoanId']], [3]);
    expect([for (final l in filterStaffLoans(loans, tab: 'ALL', staff: '5', search: 'sl-3')) l['staffLoanId']], [3]);
    const r = AssetRail.restaurant;
    expect((r.api, r.assetIdKey, r.categoryIdKey, r.costIdKey, r.cashAccountsPath, r.cashAccountNameKey, r.expensesHref, r.namePlaceholder),
        ('/api/Restaurant', 'capitalAssetId', 'assetCategoryId', 'assetCostId', '/api/Restaurant/finance/accounts', 'name', '/restaurant-expenses', 'Combi oven'));
    final p = restaurantDeferredPurchase({'purchaseId': 4, 'unit': 'kg'});
    expect((p['poultryRawMaterialPurchaseId'], p['productionUnit'], p['isLotProduced']), (4, 'kg', false));
    expect(restaurantDeferredDraw({'unit': 'kg', 'expenseId': 9})['expenseId'], isNull);
  });

  testWidgets('Employee Loans: a new advance paid out now, a repayment, and the loan page', (tester) async {
    final api = FakeApi()
      ..gets['/api/Restaurant/staff-loans'] = [
        {'staffLoanId': 2, 'loanNumber': 'SL-2', 'restaurantStaffId': 5, 'staffName': 'Ama K', 'staffIsActive': true, 'loanType': 'SalaryAdvance',
          'principalAmount': 300, 'interestAmount': 0, 'totalRepayable': 300, 'outstandingBalance': 200, 'totalPrincipalRepaid': 100,
          'totalInterestRepaid': 0, 'repaymentMethod': 'PayrollDeduction', 'defaultPayrollDeduction': 100, 'status': 'Active',
          'disbursementDate': '2026-10-01', 'cashAccountName': 'Main Cash Box', 'repaymentCount': 1, 'draftPayrollClaims': 0},
      ]
      ..gets['/api/Restaurant/staff-loans/summary'] = {'totalOutstanding': 200, 'totalDisbursed': 300, 'draftCount': 0, 'totalRepaid': 100,
        'repaidViaPayroll': 100, 'activeCount': 1, 'staffWithLoans': 1, 'draftPayrollClaims': 50}
      ..gets['/api/Restaurant/staff'] = [
        {'restaurantStaffId': 5, 'firstName': 'Ama', 'lastName': 'K', 'role': 'Cook', 'isActive': true, 'basePay': 1000},
      ]
      ..gets['/api/Restaurant/finance/accounts'] = [{'cashAccountId': 3, 'name': 'Main Cash Box', 'currentBalance': 900, 'isActive': true}]
      ..gets['/api/Restaurant/staff-loans/repayments'] = [
        {'repaymentId': 7, 'staffLoanId': 2, 'repaymentDate': '2026-10-05', 'sourceType': 'Cash', 'cashAccountName': 'Main Cash Box',
          'amount': 100, 'interestAmount': 0, 'balanceAfter': 200, 'status': 'Posted'},
      ];
    await open(tester, RestaurantStaffLoansScreen(session: await sessionFor(api), company: rest), size: tall);
    expect(find.text('OUTSTANDING'), findsWidgets);
    expect(find.textContaining('is set aside on draft payroll runs'), findsOneWidget);
    expect(find.text('SL-2 · Ama K'), findsOneWidget);

    await tester.tap(filled('New advance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose staff'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ama K — Cook').last);
    await tester.pumpAndSettle();
    await enter(tester, 'Amount given', '400');
    await tester.tap(filled('Give GHC 400.00'));
    await tester.pumpAndSettle();
    expect(find.text('Set how much to deduct from each payroll'), findsOneWidget);
    await enter(tester, 'Deduct per payroll', '100');
    expect(find.textContaining('Cleared in about 4 payroll runs'), findsOneWidget);
    await tester.tap(filled('Give GHC 400.00'));
    await tester.pumpAndSettle();
    final b = api.lastBody('/api/Restaurant/staff-loans');
    expect((b['restaurantStaffId'], b['principalAmount'], b['defaultPayrollDeduction'], b['repaymentMethod'], b['disburseNow'], b['cashAccountId']),
        (5, 400, 100, 'PayrollDeduction', true, null));

    await tester.tap(find.text('Record repayment').first);
    await tester.pumpAndSettle();
    await enter(tester, 'Amount', '500');
    await tester.tap(filled('Record'));
    await tester.pumpAndSettle();
    expect(find.textContaining('more than the'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'All').last);
    await tester.pump();
    await tester.tap(filled('Record'));
    await tester.pumpAndSettle();
    final rp = api.lastBody('/api/Restaurant/staff-loans/2/repayments');
    expect((rp['amount'], rp['sourceType']), (200, 'Cash'));

    await tester.tap(find.text('Details').first);
    await tester.pumpAndSettle();
    expect(find.text('Repayments'), findsOneWidget);
    expect(find.textContaining('into Main Cash Box'), findsOneWidget);
    await tester.tap(find.byTooltip('Reverse this repayment'));
    await tester.pumpAndSettle();
    await reasonPick(tester, 'Wrong amount');
    await tester.tap(filled('Confirm'));
    await tester.pumpAndSettle();
    expect(api.lastBody('/api/Restaurant/staff-loans/repayments/7/reverse'), {'reason': 'Wrong amount'});
  });

  testWidgets('Deferred inventory cost: the Restaurant rows, no manual panel, and a purchase history', (tester) async {
    final api = FakeApi()
      ..gets['/api/Restaurant/deferred-inventory-costs'] = {
        'summary': {'remainingDeferredCost': 40, 'recognizedCost': 60, 'operationalCost': 100, 'purchaseCount': 1},
        'purchases': [
          {'purchaseId': 4, 'purchaseDate': '2026-10-01', 'itemName': 'Rice', 'category': 'Dry goods', 'supplierName': 'Farm Fresh',
            'unit': 'kg', 'purchasedQuantity': 10, 'remainingQuantity': 4, 'consumedQuantity': 6, 'operationalCost': 100,
            'deferredTotalCost': 100, 'recognizedCost': 60, 'remainingDeferredCost': 40, 'status': 'PartiallyRecognized'},
        ],
      }
      ..gets['/api/Restaurant/deferred-inventory-costs/4/history'] = [
        {'drawId': 1, 'unit': 'kg', 'quantityDrawn': 6, 'recognizedCost': 60, 'recognitionOutcome': 'Recognized', 'isReversed': false, 'expenseId': 9},
      ];
    await open(tester, DeferredCostsScreen(session: await sessionFor(api), company: rest, restaurant: true), size: tall);
    expect(api.requests.any((r) => r.url.path == '/api/Restaurant/deferred-inventory-costs'), isTrue);
    expect(api.requests.any((r) => r.url.path.startsWith('/api/Poultry')), isFalse);
    expect(find.text('Rice'), findsWidgets);
    expect(find.textContaining('10 kg'), findsWidgets);
    expect(find.text('Manual deferred cost entry'), findsNothing);
  });

  testWidgets('Capital Investments/Assets: the Restaurant register and a new investment', (tester) async {
    final api = FakeApi()
      ..gets['/api/Restaurant/assets'] = [
        {'capitalAssetId': 3, 'assetNumber': 'RA-0003', 'assetName': 'Walk-in cold room', 'assetCategoryId': 1, 'categoryName': 'Kitchen equipment',
          'status': 'Active', 'acquisitionDate': '2026-01-10T00:00:00', 'acquisitionCost': 60000, 'additionalCost': 0, 'totalCapitalizedCost': 60000,
          'residualValue': 0, 'usefulLifeMonths': 120, 'monthlyDepreciation': 500, 'accumulatedDepreciation': 0, 'currentBookValue': 60000,
          'depreciationEntries': 0, 'amountOwed': 0},
      ]
      ..gets['/api/Restaurant/assets/categories'] = [{'assetCategoryId': 1, 'categoryName': 'Kitchen equipment', 'defaultUsefulLifeMonths': 120}]
      ..gets['/api/Restaurant/assets/summary'] = {'totalAssetCost': 60000, 'accumulatedDepreciation': 0, 'currentBookValue': 60000,
        'addedInPeriod': 0, 'addedCount': 0, 'activeAssets': 1, 'draftAssets': 0, 'fullyDepreciated': 0}
      ..gets['/api/Restaurant/asset-depreciation/due'] = []
      ..gets['/api/Restaurant/finance/accounts'] = [{'cashAccountId': 5, 'name': 'Bank', 'isActive': true}];
    await open(tester, AssetsScreen(session: await sessionFor(api), company: rest, rail: AssetRail.restaurant), size: tall);
    expect(find.text('Walk-in cold room'), findsWidgets);
    expect(api.requests.any((r) => r.url.path == '/api/Restaurant/finance/accounts'), isTrue);
    expect(api.requests.any((r) => r.url.path.startsWith('/api/Poultry')), isFalse);

    await tester.tap(find.text('New investment').first);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Combi oven'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Combi oven'), 'Combi oven');
    await see(tester, find.text('Choose a category'));
    await tester.tap(find.text('Choose a category').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kitchen equipment').last);
    await tester.pumpAndSettle();
    await enter(tester, 'Cost', '20000');
    await see(tester, find.text('Cash account'));
    await tester.tap(find.text('Cash account').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bank').last);
    await tester.pumpAndSettle();
    await see(tester, filled('Record investment'));
    await tester.tap(filled('Record investment'));
    await tester.pumpAndSettle();
    final b = api.lastBody('/api/Restaurant/assets');
    expect((b['assetName'], b['assetCategoryId'], b['amount'], b['cashAccountId'], b['paymentMethod']), ('Combi oven', 1, 20000, 5, 'Cash'));
  });
}
