import '../api/api_client.dart';
import '../design/ui/inputs.dart';
import '../models/company.dart';
import '../state/session.dart';
import 'lookup_sources.dart';

/// Fills a form's dropdowns from the same endpoints the web reads.
///
/// Options are cached per farm and path: a form with three flock-backed
/// selects, or two forms opened in a row, hits `/Flock` once. The web caches
/// flocks for the same reason.
class LookupLoader {
  LookupLoader(this.session, this.company);

  final Session session;
  final Company company;

  static final Map<String, List<AppSelectItem<String>>> _cache = {};
  static final Map<String, Future<List<AppSelectItem<String>>>> _inFlight = {};

  /// Drop everything. Not needed on a company switch — the cache key carries
  /// the farm id, so one company can never be served another's list — but
  /// useful on sign-out.
  static void clear() {
    _cache.clear();
    _inFlight.clear();
  }

  /// Options for `specKey.fieldName`, or null when the site has no list for it.
  ///
  /// [label], when given, words each option the way the web page does
  /// ("Truck 1 (Truck) — Inactive") instead of the source's label field.
  Future<List<AppSelectItem<String>>>? optionsFor(
    String slot, {
    String Function(Map row)? label,
  }) {
    ApiClient.addWriteListener(clear);
    final fixed = staticOptions[slot];
    if (fixed != null) {
      return Future.value([
        for (final pair in fixed)
          AppSelectItem(value: pair[0], label: pair.length > 1 ? pair[1] : pair[0]),
      ]);
    }

    final src = lookupSources[slot];
    if (src == null) return _discover(slot);

    final path = _api(src.path.replaceAll('{farmId}', company.farmId));
    final cacheKey =
        '${company.farmId}|$path|${src.value}|${src.label}|${label == null ? '' : identityHashCode(label)}';
    final done = _cache[cacheKey];
    if (done != null) return Future.value(done);
    return _inFlight.putIfAbsent(cacheKey, () async {
      try {
        final items = await _fetch(path, src, label);
        _cache[cacheKey] = items;
        return items;
      } finally {
        _inFlight.remove(cacheKey);
      }
    });
  }

  /// A foreign-key dropdown the generator could not place.
  ///
  /// Generation could only prove an endpoint two ways: dev returned rows
  /// carrying the id, or swagger declared a model that does. Endpoints with
  /// neither — no schema, and empty on the dev company — stayed unresolved
  /// even when they are perfectly good. On a real farm they hold data, so the
  /// same proof is available here at run time: fetch the candidate, and use
  /// it ONLY if its rows actually carry the id this field is asking for.
  /// Anything else is left unresolved rather than filled with a wrong list.
  Future<List<AppSelectItem<String>>>? _discover(String slot) {
    final field = slot.split('.').last;
    if (!field.endsWith('Id') || field.length < 4) return null;

    final entity = field.substring(0, field.length - 2);
    final bare = entity.replaceFirst(
        RegExp(r'^(poultry|water|hotel|restaurant|generic)', caseSensitive: false), '');
    final module = _moduleOf(field);

    // Rough, but these only ever PROPOSE: the fetch decides.
    final names = <String>{entity, bare}..removeWhere((s) => s.isEmpty);
    final paths = <String>[
      for (final n in names) ...[
        '/${_cap(n)}',
        '/${_cap(n)}s',
        if (module != null) '/$module/${_kebab(n)}s',
        if (module != null) '/$module/${_kebab(n)}',
      ],
    ];

    final cacheKey = '${company.farmId}|find|$slot';
    final done = _cache[cacheKey];
    if (done != null) return Future.value(done);

    return _inFlight.putIfAbsent(cacheKey, () async {
      try {
        for (final p in paths) {
          final items = await _probe(p, field);
          if (items.isNotEmpty) {
            _cache[cacheKey] = items;
            return items;
          }
        }
        // Remembered as "nothing found" so a form does not re-probe on
        // every rebuild; the field then reports itself unresolved as before.
        _cache[cacheKey] = const [];
        return const [];
      } finally {
        _inFlight.remove(cacheKey);
      }
    });
  }

  /// The module a prefixed id belongs to, so poultryProductId looks under
  /// /Poultry rather than guessing across every company type's endpoints.
  static String? _moduleOf(String field) {
    final f = field.toLowerCase();
    for (final m in ['poultry', 'water', 'hotel', 'restaurant']) {
      if (f.startsWith(m)) return _cap(m);
    }
    return null;
  }

