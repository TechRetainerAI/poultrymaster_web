// GENERATED from poultry_employee_loans_test.dart for the Water rail
// (app/water-employee-loans): /api/Water, water* ids, waterMoneyRail.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/pages/poultry/expenses/employee_loans_screen.dart';

import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/water/reports/water_money_reports.dart' show waterMoneyRail;

import 'support/harness.dart';

final water = Company(farmId: 'farm-1', name: 'Win Water', type: CompanyType.water);

final active = <String, Object?>{
  'waterEmployeeLoanId': 1, 'loanNumber': 'EL-0001', 'staffName': 'Kofi Mensah', 'loanType': 'SalaryAdvance', 'status': 'Active',
  'disbursementDate': '2026-09-01T00:00:00', 'principalAmount': 500, 'totalRepayable': 500, 'totalRepaid': 200, 'outstandingBalance': 300,
  'repaymentMethod': 'PayrollDeduction', 'defaultPayrollDeduction': 100, 'cashAccountName': 'Main Cash', 'purpose': 'School fees',
  'repaymentCount': 2, 'interestEnabled': false, 'disbursedAt': '2026-09-01T08:00:00',
};
final draft = <String, Object?>{
  'waterEmployeeLoanId': 2, 'loanNumber': 'EL-0002', 'staffName': 'Ama Owusu', 'loanType': 'EmployeeLoan', 'status': 'Draft',
  'disbursementDate': '2026-10-01T00:00:00', 'principalAmount': 1000, 'totalRepayable': 1100, 'totalRepaid': 0, 'outstandingBalance': 0,
  'repaymentMethod': 'Cash', 'repaymentCount': 0,
};

FakeApi api({int total = 2}) => FakeApi()
  ..gets['/api/Water/employee-loans'] = {'items': [active, draft], 'totalCount': total}
  ..gets['/api/Water/employee-loans/summary'] = {
    'outstandingTotal': 300, 'disbursedInPeriod': 500, 'repaidInPeriod': 200, 'activeLoans': 1, 'staffWithActiveLoans': 1,
  }
  ..gets['/api/Water/staff'] = [
    {'waterStaffId': 7, 'firstName': 'Kofi', 'lastName': 'Mensah', 'role': 'Attendant', 'isActive': true},
    {'waterStaffId': 8, 'firstName': 'Old', 'lastName': 'Hand', 'role': 'Driver', 'isActive': false},
  ]
  ..gets['/api/Water/cash-accounts'] = [
    {'waterCashAccountId': 5, 'accountName': 'Main Cash', 'currentBalance': 2000, 'isActive': true},
  ]
  ..gets['/api/Water/employee-loans/1/repayments'] = [
    {'waterEmployeeLoanRepaymentId': 11, 'repaymentDate': '2026-09-15', 'sourceType': 'ManualCash', 'referenceNumber': 'MM-9', 'amount': 100,
      'balanceBefore': 500, 'balanceAfter': 400, 'status': 'Posted'},
    {'waterEmployeeLoanRepaymentId': 12, 'repaymentDate': '2026-09-30', 'sourceType': 'Payroll', 'payrollPeriodStart': '2026-09-01',
      'payrollPeriodEnd': '2026-09-30', 'amount': 100, 'balanceBefore': 400, 'balanceAfter': 300, 'status': 'Posted'},
  ]
  ..gets['/api/Water/employee-loans/2/repayments'] = <Map>[];

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
  final field = find.descendant(of: find.ancestor(of: inDialog(find.text(label)), matching: find.byType(Column)).first, matching: find.byType(TextFormField));
  await tester.enterText(field.first, text);
  await tester.pump();
}

Map body(FakeApi a, String path) => jsonDecode(a.writes.lastWhere((w) => w.url.path == path).body) as Map;

