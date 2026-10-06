// Initial Farm Setup: the pure part. A port of the web's
// `lib/farm-setup/wizard.ts`, kept rule-for-rule and word-for-word.
//
// An established poultry farm arriving with birds already in its pens says what
// is standing there TODAY. A flock placed with 1,050 that has 960 left has a
// historical reduction of 90, and those 90 belong to the OPENING POSITION,
// never to a production record. When the farm cannot break the 90 down, they
// are an unknown adjustment — NOT mortality.
//
// The same rules exist on the server (FarmSetupValidator.cs) and that copy is
// the one that decides. This one flags a bad row as it is typed.
//
// The draft travels as JSON in the SAME shape the web saves (migration 328), so
// a setup started on the web can be resumed on the phone and the other way round.

import 'dart:math' as math;

import '../shared/business_dates.dart';

/// Limits mirrored from FarmSetupValidator.cs.
const maxBatches = 50;
const maxHouses = 200;
const maxFlocks = 200;
const maxNameLength = 100;
const maxBatchCodeLength = 25;

/// lib/houses/bulk.ts MAX_ROWS.
const maxBulkRows = 200;

int _seq = 0;
// A per-run suffix, so keys never collide with the ones a restored draft holds.
final String _keyRun = math.Random().nextInt(1 << 20).toRadixString(36).padLeft(4, '0');
String nextKey(String prefix) => '$prefix-$_keyRun-${++_seq}';

String normalize(String? raw) => (raw ?? '').trim();

String duplicateKey(String? raw) => normalize(raw).replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

/// Whole number from form text: 0 when blank, null when not a whole number.
int? parseCount(String? raw) {
  final t = normalize(raw);
  if (t.isEmpty) return 0;
  if (!RegExp(r'^-?\d+$').hasMatch(t)) return null;
  return int.tryParse(t);
}

int count(String? raw) {
  final n = parseCount(raw);
  return n == null || n < 0 ? 0 : n;
}

/// toLocaleString() for whole numbers.
String fmtInt(num n) => fmtNum(n, 0);

