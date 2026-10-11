// Poultry → Sales → Payments received and Customer Balances: the allocation
// maths and the payment folding, then both pages driven at phone width
// against a fake API.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/reports/report_export.dart';
import 'package:poultrycore_mobile/pages/poultry/sales/balances_logic.dart';
import 'package:poultrycore_mobile/pages/poultry/sales/customer_balances_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/sales/payments_received_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/sales/sales_screen.dart';

import 'support/harness.dart';

/// Newest first, as the API answers.
final payments = [
  // Sale 7 was part-paid twice: the newest keeps the row, the older folds in.
  {'paymentId': 'p3', 'paymentNumber': 'PAY-0003', 'partyId': 1, 'partyName': 'Ama', 'paymentDate': '2026-10-04T09:30:00', 'totalAmount': 50, 'paymentMethod': 'MoMo', 'sourceType': 'CustomerBalances', 'status': 'Posted', 'allocationCount': 1, 'saleId': 7, 'saleTotal': 200, 'balanceBefore': 100, 'amountApplied': 50, 'balanceAfter': 50, 'createdBy': 'kwame'},
  {'paymentId': 'p2', 'paymentNumber': 'PAY-0002', 'partyId': 2, 'partyName': 'Kofi', 'paymentDate': '2026-10-03T00:00:00', 'totalAmount': 300, 'paymentMethod': 'Cash', 'sourceType': 'SaleEntry', 'status': 'Posted', 'allocationCount': 2},
  {'paymentId': 'p1', 'paymentNumber': 'PAY-0001', 'partyId': 1, 'partyName': 'Ama', 'paymentDate': '2026-10-01T00:00:00', 'totalAmount': 100, 'paymentMethod': 'Cash', 'sourceType': 'SaleEntry', 'status': 'Posted', 'allocationCount': 1, 'saleId': 7, 'saleTotal': 200, 'balanceBefore': 200, 'amountApplied': 100, 'balanceAfter': 100},
  {'paymentId': 'p0', 'paymentNumber': 'PAY-0000', 'partyId': 2, 'partyName': 'Kofi', 'paymentDate': '2026-09-20T00:00:00', 'totalAmount': 40, 'paymentMethod': 'Card', 'sourceType': 'SaleEntry', 'status': 'Reversed', 'allocationCount': 1, 'saleId': 9, 'reversalReason': 'entered twice', 'reversedBy': 'kwame'},
];

final openSales = [
  {'documentType': 'Sale', 'documentId': 7, 'reference': 'S7', 'documentDate': '2026-09-28T00:00:00', 'label': 'Fresh Eggs', 'totalAmount': 200, 'amountPaid': 150, 'balance': 50, 'ageDays': 7, 'status': 'Partial', 'isOverdue': false, 'cashAccountId': 5},
  {'documentType': 'Sale', 'documentId': 3, 'reference': 'S3', 'documentDate': '2026-09-01T00:00:00', 'label': 'Chicken', 'totalAmount': 120, 'amountPaid': 0, 'balance': 120, 'ageDays': 34, 'status': 'Unpaid', 'isOverdue': true},
];

