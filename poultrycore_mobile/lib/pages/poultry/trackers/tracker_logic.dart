// The arithmetic behind Poultry → Trackers, ported from the web so every
// figure is the same number on both:
//
//   lib/utils/egg-ledger.ts          → buildEggStockLedger
//   lib/utils/feed-ledger.ts         → buildFeedStockLedger
//   lib/utils/feed-item-ledger.ts    → buildFeedItemMovements / Positions
//   lib/utils/birds-left-ledger.ts   → buildBirdsLeftLedger / summarize…
//   lib/utils/ledger-breakdown.ts    → groupLedgerBy / ByNet
//   lib/cash/cash-flow.ts            → assignPercentages
//   components/ui/sortable-header    → sortRows / toggleSort
//
// How the trackers link together: Egg reads production records, sales,
// egg adjustments and the egg product's stock-ledger moves; Feed, Ingredients,
// Feed inventory and Medication all read the ONE raw-material store
// (items, purchases, usage, adjustments) and only differ in which items they
// keep; Birds reads flocks, production-record mortality and bird sales. Change
// a formula here only alongside its web twin.

import 'dart:math' as math;

import '../../shared/business_dates.dart';

// ------------------------------------------------------------------ helpers

num tNum(Object? v) {
  if (v is num) return v.isFinite ? v : 0;
  final n = num.tryParse('${v ?? ''}');
  return n == null || !n.isFinite ? 0 : n;
}

int? tIntOrNull(Object? v) {
  if (v == null || v == '') return null;
  if (v is num) return v.toInt();
  return int.tryParse('$v');
}

String tStr(Object? v) => v == null ? '' : '$v';

bool tBool(Object? v) => v == true || v == 1 || '$v'.toLowerCase() == 'true';

/// Milliseconds since epoch, 0 when the value is not a date (JS's NaN sorts
/// nowhere in particular; 0 keeps it deterministic).
int tMs(Object? v) {
  final d = DateTime.tryParse(tStr(v).trim());
  return d?.millisecondsSinceEpoch ?? 0;
}

/// toLocalDateKey: the local calendar day of a stored timestamp. A bare
/// "yyyy-MM-dd" is taken as it stands.
String localDateKey(Object? v) {
  final s = tStr(v).trim();
  if (s.isEmpty) return '';
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return s;
  final d = DateTime.tryParse(s);
  if (d == null) return '';
  return isoDay(d.toLocal());
}

/// A number the way JavaScript prints it in a template string: 500, 12.5.
String jsNum(num n) {
  if (n == n.roundToDouble()) return n.toInt().toString();
  var s = n.toString();
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return s;
}

/// toLocaleString() for counts (up to 3 decimals, thousands separators).
String loc(num n, [int maxDigits = 3]) => fmtNum(n, maxDigits);

/// "Oct 5, 26" — the web trackers' formatDateShort (en-US, 2-digit year).
const _mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String trackerDate(Object? v) {
  final s = tStr(v).trim();
  if (s.isEmpty) return '—';
  DateTime? d;
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) {
    final p = s.split('-').map(int.parse).toList();
    d = DateTime(p[0], p[1], p[2]);
  } else {
    d = DateTime.tryParse(s)?.toLocal();
  }
  if (d == null) return '—';
  return '${_mon[d.month - 1]} ${d.day}, ${(d.year % 100).toString().padLeft(2, '0')}';
}