String _s(Object? v) => v == null ? '' : '$v';
int? _i(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

// ------------------------------------------------------------------- rows

class BatchRow {
  BatchRow({
    required this.key,
    this.existingBatchId,
    this.batchName = '',
    this.batchCode = '',
    this.breed = '',
    this.numberOfBirds = '',
    this.startDate = '',
    this.costPerChick = '',
    this.supplierId,
    this.notes,
    this.poultryCashAccountId,
    this.isHistorical = true,
    this.totalCost = '',
    this.amountPaid = '',
    this.supplierType = 'local',
    this.dollarConversionRate = '',
    this.orderPlacementDate = '',
    this.estimatedArrivalDate = '',
  });

  final String key;
  int? existingBatchId;
  String batchName;
  String batchCode;
  String breed;
  String numberOfBirds;
  String startDate;
  String costPerChick;
  int? supplierId;
  String? notes;

  /// The cash account the purchase was paid from.
  int? poultryCashAccountId;

  /// Bought BEFORE tracking began. Per batch: decides whether an expense is
  /// posted, the bird-stock date, and whether every bird must be in a pen.
  bool isHistorical;
  String totalCost;
  String amountPaid;
  String supplierType;
  String dollarConversionRate;
  String orderPlacementDate;
  String estimatedArrivalDate;

  Map<String, dynamic> toJson() => {
        'key': key,
        if (existingBatchId != null) 'existingBatchId': existingBatchId,
        'batchName': batchName,
        'batchCode': batchCode,
        'breed': breed,
        'numberOfBirds': numberOfBirds,
        'startDate': startDate,
        'costPerChick': costPerChick,
        if (supplierId != null) 'supplierId': supplierId,
        if (notes != null) 'notes': notes,
        if (poultryCashAccountId != null) 'poultryCashAccountId': poultryCashAccountId,
        'isHistorical': isHistorical,
        'totalCost': totalCost,
        'amountPaid': amountPaid,
        'supplierType': supplierType,
        'dollarConversionRate': dollarConversionRate,
        'orderPlacementDate': orderPlacementDate,
        'estimatedArrivalDate': estimatedArrivalDate,
      };

  factory BatchRow.fromJson(Map j) => BatchRow(
        key: _s(j['key']).isEmpty ? nextKey('batch') : _s(j['key']),
        existingBatchId: _i(j['existingBatchId']),
        batchName: _s(j['batchName']),
        batchCode: _s(j['batchCode']),
        breed: _s(j['breed']),
        numberOfBirds: _s(j['numberOfBirds']),
        startDate: _s(j['startDate']),
        costPerChick: _s(j['costPerChick']),
        supplierId: _i(j['supplierId']),
        notes: j['notes'] == null ? null : _s(j['notes']),
        poultryCashAccountId: _i(j['poultryCashAccountId']),
        isHistorical: j['isHistorical'] != false,
        totalCost: _s(j['totalCost']),
        amountPaid: _s(j['amountPaid']),
        supplierType: j['supplierType'] == null ? 'local' : _s(j['supplierType']),
        dollarConversionRate: _s(j['dollarConversionRate']),
        orderPlacementDate: _s(j['orderPlacementDate']),
        estimatedArrivalDate: _s(j['estimatedArrivalDate']),
      );
}

class HouseRow {
  HouseRow({required this.key, this.existingHouseId, this.houseName = '', this.capacity = '', this.location = ''});
  final String key;
  int? existingHouseId;
  String houseName;
  String capacity;
  String location;

  Map<String, dynamic> toJson() => {
        'key': key,
        if (existingHouseId != null) 'existingHouseId': existingHouseId,
        'houseName': houseName,
        'capacity': capacity,
        'location': location,
      };

  factory HouseRow.fromJson(Map j) => HouseRow(
        key: _s(j['key']).isEmpty ? nextKey('house') : _s(j['key']),
        existingHouseId: _i(j['existingHouseId']),
        houseName: _s(j['houseName']),
        capacity: _s(j['capacity']),
        location: _s(j['location']),
      );
}

class FlockRow {
  FlockRow({
    required this.key,
    this.batchKey = '',
    this.houseKey = '',
    this.name = '',
    this.originallyPlaced = '',
    this.currentLiveBirds = '',
    this.ageMode = 'date',
    this.startDate = '',
    this.currentAgeInWeeks = '',
    this.historyKnown = false,
    this.historicalMortality = '',
    this.historicalSold = '',
    this.historicalCulled = '',
    this.historicalTransferred = '',
    this.notes,
    this.reconciliationTouched = false,
    this.breed = '',
    this.hasArrived = true,
  });

  final String key;
  String batchKey;
  String houseKey;
  String name;
  String originallyPlaced;
  String currentLiveBirds;

  /// "date" = a placement date is known; "age" = only the current age is.
  String ageMode;
  String startDate;
  String currentAgeInWeeks;
  bool historyKnown;
  String historicalMortality;
  String historicalSold;
  String historicalCulled;
  String historicalTransferred;
  String? notes;

  /// Whether the farm has worked on this flock's reconciliation itself.
  bool reconciliationTouched;

  /// Blank means the flock takes its batch's breed.
  String breed;
  bool hasArrived;

  Map<String, dynamic> toJson() => {
        'key': key,
        'batchKey': batchKey,
        'houseKey': houseKey,
        'name': name,
        'originallyPlaced': originallyPlaced,
        'currentLiveBirds': currentLiveBirds,
        'ageMode': ageMode,
        'startDate': startDate,
        'currentAgeInWeeks': currentAgeInWeeks,
        'historyKnown': historyKnown,
        'historicalMortality': historicalMortality,
        'historicalSold': historicalSold,
        'historicalCulled': historicalCulled,
        'historicalTransferred': historicalTransferred,
        if (notes != null) 'notes': notes,
        'reconciliationTouched': reconciliationTouched,
        'breed': breed,
        'hasArrived': hasArrived,
      };

  factory FlockRow.fromJson(Map j) => FlockRow(
        key: _s(j['key']).isEmpty ? nextKey('flock') : _s(j['key']),
        batchKey: _s(j['batchKey']),
        houseKey: _s(j['houseKey']),
        name: _s(j['name']),
        originallyPlaced: _s(j['originallyPlaced']),
        currentLiveBirds: _s(j['currentLiveBirds']),
        ageMode: j['ageMode'] == 'age' ? 'age' : 'date',
        startDate: _s(j['startDate']),
        currentAgeInWeeks: _s(j['currentAgeInWeeks']),
        historyKnown: j['historyKnown'] == true,
        historicalMortality: _s(j['historicalMortality']),
        historicalSold: _s(j['historicalSold']),
        historicalCulled: _s(j['historicalCulled']),
        historicalTransferred: _s(j['historicalTransferred']),
        notes: j['notes'] == null ? null : _s(j['notes']),
        reconciliationTouched: j['reconciliationTouched'] == true,
        breed: _s(j['breed']),
        hasArrived: j['hasArrived'] != false,
      );
}

class SetupDraft {
  SetupDraft({this.mode = 'existing', List<BatchRow>? batches, List<HouseRow>? houses, List<FlockRow>? flocks})
      : batches = batches ?? [],
        houses = houses ?? [],
        flocks = flocks ?? [];
  String mode;
  List<BatchRow> batches;
  List<HouseRow> houses;
  List<FlockRow> flocks;

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'batches': [for (final b in batches) b.toJson()],
        'houses': [for (final h in houses) h.toJson()],
        'flocks': [for (final f in flocks) f.toJson()],
      };

  /// Null when the text is not a draft (the web's "unreadable draft").
  static SetupDraft? fromJson(Object? j) {
    if (j is! Map || j['batches'] is! List || j['flocks'] is! List) return null;
    return SetupDraft(
      mode: j['mode'] == 'newBatch' ? 'newBatch' : 'existing',
      batches: [for (final b in j['batches'] as List) if (b is Map) BatchRow.fromJson(b)],
      houses: [for (final h in (j['houses'] is List ? j['houses'] as List : const [])) if (h is Map) HouseRow.fromJson(h)],
      flocks: [for (final f in j['flocks'] as List) if (f is Map) FlockRow.fromJson(f)],
    );
  }
}

// --------------------------------------------------------------- context

class ExistingHouse {
  const ExistingHouse({required this.houseId, required this.houseName, this.capacity, this.occupied = 0, this.activeFlocks = 0});
  final int houseId;
  final String houseName;
  final int? capacity;
  final int occupied;
  final int activeFlocks;
}

class ExistingBatch {
  const ExistingBatch({
    required this.batchId,
    required this.batchCode,
    required this.batchName,
    required this.breed,
    required this.numberOfBirds,
    this.startDate,
    this.isHistorical,
  });
  final int batchId;
  final String batchCode;
  final String batchName;
  final String breed;
  final int numberOfBirds;
  final String? startDate;
  final bool? isHistorical;
}

class ExistingFlock {
  const ExistingFlock({required this.flockId, required this.name, this.batchId, this.houseId, this.houseName, this.quantity = 0, this.active = true});
  final int flockId;
  final String name;
  final int? batchId;
  final int? houseId;
  final String? houseName;
  final int quantity;
  final bool active;
}

class SetupContext {
  const SetupContext({
    this.existingBatches = const [],
    this.existingHouses = const [],
    this.existingFlocks = const [],
    this.existingFlockNames = const [],
    this.allocatedByBatchId = const {},
    required this.businessDate,
  });
  final List<ExistingBatch> existingBatches;
  final List<ExistingHouse> existingHouses;
  final List<ExistingFlock> existingFlocks;
  final List<String> existingFlockNames;
  final Map<int, int> allocatedByBatchId;

  /// The company's business date, from the server.
  final String businessDate;

