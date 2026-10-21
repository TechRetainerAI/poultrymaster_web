// Poultry → Customer Credits and Supplier Credits (migrations 363, 367, 370),
// against a fake API, at phone size.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/lookup_loader.dart';
import 'package:poultrycore_mobile/pages/poultry/expenses/supplier_credits_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/sales/customer_credits_screen.dart';

import 'support/harness.dart';

const cBase = '/api/Poultry/customer-payments';
const sBase = '/api/Poultry/supplier-credits';

/// Phone width; tall enough that the list under the tiles is built.
const tallPhone = Size(360, 2000);

Future<void> tapLast(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

/// Opens the dropdown showing [shown] (the last one, i.e. inside the dialog)
/// and picks the option containing [option].
Future<void> choose(WidgetTester tester, String shown, String option) async {
  await tester.ensureVisible(find.text(shown).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(shown).last);
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining(option).last);
  await tester.pumpAndSettle();
}

FakeApi customerApi() => FakeApi()
  ..gets['$cBase/credit'] = [
    {'customerId': 5, 'customerName': 'Ama Stores', 'availableCredit': 150, 'paymentCount': 2, 'outstanding': 40},
  ]
  ..gets['$cBase/refunds'] = [
    {
      'refundId': 9, 'refundNumber': 'RF-0001', 'customerId': 5, 'customerName': 'Ama Stores', 'amount': 20,
      'refundDate': '2026-10-10', 'accountName': 'Cash box', 'paymentMethod': 'Cash', 'reason': 'Overpayment returned',
      'status': 'Posted', 'paymentNumbers': 'PAY-0010',
    },
  ]
  ..gets['$cBase/credit/manual'] = [
    {
      'paymentGroupId': 'g-1', 'poultryPaymentId': 31, 'paymentNumber': 'PAY-0012', 'kind': 'Deposit', 'creditDate': '2026-10-09',
      'customerId': 5, 'customerName': 'Ama Stores', 'amount': 100, 'used': 0, 'refunded': 0, 'remaining': 100, 'status': 'Posted',
      'cashAccountName': 'Cash box', 'paymentMethod': 'Cash', 'reason': 'Advance for next order',
    },
  ]
  ..gets['$cBase/credit/events'] = [
    {
      'poultryPaymentId': 31, 'paymentGroupId': 'g-1', 'paymentNumber': 'PAY-0012', 'creditDate': '2026-10-09', 'customerId': 5,
      'customerName': 'Ama Stores', 'source': 'Customer advance', 'originalAmount': 100, 'applied': 0, 'refunded': 0,
      'available': 100, 'status': 'Available', 'isManual': true,
    },
    {
      'poultryPaymentId': 30, 'paymentNumber': 'PAY-0010', 'creditDate': '2026-10-05', 'customerId': 5, 'customerName': 'Ama Stores',
      'source': 'Sale reversal - payment kept', 'originalAmount': 70, 'applied': 0, 'refunded': 20, 'available': 50,
      'status': 'Partly used', 'isManual': false,
    },
  ]
  ..gets['/api/Poultry/cash-accounts'] = [
    {'poultryCashAccountId': 3, 'accountName': 'Cash box', 'currentBalance': 500, 'isActive': true},
  ]
  ..gets['/api/Customer'] = [
    {'customerId': 5, 'name': 'Ama Stores'},
  ];

FakeApi supplierApi() => FakeApi()
  ..gets[sBase] = [
    {'supplierId': 8, 'supplierName': 'Feed Co', 'availableCredit': 300, 'creditCount': 2, 'owed': 120},
  ]
  ..gets['$sBase/applications'] = [
    {
      'allocationId': 4, 'poultrySupplierPaymentId': 51, 'creditNumber': 'SP-0003', 'supplierId': 8, 'supplierName': 'Feed Co',
      'documentType': 'RawMaterialPurchase', 'documentId': 12, 'reference': 'INV-77', 'label': 'Maize', 'amount': 60,
      'appliedDate': '2026-10-11', 'status': 'Posted',
    },
  ]
  ..gets['$sBase/events'] = [
    {
      'poultrySupplierPaymentId': 51, 'creditNumber': 'SP-0003', 'creditDate': '2026-10-08', 'supplierId': 8, 'supplierName': 'Feed Co',
      'source': 'Supplier advance', 'sourceType': 'SupplierCredits', 'originalAmount': 250, 'applied': 60, 'refunded': 0,
      'available': 190, 'status': 'Partly used', 'isManual': true, 'poultryCashAccountId': 3, 'accountName': 'Cash box',
    },
    {
      'poultrySupplierPaymentId': 52, 'creditNumber': 'SP-0004', 'creditDate': '2026-10-09', 'supplierId': 8, 'supplierName': 'Feed Co',
      'source': 'Credit note', 'sourceType': 'SupplierCreditNote', 'originalAmount': 110, 'applied': 0, 'refunded': 0,
      'available': 110, 'status': 'Available', 'isManual': true,
    },
  ]
  ..gets['/api/Poultry/supplier-balances/8/open-purchases'] = [
    {'documentType': 'RawMaterialPurchase', 'documentId': 13, 'reference': 'INV-80', 'label': 'Soya', 'balance': 120},
  ]
  ..gets['/api/Poultry/cash-accounts'] = [
    {'poultryCashAccountId': 3, 'accountName': 'Cash box', 'currentBalance': 500, 'isActive': true},
  ]
  ..gets['/api/Supplier'] = [
    {'supplierId': 8, 'name': 'Feed Co'},
  ];

