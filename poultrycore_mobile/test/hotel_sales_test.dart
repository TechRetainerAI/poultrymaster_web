// Hotel → Sales, Expenses & Money → Sales: Sales, Payments and Customer
// Balances, at phone width against a fake API.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/hotel/hotel_sales_screen.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/sales/balances_logic.dart';
import 'package:poultrycore_mobile/pages/poultry/sales/balances_widgets.dart' show RecordPaymentScreen;
import 'package:poultrycore_mobile/pages/poultry/sales/customer_balances_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/sales/payments_received_screen.dart';

import 'support/harness.dart';

final hotel = Company(farmId: 'h1', name: 'Palm Hotel', type: CompanyType.hotel, role: 'Admin');
const tall = Size(360, 4200);

FakeApi salesApi() => FakeApi()
  ..gets['/api/Hotel/sales'] = [
    {'documentType': 'Stay', 'documentId': 31, 'partyId': 7, 'partyName': 'Kofi Mensah', 'docDate': '2026-10-20T10:00:00', 'reference': 'BK-31',
      'label': 'Room 101 · 3 nights', 'totalAmount': 900, 'amountPaid': 300, 'balance': 600, 'paymentMethod': 'Cash', 'paymentStatus': 'Partial',
      'nights': 3, 'roomNumber': '101', 'bookingStatus': 'CheckedOut', 'billedToAccount': false},
    {'documentType': 'Stay', 'documentId': 32, 'partyName': 'Ama Owusu', 'docDate': '2026-10-21T10:00:00', 'reference': 'BK-32',
      'totalAmount': 400, 'amountPaid': 400, 'balance': 0, 'paymentStatus': 'Paid', 'nights': 2, 'bookingStatus': 'CheckedIn'},
    {'documentType': 'Order', 'documentId': 9, 'partyName': 'Walk-in', 'docDate': '2026-10-22T13:00:00', 'reference': 'ORD-9',
      'totalAmount': 80, 'amountPaid': 80, 'balance': 0, 'paymentStatus': 'Paid'},
  ]
  ..gets['/api/Hotel/finance/cash-accounts'] = [
    {'hotelcashaccountid': 5, 'accountname': 'Front desk till', 'currentbalance': 1200, 'isactive': true},
  ]
  ..gets['/api/Hotel/customers'] = [
    {'hotelCustomerId': 3, 'customerName': 'Acme Ltd', 'isActive': true},
  ];

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).first);
  await tester.pumpAndSettle();
}

