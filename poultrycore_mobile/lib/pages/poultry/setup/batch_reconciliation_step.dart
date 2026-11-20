// Initial Farm Setup's batch-level reconciliation (413), as the web's
// components/farm-setup/batch-reconciliation-step.tsx. Flock-level history
// stays on the flock cards above it; this asks only about birds that NEVER
// went into a pen. The server posts it inside the setup transaction, through
// the same function as Reconcile on Flock Purchases.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design/ui/inputs.dart';
import '../farm_setup_wizard.dart';
import '../reports/report_format.dart' show fixed2;
import '../../shared/business_dates.dart' show fmtNum, isoDay;

import 'package:poultrycore_mobile/design/tone.dart';

const _slate500 = Tone.fg(0xFF64748B);
const _slate600 = Tone.fg(0xFF475569);
const _slate700 = Tone.fg(0xFF334155);
const _slate800 = Tone.fg(0xFF1E293B);
const _slate900 = Tone.fg(0xFF0F172A);
const _slate200 = Tone.line(0xFFE2E8F0);
const _slate50 = Tone.bg(0xFFF8FAFC);
const _indigo200 = Tone.line(0xFFC7D2FE);
const _emerald700 = Tone.fg(0xFF047857);
const _amber700 = Tone.fg(0xFFB45309);
const _red600 = Tone.fg(0xFFDC2626);

String _n(num v) => fmtNum(v, 0);

/// "Birds never placed in a flock": one card per batch with birds in no pen.
class BatchReconciliationStep extends StatelessWidget {
  const BatchReconciliationStep({super.key, required this.views, required this.draft, required this.onEdit, required this.businessDate, this.onViewSource});
  final List<BatchReconciliationView> views;
  final SetupDraft draft;

  /// Applies a change to the draft (and saves it), as the page's _edit.
  final void Function(VoidCallback) onEdit;
  final String businessDate;

  /// "View source": the batch's Batch Bird Reconciliation report.
  final void Function(int batchId)? onViewSource;

