// The rules behind Poultry → Sales → Sales, ported from `app/sales/page.tsx`,
// `components/sales/sale-item-row.tsx`, `components/sales/egg-class-fields.tsx`
// and `lib/sales/reversal.ts`, so the phone computes, validates and posts
// exactly what the web does.

import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;

/// The page's fixed option lists (SALE_PRODUCT_OPTIONS).
const saleProductOptions = ['Fresh Eggs', 'Chicken', 'Manure', 'Other'];
const salePaymentMethods = ['Cash', 'Credit Card', 'Bank Transfer', 'Check', 'Mobile Money'];

/// The Record payment dialog's own list (it differs from the sale form's).
const recordPaymentMethods = ['Cash', 'Mobile Money', 'Bank Transfer', 'Cheque', 'Other'];

/// Refund customer credit's methods (refund-credit-dialog.tsx).
const refundMethods = ['Cash', 'Mobile Money', 'Bank Transfer', 'Check'];

/// The Egg Size field's suggestions (the web's datalist), for farms without sizes.
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
  if (crates > 0) parts.add(long ? '${thousands(crates)} crate${crates == 1 ? '' : 's'}' : '${crates}c');
  if (pieces > 0) parts.add(long ? '${n(pieces)} piece${pieces == 1 ? '' : 's'}' : '${n(pieces)}p');
  return parts.isEmpty ? null : parts.join(' + ');
}

String thousands(num v) {
  final neg = v < 0;
  final whole = v.abs().truncate();
  final s = whole.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  final frac = v.abs() - whole;
  final tail = frac == 0 ? '' : frac.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').substring(1);
  return '${neg ? '-' : ''}$b$tail';
}

num _round2(num n) => (n * 100).round() / 100;

/// saleLineTotal: eggs are priced per crate, loose eggs pro rata; rounded to cents.
num saleLineTotal(num quantity, num unitPrice, bool isEggs, [int eggsPerCrate = 30]) {
  final amount = isEggs && eggsPerCrate > 0 ? (quantity / eggsPerCrate) * unitPrice : quantity * unitPrice;
  return _round2(amount);
}

/// eggCratesEquivalent: 75 eggs → "2.50".
String eggCratesEquivalent(num? quantity, [int eggsPerCrate = 30]) => eggsPerCrate > 0 ? ((quantity ?? 0) / eggsPerCrate).toStringAsFixed(2) : '0.00';

/// scaleLineTotals: the override replaces the sale's TOTAL; each line keeps its
/// share, rounded to the cent, and the last line takes the rounding.
List<num> scaleLineTotals(List<num> calculated, num? override) {
  if (override == null || !(override > 0) || calculated.isEmpty) return calculated;
  final target = (override * 100).round();
  final sum = calculated.fold<num>(0, (a, b) => a + b);
  final shares = [for (final c in calculated) sum > 0 ? c / sum : 1 / calculated.length];
  final cents = [for (final sh in shares) (target * sh).round()];
  cents[cents.length - 1] += target - cents.fold<int>(0, (a, b) => a + b);
  return [for (final c in cents) c / 100];
}

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
  final sameEgg = editingSale != null && stockProduct['isRawEggProduct'] == true && isEggProductName(editingSale['product']);
  return tNum(stockProduct['stockOnHand']) + (sameEgg ? tNum(editingSale['quantity']) : 0);
}

num stockShortfall(num? available, num wanted) => available == null || wanted <= available ? 0 : wanted - available;

/// isFlockClosed (migration 338).
bool isFlockClosed(Map? f) {
  final c = f?['closedDate'];
  return c != null && '$c'.isNotEmpty;
}

bool _sellsBirds(Object? p) {
  final name = tStr(p).trim().toLowerCase();
  return RegExp('bird|chick|cockerel').hasMatch(name) && !name.contains('egg');
}

