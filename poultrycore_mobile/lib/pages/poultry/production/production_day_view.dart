// Production Records → "View by Day" (components/production/day-records-dialog.tsx):
// every production record logged on one day, across all flocks and batches.
// The list screen's filters do not apply. Opens on the most recent day that
// has records; the arrows step one calendar day. Colours match the records
// table: 1st pick blue, 2nd orange, 3rd purple, extra picks teal, brokens red.

import 'package:flutter/material.dart';

import '../../shared/business_dates.dart' show fmtNum;
import '../trackers/tracker_logic.dart' show tNum, loc, localDateKey;
import '../trackers/tracker_widgets.dart' show TColors;

import 'package:poultrycore_mobile/design/tone.dart';

const _orange = Tone.fg(0xFFC2410C), _orangeBg = Tone.bg(0xFFFFF7ED), _orangeBorder = Tone.line(0xFFFED7AA);
const _purple = Tone.fg(0xFF7E22CE), _purpleBg = Tone.bg(0xFFFAF5FF), _purpleBorder = Tone.line(0xFFE9D5FF);
const _teal = Tone.fg(0xFF0F766E), _tealBg = Tone.bg(0xFFF0FDFA), _tealBorder = Tone.line(0xFF99F6E4);
const _blueBg = Tone.bg(0xFFEFF6FF);

/// Where each number lives on a record. Production records are the default;
/// batch production records pass [batchDayFields].
class DayFields {
  const DayFields({
    this.date = 'date', this.p1 = 'production9AM', this.p2 = 'production12PM', this.p3 = 'production4PM',
    this.broken = 'brokenEggs', this.eggs = 'totalProduction', this.feed = 'feedKg', this.birds = 'noOfBirds',
    this.deaths = 'mortality', this.left,
  });
  final String date, p1, p2, p3, broken, eggs, feed, birds, deaths;
  /// Birds left field; null = birds - deaths.
  final String? left;
}

const batchDayFields = DayFields(
  date: 'productionDate', p1: 'firstPickTotal', p2: 'secondPickTotal', p3: 'thirdPickTotal',
  eggs: 'totalEggs', birds: 'birdsLeft', deaths: 'deaths', left: 'birdsLeft',
);