void main() {
  test('the three Sales rows open native screens; the Hotel rail builds on /api/Hotel/balances', () {
    for (final h in ['/hotel-sales', '/hotel-payments', '/hotel-customer-balances']) {
      expect(pageScreens.containsKey(h), isTrue, reason: h);
    }
    expect(BalanceRail.hotel.isHotel, isTrue);
    expect(BalanceRail.hotel.cashAccountsPath, '/api/Hotel/finance/cash-accounts');
    expect(BalanceRail.hotel.cashAccountIdKey, 'hotelCashAccountId');
    expect(BalanceRail.hotel.supplierDocumentHref({'documentType': 'Purchase', 'documentId': 4}), '/hotel-inventory?purchaseId=4');
  });

  test('a sale as the shared view shows it', () {
    final r = hotelSaleRow(salesApi().gets['/api/Hotel/sales'] is List ? (salesApi().gets['/api/Hotel/sales'] as List).first as Map : {});
    expect((r.reference, r.nights, r.status, r.method), ('BK-31', 3, 'Partial', 'Cash'));
    expect(r.details, [('Type', 'Stay'), ('Room', '101'), ('Booking', 'CheckedOut')]);
    final order = hotelSaleRow({'documentType': 'Order', 'documentId': 9, 'totalAmount': 50, 'amountPaid': 0, 'balance': 50, 'docDate': '2026-10-01'});
    expect((order.reference, order.product, order.status), ('#9', 'Restaurant order', 'Pending'));
  });

  group('Sales', () {
    testWidgets('cards, filters, and the actions per row', (tester) async {
      final api = salesApi();
      await open(tester, HotelSalesScreen(session: await sessionFor(api), company: hotel), size: tall);
      expect(find.text('Stays and restaurant sales, what was paid and what is still owed'), findsOneWidget);
      expect(find.text('3 transactions'), findsOneWidget);
      expect(find.text('5'), findsWidgets, reason: 'room nights 3 + 2');
      // Pay only on the stay with money owed; Bill to account only on the checked-out one.
      expect(find.widgetWithText(OutlinedButton, 'Pay'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Bill to account'), findsOneWidget);
      // The walk-in order has Invoice only.
      expect(find.widgetWithText(OutlinedButton, 'Invoice'), findsNWidgets(3));
      expect(find.widgetWithText(OutlinedButton, 'Delete'), findsNWidgets(2));

      await tester.enterText(find.byType(TextField).first, 'ORD');
      await tester.pumpAndSettle();
      expect(find.text('1 transactions'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pumpAndSettle();

      await tapText(tester, 'Filters');
      await pick(tester, 'All sales', 'Stays');
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(find.text('2 transactions'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Pay opens Record payment on the stay, with the hotel accounts', (tester) async {
      final api = salesApi();
      await open(tester, HotelSalesScreen(session: await sessionFor(api), company: hotel), size: tall);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Pay'));
      await tester.pumpAndSettle();
      final screen = tester.widget<RecordPaymentScreen>(find.byType(RecordPaymentScreen));
      expect(screen.api, '/api/Hotel/balances');
      expect(screen.single!['documentType'], 'Stay');
      expect(screen.single!['documentId'], 31);
      expect(screen.cashAccounts.single['name'], 'Front desk till');
    });

    testWidgets('Bill to account posts the customer; Delete cancels the stay', (tester) async {
      final api = salesApi();
      await open(tester, HotelSalesScreen(session: await sessionFor(api), company: hotel), size: tall);
      await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Bill to account'));
      await tester.tap(find.widgetWithText(OutlinedButton, 'Bill to account'));
      await tester.pumpAndSettle();
      expect(find.textContaining('moves from the guest to a corporate account'), findsOneWidget);
      await pick(tester, 'Select a customer', 'Acme Ltd');
      await tester.tap(find.widgetWithText(FilledButton, 'Bill to account'));
      await tester.pumpAndSettle();
      final w = api.writes.lastWhere((w) => w.url.path == '/api/Hotel/sales/31/bill-to');
      expect(jsonDecode(w.body), {'farmId': 'h1', 'hotelCustomerId': 3});

      await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Delete').first);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Delete').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('The booking is cancelled and its room freed.'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(api.writes.any((w) => w.method == 'DELETE' && w.url.path == '/api/Hotel/sales/31'), isTrue);
    });

    testWidgets('Payments reads the history for that stay', (tester) async {
      final api = salesApi();
      await open(tester, HotelSalesScreen(session: await sessionFor(api), company: hotel), size: tall);
      await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Payments').first);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Payments').first);
      await tester.pumpAndSettle();
      final r = api.requests.lastWhere((r) => r.url.path == '/api/Hotel/balances/customer-payments');
      // The customer side asks by sale (paymentQuery): the booking id.
      expect(r.url.queryParameters['saleId'], '31');
    });

    testWidgets('one stay from a balance page: banner and Show all sales', (tester) async {
      await open(tester, HotelSalesScreen(session: await sessionFor(salesApi()), company: hotel, focusBookingId: 32), size: tall);
      expect(find.text('Showing one stay.'), findsOneWidget);
      expect(find.text('1 transactions'), findsOneWidget);
      await tapText(tester, 'Show all sales');
      expect(find.text('3 transactions'), findsOneWidget);
    });
  });

  testWidgets('Payments and Customer Balances read the Hotel routes and accounts', (tester) async {
    final api = salesApi()
      ..gets['/api/Hotel/balances/customer-payments'] = [
        {'paymentId': 'HP-1', 'partyName': 'Kofi Mensah', 'amount': 300, 'paymentDate': '2026-10-20', 'status': 'Posted', 'saleId': 31},
      ]
      ..gets['/api/Hotel/balances/customer-balances'] = [
        {'partyId': 7, 'partyName': 'Kofi Mensah', 'totalBalance': 600, 'openDocumentCount': 1},
      ]
      ..gets['/api/Hotel/balances/customer-balances/summary'] = {'totalBalance': 600, 'partyCount': 1};
    await open(tester, PaymentsReceivedScreen(session: await sessionFor(api), company: hotel, rail: BalanceRail.hotel), size: tall);
    expect(api.requests.any((r) => r.url.path == '/api/Hotel/balances/customer-payments'), isTrue);
    expect(api.requests.any((r) => r.url.path.startsWith('/api/Poultry')), isFalse);
    expect(find.text('Payments received'), findsWidgets);
    expect(find.textContaining('Kofi Mensah'), findsWidgets);

    await open(tester, CustomerBalancesScreen(session: await sessionFor(api), company: hotel, rail: BalanceRail.hotel), size: tall);
    expect(api.requests.any((r) => r.url.path == '/api/Hotel/balances/customer-balances'), isTrue);
    expect(api.requests.any((r) => r.url.path == '/api/Hotel/finance/cash-accounts'), isTrue);
    expect(api.requests.any((r) => r.url.path.startsWith('/api/Poultry')), isFalse);
    expect(find.textContaining('Kofi Mensah'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