/// A closed flock cannot take a BIRD sale (on any line), except the flock the
/// edited sale is on.
bool closedFlockBlocksSale(Map flock, Object? product, Map? editingSale, [List<Object?> otherProducts = const []]) {
  if (!isFlockClosed(flock)) return false;
  if (editingSale != null && tIntOrNull(editingSale['flockId']) == tIntOrNull(flock['flockId'])) return false;
  return _sellsBirds(product) || otherProducts.any((p) => !isEggProductName(p) && _sellsBirds(p));
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

bool isReversedSale(Map s) => s['status'] == 'Reversed';

// ------------------------------------------------------------------ sale rows (358)

/// toSaleRows: `lines` stays on a sale only when it has two or more, so
/// `row['lines']` reads as "this is a multi-line sale".
List<Map> toSaleRows(List<Map> sales) => [
  for (final s in sales) {...s, 'lines': (s['lines'] is List && (s['lines'] as List).length > 1) ? s['lines'] : null},
];

List<Map> multiLines(Map row) => row['lines'] is List
    ? [
        for (final l in row['lines'] as List)
          if (l is Map) l,
      ]
    : const [];

/// The sale's lines; an older payload without them reads as one line.
List<Map> saleLinesOf(Map s) {
  final l = s['lines'];
  if (l is List && l.isNotEmpty) {
    return [
      for (final x in l)
        if (x is Map) x,
    ];
  }
  return [
    {
      'saleLineId': 0,
      'lineNo': 1,
      'product': s['product'],
      'eggProductId': s['eggProductId'],
      'size': s['size'],
      'quantity': s['quantity'],
      'unitPrice': s['unitPrice'],
      'totalAmount': s['totalAmount'],
    },
  ];
}

/// "SG-00012" on a multi-line sale, else "#2351".
String saleLabel(Map row) => multiLines(row).isNotEmpty ? tStr(row['saleGroupNo']) : '#${row['saleId']}';

// ------------------------------------------------------------------ egg classes (341-344)

/// The class a sale draws from: its size, or the Unsorted product.
Map? classFor(List<Map> classes, Object? eggProductId) {
  final id = tIntOrNull(eggProductId);
  return id != null && id != 0
      ? classes.where((c) => tIntOrNull(c['poultryProductId']) == id).firstOrNull
      : classes.where((c) => c['classKind'] == 'Unsorted').firstOrNull;
}

bool hasEggSizes(List<Map> classes) => classes.any((c) => c['classKind'] == 'Size');

/// The class's default price per crate (344), when one is set.
num? classPrice(List<Map> classes, Object? eggProductId) {
  final c = classFor(classes, eggProductId);
  final p = c?['pricePerCrate'];
  return p != null && tNum(p) > 0 ? tNum(p) : null;
}

/// "Unsorted" or the size's name.
String eggClassLabel(List<Map> classes, Object? eggProductId) {
  final c = classFor(classes, eggProductId);
  return c == null || c['classKind'] == 'Unsorted' ? 'Unsorted' : tStr(c['name']);
}

/// "Jumbo 10c + 5p" per line, joined with " · " (the list's line summary).
String lineSummary(List<Map> classes, List<Map> lines, [int eggsPerCrate = 30]) => [
  for (final l in lines) '${eggClassLabel(classes, l['eggProductId'])} ${eggCrateBreakdown(tNum(l['quantity']), eggsPerCrate: eggsPerCrate) ?? 0}',
].join(' · ');

/// sale-lines-dialog's saleLineQuantityLabel: "10 crates + 5 pcs (305 eggs)".
String saleLineQuantityLabel(Map line, [int eggsPerCrate = 30]) {
  final q = tNum(line['quantity']);
  if (!isEggProductName(line['product']) || eggsPerCrate <= 0) return thousands(q);
  final crates = (q / eggsPerCrate).floor();
  final pieces = (q % eggsPerCrate).toInt();
  final parts = <String>[
    if (crates > 0) '${thousands(crates)} crate${crates == 1 ? '' : 's'}',
    if (pieces > 0) '$pieces pc${pieces == 1 ? '' : 's'}',
  ];
  return parts.isEmpty ? '0' : '${parts.join(' + ')} (${thousands(q)} eggs)';
}

// ------------------------------------------------------------------ the New sale form

/// One line of the Items table (sale-item-row.tsx). Eggs are crates + loose
/// eggs priced per crate; anything else is a plain quantity at a unit price.
class SaleItem {
  SaleItem({
    required this.key,
    this.product = 'Fresh Eggs',
    this.eggProductId,
    this.size,
    this.crates = 0,
    this.loose = 0,
    this.quantity = 0,
    this.unitPrice = 0,
  });
  final String key;
  String product;
  int? eggProductId;

  /// Free-text size, line 1 only, for farms without egg sizes.
  String? size;
  int crates, loose;
  num quantity;
  num unitPrice;

  bool get isEggs => isEggProductName(product);

  /// What the line sells: eggs for an egg line, else its quantity.
  num qty(int epc) => isEggs ? crates * epc + loose : quantity;
  int eggs(int epc) => crates * epc + loose;
  num total(int epc) => saleLineTotal(qty(epc), unitPrice, isEggs, epc);

  /// The Product dropdown's value: one of the options, else "Other".
  String get selectValue => saleProductOptions.contains(product) ? product : 'Other';
}

/// The New sale / Corrected sale form: the web's formData, its Items lines and
/// the Payment choices.
class SaleForm {
  SaleForm({this.eggsPerCrate = 30}) {
    items = [SaleItem(key: 'line-1')];
  }

  final int eggsPerCrate;
  String saleDate = '';
  String customerName = '';
  bool showNewCustomerInput = false;
  String otherCustomerName = '';
  int? flockId = 0;
  late List<SaleItem> items;
  num? overrideAmount;
  bool overrideStock = false;
  bool paid = true;
  bool partPayment = false;
  num? partPaidAmount;
  String paymentMethod = '';
  int? cashAccountId;
  String saleDescription = '';
  int _seq = 1;

  SaleItem get first => items.first;
  List<SaleItem> get extra => items.skip(1).toList();
  bool get hasExtraLines => items.length > 1;
  bool get hasOverride => overrideAmount != null && overrideAmount! > 0;

  num get firstLineAmount => first.total(eggsPerCrate);
  num get calculatedSaleTotal => _round2(items.fold<num>(0, (s, l) => s + l.total(eggsPerCrate)));
  num get allLinesAmount => hasOverride ? _round2(overrideAmount!) : calculatedSaleTotal;

  /// 360: a sale is one product, so different products are saved as one sale each.
  int get saleProductCount => {for (final l in items) l.product.trim().toLowerCase()}.where((p) => p.isNotEmpty).length;

  /// setFirstLineProduct / an added line's product change.
  void setProduct(SaleItem line, String value, List<Map> classes) {
    final egg = isEggProductName(value);
    final wasEgg = line.isEggs;
    line.product = value;
    if (!egg) {
      line.eggProductId = null;
      line.crates = 0;
      line.loose = 0;
      if (wasEgg) line.quantity = 0;
    }
    // A new egg sale with no price yet starts at its class's price (line 1).
    if (egg && identical(line, first) && !(line.unitPrice > 0)) {
      final p = classPrice(classes, line.eggProductId);
      if (p != null) line.unitPrice = p;
    }
  }

  void setClass(SaleItem line, int? eggProductId, List<Map> classes) {
    line.eggProductId = eggProductId;
    line.unitPrice = classPrice(classes, eggProductId) ?? line.unitPrice;
  }

  /// addSaleLine: a second egg line most often sells another size — offer the next one.
  SaleItem addLine(List<Map> classes) {
    final used = {for (final l in items) l.eggProductId};
    final cls = classes
        .where((c) => c['classKind'] == 'Size' && c['isActive'] == true && !used.contains(tIntOrNull(c['poultryProductId'])))
        .map((c) => tIntOrNull(c['poultryProductId']))
        .firstOrNull;
    final line = SaleItem(key: 'line-${++_seq}', eggProductId: cls, unitPrice: classPrice(classes, cls) ?? 0);
    items.add(line);
    return line;
  }

  /// Removing line 1 moves the next line up into its place.
  void removeLine(SaleItem line) {
    if (items.length < 2) return;
    final wasFirst = identical(line, first);
    items.remove(line);
    if (wasFirst) first.size = null;
  }

  // ---------------------------------------------------------- stock

  /// Line 1: an egg sale draws on its own class product, else the stock product.
  Map? firstStockProduct(List<Map> products) => first.isEggs && first.eggProductId != null
      ? products.where((p) => tIntOrNull(p['poultryProductId']) == first.eggProductId).firstOrNull
      : saleStockProduct(products, first.product);

  num? firstAvailable(List<Map> products) {
    final sp = firstStockProduct(products);
    return sp == null ? null : tNum(sp['stockOnHand']);
  }

  num firstShortfall(List<Map> products) => stockShortfall(firstAvailable(products), first.qty(eggsPerCrate));

  /// extraLineStock: what is left for each added line after the lines above it.
  List<({num available, String units, bool short})?> extraLineStock(List<Map> classes, List<Map> products) {
    final firstEggs = first.isEggs ? first.qty(eggsPerCrate) : 0;
    final ex = extra;
    final out = <({num available, String units, bool short})?>[];
    for (var idx = 0; idx < ex.length; idx++) {
      final l = ex[idx];
      final above = ex.sublist(0, idx);
      if (l.isEggs) {
        final cls = classFor(classes, l.eggProductId);
        if (cls == null) {
          out.add(null);
          continue;
        }
        final used =
            (first.isEggs && first.eggProductId == l.eggProductId ? firstEggs : 0) +
            above.where((x) => x.isEggs && x.eggProductId == l.eggProductId).fold<num>(0, (t, x) => t + x.eggs(eggsPerCrate));
        final avail = (tNum(cls['onHand']) - used).truncate();
        final available = avail < 0 ? 0 : avail;
        out.add((available: available, units: 'eggs', short: l.eggs(eggsPerCrate) > available));
        continue;
      }
      final sp = saleStockProduct(products, l.product);
      if (sp == null) {
        out.add(null);
        continue;
      }
      bool same(String name) =>
          !isEggProductName(name) && tIntOrNull(saleStockProduct(products, name)?['poultryProductId']) == tIntOrNull(sp['poultryProductId']);
      final used =
          (same(first.product) ? first.qty(eggsPerCrate) : 0) +
          above.where((x) => !x.isEggs && same(x.product)).fold<num>(0, (t, x) => t + x.quantity);
      final left = tNum(sp['stockOnHand']) - used;
      final available = left < 0 ? 0 : left;
      out.add((available: available, units: stockUnitLabel(sp), short: l.quantity > available));
    }
    return out;
  }

  /// extraLinesShort: any added EGG line asking for more than its class holds.
  bool extraEggLinesShort(List<Map> classes) {
    final mainEggs = first.isEggs ? first.qty(eggsPerCrate) : 0;
    final mainClass = first.isEggs ? first.eggProductId : null;
    final lines = extra.where((l) => l.isEggs).toList();
    for (var idx = 0; idx < lines.length; idx++) {
      final l = lines[idx];
      final cls = classFor(classes, l.eggProductId);
      final used =
          (mainClass == l.eggProductId ? mainEggs : 0) +
          lines.sublist(0, idx).where((x) => x.eggProductId == l.eggProductId).fold<num>(0, (s, x) => s + x.eggs(eggsPerCrate));
      final left = tNum(cls?['onHand']) - used;
      if (l.eggs(eggsPerCrate) > (left < 0 ? 0 : left)) return true;
    }
    return false;
  }

  // ---------------------------------------------------------- validation

  /// validateSaleForm (line 1 and the sale), in the web's order, or null.
  String? validate({required num? available, required String stockUnits}) {
    final p = first.product.trim();
    final quantity = first.qty(eggsPerCrate);
    final short = stockShortfall(available, quantity);
    if (saleDate.isEmpty) return 'Pick the date this sale happened.';
    if (p.isEmpty) return 'Choose what was sold (eggs, chicken, manure, or other).';
    if (customerName.trim().isEmpty) return 'Enter or select who bought from you.';
    if (!quantity.isFinite || quantity <= 0) return 'Enter how many units were sold — use a number greater than zero.';
    if (!first.unitPrice.isFinite || first.unitPrice <= 0) return 'Enter the price per unit — it must be greater than zero.';
    if (paymentMethod.trim().isEmpty) return 'Select how the customer paid (cash, mobile money, bank, etc.).';
    if (short > 0 && !overrideStock) {
      return 'Only ${thousands(available ?? 0)} $stockUnits in stock — this sale is '
          '${thousands(short)} more. Lower the quantity, or tick "Sell it anyway" to record it regardless.';
    }
    return null;
  }

  /// The part-payment checks, after the cash account.
  String? validatePart() {
    if (!partPayment) return null;
    final paidNow = partPaidAmount ?? 0;
    if (customerName.trim().isEmpty) return 'A part payment needs a customer, so the rest can be owed by someone.';
    if (paidNow <= 0) return 'Enter the amount the customer paid now.';
    if (paidNow >= allLinesAmount) return 'That covers the whole sale. Choose Paid now instead.';
    return null;
  }

  /// Several lines or a part payment are posted to Sale/group.
  bool get postsAsGroup => hasExtraLines || partPayment;

  /// The group checks: every added line complete, and no short line unless overridden.
  String? validateGroup(List<Map> classes, List<Map> products) {
    if (extra.any((l) => l.product.trim().isEmpty || l.qty(eggsPerCrate) <= 0 || l.unitPrice <= 0)) {
      return 'Every added line needs a product, a quantity and a price, or remove it.';
    }
    final anyShort = extraLineStock(classes, products).any((x) => x?.short == true);
    if ((anyShort || extraEggLinesShort(classes)) && !overrideStock) {
      return 'One of the added lines asks for more than is in stock. Lower it, or tick "Sell it anyway".';
    }
    return null;
  }

  /// createSaleGroup's body (343/358/360).
  Map<String, dynamic> groupBody(String farmId, String userId, {int? correctsSaleId, required String requestKey}) {
    final product = first.product.trim();
    final lines = [
      {
        'product': product,
        'eggProductId': first.isEggs ? first.eggProductId : null,
        'quantity': first.qty(eggsPerCrate),
        'unitPrice': first.unitPrice,
        'totalAmount': firstLineAmount,
      },
      for (final l in extra)
        {
          'product': (l.product.isEmpty ? product : l.product).trim(),
          'eggProductId': l.isEggs ? l.eggProductId : null,
          'quantity': l.qty(eggsPerCrate),
          'unitPrice': l.unitPrice,
          'totalAmount': l.total(eggsPerCrate),
        },
    ];
    final totals = scaleLineTotals([for (final l in lines) l['totalAmount'] as num], hasOverride ? overrideAmount : null);
    for (var i = 0; i < lines.length; i++) {
      lines[i]['totalAmount'] = totals[i];
    }
    return {
      'farmId': farmId,
      'userId': userId,
      'saleDate': saleDate,
      'customerName': customerName.isEmpty ? null : customerName,
      'paymentMethod': paymentMethod.isEmpty ? null : paymentMethod,
      'poultryCashAccountId': cashAccountId,
      'paid': partPayment ? false : paid,
      'amountPaidNow': partPayment ? _round2(partPaidAmount ?? 0) : null,
      'saleDescription': saleDescription.isEmpty ? null : saleDescription,
      'flockId': (flockId ?? 0) == 0 ? null : flockId,
      'correctsSaleId': correctsSaleId,
      'requestKey': requestKey,
      'lines': lines,
    };
  }

  /// A one-line sale's total (the override replaces it).
  num get singleTotal => hasOverride ? overrideAmount! : firstLineAmount;

  /// createSale's body: one line, as the web's SaleInput.
  Map<String, dynamic> createBody(String farmId, String userId, {int? correctsSaleId}) => {
    'farmId': farmId,
    'userId': userId,
    'saleId': 0,
    'saleDate': saleDate,
    'product': first.product.trim(),
    'quantity': first.qty(eggsPerCrate),
    'unitPrice': first.unitPrice,
    'totalAmount': singleTotal,
    'paymentMethod': paymentMethod,
    'customerName': customerName,
    'flockId': flockId ?? 0,
    'saleDescription': saleDescription,
    'paid': paid,
    'size': (first.size ?? '').trim().isNotEmpty ? first.size!.trim() : null,
    'poultryCashAccountId': cashAccountId,
    // 0 = Unsorted / General
    'eggProductId': first.isEggs ? (first.eggProductId ?? 0) : 0,
    'correctsSaleId': correctsSaleId,
    'createdDate': DateTime.now().toUtc().toIso8601String(),
  };

  /// openCorrectionForm: a NEW sale, pre-filled from the reversed one. Money
  /// kept as credit is applied after saving, so it goes in as Pay later.
  static SaleForm correctionOf(Map sale, {required num creditKept, int? defaultAccount, int eggsPerCrate = 30}) {
    final f = SaleForm(eggsPerCrate: eggsPerCrate);
    final lines = multiLines(sale);
    final first = lines.firstOrNull;
    final firstQty = tNum(first?['quantity'] ?? sale['quantity']);
    final product = tStr(sale['product']);
    final egg = isEggProductName(product);
    f
      ..saleDate = tStr(sale['saleDate']).split('T').first
      ..paymentMethod = tStr(sale['paymentMethod'])
      ..customerName = tStr(sale['customerName'])
      ..flockId = tIntOrNull(sale['flockId'])
      ..saleDescription = tStr(sale['saleDescription'])
      ..paid = creditKept > 0 ? false : (sale['paid'] ?? true) as bool
      ..cashAccountId = tIntOrNull(sale['poultryCashAccountId']) ?? defaultAccount;
    final l1 = f.first
      ..product = product
      ..unitPrice = tNum(first?['unitPrice'] ?? sale['unitPrice'])
      ..size = (first != null ? first['size'] : sale['size'])?.toString()
      ..eggProductId = tIntOrNull(first != null ? first['eggProductId'] : sale['eggProductId']);
    if (l1.eggProductId == 0) l1.eggProductId = null;
    if (egg) {
      l1.crates = (firstQty / eggsPerCrate).floor();
      l1.loose = (firstQty % eggsPerCrate).toInt();
    } else {
      l1.quantity = firstQty;
    }
    for (final l in lines.skip(1)) {
      final e = isEggProductName(l['product']);
      final q = tNum(l['quantity']);
      final id = tIntOrNull(l['eggProductId']);
      f.items.add(
        SaleItem(
          key: 'fix-${l['saleLineId']}',
          product: tStr(l['product']),
          eggProductId: e && id != 0 ? id : null,
          crates: e ? (q / eggsPerCrate).floor() : 0,
          loose: e ? (q % eggsPerCrate).toInt() : 0,
          quantity: e ? 0 : q,
          unitPrice: tNum(l['unitPrice']),
        ),
      );
    }
    return f;
  }
}

/// The default account a new sale is received into: "Main Cash Account", else
/// the first active one.
int? defaultCashAccountId(List<Map> accounts) {
  final main = accounts.where((a) => tStr(a['accountName']).trim().toLowerCase() == 'main cash account').firstOrNull;
  return tIntOrNull((main ?? accounts.firstOrNull)?['poultryCashAccountId']);
}

// ------------------------------------------------------------------ status filter (351)

const saleStatusFilters = [
  ('Active', 'Active'),
  ('Pending', 'Pending'),
  ('Partial', 'Partially paid'),
  ('Paid', 'Paid'),
  ('Reversed', 'Reversed'),
  ('All', 'All'),
];

bool matchesStatusFilter(Map sale, String paymentStatus, String filter) {
  final reversed = isReversedSale(sale);
  return switch (filter) {
    'All' => true,
    'Reversed' => reversed,
    'Active' => !reversed,
    _ => !reversed && paymentStatus == filter,
  };
}

// ------------------------------------------------------------------ reversal (351)

const reversalReasons = ['Wrong customer', 'Wrong quantity', 'Wrong price', 'Duplicate sale', 'Wrong product', 'Entered by mistake', 'Other'];

/// The choices the dialog opens with: each payment's server default.
Map<String, String> defaultHandling(List<Map> payments) => {for (final p in payments) tStr(p['key']): tStr(p['default'])};

List<String> _allowed(Map p) => [for (final a in (p['allowed'] is List ? p['allowed'] as List : const [])) '$a'];

/// A choice the server would refuse is never sent: fall back to the default.
String effectiveAction(Map item, Map<String, String> handling) {
  final chosen = handling[tStr(item['key'])];
  return chosen != null && _allowed(item).contains(chosen) ? chosen : tStr(item['default']);
}

bool allowsBoth(Map item) => _allowed(item).contains('KeepAsCredit') && _allowed(item).contains('ReversePayment');

({num creditCreated, num cashOut}) reversalOutcome(List<Map> payments, Map<String, String> handling) {
  num credit = 0, out = 0;
  for (final p in payments) {
    final amount = tNum(p['allocated']);
    if (effectiveAction(p, handling) == 'ReversePayment') {
      out += amount;
    } else {
      credit += amount;
    }
  }
  return (creditCreated: _round2(credit), cashOut: _round2(out));
}

/// How a payment's origin reads on the dialog.
String paymentSourceLabel(Map item) {
  if (item['recordedAtReversal'] == true) return 'Received at the sale';
  if (item['source'] == 'SaleEntry' && item['saleGenerated'] == true) return 'Paid with this sale';
  if (item['source'] == 'SaleEntry') return 'Paid with this sale (shared)';
  if (item['source'] == 'CustomerBalances') return 'Customer payment';
  final s = tStr(item['source']);
  return s.isEmpty ? 'Payment' : s;
}

/// "300 eggs (Large)" / "10 birds"; null when nothing comes back.
String? restoreLabel(Map line) {
  final qty = tNum(line['restoreQuantity']);
  if (qty <= 0) return null;
  final unit = line['restoreUnit'] == 'birds' ? 'birds' : 'eggs';
  final n = thousands(qty);
  return line['restoreUnit'] == 'birds' || tStr(line['restoreProductName']).isEmpty ? '$n $unit' : '$n $unit (${line['restoreProductName']})';
}

const reversalHandlingLabel = {
  'None': 'Nothing had been paid',
  'KeepAsCredit': 'Kept as customer credit',
  'ReversePayment': 'Payment reversed',
  'Mixed': 'Partly kept as credit, partly reversed',
};

/// The page's numbered pagination: 1 2 3 4 … n, with ellipses.
List<Object> pageNumbers(int page, int totalPages) {
  if (totalPages <= 7) return [for (var i = 1; i <= totalPages; i++) i];
  if (page <= 3) return [1, 2, 3, 4, 'ellipsis', totalPages];
  if (page >= totalPages - 2) return [1, 'ellipsis', for (var i = totalPages - 3; i <= totalPages; i++) i];
  return [1, 'ellipsis', page - 1, page, page + 1, 'ellipsis', totalPages];
}

/// INV-000042.
String saleInvoiceNumber(Object? saleId) => 'INV-${'${saleId ?? 0}'.padLeft(6, '0')}';
