// Add / Edit Flock's bird history (413 / 414), as the web's
// components/poultry/existing-flock-fields.tsx, flock-history-panel.tsx,
// house-picker.tsx and BatchAvailability in components/setup-views/flocks.tsx.
// The server applies the same rules; these only show the numbers first.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../shared/business_dates.dart' show fmtNum, fmtInstant, isoDay;
import 'trackers/tracker_logic.dart' show trackerDate;
import 'bird_reconciliation.dart';
import 'setup/houses_screen.dart' show houseOccupancy, HouseOccupancy;

import 'package:poultrycore_mobile/design/tone.dart';

const _slate400 = Tone.fg(0xFF94A3B8);
const _slate500 = Tone.fg(0xFF64748B);
const _slate600 = Tone.fg(0xFF475569);
const _slate700 = Tone.fg(0xFF334155);
const _slate800 = Tone.fg(0xFF1E293B);
const _slate900 = Tone.fg(0xFF0F172A);
const _slate200 = Tone.line(0xFFE2E8F0);
const _slate50 = Tone.bg(0xFFF8FAFC);
const _amber700 = Tone.fg(0xFFB45309);
const _emerald700 = Tone.fg(0xFF047857);
const _red600 = Tone.fg(0xFFDC2626);
const _indigo700 = Tone.fg(0xFF4338CA);

String _n(num? v) => fmtNum(v ?? 0, 0);
int _num(String s) => (num.tryParse(s.trim()) ?? 0).truncate().clamp(0, 1 << 31);
int _i(Object? v) => v is num ? v.truncate() : (num.tryParse('${v ?? ''}')?.truncate() ?? 0);

// ---- New flock vs existing flock -------------------------------------------

/// FlockModeSelector: "Is this a new or an existing flock?"
class FlockModeSelector extends StatelessWidget {
  const FlockModeSelector({super.key, required this.existing, this.onChanged});
  final bool existing;

  /// Null = read-only (Edit Flock shows how the flock was registered).
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    Widget opt(bool value, String title, String hint) {
      final on = existing == value;
      return InkWell(
        key: ValueKey(value ? 'flock-mode-existing' : 'flock-mode-new'),
        borderRadius: BorderRadius.circular(8),
        onTap: onChanged == null ? null : () => onChanged!(value),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: on ? const Tone.bg(0xFFEFF6FF) : Tone.bg(0xFFFFFFFF),
            border: Border.all(color: on ? const Tone.line(0xFF3B82F6) : _slate200),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Opacity(
            opacity: onChanged == null && !on ? .6 : 1,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(on ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 18,
                  color: on ? const Tone.fg(0xFF2563EB) : _slate400),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: _slate900)),
                  Text(hint, style: const TextStyle(fontSize: 12, color: _slate500)),
                ]),
              ),
            ]),
          ),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      opt(false, 'New flock — birds being placed now', 'Birds now = birds placed from the batch.'),
      const SizedBox(height: 8),
      opt(true, 'Existing flock — already operating', 'Some birds have already died, been sold or moved.'),
    ]);
  }
}

/// ExistingFlockDraft: what Add Flock asks about an existing flock.
class ExistingFlockDraft {
  ExistingFlockDraft(this.asOfDate);
  String currentLiveBirds = '';
  bool historyKnown = true;
  String mortality = '', sold = '', culled = '', transferred = '';

  /// yyyy-MM-dd.
  String asOfDate;
}

/// existingFlockHistory: the body for POST /api/Flock/existing, or why not.
({String? problem, Map<String, dynamic> history}) existingFlockHistory(int placed, ExistingFlockDraft d) {
  final p = previewFlockHistory(
    originallyPlaced: placed,
    currentLiveBirds: d.currentLiveBirds,
    historyKnown: d.historyKnown,
    mortality: d.mortality,
    sold: d.sold,
    culled: d.culled,
    transferred: d.transferred,
  );
  return (
    problem: p.problem ??
        (d.currentLiveBirds.trim().isEmpty
            ? 'Enter how many birds are remaining today.'
            : d.asOfDate.isEmpty
                ? 'Enter the date the birds were counted.'
                : null),
    history: {
      'originallyPlaced': p.placed,
      'currentLiveBirds': p.live,
      'historyKnown': d.historyKnown,
      'historicalMortality': d.historyKnown ? _num(d.mortality) : 0,
      'historicalSold': d.historyKnown ? _num(d.sold) : 0,
      'historicalCulled': d.historyKnown ? _num(d.culled) : 0,
      'historicalTransferred': d.historyKnown ? _num(d.transferred) : 0,
    },
  );
}

