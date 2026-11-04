// Egg packaging: Boxes, Crates and Pieces (migration 393/394), ported from
// lib/poultry/egg-packaging.ts and hooks/use-egg-packaging.ts.
//
// Egg stock is ALWAYS individual eggs. A crate is the farm's eggs-per-crate
// (344) and a box is the farm's crates-per-box (393); both are only ways of
// writing the same egg count. The database is the authority when posting;
// these are for entry, previews and display. A box is a quantity unit, not a
// poultry Batch (a group of birds).

import 'package:intl/intl.dart';

import '../../api/api_client.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import 'production/production_logic.dart' show eggsPerCrate;
import 'trackers/tracker_logic.dart' show tIntOrNull;

/// How a farm wants egg quantities written.
enum EggDisplay { boxesCratesPieces, cratesPieces, pieces }

/// Which packaging field comes first on a sale line. Presentation only.
enum SaleEntryUnit { boxes, crates }

const eggDisplayApi = {EggDisplay.boxesCratesPieces: 'BoxesCratesPieces', EggDisplay.cratesPieces: 'CratesPieces', EggDisplay.pieces: 'Pieces'};
const saleEntryApi = {SaleEntryUnit.boxes: 'Boxes', SaleEntryUnit.crates: 'Crates'};

EggDisplay eggDisplayOf(Object? v) =>
    eggDisplayApi.entries.firstWhere((e) => e.value == '$v', orElse: () => const MapEntry(EggDisplay.cratesPieces, '')).key;
SaleEntryUnit saleEntryOf(Object? v) => '$v' == 'Boxes' ? SaleEntryUnit.boxes : SaleEntryUnit.crates;

const maxCratesPerBox = 200;

class EggPackaging {
  const EggPackaging({
    this.eggsPerCrate = 30,
    this.enableBoxes = false,
    this.cratesPerBox,
    this.display = EggDisplay.cratesPieces,
    this.saleEntryUnit = SaleEntryUnit.crates,
    this.version = 1,
  });
  final int eggsPerCrate;
  final bool enableBoxes;

  /// Null when boxes are off.
  final int? cratesPerBox;
  final EggDisplay display;
  final SaleEntryUnit saleEntryUnit;

  /// Bumps whenever the conversion changes (393).
  final int version;

  int? get eggsPerBox => boxSize(this) == null ? null : boxSize(this)! * (eggsPerCrate < 1 ? 30 : eggsPerCrate);

  EggPackaging copyWith({int? eggsPerCrate, bool? enableBoxes, int? cratesPerBox, EggDisplay? display}) => EggPackaging(
        eggsPerCrate: eggsPerCrate ?? this.eggsPerCrate,
        enableBoxes: enableBoxes ?? this.enableBoxes,
        cratesPerBox: cratesPerBox ?? this.cratesPerBox,
        display: display ?? this.display,
        saleEntryUnit: saleEntryUnit,
        version: version,
      );
}

const defaultEggPackaging = EggPackaging();

class PackagedQuantity {
  const PackagedQuantity({this.boxes = 0, this.crates = 0, this.pieces = 0});
  final int boxes, crates, pieces;
  @override
  bool operator ==(Object other) => other is PackagedQuantity && other.boxes == boxes && other.crates == crates && other.pieces == pieces;
  @override
  int get hashCode => Object.hash(boxes, crates, pieces);
  @override
  String toString() => 'PackagedQuantity($boxes, $crates, $pieces)';
}

int _whole(Object? n) {
  final v = n is num ? n : num.tryParse('${n ?? ''}');
  return v == null || !v.isFinite ? 0 : v.truncate();
}

int _epc(EggPackaging p) => _whole(p.eggsPerCrate) < 1 ? 30 : _whole(p.eggsPerCrate);

/// Crates per box when boxes are usable, else null. Never 0.
int? boxSize(EggPackaging p) {
  final c = _whole(p.cratesPerBox);
  return p.enableBoxes && c >= 1 ? c : null;
}

