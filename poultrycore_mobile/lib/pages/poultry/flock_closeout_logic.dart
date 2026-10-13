// Flock closeout — the wizard's arithmetic, as `lib/flocks/closeout.ts`.
//
// validateCloseoutDraft mirrors FlockCloseoutValidator.cs, word for word, so
// the person is told BEFORE they press Close. The server re-checks everything.

import 'trackers/tracker_logic.dart' show tNum, tStr;

/// PAYMENT_TERMS: (value, label).
const closeoutPaymentTerms = [
  ('Paid', 'Paid in full'),
  ('Credit', 'On credit'),
  ('PartPaid', 'Part paid'),
];

String paymentTermsLabel(String v) => closeoutPaymentTerms.firstWhere((t) => t.$1 == v, orElse: () => (v, v)).$2;

/// The wizard's own lists (flock-closeout-wizard.tsx).
const closeoutPaymentMethods = ['Cash', 'Mobile Money', 'Bank Transfer', 'Check', 'Credit Card'];
const closeoutReasons = ['End of lay (spent layers)', 'Depopulated', 'Disease outbreak', 'All birds sold', 'Other'];
const closeoutSteps = ['Reconcile', 'Dispose', 'Close'];

class CloseoutSale {
  CloseoutSale({this.quantity = 0, this.cashAccountId});
  num quantity;
  num unitPrice = 0;

  /// Typed total, or null for quantity x price.
  num? totalAmount;
  String customerName = '';
  String paymentTerms = 'Paid';
  num? amountPaid;
  String? paymentMethod = 'Cash';
  int? cashAccountId;
}

class CloseoutCull {
  CloseoutCull({this.quantity = 0});
  num quantity;
  String notes = '';
}

class CloseoutTransfer {
  CloseoutTransfer({this.quantity = 0});
  num quantity;
  String destination = '';
  String notes = '';
}

class CloseoutDraft {
  CloseoutDraft({this.closedDate = '', this.reason = 'End of lay (spent layers)'});
  String closedDate;
  String reason;
  String notes = '';
  final List<CloseoutSale> sales = [];
  final List<CloseoutCull> culls = [];
  final List<CloseoutTransfer> transfers = [];
}

int _qty(num? n) {
  final v = (n ?? 0);
  if (v.isNaN || v.isInfinite) return 0;
  final t = v.truncate();
  return t < 0 ? 0 : t;
}

num _round2(num n) => (n * 100).round() / 100;

/// Quantity x unit price unless a total was typed. The same default the server uses.
num saleTotal(CloseoutSale s) {
  final t = s.totalAmount;
  if (t != null && t.isFinite) return t;
  return _round2(_qty(s.quantity) * s.unitPrice);
}

typedef DispositionTotals = ({int sold, int culled, int transferred, int total});

DispositionTotals dispositionTotals(CloseoutDraft d) {
  final sold = d.sales.fold<int>(0, (s, l) => s + _qty(l.quantity));
  final culled = d.culls.fold<int>(0, (s, l) => s + _qty(l.quantity));
  final transferred = d.transfers.fold<int>(0, (s, l) => s + _qty(l.quantity));
  return (sold: sold, culled: culled, transferred: transferred, total: sold + culled + transferred);
}

/// Birds still to account for. Negative means the dispositions overshoot.
int unresolvedBirds(Map position, CloseoutDraft d) => tNum(position['currentLiveBirds']).toInt() - dispositionTotals(d).total;

typedef ReconciliationLine = ({String key, String label, num value, String sign, String? hint, bool muted});

ReconciliationLine _line(String key, String label, num value, String sign, {String? hint, bool muted = false}) =>
    (key: key, label: label, value: value, sign: sign, hint: hint, muted: muted);

