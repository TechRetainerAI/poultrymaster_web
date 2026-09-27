import 'plumbing_fields.dart';
import 'package:flutter/material.dart';

/// How a field should be rendered.
enum FieldKind { text, money, number, date, status, boolean }

/// One field of a record.
class FieldSpec {
  const FieldSpec(
    this.key,
    this.label, {
    this.kind = FieldKind.text,
    this.suffix,
  });

  final String key;
  final String label;
  final FieldKind kind;
  final String? suffix;
}

/// How a summary card's figure is worked out from the loaded rows.
enum SummaryOp { sum, average, count, latest, distinctSum }

/// One summary card above a list, mirroring the web's StatTile.
class SummaryDef {
  const SummaryDef({
    required this.label,
    required this.op,
    this.field,
    this.money = false,
    this.tone = SummaryTone.neutral,
    this.sub,
    this.crates,
  });

  final String label;
  final SummaryOp op;
  final String? field;
  final bool money;
  final SummaryTone tone;

  /// Small line under the figure.
  final String? sub;

  /// When set, also render "Nc + Mp" using this many units per crate — the
  /// web shows egg totals that way.
  final int? crates;
}

enum SummaryTone { neutral, positive, negative }

/// A declarative description of one page.
///
/// The web has 361 page routes and ~130,000 lines of page code, but the great
/// majority are the same three shapes: a filtered list, a record detail, and a
/// create/edit form. Describing each page as data rather than writing a bespoke
/// screen is what makes porting the whole product tractable — one renderer,
/// many specs.
class PageSpec {
  const PageSpec({
    required this.key,
    required this.title,
    required this.path,
    this.query = const {},
    this.needsFarmId = true,
    this.needsUserId = false,
    this.needsCompanyType = false,
    this.farmIdParam = 'farmId',
    this.itemsAt,
    this.titleField = '',
    this.subtitleFields = const [],
    this.fields = const [],
    this.statusField,
    this.searchFields = const [],
    this.emptyMessage,
    this.module = '',
    this.source = 'farm',
    this.summaries = const [],
    this.readOnly = false,
  });

  /// True when the endpoint serves GET but no POST — a report or a view.
  ///
  /// The list screen will otherwise DERIVE a create form from the shape of a
  /// loaded row, which put an "Add …" button on 364 pages that cannot accept
  /// one, including every report. The web shows no such button there, and a
  /// button that can only fail is worse than no button.
  final bool readOnly;

  /// Per-page summary cards. When empty the list screen derives
  /// generic ones from whatever numeric fields the rows carry.
  final List<SummaryDef> summaries;

  /// Which service serves this page: 'farm' or 'login'. Account, company and
  /// billing pages live on the login API, not the farm API.
  final String source;

  /// Which company type this page belongs to: poultry, water, generic,
  /// restaurant or hotel. Drives what appears under "More".
  final String module;

  final String key;
  final String title;

  /// Farm-API path. `{farmId}` is substituted when present.
  final String path;
  final Map<String, String> query;

  /// Most endpoints take farmId as a query parameter; Poultry reports use a
  /// capital `FarmId`, and generic-company puts it in the path.
  final bool needsFarmId;
  final String farmIdParam;

  /// A few endpoints (MainFlockBatch) reject the request without a userId.
  final bool needsUserId;

  /// Some endpoints want the company's type alongside its id — the Business
  /// Office snapshot serves a different shape per type and refuses without
  /// it. The app knows the type at call time, so it is sent then.
  final bool needsCompanyType;

  /// Where the rows live when the response is an object, e.g. `items`.
  final String? itemsAt;

  /// The field used as a row's headline. Empty means "work it out from the
  /// data" — most endpoints declare no response schema in swagger, so a
  /// generated spec cannot know the field names in advance. See [titleFieldIn].
  final String titleField;
  final List<FieldSpec> subtitleFields;

  /// Shown when a row is opened.
  final List<FieldSpec> fields;

  final String? statusField;
  final List<String> searchFields;
  final String? emptyMessage;
}