/// "14:05" — the time under the Feed tracker's Last ledger event.
String trackerTime(Object? v) {
  final d = DateTime.tryParse(tStr(v).trim())?.toLocal();
  if (d == null) return '—';
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

// ------------------------------------------------------------------ sorting

enum SortDir { asc, desc }

typedef SortState = ({String? key, SortDir? dir});

/// toggleSort: a new column sorts ascending, then descending, then not at all.
SortState toggleSort(String key, SortState s) {
  if (s.key != key) return (key: key, dir: SortDir.asc);
  if (s.dir == SortDir.asc) return (key: key, dir: SortDir.desc);
  return (key: null, dir: null);
}

/// sortData: nulls first ascending / last descending, date-looking strings by
/// instant, numbers numerically, other strings alphabetically. Stable.
List<T> sortRows<T>(List<T> data, SortState s, Object? Function(T row, String key) valueOf) {
  final key = s.key, dir = s.dir;
  if (key == null || dir == null) return data;
  final asc = dir == SortDir.asc;
  final indexed = [for (var i = 0; i < data.length; i++) (i, data[i])];
  int cmp(Object? a, Object? b) {
    if (a == null && b == null) return 0;
    if (a == null) return asc ? -1 : 1;
    if (b == null) return asc ? 1 : -1;
    int r;
    if (a is DateTime && b is DateTime) {
      r = a.compareTo(b);
    } else if (a is String && b is String) {
      final da = DateTime.tryParse(a), db = DateTime.tryParse(b);
      if (da != null && db != null && a.contains('-')) {
        r = da.compareTo(db);
      } else {
        r = a.toLowerCase().compareTo(b.toLowerCase());
      }
    } else if (a is num && b is num) {
      r = a.compareTo(b);
    } else if (a is bool && b is bool) {
      r = (a ? 1 : 0) - (b ? 1 : 0);
    } else {
      r = '$a'.compareTo('$b');
    }
    return asc ? r : -r;
  }

  indexed.sort((x, y) {
    final r = cmp(valueOf(x.$2, key), valueOf(y.$2, key));
    return r != 0 ? r : x.$1 - y.$1;
  });
  return [for (final e in indexed) e.$2];
}

/// TRACKER_PAGE_SIZE_OPTIONS / _DEFAULT.
const trackerPageSizes = [5, 10, 15, 25, 50, 100];
const trackerPageSizeDefault = 10;

// ------------------------------------------------------------------ breakdown

class FlowBucket {
  FlowBucket(this.key, this.label, this.amount, this.count, [this.percent = 0]);
  final String key;
  final String label;
  final num amount;
  final int count;
  num percent;
}

/// assignPercentages: largest-remainder apportionment in tenths, so the column
/// sums to exactly 100.
List<FlowBucket> assignPercentages(List<FlowBucket> rows, num total) {
  if (rows.isEmpty || total <= 0) {
    for (final r in rows) {
      r.percent = 0;
    }
    return rows;
  }
  final exact = [for (final r in rows) (r.amount / total) * 100];
  final floored = [for (final n in exact) (n * 10).floor() / 10];
  final used = floored.fold<num>(0, (s, n) => s + n);
  var remaining = ((100 - used) * 10).round();
  final order = [for (var i = 0; i < exact.length; i++) (i, exact[i] * 10 - (exact[i] * 10).floor())]
    ..sort((a, b) => b.$2.compareTo(a.$2));
  final percents = [...floored];
  for (final (i, _) in order) {
    if (remaining <= 0) break;
    percents[i] = ((percents[i] + 0.1) * 10).round() / 10;
    remaining -= 1;
  }
  for (var i = 0; i < rows.length; i++) {
    rows[i].percent = percents[i];
  }
  return rows;
}

/// The only fields a breakdown touches.
abstract class LedgerRowLike {
  String get type;
  num get inQty;
  num get outQty;
}

List<FlowBucket> _sorted(Map<String, (String, num, int)> acc, num total) {
  final out = <FlowBucket>[];
  acc.forEach((k, v) => out.add(FlowBucket(k, v.$1, v.$2, v.$3)));
  out.sort((a, b) {
    final r = b.amount.compareTo(a.amount);
    return r != 0 ? r : a.label.compareTo(b.label);
  });
  return assignPercentages(out, total);
}

/// groupLedgerBy: one side of the flow, bucketed by [keyOf], biggest first.
List<FlowBucket> groupLedgerBy<T extends LedgerRowLike>(
  List<T> rows,
  bool inDirection,
  String? Function(T row) keyOf, [
  Map<String, String> labels = const {},
]) {
  final acc = <String, (String, num, int)>{};
  num total = 0;
  for (final row in rows) {
    final qty = inDirection ? row.inQty : row.outQty;
    if (!(qty > 0)) continue;
    final k = (keyOf(row) ?? '').trim();
    final key = k.isEmpty ? 'Other' : k;
    final b = acc[key];
    acc[key] = b == null ? (labels[key] ?? key, qty, 1) : (b.$1, b.$2 + qty, b.$3 + 1);
    total += qty;
  }
  return _sorted(acc, total);
}

List<FlowBucket> groupLedgerByType<T extends LedgerRowLike>(List<T> rows, bool inDirection,
        [Map<String, String> labels = const {}]) =>
    groupLedgerBy(rows, inDirection, (r) => r.type, labels);

/// groupLedgerByNet: what is LEFT per key (in − out), positives only.
List<FlowBucket> groupLedgerByNet<T extends LedgerRowLike>(
  List<T> rows,
  String? Function(T row) keyOf, [
  Map<String, String> labels = const {},
]) {
  const eps = 1e-6;
  final acc = <String, (String, num, int)>{};
  for (final row in rows) {
    final delta = row.inQty - row.outQty;
    if (delta == 0) continue;
    final k = (keyOf(row) ?? '').trim();
    final key = k.isEmpty ? 'Other' : k;
    final b = acc[key];
    acc[key] = b == null ? (labels[key] ?? key, delta, 1) : (b.$1, b.$2 + delta, b.$3 + 1);
  }
  acc.removeWhere((_, v) => v.$2 <= eps);
  final total = acc.values.fold<num>(0, (s, v) => s + v.$2);
  return _sorted(acc, total);
}

const eggMoveLabels = {
  'InternalUse': 'Internal use',
  'Driver Load Out': 'Driver load-out',
  'Driver Return In': 'Driver return',
  'Delivery Load': 'Delivery load-out',
  'Delivery Return': 'Delivery return',
};

const feedMoveLabels = {
  'Purchase IN': 'Purchase',
  'Usage OUT': 'Used in production',
};

// ------------------------------------------------------------------ ledger row

/// One line of the Egg / Feed / Ingredients ledgers.
class StockLedgerRow implements LedgerRowLike {
  StockLedgerRow({
    required this.sortKey,
    required this.date,
    required this.type,
    required this.description,
    required this.inQty,
    required this.outQty,
    this.balance = 0,
    this.seq = 0,
    this.itemName,
    this.cost,
    this.recognized,
    this.costLayers,
    this.reversed,
    this.productionRecordId,
  });
  final String sortKey;
  final String date;
  @override
  final String type;
  final String description;
  @override
  final num inQty;
  @override
  final num outQty;
  num balance;
  int seq;
  final String? itemName;
  final num? cost;
  final num? recognized;
  final int? costLayers;
  final bool? reversed;
  final int? productionRecordId;
}

typedef _Line = ({StockLedgerRow row, int order});

List<StockLedgerRow> _runBalance(List<_Line> lines) {
  lines.sort((a, b) {
    final da = tMs(a.row.date), db = tMs(b.row.date);
    if (da != db) return da - db;
    if (a.order != b.order) return a.order - b.order;
    return a.row.sortKey.compareTo(b.row.sortKey);
  });
  num bal = 0;
  final rows = <StockLedgerRow>[];
  for (var i = 0; i < lines.length; i++) {
    final r = lines[i].row;
    bal += r.inQty - r.outQty;
    r
      ..balance = bal
      ..seq = i;
    rows.add(r);
  }
  return rows;
}

String _adjTypeLabel(String t) => switch (t) {
      'OpeningBalance' => 'Opening balance',
      'Stocktake' => 'Stocktake',
      'Correction' => 'Correction',
      _ => t.isEmpty ? 'Adjustment' : t,
    };

/// The three manual adjustment types, as both trackers' dialogs offer them.
const adjustmentTypes = [('Correction', 'Correction'), ('Stocktake', 'Stocktake'), ('OpeningBalance', 'Opening balance')];

// ------------------------------------------------------------------ eggs

bool isEggSaleProduct(Object? product) => tStr(product).trim().toLowerCase().contains('egg');

/// Sales generated by a driver return / delivery reconcile: their eggs already
/// left as a load-out move, so counting the sale too deducts them twice.
bool isStockLedgerBackedSale(Object? description) {
  final d = tStr(description).trim().toLowerCase();
  return d.startsWith('driver return #') || d.startsWith('delivery #');
}

const _gradeLegacy = {'p1': 'Small', 'p2': 'Medium', 'p3': 'Large', 'p4': 'XLarge'};
const _gradeLabels = {
  'Small': 'Small',
  'Medium': 'Medium',
  'Large': 'Large',
  'XLarge': 'X-Large',
  'Jumbo': 'Jumbo',
  'Seconds': 'Seconds / B-grade',
  'Cracks': 'Cracks',
  'Mixed': 'Mixed grades',
};

String formatEggGradeLabel(Object? value) {
  final v = tStr(value).trim();
  if (v.isEmpty) return '—';
  final lookup = _gradeLegacy[v.toLowerCase()] ?? v;
  return _gradeLabels[lookup] ?? lookup;
}

String resolveEggFlockName(Map p, List<Map> flocks) {
  final fromApi = tStr(p['flockName']).trim();
  if (fromApi.isNotEmpty && fromApi.toLowerCase() != 'unknown flock') return fromApi;
  final id = tIntOrNull(p['flockId']);
  final f = flocks.where((f) => tIntOrNull(f['flockId']) == id).firstOrNull;
  final name = tStr(f?['name']).trim();
  if (name.isNotEmpty) return name;
  return id != null && id != 0 ? 'Flock #$id' : '—';
}

/// netReversalPairs: drops a posting and the reversal that undoes it (same
/// type, record and size, opposite sign), matched oldest-first like brackets.
List<Map> netReversalPairs(List<Map> moves) {
  int qtyOf(Map m) => tNum(m['quantity']).round();
  final open = <String, List<Map>>{};
  final cancelled = <Object?>{};
  final chronological = [...moves]..sort((a, b) => tMs(a['createdDate']) - tMs(b['createdDate']));
  for (final m in chronological) {
    if (m['relatedId'] == null) continue;
    final q = qtyOf(m);
    if (q == 0) continue;
    final key = '${tStr(m['txnType']).trim()}|${m['relatedId']}|${q.abs()}';
    final list = open.putIfAbsent(key, () => []);
    final last = list.isEmpty ? null : list.last;
    if (last != null && qtyOf(last).sign == -q.sign) {
      list.removeLast();
      cancelled
        ..add(last['poultryStockTransactionId'])
        ..add(m['poultryStockTransactionId']);
    } else {
      list.add(m);
    }
  }
  return [for (final m in moves) if (!cancelled.contains(m['poultryStockTransactionId'])) m];
}

class EggLedger {
  EggLedger(this.rows, this.currentEggsAtHand, this.lastUpdatedIso, this.unmatchedLedgerDelta);
  final List<StockLedgerRow> rows;
  final num currentEggsAtHand;
  final String lastUpdatedIso;
  final num unmatchedLedgerDelta;
}

const _eggLossLines = [
  ('brokenEggs', 'Broken eggs', 'non-saleable', 1),
  ('meatyEggs', 'Meaty eggs', 'non-saleable', 2),
  ('softEggs', 'Soft eggs', 'non-saleable', 3),
  ('lostEggs', 'Lost eggs', 'lost', 4),
];

/// buildEggStockLedger. [ledgerBalance] is the server's "In stock" for the egg
/// product; when given it is the answer, and any gap becomes an Unmatched row.
EggLedger buildEggStockLedger(
  List<Map> productions,
  List<Map> sales,
  List<Map> flocks,
  List<Map> adjustments,
  List<Map> stockMoves, [
  num? ledgerBalance,
]) {
  final lines = <_Line>[];

  for (final p in productions) {
    final inCount = math.max<num>(0, tNum(p['totalProduction']));
    final flock = resolveEggFlockName(p, flocks);
    final date = tStr(p['productionDate']);
    final grade = tStr(p['eggGrade']).trim();
    final gradeBit = grade.isNotEmpty ? ' — ${formatEggGradeLabel(grade)}' : '';
    lines.add((
      row: StockLedgerRow(
        sortKey: 'prod_${p['productionId']}',
        date: date,
        type: 'Production',
        description: '$flock$gradeBit — collected',
        inQty: inCount,
        outQty: 0,
      ),
      order: 0,
    ));
    for (final (key, type, note, order) in _eggLossLines) {
      final qty = math.max<num>(0, tNum(p[key]));
      if (qty <= 0) continue;
      lines.add((
        row: StockLedgerRow(
          sortKey: '${key}_${p['productionId']}',
          date: date,
          type: type,
          description: '$flock — $note',
          inQty: 0,
          outQty: qty,
        ),
        order: order,
      ));
    }
  }

  for (final s in sales) {
    if (!isEggSaleProduct(s['product'])) continue;
    if (isStockLedgerBackedSale(s['saleDescription'])) continue;
    final qty = math.max<num>(0, tNum(s['quantity']));
    if (qty <= 0) continue;
    final who = tStr(s['customerName']).trim();
    final product = tStr(s['product']);
    lines.add((
      row: StockLedgerRow(
        sortKey: 'sale_${s['saleId']}',
        date: tStr(s['saleDate']),
        type: 'Sale',
        description: who.isNotEmpty ? '$who — $product' : (product.isNotEmpty ? product : 'Egg sale'),
        inQty: 0,
        outQty: qty,
      ),
      order: 5,
    ));
  }

  for (final a in adjustments) {
    final d = tNum(a['eggDelta']).round();
    if (d == 0) continue;
    final raw = tStr(a['adjustmentDate']);
    final dateStr = raw.isNotEmpty ? raw : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true).toIso8601String();
    final typeLabel = _adjTypeLabel(tStr(a['adjustmentType']));
    final desc = tStr(a['description']).trim();
    lines.add((
      row: StockLedgerRow(
        sortKey: 'eggadj_${a['adjustmentId']}',
        date: dateStr,
        type: 'Adjustment',
        description: '$typeLabel: ${desc.isNotEmpty ? desc : typeLabel}',
        inQty: d > 0 ? d : 0,
        outQty: d < 0 ? -d : 0,
      ),
      order: 6,
    ));
  }

  for (final m in netReversalPairs(stockMoves)) {
    final type = tStr(m['txnType']).trim();
    if (type.isEmpty) continue;
    // Production / Sale moves are the ledger's copy of a record listed above —
    // unless nothing posted them for a record (no relatedId).
    if ((type == 'Production' || type == 'Sale') && m['relatedId'] != null) continue;
    final qty = tNum(m['quantity']).round();
    if (qty == 0) continue;
    final note = tStr(m['note']).trim();
    lines.add((
      row: StockLedgerRow(
        sortKey: 'stockmove_${m['poultryStockTransactionId']}',
        date: tStr(m['createdDate']),
        type: type,
        description: note.isNotEmpty ? note : type,
        inQty: qty > 0 ? qty : 0,
        outQty: qty < 0 ? -qty : 0,
      ),
      order: 7,
    ));
  }

  final rows = _runBalance(lines);
  final derived = rows.isNotEmpty ? rows.last.balance : 0;
  final authoritative = ledgerBalance != null && ledgerBalance.isFinite ? ledgerBalance.round() : derived;
  final unmatched = authoritative - derived;
  if (unmatched != 0) {
    rows.add(StockLedgerRow(
      sortKey: 'unmatched_ledger',
      date: rows.isNotEmpty ? rows.last.date : DateTime.now().toUtc().toIso8601String(),
      type: 'Unmatched',
      description:
          'Unmatched ledger movements — stock transactions with no matching production, sale or adjustment record',
      inQty: unmatched > 0 ? unmatched : 0,
      outQty: unmatched < 0 ? -unmatched : 0,
      balance: authoritative,
      seq: rows.length,
    ));
  }
  return EggLedger(
    rows,
    authoritative,
    rows.isNotEmpty ? rows.last.date : DateTime.now().toUtc().toIso8601String(),
    unmatched,
  );
}

