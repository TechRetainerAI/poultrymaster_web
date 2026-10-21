// Water → Sales, Expenses & Money → Money: Cash Flow, Profit & Loss, Owner
// Money and Loans at phone width against a fake API. Three are the Poultry
// screens on the Water rail; each test checks the Water endpoints, ids and
// the points where the web's Water page differs.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/money/cash_flow_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/money/loans_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/money/owner_money_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/reports/report_format.dart' show FarmMoney;
import 'package:poultrycore_mobile/pages/water/reports/water_money_reports.dart';

import 'support/harness.dart';

final water = Company(farmId: 'farm-1', name: 'Win Water', type: CompanyType.water);

const clock = {'businessDate': '2026-10-06', 'companyLocalDateTime': '2026-10-06T10:00:00', 'utcNow': '2026-10-06T10:00:00Z'};

final accounts = [
  {'waterCashAccountId': 5, 'accountName': 'Main Cash', 'currentBalance': 3000, 'isActive': true, 'allowNegativeBalance': false},
  {'waterCashAccountId': 6, 'accountName': 'Old Till', 'currentBalance': 0, 'isActive': false},
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
  await tapIn(tester, find.ancestor(of: inDialog(find.text(hint)), matching: find.byType(AppSelect<String>)));
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Future<void> enterIn(WidgetTester tester, String label, String text) async {
  final field = find.descendant(
    of: find.ancestor(of: inDialog(find.text(label)), matching: find.byType(Column)).first,
    matching: find.byType(TextFormField),
  );
  await tester.ensureVisible(field.first);
  await tester.pumpAndSettle();
  await tester.enterText(field.first, text);
  await tester.pump();
}

void clearToasts(WidgetTester tester) => tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();

void main() {
  setUp(FarmMoney.clearCache);

  test('the four Money pages are native on the sidebar routes', () {
    for (final r in ['/water-cash-flow', '/water-profit-loss', '/water-owner-money', '/water-loans']) {
      expect(pageScreens.containsKey(r), isTrue, reason: r);
    }
  });

  // ------------------------------------------------------------ owner money

  group('Owner Money', () {
    FakeApi api() => FakeApi()
      ..gets['/api/CompanyTime/context'] = clock
      ..gets['/api/Water/cash-accounts'] = accounts
      ..gets['/api/Water/owner-money'] = [
        {
          'waterOwnerMoneyId': 4, 'transactionNumber': null, 'transactionDate': '2026-10-01T00:00:00', 'transactionType': 'Contribution',
          'amount': 1000, 'waterCashAccountId': 5, 'accountName': 'Main Cash', 'paymentMethod': 'MoMo', 'ownerName': 'Ama', 'status': 'Posted',
        },
        {
          'waterOwnerMoneyId': 5, 'transactionNumber': 'OWD-1', 'transactionDate': '2026-10-02T00:00:00', 'transactionType': 'Draw',
          'amount': 80, 'accountName': 'Main Cash', 'status': 'Reversed', 'reversalReason': 'Typed twice',
        },
      ]
      ..gets['/api/Water/owner-money/summary'] = {'totalContributions': 1000, 'totalDraws': 0, 'netFunding': 1000, 'contributionCount': 1, 'drawCount': 0};

    testWidgets('Water rows, record a draw, reverse', (tester) async {
      final a = api();
      await open(tester, OwnerMoneyScreen(session: await sessionFor(a), company: water, rail: waterMoneyRail), size: phone);
      expect(a.requests.any((r) => r.url.path.startsWith('/api/Poultry')), isFalse);
      await see(tester, find.text('#4'));
      expect(find.text('#4'), findsOneWidget, reason: 'numbered by waterOwnerMoneyId');
      expect(find.text('Recorded on the Cash page — edit it there.'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Reverse'), findsOneWidget, reason: 'every posted Water row');

      await tap(tester, find.text('Record draw'));
      await tester.ensureVisible(inDialog(find.text('Which account does it leave?')));
      await tester.pumpAndSettle();
      await tester.tap(find.ancestor(of: inDialog(find.text('Which account does it leave?')), matching: find.byType(AppSelect<String>)));
      await tester.pumpAndSettle();
      expect(find.text('Old Till — GHC 0.00'), findsNothing);
      await tester.tap(find.text('Main Cash — GHC 3,000.00').last);
      await tester.pumpAndSettle();
      await enter(tester, 'Amount *', '120');
      await tester.pumpAndSettle();
      await tapIn(tester, inDialog(find.text('Record Draw')));
      final b = a.lastBody('/api/Water/owner-money');
      expect((b['transactionType'], b['amount'], b['waterCashAccountId'], b['farmId']), ('Draw', 120, 5, 'farm-1'));
      expect(b.containsKey('poultryCashAccountId'), isFalse);
      clearToasts(tester);

      await tap(tester, find.widgetWithText(OutlinedButton, 'Reverse'));
      expect(find.text('#4 · Contribution'), findsOneWidget);
      await reasonOther(tester, 'Was a loan');
      await tapIn(tester, inDialog(find.widgetWithText(FilledButton, 'Reverse')));
      expect(a.writes.last.url.path, '/api/Water/owner-money/4/reverse');
      expect(a.lastBody('/api/Water/owner-money/4/reverse'), {'reason': 'Was a loan'});
    });
  });

  // ------------------------------------------------------------ loans

  group('Loans', () {
    FakeApi api() => FakeApi()
      ..gets['/api/CompanyTime/context'] = clock
      ..gets['/api/Water/cash-accounts'] = accounts
      ..gets['/api/Water/loans'] = [
        {
          'waterLoanId': 1, 'loanNumber': 'WLN-1', 'lenderName': 'GCB Bank', 'lenderType': 'Bank', 'startDate': '2026-09-01T00:00:00',
          'originalPrincipal': 10000, 'amountReceived': 9800, 'totalPrincipalRepaid': 2000, 'outstandingPrincipal': 8000,
          'totalInterestPaid': 300, 'totalFeesPaid': 50, 'paymentCount': 1, 'status': 'Active', 'isOverdue': false,
          'waterCashAccountId': 5, 'source': 'Loan', 'sourceId': 1,
        },
        {
          'waterLoanId': 0, 'startDate': '2026-08-10T00:00:00', 'originalPrincipal': 500, 'outstandingPrincipal': 500,
          'paymentCount': 0, 'status': 'Active', 'source': 'CashAdjustment', 'sourceId': 9,
        },
      ]
      ..gets['/api/Water/loan-payments'] = [
        {
          'waterLoanPaymentId': 11, 'waterLoanId': 1, 'loanNumber': 'WLN-1', 'lenderName': 'GCB Bank', 'paymentNumber': 'WLP-1',
          'paymentDate': '2026-09-15T00:00:00', 'principalAmount': 2000, 'interestAmount': 300, 'feeAmount': 50, 'totalAmount': 2350,
          'accountName': 'Main Cash', 'status': 'Posted',
        },
      ]
      ..gets['/api/Water/loans/summary'] = {'outstandingPrincipal': 8500, 'activeLoans': 2, 'totalBorrowed': 10500};

    testWidgets('Water wording, one repayment history, record, repay, reverse', (tester) async {
      final a = api();
      await open(tester, LoansScreen(session: await sessionFor(a), company: water, rail: waterMoneyRail), size: phone);
      expect(a.requests.any((r) => r.url.path.startsWith('/api/Poultry')), isFalse);
      expect(find.text('Loans'), findsWidgets);
      expect(find.text('Loans (Financing)'), findsNothing);
      expect(find.textContaining('Money the company has borrowed.', findRichText: true), findsOneWidget);
      await see(tester, find.text('Repayment history'));
      expect(find.text('REPAYMENT HISTORY'), findsNothing, reason: 'not inside each loan, as on Poultry');
      await see(tester, find.text('WLP-1'));
      expect(find.text('WLP-1'), findsOneWidget);
      await see(tester, find.text('Recorded on Cash Flow — edit the amount there.'));
      expect(find.widgetWithText(OutlinedButton, 'Repay'), findsOneWidget, reason: 'only the real loan');

      // Record a loan.
      await tap(tester, find.text('Record loan'));
      expect(find.text('The money arriving is cash in, but it is not revenue — the company borrowed it and still owes it.'), findsOneWidget);
      await enterIn(tester, 'Lender *', 'Fidelity');
      await enterIn(tester, 'Amount borrowed *', '5000');
      await enterIn(tester, 'Amount received', '5000');
      await choose(tester, 'Where did the money land?', 'Main Cash — GHC 3,000.00');
      await choose(tester, 'Bank', 'Owner');
      await tapIn(tester, inDialog(find.text('Record Loan')));
      final b = a.lastBody('/api/Water/loans');
      expect((b['lenderName'], b['lenderType'], b['waterCashAccountId'], b['amountReceived']), ('Fidelity', 'Owner', 5, 5000));
      expect(find.textContaining('the company borrowed it.'), findsOneWidget);
      clearToasts(tester);

      // Repay.
      await tap(tester, find.widgetWithText(OutlinedButton, 'Repay'));
      expect(find.text('Main Cash — GHC 3,000.00'), findsOneWidget, reason: 'defaults to waterCashAccountId');
      expect(find.textContaining('only the interest and the fees are a cost to the company'), findsOneWidget);
      await enterIn(tester, 'Principal', '1000');
      await enterIn(tester, 'Interest', '100');
      await tester.pumpAndSettle();
      await tapIn(tester, inDialog(find.text('Record GHC 1,100.00')));
      final r = a.lastBody('/api/Water/loans/1/record-repayment');
      expect((r['waterLoanId'], r['waterCashAccountId'], r['principalAmount'], r['interestAmount']), (1, 5, 1000, 100));
      clearToasts(tester);

      // Reverse from the history table.
      await tap(tester, find.widgetWithText(OutlinedButton, 'Reverse'));
      expect(find.text('Reverse Repayment'), findsOneWidget);
      await reasonOther(tester, 'Bank bounced it');
      await tapIn(tester, inDialog(find.widgetWithText(FilledButton, 'Reverse')));
      expect(a.writes.last.url.path, '/api/Water/loan-payments/11/reverse');
    });
  });

  // ------------------------------------------------------------ cash flow

  group('Cash Flow', () {
    FakeApi api() => FakeApi()
      ..gets['/api/Water/cash-flow'] = {
        'summary': {'moneyIn': 1000, 'moneyOut': 400, 'netCashFlow': 600, 'openingCash': 0, 'closingCash': 600, 'operatingIn': 1000, 'operatingOut': 400},
        'rows': [
          {'id': 1, 'rowSource': 'Sale', 'sourceType': 'CustomerPayment', 'flowGroup': 'OperatingIn', 'category': 'Sale', 'transactionDate': '2026-10-01T00:00:00', 'description': 'Sachets', 'amount': 1000},
          {'id': 2, 'rowSource': 'Expense', 'sourceType': 'Expense', 'flowGroup': 'OperatingOut', 'category': 'Fuel', 'transactionDate': '2026-10-02T00:00:00', 'description': 'Diesel', 'amount': -400},
        ],
      }
      ..gets['/api/Water/customer-balances/summary'] = {'totalBalance': 60, 'partyCount': 1}
      ..gets['/api/Water/supplier-balances/summary'] = {'totalBalance': 0, 'partyCount': 0}
      ..gets['/api/Water/cash-accounts'] = accounts;

    testWidgets('Water text and cards; a withdrawal is a Water owner draw', (tester) async {
      final a = api();
      await open(tester, CashFlowScreen(session: await sessionFor(a), company: water, rail: waterMoneyRail), size: phone);
      expect(a.requests.any((r) => r.url.path.startsWith('/api/Poultry')), isFalse);
      expect(find.textContaining('A draft expense, or one bought on credit'), findsOneWidget, reason: 'always open');
      await see(tester, find.text('+GHC 1,000.00 · Sales'));
      expect(find.text('MONEY IN'), findsNothing, reason: 'Water cards lead with the amount');
      expect(find.text('RUNNING CASH'), findsWidgets);
      expect(find.text('Type'), findsWidgets);

      await tester.drag(_list, const Offset(0, 3000));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Adjustment'));
      await tester.pumpAndSettle();
      await tester.tap(inDialog(find.text('What kind of adjustment?')).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Withdrawal').last);
      await tester.pumpAndSettle();
      await tester.enterText(inDialog(find.byType(TextFormField)).first, '300');
      await tester.pump();
      await tester.tap(inDialog(find.text('Not linked to an account')).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Main Cash').last);
      await tester.pumpAndSettle();
      await tapIn(tester, find.widgetWithText(FilledButton, 'Record withdrawal'));
      final b = a.lastBody('/api/Water/owner-money');
      expect((b['transactionType'], b['amount'], b['waterCashAccountId']), ('Draw', 300, 5));
    });

    testWidgets('insights carry both Water notes', (tester) async {
      await open(tester, CashFlowScreen(session: await sessionFor(api()), company: water, rail: waterMoneyRail), size: phone);
      await tester.tap(find.text('Cash Flow Insights'));
      await tester.pumpAndSettle();
      expect(find.textContaining('sales, payments and approved expenses', findRichText: true), findsWidgets);
      expect(find.textContaining('are counted here separately', findRichText: true), findsWidgets);
    });
  });

  // ------------------------------------------------------------ profit & loss

  testWidgets('Profit & Loss as a page: no Reports button, no report card', (tester) async {
    final a = FakeApi();
    await open(tester, WaterProfitLossScreen(session: await sessionFor(a), company: water, page: true), size: phone);
    expect(find.text('Profit & Loss'), findsWidgets);
    expect(find.text('Reports'), findsNothing);
    expect(find.text('RECORDS'), findsNothing);
    expect(find.text('WIN WATER'), findsNothing, reason: 'no report eyebrow');
    expect(find.text('Export PDF'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await open(tester, WaterProfitLossScreen(session: await sessionFor(a), company: water), size: phone);
    expect(find.text('Reports'), findsOneWidget, reason: 'the report route keeps its frame');
  });
}
