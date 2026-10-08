// Poultry → Money → Cash Account: the rules, the list page (figures, search,
// every header button and dialog, recent transfers) and the account page
// (ledger, running balance, Adjust balance, clearing), at phone width.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/money/cash_accounts_screen.dart';

import 'support/harness.dart';

final accounts = <Map>[
  {'poultryCashAccountId': 5, 'accountName': 'Main Cash Account', 'accountType': 'FarmCashBox', 'openingBalance': 100, 'currentBalance': 900, 'allowNegativeBalance': false, 'isActive': true},
  {'poultryCashAccountId': 6, 'accountName': 'GCB Current', 'accountType': 'BankAccount', 'openingBalance': 0, 'currentBalance': -50, 'allowNegativeBalance': true, 'isActive': true, 'notes': 'Overdraft'},
  {'poultryCashAccountId': 7, 'accountName': 'Old Till', 'accountType': 'PettyCash', 'openingBalance': 0, 'currentBalance': 20, 'allowNegativeBalance': false, 'isActive': false},
];

final status = <Map>[
  {'poultryCashAccountId': 5, 'ledgerBalance': 1000, 'cacheDrift': -100, 'lastReconciledAt': '2026-10-01', 'daysSinceReconciled': 5},
  {'poultryCashAccountId': 6, 'ledgerBalance': -50, 'cacheDrift': 0, 'lastReconciledAt': null},
];

final transfers = <Map>[
  {'poultryCashTransferId': 31, 'fromAccountName': 'Main Cash Account', 'toAccountName': 'GCB Current', 'transferDate': '2026-10-02T00:00:00', 'amount': 300, 'status': 'Draft'},
  {'poultryCashTransferId': 30, 'fromAccountName': 'GCB Current', 'toAccountName': 'Main Cash Account', 'transferDate': '2026-09-20T00:00:00', 'amount': 80, 'status': 'Approved'},
];

final txns = <Map>[
  {'poultryCashTransactionId': 2, 'transactionDate': '2026-10-02T00:00:00', 'transactionType': 'CashOut', 'sourceType': 'Expense', 'amount': -200, 'description': 'Feed'},
  {'poultryCashTransactionId': 1, 'transactionDate': '2026-10-01T00:00:00', 'transactionType': 'CashIn', 'sourceType': 'Sale', 'amount': 1000, 'description': 'Eggs', 'clearingStatus': 'Cleared', 'poultryCashReconciliationId': 4, 'reconciliationReference': 'CC-4'},
];

FakeApi api() => FakeApi()
  ..gets['/api/CompanyTime/context'] = {
    'businessDate': '2026-10-06', 'companyLocalDateTime': '2026-10-06T10:00:00', 'utcNow': '2026-10-06T10:00:00Z',
  }
  ..gets['/api/Poultry/cash-accounts'] = accounts
  ..gets['/api/Poultry/cash-transfers'] = transfers
  ..gets['/api/Poultry/cash-reconciliations/account-status'] = status
  ..gets['/api/Poultry/cash-accounts/5'] = accounts[0]
  ..gets['/api/Poultry/cash-accounts/transactions'] = txns
  ..writeAnswers['/api/Poultry/cash-transfers'] = {'poultryCashTransferId': 44};

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
  await tapIn(tester, find.ancestor(of: inDialog(find.text(shown)), matching: find.byType(AppSelect<String>)));
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

