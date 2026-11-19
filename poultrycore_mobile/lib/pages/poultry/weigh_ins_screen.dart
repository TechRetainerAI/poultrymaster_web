import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../design/ui/form_dialog.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../shared/business_dates.dart' show isoDay;
import '../shared/company_clock.dart';
import '../shared/reason_dialog.dart';
import 'flock_type.dart';
import 'trackers/tracker_widgets.dart' show FilterLabel;
import 'weigh_in_stats.dart';

import 'package:poultrycore_mobile/design/tone.dart';

/// Operations → Production → Weigh-ins (`/poultry-weigh-ins`, migration 400),
/// as the web's `app/poultry-weigh-ins/page.tsx`.
///
/// One flock at a time: its growth curve (average weight by age), the
/// weigh-ins behind it, and a form to add one, either bird by bird off the
/// scale or as the summary the farm wrote down. The server derives every
/// figure from individual weights; the preview is weigh_in_stats.dart, the
/// same rule. On a phone the web shows one card per weigh-in, so does this.
class WeighInsScreen extends StatefulWidget {
  const WeighInsScreen({super.key, required this.session, required this.company, this.flockId});

  final Session session;
  final Company company;

  /// The web's `?flockId=`: open on this flock.
  final int? flockId;

  @override
  State<WeighInsScreen> createState() => _WeighInsScreenState();
}

/// reversal-reasons.ts `WEIGH_IN_DELETE_REASONS`.
const weighInDeleteReasons = [
  'Duplicate entry',
  'Wrong flock',
  'Wrong date',
  'Wrong weights',
  'Entered by mistake',
  'Test or training entry',
  'Other',
];

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "05 Nov 2026", as the web's toLocaleDateString(day 2-digit, month short).
String weighDateLabel(Object? iso) {
  final s = '${iso ?? ''}';
  final d = s.length >= 10 ? DateTime.tryParse(s.substring(0, 10)) : null;
  if (d == null) return s;
  return '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]} ${d.year}';
}

String _pct(Object? n, [int dp = 1]) {
  final v = n is num ? n : num.tryParse('${n ?? ''}');
  return v == null ? '—' : '${v.toStringAsFixed(dp)}%';
}

