// The rules behind Sales → Payments received and Sales → Customer Balances,
// ported from `lib/balances/allocate.ts`, `lib/api/balances.ts` and the two
// pages' own helpers. Money is handled in integer pesewas, as the web does, so
// an allocation never drifts by a float.

import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;

// ------------------------------------------------------------------ labels

/// Payments received's source labels.
const paymentsSourceLabels = {
  'SaleEntry': 'Sale',
  'CustomerBalances': 'Balances',
  'CustomerProfile': 'Customer',
  'PaymentsPage': 'Payments',
  'ImportedPayment': 'Imported',
  'Backfill': 'Backfill',
};
String paymentsSourceLabel(Object? s) {
  final v = tStr(s);
  return v.isEmpty ? '—' : (paymentsSourceLabels[v] ?? v);
}

/// The statement's: a Sale line prints no source, "Counter" is its own.
String statementSourceLabel(Object? s) {
  final v = tStr(s);
  if (v.isEmpty || v == 'Sale') return '—';
  return {...paymentsSourceLabels, 'Counter': 'Counter'}[v] ?? v;
}

/// PAY-0001, else the first block of the group uuid.
String paymentRef(Map row) {
  final n = tStr(row['paymentNumber']).trim();
  if (n.isNotEmpty) return n;
  final id = tStr(row['paymentId']);
  return '#${id.length > 8 ? id.substring(0, 8) : id}';
}

bool isReversedPayment(Map r) => (r['status'] ?? 'Posted') == 'Reversed';

const balanceStatusFilters = ['All', 'Partial', 'Unpaid', 'Overdue'];
String balanceStatusLabel(String s) => s == 'All' ? 'All with balance' : s == 'Partial' ? 'Partially paid' : s;

/// The Record payment dialog's methods (they differ from the Sales page's).
const balancePaymentMethods = ['Cash', 'MoMo', 'Bank Transfer', 'Cheque', 'Card', 'Other'];

/// The compact pager's sizes (components/ui/data-pagination.tsx).
const pageSizeOptions = [5, 10, 25, 50, 100];

// ------------------------------------------------------------------ allocation

int toPesewas(Object? amount) => (tNum(amount) * 100).round();
num fromPesewas(int p) => p / 100;

String docKey(Map d) => '${d['documentType']}:${d['documentId']}';

/// autoAllocateOldestFirst.
Map<String, num> autoAllocateOldestFirst(num amount, List<Map> documents) {
  var remaining = toPesewas(amount);
  final out = <String, num>{};
  if (remaining <= 0) return out;
  final oldest = [...documents]..sort((a, b) {
      final c = tStr(a['documentDate']).compareTo(tStr(b['documentDate']));
      return c != 0 ? c : (tIntOrNull(a['documentId']) ?? 0) - (tIntOrNull(b['documentId']) ?? 0);
    });
  for (final d in oldest) {
    if (remaining <= 0) break;
    final bal = toPesewas(d['balance']);
    if (bal <= 0) continue;
    final apply = bal < remaining ? bal : remaining;
    out[docKey(d)] = fromPesewas(apply);
    remaining -= apply;
  }
  return out;
}

num totalAllocated(Map<String, num> a) => fromPesewas(a.values.fold<int>(0, (s, v) => s + toPesewas(v)));
num totalOpenBalance(List<Map> docs) => fromPesewas(docs.fold<int>(0, (s, d) => s + toPesewas(d['balance'])));
num balanceAfterAllocation(Map d, Map<String, num> a) => fromPesewas(toPesewas(d['balance']) - toPesewas(a[docKey(d)] ?? 0));

class AllocationValidation {
  AllocationValidation(this.ok, this.allocated, this.unallocated, this.problems, this.overAllocated);
  final bool ok;
  final num allocated;
  final num unallocated;

  /// (docKey or null for the payment as a whole, message).
  final List<(String?, String)> problems;
  final Map<String, num> overAllocated;
  List<String> get blocking => [for (final p in problems) if (p.$1 == null) p.$2];
}

