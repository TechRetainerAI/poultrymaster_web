import '../models/company.dart';
import '../state/token_store.dart';
import 'api_client.dart';

class CompaniesApi {
  CompaniesApi(this._client, this._tokens);

  final ApiClient _client;
  final TokenStore _tokens;

  /// GET /api/Companies/mine
  Future<List<Company>> mine() async {
    final res = await _client.get('/api/Companies/mine');
    if (res is! List) return const [];
    return res
        .whereType<Map>()
        .map((e) => Company.fromJson(Map<String, dynamic>.from(e)))
        .where((c) => c.farmId.isNotEmpty)
        .toList();
  }

  /// POST /api/Companies/switch
  ///
  /// This is not a client-side selection: the server mints a NEW access token
  /// carrying the farm claim. Every farm-API call afterwards is authorised
  /// against whichever company this returned, so the new token must replace the
  /// stored one or the app will keep reading the previous company's data.
  Future<Company> switchTo(Company company) async {
    final res = await _client.post('/api/Companies/switch', body: {
      'farmId': company.farmId,
    });

    if (res is Map) {
      final map = Map<String, dynamic>.from(res);
      final payload =
          map['response'] is Map ? Map<String, dynamic>.from(map['response'] as Map) : map;

      final access = _tokenOf(payload['accessToken']);
      final refresh = _tokenOf(payload['refreshToken']);
      if (access != null) {
        await _tokens.saveTokens(access: access, refresh: refresh);
      }
      await _tokens.saveFarm(
        farmId: payload['farmId']?.toString() ?? company.farmId,
        farmName: payload['farmName']?.toString() ?? company.name,
      );
    } else {
      await _tokens.saveFarm(farmId: company.farmId, farmName: company.name);
    }
    return company;
  }

  static String? _tokenOf(dynamic node) {
    if (node is String) return node.isEmpty ? null : node;
    if (node is Map && node['token'] is String) {
      final t = node['token'] as String;
      return t.isEmpty ? null : t;
    }
    return null;
  }
}
