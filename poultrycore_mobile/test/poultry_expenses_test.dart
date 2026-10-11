// Poultry → Expenses, at phone width: receipts and payment-status rules, the
// cards, search, delete, the table's Pay / History / Cost breakdown actions,
// and the Add Expense dialog's checks and body.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/expenses/expenses_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/expenses/receipt_field.dart';

import 'support/harness.dart';

final feed = <String, Object?>{
  'expenseId': 1, 'farmId': 'farm-1', 'expenseDate': '2026-10-02T00:00:00', 'category': 'Feed',
  'description': 'Layer mash\n::rcpt:/receipt-uploads/farm-1/a.jpg::', 'amount': 500, 'paymentMethod': 'Cash',
  'paidTo': 'Agro Ltd', 'supplierId': 7, 'supplierName': 'Agro Ltd', 'amountPaid': 200, 'balance': 300,
  'paymentStatus': 'PartiallyPaid', 'flockId': 3,
};
final vet = <String, Object?>{
  'expenseId': 2, 'farmId': 'farm-1', 'expenseDate': '2026-09-15T00:00:00', 'category': 'Veterinary',
  'description': 'Vaccines', 'amount': 120, 'paymentMethod': 'Mobile Money', 'amountPaid': 120, 'balance': 0,
  'paymentStatus': 'Paid', 'sourceType': 'PoultryMedicationConsumption', 'sourceId': 44,
};

FakeApi api() => FakeApi()
  ..gets['/api/Expense'] = [feed, vet]
  ..gets['/api/Flock'] = [{'flockId': 3, 'name': 'Layers A', 'batchId': 1}]
  ..gets['/api/Supplier'] = [{'supplierId': 7, 'name': 'Agro Ltd'}]
  ..gets['/api/Poultry/cash-accounts'] = [{'poultryCashAccountId': 5, 'accountName': 'Till', 'currentBalance': 900, 'isActive': true}];

Finder get _list => find.descendant(of: find.byType(Scaffold).last, matching: find.byType(Scrollable)).first;