/// validateAllocations, with the web's messages.
AllocationValidation validateAllocations(num amount, List<Map> documents, Map<String, num> allocation,
    {bool cashAccountRequired = false, int? cashAccountId}) {
  final problems = <(String?, String)>[];
  final over = <String, num>{};
  final byKey = {for (final d in documents) docKey(d): d};
  final amountP = toPesewas(amount);
  var allocatedP = 0;
  allocation.forEach((key, raw) {
    final v = toPesewas(raw);
    if (v == 0) return;
    allocatedP += v;
    if (v < 0) {
      problems.add((key, 'Amount to apply cannot be negative.'));
      return;
    }
    final d = byKey[key];
    if (d == null) {
      problems.add((key, 'This document is no longer open.'));
      return;
    }
    final bal = toPesewas(d['balance']);
    if (v > bal) {
      over[key] = fromPesewas(v - bal);
      problems.add((key, 'Cannot apply more than the ${fromPesewas(bal).toStringAsFixed(2)} still owed on this line.'));
    }
  });
  if (amountP <= 0) problems.add((null, 'Enter a payment amount greater than 0.'));
  if (allocatedP == 0 && amountP > 0) {
    problems.add((null, 'Apply this payment to at least one line.'));
  } else if (amountP > 0 && allocatedP != amountP) {
    problems.add((
      null,
      allocatedP < amountP
          ? '${fromPesewas(amountP - allocatedP).toStringAsFixed(2)} of this payment is still unallocated.'
          : 'Applied amounts exceed the payment by ${fromPesewas(allocatedP - amountP).toStringAsFixed(2)}.',
    ));
  }
  if (cashAccountRequired && cashAccountId == null) {
    problems.add((null, 'Choose the cash account this money moves through.'));
  }
  return AllocationValidation(problems.isEmpty, fromPesewas(allocatedP), fromPesewas(amountP - allocatedP), problems, over);
}

/// formatDocumentAge: an "age" of five years or more is an opening balance.
String formatDocumentAge(Object? ageDays) {
  final d = tNum(ageDays);
  if (d >= 5 * 365) return 'Opening balance';
  return '${d < 0 ? 0 : d.toInt()}d';
}

/// entryTimestamp: today gets the real clock time, any other day midnight.
String? entryTimestamp(String dateKey, [DateTime? now]) {
  if (dateKey.isEmpty) return null;
  final n = (now ?? DateTime.now()).toUtc();
  final today = n.toIso8601String().substring(0, 10);
  return dateKey == today ? n.toIso8601String() : '${dateKey}T00:00:00.000Z';
}

// ------------------------------------------------------------------ payments received

/// The page's filters, applied to the loaded rows (dates go to the server).
List<Map> filterPayments(List<Map> rows,
    {String search = '', String status = 'Posted', String method = 'all', String source = 'all', String appliedTo = 'all'}) {
  final q = search.trim().toLowerCase();
  return rows.where((r) {
    if (status != 'all' && (r['status'] ?? 'Posted') != status) return false;
    if (method != 'all' && tStr(r['paymentMethod']) != method) return false;
    if (source != 'all' && tStr(r['sourceType']) != source) return false;
    final count = tIntOrNull(r['allocationCount']) ?? 0;
    if (appliedTo == 'single' && count != 1) return false;
    if (appliedTo == 'multiple' && count <= 1) return false;
    if (q.isNotEmpty) {
      final hay = [r['partyName'], r['paymentMethod'], r['reference'], r['notes'], paymentRef(r), r['createdBy']]
          .where((v) => v != null && '$v'.isNotEmpty)
          .join(' ')
          .toLowerCase();
      if (!hay.contains(q)) return false;
    }
    return true;
  }).toList();
}

/// How many one-sale payments each sale has taken, over every loaded row.
Map<int, int> payCountBySale(List<Map> rows) {
  final m = <int, int>{};
  for (final r in rows) {
    final sid = tIntOrNull(r['saleId']);
    if (tIntOrNull(r['allocationCount']) == 1 && sid != null) m[sid] = (m[sid] ?? 0) + 1;
  }
  return m;
}

