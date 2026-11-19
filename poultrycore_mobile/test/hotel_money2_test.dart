// Hotel → Sales, Expenses & Money → Money: Owner Money, Loans (Financing) and
// Cash Account, on hotelMoneyRail, at phone width against a fake API.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/hotel/hotel_money_rail.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/money/cash_account_dialogs.dart';
import 'package:poultrycore_mobile/pages/poultry/money/cash_accounts_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/money/loans_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/money/owner_money_screen.dart';

import 'package:poultrycore_mobile/pages/shared/reason_select.dart';

import 'support/harness.dart';

final hotel = Company(farmId: 'h1', name: 'Palm Hotel', type: CompanyType.hotel, role: 'Admin');
const tall = Size(360, 4200);

Finder filled(String t) => find.widgetWithText(FilledButton, t);

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).first);
  await tester.pumpAndSettle();
}

/// The Hotel's cash accounts answer with lower-case keys.
FakeApi base() => FakeApi()
  ..gets['/api/Hotel/finance/cash-accounts'] = [
    {'hotelcashaccountid': 5, 'accountname': 'Front desk till', 'accounttype': 'FrontDeskCash', 'openingbalance': 0, 'currentbalance': 900,
      'allownegativebalance': false, 'isactive': true, 'purpose': 'FrontDesk', 'notes': null},
  ];

