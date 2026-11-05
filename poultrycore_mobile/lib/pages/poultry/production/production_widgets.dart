// Field widgets shared by the production forms: FormSectionCard, NumField and
// CalcField (components/production/production-record-fields.tsx), and the
// feed / medication line editor (feed-lines.tsx, medication-lines.tsx).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design/ui/inputs.dart';
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull, loc, formatEggGradeLabel;
import '../trackers/tracker_widgets.dart';
import 'production_logic.dart';

import 'package:poultrycore_mobile/design/tone.dart';
enum ProdAccent { sky, amber, rose, emerald, orange, violet, slate, indigo }

/// header background, header border, rail, title, icon.
(Color, Color, Color, Color, Color) _accent(ProdAccent a) => switch (a) {
      ProdAccent.sky => (TColors.sky100, const Tone(0xFFBAE6FD), const Tone(0xFF0284C7), TColors.sky900, TColors.sky700),
      ProdAccent.amber => (TColors.amber100, TColors.amber200, TColors.amber600, TColors.amber900, TColors.amber700),
      ProdAccent.rose => (TColors.rose100, TColors.rose200, TColors.rose600, const Tone(0xFF881337), TColors.rose700),
      ProdAccent.emerald => (TColors.emerald100, TColors.emerald200, TColors.emerald600, TColors.emerald900, TColors.emerald700),
      ProdAccent.orange => (const Tone(0xFFFFEDD5), const Tone(0xFFFED7AA), const Tone(0xFFEA580C), const Tone(0xFF7C2D12), const Tone(0xFFC2410C)),
      ProdAccent.violet => (TColors.violet100, TColors.violet200, TColors.violet600, const Tone(0xFF4C1D95), TColors.violet700),
      ProdAccent.slate => (TColors.slate200, TColors.slate300, TColors.slate500, TColors.slate900, TColors.slate600),
      ProdAccent.indigo => (const Tone(0xFFE0E7FF), const Tone(0xFFC7D2FE), const Tone(0xFF4F46E5), const Tone(0xFF312E81), const Tone(0xFF4338CA)),
    };

/// FormSectionCard: a tinted header with a colour rail, icon, title,
/// description and an optional badge.
class ProdSection extends StatelessWidget {
  const ProdSection({super.key, required this.title, this.description, this.badge, this.accent = ProdAccent.slate, this.icon, required this.child});
  final String title;
  final String? description, badge;
  final ProdAccent accent;
  final IconData? icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final (bg, border, rail, titleC, iconC) = _accent(accent);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: Tone.bg(0xFFFFFFFF), border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: bg, border: Border(bottom: BorderSide(color: border))),
          child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 6, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 4, height: 32, decoration: BoxDecoration(color: rail, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 10),
              if (icon != null) ...[Icon(icon, size: 16, color: iconC), const SizedBox(width: 8)],
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width - 120),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: titleC)),
                  if (description != null) Text(description!, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                ]),
              ),
            ]),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(color: Tone.bg(0xFFFFFFFF), border: Border.all(color: border), borderRadius: BorderRadius.circular(999)),
                child: Text(badge!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: titleC)),
              ),
          ]),
        ),
        Padding(padding: const EdgeInsets.all(14), child: child),
      ]),
    );
  }
}

Widget _fieldLabel(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(t, style: const TextStyle(fontSize: 12, color: TColors.slate600)),
    );

/// NumField for a whole number held as a number (the picks).
class ProdNumField extends StatefulWidget {
  const ProdNumField({super.key, required this.label, required this.value, required this.onChanged, this.max});
  final String label;
  final num value;
  final ValueChanged<num> onChanged;

  /// Typing past this is clamped back to it, so the box can never hold more.
  final num? max;
  @override
  State<ProdNumField> createState() => _ProdNumFieldState();
}

class _ProdNumFieldState extends State<ProdNumField> {
  late final _c = TextEditingController(text: '${widget.value.toInt()}');