Widget _numBox(String value, ValueChanged<String> on, {Key? key, bool enabled = true}) => _NumBox(key: key, value: value, onChanged: on, enabled: enabled);

/// A whole-number box that keeps its own controller (the drafts hold strings).
class _NumBox extends StatefulWidget {
  const _NumBox({super.key, required this.value, required this.onChanged, this.enabled = true});
  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;
  @override
  State<_NumBox> createState() => _NumBoxState();
}

class _NumBoxState extends State<_NumBox> {
  late final _c = TextEditingController(text: widget.value);
  @override
  void didUpdateWidget(_NumBox old) {
    super.didUpdateWidget(old);
    if (widget.value != _c.text) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppInput(
        controller: _c,
        enabled: widget.enabled,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: widget.onChanged,
      );
}

Widget _label(String text, Widget child, {double size = 14}) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(text, style: TextStyle(fontSize: size, fontWeight: FontWeight.w500, color: size < 14 ? _slate600 : _slate700)),
      const SizedBox(height: 4),
      child,
    ]);

Widget _figureBox(String text, {Color color = _slate700, bool bold = false, Color? bg}) => Container(
      height: 40,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: bg ?? Tone.bg(0xFFFFFFFF), border: Border.all(color: _slate200), borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontWeight: bold ? FontWeight.w600 : FontWeight.w400, color: color)),
    );

/// Two cells per row: phones have no room for the web's three or five.
Widget _pairs(List<Widget> cells) => Column(children: [
      for (var i = 0; i < cells.length; i += 2)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: cells[i]),
            const SizedBox(width: 10),
            Expanded(child: i + 1 < cells.length ? cells[i + 1] : const SizedBox()),
          ]),
        ),
    ]);

/// ExistingFlockFields: birds remaining, counted on, the difference and
/// what happened to it. [placed] is the form's "Birds Originally Placed".
class ExistingFlockFields extends StatelessWidget {
  const ExistingFlockFields({super.key, required this.placed, required this.draft, required this.onChanged, this.enabled = true});
  final int placed;
  final ExistingFlockDraft draft;
  final VoidCallback onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = previewFlockHistory(
      originallyPlaced: placed,
      currentLiveBirds: draft.currentLiveBirds,
      historyKnown: draft.historyKnown,
      mortality: draft.mortality,
      sold: draft.sold,
      culled: draft.culled,
      transferred: draft.transferred,
    );
    void set(VoidCallback f) {
      f();
      onChanged();
    }

