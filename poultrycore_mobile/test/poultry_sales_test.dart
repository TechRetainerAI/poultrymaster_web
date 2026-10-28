// Poultry → Sales → Sales: the page's rules, then the whole page driven at
// phone width against a fake API — every dropdown picked, every form saved,
// every request body checked. Covers the sale-lines redesign (358/360) and
// reversal / correction / customer credit (351).

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
    'customerName': 'Ama', 'customerId': 1, 'flockId': 1, 'poultryCashAccountId': 5, 'status': 'Posted', 'size': null,
  },
  {
    'saleId': 2, 'saleDate': '2026-10-03T00:00:00', 'createdDate': '2026-10-03T09:00:00', 'product': 'Chicken',
    'quantity': 10, 'unitPrice': 50, 'totalAmount': 500, 'amountPaid': 200, 'paid': false, 'paymentMethod': 'Mobile Money',
    'customerName': 'Kofi', 'customerId': 2, 'flockId': 2, 'saleDescription': 'Market day', 'status': 'Posted',
  },
  {
    'saleId': 3, 'saleDate': '2026-10-02T00:00:00', 'product': 'Fresh Eggs', 'quantity': 60, 'unitPrice': 30, 'totalAmount': 60,
    'amountPaid': 0, 'paid': false, 'paymentMethod': 'Cash', 'customerName': 'Ama', 'customerId': 1, 'flockId': 1,
    'status': 'Reversed', 'reversalReason': 'Wrong price',
  },
  {
    'saleId': 4, 'saleDate': '2026-10-04T00:00:00', 'product': 'Fresh Eggs', 'quantity': 90, 'unitPrice': 33.33, 'totalAmount': 100,
    'amountPaid': 0, 'paid': false, 'paymentMethod': 'Cash', 'customerName': 'Ama', 'customerId': 1, 'flockId': 1,
    'status': 'Posted', 'saleGroupNo': 'SG-00004', 'lineCount': 2,
    'lines': [
      {'saleLineId': 41, 'lineNo': 1, 'product': 'Fresh Eggs', 'eggProductId': 11, 'quantity': 60, 'unitPrice': 40, 'totalAmount': 80},
      {'saleLineId': 42, 'lineNo': 2, 'product': 'Fresh Eggs', 'eggProductId': null, 'quantity': 30, 'unitPrice': 20, 'totalAmount': 20},
    ],
  },
];

final eggClasses = [
  {'poultryProductId': 10, 'name': 'Unsorted', 'classKind': 'Unsorted', 'isActive': true, 'onHand': 200, 'pricePerCrate': 30},
  {'poultryProductId': 11, 'name': 'Large', 'classKind': 'Size', 'isActive': true, 'onHand': 90, 'pricePerCrate': 40},
  {'poultryProductId': 12, 'name': 'Jumbo', 'classKind': 'Size', 'isActive': true, 'onHand': 30, 'pricePerCrate': 50},
];

FakeApi salesApi({bool sizes = false}) {
  final a = FakeApi()
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
      {'poultryProductId': 11, 'name': 'Eggs - Large', 'stockOnHand': 90},
    ]
    ..writeAnswers['/api/Sale'] = {'saleId': 99};
  if (sizes) a.gets['/api/Poultry/egg-sorting/classes'] = eggClasses;
  return a;
}

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

/// The field whose label (or caption) is the [index]th [label] on the page —
/// the Items lines repeat their labels.
Future<void> typeAt(WidgetTester tester, String label, int index, String text) async {
  await see(tester, find.text(label).at(index));
  final field = find.descendant(
    of: find.ancestor(of: find.text(label).at(index), matching: find.byType(Column)).first,
    matching: find.byType(TextFormField),
  );
  await tester.enterText(field.first, text);
  await tester.pump();
}

