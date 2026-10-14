// Egg Sorting Workspace rules (migrations 341-344), ported from
// lib/production/egg-sorting.ts and the history sentences of
// components/egg-sorting/egg-sorting-audit-list.tsx.
//
//   PRODUCTION CREATES EGGS. SORTING DOES NOT CREATE EGGS — IT RECLASSIFIES
//   EGGS THAT ALREADY EXIST (Unsorted → sizes + losses).

import 'dart:convert';

import '../trackers/egg_class_ledger.dart' show fmtCount;
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;

export '../trackers/egg_class_ledger.dart' show cratesText, fmtCount;

/// NotStarted / Partial / Complete.
const statusLabel = {'NotStarted': 'Not started', 'Partial': 'Partial', 'Complete': 'Complete'};

String statusOf(num sorted, num left) {
  if (left <= 0 && sorted > 0) return 'Complete';
  if (sorted > 0) return 'Partial';
  return left <= 0 ? 'Complete' : 'NotStarted';
}

/// What a pick can still give (LEAST(pick left, record left), from the API).
num pickRemaining(Map p) => tNum(p['available']) < 0 ? 0 : tNum(p['available']);
String pickStatus(Map p) => statusOf(tNum(p['pickSorted']), pickRemaining(p));

/// The losses a sorting can record (not stocked).
const lossTypes = [('Reject', 'Reject'), ('Breakage', 'Breakage'), ('OtherLoss', 'Other loss')];

String lineTypeLabel(Object? t, [Object? sizeName]) {
  if (t == 'SizedOutput') return tStr(sizeName).isEmpty ? 'Size' : tStr(sizeName);
  return lossTypes.where((l) => l.$1 == t).map((l) => l.$2).firstOrNull ?? '${t ?? ''}';
}

/// "1st Pick (9:00 AM)" from the farm's labels, else "Pick n".
String pickLabel(int n, ({String first, String second, String third, String fourth, String fifth, String sixth}) labels) {
  final all = [labels.first, labels.second, labels.third, labels.fourth, labels.fifth, labels.sixth];
  return n >= 1 && n <= 6 ? all[n - 1] : 'Pick $n';
}

/// "1st Pick" without the time.
String pickShort(int n, ({String first, String second, String third, String fourth, String fifth, String sixth}) labels) =>
    pickLabel(n, labels).split(' (').first;

String pct(num part, num whole) => whole == 0 ? '—' : '${(part / whole * 100).toStringAsFixed(1)}%';

/// One production record's day, from its pick rows.
class ProductionDay {
  ProductionDay({
    required this.productionRecordId,
    required this.flockId,
    required this.flockName,
    this.batchName,
    this.houseName,
    required this.productionDate,
    required this.gross,
    required this.collectionLoss,
    required this.saleable,
    required this.sorted,
    required this.left,
    required this.status,
    required this.picks,
    this.soldUnsorted = 0,
  });
  final int productionRecordId, flockId;
  final String flockName;
  final String? batchName, houseName;
  final String productionDate;
  final num gross, collectionLoss, saleable, sorted;
  final num left;
  final String status;
  final List<Map> picks;

  /// Eggs of this day already sold or used straight from Unsorted.
  final num soldUnsorted;
}

/// groupProductionDays: newest day first, then flock name.
List<ProductionDay> groupProductionDays(List<Map> rows) {
  final by = <int, ProductionDay>{};
  for (final r in rows) {
    final id = tIntOrNull(r['productionRecordId']) ?? 0;
    final d = by.putIfAbsent(id, () {
      final fid = tIntOrNull(r['flockId']) ?? 0;
      return ProductionDay(
        productionRecordId: id,
        flockId: fid,
        flockName: tStr(r['flockName']).isEmpty ? 'Flock $fid' : tStr(r['flockName']),
        batchName: tStr(r['batchName']).isEmpty ? null : tStr(r['batchName']),
        houseName: tStr(r['houseName']).isEmpty ? null : tStr(r['houseName']),
        productionDate: tStr(r['productionDate']).length >= 10 ? tStr(r['productionDate']).substring(0, 10) : tStr(r['productionDate']),
        gross: tNum(r['recordGross']),
        collectionLoss: tNum(r['recordCollectionLoss']),
        saleable: tNum(r['recordSaleable']),
        sorted: tNum(r['recordSorted']),
        left: tNum(r['recordLeft']),
        status: statusOf(tNum(r['recordSorted']), tNum(r['recordLeft'])),
        picks: [],
      );
    });
    d.picks.add(r);
  }
  for (final d in by.values) {
    d.picks.sort((a, b) => (tIntOrNull(a['pickNumber']) ?? 0).compareTo(tIntOrNull(b['pickNumber']) ?? 0));
  }
  final out = by.values.toList()
    ..sort((a, b) => a.productionDate == b.productionDate ? a.flockName.compareTo(b.flockName) : b.productionDate.compareTo(a.productionDate));
  return out;
}