/// A packaging configuration problem, or null (sppoultryeggpackaging_save's rules).
String? packagingConfigError({required bool enableBoxes, required int? cratesPerBox, required EggDisplay display, required SaleEntryUnit saleEntryUnit}) {
  if (enableBoxes && cratesPerBox == null) return 'Enter how many crates are in one box.';
  if (cratesPerBox != null && (cratesPerBox < 1 || cratesPerBox > maxCratesPerBox)) {
    return 'Crates per box must be a whole number from 1 to $maxCratesPerBox.';
  }
  if (display == EggDisplay.boxesCratesPieces && !enableBoxes) return 'Turn on Boxes to show quantities in boxes.';
  if (saleEntryUnit == SaleEntryUnit.boxes && !enableBoxes) return 'Turn on Boxes to enter sales in boxes first.';
  return null;
}

/// A packaging entry problem, or null. Boxes only when the farm has a box size.
String? packagedQuantityError(PackagedQuantity q, EggPackaging p) {
  for (final (k, v) in [('boxes', q.boxes), ('crates', q.crates), ('pieces', q.pieces)]) {
    if (v < 0) return '${k[0].toUpperCase()}${k.substring(1)} cannot be negative.';
  }
  if (q.boxes > 0 && boxSize(p) == null) return 'Boxes are not set up for this farm.';
  return null;
}

/// Boxes + Crates + Pieces -> eggs. Negative parts count as 0.
int toEggPieces(PackagedQuantity q, EggPackaging p) {
  final b = q.boxes < 0 ? 0 : q.boxes, c = q.crates < 0 ? 0 : q.crates, pc = q.pieces < 0 ? 0 : q.pieces;
  return b * (p.eggsPerBox ?? 0) + c * _epc(p) + pc;
}

/// Eggs -> whole boxes, whole crates, loose pieces. A negative count keeps its sign on every part.
PackagedQuantity toBoxesCratesPieces(num totalEggs, EggPackaging p) {
  final raw = _whole(totalEggs);
  final sign = raw < 0 ? -1 : 1;
  final n = raw.abs();
  final epc = _epc(p);
  final ebx = p.eggsPerBox;
  final boxes = ebx != null && ebx > 0 ? n ~/ ebx : 0;
  final rest = ebx != null && ebx > 0 ? n % ebx : n;
  return PackagedQuantity(boxes: sign * boxes, crates: sign * (rest ~/ epc), pieces: sign * (rest % epc));
}

/// Eggs -> whole crates + loose pieces, ignoring boxes.
PackagedQuantity toCratesPieces(num totalEggs, EggPackaging p) => toBoxesCratesPieces(totalEggs, EggPackaging(eggsPerCrate: p.eggsPerCrate));

/// The same eggs written in their fewest packages.
PackagedQuantity normalizePackaged(PackagedQuantity q, EggPackaging p) => toBoxesCratesPieces(toEggPieces(q, p), p);

final _int = NumberFormat('#,##0', 'en_US');
String _plural(int n, String one, String many) => n.abs() == 1 ? one : many;

/// The display mode actually usable: boxes without a box size fall back to crates.
EggDisplay effectiveDisplay(EggPackaging p, [EggDisplay? preference]) {
  final pref = preference ?? p.display;
  return pref == EggDisplay.boxesCratesPieces && boxSize(p) == null ? EggDisplay.cratesPieces : pref;
}

/// "10,675 eggs"
String formatEggs(num totalEggs) {
  final n = _whole(totalEggs);
  return '${_int.format(n)} ${_plural(n, 'egg', 'eggs')}';
}

/// "25 boxes + 5 crates + 25 pcs" / "355 crates + 25 pcs" / "10,675 eggs".
String formatEggQuantity(num totalEggs, EggPackaging p, [EggDisplay? preference]) {
  final mode = effectiveDisplay(p, preference);
  final n = _whole(totalEggs);
  if (mode == EggDisplay.pieces) return formatEggs(n);
  final q = mode == EggDisplay.boxesCratesPieces ? toBoxesCratesPieces(n, p) : toCratesPieces(n, p);
  if (q.boxes == 0 && q.crates == 0) return formatEggs(n);
  return formatPackaged(q);
}

