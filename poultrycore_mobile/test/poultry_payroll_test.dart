// Poultry → Expenses → Payroll, at phone width: runs and their status
// actions, a new run, staff lines with advance deductions, the deductions
// breakdown, and the run's detail page.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/expenses/payroll_screen.dart';

import 'support/harness.dart';

final draftRun = <String, Object?>{
  'poultryPayrollRunId': 1, 'periodStart': '2026-09-01T00:00:00', 'periodEnd': '2026-09-30T00:00:00', 'status': 'Draft',
  'totalGrossPay': 1500, 'totalDeductions': 100, 'totalNetPay': 1400, 'cashAccountName': 'Main Cash', 'poultryCashAccountId': 5,
  'items': [
    {'poultryPayrollItemId': 21, 'poultryStaffId': 7, 'staffName': 'Kofi Mensah', 'basicPay': 1500, 'dailyWage': 0, 'commission': 0,
      'bonus': 0, 'deductions': 100, 'netPay': 1400},
  ],
};
final approvedRun = <String, Object?>{
  'poultryPayrollRunId': 2, 'periodStart': '2026-08-01T00:00:00', 'periodEnd': '2026-08-31T00:00:00', 'status': 'Approved',
  'totalGrossPay': 1000, 'totalDeductions': 0, 'totalNetPay': 1000,
};
final paidRun = <String, Object?>{
  'poultryPayrollRunId': 3, 'periodStart': '2026-07-01T00:00:00', 'periodEnd': '2026-07-31T00:00:00', 'status': 'Paid',
  'totalGrossPay': 900, 'totalDeductions': 0, 'totalNetPay': 900, 'cashAccountName': 'Main Cash',
};

FakeApi api() => FakeApi()
  ..gets['/api/Poultry/payroll-runs'] = [draftRun, approvedRun, paidRun]
  ..gets['/api/Poultry/payroll-runs/1'] = draftRun
  ..gets['/api/Poultry/cash-accounts'] = [
    {'poultryCashAccountId': 5, 'accountName': 'Main Cash', 'isActive': true},
  ]
  ..gets['/api/Poultry/staff'] = [
    {'poultryStaffId': 7, 'firstName': 'Kofi', 'lastName': 'Mensah', 'basePay': 1500, 'isActive': true},
    {'poultryStaffId': 9, 'firstName': 'Esi', 'lastName': 'Boateng', 'basePay': 800, 'isActive': true},
  ]
  ..gets['/api/Poultry/employee-loans/eligible'] = [
    {'poultryEmployeeLoanId': 4, 'loanNumber': 'EL-0004', 'loanType': 'SalaryAdvance', 'repaymentMethod': 'PayrollDeduction',
      'defaultPayrollDeduction': 150, 'outstandingBalance': 120},
    {'poultryEmployeeLoanId': 5, 'loanNumber': 'EL-0005', 'loanType': 'EmployeeLoan', 'repaymentMethod': 'Cash',
      'defaultPayrollDeduction': 50, 'outstandingBalance': 300},
  ]
  ..gets['/api/Poultry/payroll-deductions'] = [
    {'poultryPayrollItemDeductionId': 31, 'deductionType': 'SalaryAdvanceRepayment', 'amount': 100, 'loanNumber': 'EL-0004',
      'loanOutstanding': 120, 'status': 'Draft', 'isLegacy': false},
  ]
  ..writeAnswers['/api/Poultry/payroll-runs/1/items'] = {'poultryPayrollItemId': 22}
  ..gets['/api/Poultry/payroll-runs/3/details'] = {
    'run': {...paidRun, 'items': draftRun['items'], 'createdBy': 'Ama', 'paidBy': 'Kofi', 'paidAt': '2026-08-02T10:00:00', 'payDate': '2026-08-02'},
    'ytdTotals': {'year': 2026, 'ytdGrossPaid': 9000, 'ytdNetPaid': 8500, 'totalPayrollRuns': 7, 'totalStaffPaid': 3},
    'ytdByStaff': [
      {'poultryStaffId': 7, 'staffName': 'Kofi Mensah', 'staffRole': 'Attendant', 'ytdGross': 6000, 'ytdDeductions': 300, 'ytdNet': 5700},
    ],
    'linkedExpense': {'category': 'Payroll', 'amount': 900, 'expenseDate': '2026-08-01', 'description': 'July payroll'},
  };

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

Future<void> enterIn(WidgetTester tester, String label, String text) async {
  final field = find.descendant(of: find.ancestor(of: inDialog(find.text(label)), matching: find.byType(Column)).first, matching: find.byType(TextFormField));
  await tester.enterText(field.first, text);
  await tester.pump();
}

Map body(FakeApi a, String path) => jsonDecode(a.writes.lastWhere((w) => w.url.path == path).body) as Map;