/// sortableByRecord: what each open record can REALLY still be sorted into once
/// eggs sold or used straight from Unsorted are taken off — from the OLDEST
/// days first (date, then record).
Map<int, num> sortableByRecord(List<ProductionDay> openDays, num unsortedOnHand) {
  final open = openDays.where((d) => d.left > 0).toList()
    ..sort((a, b) {
      final c = a.productionDate.compareTo(b.productionDate);
      return c != 0 ? c : a.productionRecordId.compareTo(b.productionRecordId);
    });
  final totalLeft = open.fold<num>(0, (s, d) => s + d.left);
  final onHand = unsortedOnHand.truncate() < 0 ? 0 : unsortedOnHand.truncate();
  var gone = totalLeft - onHand < 0 ? 0 : totalLeft - onHand;
  final out = <int, num>{};
  for (final d in open) {
    final take = gone < d.left ? gone : d.left;
    gone -= take;
    out[d.productionRecordId] = d.left - take;
  }
  return out;
}

/// capToSortable: the day as it can actually be sorted — `left` and each
/// pick's `available` cut to `sortable` (earliest pick first).
ProductionDay capToSortable(ProductionDay day, num? sortable) {
  if (sortable == null || sortable >= day.left) return day;
  var sold = day.left - (sortable < 0 ? 0 : sortable);
  final picks = [
    for (final p in day.picks)
      () {
        final avail = tNum(p['available']) < 0 ? 0 : tNum(p['available']);
        final take = sold < avail ? sold : avail;
        sold -= take;
        return take > 0 ? {...p, 'available': tNum(p['available']) - take} : p;
      }(),
  ];
  final left = sortable < 0 ? 0 : sortable;
  return ProductionDay(
    productionRecordId: day.productionRecordId,
    flockId: day.flockId,
    flockName: day.flockName,
    batchName: day.batchName,
    houseName: day.houseName,
    productionDate: day.productionDate,
    gross: day.gross,
    collectionLoss: day.collectionLoss,
    saleable: day.saleable,
    sorted: day.sorted,
    left: left,
    status: statusOf(day.sorted, left),
    picks: picks,
    soldUnsorted: day.left - left,
  );
}

/// Whole, positive eggs, or null.
int? parseEggs(String text) {
  final t = text.trim();
  if (t.isEmpty) return null;
  final n = int.tryParse(t);
  return n != null && n > 0 ? n : null;
}

class SortingLine {
  const SortingLine({required this.key, required this.lineType, this.eggSizeId, required this.text});
  final String key;
  final String lineType; // SizedOutput | Reject | Breakage | OtherLoss
  final int? eggSizeId;
  final String text;
}

class SortingBalance {
  const SortingBalance(this.available, this.sized, this.loss, this.invalidLines);
  final num available;
  final int sized, loss, invalidLines;

  /// sized + loss: what this sorting takes out of Unsorted.
  int get input => sized + loss;

  /// still unsorted after posting (negative = too many).
  num get remainingAfter => available - input;
}

SortingBalance sortingBalance(num available, List<SortingLine> lines) {
  var sized = 0, loss = 0, invalid = 0;
  for (final l in lines) {
    if (l.text.trim().isEmpty) continue;
    final n = parseEggs(l.text);
    if (n == null) {
      invalid++;
      continue;
    }
    if (l.lineType == 'SizedOutput') {
      sized += n;
    } else {
      loss += n;
    }
  }
  return SortingBalance(available, sized, loss, invalid);
}

/// The reason Post is disabled, or null.
String? sortingBlocker(SortingBalance b) {
  if (b.invalidLines > 0) return 'Quantities must be whole numbers of eggs.';
  if (b.input <= 0) return 'Enter how the eggs graded.';
  if (b.remainingAfter < 0) return 'That is ${fmtCount(-b.remainingAfter)} more than are left to sort.';
  return null;
}

List<Map<String, dynamic>> toApiLines(List<SortingLine> lines) => [
      for (final l in lines)
        if (parseEggs(l.text) != null)
          {
            'lineType': l.lineType,
            'eggSizeId': l.lineType == 'SizedOutput' ? l.eggSizeId : null,
            'quantity': parseEggs(l.text),
            'notes': null,
          },
    ];

/// The Daily Closing rule, when the day's eggs are not all sorted.
const closingPolicyText = {
  'Off': 'Say nothing about unsorted eggs',
  'Warning': 'Warn, but allow closing (recommended — many farms sort the next morning)',
  'Blocking': "Block closing until the day's eggs are sorted",
};