/// A packaged quantity exactly as entered: "2 boxes + 3 crates + 10 pcs". Empty -> "0 eggs".
String formatPackaged(PackagedQuantity q) {
  final parts = [
    if (q.boxes != 0) '${_int.format(q.boxes)} ${_plural(q.boxes, 'box', 'boxes')}',
    if (q.crates != 0) '${_int.format(q.crates)} ${_plural(q.crates, 'crate', 'crates')}',
    if (q.pieces != 0) '${_int.format(q.pieces)} pcs',
  ];
  return parts.isEmpty ? '0 eggs' : parts.join(' + ');
}

/// The secondary line under a total, or null when it would only repeat it.
String? eggQuantityHint(num totalEggs, EggPackaging p, [EggDisplay? preference]) {
  final mode = effectiveDisplay(p, preference);
  final n = _whole(totalEggs);
  if (mode == EggDisplay.pieces) {
    final alt = formatEggQuantity(n, p, boxSize(p) != null ? EggDisplay.boxesCratesPieces : EggDisplay.cratesPieces);
    return alt == formatEggs(n) ? null : alt;
  }
  final main = formatEggQuantity(n, p, mode);
  return main == formatEggs(n) ? null : formatEggs(n);
}

/// " (≈ 20 boxes)"-style suffix: " · ≈ 2 boxes + 3 crates" on a farm that shows
/// boxes, "" on every other farm (reports' eggsHint).
String eggBoxesHint(num? n, EggPackaging p) {
  if (n == null || boxSize(p) == null || p.display == EggDisplay.cratesPieces) return '';
  return ' · ≈ ${formatEggQuantity(n, p, EggDisplay.boxesCratesPieces)}';
}

/// useEggBoxesSuffix: " (≈ 20 boxes)" after an egg figure on a farm that
/// shows boxes (or shows eggs only); "" everywhere else. Display only.
String eggBoxesSuffix(num? eggs, EggPackaging p) {
  if (eggs == null || !eggs.isFinite || boxSize(p) == null || p.display == EggDisplay.cratesPieces) return '';
  return ' (≈ ${formatEggQuantity(eggs.truncate(), p, EggDisplay.boxesCratesPieces)})';
}

/// EggBoxesHint: the "≈ 20 boxes" line under an egg figure, or null.
String? eggBoxesLine(num? eggs, EggPackaging p) {
  if (eggs == null || !eggs.isFinite || boxSize(p) == null || p.display == EggDisplay.cratesPieces) return null;
  return '≈ ${formatEggQuantity(eggs.truncate(), p, EggDisplay.boxesCratesPieces)}';
}

// ------------------------------------------------------------ pricing (394)

/// The box price a line uses: its own, else crates per box × the crate price.
num effectiveBoxPrice(num pricePerCrate, num? pricePerBox, EggPackaging p) => pricePerBox ?? pricePerCrate * (boxSize(p) ?? 0);

/// The piece price a line uses: its own, else the crate price over the crate.
num effectivePiecePrice(num pricePerCrate, num? pricePerPiece, EggPackaging p) => pricePerPiece ?? pricePerCrate / _epc(p);

/// What a packaged egg line comes to (fnpoultry_eggpackagedamount), rounded once to the cent.
num packagedLineAmount(PackagedQuantity q, {required num pricePerCrate, num? pricePerBox, num? pricePerPiece, required EggPackaging p}) {
  final b = q.boxes < 0 ? 0 : q.boxes, c = q.crates < 0 ? 0 : q.crates, pc = q.pieces < 0 ? 0 : q.pieces;
  final amount = b * effectiveBoxPrice(pricePerCrate, pricePerBox, p) + c * pricePerCrate + pc * effectivePiecePrice(pricePerCrate, pricePerPiece, p);
  return (amount * 100 + 1e-9).round() / 100;
}

// ------------------------------------------------------------ posted lines (394)

/// A posted line's egg quantity: as entered (with ITS conversion) when the
/// line carries packaging, else a derived equivalent in today's packaging.
({String text, int eggs, bool asEntered}) postedLineQuantity(Map l, EggPackaging today) {
  final eggs = _whole(l['quantity']);
  if (l['crates'] != null) {
    return (
      text: formatPackaged(PackagedQuantity(boxes: _whole(l['boxes']), crates: _whole(l['crates']), pieces: _whole(l['pieces']))),
      eggs: eggs,
      asEntered: true,
    );
  }
  return (
    text: formatEggQuantity(eggs, today, today.display == EggDisplay.pieces ? EggDisplay.cratesPieces : today.display),
    eggs: eggs,
    asEntered: false,
  );
}

