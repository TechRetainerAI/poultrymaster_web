// Receive Purchase (migration 345) — the arithmetic the form shows BEFORE it
// saves, as `lib/poultry/purchase-receipt.ts`, which mirrors
// sppoultrypurchasereceipt_post. Money is worked in whole pesewas; additional
// costs are spread by line value (by quantity when every line is free) and the
// last line takes the rounding; a payment fills the lines in order.

const expenseWhenConsumed = 'EXPENSE_WHEN_CONSUMED';

/// To pesewas, half away from zero like Postgres round(numeric, 2).
int toCents(num n) {
  if (!n.isFinite) return 0;
  final sign = n < 0 ? -1 : 1;
  return sign * (n.abs() * 100 + 1e-7).round();
}

num fromCents(int c) => c / 100;

class ReceiptLineDraft {
  const ReceiptLineDraft({this.itemId, this.quantity = 0, this.unitCost = 0, this.unitsPerPurchaseUnit, this.method});
  final int? itemId;
  final num quantity;
  final num unitCost;
  final num? unitsPerPurchaseUnit;
  final String? method;
}

class ReceiptLinePreview {
  const ReceiptLinePreview({
    required this.subtotal,
    required this.allocatedAdditional,
    required this.total,
    required this.landedUnitCost,
    required this.productionQuantity,
    required this.paidNow,
    required this.balance,
    required this.deferred,
    required this.expenseNow,
  });
  final num subtotal, allocatedAdditional, total, landedUnitCost, productionQuantity, paidNow, balance, expenseNow;
  final bool deferred;
}

class ReceiptPreview {
  const ReceiptPreview({
    required this.lines,
    required this.subtotal,
    required this.additionalCosts,
    required this.total,
    required this.paid,
    required this.balance,
    required this.status,
    required this.inventoryIncrease,
    required this.cashOut,
    required this.payableIncrease,
    required this.expenseNow,
    required this.deferredToConsumption,
    required this.expenseWhenBalancePaid,
  });
  final List<ReceiptLinePreview> lines;
  final num subtotal, additionalCosts, total, paid, balance;
  final String status;
  final num inventoryIncrease, cashOut, payableIncrease, expenseNow, deferredToConsumption, expenseWhenBalancePaid;
}

int lineSubtotalCents(num quantity, num unitCost) => toCents(quantity * unitCost);

/// Spreads [additionalCents] over the lines; always sums to it exactly.
List<int> allocateAdditionalCents(List<({int subtotalCents, num quantity})> lines, int additionalCents) {
  final out = List<int>.filled(lines.length, 0);
  if (lines.isEmpty || additionalCents <= 0) return out;
  final valueTotal = lines.fold<int>(0, (s, l) => s + l.subtotalCents);
  final byValue = valueTotal > 0;
  final weightTotal = byValue ? valueTotal : lines.fold<num>(0, (s, l) => s + l.quantity);
  var left = additionalCents;
  for (var i = 0; i < lines.length; i++) {
    if (i == lines.length - 1) {
      out[i] = left;
      break;
    }
    final w = byValue ? lines[i].subtotalCents : lines[i].quantity;
    final share = weightTotal > 0 ? ((additionalCents * w) / weightTotal + 1e-9).round() : 0;
    out[i] = share < left ? share : left;
    left -= out[i];
  }
  return out;
}

/// Applies a payment to the lines in order, filling each before the next.
List<int> allocatePaymentCents(List<int> lineTotalsCents, int paidCents) {
  var left = paidCents < 0 ? 0 : paidCents;
  return [
    for (final t in lineTotalsCents)
      () {
        if (t <= 0 || left <= 0) return 0;
        final a = left < t ? left : t;
        left -= a;
        return a;
      }(),
  ];
}

String paymentStatusFor(int totalCents, int paidCents) {
  if (paidCents <= 0) return 'Unpaid';
  if (paidCents >= totalCents) return 'Paid';
  return 'Part paid';
}