/// The products whose stock is "eggs": the raw egg product, or the legacy names.
bool isEggProduct(Map p) =>
    tBool(p['isRawEggProduct']) || p['name'] == 'Eggs' || p['name'] == 'Chicken Eggs';

// ------------------------------------------------------------------ feed

enum FeedKind { ingredient, finishedFeed }

bool isFinishedFeedCategory(Object? c) => c != null && RegExp('finish', caseSensitive: false).hasMatch('$c');
bool isIngredientCategory(Object? c) =>
    c != null && RegExp('feed', caseSensitive: false).hasMatch('$c') && !isFinishedFeedCategory(c);

FeedKind? feedItemKind(Object? c) {
  if (isFinishedFeedCategory(c)) return FeedKind.finishedFeed;
  if (isIngredientCategory(c)) return FeedKind.ingredient;
  return null;
}

/// productionQty: a purchase in STOCK units (bags × kg per bag). A factor of 0
/// counts as 1, as migration 175 does.
num productionQty(Map p) {
  final qty = tNum(p['quantity']);
  final f = tNum(p['productionUnitsPerPurchaseUnit']);
  return qty * (f == 0 ? 1 : f);
}

num _fmtQty(num n) => ((n + 2.220446049250313e-16) * 1000).round() / 1000;
String _unitBit(Object? u) {
  final s = tStr(u).trim();
  return s.isNotEmpty ? ' $s' : '';
}

