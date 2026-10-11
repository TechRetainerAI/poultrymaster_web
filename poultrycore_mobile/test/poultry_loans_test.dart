// Poultry → Money → Loans (Financing): the rules, then the page at phone width —
// figures, status buttons, repayment history, Record loan, Repay, Reverse.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/money/loan_repayment_dialog.dart';
import 'package:poultrycore_mobile/pages/poultry/money/loans_screen.dart';

import 'support/harness.dart';

final loans = <Map>[
  {
    'poultryLoanId': 1, 'loanNumber': 'LN-2026-0001', 'lenderName': 'GCB Bank', 'lenderType': 'Bank',
    'startDate': '2026-09-01T00:00:00', 'createdAt': '2026-09-01T08:30:00Z', 'originalPrincipal': 10000,
    'amountReceived': 9800, 'totalPrincipalRepaid': 2000, 'outstandingPrincipal': 8000, 'totalInterestPaid': 300,
    'totalFeesPaid': 50, 'interestRate': 24, 'interestType': 'ReducingBalance', 'nextPaymentDate': '2026-11-01T00:00:00',
    'paymentCount': 1, 'status': 'Active', 'isOverdue': false, 'poultryCashAccountId': 5, 'source': 'Loan', 'sourceId': 1,
  },
  {
    'poultryLoanId': 0, 'loanNumber': null, 'lenderName': null, 'startDate': '2026-08-10T00:00:00',
    'originalPrincipal': 500, 'amountReceived': 500, 'outstandingPrincipal': 500, 'paymentCount': 0,
    'status': 'Active', 'source': 'CashAdjustment', 'sourceId': 9,
  },
  {
    'poultryLoanId': 3, 'loanNumber': 'LN-2026-0003', 'lenderName': '', 'lenderType': 'Individual',
    'startDate': '2026-07-01T00:00:00', 'originalPrincipal': 100, 'outstandingPrincipal': 0, 'paymentCount': 0,
    'status': 'PaidOff', 'source': 'Loan', 'sourceId': 3,
  },
];

final payments = <Map>[
  {
    'poultryLoanPaymentId': 11, 'poultryLoanId': 1, 'paymentNumber': 'LP-0001', 'paymentDate': '2026-09-15T00:00:00',
    'principalAmount': 2000, 'interestAmount': 300, 'feeAmount': 50, 'totalAmount': 2350, 'accountName': 'Main Cash',
    'status': 'Posted',
  },
  {
    'poultryLoanPaymentId': 12, 'poultryLoanId': 1, 'paymentNumber': 'LP-0002', 'paymentDate': '2026-10-01T00:00:00',
    'principalAmount': 100, 'interestAmount': 0, 'feeAmount': 0, 'totalAmount': 100, 'status': 'Reversed',
  },
];

FakeApi api() => FakeApi()
  ..gets['/api/CompanyTime/context'] = {
    'businessDate': '2026-10-06', 'companyLocalDateTime': '2026-10-06T10:00:00', 'utcNow': '2026-10-06T10:00:00Z',
  }
  ..gets['/api/Poultry/cash-accounts'] = [
    {'poultryCashAccountId': 5, 'accountName': 'Main Cash', 'currentBalance': 3000, 'isActive': true, 'allowNegativeBalance': false},
    {'poultryCashAccountId': 6, 'accountName': 'MoMo', 'currentBalance': 100, 'isActive': true, 'allowNegativeBalance': false},
  ]
  ..gets['/api/Poultry/loans'] = loans
  ..gets['/api/Poultry/loan-payments'] = payments
  ..gets['/api/Poultry/loans/summary'] = {
    'outstandingPrincipal': 8500, 'activeLoans': 2, 'totalBorrowed': 10600, 'totalReceived': 10400,
    'totalPrincipalRepaid': 2000, 'totalInterestPaid': 300, 'totalFeesPaid': 50, 'nextPaymentDate': '2026-11-01T00:00:00',
    'overdueLoans': 1,
  };

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