  @override
  void didUpdateWidget(ProdNumField old) {
    super.didUpdateWidget(old);
    if ((num.tryParse(_c.text) ?? 0) != widget.value) _c.text = '${widget.value.toInt()}';
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        _fieldLabel(widget.label),
        AppInput(
          controller: _c,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, if (widget.max != null) clampFormatter(widget.max!)],
          onChanged: (v) => widget.onChanged(num.tryParse(v) ?? 0),
        ),
      ]);
}

/// NumField's `max`: a value typed past [max] becomes [max].
TextInputFormatter clampFormatter(num max) => TextInputFormatter.withFunction((old, next) {
      final v = num.tryParse(next.text);
      if (v == null || v <= max) return next;
      final t = '${max.toInt()}';
      return TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
    });

/// NumField with `text`: the raw string is kept, so blank stays blank.
class ProdTextField extends StatelessWidget {
  const ProdTextField({super.key, required this.label, required this.controller, this.decimal = false, this.max});
  final String label;
  final TextEditingController controller;
  final bool decimal;

  /// Typing past this is clamped back to it (the web's NumField `max`).
  final num? max;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        _fieldLabel(label),
        AppInput(
          controller: controller,
          keyboardType: TextInputType.numberWithOptions(decimal: decimal),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(decimal ? r'[0-9.]' : r'[0-9]')), if (max != null) clampFormatter(max!)],
        ),
      ]);
}

/// 372: what happens to a record's broken eggs / dead birds. "Keep" puts them
/// into the Broken Eggs / Dead Birds stock; "Disposed" records them as
/// generated and disposed at once. Shown only when there are some.
/// 390 / 391: keep all, dispose some, or dispose all of a record's broken
/// eggs / dead birds.
enum DisposalMode { keep, some, all }

/// How many a mode disposes, capped at the count recorded.
int disposedCount(DisposalMode mode, String disposed, int count) {
  if (count <= 0 || mode == DisposalMode.keep) return 0;
  if (mode == DisposalMode.all) return count;
  final n = int.tryParse(disposed) ?? 0;
  return n < 0 ? 0 : (n > count ? count : n);
}

/// disposalModeFrom: the form's mode from a saved record. An older API sends
/// no count, so the Keep / Disposed choice decides (none / all).
({DisposalMode mode, String disposed}) disposalModeFrom(int count, Object? disposed, Object? disposition) {
  final out = disposed is num ? disposed.toInt() : (disposition == 'Disposed' ? count : 0);
  if (out <= 0) return (mode: DisposalMode.keep, disposed: '');
  if (out >= count) return (mode: DisposalMode.all, disposed: '');
  return (mode: DisposalMode.some, disposed: '$out');
}

/// disposalPayload: the count is the authority; Keep / Disposed rides along for
/// none / all only. Nothing is sent while no choice was loaded or made ('').
Map<String, Object?> disposalPayload(DisposalMode mode, String disposed, String disposition, int count, String countKey, String dispositionKey) {
  if (disposition.isEmpty) return const {};
  final out = disposedCount(mode, disposed, count);
  if (out == 0) return {countKey: 0, dispositionKey: 'Keep'};
  if (out == count) return {countKey: out, dispositionKey: 'Disposed'};
  return {countKey: out};
}

/// DisposalSplitField: what happens to a record's broken eggs / dead birds.
/// Some can be disposed at once and the rest added to Broken Eggs / Dead Birds
/// stock. Shown only when there are some.
class DisposalSplitField extends StatelessWidget {
  const DisposalSplitField({
    super.key,
    required this.label,
    required this.count,
    required this.mode,
    required this.disposed,
    required this.onMode,
    required this.onDisposed,
    required this.noun,
    required this.stockName,
  });

  /// Names the choice, e.g. "Broken Egg Stock allocation". On its own line, as
  /// the web shows it on a phone.
  final String label;
  final int count;
  final DisposalMode mode;

  /// The "Dispose some" count, as typed.
  final String disposed;
  final ValueChanged<DisposalMode> onMode;
  final ValueChanged<String> onDisposed;

  /// e.g. ('broken egg', 'broken eggs').
  final (String, String) noun;