    final message = p.problem ??
        (p.difference == 0
            ? 'No birds are missing: the flock starts with every bird placed.'
            : '${_n(placed)} placed from the batch, ${_n(p.live)} standing now. The ${_n(p.difference)} gone are recorded once, '
                "as this flock's opening history — not as today's deaths and not as a sale. "
                '${p.other > 0 ? '${_n(p.other)} unexplained are recorded as “other”, never as mortality.' : ''}');
    return Container(
      key: const ValueKey('existing-flock-fields'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Tone.bg(0x80FFFBEB),
        border: Border.all(color: const Tone.line(0xFFFDE68A)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _pairs([
          _label('Birds remaining now *', _numBox(draft.currentLiveBirds, (v) => set(() => draft.currentLiveBirds = v), key: const ValueKey('existing-live'), enabled: enabled)),
          _label(
            'Counted on *',
            AppDateField(
              value: DateTime.tryParse(draft.asOfDate),
              enabled: enabled,
              lastDate: DateTime.now(),
              onChanged: (d) => set(() => draft.asOfDate = d == null ? '' : isoDay(d)),
            ),
          ),
          _label('Historical difference', _figureBox(_n(p.difference), color: _amber700, bold: true)),
        ]),
        if (p.difference > 0) ...[
          InkWell(
            key: const ValueKey('existing-unknown'),
            onTap: !enabled
                ? null
                : () => set(() {
                      if (draft.historyKnown) {
                        draft
                          ..historyKnown = false
                          ..mortality = ''
                          ..sold = ''
                          ..culled = ''
                          ..transferred = '';
                      } else {
                        draft.historyKnown = true;
                      }
                    }),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Icon(!draft.historyKnown ? Icons.check_box : Icons.check_box_outline_blank, size: 20, color: _slate600),
                const SizedBox(width: 8),
                const Expanded(child: Text("I don't know what happened to them", style: TextStyle(fontSize: 14, color: _slate700))),
              ]),
            ),
          ),
          if (draft.historyKnown) ...[
            const SizedBox(height: 6),
            _pairs([
              _label('Historical mortality', _numBox(draft.mortality, (v) => set(() => draft.mortality = v), key: const ValueKey('existing-mortality'), enabled: enabled), size: 12),
              _label('Previously sold', _numBox(draft.sold, (v) => set(() => draft.sold = v), key: const ValueKey('existing-sold'), enabled: enabled), size: 12),
              _label('Culled', _numBox(draft.culled, (v) => set(() => draft.culled = v), key: const ValueKey('existing-culled'), enabled: enabled), size: 12),
              _label('Transferred out', _numBox(draft.transferred, (v) => set(() => draft.transferred = v), key: const ValueKey('existing-transferred'), enabled: enabled), size: 12),
              _label('Other / unknown', _figureBox(_n(p.other), bg: _slate50), size: 12),
            ]),
          ],
        ],
        Text(message, key: const ValueKey('existing-message'), style: TextStyle(fontSize: 12, color: p.problem != null ? _red600 : _slate600)),
      ]),
    );
  }
}

// ---- Batch availability -------------------------------------------------------

/// BatchAvailability: where a batch's birds are, and how many are free.
class BatchAvailability extends StatelessWidget {
  const BatchAvailability({super.key, required this.size, required this.free, this.recon, this.ownBirds = 0});
  final int size, free, ownBirds;
  final Map? recon;

  @override
  Widget build(BuildContext context) {
    final r = recon;
    final inFlocks = r != null ? _i(r['originallyAllocated']) : (size - free).clamp(0, 1 << 31);
    final sold = r != null ? _i(r['batchSold']) : 0;
    final lost = r != null ? _i(r['batchMortality']) + _i(r['batchCulled']) + _i(r['batchTransferred']) + _i(r['batchOtherRemovals']) : 0;
    final segs = [
      ('in flocks', inFlocks, const Tone.bg(0xFF10B981)),
      ('sold before placing', sold, const Tone.bg(0xFFFB923C)),
      ('died or removed before placing', lost, const Tone.bg(0xFFFB7185)),
      ('free to place', free, const Tone.bg(0xFF6366F1)),
    ];
    final sum = segs.fold<int>(0, (a, g) => a + g.$2);
    final total = [size, sum, 1].reduce((a, b) => a > b ? a : b);
    final max = ownBirds + free;
    return Container(
      key: const ValueKey('batch-availability'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: _slate50, border: Border.all(color: _slate200), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: free > 0
                ? Text('${_n(free)} birds free to place', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _indigo700))
                : const Text('No birds left to place', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _slate700)),
          ),
          Text('Batch of ${_n(size)}', style: const TextStyle(fontSize: 12, color: _slate500)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: Container(
            height: 6,
            color: _slate200,
            child: Row(children: [
              for (final g in segs)
                if (g.$2 > 0) Expanded(flex: (g.$2 * 1000 ~/ total).clamp(1, 1000), child: Container(color: g.$3, margin: const EdgeInsets.only(right: 1))),
              if (sum < total) Expanded(flex: ((total - sum) * 1000 ~/ total).clamp(1, 1000), child: const SizedBox()),
            ]),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 12, runSpacing: 2, children: [
          for (final g in segs)
            if (g.$2 > 0 && g.$1 != 'free to place')
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: g.$3, shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Flexible(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: _n(g.$2), style: const TextStyle(fontWeight: FontWeight.w500, color: _slate800)),
                    TextSpan(text: ' ${g.$1}'),
                  ]), style: const TextStyle(fontSize: 12, color: _slate600)),
                ),
              ]),
        ]),
        if (ownBirds > 0) ...[
          const Divider(height: 14, color: _slate200),
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'This flock can have up to '),
              TextSpan(text: _n(max), style: const TextStyle(fontWeight: FontWeight.w600, color: _slate900)),
              TextSpan(text: ' birds${free > 0 ? ' (its own ${_n(ownBirds)} + ${_n(free)} free).' : ': the ${_n(ownBirds)} it already has.'}'),
            ]),
            style: const TextStyle(fontSize: 12, color: _slate600),
          ),
        ],
      ]),
    );
  }
}

