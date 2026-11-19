// Hotel Capital Investments/Assets in the shape the asset register works with:
// `lib/hotel/capital-assets-view.ts`. Every call reads or writes /api/Hotel
// (migration 322) and turns its rows into the Restaurant's names, so the
// register and its panels run on AssetRail.hotel without a Hotel branch of
// their own.
//
// Differences from the Restaurant API, handled here as the web does:
//   * a Hotel asset starts as Draft and needs an explicit Activate, so create
//     and update call it when a Draft asset has an in-service date;
//   * Hotel update replaces every field, so it merges onto the current asset;
//   * the summary has no "added this period" or "amount owed": they are worked
//     out from the asset list (this calendar month);
//   * Hotel has no default cash account: money paid now must say where from.

import '../../../api/api_client.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;

List<Map> _rows(Object? r) => [for (final x in (r is List ? r : const [])) if (x is Map) x];
String _day(Object? d) {
  final s = tStr(d);
  return s.length >= 10 ? s.substring(0, 10) : s;
}

/// toView.
Map hotelAssetView(Map a, {int costs = 0, int deps = 0}) {
  final total = tNum(a['totalCapitalizedCost']), residual = tNum(a['residualValue']), life = tNum(a['usefulLifeMonths']);
  final depreciable = total - residual > 0 ? total - residual : 0;
  final id = a['hotelCapitalAssetId'];
  final remaining = tNum(a['currentBookValue']) - residual;
  return {
    'capitalAssetId': id,
    'assetNumber': tStr(a['assetNumber']).isNotEmpty ? a['assetNumber'] : '#${tStr(id)}',
    'assetName': a['assetName'],
    'assetCategoryId': a['hotelAssetCategoryId'],
    'categoryName': a['categoryName'],
    'description': null,
    'acquisitionDate': a['acquisitionDate'] ?? a['createdAt'],
    'inServiceDate': a['inServiceDate'],
    'location': a['location'],
    'serialNumber': a['serialNumber'],
    'supplierId': null,
    'supplierName': a['supplier'],
    'status': a['status'],
    'notes': a['notes'],
    'acquisitionCost': tNum(a['acquisitionCost']),
    'additionalCost': tNum(a['additionalCost']),
    'totalCapitalizedCost': total,
    'residualValue': residual,
    'depreciableAmount': depreciable,
    'usefulLifeMonths': life > 0 ? life : null,
    'monthlyDepreciation': life > 0 ? depreciable / life : null,
    'accumulatedDepreciation': tNum(a['accumulatedDepreciation']),
    'currentBookValue': tNum(a['currentBookValue']),
    'remainingDepreciable': remaining > 0 ? remaining : 0,
    'isFullyDepreciated': tStr(a['status']) == 'FullyDepreciated',
    'costEntries': costs,
    'depreciationEntries': deps,
    'amountOwed': 0,
    'disposalDate': a['disposalDate'],
    'disposalProceeds': null,
    'disposalNotes': null,
    'createdBy': a['createdBy'],
    'createdAt': a['createdAt'],
    'updatedAt': a['updatedAt'],
    'reversedBy': a['reversedBy'],
    'reversedAt': a['reversedAt'],
    'reversalReason': a['reversedReason'],
  };
}

Map hotelCostView(int assetId, Map c) => {
      'assetCostId': c['hotelCapitalAssetCostId'],
      'capitalAssetId': assetId,
      'costDate': c['costDate'] ?? c['createdAt'],
      'description': c['description'],
      'amount': tNum(c['amount']),
      'sourceType': c['sourceType'],
      'amountPaid': 0,
      'balance': 0,
      'status': c['status'],
      'createdAt': c['createdAt'],
    };

/// depView: the period ends on the last day of its month.
Map hotelDepreciationView(Map d) {
  final start = DateTime.tryParse(_day(d['periodStart']));
  String two(int n) => n.toString().padLeft(2, '0');
  final end = start == null ? null : DateTime(start.year, start.month + 1, 0);
  return {
    'assetDepreciationId': d['hotelAssetDepreciationId'],
    'capitalAssetId': d['hotelCapitalAssetId'],
    'assetName': d['assetName'],
    'periodStart': _day(d['periodStart']),
    'periodEnd': end == null ? '' : '${end.year}-${two(end.month)}-${two(end.day)}',
    'amount': tNum(d['amount']),
    'sourceType': d['sourceType'],
    'status': d['status'],
    'accumulatedAfter': d['accumulatedAfter'],
    'bookValueAfter': d['bookValueAfter'],
    'createdAt': d['createdAt'],
    'reversalReason': d['reason'],
  };
}