  /// Every controller routes under /api, but the source table stores paths
  /// without it ("/Flock"). Nothing ever prepended it, so every lookup fetch
  /// hit /Flock and 404'd — which is why no dropdown has EVER filled, on any
  /// of the 95 original sources either. Normalised here so one fix covers
  /// them all.
  static String _api(String path) =>
      path.startsWith('/api/') ? path : '/api$path';

  /// Fetch a candidate and accept it only if its rows carry [idField].
  Future<List<AppSelectItem<String>>> _probe(String path, String idField) async {
    try {
      final res = await session.farmClient.get(_api(path), query: {
        'farmId': company.farmId,
        'userId': session.tokens.userId ?? '',
      });
      final rows = _rowsIn(res);
      if (rows.isEmpty) return const [];
      final first = rows.first;
      if (first is! Map) return const [];

      final idKey = first.keys.cast<String?>().firstWhere(
            (k) => k != null && k.toLowerCase() == idField.toLowerCase(),
            orElse: () => null,
          );
      if (idKey == null) return const [];   // wrong collection — say nothing

      final labelKey = _labelKeyIn(first, idKey);
      return _itemsFrom(rows, idKey, labelKey);
    } catch (_) {
      return const [];
    }
  }

  /// A field a person can read. Never an identifier: filling a dropdown with
  /// GUIDs looks like data but tells the user nothing.
  static String? _labelKeyIn(Map row, String idKey) {
    const preferred = [
      'name', 'title', 'accountname', 'customername', 'suppliername',
      'employeename', 'itemname', 'productname', 'batchname', 'housename',
      'fullname', 'firstname', 'description', 'code', 'roomnumber',
    ];
    bool ok(String k) {
      if (k == idKey) return false;
      final lk = k.toLowerCase();
      if (lk.endsWith('id') || lk.endsWith('guid')) return false;
      final v = row[k];
      if (v is! String || v.trim().isEmpty || v.length > 60) return false;
      if (RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-', caseSensitive: false).hasMatch(v)) {
        return false;
      }
      return true;
    }

    for (final want in preferred) {
      for (final k in row.keys) {
        if (k is String && k.toLowerCase() == want && ok(k)) return k;
      }
    }
    for (final k in row.keys) {
      if (k is String && ok(k)) return k;
    }
    return null;
  }

  List<AppSelectItem<String>> _itemsFrom(
      List rows, String idKey, String? labelKey) {
    final out = <AppSelectItem<String>>[];
    final seen = <String>{};
    for (final row in rows) {
      if (row is! Map) continue;
      final v = row[idKey];
      if (v == null || '$v'.isEmpty || !seen.add('$v')) continue;
      final l = labelKey == null ? null : row[labelKey];
      out.add(AppSelectItem(
        value: '$v',
        label: l == null || '$l'.isEmpty ? '$v' : '$l',
      ));
    }
    return out;
  }

  static String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static String _kebab(String s) => s
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]}-${m[2]}')
      .toLowerCase();

  Future<List<AppSelectItem<String>>> _fetch(
      String path, LookupSource src, String Function(Map row)? format) async {
    final res = await session.farmClient.get(path, query: {
      'farmId': company.farmId,
      'userId': session.tokens.userId ?? '',
    });

    final rows = _rowsIn(res);
    final out = <AppSelectItem<String>>[];
    final seen = <String>{};
    for (final row in rows) {
      if (row is! Map) continue;
      final value = row[src.value] ?? row[_lower(src.value)];
      if (value == null || '$value'.isEmpty) continue;
      if (!seen.add('$value')) continue;
      final label = format != null ? format(row) : (row[src.label] ?? row[_lower(src.label)]);
      out.add(AppSelectItem(
        value: '$value',
        // Falling back to the id is better than a blank row: the record is
        // still selectable, just not named.
        label: label == null || '$label'.isEmpty ? '$value' : '$label',
      ));
    }
    out.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return out;
  }

  static String _lower(String k) =>
      k.isEmpty ? k : k[0].toLowerCase() + k.substring(1);

  /// These endpoints return either a bare list or a list under `data`/`items`.
  /// The row list inside a response, for screens that fetch their own lists.
  static List<dynamic> rowsIn(dynamic res) => _rowsIn(res);

  static List<dynamic> _rowsIn(dynamic res) {
    if (res is List) return res;
    if (res is Map) {
      for (final k in const ['data', 'items', 'result', 'records', 'value']) {
        final v = res[k];
        if (v is List) return v;
        if (v is Map) {
          final nested = _rowsIn(v);
          if (nested.isNotEmpty) return nested;
        }
      }
    }
    return const [];
  }
}
