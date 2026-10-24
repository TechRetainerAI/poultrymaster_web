// Restaurant → Orders & Kitchen (2026-10-21): POS / New Order, All Orders,
// New Guest Orders and the Kitchen Display, against a fake API at 360 px.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/money/money_routes.dart';
import 'package:poultrycore_mobile/pages/poultry/reports/report_export.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_kds_screen.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_orders_screen.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_pending_orders_screen.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_pos_screen.dart';

import 'support/harness.dart';

final rest = Company(farmId: 'farm-1', name: 'Rose Bistro', type: CompanyType.restaurant, role: 'Admin');
const tall = Size(360, 3000);

Finder filled(String t) => find.widgetWithText(FilledButton, t);

Future<void> enterUnder(WidgetTester tester, String label, String text) async {
  final l = find.byWidgetPredicate((w) => w is Text && RegExp('^${RegExp.escape(label)}' r'( \*)?$').hasMatch(w.data ?? w.textSpan?.toPlainText() ?? ''));
  final box = find.descendant(of: find.ancestor(of: l.last, matching: find.byType(Column)).first, matching: find.byType(EditableText));
  await tester.enterText(box.first, text);
  await tester.pump();
}

Future<void> pickLast(WidgetTester tester, String shown, String option) async {
  await tester.ensureVisible(find.text(shown).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(shown).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Map<String, Object?> order(int id, {String status = 'Placed', num total = 20, num paid = 0, String pay = 'Unpaid', Map<String, Object?> extra = const {}}) => {
      'orderId': id, 'orderNumber': 'ORD-$id', 'orderType': 'DineIn', 'status': status, 'subtotal': total, 'taxAmount': 0, 'discountAmount': 0,
      'serviceChargeAmount': 0, 'totalAmount': total, 'paidAmount': paid, 'paymentStatus': pay, 'itemCount': 2, 'covers': 1,
      'createdAt': DateTime.now().toUtc().toIso8601String(), ...extra,
    };

void main() {
  test('routes, the Sales → Edit link, and the small helpers', () async {
    for (final h in ['/restaurant-pos', '/restaurant-orders', '/restaurant-pending-orders', '/restaurant-kds']) {
      expect(pageScreens.containsKey(h), isTrue, reason: h);
    }
    final s = await sessionFor(FakeApi());
    final w = moneyScreenForHref('/restaurant-orders?orderId=7', s, rest);
    expect(w, isA<RestaurantOrdersScreen>());
    expect((w as RestaurantOrdersScreen).openOrderId, 7);
    expect(kdsTime(.5), '<1m');
    expect(kdsTime(12.9), '12m');
    expect(kdsTime(65), '1h5m');
    expect(kdsTiming(3).$1, const Color(0xFF22C55E));
    expect(kdsTiming(20).$1, const Color(0xFFEF4444));
    final g = kdsGroups([
      {'orderId': 1, 'orderNumber': 'A'},
      {'orderId': 2, 'orderNumber': 'B'},
      {'orderId': 1, 'orderNumber': 'A'},
    ]);
    expect(g.map((x) => x.length), [2, 1]);
    expect(pendingWaitTone(12).$2, const Color(0xFFFEF2F2));
    final list = [
      {'orderId': 1, 'onlineSource': 'QR'},
      {'orderId': 2},
    ];
    expect(visibleOrders(list, 'online').map((o) => o['orderId']), [1]);
    expect(visibleOrders(list, 'pos').map((o) => o['orderId']), [2]);
    expect(onlineLabel({'onlineSource': 'Web'}), 'ONLINE · WEB');
    final r = PosReceipt(order(9, status: 'Completed', pay: 'Paid', paid: 20), [
      {'quantity': 2, 'itemName': 'Jollof', 'unitPrice': 10, 'lineTotal': 20},
    ], method: 'Cash', amount: 50, tip: 0, change: 30);
    for (final pdf in await Future.wait([posInvoicePdf(r, 'Rose Bistro', null), posEmailPdf(r, 'Rose Bistro', null), posRollPdf(r, 'Rose Bistro', null)])) {
      expect(String.fromCharCodes(pdf.take(4)), '%PDF');
    }
  });

  testWidgets('POS: filter the menu, build a dine-in order for a customer, place it, pay cash into a chosen till, receipt', (tester) async {
    final shared = <String>[];
    ReportExport.sharer = (name, bytes, mime, subject) async => shared.add(name);
    var paid = false;
    final api = FakeApi()
      ..gets['/api/Restaurant/menu/categories'] = [
        {'menuCategoryId': 1, 'name': 'Mains', 'isActive': true},
        {'menuCategoryId': 2, 'name': 'Drinks', 'isActive': true},
      ]
      ..gets['/api/Restaurant/menu/items'] = [
        {'menuItemId': 11, 'name': 'Jollof', 'price': 10, 'menuCategoryId': 1, 'categoryName': 'Mains', 'isAvailable': true, 'isActive': true, 'prepTime': 15},
        {'menuItemId': 12, 'name': 'Sobolo', 'price': 3, 'menuCategoryId': 2, 'categoryName': 'Drinks', 'isAvailable': true, 'isActive': true},
        {'menuItemId': 13, 'name': 'Sold out', 'price': 5, 'menuCategoryId': 1, 'isAvailable': false, 'isActive': true},
      ]
      ..gets['/api/Restaurant/floor/tables'] = [
        {'tableId': 4, 'tableNumber': 'A4', 'capacity': 4, 'status': 'Available'},
      ]
      ..gets['/api/Restaurant/crm/customers'] = [
        {'customerId': 30, 'name': 'Efua', 'phone': '055', 'email': 'efua@x.test'},
      ]
      ..gets['/api/Restaurant/expenses/receipt-template'] = {'headerText': 'Osu, Accra', 'footerText': 'Come again'}
      ..gets['/api/Restaurant/finance/shifts'] = [
        {'shiftId': 1, 'tillName': 'Front', 'shiftNumber': 'S-1'},
        {'shiftId': 2, 'tillName': 'Bar', 'shiftNumber': 'S-2', 'openedBy': 'Kofi'},
      ]
      ..gets['/api/Restaurant/orders/9/items'] = [
        {'orderItemId': 1, 'quantity': 2, 'itemName': 'Jollof', 'unitPrice': 10, 'lineTotal': 20},
      ]
      ..writeAnswers['/api/Restaurant/orders'] = {'orderId': 9, 'orderNumber': 'ORD-9'};
    api.gets['/api/Restaurant/orders/9'] = order(9, extra: {'tableNumber': 'A4', 'customerId': 30, 'customerName': 'Efua'});
    api.onWrite = (req) {
      if (req.url.path == '/api/Restaurant/orders/9/payments') {
        paid = true;
        api.gets['/api/Restaurant/orders/9'] = order(9, paid: 20, pay: 'Paid', extra: {'tableNumber': 'A4', 'customerId': 30, 'customerName': 'Efua'});
      }
    };
    await open(tester, RestaurantPosScreen(session: await sessionFor(api), company: rest), size: const Size(360, 900));
    expect(find.text('Sold out'), findsNothing, reason: 'unavailable items are left off');
    await tester.tap(find.text('Drinks').first);
    await tester.pump();
    expect(find.text('Jollof'), findsNothing);
    await tester.tap(find.text('All'));
    await tester.pump();
    await tester.tap(find.text('Jollof'));
    await tester.tap(find.text('Jollof'));
    await tester.pump();
    expect(find.text('View order · 2 items · 20.00'), findsOneWidget);

    // The order panel: table and customer, then Place Order.
    await tester.tap(find.text('View order · 2 items · 20.00'));
    await tester.pumpAndSettle();
    await pickLast(tester, 'No table', 'Table A4 (4)');
    await pickLast(tester, 'Walk-in (Guest)', 'Efua (055)');
    await tester.tap(find.text('Place Order'));
    await tester.pumpAndSettle();
    final o = api.lastBody('/api/Restaurant/orders');
    expect((o['orderType'], o['tableId'], o['tableNumber'], o['customerId'], o['customerName'], o['covers'], o['farmId']),
        ('DineIn', 4, 'A4', 30, 'Efua', 1, 'farm-1'));
    final item = api.lastBody('/api/Restaurant/orders/9/items');
    expect((item['menuItemId'], item['itemName'], item['quantity'], item['unitPrice'], item['orderId']), (11, 'Jollof', 2, 10, 9));
    expect(item['modifiers'], isEmpty);
    expect(api.lastBody('/api/Restaurant/orders/9/recalc'), {'taxRate': null, 'serviceChargeRate': null});
    expect(api.lastBody('/api/Restaurant/loyalty/accounts'), {'customerName': 'Efua', 'customerId': 30});
    expect(find.text('ORD-9'), findsOneWidget);

    // Pay: cash with two tills open asks which one.
    await tester.tap(filled('Pay 20.00'));
    await tester.pumpAndSettle();
    expect(find.text('Choose the till.'), findsOneWidget);
    await enterUnder(tester, 'Cash received', '50');
    expect(find.text('30.00'), findsOneWidget, reason: 'change to give');
    await tester.tap(find.byWidgetPredicate((w) => w.runtimeType.toString().startsWith('AppSelect<int>')).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bar — S-2 (Kofi)').last);
    await tester.pumpAndSettle();
    await tester.tap(filled('Record 20.00'));
    await tester.pumpAndSettle();
    expect(paid, isTrue);
    expect(api.lastBody('/api/Restaurant/orders/9/payments'),
        {'paymentMethod': 'Cash', 'amount': 20, 'tipAmount': 0, 'reference': null, 'shiftId': 2});
    expect(api.lastBody('/api/Restaurant/orders/9/status', 'PATCH'), {'status': 'Completed'});

    // The receipt.
    expect(find.text('Receipt'), findsOneWidget);
    expect(find.text('Paid (Cash)'), findsOneWidget);
    expect(find.text('50.00'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
    expect(find.text('Osu, Accra'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('Download PDF'));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();
    expect(shared, ['Receipt_ORD-9.pdf']);
    await tester.tap(find.text('Email'));
    for (var i = 0; i < 20 && !api.writes.any((w) => w.url.path == '/api/Email/Report'); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.textContaining('Receipt emailed', findRichText: true), findsOneWidget);
    final mail = api.writes.lastWhere((w) => w.url.path == '/api/Email/Report');
    final body = utf8.decode(mail.bodyBytes, allowMalformed: true);
    expect(body.contains('efua@x.test'), isTrue);
    expect(body.contains('Your Receipt — Order ORD-9'), isTrue);
  });

  testWidgets('All Orders: filters, a status step, Completed takes payment first, detail with customer, pay later and refund', (tester) async {
    final api = FakeApi()
      ..gets['/api/Restaurant/orders'] = [
        order(1, extra: {'onlineSource': 'QR', 'customerName': 'Ama', 'customerPhone': '024', 'guestPaymentIntent': 'Cash'}),
        order(2, status: 'Served', total: 30),
        order(3, status: 'Completed', pay: 'Paid', paid: 20),
      ]
      ..gets['/api/Restaurant/orders/1'] = order(1, extra: {'onlineSource': 'QR', 'customerName': 'Ama', 'customerPhone': '024', 'guestPaymentIntent': 'Cash'})
      ..gets['/api/Restaurant/orders/1/items'] = [
        {'orderItemId': 1, 'quantity': 1, 'itemName': 'Jollof', 'lineTotal': 20, 'status': 'Pending'},
      ]
      ..gets['/api/Restaurant/orders/2'] = order(2, status: 'Served', total: 30, paid: 10, pay: 'PartiallyPaid', extra: {'customerId': 5, 'customerName': 'Kojo'})
      ..gets['/api/Restaurant/orders/2/items'] = []
      ..gets['/api/Restaurant/finance/shifts'] = []
      ..writeAnswers['/api/Restaurant/orders/1/link-customer'] = {'created': true, 'name': 'Ama', 'message': 'Saved.'};
    await open(tester, RestaurantOrdersScreen(session: await sessionFor(api), company: rest), size: tall);
    expect(find.text('ORD-1'), findsOneWidget);
    expect(find.text('ORD-3'), findsNothing, reason: 'Active hides completed orders');
    expect(find.text('ONLINE · QR'), findsOneWidget);
    expect(find.text('Awaiting confirmation'), findsOneWidget);
    expect(find.text('Plans to pay by Cash'), findsOneWidget);

    // Online only.
    await pickLast(tester, 'All Sources', 'Online only');
    expect(find.text('ORD-2'), findsNothing);
    expect(find.textContaining('online only'), findsOneWidget);
    await pickLast(tester, 'Online only', 'All Sources');

    // Placed → Confirmed.
    await tester.tap(filled('Confirmed'));
    await tester.pumpAndSettle();
    expect(api.lastBody('/api/Restaurant/orders/1/status', 'PATCH'), {'status': 'Confirmed'});

    // Served → Completed on an unpaid order opens Take payment instead.
    await tester.tap(filled('Completed'));
    await tester.pumpAndSettle();
    expect(find.text('Take payment — ORD-2'), findsOneWidget);
    expect(find.text('No till shift is open — cash will be recorded in the main cash box.'), findsOneWidget);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();

    // Detail of the online order: save the guest as a customer.
    await tester.tap(find.text('ORD-1'));
    await tester.pumpAndSettle();
    expect(find.text('Not a saved customer yet'), findsOneWidget);
    expect(find.textContaining('Not yet confirmed — the kitchen cannot see this order', findRichText: true), findsOneWidget);
    await tester.tap(find.text('Add this person as a customer'));
    await tester.pumpAndSettle();
    expect(api.writes.any((w) => w.method == 'POST' && w.url.path == '/api/Restaurant/orders/1/link-customer'), isTrue);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    // Detail of the part-paid order with a saved customer: Pay later, then Refund.
    await tester.tap(find.text('ORD-2'));
    await tester.pumpAndSettle();
    expect(find.text('Saved as a customer.'), findsOneWidget);
    expect(find.text('10.00 (PartiallyPaid)'), findsOneWidget);
    await tester.tap(find.text('Pay later'));
    await tester.pumpAndSettle();
    expect(find.textContaining('20.00 is owed by Kojo'), findsOneWidget);
    await tester.tap(filled('Complete as pay later'));
    await tester.pumpAndSettle();
    expect(api.lastBody('/api/Restaurant/orders/2/pay-later'), {'farmId': 'farm-1', 'dueDate': null, 'notes': null});
    await tester.tap(find.text('Refund'));
    await tester.pumpAndSettle();
    expect(find.text('Give a reason.'), findsOneWidget);
    await reasonPick(tester, 'Long wait');
    await tester.tap(filled('Refund 10.00'));
    await tester.pumpAndSettle();
    expect(api.lastBody('/api/Restaurant/orders/2/refunds'), {'amount': 10, 'paymentMethod': 'Cash', 'reason': 'Long wait', 'shiftId': null});
  });

  testWidgets('New Guest Orders: the card, accept, and reject with a reason', (tester) async {
    final api = FakeApi()
      ..gets['/api/Restaurant/online/pending-orders'] = [
        {'orderId': 5, 'orderNumber': 'ORD-5', 'orderType': 'DineIn', 'onlineSource': 'QR', 'tableNumber': '3', 'waitingMinutes': 11.4,
          'customerName': 'Yaw', 'customerPhone': '020', 'guestPaymentIntent': 'MobileMoney', 'itemCount': 2, 'itemSummary': '2x Jollof',
          'notes': 'No pepper', 'totalAmount': 20},
      ]
      ..writeAnswers['/api/Restaurant/online/orders/5/accept'] = {'message': 'Sent to the kitchen.'};
    await open(tester, RestaurantPendingOrdersScreen(session: await sessionFor(api), company: rest), size: tall);
    expect(find.text('Table 3'), findsOneWidget);
    expect(find.text('11m'), findsOneWidget);
    expect(find.text('2 items'), findsOneWidget);
    expect(find.text('“No pepper”'), findsOneWidget);
    expect(find.text('Plans to pay by MobileMoney'), findsOneWidget);
    await tester.tap(find.text('Sound on'));
    await tester.pump();
    expect(find.text('Sound off'), findsOneWidget);
    await tester.tap(filled('Accept'));
    await tester.pumpAndSettle();
    expect(api.writes.any((w) => w.url.path == '/api/Restaurant/online/orders/5/accept'), isTrue);
    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    expect(find.text('Reject order ORD-5?'), findsOneWidget);
    await reasonPick(tester, 'Kitchen is closed');
    await tester.tap(filled('Reject order'));
    await tester.pumpAndSettle();
    expect(api.lastBody('/api/Restaurant/online/orders/5/reject'), {'reason': 'Kitchen is closed'});
  });

  testWidgets('Kitchen Display: stations, a card per order, bump, recall, bump all, Expo', (tester) async {
    final api = FakeApi()
      ..gets['/api/Restaurant/kds/stations'] = [
        {'kdsStationId': 1, 'name': 'Grill', 'displayColor': '#dc2626', 'isActive': true, 'isExpo': false},
        {'kdsStationId': 2, 'name': 'Old', 'isActive': false},
      ]
      ..gets['/api/Restaurant/kds/queue'] = [
        {'orderItemId': 100, 'orderId': 9, 'orderNumber': 'ORD-9', 'orderType': 'DineIn', 'tableNumber': '4', 'quantity': 2, 'itemName': 'Jollof',
          'status': 'Pending', 'elapsedMinutes': 3, 'notes': 'No pepper'},
        {'orderItemId': 101, 'orderId': 9, 'orderNumber': 'ORD-9', 'orderType': 'DineIn', 'tableNumber': '4', 'quantity': 1, 'itemName': 'Sobolo',
          'status': 'Preparing', 'elapsedMinutes': 12},
      ]
      ..gets['/api/Restaurant/kds/stats'] = {'pendingCount': 1, 'preparingCount': 1, 'readyCount': 0, 'avgPrepMinutes': 7.25, 'longestWaitMinutes': 16}
      ..writeAnswers['/api/Restaurant/kds/bump/100'] = {'newStatus': 'Preparing'};
    await open(tester, RestaurantKdsScreen(session: await sessionFor(api), company: rest), size: tall);
    expect(find.text('Grill'), findsOneWidget);
    expect(find.text('Old'), findsNothing, reason: 'inactive stations are hidden');
    expect(find.text('ORD-9'), findsOneWidget, reason: 'one card per order');
    expect(find.text('T4'), findsOneWidget);
    expect(find.text('12m'), findsOneWidget, reason: 'the oldest item');
    expect(find.text('* No pepper'), findsOneWidget);
    expect(find.text('Max: 16m'), findsOneWidget);
    expect(find.text('Avg: 7.3m'), findsOneWidget);
    expect(find.text('Recall'), findsOneWidget, reason: 'only the item past Pending');
    await tester.tap(find.text('Bump').first);
    await tester.pumpAndSettle();
    expect(find.text('Item bumped to Preparing'), findsOneWidget);
    await tester.tap(find.text('Recall'));
    await tester.pumpAndSettle();
    expect(api.writes.any((w) => w.url.path == '/api/Restaurant/kds/recall/101'), isTrue);
    await tester.tap(find.text('Bump All'));
    await tester.pumpAndSettle();
    expect(api.writes.any((w) => w.url.path == '/api/Restaurant/kds/bump-order/9'), isTrue);
    await tester.tap(find.text('Grill'));
    await tester.pumpAndSettle();
    expect(api.requests.last.url.path == '/api/Restaurant/kds/stats' || api.requests.last.url.path == '/api/Restaurant/kds/queue', isTrue);
    expect(api.requests.any((r) => r.url.path == '/api/Restaurant/kds/queue' && r.url.queryParameters['stationId'] == '1'), isTrue);
    await tester.tap(find.text('Expo'));
    await tester.pumpAndSettle();
    expect(api.requests.any((r) => r.url.path == '/api/Restaurant/kds/queue' && r.url.queryParameters['isExpo'] == 'true'), isTrue);
  });
}