/// A reason picked from a ReasonSelectField inside a dialog, tapping the field itself.
Future<void> pickReason(WidgetTester tester, String option) async {
  final field = find.byType(ReasonSelectField).last;
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Map body(FakeApi api, String path, [String method = 'POST']) =>
    jsonDecode(api.writes.lastWhere((w) => w.url.path == path && w.method == method).body) as Map;

void main() {
  test('the three rows open native screens; the rail reads the lower-case accounts', () {
    for (final h in ['/hotel-owner-money', '/hotel-loans', '/hotel-cash-accounts']) {
      expect(pageScreens.containsKey(h), isTrue, reason: h);
    }
    final a = hotelMoneyRail.accountsOf([
      {'hotelcashaccountid': 5, 'accountname': 'Till', 'isactive': true},
    ]).first;
    expect((a['hotelCashAccountId'], a['accountName'], a['isActive']), (5, 'Till', true));
    expect(hotelMoneyRail.cashAccountsApi, '/api/Hotel/finance/cash-accounts');
    expect((hotelAccountTypeLabel('MobileMoney'), hotelPurposeLabel('POS'), hotelPurposeLabel(null)), ('Mobile Money', 'POS / Restaurant', null));
  });

  testWidgets('Owner Money: Hotel records, Record contribution and Reverse', (tester) async {
    final api = base()
      ..gets['/api/Hotel/owner-money'] = [
        {'hotelOwnerMoneyId': 1, 'transactionNumber': 'OM-1', 'transactionDate': '2026-10-10', 'transactionType': 'Draw', 'amount': 100,
          'hotelCashAccountId': 5, 'accountName': 'Front desk till', 'status': 'Posted'},
      ]
      ..gets['/api/Hotel/owner-money/summary'] = {'totalContributions': 0, 'totalDraws': 100, 'drawCount': 1};
    await open(tester, OwnerMoneyScreen(session: await sessionFor(api), company: hotel, rail: hotelMoneyRail), size: tall);
    expect(find.textContaining('OM-1'), findsWidgets);
    expect(api.requests.any((r) => r.url.path.startsWith('/api/Poultry') || r.url.path == '/api/Hotel/cash-accounts'), isFalse);

    await tapText(tester, 'Record contribution');
    final picker = find.ancestor(of: find.text('Which account does it arrive in?'), matching: find.byType(AppSelect<String>));
    await tester.ensureVisible(picker);
    await tester.pumpAndSettle();
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Front desk till').last);
    await tester.pumpAndSettle();
    await enter(tester, 'Amount *', '250');
    await tester.ensureVisible(filled('Record Contribution'));
    await tester.tap(filled('Record Contribution'));
    await tester.pumpAndSettle();
    final b = body(api, '/api/Hotel/owner-money');
    expect((b['transactionType'], b['amount'], b['hotelCashAccountId']), ('Contribution', 250, 5));

    await tapText(tester, 'Reverse');
    await pickReason(tester, 'Duplicate entry');
    await tester.tap(filled('Reverse').last);
    await tester.pumpAndSettle();
    final r = body(api, '/api/Hotel/owner-money/1/reverse');
    expect((r['farmId'], r['reason']), ('h1', 'Duplicate entry'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Loans: no Draft filter, Repay posts to /repayments, a repayment reverses', (tester) async {
    final api = base()
      ..gets['/api/Hotel/loans'] = [
        {'hotelLoanId': 2, 'loanNumber': 'LN-2', 'lenderName': 'Bank A', 'lenderType': 'Bank', 'status': 'Active', 'startDate': '2026-09-01',
          'originalPrincipal': 1000, 'amountReceived': 1000, 'outstandingPrincipal': 600, 'totalPrincipalRepaid': 400, 'hotelCashAccountId': 5},
      ]
      ..gets['/api/Hotel/loan-payments'] = [
        {'hotelLoanPaymentId': 3, 'hotelLoanId': 2, 'paymentNumber': 'LP-3', 'paymentDate': '2026-10-12', 'totalAmount': 400, 'principalAmount': 400,
          'interestAmount': 0, 'feeAmount': 0, 'status': 'Posted', 'accountName': 'Front desk till'},
      ]
      ..gets['/api/Hotel/loans/summary'] = {'activeLoans': 1, 'outstandingPrincipal': 600};
    await open(tester, LoansScreen(session: await sessionFor(api), company: hotel, rail: hotelMoneyRail), size: tall);
    expect(find.text('Loans (Financing)'), findsWidgets);
    expect(find.text('Draft'), findsNothing);
    expect(find.text('LN-2 · Bank A'), findsOneWidget);
    expect(find.textContaining('LP-3'), findsWidgets, reason: 'the repayment hangs off its loan');

    await tapText(tester, 'Repay');
    expect(find.text('Record a Repayment'), findsOneWidget);
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField)).first, '100');
    await tester.pumpAndSettle();
    final record = find.ancestor(of: find.textContaining('Record '), matching: find.byType(FilledButton)).last;
    await tester.ensureVisible(record);
    await tester.tap(record);
    await tester.pumpAndSettle();
    final p = body(api, '/api/Hotel/loans/2/repayments');
    expect((p['principalAmount'], p['hotelCashAccountId'], p['farmId']), (100, 5, 'h1'));

    await tapText(tester, 'Reverse');
    await pickReason(tester, 'Duplicate entry');
    await tester.tap(filled('Reverse').last);
    await tester.pumpAndSettle();
    expect(body(api, '/api/Hotel/loan-payments/3/reverse')['farmId'], 'h1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cash Account: Hotel types and purpose, transactions with Reverse, deactivate, one-step transfer', (tester) async {
    final api = base()
      ..gets['/api/Hotel/cash-transfers'] = [
        {'hotelCashTransferId': 7, 'fromAccountName': 'Front desk till', 'toAccountName': 'Bank', 'transferDate': '2026-10-01', 'amount': 50, 'status': 'Reversed'},
      ]
      ..gets['/api/Hotel/finance/cash-accounts/status'] = [
        {'hotelCashAccountId': 5, 'ledgerBalance': 880, 'cacheDrift': 20, 'lastReconciledAt': null},
      ]
      ..gets['/api/Hotel/finance/cash-transactions'] = [
        {'hotelcashtxnid': 1, 'txndate': '2026-10-03', 'txntype': 'Credit', 'amount': 30, 'sourcetype': 'CashAdjustment', 'sourceid': 9,
          'balanceafter': 900, 'description': 'Opening balance correction'},
      ];
    await open(tester, CashAccountsScreen(session: await sessionFor(api), company: hotel, rail: hotelMoneyRail), size: tall);
    expect(find.text('Front Desk Cash'), findsWidgets);
    expect(find.text('Front Desk'), findsOneWidget, reason: 'Used for');
    expect(find.text('Stored balance disagrees with its transactions'), findsOneWidget);
    expect(find.text('REVERSED TRANSFERS'), findsOneWidget);
    expect(find.text('All transfers →'), findsOneWidget);

    await tapText(tester, 'View details');
    expect(api.requests.last.url.queryParameters['accountId'], '5');
    expect(find.textContaining('Money in · '), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Reverse'));
    await tester.pumpAndSettle();
    await pickReason(tester, 'Miscounted');
    await tester.tap(filled('Reverse'));
    await tester.pumpAndSettle();
    expect(body(api, '/api/Hotel/finance/cash-adjustments/9/reverse')['reason'], 'Miscounted');
    Navigator.of(tester.element(find.textContaining('Transactions —'))).pop();
    await tester.pumpAndSettle();

    await tapText(tester, 'Delete');
    await tester.tap(filled('Remove account'));
    await tester.pumpAndSettle();
    final d = body(api, '/api/Hotel/finance/cash-accounts/5', 'PUT');
    expect((d['isActive'], d['purpose'], d['accountName']), (false, 'FrontDesk', 'Front desk till'));

    await tapText(tester, 'Recalculate');
    expect(api.writes.any((w) => w.url.path == '/api/Hotel/finance/cash-accounts/recalculate'), isTrue);
    expect(tester.takeException(), isNull);
  });
}
