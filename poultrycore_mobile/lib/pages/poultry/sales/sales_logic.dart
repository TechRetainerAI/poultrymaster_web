// The rules behind Poultry → Sales → Sales, ported from `app/sales/page.tsx`
// so the phone computes, validates and posts exactly what the web does.

import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;

/// The page's fixed option lists.
const saleProductOptions = ['Fresh Eggs', 'Chicken', 'Manure', 'Other'];
const salePaymentMethods = ['Cash', 'Credit Card', 'Bank Transfer', 'Check', 'Mobile Money'];

/// The Record payment dialog's own list (it differs from the sale form's).
const recordPaymentMethods = ['Cash', 'Mobile Money', 'Bank Transfer', 'Cheque', 'Other'];

/// The Egg Size field's suggestions (the web's datalist).
const eggSizeSuggestions = ['Inside', 'Tee', 'Serum', 'Small', 'Medium', 'Large', 'XLarge', 'Jumbo'];

const salePageSizes = [5, 10, 15, 25, 50, 100];

bool isEggProductName(Object? product) => tStr(product).toLowerCase().contains('egg');

/// eggCrateBreakdown: "2c + 15p", or long "2 crates + 15 pieces"; null for nothing.
String? eggCrateBreakdown(num quantity, {bool long = false, int eggsPerCrate = 30}) {
  if (!quantity.isFinite || quantity <= 0 || eggsPerCrate <= 0) return null;
  final crates = (quantity / eggsPerCrate).floor();
  final pieces = quantity % eggsPerCrate;
  final parts = <String>[];
  String n(num v) => v == v.roundToDouble() ? v.toInt().toString() : '$v';
  if (crates > 0) parts.add(long ? '${_thousands(crates)} crate${crates == 1 ? '' : 's'}' : '${crates}c');
  if (pieces > 0) parts.add(long ? '${n(pieces)} piece${pieces == 1 ? '' : 's'}' : '${n(pieces)}p');
  return parts.isEmpty ? null : parts.join(' + ');
}

String _thousands(int v) {
  final s = v.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '${v < 0 ? '-' : ''}$b';
}

/// saleLineTotal: eggs are priced per crate, loose eggs pro rata; rounded to cents.
num saleLineTotal(num quantity, num unitPrice, bool isEggs, [int eggsPerCrate = 30]) {
  final amount = isEggs && eggsPerCrate > 0 ? (quantity / eggsPerCrate) * unitPrice : quantity * unitPrice;
  return (amount * 100).round() / 100;
}

/// eggCratesEquivalent: 75 eggs → "2.50".
String eggCratesEquivalent(num? quantity, [int eggsPerCrate = 30]) =>
    eggsPerCrate > 0 ? ((quantity ?? 0) / eggsPerCrate).toStringAsFixed(2) : '0.00';

/// saleStockProduct: the finished product a sale draws on (server rules of 134/139).
Map? saleStockProduct(List<Map> products, Object? product) {
  final name = tStr(product).trim().toLowerCase();
  if (name.isEmpty) return null;
  if (name.contains('egg')) {
    return products.where((p) => p['isRawEggProduct'] == true).firstOrNull ??
        products.where((p) => tStr(p['name']).toLowerCase().contains('egg')).firstOrNull;
  }
  if (RegExp('bird|chick|cockerel').hasMatch(name)) {
    return products.where((p) => p['isBirdProduct'] == true).firstOrNull ??
        products.where((p) => tStr(p['name']).toLowerCase().contains('bird')).firstOrNull;
  }
  return products.where((p) => tStr(p['name']).trim().toLowerCase() == name).firstOrNull;
}

String stockUnitLabel(Map? product) {
  if (product == null) return 'units';
  if (product['isRawEggProduct'] == true) return 'eggs';
  if (product['isBirdProduct'] == true) return 'birds';
  final u = tStr(product['unit']);
  return (u.isEmpty ? 'units' : u).toLowerCase();
}