void main() {
  test('only payroll advances are deducted, and never more than is owed', () {
    expect(payrollDeductionFor({'repaymentMethod': 'PayrollDeduction', 'defaultPayrollDeduction': 150, 'outstandingBalance': 120}), 120);
    expect(payrollDeductionFor({'repaymentMethod': 'Mixed', 'defaultPayrollDeduction': 50, 'outstandingBalance': 120}), 50);
    expect(payrollDeductionFor({'repaymentMethod': 'Cash', 'defaultPayrollDeduction': 50, 'outstandingBalance': 120}), 0);
    expect(payrollEditable('Reopened'), isTrue);
    expect(payrollEditable('Approved'), isFalse);
    expect(pageScreens.containsKey('/poultry-payroll'), isTrue);
  });

  testWidgets('figures, status filter, the actions each status allows, approve / pay / reopen / delete', (tester) async {
    final a = api();
    await open(tester, PayrollScreen(session: await sessionFor(a), company: company), size: phone);

    expect(find.text('GHC 900.00'), findsWidgets, reason: 'total net paid');
    await see(tester, find.text('2026-09-01 → 2026-09-30'));
    await tap(tester, find.text('Approve'));
    expect(a.writes.last.url.path, '/api/Poultry/payroll-runs/1/approve');
    expect(a.writes.last.url.queryParameters['approvedBy'], 'user-1');
    expect(find.textContaining('A linked expense was created.'), findsOneWidget);

    await see(tester, find.text('Status'));
    await tester.tap(find.ancestor(of: find.text('All'), matching: find.byType(AppSelect<String>)).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approved').last);
    await tester.pumpAndSettle();
    await see(tester, find.text('Mark paid'));
    expect(find.text('2026-09-01 → 2026-09-30'), findsNothing);
    await tester.tap(find.text('Mark paid'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No cash account is set on this run'), findsOneWidget);
    await tapIn(tester, inDialog(find.widgetWithText(FilledButton, 'Mark paid')));
    expect(a.writes.last.url.path, '/api/Poultry/payroll-runs/2/mark-paid');
    expect((jsonDecode(a.writes.last.body) as Map).containsKey('payDate'), isTrue);

    await tap(tester, find.text('Reopen'));
    await tapIn(tester, inDialog(find.widgetWithText(FilledButton, 'Reopen')));
    expect(find.textContaining('A reason is required'), findsOneWidget);
    await enterIn(tester, 'Reason *', 'Wrong rate');
    await tapIn(tester, inDialog(find.widgetWithText(FilledButton, 'Reopen')));
    expect(body(a, '/api/Poultry/payroll-runs/2/unapprove'), {'reason': 'Wrong rate'});
  });

  testWidgets('new run', (tester) async {
    final a = api();
    await open(tester, PayrollScreen(session: await sessionFor(a), company: company), size: phone);
    await tap(tester, find.text('New payroll run'));
    await tapIn(tester, inDialog(find.text('— None —')));
    await tester.tap(find.text('Main Cash').last);
    await tester.pumpAndSettle();
    await tapIn(tester, inDialog(find.text('Create run')));
    final b = body(a, '/api/Poultry/payroll-runs');
    expect((b['poultryCashAccountId'], b['payDate'], b['farmId']), (5, null, 'farm-1'));
    expect(a.writes.last.url.queryParameters['createdBy'], 'user-1');
  });

  testWidgets('staff lines: prefill, advance deductions added after the line, the breakdown', (tester) async {
    final a = api();
    await open(tester, PayrollScreen(session: await sessionFor(a), company: company), size: phone);
    await tap(tester, find.text('Lines'));
    expect(find.text('Staff lines'), findsOneWidget);
    expect(find.text('Kofi Mensah'), findsOneWidget);

    await see(tester, find.text('Pick staff'));
    await tester.tap(find.ancestor(of: find.text('Pick staff'), matching: find.byType(AppSelect<String>)).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Esi Boateng').last);
    await tester.pumpAndSettle();
    await see(tester, find.text('2 active advances'));
    expect(find.text('repaid by cash — not deducted here'), findsOneWidget);
    expect(find.textContaining('Includes GHC 120.00 of advance repayment'), findsOneWidget);
    await tap(tester, find.text('Add / update line'));

    final item = body(a, '/api/Poultry/payroll-runs/1/items');
    expect((item['poultryStaffId'], item['basicPay'], item['deductions']), (9, 800, 120));
    final d = a.writes.lastWhere((w) => w.url.path == '/api/Poultry/payroll-deductions');
    expect(jsonDecode(d.body), containsPair('deductionType', 'SalaryAdvanceRepayment'));
    expect(jsonDecode(d.body), containsPair('poultryPayrollItemId', 22));
    expect(find.textContaining('Advance repayment added'), findsOneWidget, reason: 'EL-0004 was not yet on the new line');

    await tap(tester, find.textContaining('view breakdown', findRichText: true));
    expect(find.text('Deductions — Kofi Mensah'), findsOneWidget);
    expect(find.text('EL-0004 · GHC 120.00 left'), findsOneWidget);
    await enterIn(tester, 'Amount *', '500');
    await tester.pumpAndSettle();
    expect(find.text('Only GHC 120.00 is left on EL-0004.'), findsOneWidget);
    await tapIn(tester, inDialog(find.byIcon(Icons.delete_outline)));
    expect(a.writes.last.method, 'DELETE');
    expect(a.writes.last.url.path, '/api/Poultry/payroll-deductions/31');
  });

  testWidgets('the run detail page', (tester) async {
    final a = api();
    await open(tester, PayrollRunDetailScreen(session: await sessionFor(a), company: company, runId: 3), size: phone);
    expect(find.text('Payroll · 2026-07-01 → 2026-07-31'), findsOneWidget);
    await see(tester, find.text('YTD gross (2026)'));
    await see(tester, find.text('July payroll'));
    await see(tester, find.text('Kofi · 2026-08-02'));
  });
}