ReceiptPreview previewReceipt(List<ReceiptLineDraft> lines, num additionalCosts, num amountPaid) {
  final subs = [for (final l in lines) lineSubtotalCents(l.quantity, l.unitCost)];
  final addC = toCents(additionalCosts) < 0 ? 0 : toCents(additionalCosts);
  final alloc = allocateAdditionalCents([for (var i = 0; i < lines.length; i++) (subtotalCents: subs[i], quantity: lines[i].quantity)], addC);
  final totals = [for (var i = 0; i < lines.length; i++) subs[i] + alloc[i]];
  final totalC = totals.fold<int>(0, (a, b) => a + b);
  final paidRaw = toCents(amountPaid) < 0 ? 0 : toCents(amountPaid);
  final paidC = paidRaw < totalC ? paidRaw : totalC;
  final paidPer = allocatePaymentCents(totals, paidC);

  final previews = [
    for (var i = 0; i < lines.length; i++)
      () {
        final l = lines[i];
        final deferred = l.method == expenseWhenConsumed;
        final q = l.quantity;
        // The database keeps the invoice price when nothing was added, and
        // rounds the landed figure to 2 dp otherwise.
        final landed = alloc[i] == 0 ? l.unitCost : (q > 0 ? (totals[i] / q + 1e-9).round() / 100 : 0);
        final upu = l.unitsPerPurchaseUnit;
        return ReceiptLinePreview(
          subtotal: fromCents(subs[i]),
          allocatedAdditional: fromCents(alloc[i]),
          total: fromCents(totals[i]),
          landedUnitCost: landed,
          productionQuantity: q * (upu != null && upu > 0 ? upu : 1),
          paidNow: fromCents(paidPer[i]),
          balance: fromCents(totals[i] - paidPer[i]),
          deferred: deferred,
          expenseNow: deferred ? 0 : fromCents(paidPer[i]),
        );
      }(),
  ];
  int sumC(int Function(ReceiptLinePreview p, int i) f) {
    var s = 0;
    for (var i = 0; i < previews.length; i++) {
      s += f(previews[i], i);
    }
    return s;
  }

  return ReceiptPreview(
    lines: previews,
    subtotal: fromCents(subs.fold<int>(0, (a, b) => a + b)),
    additionalCosts: fromCents(addC),
    total: fromCents(totalC),
    paid: fromCents(paidC),
    balance: fromCents(totalC - paidC),
    status: paymentStatusFor(totalC, paidC),
    inventoryIncrease: fromCents(totalC),
    cashOut: fromCents(paidC),
    payableIncrease: fromCents(totalC - paidC),
    expenseNow: fromCents(sumC((p, i) => p.deferred ? 0 : paidPer[i])),
    deferredToConsumption: fromCents(sumC((p, i) => p.deferred ? totals[i] : 0)),
    expenseWhenBalancePaid: fromCents(sumC((p, i) => p.deferred ? 0 : totals[i] - paidPer[i])),
  );
}

/// The database's refusals, in the same words. Empty when the form may be saved.
List<String> validateReceipt({
  required bool supplierChosen,
  required String purchaseDate,
  required String today,
  String? dueDate,
  required List<ReceiptLineDraft> lines,
  required num additionalCosts,
  required num amountPaid,
  int? cashAccountId,
}) {
  final errs = <String>[];
  if (!supplierChosen) errs.add('Choose the supplier you bought from.');
  if (purchaseDate.isNotEmpty && today.isNotEmpty && purchaseDate.compareTo(today) > 0) {
    errs.add('The purchase date ($purchaseDate) is in the future. Goods can only be received on or before today ($today).');
  }
  if (lines.isEmpty) errs.add('Add at least one item to the receipt.');
  if (lines.length > 50) errs.add('A receipt can hold at most 50 lines (this one has ${lines.length}). Split the invoice into two receipts.');
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    final n = i + 1;
    if (l.itemId == null || l.itemId == 0) errs.add('Line $n: choose an item.');
    if (!(l.quantity > 0)) {
      errs.add('Line $n: quantity must be greater than 0.');
    } else if ((l.quantity * 1000).round() / 1000 != l.quantity) {
      errs.add('Line $n: quantity can have at most 3 decimal places.');
    }
    if (l.unitCost < 0) errs.add('Line $n: unit cost cannot be negative.');
    if (l.unitsPerPurchaseUnit != null && l.unitsPerPurchaseUnit! < 0) errs.add('Line $n: units per purchase unit must be greater than 0.');
  }
  if (additionalCosts < 0) errs.add('Additional costs cannot be negative.');
  final p = previewReceipt(lines, additionalCosts, 0);
  if (lines.isNotEmpty && p.total <= 0) errs.add('The receipt total must be greater than 0.');
  if (amountPaid < 0) errs.add('Amount paid cannot be negative.');
  if (toCents(amountPaid) > toCents(p.total) && p.total > 0) {
    errs.add('Amount paid (${amountPaid.toStringAsFixed(2)}) is more than the purchase total (${p.total.toStringAsFixed(2)}).');
  }
  if (amountPaid > 0 && (cashAccountId == null || cashAccountId == 0)) errs.add('Choose the cash account the payment came from.');
  if (dueDate != null && dueDate.isNotEmpty && purchaseDate.isNotEmpty && dueDate.compareTo(purchaseDate) < 0 && toCents(amountPaid) < toCents(p.total)) {
    errs.add('The due date ($dueDate) cannot be before the purchase date ($purchaseDate).');
  }
  return errs;
}
