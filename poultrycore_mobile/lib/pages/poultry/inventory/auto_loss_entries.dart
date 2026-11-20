// Automatic rows on the Poultry Loss & Damage page, as the web's
// lib/poultry/auto-loss-entries.ts.
//
// Eggs are marked damaged in three places, and before this none of them showed
// on Loss & Damage, which only listed rows typed in by hand:
//   1. a production record's broken eggs,
//   2. damaged / missing crates on a driver return (and delivery or production
//      batch losses), which the API already writes to poultryproductionloss,
//   3. an 'Egg Loss' adjustment (breakage / loss) on an egg class in the Egg
//      Sorting workspace, which is a stock-ledger row.
//
// These rows are DERIVED, never stored: each is read from its source every
// time, so editing or deleting the source changes the row. They carry no
// approval step and add no value to the closing report's loss figure. To change
// one, change its source; the row links there.

import '../../../api/api_client.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../trackers/tracker_logic.dart' show tNum, tStr;

/// ProductionRecord | DriverReturn | Delivery | ProductionBatch | EggSorting
class AutoLossEntry {
  const AutoLossEntry({
    required this.key,
    required this.source,
    required this.sourceLabel,
    required this.lossDate,
    required this.lossType,
    required this.productName,
    required this.quantity,
    this.estimatedValue,
    this.reason,
    this.href,
  });

  /// Unique across all sources.
  final String key;
  final String source;

  /// Shown as "lossType — from sourceLabel".
  final String sourceLabel;
  final String lossDate;
  final String lossType;
  final String productName;
  final num quantity;
  final num? estimatedValue;
  final String? reason;

  /// Where the entry is changed. Null when the source has no page.
  final String? href;
}

final _returnTo = Uri.encodeComponent('/poultry-loss-records');

String _dayOf(Object? d) => tStr(d).split('T').first;

bool _inRange(String d, String? from, String? to) {
  final day = _dayOf(d);
  if (day.isEmpty) return false;
  if (from != null && from.isNotEmpty && day.compareTo(from) < 0) return false;
  if (to != null && to.isNotEmpty && day.compareTo(to) > 0) return false;
  return true;
}

String _disposed(num broken, num? disposed) => disposed! >= broken ? 'all disposed' : '${_n(disposed)} disposed, ${_n(broken - disposed)} kept';