/// "1 box = 14 crates × 30 = 420 eggs", or null when the line had no boxes.
String? postedLineConversion(Map l) {
  final boxes = _whole(l['boxes']), cpb = _whole(l['cratesPerBox']);
  if (boxes == 0 || cpb == 0) return null;
  final epc = tIntOrNull(l['eggsPerCrate']) ?? 30;
  return '1 box = $cpb crates × $epc = ${_int.format(cpb * epc)} eggs';
}

// ------------------------------------------------------------ the active farm's packaging

/// The stored box configuration (use-egg-packaging.ts BoxConfig), per farm.
class _BoxConfig {
  const _BoxConfig({this.farmId, this.enableBoxes = false, this.cratesPerBox, this.display = EggDisplay.cratesPieces, this.entry = SaleEntryUnit.crates, this.version = 1});
  final String? farmId;
  final bool enableBoxes;
  final int? cratesPerBox;
  final EggDisplay display;
  final SaleEntryUnit entry;
  final int version;
}

_BoxConfig _current = const _BoxConfig();

/// Applies a farm's settings (GET .../packaging) right away.
void applyEggPackaging(String farmId, Map s) {
  final cpb = tIntOrNull(s['cratesPerBox']);
  _current = _BoxConfig(
    farmId: farmId,
    enableBoxes: s['enableBoxes'] == true && (cpb ?? 0) >= 1,
    cratesPerBox: cpb,
    display: eggDisplayOf(s['eggDisplay']),
    entry: saleEntryOf(s['saleEntryUnit']),
    version: tIntOrNull(s['packagingVersion']) ?? 1,
  );
}

/// Back to "boxes off" (switching company, tests).
void resetEggPackaging() => _current = const _BoxConfig();

/// The active farm's packaging now, composed with the live eggs per crate.
/// Another company's stored config is never used for [farmId].
EggPackaging eggPackagingFor(String? farmId) {
  final c = _current.farmId != null && _current.farmId == farmId ? _current : const _BoxConfig();
  final on = c.enableBoxes && (c.cratesPerBox ?? 0) >= 1;
  return EggPackaging(
    eggsPerCrate: eggsPerCrate,
    enableBoxes: on,
    cratesPerBox: on ? c.cratesPerBox : null,
    display: c.display == EggDisplay.boxesCratesPieces && !on ? EggDisplay.cratesPieces : c.display,
    saleEntryUnit: on ? c.entry : SaleEntryUnit.crates,
    version: c.version,
  );
}

/// The packaging of the farm loaded last (for helpers outside a screen).
EggPackaging get currentEggPackaging => eggPackagingFor(_current.farmId);

/// EggPackagingLoader: GET /api/Poultry/egg-sorting/packaging. Before 393 or
/// offline the farm stays on "boxes off".
Future<EggPackaging> loadEggPackaging(Session session, Company company) async {
  if (company.type != CompanyType.poultry) return defaultEggPackaging;
  if (_current.farmId != company.farmId) _current = _BoxConfig(farmId: company.farmId);
  try {
    final res = await session.farmClient.get('/api/Poultry/egg-sorting/packaging', query: {'farmId': company.farmId});
    if (res is Map) applyEggPackaging(company.farmId, res);
  } on ApiException {
    // Keep "boxes off".
  }
  return eggPackagingFor(company.farmId);
}

/// The settings screen's raw answer, for its form (stored values included).
Future<Map?> fetchEggPackagingSettings(Session session, Company company) async {
  final res = await session.farmClient.get('/api/Poultry/egg-sorting/packaging', query: {'farmId': company.farmId});
  return res is Map ? res : null;
}

String eggDisplayText(EggDisplay d) => switch (d) {
      EggDisplay.boxesCratesPieces => 'Boxes, crates & pieces',
      EggDisplay.cratesPieces => 'Crates & pieces',
      EggDisplay.pieces => 'Total eggs (packaging as a hint)',
    };