  /// From `/PoultryFarmSetup/context`, as the page's setupContext memo.
  factory SetupContext.fromServer(Map? c, String fallbackDate) {
    List l(Object? v) => v is List ? v : const [];
    int n(Object? v) => _i(v) ?? 0;
    final alloc = <int, int>{};
    final a = c?['allocatedByBatchId'];
    if (a is Map) {
      a.forEach((k, v) {
        final id = int.tryParse('$k');
        if (id != null) alloc[id] = n(v);
      });
    }
    return SetupContext(
      existingBatches: [
        for (final b in l(c?['batches']))
          if (b is Map)
            ExistingBatch(
              batchId: n(b['batchId']),
              batchCode: _s(b['batchCode']),
              batchName: _s(b['batchName']),
              breed: _s(b['breed']),
              numberOfBirds: n(b['numberOfBirds']),
              startDate: b['startDate'] == null ? null : _s(b['startDate']),
              isHistorical: b['isHistorical'] is bool ? b['isHistorical'] as bool : null,
            ),
      ],
      existingHouses: [
        for (final h in l(c?['houses']))
          if (h is Map)
            ExistingHouse(
              houseId: n(h['houseId']),
              houseName: _s(h['houseName']),
              capacity: _i(h['capacity']),
              occupied: n(h['occupied']),
              activeFlocks: n(h['activeFlocks']),
            ),
      ],
      existingFlocks: [
        for (final f in l(c?['flocks']))
          if (f is Map)
            ExistingFlock(
              flockId: n(f['flockId']),
              name: _s(f['name']),
              batchId: _i(f['batchId']),
              houseId: _i(f['houseId']),
              houseName: f['houseName'] == null ? null : _s(f['houseName']),
              quantity: n(f['quantity']),
              active: f['active'] != false,
            ),
      ],
      existingFlockNames: [for (final x in l(c?['existingFlockNames'])) _s(x)],
      allocatedByBatchId: alloc,
      businessDate: toBusinessDate(c?['businessDate']) ?? fallbackDate,
    );
  }
}

class SetupRowError {
  const SetupRowError(this.section, this.index, this.field, this.message);

  /// batches | houses | flocks | setup
  final String section;

  /// Index into that section, or -1 for the setup as a whole.
  final int index;
  final String field;
  final String message;
}

// ------------------------------------------------------------- builders

BatchRow emptyBatch() => BatchRow(key: nextKey('batch'));

HouseRow emptyHouse([String capacity = '', String location = '']) =>
    HouseRow(key: nextKey('house'), capacity: capacity, location: location);

FlockRow emptyFlock([String batchKey = '', String houseKey = '']) =>
    FlockRow(key: nextKey('flock'), batchKey: batchKey, houseKey: houseKey);

/// generateBatches: `count` rows numbered from `startNumber`. Names "Batch 1",
/// codes "B1" — no space, because codes are identifiers.
List<BatchRow> generateBatches({
  required int count,
  required String prefix,
  required String codePrefix,
  required int startNumber,
  required String breed,
  required String numberOfBirds,
  required String startDate,
}) {
  final n = math.max(0, math.min(count, maxBatches));
  final p = normalize(prefix), cp = normalize(codePrefix);
  return [
    for (var i = 0; i < n; i++)
      BatchRow(
        key: nextKey('batch'),
        batchName: p.isNotEmpty ? '$p ${startNumber + i}' : '${startNumber + i}',
        batchCode: cp.isNotEmpty ? '$cp${startNumber + i}' : '${startNumber + i}',
        breed: normalize(breed),
        numberOfBirds: normalize(numberOfBirds),
        startDate: normalize(startDate),
      ),
  ];
}

/// lib/houses/bulk.ts generateRows: "Pen 1", "Pen 2"… with the defaults.
List<HouseRow> generateHouseRows({
  required int count,
  required String prefix,
  required int startNumber,
  String capacity = '',
  String location = '',
}) {
  final n = math.max(0, math.min(count, maxBulkRows));
  final p = prefix.trim();
  return [
    for (var i = 0; i < n; i++)
      HouseRow(
        key: nextKey('house'),
        houseName: p.isNotEmpty ? '$p ${startNumber + i}' : '${startNumber + i}',
        capacity: capacity.trim(),
        location: location.trim(),
      ),
  ];
}

/// lib/houses/bulk.ts nextStartNumber: the first number after the highest
/// existing `prefix n` (or `prefixn`).
int nextStartNumber(String prefix, Iterable<String?> existingNames) {
  final key = duplicateKey(prefix);
  var highest = 0;
  for (final name in existingNames) {
    final k = duplicateKey(name);
    final String? rest = key.isNotEmpty ? (k.startsWith(key) ? k.substring(key.length) : null) : k;
    final m = rest == null ? null : RegExp(r'^\s*(\d+)$').firstMatch(rest);
    final v = m == null ? null : int.tryParse(m.group(1)!);
    if (v != null) highest = math.max(highest, v);
  }
  return highest + 1;
}

BatchRow batchRowFromExisting(ExistingBatch b) => BatchRow(
      key: nextKey('batch'),
      existingBatchId: b.batchId,
      batchName: b.batchName,
      batchCode: b.batchCode,
      breed: b.breed,
      numberOfBirds: '${b.numberOfBirds}',
      startDate: b.startDate == null ? '' : b.startDate!.split('T').first,
      isHistorical: b.isHistorical ?? false,
    );

HouseRow houseRowFromExisting(ExistingHouse h) => HouseRow(
      key: nextKey('house'),
      existingHouseId: h.houseId,
      houseName: h.houseName,
      capacity: h.capacity != null ? '${h.capacity}' : '',
    );

/// "B1 - Pen 1".
String defaultFlockName(String batchCode, String houseName) {
  final code = normalize(batchCode), house = normalize(houseName);
  if (code.isEmpty) return house;
  if (house.isEmpty) return code;
  return '$code - $house';
}

