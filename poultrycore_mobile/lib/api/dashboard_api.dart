import '../models/company.dart';
import 'api_client.dart';

/// A single headline figure on a dashboard.
class Metric {
  Metric(this.label, this.value, {this.isMoney = false, this.hint});
  final String label;
  final Object? value;
  final bool isMoney;

  /// The small line under the figure, as the web shows ("Total eggs produced").
  final String? hint;
}

class DashboardData {
  DashboardData({required this.metrics, this.raw, this.note});
  final List<Metric> metrics;
  final Map<String, dynamic>? raw;

  /// Set when the module has no dashboard endpoint and we fell back to
  /// something else, so the UI can say so rather than imply completeness.
  final String? note;

  bool get isEmpty => metrics.isEmpty;
}

/// Reads the per-company-type summary endpoints.
///
/// There is no single dashboard API — each module grew its own, with different
/// shapes and even different casing for the farmId parameter. This class is the
/// one place that inconsistency is absorbed.
class DashboardApi {
  DashboardApi(this._farm);
  final ApiClient _farm;

  Future<DashboardData> load(Company company) async {
    switch (company.type) {
      case CompanyType.poultry:
        return _poultry(company.farmId);
      case CompanyType.water:
        return _simple('/api/Water/dashboard/summary', company.farmId);
      case CompanyType.hotel:
        return _simple('/api/Hotel/dashboard/summary', company.farmId);
      case CompanyType.generic:
        return _generic(company.farmId);
      case CompanyType.restaurant:
        return _restaurant(company.farmId);
      case CompanyType.unknown:
        return DashboardData(
          metrics: const [],
          note: 'This company type is not recognised by the app yet.',
        );
    }
  }

  // Poultry is the one module that takes PascalCase query parameters.
  Future<DashboardData> _poultry(String farmId) async {
    final res = await _farm
        .get('/api/poultry/reports/farm-summary', query: {'FarmId': farmId});
    // Field names verified against a live dev response, not guessed.
    return _fromMap(res, preferred: const [
      'totalEggsProduced',
      'saleableEggs',
      'brokenRejectedEggs',
      'activeFlocks',
      'activeBirds',
      'deaths',
      'feedConsumedKg',
      'salesRevenue',
    ]);
  }

  Future<DashboardData> _simple(String path, String farmId) async {
    final res = await _farm.get(path, query: {'farmId': farmId});
    return _fromMap(res);
  }

  Future<DashboardData> _generic(String farmId) async {
    final res = await _farm.get('/api/generic-company/$farmId/reports/dashboard');
    return _fromMap(res);
  }

  /// Restaurant never grew a dashboard endpoint — the web builds its overview
  /// from the reports set — so today's sales stands in for one.
  Future<DashboardData> _restaurant(String farmId) async {
    final res = await _farm.get('/api/Restaurant/reports/daily-sales',
        query: {'farmId': farmId});
    final data = _fromMap(res);
    return DashboardData(
      metrics: data.metrics,
      raw: data.raw,
      note: "Restaurant has no dashboard endpoint; showing today's sales.",
    );
  }

  /// Turns an arbitrary summary object into headline metrics.
  ///
  /// The shapes differ per module and are not documented in swagger (most of
  /// these endpoints declare only "200 Success"), so rather than hard-code a
  /// model per module we surface the scalar fields and let the UI label them.
  DashboardData _fromMap(dynamic res, {List<String> preferred = const []}) {
    Map<String, dynamic>? map;
    if (res is Map) {
      var current = Map<String, dynamic>.from(res);
      // Several endpoints wrap the payload.
      for (final key in ['data', 'result', 'summary', 'response']) {
        final inner = current[key];
        if (inner is Map) {
          current = Map<String, dynamic>.from(inner);
          break;
        }
      }
      map = current;
    } else if (res is List && res.isNotEmpty && res.first is Map) {
      map = Map<String, dynamic>.from(res.first as Map);
    }
    if (map == null) return DashboardData(metrics: const []);

    final metrics = <Metric>[];
    void add(String key, dynamic value) {
      if (value == null || value is Map || value is List) return;
      if (value is bool) return;
      metrics.add(Metric(_humanise(key), value,
          isMoney: _looksMonetary(key), hint: _hintFor(key)));
    }

    for (final key in preferred) {
      if (map.containsKey(key)) add(key, map[key]);
    }
    for (final entry in map.entries) {
      if (preferred.contains(entry.key)) continue;
      if (metrics.length >= 12) break;
      add(entry.key, entry.value);
    }

    return DashboardData(metrics: metrics, raw: map);
  }

  /// Whether a field should be rendered as money.
  ///
  /// The earlier rule treated any key containing "total" as money, which showed
  /// "Total customers" as ₵0.00 — a count formatted as currency. Counting words
  /// now win outright, and "total" alone no longer implies money.
  static bool _looksMonetary(String key) {
    final k = key.toLowerCase();

    const counts = [
      'count', 'customers', 'products', 'items', 'orders', 'birds', 'eggs',
      'flocks', 'deaths', 'crates', 'staff', 'rooms', 'bookings', 'users',
      'quantity', 'qty', 'kg', 'litres', 'liters',
    ];
    for (final c in counts) {
      if (k.contains(c)) return false;
    }

    const money = [
      'amount', 'revenue', 'sales', 'expense', 'profit', 'cash', 'balance',
      'cost', 'price', 'value', 'payable', 'receivable', 'income', 'payment',
      'outstanding', 'net', 'gross', 'debt', 'loan',
    ];
    return money.any(k.contains);
  }

  /// Short descriptions matching the web's dashboard cards.
  static String? _hintFor(String key) {
    const hints = {
      'totalEggsProduced': 'Total eggs produced',
      'saleableEggs': 'Eggs fit for sale',
      'brokenRejectedEggs': 'Broken or rejected',
      'activeFlocks': 'Currently active flocks',
      'activeBirds': 'Birds currently on the farm',
      'deaths': 'Recorded mortality',
      'feedConsumedKg': 'Feed consumed (kg)',
      'salesRevenue': 'Revenue from sales',
      'expenses': 'Recorded expenses',
      'estimatedProfit': 'Revenue less expenses',
      'totalCustomers': 'Total registered customers',
      'totalProduction': 'Overall production count',
      'totalSales': 'All-time sales value',
      'thisMonthSales': 'Sales for current month',
      'averageSale': 'Average transaction value',
      'productionEfficiency': 'Overall efficiency rating',
    };
    return hints[key];
  }

  static String _humanise(String key) {
    final spaced = key.replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}');
    return spaced.isEmpty
        ? key
        : spaced[0].toUpperCase() + spaced.substring(1).toLowerCase();
  }
}
