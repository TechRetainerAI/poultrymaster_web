// Poultry → Money → Reconciliation: the rules, then the page at phone width —
// account picker, tiles, drift and draft banners, history actions, the count
// form (save / edit / count again), discard, post and reverse.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/money/cash_accounts_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/money/cash_vocabulary.dart';
import 'package:poultrycore_mobile/pages/poultry/money/money_routes.dart';
import 'package:poultrycore_mobile/pages/poultry/money/reconciliation_screen.dart';

import 'support/harness.dart';

final accounts = <Map>[
  {'poultryCashAccountId': 4, 'accountName': 'Old Box', 'accountType': 'FarmCashBox', 'currentBalance': 0, 'isActive': false},
  {'poultryCashAccountId': 5, 'accountName': 'Main Cash', 'accountType': 'FarmCashBox', 'currentBalance': 900, 'isActive': true},
  {'poultryCashAccountId': 6, 'accountName': 'GCB Current', 'accountType': 'BankAccount', 'currentBalance': 2000, 'isActive': true},
];

final status = <Map>[
  {
    'poultryCashAccountId': 5, 'ledgerBalance': 1000, 'cacheDrift': -100, 'lastReconciledAt': '2026-09-30T00:00:00',
    'lastReconciledBalance': 950, 'daysSinceReconciled': 6, 'unclearedCount': 3, 'unclearedAmount': 420,
  },
];

final counts = <Map>[
  {
    'poultryCashReconciliationId': 21, 'referenceNo': 'CC-21', 'reconciliationDate': '2026-10-05T00:00:00', 'systemBalance': 1000,
    'actualBalance': 980, 'difference': -20, 'reason': 'Cash shortage', 'status': 'Draft',
  },
  {
    'poultryCashReconciliationId': 20, 'referenceNo': 'CC-20', 'reconciliationDate': '2026-09-30T00:00:00', 'systemBalance': 950,
    'actualBalance': 950, 'difference': 0, 'status': 'Posted',
  },
  {
    'poultryCashReconciliationId': 19, 'referenceNo': 'CC-19', 'reconciliationDate': '2026-09-01T00:00:00', 'systemBalance': 700,
    'actualBalance': 750, 'difference': 50, 'reason': 'Till float returned', 'notes': 'Depot', 'status': 'Reversed',
  },
];

