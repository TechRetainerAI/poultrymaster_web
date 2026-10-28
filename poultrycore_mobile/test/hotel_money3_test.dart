// Hotel → Sales, Expenses & Money → Money: Cash Transfers and Reconciliation,
// on hotelMoneyRail, at phone width against a fake API.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/hotel/hotel_money_rail.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/money/cash_transfers_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/money/reconciliation_screen.dart';
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

/// An AppSelect found by its hint, then one of its options.
Future<void> choose(WidgetTester tester, String hint, String option) async {
  final picker = find.ancestor(of: find.text(hint), matching: find.byType(AppSelect<String>)).first;
  await tester.ensureVisible(picker);
  await tester.pumpAndSettle();
  await tester.tap(picker);
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining(option).last);
  await tester.pumpAndSettle();
}

Map body(FakeApi api, String path, [String method = 'POST']) =>
    jsonDecode(api.writes.lastWhere((w) => w.url.path == path && w.method == method).body) as Map;

FakeApi base() => FakeApi()
  ..gets['/api/Hotel/finance/cash-accounts'] = [
    {'hotelcashaccountid': 5, 'accountname': 'Front desk till', 'accounttype': 'FrontDeskCash', 'currentbalance': 900, 'isactive': true},
    {'hotelcashaccountid': 6, 'accountname': 'Bank', 'accounttype': 'Bank', 'currentbalance': 100, 'isactive': true},
  ];

void main() {
  test('the two rows open native screens; Hotel account types map onto the counting words', () {
    for (final h in ['/hotel-cash-transfers', '/hotel-cash-reconciliation']) {
      expect(pageScreens.containsKey(h), isTrue, reason: h);
    }
    expect([for (final t in ['FrontDeskCash', 'CashBox', 'Bank', 'MobileMoney', 'Other']) hotelVocabularyType(t)], ['cash', 'cash', 'bank', 'momo', 'other']);
  });

  testWidgets('Cash Transfers: Hotel filters, a transfer posted in one request, Reverse', (tester) async {
    final api = base()
      ..gets['/api/Hotel/cash-transfers'] = [
        {'hotelCashTransferId': 7, 'transferNumber': 'TR-7', 'fromAccountName': 'Front desk till', 'toAccountName': 'Bank',
          'transferDate': '2026-10-01', 'amount': 50, 'status': 'Approved'},
      ];
    await open(tester, CashTransfersScreen(session: await sessionFor(api), company: hotel, rail: hotelMoneyRail), size: tall);
    expect(find.text('TR-7'), findsWidgets);
    expect(find.text('Draft'), findsNothing);
    expect(find.text('Cancelled'), findsNothing);
    expect(find.textContaining("hotel's own cash accounts"), findsOneWidget);

    await tapText(tester, 'Record transfer');
    await choose(tester, 'Pick the account the money leaves', 'Front desk till');
    await choose(tester, 'Pick the account the money arrives in', 'Bank');
    await enter(tester, 'Amount *', '200');
    await tester.ensureVisible(filled('Record Transfer'));
    await tester.tap(filled('Record Transfer'));
    await tester.pumpAndSettle();
    final b = body(api, '/api/Hotel/cash-transfers');
    expect((b['fromHotelCashAccountId'], b['toHotelCashAccountId'], b['amount'], b['farmId']), (5, 6, 200, 'h1'));
    expect(api.writes.any((w) => w.url.path.endsWith('/approve')), isFalse, reason: 'no Draft step to approve');

    final rev = find.widgetWithText(OutlinedButton, 'Reverse').first;
    await tester.ensureVisible(rev);
    await tester.pumpAndSettle();
    await tester.tap(rev);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    final field = find.byType(ReasonSelectField).last;
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate entry').last);
    await tester.pumpAndSettle();
    await tester.tap(filled('Reverse Transfer'));
    await tester.pumpAndSettle();
    final r = body(api, '/api/Hotel/cash-transfers/7/reverse');
    expect((r['farmId'], r['reason']), ('h1', 'Duplicate entry'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Reconciliation: Hotel counts, no Open ledger, cash wording, post a draft and reverse a count', (tester) async {
    final api = base()
      ..gets['/api/Hotel/finance/cash-accounts/status'] = [
        {'hotelCashAccountId': 5, 'ledgerBalance': 900, 'cacheDrift': 0, 'lastReconciledAt': '2026-10-01', 'daysSinceReconciled': 3},
      ]
      ..gets['/api/Hotel/cash-reconciliations'] = [
        {'hotelCashReconciliationId': 11, 'hotelCashAccountId': 5, 'referenceNo': 'RC-11', 'reconciliationDate': '2026-10-20',
          'systemBalance': 900, 'actualBalance': 880, 'difference': -20, 'reason': 'Cash shortage', 'status': 'Draft'},
        {'hotelCashReconciliationId': 10, 'hotelCashAccountId': 5, 'referenceNo': 'RC-10', 'reconciliationDate': '2026-10-01',
          'systemBalance': 500, 'actualBalance': 500, 'difference': 0, 'status': 'Posted'},
      ]
      ..writeAnswers['/api/Hotel/cash-reconciliations/11/post'] = {'adjustmentTransactionId': 99};
    await open(tester, ReconciliationScreen(session: await sessionFor(api), company: hotel, rail: hotelMoneyRail, accountId: 5), size: tall);
    final list = api.requests.lastWhere((r) => r.url.path == '/api/Hotel/cash-reconciliations');
    expect(list.url.queryParameters['accountId'], '5');
    expect(find.text('Open ledger'), findsNothing);
    expect(find.text('Finish RC-11'), findsOneWidget, reason: 'the open draft');
    expect(find.textContaining('RC-11 is saved but not posted'), findsOneWidget);

    await tapText(tester, 'Post it');
    expect(body(api, '/api/Hotel/cash-reconciliations/11/post')['farmId'], 'h1');

    await tapText(tester, 'Recalculate');
    expect(body(api, '/api/Hotel/finance/cash-accounts/recalculate')['farmId'], 'h1');

    await tester.tap(find.widgetWithText(OutlinedButton, 'Reverse').first);
    await tester.pumpAndSettle();
    final reason = find.ancestor(of: find.text('Why is this count being reversed?'), matching: find.byType(AppSelect<String>));
    await tester.tap(reason);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Miscounted').last);
    await tester.pumpAndSettle();
    await tester.tap(filled('Reverse'));
    await tester.pumpAndSettle();
    final rv = body(api, '/api/Hotel/cash-reconciliations/10/reverse');
    expect((rv['farmId'], rv['reason']), ('h1', 'Miscounted'));
    expect(tester.takeException(), isNull);
  });
}
