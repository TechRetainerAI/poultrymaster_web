// Generic → Sales at phone width (lib/nav/generic-nav-config.ts "Sales"):
// Sales (list, New sale, the sale), Customers (list, dialog, ledger) and
// Payments, each against a fake API.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/generic/generic_customer_payments_screen.dart';
import 'package:poultrycore_mobile/pages/generic/generic_customers_screen.dart';
import 'package:poultrycore_mobile/pages/generic/generic_kit.dart';
import 'package:poultrycore_mobile/pages/generic/generic_sales_screen.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart' show pageScreens;
import 'package:poultrycore_mobile/pages/web_nav.dart';

import 'support/harness.dart';

final generic = Company(farmId: 'g1', name: 'Kofi Gym', type: CompanyType.generic, role: 'Admin');
const base = '/api/generic-company/g1';

/// GHS with the no-break space the number formatter writes.
String ghs(String n) => 'GHS $n';

final ama = <String, Object?>{
  'genericCustomerId': 1, 'customerName': 'Ama Mensah', 'customerType': 'Individual', 'phoneNumber': '0244111222',
  'location': 'Osu', 'creditLimit': 100, 'paymentTermsDays': 7, 'openingBalance': 0, 'currentBalance': 150, 'isActive': true,
};
final kojo = <String, Object?>{
  'genericCustomerId': 2, 'customerName': 'Kojo Ltd', 'customerType': 'Business', 'creditLimit': 0, 'paymentTermsDays': 0,
  'openingBalance': 0, 'currentBalance': 40, 'isActive': true,
};

final sale = <String, Object?>{
  'genericSaleId': 12, 'saleDate': '2026-11-02T00:00:00', 'customerName': 'Ama Mensah', 'salesType': 'CustomerSale',
  'subtotalAmount': 100, 'discountAmount': 5, 'taxAmount': 0, 'totalAmount': 95, 'amountPaid': 50, 'balance': 45,
  'paymentMethod': 'MoMo', 'paymentStatus': 'PartiallyPaid', 'status': 'Draft', 'receiptNumber': 'R-9', 'notes': 'Deliver Friday',
  'items': [
    {'genericSaleItemId': 1, 'itemType': 'Product', 'genericProductId': 1, 'description': 'Bar soap', 'quantity': 10, 'unitPrice': 10,
      'discountAmount': 0, 'lineTotal': 100},
  ],
};