void main() {
  testWidgets('figures, filters to the server, cards, detail with history, paging', (tester) async {
    final a = api(total: 60);
    await open(tester, EmployeeLoansScreen(session: await sessionFor(a), company: water, rail: waterMoneyRail), size: phone);
    Map<String, String> q() => a.requests.lastWhere((r) => r.url.path == '/api/Water/employee-loans').url.queryParameters;

    expect(q()['status'], 'Active');
    expect((q()['limit'], q()['offset']), ('25', '0'));
    expect(find.text('What staff still owe the company'), findsOneWidget);
    expect(find.text('1 member(s) of staff'), findsOneWidget);
    await see(tester, find.text('EL-0001 · Kofi Mensah'));
    expect(find.text('Record repayment'), findsOneWidget);
    expect(find.text('Hand over'), findsOneWidget, reason: 'the draft');

    await tap(tester, find.widgetWithText(OutlinedButton, 'All'));
    expect(q().containsKey('status'), isFalse);
    await see(tester, find.text('All staff'));
    await tester.tap(find.text('All staff'));
    await tester.pumpAndSettle();
    expect(find.text('Old Hand'), findsNothing, reason: 'inactive staff are left out');
    await tester.tap(find.text('Kofi Mensah').last);
    await tester.pumpAndSettle();
    expect(q()['staffId'], '7');
    await tester.tap(find.text('All types'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salary advance').last);
    await tester.pumpAndSettle();
    expect(q()['loanType'], 'SalaryAdvance');

    await see(tester, find.text('Showing 1–25 of 60'));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(q()['offset'], '25');

    await tap(tester, find.text('Details'));
    expect(find.text('Salary advance · issued 2026-09-01 · repaid by Payroll deduction'), findsOneWidget);
    expect(find.text('School fees'), findsWidgets);
    await see(tester, find.text('via payroll'));
    expect(find.text('Payroll 2026-09-01 – 2026-09-30'), findsOneWidget);
    expect(find.text('no cash moved'), findsOneWidget);
    await tester.tap(inDialog(find.text('Reverse')));
    await tester.pumpAndSettle();
    expect(find.text('Reverse this repayment'), findsOneWidget);
    await reasonOther(tester, 'Counted twice');
    await tapIn(tester, inDialog(find.text('Undo it')));
    expect(body(a, '/api/Water/employee-loans/repayments/11/reverse'), {'farmId': 'farm-1', 'reason': 'Counted twice', 'actionBy': 'user-1'});
    expect(find.textContaining('Done'), findsOneWidget);
  });

  testWidgets('new advance: the save rules, interest, hand over now; then hand over and repay', (tester) async {
    final a = api();
    await open(tester, EmployeeLoansScreen(session: await sessionFor(a), company: water, rail: waterMoneyRail), size: phone);

    await tap(tester, find.text('New loan / advance'));
    final save = inDialog(find.widgetWithText(FilledButton, 'Record and hand over'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await choose(tester, 'Choose a member of staff', 'Kofi Mensah — Attendant');
    await enterIn(tester, 'Amount *', '600');
    await tapIn(tester, inDialog(find.byType(Switch)).first);
    await enterIn(tester, 'Interest amount', '60');
    await tester.pumpAndSettle();
    expect(find.textContaining('GHC 660.00', findRichText: true), findsOneWidget);
    expect(tester.widget<FilledButton>(save).onPressed, isNull, reason: 'handing over needs an account');
    await choose(tester, 'Choose a cash account', 'Main Cash — GHC 2,000.00');
    await tapIn(tester, save);
    final b = body(a, '/api/Water/employee-loans');
    expect((b['waterStaffId'], b['principalAmount'], b['interestEnabled'], b['interestAmount'], b['disburseNow'], b['waterCashAccountId']),
        (7, 600, true, 60, true, 5));
    expect((b['repaymentMethod'], b['paymentMethod'], b['defaultPayrollDeduction'], b['createdBy']), ('PayrollDeduction', 'Cash', null, 'user-1'));
    expect(find.textContaining('Advance recorded'), findsOneWidget);

    await tap(tester, find.text('Hand over'));
    expect(find.text('Hand over GHC 1,000.00'), findsOneWidget);
    await choose(tester, 'Choose a cash account', 'Main Cash — GHC 2,000.00');
    await tapIn(tester, inDialog(find.text('Hand it over')));
    expect(body(a, '/api/Water/employee-loans/2/disburse'),
        {'waterCashAccountId': 5, 'paymentMethod': 'Cash', 'referenceNumber': null, 'farmId': 'farm-1', 'disbursedBy': 'user-1'});

    await tap(tester, find.text('Record repayment'));
    await enterIn(tester, 'Amount *', '400');
    await tester.pumpAndSettle();
    expect(find.text('More than the GHC 300.00 still owed.'), findsOneWidget);
    await enterIn(tester, 'Amount *', '120');
    await choose(tester, 'Cash', 'MoMo');
    await choose(tester, 'Cash account', 'Main Cash');
    await tester.pumpAndSettle();
    expect(find.textContaining('GHC 180.00', findRichText: true), findsOneWidget);
    await tapIn(tester, inDialog(find.text('Record it')));
    final r = body(a, '/api/Water/employee-loans/repayments');
    expect((r['waterEmployeeLoanId'], r['amount'], r['sourceType'], r['waterCashAccountId']), (1, 120, 'MoMo', 5));
  });

  testWidgets('cancel a draft, reverse an advance', (tester) async {
    final a = api();
    await open(tester, EmployeeLoansScreen(session: await sessionFor(a), company: water, rail: waterMoneyRail), size: phone);
    await tap(tester, find.widgetWithText(TextButton, 'Cancel'));
    expect(find.text('Cancel this advance'), findsOneWidget);
    await tapIn(tester, inDialog(find.text('Undo it')));
    expect(a.writes.last.url.path, '/api/Water/employee-loans/2/cancel');
    expect(body(a, '/api/Water/employee-loans/2/cancel')['reason'], isNull);
  });
}
