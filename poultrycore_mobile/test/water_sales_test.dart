// Water → Sales, Expenses & Money → Sales: the Sales page, Payments and
// Customer Balances, driven at phone width against a fake API. Payments and
// Balances are the shared pages on the Water rail, as on the web.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/reports/report_format.dart' show FarmMoney;
import 'package:poultrycore_mobile/pages/poultry/sales/balances_logic.dart';
import 'package:poultrycore_mobile/pages/poultry/sales/customer_balances_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/sales/payments_received_screen.dart';
import 'package:poultrycore_mobile/pages/water/water_sales_screen.dart';
import 'package:poultrycore_mobile/pages/web_nav.dart';

import 'support/harness.dart';

final water = Company(farmId: 'farm-1', name: 'Win Water', type: CompanyType.water);

final sales = [
  {
    'waterSaleId': 12, 'saleDate': '2026-10-08T09:30:00', 'customerName': 'Ama', 'status': 'PartiallyPaid',
    'totalAmount': 100, 'amountPaid': 40, 'balance': 60, 'paymentMethod': 'Cash', 'sourceType': 'Direct', 'notes': 'east gate',
  },
  {
    'waterSaleId': 11, 'saleDate': '2026-10-07T15:00:00', 'customerName': null, 'status': 'Paid',
    'totalAmount': 30, 'amountPaid': 30, 'balance': 0, 'paymentMethod': null, 'sourceType': 'DeliveryRun', 'sourceId': 4,
  },
];

final products = [
  {'waterProductId': 1, 'name': 'Sachet water', 'unit': 'Bag', 'productType': 'FinishedGood', 'isActive': true, 'isSachetProduct': true, 'unitPrice': 9, 'bagPrice': 10, 'sachetPrice': 0.5, 'stockOnHand': 300},
  {'waterProductId': 2, 'name': 'Bottle 1.5L', 'unit': 'Pack', 'productType': 'FinishedGood', 'isActive': true, 'isSachetProduct': false, 'unitPrice': 25, 'stockOnHand': 40},
  {'waterProductId': 3, 'name': 'Sachet film', 'unit': 'Roll', 'productType': 'PackagingMaterial', 'isActive': true, 'unitPrice': 5},
];

FakeApi api() => FakeApi()
  ..gets['/api/Water/sales'] = sales
  ..gets['/api/Water/products'] = products
  ..gets['/api/Water/customers'] = [
    {'waterCustomerId': 7, 'name': 'Ama'},
    {'waterCustomerId': 8, 'name': 'Kojo Stores'},
  ]
  ..gets['/api/Water/sales/12'] = {
    ...sales.first,
    'items': [
      {'waterSaleItemId': 1, 'productName': 'Sachet water', 'sellingUnit': 'Bag', 'baseUnit': 'Sachet', 'baseQuantity': 1500, 'quantity': 5, 'unitPrice': 20, 'lineTotal': 100},
    ],
  }
  ..writeAnswers['/api/Water/sales'] = {'waterSaleId': 13};

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

Map<String, String> lastQuery(FakeApi a, String path) => a.requests.lastWhere((r) => r.url.path == path).url.queryParameters;

Future<void> openSales(WidgetTester tester, FakeApi a, {int? focus}) async =>
    open(tester, WaterSalesScreen(session: await sessionFor(a), company: water, focusSaleId: focus), size: phone);