/// A generated name follows the pen; a name the farm wrote is kept.
String renameForHouse(String currentName, String batchCode, String previousHouseName, String nextHouseName) {
  final before = defaultFlockName(batchCode, previousHouseName);
  final ours = normalize(currentName).isEmpty || duplicateKey(currentName) == duplicateKey(before);
  return ours ? defaultFlockName(batchCode, nextHouseName) : currentName;
}

// ------------------------------------------------------------ arithmetic

int historicalReduction(FlockRow f) => math.max(0, count(f.originallyPlaced) - count(f.currentLiveBirds));

class OpeningBreakdown {
  const OpeningBreakdown({
    required this.mortality,
    required this.sold,
    required this.culled,
    required this.transferred,
    required this.other,
    required this.stated,
    required this.difference,
    required this.overStated,
  });
  final int mortality, sold, culled, transferred, other, stated, difference;
  final bool overStated;
}

/// With historyKnown false the ENTIRE difference is an unknown adjustment.
OpeningBreakdown breakdown(FlockRow f) {
  final difference = historicalReduction(f);
  if (!f.historyKnown) {
    return OpeningBreakdown(
        mortality: 0, sold: 0, culled: 0, transferred: 0, other: difference, stated: 0, difference: difference, overStated: false);
  }
  final m = count(f.historicalMortality), s = count(f.historicalSold);
  final c = count(f.historicalCulled), t = count(f.historicalTransferred);
  final stated = m + s + c + t;
  return OpeningBreakdown(
    mortality: m,
    sold: s,
    culled: c,
    transferred: t,
    other: math.max(0, difference - stated),
    stated: stated,
    difference: difference,
    overStated: stated > difference,
  );
}

List<FlockRow> flocksNeedingReconciliation(List<FlockRow> flocks) =>
    [for (final f in flocks) if (historicalReduction(f) > 0) f];

String deriveStartDate(String businessDate, int ageInWeeks) =>
    shiftBusinessDate(businessDate, -7 * math.max(0, ageInWeeks)) ?? businessDate;

({String date, bool estimated}) resolveStartDate(FlockRow f, String businessDate) {
  if (f.ageMode == 'date' && normalize(f.startDate).isNotEmpty) return (date: normalize(f.startDate), estimated: false);
  return (date: deriveStartDate(businessDate, count(f.currentAgeInWeeks)), estimated: true);
}

class SetupTotals {
  int batchCount = 0, houseCount = 0, flockCount = 0, batchBirds = 0, originallyPlaced = 0, openingLiveBirds = 0;
  int historicalReduction = 0, historicalMortality = 0, historicalSold = 0, historicalCulled = 0;
  int historicalTransferred = 0, otherAdjustment = 0, flocksWithUnknownHistory = 0;
}

SetupTotals summarize(SetupDraft d) {
  final t = SetupTotals()
    ..batchCount = d.batches.length
    ..houseCount = d.houses.length
    ..flockCount = d.flocks.length
    ..batchBirds = d.batches.fold(0, (s, b) => s + count(b.numberOfBirds));
  for (final f in d.flocks) {
    final b = breakdown(f);
    t.originallyPlaced += count(f.originallyPlaced);
    t.openingLiveBirds += count(f.currentLiveBirds);
    t.historicalReduction += b.difference;
    t.historicalMortality += b.mortality;
    t.historicalSold += b.sold;
    t.historicalCulled += b.culled;
    t.historicalTransferred += b.transferred;
    t.otherAdjustment += b.other;
    if (!f.historyKnown && b.difference > 0) t.flocksWithUnknownHistory++;
  }
  return t;
}

/// What a pen is carrying, as the setup sees it. Capacity is a FORWARD-PLANNING
/// figure; it never populates a bird count or blocks a fact.
class HouseLoad {
  const HouseLoad({
    required this.label,
    required this.capacity,
    required this.occupied,
    required this.activeFlocks,
    required this.standing,
  });
  final String label;
  final int? capacity;
  final int occupied;
  final int activeFlocks;
  final int standing;
  int get total => occupied + standing;
  int get overBy => capacity == null ? 0 : math.max(0, total - capacity!);
}

HouseLoad? houseLoad(String houseKey, SetupDraft d, SetupContext ctx) {
  final row = d.houses.where((h) => h.key == houseKey).firstOrNull;
  if (row == null) return null;
  int? capacity = count(row.capacity) == 0 ? null : count(row.capacity);
  var occupied = 0, active = 0;
  var label = normalize(row.houseName);
  if (row.existingHouseId != null) {
    final e = ctx.existingHouses.where((h) => h.houseId == row.existingHouseId).firstOrNull;
    if (e == null) return null;
    capacity = e.capacity != null && e.capacity! > 0 ? e.capacity : null;
    occupied = e.occupied;
    active = e.activeFlocks;
    label = e.houseName;
  }
  final standing = d.flocks.fold(0, (s, f) => f.houseKey == houseKey ? s + count(f.currentLiveBirds) : s);
  return HouseLoad(label: label, capacity: capacity, occupied: occupied, activeFlocks: active, standing: standing);
}

/// The note for a pen holding more than its recorded capacity.
String? houseCapacityNote(HouseLoad load) {
  if (load.capacity == null || load.overBy == 0) return null;
  final held = load.occupied > 0 ? ' and already holds ${fmtInt(load.occupied)}' : '';
  return '${load.label} is recorded as taking ${fmtInt(load.capacity!)} birds$held, '
      'but this setup puts ${fmtInt(load.standing)} in it. '
      'Update the capacity — it is what decides where your next batch can go.';
}

/// over | unallocated | partial | complete
const _statusRank = {'over': 0, 'unallocated': 1, 'partial': 2, 'complete': 3};

