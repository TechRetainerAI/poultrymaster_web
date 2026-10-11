// Batch production helpers: lib/api/production-batch.ts (status labels, the
// name and scope labels), lib/utils/batch-allocation.ts (the allocation grid,
// the four pre-fill methods and the reconciliation) and the missing-production
// prefill from lib/activity/completeness.ts.

import 'dart:math' as math;

import '../../shared/business_dates.dart';
import '../reports/dashboard_screen.dart' show latestRecordForFlock, birdsLeftFromRecord;
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;

const batchStatuses = ['Draft', 'PendingAllocation', 'Allocated', 'Posted', 'Reversed', 'Cancelled'];

const batchStatusLabels = {
  'Draft': 'Draft',
  'PendingAllocation': 'Pending Allocation',
  'Allocated': 'Allocated',
  'Posted': 'Posted',
  'Reversed': 'Reversed',
  'Cancelled': 'Cancelled',
};

String batchStatusLabel(Object? s) => batchStatusLabels[tStr(s)] ?? tStr(s);

String batchNameLabel(Map r) {
  final name = tStr(r['batchName']).trim();
  if (name.isNotEmpty) return name;
  final t = tStr(r['batchSelectionType']);
  if (t == 'AllBatches') return 'All Batches';
  if (t == 'CustomBatch') return 'Custom Batch';
  return 'Batch';
}

/// The secondary line under the batch name: the included flocks.
String batchScopeLabel(Map r) {
  if (tStr(r['batchSelectionType']) == 'AllBatches') return 'All active flocks';
  final names = [
    for (final f in (r['includedFlocks'] as List? ?? const []))
      if (f is Map) tStr(f['flockName']).isNotEmpty ? tStr(f['flockName']) : 'Flock ${tStr(f['flockId'])}',
  ];
  if (names.isEmpty) return '—';
  if (names.length <= 4) return names.join(', ');
  return '${names.take(4).join(', ')} +${names.length - 4} more';
}

/// The Batch filter's key: the bird-batch id, else scope type + name.
String batchFilterKey(Map r) => r['selectedBirdBatchId'] != null
    ? 'b:${tStr(r['selectedBirdBatchId'])}'
    : 't:${tStr(r['batchSelectionType'])}:${tStr(r['batchName']).trim().toLowerCase()}';

List<Map> listOf(Map r, String k) => [for (final x in (r[k] as List? ?? const [])) if (x is Map) x];

// ------------------------------------------------------------ prefill

class MissingProductionPrefill {
  const MissingProductionPrefill(this.date, this.flockIds);
  final String date;
  final List<int> flockIds;
}

const maxPrefillFlocks = 500;

/// parseMissingProductionPrefill: no valid date means no prefill at all.
MissingProductionPrefill? parseMissingProductionPrefill(Map<String, String> q) {
  final date = toBusinessDate(q['date']);
  final seen = <int>{};
  final ids = <int>[];
  for (final part in (q['flockIds'] ?? '').split(',')) {
    final t = part.trim();
    if (!RegExp(r'^\d+$').hasMatch(t)) continue;
    final n = int.tryParse(t);
    if (n == null || n <= 0 || seen.contains(n)) continue;
    seen.add(n);
    ids.add(n);
    if (ids.length >= maxPrefillFlocks) break;
  }
  if (date == null) return null;
  return MissingProductionPrefill(date, ids);
}

