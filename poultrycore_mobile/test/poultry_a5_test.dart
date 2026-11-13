// Report 35 Part 4, A5 of the 9 Nov web pull: the smaller Poultry changes,
// checked against the web. The cash-shortfall cases are the web's own, ported
// one for one from lib/api/http-error.test.ts. The screens run at phone width
// against a fake API: the Stock page (totals, the entered time, the manual
// movement rules), Expenses (the feed notice, the optional flock, the balance
// message) and Daily Closing (disposed eggs).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/pages/poultry/daily_closing_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/expenses/expenses_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/inventory/stock_movements_screen.dart';

import 'poultry_daily_closing_test.dart' as dc;
import 'poultry_expenses_test.dart' as ex;
import 'support/harness.dart';

void main() {
  // ------------------------------------------------------- http-error.test.ts
  group('explainCashShortfall (the web\'s cases)', () {
    const raw = 'This payment would overdraw the cash account (balance 0.00, payment 2500.00).';
    test('names the account, the balance and the payment', () {
      expect(explainCashShortfall(raw, 'MoMo Wallet'), 'Your MoMo Wallet has 0.00, cannot pay 2,500.00. Please top up or choose another account.');
    });
    test('never echoes the database wording', () {
      expect(explainCashShortfall(raw, 'MoMo Wallet'), isNot(matches(RegExp(r'overdraw|sql|/api', caseSensitive: false))));
    });
    test('still reads well without an account name or numbers', () {
      expect(explainCashShortfall(raw), startsWith('Your cash account has 0.00'));
      expect(explainCashShortfall('Source cash account would go negative; transfer rejected.', 'Bank'),
          'Your Bank does not have enough money for this payment. Please top up or choose another account.');
    });
    test('leaves other errors alone', () {
      expect(explainCashShortfall('Supplier does not belong to this company.', 'MoMo'), isNull);
    });
  });

  test('feed is a category of its own, matched loosely', () {
    expect((isFeedCategory('Feed'), isFeedCategory(' feed '), isFeedCategory('Feeders'), isFeedCategory(null)), (true, true, false, false));
  });

  // ---------------------------------------------------------------- Stock page
  group('Stock page', () {
    test('the business date and the posting time are two facts; the opening position and the batch pool are named', () {
      final moves = buildStockMoves([
        {'poultryStockTransactionId': 1, 'txnType': 'Damage/Loss', 'quantity': -5, 'productName': 'Eggs',
          'effectiveDate': '2024-03-01T00:00:00', 'createdDate': '2026-11-08T15:49:00Z'},
        {'poultryStockTransactionId': 2, 'txnType': 'Opening Adjustment', 'quantity': 40, 'productName': 'Birds',
          'createdDate': '2026-11-01T00:00:00', 'batchCode': 'B-001', 'birdScope': 'BatchUnallocated', 'flockName': 'Pen 1'},
      ], const [], const [], const []);
      final a = moves.firstWhere((m) => m['key'] == 'pt1'), b = moves.firstWhere((m) => m['key'] == 'pt2');
      expect((a['date'], a['postedAt']), ('2024-03-01T00:00:00', '2026-11-08T15:49:00Z'));
      expect(enteredOnAnotherDay(a, Duration.zero), isTrue);
      expect((b['postedAt'], b['source'], b['batchFlock']), (null, 'Opening position', 'B-001 / Not placed in a flock'),
          reason: 'a bare business date has no time; a batch-pool row says so');
      expect((hasClockTime('2026-11-01T00:00:00'), hasClockTime('2026-11-01 08:30:00'), hasClockTime('2026-11-01')), (false, true, false));
    });

    test('totals: in and out apart; the net only for one item', () {
      final mixed = stockMoveTotals([
        {'item': 'Eggs', 'qty': 30},
        {'item': 'Feed', 'qty': -10},
      ]);
      expect((mixed.totalIn, mixed.totalOut, mixed.oneItem, mixed.itemCount), (30, 10, null, 2));
      final one = stockMoveTotals([
        {'item': 'Eggs', 'qty': 30},
        {'item': 'Eggs', 'qty': -45},
      ]);
      expect((one.net, one.oneItem), (-15, 'Eggs'));
    });

    test('manual movement reasons: a sale / loss of birds is never an increase', () {
      final birdsUp = manualReasonsFor('birds', 1, null, false);
      for (final r in ['Historical Sale', 'Historical Sale / Use', 'Cull', 'Transfer Out', 'Damage', 'Loss', 'Disposal', 'Historical Mortality']) {
        expect(birdsUp, isNot(contains(r)), reason: r);
      }
      expect(birdsUp, contains('Opening Bird Count'));
      final birdsDown = manualReasonsFor('birds', -1, null, false);
      expect(birdsDown, containsAll(['Historical Sale', 'Transfer Out', 'Cull']));
      expect(manualReasonsFor('product', -1, null, true), isNot(anyOf(contains('Historical Sale'), contains('Transfer Out'))));
    });

    testWidgets('the totals panel and the "Entered" line', (tester) async {
      final a = FakeApi()
        ..gets['/api/Poultry/products'] = []
        ..gets['/api/Poultry/stock/transactions'] = [
          {'poultryStockTransactionId': 1, 'txnType': 'Damage/Loss', 'quantity': -5, 'productName': 'Eggs',
            'effectiveDate': '2024-03-01T00:00:00', 'postedAt': '2026-11-08T15:49:00Z'},
          {'poultryStockTransactionId': 2, 'txnType': 'Production', 'quantity': 30, 'productName': 'Eggs', 'createdDate': '2026-11-08T09:00:00Z'},
        ];
      await open(tester, StockMovementsScreen(session: await sessionFor(a), company: company), size: phone);
      final panel = find.byKey(const ValueKey('stock-totals'));
      await tester.ensureVisible(panel);
      expect(find.descendant(of: panel, matching: find.text('+30')), findsOneWidget);
      expect(find.descendant(of: panel, matching: find.text('-5')), findsOneWidget);
      expect(find.descendant(of: panel, matching: find.text('+25')), findsOneWidget, reason: 'one item: the net');
      expect(find.textContaining('across all 2 filtered rows, not just this page.', findRichText: true), findsOneWidget);
      expect(find.textContaining('Entered: 8 Nov 2026', findRichText: true), findsOneWidget, reason: 'effective in 2024, entered in 2026');
    });
  });

  // ------------------------------------------------------------------ Expenses
  group('Expenses', () {
    testWidgets('paying more than the account holds is stopped with its name, and nothing is sent', (tester) async {
      final a = ex.api();
      await open(tester, ExpensesScreen(session: await sessionFor(a), company: company), size: phone);
      await tester.tap(find.text('Add Expense'));
      await tester.pumpAndSettle();
      await ex.choose(tester, 'Select category', 'Veterinary');
      await ex.choose(tester, 'What was this expense for?', 'Other (type your own)');
      await tester.enterText(ex.inDialog(find.byType(TextField)).last, 'Vaccines');
      await tester.enterText(ex.inDialog(find.byType(TextField)).first, '1000');
      await ex.choose(tester, 'Select payment method', 'Cash');
      await ex.choose(tester, 'None (no cash movement)', 'Till (900.00)');
      await ex.tapIn(tester, ex.inDialog(find.text('Create Expense')));
      expect(ex.inDialog(find.text('Your Till has 900.00, cannot pay 1,000.00. Please top up or choose another account.')), findsOneWidget);
      expect(a.writes.where((w) => w.url.path == '/api/Expense'), isEmpty);
    });

    testWidgets('an expense saved as Feed before the rule can still be edited', (tester) async {
      final a = ex.api()..gets['/api/Expense/1'] = ex.feed;
      final s = await sessionFor(a);
      await open(
        tester,
        Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () => showDialog<bool>(
                  context: ctx,
                  builder: (_) => ExpenseFormDialog(
                    session: s,
                    company: company,
                    expenseId: 1,
                    flocks: const [],
                    batches: const [],
                    flocksLoading: false,
                    suppliers: const [],
                    accounts: const [],
                  ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
        size: phone,
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(ex.inDialog(find.text('Feed')), findsWidgets);
      expect(find.byKey(const ValueKey('feed-purchase-notice')), findsNothing);
    });
  });

  // ------------------------------------------------------------- Daily Closing
  testWidgets('Daily Closing: total disposed eggs next to the broken ones (a dash before 404)', (tester) async {
    final ws = dc.workspace('2026-10-02');
    (ws['production'] as Map)['eggsDisposed'] = 7;
    final api = dc.closingApi(day: {'businessDate': '2026-10-02', 'closing': null, 'live': ws, 'atClose': null, 'history': []});
    await open(tester, DailyClosingScreen(session: await sessionFor(api), company: adminCompany), size: const Size(360, 3000));
    expect(find.text('TOTAL DAMAGED (BROKEN) EGGS'), findsOneWidget);
    expect(find.text('TOTAL DISPOSED EGGS'), findsOneWidget);
    expect(find.text('7'), findsWidgets);

    (ws['production'] as Map).remove('eggsDisposed');
    final before = dc.closingApi(day: {'businessDate': '2026-10-02', 'closing': null, 'live': ws, 'atClose': null, 'history': []});
    await open(tester, DailyClosingScreen(session: await sessionFor(before), company: adminCompany), size: const Size(360, 3000));
    expect(find.text('TOTAL DISPOSED EGGS'), findsOneWidget);
    expect(find.text('—'), findsWidgets, reason: 'absent until migration 404');
  });
}
