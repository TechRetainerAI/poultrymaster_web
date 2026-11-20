// Batch Bird Reconciliation and existing-flock history (migration 413), as the
// web's lib/flocks/bird-reconciliation.ts and lib/api/bird-reconciliation.ts.
// The server recomputes and enforces every figure; these only let a form show
// the same numbers before it is saved. Money is worked in whole pesewas
// (integers) so 2,000 × 45.10 is exact.

import 'dart:math' as math;

import '../../models/company.dart';
import '../../state/session.dart';
import '../shared/business_dates.dart' show fmtNum;

enum ReconciliationKind { sale, mortality, cull, transferOut, stockCorrection, other }

/// The API's spelling of each kind.
const reconciliationKindNames = {
  ReconciliationKind.sale: 'Sale',
  ReconciliationKind.mortality: 'Mortality',
  ReconciliationKind.cull: 'Cull',
  ReconciliationKind.transferOut: 'TransferOut',
  ReconciliationKind.stockCorrection: 'StockCorrection',
  ReconciliationKind.other: 'Other',
};

/// KIND_LABELS.
const reconciliationKindLabels = {
  ReconciliationKind.sale: 'Previously sold',
  ReconciliationKind.mortality: 'Historical mortality',
  ReconciliationKind.cull: 'Culled / removed',
  ReconciliationKind.transferOut: 'Transferred outside the batch',
  ReconciliationKind.stockCorrection: 'Historical stock correction',
  ReconciliationKind.other: 'Other documented reason',
};

/// One line as the API takes it.
class ReconciliationLine {
  ReconciliationLine({
    required this.kind,
    this.quantity = 0,
    this.date,
    this.note,
    this.increase = false,
    this.flockId,
    this.pricePerBird,
    this.valueUnknown = false,
    this.customerId,
    this.amountReceived,
    this.createReceivable = false,
    this.reference,
  });
  ReconciliationKind kind;
  num quantity;
  String? date;
  String? note;

  /// StockCorrection only: "More birds than recorded".
  bool increase;

  // ---- Sale only
  /// Set = sold from this flock after placing: values the flock's opening
  /// "sold", moves no bird.
  int? flockId;
  num? pricePerBird;
  bool valueUnknown;
  int? customerId;
  num? amountReceived;
  bool createReceivable;
  String? reference;

  Map<String, dynamic> toJson() => {
        'kind': reconciliationKindNames[kind],
        'quantity': quantity.truncate(),
        'date': date,
        'note': note,
        if (kind == ReconciliationKind.stockCorrection) 'direction': increase ? 'Increase' : 'Decrease',
        if (kind == ReconciliationKind.sale) ...{
          'flockId': flockId,
          'pricePerBird': valueUnknown ? null : (pricePerBird ?? 0),
          'valueUnknown': valueUnknown,
          'customerId': customerId,
          'amountReceived': valueUnknown ? null : (amountReceived ?? saleValue(this).total),
          'createReceivable': createReceivable,
          'reference': reference,
        },
      };
}

int _int(Object? v) => v is num ? v.truncate() : (num.tryParse('${v ?? ''}')?.truncate() ?? 0);
int _pesewas(Object? v) => v is num ? (v * 100).round() : ((num.tryParse('${v ?? ''}') ?? 0) * 100).round();

/// Birds this line takes out of the batch's never-placed pool (negative = adds back).
int lineRemoves(ReconciliationLine line) {
  if (line.kind == ReconciliationKind.sale && (line.flockId ?? 0) != 0) return 0; // valued from a flock, no bird moves
  final q = math.max(0, _int(line.quantity));
  return line.kind == ReconciliationKind.stockCorrection && line.increase ? -q : q;
}

class SaleValue {
  const SaleValue(this.total, this.received, this.owed, this.treatment, this.problem);

  /// Null when the value is unknown.
  final num? total;
  final num received;
  final num owed;

  /// QuantityOnly | HistoricalPaid | HistoricalReceivable | HistoricalUnpaidNotTracked
  final String treatment;
  final String? problem;
}

/// Mirrors sppoultrybatchreconcile_post's rules for a sale line.
SaleValue saleValue(ReconciliationLine line) {
  if (line.valueUnknown) return const SaleValue(null, 0, 0, 'QuantityOnly', null);
  final q = math.max(0, _int(line.quantity));
  final price = line.pricePerBird;
  if (price == null || price < 0) {
    return const SaleValue(null, 0, 0, 'QuantityOnly', 'Enter the selling price per bird, or tick “value unknown”.');
  }
  final totalP = q * _pesewas(price);
  final receivedP = line.amountReceived == null ? totalP : _pesewas(line.amountReceived);
  if (receivedP < 0 || receivedP > totalP) {
    return SaleValue(totalP / 100, receivedP / 100, 0, 'HistoricalPaid', 'Amount received must be between 0 and the sale value.');
  }
  final owedP = totalP - receivedP;
  final treatment = owedP == 0 ? 'HistoricalPaid' : (line.createReceivable ? 'HistoricalReceivable' : 'HistoricalUnpaidNotTracked');
  final problem = treatment == 'HistoricalReceivable' && line.customerId == null ? 'Choose the customer who still owes the balance.' : null;
  return SaleValue(totalP / 100, receivedP / 100, owedP / 100, treatment, problem);
}

class BatchReconciliationPreview {
  const BatchReconciliationPreview({
    required this.poolBefore,
    required this.removed,
    required this.poolAfter,
    required this.stillAlive,
    required this.unexplained,
    required this.saleBirds,
    required this.saleValue,
    required this.received,
    required this.owed,
    required this.receivablesToCreate,
    required this.problems,
    required this.status,
  });