double? _d(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
int _i(Object? v) => v is num ? v.toInt() : (int.tryParse('${v ?? ''}') ?? 0);

/// A number as JavaScript's String(n) writes it: 1850, not 1850.0.
String jsNum(num n) => n == n.roundToDouble() ? n.toInt().toString() : n.toString();

String _thousands(int v) {
  final s = v.abs().toString();
  final b = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

/// One weigh-in as the API sends it (`FlockWeighIn`).
class WeighIn {
  WeighIn(Map m)
      : id = _i(m['weighInId']),
        flockId = _i(m['flockId']),
        weighDate = '${m['weighDate'] ?? ''}',
        ageInDays = _i(m['ageInDays']),
        sampleSize = _i(m['sampleSize']),
        avgWeightG = _d(m['avgWeightG']) ?? 0,
        minWeightG = _d(m['minWeightG']),
        maxWeightG = _d(m['maxWeightG']),
        uniformityPct = _d(m['uniformityPct']),
        cvPct = _d(m['cvPct']),
        weightsG = m['weightsG'] is List ? [for (final w in m['weightsG'] as List) if (_d(w) != null) _d(w)!] : null,
        notes = m['notes'] == null || '${m['notes']}'.isEmpty ? null : '${m['notes']}',
        daysSincePrev = m['daysSincePrev'] == null ? null : _i(m['daysSincePrev']),
        dailyGainG = _d(m['dailyGainG']);
  final int id;
  final int flockId;
  final String weighDate;
  final int ageInDays;
  final int sampleSize;
  final double avgWeightG;
  final double? minWeightG;
  final double? maxWeightG;
  final double? uniformityPct;
  final double? cvPct;
  final List<double>? weightsG;
  final String? notes;
  final int? daysSincePrev;
  final double? dailyGainG;
}

class _WeighInsScreenState extends State<WeighInsScreen> {
  List<Map<String, dynamic>> _flocks = const [];
  bool _flocksLoading = true;
  List<WeighIn> _rows = const [];
  bool _rowsLoading = false;
  String _error = '';
  int? _picked;
  String? _today;

  Map<String, dynamic> get _scope => {'farmId': widget.company.farmId};

  @override
  void initState() {
    super.initState();
    _picked = widget.flockId;
    _loadFlocks();
    CompanyClock.load(widget.session, widget.company).then((c) {
      if (mounted) setState(() => _today = c.today);
    });
  }

  static int _byType(Map a, Map b) {
    final t = (isBroilerFlock(b) ? 1 : 0) - (isBroilerFlock(a) ? 1 : 0);
    return t != 0 ? t : '${a['name'] ?? ''}'.compareTo('${b['name'] ?? ''}');
  }

  static bool _closed(Map f) => '${f['closedDate'] ?? ''}'.isNotEmpty;

  /// Open flocks first, broilers before layers; closed flocks after.
  List<Map<String, dynamic>> get _live => [for (final f in _flocks) if (f['isDeleted'] != true) f];
  List<Map<String, dynamic>> get _openFlocks => _live.where((f) => !_closed(f)).toList()..sort(_byType);
  List<Map<String, dynamic>> get _closedFlocks => _live.where(_closed).toList()..sort(_byType);

  int get _selectedId {
    final p = _picked;
    if (p != null && p > 0) return p;
    final open = _openFlocks, closed = _closedFlocks;
    return open.isNotEmpty ? _i(open.first['flockId']) : (closed.isNotEmpty ? _i(closed.first['flockId']) : 0);
  }

  Map<String, dynamic>? get _selected =>
      _flocks.where((f) => _i(f['flockId']) == _selectedId).firstOrNull;

  bool get _isClosed => _selected != null && _closed(_selected!);

  Future<void> _loadFlocks() async {
    try {
      final res = await widget.session.farmClient.get('/api/Flock', query: {
        ..._scope,
        'userId': widget.session.tokens.userId ?? '',
      });
      final list = res is List ? res : (res is Map && res['data'] is List ? res['data'] as List : const []);
      if (!mounted) return;
      setState(() => _flocks = [for (final f in list) if (f is Map) Map<String, dynamic>.from(f)]);
    } catch (_) {
      if (mounted) setState(() => _flocks = const []);
    }
    if (!mounted) return;
    setState(() => _flocksLoading = false);
    await _loadRows();
  }

  Future<void> _loadRows() async {
    final id = _selectedId;
    if (id == 0) {
      setState(() => _rows = const []);
      return;
    }
    setState(() {
      _rowsLoading = true;
      _error = '';
    });
    try {
      final res = await widget.session.farmClient.get('/api/Poultry/weigh-ins', query: {..._scope, 'flockId': '$id'});
      if (!mounted || id != _selectedId) return;
      final list = res is List ? res : const [];
      setState(() => _rows = [for (final r in list) if (r is Map) WeighIn(r)]);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load the weigh-ins.');
    } finally {
      if (mounted) setState(() => _rowsLoading = false);
    }
  }

  void _selectFlock(int id) {
    setState(() {
      _picked = id;
      _rows = const [];
    });
    _loadRows();
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _openForm(WeighIn? existing) async {
    final selected = _selected;
    if (selected == null) return;
    final savedFlock = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WeighInDialog(
        session: widget.session,
        company: widget.company,
        flocks: _openFlocks,
        defaultFlockId: _i(selected['flockId']),
        existing: existing,
        maxDate: _today ?? isoDay(DateTime.now()),
      ),
    );
    if (savedFlock == null || !mounted) return;
    if (savedFlock != _selectedId) {
      _selectFlock(savedFlock);
    } else {
      await _loadRows();
    }
  }

  Future<void> _delete(WeighIn r) async {
    final reason = await showReasonDialog(
      context,
      title: 'Delete this weigh-in?',
      description: '${formatWeight(r.avgWeightG)} on ${weighDateLabel(r.weighDate)}. '
          'It is kept in the record as deleted, with your reason.',
      confirmLabel: 'Delete weigh-in',
      destructive: true,
      options: weighInDeleteReasons,
    );
    if (reason == null || !mounted) return;
    try {
      await widget.session.farmClient.delete('/api/Poultry/weigh-ins/${r.id}', query: {..._scope, 'reason': reason});
      if (!mounted) return;
      _snack('Weigh-in deleted');
      await _loadRows();
    } on ApiException catch (e) {
      if (mounted) _snack('Not deleted: ${e.message}');
    } catch (e) {
      if (mounted) _snack('Not deleted: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-weigh-ins');
    final selected = _selected;
    final latest = _rows.isEmpty ? null : _rows.last;
    final birds = _rows.fold<int>(0, (a, r) => a + r.sampleSize);
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Weigh-ins')),
      body: RefreshIndicator(
        onRefresh: _loadRows,
        child: ListView(key: const ValueKey('weigh-ins-list'), padding: const EdgeInsets.fromLTRB(14, 16, 14, 28), children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: _orange100, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.scale_outlined, size: 20, color: _orange700),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Weigh-ins', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: _slate900)),
                Text('Weigh a sample of birds to follow how a flock is growing.',
                    style: TextStyle(fontSize: 13.5, color: _slate600)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const ValueKey('weigh-in-new'),
              style: FilledButton.styleFrom(backgroundColor: Tone.button(const Tone.bg(0xFFF97316)), foregroundColor: Colors.white),
              onPressed: selected == null || _isClosed ? null : () => _openForm(null),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New weigh-in'),
            ),
          ),
          const SizedBox(height: 14),
          _card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FilterLabel('Flock', _flockSelect()),
            if (selected != null) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (isBroilerFlock(selected)) const BroilerBadge(),
                if ('${selected['breed'] ?? ''}'.isNotEmpty)
                  Text('${selected['breed']}', style: const TextStyle(fontSize: 13.5, color: _slate600)),
                Text('· started ${weighDateLabel(selected['startDate'])}', style: const TextStyle(fontSize: 13.5, color: _slate600)),
                if (_isClosed) _pill('Closed: weigh-ins are read-only'),
              ]),
            ],
          ])),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Tone.bg(0xFFFEF2F2),
                border: Border.all(color: const Tone.line(0xFFFECACA)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(_error, style: const TextStyle(fontSize: 13.5, color: Tone.fg(0xFFB91C1C))),
            ),
          ],
          const SizedBox(height: 12),
          // ---- Headline figures
          _tiles([
            _Tile('Latest average', latest == null ? '—' : formatWeight(latest.avgWeightG),
                latest == null ? 'No weigh-ins yet' : 'Day ${latest.ageInDays} · ${weighDateLabel(latest.weighDate)}'),
            _Tile('Gain per day', latest?.dailyGainG == null ? '—' : '${latest!.dailyGainG!.toStringAsFixed(1)} g',
                (latest?.daysSincePrev ?? 0) > 0 ? 'over the last ${latest!.daysSincePrev} days' : 'Needs two weigh-ins'),
            _Tile('Uniformity', _pct(latest?.uniformityPct), 'Birds within ±10% of the average'),
            _Tile('Weigh-ins', '${_rows.length}', _rows.isEmpty ? '—' : '${_thousands(birds)} birds weighed'),
          ]),
          const SizedBox(height: 12),
          // ---- Growth curve
          _card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Average weight by age', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _slate900)),
            const SizedBox(height: 2),
            const Text('Each point is one weigh-in. Tap a point for the details.', style: TextStyle(fontSize: 12, color: _slate500)),
            const SizedBox(height: 12),
            if (_rowsLoading || _flocksLoading)
              const SizedBox(height: 200, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
            else if (_rows.isEmpty)
              Container(
                height: 140,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: _slate200),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(selected != null ? 'No weigh-ins for this flock yet.' : 'Choose a flock.',
                    style: const TextStyle(fontSize: 13.5, color: _slate500)),
              )
            else
              GrowthChart(key: ValueKey('growth-$_selectedId'), rows: _rows),
          ])),
          // ---- The weigh-ins, newest first
          if (_rows.isNotEmpty) ...[
            const SizedBox(height: 12),
            _card(
              Column(children: [
                for (final (i, r) in _rows.reversed.indexed) ...[
                  if (i > 0) const Divider(height: 1, color: _slate200),
                  _row(r),
                ],
              ]),
              padding: EdgeInsets.zero,
            ),
          ],
        ]),
      ),
    );
  }

  Widget _flockSelect() {
    final open = _openFlocks, closed = _closedFlocks;
    final id = _selectedId;
    return AppSelect<String>(
      key: const ValueKey('weigh-in-flock'),
      value: id == 0 ? null : '$id',
      enabled: !_flocksLoading && _flocks.isNotEmpty,
      hintText: _flocksLoading ? 'Loading flocks…' : 'No flocks yet',
      items: [
        if (open.isNotEmpty) const AppSelectItem(value: '__running__', label: 'Running', enabled: false),
        for (final f in open)
          AppSelectItem(value: '${f['flockId']}', label: '${f['name'] ?? ''}${isBroilerFlock(f) ? ' · Broiler' : ''}'),
        if (closed.isNotEmpty) const AppSelectItem(value: '__closed__', label: 'Closed', enabled: false),
        for (final f in closed) AppSelectItem(value: '${f['flockId']}', label: '${f['name'] ?? ''}'),
      ],
      onChanged: (v) {
        final n = int.tryParse(v ?? '');
        if (n != null && n != _selectedId) _selectFlock(n);
      },
    );
  }

  /// The web's phone card for one weigh-in.
  Widget _row(WeighIn r) {
    final gain = r.dailyGainG == null ? '—' : '${r.dailyGainG!.toStringAsFixed(1)} g/day';
    return Padding(
      key: ValueKey('weigh-in-${r.id}'),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(TextSpan(children: [
              TextSpan(text: formatWeight(r.avgWeightG), style: const TextStyle(fontWeight: FontWeight.w600, color: _slate900)),
              TextSpan(text: ' · day ${r.ageInDays}', style: const TextStyle(color: _slate500)),
            ]), style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 2),
            Text('${weighDateLabel(r.weighDate)} · ${r.sampleSize} birds', style: const TextStyle(fontSize: 13.5, color: _slate600)),
            const SizedBox(height: 2),
            Text('Gain $gain · Uniformity ${_pct(r.uniformityPct)}', style: const TextStyle(fontSize: 12, color: _slate500)),
          ]),
        ),
        IconButton(
          tooltip: 'Edit weigh-in',
          onPressed: _isClosed ? null : () => _openForm(r),
          icon: const Icon(Icons.edit_outlined, size: 18),
        ),
        IconButton(
          tooltip: 'Delete weigh-in',
          onPressed: _isClosed ? null : () => _delete(r),
          icon: Icon(Icons.delete_outline, size: 18, color: _isClosed ? null : const Tone.fg(0xFFDC2626)),
        ),
      ]),
    );
  }

  Widget _card(Widget child, {EdgeInsets padding = const EdgeInsets.all(14)}) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: const Tone.bg(0xFFFFFFFF),
          border: Border.all(color: _slate200),
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      );

  Widget _pill(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: const Tone.bg(0xFFF1F5F9), borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Tone.fg(0xFF0F172A))),
      );

  /// Two per row, as the web's grid-cols-2 on a phone.
  Widget _tiles(List<_Tile> tiles) => Column(children: [
        for (var i = 0; i < tiles.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: _tile(tiles[i])),
              const SizedBox(width: 10),
              Expanded(child: i + 1 < tiles.length ? _tile(tiles[i + 1]) : const SizedBox()),
            ]),
          ),
        ],
      ]);

  Widget _tile(_Tile t) => _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t.label.toUpperCase(),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: .5, color: _slate500)),
        const SizedBox(height: 4),
        Text(t.value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: _slate900)),
        const SizedBox(height: 2),
        Text(t.sub, style: const TextStyle(fontSize: 12, color: _slate500)),
      ]));
}