  /// e.g. "Broken Egg stock".
  final String stockName;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final out = disposedCount(mode, disposed, count);
    final kept = count - out;
    String n(int x) => '${loc(x)} ${x == 1 ? noun.$1 : noun.$2}';
    Widget option(DisposalMode v, String text) => Material(
          color: mode == v ? Tone.button(TColors.slate800)! : Tone.bg(0xFFFFFFFF),
          child: InkWell(
            key: ValueKey('$label-${v.name}'),
            onTap: () => onMode(v),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: mode == v ? Colors.white : TColors.slate600)),
            ),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: TColors.slate700)),
      const SizedBox(height: 6),
      Semantics(
        label: label,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(border: Border.all(color: TColors.slate300), borderRadius: BorderRadius.circular(6)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: option(DisposalMode.keep, 'Keep all')),
            Flexible(child: option(DisposalMode.some, 'Dispose some')),
            Flexible(child: option(DisposalMode.all, 'Dispose all')),
          ]),
        ),
      ),
      if (mode == DisposalMode.some) ...[
        const SizedBox(height: 8),
        SizedBox(
          width: 160,
          child: ProdNumField(
            key: ValueKey('$label-disposed'),
            label: 'Disposed now',
            value: int.tryParse(disposed) ?? 0,
            max: count,
            onChanged: (v) => onDisposed('${v.toInt()}'),
          ),
        ),
      ],
      const SizedBox(height: 6),
      Text(
        out == 0
            ? '${n(count)} will be added to $stockName.'
            : kept == 0
                ? '${n(count)} recorded and disposed of. Nothing is added to stock.'
                : '${n(out)} disposed of; ${n(kept)} added to $stockName.',
        style: const TextStyle(fontSize: 12, color: TColors.slate600),
      ),
    ]);
  }
}

enum CalcTone { good, bad }

/// CalcField: "Label (auto)" over a dashed read-only value.
class CalcField extends StatelessWidget {
  const CalcField({super.key, required this.label, required this.value, this.tone});
  final String label, value;
  final CalcTone? tone;
  @override
  Widget build(BuildContext context) {
    final (bg, border, fg) = switch (tone) {
      CalcTone.good => (TColors.emerald100, const Tone(0xFF34D399), TColors.emerald900),
      CalcTone.bad => (TColors.red100, const Tone(0xFFF87171), TColors.red900),
      _ => (TColors.slate50, TColors.slate300, TColors.slate700),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text.rich(TextSpan(children: [
        TextSpan(text: '$label '),
        const TextSpan(text: '(auto)', style: TextStyle(color: TColors.slate400)),
      ]), style: const TextStyle(fontSize: 12, color: TColors.slate600)),
      const SizedBox(height: 4),
      Container(
        height: 40,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(6)),
        child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: fg)),
      ),
    ]);
  }
}

String _fmtStock(num n) => loc((n * 1000).round() / 1000);

/// FeedLines / MedicationLines: one row per inventory draw with the FIFO /
/// LIFO / HIFO unit cost, the line total and a shortfall warning.
class ConsumptionLines extends StatelessWidget {
  const ConsumptionLines({
    super.key,
    required this.lines,
    required this.computed,
    required this.items,
    required this.itemLabel,
    required this.placeholder,
    required this.emptyText,
    required this.noItemsText,
    required this.removeLabel,
    required this.onAdd,
    required this.onRemove,
    required this.onChanged,
    this.showIngredientTag = false,
    this.seed = 0,
  });
  final List<ConsumptionLine> lines;
  final LinesComputed computed;
  final List<Map> items;
  final String itemLabel, placeholder, emptyText, noItemsText, removeLabel;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final VoidCallback onChanged;

  /// Feed lines mark a non-finished-feed item "(ingredient)".
  final bool showIngredientTag;