Future<void> see(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
    await tester.drag(_list, const Offset(0, -200));
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
  await tester.ensureVisible(f.first);
  await tester.pumpAndSettle();
  await tester.tap(f.first);
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, String shown, String option) async {
  await tapIn(tester, find.ancestor(of: inDialog(find.text(shown)), matching: find.byType(AppSelect<String>)));
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

void clearToasts(WidgetTester tester) => tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();

void main() {
  test('receipts, payment rules, filters, links', () async {
    expect(stripReceipt(feed['description']), 'Layer mash');
    expect(receiptViewUrl(receiptPathOf(feed['description']), 'farm-1'), '/api/receipt-file/receipt-uploads/farm-1/a.jpg');
    expect(appendReceipt('Diesel', '/receipt-uploads/x.jpg'), 'Diesel\n::rcpt:/receipt-uploads/x.jpg::');
    expect(amountPaidForStatus('Paid', 5), isNull);
    expect(amountPaidForStatus('Unpaid', 5), 0);
    expect(expensePaymentErrors(total: 100, status: 'PartiallyPaid', amountPaid: 100, paymentMethod: 'Cash', cashAccountId: 5),
        ['That settles the whole bill — choose "Paid" instead.']);
    expect(expensePaymentErrors(total: 100, status: 'Paid', amountPaid: 0), [
      'Choose the cash account this money came out of.',
      'Choose a payment method.',
    ]);
    expect((isPayableExpense(feed), isPayableExpense(vet)), (true, false));
    expect(expenseStatusLabel(feed, DateTime(2026, 10, 6)), 'Partially paid');
    expect(expenseStatusLabel({...feed, 'dueDate': '2026-10-01'}, DateTime(2026, 10, 6)), 'Overdue');
    final f = ExpenseFilters()..search = 'agro';
    expect([for (final e in filterExpenses([feed, vet], f)) e['expenseId']], [1]);
    final g = ExpenseFilters()..month = '9';
    expect([for (final e in filterExpenses([feed, vet], g)) e['expenseId']], [2]);
    final h = ExpenseFilters()..cashAccount = 'none';
    expect(filterExpenses([feed, vet], h).length, 2);
    expect(pageScreens.containsKey('/expenses'), isTrue);
    final s = expensesScreenForHref('/expenses?expenseId=2', await sessionFor(FakeApi()), company) as ExpensesScreen;
    expect(s.focusExpenseId, 2);
  });

  testWidgets('cards, search, delete, table actions', (tester) async {
    final a = api();
    await open(tester, ExpensesScreen(session: await sessionFor(a), company: company), size: phone);

    expect(find.text('Total (Filtered)'), findsOneWidget);
    expect(find.text('GHC 620.00'), findsOneWidget);
    expect(find.text('Layer mash'), findsOneWidget, reason: 'receipt suffix stripped');
    expect(find.byTooltip('View receipt'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'vacc');
    await tester.pumpAndSettle();
    expect(find.text('Layer mash'), findsNothing);
    expect(find.text('GHC 120.00'), findsWidgets);

    await tap(tester, find.text('Delete'));
    expect(find.text('This will permanently remove “Vaccines”.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    final w = a.writes.last;
    expect((w.method, w.url.path, w.url.queryParameters['userId'], w.url.queryParameters['farmId']),
        ('DELETE', '/api/Expense/2', 'user-1', 'farm-1'));
    expect(find.text('No expenses found'), findsOneWidget);
    clearToasts(tester);

    await tester.enterText(find.byType(TextField).first, '');
    await tester.pumpAndSettle();
    await tap(tester, find.text('View table format'));
    expect(find.byTooltip('Record a payment against this expense'), findsOneWidget);
    expect(find.byTooltip('Payments applied to this expense'), findsOneWidget);
    expect(find.byTooltip("Open this supplier's balance"), findsOneWidget);
    expect(find.text('Partially paid'), findsOneWidget);
  });

  testWidgets('Add Expense: checks in order, then the body', (tester) async {
    final a = api();
    await open(tester, ExpensesScreen(session: await sessionFor(a), company: company), size: phone);
    await tester.tap(find.text('Add Expense'));
    await tester.pumpAndSettle();

    await tapIn(tester, inDialog(find.text('Create Expense')));
    expect(inDialog(find.text('Choose a flock')), findsNWidgets(2), reason: 'the error banner and the placeholder');
    expect(find.textContaining('Select which flock this expense belongs to'), findsOneWidget);
    clearToasts(tester);

    await choose(tester, 'Choose a flock', 'All flocks (farm-wide)');
    await choose(tester, 'Select category', 'Feed');
    await choose(tester, 'What was this expense for?', 'Other (type your own)');
    await tester.enterText(inDialog(find.byType(TextField)).last, 'Diesel');
    await tester.enterText(inDialog(find.byType(TextField)).first, '50');
    await choose(tester, 'Select payment method', 'Cash');
    await tapIn(tester, inDialog(find.text('Create Expense')));
    expect(inDialog(find.text('Choose the cash account this money came out of.')), findsOneWidget);
    clearToasts(tester);

    await choose(tester, 'Paid', 'Unpaid');
    expect(inDialog(find.text('Select a supplier if you want this unpaid expense to appear in Supplier Balances.')), findsOneWidget);
    await tapIn(tester, inDialog(find.text('Create Expense')));
    final w = a.writes.last;
    expect((w.method, w.url.path), ('POST', '/api/Expense'));
    final b = jsonDecode(w.body) as Map;
    expect((b['flockId'], b['category'], b['description'], b['amount'], b['amountPaid'], b['poultryCashAccountId'], b['supplierId']),
        (null, 'Feed', 'Diesel', 50, 0, null, null));
    expect((b['expenseDate'] as String).endsWith('T00:00:00Z'), isTrue);
    expect(find.textContaining('Expense created successfully.'), findsOneWidget);
  });

  test('receipt checks', () {
    expect(validateReceipt(ReceiptImage(Uint8List(10), 'a.heic', receiptMimeOf('a.heic'))), 'Use a JPEG, PNG, or WebP image.');
    expect(validateReceipt(ReceiptImage(Uint8List(receiptMaxBytes + 1), 'a.jpg', receiptMimeOf('a.jpg'))), 'Image must be 4 MB or smaller.');
    expect(validateReceipt(ReceiptImage(Uint8List(10), 'a.PNG', receiptMimeOf('a.PNG'))), isNull);
  });

  testWidgets('Add Expense with a receipt photo: checks, preview, upload, suffix', (tester) async {
    final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=');
    var next = ReceiptImage(Uint8List(receiptMaxBytes + 1), 'big.jpg', 'image/jpeg');
    bool? usedCamera;
    pickReceiptImage = ({required bool camera}) async {
      usedCamera = camera;
      return next;
    };
    final uploads = <(String, String)>[];
    var answer = (ok: false, path: null as String?, message: 'Only JPEG, PNG, or WebP images are allowed.' as String?);
    uploadExpenseReceipt = (session, file, farmId) async {
      uploads.add((file.name, farmId));
      return answer;
    };
    addTearDown(() {
      pickReceiptImage = ({required bool camera}) async => null;
    });

    final a = api();
    await open(tester, ExpensesScreen(session: await sessionFor(a), company: company), size: phone);
    await tester.tap(find.text('Add Expense'));
    await tester.pumpAndSettle();

    await tapIn(tester, inDialog(find.text('Take photo')));
    expect(usedCamera, isTrue);
    expect(inDialog(find.text('Image must be 4 MB or smaller.')), findsOneWidget);
    expect(inDialog(find.text('Clear new image')), findsNothing);

    next = ReceiptImage(png, 'r.png', 'image/png');
    await tapIn(tester, inDialog(find.text('Upload image')));
    expect(usedCamera, isFalse);
    expect(inDialog(find.text('Replace image')), findsOneWidget);
    expect(inDialog(find.text('Clear new image')), findsOneWidget);

    await choose(tester, 'Choose a flock', 'All flocks (farm-wide)');
    await choose(tester, 'Select category', 'Feed');
    await choose(tester, 'What was this expense for?', 'Other (type your own)');
    await tester.enterText(inDialog(find.byType(TextField)).last, 'Diesel');
    await tester.enterText(inDialog(find.byType(TextField)).first, '50');
    await choose(tester, 'Select payment method', 'Cash');
    await choose(tester, 'Paid', 'Unpaid');

    await tapIn(tester, inDialog(find.text('Create Expense')));
    expect(uploads, [('r.png', 'farm-1')]);
    expect(inDialog(find.text('Only JPEG, PNG, or WebP images are allowed.')), findsOneWidget);
    expect(a.writes.where((w) => w.url.path == '/api/Expense'), isEmpty, reason: 'nothing saved when the upload fails');

    answer = (ok: true, path: '/receipt-uploads/farm-1/x.png', message: null);
    await tapIn(tester, inDialog(find.text('Create Expense')));
    final b = jsonDecode(a.writes.last.body) as Map;
    expect(b['description'], 'Diesel\n::rcpt:/receipt-uploads/farm-1/x.png::');
  });
}