/// The flock's birds, top to bottom, every line a column of fnflock_birdposition.
List<ReconciliationLine> reconciliationLines(Map p) {
  num v(String k) => tNum(p[k]);
  final lines = <ReconciliationLine>[_line('placed', 'Originally placed', v('originallyPlaced'), '=')];
  final hasOpening = p['hasOpeningPosition'] == true;

  if (hasOpening && v('originallyPlaced') != v('openingLiveBirds')) {
    if (p['historyKnown'] == true) {
      const hist = [
        ('openingMortality', 'Opening historical mortality'),
        ('openingSold', 'Sold before tracking began'),
        ('openingCulled', 'Culled before tracking began'),
        ('openingTransferred', 'Transferred before tracking began'),
        ('openingOther', 'Other opening adjustment'),
      ];
      for (final (key, label) in hist) {
        if (v(key) != 0) lines.add(_line(key, label, v(key), '-', muted: true));
      }
    } else {
      lines.add(_line('openingOther', 'Opening reduction (history not recorded)', v('originallyPlaced') - v('openingLiveBirds'), '-',
          muted: true, hint: 'Not known to be deaths, so it is not counted as mortality.'));
    }
  }

  lines.add(_line('openingLive', hasOpening ? 'Opening current position' : 'Birds at start', v('openingLiveBirds'), '='));
  lines.add(_line('mortality', 'Recorded mortality', v('recordedMortality'), '-'));
  if (v('correction') != 0) {
    lines.add(_line('correction', 'Count corrections', v('correction'), '±',
        hint: 'Changes in the production-record head count that recorded mortality does not explain.'));
  }
  lines.add(_line('lastCount', 'Last counted', v('lastCountedBirds'), '=',
      hint: tStr(p['lastCountDate']).isNotEmpty ? null : "No production records yet: the flock's starting number."));
  lines.add(_line('sold', 'Birds sold', v('birdsSold'), '-'));
  if (v('birdsCulled') != 0) lines.add(_line('culled', 'Culled', v('birdsCulled'), '-'));
  if (v('birdsTransferred') != 0) lines.add(_line('transferred', 'Transferred', v('birdsTransferred'), '-'));
  lines.add(_line('live', 'Current live birds', v('currentLiveBirds'), '='));
  return lines;
}

String _day(Object? v) {
  final s = tStr(v);
  return s.length >= 10 ? s.substring(0, 10) : s;
}

/// Mirrors FlockCloseoutValidator.Validate. Empty means ready to close.
List<String> validateCloseoutDraft(CloseoutDraft draft, Map context) {
  final errors = <String>[];
  if (context['isClosed'] == true) return ['This flock is already closed.'];
  final ineligible = tStr(context['ineligibleReason']);
  if (ineligible.isNotEmpty) return [ineligible];

  if (draft.reason.trim().isEmpty) errors.add('A reason is required to close a flock.');

  final closed = _day(draft.closedDate);
  final today = _day(context['businessDate']);
  final earliest = _day(context['earliestCloseDate']);
  if (closed.isEmpty) {
    errors.add('Choose the closing date.');
  } else {
    if (today.isNotEmpty && closed.compareTo(today) > 0) errors.add('The closing date cannot be in the future.');
    if (earliest.isNotEmpty && closed.compareTo(earliest) < 0) errors.add('The closing date cannot be before $earliest.');
  }

  for (var i = 0; i < draft.sales.length; i++) {
    final s = draft.sales[i];
    final n = 'Sale ${i + 1}';
    if (_qty(s.quantity) <= 0) errors.add('$n: enter how many birds were sold.');
    if (s.unitPrice < 0 || (s.totalAmount ?? 0) < 0) errors.add('$n: the price cannot be negative.');
    final total = saleTotal(s);
    final hasCustomer = s.customerName.trim().isNotEmpty;
    if (s.paymentTerms != 'Credit' && s.cashAccountId == null) {
      errors.add('$n: choose the cash account the money was received into.');
    }
    if (s.paymentTerms != 'Paid' && !hasCustomer) {
      errors.add('$n: a sale on credit needs a customer, so the balance has someone to belong to.');
    }
    if (s.paymentTerms == 'PartPaid') {
      final paid = s.amountPaid ?? 0;
      if (paid <= 0 || paid >= total) {
        errors.add('$n: a part payment must be more than zero and less than the sale total (${total.toStringAsFixed(2)}).');
      }
    }
    if (s.paymentTerms != 'Credit' && (s.paymentMethod ?? '').trim().isEmpty) errors.add('$n: choose how the customer paid.');
  }

  for (var i = 0; i < draft.culls.length; i++) {
    if (_qty(draft.culls[i].quantity) <= 0) errors.add('Cull ${i + 1}: enter how many birds were culled.');
  }
  for (var i = 0; i < draft.transfers.length; i++) {
    final t = draft.transfers[i];
    if (_qty(t.quantity) <= 0) errors.add('Transfer ${i + 1}: enter how many birds were transferred.');
    if (t.destination.trim().isEmpty) errors.add('Transfer ${i + 1}: say where the birds went.');
  }

  final position = context['position'] is Map ? context['position'] as Map : const {};
  final live = tNum(position['currentLiveBirds']).toInt();
  final left = unresolvedBirds(position, draft);
  if (live < 0) {
    errors.add(
        "The flock's records account for ${-live} more birds than it had. Check for a bird sale that was also deducted on a production record before closing.");
  } else if (left > 0) {
    errors.add(
        'Unresolved bird balance: $left bird(s) are still unaccounted for. Sell, cull or transfer them, or record any unrecorded deaths as mortality on a production record, before closing.');
  } else if (left < 0) {
    errors.add('Unresolved bird balance: the dispositions account for ${-left} more bird(s) than the flock has ($live).');
  }
  return errors;
}