/// Picks the headline field for a row when the spec does not name one.
///
/// Prefers an explicit name/title, then a code or reference, then a
/// description, then a date — the same order a person scanning a table would
/// read. Falls back to the first short string so a row is never blank.
String titleFieldIn(Map<String, dynamic> row, String declared) {
  if (declared.isNotEmpty) return declared;

  const preferred = [
    'name', 'title', 'fullname', 'customername', 'employeename', 'guestname',
    'itemname', 'productname', 'assetname', 'accountname', 'batchname',
    'lendername', 'suppliername', 'roomnumber', 'ordernumber', 'code',
    'batchcode', 'referenceno', 'description', 'category', 'date',
  ];
  final keys = row.keys.toList();

  for (final want in preferred) {
    for (final k in keys) {
      if (k.toLowerCase() == want && row[k] != null && '${row[k]}'.isNotEmpty) {
        return k;
      }
    }
  }
  for (final want in preferred) {
    for (final k in keys) {
      if (k.toLowerCase().contains(want) &&
          row[k] is String &&
          (row[k] as String).isNotEmpty) {
        return k;
      }
    }
  }
  for (final k in keys) {
    final v = row[k];
    if (v is String && v.isNotEmpty && v.length <= 60 && !_looksLikeId(k)) {
      return k;
    }
  }
  return keys.isEmpty ? '' : keys.first;
}

bool _looksLikeId(String key) {
  final k = key.toLowerCase();
  return k == 'id' || k.endsWith('id') || k.endsWith('guid');
}

/// Fields worth showing under the headline when the spec names none.
List<FieldSpec> autoSubtitles(Map<String, dynamic> row, String titleKey) {
  final out = <FieldSpec>[];
  for (final k in row.keys) {
    if (k == titleKey || _looksLikeId(k)) continue;
    final v = row[k];
    if (v == null || v is Map || v is List) continue;
    if (isPlumbingField(k, v)) continue;
    final lower = k.toLowerCase();
    FieldKind kind;
    if (v is num) {
      kind = _moneyish(lower) ? FieldKind.money : FieldKind.number;
    } else if (v is bool) {
      kind = FieldKind.boolean;
    } else if (lower.contains('date') || DateTime.tryParse('$v') != null) {
      kind = FieldKind.date;
    } else {
      continue; // plain strings read better on the detail screen
    }
    out.add(FieldSpec(k, _humanise(k), kind: kind));
    if (out.length == 3) break;
  }
  return out;
}

bool _moneyish(String k) {
  const money = [
    'amount', 'price', 'cost', 'total', 'balance', 'revenue', 'paid',
    'value', 'fee', 'rate', 'principal', 'outstanding',
  ];
  const counts = ['count', 'quantity', 'qty', 'number', 'birds', 'eggs'];
  if (counts.any(k.contains)) return false;
  return money.any(k.contains);
}

String _humanise(String key) {
  final spaced =
      key.replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}');
  return spaced.isEmpty ? key : spaced[0].toUpperCase() + spaced.substring(1);
}

/// Colour for a status value, following the web's convention of green for
/// settled/active, amber for pending, red for cancelled or rejected.
({Color bg, Color fg}) statusStyle(String raw) {
  final s = raw.toLowerCase();
  if (s.contains('cancel') || s.contains('reject') || s.contains('fail') ||
      s.contains('overdue') || s.contains('unpaid')) {
    return (bg: const Color(0xFFFEE2E2), fg: const Color(0xFF991B1B));
  }
  if (s.contains('pending') || s.contains('draft') || s.contains('partial') ||
      s.contains('submitted') || s.contains('await')) {
    return (bg: const Color(0xFFFEF3C7), fg: const Color(0xFF92400E));
  }
  if (s.contains('active') || s.contains('approved') || s.contains('paid') ||
      s.contains('complete') || s.contains('closed') || s.contains('settled')) {
    return (bg: const Color(0xFFDCFCE7), fg: const Color(0xFF166534));
  }
  return (bg: const Color(0xFFF1F5F9), fg: const Color(0xFF334155));
}