String _key(DateTime d) => '${d.year}-${'${d.month}'.padLeft(2, '0')}-${'${d.day}'.padLeft(2, '0')}';
DateTime _parse(String k) {
  final p = k.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
String _longDate(String k) {
  final d = _parse(k);
  return '${_days[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}, ${d.year}';
}

/// Opens the day view. [onEdit] is called after the view closes, with the
/// record the user tapped Edit on.
Future<void> showProductionDayView(
  BuildContext context, {
  required List<Map> records,
  required List<(String, String)> extraPicks,
  required String Function(Map) flockLabel,
  required String Function(Map) batchLabel,
  required void Function(Map) onEdit,
  DayFields fields = const DayFields(),
  Widget Function(Map)? badge,
  String batchPrefix = 'Batch: ',
  bool showBirds = true,
  IconData editIcon = Icons.edit_outlined,
  String editTooltip = 'Edit',
  String description = 'Every production record logged on the chosen day, for all flocks.',
  void Function(String day)? onShowInTable,
}) async {
  // Pops with the record to edit, or with the day for "Show in table".
  final picked = await Navigator.of(context).push<Object>(MaterialPageRoute(
    builder: (_) => ProductionDayView(
      records: records, extraPicks: extraPicks, flockLabel: flockLabel, batchLabel: batchLabel, fields: fields, badge: badge,
      batchPrefix: batchPrefix, showBirds: showBirds, editIcon: editIcon, editTooltip: editTooltip,
      description: description, canShowInTable: onShowInTable != null,
    ),
  ));
  if (picked is Map) onEdit(picked);
  if (picked is String) onShowInTable?.call(picked);
}

class ProductionDayView extends StatefulWidget {
  const ProductionDayView({
    super.key, required this.records, required this.extraPicks, required this.flockLabel, required this.batchLabel,
    this.fields = const DayFields(), this.badge, this.batchPrefix = 'Batch: ', this.showBirds = true,
    this.editIcon = Icons.edit_outlined, this.editTooltip = 'Edit',
    this.description = 'Every production record logged on the chosen day, for all flocks.', this.canShowInTable = false,
  });
  final String description;

  /// "Show in table": apply this day as the page's date filter and close.
  final bool canShowInTable;
  final DayFields fields;
  final Widget Function(Map)? badge;
  final String batchPrefix;
  final bool showBirds;
  final IconData editIcon;
  final String editTooltip;
  final List<Map> records;
  final List<(String, String)> extraPicks;
  final String Function(Map) flockLabel;
  final String Function(Map) batchLabel;

  @override
  State<ProductionDayView> createState() => _ProductionDayViewState();
}

class _ProductionDayViewState extends State<ProductionDayView> {
  late final String _latest = () {
    var best = '';
    for (final r in widget.records) {
      final k = localDateKey(r[widget.fields.date]);
      if (k.compareTo(best) > 0) best = k;
    }
    return best.isEmpty ? _key(DateTime.now()) : best;
  }();
  late String _day = _latest;

  void _shift(int days) {
    final d = _parse(_day);
    setState(() => _day = _key(DateTime(d.year, d.month, d.day + days)));
  }

  Future<void> _pick() async {
    final d = await showDatePicker(context: context, initialDate: _parse(_day), firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (d != null) setState(() => _day = _key(d));
  }

  num _sum(List<Map> rows, String k) => rows.fold<num>(0, (s, r) => s + tNum(r[k]));
  num _left(Map r) => widget.fields.left != null ? tNum(r[widget.fields.left]) : tNum(r[widget.fields.birds]) - tNum(r[widget.fields.deaths]);

  @override
  Widget build(BuildContext context) {
    final F = widget.fields;
    final rows = [for (final r in widget.records) if (localDateKey(r[F.date]) == _day) r]
      ..sort((a, b) => widget.flockLabel(a).compareTo(widget.flockLabel(b)));
    final picks = <(String, String, Color, Color, Color)>[
      ('1st Pick', F.p1, TColors.blue600, _blueBg, TColors.blue200),
      ('2nd Pick', F.p2, _orange, _orangeBg, _orangeBorder),
      ('3rd Pick', F.p3, _purple, _purpleBg, _purpleBorder),
      for (final (h, k) in widget.extraPicks) (h, k, _teal, _tealBg, _tealBorder),
      ('Brokens', F.broken, TColors.red700, TColors.red50, TColors.red200),
    ];
    final eggs = _sum(rows, F.eggs), feed = _sum(rows, F.feed), deaths = _sum(rows, F.deaths);
    final left = rows.fold<num>(0, (s, r) => s + _left(r));

    Widget tile(String label, String value, Color bg, Color border, Color fg) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .4, color: fg)),
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: fg)),
          ]),
        );

    Widget pickChip(String label, num v, Color fg, Color bg, Color border) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(6)),
          child: Text.rich(TextSpan(children: [
            TextSpan(text: '$label ', style: TextStyle(fontSize: 12, color: fg.withValues(alpha: .8))),
            TextSpan(text: loc(v), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
          ])),
        );

    Widget kv(String l, String v, {Color? color}) => Text.rich(TextSpan(children: [
          TextSpan(text: '$l ', style: const TextStyle(color: TColors.slate500)),
          TextSpan(text: v, style: TextStyle(fontWeight: FontWeight.w600, color: color ?? TColors.slate800)),
        ]), style: const TextStyle(fontSize: 13));

    Widget recordCard(Map r, int i) {
      final mortality = tNum(r[F.deaths]);
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: i.isEven ? Tone.bg(0xFFFFFFFF) : TColors.slate50,
          border: Border.all(color: TColors.slate200),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(widget.flockLabel(r), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: TColors.slate900)),
                  if (widget.badge != null) widget.badge!(r),
                ]),
                if (widget.batchLabel(r) != '-')
                  Text('${widget.batchPrefix}${widget.batchLabel(r)}',
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: TColors.emerald100, borderRadius: BorderRadius.circular(999)),
              child: Text('${loc(tNum(r[F.eggs]))} eggs',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: TColors.emerald800)),
            ),
            IconButton(
              tooltip: widget.editTooltip,
              visualDensity: VisualDensity.compact,
              icon: Icon(widget.editIcon, size: 18, color: TColors.slate600),
              onPressed: () => Navigator.of(context).pop(r),
            ),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (l, k, fg, bg, border) in picks) pickChip(l, tNum(r[k]), fg, bg, border),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 14, runSpacing: 4, children: [
            kv('Feed', '${fmtNum(tNum(r[F.feed]), 3)} kg'),
            if (widget.showBirds) kv('Birds', loc(tNum(r[F.birds]))),
            kv('Deaths', loc(mortality), color: mortality > 0 ? TColors.red600 : null),
            kv('Left', r[F.left ?? F.birds] == null ? '—' : loc(_left(r)), color: TColors.blue900),
          ]),
        ]),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Records for a day')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
        children: [
          Text(widget.description, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
          const SizedBox(height: 10),
          Row(children: [
            IconButton.outlined(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left), tooltip: 'Previous day'),
            const SizedBox(width: 6),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                onPressed: _pick,
                icon: const Icon(Icons.calendar_today_outlined, size: 16),
                label: Text(_day),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.outlined(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right), tooltip: 'Next day'),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: Text('${_longDate(_day)} · ${rows.length} ${rows.length == 1 ? 'record' : 'records'}',
                  style: const TextStyle(fontSize: 13, color: TColors.slate600)),
            ),
            if (_day != _latest) TextButton(onPressed: () => setState(() => _day = _latest), child: const Text('Latest day')),
          ]),
          if (widget.canShowInTable) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                key: const ValueKey('day-show-in-table'),
                onPressed: rows.isEmpty ? null : () => Navigator.of(context).pop(_day),
                icon: const Icon(Icons.filter_list, size: 16),
                label: const Text('Show in table'),
              ),
            ),
          ],
          const SizedBox(height: 8),
          if (rows.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(10)),
              child: const Text('No production records on this day.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate500)),
            )
          else ...[
            Row(children: [
              Expanded(child: tile('Total eggs', loc(eggs), TColors.emerald50, TColors.emerald200, TColors.emerald800)),
              const SizedBox(width: 8),
              Expanded(child: tile('Feed used', '${fmtNum((feed * 100).round() / 100, 2)} kg', TColors.amber50, TColors.amber200, TColors.amber800)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: tile('Deaths', loc(deaths), TColors.red50, TColors.red200, TColors.red700)),
              const SizedBox(width: 8),
              Expanded(child: tile('Birds left', loc(left), _blueBg, TColors.blue200, TColors.blue900)),
            ]),
            const SizedBox(height: 8),
            // Day totals per pick, same colours as the table's totals row.
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: _blueBg, border: Border.all(color: TColors.blue200), borderRadius: BorderRadius.circular(10)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('DAY TOTALS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .4, color: TColors.blue900)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final (l, k, fg, bg, border) in picks) pickChip(l, _sum(rows, k), fg, bg, border),
                ]),
              ]),
            ),
            const SizedBox(height: 12),
            for (final (i, r) in rows.indexed) recordCard(r, i),
          ],
        ],
      ),
    );
  }
}