void main() {
  group('cash account rules', () {
    test('ledger labels, attention, cash at hand, running balance', () {
      expect(ledgerTypeLabel('OwnerDrawReversal'), 'Owner draw reversed');
      expect(ledgerTypeLabel('SupplierRefundIn'), 'Supplier Refund In');
      expect(ledgerTypeLabel(null), '—');
      expect(accountAttention(status[0]), 'Stored balance disagrees with its transactions');
      expect(accountAttention(status[1]), 'Never reconciled');
      expect(accountAttention({'cacheDrift': 0, 'lastReconciledAt': '2026-08-01', 'daysSinceReconciled': 45}), 'Not reconciled in 45 days');
      expect(accountAttention({'cacheDrift': 0.004, 'lastReconciledAt': '2026-10-01', 'daysSinceReconciled': 3}), isNull);
      final byId = {for (final s in status) '${s['poultryCashAccountId']}': s};
      expect(totalCashAtHand(accounts, byId), 950, reason: 'ledger balances of active accounts');
      expect(totalCashAtHand(accounts, {}), 850, reason: 'cached balances without the status feed');
      final l = accountLedger(txns, 100);
      expect([for (final r in l) r['running']], [900, 1100], reason: 'newest first, accumulated oldest first');
    });
  });

  test('on the sidebar route', () => expect(pageScreens.containsKey('/poultry-cash-accounts'), isTrue));

  testWidgets('figures, cards, search, table, recent transfers, delete', (tester) async {
    final a = api();
    await open(tester, CashAccountsScreen(session: await sessionFor(a), company: company), size: phone);

    expect(find.text('GHC 950.00'), findsOneWidget);
    expect(find.text('2'), findsOneWidget, reason: 'active accounts');
    expect(find.text('1'), findsNWidgets(2), reason: 'one pending, one approved transfer');
    await see(tester, find.text('Main Cash Account'));
    await see(tester, find.text('GHC -50.00'));
    await see(tester, find.text('Inactive'));

    final searchBox = find.descendant(
        of: find.ancestor(of: find.text('Search'), matching: find.byType(Column)).first, matching: find.byType(TextFormField));
    await see(tester, find.text('Search'));
    await tester.enterText(searchBox, 'bank');
    await tester.pumpAndSettle();
    expect(find.text('Old Till'), findsNothing);
    await see(tester, find.text('GCB Current'));
    await see(tester, find.text('Search'));
    await tester.enterText(searchBox, '');
    await tester.pumpAndSettle();

    await tap(tester, find.text('View table format'));
    await see(tester, find.text('drift'));
    expect(find.text('Stored balance disagrees with its transactions'), findsOneWidget);
    await see(tester, find.text('Never reconciled'));
    await tap(tester, find.text('Cards'));

    await see(tester, find.text('Recent transfers'));
    await see(tester, find.text('Main Cash Account → GCB Current'));
    await tap(tester, find.widgetWithText(OutlinedButton, 'Approve'));
    expect(a.writes.last.url.path, '/api/Poultry/cash-transfers/31/approve');
    expect(a.writes.last.url.queryParameters['approvedBy'], 'user-1');

    await tap(tester, find.widgetWithText(OutlinedButton, 'Delete'));
    expect(find.text('Remove Main Cash Account?'), findsOneWidget);
    await tester.tap(find.text('Remove account'));
    await tester.pumpAndSettle();
    expect(a.writes.last.method, 'DELETE');
    expect(a.writes.last.url.path, '/api/Poultry/cash-accounts/5');
    expect(find.textContaining('Cash account removed'), findsOneWidget);
  });

  testWidgets('New account, Edit, default account, Recalculate', (tester) async {
    final a = api();
    await open(tester, CashAccountsScreen(session: await sessionFor(a), company: company), size: phone);

    await tap(tester, find.text('Create default account'));
    expect(find.textContaining('Default account already exists'), findsOneWidget);
    expect(a.writes, isEmpty);
    clearToasts(tester);

    await tap(tester, find.text('Recalculate'));
    expect(a.writes.single.url.path, '/api/Poultry/cash-accounts/reconcile-balances');

    await tap(tester, find.text('New account'));
    await tapIn(tester, inDialog(find.text('Save')));
    expect(find.textContaining('Name required'), findsOneWidget);
    clearToasts(tester);
    await enterIn(tester, 'Name *', 'MTN MoMo');
    await choose(tester, 'FarmCashBox', 'MoMoWallet');
    await enterIn(tester, 'Opening balance', '250');
    await tapIn(tester, inDialog(find.byType(Switch).first));
    expect(inDialog(find.text('Active')), findsNothing, reason: 'Active is an edit-only switch');
    await tapIn(tester, inDialog(find.text('Save')));
    final b = a.lastBody('/api/Poultry/cash-accounts');
    expect(b, {
      'accountName': 'MTN MoMo', 'accountType': 'MoMoWallet', 'openingBalance': 250, 'allowNegativeBalance': true,
      'notes': '', 'farmId': 'farm-1',
    });

    await tap(tester, find.widgetWithText(OutlinedButton, 'Edit'));
    expect(find.text('Edit account'), findsOneWidget);
    expect(inDialog(find.text('Opening balance')), findsNothing);
    await tapIn(tester, inDialog(find.byType(Switch).last));
    await tapIn(tester, inDialog(find.text('Save')));
    final u = a.lastBody('/api/Poultry/cash-accounts/5', 'PUT');
    expect(u['isActive'], false);
    expect(u['poultryCashAccountId'], 5);
    expect(u['accountName'], 'Main Cash Account');
    expect(find.textContaining('Account updated'), findsOneWidget);
  });

  testWidgets('Transfer: checks, the Other note, then create and approve', (tester) async {
    final a = api();
    await open(tester, CashAccountsScreen(session: await sessionFor(a), company: company), size: phone);
    await tap(tester, find.widgetWithText(OutlinedButton, 'Transfer'));
    expect(find.text('Cash transfer (Draft → Approved)'), findsOneWidget);
    final go = inDialog(find.text('Create & approve'));
    await tapIn(tester, go);
    expect(find.textContaining('From and To must differ'), findsOneWidget);
    clearToasts(tester);
    await choose(tester, 'From account', 'Main Cash Account');
    await choose(tester, 'To account', 'GCB Current');
    await tapIn(tester, go);
    expect(find.textContaining('Amount required'), findsOneWidget);
    clearToasts(tester);
    await enterIn(tester, 'Amount', '150');
    await choose(tester, 'Why is the money moving?', 'Other');
    await tapIn(tester, go);
    expect(find.textContaining('Say what happened'), findsWidgets);
    clearToasts(tester);
    await enterIn(tester, 'Say what happened *', 'Safe overnight');
    await tapIn(tester, go);
    final b = a.lastBody('/api/Poultry/cash-transfers');
    expect(b['fromPoultryCashAccountId'], 5);
    expect(b['toPoultryCashAccountId'], 6);
    expect(b['amount'], 150);
    expect(b['notes'], 'Safe overnight');
    expect(a.writes.last.url.path, '/api/Poultry/cash-transfers/44/approve');
    expect(find.textContaining('Transfer approved'), findsOneWidget);
  });

  testWidgets('Record Cash Adjustment steers a shortage to Reconcile', (tester) async {
    final a = api();
    await open(tester, CashAccountsScreen(session: await sessionFor(a), company: company), size: phone);
    await tap(tester, find.text('Record Cash Adjustment'));
    final save = inDialog(find.widgetWithText(FilledButton, 'Record adjustment'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await choose(tester, 'Which account?', 'GCB Current');
    await choose(tester, 'Add money (cash in)', 'Remove money (cash out)');
    await enterIn(tester, 'Amount *', '12');
    await choose(tester, 'Why is the balance changing?', 'Cash shortage');
    expect(find.textContaining('A cash shortage means reality disagreed with the books'), findsOneWidget);
    expect(find.text('Reconcile this account'), findsOneWidget);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await choose(tester, 'Cash shortage', 'Bank charge');
    expect(find.textContaining('A money-out transaction of GHC 12.00'), findsOneWidget);
    await tapIn(tester, save);
    final w = a.writes.single;
    expect(w.url.path, '/api/Poultry/cash-accounts/6/adjust');
    expect(a.lastBody('/api/Poultry/cash-accounts/6/adjust'), {'amount': -12, 'reason': 'Bank charge', 'createdBy': 'user-1'});
    expect(find.textContaining('GHC 12.00 removed from the account.'), findsOneWidget);
  });

  testWidgets('account page: figures, ledger, Adjust balance, clearing', (tester) async {
    final a = api();
    await open(tester, CashAccountDetailScreen(session: await sessionFor(a), company: company, accountId: 5), size: phone);

    expect(find.text('Back to Cash Account'), findsOneWidget);
    expect(find.text('FarmCashBox'), findsOneWidget);
    expect(find.text('GHC 1,000.00'), findsOneWidget, reason: 'money in');
    expect(find.text('GHC 200.00'), findsOneWidget, reason: 'money out');
    await see(tester, find.text('−GHC 200.00 · CashOut'));
    expect(find.text('2 Oct 2026 · Bal GHC 900.00'), findsOneWidget);
    expect(find.text('Running balance'), findsNothing, reason: 'cards start closed here');

    await tap(tester, find.text('Adjust balance'));
    final save = inDialog(find.text('Save adjustment'));
    await tapIn(tester, save);
    expect(find.textContaining('Enter an amount greater than 0'), findsOneWidget);
    clearToasts(tester);
    await enterIn(tester, 'Amount *', '50');
    await tapIn(tester, save);
    expect(find.textContaining('Pick a reason'), findsOneWidget);
    clearToasts(tester);
    await choose(tester, 'Why is the balance changing?', 'Rounding difference');
    expect(find.textContaining('New balance will be GHC 950.00 (from GHC 900.00).', findRichText: true), findsOneWidget);
    await tapIn(tester, save);
    expect(a.lastBody('/api/Poultry/cash-accounts/5/adjust'), {'amount': 50, 'reason': 'Rounding difference', 'createdBy': 'user-1'});
    expect(find.textContaining('Added GHC 50.00.'), findsOneWidget);
    clearToasts(tester);

    await tap(tester, find.text('View table format'));
    await see(tester, find.text('Uncleared'));
    expect(find.byWidgetPredicate((w) => w is Tooltip && w.message == 'Cleared by cash count CC-4'), findsOneWidget, reason: 'locked by a count: a badge');
    await tester.tap(find.text('Uncleared'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disputed').last);
    await tester.pumpAndSettle();
    final c = a.lastBody('/api/Poultry/cash-reconciliations/clearing');
    expect(c, {'poultryCashAccountId': 5, 'transactionIds': [2], 'clearingStatus': 'Disputed', 'userId': 'user-1'});
  });
}