String _n(num v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';

/// One row per production record with broken eggs.
List<AutoLossEntry> fromProductionRecords(List<Map> records) => [
      for (final r in records)
        if (tNum(r['brokenEggs']) > 0)
          () {
            final broken = tNum(r['brokenEggs']);
            final disposed = r['brokenEggsDisposed'] == null ? null : tNum(r['brokenEggsDisposed']);
            final bits = <String>[
              if (tStr(r['flockName']).isNotEmpty) 'Flock ${tStr(r['flockName'])}',
              if (disposed != null) _disposed(broken, disposed) else if (r['brokenEggDisposition'] == 'Disposed') 'all disposed',
            ];
            return AutoLossEntry(
              key: 'pr-${r['id']}',
              source: 'ProductionRecord',
              sourceLabel: 'production record',
              lossDate: tStr(r['date']),
              lossType: 'Damage',
              productName: 'Broken eggs',
              quantity: broken,
              reason: bits.isEmpty ? null : bits.join(' · '),
              href: '/production-records/${r['id']}?returnTo=$_returnTo',
            );
          }(),
    ];

/// Driver-return, delivery and production-batch losses (already one row each).
List<AutoLossEntry> fromProductionLosses(List<Map> losses) => [
      for (final l in losses)
        if (tNum(l['quantityLost']) > 0)
          () {
            final src = l['sourceType'] == 'PoultryDriverReturn'
                ? 'DriverReturn'
                : l['sourceType'] == 'PoultryDelivery'
                    ? 'Delivery'
                    : 'ProductionBatch';
            return AutoLossEntry(
              key: 'pl-${l['poultryProductionLossId']}',
              source: src,
              sourceLabel: _labelOf(src),
              lossDate: tStr(l['lossDate']),
              lossType: 'Damage',
              productName: tStr(l['productName']).isEmpty ? 'Eggs' : tStr(l['productName']),
              quantity: tNum(l['quantityLost']),
              estimatedValue: l['estimatedValue'] == null ? null : tNum(l['estimatedValue']),
              reason: l['reason'] == null ? null : tStr(l['reason']),
              href: _hrefOf(src),
            );
          }(),
    ];

/// 'Egg Loss' ledger rows: breakage or loss taken out of an egg class.
List<AutoLossEntry> fromEggLossTransactions(List<Map> txns) => [
      for (final t in txns)
        if (t['txnType'] == 'Egg Loss' && tNum(t['quantity']) < 0)
          AutoLossEntry(
            key: 'st-${t['poultryStockTransactionId']}',
            source: 'EggSorting',
            sourceLabel: 'egg sorting',
            lossDate: tStr(t['effectiveDate']).isNotEmpty ? tStr(t['effectiveDate']) : tStr(t['createdDate']),
            lossType: 'Damage',
            productName: tStr(t['productName']).isNotEmpty ? '${tStr(t['productName'])} eggs' : 'Eggs',
            quantity: tNum(t['quantity']).abs(),
            reason: t['note'] != null ? tStr(t['note']) : (t['reason'] != null ? tStr(t['reason']) : null),
            href: '/poultry-egg-sorting',
          ),
    ];

String _labelOf(String src) => src == 'DriverReturn'
    ? 'driver return'
    : src == 'Delivery'
        ? 'delivery'
        : 'production batch';

String? _hrefOf(String src) => src == 'DriverReturn'
    ? '/poultry-driver-returns'
    : src == 'Delivery'
        ? '/poultry-deliveries'
        : null;

/// Maps GET /Poultry/loss-records/auto-damage (migration 405) rows to the same
/// shape the fallback builds.
List<AutoLossEntry> fromAutoDamageApi(List<Map> rows) => [
      for (final (i, r) in rows.indexed)
        () {
          final id = r['sourceId'] ?? 'x$i';
          switch (r['sourceType']) {
            case 'ProductionRecord':
              final broken = r['brokenEggs'] != null ? tNum(r['brokenEggs']) : tNum(r['quantity']);
              final d = r['disposed'] == null ? null : tNum(r['disposed']);
              final bits = <String>[
                if (tStr(r['flockName']).isNotEmpty) 'Flock ${tStr(r['flockName'])}',
                if (d != null && d > 0) _disposed(broken, d),
              ];
              return AutoLossEntry(
                key: 'pr-$id',
                source: 'ProductionRecord',
                sourceLabel: 'production record',
                lossDate: tStr(r['lossDate']),
                lossType: tStr(r['lossType']),
                productName: tStr(r['productName']).isEmpty ? 'Broken eggs' : tStr(r['productName']),
                quantity: tNum(r['quantity']),
                reason: bits.isEmpty ? null : bits.join(' · '),
                href: r['sourceId'] != null ? '/production-records/${r['sourceId']}?returnTo=$_returnTo' : null,
              );
            case 'EggSorting':
              return AutoLossEntry(
                key: 'st-$id',
                source: 'EggSorting',
                sourceLabel: 'egg sorting',
                lossDate: tStr(r['lossDate']),
                lossType: tStr(r['lossType']),
                productName: tStr(r['productName']).isEmpty ? 'Eggs' : tStr(r['productName']),
                quantity: tNum(r['quantity']),
                reason: r['details'] == null ? null : tStr(r['details']),
                href: '/poultry-egg-sorting',
              );
            default:
              final src = r['sourceType'] == 'DriverReturn'
                  ? 'DriverReturn'
                  : r['sourceType'] == 'Delivery'
                      ? 'Delivery'
                      : 'ProductionBatch';
              return AutoLossEntry(
                key: 'pl-$src-$id-$i',
                source: src,
                sourceLabel: _labelOf(src),
                lossDate: tStr(r['lossDate']),
                lossType: tStr(r['lossType']),
                productName: tStr(r['productName']).isEmpty ? 'Eggs' : tStr(r['productName']),
                quantity: tNum(r['quantity']),
                estimatedValue: r['estimatedValue'] == null ? null : tNum(r['estimatedValue']),
                reason: r['details'] == null ? null : tStr(r['details']),
                href: _hrefOf(src),
              );
          }
        }(),
    ];

/// All three, newest first, optionally limited to a date range (yyyy-MM-dd).
List<AutoLossEntry> buildAutoLossEntries({
  List<Map> records = const [],
  List<Map> losses = const [],
  List<Map> txns = const [],
  String? fromDate,
  String? toDate,
}) {
  final all = [
    ...fromProductionRecords(records),
    ...fromProductionLosses(losses),
    ...fromEggLossTransactions(txns),
  ].where((e) => _inRange(e.lossDate, fromDate, toDate)).toList();
  // Newest first; ties keep their order (a stable sort, as the web's).
  final indexed = all.indexed.toList()
    ..sort((a, b) {
      final c = _dayOf(b.$2.lossDate).compareTo(_dayOf(a.$2.lossDate));
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
  return [for (final (_, e) in indexed) e];
}

List<Map> _rows(Object? r) {
  final v = r is Map ? (r['data'] ?? r['items']) : r;
  return [for (final x in v is List ? v : const []) if (x is Map) x];
}

/// The automatic damage rows. Fast path: the server query (405). If that
/// endpoint is missing, build them here from the production records, the
/// production losses and the stock ledger. Never throws: the manual records
/// must still show.
Future<List<AutoLossEntry>> loadAutoDamage(Session s, Company c) async {
  final api = s.farmClient;
  final farm = {'farmId': c.farmId};
  try {
    return fromAutoDamageApi(_rows(await api.get('/api/Poultry/loss-records/auto-damage', query: farm)));
  } catch (_) {
    // fall back
  }
  Future<List<Map>> safe(Future<Object?> f) async {
    try {
      return _rows(await f);
    } on ApiException {
      return const [];
    } catch (_) {
      return const [];
    }
  }

  final r = await Future.wait([
    safe(api.get('/api/ProductionRecord', query: {'userId': s.tokens.userId ?? '', 'farmId': c.farmId})),
    safe(api.get('/api/Poultry/production-losses', query: farm)),
    safe(api.get('/api/Poultry/stock/transactions', query: farm)),
  ]);
  return buildAutoLossEntries(records: r[0], losses: r[1], txns: r[2]);
}