String _iso(Object? raw) {
  final d = tStr(raw).trim();
  final parsed = d.isEmpty ? null : DateTime.tryParse(d);
  return (parsed ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)).toUtc().toIso8601String();
}

class FeedLedger {
  FeedLedger(this.rows, this.atHand, this.lastUpdatedIso, this.totalIn, this.totalOut);
  final List<StockLedgerRow> rows;
  final num atHand;
  final String lastUpdatedIso;
  final num totalIn;
  final num totalOut;
}

/// buildFeedStockLedger: ONE half of the feed store (finished feed or
/// ingredients) from the raw-material store's purchases, usage and adjustments,
/// plus this page's own whole-farm kg corrections.
FeedLedger buildFeedStockLedger({
  required FeedKind kind,
  required List<Map> items,
  required List<Map> purchases,
  required List<Map> usages,
  required List<Map> adjustments,
  List<Map> manualAdjustments = const [],
}) {
  final inScope = {
    for (final i in items)
      if (feedItemKind(i['category']) == kind) tIntOrNull(i['poultryRawMaterialItemId']),
  };
  final byId = {for (final i in items) tIntOrNull(i['poultryRawMaterialItemId']): i};
  final otherHalf = {
    for (final i in items)
      if (feedItemKind(i['category']) != null && feedItemKind(i['category']) != kind)
        tIntOrNull(i['poultryRawMaterialItemId']),
  };
  bool isFeed(int? id, Object? rowCategory) =>
      inScope.contains(id) || (!otherHalf.contains(id) && feedItemKind(rowCategory) == kind);
  String nameOf(int? id, Object? fallback) {
    final n = tStr(byId[id]?['itemName']);
    if (n.isNotEmpty) return n;
    final f = tStr(fallback);
    return f.isNotEmpty ? f : 'Item #$id';
  }

  String unitOf(int? id, Object? fallback) {
    final u = tStr(byId[id]?['unitOfMeasure']);
    return u.isNotEmpty ? u : tStr(fallback);
  }

  final lines = <_Line>[];

  for (final p in purchases) {
    final id = tIntOrNull(p['poultryRawMaterialItemId']);
    if (!isFeed(id, p['category'])) continue;
    final qty = productionQty(p);
    if (qty <= 0) continue;
    final unit = unitOf(id, p['unitOfMeasure']);
    final from = tStr(p['supplierName']).trim();
    final f = tNum(p['productionUnitsPerPurchaseUnit']);
    final factor = f == 0 ? 1 : f;
    final bought = factor != 1
        ? ' — bought as ${jsNum(_fmtQty(tNum(p['quantity'])))}${_unitBit(byId[id]?['purchaseUnitOfMeasure'])} × ${jsNum(_fmtQty(factor))}'
        : '';
    final name = nameOf(id, p['itemName']);
    lines.add((
      row: StockLedgerRow(
        sortKey: 'purchase_${p['poultryRawMaterialPurchaseId']}',
        itemName: name,
        date: _iso(p['purchaseDate']),
        type: 'Purchase IN',
        description: '$name — purchased (${jsNum(_fmtQty(qty))}${_unitBit(unit)})${from.isNotEmpty ? ' from $from' : ''}$bought',
        inQty: qty,
        outQty: 0,
      ),
      order: 0,
    ));
  }

  for (final u in usages) {
    final id = tIntOrNull(u['poultryRawMaterialItemId']);
    if (!isFeed(id, null)) continue;
    final qty = tNum(u['quantityUsed']);
    if (qty <= 0) continue;
    final unit = unitOf(id, u['unitOfMeasure']);
    final batchId = u['poultryFeedProductionBatchId'];
    final via = batchId != null && batchId != 0
        ? ' — feed production ${u['feedProductionBatchNumber'] ?? '#$batchId'}'
        : ' — used in production';
    final name = nameOf(id, u['itemName']);
    lines.add((
      row: StockLedgerRow(
        sortKey: 'usage_${u['poultryRawMaterialUsageId']}',
        itemName: name,
        date: _iso(u['usedDate']),
        type: 'Usage OUT',
        description: '$name$via (${jsNum(qty)}${_unitBit(unit)})',
        inQty: 0,
        outQty: qty,
        cost: u['operationalCost'] == null ? null : tNum(u['operationalCost']),
        recognized: u['recognizedCost'] == null ? null : tNum(u['recognizedCost']),
        costLayers: tIntOrNull(u['costLayerCount']),
        reversed: u['isReversed'] == null ? null : tBool(u['isReversed']),
        productionRecordId: tIntOrNull(u['productionRecordId']),
      ),
      order: 1,
    ));
  }

  for (final a in adjustments) {
    final id = tIntOrNull(a['poultryRawMaterialItemId']);
    if (!isFeed(id, a['category'])) continue;
    final qty = tNum(a['quantity']);
    if (qty == 0) continue;
    final unit = unitOf(id, a['unitOfMeasure']);
    final mt = tStr(a['movementType']).trim();
    final label = mt.isEmpty ? 'Adjustment' : mt;
    final note = tStr(a['note']).trim();
    final name = nameOf(id, a['itemName']);
    lines.add((
      row: StockLedgerRow(
        sortKey: 'stockadj_${a['poultryRawMaterialAdjustmentId']}',
        itemName: name,
        date: _iso(a['adjustedDate']),
        type: 'Adjustment',
        description: '$name — $label${note.isNotEmpty ? ': $note' : ''} (${jsNum(qty.abs())}${_unitBit(unit)})',
        inQty: qty > 0 ? qty : 0,
        outQty: qty < 0 ? -qty : 0,
      ),
      order: 2,
    ));
  }

  for (final a in manualAdjustments) {
    final d = tNum(a['feedDeltaKg']);
    if (d == 0) continue;
    final typeLabel = _adjTypeLabel(tStr(a['adjustmentType']));
    final desc = tStr(a['description']).trim();
    lines.add((
      row: StockLedgerRow(
        sortKey: 'feedadj_${a['adjustmentId']}',
        date: _iso(a['adjustmentDate']),
        type: 'Adjustment',
        description: '$typeLabel: ${desc.isNotEmpty ? desc : typeLabel}',
        inQty: d > 0 ? d : 0,
        outQty: d < 0 ? -d : 0,
      ),
      order: 3,
    ));
  }

  final rows = _runBalance(lines);
  num tin = 0, tout = 0;
  for (final r in rows) {
    tin += r.inQty;
    tout += r.outQty;
  }
  return FeedLedger(
    rows,
    rows.isNotEmpty ? rows.last.balance : 0,
    rows.isNotEmpty ? rows.last.date : DateTime.now().toUtc().toIso8601String(),
    tin,
    tout,
  );
}

