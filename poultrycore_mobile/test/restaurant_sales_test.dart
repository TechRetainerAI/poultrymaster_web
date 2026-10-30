// Restaurant → Sales (2026-10-21): Sales, Payments and Customer Balances as the
// web pages, against a fake API at phone width.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/sales/balances_logic.dart';
import 'package:poultrycore_mobile/pages/poultry/sales/customer_balances_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/sales/payments_received_screen.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_sales_screen.dart';

import 'support/harness.dart';

final rest = Company(farmId: 'farm-1', name: 'Rose Bistro', type: CompanyType.restaurant, role: 'Admin');
const tall = Size(390, 4000);

Finder filled(String t) => find.widgetWithText(FilledButton, t);

final payLater = {
  'orderId': 11, 'orderNumber': 'ORD-011', 'createdAt': '2026-10-10T12:00:00', 'customerId': 4, 'customerName': 'Esi',
  'orderType': 'DineIn', 'itemCount': 3, 'totalAmount': 120, 'paidAmount': 20, 'status': 'Completed', 'tableNumber': '5',
};
final atTill = {
  'orderId': 12, 'orderNumber': 'ORD-012', 'createdAt': '2026-10-11T19:00:00', 'orderType': 'Takeaway', 'itemCount': 1,
  'totalAmount': 50, 'paidAmount': 0, 'status': 'Open', 'guestPaymentIntent': 'Cash',
};
final paid = {
  'orderId': 13, 'orderNumber': 'ORD-013', 'createdAt': '2026-10-12T09:00:00', 'orderType': 'Delivery', 'itemCount': 2,
  'totalAmount': 80, 'paidAmount': 80, 'status': 'Completed', 'onlineSource': 'Web',
};