// ---- House picker ---------------------------------------------------------------

const _stateText = {'empty': 'Empty', 'free': 'Has space', 'full': 'Full', 'unknown': 'In use'};

String _houseName(Map h) => '${h['houseName'] ?? h['name'] ?? 'House ${h['houseId']}'}';

String _capacityText(HouseOccupancy o) {
  if (o.capacity <= 0) return o.occupied > 0 ? '${_n(o.occupied)} birds · no capacity set' : 'No capacity set';
  return '${_n(o.occupied)} / ${_n(o.capacity)} birds';
}

/// HousePicker: each option shows the location, capacity, birds in it and
/// the room left, and warns when this flock's birds will not fit.
class HousePicker extends StatelessWidget {
  const HousePicker({
    super.key,
    required this.houses,
    required this.flocks,
    required this.value,
    required this.onChanged,
    this.birds = 0,
    this.excludeFlockId,
    this.enabled = true,
  });
  final List<Map> houses, flocks;
  final int? value;
  final ValueChanged<int?> onChanged;
  final int birds;
  final int? excludeFlockId;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final rows = [for (final h in houses) (h: h, o: houseOccupancy(h, flocks, excludeFlockId: excludeFlockId))];
    final selected = value == null ? null : rows.where((r) => _i(r.h['houseId']) == value).firstOrNull;
    final need = birds < 0 ? 0 : birds;
    final overBy = selected != null && selected.o.free != null && need > selected.o.free! ? need - selected.o.free! : 0;
    final loc = selected == null ? '' : '${selected.h['location'] ?? ''}'.trim();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AppSelect<String>(
        key: const ValueKey('house-picker'),
        value: value == null ? 'none' : '$value',
        enabled: enabled,
        items: [
          const AppSelectItem(value: 'none', label: 'No house — assign one later'),
          for (final r in rows)
            AppSelectItem(
              value: '${r.h['houseId']}',
              // One line on a phone: name (state) · location · capacity · free.
              label: [
                '${_houseName(r.h)} (${_stateText[r.o.state] ?? ''})',
                '${r.h['location'] ?? ''}'.trim().isEmpty ? 'No location' : '${r.h['location']}'.trim(),
                _capacityText(r.o),
                if (r.o.free != null) '${_n(r.o.free)} free',
              ].join(' · '),
            ),
        ],
        onChanged: (v) => onChanged(v == null || v == 'none' ? null : int.tryParse(v)),
      ),
      if (selected != null) ...[
        const SizedBox(height: 6),
        Text(
          '${loc.isNotEmpty ? '$loc · ' : ''}${_capacityText(selected.o)}'
          '${selected.o.flockCount > 0 ? ' in ${selected.o.flockCount} active flock${selected.o.flockCount == 1 ? '' : 's'}' : ''}'
          '${selected.o.free != null ? ' · ${_n(selected.o.free)} free' : ''}',
          style: const TextStyle(fontSize: 12, color: _slate500),
        ),
      ],
      if (houses.isEmpty) ...[
        const SizedBox(height: 6),
        const Text('No houses set up yet. Add them under Farm Setup → Houses.', style: TextStyle(fontSize: 12, color: _slate500)),
      ],
      if (overBy > 0 && selected != null) ...[
        const SizedBox(height: 6),
        Text(
          'Not enough room: ${_houseName(selected.h)} has space for ${_n(selected.o.free)} more birds; this flock needs ${_n(need)}.',
          key: const ValueKey('house-over'),
          style: const TextStyle(fontSize: 12, color: _red600),
        ),
      ],
    ]);
  }
}

// ---- Edit Flock: the flock as it was registered (414) ---------------------------

/// GET /api/Flock/{id}/edit-context. Null before 414: the form behaves as before.
Future<Map?> loadFlockEditContext(Session s, Company c, int flockId) async {
  try {
    final r = await s.farmClient.get('/api/Flock/$flockId/edit-context', query: {'farmId': c.farmId});
    return r is Map ? r : null;
  } catch (_) {
    return null;
  }
}