FakeApi api() => FakeApi()
  ..gets['/api/CompanyTime/context'] = {
    'businessDate': '2026-11-04', 'companyLocalDateTime': '2026-11-04T10:00:00', 'utcNow': '2026-11-04T10:00:00Z',
  }
  ..gets['$base/module-settings'] = {for (final k in genericModuleKeys) k: true}
  ..gets['$base/business-template'] = {'genericIndustryTemplate': 'Gym', 'genericBusinessTemplate': businessTemplateFor('Gym')}
  ..gets['$base/sales'] = [
    sale,
    {'genericSaleId': 13, 'saleDate': '2026-10-20T00:00:00', 'salesType': 'WalkInSale', 'totalAmount': 20, 'amountPaid': 20, 'balance': 0,
      'status': 'Approved'},
  ]
  ..gets['$base/sales/12'] = sale
  ..gets['$base/customers'] = [ama, kojo]
  ..gets['$base/customers/1'] = ama
  ..gets['$base/customers/1/ledger'] = [
    {'genericCustomerLedgerId': 1, 'transactionDate': '2026-11-02T00:00:00', 'transactionType': 'SaleDebit', 'description': 'Sale #12',
      'saleId': 12, 'debitAmount': 95, 'creditAmount': 0, 'balanceAfterTransaction': 150},
  ]
  ..gets['$base/products'] = [
    {'genericProductId': 1, 'productName': 'Bar soap', 'sku': 'SP-1', 'sellingPrice': 6.5},
  ]
  ..gets['$base/cash-accounts'] = [
    {'genericCashAccountId': 5, 'accountName': 'Till', 'accountType': 'Cash', 'isActive': false},
    {'genericCashAccountId': 6, 'accountName': 'MoMo wallet', 'accountType': 'MobileMoney', 'isActive': true},
  ]
  ..gets['$base/customer-payments'] = [
    {'genericCustomerPaymentId': 3, 'genericCustomerId': 1, 'customerName': 'Ama Mensah', 'paymentDate': '2026-11-03T00:00:00',
      'paymentMethod': 'MoMo', 'amount': 30, 'status': 'Draft', 'notes': 'part'},
    {'genericCustomerPaymentId': 4, 'paymentDate': '2026-10-01T00:00:00', 'paymentMethod': 'Cash', 'amount': 10, 'status': 'Approved'},
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

Finder selectShowing(String shown) => find.ancestor(of: find.text(shown), matching: find.byType(AppSelect<String>)).first;

Future<void> choose(WidgetTester tester, Finder select, String option) async {
  await tapIn(tester, select);
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Future<void> enterIn(WidgetTester tester, String label, String text, {bool dialog = true}) async {
  final l = find.text(label);
  final field = find.descendant(
      of: find.ancestor(of: dialog ? inDialog(l) : l, matching: find.byType(Column)).first, matching: find.byType(TextFormField));
  await tester.ensureVisible(field.first);
  await tester.enterText(field.first, text);
  await tester.pump();
}

void clearToasts(WidgetTester tester) => tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();

void main() {
  tearDown(invalidateGenericModules);

  testWidgets('the Sales menu: web order, native screens, the template words', (tester) async {
    final groups = webNavGroups['generic']!;
    final sales = groups.firstWhere((g) => g.title == 'Sales');
    expect([for (final l in sales.subGroups.single.links) l.href], ['/generic-sales', '/generic-customers', '/generic-customer-payments', '/generic-customer-credits']);
    expect(groups.indexOf(sales), groups.indexWhere((g) => g.title == 'Subscriptions') + 1);
    final elsewhere = [for (final g in groups) if (g != sales) for (final s in g.subGroups) for (final l in s.links) l.href];
    for (final href in ['/generic-sales', '/generic-customers', '/generic-customer-payments']) {
      expect(elsewhere, isNot(contains(href)));
      expect(pageScreens[href], isNotNull, reason: href);
    }
    expect(pageScreens['/generic-sales/new'], isNotNull);
    await tester.runAsync(() async => loadGenericModules(await sessionFor(api()), generic));
    final gm = cachedGenericModules('g1')!;
    final worded = gateGenericCatalog(groups, generic).firstWhere((g) => g.title == 'Sales').subGroups.single.links.map((l) => l.label);
    expect(worded, ['Sales', gm.labels.customerPlural, gm.labels.paymentPlural, 'Customer Credits']);
  });

  test('filters, badges and ledger refs', () {
    final rows = [for (final r in api().gets['$base/sales']! as List) r as Map];
    expect([for (final r in filterGenericSales(rows, search: 'friday')) r['genericSaleId']], [12]);
    expect([for (final r in filterGenericSales(rows, to: '2026-10-31')) r['genericSaleId']], [13]);
    expect([for (final c in filterGenericCustomers([ama, kojo], 'osu')) c['genericCustomerId']], [1]);
    final pays = [for (final r in api().gets['$base/customer-payments']! as List) r as Map];
    expect([for (final p in filterGenericPayments(pays, search: 'momo')) p['genericCustomerPaymentId']], [3]);
    expect(genericLedgerRef({'paymentId': 4}), 'Pay #4');
    expect(genericLedgerRef({}), '—');
  });

  testWidgets('Sales list: count, walk-in, status buttons, balance', (tester) async {
    await open(tester, GenericSalesScreen(session: await sessionFor(api()), company: generic), size: phone);
    expect(find.text('2  sale(s)'), findsOneWidget, reason: 'the web leaves the empty status word in');
    expect(find.text('#12 · Ama Mensah'), findsOneWidget);
    expect(find.text('#13 · Walk-in'), findsOneWidget);
    await see(tester, find.text(ghs('45.00')));
    await tap(tester, find.widgetWithText(OutlinedButton, 'Draft'));
    expect(find.text('2 draft sale(s)'), findsOneWidget);
  });

  testWidgets('New sale: lines, totals, the body, then the sale', (tester) async {
    final a = api()..writeAnswers['$base/sales'] = {'genericSaleId': 12};
    await open(tester, GenericNewSaleScreen(session: await sessionFor(a), company: generic), size: phone);
    expect(find.text('— Walk-in —'), findsOneWidget);
    await see(tester, find.text('MoMo wallet (MobileMoney)'));
    expect(find.text('MoMo wallet (MobileMoney)'), findsOneWidget, reason: 'the first active account is the default');

    await tap(tester, find.text('Create as Draft'));
    expect(find.textContaining('Add at least one item'), findsOneWidget);
    clearToasts(tester);

    await see(tester, find.text('— select product —'));
    await choose(tester, selectShowing('— select product —'), 'Bar soap (SP-1)');
    await enterIn(tester, 'Qty', '2', dialog: false);
    await tap(tester, find.text('Add row'));
    await choose(tester, find.ancestor(of: find.text('Product'), matching: find.byType(AppSelect<String>)).last, 'Service');
    final svc = find.ancestor(of: find.text('Service description'), matching: find.byType(TextFormField));
    await tester.ensureVisible(svc);
    await tester.enterText(svc, 'Ironing');
    await tester.pump();
    await see(tester, find.text('Customer (optional)'));
    await choose(tester, selectShowing('— Walk-in —'), 'Kojo Ltd');
    await see(tester, find.text('Amount paid'));
    await enterIn(tester, 'Amount paid', '5', dialog: false);
    await enterIn(tester, 'Tax', '1', dialog: false);
    await see(tester, find.text('Subtotal'));
    expect(find.text(ghs('13.00')), findsWidgets, reason: 'subtotal and line: 2 × 6.50 (the service row has qty 1 × 0)');
    expect(find.text(ghs('14.00')), findsOneWidget, reason: 'total = 13 + 1 tax');
    expect(find.text(ghs('9.00')), findsOneWidget, reason: 'balance');

    await tap(tester, find.text('Create as Draft'));
    final b = a.lastBody('$base/sales');
    expect((b['genericCustomerId'], b['salesType'], b['taxAmount'], b['amountPaid'], b['paymentMethod'], b['genericCashAccountId'], b['farmId']),
        (2, 'WalkInSale', 1, 5, 'Cash', 6, 'g1'));
    expect(b['items'], [
      {'itemType': 'Product', 'genericProductId': 1, 'genericServiceId': null, 'description': 'Bar soap', 'quantity': 2, 'unitPrice': 6.5,
        'discountAmount': 0},
      {'itemType': 'Service', 'genericProductId': null, 'genericServiceId': null, 'description': 'Ironing', 'quantity': 1, 'unitPrice': 0,
        'discountAmount': 0},
    ]);
    expect(find.text('Sale #12'), findsWidgets, reason: 'opens the sale');
  });

  testWidgets('the sale: totals, header, approve, cancel', (tester) async {
    final a = api();
    await open(tester, GenericSaleDetailScreen(session: await sessionFor(a), company: generic, saleId: 12), size: phone);
    expect(find.text('Draft'), findsOneWidget);
    await see(tester, find.text('Paid (MoMo)'));
    expect(find.text('Receipt: R-9'), findsOneWidget);
    expect(find.text('Deliver Friday'), findsOneWidget);
    await tap(tester, find.widgetWithText(FilledButton, 'Approve'));
    expect(a.writes.last.url.path, '$base/sales/12/approve');
    expect(find.textContaining('Sale #12 approved'), findsOneWidget);
    clearToasts(tester);
    await tap(tester, find.widgetWithText(OutlinedButton, 'Cancel'));
    expect(find.text('Cancel this draft sale?'), findsOneWidget);
    await tester.tap(find.text('Yes, cancel'));
    await tester.pumpAndSettle();
    expect(a.writes.last.url.path, '$base/sales/12/cancel');
    expect(jsonDecode(a.writes.last.body), isEmpty);
  });

  testWidgets('the sale: an approved sale refunds; a missing sale says so', (tester) async {
    final a = api()..gets['$base/sales/12'] = {...sale, 'status': 'Approved'};
    await open(tester, GenericSaleDetailScreen(session: await sessionFor(a), company: generic, saleId: 12), size: phone);
    await tap(tester, find.widgetWithText(OutlinedButton, 'Refund'));
    expect(find.textContaining('All three are atomic.'), findsOneWidget);
    await tester.tap(find.text('Yes, refund'));
    await tester.pumpAndSettle();
    expect(a.writes.last.url.path, '$base/sales/12/refund');

    final b = api()..statuses['$base/sales/99'] = 404;
    await open(tester, GenericSaleDetailScreen(session: await sessionFor(b), company: generic, saleId: 99), size: phone);
    expect(find.text('Sale not found.'), findsOneWidget);
  });

  testWidgets('Customers: words, badges, create, edit, delete, ledger', (tester) async {
    final a = api()..writeAnswers['$base/customers'] = {'genericCustomerId': 9, 'customerName': 'Yaw'};
    await open(tester, GenericCustomersScreen(session: await sessionFor(a), company: generic), size: phone);
    final l = cachedGenericModules('g1')!.labels;
    expect(find.text('2 ${l.customerPlural.toLowerCase()}'), findsOneWidget);
    expect(find.text('Over limit'), findsOneWidget);
    expect(find.text('Owes'), findsOneWidget);

    await tap(tester, find.text('New ${l.customer.toLowerCase()}'));
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Name is required'), findsOneWidget);
    clearToasts(tester);
    await enterIn(tester, '${l.customer} name *', ' Yaw ');
    await choose(tester, inDialog(selectShowing('Individual')), 'Wholesale Customer');
    await enterIn(tester, 'Credit limit', '250');
    await tapIn(tester, find.widgetWithText(FilledButton, 'Create'));
    final b = a.lastBody('$base/customers');
    expect((b['customerName'], b['customerType'], b['creditLimit'], b['phoneNumber'], b['isActive'], b['farmId']),
        ('Yaw', 'Wholesale Customer', 250, null, true, 'g1'));
    clearToasts(tester);

    await tap(tester, find.widgetWithText(OutlinedButton, 'Edit'));
    await tapIn(tester, find.widgetWithText(FilledButton, 'Save changes'));
    final put = a.lastBody('$base/customers/1', 'PUT');
    expect((put['customerName'], put['paymentTermsDays'], put['farmId']), ('Ama Mensah', 7, 'g1'));
    expect(find.textContaining('${l.customer} updated.'), findsOneWidget);
    clearToasts(tester);

    await tap(tester, find.widgetWithText(OutlinedButton, 'Delete'));
    expect(find.textContaining('"Ama Mensah" owes ${ghs('150.00')}.'), findsOneWidget);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();

    await tap(tester, find.text('Ama Mensah'));
    expect(find.text('Individual · 0244111222 · Osu'), findsOneWidget);
    expect(find.text('Credit limit: ${ghs('100.00')}'), findsOneWidget);
    expect(find.text('SaleDebit'), findsOneWidget);
    expect(find.text('Sale #12'), findsWidgets);
  });

  testWidgets('Payments: record (customer, amount, account), approve, cancel', (tester) async {
    final a = api()..writeAnswers['$base/customer-payments'] = {'genericCustomerPaymentId': 7};
    await open(tester, GenericCustomerPaymentsScreen(session: await sessionFor(a), company: generic), size: phone);
    final l = cachedGenericModules('g1')!.labels;
    expect(find.text('2 payment(s) – money coming in from ${l.customerPlural.toLowerCase()}.'), findsOneWidget);
    expect(find.text('#4 · –'), findsOneWidget);

    await tap(tester, find.text('Record payment'));
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Pick a ${l.customer.toLowerCase()}'), findsOneWidget);
    clearToasts(tester);
    await choose(tester, inDialog(selectShowing('Pick ${l.customer.toLowerCase()}...')), 'Ama Mensah – owes ${ghs('150.00')}');
    await tapIn(tester, find.widgetWithText(FilledButton, 'Create'));
    expect(find.textContaining('Amount must be greater than zero'), findsOneWidget);
    clearToasts(tester);
    await enterIn(tester, 'Amount *', '60');
    await choose(tester, inDialog(selectShowing('Cash')), 'Bank');
    await tapIn(tester, find.widgetWithText(FilledButton, 'Create'));
    final b = a.lastBody('$base/customer-payments');
    expect((b['genericCustomerId'], b['amount'], b['paymentMethod'], b['genericCashAccountId'], b['notes'], b['farmId']),
        (1, 60, 'Bank', 6, null, 'g1'));
    expect(find.textContaining('${l.payment} created as Draft.'), findsOneWidget);
    clearToasts(tester);

    await tap(tester, find.widgetWithText(OutlinedButton, 'Approve'));
    expect(a.writes.last.url.path, '$base/customer-payments/3/approve');
    expect(find.textContaining('Payment #3 approved.'), findsOneWidget);
    clearToasts(tester);
    await tap(tester, find.widgetWithText(OutlinedButton, 'Cancel'));
    expect(a.writes.last.url.path, '$base/customer-payments/3/cancel');
    await tap(tester, find.widgetWithText(OutlinedButton, 'Approved'));
    expect(find.widgetWithText(FilledButton, 'Approved'), findsOneWidget);
  });
}