/// The Hotel calls behind the register.
class HotelAssetApi {
  HotelAssetApi(this.session, this.company);
  final Session session;
  final Company company;
  ApiClient get _api => session.farmClient;
  String get _f => company.farmId;
  Map<String, String> get _q => {'farmId': _f};

  Future<List<Map>> _raw() async => _rows(await _api.get('/api/Hotel/assets', query: _q));
  Future<List<Map>> _soft(Future<Object?> f) async {
    try {
      return _rows(await f);
    } on ApiException {
      return const [];
    }
  }

  Future<List<Map>> assets() async => [for (final a in await _raw()) hotelAssetView(a)];

  Future<List<Map>> categories() async {
    final r = await Future.wait([_api.get('/api/Hotel/assets/categories', query: _q), _soft(_api.get('/api/Hotel/assets', query: _q))]);
    final assets = r[1] as List<Map>;
    return [
      for (final c in _rows(r[0]))
        {
          'assetCategoryId': c['hotelAssetCategoryId'],
          'categoryName': c['categoryName'],
          'defaultUsefulLifeMonths': c['defaultUsefulLifeMonths'],
          'sortOrder': c['sortOrder'],
          'isActive': c['isActive'],
          'assetCount': assets.where((a) => tStr(a['hotelAssetCategoryId']) == tStr(c['hotelAssetCategoryId']) && tStr(a['status']) != 'Reversed').length,
        },
    ];
  }

  Future<Map> summary() async {
    final r = await Future.wait([_api.get('/api/Hotel/assets/summary', query: _q), _raw()]);
    final s = r[0] is Map ? r[0] as Map : const {};
    final assets = r[1] as List<Map>;
    final month = DateTime.now().toUtc().toIso8601String().substring(0, 7);
    final added = [for (final a in assets) if (tStr(a['status']) != 'Reversed' && _day(a['acquisitionDate'] ?? a['createdAt']).startsWith(month)) a];
    return {
      'totalAssets': tNum(s['totalAssets']),
      'activeAssets': tNum(s['activeAssets']),
      'draftAssets': tNum(s['draftAssets']),
      'disposedAssets': assets.where((a) => tStr(a['status']) == 'Disposed').length,
      'fullyDepreciated': assets.where((a) => tStr(a['status']) == 'FullyDepreciated').length,
      'totalAssetCost': tNum(s['totalAssetCost']),
      'accumulatedDepreciation': tNum(s['accumulatedDepreciation']),
      'currentBookValue': tNum(s['currentBookValue']),
      'addedInPeriod': added.fold<num>(0, (t, a) => t + tNum(a['totalCapitalizedCost'])),
      'addedCount': added.length,
      'amountOwed': 0,
    };
  }

  /// loadHotelCashAccounts → the Restaurant CashAccount names; active only.
  Future<List<Map>> cashAccounts() async => [
        for (final a in await _soft(_api.get('/api/Hotel/finance/cash-accounts', query: _q)))
          if ((a['isActive'] ?? a['isactive']) != false)
            {
              'cashAccountId': a['hotelCashAccountId'] ?? a['hotelcashaccountid'],
              'name': a['accountName'] ?? a['accountname'],
              'currentBalance': tNum(a['currentBalance'] ?? a['currentbalance']),
              'isActive': true,
            },
      ];

  /// One asset with its cost and depreciation history.
  Future<Map?> get(int id) async {
    final r = await Future.wait([
      _api.get('/api/Hotel/assets/$id', query: _q),
      _soft(_api.get('/api/Hotel/assets/$id/costs', query: _q)),
      _soft(_api.get('/api/Hotel/asset-depreciation', query: {..._q, 'assetId': '$id'})),
    ]);
    if (r[0] is! Map) throw ApiException(404, 'Asset not found');
    final costs = r[1] as List<Map>, deps = r[2] as List<Map>;
    return {
      ...hotelAssetView(r[0] as Map, costs: costs.length, deps: deps.where((d) => tStr(d['status']) != 'Reversed').length),
      'costs': [for (final c in costs) hotelCostView(id, c)],
      'depreciation': [for (final d in deps) hotelDepreciationView(d)],
    };
  }

  /// requirePaidFrom: the refusal, or null.
  static String? paidFromError(num? amountPaid, num? amount, int? cashAccountId) {
    final paidNow = amountPaid ?? amount ?? 0;
    return paidNow > 0 && cashAccountId == null ? 'Choose the cash account this was paid from (Paid from), or set Amount paid now to 0.' : null;
  }