/// The delete confirm's text from the edit context (null = the usual text).
({bool canDelete, String message})? flockDeleteCheck(Map? ctx) {
  if (ctx == null) return null;
  if (ctx['canDelete'] == false) {
    final blockers = [for (final b in (ctx['deleteBlockers'] is List ? ctx['deleteBlockers'] as List : const [])) if (b is Map) b];
    return (
      canDelete: false,
      message: 'This flock has posted activity and cannot be deleted:\n'
          '${[for (final b in blockers) '• ${_n(_i(b['rows']))} ${b['label'] ?? b['source'] ?? ''}'].join('\n')}\n'
          'Reverse those entries first, or close the flock (Tools > Flock Closeout) to keep its history.',
    );
  }
  final p = ctx['position'];
  return (
    canDelete: true,
    message: 'Delete this flock?'
        '${p is Map ? ' Its ${_n(_i(p['originallyplaced']))} placed birds go back to the batch, and its opening entries are reversed.' : ''}'
        ' This cannot be undone.',
  );
}

/// OpeningHistoryDraft: the opening history as typed in Edit Flock.
class OpeningHistoryDraft {
  OpeningHistoryDraft({required this.placed, required this.live, required this.known, this.mort = '', this.sold = '', this.culled = '', this.moved = ''});
  String placed, live, mort, sold, culled, moved;
  bool known;

  /// What PUT /api/Flock/{id} takes as OpeningHistory.
  Map<String, dynamic> toEdit() => {
        'OriginallyPlaced': _num(placed),
        'OpeningLiveBirds': _num(live),
        'HistoryKnown': known,
        'HistoricalMortality': known ? _num(mort) : 0,
        'HistoricalSold': known ? _num(sold) : 0,
        'HistoricalCulled': known ? _num(culled) : 0,
        'HistoricalTransferred': known ? _num(moved) : 0,
        'Notes': null,
      };
}

String _blankZero(Object? v) => _i(v) == 0 ? '' : '${_i(v)}';

OpeningHistoryDraft? openingDraftFrom(Map? ctx) {
  final o = ctx?['opening'];
  if (o is! Map) return null;
  return OpeningHistoryDraft(
    placed: '${_i(o['originallyPlaced'])}',
    live: '${_i(o['openingLiveBirds'])}',
    known: o['historyKnown'] == true,
    mort: _blankZero(o['historicalMortality']),
    sold: _blankZero(o['historicalSold']),
    culled: _blankZero(o['historicalCulled']),
    moved: _blankZero(o['historicalTransferred']),
  );
}

/// Warnings only; nothing here stops the save.
List<String> openingDraftWarnings(Map? ctx, OpeningHistoryDraft? d) {
  final o = ctx?['opening'];
  if (o is! Map || d == null) return const [];
  final w = <String>[];
  final placed = _num(d.placed), live = _num(d.live);
  final missing = placed - live;
  final explained = _num(d.mort) + _num(d.sold) + _num(d.culled) + _num(d.moved);
  if (live > placed) {
    w.add('${_n(live)} alive is more than the ${_n(placed)} originally placed — originally placed will be saved as ${_n(live)}.');
  } else if (d.known && explained > missing) {
    w.add('The breakdown adds up to ${_n(explained)}, but only ${_n(missing)} birds are missing. It will be saved as "not yet explained" until it matches.');
  }
  final p = ctx?['position'];
  final recs = p is Map ? _i(p['productionrecordcount']) : 0;
  if (recs > 0 && (placed != _i(o['originallyPlaced']) || live != _i(o['openingLiveBirds']))) {
    w.add('This flock already has ${_n(recs)} production record(s). Live birds now come from the latest record, so check it still matches.');
  }
  return w;
}

/// FlockHistoryPanel: how the flock was registered, what happened to the
/// difference, and what has happened since. Editable when [draft] is given.
class FlockHistoryPanel extends StatelessWidget {
  const FlockHistoryPanel({super.key, required this.ctx, this.draft, this.onChanged, this.enabled = true, required this.offset});
  final Map ctx;
  final OpeningHistoryDraft? draft;
  final VoidCallback? onChanged;
  final bool enabled;

  /// The company's clock, for "Entered".
  final Duration offset;

