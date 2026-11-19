import 'dart:math' as math;

/// Weigh-in arithmetic (migration 400), as the web's
/// `lib/poultry/weigh-in-stats.ts`. Weights are in grams throughout.
///
/// The server recomputes every figure from the weights it receives; this copy
/// only previews them while typing.
///
///   uniformity = % of sampled birds within ±10% of the sample average
///   CV         = sample standard deviation / average × 100 (needs 2+ birds)
enum WeightUnit { g, kg }

class WeighInStats {
  const WeighInStats({
    required this.sampleSize,
    required this.avgWeightG,
    required this.minWeightG,
    required this.maxWeightG,
    required this.uniformityPct,
    required this.cvPct,
  });
  final int sampleSize;
  final double avgWeightG;
  final double minWeightG;
  final double maxWeightG;
  final double uniformityPct;

  /// Null for a single bird: a spread needs two.
  final double? cvPct;
}

/// The web's `round`: Math.round((n + EPSILON) × 10^dp) / 10^dp, where
/// JavaScript's Math.round(x) is floor(x + 0.5).
double roundTo(num n, int dp) {
  final f = math.pow(10, dp);
  return ((n + 2.220446049250313e-16) * f + 0.5).floorToDouble() / f;
}

WeighInStats? computeWeighInStats(List<double> weightsG) {
  final w = weightsG.where((x) => x.isFinite).toList();
  final n = w.length;
  if (n == 0) return null;
  final mean = w.reduce((a, b) => a + b) / n;
  final within = w.where((x) => x >= mean * 0.9 && x <= mean * 1.1).length;
  final sd = n < 2 ? null : math.sqrt(w.fold<double>(0, (a, x) => a + (x - mean) * (x - mean)) / (n - 1));
  return WeighInStats(
    sampleSize: n,
    avgWeightG: roundTo(mean, 1),
    minWeightG: roundTo(w.reduce(math.min), 1),
    maxWeightG: roundTo(w.reduce(math.max), 1),
    uniformityPct: roundTo(100 * within / n, 1),
    cvPct: sd == null ? null : roundTo(100 * sd / mean, 2),
  );
}

class ParsedWeights {
  const ParsedWeights(this.weightsG, this.invalid);

  /// In grams, one per bird, rounded to 0.1 g.
  final List<double> weightsG;

  /// Pieces of the text that are not a usable weight, as typed.
  final List<String> invalid;
}

/// JavaScript's Number(token) for what a scale user types: a decimal or
/// integer, with an optional sign and exponent. Anything else is NaN.
double _jsNumber(String token) {
  if (!RegExp(r'^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$').hasMatch(token)) return double.nan;
  return double.parse(token);
}

/// Weights as a farm types them off a scale: separated by spaces, commas,
/// semicolons or new lines, in grams or kilograms. A decimal comma ("1,85")
/// is NOT supported (commas separate birds), so kg must use a point.
ParsedWeights parseWeights(String text, WeightUnit unit) {
  final weightsG = <double>[];
  final invalid = <String>[];
  for (final token in text.split(RegExp(r'[\s,;]+'))) {
    if (token.isEmpty) continue;
    final n = _jsNumber(token);
    final g = unit == WeightUnit.kg ? n * 1000 : n;
    if (!n.isFinite || g <= 0 || g > 20000) {
      invalid.add(token);
    } else {
      weightsG.add(roundTo(g, 1));
    }
  }
  return ParsedWeights(weightsG, invalid);
}

/// "934 g" under 1 kg, else "1.85 kg".
String formatWeight(num? g) {
  if (g == null || !g.isFinite) return '—';
  if (g.abs() < 1000) return '${_thousands(roundTo(g, 0).round())} g';
  return '${(g / 1000).toStringAsFixed(2)} kg';
}

String _thousands(int v) {
  final s = v.abs().toString();
  final b = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}
