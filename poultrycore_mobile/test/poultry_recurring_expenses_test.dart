// Poultry → Tools → Recurring Expenses (migration 348): the date and form
// rules, then the page at phone width against a fake API — review, post,
// skip, pause, end, and a new template, every body checked.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/expenses/recurring_expenses_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/expenses/recurring_logic.dart';
import 'package:poultrycore_mobile/pages/web_nav.dart';

import 'support/harness.dart';

final occurrences = [
  {
    'occurrenceId': 1, 'templateId': 7, 'templateName': 'Office rent', 'occurrenceNo': 3, 'scheduledDate': '2026-10-01T00:00:00',
    'status': 'Draft', 'amount': 500, 'templateAmount': 500, 'isVariable': false, 'expenseDate': '2026-10-01T00:00:00',
    'paymentMethod': 'Cash', 'cashAccountId': null, 'categoryName': 'Rent', 'isInterrupted': false,
  },
  {
    'occurrenceId': 2, 'templateId': 8, 'templateName': 'Electricity', 'occurrenceNo': 1, 'scheduledDate': '2026-10-05T00:00:00',
    'status': 'Draft', 'amount': 120, 'templateAmount': 120, 'isVariable': true, 'expenseDate': '2026-10-05T00:00:00',
    'paymentMethod': 'MoMo', 'cashAccountId': 5, 'categoryName': 'Utilities', 'isInterrupted': false,
  },
];

final templates = [
  {
    'templateId': 7, 'name': 'Office rent', 'categoryName': 'Rent', 'amount': 500, 'isVariable': false, 'frequency': 'Monthly',
    'startDate': '2026-08-01T00:00:00', 'paymentMethod': 'Cash', 'approvalMode': 'Draft', 'status': 'Active',
    'nextDueDate': '2026-11-01T00:00:00', 'drafts': 1, 'posted': 2, 'skipped': 0,
  },
  {
    'templateId': 9, 'name': 'Security', 'categoryName': 'Security', 'amount': 80, 'isVariable': false, 'frequency': 'Weekly',
    'startDate': '2026-10-20T00:00:00', 'paymentMethod': 'Cash', 'approvalMode': 'AutoPost', 'status': 'Paused',
    'drafts': 0, 'posted': 0, 'skipped': 0,
  },
];

FakeApi api() => FakeApi()
  ..writeAnswers['/api/recurring-expenses/generate'] = {'generated': 0, 'autoPosted': 0, 'autoPostFailures': []}
  ..gets['/api/recurring-expenses/templates'] = templates
  ..gets['/api/recurring-expenses/occurrences'] = occurrences
  ..gets['/api/recurring-expenses/upcoming'] = [
    {'templateId': 7, 'name': 'Office rent', 'amount': 500, 'isVariable': false, 'frequency': 'Monthly', 'occurrenceNo': 4,
      'scheduledDate': '2026-11-01T00:00:00', 'daysAway': 1},
  ]
  ..gets['/api/Poultry/cash-accounts'] = [
    {'poultryCashAccountId': 5, 'accountName': 'Main Cash Account', 'isActive': true},
    {'poultryCashAccountId': 6, 'accountName': 'Old till', 'isActive': false},
  ]
  ..gets['/api/Supplier'] = [
    {'supplierId': 3, 'name': 'ECG'},
  ]
  ..writeAnswers['/api/recurring-expenses/occurrences/1/record'] = {'message': 'Expense #44 recorded.'};

Finder get _list => find.descendant(of: find.byType(Scaffold).last, matching: find.byType(Scrollable)).first;

Future<void> see(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 30 && f.evaluate().isEmpty; i++) {
    await tester.drag(_list, const Offset(0, -200));
    await tester.pumpAndSettle();
  }
  for (var i = 0; i < 60 && f.evaluate().isEmpty; i++) {
    await tester.drag(_list, const Offset(0, 200));
    await tester.pumpAndSettle();
  }
  Scrollable.ensureVisible(tester.element(f.first), alignment: .5);
  await tester.pumpAndSettle();
}

Future<void> tapSeen(WidgetTester tester, Finder f) async {
  ScaffoldMessenger.of(tester.element(find.byType(Scaffold).last)).removeCurrentSnackBar();
  await tester.pumpAndSettle();
  await see(tester, f);
  await tester.tap(f.first);
  await tester.pumpAndSettle();
}

Future<void> openScreen(WidgetTester tester, FakeApi a) async =>
    open(tester, RecurringExpensesScreen(session: await sessionFor(a), company: company), size: phone);

