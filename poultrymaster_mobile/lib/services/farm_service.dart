import '../core/api_client.dart';
import '../core/config.dart';
import '../core/json.dart';

/// Generic CRUD against the Farm API. Every endpoint follows the same
/// convention: list/detail take userId+farmId query params, create/update
/// bodies carry them, delete takes them as query params.
class FarmService {
  static final _api = ApiClient.instance;
  static String get _base => AppConfig.farmApiBaseUrl;

  static Map<String, dynamic> get _ctx {
    final s = _api.session;
    return {'userId': s?.userId ?? '', 'farmId': s?.farmId ?? ''};
  }

  static Future<List<Map<String, dynamic>>> list(String endpoint) async {
    final data = await _api.request('GET', '$_base/api/$endpoint', query: _ctx);
    if (data is List) return data.whereType<Map<String, dynamic>>().toList();
    if (data is Map<String, dynamic>) {
      final inner = pick(data, ['data', 'items', 'result', 'response']);
      if (inner is List) return inner.whereType<Map<String, dynamic>>().toList();
    }
    return [];
  }

  static Future<void> create(String endpoint, Map<String, dynamic> body) =>
      _api.request('POST', '$_base/api/$endpoint', body: {...body, ..._ctx});

  static Future<void> update(String endpoint, Object id, Map<String, dynamic> body) =>
      _api.request('PUT', '$_base/api/$endpoint/$id', body: {...body, ..._ctx});

  static Future<void> delete(String endpoint, Object id) =>
      _api.request('DELETE', '$_base/api/$endpoint/$id', query: _ctx);

  static Future<Map<String, dynamic>> dashboardSummary() async {
    final data = await _api.request('GET', '$_base/api/Dashboard/Summary',
        query: {'farmId': _ctx['farmId']});
    return data is Map<String, dynamic> ? data : {};
  }
}