/// The bottom bar's button (pinned outside the scrolling form).
Future<void> tapPinned(WidgetTester tester, String textStart) async {
  ScaffoldMessenger.of(tester.element(find.byType(Scaffold).last)).removeCurrentSnackBar();
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining(textStart).last);
  await tester.pumpAndSettle();
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
      f.first.product = '';
      expect(f.validate(available: null, stockUnits: 'units'), 'Choose what was sold (eggs, chicken, manure, or other).');
      f.first
        ..product = 'Fresh Eggs'
        ..crates = 5
        ..unitPrice = 30;
      f
        ..customerName = 'Ama'
        ..paymentMethod = 'Cash';
      expect(f.validate(available: 100, stockUnits: 'eggs'),
          'Only 100 eggs in stock — this sale is 50 more. Lower the quantity, or tick "Sell it anyway" to record it regardless.');
      f.overrideStock = true;
      expect(f.validate(available: 100, stockUnits: 'eggs'), isNull);
      f
        ..partPayment = true
        ..partPaidAmount = 150;
      expect(f.validatePart(), 'That covers the whole sale. Choose Paid now instead.');
    });

    test('status, owed, rows, filters', () {
      expect(paymentStatusOf(sales[0]), 'Paid');
      expect(paymentStatusOf(sales[1]), 'Partial');
      expect(paymentStatusOf({'totalAmount': 10, 'paid': false}), 'Pending');
      expect(saleOwed(sales[1]), 300);
      expect(pageNumbers(5, 10), [1, 'ellipsis', 4, 5, 6, 'ellipsis', 10]);
      expect(saleInvoiceNumber(42), 'INV-000042');
      final rows = toSaleRows([
        {...sales[0], 'lines': [{'lineNo': 1}]},
        sales[3],
      ]);
      expect(rows[0]['lines'], isNull, reason: 'one line is not a multi-line sale');
      expect(saleLabel(rows[1]), 'SG-00004');
      expect(matchesStatusFilter(sales[2], 'Pending', 'Active'), isFalse);
      expect(matchesStatusFilter(sales[2], 'Pending', 'Reversed'), isTrue);
      expect(matchesStatusFilter(sales[2], 'Pending', 'Pending'), isFalse, reason: 'a reversed sale is never Pending');
      expect(lineSummary(eggClasses, multiLines(sales[3])), 'Large 2c · Unsorted 1c');
      expect(saleLineQuantityLabel({'product': 'Fresh Eggs', 'quantity': 305}), '10 crates + 5 pcs (305 eggs)');
    });

    test('an override is shared across the lines; the last takes the rounding', () {
      expect(scaleLineTotals([80, 50], 200), [123.08, 76.92]);
      expect(scaleLineTotals([80, 50], null), [80, 50]);
    });

    test('reversal: a refused choice falls back to the default; credit and cash out', () {
      final payments = [
        {'key': 'g1', 'allocated': 50, 'allowed': ['KeepAsCredit', 'ReversePayment'], 'default': 'KeepAsCredit'},
        {'key': 'AT-SALE', 'allocated': 20, 'allowed': ['KeepAsCredit'], 'default': 'KeepAsCredit'},
      ];
      final h = {'g1': 'ReversePayment', 'AT-SALE': 'ReversePayment'};
      expect(effectiveAction(payments[1], h), 'KeepAsCredit');
      final o = reversalOutcome(payments, h);
      expect((o.creditCreated, o.cashOut), (20, 50));
      expect(restoreLabel({'restoreQuantity': 300, 'restoreUnit': 'eggs', 'restoreProductName': 'Large'}), '300 eggs (Large)');
      expect(restoreLabel({'restoreQuantity': 10, 'restoreUnit': 'birds', 'restoreProductName': 'Birds'}), '10 birds');
      expect(paymentSourceLabel({'source': 'SaleEntry', 'saleGenerated': true}), 'Paid with this sale');
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
    testWidgets('summary leaves out the reversed sale; multi-line and reversed rows; status filter', (tester) async {
      final api = salesApi(sizes: true);
      await open(tester, await screen(api), size: phone);
      expect(api.requests.lastWhere((r) => r.url.path == '/api/Sale').url.queryParameters['includeReversed'], 'true');
      expect(find.text('GHC 675.00'), findsOneWidget, reason: 'Total Sales, reversed sale not totalled');
      expect(find.text('4 transactions'), findsOneWidget);
      expect(find.text('175'), findsOneWidget, reason: 'Total Quantity');
      expect(find.text('5 crates + 25 pieces'), findsOneWidget);
      await see(tester, find.text('SG-00004'));
      expect(find.text('Large 2c · Unsorted 1c'), findsOneWidget);
      await see(tester, find.text('Reversed'));
      expect(find.text('Edit & repost'), findsOneWidget);

      await tester.drag(_list, const Offset(0, 4000));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'kofi');
      await tester.pumpAndSettle();
      expect(find.text('1 transactions'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, '');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      expect(find.text('GHS'), findsOneWidget, reason: 'read-only currency');
      await pick(tester, 'All', 'Reversed');
      await tester.tapAt(const Offset(180, 40));
      await tester.pumpAndSettle();
      expect(find.text('1 transactions'), findsOneWidget);
      expect(find.text('GHC 0.00'), findsWidgets, reason: 'a reversed sale is listed, not totalled');
    });

    testWidgets('a ?saleId= link shows that sale only, with the way back', (tester) async {
      await open(tester, await screen(salesApi(), focus: 2), size: phone);
      expect(find.text('1 transactions'), findsOneWidget);
      await tester.tap(find.text('Show all sales'));
      await tester.pumpAndSettle();
      expect(find.text('4 transactions'), findsOneWidget);
    });

    testWidgets('table view, sort and the per-page select', (tester) async {
      await open(tester, await screen(salesApi(sizes: true)), size: phone);
      await tapSeen(tester, find.text('View table format'));
      expect(find.text('Table • Scroll → for more'), findsOneWidget);
      expect(find.text('75 (2c + 15p)'), findsOneWidget);
      expect(find.text('2 egg lines'), findsOneWidget);
      await choose(tester, '10 / page', '5 / page');
      expect(find.text('Showing 1 to 4 of 4 records'), findsOneWidget);
    });
  });

  // ------------------------------------------------------------ new sale

  group('New sale', () {
    testWidgets('one egg line: crates and loose, the main cash account, paid now records the payment', (tester) async {
      final api = salesApi();
      await open(tester, await screen(api), size: phone);
      await tester.tap(find.text('Add Sale'));
      await tester.pumpAndSettle();
      expect(find.text('New sale'), findsOneWidget);
      await see(tester, find.text('Main Cash Account (1200.50)'));
      expect(find.text('Main Cash Account (1200.50)'), findsOneWidget, reason: 'defaulted');
      expect(find.text('Old till (0.00)'), findsNothing, reason: 'inactive accounts are not offered');
      expect(find.text('Fresh Eggs'), findsOneWidget, reason: 'most sales are eggs');

      await choose(tester, 'Select a customer', 'Kofi');
      await choose(tester, 'All flocks', 'Layers A (500 birds)');
      await type(tester, 'crates (30)', '2');
      await type(tester, 'loose eggs', '15');
      expect(find.text('2 crates + 15 loose = 75 eggs — loose eggs charged pro rata'), findsOneWidget);
      expect(find.text('In stock: 100 eggs'), findsOneWidget);
      await type(tester, 'Unit price', '30');
      expect(find.text('Record sale · GHC 75.00'), findsOneWidget);
      await choose(tester, 'Select payment method', 'Mobile Money');
      await tapPinned(tester, 'Record sale');

      final body = api.lastBody('/api/Sale');
      expect(body['product'], 'Fresh Eggs');
      expect((body['quantity'], body['unitPrice'], body['totalAmount'], body['eggProductId']), (75, 30, 75, 0));
      expect((body['customerName'], body['flockId'], body['paymentMethod']), ('Kofi', 1, 'Mobile Money'));
      expect((body['paid'], body['poultryCashAccountId'], body['farmId'], body['userId']), (true, 5, 'farm-1', 'user-1'));
      final pay = api.lastBody('/api/Poultry/payments');
      expect((pay['saleId'], pay['amount'], pay['paymentMethod']), (99, 75, 'Mobile Money'));
      expect(find.text('Success — Sale created successfully'), findsOneWidget);
    });

    testWidgets('egg sizes: two lines, class prices, an override shared, a part payment — one Sale/group post', (tester) async {
      final api = salesApi(sizes: true)
        ..writeAnswers['/api/Sale/group'] = {'saleGroupNo': 'SG-00009', 'saleId': 99, 'saleIds': [99], 'totalAmount': 200, 'lineCount': 2, 'saleCount': 1};
      await open(tester, await screen(api), size: phone);
      await tester.tap(find.text('Add Sale'));
      await tester.pumpAndSettle();
      await choose(tester, 'Select a customer', 'Kofi');
      await choose(tester, 'Unsorted / General · stock 200', 'Large · stock 90');
      await typeAt(tester, 'crates (30)', 0, '2');
      await tapSeen(tester, find.text('Add line'));
      expect(find.text('Jumbo · stock 30'), findsOneWidget, reason: 'the next unused size is offered');
      await typeAt(tester, 'crates (30)', 1, '1');
      expect(find.text('In stock: 30 eggs'), findsOneWidget);
      expect(find.text('Record sale · GHC 130.00'), findsOneWidget, reason: '2 × 40 + 1 × 50');

      await type(tester, 'Override Total Sale Amount', '200');
      expect(find.text('The override is shared across the lines in proportion to their amounts.'), findsOneWidget);
      expect(find.text('calculated GHC 130.00'), findsOneWidget);
      await tapSeen(tester, find.text('Part payment'));
      await type(tester, 'Amount paid now *', '50');
      expect(find.text('Still owed: GHC 150.00', findRichText: true), findsOneWidget);
      await choose(tester, 'Select payment method', 'Cash');
      await tapPinned(tester, 'Record sale');

      final body = api.lastBody('/api/Sale/group');
      expect((body['customerName'], body['paid'], body['amountPaidNow'], body['poultryCashAccountId']), ('Kofi', false, 50, 5));
      expect(body['requestKey'], isNotEmpty);
      expect(body['lines'], [
        {'product': 'Fresh Eggs', 'eggProductId': 11, 'quantity': 60, 'unitPrice': 40, 'totalAmount': 123.08},
        {'product': 'Fresh Eggs', 'eggProductId': 12, 'quantity': 30, 'unitPrice': 50, 'totalAmount': 76.92},
      ]);
      expect(api.writes.where((w) => w.url.path == '/api/Poultry/payments'), isEmpty, reason: 'the group posts its own payment');
      expect(find.text('Sale SG-00009 created — 2 lines, one sale. Paid GHC 50.00. Owed GHC 150.00.'), findsOneWidget);
    });

    testWidgets('other product and customer, override, pay later, a short stock needs Sell it anyway', (tester) async {
      final api = salesApi();
      await open(tester, await screen(api), size: phone);
      await tester.tap(find.text('Add Sale'));
      await tester.pumpAndSettle();
      await choose(tester, 'Fresh Eggs', 'Other');
      await tester.enterText(find.widgetWithText(TextFormField, 'Product name'), 'Birds');
      await tester.pumpAndSettle();
      await choose(tester, 'Select a customer', 'Other Customer');
      await tester.enterText(find.widgetWithText(TextFormField, 'Enter other customer name'), 'Walk-in Yaw');
      await tester.pumpAndSettle();
      await type(tester, 'Quantity', '60');
      expect(find.text('Only 50 birds in stock — this sale is 10 more than you have.'), findsOneWidget);
      await type(tester, 'Unit price', '20');
      await type(tester, 'Override Total Sale Amount', '1100');
      await choose(tester, 'Select payment method', 'Cash');
      await tapSeen(tester, find.text('Pay later'));
      await tapPinned(tester, 'Record sale');
      expect(api.writes, isEmpty, reason: 'refused until Sell it anyway');

      await tapSeen(tester, find.textContaining('Sell it anyway'));
      await tapPinned(tester, 'Record sale');
      final body = api.lastBody('/api/Sale');
      expect((body['product'], body['customerName'], body['totalAmount'], body['paid']), ('Birds', 'Walk-in Yaw', 1100, false));
      expect(api.writes.where((w) => w.url.path == '/api/Poultry/payments'), isEmpty, reason: 'pay later');
    });

    testWidgets('a closed flock cannot take a bird sale', (tester) async {
      await open(tester, await screen(salesApi()), size: phone);
      await tester.tap(find.text('Add Sale'));
      await tester.pumpAndSettle();
      await choose(tester, 'Fresh Eggs', 'Chicken');
      await see(tester, find.text('All flocks'));
      await tester.tap(find.text('All flocks'));
      await tester.pumpAndSettle();
      final item = tester.widget<DropdownMenuItem<int?>>(find.ancestor(
          of: find.text('Broilers B (200 birds) · Closed').last, matching: find.byType(DropdownMenuItem<int?>)));
      expect(item.enabled, isFalse);
    });

    testWidgets('Pay later: no payment method or cash account, stored as Pay later', (tester) async {
      final api = salesApi();
      await open(tester, await screen(api), size: phone);
      await tester.tap(find.text('Add Sale'));
      await tester.pumpAndSettle();
      await choose(tester, 'Fresh Eggs', 'Chicken');
      await choose(tester, 'Select a customer', 'Ama');
      await type(tester, 'Quantity', '2');
      await type(tester, 'Unit price', '20');
      await tapSeen(tester, find.text('Pay later'));
      expect(find.text('Payment method *'), findsNothing);
      expect(find.text('Receive into cash account *'), findsNothing);
      expect(find.textContaining('No money is received now'), findsOneWidget);
      await tapPinned(tester, 'Record sale');
      final body = api.lastBody('/api/Sale');
      expect((body['paymentMethod'], body['paid']), ('Pay later', false));
    });

    testWidgets('Use customer credit: part from credit, the rest paid now, one group post', (tester) async {
      final api = salesApi()..gets['/api/Poultry/customer-payments/credit/1'] = [{'unapplied': 30}];
      await open(tester, await screen(api), size: phone);
      await tester.tap(find.text('Add Sale'));
      await tester.pumpAndSettle();
      await choose(tester, 'Fresh Eggs', 'Chicken');
      await choose(tester, 'Select a customer', 'Ama');
      expect(find.text('Available customer credit: GHC 30.00'), findsOneWidget);
      await type(tester, 'Quantity', '2');
      await type(tester, 'Unit price', '20');
      await tapSeen(tester, find.text('Use customer credit'));
      expect(find.text('Rest to pay: GHC 10.00', findRichText: true), findsOneWidget);
      expect(find.text('The rest'), findsOneWidget);
      await choose(tester, 'Select payment method', 'Cash');
      await tapPinned(tester, 'Record sale');
      final body = api.lastBody('/api/Sale/group');
      expect((body['customerCreditAmount'], body['paid'], body['amountPaidNow'], body['paymentMethod'], body['poultryCashAccountId']),
          (30, false, 10, 'Cash', 5));
    });

    testWidgets('Batch narrows the flocks; byproducts follow the company settings and their price', (tester) async {
      final api = salesApi()
        ..gets['/api/Flock'] = [
          {'flockId': 1, 'name': 'Layers A', 'quantity': 500, 'batchId': 3},
          {'flockId': 2, 'name': 'Broilers B', 'quantity': 200, 'batchId': 4},
        ]
        ..gets['/api/MainFlockBatch'] = [
          {'batchId': 3, 'batchName': 'Batch Three'},
          {'batchId': 4, 'batchName': 'Batch Four'},
        ]
        ..gets['/api/Poultry/stock/byproduct-settings'] = {'brokenEggsInSales': false, 'deadBirdsInSales': true}
        ..gets['/api/Poultry/products'] = [
          {'poultryProductId': 1, 'name': 'Eggs', 'isRawEggProduct': true, 'stockOnHand': 100},
          {'poultryProductId': 7, 'name': 'Dead Birds', 'unit': 'bird', 'unitPrice': 5, 'stockOnHand': 7},
        ];
      await open(tester, await screen(api), size: phone);
      await tester.tap(find.text('Add Sale'));
      await tester.pumpAndSettle();
      await choose(tester, 'All batches', 'Batch Three');
      await see(tester, find.text('All flocks'));
      await tester.tap(find.text('All flocks'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Broilers B'), findsNothing, reason: 'another batch');
      await tester.tap(find.text('Layers A (500 birds)').last);
      await tester.pumpAndSettle();

      await see(tester, find.text('Fresh Eggs'));
      await tester.tap(find.text('Fresh Eggs'));
      await tester.pumpAndSettle();
      expect(find.text('Broken Eggs'), findsNothing, reason: 'turned off for this company');
      await tester.tap(find.text('Dead Birds').last);
      await tester.pumpAndSettle();
      expect(find.text('In stock: 7 birds', findRichText: true), findsOneWidget);
      await choose(tester, 'Select a customer', 'Ama');
      await type(tester, 'Quantity', '2');
      await choose(tester, 'Select payment method', 'Cash');
      await tapPinned(tester, 'Record sale');
      final body = api.lastBody('/api/Sale');
      expect((body['product'], body['unitPrice'], body['totalAmount'], body['batchId'], body['flockId']), ('Dead Birds', 5, 10, 3, 1));
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

    testWidgets('Pay → Use customer credit: an allocation, no cash', (tester) async {
      final api = salesApi()..gets['/api/Poultry/customer-payments/credit/2'] = [{'unapplied': 120}];
      await open(tester, await screen(api), size: phone);
      await tapSeen(tester, find.text('Pay'));
      await tester.tap(find.text('Use customer credit'));
      await tester.pumpAndSettle();
      expect(find.text('Apply customer credit'), findsOneWidget);
      expect(find.text('GHC 120.00'), findsOneWidget, reason: 'available credit');
      await tester.tap(find.ancestor(of: find.textContaining('Apply credit'), matching: find.byType(FilledButton)).first);
      await tester.pumpAndSettle();
      final body = api.lastBody('/api/Poultry/customer-payments/apply-credit');
      expect((body['customerId'], body['saleId'], body['amount'], body['farmId']), (2, 2, 120, 'farm-1'));
      expect(find.text('Credit applied — GHC 120.00 of customer credit settled #2. No new cash was recorded.'), findsOneWidget);
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
      expect(api.requests.lastWhere((r) => r.url.path == '/api/Poultry/customer-payments').url.queryParameters,
          {'farmId': 'farm-1', 'saleId': '1'});
      await tester.tap(find.text('GHC 200.00').last);
      await tester.pumpAndSettle();
      expect(find.text('Before GHC 500.00'), findsOneWidget);
      await tester.tap(find.text('Reverse').last);
      await tester.pumpAndSettle();
      // Its own window, with the reason from the list.
      expect(find.text('Reverse PAY-0007?'), findsOneWidget);
      final confirm = find.ancestor(of: find.textContaining('Reverse payment'), matching: find.byType(FilledButton)).first;
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull, reason: 'a reason is required');
      await choose(tester, 'Select a reason', 'Duplicate entry');
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      final body = api.lastBody('/api/Poultry/customer-payments/abcd1234-ef/reverse');
      expect((body['reason'], body['farmId'], body['reversedBy']), ('Duplicate entry', 'farm-1', 'user-1'));
    });

    testWidgets('Invoice: a multi-line sale prints its lines under its SG number', (tester) async {
      final shared = <String>[];
      ReportExport.sharer = (name, bytes, mime, subject) async => shared.add(name);
      await open(tester, await screen(salesApi(sizes: true)), size: phone);
      await see(tester, find.text('SG-00004'));
      final card = find.ancestor(of: find.text('SG-00004'), matching: find.byKey(const ValueKey('sale-4')));
      await tapSeen(tester, find.descendant(of: card, matching: find.text('Invoice')));
      expect(find.text('SG-00004'), findsOneWidget);
      expect(find.text('Fresh Eggs — Large'), findsOneWidget);
      expect(find.text('Fresh Eggs — Unsorted'), findsOneWidget);
      await tester.tap(find.text('Print invoice'));
      await tester.pumpAndSettle();
      expect(shared, ['SG-00004.pdf']);
    });

    testWidgets('View: read-only, the note is the only thing saved', (tester) async {
      final api = salesApi();
      await open(tester, await screen(api), size: phone);
      await tapSeen(tester, find.text('View'));
      expect(find.text('Sale #1'), findsWidgets);
      expect(find.text('Posted'), findsOneWidget);
      expect(find.text('Save note'), findsNothing, reason: 'nothing changed yet');
      await tester.enterText(find.widgetWithText(TextFormField, "Internal note (does not change the sale's money or stock)"), 'paid at gate');
      await tester.pumpAndSettle();
      await tapSeen(tester, find.text('Save note'));
      final body = api.lastBody('/api/Sale/1', 'PUT');
      expect((body['saleDescription'], body['quantity'], body['totalAmount'], body['eggProductId']), ('paid at gate', 75, 75, 0));
      expect(find.text('Note saved'), findsOneWidget);
    });

    testWidgets('Reverse: the server preview, reverse the payment, a reason from the list', (tester) async {
      final api = salesApi()
        ..gets['/api/Sale/1/reversal-preview'] = {
          'found': true, 'saleId': 1, 'customerName': 'Ama', 'total': 75, 'paid': 75, 'outstanding': 0, 'fingerprint': 'fp1',
          'lines': [{'restoreQuantity': 75, 'restoreUnit': 'eggs', 'restoreProductName': 'Unsorted'}],
          'payments': [
            {'key': 'g1', 'paymentNumbers': 'PAY-0001', 'source': 'SaleEntry', 'saleGenerated': true, 'allocated': 75, 'paymentTotal': 75,
              'paymentMethod': 'Cash', 'cashAccountName': 'Main Cash Account', 'allowed': ['KeepAsCredit', 'ReversePayment'], 'default': 'KeepAsCredit'},
          ],
          'blockers': [],
        }
        ..writeAnswers['/api/Sale/1/reverse'] = {'salereversalid': 5, 'reversal': {'creditCreated': 0, 'cashReversed': 75}};
      await open(tester, await screen(api), size: phone);
      await tapSeen(tester, find.text('Reverse'));
      expect(find.text('Reverse sale #1?'), findsWidgets);
      expect(find.text('Put back 75 eggs (Unsorted) — exactly what was sold'), findsOneWidget);
      expect(find.text('Paid with this sale'), findsNothing, reason: 'shown inline with the number');
      await tapSeen(tester, find.text('Reverse the payment'));
      expect(find.text('GHC 75.00'), findsWidgets);
      final confirm = find.ancestor(of: find.textContaining('Reverse sale'), matching: find.byType(FilledButton)).first;
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull, reason: 'a reason is needed');
      await choose(tester, 'Choose a reason', 'Other');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull, reason: 'Other needs a note');
      await tester.enterText(find.widgetWithText(TextFormField, 'Say what happened (needed for Other)'), 'customer returned eggs');
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      final body = api.lastBody('/api/Sale/1/reverse');
      expect((body['reasonCode'], body['reason'], body['expectedFingerprint']), ('Other', 'customer returned eggs', 'fp1'));
      expect(body['paymentHandling'], {'g1': 'ReversePayment'});
      expect(body['idempotencyKey'], isNotEmpty);
      expect(find.text('Sale #1 reversed — Revenue and stock undone. GHC 75.00 paid back out of cash.'), findsOneWidget);
    });

    testWidgets('Correct sale: reversed, re-entered linked to it, the kept credit used in the form', (tester) async {
      final api = salesApi()
        ..gets['/api/Sale/2/reversal-preview'] = {
          'found': true, 'saleId': 2, 'customerName': 'Kofi', 'total': 500, 'paid': 200, 'outstanding': 300, 'fingerprint': 'fp2',
          'lines': [], 'blockers': [],
          'payments': [{'key': 'g2', 'allocated': 200, 'allowed': ['KeepAsCredit'], 'default': 'KeepAsCredit', 'reverseUnavailableReason': 'Received on Customer Balances.'}],
        }
        ..writeAnswers['/api/Sale/2/reverse'] = {'reversal': {'creditCreated': 200, 'cashReversed': 0}}
        ..gets['/api/Poultry/customer-payments/credit/2'] = [{'unapplied': 200}];
      await open(tester, await screen(api), size: phone);
      final card = find.byKey(const ValueKey('sale-2'));
      await see(tester, card);
      await tapSeen(tester, find.descendant(of: card, matching: find.text('View')));
      await tapSeen(tester, find.text('Correct sale'));
      await see(tester, find.textContaining('Received on Customer Balances.'));
      expect(find.textContaining('Received on Customer Balances.'), findsOneWidget);
      await choose(tester, 'Choose a reason', 'Wrong price');
      await tester.tap(find.ancestor(of: find.textContaining('Reverse and correct'), matching: find.byType(FilledButton)).first);
      await tester.pumpAndSettle();
      expect(find.text('Corrected sale (replaces #2)'), findsOneWidget);
      expect(find.textContaining('GHC 200.00 from the reversed sale is held as customer credit.'), findsOneWidget);
      await see(tester, find.text('Chicken'));
      expect(find.text('Chicken'), findsOneWidget, reason: 'pre-filled');
      await type(tester, 'Unit price', '45');
      await tapPinned(tester, 'Record sale');
      // The money kept at the reversal pays the corrected sale from the form
      // (Use customer credit), in the same Sale/group post; nothing is offered after.
      final body = api.lastBody('/api/Sale/group');
      expect((body['correctsSaleId'], body['customerCreditAmount'], body['paid'], body['amountPaidNow'], body['paymentMethod']),
          (2, 200, false, null, 'Pay later'));
      final line = (body['lines'] as List).single as Map;
      expect((line['product'], line['quantity'], line['totalAmount']), ('Chicken', 10, 450));
      expect(find.text('Apply customer credit'), findsNothing);
    });

    testWidgets('Edit & repost a reversed sale opens it pre-filled', (tester) async {
      final api = salesApi()..gets['/api/Sale/3/reversal'] = {'reversalNumber': 'SR-0001', 'creditCreated': 0, 'correctionSaleId': null};
      await open(tester, await screen(api), size: phone);
      await tapSeen(tester, find.text('Edit & repost'));
      expect(find.text('Corrected sale (replaces #3)'), findsOneWidget);
      expect(find.text('Record sale · GHC 60.00'), findsOneWidget);
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
