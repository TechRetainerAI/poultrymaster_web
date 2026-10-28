// Hotel → Sales, Expenses & Money → Expenses: Employee Loans & Advances,
// Deferred inventory cost and Capital Investments/Assets, at phone width
// against a fake API.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/hotel/hotel_employee_loans_screen.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/expenses/asset_logic.dart';
import 'package:poultrycore_mobile/pages/poultry/expenses/assets_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/expenses/deferred_costs_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/expenses/hotel_asset_view.dart';

import 'support/harness.dart';

final hotel = Company(farmId: 'h1', name: 'Palm Hotel', type: CompanyType.hotel, role: 'Admin');
const tall = Size(360, 4200);

Finder filled(String t) => find.widgetWithText(FilledButton, t);

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).first);
  await tester.pumpAndSettle();
}

final _loans = [
  {'hotelEmployeeLoanId': 1, 'hotelStaffId': 1, 'staffName': 'Esi Boateng', 'staffIsActive': true, 'loanNumber': 'LN-1', 'loanType': 'SalaryAdvance',
    'status': 'Active', 'principalAmount': 600, 'interestAmount': 0, 'totalRepayable': 600, 'totalPrincipalRepaid': 200, 'totalInterestRepaid': 0,
    'outstandingBalance': 400, 'repaymentMethod': 'PayrollDeduction', 'defaultPayrollDeduction': 200, 'disbursementDate': '2026-10-02',
    'hotelCashAccountId': 5, 'cashAccountName': 'Front desk till', 'createdAt': '2026-10-02T09:00:00Z', 'draftPayrollClaims': 0},
  {'hotelEmployeeLoanId': 2, 'hotelStaffId': 2, 'staffName': 'Kwame Asante', 'staffIsActive': true, 'loanNumber': 'LN-2', 'loanType': 'EmployeeLoan',
    'status': 'Draft', 'principalAmount': 1000, 'interestAmount': 50, 'totalRepayable': 1050, 'totalPrincipalRepaid': 0, 'totalInterestRepaid': 0,
    'outstandingBalance': 1050, 'repaymentMethod': 'Cash', 'defaultPayrollDeduction': 0, 'createdAt': '2026-10-20T09:00:00Z', 'draftPayrollClaims': 0},
  {'hotelEmployeeLoanId': 3, 'hotelStaffId': 2, 'staffName': 'Kwame Asante', 'loanNumber': 'LN-3', 'loanType': 'OtherAdvance', 'status': 'Reversed',
    'principalAmount': 90, 'createdAt': '2026-09-01T09:00:00Z'},
];

FakeApi loansApi() => FakeApi()
  ..gets['/api/Hotel/employee-loans'] = _loans
  ..gets['/api/Hotel/employee-loans/summary'] = {
    'totalOutstanding': 400, 'totalDisbursed': 600, 'totalRepaid': 200, 'repaidViaPayroll': 200, 'activeCount': 1, 'staffWithLoans': 1,
    'draftCount': 1, 'draftPayrollClaims': 0,
  }
  ..gets['/api/Hotel/employee-loans/1/repayments'] = [
    {'hotelEmployeeLoanRepaymentId': 7, 'hotelEmployeeLoanId': 1, 'amount': 200, 'interestAmount': 0, 'sourceType': 'Cash',
      'cashAccountName': 'Front desk till', 'balanceAfter': 400, 'repaymentDate': '2026-10-10', 'status': 'Posted'},
    {'hotelEmployeeLoanRepaymentId': 8, 'hotelEmployeeLoanId': 1, 'amount': 50, 'sourceType': 'Payroll', 'payrollPeriod': 'Sep 2026',
      'balanceAfter': 350, 'repaymentDate': '2026-09-30', 'status': 'Posted'},
  ]
  ..gets['/api/Hotel/staff'] = [
    {'hotelStaffId': 1, 'firstName': 'Esi', 'lastName': 'Boateng', 'role': 'Housekeeping', 'isActive': true},
    {'hotelstaffid': 2, 'firstname': 'Kwame', 'lastname': 'Asante', 'isactive': true},
  ]
  ..gets['/api/Hotel/finance/cash-accounts'] = [
    {'hotelcashaccountid': 5, 'accountname': 'Front desk till', 'currentbalance': 900, 'isactive': true},
  ];