/// Stock available to THIS sale: an edited egg sale adds its own quantity back.
num? availableStock(Map? stockProduct, Map? editingSale) {
  if (stockProduct == null) return null;
  final sameEgg = editingSale != null &&
      stockProduct['isRawEggProduct'] == true &&
      isEggProductName(editingSale['product']);
  return tNum(stockProduct['stockOnHand']) + (sameEgg ? tNum(editingSale['quantity']) : 0);
}

num stockShortfall(num? available, num wanted) => available == null || wanted <= available ? 0 : wanted - available;

/// isFlockClosed (migration 338).
bool isFlockClosed(Map? f) {
  final c = f?['closedDate'];
  return c != null && '$c'.isNotEmpty;
}

/// A closed flock cannot take a BIRD sale, except the flock the edited sale is on.
bool closedFlockBlocksSale(Map flock, Object? product, Map? editingSale) {
  if (!isFlockClosed(flock)) return false;
  if (editingSale != null && tIntOrNull(editingSale['flockId']) == tIntOrNull(flock['flockId'])) return false;
  final name = tStr(product).trim().toLowerCase();
  return RegExp('bird|chick|cockerel').hasMatch(name) && !name.contains('egg');
}

num salePaid(Map s) {
  final total = tNum(s['totalAmount']);
  return s['amountPaid'] != null ? tNum(s['amountPaid']) : (s['paid'] == false ? 0 : total);
}

num saleOwed(Map s) {
  final o = tNum(s['totalAmount']) - salePaid(s);
  return o > 0 ? o : 0;
}

/// paymentStatusOf: Paid / Partial / Pending.
String paymentStatusOf(Map s) {
  final total = tNum(s['totalAmount']);
  final paid = salePaid(s);
  if (paid <= 0) return 'Pending';
  if (paid + 0.001 < total) return 'Partial';
  return 'Paid';
}

/// The sale form's state, as the web's formData plus its side fields.
class SaleForm {
  String saleDate = '';
  String product = '';
  num quantity = 0;
  num unitPrice = 0;
  num totalAmount = 0;
  String paymentMethod = '';
  String customerName = '';
  int? flockId = 0;
  String saleDescription = '';
  bool paid = true;
  String? size;
  int? cashAccountId;

  String? productSelection;
  String productOther = '';
  bool showNewCustomerInput = false;
  String otherCustomerName = '';
  num? overrideAmount;
  bool overrideStock = false;
  int crates = 0;
  int looseEggs = 0;

  bool get isEggs => isEggProductName(product);

  /// productSelectValue: the explicit pick, else what the product implies.
  String? get productSelectValue =>
      productSelection ?? (product.isNotEmpty ? (saleProductOptions.contains(product) ? product : 'Other') : null);

  num get calculated => saleLineTotal(quantity, unitPrice, isEggs);
  num get finalTotal => overrideAmount != null && overrideAmount! > 0 ? overrideAmount! : calculated;

  /// handleProductSelect.
  void selectProduct(String value) {
    productSelection = value;
    if (value == 'Other') {
      final existing = productOther.isNotEmpty
          ? productOther
          : (product.isNotEmpty && !saleProductOptions.contains(product) ? product : '');
      productOther = existing;
      product = existing;
    } else {
      productOther = '';
      product = value;
    }
    final isEgg = value.toLowerCase().contains('egg') || (value == 'Other' && productOther.toLowerCase().contains('egg'));
    if (!isEgg) {
      crates = 0;
      looseEggs = 0;
    }
  }

  void setCrates(int c) {
    crates = c;
    quantity = c * 30 + looseEggs;
  }

  void setLoose(int l) {
    looseEggs = l;
    quantity = crates * 30 + l;
  }

