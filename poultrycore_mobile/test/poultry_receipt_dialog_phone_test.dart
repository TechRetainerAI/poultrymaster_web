// The receipt dialog on a real phone size with intrinsic-size checks on:
// twoUp's LayoutBuilder inside AlertDialog drew as an empty dimmed screen (2026-10-15).

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/pages/poultry/purchase_receipts_screen.dart';

import 'support/harness.dart';

const base = '/api/Poultry/purchase-receipts';
final rcv3 = {
  'poultryPurchaseReceiptId': 3, 'farmId': 'farm-1', 'receiptNumber': 'RCV-00003', 'supplierId': 4, 'supplierName': 'mo b',
  'purchaseDate': '2026-10-15T12:22:00', 'referenceNo': null, 'dueDate': '2026-10-15T00:00:00', 'subtotal': 1.0,
  'additionalCosts': 1.0, 'additionalCostsNote': null, 'totalCost': 2.0, 'amountPaid': 0.0, 'balance': 2.0,
  'amountPaidAtReceipt': 0.0, 'paymentStatus': 'Unpaid', 'isOverdue': false, 'status': 'Posted', 'paymentMethod': null,
  'cashAccountId': null, 'cashAccountName': null, 'poultrySupplierPaymentId': null, 'expensedAtPurchaseCost': 2.0,
  'deferredCost': 0.0, 'itemSummary': 'feed', 'lineCount': 1, 'notes': null, 'reversedAt': null, 'reversalReason': null,
  'reversalBlocker': null, 'createdDate': '2026-10-15T12:22:31.123456Z',
  'lines': [
    {'poultryPurchaseReceiptLineId': 7, 'itemName': 'feed', 'quantity': 1.0, 'unitCost': 1.0, 'lineTotal': 2.0,
      'allocatedAdditionalCost': 1.0, 'landedUnitCost': 2.0, 'productionUnitsPerPurchaseUnit': null, 'productionQuantity': 1.0,
      'unitOfMeasure': 'Kilogram', 'recognitionLabel': 'Expensed as paid', 'consumedQuantity': 0.0, 'balance': 2.0},
  ],
};

Future<void> seek(WidgetTester tester, String text) async {
  for (final down in [true, false]) {
    for (var i = 0; i < 30 && find.text(text).evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, Offset(0, down ? -300 : 300));
      await tester.pumpAndSettle();
    }
  }
  await tester.ensureVisible(find.text(text).first);
  await tester.pumpAndSettle();
}

void main() {
  for (final scale in [1.0, 1.3]) {
    testWidgets('RCV-00003 opens on a real phone, text x$scale', (tester) async {
      debugCheckIntrinsicSizes = true;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final api = FakeApi()
        ..gets['/api/CompanyTime/context'] = {'businessDate': '2026-10-15'}
        ..gets[base] = [rcv3]
        ..gets['$base/3'] = rcv3;
      await open(tester, PurchaseReceiptsScreen(session: await sessionFor(api), company: adminCompany), size: const Size(393, 851));
      await seek(tester, 'RCV-00003 · mo b');
      await tester.tap(find.text('RCV-00003 · mo b').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('MONEY'), findsOneWidget);
      expect(find.text('Reverse receipt'), findsOneWidget);
      debugCheckIntrinsicSizes = false;
    });
  }
}