void main() {
  test('dates from the start date, the form checks, the payment wording', () {
    expect(previewDates('2026-01-31', 'Monthly', 3), ['2026-01-31', '2026-02-28', '2026-03-31']);
    expect(previewDates('2026-10-01', 'Biweekly', 3, '2026-10-20'), ['2026-10-01', '2026-10-15']);
    expect(occurrenceDate('2024-02-29', 'Annual', 1), '2025-02-28');
    expect(frequencyLabel('SemiAnnual'), 'Every 6 months');
    expect(
      validateTemplate(name: '', amount: 0, frequency: 'Monthly', startDate: '2026-10-01', endDate: '2026-09-01', categoryOk: false, paymentMethod: 'Credit'),
      [
        'Give the recurring expense a name.',
        'The amount must be greater than 0.',
        'The end date (2026-09-01) is before the start date (2026-10-01).',
        'Choose a category.',
        'An expense bought on credit needs a supplier, so it can be owed to someone.',
      ],
    );
    expect(validateTemplate(name: 'x', amount: 1, frequency: 'Monthly', startDate: '2026-10-01', categoryOk: true, paymentMethod: 'Cash', approvalMode: 'AutoPost'),
        ['Automatic posting needs the cash account it is paid from.']);
    expect(paymentEffect('Credit', false, false), 'Posted unpaid — it becomes a supplier balance, no cash moves.');
    expect(paymentEffect('Cash', true, false), 'Paid — cash leaves the account when you post it.');
  });

  test('the route and its new place in the menu (Tools, after Receive Purchase)', () {
    expect(pageScreens.containsKey('/recurring-expenses'), isTrue);
    final groups = webNavGroups['poultry']!;
    final tools = groups.firstWhere((g) => g.title == 'Tools').subGroups.single.links;
    expect([for (final l in tools.reversed.take(2)) l.label], ['Recurring Expenses', 'Receive Purchase']);
    final expenses = groups.firstWhere((g) => g.title == 'Sales, Expenses & Money').subGroups.firstWhere((s) => s.title == 'Expenses').links;
    expect([for (final l in expenses.take(3)) l.label], ['Expenses', 'Supplier Payments', 'Supplier Balances']);
    final production = groups.firstWhere((g) => g.title == 'Operations').subGroups.firstWhere((s) => s.title == 'Production').links;
    expect([for (final l in production) l.href].contains('/egg-production'), isFalse, reason: 'the legacy page is hidden');
    expect(production.any((l) => l.label == 'Egg Sorting' && l.href == '/poultry-egg-sorting'), isTrue);
  });

  testWidgets('drafts: tiles; Post without an account opens Review; Save and post; Skip needs a reason', (tester) async {
    final a = api();
    await openScreen(tester, a);
    expect(a.writes.first.url.path, '/api/recurring-expenses/generate', reason: 'what has fallen due is raised first');
    expect(find.text('2'), findsWidgets, reason: 'Drafts to review');
    expect(find.text('GHC 620.00'), findsOneWidget, reason: 'Drafts total');
    await see(tester, find.text('Estimate — confirm the actual amount'));
    expect(find.text('Estimate — confirm the actual amount'), findsOneWidget);
    expect(find.text('Cash · no cash account · dated 2026-10-01'), findsOneWidget);

    await tapSeen(tester, find.text('Post').first);
    expect(find.text('Choose a cash account first — Pick the account this is paid from, then post.'), findsOneWidget);
    expect(find.text('Choose the cash account it is paid from.'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save and post')).onPressed, isNull);
    await pick(tester, 'Choose', 'Main Cash Account');
    expect(find.text('Old till'), findsNothing, reason: 'inactive accounts are not offered');
    await tester.tap(find.widgetWithText(FilledButton, 'Save and post'));
    await tester.pumpAndSettle();
    final put = a.lastBody('/api/recurring-expenses/occurrences/1', 'PUT');
    expect((put['amount'], put['expenseDate'], put['paymentMethod'], put['cashAccountId'], put['farmId']), (500, '2026-10-01', 'Cash', 5, 'farm-1'));
    expect(a.writes.any((w) => w.url.path == '/api/recurring-expenses/occurrences/1/record'), isTrue);
    expect(find.text('Office rent posted — Expense #44 recorded.'), findsOneWidget);

    await tapSeen(tester, find.text('Skip').last);
    expect(find.text('Skip Electricity (2026-10-05)?'), findsOneWidget);
    // As the web's PromptDialog with options: Skip says a reason is needed.
    await tester.tap(find.widgetWithText(FilledButton, 'Skip'));
    await tester.pumpAndSettle();
    expect(find.text('Why? is required.'), findsOneWidget);
    await reasonOther(tester, 'no power this month');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Skip'));
    await tester.pumpAndSettle();
    expect(a.lastBody('/api/recurring-expenses/occurrences/2/skip', 'PUT')['reason'], 'no power this month');
  });

  testWidgets('show filter, upcoming, templates: pause, resume, end, delete only when unused', (tester) async {
    final a = api();
    await openScreen(tester, a);
    await tapSeen(tester, find.text('Skipped'));
    expect(a.requests.lastWhere((r) => r.url.path == '/api/recurring-expenses/occurrences').url.queryParameters['status'], 'Skipped');

    await tapSeen(tester, find.text('Upcoming'));
    await see(tester, find.text('2026-11-01 · tomorrow · Monthly'));
    expect(find.text('2026-11-01 · tomorrow · Monthly'), findsOneWidget);
    await tapSeen(tester, find.text('Next 7 days'));
    expect(a.requests.lastWhere((r) => r.url.path == '/api/recurring-expenses/upcoming').url.queryParameters['days'], '7');
    expect(find.text('Due in next 7 days'), findsOneWidget);

    await tapSeen(tester, find.textContaining('Templates'));
    await see(tester, find.text('Posts automatically'));
    expect(find.text('Posts automatically'), findsOneWidget);
    expect(find.text('2 posted · 1 waiting · 0 skipped'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget, reason: 'only Security has never been raised');
    await tapSeen(tester, find.text('Pause'));
    expect(a.lastBody('/api/recurring-expenses/templates/7/status', 'PUT')['action'], 'Pause');
    await tapSeen(tester, find.text('Resume'));
    expect(find.text('Resumed — It continues from today; periods missed while paused are not raised.'), findsOneWidget);

    await tapSeen(tester, find.text('End').first);
    expect(find.text('End "Office rent"?'), findsOneWidget);
    // END_REASONS: the reason is picked from the list (it was optional free text).
    await reasonPick(tester, 'No longer needed');
    await tester.tap(find.widgetWithText(FilledButton, 'End it'));
    await tester.pumpAndSettle();
    final end = a.lastBody('/api/recurring-expenses/templates/7/status', 'PUT');
    expect((end['action'], end['reason']), ('End', 'No longer needed'));
  });

  testWidgets('a new template: the checks, the preview, then the body', (tester) async {
    final a = api();
    await openScreen(tester, a);
    await tester.tap(find.text('New recurring expense'));
    await tester.pumpAndSettle();
    expect(find.text('New recurring expense'), findsWidgets);
    await see(tester, find.widgetWithText(FilledButton, 'Save'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    await see(tester, find.text('Give the recurring expense a name.'));
    expect(find.text('Choose a category.'), findsOneWidget);
    expect(a.writes.where((w) => w.url.path == '/api/recurring-expenses/templates'), isEmpty);

    await see(tester, find.text('e.g. Office rent'));
    await tester.enterText(find.widgetWithText(TextFormField, 'e.g. Office rent'), 'Internet');
    await see(tester, find.text('Choose'));
    await pick(tester, 'Choose', 'Internet');
    await see(tester, find.text('Amount *'));
    await enter(tester, 'Amount *', '300');
    await see(tester, find.text('Monthly'));
    await pick(tester, 'Monthly', 'Quarterly');
    await see(tester, find.text('Cash'));
    await pick(tester, 'Cash', 'Credit (pay later)');
    expect(find.text('Cash account'), findsNothing, reason: 'credit has no cash account');
    await see(tester, find.text('Post automatically'));
    await tester.tap(find.text('Post automatically'));
    await tester.pumpAndSettle();
    await see(tester, find.textContaining('Next dates:', findRichText: true));
    expect(find.text('Posted unpaid — it becomes a supplier balance, no cash moves.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    await see(tester, find.text('An expense bought on credit needs a supplier, so it can be owed to someone.'));

    await see(tester, find.text('No supplier'));
    await pick(tester, 'No supplier', 'ECG');
    await see(tester, find.widgetWithText(FilledButton, 'Save'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    final b = a.lastBody('/api/recurring-expenses/templates');
    expect((b['name'], b['categoryName'], b['amount'], b['frequency'], b['paymentMethod'], b['supplierId'], b['approvalMode'], b['farmId']),
        ('Internet', 'Internet', 300, 'Quarterly', 'Credit', 3, 'AutoPost', 'farm-1'));
    expect(find.text('Recurring expense created'), findsOneWidget);
  });
}