  Future<void> _activateIfInService(int id, String? inServiceDate) async {
    if (inServiceDate == null || inServiceDate.isEmpty) return;
    final a = await _api.get('/api/Hotel/assets/$id', query: _q);
    if (a is Map && tStr(a['status']) == 'Draft') await _api.post('/api/Hotel/assets/$id/activate', query: _q);
  }

  /// [b] is the register's New investment body.
  Future<void> create(Map<String, Object?> b) async {
    final err = paidFromError(b['amountPaid'] as num?, b['amount'] as num?, b['cashAccountId'] as int?);
    if (err != null) throw ApiException(400, err);
    final notes = [b['description'], b['notes']].where((x) => x != null && tStr(x).isNotEmpty).join('\n');
    final res = await _api.post('/api/Hotel/assets', body: {
      'farmId': _f,
      'assetName': b['assetName'],
      'hotelAssetCategoryId': b['assetCategoryId'],
      'acquisitionDate': b['acquisitionDate'],
      'inServiceDate': b['inServiceDate'],
      'residualValue': tNum(b['residualValue']),
      'usefulLifeMonths': b['usefulLifeMonths'],
      'amount': b['amount'],
      'supplier': b['supplier'],
      'location': b['location'],
      'serialNumber': b['serialNumber'],
      'notes': notes.isEmpty ? null : notes,
      'hotelCashAccountId': b['cashAccountId'],
      'amountPaid': b['amountPaid'],
      'dueDate': b['dueDate'],
    });
    final id = tIntOrNull(res is Map ? res['hotelCapitalAssetId'] : null);
    if (id != null) await _activateIfInService(id, b['inServiceDate'] as String?);
  }

  /// [b] is the Edit body; only the financial fields it sets are taken.
  Future<void> update(int id, Map<String, Object?> b) async {
    final cur = await _api.get('/api/Hotel/assets/$id', query: _q);
    if (cur is! Map) throw ApiException(404, 'Asset not found');
    final fin = b['setFinancials'] == true;
    final inService = fin ? b['inServiceDate'] : cur['inServiceDate'];
    await _api.put('/api/Hotel/assets/$id', body: {
      'farmId': _f,
      'assetName': b['assetName'] ?? cur['assetName'],
      'hotelAssetCategoryId': b['assetCategoryId'],
      'acquisitionDate': cur['acquisitionDate'],
      'inServiceDate': inService,
      'residualValue': tNum(fin ? b['residualValue'] : cur['residualValue']),
      'usefulLifeMonths': tNum(fin ? b['usefulLifeMonths'] : cur['usefulLifeMonths']),
      'supplier': cur['supplier'],
      'location': b['location'],
      'serialNumber': b['serialNumber'],
      'notes': b['notes'],
    });
    await _activateIfInService(id, inService == null ? null : tStr(inService));
  }

  Future<void> addCost(int id, Map<String, Object?> b) async {
    final err = paidFromError(b['amountPaid'] as num?, b['amount'] as num?, b['cashAccountId'] as int?);
    if (err != null) throw ApiException(400, err);
    await _api.post('/api/Hotel/assets/$id/costs', body: {
      'farmId': _f,
      'amount': b['amount'],
      'description': b['description'],
      'costDate': b['costDate'],
      'hotelCashAccountId': b['cashAccountId'],
      'amountPaid': b['amountPaid'],
      'dueDate': b['dueDate'],
    });
  }

  Future<void> reverseCost(int assetId, int costId, String reason) =>
      _api.delete('/api/Hotel/assets/$assetId/costs/$costId', query: {..._q, if (reason.isNotEmpty) 'reason': reason});

  /// The Hotel keeps no proceeds: the date and the notes (as its reason) only.
  Future<void> dispose(int id, String? date, String? notes) =>
      _api.post('/api/Hotel/assets/$id/dispose', body: {'farmId': _f, 'disposalDate': date, 'reason': notes});

  Future<void> reverse(int id, String reason) => _api.post('/api/Hotel/assets/$id/reverse', body: {'farmId': _f, 'reason': reason});

  Future<Object?> generateDepreciation() => _api.post('/api/Hotel/asset-depreciation/generate', body: {'farmId': _f});

  Future<void> reverseDepreciation(int entryId, String reason) =>
      _api.post('/api/Hotel/asset-depreciation/$entryId/reverse', body: {'farmId': _f, 'reason': reason});
}