FakeApi api() => FakeApi()
  ..gets['/api/CompanyTime/context'] = {
    'businessDate': '2026-10-06', 'companyLocalDateTime': '2026-10-06T10:00:00', 'utcNow': '2026-10-06T10:00:00Z',
  }
  ..gets['/api/Poultry/cash-accounts'] = accounts
  ..gets['/api/Poultry/cash-reconciliations/account-status'] = status
  ..gets['/api/Poultry/cash-reconciliations/account/5'] = counts
  ..gets['/api/Poultry/cash-reconciliations/account/6'] = <Map>[]
  ..writeAnswers['/api/Poultry/cash-reconciliations/21/post'] = {'adjustmentTransactionId': 77};

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
  group('reconciliation rules', () {
    test('words follow the account type', () {
      expect(cashAccountVocabulary('FarmCashBox').action, 'Reconcile Cash Balance');
      expect(cashAccountVocabulary('BankAccount').amountLabel, 'Statement Balance');
      expect(cashAccountVocabulary('MoMoWallet').recordNoun, 'MoMo reconciliation');
      expect(cashAccountVocabulary(null).emptyHistory, 'This account has never been reconciled.');
    });

    test('opening account, difference to the cent', () {
      expect(initialReconcileAccount(accounts, 6), 6);
      expect(initialReconcileAccount(accounts, 99), 5, reason: 'unknown id → first active');
      expect(initialReconcileAccount(accounts, null), 5);
      expect(countDifference(980, 1000), (difference: -20, balanced: false));
      expect(countDifference(1000.004, 1000).balanced, isTrue);
    });

    test('links with an id or a query open natively', () async {
      final sessionStub = await sessionFor(FakeApi());
      expect(pageScreens.containsKey('/poultry-cash-reconciliation'), isTrue);
      final s = moneyScreenForHref('/poultry-cash-reconciliation?accountId=6', sessionStub, company);
      expect((s as ReconciliationScreen).accountId, 6);
      expect(moneyScreenForHref('/poultry-cash-accounts/5', sessionStub, company), isNotNull);
      expect(moneyScreenForHref('/poultry-cash-accounts', sessionStub, company), isNull);
    });
  });

  testWidgets('tiles, banners, history, table; another account; post the draft', (tester) async {
    final a = api();
    await open(tester, ReconciliationScreen(session: await sessionFor(a), company: company), size: phone);

    expect(find.text('Main Cash'), findsOneWidget, reason: 'first active account');
    expect(find.text('Finish CC-21'), findsOneWidget);
    expect(find.text('GHC 1,000.00'), findsOneWidget, reason: 'the ledger balance, not the cache');
    expect(find.text('rebuilt from transactions'), findsOneWidget);
    expect(find.text('2026-09-30'), findsOneWidget);
    expect(find.text('6 days ago'), findsOneWidget);
    expect(find.text('GHC 420.00'), findsOneWidget);
    await see(tester, find.textContaining('is GHC 100.00 away from what its transactions add up to'));
    await see(tester, find.textContaining('CC-21 is saved but not posted'));
    expect(find.textContaining('Counted GHC 980.00.'), findsOneWidget);

    await see(tester, find.text('CC-19'));
    expect(find.text('Balanced'), findsOneWidget);
    expect(find.text('Count again'), findsOneWidget);
    await see(tester, find.text('Reverse'));

    await tap(tester, find.text('View table format'));
    await see(tester, find.text('Actual Balance'));
    expect(find.byTooltip('Post this count to the ledger'), findsOneWidget);
    await tap(tester, find.text('Cards'));

    await tap(tester, find.text('Post it'));
    expect(a.writes.last.url.path, '/api/Poultry/cash-reconciliations/21/post');
    expect(a.lastBody('/api/Poultry/cash-reconciliations/21/post'), {'clearedTransactionIds': [], 'postedBy': 'user-1'});
    expect(find.textContaining('Cash count posted'), findsOneWidget);
    clearToasts(tester);

    await see(tester, find.text('ACCOUNT TO RECONCILE'));
    await tester.tap(find.text('Main Cash'));
    await tester.pumpAndSettle();
    expect(find.text('Old Box (inactive)'), findsWidgets);
    await tester.tap(find.text('GCB Current').last);
    await tester.pumpAndSettle();
    expect(find.text('Reconcile Bank Account'), findsOneWidget);
    await see(tester, find.text('This account has never been reconciled against a statement.'));
    expect(find.text('Never'), findsOneWidget);
  });

  testWidgets('the count form: a reason when it differs, Other needs a note, the body', (tester) async {
    final a = api();
    await open(tester, ReconciliationScreen(session: await sessionFor(a), company: company, accountId: 6), size: phone);
    await tap(tester, find.text('Reconcile Bank Account'));
    expect(find.textContaining('GCB Current — saving does not move money.'), findsOneWidget);
    final save = inDialog(find.widgetWithText(FilledButton, 'Save bank reconciliation'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    await enterIn(tester, 'Statement Balance *', '2000');
    await tester.pumpAndSettle();
    expect(find.text('Balanced — no adjustment needed'), findsOneWidget);
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull, reason: 'balanced needs no reason');

    await enterIn(tester, 'Statement Balance *', '1985.5');
    await tester.pumpAndSettle();
    expect(find.text('Difference: GHC -14.50 (short)'), findsOneWidget);
    expect(find.textContaining('A money-out adjustment of GHC 14.50 will be posted'), findsOneWidget);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await choose(tester, 'Why the difference?', 'Other');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(inDialog(find.widgetWithText(TextFormField, 'Say what happened')), 'Charge not on our books');
    await tester.pumpAndSettle();
    await tapIn(tester, save);

    final b = a.lastBody('/api/Poultry/cash-reconciliations');
    expect(a.writes.last.url.queryParameters, {'farmId': 'farm-1'});
    expect(b['reconciliationDate'], DateTime.now().toUtc().toIso8601String().substring(0, 10), reason: 'a plain day, no clock time');
    b.remove('reconciliationDate');
    expect(b, {'poultryCashAccountId': 6, 'actualBalance': 1985.5, 'reason': 'Charge not on our books', 'notes': null, 'createdBy': 'user-1'});
    expect(find.textContaining('Bank reconciliation saved'), findsOneWidget);
  });

  testWidgets('edit the draft, count again is locked while a draft is open, discard, reverse', (tester) async {
    final a = api();
    await open(tester, ReconciliationScreen(session: await sessionFor(a), company: company), size: phone);

    await tap(tester, find.text('Finish CC-21'));
    expect(find.text('Edit CC-21'), findsOneWidget);
    expect(find.text('Cash shortage'), findsWidgets, reason: 'the stored reason is preselected');
    await enterIn(tester, 'Amount Counted *', '990');
    await tester.pumpAndSettle();
    await tapIn(tester, inDialog(find.widgetWithText(FilledButton, 'Save cash count')));
    final put = a.writes.last;
    expect(put.method, 'PUT');
    expect(put.url.path, '/api/Poultry/cash-reconciliations/21');
    expect(a.lastBody('/api/Poultry/cash-reconciliations/21', 'PUT')['actualBalance'], 990);
    expect(a.lastBody('/api/Poultry/cash-reconciliations/21', 'PUT')['reconciliationDate'], '2026-10-05');
    clearToasts(tester);

    await tap(tester, find.text('Count again'));
    expect(find.text('Reconcile Cash Balance again'), findsOneWidget);
    expect(find.textContaining('Seeded from CC-19'), findsOneWidget);
    expect(inDialog(find.text('Till float returned')), findsOneWidget, reason: 'an unlisted reason comes back as Other + its text');
    expect(tester.widget<FilledButton>(inDialog(find.widgetWithText(FilledButton, 'Save cash count'))).onPressed, isNull,
        reason: 'one open draft per account');
    await tapIn(tester, inDialog(find.text('Cancel')));

    await tap(tester, find.widgetWithText(OutlinedButton, 'Discard'));
    expect(find.text('Discard CC-21?'), findsOneWidget);
    await tester.tap(find.text('Discard draft'));
    await tester.pumpAndSettle();
    expect(a.writes.last.method, 'DELETE');
    expect(a.writes.last.url.path, '/api/Poultry/cash-reconciliations/21');
    expect(a.writes.last.url.queryParameters, {'farmId': 'farm-1', 'userId': 'user-1'});

    await tap(tester, find.widgetWithText(OutlinedButton, 'Reverse'));
    expect(find.text('Reverse this cash count?'), findsOneWidget);
    await tapIn(tester, inDialog(find.widgetWithText(FilledButton, 'Reverse')));
    expect(find.text('Reason for reversal is required.'), findsOneWidget);
    await choose(tester, 'Why is this count being reversed?', 'Duplicate count');
    await tapIn(tester, inDialog(find.widgetWithText(FilledButton, 'Reverse')));
    expect(a.lastBody('/api/Poultry/cash-reconciliations/20/reverse'), {'reason': 'Duplicate count', 'reversedBy': 'user-1'});
    expect(find.textContaining('Cash count reversed'), findsOneWidget);
  });

  testWidgets('Back goes to the Cash Account list, as the web link does', (tester) async {
    final a = api()..gets['/api/Poultry/cash-transfers'] = <Map>[];
    await open(tester, ReconciliationScreen(session: await sessionFor(a), company: company), size: phone);
    await tester.tap(find.text('Back to Cash & Accounts'));
    await tester.pumpAndSettle();
    expect(find.byType(CashAccountsScreen), findsOneWidget);
    expect(find.byType(ReconciliationScreen), findsNothing);
  });
}
