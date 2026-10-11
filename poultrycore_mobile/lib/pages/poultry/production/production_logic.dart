// Production rules shared by the production pages, ported from the web:
// lib/production/production-record-calc.ts, lib/utils/raw-material-costing.ts,
// components/production/feed-lines.tsx + medication-lines.tsx (their compute
// halves), lib/constants/egg-grade.ts and lib/api/farm-production-settings.ts.

import '../../../api/api_client.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;

const eggsPerCrate = 30;

// ------------------------------------------------------------ pick settings

class PickSettings {
  const PickSettings({
    this.first = '09:00',
    this.second = '12:00',
    this.third = '16:00',
    this.fourth = '18:00',
    this.fifth = '',
    this.sixth = '',
    this.enableFourth = false,
    this.enableFifth = false,
    this.enableSixth = false,
  });
  final String first, second, third, fourth, fifth, sixth;
  final bool enableFourth, enableFifth, enableSixth;

  static PickSettings fromJson(Object? raw) {
    if (raw is! Map) return const PickSettings();
    String s(String k, String d) => raw[k] == null ? d : tStr(raw[k]);
    return PickSettings(
      first: s('firstPickTime', '09:00'),
      second: s('secondPickTime', '12:00'),
      third: s('thirdPickTime', '16:00'),
      fourth: s('fourthPickTime', '18:00'),
      fifth: s('fifthPickTime', ''),
      sixth: s('sixthPickTime', ''),
      enableFourth: raw['enableFourthPick'] == true,
      enableFifth: raw['enableFifthPick'] == true,
      enableSixth: raw['enableSixthPick'] == true,
    );
  }

  /// GET /api/FarmProductionSettings; the defaults when it fails.
  static Future<PickSettings> load(Session session, Company company) async {
    try {
      return fromJson(await session.farmClient.get('/api/FarmProductionSettings', query: {'farmId': company.farmId}));
    } on ApiException {
      return const PickSettings();
    }
  }

  /// "1st Pick (9:00 AM)", …
  ({String first, String second, String third, String fourth, String fifth, String sixth}) get labels => (
        first: '1st Pick${_suffix(first)}',
        second: '2nd Pick${_suffix(second)}',
        third: '3rd Pick${_suffix(third)}',
        fourth: '4th Pick${_suffix(fourth)}',
        fifth: '5th Pick${_suffix(fifth)}',
        sixth: '6th Pick${_suffix(sixth)}',
      );

  /// The enabled extra picks as (header, record key) — the list's pickColumns.
  List<(String, String)> get extraColumns => [
        if (enableFourth) ('4th Pick', 'production4thPick'),
        if (enableFifth) ('5th Pick', 'production5thPick'),
        if (enableSixth) ('6th Pick', 'production6thPick'),
      ];
}

/// formatPickTime: "09:00" → "9:00 AM".
String formatPickTime(String? hhmm) {
  if (hhmm == null || hhmm.isEmpty) return '';
  final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(hhmm.trim());
  if (m == null) return hhmm;
  var h = int.parse(m[1]!);
  final ampm = h >= 12 ? 'PM' : 'AM';
  h = h % 12;
  if (h == 0) h = 12;
  return '$h:${m[2]} $ampm';
}

String _suffix(String v) {
  final f = formatPickTime(v);
  return f.isEmpty ? '' : ' ($f)';
}

// ------------------------------------------------------------ egg grades

const eggGradeNone = '__none__';
const eggGradeOptions = [
  (eggGradeNone, 'Not specified'),
  ('Small', 'Small'),
  ('Medium', 'Medium'),
  ('Large', 'Large'),
  ('XLarge', 'X-Large'),
  ('Jumbo', 'Jumbo'),
  ('Seconds', 'Seconds / B-grade'),
  ('Cracks', 'Cracks'),
  ('Mixed', 'Mixed grades'),
];
const _legacyGrades = {'p1': 'Small', 'p2': 'Medium', 'p3': 'Large', 'p4': 'XLarge'};

String eggGradeFromApi(Object? value) {
  final v = tStr(value).trim();
  if (v.isEmpty) return eggGradeNone;
  final mapped = _legacyGrades[v.toLowerCase()];
  if (mapped != null) return mapped;
  return eggGradeOptions.any((o) => o.$1 == v) ? v : eggGradeNone;
}

String? eggGradeToApi(String v) => v.isEmpty || v == eggGradeNone ? null : v.trim();

// ------------------------------------------------------------ production-record-calc

int pickTotal(num crates, num loose) => (crates < 0 ? 0 : crates.truncate()) * eggsPerCrate + (loose < 0 ? 0 : loose.truncate());

({int crates, int pieces}) cratesEquivalent(num total) {
  final t = total < 0 ? 0 : total.truncate();
  return (crates: t ~/ eggsPerCrate, pieces: t % eggsPerCrate);
}

num netSellableEggs(num total, num losses) => total - losses < 0 ? 0 : total - losses;