class BatchAllocationView {
  const BatchAllocationView({
    required this.batch,
    required this.index,
    required this.isExisting,
    required this.batchBirds,
    required this.previouslyAllocated,
    required this.thisAllocation,
    required this.available,
    required this.remaining,
    required this.status,
    required this.mustBeFullyAllocated,
  });
  final BatchRow batch;
  final int index;
  final bool isExisting;
  final int batchBirds, previouslyAllocated, thisAllocation, available, remaining;
  final String status;
  final bool mustBeFullyAllocated;
  int get overBy => previouslyAllocated + thisAllocation - batchBirds;
}

/// Measured on the PLACED basis throughout (migration 325).
List<BatchAllocationView> batchAllocationViews(SetupDraft d, SetupContext ctx) => [
      for (final (index, batch) in d.batches.indexed)
        () {
          final existing = batch.existingBatchId == null
              ? null
              : ctx.existingBatches.where((b) => b.batchId == batch.existingBatchId).firstOrNull;
          final batchBirds = existing?.numberOfBirds ?? count(batch.numberOfBirds);
          final previously = existing == null ? 0 : (ctx.allocatedByBatchId[existing.batchId] ?? 0);
          final thisAlloc = d.flocks.fold(0, (s, f) => f.batchKey == batch.key ? s + count(f.originallyPlaced) : s);
          final available = math.max(0, batchBirds - previously);
          final placed = previously + thisAlloc;
          final status = batchBirds > 0 && placed > batchBirds
              ? 'over'
              : batchBirds > 0 && placed == batchBirds
                  ? 'complete'
                  : placed == 0
                      ? 'unallocated'
                      : 'partial';
          return BatchAllocationView(
            batch: batch,
            index: index,
            isExisting: batch.existingBatchId != null,
            batchBirds: batchBirds,
            previouslyAllocated: previously,
            thisAllocation: thisAlloc,
            available: available,
            remaining: math.max(0, available - thisAlloc),
            status: status,
            mustBeFullyAllocated: isHistoricalBatch(batch, ctx),
          );
        }(),
    ];

/// Most in need of attention first; fully allocated existing batches hidden
/// unless [showAll]. [keepKey] is never filtered out.
List<BatchAllocationView> visibleBatchRows(List<BatchAllocationView> views, bool showAll, [String? keepKey]) {
  final shown = showAll
      ? [...views]
      : [for (final v in views) if (v.batch.key == keepKey || !v.isExisting || v.status != 'complete') v];
  shown.sort((a, b) {
    final r = _statusRank[a.status]!.compareTo(_statusRank[b.status]!);
    return r != 0 ? r : a.index.compareTo(b.index);
  });
  return shown;
}

({int total, int hidden, int withBirdsLeft}) summarizeBatchRows(List<BatchAllocationView> views) => (
      total: views.length,
      hidden: views.where((v) => v.isExisting && v.status == 'complete').length,
      withBirdsLeft: views.where((v) => v.remaining > 0).length,
    );

/// Standing starts EQUAL to placed — the farm records losses by lowering it.
void _withBirds(FlockRow f, int birds) {
  final v = birds > 0 ? '$birds' : '';
  f.originallyPlaced = v;
  f.currentLiveBirds = v;
}

/// The Batch Allocation tool's even split: floor, remainder to the first rows.
List<int> distributeEqually(int available, int rows) {
  if (rows == 0 || available <= 0) return List.filled(rows, 0);
  final base = available ~/ rows;
  final remainder = available - base * rows;
  return [for (var i = 0; i < rows; i++) base + (i < remainder ? 1 : 0)];
}

void distributePensEvenly(SetupDraft d, String batchKey, int available) {
  final targets = [for (final f in d.flocks) if (f.batchKey == batchKey) f];
  if (targets.isEmpty || available <= 0) return;
  final shares = distributeEqually(available, targets.length);
  for (final (i, f) in targets.indexed) {
    _withBirds(f, shares[i]);
  }
}

/// Fill each chosen pen to its remaining capacity, in order, until the birds
/// run out. A pen with no capacity takes whatever is left.
void fillPensToCapacity(SetupDraft d, SetupContext ctx, String batchKey, int available) {
  final targets = [for (final f in d.flocks) if (f.batchKey == batchKey) f];
  if (targets.isEmpty || available <= 0) return;
  final targetKeys = {for (final f in targets) f.key};
  final baseline = <String, int>{};
  for (final f in d.flocks) {
    if (targetKeys.contains(f.key) || f.houseKey.isEmpty) continue;
    baseline[f.houseKey] = (baseline[f.houseKey] ?? 0) + count(f.currentLiveBirds);
  }
  var remaining = available;
  final share = <String, int>{};
  for (final f in targets) {
    if (remaining <= 0) {
      share[f.key] = 0;
      continue;
    }
    final row = d.houses.where((h) => h.key == f.houseKey).firstOrNull;
    int? capacity = row == null || count(row.capacity) == 0 ? null : count(row.capacity);
    var occupied = 0;
    if (row?.existingHouseId != null) {
      final e = ctx.existingHouses.where((h) => h.houseId == row!.existingHouseId).firstOrNull;
      capacity = e?.capacity != null && e!.capacity! > 0 ? e.capacity : null;
      occupied = e?.occupied ?? 0;
    }
    final used = occupied + (baseline[f.houseKey] ?? 0);
    final room = capacity == null ? remaining : math.max(0, capacity - used);
    final take = math.min(remaining, room);
    share[f.key] = take;
    remaining -= take;
  }
  for (final f in targets) {
    _withBirds(f, share[f.key] ?? 0);
  }
}

/// MORTALITY IS THE BALANCING BUCKET: typing Sold / Culled / Transferred takes
/// the birds out of mortality; editing mortality leaves the others alone.
void balanceBreakdown(FlockRow f, String field, String value) {
  f.reconciliationTouched = true;
  switch (field) {
    case 'historicalMortality':
      f.historicalMortality = value;
      return;
    case 'historicalSold':
      f.historicalSold = value;
    case 'historicalCulled':
      f.historicalCulled = value;
    case 'historicalTransferred':
      f.historicalTransferred = value;
  }
  final claimed = count(f.historicalSold) + count(f.historicalCulled) + count(f.historicalTransferred);
  final left = math.max(0, historicalReduction(f) - claimed);
  f.historicalMortality = left > 0 ? '$left' : '0';
}

