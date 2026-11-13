// Selling birds per bird or per kg of live weight (migration 401), as the
// web's lib/poultry/bird-pricing.ts. Pure.
//
// The quantity of a bird line is ALWAYS the number of birds -- the flock's
// bird position subtracts it. Per kg, the amount is live weight × price per kg
// and the per-bird price is amount / birds, which is what the database stores
// as the line's unit price so every older report still multiplies correctly.

import '../shared/business_dates.dart' show fmtNum;
import 'sales/sales_logic.dart' show byproductRole;

enum BirdPricingBasis { perBird, perKg }

class BirdPricing {
  const BirdPricing({this.basis = BirdPricingBasis.perBird, this.liveWeightKg, this.pricePerKg});

  final BirdPricingBasis basis;

  /// Total live weight of the birds on the line; optional per bird.
  final num? liveWeightKg;

  /// Per kg only.
  final num? pricePerKg;

  bool get perKg => basis == BirdPricingBasis.perKg;

  BirdPricing copyWith({BirdPricingBasis? basis, num? Function()? liveWeightKg, num? Function()? pricePerKg}) => BirdPricing(
        basis: basis ?? this.basis,
        liveWeightKg: liveWeightKg != null ? liveWeightKg() : this.liveWeightKg,
        pricePerKg: pricePerKg != null ? pricePerKg() : this.pricePerKg,
      );

  @override
  bool operator ==(Object other) =>
      other is BirdPricing && other.basis == basis && other.liveWeightKg == liveWeightKg && other.pricePerKg == pricePerKg;

  @override
  int get hashCode => Object.hash(basis, liveWeightKg, pricePerKg);

  @override
  String toString() => 'BirdPricing($basis, $liveWeightKg kg, $pricePerKg / kg)';
}

const emptyBirdPricing = BirdPricing();

/// Is this product a sale of live birds? The database's rule
/// (fnpoultrysale_isbirdsale, 374 + 401) exactly: bird / chick / cockerel /
/// broiler -- but not "Broiler feed" -- never an egg, never a byproduct.
bool isLiveBirdProduct(Object? product) {
  final p = (product?.toString() ?? '').toLowerCase();
  if (p.isEmpty || p.contains('egg') || byproductRole(product) != null) return false;
  if (p == 'birds' || p.contains('bird') || p.contains('chick') || p.contains('cockerel')) return true;
  return p.contains('broiler') && !RegExp('(feed|mash|starter|grower|finisher|concentrate)').hasMatch(p);
}

/// The web's round2: Math.round((n + EPSILON) × 100) / 100.
num _round2(num n) => ((n + 2.220446049250313e-16) * 100 + 0.5).floorToDouble() / 100;

/// The line amount: per kg, kg × price per kg; per bird, birds × unit price.
num birdLineAmount(num birds, num unitPrice, BirdPricing pricing) {
  if (pricing.perKg) return _round2((pricing.liveWeightKg ?? 0) * (pricing.pricePerKg ?? 0));
  return _round2(birds * unitPrice);
}

/// The per-bird price stored for a per-kg line. 0 with no birds.
num perBirdPrice(num amount, num birds) => birds > 0 ? _round2(amount / birds) : 0;

/// Average live weight per bird, or null when unknown.
double? avgKgPerBird(num birds, num? liveWeightKg) =>
    birds > 0 && liveWeightKg != null && liveWeightKg > 0 ? liveWeightKg / birds : null;

/// Does the line carry anything the database's bird branch should see?
bool hasBirdPricing(BirdPricing? p) => p != null && (p.perKg || (p.liveWeightKg != null && p.liveWeightKg! > 0));

String _js(num n) => n == n.roundToDouble() ? n.toInt().toString() : '$n';

/// What is wrong with the line, or null. Same limits as the database.
String? birdPricingProblem(num birds, BirdPricing p) {
  if (!hasBirdPricing(p)) return null;
  if (!(birds > 0) || birds != birds.roundToDouble()) return 'Enter the number of birds as a whole number.';
  final kg = p.liveWeightKg;
  if (kg != null && !(kg > 0)) return 'The live weight must be above 0 kg.';
  if (kg != null && kg / birds > 20) return '${_js(kg)} kg for ${_js(birds)} birds is over 20 kg a bird. Check the weight.';
  if (p.perKg) {
    if (kg == null) return 'A sale priced per kg needs the total live weight in kg.';
    if (p.pricePerKg == null || !(p.pricePerKg! > 0)) return 'Enter the price per kg.';
  }
  return null;
}

/// The fields a sale line sends for the database's bird branch (empty when none).
Map<String, dynamic> birdPricingPayload(BirdPricing? p, {bool amountOverridden = false}) {
  if (p == null || !hasBirdPricing(p)) return const {};
  return {
    'pricingBasis': p.perKg ? 'PerKg' : 'PerBird',
    'liveWeightKg': p.liveWeightKg,
    'pricePerKg': p.perKg ? p.pricePerKg : null,
    if (amountOverridden) 'amountOverridden': true,
  };
}

num? _n(Object? v) => v == null ? null : (v is num ? v : num.tryParse('$v'));

/// A saved line back into the form's shape (Correct Sale).
BirdPricing birdPricingFromLine(Map? l) {
  final basis = l?['pricingBasis'];
  if (basis == null || '$basis'.isEmpty) return emptyBirdPricing;
  return BirdPricing(
    basis: basis == 'PerKg' ? BirdPricingBasis.perKg : BirdPricingBasis.perBird,
    liveWeightKg: _n(l!['liveWeightKg']),
    pricePerKg: _n(l['pricePerKg']),
  );
}

/// One line of text for a saved bird line, e.g. "250 kg at 30.00 / kg · 2.50 kg a bird".
String? birdLineNote(Map l) {
  final basis = l['pricingBasis'];
  final kg = _n(l['liveWeightKg']);
  if (basis == null || '$basis'.isEmpty || kg == null) return null;
  final avg = avgKgPerBird(_n(l['quantity']) ?? 0, kg);
  final ppk = _n(l['pricePerKg']);
  final parts = [
    basis == 'PerKg' && ppk != null ? '${fmtNum(kg, 3)} kg at ${ppk.toStringAsFixed(2)} / kg' : '${fmtNum(kg, 3)} kg live weight',
    if (avg != null) '${avg.toStringAsFixed(2)} kg a bird',
  ];
  return parts.join(' · ');
}
