// Water → Expenses → Payroll and Expenses, at phone width against a fake API:
// every dropdown, the request bodies, and the rules the web pages apply.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/money/money_routes.dart';
import 'package:poultrycore_mobile/pages/water/water_expenses_screen.dart';
import 'package:poultrycore_mobile/pages/water/water_payroll_screen.dart';

import 'support/harness.dart';

final water = Company(farmId: 'farm-1', name: 'Win Water', type: CompanyType.water);
const clock = {'businessDate': '2026-10-06', 'companyLocalDateTime': '2026-10-06T10:00:00', 'utcNow': '2026-10-06T10:00:00Z'};

final accounts = [
  {'waterCashAccountId': 5, 'accountName': 'Factory Box', 'currentBalance': 900, 'isActive': true},
];

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
  ScaffoldMessenger.of(tester.element(find.byType(Scaffold).last)).removeCurrentSnackBar();
  await tester.pumpAndSettle();
  await see(tester, f);
  await tester.tap(f.first);
  await tester.pumpAndSettle();
}

Finder inDialog(Finder f) => find.descendant(of: find.byType(AlertDialog), matching: f);

Future<void> choose(WidgetTester tester, String shown, String option) async {
  await see(tester, find.text(shown));
  await tester.tap(find.ancestor(of: find.text(shown).first, matching: find.byType(AppSelect<Object?>)).evaluate().isEmpty
      ? find.text(shown).first
      : find.text(shown).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Future<void> enterLabelled(WidgetTester tester, String label, String text) async {
  await see(tester, find.text(label));
  final field = find.descendant(of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first, matching: find.byType(TextFormField));
  await tester.enterText(field.first, text);
  await tester.pump();
}

void main() {
  test('Expenses and Payroll are native for Water, with the run deep link', () async {
    for (final r in ['/water-expenses', '/water-internal-use', '/water-payroll', '/water-employee-loans']) {
      expect(pageScreens.containsKey(r), isTrue, reason: r);
    }
    expect(moneyScreenForHref('/water-payroll/9', await sessionFor(FakeApi()), water), isA<WaterPayrollDetailScreen>());
    expect(waterPayrollEditable('Pending'), isTrue, reason: 'Water keeps Pending runs editable');
    expect(waterPayrollEditable('Approved'), isFalse);
  });

  // ------------------------------------------------------------ payroll

  group('Payroll', () {
    final runs = [
      {'waterPayrollRunId': 3, 'periodStart': '2026-09-01T00:00:00', 'periodEnd': '2026-09-30T00:00:00', 'status': 'Draft', 'totalGrossPay': 1000, 'totalNetPay': 900, 'totalDeductions': 100, 'notes': 'september'},
      {'waterPayrollRunId': 2, 'periodStart': '2026-08-01T00:00:00', 'periodEnd': '2026-08-31T00:00:00', 'status': 'Approved', 'totalGrossPay': 800, 'totalNetPay': 800, 'totalDeductions': 0, 'cashAccountName': 'Factory Box'},
    ];
    FakeApi api() => FakeApi()
      ..gets['/api/CompanyTime/context'] = clock
      ..gets['/api/Water/payroll-runs'] = runs
      ..gets['/api/Water/staff'] = [
        {'waterStaffId': 7, 'firstName': 'Kojo', 'lastName': 'Mensah', 'role': 'Driver', 'basePay': 600, 'isActive': true},
      ]
      ..gets['/api/Water/cash-accounts'] = accounts
      ..gets['/api/Water/payroll-runs/3'] = {
        ...runs.first,
        'items': [
          {'waterPayrollItemId': 30, 'waterStaffId': 7, 'staffName': 'Kojo Mensah', 'basicPay': 600, 'dailyWage': 0, 'commission': 0, 'bonus': 0, 'deductions': 100, 'netPay': 500},
        ],
      }
      ..gets['/api/Water/payroll-deductions/run/3'] = [
        {'waterPayrollItemId': 30, 'activeLoanCount': 1, 'activeLoanOutstanding': 400},
      ]
      ..gets['/api/Water/employee-loans/eligible'] = [
        {'waterEmployeeLoanId': 11, 'loanNumber': 'ADV-1', 'loanType': 'SalaryAdvance', 'repaymentMethod': 'PayrollDeduction', 'defaultPayrollDeduction': 150, 'outstandingBalance': 400},
      ]
      ..gets['/api/Water/payroll-deductions'] = <Map>[]
      ..writeAnswers['/api/Water/payroll-runs/3/items'] = {'waterPayrollItemId': 31};

    testWidgets('cards and actions by status; search; mark paid sends no date', (tester) async {
      final a = api();
      await open(tester, WaterPayrollScreen(session: await sessionFor(a), company: water), size: phone);
      expect(find.text('2026-09-01 → 2026-09-30'), findsOneWidget);
      expect(find.text('Approve'), findsOneWidget, reason: 'only the draft');
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      await see(tester, find.text('Mark paid'));
      expect(find.text('Reopen'), findsOneWidget);
      await tap(tester, find.text('Mark paid'));
      final w = a.writes.last;
      expect((w.url.path, w.url.queryParameters['paidBy']), ('/api/Water/payroll-runs/2/mark-paid', 'user-1'));
      expect(jsonDecode(w.body), {'payDate': null});

      await see(tester, find.byType(TextFormField));
      await tester.enterText(find.byType(TextFormField).first, 'september');
      await tester.pumpAndSettle();
      expect(find.text('2026-08-01 → 2026-08-31'), findsNothing);
    });

    testWidgets('new run needs a period; then the body', (tester) async {
      final a = api();
      await open(tester, WaterPayrollScreen(session: await sessionFor(a), company: water), size: phone);
      await tap(tester, find.text('New run'));
      await tester.tap(inDialog(find.text('Create')));
      await tester.pumpAndSettle();
      expect(find.text('Period required'), findsOneWidget);
      expect(a.writes, isEmpty);
    });

    testWidgets('open a run: hints, prefill from staff, advances panel, save item auto-adds the deduction', (tester) async {
      final a = api();
      await open(tester, WaterPayrollScreen(session: await sessionFor(a), company: water), size: phone);
      await tap(tester, find.text('Open'));
      expect(find.text('Run: 2026-09-01 → 2026-09-30'), findsOneWidget);
      expect(find.text('active advance'), findsOneWidget);

      await see(tester, find.text('Pick staff'));
      await tester.tap(find.text('Pick staff'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kojo Mensah (Driver)').last);
      await tester.pumpAndSettle();
      await see(tester, find.text('1 active advance'));
      expect(find.text('1 active advance'), findsOneWidget);
      expect(find.textContaining('will deduct', findRichText: true), findsOneWidget);

      await tap(tester, find.text('Save item'));
      final item = a.lastBody('/api/Water/payroll-runs/3/items');
      expect((item['waterStaffId'], item['basicPay'], item['deductions']), (7, 600, 150), reason: 'basePay and the advance prefill');
      final ded = a.lastBody('/api/Water/payroll-deductions');
      expect((ded['waterPayrollItemId'], ded['deductionType'], ded['amount'], ded['waterEmployeeLoanId']), (31, 'SalaryAdvanceRepayment', 150, 11));
      expect(find.textContaining('ADV-1 150.00 — review before approving'), findsOneWidget);
    });

    testWidgets('details page: header, totals, YTD, linked expense', (tester) async {
      final a = api()
        ..gets['/api/Water/payroll-runs/2/details'] = {
          'run': {...runs[1], 'createdBy': 'Ama', 'createdAt': '2026-09-01T08:00:00Z', 'items': []},
          'ytdTotals': {'year': 2026, 'ytdGrossPaid': 800, 'ytdDeductions': 0, 'ytdNetPaid': 800, 'totalPayrollRuns': 1, 'totalStaffPaid': 1},
          'ytdByStaff': <Map>[],
          'linkedExpense': {'categoryName': 'Payroll', 'amount': 800, 'expenseDate': '2026-09-01T00:00:00', 'status': 'Approved', 'sourceType': 'Payroll', 'sourceId': 2},
        };
      await open(tester, WaterPayrollDetailScreen(session: await sessionFor(a), company: water, runId: 2), size: phone);
      expect(find.text('Payroll Run #2'), findsOneWidget);
      expect(find.text('Mark paid'), findsOneWidget);
      expect(find.text('Reopen'), findsOneWidget);
      await see(tester, find.text('Open in Expenses'));
      expect(find.textContaining('Payroll #2'), findsOneWidget);
      await see(tester, find.text('No payroll items for this run.'));
      expect(find.text('No payroll items for this run.'), findsOneWidget);
    });
  });

  // ------------------------------------------------------------ expenses

  group('Expenses', () {
    FakeApi api() => FakeApi()
      ..gets['/api/CompanyTime/context'] = clock
      ..gets['/api/Water/expenses'] = [
        {'waterExpenseId': 40, 'expenseDate': '2026-10-03T00:00:00', 'categoryName': 'Fuel', 'description': 'Diesel', 'amount': 300, 'amountPaid': 100, 'balance': 200,
          'paymentMethod': 'Credit', 'status': 'Approved', 'supplierId': 9, 'supplierName': 'Goil'},
        {'waterExpenseId': 39, 'expenseDate': '2026-10-02T00:00:00', 'categoryName': 'Repairs', 'amount': 50, 'amountPaid': 50, 'balance': 0, 'paymentMethod': 'Cash', 'status': 'Draft'},
      ]
      ..gets['/api/Water/delivery-expenses'] = [
        {'waterDeliveryExpenseId': 5, 'returnDate': '2026-10-04T00:00:00', 'expenseCategory': 'Tolls', 'amount': 20, 'driverName': 'Kojo', 'isApproved': true, 'returnStatus': 'Approved', 'waterVehicleLoadingId': 12},
      ]
      ..gets['/api/Water/expense-categories'] = [
        {'waterExpenseCategoryId': 1, 'name': 'Fuel', 'isActive': true},
        {'waterExpenseCategoryId': 2, 'name': 'Old', 'isActive': false},
      ]
      ..gets['/api/Water/cash-accounts'] = accounts
      ..gets['/api/Water/suppliers'] = [
        {'waterSupplierId': 9, 'supplierName': 'Goil', 'supplierType': 'Fuel Supplier'},
      ]
      ..writeAnswers['/api/Water/expenses'] = {'waterExpenseId': 41};

    test('the merged ledger and its status rule', () {
      final rows = mergeWaterExpenses([
        {'waterExpenseId': 1, 'expenseDate': '2026-10-01', 'status': 'Draft'},
      ], [
        {'waterDeliveryExpenseId': 2, 'returnDate': '2026-10-02', 'isApproved': true, 'returnStatus': 'Open'},
        {'waterDeliveryExpenseId': 3, 'createdAt': '2026-09-30', 'isApproved': false},
      ]);
      expect([for (final r in rows) r.key], ['del-2', 'exp-1', 'del-3']);
      expect([for (final r in rows) r.status], ['Submitted', 'Draft', 'Draft']);
    });

    testWidgets('direct and delivery rows, totals, actions, status filter to the server', (tester) async {
      final a = api();
      await open(tester, WaterExpensesScreen(session: await sessionFor(a), company: water), size: phone);
      expect(find.text('320.00'), findsOneWidget, reason: 'approved: the bill and the approved delivery');
      expect(find.text('3'), findsOneWidget);
      await see(tester, find.text('Tolls · 20.00'));
      expect(find.text('Delivery #12'), findsOneWidget);
      await see(tester, find.text('Submit'));
      await tap(tester, find.text('Submit'));
      expect(a.writes.last.url.path, '/api/Water/expenses/39/submit');

      await see(tester, find.text('All statuses'));
      await tester.tap(find.text('All statuses'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approved').last);
      await tester.pumpAndSettle();
      expect(a.requests.lastWhere((r) => r.url.path == '/api/Water/expenses').url.queryParameters['status'], 'Approved');
    });

    testWidgets('table: pay a bill opens the supplier payment; history', (tester) async {
      final a = api();
      await open(tester, WaterExpensesScreen(session: await sessionFor(a), company: water), size: phone);
      await tap(tester, find.text('View table format'));
      await see(tester, find.byTooltip('Record a payment against this bill'));
      await tester.tap(find.byTooltip('Record a payment against this bill'));
      await tester.pumpAndSettle();
      expect(find.text('Record payment'), findsWidgets);
      expect(find.textContaining('E40'), findsWidgets);
    });

    testWidgets('record: unpaid becomes Credit, partial needs an amount, the bodies', (tester) async {
      final a = api();
      await open(tester, WaterExpensesScreen(session: await sessionFor(a), company: water), size: phone);
      await tap(tester, find.text('Record expense'));
      expect(find.text('Record water expense'), findsWidgets);
      await enterLabelled(tester, 'Amount *', '250');

      await see(tester, find.text('Paid'));
      await tester.tap(find.text('Paid').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Partially paid').last);
      await tester.pumpAndSettle();
      await tap(tester, find.text('Save as Draft'));
      expect(find.text('Cash account required for non-credit expenses'), findsOneWidget);

      await see(tester, find.text('Partially paid'));
      await tester.tap(find.text('Partially paid').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unpaid').last);
      await tester.pumpAndSettle();
      expect(find.text('Credit'), findsOneWidget, reason: 'unpaid sets the method to Credit');
      expect(find.text('(not required for credit)'), findsOneWidget);

      await see(tester, find.text('No supplier / Other (use freetext below)'));
      await tester.tap(find.text('No supplier / Other (use freetext below)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Goil · Fuel Supplier').last);
      await tester.pumpAndSettle();
      await tap(tester, find.text('Save as Draft'));

      final b = a.lastBody('/api/Water/expenses');
      expect((b['waterExpenseCategoryId'], b['amount'], b['paymentMethod'], b['waterCashAccountId'], b['supplierId']), (1, 250, 'Credit', null, 9));
      expect(a.lastBody('/api/Water/expenses/41/payment'), {'amountPaid': 0, 'dueDate': null});
      expect(find.text('Expense recorded as Draft'), findsOneWidget);
    });

    testWidgets('categories: the list and add', (tester) async {
      final a = api();
      await open(tester, WaterExpensesScreen(session: await sessionFor(a), company: water), size: phone);
      await tap(tester, find.text('Categories'));
      expect(find.text('inactive'), findsOneWidget);
      await tester.enterText(inDialog(find.byType(TextFormField)), 'Water tests');
      await tester.tap(inDialog(find.text('Add')));
      await tester.pumpAndSettle();
      expect(a.lastBody('/api/Water/expense-categories'), {'name': 'Water tests', 'farmId': 'farm-1', 'isActive': true});
    });
  });
}