/// Pre-fill: the missing birds died — on screen, for the farm to agree with or
/// change. Only flocks the farm has not worked on.
void seedReconciliation(SetupDraft d) {
  for (final f in d.flocks) {
    if (f.reconciliationTouched) continue;
    final diff = historicalReduction(f);
    if (diff <= 0) continue;
    f.historyKnown = true;
    f.historicalMortality = '$diff';
    f.historicalSold = '';
    f.historicalCulled = '';
    f.historicalTransferred = '';
  }
}

/// A REUSED batch answers from what is stored against it.
bool isHistoricalBatch(BatchRow b, SetupContext ctx) {
  if (b.existingBatchId != null) {
    return ctx.existingBatches.where((x) => x.batchId == b.existingBatchId).firstOrNull?.isHistorical ?? false;
  }
  return b.isHistorical;
}

class HouseRowView {
  const HouseRowView({
    required this.row,
    required this.index,
    required this.isExisting,
    required this.load,
    required this.hasRoom,
    required this.isEmpty,
    required this.isEmptyOnFarm,
  });
  final HouseRow row;
  final int index;
  final bool isExisting;
  final HouseLoad? load;
  final bool hasRoom, isEmpty, isEmptyOnFarm;
}

List<HouseRowView> houseRowViews(SetupDraft d, SetupContext ctx) => [
      for (final (i, row) in d.houses.indexed)
        () {
          final load = houseLoad(row.key, d, ctx);
          return HouseRowView(
            row: row,
            index: i,
            isExisting: row.existingHouseId != null,
            load: load,
            hasRoom: load?.capacity == null ? true : load!.total < load.capacity!,
            isEmpty: load == null ? true : load.total == 0,
            isEmptyOnFarm: load == null ? true : load.occupied == 0,
          );
        }(),
    ];

/// With [showAll] off an EXISTING pen shows only when empty on the farm.
List<HouseRowView> visibleHouseRows(List<HouseRowView> views, bool showAll) =>
    showAll ? views : [for (final v in views) if (!v.isExisting || v.isEmptyOnFarm) v];

/// Pens the allocation picker offers: everything with room, plus [selectedKey].
List<HouseRowView> penOptions(List<HouseRowView> views, [String? selectedKey]) =>
    [for (final v in views) if (v.row.key == selectedKey || v.hasRoom) v];

({int total, int existing, int occupied, int hidden}) summarizeHouseRows(List<HouseRowView> views) {
  final existing = views.where((v) => v.isExisting).toList();
  final occupied = existing.where((v) => !v.isEmptyOnFarm).length;
  return (total: views.length, existing: existing.length, occupied: occupied, hidden: occupied);
}

/// patchForCostChange / deriveTotalCost: cost × birds, as text, blank when 0.
String deriveTotalCost(String costPerChick, String numberOfBirds) {
  final total = (double.tryParse(costPerChick.trim()) ?? 0) * (double.tryParse(numberOfBirds.trim()) ?? 0);
  if (total <= 0) return '';
  final v = double.parse(total.toStringAsFixed(2));
  return v == v.roundToDouble() ? '${v.toInt()}' : '$v';
}

/// batchBalance: never negative.
double batchBalance(String totalCost, String amountPaid) =>
    math.max(0, (double.tryParse(totalCost.trim()) ?? 0) - (double.tryParse(amountPaid.trim()) ?? 0));

// ------------------------------------------------------------ validation