// ---------------------------------------------------------------------------
// Comparison
// ---------------------------------------------------------------------------

/// GROUP_OPTIONS: (value, label).
const lifetimeGroupOptions = [
  ('batch', 'Batch'),
  ('breed', 'Breed'),
  ('supplier', 'Supplier'),
  ('house', 'House'),
  ('flock', 'Flock'),
];

class LifetimeGroup {
  LifetimeGroup(this.key, this.label);
  final String key;
  final String label;
  int flocks = 0;
  num originallyPlaced = 0, totalEggs = 0, recordedMortality = 0, openingLiveBirds = 0;
  num feedConsumedKg = 0, totalRevenue = 0, totalCost = 0, profit = 0;

  /// Re-derived from the sums, never an average of per-flock rates.
  num? get trackedMortalityRate => openingLiveBirds > 0 ? recordedMortality / openingLiveBirds : null;
  num? get profitPerOriginalBird => originallyPlaced > 0 ? _round2(profit / originallyPlaced) : null;
  num? get revenuePerOriginalBird => originallyPlaced > 0 ? _round2(totalRevenue / originallyPlaced) : null;
  num? get feedKgPerDozenEggs => totalEggs > 0 ? ((feedConsumedKg / (totalEggs / 12)) * 1000).round() / 1000 : null;
}

(String, String) _groupKey(Map row, String by) {
  switch (by) {
    case 'batch':
      final code = tStr(row['batchCode']);
      final name = tStr(row['batchName']);
      return ('b${row['batchId'] ?? 'none'}', code.isNotEmpty ? code : (name.isNotEmpty ? name : 'No batch'));
    case 'breed':
      final b = tStr(row['breed']).trim();
      return ('r${b.isEmpty ? 'none' : b.toLowerCase()}', b.isEmpty ? 'Unknown breed' : b);
    case 'supplier':
      if (row['supplierId'] != null) {
        final type = row['supplierType'];
        return ('s${type ?? ''}:${row['supplierId']}', '${type ?? 'Supplier'} #${row['supplierId']}');
      }
      return ('snone', 'No supplier recorded');
    case 'house':
      final h = tStr(row['houseName']);
      return ('h${row['houseId'] ?? 'none'}', h.isEmpty ? 'No house' : h);
    default:
      return ('f${row['flockId']}', tStr(row['flockName']));
  }
}

/// Batch vs Batch, Breed vs Breed, … — the same grouping over the lifetime rows.
List<LifetimeGroup> groupLifetimeSummaries(List<Map> rows, String by) {
  final map = <String, LifetimeGroup>{};
  for (final row in rows) {
    final (key, label) = _groupKey(row, by);
    final g = map.putIfAbsent(key, () => LifetimeGroup(key, label));
    g.flocks += 1;
    g.originallyPlaced += tNum(row['originallyPlaced']);
    g.totalEggs += tNum(row['totalEggs']);
    g.recordedMortality += tNum(row['recordedMortality']);
    g.openingLiveBirds += tNum(row['openingLiveBirds']);
    g.feedConsumedKg += tNum(row['feedConsumedKg']);
    g.totalRevenue += tNum(row['totalRevenue']);
    g.totalCost += tNum(row['totalCost']);
    g.profit += tNum(row['profit']);
  }
  return map.values.toList();
}