  /// openEditDialog: prefill from a sale.
  static SaleForm fromSale(Map s) {
    final f = SaleForm()
      ..saleDate = tStr(s['saleDate']).split('T').first
      ..product = tStr(s['product'])
      ..quantity = tNum(s['quantity'])
      ..unitPrice = tNum(s['unitPrice'])
      ..totalAmount = tNum(s['totalAmount'])
      ..paymentMethod = tStr(s['paymentMethod'])
      ..customerName = tStr(s['customerName'])
      ..flockId = tIntOrNull(s['flockId'])
      ..saleDescription = tStr(s['saleDescription'])
      ..paid = s['paid'] ?? true
      ..size = s['size'] == null ? null : tStr(s['size'])
      ..cashAccountId = tIntOrNull(s['poultryCashAccountId']);
    f.productSelection = saleProductOptions.contains(f.product) ? f.product : 'Other';
    f.productOther = f.productSelection == 'Other' ? f.product : '';
    if (f.isEggs && f.quantity > 0) {
      f.crates = (f.quantity / 30).floor();
      f.looseEggs = (f.quantity % 30).toInt();
    }
    return f;
  }

  /// validateSaleForm: the first problem, in the web's order, or null.
  String? validate({required num? available, required String stockUnits}) {
    final p = product.trim();
    final short = stockShortfall(available, quantity);
    if (saleDate.isEmpty) return 'Pick the date this sale happened.';
    if (p.isEmpty) return 'Choose what was sold (eggs, chicken, manure, or other).';
    if (customerName.trim().isEmpty) return 'Enter or select who bought from you.';
    if (!quantity.isFinite || quantity <= 0) return 'Enter how many units were sold — use a number greater than zero.';
    if (!unitPrice.isFinite || unitPrice <= 0) return 'Enter the price per unit — it must be greater than zero.';
    if (paymentMethod.trim().isEmpty) return 'Select how the customer paid (cash, mobile money, bank, etc.).';
    if (short > 0 && !overrideStock) {
      return 'Only ${_thousands((available ?? 0).toInt())} $stockUnits in stock — this sale is '
          '${_thousands(short.toInt())} more. Lower the quantity, or tick "Sell it anyway" to record it regardless.';
    }
    return null;
  }

  /// createSale's request body.
  Map<String, dynamic> createBody(String farmId, String userId) => {
        'farmId': farmId,
        'userId': userId,
        'saleId': 0,
        'saleDate': saleDate,
        'product': product.trim(),
        'quantity': quantity,
        'unitPrice': unitPrice,
        'totalAmount': finalTotal,
        'paymentMethod': paymentMethod,
        'customerName': customerName,
        'flockId': flockId ?? 0,
        'saleDescription': saleDescription,
        'paid': paid,
        'size': (size ?? '').trim().isNotEmpty ? size!.trim() : null,
        'poultryCashAccountId': cashAccountId,
        'createdDate': DateTime.now().toUtc().toIso8601String(),
      };

  /// updateSale's request body: as lib/api/sale.ts, empty strings are left out.
  Map<String, dynamic> updateBody(String farmId, String userId) {
    final p = product.trim();
    return {
      'farmId': farmId,
      'userId': userId,
      if (saleDate.isNotEmpty) 'saleDate': saleDate,
      if (p.isNotEmpty) 'product': p,
      'quantity': quantity,
      'unitPrice': unitPrice,
      'totalAmount': finalTotal,
      if (paymentMethod.isNotEmpty) 'paymentMethod': paymentMethod,
      if (customerName.isNotEmpty) 'customerName': customerName,
      'flockId': flockId ?? 0,
      if (saleDescription.isNotEmpty) 'saleDescription': saleDescription,
      'paid': paid,
      'size': (size ?? '').trim().isNotEmpty ? size!.trim() : null,
      'poultryCashAccountId': cashAccountId,
    };
  }
}

/// The page's numbered pagination: 1 2 3 4 … n, with ellipses.
List<Object> pageNumbers(int page, int totalPages) {
  if (totalPages <= 7) return [for (var i = 1; i <= totalPages; i++) i];
  if (page <= 3) return [1, 2, 3, 4, 'ellipsis', totalPages];
  if (page >= totalPages - 2) return [1, 'ellipsis', for (var i = totalPages - 3; i <= totalPages; i++) i];
  return [1, 'ellipsis', page - 1, page, page + 1, 'ellipsis', totalPages];
}

/// INV-000042.
String saleInvoiceNumber(Object? saleId) => 'INV-${'${saleId ?? 0}'.padLeft(6, '0')}';