// ------------------------------------------------------------------ feed per item

class FeedItemMovement {
  FeedItemMovement({
    required this.key,
    required this.itemId,
    required this.date,
    required this.timestamp,
    required this.kind,
    required this.label,
    required this.description,
    required this.inQty,
    required this.outQty,
    this.cost,
    this.recognized,
    this.reversed,
    this.productionRecordId,
    required this.order,
    required this.id,
  });
  final String key;
  final int itemId;
  final String date;
  final String timestamp;
  final String kind; // Purchase | Usage | Adjustment
  final String label;
  final String description;
  final num inQty;
  final num outQty;
  final num? cost;
  final num? recognized;
  final bool? reversed;
  final int? productionRecordId;
  final int order;
  final int id;
  num balance = 0;
  int seq = 0;
  // Filled in by the page for the ledger table.
  String itemName = '';
  String unit = '';
}

class FeedItemPosition {
  FeedItemPosition({
    required this.itemId,
    required this.itemName,
    required this.category,
    required this.kind,
    required this.unit,
    required this.isActive,
    required this.minimumStockAlert,
    required this.opening,
    required this.inQty,
    required this.outQty,
    required this.closing,
    required this.movementCount,
    required this.derivedNow,
    required this.onRecord,
    required this.drift,
    required this.lastMovementDate,
  });
  final int itemId;
  final String itemName;
  final String category;
  final FeedKind kind;
  final String unit;
  final bool isActive;
  final num minimumStockAlert;
  final num opening, inQty, outQty, closing;
  final int movementCount;
  final num derivedNow, onRecord, drift;
  final String? lastMovementDate;
}

class FeedUnitTotals {
  FeedUnitTotals(this.unit);
  final String unit;
  int items = 0;
  num opening = 0, inQty = 0, outQty = 0, closing = 0, onRecord = 0;
  int movementCount = 0;
  int driftItems = 0;
}

String dayOf(Object? raw) {
  final s = tStr(raw).trim();
  return s.length >= 10 ? s.substring(0, 10) : s;
}

