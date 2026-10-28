// Hotel → Setup → Finance (Customers, Suppliers) and Facilities (Supplies,
// Maintenance), at phone width against a fake API.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/hotel/hotel_maintenance_screen.dart';
import 'package:poultrycore_mobile/pages/hotel/hotel_parties_screen.dart';
import 'package:poultrycore_mobile/pages/hotel/hotel_supplies_screen.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';

import 'support/harness.dart';

final hotel = Company(farmId: 'h1', name: 'Palm Hotel', type: CompanyType.hotel, role: 'Admin');
const tallPhone = Size(360, 3000);

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

Future<void> tapTip(WidgetTester tester, String tip, {int index = 0}) async {
  await tester.ensureVisible(find.byTooltip(tip).at(index));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip(tip).at(index));
  await tester.pumpAndSettle();
}

/// [pick] for a dropdown inside the open dialog.
Future<void> pickIn(WidgetTester tester, String shown, String option) async {
  final f = find.descendant(of: find.byType(AlertDialog), matching: find.text(shown)).first;
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Map<String, dynamic> lastWrite(FakeApi api, String path, String method) =>
    jsonDecode(api.writes.lastWhere((w) => w.url.path == path && w.method == method).body) as Map<String, dynamic>;

Future<void> save(WidgetTester tester, String label) async {
  final f = find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(FilledButton, label));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  test('the four rows open native screens', () {
    for (final h in ['/hotel-customers', '/hotel-suppliers', '/hotel-inventory', '/hotel-maintenance']) {
      expect(pageScreens.containsKey(h), isTrue, reason: h);
    }
  });

  group('Customers', () {
    FakeApi api() => FakeApi()
      ..gets['/api/Hotel/customers'] = [
        {'hotelCustomerId': 1, 'customerName': 'Acme Ltd', 'customerType': 'Corporate', 'phone': '0244', 'email': 'ap@acme.test',
          'paymentTermDays': 30, 'creditLimit': 5000, 'openingBalance': 0, 'currentBalance': 1200.5, 'isActive': true},
        {'hotelCustomerId': 2, 'customerName': 'Ministry of Tourism', 'customerType': 'Government', 'currentBalance': 0, 'isActive': false},
      ]
      ..gets['/api/Hotel/customers/balance-summary'] = {'totalCustomers': 2, 'customersOwing': 1, 'totalBalance': 1200.5}
      ..gets['/api/Hotel/customers/1'] = {'hotelCustomerId': 1, 'customerName': 'Acme Ltd', 'customerType': 'Corporate', 'phone': '0244',
        'paymentTermDays': 30, 'currentBalance': 1200.5}
      ..gets['/api/Hotel/customers/1/ledger'] = [
        {'hotelCustomerLedgerId': 9, 'transactionDate': '2026-10-01T00:00:00', 'transactionType': 'InvoiceCredit', 'description': 'Room 101',
          'invoiceId': 44, 'debitAmount': 1200.5, 'creditAmount': 0, 'balanceAfterTransaction': 1200.5},
      ];

    testWidgets('summary, statuses, search; new, edit, delete; the statement', (tester) async {
      final a = api();
      await open(tester, HotelPartiesScreen(session: await sessionFor(a), company: hotel, kind: HotelPartyKind.customers), size: tallPhone);
      for (final t in ['Total Customers', 'Customers Owing', 'Total Balance Owed', '1,200.50', 'Owed', 'Inactive']) {
        expect(find.text(t), findsWidgets, reason: t);
      }
      await tester.enterText(find.byType(TextField).first, 'gov');
      await tester.pumpAndSettle();
      expect(find.text('Acme Ltd'), findsNothing);
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pumpAndSettle();

      await tapText(tester, 'New Customer');
      expect(find.text('Add a new credit customer'), findsOneWidget);
      await save(tester, 'Create');
      expect(find.textContaining('Name required'), findsOneWidget);
      await enter(tester, 'Customer Name *', 'Golden Tours');
      await pickIn(tester, 'Corporate', 'TravelAgent');
      await enter(tester, 'Credit Limit', '2500');
      await enter(tester, 'Opening Balance', '300');
      await save(tester, 'Create');
      final b = lastWrite(a, '/api/Hotel/customers', 'POST');
      expect((b['customerName'], b['customerType'], b['creditLimit'], b['openingBalance'], b['farmId']),
          ('Golden Tours', 'TravelAgent', 2500.0, 300.0, 'h1'));

      await tapTip(tester, 'Edit');
      expect(find.text('Edit Customer'), findsOneWidget);
      expect(find.text('Opening Balance'), findsNothing);
      await save(tester, 'Update');
      expect(lastWrite(a, '/api/Hotel/customers/1', 'PUT')['paymentTermDays'], 30);

      await tapTip(tester, 'Delete');
      expect(find.textContaining('Are you sure you want to delete "Acme Ltd"?'), findsOneWidget);
      await save(tester, 'Delete');
      expect(a.writes.any((w) => w.method == 'DELETE' && w.url.path == '/api/Hotel/customers/1'), isTrue);

      await tapTip(tester, 'View statement');
      expect(find.text('Acme Ltd — Statement'), findsWidgets);
      for (final t in ['30 days', 'Balance Owed', 'InvoiceCredit', 'Inv #44', 'Room 101']) {
        expect(find.text(t), findsWidgets, reason: t);
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('Suppliers', () {
    testWidgets('summary, ten to a page, new with location', (tester) async {
      final a = FakeApi()
        ..gets['/api/Hotel/suppliers'] = [
          for (var i = 1; i <= 12; i++)
            {'hotelSupplierId': i, 'supplierName': 'Supplier $i', 'supplierType': 'ProductSupplier', 'currentBalance': i == 1 ? 80 : 0, 'isActive': true},
        ]
        ..gets['/api/Hotel/suppliers/balance-summary'] = {'totalSuppliers': 12, 'suppliersOwed': 1, 'totalBalance': 80};
      await open(tester, HotelPartiesScreen(session: await sessionFor(a), company: hotel, kind: HotelPartyKind.suppliers), size: tallPhone);
      expect(find.text('1 suppliers'), findsOneWidget);
      expect(find.text('Total Payable'), findsOneWidget);
      expect(find.text('Supplier 10'), findsOneWidget);
      expect(find.text('Supplier 11'), findsNothing);

      await tapText(tester, 'New Supplier');
      await enter(tester, 'Supplier Name *', 'Linen Co');
      await enter(tester, 'Location', 'Tema');
      await save(tester, 'Create');
      final b = lastWrite(a, '/api/Hotel/suppliers', 'POST');
      expect((b['supplierName'], b['supplierType'], b['location'], b.containsKey('creditLimit')), ('Linen Co', 'ProductSupplier', 'Tema', false));
      expect(tester.takeException(), isNull);
    });
  });

  group('Supplies', () {
    FakeApi api() => FakeApi()
      ..gets['/api/Hotel/inventory'] = [
        {'hotelinventoryitemid': 1, 'name': 'Soap', 'category': 'Toiletries', 'unit': 'pcs', 'stockonhand': 4, 'reorderlevel': 10, 'unitcost': 2.5},
        {'hotelInventoryItemId': 2, 'name': 'Towel', 'category': 'Linen', 'unit': 'pcs', 'stockOnHand': 50, 'reorderLevel': 10, 'unitCost': 30},
      ]
      ..gets['/api/Hotel/setup/supply-categories'] = [
        {'description': 'Toiletries'},
        {'description': 'Linen'},
        {'description': 'Other'},
      ]
      ..gets['/api/Hotel/setup/supply-items'] = [
        {'description': 'Shampoo', 'category': 'Toiletries'},
        {'description': 'Bath towel', 'category': 'Linen'},
      ]
      ..gets['/api/Hotel/supplies/purchases'] = [
        {'purchaseId': 5, 'purchaseDate': '2026-10-20T00:00:00', 'itemId': 1, 'itemName': 'Soap', 'supplierName': 'Linen Co', 'quantity': 100,
          'unit': 'pcs', 'totalCost': 250, 'amountPaid': 100, 'allocated': 0, 'balance': 150, 'paymentStatus': 'PartiallyPaid',
          'costMode': 'EXPENSE_WHEN_PURCHASED', 'status': 'Posted'},
      ]
      ..gets['/api/Hotel/supplies/cost-recognition'] = [
        {'category': 'Toiletries', 'costMode': 'EXPENSE_WHEN_PURCHASED', 'itemCount': 1},
      ]
      ..gets['/api/Hotel/suppliers'] = [
        {'hotelSupplierId': 3, 'supplierName': 'Linen Co', 'isActive': true},
      ]
      ..gets['/api/Hotel/finance/cash-accounts'] = [
        {'hotelcashaccountid': 7, 'accountname': 'Front desk till', 'currentbalance': 900, 'isactive': true},
      ];

    testWidgets('items with Low, purchases, cost recognition, reverse', (tester) async {
      final a = api();
      await open(tester, HotelSuppliesScreen(session: await sessionFor(a), company: hotel), size: tallPhone);
      expect(find.text('Supplies & Inventory  (2)', findRichText: true), findsOneWidget);
      expect(find.text('Low'), findsOneWidget);
      expect(find.text('Stock 4 pcs'), findsOneWidget);
      expect(find.text('PO-5'), findsOneWidget);
      expect(find.text('PartiallyPaid'), findsOneWidget);

      // The purchase card shows the same words; the picker is the last one.
      await tapText(tester, 'Expense when purchased');
      await tester.tap(find.text('Expense when consumed').last);
      await tester.pumpAndSettle();
      expect(lastWrite(a, '/api/Hotel/supplies/cost-recognition', 'PUT'),
          {'farmId': 'h1', 'category': 'Toiletries', 'costMode': 'EXPENSE_WHEN_CONSUMED'});

      await tapTip(tester, 'Reverse purchase');
      final reverse = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Reverse'));
      expect(reverse.onPressed, isNull, reason: 'a reason is required');
      await pickIn(tester, 'Select a reason', 'Duplicate entry');
      await save(tester, 'Reverse');
      expect(lastWrite(a, '/api/Hotel/supplies/purchases/5/reverse', 'POST'), {'farmId': 'h1', 'reason': 'Duplicate entry'});
      expect(tester.takeException(), isNull);
    });

    testWidgets('Add Item: the category filters the names; "Other" is remembered', (tester) async {
      final a = api();
      await open(tester, HotelSuppliesScreen(session: await sessionFor(a), company: hotel), size: tallPhone);
      await tapText(tester, 'Add Item');
      await save(tester, 'Add');
      expect(find.textContaining('Name required'), findsOneWidget);
      await pickIn(tester, 'Select category', 'Linen');
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Select item')).first);
      await tester.pumpAndSettle();
      expect(find.text('Shampoo'), findsNothing, reason: 'only Linen items are offered');
      await tester.tap(find.text('Other (type name)').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)).first, 'Hand towel');
      await tester.pumpAndSettle();
      await save(tester, 'Add');
      final b = lastWrite(a, '/api/Hotel/inventory', 'POST');
      expect((b['name'], b['category'], b['unit'], b['reorderLevel']), ('Hand towel', 'Linen', 'pcs', 10.0));
      expect(lastWrite(a, '/api/Hotel/custom-options', 'POST'), {'farmId': 'h1', 'listKey': 'SupplyItemName', 'value': 'Hand towel'});
    });

    testWidgets('Record Purchase: paid follows the total; on credit the supplier is required', (tester) async {
      final a = api();
      await open(tester, HotelSuppliesScreen(session: await sessionFor(a), company: hotel), size: tallPhone);
      await tapText(tester, 'Record Purchase');
      expect(find.text('New purchase'), findsOneWidget);
      await pickIn(tester, 'Pick item', 'Towel (pcs) · Linen');
      await enter(tester, 'Purchase quantity (pcs) *', '20');
      await enter(tester, 'Total purchase cost *', '600');
      expect(find.textContaining('30.00 per pcs'), findsOneWidget);
      await pickIn(tester, 'Cash', 'Credit');
      await save(tester, 'Save');
      expect(find.textContaining('Choose the supplier'), findsOneWidget);
      await pickIn(tester, 'Not linked to a supplier', 'Linen Co');
      await save(tester, 'Save');
      final b = lastWrite(a, '/api/Hotel/supplies/purchases', 'POST');
      expect((b['itemId'], b['quantity'], b['totalCost'], b['amountPaid'], b['supplierId'], b['cashAccountId'], b['paymentMethod']),
          (2, 20.0, 600.0, 0, 3, null, 'Credit'));
      expect(tester.takeException(), isNull);
    });
  });

  group('Maintenance', () {
    testWidgets('open badge, status filter, change status, new request', (tester) async {
      final a = FakeApi()
        ..gets['/api/Hotel/maintenance'] = [
          {'hotelMaintenanceRequestId': 1, 'roomNumber': '101', 'assetDescription': 'Air conditioner', 'issueDescription': 'Not cooling',
            'priority': 'High', 'status': 'Open', 'estimatedCost': 150, 'reportedAt': '2026-10-24T09:00:00'},
          {'hotelmaintenancerequestid': 2, 'assetdescription': 'Lobby lights', 'issuedescription': 'Flicker', 'priority': 'Low',
            'status': 'Completed', 'estimatedcost': 20},
        ]
        ..gets['/api/Hotel/rooms'] = [
          {'hotelRoomId': 100, 'roomNumber': '101', 'floorName': 'Ground Floor', 'roomTypeName': 'Deluxe'},
        ]
        ..gets['/api/Hotel/setup/maintenance-assets'] = [
          {'description': 'Air conditioner'},
          {'description': 'Plumbing'},
        ];
      await open(tester, HotelMaintenanceScreen(session: await sessionFor(a), company: hotel), size: tallPhone);
      expect(find.text('1 open'), findsOneWidget);
      expect(find.text('General'), findsOneWidget);
      expect(find.text('Lobby lights'), findsOneWidget);
      await tapText(tester, 'Open (1)');
      expect(find.text('Lobby lights'), findsNothing);
      await tapText(tester, 'All (2)');

      await tester.tap(find.text('Change...').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('InProgress').last);
      await tester.pumpAndSettle();
      expect(lastWrite(a, '/api/Hotel/maintenance/1/status', 'PATCH'), {'status': 'InProgress'});

      await tapText(tester, 'New Request');
      await save(tester, 'Submit Request');
      expect(find.textContaining('Issue description required'), findsOneWidget);
      await pickIn(tester, 'General / Common Area', 'Room 101 — Ground Floor (Deluxe)');
      await pickIn(tester, 'Select asset/area', 'Plumbing');
      await enter(tester, 'Issue Description *', 'Leaking tap');
      await pickIn(tester, 'Normal', 'Critical');
      await save(tester, 'Submit Request');
      expect(lastWrite(a, '/api/Hotel/maintenance', 'POST'), {
        'hotelRoomId': 100, 'assetDescription': 'Plumbing', 'issueDescription': 'Leaking tap', 'priority': 'Critical', 'estimatedCost': 0.0,
        'farmId': 'h1',
      });
      expect(tester.takeException(), isNull);
    });
  });
}
