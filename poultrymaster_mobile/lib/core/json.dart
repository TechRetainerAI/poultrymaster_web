/// The Login API and Farm API are inconsistent about JSON casing (camelCase
/// by default, PascalCase in a few code paths — the web frontend handles both
/// too). These helpers read a key case-insensitively so DTO drift never
/// silently drops a field.
library;

dynamic pick(Map<String, dynamic>? map, List<String> keys) {
  if (map == null) return null;
  for (final k in keys) {
    if (map.containsKey(k) && map[k] != null) return map[k];
  }
  final lower = {for (final e in map.entries) e.key.toLowerCase(): e.value};
  for (final k in keys) {
    final v = lower[k.toLowerCase()];
    if (v != null) return v;
  }
  return null;
}

String pickString(Map<String, dynamic>? map, List<String> keys, [String fallback = '']) =>
    pick(map, keys)?.toString() ?? fallback;

bool pickBool(Map<String, dynamic>? map, List<String> keys, [bool fallback = false]) {
  final v = pick(map, keys);
  if (v is bool) return v;
  if (v is String) return v.toLowerCase() == 'true';
  if (v is num) return v != 0;
  return fallback;
}

num pickNum(Map<String, dynamic>? map, List<String> keys, [num fallback = 0]) {
  final v = pick(map, keys);
  if (v is num) return v;
  if (v is String) return num.tryParse(v) ?? fallback;
  return fallback;
}

DateTime? pickDate(Map<String, dynamic>? map, List<String> keys) {
  final v = pick(map, keys);
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
  return null;
}
