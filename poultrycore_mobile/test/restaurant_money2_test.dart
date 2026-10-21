// Restaurant → Money (2026-10-20, second set): Owner Money, Loans (Financing)
// and Cash Account as the web pages, against a fake API at phone width.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_cash_accounts_screen.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_loans_screen.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_owner_money_screen.dart';

import 'support/harness.dart' hide enter;

final rest = Company(farmId: 'farm-1', name: 'Rose Bistro', type: CompanyType.restaurant, role: 'Admin');
const tall = Size(390, 4000);
const fin = '/api/Restaurant/finance';

Future<void> tapLast(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f.last);
  await tester.pumpAndSettle();
  await tester.tap(f.last);
  await tester.pumpAndSettle();
}

Finder filled(String t) => find.widgetWithText(FilledButton, t);

/// The box under [label]; a required label carries a rose " *".
Future<void> enter(WidgetTester tester, String label, String text) async {
  final l = find.textContaining(RegExp('^${RegExp.escape(label)}' r'( \*)?$'), findRichText: true);
  final box = find.descendant(of: find.ancestor(of: l.last, matching: find.byType(Column)).first, matching: find.byType(TextFormField));
  await tester.enterText(box.first, text);
  await tester.pump();
}

void main() {
  test('the three Money rows open native screens; the loan cards', () {
    for (final h in ['/restaurant-owner-money', '/restaurant-loans', '/restaurant-cash-accounts']) {
      expect(pageScreens.containsKey(h), isTrue, reason: h);
    }
    final s = restaurantLoanStats([
      {'status': 'Active', 'principal': 1000, 'amountReceived': 950, 'outstandingPrincipal': 800, 'principalRepaid': 200,
        'interestPaid': 20, 'feesPaid': 5, 'dueDate': '2026-12-01', 'isOverdue': false},
      {'status': 'Active', 'principal': 300, 'amountReceived': 300, 'outstandingPrincipal': 300, 'dueDate': '2026-11-01', 'isOverdue': true},
      {'status': 'Cancelled', 'principal': 999, 'amountReceived': 999, 'outstandingPrincipal': 999},
    ]);
    expect((s.outstanding, s.activeCount, s.costsPaid, s.overdue, s.borrowed, s.received, s.repaid, s.nextDue),
        (1100, 2, 25, 1, 1300, 1250, 200, '2026-11-01'));
  });

  testWidgets('Owner Money: stats from posted entries, record a drawing, reverse a contribution', (tester) async {
    final api = FakeApi()
      ..gets['$fin/owner-money'] = [
        {'ownerMoneyId': 1, 'entryNumber': 'OM-001', 'entryType': 'Contribution', 'status': 'Posted', 'amount': 500,
          'entryDate': '2026-10-01T00:00:00', 'accountName': 'Cash Box', 'ownerName': 'Ama'},
        {'ownerMoneyId': 2, 'entryType': 'Draw', 'status': 'Reversed', 'amount': 100, 'entryDate': '2026-10-02',
          'accountName': 'Cash Box', 'reversalReason': 'Wrong amount'},
      ]
      ..gets['$fin/accounts'] = [
        {'cashAccountId': 3, 'name': 'Cash Box', 'currentBalance': 400, 'isActive': true},
        {'cashAccountId': 4, 'name': 'Old Safe', 'currentBalance': 0, 'isActive': false},
      ];
    await open(tester, RestaurantOwnerMoneyScreen(session: await sessionFor(api), company: rest), size: tall);
    final q = api.requests.firstWhere((r) => r.url.path == '$fin/owner-money').url.queryParameters;
    expect(q['from'], '${DateTime.now().year}-01-01');
    expect(find.text('CONTRIBUTIONS IN RANGE'), findsOneWidget);
    expect(find.text('1 record(s)'), findsOneWidget, reason: 'one posted contribution');
    expect(find.text('0 record(s)'), findsOneWidget, reason: 'the reversed draw is not counted');
    expect(find.text('OM-001 · Contribution'), findsOneWidget);
    expect(find.text('#2 · Draw'), findsOneWidget);
    expect(find.text('Reverse'), findsOneWidget, reason: 'only a posted entry can be reversed');

    await tester.tap(find.text('Record draw'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Cash Box — '), findsOneWidget, reason: 'the only active account is picked');
    await enter(tester, 'Amount', '120');
    await tester.tap(filled('Record drawing'));
    await tester.pumpAndSettle();
    final b = api.lastBody('$fin/owner-money');
    expect((b['entryType'], b['cashAccountId'], b['amount'], b['ownerName'], b['notes']), ('Draw', 3, 120, null, null));
    expect(b['entryDate'], isNotNull);

    await tapLast(tester, find.text('Reverse'));
    expect(find.textContaining('comes back out of Cash Box'), findsOneWidget);
    await reasonPick(tester, 'Duplicate entry');
    await tester.tap(filled('Reverse'));
    await tester.pumpAndSettle();
    expect(api.lastBody('$fin/owner-money/1/reverse'), {'reason': 'Duplicate entry'});
  });

  testWidgets('Loans: record, repay, payments with a reversal, and cancel', (tester) async {
    final api = FakeApi()
      ..gets['$fin/loans'] = [
        {'loanId': 7, 'loanNumber': 'LN-007', 'lenderName': 'GCB Bank', 'principal': 1000, 'amountReceived': 1000,
          'outstandingPrincipal': 1000, 'principalRepaid': 0, 'interestPaid': 0, 'feesPaid': 0, 'status': 'Active',
          'loanDate': '2026-09-01', 'dueDate': '2026-12-01', 'receivedAccountName': 'Bank', 'interestRate': 12.5},
      ]
      ..gets['$fin/accounts'] = [
        {'cashAccountId': 3, 'name': 'Cash Box', 'currentBalance': 400, 'isActive': true},
        {'cashAccountId': 5, 'name': 'Bank', 'currentBalance': 4000, 'isActive': true},
      ]
      ..gets['$fin/loans/7/payments'] = [
        {'loanPaymentId': 9, 'loanId': 7, 'paymentDate': '2026-10-01', 'accountName': 'Bank', 'principalAmount': 200,
          'interestAmount': 10, 'feeAmount': 0, 'totalAmount': 210, 'status': 'Posted'},
      ];
    await open(tester, RestaurantLoansScreen(session: await sessionFor(api), company: rest), size: tall);
    expect(find.text('STILL OWED'), findsWidgets);
    expect(find.text('12.5%'), findsOneWidget);

    // Record loan: amount received follows the loan amount until typed into.
    await tester.tap(filled('Record loan').first);
    await tester.pumpAndSettle();
    await enter(tester, 'Lender', 'Uncle Kofi');
    await enter(tester, 'Loan amount', '500');
    expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('500')), findsNWidgets(2));
    await enter(tester, 'Amount actually received', '450');
    expect(find.textContaining('The lender kept'), findsOneWidget);
    await tester.tap(filled('Record loan').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Pick an account'), findsOneWidget, reason: 'money received needs an account');
    await pick(tester, 'Select account', 'Bank — GHC 4,000.00');
    await tester.tap(filled('Record loan').last);
    await tester.pumpAndSettle();
    final l = api.lastBody('$fin/loans');
    expect((l['lenderName'], l['principal'], l['amountReceived'], l['receivedAccountId'], l['interestRate'], l['dueDate']),
        ('Uncle Kofi', 500, 450, 5, null, null));

    // Repay: too much principal blocks the button.
    await tapLast(tester, find.text('Repay'));
    await pick(tester, 'Select account', 'Bank — GHC 4,000.00');
    await enter(tester, 'Principal', '1200');
    expect(find.text('Principal is more than what is still owed.'), findsOneWidget);
    expect(tester.widget<FilledButton>(filled('Record repayment')).onPressed, isNull);
    await enter(tester, 'Principal', '200');
    await enter(tester, 'Interest', '10');
    await tester.tap(filled('Record repayment'));
    await tester.pumpAndSettle();
    final r = api.lastBody('$fin/loans/7/repay');
    expect((r['cashAccountId'], r['principal'], r['interest'], r['fees']), (5, 200, 10, 0));

    // Payments, and a repayment reversed.
    await tapLast(tester, find.text('Payments'));
    expect(find.text('Payments — GCB Bank'), findsOneWidget);
    await tapLast(tester, find.text('Reverse'));
    expect(find.textContaining('is owed again'), findsOneWidget);
    await reasonPick(tester, 'Wrong amount');
    await tester.tap(filled('Reverse'));
    await tester.pumpAndSettle();
    expect(api.lastBody('$fin/loans/payments/9/reverse'), {'reason': 'Wrong amount'});
    await tapLast(tester, find.text('Close'));

    // Cancel: offered because nothing has been repaid.
    await tapLast(tester, find.text('Cancel'));
    expect(find.text('Cancel loan from GCB Bank'), findsOneWidget);
    await reasonPick(tester, 'Posted by mistake');
    await tester.tap(filled('Cancel loan'));
    await tester.pumpAndSettle();
    expect(api.lastBody('$fin/loans/7/cancel'), {'reason': 'Posted by mistake'});
  });

  testWidgets('Cash Account: tiles, new and edit account, ledger, count, and a count reversed', (tester) async {
    final api = FakeApi()
      ..gets['$fin/accounts'] = [
        {'cashAccountId': 3, 'name': 'Cash Box', 'accountType': 'CashBox', 'defaultFor': 'Cash', 'currentBalance': 200,
          'ledgerBalance': 150, 'isActive': true, 'allowNegative': false},
        {'cashAccountId': 4, 'name': 'Till 1', 'accountType': 'Till', 'currentBalance': -10, 'ledgerBalance': -10,
          'isActive': true, 'openShiftId': 5, 'openShiftNumber': 'SH-005'},
      ]
      ..gets['$fin/counts'] = [
        {'countId': 2, 'accountName': 'Cash Box', 'countDate': '2026-10-10T09:00:00', 'systemBalance': 205,
          'countedBalance': 200, 'difference': -5, 'status': 'Posted'},
      ]
      ..gets['$fin/accounts/3/ledger'] = [
        {'cashTxnId': 1, 'txnDate': '2026-10-19', 'sourceType': 'OrderPayment', 'amount': 50, 'runningBalance': 200},
      ];
    await open(tester, RestaurantCashAccountsScreen(session: await sessionFor(api), company: rest), size: tall);
    expect(find.text('TOTAL CASH AT HAND'), findsOneWidget);
    expect(find.text('Cash box / safe · default for Cash payments'), findsOneWidget);
    expect(find.text('Ledger says GHC 150.00'), findsOneWidget, reason: 'out of sync');
    final counts = tester.widgetList<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Count')).toList();
    expect([for (final b in counts) b.onPressed != null], [true, false], reason: 'a till with an open shift cannot be counted');

    await tester.tap(filled('New account'));
    await tester.pumpAndSettle();
    await enter(tester, 'Name', 'Safe');
    await pick(tester, 'Cash box / safe', 'Bank account');
    await enter(tester, 'Opening balance', '100');
    await tester.tap(filled('Create account'));
    await tester.pumpAndSettle();
    final n = api.lastBody('$fin/accounts');
    expect((n['name'], n['accountType'], n['openingBalance'], n['defaultFor'], n['allowNegative'], n['farmId']),
        ('Safe', 'Bank', 100, null, false, 'farm-1'));

    await tapLast(tester, find.widgetWithText(OutlinedButton, 'Edit').first);
    expect(find.text('Active'), findsOneWidget);
    await tester.tap(filled('Save changes'));
    await tester.pumpAndSettle();
    final u = api.lastBody('$fin/accounts/3', 'PUT');
    expect((u['name'], u['accountType'], u['isActive'], u['defaultFor']), ('Cash Box', 'CashBox', true, 'Cash'));

    await tapLast(tester, find.text('View details').first);
    expect(find.text('Ledger — Cash Box'), findsOneWidget);
    expect(find.text('Order payment'), findsOneWidget);
    await tapLast(tester, find.text('Close'));

    await tester.tap(find.widgetWithText(OutlinedButton, 'Count').first);
    await tester.pumpAndSettle();
    await enter(tester, 'Counted / confirmed balance', '190');
    expect(find.text('GHC 10.00 short'), findsOneWidget);
    await tester.tap(filled('Post count'));
    await tester.pumpAndSettle();
    final c = api.lastBody('$fin/counts');
    expect((c['cashAccountId'], c['counted'], c['notes']), (3, 190, null));

    await tapLast(tester, find.text('Count history'));
    expect(find.textContaining(RegExp(r'5.00 short$')), findsOneWidget);
    await tapLast(tester, find.text('Reverse'));
    await reasonPick(tester, 'Miscounted');
    await tester.tap(filled('Reverse'));
    await tester.pumpAndSettle();
    expect(api.lastBody('$fin/counts/2/reverse'), {'reason': 'Miscounted'});
  });
}