Future<void> choose(WidgetTester tester, String hint, String option) async {
  final sel = find.ancestor(of: inDialog(find.text(hint)), matching: find.byType(AppSelect<String>));
  await tapIn(tester, sel);
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

/// [enter], but only inside the open dialog: the page behind has the same labels.
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
  group('loan rules', () {
    test('only a real, open loan with debt left can be repaid', () {
      expect(isRepayableLoan(loans[0]), isTrue);
      expect(isRepayableLoan(loans[1]), isFalse, reason: 'a Cash Flow row has no loan record');
      expect(isRepayableLoan(loans[2]), isFalse, reason: 'paid off');
      expect(isRepayableLoan({...loans[0], 'status': 'Overdue'}), isTrue);
      expect(isRepayableLoan({...loans[0], 'source': null}), isTrue, reason: 'an older read has no source');
    });

    test('the lender cell names the gap; keys; repayments newest first', () {
      expect(lenderCell(loans[0]), 'GCB Bank');
      expect(lenderCell(loans[1]), 'Loan received');
      expect(lenderCell(loans[2]), 'Lender not recorded');
      expect(loanRowKey(loans[1]), 'CashAdjustment:9');
      expect([for (final p in paymentsByLoan(payments)[1]!) p['paymentNumber']], ['LP-0002', 'LP-0001']);
    });
  });

  test('on the sidebar route', () => expect(pageScreens.containsKey('/poultry-loans'), isTrue));

  testWidgets('figures, cards, repayment history, status buttons, Cash Flow rows, table', (tester) async {
    await open(tester, LoansScreen(session: await sessionFor(api()), company: company), size: phone);

    expect(find.text('GHC 8,500.00'), findsOneWidget);
    expect(find.text('2 active loan(s)'), findsOneWidget);
    expect(find.text('GHC 10,400.00 received'), findsOneWidget);
    expect(find.text('GHC 350.00'), findsOneWidget, reason: 'interest + fees');
    expect(find.text('1 Nov 2026'), findsOneWidget);
    expect(find.text('1 overdue'), findsOneWidget);

    await see(tester, find.text('LN-2026-0001 · GCB Bank'));
    expect(find.text('1 Sep 2026, 08:30 · Bank'), findsOneWidget);
    await see(tester, find.text('24% ReducingBalance'));
    await see(tester, find.text('LP-0001 · Main Cash'));
    expect(find.text('GHC 2,350.00'), findsOneWidget);
    expect(find.text('Reverse'), findsOneWidget, reason: 'only the posted repayment');
    await see(tester, find.text('#0 · Loan received'));
    expect(find.text('Recorded on Cash Flow — edit the amount there.'), findsOneWidget);
    await see(tester, find.text('LN-2026-0003 · Lender not recorded'));
    expect(find.text('Repay'), findsOneWidget, reason: 'only the open real loan');

    await tap(tester, find.widgetWithText(OutlinedButton, 'PaidOff'));
    expect(find.text('LN-2026-0001 · GCB Bank'), findsNothing);
    expect(find.text('LN-2026-0003 · Lender not recorded'), findsOneWidget);
    await tap(tester, find.widgetWithText(OutlinedButton, 'Draft'));
    expect(find.text('No loans match this filter.'), findsOneWidget);
    await tap(tester, find.widgetWithText(OutlinedButton, 'All'));

    await tap(tester, find.text('View table format'));
    await see(tester, find.text('2 repayments'));
    await tester.tap(find.text('2 repayments'));
    await tester.pumpAndSettle();
    await see(tester, find.text('Total paid'));
    expect(find.text('Cash Flow'), findsOneWidget);
  });

  testWidgets('Record a Loan: checks in the web order, the withheld-fee note, the body', (tester) async {
    final a = api();
    await open(tester, LoansScreen(session: await sessionFor(a), company: company), size: phone);
    await tap(tester, find.text('Record loan'));
    final save = inDialog(find.text('Record Loan'));

    await tapIn(tester, save);
    expect(find.textContaining('Who lent the money?'), findsWidgets);
    clearToasts(tester);
    await enterIn(tester, 'Lender *', 'Fidelity');
    await tapIn(tester, save);
    expect(find.textContaining('Enter the loan amount'), findsOneWidget);
    clearToasts(tester);
    await enterIn(tester, 'Amount borrowed *', '5000');
    await enterIn(tester, 'Amount received', '6000');
    await tapIn(tester, save);
    expect(find.textContaining('Received cannot exceed the principal'), findsOneWidget);
    clearToasts(tester);
    await enterIn(tester, 'Amount received', '4800');
    await tester.pumpAndSettle();
    expect(find.textContaining('GHC 200.00 less than the principal'), findsOneWidget);
    await tapIn(tester, save);
    expect(find.textContaining('Which account received it?'), findsOneWidget);
    clearToasts(tester);

    await choose(tester, 'Where did the money land?', 'Main Cash — GHC 3,000.00');
    await choose(tester, 'Bank', 'FinancialInstitution');
    await choose(tester, 'ReducingBalance', 'Flat');
    await choose(tester, 'Monthly', 'Quarterly');
    await enterIn(tester, 'Interest rate (%)', '18');
    await enterIn(tester, 'Term (months)', '12');
    await tapIn(tester, save);

    final b = a.lastBody('/api/Poultry/loans');
    expect(b['lenderName'], 'Fidelity');
    expect(b['lenderType'], 'FinancialInstitution');
    expect(b['originalPrincipal'], 5000);
    expect(b['amountReceived'], 4800);
    expect(b['poultryCashAccountId'], 5);
    expect(b['interestRate'], 18);
    expect(b['interestType'], 'Flat');
    expect(b['termMonths'], 12);
    expect(b['paymentFrequency'], 'Quarterly');
    expect(b['nextPaymentDate'], isNull);
    expect(b['accountNumber'], isNull);
    expect(b['createdBy'], 'user-1');
    expect(find.textContaining('GHC 4,800.00 in.'), findsOneWidget);
  });

  testWidgets('Repay: the split is the input, the total and the debt after follow', (tester) async {
    final a = api();
    await open(tester, LoansScreen(session: await sessionFor(a), company: company), size: phone);
    await tap(tester, find.widgetWithText(OutlinedButton, 'Repay'));
    expect(find.text('Record a Repayment'), findsOneWidget);
    expect(find.text('Still owed GHC 8,000.00'), findsOneWidget);
    expect(find.text('Main Cash — GHC 3,000.00'), findsOneWidget, reason: 'paid from defaults to where the loan landed');

    await enterIn(tester, 'Principal', '9000');
    await tester.pumpAndSettle();
    expect(find.text('That is more principal than is still owed.'), findsOneWidget);
    await enterIn(tester, 'Principal', '1000');
    await enterIn(tester, 'Interest', '200');
    await enterIn(tester, 'Fees', '20');
    await tester.pumpAndSettle();
    expect(find.text('GHC 1,220.00'), findsOneWidget);
    expect(find.text('GHC 220.00'), findsOneWidget);
    expect(find.textContaining('GHC 8,000.00 → GHC 7,000.00', findRichText: true), findsOneWidget);

    await choose(tester, 'Main Cash — GHC 3,000.00', 'MoMo — GHC 100.00');
    expect(find.text('The account does not hold this much and cannot go negative.'), findsOneWidget);
    expect(tester.widget<FilledButton>(inDialog(find.widgetWithText(FilledButton, 'Record GHC 1,220.00'))).onPressed, isNull);
    await choose(tester, 'MoMo — GHC 100.00', 'Main Cash — GHC 3,000.00');
    await choose(tester, 'BankTransfer', 'MoMo');
    await enterIn(tester, 'Reference', 'TX-9');
    await tapIn(tester, inDialog(find.text('Record GHC 1,220.00')));

    final b = a.lastBody('/api/Poultry/loans/1/record-repayment');
    expect(b['poultryLoanId'], 1);
    expect(b['poultryCashAccountId'], 5);
    expect(b['principalAmount'], 1000);
    expect(b['interestAmount'], 200);
    expect(b['feeAmount'], 20);
    expect(b['otherAmount'], 0);
    expect(b['paymentMethod'], 'MoMo');
    expect(b['referenceNumber'], 'TX-9');
    expect(b['notes'], isNull);
    expect(find.textContaining('GHC 1,220.00 left the account; only GHC 220.00 of it is a cost.'), findsOneWidget);
  });

  testWidgets('Reverse a repayment needs a reason', (tester) async {
    final a = api();
    await open(tester, LoansScreen(session: await sessionFor(a), company: company), size: phone);
    await tap(tester, find.widgetWithText(OutlinedButton, 'Reverse'));
    expect(find.text('Reverse Repayment'), findsOneWidget);
    expect(find.text('GHC 2,350.00 on 15 Sep 2026'), findsOneWidget);
    expect(find.text('GHC 2,000.00 principal · GHC 300.00 interest · GHC 50.00 fees'), findsOneWidget);
    final go = inDialog(find.widgetWithText(FilledButton, 'Reverse'));
    await tapIn(tester, go);
    expect(find.textContaining('Say why'), findsOneWidget);
    expect(a.writes, isEmpty);
    clearToasts(tester);
    await enterIn(tester, 'Reason *', 'Bank bounced it');
    await tapIn(tester, go);
    final w = a.writes.single;
    expect(w.url.path, '/api/Poultry/loan-payments/11/reverse');
    expect(w.url.queryParameters, {'farmId': 'farm-1', 'reversedBy': 'user-1'});
    expect(find.textContaining('Repayment reversed'), findsOneWidget);
  });
}