  @override
  Widget build(BuildContext context) {
    if (views.isEmpty) return const SizedBox.shrink();
    return Container(
      key: const ValueKey('batch-recon-step'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(border: Border.all(color: _indigo200), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: Tone.button(const Tone.bg(0xFF4F46E5)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            const Flexible(child: Text('Birds never placed in a flock', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white))),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .25), borderRadius: BorderRadius.circular(99)),
              child: Text('${views.length}', style: const TextStyle(fontSize: 12, color: Colors.white)),
            ),
          ]),
        ),
        Container(
          color: const Tone.bg(0x66EEF2FF),
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text.rich(
              TextSpan(children: [
                TextSpan(text: 'Worked out from the birds each flock was '),
                TextSpan(text: 'originally', style: TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: " placed with, so a flock's own deaths are not counted again here. Nothing below creates a sale, cash or revenue."),
              ]),
              style: TextStyle(fontSize: 14, color: _slate600),
            ),
            for (final v in views) ...[const SizedBox(height: 12), _card(v)],
          ]),
        ),
      ]),
    );
  }

  BatchReconciliationDraft _get(String key) => draft.batchReconciliations[key] ?? BatchReconciliationDraft();

  void _set(String key, void Function(BatchReconciliationDraft r) f) => onEdit(() {
        final r = draft.batchReconciliations.putIfAbsent(key, BatchReconciliationDraft.new);
        f(r);
      });

  Widget _card(BatchReconciliationView v) {
    final r = _get(v.batchKey);
    final tone = v.unexplained == 0 ? _emerald700 : v.unexplained < 0 ? _red600 : _amber700;
    Widget field(String label, Widget child) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _slate600)),
          const SizedBox(height: 4),
          child,
        ]);
    Widget pairs(List<Widget> cells) => Column(children: [
          for (var i = 0; i < cells.length; i += 2)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(child: cells[i]),
                const SizedBox(width: 8),
                Expanded(child: i + 1 < cells.length ? cells[i + 1] : const SizedBox()),
              ]),
            ),
        ]);
    final k = v.batchKey;
    return Container(
      key: ValueKey('batch-recon-$k'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Tone.bg(0xFFFFFFFF), border: Border.all(color: _indigo200), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(v.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: _slate900)),
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: '${_n(v.originalBirds)} bought'),
                  if (v.previouslyAccountedFor != 0) TextSpan(text: ' · ${_n(v.previouslyAccountedFor)} already recorded'),
                  TextSpan(text: ' · ${_n(v.placed)} originally placed in flocks · '),
                  TextSpan(text: '${_n(v.neverPlaced)} still not in a pen', style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
                style: const TextStyle(fontSize: 14, color: _slate600),
              ),
              const SizedBox(height: 4),
              Text('What happened to the remaining ${_n(v.neverPlaced)} birds that are not in a pen?',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: _slate800)),
            ]),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: _slate50, border: Border.all(color: _slate200), borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              const Text('UNEXPLAINED', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .4, color: _slate500)),
              Text(_n(v.unexplained), key: ValueKey('batch-recon-unexplained-$k'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: tone)),
            ]),
          ),
        ]),
        if (v.previous != null && v.previouslyAccountedFor != 0) ...[const SizedBox(height: 12), _alreadyRecorded(v)],
        const SizedBox(height: 12),
        Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 4, children: [
          Text(v.previouslyAccountedFor != 0 ? 'Further sales not yet recorded' : 'Previously sold',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: _slate700)),
          OutlinedButton.icon(
            key: ValueKey('batch-recon-add-sale-$k'),
            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: () => _set(k, (r) => r.sales.add(BatchSaleDraft(key: '${DateTime.now().microsecondsSinceEpoch}-${r.sales.length}', date: businessDate))),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add historical sale'),
          ),
        ]),
        for (final (i, s) in r.sales.indexed) ...[
          const SizedBox(height: 8),
          Container(
            key: ValueKey('batch-recon-sale-$k-$i'),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: _slate50, borderRadius: BorderRadius.circular(6)),
            child: () {
              final total = s.valueUnknown ? null : (count(s.quantity) * ((num.tryParse(s.pricePerBird.trim()) ?? 0) * 100).round()).round() / 100;
              return pairs([
                field('Birds', _Box(value: s.quantity, key: ValueKey('sale-qty-$k-$i'), onChanged: (x) => _set(k, (_) => s.quantity = x))),
                field(
                  'Date',
                  AppDateField(
                    value: DateTime.tryParse(s.date),
                    lastDate: DateTime.tryParse(businessDate),
                    onChanged: (d) => _set(k, (_) => s.date = d == null ? '' : isoDay(d)),
                  ),
                ),
                field('Price per bird',
                    _Box(value: s.pricePerBird, decimal: true, enabled: !s.valueUnknown, key: ValueKey('sale-price-$k-$i'), onChanged: (x) => _set(k, (_) => s.pricePerBird = x))),
                field(
                  'Sale value',
                  Container(
                    height: 40,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(color: Tone.bg(0xFFFFFFFF), border: Border.all(color: _slate200), borderRadius: BorderRadius.circular(6)),
                    child: Text(total == null ? '—' : fixed2(total), key: ValueKey('sale-value-$k-$i')),
                  ),
                ),
                field(
                  'Already received',
                  _Box(
                    value: s.amountReceived,
                    decimal: true,
                    enabled: !s.valueUnknown,
                    hint: total == null ? '' : '$total',
                    onChanged: (x) => _set(k, (_) => s.amountReceived = x),
                  ),
                ),
                Row(children: [
                  Expanded(
                    child: InkWell(
                      key: ValueKey('sale-unknown-$k-$i'),
                      onTap: () => _set(k, (_) {
                        s
                          ..valueUnknown = !s.valueUnknown
                          ..pricePerBird = ''
                          ..amountReceived = '';
                      }),
                      child: SizedBox(
                        height: 40,
                        child: Row(children: [
                          Icon(s.valueUnknown ? Icons.check_box : Icons.check_box_outline_blank, size: 20, color: _slate600),
                          const SizedBox(width: 6),
                          const Flexible(child: Text('Value unknown', style: TextStyle(fontSize: 12, color: _slate700))),
                        ]),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove sale',
                    icon: const Icon(Icons.delete_outline, size: 18, color: _red600),
                    onPressed: () => _set(k, (r) => r.sales.remove(s)),
                  ),
                ]),
              ]);
            }(),
          ),
        ],
        if (r.sales.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'Historical sales value ${fixed2(v.saleValue)}. Recorded as history only — no cash today, no revenue in this period. '
            "Money a customer still owes can be added as an opening debt from the batch's Reconcile action after setup.",
            style: const TextStyle(fontSize: 12, color: _slate500),
          ),
        ],
        const SizedBox(height: 12),
        pairs([
          field('Historical mortality', _Box(value: r.mortality, key: ValueKey('recon-mort-$k'), onChanged: (x) => _set(k, (r) => r.mortality = x))),
          field('Culled / removed', _Box(value: r.culled, key: ValueKey('recon-culled-$k'), onChanged: (x) => _set(k, (r) => r.culled = x))),
          field('Transferred outside the batch', _Box(value: r.transferred, key: ValueKey('recon-moved-$k'), onChanged: (x) => _set(k, (r) => r.transferred = x))),
          field('Other documented reason', _Box(value: r.other, key: ValueKey('recon-other-$k'), onChanged: (x) => _set(k, (r) => r.other = x))),
          field((num.tryParse(r.other.trim()) ?? 0) > 0 ? 'What were they? *' : 'What were they?',
              _Box(value: r.otherNote, text: true, key: ValueKey('recon-note-$k'), onChanged: (x) => _set(k, (r) => r.otherNote = x))),
          field('Still alive, not yet in a flock', _Box(value: r.stillAlive, key: ValueKey('recon-alive-$k'), onChanged: (x) => _set(k, (r) => r.stillAlive = x))),
        ]),
        Text(
          v.unexplained == 0
              ? 'Fully accounted for.'
              : v.unexplained < 0
                  ? 'These add up to ${_n(v.explained)} — more than the ${_n(v.neverPlaced)} not in a pen.'
                  : v.isHistorical
                      ? '${_n(v.unexplained)} still to explain. A batch you already had must be fully accounted for before setup can finish '
                          '(save the draft and come back if you need to find out).'
                      : '${_n(v.unexplained)} not explained — for a new purchase they stay available to place in a flock later.',
          key: ValueKey('batch-recon-note-$k'),
          style: TextStyle(fontSize: 12, color: tone),
        ),
      ]),
    );
  }

  /// Dispositions already POSTED against this batch's never-placed birds:
  /// read-only, never sent again.
  Widget _alreadyRecorded(BatchReconciliationView v) {
    final p = v.previous!;
    int i(Object? x) => x is num ? x.truncate() : (num.tryParse('${x ?? ''}')?.truncate() ?? 0);
    final rows = [
      ('Historical sales', i(p['previouslySold'])),
      ('Historical mortality', i(p['previousMortality'])),
      ('Culled / removed', i(p['previouslyCulled'])),
      ('Transferred out', i(p['previouslyTransferred'])),
      ('Other removals', i(p['previousOther'])),
      ('Birds added', -i(p['previousAdditions'])),
    ].where((e) => e.$2 != 0).toList();
    final last = '${p['lastReconciliationNo'] ?? ''}';
    return Container(
      key: ValueKey('batch-recon-already-${v.batchKey}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: _slate50, border: Border.all(color: _slate200), borderRadius: BorderRadius.circular(6)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
          Text('Already recorded${last.isNotEmpty ? ' (last: $last)' : ''} — not posted again',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: _slate700)),
          if (v.existingBatchId != null && onViewSource != null)
            InkWell(
              onTap: () => onViewSource!(v.existingBatchId!),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Text('View source', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Tone.fg(0xFF4338CA))),
                SizedBox(width: 4),
                Icon(Icons.open_in_new, size: 12, color: Tone.fg(0xFF4338CA)),
              ]),
            ),
        ]),
        const SizedBox(height: 6),
        for (final (label, q) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              Expanded(child: Text(label, style: const TextStyle(fontSize: 14, color: _slate600))),
              Text('${q > 0 ? '−' : '+'}${_n(q.abs())}', style: const TextStyle(fontSize: 14, color: _slate900)),
            ]),
          ),
        const SizedBox(height: 4),
        const Text(
          "These birds are already accounted for, so you are not asked about them again. To correct one, reverse it from the batch's reconciliation history.",
          style: TextStyle(fontSize: 12, color: _slate500),
        ),
      ]),
    );
  }
}

/// A box that keeps its own controller (the draft holds strings).
class _Box extends StatefulWidget {
  const _Box({super.key, required this.value, required this.onChanged, this.decimal = false, this.text = false, this.enabled = true, this.hint = ''});
  final String value, hint;
  final ValueChanged<String> onChanged;
  final bool decimal, text, enabled;
  @override
  State<_Box> createState() => _BoxState();
}

class _BoxState extends State<_Box> {
  late final _c = TextEditingController(text: widget.value);
  @override
  void didUpdateWidget(_Box old) {
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
        hintText: widget.hint,
        keyboardType: widget.text ? TextInputType.text : TextInputType.numberWithOptions(decimal: widget.decimal),
        inputFormatters: widget.text ? null : [FilteringTextInputFormatter.allow(RegExp(widget.decimal ? r'[0-9.]' : r'[0-9]'))],
        onChanged: widget.onChanged,
      );
}