void main() {
  test('the three rows open native screens; the loan filters; the Hotel asset in the register\'s names', () {
    for (final h in ['/hotel-employee-loans', '/hotel-deferred-costs', '/hotel-assets']) {
      expect(pageScreens.containsKey(h), isTrue, reason: h);
    }
    expect([for (final l in filterHotelLoans(_loans)) l['loanNumber']], ['LN-1', 'LN-2'], reason: 'Open = Draft + Active');
    expect([for (final l in filterHotelLoans(_loans, tab: 'CLOSED')) l['loanNumber']], ['LN-3']);
    expect([for (final l in filterHotelLoans(_loans, tab: 'ALL', staff: '2', type: 'OtherAdvance')) l['loanNumber']], ['LN-3']);
    expect(filterHotelLoans(_loans, tab: 'ALL', search: 'esi').length, 1);

    final v = hotelAssetView({'hotelCapitalAssetId': 4, 'assetName': 'Laundry machine', 'hotelAssetCategoryId': 2, 'status': 'Active',
      'totalCapitalizedCost': 1300, 'residualValue': 100, 'usefulLifeMonths': 12, 'currentBookValue': 1200, 'supplier': 'LG', 'reversedReason': 'x'});
    expect((v['capitalAssetId'], v['assetNumber'], v['assetCategoryId'], v['supplierName'], v['reversalReason']), (4, '#4', 2, 'LG', 'x'));
    expect((v['depreciableAmount'], v['monthlyDepreciation'], v['remainingDepreciable']), (1200, 100, 1100));
    expect(hotelDepreciationView({'periodStart': '2026-02-01T00:00:00'})['periodEnd'], '2026-02-28');
    expect(HotelAssetApi.paidFromError(null, 500, null), isNotNull, reason: 'a blank amount paid means paid in full, so it needs a cash account');
    expect(HotelAssetApi.paidFromError(0, 500, null), isNull);
    expect((AssetRail.hotel.canCorrectOriginalCost, AssetRail.hotel.hasDepreciationDue, AssetRail.hotel.expensesHref), (false, false, '/hotel-expenses'));
  });

  testWidgets('Employee Loans: cards, tabs, per-status actions, New advance paid out now', (tester) async {
    final api = loansApi();
    await open(tester, HotelEmployeeLoansScreen(session: await sessionFor(api), company: hotel), size: tall);
    expect(find.text('Employee Loans & Advances'), findsWidgets);
    expect(find.text('OUTSTANDING'), findsWidgets);
    expect(find.text('LN-1 · Esi Boateng'), findsOneWidget);
    expect(find.text('LN-2 · Kwame Asante'), findsOneWidget);
    expect(find.text('LN-3 · Kwame Asante'), findsNothing, reason: 'Open hides a reversed loan');
    expect(find.text('Record repayment'), findsOneWidget);
    expect(find.text('Pay out'), findsOneWidget);
    expect(find.text('2 loan(s)'), findsNothing);
    expect(find.textContaining('2 loan(s) · '), findsOneWidget);

    await tapText(tester, 'Cancelled / reversed');
    expect(find.text('LN-3 · Kwame Asante'), findsOneWidget);
    await tapText(tester, 'Open');

    await tester.tap(find.text('New advance').first);
    await tester.pumpAndSettle();
    expect(find.text('New loan or advance'), findsOneWidget);
    final staffPicker = find.ancestor(of: find.text('Choose staff'), matching: find.byType(AppSelect<int>));
    await tester.ensureVisible(staffPicker);
    await tester.pumpAndSettle();
    await tester.tap(staffPicker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Esi Boateng — Housekeeping').last);
    await tester.pumpAndSettle();
    await enter(tester, 'Amount given *', '300');
    await enter(tester, 'Deduct per payroll *', '100');
    await tester.pumpAndSettle();
    expect(find.textContaining('cleared in about 3 payroll runs'), findsOneWidget);
    // The one active account is picked already.
    await tester.ensureVisible(find.textContaining('Give '));
    await tester.tap(find.textContaining('Give '));
    await tester.pumpAndSettle();
    final b = api.lastBody('/api/Hotel/employee-loans');
    expect((b['hotelStaffId'], b['staffName'], b['principalAmount'], b['defaultPayrollDeduction'], b['disburseNow'], b['hotelCashAccountId']),
        (1, 'Esi Boateng', 300, 100, true, 5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Employee Loans: pay out a draft, record a repayment, the details with its repayments', (tester) async {
    final api = loansApi();
    await open(tester, HotelEmployeeLoansScreen(session: await sessionFor(api), company: hotel), size: tall);

    await tapText(tester, 'Pay out');
    await tester.tap(filled('Pay out'));
    await tester.pumpAndSettle();
    final d = api.lastBody('/api/Hotel/employee-loans/2/disburse');
    expect((d['hotelCashAccountId'], d['farmId']), (5, 'h1'));

    await tapText(tester, 'Record repayment');
    await enter(tester, 'Amount *', '500');
    await tester.tap(filled('Record'));
    await tester.pumpAndSettle();
    expect(find.textContaining('more than the'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'All').last);
    await tester.pumpAndSettle();
    await tester.tap(filled('Record'));
    await tester.pumpAndSettle();
    final r = api.lastBody('/api/Hotel/employee-loan-repayments');
    expect((r['hotelEmployeeLoanId'], r['amount'], r['sourceType'], r['hotelCashAccountId']), (1, 400, 'Cash', 5));

    await tester.tap(find.text('Details').first);
    await tester.pumpAndSettle();
    expect(find.text('Repayments'), findsOneWidget);
    expect(find.textContaining('Payroll Sep 2026 · no cash moved'), findsOneWidget);
    expect(find.byTooltip('Reverse this repayment'), findsOneWidget, reason: 'a payroll repayment is undone from its run');
    expect(find.text('Edit plan'), findsOneWidget);
    expect(find.text('Reverse loan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Employee Loans: ?staffId= opens filtered to that staff member', (tester) async {
    await open(tester, HotelEmployeeLoansScreen(session: await sessionFor(loansApi()), company: hotel, staffId: 2), size: tall);
    expect(find.text('LN-2 · Kwame Asante'), findsOneWidget);
    expect(find.text('LN-1 · Esi Boateng'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Deferred inventory cost reads /api/Hotel, with the hotel wording and no manual-cost panel', (tester) async {
    final api = FakeApi()
      ..gets['/api/Hotel/deferred-inventory-costs'] = {
        'summary': {'remainingDeferredCost': 0, 'purchaseCount': 0},
        'purchases': [],
      };
    await open(tester, DeferredCostsScreen(session: await sessionFor(api), company: hotel, hotel: true), size: tall);
    expect(api.requests.any((r) => r.url.path == '/api/Hotel/deferred-inventory-costs'), isTrue);
    expect(api.requests.any((r) => r.url.path.startsWith('/api/Poultry') || r.url.path.startsWith('/api/Restaurant')), isFalse);
    expect(find.textContaining('On a hotel that expenses stock'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Capital Investments/Assets: Hotel calls, no Correct cost, New investment activates, Post depreciation', (tester) async {
    final api = FakeApi()
      ..gets['/api/Hotel/assets'] = [
        {'hotelCapitalAssetId': 4, 'assetNumber': 'HA-4', 'assetName': 'Laundry machine', 'hotelAssetCategoryId': 2, 'categoryName': 'Equipment',
          'status': 'Active', 'acquisitionDate': '2026-10-01', 'acquisitionCost': 1300, 'totalCapitalizedCost': 1300, 'residualValue': 100,
          'usefulLifeMonths': 12, 'accumulatedDepreciation': 100, 'currentBookValue': 1200, 'createdAt': '2026-10-01T09:00:00Z'},
      ]
      ..gets['/api/Hotel/assets/categories'] = [
        {'hotelAssetCategoryId': 2, 'categoryName': 'Equipment', 'defaultUsefulLifeMonths': 60, 'isActive': true},
      ]
      ..gets['/api/Hotel/assets/summary'] = {'totalAssets': 1, 'activeAssets': 1, 'draftAssets': 0, 'totalAssetCost': 1300, 'currentBookValue': 1200}
      ..gets['/api/Hotel/assets/9'] = {'hotelCapitalAssetId': 9, 'status': 'Draft'}
      ..gets['/api/Hotel/finance/cash-accounts'] = [
        {'hotelcashaccountid': 5, 'accountname': 'Front desk till', 'isactive': true},
      ]
      ..writeAnswers['/api/Hotel/assets'] = {'hotelCapitalAssetId': 9}
      ..writeAnswers['/api/Hotel/asset-depreciation/generate'] = {'assetsProcessed': 1, 'entriesCreated': 1, 'totalAmount': 100};
    await open(tester, AssetsScreen(session: await sessionFor(api), company: hotel, rail: AssetRail.hotel), size: tall);
    expect(find.text('Laundry machine'), findsWidgets);
    expect(find.text('Correct cost'), findsNothing);
    expect(api.requests.any((r) => r.url.path.startsWith('/api/Restaurant') || r.url.path.startsWith('/api/Poultry')), isFalse);
    expect(api.requests.any((r) => r.url.path == '/api/Hotel/asset-depreciation/due'), isFalse);

    await tester.tap(find.text('New investment'));
    await tester.pumpAndSettle();
    await enter(tester, 'Investment name', 'Generator');
    await enter(tester, 'Cost', '5000');
    await enter(tester, 'Amount paid now', '0');
    await tester.tap(find.text('Record investment'));
    await tester.pumpAndSettle();
    final b = api.lastBody('/api/Hotel/assets');
    expect((b['assetName'], b['amount'], b['amountPaid'], b['farmId']), ('Generator', 5000, 0, 'h1'));
    expect(api.writes.any((w) => w.url.path == '/api/Hotel/assets/9/activate'), isFalse, reason: 'no in-service date, so it stays Draft');

    await tester.tap(find.text('Depreciation'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Months already posted are skipped.'), findsOneWidget);
    await tester.tap(filled('Post depreciation'));
    await tester.pumpAndSettle();
    expect(jsonDecode(api.writes.lastWhere((w) => w.url.path == '/api/Hotel/asset-depreciation/generate').body), {'farmId': 'h1'});
    expect(tester.takeException(), isNull);
  });
}
