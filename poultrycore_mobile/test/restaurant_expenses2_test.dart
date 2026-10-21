// Restaurant → Expenses (2026-10-20, second set): Recurring Expenses, Internal
// Use and Payroll as the web pages, against a fake API at phone width.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/expenses/recurring_expenses_screen.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_internal_use_screen.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_payroll_screen.dart';
import 'package:poultrycore_mobile/pages/web_nav.dart';

import 'support/harness.dart' hide enter;

final rest = Company(farmId: 'farm-1', name: 'Rose Bistro', type: CompanyType.restaurant, role: 'Admin');
const tall = Size(390, 4000);

Finder filled(String t) => find.widgetWithText(FilledButton, t);

Future<void> see(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f.last);
  await tester.pumpAndSettle();
}

/// The box under [label]; a required label carries " *".
Future<void> enter(WidgetTester tester, String label, String text) async {
  final re = RegExp('^${RegExp.escape(label)}' r'( \*)?$');
  final l = find.byWidgetPredicate((w) => w is Text && re.hasMatch(w.data ?? w.textSpan?.toPlainText() ?? ''));
  await see(tester, l);
  final box = find.descendant(of: find.ancestor(of: l.last, matching: find.byType(Column)).first, matching: find.byType(TextFormField));
  await tester.enterText(box.first, text);
  await tester.pump();
}