/// One row per part-paid sale: the newest surviving payment carries the trail,
/// the older ones fold into it.
({List<Map> visible, Map<int, String> carriers, int folded}) foldPayments(List<Map> filtered, Map<int, int> counts) {
  final carriers = <int, String>{};
  final visible = <Map>[];
  var folded = 0;
  for (final r in filtered) {
    final sid = tIntOrNull(r['allocationCount']) == 1 ? tIntOrNull(r['saleId']) : null;
    if (sid == null || (counts[sid] ?? 0) < 2) {
      visible.add(r);
      continue;
    }
    if (carriers.containsKey(sid)) {
      folded++;
      continue;
    }
    carriers[sid] = tStr(r['paymentId']);
    visible.add(r);
  }
  return (visible: visible, carriers: carriers, folded: folded);
}

/// The totals count POSTED payments; sales settled counts their allocations.
({int count, num amount, int sales}) paymentTotals(List<Map> filtered) {
  final posted = [for (final r in filtered) if (!isReversedPayment(r)) r];
  return (
    count: posted.length,
    amount: posted.fold<num>(0, (s, r) => s + tNum(r['totalAmount'])),
    sales: posted.fold<int>(0, (s, r) => s + (tIntOrNull(r['allocationCount']) ?? 0)),
  );
}

/// The compact pager: hidden under the smallest page size, pages only when
/// there is more than one.
List<T> pageSlice<T>(List<T> rows, int page, int size) {
  final pages = rows.isEmpty ? 1 : (rows.length + size - 1) ~/ size;
  final p = page.clamp(1, pages);
  final start = (p - 1) * size;
  return rows.sublist(start.clamp(0, rows.length), (start + size).clamp(0, rows.length));
}

// ------------------------------------------------------------------ side

/// The customer and supplier sides of `components/balances/*`: they differ
/// only in wording and in which endpoints they call (`lib/api/balances.ts`).
class BalanceSide {
  const BalanceSide._(this.isCustomer);
  static const customer = BalanceSide._(true);
  static const supplier = BalanceSide._(false);
  final bool isCustomer;

  String get balancesPath => isCustomer ? 'customer-balances' : 'supplier-balances';
  String get paymentsPath => isCustomer ? 'customer-payments' : 'supplier-payments';
  String get openLeaf => isCustomer ? 'open-sales' : 'open-purchases';
  String get statementLeaf => isCustomer ? 'customers' : 'suppliers';

  /// Customer routes say customerId; supplier routes say supplierId.
  String get partyParam => isCustomer ? 'customerId' : 'supplierId';
  String get partyWord => isCustomer ? 'customer' : 'supplier';
  String get partyTitle => isCustomer ? 'Customer' : 'Supplier';
  String get docWord => isCustomer ? 'sale' : 'purchase';
  String get docTitle => isCustomer ? 'Sale' : 'Purchase';
  String get title => isCustomer ? 'Customer Balances' : 'Supplier Balances';
  String get sourceType => isCustomer ? 'CustomerBalances' : 'SupplierBalances';
  String get statementTitle => isCustomer ? 'Customer statement' : 'Supplier statement';

  /// "Receive payment" on the customer side, "Record payment" on the supplier side.
  String payTitle({required bool single}) =>
      isCustomer ? (single ? 'Receive payment' : 'Receive bulk payment') : (single ? 'Record payment' : 'Record bulk payment');

  /// A supplier payment has to name the account the money physically left.
  bool get cashAccountRequired => !isCustomer;

  /// The query for one party's or one document's payments (listPayments).
  Map<String, String> paymentQuery({int? partyId, String? documentType, int? documentId}) => {
        if (partyId != null) partyParam: '$partyId',
        if (isCustomer && documentId != null) 'saleId': '$documentId',
        if (!isCustomer && documentType != null) 'documentType': documentType,
        if (!isCustomer && documentId != null) 'documentId': '$documentId',
      };
}

/// Would a supplier payment overdraw its account? (The server blocks it too.)
bool paymentOverdraws(BalanceSide side, Map? account, num amount) {
  if (side.isCustomer || account == null || account['allowNegativeBalance'] == true) return false;
  if (account['currentBalance'] == null) return false;
  return tNum(account['currentBalance']) - amount < 0;
}