void main() {
  setUp(LookupLoader.clear);

  group('Customer Credits', () {
    testWidgets('held credit, one credit refunded with an Other reason', (tester) async {
      final api = customerApi();
      await open(tester, CustomerCreditsScreen(session: await sessionFor(api), company: adminCompany), size: tallPhone);
      expect(find.text('Customer Credits'), findsWidgets);
      expect(find.text('They still owe (not netted)'), findsOneWidget);
      expect(find.text('Ama Stores'), findsOneWidget);
      expect(find.text('2 credits'), findsOneWidget);

      await tapLast(tester, 'Credits');
      expect(find.text("Ama Stores's credits"), findsOneWidget);
      expect(find.text('PAY-0012 · Customer advance'), findsOneWidget);
      expect(find.text('PAY-0010 · Sale reversal - payment kept'), findsOneWidget);
      // The manual credit can be reversed from here; the kept payment cannot.
      expect(find.text('Reverse'), findsOneWidget);

      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Refund')).first);
      await tester.pumpAndSettle();
      expect(find.text('Refund customer credit'), findsOneWidget);
      expect(find.textContaining('PAY-0012 · Customer advance', findRichText: true), findsWidgets, reason: 'the credit label');
      expect(find.textContaining('Available on this credit'), findsOneWidget);

      await choose(tester, 'Select a reason', 'Other');
      await tester.enterText(find.byType(TextFormField).last, 'Customer moved away');
      await tester.pumpAndSettle();
      await tapLast(tester, 'Refund');

      final body = api.lastBody('$cBase/refunds');
      expect(body['poultryPaymentId'], 31);
      expect(body['reason'], 'Customer moved away');
      expect(body['amount'], 100);
      expect(body['poultryCashAccountId'], 3);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Add credit: a customer advance with account, method and a listed reason', (tester) async {
      final api = customerApi();
      await open(tester, CustomerCreditsScreen(session: await sessionFor(api), company: adminCompany), size: tallPhone);
      await tapLast(tester, 'Add credit');
      expect(find.text('Add customer credit'), findsOneWidget);

      await choose(tester, 'Choose the customer', 'Ama Stores');
      await tapLast(tester, 'Customer advance');
      expect(find.text('Received into *'), findsOneWidget);
      await enter(tester, 'Amount *', '75');
      await choose(tester, 'Cash', 'Mobile Money');
      await choose(tester, 'Select a reason', 'Prepayment for a bulk order');
      expect(find.textContaining('goes up by the same amount'), findsOneWidget);
      await tapLast(tester, 'Add credit');

      final body = api.lastBody('$cBase/credit/manual');
      expect(body['customerId'], 5);
      expect(body['kind'], 'Deposit');
      expect(body['amount'], 75);
      expect(body['poultryCashAccountId'], 3);
      expect(body['paymentMethod'], 'Mobile Money');
      expect(body['reason'], 'Prepayment for a bulk order');
      // The page moves to the hand-added tab.
      expect(find.text('Advance for next order'), findsOneWidget);
    });

    testWidgets('Refunds tab: a refund reversed with a reason', (tester) async {
      final api = customerApi();
      await open(tester, CustomerCreditsScreen(session: await sessionFor(api), company: adminCompany), size: tallPhone);
      await tapLast(tester, 'Refunds');
      expect(find.textContaining('RF-0001'), findsOneWidget);
      await tapLast(tester, 'Reverse refund');
      expect(find.textContaining('Reversing this refund will restore'), findsOneWidget);
      await choose(tester, 'Select a reason', 'Wrong amount');
      await tapLast(tester, 'Reverse refund');
      expect(api.lastBody('$cBase/refunds/9/reverse')['reason'], 'Wrong amount');
    });

    testWidgets('staff without the view permission are told so', (tester) async {
      final api = customerApi();
      final staff = Company(farmId: 'farm-1', name: 'Test Farm', type: CompanyType.poultry, role: 'Staff');
      await open(tester, CustomerCreditsScreen(session: await sessionFor(api), company: staff), size: tallPhone);
      expect(find.text('You do not have access to customer credits.'), findsOneWidget);
    });
  });

  group('Supplier Credits', () {
    testWidgets('credits dialog: refund only on an advance, apply to an open purchase', (tester) async {
      final api = supplierApi();
      await open(tester, SupplierCreditsScreen(session: await sessionFor(api), company: adminCompany), size: tallPhone);
      expect(find.text('Supplier Credits & Advances'), findsOneWidget);
      expect(find.text('Feed Co'), findsOneWidget);

      await tapLast(tester, 'Credits');
      expect(find.text('SP-0003 · Supplier advance'), findsOneWidget);
      expect(find.text('Apply'), findsNWidgets(2));
      expect(find.text('Refund'), findsOneWidget, reason: 'a credit note is not refunded in cash');
      expect(find.text('Reverse'), findsOneWidget, reason: 'the advance has been applied, so only the note');

      await tester.tap(find.text('Apply').first);
      await tester.pumpAndSettle();
      expect(find.text('Apply supplier credit'), findsOneWidget);
      await choose(tester, 'Choose a purchase, bill or debt', 'INV-80');
      expect(find.textContaining('At most'), findsOneWidget);
      await tapLast(tester, 'Apply credit');

      final body = api.lastBody('$sBase/apply');
      expect(body['poultrySupplierPaymentId'], 51);
      expect(body['documentType'], 'RawMaterialPurchase');
      expect(body['documentId'], 13);
      expect(body['amount'], 120);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Pay advance posts a supplier payment applied to nothing', (tester) async {
      final api = supplierApi();
      await open(tester, SupplierCreditsScreen(session: await sessionFor(api), company: adminCompany), size: tallPhone);
      await tapLast(tester, 'Pay advance');
      await choose(tester, 'Choose the supplier', 'Feed Co');
      await enter(tester, 'Amount *', '80');
      await choose(tester, 'Cash', 'Bank Transfer');
      await tapLast(tester, 'Pay advance');

      final body = api.lastBody('/api/Poultry/supplier-payments');
      expect(body['partyId'], 8);
      expect(body['amount'], 80);
      expect(body['cashAccountId'], 3);
      expect(body['paymentMethod'], 'Bank Transfer');
      expect(body['sourceType'], 'SupplierCredits');
      expect(body['allocations'], isEmpty);
    });

    testWidgets('Add credit: a credit note with a listed reason', (tester) async {
      final api = supplierApi();
      await open(tester, SupplierCreditsScreen(session: await sessionFor(api), company: adminCompany), size: tallPhone);
      await tapLast(tester, 'Add credit');
      await choose(tester, 'Choose the supplier', 'Feed Co');
      await tapLast(tester, 'Opening credit');
      await enter(tester, 'Amount *', '40');
      await choose(tester, 'Select a reason', 'Balance carried from old books');
      await tapLast(tester, 'Add credit');

      final body = api.lastBody('$sBase/manual');
      expect(body['supplierId'], 8);
      expect(body['kind'], 'SupplierOpeningCredit');
      expect(body['amount'], 40);
      expect(body['reason'], 'Balance carried from old books');
    });

    testWidgets('Applied tab: unapply with a reason', (tester) async {
      final api = supplierApi();
      await open(tester, SupplierCreditsScreen(session: await sessionFor(api), company: adminCompany), size: tallPhone);
      await tapLast(tester, 'Applied');
      expect(find.textContaining('SP-0003 → INV-77'), findsOneWidget);
      await tapLast(tester, 'Unapply');
      expect(find.textContaining('is owed again'), findsOneWidget);
      await choose(tester, 'Select a reason', 'Posted by mistake');
      await tapLast(tester, 'Unapply');
      expect(api.lastBody('$sBase/applications/4/reverse')['reason'], 'Posted by mistake');
    });
  });
}