String? safeReturnPath(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final v = raw.trim();
  if (!v.startsWith('/') || v.startsWith('//') || v.startsWith(r'/\') || v.contains(r'\')) return null;
  if (RegExp(r'[\u0000-\u001f]').hasMatch(v)) return null;
  return v;
}

String farmCompletenessHref(String? businessDate) {
  final d = toBusinessDate(businessDate);
  return d != null ? '/poultry-farm-completeness?date=$d' : '/poultry-farm-completeness';
}

// ------------------------------------------------------------ allocation

class AllocRow {
  AllocRow({
    required this.flockId,
    required this.flockName,
    this.ageInWeeks,
    this.ageInDays,
    this.birdsBefore = 0,
    this.deaths = 0,
    this.p1 = 0,
    this.p2 = 0,
    this.p3 = 0,
    this.p4 = 0,
    this.p5 = 0,
    this.p6 = 0,
    this.broken = 0,
    this.meaty = 0,
    this.soft = 0,
    this.lost = 0,
    Map<int, num>? feedQty,
    Map<int, num>? medQty,
    this.notes = '',
  })  : feedQty = feedQty ?? {},
        medQty = medQty ?? {};
  final int flockId;
  final String flockName;
  final int? ageInWeeks, ageInDays;
  num birdsBefore;
  int deaths, p1, p2, p3, p4, p5, p6, broken, meaty, soft, lost;
  Map<int, num> feedQty, medQty;
  String notes;
}

const allocMethods = [
  ('Manual', 'Manual Allocation', 'Enter exact numbers per flock. The grid opens blank for you to fill in.'),
  ('ByBirdCount', 'By Bird Count', "Distribute totals in proportion to each flock's birds left."),
  ('ByPreviousProduction', 'By Previous Production %', 'Distribute by recent laying performance (last 7 records). Falls back to bird count.'),
  ('EqualSplit', 'Equal Split', 'Split every total evenly across the included flocks.'),
];

/// Largest-remainder split of an integer total by weight.
List<int> distributeInteger(num total, List<num> weights) {
  final n = weights.length;
  if (n == 0) return [];
  final t = (total).round();
  final sumW = weights.fold<num>(0, (a, b) => a + (b > 0 ? b : 0));
  if (t <= 0 || sumW <= 0) return List.filled(n, 0);
  final raw = [for (final w in weights) t * (w > 0 ? w : 0) / sumW];
  final floors = [for (final x in raw) x.floor()];
  var remainder = t - floors.fold<int>(0, (a, b) => a + b);
  final order = [for (var i = 0; i < n; i++) (i: i, frac: raw[i] - raw[i].floor())]..sort((a, b) => b.frac.compareTo(a.frac));
  final result = [...floors];
  for (var k = 0; k < order.length && remainder > 0; k++) {
    result[order[k].i] += 1;
    remainder -= 1;
  }
  return result;
}

List<num> distributeDecimal(num total, List<num> weights, [int dp = 3]) {
  if (weights.isEmpty) return [];
  final factor = math.pow(10, dp);
  return [for (final x in distributeInteger((total * factor).round(), weights)) x / factor];
}

({int weeks, int days})? ageFromStartDate(Object? startDate, [DateTime? asOf]) {
  final s = tStr(startDate);
  if (s.isEmpty) return null;
  var start = DateTime.tryParse(s);
  if (start == null) return null;
  // new Date("yyyy-MM-dd") is UTC midnight.
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) start = DateTime.utc(start.year, start.month, start.day);
  final diff = (asOf ?? DateTime.now()).difference(start).inMilliseconds / 86400000;
  final days = math.max(0, diff.floor());
  return (weeks: days ~/ 7, days: days);
}

num birdsForFlock(Map flock, List<Map> records) {
  final latest = latestRecordForFlock(records, tIntOrNull(flock['flockId']) ?? -1);
  if (latest != null) return birdsLeftFromRecord(latest);
  return math.max(0, tNum(flock['quantity']));
}

num recentProductionAvg(List<Map> records, int flockId, [int n = 7]) {
  final rows = [for (final r in records) if (tIntOrNull(r['flockId'] ?? r['FlockId']) == flockId) r]
    ..sort((a, b) => (DateTime.tryParse(tStr(b['date'])) ?? DateTime(0)).compareTo(DateTime.tryParse(tStr(a['date'])) ?? DateTime(0)));
  final take = rows.take(n).toList();
  if (take.isEmpty) return 0;
  return take.fold<num>(0, (a, r) => a + tNum(r['totalProduction'] ?? r['TotalProduction'])) / take.length;
}

List<int> _ids(Map batch, String k) => [for (final f in listOf(batch, k)) tIntOrNull(f['itemId']) ?? 0];

List<AllocRow> buildBlankRows(Map batch, Map<int, Map> flocksById, List<Map> records) {
  final feedIds = _ids(batch, 'feeds'), medIds = _ids(batch, 'medications');
  return [
    for (final incl in listOf(batch, 'includedFlocks'))
      () {
        final id = tIntOrNull(incl['flockId']) ?? 0;
        final flock = flocksById[id];
        final age = flock != null ? ageFromStartDate(flock['startDate']) : null;
        return AllocRow(
          flockId: id,
          flockName: tStr(incl['flockName']).isNotEmpty ? tStr(incl['flockName']) : (tStr(flock?['name']).isNotEmpty ? tStr(flock?['name']) : 'Flock $id'),
          ageInWeeks: age?.weeks,
          ageInDays: age?.days,
          birdsBefore: flock != null ? birdsForFlock(flock, records) : 0,
          feedQty: {for (final i in feedIds) i: 0},
          medQty: {for (final i in medIds) i: 0},
        );
      }(),
  ];
}

/// allocationsToRows: a saved allocation, back into the grid.
List<AllocRow> allocationsToRows(Map batch) {
  final feedIds = _ids(batch, 'feeds'), medIds = _ids(batch, 'medications');
  num qty(List<Map> lines, int id) => tNum(lines.where((l) => tIntOrNull(l['itemId']) == id).firstOrNull?['qty']);
  return [
    for (final a in listOf(batch, 'allocations'))
      AllocRow(
        flockId: tIntOrNull(a['flockId']) ?? 0,
        flockName: tStr(a['flockName']).isNotEmpty ? tStr(a['flockName']) : 'Flock ${tStr(a['flockId'])}',
        ageInWeeks: tIntOrNull(a['ageInWeeks']),
        ageInDays: tIntOrNull(a['ageInDays']),
        birdsBefore: tNum(a['birdsBefore']),
        deaths: tNum(a['deaths']).toInt(),
        p1: tNum(a['firstPickEggs']).toInt(),
        p2: tNum(a['secondPickEggs']).toInt(),
        p3: tNum(a['thirdPickEggs']).toInt(),
        p4: tNum(a['fourthPickEggs']).toInt(),
        p5: tNum(a['fifthPickEggs']).toInt(),
        p6: tNum(a['sixthPickEggs']).toInt(),
        broken: tNum(a['brokenEggs']).toInt(),
        meaty: tNum(a['meatyEggs']).toInt(),
        soft: tNum(a['softEggs']).toInt(),
        lost: tNum(a['lostEggs']).toInt(),
        feedQty: {for (final i in feedIds) i: qty(listOf(a, 'feeds'), i)},
        medQty: {for (final i in medIds) i: qty(listOf(a, 'medications'), i)},
        notes: tStr(a['notes']),
      ),
  ];
}

List<num> weightsForMethod(String method, List<AllocRow> rows, List<Map> records) {
  if (method == 'EqualSplit') return [for (final _ in rows) 1];
  if (method == 'ByBirdCount') return [for (final r in rows) r.birdsBefore];
  if (method == 'ByPreviousProduction') {
    final w = [for (final r in rows) recentProductionAvg(records, r.flockId)];
    if (w.fold<num>(0, (a, b) => a + b) <= 0) return [for (final r in rows) r.birdsBefore];
    return w;
  }
  return [for (final _ in rows) 0];
}

List<AllocRow> applyMethod(String method, List<AllocRow> rows, Map batch, List<Map> records) {
  AllocRow copy(AllocRow r, {required List<int> v, required Map<int, num> feed, required Map<int, num> med}) => AllocRow(
        flockId: r.flockId,
        flockName: r.flockName,
        ageInWeeks: r.ageInWeeks,
        ageInDays: r.ageInDays,
        birdsBefore: r.birdsBefore,
        deaths: v[0],
        p1: v[1],
        p2: v[2],
        p3: v[3],
        p4: v[4],
        p5: v[5],
        p6: v[6],
        broken: v[7],
        meaty: v[8],
        soft: v[9],
        lost: v[10],
        feedQty: feed,
        medQty: med,
        notes: r.notes,
      );
  if (method == 'Manual') {
    return [
      for (final r in rows)
        copy(r, v: List.filled(11, 0), feed: {for (final k in r.feedQty.keys) k: 0}, med: {for (final k in r.medQty.keys) k: 0}),
    ];
  }
  final w = weightsForMethod(method, rows, records);
  List<int> d(String k) => distributeInteger(tNum(batch[k]), w);
  final cols = [
    d('deaths'), d('firstPickTotal'), d('secondPickTotal'), d('thirdPickTotal'), d('fourthPickTotal'), d('fifthPickTotal'),
    d('sixthPickTotal'), d('brokenEggs'), d('meatyEggs'), d('softEggs'), d('lostEggs'),
  ];
  final feeds = listOf(batch, 'feeds'), meds = listOf(batch, 'medications');
  final feedDist = {for (final f in feeds) tIntOrNull(f['itemId']) ?? 0: distributeDecimal(tNum(f['qty']), w)};
  final medDist = {for (final m in meds) tIntOrNull(m['itemId']) ?? 0: distributeDecimal(tNum(m['qty']), w)};
  return [
    for (var i = 0; i < rows.length; i++)
      copy(
        rows[i],
        v: [for (final c in cols) c[i]],
        feed: {for (final e in feedDist.entries) e.key: e.value[i]},
        med: {for (final e in medDist.entries) e.key: e.value[i]},
      ),
  ];
}

int rowTotalEggs(AllocRow r) => r.p1 + r.p2 + r.p3 + r.p4 + r.p5 + r.p6;
num rowBirdsAfter(AllocRow r) => math.max(0, r.birdsBefore - r.deaths);
num rowEggPct(AllocRow r) => r.birdsBefore > 0 ? rowTotalEggs(r) / r.birdsBefore * 100 : 0;
num rowFeedCost(AllocRow r, Map batch) =>
    listOf(batch, 'feeds').fold<num>(0, (s, f) => s + (r.feedQty[tIntOrNull(f['itemId'])] ?? 0) * tNum(f['unitCost']));
num rowMedCost(AllocRow r, Map batch) =>
    listOf(batch, 'medications').fold<num>(0, (s, m) => s + (r.medQty[tIntOrNull(m['itemId'])] ?? 0) * tNum(m['unitCost']));

class ReconLine {
  const ReconLine(this.key, this.label, this.batchTotal, this.allocated, this.balanced, {this.money = false, this.decimals});
  final String key, label;
  final num batchTotal, allocated;
  final bool balanced, money;
  final int? decimals;
  num get diff => allocated - batchTotal;
}

({List<ReconLine> lines, bool balanced}) buildReconciliation(List<AllocRow> rows, Map batch) {
  num sum(num Function(AllocRow) fn) => rows.fold<num>(0, (s, r) => s + fn(r));
  final lines = <ReconLine>[];
  void intLine(String key, String label, num batchTotal, num allocated) =>
      lines.add(ReconLine(key, label, batchTotal, allocated, (allocated - batchTotal).abs() <= 0));
  void qtyLine(String key, String label, num batchTotal, num allocated) =>
      lines.add(ReconLine(key, label, batchTotal, allocated, (allocated - batchTotal).abs() <= 0.001, decimals: 3));
  void moneyLine(String key, String label, num batchTotal, num allocated) =>
      lines.add(ReconLine(key, label, batchTotal, allocated, (allocated - batchTotal).abs() <= 0.01, money: true));
  intLine('p1', '1st Pick', tNum(batch['firstPickTotal']), sum((r) => r.p1));
  intLine('p2', '2nd Pick', tNum(batch['secondPickTotal']), sum((r) => r.p2));
  intLine('p3', '3rd Pick', tNum(batch['thirdPickTotal']), sum((r) => r.p3));
  intLine('p4', '4th Pick', tNum(batch['fourthPickTotal']), sum((r) => r.p4));
  intLine('p5', '5th Pick', tNum(batch['fifthPickTotal']), sum((r) => r.p5));
  intLine('p6', '6th Pick', tNum(batch['sixthPickTotal']), sum((r) => r.p6));
  intLine('broken', 'Broken', tNum(batch['brokenEggs']), sum((r) => r.broken));
  intLine('meaty', 'Meaty', tNum(batch['meatyEggs']), sum((r) => r.meaty));
  intLine('soft', 'Soft', tNum(batch['softEggs']), sum((r) => r.soft));
  intLine('lost', 'Lost', tNum(batch['lostEggs']), sum((r) => r.lost));
  intLine('total', 'Total Eggs', tNum(batch['totalEggs']), sum(rowTotalEggs));
  intLine('deaths', 'Deaths', tNum(batch['deaths']), sum((r) => r.deaths));
  for (final f in listOf(batch, 'feeds')) {
    final id = tIntOrNull(f['itemId']);
    qtyLine('feed-$id', '${tStr(f['itemName']).isNotEmpty ? tStr(f['itemName']) : 'Feed'} (feed)', tNum(f['qty']), sum((r) => r.feedQty[id] ?? 0));
  }
  for (final m in listOf(batch, 'medications')) {
    final id = tIntOrNull(m['itemId']);
    qtyLine('med-$id', '${tStr(m['itemName']).isNotEmpty ? tStr(m['itemName']) : 'Medication'} (med)', tNum(m['qty']), sum((r) => r.medQty[id] ?? 0));
  }
  moneyLine('feedCost', 'Total Feed Cost', tNum(batch['totalFeedCost']), sum((r) => rowFeedCost(r, batch)));
  moneyLine('medCost', 'Total Medication Cost', tNum(batch['totalMedicationCost']), sum((r) => rowMedCost(r, batch)));
  moneyLine('prodCost', 'Total Cost of Production', tNum(batch['totalCostOfProduction']), sum((r) => rowFeedCost(r, batch) + rowMedCost(r, batch)));
  return (lines: lines, balanced: lines.where((l) => !l.money).every((l) => l.balanced));
}

/// The web's fmtRecon.
String fmtRecon(ReconLine l, num v) => l.money ? v.toStringAsFixed(2) : (l.decimals != null ? v.toStringAsFixed(l.decimals!) : '${v.round()}');