void main() {
  test('routes, the Expenses menu in the web order, and internal-use wording', () {
    for (final h in ['/restaurant-recurring-expenses', '/restaurant-internal-use', '/restaurant-payroll']) {
      expect(pageScreens.containsKey(h), isTrue, reason: h);
    }
    final expenses = webNavGroups['restaurant']!.firstWhere((g) => g.title == 'Sales, Expenses & Money').subGroups.firstWhere((s) => s.title == 'Expenses');
    expect([for (final l in expenses.links) l.label], [
      'Expenses', 'Supplier Payments', 'Supplier Balances', 'Recurring Expenses', 'Internal Use', 'Payroll',
      'Employee Loans & Advances', 'Deferred inventory cost', 'Capital Investments/Assets',
    ]);
    expect(restaurantInternalUseLabel('StaffWelfare'), 'Staff meal');
    expect(restaurantInternalUseLabel('InternalConsumption'), 'Kitchen use');
    expect(describeRestaurantInternalQty({'items': [{'entryQuantity': 3, 'entryUnit': 'portion'}]}), '3 portions');
    expect(markPaidDefaultDate({'payDate': '2999-01-01'}), isNot('2999-01-01'));
    expect(markPaidDefaultDate({'payDate': '2020-01-31'}), '2020-01-31');
  });

  testWidgets('Recurring Expenses: the Restaurant lookups, and a template by category id', (tester) async {
    final api = FakeApi()
      ..gets['/api/recurring-expenses/templates'] = []
      ..gets['/api/recurring-expenses/occurrences'] = []
      ..gets['/api/recurring-expenses/upcoming'] = []
      ..gets['/api/Restaurant/expenses/categories'] = [
        {'expenseCategoryId': 3, 'name': 'Gas', 'isActive': true},
        {'expenseCategoryId': 4, 'name': 'Old', 'isActive': false},
      ]
      ..gets['/api/Restaurant/setup/suppliers'] = [{'restaurantsupplierid': 8, 'name': 'Farm Fresh'}]
      ..gets['/api/Restaurant/finance/accounts'] = [{'cashAccountId': 5, 'name': 'Bank', 'isActive': true}];
    await open(tester, RecurringExpensesScreen(session: await sessionFor(api), company: rest), size: tall);
    expect(api.requests.any((r) => r.url.path == '/api/Restaurant/expenses/categories'), isTrue);
    expect(api.requests.any((r) => r.url.path.startsWith('/api/Poultry') || r.url.path == '/api/Supplier'), isFalse);

    await tester.tap(find.text('New recurring expense').first);
    await tester.pumpAndSettle();
    await see(tester, find.text('e.g. Office rent'));
    await tester.enterText(find.widgetWithText(TextFormField, 'e.g. Office rent'), 'Gas refill');
    await see(tester, find.text('Choose'));
    await tester.tap(find.text('Choose').last);
    await tester.pumpAndSettle();
    expect(find.text('Old'), findsNothing, reason: 'inactive categories are left out');
    await tester.tap(find.text('Gas').last);
    await tester.pumpAndSettle();
    await enter(tester, 'Amount', '300');
    await see(tester, find.text('Cash'));
    await pick(tester, 'Cash', 'Credit (pay later)');
    await see(tester, find.text('No supplier'));
    await pick(tester, 'No supplier', 'Farm Fresh');
    await see(tester, filled('Save'));
    await tester.tap(filled('Save'));
    await tester.pumpAndSettle();
    final b = api.lastBody('/api/recurring-expenses/templates');
    expect((b['name'], b['categoryId'], b['categoryName'], b['amount'], b['supplierId']), ('Gas refill', 3, 'Gas', 300, 8));
  });

  testWidgets('Internal Use: a menu item for staff, the stock check, post and reverse', (tester) async {
    final api = FakeApi()
      ..gets['/api/Restaurant/internal-usage'] = [
        {'internalUsageId': 1, 'usageDate': '2026-10-10', 'category': 'OwnerUse', 'status': 'Draft', 'totalCostValue': 25,
          'items': [{'itemType': 'Ingredient', 'ingredientId': 4, 'itemName': 'Rice', 'entryQuantity': 10, 'entryUnit': 'kg', 'entryUnitCost': 2.5}]},
        {'internalUsageId': 2, 'usageDate': '2026-10-11', 'category': 'StaffWelfare', 'status': 'Posted', 'totalCostValue': 24, 'plCost': 24,
          'items': [{'itemType': 'MenuItem', 'menuItemId': 7, 'itemName': 'Jollof', 'entryQuantity': 2, 'entryUnit': 'portion', 'entryUnitCost': 12}]},
      ]
      ..gets['/api/Restaurant/internal-usage/items'] = [
        {'itemType': 'Ingredient', 'itemId': 4, 'name': 'Rice', 'unit': 'kg', 'onHand': 10, 'suggestedUnitCost': 2.5},
        {'itemType': 'MenuItem', 'itemId': 7, 'name': 'Jollof', 'onHand': 3, 'suggestedUnitCost': 12},
      ];
    await open(tester, RestaurantInternalUseScreen(session: await sessionFor(api), company: rest), size: tall);
    expect(find.text('Owner use'), findsOneWidget);
    expect(find.text('10 kgs'), findsOneWidget);

    await tester.tap(filled('Record internal use'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pick a product'));
    await tester.pumpAndSettle();
    expect(find.text('Menu items (uses the recipe)'), findsOneWidget);
    await tester.tap(find.text('Jollof').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('enough for 3 portions'), findsOneWidget);
    await enter(tester, 'Number of staff', '2');
    await enter(tester, 'portions each', '2');
    expect(find.textContaining('Not enough stock'), findsOneWidget);
    expect(tester.widget<FilledButton>(filled('Save draft')).onPressed, isNull);
    await enter(tester, 'portions each', '1');
    await tester.tap(filled('Save draft'));
    await tester.pumpAndSettle();
    final b = api.lastBody('/api/Restaurant/internal-usage');
    final line = (b['items'] as List).first as Map;
    expect((b['category'], b['staffCount'], line['itemType'], line['menuItemId'], line['ingredientId'], line['entryQuantity'], line['entryUnit'],
            line['quantityPerStaff'], line['entryUnitCost']),
        ('StaffWelfare', 2, 'MenuItem', 7, null, 2, 'portion', 1, 12));

    await tester.tap(find.byTooltip('Post').first);
    await tester.pumpAndSettle();
    await tester.tap(filled('Post'));
    await tester.pumpAndSettle();
    expect(api.writes.any((w) => w.url.path == '/api/Restaurant/internal-usage/1/post'), isTrue);

    await tester.tap(find.byTooltip('Reverse').first);
    await tester.pumpAndSettle();
    await reasonPick(tester, 'Wrong quantity');
    await tester.tap(find.widgetWithText(FilledButton, 'Reverse').last);
    await tester.pumpAndSettle();
    expect(api.lastBody('/api/Restaurant/internal-usage/2/reverse')['reason'], 'Wrong quantity');
  });

  testWidgets('Payroll: approve, mark paid, and a run with a staff line and a loan deduction', (tester) async {
    final api = FakeApi()
      ..gets['/api/Restaurant/payroll/runs'] = [
        {'payrollRunId': 1, 'runNumber': 'PR-001', 'status': 'Draft', 'periodStart': '2026-10-01', 'periodEnd': '2026-10-31',
          'payDate': '2026-10-31', 'lineCount': 0, 'totalGross': 0, 'totalDeductions': 0, 'totalNet': 0, 'totalLoanDeductions': 0},
        {'payrollRunId': 2, 'runNumber': 'PR-002', 'status': 'Approved', 'periodStart': '2026-09-01', 'periodEnd': '2026-09-30',
          'payDate': '2999-01-01', 'cashAccountId': 5, 'lineCount': 1, 'totalGross': 1000, 'totalDeductions': 100, 'totalNet': 900,
          'totalLoanDeductions': 100},
      ]
      ..gets['/api/Restaurant/staff'] = [
        {'restaurantStaffId': 5, 'firstName': 'Ama', 'lastName': 'K', 'role': 'Cook', 'salaryType': 'Monthly', 'basePay': 1000, 'isActive': true},
      ]
      ..gets['/api/Restaurant/finance/accounts'] = [{'cashAccountId': 5, 'name': 'Bank', 'currentBalance': 4000, 'isActive': true}]
      ..gets['/api/Restaurant/payroll/runs/1'] = {
        'run': {'payrollRunId': 1, 'runNumber': 'PR-001', 'status': 'Draft', 'periodStart': '2026-10-01', 'periodEnd': '2026-10-31',
          'totalGross': 0, 'totalDeductions': 0, 'totalNet': 0, 'totalLoanDeductions': 0},
        'lines': [],
        'deductions': [],
      }
      ..gets['/api/Restaurant/staff-loans/eligible'] = [
        {'staffLoanId': 9, 'loanNumber': 'SL-9', 'loanType': 'SalaryAdvance', 'outstandingBalance': 300, 'available': 300,
          'suggestedDeduction': 100, 'currentDeduction': 0},
      ]
      ..writeAnswers['/api/Restaurant/payroll/runs/1/approve'] = {'loanRepaymentsPosted': 0}
      ..writeAnswers['/api/Restaurant/payroll/runs/1/add-all-staff'] = {'added': 1};
    await open(tester, RestaurantPayrollScreen(session: await sessionFor(api), company: rest), size: tall);
    expect(find.textContaining('Approved, not yet paid (1)'), findsOneWidget);

    await tester.tap(find.byTooltip('Approve').first);
    await tester.pumpAndSettle();
    expect(api.writes.any((w) => w.url.path == '/api/Restaurant/payroll/runs/1/approve'), isTrue);
    expect(find.text('Payroll run approved'), findsOneWidget);

    await tester.tap(find.byTooltip('Mark paid').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('The P&L shows'), findsOneWidget);
    await tester.tap(filled('Mark paid'));
    await tester.pumpAndSettle();
    final paid = api.lastBody('/api/Restaurant/payroll/runs/2/mark-paid');
    expect(paid['cashAccountId'], 5);
    expect(paid['payDate'], isNot('2999-01-01'), reason: 'a future pay date is moved to today');

    await tester.tap(find.byTooltip('Open').first);
    await tester.pumpAndSettle();
    expect(find.text('No staff on this run yet.'), findsOneWidget);
    await see(tester, find.text('Choose staff'));
    await tester.tap(find.text('Choose staff'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Ama K — Cook').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('SL-9'), findsWidgets);
    expect(find.textContaining('Net pay GHC 900.00'), findsOneWidget, reason: '1000 basic less the 100 suggested deduction');
    await see(tester, filled('Add line'));
    await tester.tap(filled('Add line'));
    await tester.pumpAndSettle();
    final line = api.lastBody('/api/Restaurant/payroll/runs/1/lines');
    expect((line['restaurantStaffId'], line['basicPay'], line['paymentMethod'], '${line['loanDeductions']}'), (5, 1000, 'Cash', '[{loanId: 9, amount: 100}]'));

    await see(tester, find.text('Add all at base pay'));
    await tester.tap(find.text('Add all at base pay'));
    await tester.pumpAndSettle();
    expect(api.writes.any((w) => w.url.path == '/api/Restaurant/payroll/runs/1/add-all-staff'), isTrue);
  });
}