({List<SetupRowError> errors, List<SetupRowError> warnings}) validateSetup(SetupDraft d, SetupContext ctx) {
  final errors = <SetupRowError>[];
  final warnings = <SetupRowError>[];
  void err(String s, int i, String f, String m) => errors.add(SetupRowError(s, i, f, m));
  void warn(String s, int i, String f, String m) => warnings.add(SetupRowError(s, i, f, m));

  if (d.batches.length > maxBatches) err('setup', -1, 'batches', 'At most $maxBatches batches in one setup.');
  if (d.houses.length > maxHouses) err('setup', -1, 'houses', 'At most $maxHouses houses in one setup.');
  if (d.flocks.length > maxFlocks) err('setup', -1, 'flocks', 'At most $maxFlocks flocks in one setup.');
  if (errors.isNotEmpty) return (errors: errors, warnings: warnings);

  // ---- Batches
  final existingCodes = {for (final b in ctx.existingBatches) duplicateKey(b.batchCode)};
  final seenCodes = <String>{};
  final batchByKey = <String, BatchRow>{};
  for (final (i, b) in d.batches.indexed) {
    batchByKey[b.key] = b;
    if (b.existingBatchId != null) continue;
    if (normalize(b.batchName).isEmpty) {
      err('batches', i, 'batchName', 'Batch name is required.');
    } else if (normalize(b.batchName).length > maxNameLength) {
      err('batches', i, 'batchName', 'Batch name cannot be longer than $maxNameLength characters.');
    }
    final code = normalize(b.batchCode);
    if (code.isEmpty) {
      err('batches', i, 'batchCode', 'Batch code is required.');
    } else if (code.length > maxBatchCodeLength) {
      err('batches', i, 'batchCode', 'Batch code cannot be longer than $maxBatchCodeLength characters.');
    } else if (existingCodes.contains(duplicateKey(code))) {
      err('batches', i, 'batchCode', 'A batch with code "$code" already exists — reuse it instead of creating a second one.');
    } else if (seenCodes.contains(duplicateKey(code))) {
      err('batches', i, 'batchCode', '"$code" appears more than once in this setup.');
    } else {
      seenCodes.add(duplicateKey(code));
    }
    if (count(b.numberOfBirds) <= 0) {
      err('batches', i, 'numberOfBirds', 'Enter how many birds the batch originally had — more than zero.');
    }
    if (normalize(b.startDate).isEmpty) err('batches', i, 'startDate', 'Give the batch an arrival or placement date.');
  }

  // ---- Houses
  final existingHouseNames = {for (final h in ctx.existingHouses) duplicateKey(h.houseName)};
  final seenHouseNames = <String>{};
  final houseByKey = <String, HouseRow>{};
  for (final (i, h) in d.houses.indexed) {
    houseByKey[h.key] = h;
    if (h.existingHouseId != null) continue;
    final name = normalize(h.houseName);
    if (name.isEmpty) {
      err('houses', i, 'houseName', 'House name is required.');
    } else if (name.length > maxNameLength) {
      err('houses', i, 'houseName', 'House name cannot be longer than $maxNameLength characters.');
    } else if (existingHouseNames.contains(duplicateKey(name))) {
      err('houses', i, 'houseName', 'A house named "$name" already exists — select it instead of creating a second one.');
    } else if (seenHouseNames.contains(duplicateKey(name))) {
      err('houses', i, 'houseName', '"$name" appears more than once in this setup.');
    } else {
      seenHouseNames.add(duplicateKey(name));
    }
    if (parseCount(h.capacity) == null) {
      err('houses', i, 'capacity', 'Capacity must be a whole number.');
    } else if (parseCount(h.capacity)! < 0) {
      err('houses', i, 'capacity', 'Capacity cannot be negative.');
    }
  }

  // ---- Flocks
  final existingNames = {for (final n in ctx.existingFlockNames) duplicateKey(n)}..remove('');
  final nameCounts = <String, int>{};
  for (final f in d.flocks) {
    final k = duplicateKey(f.name);
    if (k.isNotEmpty) nameCounts[k] = (nameCounts[k] ?? 0) + 1;
  }
  final placedByBatchKey = <String, int>{};
  final standingByHouseKey = <String, int>{};
  final newBirdsByHouseKey = <String, int>{};

  for (final (i, f) in d.flocks.indexed) {
    final name = normalize(f.name);
    if (name.isEmpty) {
      err('flocks', i, 'name', 'Flock name is required.');
    } else if (name.length > maxNameLength) {
      err('flocks', i, 'name', 'Flock name cannot be longer than $maxNameLength characters.');
    } else if ((nameCounts[duplicateKey(name)] ?? 0) > 1) {
      err('flocks', i, 'name', '"$name" appears more than once in this setup.');
    } else if (existingNames.contains(duplicateKey(name))) {
      err('flocks', i, 'name', 'A flock named "$name" already exists on this farm.');
    }

    final placed = parseCount(f.originallyPlaced);
    final live = parseCount(f.currentLiveBirds);
    if (placed == null) {
      err('flocks', i, 'originallyPlaced', 'Originally placed must be a whole number.');
    } else if (placed <= 0) {
      err('flocks', i, 'originallyPlaced', 'Enter how many birds were originally placed in this flock.');
    }
    if (live == null) {
      err('flocks', i, 'currentLiveBirds', 'Current live birds must be a whole number.');
    } else if (live < 0) {
      err('flocks', i, 'currentLiveBirds', 'Current live birds cannot be negative.');
    } else if (placed != null && placed > 0 && live > placed) {
      err('flocks', i, 'currentLiveBirds',
          'There cannot be more birds standing (${fmtInt(live)}) than were placed (${fmtInt(placed)}).');
    }

    if (f.ageMode == 'date' && normalize(f.startDate).isEmpty) {
      err('flocks', i, 'startDate', "Give either the placement date or the flock's current age in weeks.");
    }
    if (f.ageMode == 'age' && parseCount(f.currentAgeInWeeks) == null) {
      err('flocks', i, 'currentAgeInWeeks', 'Current age must be a whole number of weeks.');
    }

    if (f.historyKnown) {
      final b = breakdown(f);
      if (b.overStated) {
        err('flocks', i, 'breakdown',
            'The breakdown adds up to ${fmtInt(b.stated)} but only ${fmtInt(b.difference)} birds remain to account for.');
      }
    }

    if (f.batchKey.isEmpty || !batchByKey.containsKey(f.batchKey)) {
      err('flocks', i, 'batchKey', 'Choose which batch this flock came from.');
    } else {
      placedByBatchKey[f.batchKey] = (placedByBatchKey[f.batchKey] ?? 0) + count(f.originallyPlaced);
    }

    if (f.houseKey.isEmpty || !houseByKey.containsKey(f.houseKey)) {
      err('flocks', i, 'houseKey', 'Choose which house/pen this flock is in.');
    } else {
      standingByHouseKey[f.houseKey] = (standingByHouseKey[f.houseKey] ?? 0) + count(f.currentLiveBirds);
      final fb = batchByKey[f.batchKey];
      if (fb != null && !isHistoricalBatch(fb, ctx)) {
        newBirdsByHouseKey[f.houseKey] = (newBirdsByHouseKey[f.houseKey] ?? 0) + count(f.currentLiveBirds);
      }
    }
  }

  // ---- Batch integrity: an ERROR
  placedByBatchKey.forEach((key, placed) {
    final batch = batchByKey[key];
    if (batch == null) return;
    final index = d.batches.indexOf(batch);
    var capacity = count(batch.numberOfBirds);
    var already = 0;
    var label = normalize(batch.batchCode);
    if (batch.existingBatchId != null) {
      final e = ctx.existingBatches.where((b) => b.batchId == batch.existingBatchId).firstOrNull;
      if (e == null) return;
      capacity = e.numberOfBirds;
      already = ctx.allocatedByBatchId[e.batchId] ?? 0;
      label = e.batchCode;
    }
    if (capacity <= 0) return;
    if (placed + already > capacity) {
      final note = already > 0 ? ' (${fmtInt(already)} already allocated)' : '';
      err('batches', index, 'numberOfBirds',
          'Flocks from $label were placed with ${fmtInt(placed)} birds$note, but the batch only had ${fmtInt(capacity)}.');
    } else if (isHistoricalBatch(batch, ctx) && placed + already < capacity) {
      final missing = capacity - (placed + already);
      err('batches', index, 'numberOfBirds',
          '$label is a batch you already had, so all ${fmtInt(capacity)} of its birds must be in a pen — '
          '${fmtInt(missing)} are unaccounted for. Put them in a pen, or lower the batch to ${fmtInt(placed + already)}.');
    }
  });

  if (d.flocks.isEmpty) {
    err('setup', -1, 'flocks', 'Add at least one flock — that is what tells us how many birds you have.');
  }

  // ---- House capacity: a WARNING (an error only for newly bought birds)
  standingByHouseKey.forEach((key, _) {
    final house = houseByKey[key];
    if (house == null) return;
    final load = houseLoad(key, d, ctx);
    if (load == null || load.capacity == null || load.overBy == 0) return;
    final index = d.houses.indexOf(house);
    final newBirds = newBirdsByHouseKey[key] ?? 0;
    if (newBirds > 0) {
      final occ = load.occupied > 0 ? ' and already holds ${fmtInt(load.occupied)}' : '';
      final room = math.max(0, load.capacity! - load.occupied - (load.standing - newBirds));
      err('houses', index, 'capacity',
          '${load.label} holds ${fmtInt(load.capacity!)} birds$occ. '
          'You are placing ${fmtInt(newBirds)} newly bought birds in it and only ${fmtInt(room)} will fit.');
    } else {
      final note = houseCapacityNote(load);
      if (note != null) warn('houses', index, 'capacity', note);
    }
  });

  // ---- Optional data: INFORMATIONAL only
  for (final (i, b) in d.batches.indexed) {
    if (b.existingBatchId != null) continue;
    final label = normalize(b.batchCode).isNotEmpty ? normalize(b.batchCode) : 'Batch ${i + 1}';
    if (b.supplierId == null) {
      warn('batches', i, 'supplierId', '$label has no supplier recorded. You can complete this later.');
    }
    if (count(b.costPerChick) == 0 && count(b.totalCost) == 0) {
      warn('batches', i, 'costPerChick', '$label has no purchase cost recorded. You can complete this later.');
    }
    if (normalize(b.breed).isEmpty) {
      warn('batches', i, 'breed', '$label has no breed recorded. You can complete this later.');
    }
  }

  return (errors: errors, warnings: warnings);
}

