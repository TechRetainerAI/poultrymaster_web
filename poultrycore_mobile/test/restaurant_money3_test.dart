// Restaurant → Money (2026-10-20, last set): Cash Transfers and Reconciliation
// as the web pages, against a fake API at phone width.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_cash_reconciliation_screen.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_cash_transfers_screen.dart';

import 'support/harness.dart' hide enter;

final rest = Company(farmId: 'farm-1', name: 'Rose Bistro', type: CompanyType.restaurant, role: 'Admin');
const tall = Size(390, 4000);
const fin = '/api/Restaurant/finance';

Finder filled(String t) => find.widgetWithText(FilledButton, t);

Future<void> tapLast(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f.last);
  await tester.pumpAndSettle();
  await tester.tap(f.last);
  await tester.pumpAndSettle();
}

/// The box under [label]; a required label carries a rose " *".
Future<void> enter(WidgetTester tester, String label, String text) async {
  final l = find.textContaining(RegExp('^${RegExp.escape(label)}' r'( \*)?$'), findRichText: true);
  final box = find.descendant(of: find.ancestor(of: l.last, matching: find.byType(Column)).first, matching: find.byType(TextFormField));
  await tester.enterText(box.first, text);
  await tester.pump();
}

void main() {
  test('both rows open native screens; transfer cards and the reconciliation history', () {
    for (final h in ['/restaurant-cash-transfers', '/restaurant-cash-reconciliation']) {
      expect(pageScreens.containsKey(h), isTrue, reason: h);
    }
    final now = DateTime.utc(2026, 10, 20, 12);
    final s = transferStats([
      {'status': 'Posted', 'amount': 100, 'transferDate': '2026-10-20', 'fromAccountName': 'Cash Box', 'toAccountName': 'Bank'},
      {'status': 'Posted', 'amount': 50, 'transferDate': '2026-10-02', 'fromAccountName': 'Cash Box', 'toAccountName': 'MoMo'},
      {'status': 'Posted', 'amount': 30, 'transferDate': '2026-09-30', 'fromAccountName': 'Bank', 'toAccountName': 'MoMo'},
      {'status': 'Reversed', 'amount': 999, 'transferDate': '2026-10-20', 'fromAccountName': 'Bank', 'toAccountName': 'Bank'},
    ], now: now);
    expect((s.today, s.month, s.count, s.moved, s.reversed, s.topFrom, s.topTo), (100, 150, 3, 180, 1, 'Cash Box', 'MoMo'));

    final h = reconciliationHistory([
      {'countId': 1, 'countDate': '2026-10-05T10:00:00', 'accountName': 'Cash Box', 'status': 'Reversed', 'reversalReason': 'Miscounted', 'difference': -5},
      {'countId': 2, 'countDate': '2026-09-01T10:00:00', 'accountName': 'Cash Box', 'status': 'Posted'},
    ], [
      {'shiftId': 8, 'shiftNumber': 'SH-008', 'tillName': 'Till 1', 'closedAt': '2026-10-09T22:00:00', 'variance': 2},
    ], '2026-10-01', '2026-10-20');
    expect([for (final r in h) (r.key, r.kind, r.note)], [('s8', 'Till shift', ''), ('c1', 'Count', 'Reversed: Miscounted')]);
  });

  testWidgets('Cash Transfers: cards, filter, post a transfer, reverse one', (tester) async {
    final api = FakeApi()
      ..gets['$fin/accounts'] = [
        {'cashAccountId': 3, 'name': 'Cash Box', 'currentBalance': 400, 'isActive': true},
        {'cashAccountId': 5, 'name': 'Bank', 'currentBalance': 4000, 'isActive': true},
      ]
      ..gets['$fin/transfers'] = [
        {'transferId': 11, 'transferNumber': 'TR-011', 'fromAccountName': 'Cash Box', 'toAccountName': 'Bank', 'amount': 300,
          'transferDate': '2026-10-15', 'status': 'Posted', 'reference': 'Slip 9', 'createdBy': 'ama'},
      ];
    await open(tester, RestaurantCashTransfersScreen(session: await sessionFor(api), company: rest), size: tall);
    expect(find.text('MOVED TODAY'), findsOneWidget);
    expect(find.text('Cash Box → Bank'), findsOneWidget);
    expect(find.text('Slip 9'), findsOneWidget);
    final q = api.requests.firstWhere((r) => r.url.path == '$fin/transfers').url.queryParameters;
    expect(q['from']!.endsWith('-01'), isTrue);

    await tester.tap(filled('Record transfer'));
    await tester.pumpAndSettle();
    await enter(tester, 'Amount', '250');
    await tester.tap(filled('Post transfer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Pick both accounts'), findsOneWidget);
    await pick(tester, 'Select account', 'Cash Box — GHC 400.00');
    // The "to" list leaves out the "from" account.
    await tester.tap(find.text('Select account').last);
    await tester.pumpAndSettle();
    expect(find.text('Cash Box — GHC 400.00'), findsOneWidget);
    await tester.tap(find.text('Bank — GHC 4,000.00').last);
    await tester.pumpAndSettle();
    await enter(tester, 'Reference', 'Slip 10');
    await tester.tap(filled('Post transfer'));
    await tester.pumpAndSettle();
    final b = api.lastBody('$fin/transfers');
    expect((b['fromAccountId'], b['toAccountId'], b['amount'], b['reference'], b['notes']), (3, 5, 250, 'Slip 10', null));

    await tapLast(tester, find.text('Reverse'));
    expect(find.textContaining('The opposite pair will be posted dated today.'), findsOneWidget);
    await reasonPick(tester, 'Wrong account');
    await tester.tap(filled('Reverse'));
    await tester.pumpAndSettle();
    expect(api.lastBody('$fin/transfers/11/reverse'), {'reason': 'Wrong account'});
  });

  testWidgets('Reconciliation: save a draft, the lock, post, edit, discard and reverse', (tester) async {
    final today = DateTime.now();
    final d = '${today.year}-${today.month.toString().padLeft(2, '0')}-01T09:00:00';
    final api = FakeApi()
      ..gets['$fin/accounts'] = [
        {'cashAccountId': 3, 'name': 'Cash Box', 'accountType': 'CashBox', 'currentBalance': 400, 'isActive': true},
        {'cashAccountId': 5, 'name': 'Bank', 'accountType': 'Bank', 'currentBalance': 4000, 'isActive': true},
        {'cashAccountId': 7, 'name': 'Till 1', 'accountType': 'Till', 'currentBalance': 50, 'isActive': true},
      ]
      ..gets['$fin/counts'] = [
        {'countId': 21, 'cashAccountId': 5, 'accountName': 'Bank', 'countDate': d, 'systemBalance': 4000, 'countedBalance': 3990,
          'difference': -10, 'status': 'Draft'},
        {'countId': 22, 'cashAccountId': 3, 'accountName': 'Cash Box', 'countDate': d, 'systemBalance': 400, 'countedBalance': 400,
          'difference': 0, 'status': 'Posted'},
      ]
      ..gets['$fin/shifts'] = []
      ..writeAnswers['$fin/counts/21/post'] = {'countId': 21, 'adjustmentTransactionId': 77};
    await open(tester, RestaurantCashReconciliationScreen(session: await sessionFor(api), company: rest), size: tall);
    expect(find.text('1 of 1'), findsOneWidget, reason: 'the posted count balanced; the draft is not counted');
    expect(api.requests.firstWhere((r) => r.url.path == '$fin/shifts').url.queryParameters['status'], 'Closed');

    // Tills are not offered.
    await tester.tap(find.text('Choose an account'));
    await tester.pumpAndSettle();
    expect(find.text('Till 1 (Till (cash drawer))'), findsNothing);
    await tester.tap(find.text('Cash Box (Cash box / safe)').last);
    await tester.pumpAndSettle();
    await enter(tester, 'Counted / statement balance', '395');
    expect(find.textContaining('Short by GHC 5.00'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Why is it short?'), findsOneWidget);
    await tester.tap(filled('Save draft'));
    await tester.pumpAndSettle();
    final s = api.lastBody('$fin/counts/draft');
    expect((s['cashAccountId'], s['counted'], s['notes']), (3, 395, null));

    // The Bank has an open draft: the form locks until it is edited.
    await pick(tester, 'Cash Box (Cash box / safe)', 'Bank (Bank account)');
    expect(find.textContaining('Count #21 is saved but not posted'), findsOneWidget);
    expect(tester.widget<FilledButton>(filled('Save draft')).onPressed, isNull);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Edit').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Editing draft count #21'), findsOneWidget);
    await enter(tester, 'Counted / statement balance', '3995');
    await tester.tap(filled('Update draft'));
    await tester.pumpAndSettle();
    final u = api.lastBody('$fin/counts/21/draft', 'PUT');
    expect(u['counted'], 3995);

    // Post it (the history's Post), then discard, then reverse the posted count.
    await tapLast(tester, find.widgetWithText(OutlinedButton, 'Post'));
    expect(api.writes.any((w) => w.url.path == '$fin/counts/21/post'), isTrue);
    expect(find.textContaining('Cash count posted'), findsWidgets);

    await tapLast(tester, find.widgetWithText(OutlinedButton, 'Discard'));
    expect(find.text('Discard count #21?'), findsOneWidget);
    await tester.tap(filled('Discard draft'));
    await tester.pumpAndSettle();
    expect(api.writes.any((w) => w.url.path == '$fin/counts/21/draft' && w.method == 'DELETE'), isTrue);

    await tapLast(tester, find.widgetWithText(OutlinedButton, 'Reverse'));
    await reasonPick(tester, 'Duplicate count');
    await tester.tap(filled('Reverse'));
    await tester.pumpAndSettle();
    expect(api.lastBody('$fin/counts/22/reverse'), {'reason': 'Duplicate count'});
  });
}