void main() {
  setUp(FarmMoney.clearCache);

  test('the three Sales pages are native on the sidebar routes', () {
    for (final r in ['/water-sales', '/water-payments', '/water-customer-balances']) {
      expect(pageScreens.containsKey(r), isTrue, reason: r);
    }
    expect(waterUnitOptionsFor(products[0]), ['Bag', 'Sachet']);
    expect(waterUnitOptionsFor(products[1]), ['Pack']);
    expect(waterUnitOptionsFor(null), ['Unit']);
    expect(waterPriceFor(products[0], 'Sachet'), 0.5);
    expect(waterPriceFor(products[1], 'Bag'), 25);
  });

  test('the Water sidebar follows buildWaterNavConfig', () {
    final nav = webNavGroups['water']!;
    expect([for (final g in nav) g.title],
        ['Quick Links', 'Operations', 'Sales, Expenses & Money', 'Trackers', 'Reports', 'Setup', 'System']);
    final sales = nav.firstWhere((g) => g.title == 'Sales, Expenses & Money').subGroups.first;
    expect([for (final l in sales.links) l.href], ['/water-sales', '/water-payments', '/water-customer-balances']);
    expect([for (final sg in nav.firstWhere((g) => g.title == 'Trackers').subGroups) sg.title], ['Stock']);
    final system = nav.last.subGroups.single;
    expect([for (final l in system.links) (l.label, l.href)], [
      ('Alerts', '#alerts'), ('Billing', '/business-office/billing'),
      ('Activity Log', '/audit-logs'), ('Terms & Conditions', '/terms'),
    ]);
  });

  group('Water sales', () {
    testWidgets('cards, search, a delivery sale cannot be deleted', (tester) async {
      final a = api();
      await openSales(tester, a);
      expect(find.text('#12 · Ama'), findsOneWidget);
      expect(find.text('Direct sale'), findsOneWidget);
      await see(tester, find.text('#11 · Walk-in'));
      expect(find.text('Delivery #4'), findsOneWidget);
      expect(find.text('From delivery'), findsOneWidget);
      expect(find.text('Mark as Paid'), findsOneWidget, reason: 'only the owing sale');
      expect(find.text('Delete'), findsOneWidget, reason: 'the delivery sale has none');

      await see(tester, find.byType(TextFormField));
      await tester.enterText(find.byType(TextFormField).first, 'east');
      await tester.pumpAndSettle();
      expect(find.text('#11 · Walk-in'), findsNothing);
      expect(find.text('#12 · Ama'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a focused sale shows alone until Show all sales', (tester) async {
      await openSales(tester, api(), focus: 11);
      expect(find.textContaining('W11', findRichText: true), findsOneWidget);
      expect(find.text('#12 · Ama'), findsNothing);
      await tester.tap(find.text('Show all sales'));
      await tester.pumpAndSettle();
      expect(find.text('#12 · Ama'), findsOneWidget);
    });

    testWidgets('new sale: finished goods only, unit switches price, paid now posts the payment', (tester) async {
      final a = api();
      await openSales(tester, a);
      await tester.tap(find.text('New sale'));
      await tester.pumpAndSettle();
      expect(find.text('New water sale'), findsOneWidget);
      expect(find.text('No items. Click '), findsNothing, reason: 'rich text');
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Record sale')).onPressed, isNull);

      await pick(tester, 'Walk-in / cash', 'Kojo Stores');
      await tester.tap(find.text('Add line'));
      await tester.pumpAndSettle();
      expect(find.text('10.00'), findsWidgets, reason: 'Bag price, qty 1');

      // The product dropdown lists finished goods with their stock.
      await tester.tap(find.text('Sachet water (Bag)').first);
      await tester.pumpAndSettle();
      expect(find.text('stock 300'), findsOneWidget);
      expect(find.text('Sachet film (Roll)'), findsNothing);
      await tester.tap(find.text('Bottle 1.5L (Pack)').last);
      await tester.pumpAndSettle();
      expect(find.text('25.00'), findsWidgets);
      await tester.tap(find.text('Bottle 1.5L (Pack)').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sachet water (Bag)').last);
      await tester.pumpAndSettle();

      await pick(tester, 'Bag', 'Sachet');
      await enter(tester, 'Qty', '40');
      expect(find.text('Total: '), findsNothing, reason: 'rich text');
      expect(find.text('20.00'), findsWidgets, reason: '40 sachets × 0.50');

      await tapSeen(tester, find.text('Paid now'));
      await see(tester, find.text('Cash'));
      await pick(tester, 'Cash', 'Mobile Money');
      await see(tester, find.text('Notes'));
      await enter(tester, 'Notes', 'gate 2');
      await tapSeen(tester, find.text('Record sale'));
      await tester.pumpAndSettle();

      final sale = a.lastBody('/api/Water/sales');
      expect((sale['waterCustomerId'], sale['notes'], sale['farmId']), (8, 'gate 2', 'farm-1'));
      expect(sale['items'], [
        {'waterProductId': 1, 'quantity': 40, 'unitPrice': 0.5, 'sellingUnit': 'Sachet'},
      ]);
      final pay = a.lastBody('/api/Water/payments');
      expect((pay['waterSaleId'], pay['amount'], pay['paymentMethod']), (13, 20, 'Mobile Money'));
      expect(find.text('Sale #13 recorded · Paid in full'), findsOneWidget);
    });

    testWidgets('new sale: quantity below 1 is refused', (tester) async {
      final a = api();
      await openSales(tester, a);
      await tester.tap(find.text('New sale'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add line'));
      await tester.pumpAndSettle();
      await enter(tester, 'Qty', '0');
      await tapSeen(tester, find.text('Record sale'));
      await tester.pumpAndSettle();
      expect(find.text('Quantity must be ≥ 1'), findsOneWidget);
      expect(a.writes, isEmpty);
    });

    testWidgets('mark as paid checks the balance; details record a payment; delete', (tester) async {
      final a = api();
      await openSales(tester, a);
      await tapSeen(tester, find.text('Mark as Paid'));
      expect(find.text('Record payment · Sale #12'), findsOneWidget);
      await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField)), '70');
      await tester.tap(find.text('Record'));
      await tester.pumpAndSettle();
      expect(find.text('Amount exceeds balance'), findsOneWidget);
      expect(a.writes, isEmpty);
      await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField)), '60');
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Cash')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bank transfer').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Record'));
      await tester.pumpAndSettle();
      final pay = a.lastBody('/api/Water/payments');
      expect((pay['waterSaleId'], pay['amount'], pay['paymentMethod']), (12, 60, 'Bank'));

      await tapSeen(tester, find.text('Details'));
      expect(find.text('Sale #12'), findsOneWidget);
      expect(find.text(' (1,500 Sachet)'), findsNothing, reason: 'rich text');
      expect(find.textContaining('1,500 Sachet', findRichText: true), findsOneWidget);
      await tester.tap(find.text('Record payment'));
      await tester.pumpAndSettle();
      expect(find.text('Record payment · Sale #12'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      await tapSeen(tester, find.text('Delete'));
      expect(find.text('Delete sale #12?'), findsOneWidget);
      await tester.tap(find.text('Delete sale'));
      await tester.pumpAndSettle();
      expect(a.writes.last.method, 'DELETE');
      expect(a.writes.last.url.path, '/api/Water/sales/12');
      expect(find.text('Sale #12 deleted — Stock was restored.'), findsOneWidget);
    });
  });

  group('Payments and Customer Balances on the Water rail', () {
    testWidgets('payments read the Water endpoint; a sale link opens Water sales', (tester) async {
      final a = api()
        ..gets['/api/Water/customer-payments'] = [
          {'paymentId': 'w1', 'paymentNumber': 'WPAY-1', 'partyId': 7, 'partyName': 'Ama', 'paymentDate': '2026-10-08T00:00:00', 'totalAmount': 40, 'paymentMethod': 'Cash', 'sourceType': 'SaleEntry', 'status': 'Posted', 'allocationCount': 1, 'saleId': 12, 'saleTotal': 100, 'balanceBefore': 100, 'amountApplied': 40, 'balanceAfter': 60},
        ];
      await open(tester, PaymentsReceivedScreen(session: await sessionFor(a), company: water, rail: BalanceRail.water), size: phone);
      expect(a.requests.any((r) => r.url.path.startsWith('/api/Poultry')), isFalse);
      await tapSeen(tester, find.text('#12'));
      expect(find.byType(WaterSalesScreen), findsOneWidget);
      expect(tester.widget<WaterSalesScreen>(find.byType(WaterSalesScreen)).focusSaleId, 12);
    });

    testWidgets('balances: no cash accounts, payment posts to Water, open sale', (tester) async {
      final a = api()
        ..gets['/api/Water/customer-balances'] = [
          {'partyId': 7, 'partyName': 'Ama', 'totalBalance': 60, 'openDocumentCount': 1, 'overdueAmount': 0},
        ]
        ..gets['/api/Water/customer-balances/summary'] = {'totalBalance': 60, 'partyCount': 1, 'overdueBalance': 0, 'paymentsToday': 0}
        ..gets['/api/Water/customer-balances/7/open-sales'] = [
          {'documentType': 'WaterSale', 'documentId': 12, 'reference': 'W12', 'documentDate': '2026-10-08T00:00:00', 'label': 'Sachet water', 'totalAmount': 100, 'amountPaid': 40, 'balance': 60, 'ageDays': 0, 'status': 'Partial', 'isOverdue': false},
        ];
      await open(tester, CustomerBalancesScreen(session: await sessionFor(a), company: water, rail: BalanceRail.water), size: phone);
      expect(a.requests.any((r) => r.url.path.startsWith('/api/Poultry')), isFalse);
      expect(a.requests.any((r) => r.url.path.endsWith('cash-accounts')), isFalse);

      await tapSeen(tester, find.text('Show 1 open sale'));
      await tapSeen(tester, find.text('Receive payment'));
      expect(find.text('Cash account (optional)'), findsOneWidget, reason: 'shown, with nothing to pick');
      await tapSeen(tester, find.widgetWithText(FilledButton, 'Receive payment'));
      final body = a.lastBody('/api/Water/customer-payments');
      expect((body['partyId'], body['amount'], body['cashAccountId'], body['sourceType']), (7, 60, null, 'CustomerBalances'));

      await tapSeen(tester, find.text('Show 1 open sale'));
      expect(find.text('W12'), findsOneWidget);
      await tapSeen(tester, find.text('Open'));
      expect(find.byType(WaterSalesScreen), findsOneWidget);
      expect(tester.widget<WaterSalesScreen>(find.byType(WaterSalesScreen)).focusSaleId, 12);
    });
  });
}