bool eggsExceedBirdsLeft(num eggs, num? birdsLeft) => eggs > 0 && birdsLeft != null && eggs > birdsLeft;

/// flockAge: whole days from the flock's start date to the record date (UTC calendar days).
({int weeks, int days, int years}) flockAge(Object? startDate, String? onDate) {
  DateTime? d(Object? v) {
    final s = tStr(v).split('T').first;
    final p = s.split('-');
    if (p.length != 3) return null;
    final y = int.tryParse(p[0]), m = int.tryParse(p[1]), dd = int.tryParse(p[2]);
    return y == null || m == null || dd == null ? null : DateTime.utc(y, m, dd);
  }

  final s = d(startDate), c = d(onDate);
  if (s == null || c == null) return (weeks: 0, days: 0, years: 0);
  final days = c.difference(s).inDays < 0 ? 0 : c.difference(s).inDays;
  return (weeks: days ~/ 7, days: days, years: days ~/ 365);
}

/// resolveAge: manual entry wins when ticked; each figure falls back to the others.
({int weeks, int days}) resolveAge(bool manual, ({int weeks, int days}) calculated, {String weeks = '', String days = '', String years = ''}) {
  if (!manual) return calculated;
  final w = int.tryParse(weeks) ?? 0, d = int.tryParse(days) ?? 0, y = int.tryParse(years) ?? 0;
  return (days: d != 0 ? d : (y != 0 ? y * 365 : w * 7), weeks: w != 0 ? w : (d ~/ 7 != 0 ? d ~/ 7 : y * 52));
}

num effectiveFeedKg(num lineTotal, String manual) => lineTotal > 0 ? lineTotal : (num.tryParse(manual) ?? 0);

num round2(num v) => double.parse(v.toStringAsFixed(2));

// ------------------------------------------------------------ raw-material-costing

class CostPreview {
  const CostPreview({this.unitCost, this.totalCost, this.covered = 0, this.shortfall = 0});
  final num? unitCost, totalCost;
  final num covered, shortfall;
}

/// Item id → what the record being edited already drew (it goes back on first).
typedef ConsumptionCredit = Map<int, ({num qty, num unitCost})>;

class _Lot {
  _Lot(this.unitCost, this.date, this.id, this.remaining, this.mult, {this.isCredit = false});
  final num unitCost;
  final String date;
  final int id;
  num remaining;
  final num mult;
  final bool isCredit;
}

/// previewLinesSequential: every line draws from the same lots in its item's
/// FIFO / LIFO / HIFO order, so a later line sees what an earlier one took.
List<CostPreview> previewLinesSequential(List<(Map?, num)> lines, List<Map> purchases, [ConsumptionCredit? credit]) {
  final lots = <int, List<_Lot>>{};
  for (final p in purchases) {
    if (tNum(p['remainingQuantity']) <= 0) continue;
    final mult = tNum(p['productionUnitsPerPurchaseUnit']) > 0 ? tNum(p['productionUnitsPerPurchaseUnit']) : 1;
    (lots[tIntOrNull(p['poultryRawMaterialItemId']) ?? 0] ??= []).add(_Lot(tNum(p['unitCost']), tStr(p['purchaseDate']),
        tIntOrNull(p['poultryRawMaterialPurchaseId']) ?? 0, tNum(p['remainingQuantity']), mult));
  }
  credit?.forEach((id, c) {
    if (c.qty > 0) (lots[id] ??= []).add(_Lot(c.unitCost, '1900-01-01', -1, c.qty, 1, isCredit: true));
  });
  int ms(String s) => DateTime.tryParse(s)?.millisecondsSinceEpoch ?? 0;
  return [
    for (final (item, qty) in lines)
      (() {
        if (item == null || qty <= 0) return const CostPreview();
        final method = tStr(item['usageMethod']).isEmpty ? 'FIFO' : tStr(item['usageMethod']);
        final mine = [...?lots[tIntOrNull(item['poultryRawMaterialItemId'])]]
          ..sort((a, b) {
            if (a.isCredit != b.isCredit) return a.isCredit ? -1 : 1;
            if (method == 'HIFO') {
              if (b.unitCost != a.unitCost) return b.unitCost.compareTo(a.unitCost);
              return a.id - b.id;
            }
            final dir = method == 'LIFO' ? -1 : 1;
            final d = ms(a.date) - ms(b.date);
            if (d != 0) return dir * d.sign;
            return dir * (a.id - b.id).sign;
          });
        num remaining = qty, covered = 0, cost = 0;
        for (final lot in mine) {
          if (remaining <= 0) break;
          final avail = lot.remaining * lot.mult;
          final take = avail < remaining ? avail : remaining;
          if (take <= 0) continue;
          covered += take;
          cost += (take / lot.mult) * lot.unitCost;
          remaining -= take;
          lot.remaining -= take / lot.mult;
        }
        final unit = covered > 0 ? cost / covered : null;
        return CostPreview(unitCost: unit, totalCost: unit == null ? null : unit * qty, covered: covered, shortfall: qty - covered > 0 ? qty - covered : 0);
      })(),
  ];
}