String _humanMovement(Object? t) {
  final v = tStr(t).trim();
  if (v.isEmpty) return 'Adjustment';
  return switch (v) {
    'ProductionReversal' => 'Production reversed',
    'FeedProductionReversal' => 'Feed production reversed',
    'Correction' => 'Correction',
    'Stocktake' => 'Stocktake',
    'OpeningBalance' => 'Opening balance',
    _ => v.replaceAllMapped(RegExp('([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}'),
  };
}

/// buildFeedItemMovements: every feed movement per item, in that item's own
/// ledger order, with a running balance per item.
Map<int, List<FeedItemMovement>> buildFeedItemMovements(
    List<Map> items, List<Map> purchases, List<Map> usages, List<Map> adjustments) {
  final feedItems = <int, Map>{
    for (final i in items)
      if (feedItemKind(i['category']) != null && tIntOrNull(i['poultryRawMaterialItemId']) != null)
        tIntOrNull(i['poultryRawMaterialItemId'])!: i,
  };
  String unitOf(int id, Object? fb) {
    final u = tStr(feedItems[id]?['unitOfMeasure']).trim();
    return u.isNotEmpty ? u : tStr(fb).trim();
  }

  final drafts = <int, List<FeedItemMovement>>{};
  void push(int id, FeedItemMovement m) => drafts.putIfAbsent(id, () => []).add(m);

  for (final p in purchases) {
    final id = tIntOrNull(p['poultryRawMaterialItemId']);
    if (id == null || !feedItems.containsKey(id)) continue;
    final qty = productionQty(p);
    if (qty == 0) continue;
    final unit = unitOf(id, p['unitOfMeasure']);
    final srcBatch = p['sourceFeedProductionBatchId'];
    final batch = p['feedProductionBatchNumber'] ?? (srcBatch != null && srcBatch != 0 ? '#$srcBatch' : null);
    final supplier = tStr(p['supplierName']).trim();
    var label = 'Purchase';
    var description = supplier.isNotEmpty ? 'Purchased from $supplier' : 'Purchased';
    final role = tStr(p['feedProductionRole']);
    if (role == 'Produced') {
      label = 'Produced';
      description = batch != null ? 'Produced by feed batch $batch' : 'Produced by feed production';
    } else if (role == 'Purchased' || (srcBatch != null && srcBatch != 0)) {
      label = 'Bought for production';
      description = batch != null
          ? 'Bought for feed batch $batch${supplier.isNotEmpty ? ' from $supplier' : ''}'
          : 'Bought during feed production';
    }
    final f = tNum(p['productionUnitsPerPurchaseUnit']);
    final factor = f == 0 ? 1 : f;
    if (factor != 1) {
      final bought = tNum(p['quantity']);
      final boughtUnit = tStr(feedItems[id]?['purchaseUnitOfMeasure']).trim();
      description += ' — ${loc(bought)}${boughtUnit.isNotEmpty ? ' $boughtUnit' : ''}'
          ' × ${loc(factor)} = ${loc(qty)}${unit.isNotEmpty ? ' $unit' : ''}';
    }
    final notes = tStr(p['notes']).trim();
    if (notes.isNotEmpty) description += ' · $notes';
    push(
        id,
        FeedItemMovement(
          key: 'purchase_${p['poultryRawMaterialPurchaseId']}',
          id: tIntOrNull(p['poultryRawMaterialPurchaseId']) ?? 0,
          itemId: id,
          date: dayOf(p['purchaseDate']),
          timestamp: tStr(p['purchaseDate']),
          kind: 'Purchase',
          label: label,
          description: description,
          inQty: qty > 0 ? qty : 0,
          outQty: qty < 0 ? -qty : 0,
          order: 0,
        ));
  }

  for (final u in usages) {
    final id = tIntOrNull(u['poultryRawMaterialItemId']);
    if (id == null || !feedItems.containsKey(id)) continue;
    final qty = tNum(u['quantityUsed']);
    if (qty == 0) continue;
    final batchId = u['poultryFeedProductionBatchId'];
    final hasBatch = batchId != null && batchId != 0;
    final batch = u['feedProductionBatchNumber'] ?? (hasBatch ? '#$batchId' : null);
    var label = 'Fed to flock';
    var description = 'Consumed in production';
    if (hasBatch) {
      label = 'Used in feed production';
      description = batch != null ? 'Drawn into feed batch $batch' : 'Drawn into feed production';
      final feedName = tStr(u['feedProductionFeedName']).trim();
      if (feedName.isNotEmpty) description += ' → $feedName';
    }
    final vr = tStr(u['varianceReason']).trim();
    if (vr.isNotEmpty) description += ' · $vr';
    final notes = tStr(u['notes']).trim();
    if (notes.isNotEmpty) description += ' · $notes';
    final reversed = tBool(u['isReversed']);
    if (reversed) description += ' · reversed';
    push(
        id,
        FeedItemMovement(
          key: 'usage_${u['poultryRawMaterialUsageId']}',
          id: tIntOrNull(u['poultryRawMaterialUsageId']) ?? 0,
          itemId: id,
          date: dayOf(u['usedDate']),
          timestamp: tStr(u['usedDate']),
          kind: 'Usage',
          label: label,
          description: description,
          inQty: qty < 0 ? -qty : 0,
          outQty: qty > 0 ? qty : 0,
          order: 1,
          cost: u['operationalCost'] == null ? null : tNum(u['operationalCost']),
          recognized: u['recognizedCost'] == null ? null : tNum(u['recognizedCost']),
          reversed: u['isReversed'] == null ? null : reversed,
          productionRecordId: tIntOrNull(u['productionRecordId']),
        ));
  }

  for (final a in adjustments) {
    final id = tIntOrNull(a['poultryRawMaterialItemId']);
    if (id == null || !feedItems.containsKey(id)) continue;
    final qty = tNum(a['quantity']);
    if (qty == 0) continue;
    final note = tStr(a['note']).trim();
    push(
        id,
        FeedItemMovement(
          key: 'adjustment_${a['poultryRawMaterialAdjustmentId']}',
          id: tIntOrNull(a['poultryRawMaterialAdjustmentId']) ?? 0,
          itemId: id,
          date: dayOf(a['adjustedDate']),
          timestamp: tStr(a['adjustedDate']),
          kind: 'Adjustment',
          label: _humanMovement(a['movementType']),
          description: note.isNotEmpty ? note : (qty > 0 ? 'Stock increased' : 'Stock decreased'),
          inQty: qty > 0 ? qty : 0,
          outQty: qty < 0 ? -qty : 0,
          order: 2,
        ));
  }

  final out = <int, List<FeedItemMovement>>{};
  drafts.forEach((id, list) {
    list.sort((a, b) {
      if (a.timestamp != b.timestamp) return a.timestamp.compareTo(b.timestamp);
      if (a.order != b.order) return a.order - b.order;
      return a.id - b.id;
    });
    num balance = 0;
    for (var i = 0; i < list.length; i++) {
      balance += list[i].inQty - list[i].outQty;
      list[i]
        ..balance = balance
        ..seq = i;
    }
    out[id] = list;
  });
  for (final id in feedItems.keys) {
    out.putIfAbsent(id, () => []);
  }
  return out;
}

/// buildFeedItemPositions: per-item opening / in / out / closing for
/// [from, to] (yyyy-MM-dd, empty = open-ended), plus drift against the stored
/// stock figure.
List<FeedItemPosition> buildFeedItemPositions(
    List<Map> items, Map<int, List<FeedItemMovement>> moves, String from, String to) {
  final positions = <FeedItemPosition>[];
  for (final item in items) {
    final kind = feedItemKind(item['category']);
    if (kind == null) continue;
    final id = tIntOrNull(item['poultryRawMaterialItemId']) ?? 0;
    final list = moves[id] ?? const <FeedItemMovement>[];
    num opening = 0, inQty = 0, outQty = 0;
    var count = 0;
    for (final m in list) {
      if (from.isNotEmpty && m.date.compareTo(from) < 0) {
        opening += m.inQty - m.outQty;
        continue;
      }
      if (to.isNotEmpty && m.date.compareTo(to) > 0) continue;
      inQty += m.inQty;
      outQty += m.outQty;
      count++;
    }
    final derivedNow = list.isNotEmpty ? list.last.balance : 0;
    final onRecord = tNum(item['currentQuantity']);
    positions.add(FeedItemPosition(
      itemId: id,
      itemName: tStr(item['itemName']),
      category: tStr(item['category']),
      kind: kind,
      unit: tStr(item['unitOfMeasure']).trim(),
      isActive: tBool(item['isActive']),
      minimumStockAlert: tNum(item['minimumStockAlert']),
      opening: opening,
      inQty: inQty,
      outQty: outQty,
      closing: opening + inQty - outQty,
      movementCount: count,
      derivedNow: derivedNow,
      onRecord: onRecord,
      drift: ((derivedNow - onRecord) * 1000).round() / 1000,
      lastMovementDate: list.isNotEmpty ? list.last.date : null,
    ));
  }
  positions.sort((a, b) => a.itemName.compareTo(b.itemName));
  return positions;
}

/// summariseFeedPositions: one line per stocking unit, never summed across.
List<FeedUnitTotals> summariseFeedPositions(List<FeedItemPosition> positions) {
  final byUnit = <String, FeedUnitTotals>{};
  for (final p in positions) {
    final t = byUnit.putIfAbsent(p.unit, () => FeedUnitTotals(p.unit));
    t.items++;
    t.opening += p.opening;
    t.inQty += p.inQty;
    t.outQty += p.outQty;
    t.closing += p.closing;
    t.onRecord += p.onRecord;
    t.movementCount += p.movementCount;
    if (p.drift != 0) t.driftItems++;
  }
  return byUnit.values.toList()
    ..sort((a, b) {
      final r = b.items - a.items;
      return r != 0 ? r : a.unit.compareTo(b.unit);
    });
}

// ------------------------------------------------------------------ cost note

String recognizedCostNote(num recognized, num operational) {
  if (recognized > 0) return 'Charged to Profit & Loss when this usage was recorded.';
  if (operational > 0) {
    return 'Already charged to Profit & Loss when this stock was bought, so using it adds no new expense.';
  }
  return 'No cost layers were drawn for this usage.';
}

// ------------------------------------------------------------------ birds

/// Sales that reduce the live bird count (not eggs).
bool isBirdSaleProduct(Object? product) {
  final p = tStr(product).trim().toLowerCase();
  if (p.isEmpty || p.contains('egg')) return false;
  return RegExp('bird|chicken|broiler|layer|cull|live|poultry|hen|rooster').hasMatch(p);
}

/// flockCountsTowardBirdTotals: arrived AND active.
bool flockCountsTowardBirdTotals(Map f) => tBool(f['active']) && tBool(f['hasArrived']);

class BirdsLedgerRow {
  BirdsLedgerRow(this.id, this.date, this.type, this.category, this.flockId, this.flockName, this.quantity,
      this.description);
  final String id;
  final String date;
  final String type; // IN | OUT
  final String category; // Placement | Mortality | Bird sale
  final int flockId;
  final String flockName;
  final num quantity;
  final String description;
}

class FlockBirdsSummary {
  FlockBirdsSummary(this.flockId, this.flockName, this.placedIn, this.totalMortalityOut, this.totalBirdSalesOut,
      this.birdsLeftCalculated, this.birdsLeftFromLatestLog);
  final int flockId;
  final String flockName;
  final num placedIn, totalMortalityOut, totalBirdSalesOut, birdsLeftCalculated;
  final num? birdsLeftFromLatestLog;
}

String _datePart(Object? v) => tStr(v).split('T').first;

List<BirdsLedgerRow> buildBirdsLeftLedger(List<Map> flocks, List<Map> records, List<Map> sales) {
  final rows = <BirdsLedgerRow>[];
  String flockName(int id) {
    final f = flocks.where((f) => tIntOrNull(f['flockId']) == id).firstOrNull;
    final n = f?['name'];
    return n != null ? '$n' : 'Flock #$id';
  }

  for (final f in flocks) {
    final qty = math.max<num>(0, tNum(f['quantity']));
    if (qty <= 0) continue;
    final id = tIntOrNull(f['flockId']) ?? 0;
    final start = _datePart(f['startDate']);
    rows.add(BirdsLedgerRow(
      'in-flock-$id',
      start.isNotEmpty ? start : isoDay(DateTime.now()),
      'IN',
      'Placement',
      id,
      f['name'] != null ? '${f['name']}' : flockName(id),
      qty,
      'Birds placed when flock was created (${loc(qty)})',
    ));
  }

  for (final r in records) {
    final fid = tIntOrNull(r['flockId']);
    if (fid == null) continue;
    final mort = tNum(r['mortality']);
    if (mort <= 0) continue;
    final d = _datePart(r['date']);
    rows.add(BirdsLedgerRow(
      'mort-${r['id'] ?? '$fid-$d'}',
      d,
      'OUT',
      'Mortality',
      fid,
      r['flockName'] != null ? '${r['flockName']}' : flockName(fid),
      mort,
      'Deaths on production record',
    ));
  }

  for (final s in sales) {
    if (!isBirdSaleProduct(s['product'])) continue;
    final fid = tIntOrNull(s['flockId']);
    if (fid == null) continue;
    final q = tNum(s['quantity']);
    if (q <= 0) continue;
    final d = _datePart(s['saleDate']);
    final product = tStr(s['product']);
    rows.add(BirdsLedgerRow(
      'sale-${s['saleId'] ?? '$fid-$d'}',
      d,
      'OUT',
      'Bird sale',
      fid,
      flockName(fid),
      q,
      product.isNotEmpty ? 'Sale: $product' : 'Bird sale',
    ));
  }

  rows.sort((a, b) {
    if (a.date != b.date) return b.date.compareTo(a.date);
    if (a.type != b.type) return a.type == 'IN' ? -1 : 1;
    return a.flockId - b.flockId;
  });
  return rows;
}

/// getBirdsLeftFromRecord on the latest production record of a flock.
num birdsLeftFromLatestRecord(List<Map> records, int flockId) {
  final byFlock = [for (final r in records) if (tIntOrNull(r['flockId']) == flockId) r];
  if (byFlock.isEmpty) return 0;
  byFlock.sort((a, b) {
    final d = tMs(b['date']) - tMs(a['date']);
    if (d != 0) return d;
    final u = tMs(b['updatedAt']) - tMs(a['updatedAt']);
    if (u != 0) return u;
    return (tNum(b['id']) - tNum(a['id'])).toInt();
  });
  final r = byFlock.first;
  final birds = tNum(r['noOfBirds']);
  final left = tNum(r['noOfBirdsLeft']);
  final mort = tNum(r['mortality']);
  if (birds <= 0) return math.max<num>(0, left);
  final sameDayLeft = math.max<num>(0, birds - mort);
  if (mort > 0 && left >= birds) return math.min(sameDayLeft, birds);
  return math.max<num>(0, math.min(left, birds));
}

List<FlockBirdsSummary> summarizeBirdsLeftByFlock(List<Map> flocks, List<Map> records, List<Map> sales) {
  final ledger = buildBirdsLeftLedger(flocks, records, sales);
  return [
    for (final f in flocks)
      () {
        final id = tIntOrNull(f['flockId']) ?? 0;
        final placed = math.max<num>(0, tNum(f['quantity']));
        final mine = ledger.where((r) => r.flockId == id);
        final mort = mine.where((r) => r.category == 'Mortality').fold<num>(0, (s, r) => s + r.quantity);
        final sold = mine.where((r) => r.category == 'Bird sale').fold<num>(0, (s, r) => s + r.quantity);
        final hasRecords = records.any((r) => tIntOrNull(r['flockId']) == id);
        return FlockBirdsSummary(
          id,
          f['name'] != null ? '${f['name']}' : 'Flock #$id',
          placed,
          mort,
          sold,
          math.max<num>(0, placed - mort - sold),
          hasRecords ? birdsLeftFromLatestRecord(records, id) : null,
        );
      }(),
  ];
}

// ------------------------------------------------------------------ medication

class MedLedgerRow {
  MedLedgerRow({
    required this.key,
    required this.itemId,
    required this.medication,
    required this.unit,
    required this.date,
    required this.type,
    required this.source,
    required this.inQty,
    required this.outQty,
    required this.balance,
    this.cost,
    this.recognized,
    this.reversed,
    this.productionRecordId,
  });
  final String key;
  final int itemId;
  final String medication, unit, date, type, source;
  final num inQty, outQty, balance;
  final num? cost, recognized;
  final bool? reversed;
  final int? productionRecordId;
}

class MedSummary {
  MedSummary(this.id, this.name, this.unit, this.totalIn, this.totalOut, this.left, this.minAlert, this.isActive,
      this.isLow, this.status);
  final int id;
  final String name, unit;
  final num totalIn, totalOut, left, minAlert;
  final bool isActive, isLow;
  final String status; // Inactive | Finished | Low | In stock
}

List<Map> medicationItems(List<Map> items) => [for (final i in items) if (i['category'] == 'Medication') i];

/// The Medication tracker's per-medication ledger: purchases in (raw quantity,
/// as the web does), usage out, a running balance kept per medication.
List<MedLedgerRow> buildMedicationLedger(List<Map> meds, List<Map> purchases, List<Map> usage) {
  final rows = <MedLedgerRow>[];
  for (final m in meds) {
    final id = tIntOrNull(m['poultryRawMaterialItemId']) ?? 0;
    final events = <({String date, String type, String source, num inQty, num outQty, String key, Map? u})>[
      for (final p in purchases)
        if (tIntOrNull(p['poultryRawMaterialItemId']) == id)
          (
            date: tStr(p['purchaseDate']),
            type: 'Purchase',
            source: tStr(p['supplierName']).isNotEmpty ? 'Purchase — ${p['supplierName']}' : 'Purchase',
            inQty: tNum(p['quantity']),
            outQty: 0,
            key: 'p${p['poultryRawMaterialPurchaseId']}',
            u: null,
          ),
      for (final u in usage)
        if (tIntOrNull(u['poultryRawMaterialItemId']) == id)
          (
            date: tStr(u['usedDate']),
            type: 'Usage',
            source: tStr(u['varianceReason']).isNotEmpty
                ? 'Production usage — ${u['varianceReason']}'
                : 'Production usage',
            inQty: 0,
            outQty: tNum(u['quantityUsed']).abs(),
            key: 'u${u['poultryRawMaterialUsageId']}',
            u: u,
          ),
    ];
    // Stable, like Array.prototype.sort on a string compare.
    final indexed = [for (var i = 0; i < events.length; i++) (i, events[i])]
      ..sort((a, b) {
        final r = a.$2.date.compareTo(b.$2.date);
        return r != 0 ? r : a.$1 - b.$1;
      });
    num run = 0;
    for (final (_, e) in indexed) {
      run += e.inQty - e.outQty;
      final u = e.u;
      rows.add(MedLedgerRow(
        key: e.key,
        itemId: id,
        medication: tStr(m['itemName']),
        unit: tStr(m['unitOfMeasure']),
        date: e.date,
        type: e.type,
        source: e.source,
        inQty: e.inQty,
        outQty: e.outQty,
        balance: run,
        cost: u == null || u['operationalCost'] == null ? null : tNum(u['operationalCost']),
        recognized: u == null || u['recognizedCost'] == null ? null : tNum(u['recognizedCost']),
        reversed: u == null || u['isReversed'] == null ? null : tBool(u['isReversed']),
        productionRecordId: u == null ? null : tIntOrNull(u['productionRecordId']),
      ));
    }
  }
  return rows;
}

List<MedSummary> summarizeMedications(List<Map> meds, List<Map> purchases, List<Map> usage) => [
      for (final m in meds)
        () {
          final id = tIntOrNull(m['poultryRawMaterialItemId']) ?? 0;
          final totalIn = purchases
              .where((p) => tIntOrNull(p['poultryRawMaterialItemId']) == id)
              .fold<num>(0, (s, p) => s + tNum(p['quantity']));
          final totalOut = usage
              .where((u) => tIntOrNull(u['poultryRawMaterialItemId']) == id)
              .fold<num>(0, (s, u) => s + tNum(u['quantityUsed']).abs());
          final left = tNum(m['currentQuantity']);
          final min = tNum(m['minimumStockAlert']);
          final active = tBool(m['isActive']);
          final low = m['isLowStock'] != null ? tBool(m['isLowStock']) : left <= min;
          final unit = tStr(m['unitOfMeasure']);
          return MedSummary(id, tStr(m['itemName']), unit.isEmpty ? '—' : unit, totalIn, totalOut, left, min, active,
              low, !active ? 'Inactive' : left <= 0 ? 'Finished' : low ? 'Low' : 'In stock');
        }(),
    ];