  /// Changes when lines are added or removed, so each row keeps its own text.
  final int seed;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (lines.isEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(emptyText, style: const TextStyle(fontSize: 12, color: TColors.slate400))),
        for (var i = 0; i < lines.length; i++) _row(i),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(onPressed: onAdd, icon: const Icon(Icons.add, size: 14), label: const Text('Add line')),
        ),
      ]);

  Widget _row(int i) {
    final line = lines[i];
    final row = i < computed.rows.length ? computed.rows[i] : null;
    final preview = row?.preview;
    final item = row?.item;
    final visible = [for (final it in items) if (it['isActive'] == true || tStr(it['poultryRawMaterialItemId']) == line.itemId) it];
    final first = i == 0;
    Widget box(String text, {bool bold = false, Color bg = TColors.slate100}) => Container(
          height: 40,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: bg, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
          child: Text(text, style: TextStyle(fontWeight: bold ? FontWeight.w600 : FontWeight.w400, color: TColors.slate700)),
        );
    return Container(
      key: ValueKey('line-$seed-$i'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Tone.bg(0xFFFFFFFF), border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (first) _fieldLabel(itemLabel),
        AppSelect<String>(
          value: line.itemId.isEmpty ? 'none' : line.itemId,
          hintText: placeholder,
          items: [
            const AppSelectItem(value: 'none', label: 'None'),
            for (final it in visible)
              AppSelectItem(
                value: tStr(it['poultryRawMaterialItemId']),
                label: '${tStr(it['itemName'])}${tStr(it['unitOfMeasure']).isNotEmpty ? ' (${tStr(it['unitOfMeasure'])})' : ''} · '
                    '${_fmtStock(computed.pendingStock[tIntOrNull(it['poultryRawMaterialItemId'])] ?? tNum(it['currentQuantity']))} in stock · '
                    '${tStr(it['usageMethod'])}${it['isActive'] == true ? '' : ' · (inactive)'}'
                    '${showIngredientTag && !isFinishedFeedCategory(it['category']) ? ' · (ingredient)' : ''}',
              ),
            if (visible.isEmpty) AppSelectItem(value: '__empty', label: noItemsText, enabled: false),
          ],
          onChanged: (v) {
            line.itemId = v == null || v == 'none' ? '' : v;
            onChanged();
          },
        ),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (first) _fieldLabel('Consumed'),
              AppInput(
                initialValue: line.qty,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                onChanged: (v) {
                  line.qty = v;
                  onChanged();
                },
              ),
            ]),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (first)
                Text.rich(TextSpan(children: [
                  const TextSpan(text: 'Unit Cost '),
                  TextSpan(
                    text: '(${tStr(item?['usageMethod']).isEmpty ? 'FIFO' : tStr(item?['usageMethod'])})',
                    style: const TextStyle(color: TColors.slate400),
                  ),
                ]), style: const TextStyle(fontSize: 12, color: TColors.slate600)),
              if (first) const SizedBox(height: 4),
              box(preview?.unitCost != null ? preview!.unitCost!.toStringAsFixed(4) : '—'),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (first) _fieldLabel('Total Cost'),
              box(preview?.totalCost != null ? preview!.totalCost!.toStringAsFixed(2) : '0.00', bold: true, bg: Tone.bg(0xFFFFFFFF)),
            ]),
          ),
          IconButton(
            tooltip: removeLabel,
            icon: const Icon(Icons.delete_outline, size: 18, color: TColors.red600),
            onPressed: () => onRemove(i),
          ),
        ]),
        if (item != null && preview != null && preview.shortfall > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Not enough purchased stock tracked to cover ${line.qty} — only ${loc(preview.covered)} available across recorded purchases. Record a new purchase before saving.',
              style: const TextStyle(fontSize: 12, color: TColors.red600),
            ),
          ),
      ]),
    );
  }
}

/// The production forms' Egg grade since egg sorting: read-only. A new record
/// is Mixed ("Set automatically"); an older record keeps its own grade.
class EggGradeReadout extends StatelessWidget {
  const EggGradeReadout({super.key, required this.grade});
  final String grade;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          height: 40,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: TColors.slate50, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
          child: Text(formatEggGradeLabel(eggGradeToApi(grade)), style: const TextStyle(fontSize: 14, color: TColors.slate700)),
        ),
        const SizedBox(height: 4),
        Text(
          grade == productionEggGradeValue ? 'Set automatically. Sizes are recorded when the eggs are sorted.' : 'Recorded before egg sorting; kept as it was.',
          style: const TextStyle(fontSize: 12, color: TColors.slate500),
        ),
      ]);
}
