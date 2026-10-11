// Poultry → Sales → Sales: the page's rules, then the whole page driven at
// phone width against a fake API — every dropdown picked, every form saved,
// every request body checked.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/models/module.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/reports/report_export.dart';
import 'package:poultrycore_mobile/pages/poultry/sales/sale_dialogs.dart';
import 'package:poultrycore_mobile/pages/poultry/sales/sales_logic.dart';
import 'package:poultrycore_mobile/pages/poultry/sales/sales_screen.dart';
import 'package:poultrycore_mobile/screens/module_placeholder_screen.dart';

import 'support/harness.dart';

final sales = [
  {
    'saleId': 1, 'saleDate': '2026-10-01T00:00:00', 'createdDate': '2026-10-01T09:00:00', 'product': 'Fresh Eggs',
    'quantity': 75, 'unitPrice': 30, 'totalAmount': 75, 'amountPaid': 75, 'paid': true, 'paymentMethod': 'Cash',
    'customerName': 'Ama', 'flockId': 1, 'poultryCashAccountId': 5,
  },
  {
    'saleId': 2, 'saleDate': '2026-10-03T00:00:00', 'createdDate': '2026-10-03T09:00:00', 'product': 'Chicken',
    'quantity': 10, 'unitPrice': 50, 'totalAmount': 500, 'amountPaid': 200, 'paid': false, 'paymentMethod': 'Mobile Money',
    'customerName': 'Kofi', 'flockId': 2, 'saleDescription': 'Market day',
  },
];

FakeApi salesApi() => FakeApi()
  ..gets['/api/Sale'] = sales
  ..gets['/api/Flock'] = [
    {'flockId': 1, 'name': 'Layers A', 'quantity': 500},
    {'flockId': 2, 'name': 'Broilers B', 'quantity': 200, 'closedDate': '2026-09-30'},
  ]
  ..gets['/api/Customer'] = [
    {'customerId': 1, 'name': 'Ama'},
    {'customerId': 2, 'name': 'Kofi'},
  ]
  ..gets['/api/Poultry/cash-accounts'] = [
    {'poultryCashAccountId': 4, 'accountName': 'Momo', 'currentBalance': 10, 'isActive': true},
    {'poultryCashAccountId': 5, 'accountName': 'Main Cash Account', 'currentBalance': 1200.5, 'isActive': true},
    {'poultryCashAccountId': 6, 'accountName': 'Old till', 'currentBalance': 0, 'isActive': false},
  ]
  ..gets['/api/Poultry/products'] = [
    {'poultryProductId': 1, 'name': 'Eggs', 'isRawEggProduct': true, 'stockOnHand': 100},
    {'poultryProductId': 2, 'name': 'Birds', 'isBirdProduct': true, 'stockOnHand': 50},
  ]
  ..writeAnswers['/api/Sale'] = {'saleId': 99};

/// The main list of the screen on top (a pushed form sits over the Sales page).
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
  // Centre it: at the very top edge a tap can land on the app bar instead.
  Scrollable.ensureVisible(tester.element(f.first), alignment: .5);
  await tester.pumpAndSettle();
}

