import '../api/api_client.dart';
import '../models/company.dart';
import '../state/session.dart';
import 'lookup_loader.dart';
import 'page_spec.dart';

/// Create, update and delete for a list page.
///
/// The endpoint is the page's own collection path: POST to it creates,
/// PUT/DELETE to `{path}/{id}` change one record. farmId is always included —
/// every write endpoint in this API is farm-scoped, and omitting it is the
/// most common cause of a 400.
class RecordApi {
  const RecordApi(this.session, this.spec, this.company);

  final Session session;
  final PageSpec spec;
  final Company company;

  ApiClient get _client =>
      spec.source == 'login' ? session.loginClient : session.farmClient;

  String get _path => (spec.writePath ?? spec.path).replaceAll('{farmId}', company.farmId);

  /// Scope keys that are never the record's own id.
  static const _foreign = {
    'farmid', 'userid', 'companyid', 'tenantid',
    'createdbyid', 'updatedbyid', 'modifiedbyid',
  };

  static bool _usable(Object? v) =>
      v != null && '$v'.isNotEmpty && '$v' != '0';

  /// The record's own id, whatever the endpoint calls it.
  ///
  /// Taking the first key ending in `Id` is wrong: a production log carries
  /// `flockId` before its own `productionId`, and deleting by the flock id
  /// would hit the wrong record. So an exact `id` wins, then the key named
  /// after this page, and only then any remaining candidate.
  static Object? idOf(Map<String, dynamic> row, {String? hint}) {
    for (final k in row.keys) {
      if (k.toLowerCase() == 'id' && _usable(row[k])) return row[k];
    }

    final candidates = row.keys.where((k) {
      final lk = k.toLowerCase();
      return lk.endsWith('id') && !_foreign.contains(lk) && _usable(row[k]);
    }).toList();
    if (candidates.isEmpty) return null;

    final words = (hint ?? '')
        .toLowerCase()
        .split(RegExp(r'[^a-z]+'))
        .where((w) => w.length >= 4);
    for (final k in candidates) {
      final stem = k.substring(0, k.length - 2).toLowerCase();
      if (stem.length < 3) continue;
      for (final w in words) {
        if (w.startsWith(stem) || stem.startsWith(w)) return row[k];
      }
    }
    return row[candidates.first];
  }

  /// The id of [row] resolved against this page, so the page name can break
  /// ties between an own id and a foreign key.
  Object? idIn(Map<String, dynamic> row) =>
      idOf(row, hint: '${spec.key} ${spec.title}');

  Map<String, dynamic> _withFarm(Map<String, dynamic> body) => {
        ...body,
        if (spec.needsFarmId) 'farmId': company.farmId,
        if (spec.needsUserId) 'userId': session.tokens.userId ?? '',
      };

  /// The page's rows, fetched as its list screen fetches them (same farm,
  /// user and company-type parameters).
  Future<List<Map<String, dynamic>>> list() async {
    final query = <String, dynamic>{...spec.query};
    if (spec.needsFarmId && !spec.path.contains('{farmId}')) {
      query[spec.farmIdParam] = company.farmId;
    }
    if (spec.needsUserId) query['userId'] = session.tokens.userId ?? '';
    if (spec.needsCompanyType) query['type'] = company.type.wire;
    final res = await _client.get(spec.path.replaceAll('{farmId}', company.farmId), query: query);
    dynamic node = res;
    if (node is Map && spec.itemsAt != null && node[spec.itemsAt] is List) node = node[spec.itemsAt];
    final rows = node is List ? node : LookupLoader.rowsIn(node);
    return [for (final r in rows) if (r is Map) Map<String, dynamic>.from(r)];
  }

  Future<void> create(Map<String, dynamic> body) =>
      _client.post(_path, body: _withFarm(body));

  Future<void> update(Object id, Map<String, dynamic> body) =>
      _client.put('$_path/$id', body: _withFarm(body));

  /// Endpoints that need userId on writes check it on DELETE too (the web
  /// sends it for flocks and houses), so it goes in the query here.
  Future<void> remove(Object id) => _client.delete(
      '$_path/$id?farmId=${Uri.encodeComponent(company.farmId)}'
      '${spec.needsUserId ? '&userId=${Uri.encodeComponent(session.tokens.userId ?? '')}' : ''}');
}