FakeApi api() => FakeApi()
  ..gets['/api/Poultry/customer-payments'] = payments
  ..gets['/api/Poultry/customer-payments/p2'] = {
    'payment': {},
    'allocations': [
      {'allocationId': 1, 'documentId': 4, 'label': 'Eggs', 'documentDate': '2026-10-02', 'documentTotal': 200, 'amountApplied': 200, 'balanceBefore': 200, 'balanceAfter': 0},
      {'allocationId': 2, 'documentId': 5, 'label': 'Manure', 'documentDate': '2026-10-02', 'documentTotal': 150, 'amountApplied': 100, 'balanceBefore': 150, 'balanceAfter': 50},
    ],
  }
  ..gets['/api/Poultry/customer-balances'] = [
    {'partyId': 1, 'partyName': 'Ama', 'contactPhone': '024 000 0001', 'totalBalance': 170, 'openDocumentCount': 2, 'oldestDocumentDate': '2026-09-01T00:00:00', 'lastPaymentDate': '2026-10-04T09:30:00', 'overdueAmount': 120},
    {'partyId': 2, 'partyName': 'Kofi', 'totalBalance': 50, 'openDocumentCount': 1, 'overdueAmount': 0},
  ]
  ..gets['/api/Poultry/customer-balances/summary'] = {
    'totalBalance': 220, 'partyCount': 2, 'overdueBalance': 120, 'paymentsToday': 50, 'largestBalance': 170, 'largestBalanceParty': 'Ama',
  }
  ..gets['/api/Poultry/customer-balances/1/open-sales'] = openSales
  ..gets['/api/Poultry/cash-accounts'] = [
    {'poultryCashAccountId': 5, 'accountName': 'Main Cash Account', 'currentBalance': 900, 'isActive': true},
  ]
  ..gets['/api/Poultry/customers/1/statement'] = [
    {'entryType': 'OpeningBalance', 'debit': 0, 'credit': 0, 'runningBalance': 0},
    {'entryDate': '2026-09-01T00:00:00', 'entryType': 'Sale', 'reference': 'S3', 'description': 'Chicken', 'sourceType': 'Sale', 'debit': 120, 'credit': 0, 'runningBalance': 120},
    {'entryDate': '2026-10-03T00:00:00', 'entryType': 'Payment', 'reference': 'PAY-0002', 'description': 'Cash payment', 'sourceType': 'SaleEntry', 'debit': 0, 'credit': 300, 'runningBalance': -180, 'paymentId': 'p2', 'allocationCount': 2},
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

Future<void> tapSeen(WidgetTester tester, Finder f) async {
  ScaffoldMessenger.of(tester.element(find.byType(Scaffold).last)).removeCurrentSnackBar();
  await tester.pumpAndSettle();
  await see(tester, f);
  await tester.tap(f.first);
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, String shown, String option) async {
  await see(tester, find.text(shown));
  await pick(tester, shown, option);
}

Map<String, String> lastQuery(FakeApi a, String path) => a.requests.lastWhere((r) => r.url.path == path).url.queryParameters;

void main() {
  // ------------------------------------------------------------ rules

  group('allocation and folding', () {
    test('auto-allocate oldest first, in pesewas', () {
      expect(autoAllocateOldestFirst(140.5, openSales), {'Sale:3': 120, 'Sale:7': 20.5});
      expect(autoAllocateOldestFirst(1000, openSales), {'Sale:3': 120, 'Sale:7': 50});
    });

    test('validation messages, as the web', () {
      expect(validateAllocations(0, openSales, {}).blocking, ['Enter a payment amount greater than 0.']);
      expect(validateAllocations(100, openSales, {}).blocking, ['Apply this payment to at least one line.']);
      expect(validateAllocations(100, openSales, {'Sale:7': 40}).blocking, ['60.00 of this payment is still unallocated.']);
      final over = validateAllocations(60, openSales, {'Sale:7': 60});
      expect(over.overAllocated, {'Sale:7': 10});
      expect(over.problems.first.$2, 'Cannot apply more than the 50.00 still owed on this line.');
      expect(validateAllocations(50, openSales, {'Sale:7': 50}).ok, isTrue);
      expect(formatDocumentAge(2000), 'Opening balance');
      expect(formatDocumentAge(-3), '0d');
      expect(entryTimestamp('2026-01-02'), '2026-01-02T00:00:00.000Z');
    });

    test('a part-paid sale keeps one row; totals count posted payments', () {
      final filtered = filterPayments(payments, status: 'all');
      final fold = foldPayments(filtered, payCountBySale(payments));
      expect([for (final r in fold.visible) r['paymentId']], ['p3', 'p2', 'p0']);
      expect(fold.folded, 1);
      expect(fold.carriers, {7: 'p3'});
      final t = paymentTotals(filterPayments(payments));
      expect((t.count, t.amount, t.sales), (3, 450, 4));
      expect(filterPayments(payments, search: 'pay-0002').single['paymentId'], 'p2');
      expect(filterPayments(payments, appliedTo: 'multiple').single['paymentId'], 'p2');
    });
  });

  test('both pages are on the sidebar routes', () {
    expect(pageScreens.containsKey('/poultry-payments'), isTrue);
    expect(pageScreens.containsKey('/customer-balances'), isTrue);
  });

  // ------------------------------------------------------------ payments received

  group('Payments received', () {
    testWidgets('totals, the folded trail, a multi-sale allocation, every filter', (tester) async {
      final a = api();
      await open(tester, PaymentsReceivedScreen(session: await sessionFor(a), company: company), size: phone);
      await see(tester, find.text('1 inside a sale’s trail'));
      expect(find.text('1 inside a sale’s trail'), findsOneWidget);
      await see(tester, find.text('GHC 450.00'));
      expect(find.text('GHC 450.00'), findsOneWidget, reason: 'posted only');
      await see(tester, find.text(' (paid 2 times)'));
      expect(find.text('By: kwame'), findsOneWidget);

      await tapSeen(tester, find.text('GHC 50.00').first);
      expect(lastQuery(a, '/api/Poultry/customer-payments')['saleId'], '7');
      expect(find.text('SALE #7 · PAID 4 TIMES'), findsOneWidget, reason: 'the trail lists what the API returns');

      await tapSeen(tester, find.text('GHC 300.00'));
      await see(tester, find.text('#5'));
      expect(find.text('Before GHC 150.00'), findsOneWidget);

      await choose(tester, 'All methods', 'Cash');
      await choose(tester, 'Any', 'Several sales');
      expect(find.text('PAY-0002'), findsOneWidget);
      expect(find.text('PAY-0003'), findsNothing);
      await choose(tester, 'Several sales', 'Any');
      await choose(tester, 'Cash', 'All methods');
      await choose(tester, 'All sources', 'Balances');
      await see(tester, find.text('PAY-0003'));
      expect(find.text('PAY-0003'), findsOneWidget);
      await choose(tester, 'Balances', 'All sources');
      await choose(tester, 'Posted', 'Reversed');
      expect(find.text('PAY-0000'), findsOneWidget);
      expect(find.text('Reversed by kwame: entered twice'), findsOneWidget);

      await choose(tester, 'Custom Date Range', 'This Month');
      expect(lastQuery(a, '/api/Poultry/customer-payments')['from'], isNotNull, reason: 'dates go to the server');
    });

    testWidgets('reverse needs a reason; the sale link opens the sale', (tester) async {
      final a = api();
      await open(tester, PaymentsReceivedScreen(session: await sessionFor(a), company: company), size: phone);
      // The web's dialog shows a never-ending "Loading the sales it covers…"
      // for a payment whose detail was never loaded, so pump, not settle.
      await see(tester, find.text('Reverse'));
      await tester.tap(find.text('Reverse').first);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Loading the sales it covers…'), findsOneWidget);
      expect(find.text('This reverses the whole payment and restores the balance on every sale it was applied to.'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Reverse payment'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(a.writes, isEmpty);
      await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField)), 'wrong customer');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Reverse payment'));
      await tester.pumpAndSettle();
      final body = a.lastBody('/api/Poultry/customer-payments/p3/reverse');
      expect((body['reason'], body['farmId']), ('wrong customer', 'farm-1'));
      expect(find.text('Payment reversed — GHC 50.00 put back on 1 sale.'), findsOneWidget);

      await tapSeen(tester, find.text('#7'));
      expect(find.byType(SalesScreen), findsOneWidget);
      expect(tester.widget<SalesScreen>(find.byType(SalesScreen)).focusSaleId, 7);
    });
  });

  // ------------------------------------------------------------ customer balances

  group('Customer Balances', () {
    testWidgets('summary, cards, filters to the server, method filter on the page', (tester) async {
      final a = api();
      await open(tester, CustomerBalancesScreen(session: await sessionFor(a), company: company), size: phone);
      expect(find.text('GHC 220.00'), findsOneWidget);
      expect(find.text('Largest balance: Ama'), findsOneWidget);
      await see(tester, find.text('No phone'));
      expect(find.text('No phone'), findsOneWidget);

      await choose(tester, 'All customers', 'Ama');
      expect(lastQuery(a, '/api/Poultry/customer-balances')['customerId'], '1');
      await choose(tester, 'All with balance', 'Overdue');
      expect(lastQuery(a, '/api/Poultry/customer-balances')['status'], 'Overdue');
      await see(tester, find.text('Reset'));
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      expect(lastQuery(a, '/api/Poultry/customer-balances')['status'], 'All');

      await choose(tester, 'Any method', 'MoMo');
      await see(tester, find.text('024 000 0001'));
      expect(find.text('Kofi'), findsNothing, reason: 'Kofi never paid by MoMo');
      await see(tester, find.text('MoMo'));
      await tester.tap(find.text('MoMo').first);
      await tester.pumpAndSettle();
      expect(find.text('Card'), findsNothing, reason: 'a reversed payment is no evidence of a method');
      await tester.tap(find.text('Cash').last);
      await tester.pumpAndSettle();
      await see(tester, find.text('No phone'));
      expect(find.text('No phone'), findsOneWidget, reason: 'Kofi paid by Cash');
    });

    testWidgets('open sales, receive one payment, open the sale', (tester) async {
      final a = api();
      await open(tester, CustomerBalancesScreen(session: await sessionFor(a), company: company), size: phone);
      await tapSeen(tester, find.text('Show 2 open sales'));
      expect(find.text('S3'), findsOneWidget);
      expect(find.text('⚠ Overdue'), findsOneWidget);

      await tapSeen(tester, find.text('Receive payment'));
      expect(find.text('Ama · S7 · GHC 50.00 outstanding'), findsOneWidget);
      expect(find.text('Main Cash Account · GHC 900.00'), findsOneWidget, reason: "the sale's own account");
      await choose(tester, 'Cash', 'MoMo');
      await tapSeen(tester, find.widgetWithText(FilledButton, 'Receive payment'));
      final body = a.lastBody('/api/Poultry/customer-payments');
      expect((body['partyId'], body['amount'], body['paymentMethod'], body['cashAccountId'], body['sourceType']),
          (1, 50, 'MoMo', 5, 'CustomerBalances'));
      expect(body['allocations'], [
        {'saleId': 7, 'documentType': 'Sale', 'documentId': 7, 'amount': 50},
      ]);
    });

    testWidgets('bulk payment: auto-allocate oldest first, a short allocation blocks', (tester) async {
      final a = api();
      await open(tester, CustomerBalancesScreen(session: await sessionFor(a), company: company), size: phone);
      await tapSeen(tester, find.text('Receive bulk payment'));
      expect(find.text('Receive bulk payment'), findsWidgets);
      expect(find.text('Ama · GHC 170.00 outstanding across 2 open item(s)'), findsOneWidget);
      await enter(tester, 'Payment amount', '150');
      await tapSeen(tester, find.text('Auto-allocate oldest first'));
      expect(find.text('Balance after GHC 0.00'), findsOneWidget, reason: 'S3 settled first');
      expect(find.text('Balance after GHC 20.00'), findsOneWidget);
      await tapSeen(tester, find.widgetWithText(FilledButton, 'Receive payment'));
      final body = a.lastBody('/api/Poultry/customer-payments');
      expect(body['amount'], 150);
      expect([for (final x in body['allocations']) (x['documentId'], x['amount'])], [(7, 30), (3, 120)]);
    });

    testWidgets('statement with its allocation, print; all payments history', (tester) async {
      final shared = <String>[];
      ReportExport.sharer = (name, bytes, mime, subject) async => shared.add(name);
      final a = api();
      await open(tester, CustomerBalancesScreen(session: await sessionFor(a), company: company), size: phone);
      await tapSeen(tester, find.text('Statement'));
      expect(find.text('Customer statement'), findsWidgets);
      expect(find.text('Closing balance owed to us'), findsOneWidget);
      await tapSeen(tester, find.text('Cash payment'));
      expect(find.textContaining('Sale #5'), findsOneWidget);
      await tapSeen(tester, find.text('Print'));
      expect(shared.single, startsWith('customer-statement'));
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tapSeen(tester, find.text('All payments'));
      expect(find.text('Payment history'), findsOneWidget);
      expect(lastQuery(a, '/api/Poultry/customer-payments'), {'farmId': 'farm-1'});
    });
  });
}