/// Errors keyed by section, index, field.
Map<String, Map<int, Map<String, String>>> errorsBySection(List<SetupRowError> errors) {
  final map = <String, Map<int, Map<String, String>>>{};
  for (final e in errors) {
    if (e.index < 0) continue;
    map.putIfAbsent(e.section, () => {}).putIfAbsent(e.index, () => {})[e.field] = e.message;
  }
  return map;
}

num? _money(String raw) => normalize(raw).isEmpty ? null : num.tryParse(raw.trim());

/// The request body. Keys travel as-is; the server resolves them to real ids.
Map<String, dynamic> toRequest(SetupDraft d, SetupContext ctx, String userId, String farmId) => {
      'UserId': userId,
      'FarmId': farmId,
      'SetupMode': 'ExistingFarm',
      'Source': 'Initial Farm Setup',
      'Batches': [
        for (final b in d.batches)
          {
            'Key': b.key,
            'ExistingBatchId': b.existingBatchId,
            'BatchName': normalize(b.batchName),
            'BatchCode': normalize(b.batchCode),
            'Breed': normalize(b.breed),
            'NumberOfBirds': count(b.numberOfBirds),
            'StartDate': normalize(b.startDate).isNotEmpty ? '${normalize(b.startDate)}T00:00:00' : null,
            'CostPerChick': _money(b.costPerChick),
            'TotalCost': _money(b.totalCost),
            'AmountPaid': _money(b.amountPaid),
            'SupplierId': b.supplierId,
            'SupplierType': normalize(b.supplierType).isEmpty ? null : normalize(b.supplierType),
            'PoultryCashAccountId': b.poultryCashAccountId,
            'DollarConversionRate': _money(b.dollarConversionRate),
            'OrderPlacementDate': normalize(b.orderPlacementDate).isEmpty ? null : normalize(b.orderPlacementDate),
            'EstimatedArrivalDate': normalize(b.estimatedArrivalDate).isEmpty ? null : normalize(b.estimatedArrivalDate),
            'IsHistorical': b.isHistorical,
            'Notes': b.notes,
          },
      ],
      'Houses': [
        for (final h in d.houses)
          {
            'Key': h.key,
            'ExistingHouseId': h.existingHouseId,
            'HouseName': normalize(h.houseName),
            'Capacity': normalize(h.capacity).isNotEmpty ? count(h.capacity) : null,
            'Location': normalize(h.location).isEmpty ? null : normalize(h.location),
          },
      ],
      'Flocks': [
        for (final f in d.flocks)
          () {
            final b = breakdown(f);
            final r = resolveStartDate(f, ctx.businessDate);
            return {
              'BatchKey': f.batchKey,
              'HouseKey': f.houseKey,
              'Name': normalize(f.name),
              'Breed': normalize(f.breed).isEmpty ? null : normalize(f.breed),
              'HasArrived': f.hasArrived,
              'OriginallyPlaced': count(f.originallyPlaced),
              'CurrentLiveBirds': count(f.currentLiveBirds),
              'StartDate': r.estimated ? null : '${r.date}T00:00:00',
              'CurrentAgeInWeeks': r.estimated ? count(f.currentAgeInWeeks) : null,
              'HistoryKnown': f.historyKnown,
              'HistoricalMortality': b.mortality,
              'HistoricalSold': b.sold,
              'HistoricalCulled': b.culled,
              'HistoricalTransferred': b.transferred,
              'OtherAdjustment': b.other,
              'Notes': f.notes,
            };
          }(),
      ],
    };
