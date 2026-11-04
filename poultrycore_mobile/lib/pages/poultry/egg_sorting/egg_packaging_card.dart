// Egg packaging & units (components/egg-sorting/egg-packaging-card.tsx,
// migration 393): Boxes of N crates, how egg quantities are written, and which
// field a sale line puts first. Saving changes how quantities are entered and
// shown -- never stock, posted sales or stock movements.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../egg_packaging.dart';
import '../production/production_logic.dart' show eggsPerCrate;
import '../trackers/tracker_logic.dart' show tIntOrNull;
import '../trackers/tracker_widgets.dart';

const _sample = 10675;
const _amber600 = Color(0xFFD97706);

class EggPackagingCard extends StatefulWidget {
  const EggPackagingCard({super.key, required this.session, required this.company, required this.canEdit, this.onChanged});
  final Session session;
  final Company company;
  final bool canEdit;
  final VoidCallback? onChanged;
  @override
  State<EggPackagingCard> createState() => _EggPackagingCardState();
}

class _EggPackagingCardState extends State<EggPackagingCard> {
  Map? _saved;
  String? _loadError;
  bool _on = false, _busy = false;
  final _crates = TextEditingController();
  EggDisplay _display = EggDisplay.cratesPieces;
  SaleEntryUnit _entry = SaleEntryUnit.crates;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _crates.dispose();
    super.dispose();
  }

  void _reset(Map s) {
    _on = s['enableBoxes'] == true;
    final stored = tIntOrNull(s['storedCratesPerBox']);
    _crates.text = stored == null ? '' : '$stored';
    _display = eggDisplayOf(s['storedDisplay'] ?? 'CratesPieces');
    _entry = saleEntryOf(s['storedEntryUnit'] ?? 'Crates');
  }

  Future<void> _load() async {
    try {
      final s = await fetchEggPackagingSettings(widget.session, widget.company);
      if (!mounted || s == null) return;
      setState(() {
        _saved = s;
        _reset(s);
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message.isEmpty ? 'Could not load egg packaging.' : e.message);
    }
  }

  int? get _cratesN => _crates.text.trim().isEmpty ? null : int.tryParse(_crates.text.trim());

  bool get _dirty {
    final s = _saved;
    if (s == null) return false;
    return _on != (s['enableBoxes'] == true) ||
        _cratesN != tIntOrNull(s['storedCratesPerBox']) ||
        _display != eggDisplayOf(s['storedDisplay'] ?? 'CratesPieces') ||
        _entry != saleEntryOf(s['storedEntryUnit'] ?? 'Crates');
  }

  /// The conversion itself changes (not just how it is written).
  bool get _conversionChanges {
    final s = _saved;
    if (s == null) return false;
    return _on != (s['enableBoxes'] == true) || (_on && _cratesN != tIntOrNull(s['cratesPerBox']));
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.session.farmClient.put('/api/Poultry/egg-sorting/packaging', body: {
        'farmId': widget.company.farmId,
        'enableBoxes': _on,
        'cratesPerBox': _cratesN,
        'eggDisplay': eggDisplayApi[_display],
        'saleEntryUnit': saleEntryApi[_entry],
      });
      final fresh = await fetchEggPackagingSettings(widget.session, widget.company);
      if (fresh != null) {
        applyEggPackaging(widget.company.farmId, fresh);
        if (mounted) {
          setState(() {
            _saved = fresh;
            _reset(fresh);
          });
        }
      }
      messenger.showSnackBar(const SnackBar(content: Text('Egg packaging saved')));
      widget.onChanged?.call();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Not saved. ${e.message}')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmThenSave() async {
    final saved = _saved;
    final n = _cratesN;
    final title = _on ? (saved?['enableBoxes'] == true ? 'Change the box size?' : 'Turn on boxes?') : 'Turn off boxes?';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_on && n != null)
              Text.rich(TextSpan(style: const TextStyle(fontSize: 14, color: TColors.slate600), children: [
                const TextSpan(text: 'From now on, 1 box = '),
                TextSpan(text: '$n crates = ${NumberFormat('#,##0').format(n * eggsPerCrate)} eggs', style: const TextStyle(fontWeight: FontWeight.w700)),
                const TextSpan(text: '.'),
              ])),
            const SizedBox(height: 8),
            for (final t in [
              'Your egg stock does not change. It is kept in individual eggs; only how it is shown changes.',
              'Sales already posted keep the box size they were recorded with. Their quantities and amounts do not change.',
              'Past stock movements and reports of past transactions are not recalculated.',
              if (!_on) 'Your box size is kept, so turning boxes back on later restores it.',
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('•  ', style: TextStyle(color: TColors.slate600)),
                  Expanded(child: Text(t, style: const TextStyle(fontSize: 14, color: TColors.slate600))),
                ]),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(key: const ValueKey('packaging-confirm-save'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true) await _save();
  }

  @override
  Widget build(BuildContext context) {
    final can = widget.canEdit;
    final n = _cratesN;
    final error = packagingConfigError(enableBoxes: _on, cratesPerBox: n, display: _display, saleEntryUnit: _entry);
    final preview = EggPackaging(eggsPerCrate: eggsPerCrate, enableBoxes: _on && n != null && n >= 1, cratesPerBox: _on ? n : null, display: _display);
    final dirty = _dirty;
    return Container(
      key: const ValueKey('egg-packaging-card'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.inventory_2_outlined, size: 16, color: _amber600),
                SizedBox(width: 6),
                Expanded(child: Text('Egg packaging & units', style: TextStyle(fontWeight: FontWeight.w600, color: TColors.slate900))),
              ]),
              SizedBox(height: 2),
              Text(
                'Large farms that sell by the box can enter and see eggs in boxes, crates and pieces. A box is only a way of '
                'counting: your stock is always kept in individual eggs, and nothing here packs eggs or changes stock.',
                style: TextStyle(fontSize: 13, color: TColors.slate600),
              ),
            ]),
          ),
          Switch(
            key: const ValueKey('packaging-boxes'),
            value: _on,
            onChanged: !can || _busy || _saved == null
                ? null
                : (v) => setState(() {
                      _on = v;
                      if (!v) {
                        if (_display == EggDisplay.boxesCratesPieces) _display = EggDisplay.cratesPieces;
                        _entry = SaleEntryUnit.crates;
                      } else if (_display == EggDisplay.cratesPieces) {
                        _display = EggDisplay.boxesCratesPieces;
                      }
                    }),
          ),
        ]),
        if (_loadError != null) Text(_loadError!, style: const TextStyle(fontSize: 13, color: TColors.rose700)),
        const SizedBox(height: 12),
        FilterLabel(
          'Crates per box',
          AppInput(
            key: const ValueKey('packaging-crates'),
            controller: _crates,
            enabled: can && _on,
            hintText: 'e.g. 14',
            keyboardType: TextInputType.number,
            onChanged: (v) {
              final digits = v.replaceAll(RegExp(r'[^\d]'), '');
              if (digits != v) _crates.text = digits;
              setState(() {});
            },
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _on && n != null && n >= 1 && n <= maxCratesPerBox
              ? '1 box = $n crates × $eggsPerCrate = ${NumberFormat('#,##0').format(n * eggsPerCrate)} eggs'
              : 'Whole number, 1 to $maxCratesPerBox. Eggs per box follows your eggs per crate ($eggsPerCrate).',
          style: const TextStyle(fontSize: 11, color: TColors.slate500),
        ),
        const SizedBox(height: 12),
        FilterLabel(
          'Show egg quantities as',
          AppSelect<EggDisplay>(
            key: const ValueKey('packaging-display'),
            value: _display,
            enabled: can,
            items: [
              for (final d in EggDisplay.values)
                if (d != EggDisplay.boxesCratesPieces || _on) AppSelectItem(value: d, label: eggDisplayText(d)),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _display = v);
            },
          ),
        ),
        const SizedBox(height: 4),
        Text.rich(TextSpan(style: const TextStyle(fontSize: 11, color: TColors.slate500), children: [
          TextSpan(text: '${NumberFormat('#,##0').format(_sample)} eggs → '),
          TextSpan(text: formatEggQuantity(_sample, preview, _display), style: const TextStyle(fontWeight: FontWeight.w700)),
        ])),
        const SizedBox(height: 12),
        FilterLabel(
          'Order of quantity fields on a sale',
          AppSelect<SaleEntryUnit>(
            key: const ValueKey('packaging-entry'),
            value: _entry,
            enabled: can && _on,
            items: const [
              AppSelectItem(value: SaleEntryUnit.boxes, label: 'Boxes, then crates, then pieces'),
              AppSelectItem(value: SaleEntryUnit.crates, label: 'Crates, then boxes, then pieces'),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _entry = v);
            },
          ),
        ),
        const SizedBox(height: 4),
        const Text('A sale line asks for boxes, crates and pieces. This only sets which comes first; the eggs sold are the same either way.',
            style: TextStyle(fontSize: 11, color: TColors.slate500)),
        if (error != null && dirty) ...[
          const SizedBox(height: 8),
          Text(error, style: const TextStyle(fontSize: 12, color: TColors.rose700)),
        ],
        const SizedBox(height: 10),
        Wrap(alignment: WrapAlignment.end, spacing: 8, children: [
          if (dirty)
            TextButton(onPressed: _busy ? null : () => setState(() => _reset(_saved!)), child: const Text('Cancel')),
          FilledButton(
            key: const ValueKey('packaging-save'),
            onPressed: !can || !dirty || error != null || _busy ? null : () => _conversionChanges ? _confirmThenSave() : _save(),
            child: const Text('Save'),
          ),
        ]),
      ]),
    );
  }
}