void main() {
  test('routes, the sale row, pay-later and the filters', () {
    for (final h in ['/restaurant-sales', '/restaurant-payments', '/restaurant-customer-balances']) {
      expect(pageScreens.containsKey(h), isTrue, reason: h);
    }
    final r = orderSaleRow(payLater);
    expect((r.reference, r.customer, r.product, r.paid, r.balance, r.status), ('ORD-011', 'Esi', 'Dine In · 3 items', 20, 100, 'Partial'));
    expect(orderSaleRow(atTill).customer, 'Walk-in');
    expect(orderSaleRow({...atTill, 'tableNumber': '9'}).customer, 'Table 9');
    expect([isPayLaterOrder(payLater), isPayLaterOrder(atTill), isPayLaterOrder(paid)], [true, false, false]);
    expect(saleStatusOf(0, 0), 'Paid');
    final all = [payLater, atTill, paid];
    expect(filterOrderSales(all, type: 'DineIn').map((o) => o['orderId']), [11]);
    expect(filterOrderSales(all, status: 'Pending').map((o) => o['orderId']), [12]);
    expect(filterOrderSales(all, search: 'delivery').map((o) => o['orderId']), [13]);
  });

  testWidgets('Sales: cards, the card buttons per order, Pay, Payments, Invoice and Delete', (tester) async {
    final api = FakeApi()
      ..gets['/api/Restaurant/orders'] = [payLater, atTill, paid, {...paid, 'orderId': 14, 'status': 'Cancelled'}]
      ..gets['/api/Restaurant/finance/accounts'] = [{'cashAccountId': 5, 'name': 'Bank', 'currentBalance': 900, 'isActive': true}]
      ..gets['/api/Restaurant/orders/11/items'] = [
        {'itemName': 'Jollof', 'quantity': 2, 'unitPrice': 40, 'modifierTotal': 5, 'lineTotal': 90, 'status': 'Served'},
        {'itemName': 'Coke', 'quantity': 1, 'unitPrice': 10, 'lineTotal': 10, 'status': 'Voided'},
      ]
      ..gets['/api/Restaurant/customer-payments'] = []
      ..gets['/api/Restaurant/customer-balances/4/open-documents'] = [];
    await open(tester, RestaurantSalesScreen(session: await sessionFor(api), company: rest), size: tall);
    expect(find.text('3 transactions'), findsOneWidget, reason: 'the cancelled order is left out');
    expect(find.text('ORD-011'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Pay'), findsOneWidget, reason: 'only the pay-later order');
    expect(find.widgetWithText(OutlinedButton, 'Pay at till'), findsOneWidget, reason: 'the open order still owed');
    expect(find.text('Source '), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Invoice').first);
    await tester.pumpAndSettle();
    expect(find.text('Jollof'), findsOneWidget);
    expect(find.text('Coke'), findsNothing, reason: 'voided lines are left out');
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Pay'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Esi', findRichText: true), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Payments').first);
    await tester.pumpAndSettle();
    final q = api.requests.lastWhere((r) => r.url.path == '/api/Restaurant/customer-payments').url.queryParameters;
    expect(q['saleId'], '11', reason: 'the customer side sends saleId, as listPayments');
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('will be cancelled'), findsOneWidget);
    await tester.tap(filled('Delete'));
    await tester.pumpAndSettle();
    final d = api.lastBody('/api/Restaurant/orders/11/status', 'PATCH');
    expect((d['status'], d['reason']), ('Cancelled', 'Deleted from Sales'));
  });

  testWidgets('Sales: the Filters sheet narrows by type and status; ?orderId= shows one order', (tester) async {
    final api = FakeApi()..gets['/api/Restaurant/orders'] = [payLater, atTill, paid];
    await open(tester, RestaurantSalesScreen(session: await sessionFor(api), company: rest), size: tall);
    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    await pick(tester, 'All types', 'Takeaway');
    await tester.tap(filled('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('1 transactions'), findsOneWidget);
    expect(find.text('ORD-012'), findsOneWidget);

    await open(tester, RestaurantSalesScreen(session: await sessionFor(api), company: rest, focusOrderId: 13), size: tall);
    expect(find.text('Showing one order.'), findsOneWidget);
    expect(find.text('ORD-013'), findsOneWidget);
    expect(find.text('ORD-011'), findsNothing);
  });

  testWidgets('Payments and Customer Balances read the Restaurant routes, without the Poultry extras', (tester) async {
    final api = FakeApi()
      ..gets['/api/Restaurant/customer-payments'] = [
        {'paymentId': 'CP-1', 'partyName': 'Esi', 'amount': 20, 'paymentDate': '2026-10-10', 'status': 'Posted', 'saleId': 11},
      ]
      ..gets['/api/Restaurant/customer-balances'] = [
        {'partyId': 4, 'partyName': 'Esi', 'totalBalance': 100, 'openDocumentCount': 1},
      ]
      ..gets['/api/Restaurant/customer-balances/summary'] = {'totalBalance': 100, 'partyCount': 1}
      ..gets['/api/Restaurant/finance/accounts'] = [{'cashAccountId': 5, 'name': 'Bank', 'currentBalance': 900, 'isActive': true}];
    await open(tester, PaymentsReceivedScreen(session: await sessionFor(api), company: rest, rail: BalanceRail.restaurant), size: tall);
    expect(api.requests.any((r) => r.url.path == '/api/Restaurant/customer-payments'), isTrue);
    expect(api.requests.any((r) => r.url.path.startsWith('/api/Poultry')), isFalse);
    expect(find.text('Sale details'), findsNothing, reason: 'Poultry only');

    await open(tester, CustomerBalancesScreen(session: await sessionFor(api), company: rest, rail: BalanceRail.restaurant), size: tall);
    expect(api.requests.any((r) => r.url.path == '/api/Restaurant/customer-balances'), isTrue);
    expect(api.requests.any((r) => r.url.path == '/api/Restaurant/finance/accounts'), isTrue);
    expect(api.requests.any((r) => r.url.path.startsWith('/api/Poultry')), isFalse);
    expect(find.textContaining('Esi'), findsWidgets);
  });
}