  /// Birds not in any flock right now (server figure).
  final int poolBefore;
  final int removed;
  final int poolAfter;
  final int stillAlive;

  /// poolAfter − stillAlive. Positive = still to explain; negative = over-explained.
  final int unexplained;
  final int saleBirds;
  final num saleValue;
  final num received;
  final num owed;
  final int receivablesToCreate;
  final List<String> problems;

  /// Reconciled only when nothing is left unexplained and nothing is wrong.
  final String status;
}

BatchReconciliationPreview previewBatchReconciliation(int poolBefore, List<ReconciliationLine> lines, num stillAlive) {
  final problems = <String>[];
  var removed = 0, saleBirds = 0, valueP = 0, receivedP = 0, owedP = 0, receivables = 0;
  for (final (i, l) in lines.indexed) {
    final q = _int(l.quantity);
    if (q < 0) problems.add('Line ${i + 1}: birds cannot be negative.');
    if (q == 0) continue;
    removed += lineRemoves(l);
    if (l.kind == ReconciliationKind.other && (l.note ?? '').trim().isEmpty) {
      problems.add('Line ${i + 1}: “Other” needs a note saying what happened.');
    }
    if (l.kind == ReconciliationKind.sale) {
      saleBirds += math.max(0, q);
      final v = saleValue(l);
      if (v.problem != null) problems.add('Line ${i + 1}: ${v.problem}');
      valueP += ((v.total ?? 0) * 100).round();
      receivedP += (v.received * 100).round();
      owedP += (v.owed * 100).round();
      if (v.treatment == 'HistoricalReceivable') receivables++;
    }
  }
  final alive = math.max(0, _int(stillAlive));
  final poolAfter = poolBefore - removed;
  if (poolAfter < 0) {
    problems.add('These lines take out ${fmtNum(removed, 0)} birds but only ${fmtNum(poolBefore, 0)} are not in a flock.');
  }
  if (alive > math.max(poolAfter, 0)) {
    problems.add('Only ${fmtNum(math.max(poolAfter, 0), 0)} birds are left out of a flock, so ${fmtNum(alive, 0)} cannot still be alive there.');
  }
  final unexplained = poolAfter - alive;
  return BatchReconciliationPreview(
    poolBefore: poolBefore,
    removed: removed,
    poolAfter: poolAfter,
    stillAlive: alive,
    unexplained: unexplained,
    saleBirds: saleBirds,
    saleValue: valueP / 100,
    received: receivedP / 100,
    owed: owedP / 100,
    receivablesToCreate: receivables,
    problems: problems,
    status: problems.isNotEmpty ? 'Invalid' : unexplained == 0 ? 'Reconciled' : 'Unexplained',
  );
}

// ---- Existing flock ---------------------------------------------------------

class FlockHistoryPreview {
  const FlockHistoryPreview(this.placed, this.live, this.difference, this.stated, this.other, this.problem);
  final int placed;
  final int live;
  final int difference;
  final int stated;

  /// Recorded as "other / unknown", never as mortality.
  final int other;
  final String? problem;
}

/// Same rule as ExistingFlockHistory.Breakdown / FarmSetupValidator.Breakdown.
FlockHistoryPreview previewFlockHistory({
  required Object? originallyPlaced,
  required Object? currentLiveBirds,
  required bool historyKnown,
  Object? mortality,
  Object? sold,
  Object? culled,
  Object? transferred,
}) {
  final placed = _int(originallyPlaced);
  final live = _int(currentLiveBirds);
  final difference = math.max(0, placed - live);
  final parts = [mortality, sold, culled, transferred].map(_int).toList();
  final stated = historyKnown ? parts.fold<int>(0, (a, b) => a + b) : 0;
  String? problem;
  if (placed <= 0) {
    problem = 'Enter how many birds were originally placed.';
  } else if (live < 0) {
    problem = 'Birds remaining cannot be negative.';
  } else if (live > placed) {
    problem = 'Birds remaining are more than were placed. Record the extra birds as a transfer in or a correction instead.';
  } else if (parts.any((p) => p < 0)) {
    problem = 'Historical figures cannot be negative.';
  } else if (stated > difference) {
    problem = 'The reasons add up to ${fmtNum(stated, 0)} but only ${fmtNum(difference, 0)} birds are gone.';
  }
  return FlockHistoryPreview(placed, live, difference, stated, math.max(0, difference - stated), problem);
}

final _rnd = math.Random();

/// A fresh idempotency key for one submission (a retry reuses it).
String newRequestKey(String prefix) =>
    '$prefix:${DateTime.now().microsecondsSinceEpoch}-${_rnd.nextInt(1 << 31).toRadixString(36)}';

// ---- API ---------------------------------------------------------------------

/// The server's bird accounting per batch, keyed by batch id: the one figure
/// every page agrees on. Empty before migration 413 (callers fall back).
Future<Map<int, Map>> loadBatchReconciliation(Session s, Company c) async {
  try {
    final res = await s.farmClient.get('/api/Poultry/bird-reconciliation/batches', query: {'farmId': c.farmId});
    final rows = res is List ? res : const [];
    return {for (final r in rows) if (r is Map) _int(r['batchId']): r};
  } catch (_) {
    return const {};
  }
}

/// Birds sold from the batch: before placement (batchSold) + out of its flocks.
int batchSoldOf(Map? row) => row == null ? 0 : _int(row['batchSold']) + _int(row['flockSold']);

/// The batch has birds the records do not explain.
bool batchNeedsReconcile(Map? row) => row != null && '${row['status']}' != 'FullyAccountedFor';