  @override
  Widget build(BuildContext context) {
    final o = ctx['opening'] is Map ? ctx['opening'] as Map : null;
    final p = ctx['position'] is Map ? ctx['position'] as Map : null;
    final d = o != null && draft != null && onChanged != null ? draft : null;
    final placed = d != null ? _num(d.placed) : (o != null ? _i(o['originallyPlaced']) : _i(p?['originallyplaced']));
    final live = d != null ? _num(d.live) : _i(o?['openingLiveBirds']);
    final reduction = (placed - live).clamp(0, 1 << 31);
    final known = d != null ? d.known : o?['historyKnown'] == true;
    final parts = d != null
        ? (_num(d.mort), _num(d.sold), _num(d.culled), _num(d.moved))
        : (_i(o?['historicalMortality']), _i(o?['historicalSold']), _i(o?['historicalCulled']), _i(o?['historicalTransferred']));
    final explained = parts.$1 + parts.$2 + parts.$3 + parts.$4;
    final unexplained = !known ? reduction : (reduction - explained).clamp(0, 1 << 31);
    final breakdown = [
      ('Died', parts.$1),
      ('Sold', parts.$2),
      ('Culled', parts.$3),
      ('Transferred out', parts.$4),
      ('Not explained', unexplained),
    ].where((e) => e.$2 > 0).toList();
    void set(VoidCallback f) {
      f();
      onChanged?.call();
    }

    final liveNow = p != null ? _i(p['currentlivebirds']) : live;
    final sinceLost = p == null ? 0 : _i(p['recordedmortality']) + _i(p['birdssold']) + _i(p['birdsculled']) + _i(p['birdstransferred']);
    final movements = [for (final m in (ctx['movements'] is List ? ctx['movements'] as List : const [])) if (m is Map) m];
    final effective = trackerDate(o?['effectiveDate']);

    Widget figure(String label, int value, {Color color = _slate900}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: _slate50, border: Border.all(color: _slate200), borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .4, color: _slate500)),
            Text(_n(value), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
          ]),
        );

    return Container(
      key: const ValueKey('flock-history-panel'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(border: Border.all(color: _slate200), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: Tone.button(const Tone.bg(0xFF334155)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(o != null ? 'Bird history — originally placed, current and the difference' : 'Bird history',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
        ),
        Container(
          color: Tone.bg(0xFFFFFFFF),
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FlockModeSelector(existing: ctx['mode'] == 'Existing'),
            const SizedBox(height: 14),
            if (d != null)
              _pairs([
                _label('Originally placed', _numBox(d.placed, (v) => set(() => d.placed = v), key: const ValueKey('history-placed'), enabled: enabled), size: 12),
                _label('Birds on $effective', _numBox(d.live, (v) => set(() => d.live = v), key: const ValueKey('history-live'), enabled: enabled), size: 12),
                figure('Difference', reduction, color: reduction > 0 ? _amber700 : _slate900),
                figure('Live birds now', liveNow, color: _emerald700),
              ])
            else
              _pairs([
                figure('Originally placed', placed),
                if (o != null) figure('Birds on $effective', live),
                if (o != null) figure('Difference', reduction, color: reduction > 0 ? _amber700 : _slate900),
                figure('Live birds now', liveNow, color: _emerald700),
              ]),
            if (o != null) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: _slate50, borderRadius: BorderRadius.circular(6)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(
                    reduction == 0
                        ? 'No birds were missing when it was registered.'
                        : 'How the difference of ${_n(reduction)} was allocated (${_n(placed)} placed − ${_n(live)} current)',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: _slate800),
                  ),
                  if (d != null && reduction > 0) ...[
                    const SizedBox(height: 6),
                    InkWell(
                      key: const ValueKey('history-known'),
                      onTap: enabled ? () => set(() => d.known = !d.known) : null,
                      child: Row(children: [
                        Icon(d.known ? Icons.check_box : Icons.check_box_outline_blank, size: 20, color: _slate600),
                        const SizedBox(width: 8),
                        const Expanded(child: Text('We know what happened to them', style: TextStyle(fontSize: 14, color: _slate700))),
                      ]),
                    ),
                    if (d.known) ...[
                      const SizedBox(height: 8),
                      _pairs([
                        _label('Died', _numBox(d.mort, (v) => set(() => d.mort = v), key: const ValueKey('history-mort'), enabled: enabled), size: 12),
                        _label('Sold (historical)', _numBox(d.sold, (v) => set(() => d.sold = v), key: const ValueKey('history-sold'), enabled: enabled), size: 12),
                        _label('Culled', _numBox(d.culled, (v) => set(() => d.culled = v), key: const ValueKey('history-culled'), enabled: enabled), size: 12),
                        _label('Transferred out', _numBox(d.moved, (v) => set(() => d.moved = v), key: const ValueKey('history-moved'), enabled: enabled), size: 12),
                      ]),
                    ],
                  ],
                  if (d == null && breakdown.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(spacing: 18, runSpacing: 2, children: [
                      for (final (label, q) in breakdown)
                        Text.rich(TextSpan(children: [
                          TextSpan(text: '$label: '),
                          TextSpan(text: _n(q), style: const TextStyle(fontWeight: FontWeight.w700, color: _slate900)),
                        ]), style: const TextStyle(fontSize: 14, color: _slate600)),
                    ]),
                  ],
                  if (reduction > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${known && explained > reduction ? 'The breakdown adds up to ${_n(explained)} — ${_n(explained - reduction)} more than are missing.' : unexplained > 0 ? '${_n(unexplained)} not explained yet.' : 'All of the difference is explained.'}'
                      '${'${o['source'] ?? ''}'.isNotEmpty ? ' Registered from ${o['source']}.' : ''}'
                      '${o['startDateEstimated'] == true ? ' Start date was estimated.' : ''}',
                      style: TextStyle(fontSize: 12, color: unexplained > 0 || (known && explained > reduction) ? _amber700 : _emerald700),
                    ),
                  ],
                ]),
              ),
            ],
            if (p != null && (sinceLost > 0 || _i(p['productionrecordcount']) > 0)) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(border: Border.all(color: _slate200), borderRadius: BorderRadius.circular(6)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Since ${o != null ? 'it was registered' : 'it was placed'}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: _slate800)),
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text: '${_n(o != null ? live : placed)} at the start − ${_n(_i(p['recordedmortality']))} recorded deaths − ${_n(_i(p['birdssold']))} sold'
                              '${_i(p['birdsculled']) > 0 ? ' − ${_n(_i(p['birdsculled']))} culled' : ''}'
                              '${_i(p['birdstransferred']) > 0 ? ' − ${_n(_i(p['birdstransferred']))} transferred' : ''} → '),
                      TextSpan(text: '${_n(liveNow)} live now', style: const TextStyle(fontWeight: FontWeight.w700, color: _emerald700)),
                      TextSpan(
                          text: ' (${_n(_i(p['productionrecordcount']))} production record${_i(p['productionrecordcount']) == 1 ? '' : 's'}).'),
                    ]),
                    style: const TextStyle(fontSize: 12, color: _slate600),
                  ),
                ]),
              ),
            ],
            if (movements.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('POSTED BIRD MOVEMENTS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: .4, color: _slate500)),
              const SizedBox(height: 4),
              for (final m in movements)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: Tone.line(0xFFF1F5F9)))),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${'${m['reason'] ?? ''}'.isNotEmpty ? m['reason'] : m['type'] ?? ''}', style: const TextStyle(fontSize: 14, color: _slate900)),
                        if ('${m['note'] ?? ''}'.isNotEmpty) Text('${m['note']}', style: const TextStyle(fontSize: 12, color: _slate500)),
                        Text(
                          'Effective ${trackerDate(m['effectiveDate'])} · Entered '
                          '${'${m['postedAt'] ?? ''}'.isNotEmpty ? fmtInstant(m['postedAt'], offset) : 'time not recorded'}',
                          style: const TextStyle(fontSize: 12, color: _slate500),
                        ),
                      ]),
                    ),
                    Text(
                      '${(num.tryParse('${m['quantity']}') ?? 0) > 0 ? '+' : ''}${_n(num.tryParse('${m['quantity']}') ?? 0)}',
                      style: TextStyle(
                          fontSize: 14,
                          color: (num.tryParse('${m['quantity']}') ?? 0) < 0 ? _red600 : const Tone.fg(0xFF15803D)),
                    ),
                  ]),
                ),
            ],
          ]),
        ),
      ]),
    );
  }
}

