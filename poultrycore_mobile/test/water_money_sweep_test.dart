// Water Sales / Expenses / Money sweep (2026-10-20): Recurring Expenses under
// Water's own route with Water's lookups, and the reason lists on Water's own
// Cancel expense / Cancel run / Reopen run prompts.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/expenses/recurring_expenses_screen.dart';
import 'package:poultrycore_mobile/pages/water/water_payroll_screen.dart';
import 'package:poultrycore_mobile/pages/web_nav.dart';

import 'support/harness.dart';

final water = Company(farmId: 'farm-1', name: 'Win Water', type: CompanyType.water, role: 'Admin');

FakeApi api() => FakeApi()
  ..writeAnswers['/api/recurring-expenses/generate'] = {'generated': 0, 'autoPosted': 0, 'autoPostFailures': []}
  ..gets['/api/recurring-expenses/templates'] = []
  ..gets['/api/recurring-expenses/occurrences'] = []
  ..gets['/api/recurring-expenses/upcoming'] = []
  ..gets['/api/Water/expense-categories'] = [
    {'waterExpenseCategoryId': 4, 'name': 'Rent', 'isActive': true},
    {'waterExpenseCategoryId': 5, 'name': 'Old category', 'isActive': false},
  ]
  ..gets['/api/Water/suppliers'] = [
    {'waterSupplierId': 2, 'supplierName': 'Landlord Ltd'},
  ]
  ..gets['/api/Water/cash-accounts'] = [
    {'waterCashAccountId': 9, 'accountName': 'Main till', 'isActive': true},
  ];

Finder get _list => find.descendant(of: find.byType(Scaffold).last, matching: find.byType(Scrollable)).first;

Future<void> see(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 30 && f.evaluate().isEmpty; i++) {
    await tester.drag(_list, const Offset(0, -200));
    await tester.pumpAndSettle();
  }
  Scrollable.ensureVisible(tester.element(f.first), alignment: .5);
  await tester.pumpAndSettle();
}

void main() {
  test('Recurring Expenses is routed and in the Water Expenses menu, under Expenses', () {
    expect(pageScreens['/water-recurring-expenses'], isNotNull);
    final expenses = webNavGroups['water']!.expand((g) => g.subGroups).firstWhere((s) => s.title == 'Expenses');
    expect([for (final l in expenses.links.take(3)) l.label], ['Expenses', 'Recurring Expenses', 'Internal Use']);
  });

  test('Operations: Inventory & supply purchases has the new address, and the old one still opens it', () {
    expect(pageScreens['/water-supply-purchases'], isNotNull);
    expect(pageScreens['/water-raw-materials'], isNotNull);
    final inventory = webNavGroups['water']!.expand((g) => g.subGroups).firstWhere((s) => s.title == 'Inventory');
    expect(inventory.links.any((l) => l.label == 'Inventory & supply purchases' && l.href == '/water-supply-purchases'), isTrue);
  });

  testWidgets('Water Recurring Expenses: approval note, category table by id', (tester) async {
    final a = api();
    await open(tester, RecurringExpensesScreen(session: await sessionFor(a), company: water), size: phone);
    expect(find.text(' Posted expenses then follow the normal approval on ', findRichText: true), findsNothing);
    expect(find.textContaining('Posted expenses then follow the normal approval on', findRichText: true), findsOneWidget);

    await tester.tap(find.text('New recurring expense'));
    await tester.pumpAndSettle();
    await see(tester, find.text('e.g. Office rent'));
    await tester.enterText(find.widgetWithText(TextFormField, 'e.g. Office rent'), 'Plant rent');
    await see(tester, find.text('Choose'));
    await tester.tap(find.text('Choose').first);
    await tester.pumpAndSettle();
    expect(find.text('Old category'), findsNothing, reason: 'inactive categories are not offered');
    await tester.tap(find.text('Rent').last);
    await tester.pumpAndSettle();
    await see(tester, find.text('Amount *'));
    await enter(tester, 'Amount *', '900');
    await see(tester, find.widgetWithText(FilledButton, 'Save'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    final b = a.lastBody('/api/recurring-expenses/templates');
    expect((b['name'], b['categoryId'], b['categoryName'], b['amount']), ('Plant rent', 4, 'Rent', 900));
  });

  testWidgets('Water prompts: Cancel takes a reason from the list', (tester) async {
    String? sent;
    await open(
      tester,
      Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => showWaterPayrollPrompt(context,
                title: 'Cancel payroll run', description: 'Run will be cancelled.', label: 'Reason (optional)', placeholder: '',
                confirm: 'Cancel run', allowEmpty: true, options: const ['Created by mistake', 'Other'], onSubmit: (r) async {
              sent = r;
              return true;
            }),
            child: const Text('open'),
          ),
        ),
      ),
      size: phone,
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel run'));
    await tester.pumpAndSettle();
    expect(find.text('Reason (optional) is required.'), findsOneWidget, reason: "PromptDialog with options: a pick is needed");
    await reasonOther(tester, 'Ran twice');
    await tester.tap(find.text('Cancel run'));
    await tester.pumpAndSettle();
    expect(sent, 'Ran twice');
  });
}