Future<void> tapSeen(WidgetTester tester, Finder f) async {
  // A toast from the last step must not sit on the button being pressed.
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

Future<void> type(WidgetTester tester, String label, String text) async {
  await see(tester, find.text(label));
  await enter(tester, label, text);
}

Future<SalesScreen> screen(FakeApi api, {int? focus, String? date}) async =>
    SalesScreen(session: await sessionFor(api), company: company, focusSaleId: focus, initialDate: date);

void main() {
  // ------------------------------------------------------------ rules

  group('sale rules', () {
    test('eggs are priced per crate, loose eggs pro rata', () {
      expect(saleLineTotal(75, 30, true), 75);
      expect(saleLineTotal(10, 50, false), 500);
      expect(eggCratesEquivalent(75), '2.50');
      expect(eggCrateBreakdown(75), '2c + 15p');
      expect(eggCrateBreakdown(60, long: true), '2 crates');
      expect(eggCrateBreakdown(0), isNull);
    });

    test('validation runs in the web order, stock shortfall last', () {
      final f = SaleForm()..saleDate = '2026-10-05';
      expect(f.validate(available: null, stockUnits: 'units'), 'Choose what was sold (eggs, chicken, manure, or other).');
      f
        ..product = 'Fresh Eggs'
        ..customerName = 'Ama'
        ..quantity = 150
        ..unitPrice = 30
        ..paymentMethod = 'Cash';
      expect(f.validate(available: 100, stockUnits: 'eggs'),
          'Only 100 eggs in stock — this sale is 50 more. Lower the quantity, or tick "Sell it anyway" to record it regardless.');
      f.overrideStock = true;
      expect(f.validate(available: 100, stockUnits: 'eggs'), isNull);
    });

    test('status, owed, an edited egg sale adds its own eggs back', () {
      expect(paymentStatusOf(sales[0]), 'Paid');
      expect(paymentStatusOf(sales[1]), 'Partial');
      expect(paymentStatusOf({'totalAmount': 10, 'paid': false}), 'Pending');
      expect(saleOwed(sales[1]), 300);
      expect(availableStock({'isRawEggProduct': true, 'stockOnHand': 100}, sales[0]), 175);
      expect(pageNumbers(5, 10), [1, 'ellipsis', 4, 5, 6, 'ellipsis', 10]);
      expect(saleInvoiceNumber(42), 'INV-000042');
    });
  });

  // ------------------------------------------------------------ routes

  test('the sidebar link, Daily Closing’s ?date= and the Sales tab open the page', () async {
    expect(pageScreens.containsKey('/sales'), isTrue);
    final s = await sessionFor(FakeApi());
    final dated = salesScreenForHref('/sales?date=2026-10-03', s, company) as SalesScreen;
    expect(dated.initialDate, '2026-10-03');
    final focused = salesScreenForHref('/sales?saleId=2', s, company) as SalesScreen;
    expect(focused.focusSaleId, 2);
    final tab = pageFor(
        module: const AppModule(key: 'sales', label: 'Sales', icon: Icons.shopping_cart_outlined),
        company: company,
        session: s);
    expect(tab, isA<SalesScreen>());
  });

  // ------------------------------------------------------------ list

  group('Sales list', () {
    testWidgets('summary cards, cards with status, search, filters sheet, focus banner', (tester) async {
      final api = salesApi();
      await open(tester, await screen(api), size: phone);
      expect(find.text('GHC 575.00'), findsOneWidget, reason: 'Total Sales');
      expect(find.text('2 transactions'), findsOneWidget);
      expect(find.text('85'), findsOneWidget, reason: 'Total Quantity');
      expect(find.text('2 crates + 25 pieces'), findsOneWidget);
      expect(find.text('GHC 287.50'), findsOneWidget, reason: 'Average Sale');
      await see(tester, find.text('Partial'));
      expect(find.text('Paid'), findsWidgets);

      await tester.drag(_list, const Offset(0, 3000));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'kofi');
      await tester.pumpAndSettle();
      expect(find.text('1 transactions'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).first, '');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      expect(find.text('GHS'), findsOneWidget, reason: 'read-only currency');
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Apply')).onPressed, isNull,
          reason: 'Apply waits for a change');
      await tester.tap(find.text('Start date').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();
      expect(find.text('Filters applied — Sales list updated.'), findsOneWidget);
    });

    testWidgets('a ?saleId= link shows that sale only, with the way back', (tester) async {
      await open(tester, await screen(salesApi(), focus: 2), size: phone);
      expect(find.text('1 transactions'), findsOneWidget);
      expect(find.text('Show all sales'), findsOneWidget);
      await tester.tap(find.text('Show all sales'));
      await tester.pumpAndSettle();
      expect(find.text('2 transactions'), findsOneWidget);
    });

    testWidgets('table view, sort and the per-page select', (tester) async {
      await open(tester, await screen(salesApi()), size: phone);
      await tapSeen(tester, find.text('View table format'));
      expect(find.text('Table • Scroll → for more'), findsOneWidget);
      expect(find.text('75 (2c + 15p)'), findsOneWidget);
      await choose(tester, '10 / page', '5 / page');
      expect(find.text('Showing 1 to 2 of 2 records'), findsOneWidget);
    });
  });

  // ------------------------------------------------------------ add / edit

  group('Add Sale', () {
    testWidgets('eggs: crates and loose, every dropdown, main cash account, paid now records the payment', (tester) async {
      final api = salesApi();
      await open(tester, await screen(api), size: phone);
      await tester.tap(find.text('Add Sale'));
      await tester.pumpAndSettle();
      expect(find.text('Create New Sale'), findsOneWidget);
      expect(find.text('Main Cash Account (1200.50)'), findsOneWidget, reason: 'defaulted');
      expect(find.text('Old till (0.00)'), findsNothing, reason: 'inactive accounts are not offered');

      await choose(tester, 'Select product', 'Fresh Eggs');
      expect(find.text('Egg Quantity (Crates × 30 + Loose Eggs)'), findsOneWidget);
      await type(tester, 'Crates (30 eggs)', '2');
      await type(tester, 'Loose Eggs', '15');
      expect(find.text('Calculation: 2 crates × 30 + 15 loose = 75 eggs'), findsOneWidget);
      expect(find.text('In stock: 100 eggs'), findsOneWidget);
      await choose(tester, 'Select a customer', 'Kofi');
      await choose(tester, 'All flocks', 'Layers A (500 birds)');
      await type(tester, 'Unit Price Per Crate *', '30');
      expect(find.text('2 crates + 15 loose priced as 2.50 crates — loose eggs charged pro rata.'), findsOneWidget);
      await choose(tester, 'Select payment method', 'Mobile Money');
      await tapSeen(tester, find.text('Create Sale'));

      final body = api.lastBody('/api/Sale');
      expect(body['product'], 'Fresh Eggs');
      expect((body['quantity'], body['unitPrice'], body['totalAmount']), (75, 30, 75));
      expect((body['customerName'], body['flockId'], body['paymentMethod']), ('Kofi', 1, 'Mobile Money'));
      expect((body['paid'], body['poultryCashAccountId'], body['farmId'], body['userId']), (true, 5, 'farm-1', 'user-1'));
      final pay = api.lastBody('/api/Poultry/payments');
      expect((pay['saleId'], pay['amount'], pay['paymentMethod']), (99, 75, 'Mobile Money'));
    });

    testWidgets('other product and customer, override, pay later, a short stock needs Sell it anyway', (tester) async {
      final api = salesApi();
      await open(tester, await screen(api), size: phone);
      await tester.tap(find.text('Add Sale'));
      await tester.pumpAndSettle();
      await choose(tester, 'Select product', 'Other');
      await type(tester, 'Product *', 'Birds');
      await choose(tester, 'Select a customer', 'Other Customer');
      await type(tester, 'Customer Name *', 'Walk-in Yaw');
      await type(tester, 'Quantity *', '60');
      expect(find.text('Only 50 birds in stock — this sale is 10 more than you have.'), findsOneWidget);
      await type(tester, 'Unit Price *', '20');
      await type(tester, 'Override Amount', '1100');
      await choose(tester, 'Select payment method', 'Cash');
      await tapSeen(tester, find.text('Pay later (pending)'));
      await tapSeen(tester, find.text('Create Sale'));
      expect(api.writes, isEmpty, reason: 'refused until Sell it anyway');

      await tapSeen(tester, find.textContaining('Sell it anyway'));
      await tapSeen(tester, find.text('Create Sale'));
      final body = api.lastBody('/api/Sale');
      expect((body['product'], body['customerName'], body['totalAmount'], body['paid']), ('Birds', 'Walk-in Yaw', 1100, false));
      expect(api.writes.where((w) => w.url.path == '/api/Poultry/payments'), isEmpty, reason: 'pay later');
    });

    testWidgets('a closed flock cannot take a bird sale', (tester) async {
      await open(tester, await screen(salesApi()), size: phone);
      await tester.tap(find.text('Add Sale'));
      await tester.pumpAndSettle();
      await choose(tester, 'Select product', 'Chicken');
      await see(tester, find.text('All flocks'));
      await tester.tap(find.text('All flocks'));
      await tester.pumpAndSettle();
      final item = tester.widget<DropdownMenuItem<int?>>(find.ancestor(
          of: find.text('Broilers B (200 birds) · Closed').last, matching: find.byType(DropdownMenuItem<int?>)));
      expect(item.enabled, isFalse);
    });

    testWidgets('Edit: prefilled, Paid / Pending (owed), None account, PUT', (tester) async {
      final api = salesApi();
      await open(tester, await screen(api), size: phone);
      await tapSeen(tester, find.text('Edit'));
      expect(find.text('Edit Sale'), findsOneWidget);
      expect(find.text('Egg Size (optional)'), findsNothing, reason: 'the web edit dialog has none');
      await see(tester, find.text('Pending (owed)'));
      expect(find.text('Pending (owed)'), findsOneWidget);
      await choose(tester, 'Main Cash Account (1200.50)', 'None (no cash movement)');
      await tapSeen(tester, find.text('Update Sale'));
      final body = api.lastBody('/api/Sale/1', 'PUT');
      expect((body['quantity'], body['totalAmount'], body['customerName'], body['poultryCashAccountId']), (75, 75, 'Ama', null));
    });
  });

  // ------------------------------------------------------------ row actions

  group('row actions', () {
    testWidgets('Pay: method dropdown, amount defaults to what is owed', (tester) async {
      final api = salesApi();
      await open(tester, await screen(api), size: phone);
      await tapSeen(tester, find.text('Pay'));
      expect(find.text('#2 · Kofi'), findsOneWidget);
      expect(find.text('300.00'), findsWidgets);
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Cash')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cheque').last);
      await tester.pumpAndSettle();
      await enter(tester, 'Note', 'part');
      await tester.tap(find.widgetWithText(FilledButton, 'Record payment'));
      await tester.pumpAndSettle();
      final body = api.lastBody('/api/Poultry/payments');
      expect((body['saleId'], body['amount'], body['paymentMethod'], body['note']), (2, 300.0, 'Cheque', 'part'));
      expect(find.text('Payment recorded — 300.00 received for sale #2.'), findsOneWidget);
    });

    testWidgets('Payments: history, allocation, reverse needs a reason', (tester) async {
      final api = salesApi()
        ..gets['/api/Poultry/customer-payments'] = [
          {'paymentId': 'abcd1234-ef', 'paymentNumber': 'PAY-0007', 'paymentDate': '2026-10-03T10:00:00', 'totalAmount': 200, 'paymentMethod': 'Cash', 'allocationCount': 1, 'sourceType': 'SaleEntry', 'status': 'Posted'},
        ]
        ..gets['/api/Poultry/customer-payments/abcd1234-ef'] = {
          'payment': {},
          'allocations': [
            {'allocationId': 1, 'documentId': 2, 'reference': 'S2', 'label': 'Chicken', 'documentDate': '2026-10-03', 'documentTotal': 500, 'amountApplied': 200, 'balanceBefore': 500, 'balanceAfter': 300},
          ],
        };
      await open(tester, await screen(api), size: phone);
      await tapSeen(tester, find.text('Payments'));
      expect(find.text('Payment history'), findsOneWidget);
      expect(find.text('PAY-0007'), findsOneWidget);
      expect(find.text('Source: Sale'), findsOneWidget);
      expect(api.requests.lastWhere((r) => r.url.path == '/api/Poultry/customer-payments').url.queryParameters,
          {'farmId': 'farm-1', 'saleId': '1'});
      await tester.tap(find.text('GHC 200.00').last);
      await tester.pumpAndSettle();
      expect(find.text('Before GHC 500.00'), findsOneWidget);

      await tester.tap(find.text('Reverse'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reverse payment'));
      await tester.pumpAndSettle();
      expect(api.writes, isEmpty, reason: 'a reason is required');
      await enter(tester, 'Why is this being reversed?', 'entered twice');
      await tester.tap(find.text('Reverse payment'));
      await tester.pumpAndSettle();
      final body = api.lastBody('/api/Poultry/customer-payments/abcd1234-ef/reverse');
      expect((body['reason'], body['farmId'], body['reversedBy']), ('entered twice', 'farm-1', 'user-1'));
    });

    testWidgets('Invoice prints; Delete confirms and sends userId and farmId', (tester) async {
      final shared = <String>[];
      ReportExport.sharer = (name, bytes, mime, subject) async => shared.add(name);
      final api = salesApi();
      await open(tester, await screen(api), size: phone);
      await tapSeen(tester, find.text('Invoice'));
      expect(find.text('INV-000001'), findsOneWidget);
      expect(find.text('PAID IN FULL'), findsOneWidget);
      await tester.tap(find.text('Print invoice'));
      await tester.pumpAndSettle();
      expect(shared, ['INV-000001.pdf']);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tapSeen(tester, find.text('Delete'));
      expect(find.text('Delete Sale'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      final del = api.writes.lastWhere((w) => w.method == 'DELETE');
      expect(del.url.path, '/api/Sale/1');
      expect((del.url.queryParameters['userId'], del.url.queryParameters['farmId']), ('user-1', 'farm-1'));
    });

    testWidgets('PDF shares the report; Email sends it to the signed-in address', (tester) async {
      final shared = <String>[];
      ReportExport.sharer = (name, bytes, mime, subject) async => shared.add(name);
      final api = salesApi();
      final s = await sessionFor(api);
      await s.tokens.saveUser(username: 'owner@farm.com');
      await open(tester, SalesScreen(session: s, company: company), size: phone);
      await tester.tap(find.text('PDF'));
      await tester.pumpAndSettle();
      expect(shared.single, startsWith('sales-'));
      await tester.tap(find.text('Email'));
      await tester.pumpAndSettle();
      final mail = utf8.decode(api.writes.lastWhere((w) => w.url.path == '/api/Email/Report').bodyBytes, allowMalformed: true);
      expect(mail, contains('owner@farm.com'));
      expect(mail, contains('Sales Report'));
      expect(find.text('Report emailed — Sent to owner@farm.com.'), findsOneWidget);
    });
  });

  test('company type guard: the Sales tab is native for Poultry only', () async {
    final s = await sessionFor(FakeApi());
    final water = Company(farmId: 'w', name: 'W', type: CompanyType.water);
    expect(
        pageFor(module: const AppModule(key: 'sales', label: 'Sales', icon: Icons.shopping_cart_outlined), company: water, session: s),
        isNot(isA<SalesScreen>()));
  });

  test('invoice number helper is exported for the dialog', () {
    expect(SaleInvoiceScreen.jsQty(75), '75');
  });
}