/// A size price as typed: null = not set; 'bad' = not a price.
Object? parsePrice(String t) {
  if (t.trim().isEmpty) return null;
  final n = num.tryParse(t.trim());
  return n != null && n >= 0 ? (n * 100).round() / 100 : 'bad';
}

String priceText(Object? n) => n == null ? '' : (tNum(n) == tNum(n).roundToDouble() ? tNum(n).toInt().toString() : '${tNum(n)}');

// ------------------------------------------------------------------ audit

const auditActionLabel = {
  'DraftCreated': 'Sorting draft created',
  'DraftEdited': 'Sorting draft edited',
  'DraftDiscarded': 'Sorting draft discarded',
  'Posted': 'Sorting posted',
  'Reversed': 'Sorting reversed',
  'SizeAdded': 'Egg size added',
  'SizeChanged': 'Egg size changed',
  'SettingsChanged': 'Sorting settings changed',
  'SaleEggClassSet': 'Sale egg class set',
  'EggClassAdjusted': 'Egg stock adjusted',
};

Map _parse(Object? d) {
  try {
    final v = d == null ? null : jsonDecode('$d');
    return v is Map ? v : const {};
  } catch (_) {
    return const {};
  }
}

String _js(Object? v) => v == null ? 'null' : '$v';

/// describeAudit: one plain sentence per entry, from its details.
String describeAudit(Map a) {
  final d = _parse(a['details']);
  switch (a['action']) {
    case 'Posted' || 'Reversed' || 'DraftCreated' || 'DraftEdited' || 'DraftDiscarded':
      final base = '${d['sessionNo'] ?? '#${a['entityId']}'}: ${fmtCount(tNum(d['input']))} eggs'
          '${d['sized'] != null ? ' (${fmtCount(tNum(d['sized']))} into sizes, ${fmtCount(tNum(d['loss']))} lost)' : ''}';
      final lines = d['lines'] is List
          ? ' — ${(d['lines'] as List).map((l) => '${l is Map ? (l['size'] ?? l['type']) : ''} ${fmtCount(tNum(l is Map ? l['qty'] : 0))}').join(', ')}'
          : '';
      final from = d['sources'] is List
          ? '; from ${(d['sources'] as List).map((s) => s is Map ? '${s['productionDate']} pick ${s['pick']} (${fmtCount(tNum(s['qty']))})' : '').join(', ')}'
          : '';
      final why = tStr(d['reason']).isNotEmpty ? '; reason: ${d['reason']}' : '';
      return base + lines + from + why;
    case 'SizeAdded':
      return '${d['name']}${d['price'] != null ? ' at ${d['price']} per crate' : ''}';
    case 'SizeChanged':
      final parts = <String>[
        if (d['name'] is List) 'renamed ${(d['name'] as List)[0]} → ${(d['name'] as List)[1]}',
        if (d['pricePerCrate'] is List)
          'price ${(d['pricePerCrate'] as List)[0] ?? 'none'} → ${(d['pricePerCrate'] as List)[1] ?? 'none'}',
        if (d['active'] is List) (d['active'] as List)[1] == true ? 'switched on' : 'switched off',
        if (d['order'] is List) 'reordered',
      ];
      return '${d['name'] is String ? d['name'] : ''} ${parts.join(', ')}'.trim();
    case 'SettingsChanged':
      return 'sorting ${d['enableEggSorting'] == true ? 'on' : 'off'}, Daily Closing ${_js(d['closingPolicy'])}, ${_js(d['eggsPerCrate'])} eggs per crate'
          '${d['unsortedPricePerCrate'] != null ? ', unsorted ${d['unsortedPricePerCrate']} per crate' : ''}';
    case 'SaleEggClassSet':
      return 'Sale #${a['entityId']}: ${_js(d['from'])} → ${_js(d['to'])}, ${fmtCount(tNum(d['quantity']))} eggs'
          '${tStr(d['customer']).isNotEmpty ? ' (${d['customer']})' : ''}${tStr(d['saleGroupNo']).isNotEmpty ? ', ${d['saleGroupNo']}' : ''}';
    case 'EggClassAdjusted':
      return '${_js(d['class'])}: ${_js(d['kind'])} ${tNum(d['quantity']) > 0 ? '+' : ''}${fmtCount(tNum(d['quantity']))} '
          '(${fmtCount(tNum(d['onHandBefore']))} → ${fmtCount(tNum(d['onHandAfter']))}); ${tStr(d['reason'])}';
    default:
      return tStr(a['details']);
  }
}

/// Size composition groupings.
const compositionGroups = [
  ('productiondate', 'Production date'),
  ('sortingdate', 'Sorting date'),
  ('flock', 'Flock'),
  ('batch', 'Batch'),
  ('age', 'Flock age (weeks)'),
  ('pick', 'Pick'),
];