class _Tile {
  const _Tile(this.label, this.value, this.sub);
  final String label, value, sub;
}

// ---------------------------------------------------------------- the chart

/// One series, one axis: average weight (g) against age (days). Thin line,
/// visible points, recessive grid. Tapping a point shows what the web's
/// hover tooltip shows.
class GrowthChart extends StatefulWidget {
  const GrowthChart({super.key, required this.rows});
  final List<WeighIn> rows;

  @override
  State<GrowthChart> createState() => _GrowthChartState();
}

class _GrowthChartState extends State<GrowthChart> {
  int? _picked;
  static const _height = 256.0;

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    final p = _picked == null || _picked! >= rows.length ? null : rows[_picked!];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (p != null)
        Container(
          key: const ValueKey('growth-tooltip'),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Tone.bg(0xFFFFFFFF),
            border: Border.all(color: _slate200),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Day ${p.ageInDays} · ${weighDateLabel(p.weighDate)}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _slate900)),
            const SizedBox(height: 2),
            Text.rich(TextSpan(children: [
              const TextSpan(text: 'Average '),
              TextSpan(text: formatWeight(p.avgWeightG), style: const TextStyle(fontWeight: FontWeight.w700)),
            ]), style: const TextStyle(fontSize: 12, color: Tone.fg(0xFF334155))),
            if (p.dailyGainG != null)
              Text('Gain ${p.dailyGainG!.toStringAsFixed(1)} g/day', style: const TextStyle(fontSize: 12, color: _slate600)),
            Text('${p.sampleSize} birds${p.uniformityPct != null ? ' · uniformity ${p.uniformityPct!.toStringAsFixed(1)}%' : ''}',
                style: const TextStyle(fontSize: 12, color: _slate600)),
          ]),
        ),
      Semantics(
        label: 'Average weight by age in days',
        child: LayoutBuilder(
          builder: (_, box) {
            final geo = _GrowthGeometry(rows, Size(box.maxWidth, _height));
            return GestureDetector(
              onTapDown: (e) {
                final i = geo.nearest(e.localPosition);
                setState(() => _picked = i == null || i == _picked ? null : i);
              },
              child: CustomPaint(
                size: Size(box.maxWidth, _height),
                painter: _GrowthPainter(geo, _picked, DefaultTextStyle.of(context).style.fontFamily),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

/// Where everything sits: x by age between the first and last weigh-in,
/// y from 0 to a round number above the heaviest average.
class _GrowthGeometry {
  _GrowthGeometry(this.rows, this.size) {
    final ages = rows.map((r) => r.ageInDays);
    minAge = ages.reduce(math.min);
    maxAge = ages.reduce(math.max);
    final hi = rows.map((r) => r.avgWeightG).reduce(math.max);
    step = _niceStep(hi <= 0 ? 1 : hi / 4);
    top = step * (hi / step).ceil().clamp(1, 1 << 30);
  }
  final List<WeighIn> rows;
  final Size size;
  late final int minAge, maxAge;
  late final double step, top;

  static const left = 64.0, right = 16.0, topPad = 8.0, bottom = 40.0;

  double get plotW => size.width - left - right;
  double get plotH => size.height - topPad - bottom;

  double x(int age) => maxAge == minAge ? left + plotW / 2 : left + plotW * (age - minAge) / (maxAge - minAge);
  double y(double g) => topPad + plotH * (1 - g / top);
  Offset pt(int i) => Offset(x(rows[i].ageInDays), y(rows[i].avgWeightG));

  int? nearest(Offset tap) {
    int? best;
    var bestD = double.infinity;
    for (var i = 0; i < rows.length; i++) {
      final d = (pt(i) - tap).distance;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return bestD <= 40 ? best : null;
  }

  /// 1, 2, 2.5 or 5 × a power of ten, as a chart library picks ticks.
  static double _niceStep(double raw) {
    final p = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    for (final m in [1.0, 2.0, 2.5, 5.0, 10.0]) {
      if (m * p >= raw) return m * p;
    }
    return 10 * p;
  }

  /// Whole-day ticks across the age range, at most about five.
  List<int> get ageTicks {
    if (maxAge == minAge) return [minAge];
    final span = maxAge - minAge;
    final s = math.max(1, _niceStep(span / 4).ceil());
    final first = (minAge / s).ceil() * s;
    return [for (var a = first; a <= maxAge; a += s) a];
  }
}

class _GrowthPainter extends CustomPainter {
  _GrowthPainter(this.g, this.picked, this.font);
  final _GrowthGeometry g;
  final int? picked;
  final String? font;

  void _text(Canvas c, String s, Offset at, {bool right = false, bool centre = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: 12, color: _slate500, fontFamily: font)),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = right ? at.dx - tp.width : (centre ? at.dx - tp.width / 2 : at.dx);
    tp.paint(c, Offset(dx, at.dy - tp.height / 2));
  }

  static String _yLabel(double v) =>
      v >= 1000 ? '${(v / 1000).toStringAsFixed(1)} kg' : '${jsNum(v)} g';

  @override
  void paint(Canvas canvas, Size size) {
    const left = _GrowthGeometry.left;
    final grid = Paint()
      ..color = _slate200
      ..strokeWidth = 1;
    // Dashed horizontal grid lines and the weight ticks.
    for (var v = 0.0; v <= g.top + .001; v += g.step) {
      final yy = g.y(v);
      for (var x = left; x < size.width - _GrowthGeometry.right; x += 6) {
        canvas.drawLine(Offset(x, yy), Offset(math.min(x + 3, size.width - _GrowthGeometry.right), yy), grid);
      }
      _text(canvas, _yLabel(v), Offset(left - 8, yy), right: true);
    }
    // The age axis.
    final axisY = g.y(0);
    canvas.drawLine(Offset(left, axisY), Offset(size.width - _GrowthGeometry.right, axisY), Paint()..color = _slate300);
    for (final a in g.ageTicks) {
      _text(canvas, '$a', Offset(g.x(a), axisY + 10), centre: true);
    }
    _text(canvas, 'Age (days)', Offset(left + g.plotW / 2, size.height - 9), centre: true);

    // The line, then the points on top.
    final line = Paint()
      ..color = _line
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final path = Path()..moveTo(g.pt(0).dx, g.pt(0).dy);
    for (var i = 1; i < g.rows.length; i++) {
      path.lineTo(g.pt(i).dx, g.pt(i).dy);
    }
    if (g.rows.length > 1) canvas.drawPath(path, line);
    for (var i = 0; i < g.rows.length; i++) {
      final on = picked == i;
      canvas.drawCircle(g.pt(i), on ? 7 : 5, Paint()..color = const Tone.bg(0xFFFFFFFF));
      canvas.drawCircle(g.pt(i), on ? 5 : 3.5, Paint()..color = _line);
    }
  }

  @override
  bool shouldRepaint(_GrowthPainter o) => o.picked != picked || o.g.rows != g.rows || o.g.size != g.size;
}

// ---------------------------------------------------------------- the form

enum _Mode { birds, summary }

/// New / Edit weigh-in. Pops with the flock id it was saved on.
class WeighInDialog extends StatefulWidget {
  const WeighInDialog({
    super.key,
    required this.session,
    required this.company,
    required this.flocks,
    required this.defaultFlockId,
    required this.existing,
    required this.maxDate,
  });

  final Session session;
  final Company company;
  final List<Map<String, dynamic>> flocks;
  final int defaultFlockId;
  final WeighIn? existing;

  /// The company's business date: no weigh-in after today.
  final String maxDate;

  @override
  State<WeighInDialog> createState() => _WeighInDialogState();
}

class _WeighInDialogState extends State<WeighInDialog> {
  late int _flockId = widget.existing?.flockId ?? widget.defaultFlockId;
  late String _date = widget.existing != null && widget.existing!.weighDate.length >= 10
      ? widget.existing!.weighDate.substring(0, 10)
      : widget.maxDate;
  late _Mode _mode = _summaryOnly ? _Mode.summary : _Mode.birds;
  WeightUnit _unit = WeightUnit.g;
  bool _saving = false;

  late final _weights = TextEditingController(text: widget.existing?.weightsG?.map(jsNum).join(' ') ?? '');
  late final _sample = TextEditingController(text: _summaryOnly ? '${widget.existing!.sampleSize}' : '');
  late final _avg = TextEditingController(text: _summaryOnly ? jsNum(widget.existing!.avgWeightG) : '');
  late final _uniformity = TextEditingController(text: _from(widget.existing?.uniformityPct));
  late final _cv = TextEditingController(text: _from(widget.existing?.cvPct));
  late final _minW = TextEditingController(text: _from(widget.existing?.minWeightG));
  late final _maxW = TextEditingController(text: _from(widget.existing?.maxWeightG));
  late final _notes = TextEditingController(text: widget.existing?.notes ?? '');

  /// An existing weigh-in recorded as a summary, with no bird weights.
  bool get _summaryOnly => widget.existing != null && (widget.existing!.weightsG?.isEmpty ?? true);

  String _from(double? v) => v != null && _summaryOnly ? jsNum(v) : '';

  @override
  void dispose() {
    for (final c in [_weights, _sample, _avg, _uniformity, _cv, _minW, _maxW, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  ParsedWeights get _parsed => parseWeights(_weights.text, _unit);

  Map<String, dynamic>? get _flock => widget.flocks.where((f) => _i(f['flockId']) == _flockId).firstOrNull;

  static double? _num(String s) => s.trim().isEmpty ? null : double.tryParse(s.trim());

  String? get _problem {
    if (_flockId == 0) return 'Choose the flock.';
    if (_date.isEmpty) return 'Choose the date.';
    if (_mode == _Mode.birds) {
      final p = _parsed;
      if (p.invalid.isNotEmpty) {
        return 'Not a weight: ${p.invalid.take(3).join(', ')}${p.invalid.length > 3 ? '…' : ''}';
      }
      if (p.weightsG.isEmpty) return "Enter each bird's weight.";
    } else {
      if (!((_num(_sample.text) ?? 0) >= 1)) return 'Enter how many birds were weighed.';
      if (!((_num(_avg.text) ?? 0) > 0)) return 'Enter the average weight in grams.';
    }
    return null;
  }

  Future<void> _save() async {
    if (_problem != null) return;
    setState(() => _saving = true);
    final notes = _notes.text.isEmpty ? null : _notes.text;
    final body = <String, dynamic>{
      'flockId': _flockId,
      'weighDate': _date,
      if (_mode == _Mode.birds) ...{
        'weightsG': _parsed.weightsG,
      } else ...{
        'sampleSize': _num(_sample.text),
        'avgWeightG': _num(_avg.text),
        'uniformityPct': _num(_uniformity.text),
        'cvPct': _num(_cv.text),
        'minWeightG': _num(_minW.text),
        'maxWeightG': _num(_maxW.text),
      },
      'notes': notes,
      'farmId': widget.company.farmId,
    };
    final messenger = ScaffoldMessenger.of(context);
    try {
      final client = widget.session.farmClient;
      final existing = widget.existing;
      if (existing != null) {
        await client.put('/api/Poultry/weigh-ins/${existing.id}', body: body);
      } else {
        await client.post('/api/Poultry/weigh-ins', body: body);
      }
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(existing != null ? 'Weigh-in updated' : 'Weigh-in saved')));
      Navigator.of(context).pop(_flockId);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('Not saved: ${e.message}')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('Not saved: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    final preview = _mode == _Mode.birds ? computeWeighInStats(_parsed.weightsG) : null;
    final minDate = DateTime.tryParse('${_flock?['startDate'] ?? ''}'.split('T').first);
    final maxDate = DateTime.tryParse(widget.maxDate);
    final typed = _weights.text.isNotEmpty || _sample.text.isNotEmpty || _avg.text.isNotEmpty;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: FormDialogTitle(
          icon: Icons.scale_outlined,
          color: FormColor.amber,
          text: widget.existing != null ? 'Edit weigh-in' : 'New weigh-in',
        ),
        content: SizedBox(
          width: 672,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Weigh a sample of birds spread across the house, not just the ones nearest the door.',
                style: TextStyle(fontSize: 13.5, color: _slate500)),
            const SizedBox(height: 16),
            TintedSection(title: 'Flock & date', color: FormColor.orange, children: [
              FormPair(
                stackOnMobile: true,
                FilterLabel(
                  'Flock',
                  AppSelect<String>(
                    key: const ValueKey('weigh-in-dialog-flock'),
                    value: '$_flockId',
                    enabled: !_saving,
                    items: [
                      for (final f in widget.flocks)
                        AppSelectItem(value: '${f['flockId']}', label: '${f['name'] ?? ''}${isBroilerFlock(f) ? ' · Broiler' : ''}'),
                    ],
                    onChanged: (v) => setState(() => _flockId = int.tryParse(v ?? '') ?? _flockId),
                  ),
                ),
                FilterLabel(
                  'Date weighed',
                  AppDateField(
                    value: DateTime.tryParse(_date),
                    firstDate: minDate,
                    lastDate: maxDate,
                    enabled: !_saving,
                    onChanged: (d) => setState(() => _date = d == null ? '' : isoDay(d)),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            TintedSection(
              title: 'Weights',
              color: FormColor.amber,
              action: _toggle<_Mode>(
                const [(_Mode.birds, 'Bird by bird'), (_Mode.summary, 'Summary only')],
                _mode,
                (m) => setState(() => _mode = m),
                onBand: true,
              ),
              children: [
                if (_mode == _Mode.birds) ..._birds(preview) else ..._summary(),
              ],
            ),
            const SizedBox(height: 16),
            TintedSection(title: 'Notes', color: FormColor.slate, children: [
              AppTextarea(
                controller: _notes,
                rows: 2,
                enabled: !_saving,
                hintText: 'Anything unusual: feed change, heat, a sick pen…',
              ),
            ]),
            if (problem != null && typed) ...[
              const SizedBox(height: 12),
              Text(problem, key: const ValueKey('weigh-in-problem'), style: const TextStyle(fontSize: 13.5, color: Tone.fg(0xFFB45309))),
            ],
          ]),
        ),
        actions: [
          FormDialogFooter(onCancel: () => Navigator.of(context).pop(), cancelDisabled: _saving, children: [
            FilledButton(
              key: const ValueKey('weigh-in-save'),
              style: formPrimary(FormColor.amber),
              onPressed: _saving || problem != null ? null : _save,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (_saving) ...[
                  const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(widget.existing != null ? 'Save changes' : 'Save weigh-in', overflow: TextOverflow.ellipsis),
                ),
              ]),
            ),
          ]),
        ],
      ),
    );
  }

  List<Widget> _birds(WeighInStats? preview) => [
        // A Wrap, not a Row: on a narrow phone the unit switch drops under
        // the label instead of squeezing it.
        Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.end, spacing: 8, runSpacing: 6, children: [
          const Text('One weight per bird',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: Tone.fg(0xFF334155))),
          _toggle<WeightUnit>(
            const [(WeightUnit.g, 'grams'), (WeightUnit.kg, 'kilograms')],
            _unit,
            (u) => setState(() => _unit = u),
          ),
        ]),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('weigh-in-weights'),
          controller: _weights,
          enabled: !_saving,
          minLines: 5,
          maxLines: 8,
          keyboardType: TextInputType.text,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
          decoration: InputDecoration(
            hintText: _unit == WeightUnit.g ? '1850 1920 1780 2010 …' : '1.85 1.92 1.78 2.01 …',
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Separate birds with spaces, commas or new lines.${_unit == WeightUnit.kg ? ' Use a point for decimals (1.85).' : ''}',
          style: const TextStyle(fontSize: 12, color: _slate500),
        ),
        if (preview != null) ...[
          const SizedBox(height: 10),
          Container(
            key: const ValueKey('weigh-in-preview'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Tone.bg(0xFFFFFFFF),
              border: Border.all(color: const Tone.line(0xFFFDE68A)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(children: [
              Row(children: [
                Expanded(child: _fig('Birds', '${preview.sampleSize}')),
                Expanded(child: _fig('Average', formatWeight(preview.avgWeightG))),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _fig('Uniformity', _pct(preview.uniformityPct))),
                Expanded(child: _fig('CV', _pct(preview.cvPct, 2))),
              ]),
            ]),
          ),
        ],
      ];

  List<Widget> _summary() => [
        FormPair(_field('Birds weighed *', _sample, whole: true), _field('Average (g) *', _avg)),
        FormPair(_field('Uniformity (%)', _uniformity), _field('CV (%)', _cv)),
        FormPair(_field('Lightest (g)', _minW), _field('Heaviest (g)', _maxW)),
      ];

  Widget _field(String label, TextEditingController c, {bool whole = false}) => FilterLabel(
        label,
        AppInput(
          controller: c,
          enabled: !_saving,
          keyboardType: TextInputType.numberWithOptions(decimal: !whole),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(whole ? r'^\d*' : r'^\d*\.?\d*'))],
          onChanged: (_) => setState(() {}),
        ),
      );

  Widget _fig(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 12, color: _slate500)),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _slate900)),
      ]);

  /// The web's small two-way radio: on the amber band (white on tint) or on
  /// the form (amber when picked).
  /// Shrinks to fit rather than overflow on a narrow phone or large text.
  Widget _toggle<T>(List<(T, String)> options, T value, ValueChanged<T> onChanged, {bool onBand = false}) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: _toggleBody<T>(options, value, onChanged, onBand: onBand),
      );

  Widget _toggleBody<T>(List<(T, String)> options, T value, ValueChanged<T> onChanged, {bool onBand = false}) => Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: onBand ? const Tone.bg(0x33FFFFFF) : const Tone.bg(0xFFFFFFFF),
          border: onBand ? null : Border.all(color: _slate200),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final (v, label) in options)
            Semantics(
              inMutuallyExclusiveGroup: true,
              checked: v == value,
              button: true,
              child: InkWell(
                key: ValueKey('toggle-$label'),
                borderRadius: BorderRadius.circular(4),
                onTap: _saving ? null : () => onChanged(v),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: v == value
                        ? (onBand ? const Tone.bg(0xFFFFFFFF) : Tone.button(const Tone.bg(0xFFF59E0B)))
                        : null,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: v == value
                          ? (onBand ? const Tone.fg(0xFFB45309) : Colors.white)
                          : (onBand ? Colors.white : _slate600),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      );
}

const _line = Tone.fg(0xFFEA580C); // orange-600, the poultry accent
const _orange100 = Tone.bg(0xFFFFEDD5);
const _orange700 = Tone.fg(0xFFC2410C);
const _slate200 = Tone.line(0xFFE2E8F0);
const _slate300 = Tone.line(0xFFCBD5E1);
const _slate500 = Tone.fg(0xFF64748B);
const _slate600 = Tone.fg(0xFF475569);
const _slate900 = Tone.fg(0xFF0F172A);