/// One feed or medication line on the form: the item id (or '') and the quantity typed.
class ConsumptionLine {
  ConsumptionLine([this.itemId = '', this.qty = '']);
  String itemId, qty;
}

/// The keys of a feed or medication line in the API.
class LineKeys {
  const LineKeys(this.id, this.name, this.consumed, this.unitCost, this.totalCost);
  final String id, name, consumed, unitCost, totalCost;
  static const feed = LineKeys('specificFeedUsedId', 'specificFeedUsedName', 'totalFeedConsumed', 'feedUnitCost', 'totalFeedCost');
  static const med =
      LineKeys('specificMedicationUsedId', 'specificMedicationUsedName', 'totalMedicationConsumed', 'medicationUnitCost', 'totalMedicationCost');
}

class LinesComputed {
  LinesComputed(this.rows, this.totalCost, this.totalConsumed, this.firstShortfall, this.lines, this.pendingStock);
  final List<({Map? item, num qty, CostPreview preview})> rows;
  final num totalCost, totalConsumed;
  final ({Map? item, num qty, CostPreview preview})? firstShortfall;

  /// What is sent: one entry per line with an item and a quantity.
  final List<Map<String, Object?>> lines;

  /// Item id → stock after this form's lines (with the credit back).
  final Map<int, num> pendingStock;
}

ConsumptionCredit buildCredit(List<Map> saved, LineKeys k) {
  final out = <int, ({num qty, num unitCost})>{};
  for (final f in saved) {
    final id = tIntOrNull(f[k.id]);
    if (id == null || tNum(f[k.consumed]) == 0) continue;
    final prev = out[id];
    out[id] = (qty: (prev?.qty ?? 0) + tNum(f[k.consumed]), unitCost: f[k.unitCost] != null ? tNum(f[k.unitCost]) : (prev?.unitCost ?? 0));
  }
  return out;
}

LinesComputed computeLines(List<ConsumptionLine> lines, List<Map> items, List<Map> purchases, ConsumptionCredit credit, LineKeys k) {
  final resolved = [
    for (final l in lines) (items.where((i) => tStr(i['poultryRawMaterialItemId']) == l.itemId).firstOrNull, num.tryParse(l.qty) ?? 0),
  ];
  final previews = previewLinesSequential(resolved, purchases, credit);
  final rows = [for (var i = 0; i < resolved.length; i++) (item: resolved[i].$1, qty: resolved[i].$2, preview: previews[i])];
  final consumed = <int, num>{};
  for (final r in rows) {
    if (r.item != null && r.qty > 0) {
      final id = tIntOrNull(r.item!['poultryRawMaterialItemId']) ?? 0;
      consumed[id] = (consumed[id] ?? 0) + r.qty;
    }
  }
  return LinesComputed(
    rows,
    rows.fold<num>(0, (a, r) => a + (r.preview.totalCost ?? 0)),
    rows.fold<num>(0, (a, r) => a + r.qty),
    rows.where((r) => r.item != null && r.preview.shortfall > 0).firstOrNull,
    [
      for (final r in rows)
        if (r.item != null && r.qty > 0)
          {
            k.id: tIntOrNull(r.item!['poultryRawMaterialItemId']),
            k.name: tStr(r.item!['itemName']),
            k.consumed: r.qty,
            k.unitCost: r.preview.unitCost,
            k.totalCost: round2(r.preview.totalCost ?? 0),
          },
    ],
    {
      for (final it in items)
        tIntOrNull(it['poultryRawMaterialItemId']) ?? 0: tNum(it['currentQuantity']) +
            (credit[tIntOrNull(it['poultryRawMaterialItemId'])]?.qty ?? 0) -
            (consumed[tIntOrNull(it['poultryRawMaterialItemId'])] ?? 0),
    },
  );
}

bool isFinishedFeedCategory(Object? c) => RegExp('finish', caseSensitive: false).hasMatch(tStr(c));
bool isMedicationCategory(Object? c) => RegExp('(medic|vaccin|drug)', caseSensitive: false).hasMatch(tStr(c));

// ------------------------------------------------------------ the production list

/// formatAge: "0 yr 12 wk 3 d (87 days)".
String formatProductionAge(Map r) {
  final days = tNum(r['ageInDays'] ?? r['ageDays']), weeks = tNum(r['ageInWeeks'] ?? r['ageWeeks']);
  final d = (days != 0 ? days : weeks * 7).toInt();
  if (d == 0) return '-';
  return '${d ~/ 365} yr ${(d % 365) ~/ 7} wk ${d % 7} d ($d days)';
}

/// Egg% = total ÷ birds, or null without birds.
num? eggPercent(Map r) {
  final b = tNum(r['noOfBirds']);
  return b == 0 ? null : tNum(r['totalProduction']) / b * 100;
}

String monthKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
