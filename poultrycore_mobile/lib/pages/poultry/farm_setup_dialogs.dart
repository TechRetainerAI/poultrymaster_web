import 'package:flutter/material.dart';

import '../../design/ui/inputs.dart';
import 'farm_setup_wizard.dart';

// The three dialogs Initial Farm Setup opens from inside a step, as
// `components/poultry/pen-capacity-dialog.tsx`, `new-pen-dialog.tsx` and
// `batch-size-dialog.tsx`: each fixes a number where it was found wrong.

const _amber700 = Color(0xFFB45309);
const _blue700 = Color(0xFF1D4ED8);

Widget _figure(BuildContext context, String label, String value, {Color? color}) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
          Text(value, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
        ]),
      ),
    );

Widget _label(String text) =>
    Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)));

// ------------------------------------------------------------ pen capacity

/// "Update `pen` capacity". [onSave] throws to keep the dialog open with its
/// message; completes true once saved.
Future<bool?> showPenCapacityDialog(
  BuildContext context, {
  required String penName,
  required int? capacity,
  required int occupied,
  required int standing,
  required bool savesImmediately,
  required Future<void> Function(int capacity) onSave,
}) =>
    showDialog<bool>(
      context: context,
      builder: (_) => _PenCapacityDialog(
        penName: penName,
        capacity: capacity,
        occupied: occupied,
        standing: standing,
        savesImmediately: savesImmediately,
        onSave: onSave,
      ),
    );

class _PenCapacityDialog extends StatefulWidget {
  const _PenCapacityDialog({
    required this.penName,
    required this.capacity,
    required this.occupied,
    required this.standing,
    required this.savesImmediately,
    required this.onSave,
  });
  final String penName;
  final int? capacity;
  final int occupied, standing;
  final bool savesImmediately;
  final Future<void> Function(int) onSave;

  @override
  State<_PenCapacityDialog> createState() => _PenCapacityDialogState();
}

class _PenCapacityDialogState extends State<_PenCapacityDialog> {
  late final int _total = widget.occupied + widget.standing;
  late final _value = TextEditingController(text: '$_total');
  bool _saving = false;
  String _error = '';

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final entered = double.tryParse(_value.text.trim());
    if (entered == null || entered < 0) {
      setState(() => _error = 'Enter how many birds this pen can hold.');
      return;
    }
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      await widget.onSave(entered.floor());
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e is StateError ? e.message : 'That could not be saved. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final entered = double.tryParse(_value.text.trim());
    final tooSmall = entered != null && entered > 0 && entered < _total;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text('Update ${widget.penName.isEmpty ? 'pen' : widget.penName} capacity'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              widget.savesImmediately
                  ? 'This saves to the pen straight away — it is not part of the setup you are filling in.'
                  : 'This pen is being created by this setup, so the change is saved with the rest of it.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            Row(children: [
              _figure(context, 'Recorded', widget.capacity == null ? '—' : fmtInt(widget.capacity!)),
              const SizedBox(width: 6),
              _figure(context, 'Already in it', fmtInt(widget.occupied)),
              const SizedBox(width: 6),
              _figure(context, 'This setup adds', fmtInt(widget.standing), color: _blue700),
            ]),
            const SizedBox(height: 12),
            _label('Capacity (birds)'),
            AppNumberInput(controller: _value, enabled: !_saving, onChanged: (_) => setState(() {})),
            const SizedBox(height: 4),
            Text('${fmtInt(_total)} birds are in this pen. Leave it at 0 if the pen has no limit.',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            if (tooSmall) ...[
              const SizedBox(height: 6),
              Text('That is less than the ${fmtInt(_total)} birds already in the pen. You can still save it.',
                  style: const TextStyle(fontSize: 12, color: _amber700)),
            ],
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(_error, style: const TextStyle(fontSize: 12, color: Color(0xFFDC2626))),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: _saving ? null : _submit, child: Text(_saving ? 'Saving…' : 'Save capacity')),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- new pen

typedef NewPen = ({String name, String capacity, String location});

/// "New house/pen": one pen, or a run of them. Completes with the pens.
Future<List<NewPen>?> showNewPenDialog(
  BuildContext context, {
  required String suggestedName,
  required List<String> takenNames,
}) =>
    showDialog<List<NewPen>>(
      context: context,
      builder: (_) => _NewPenDialog(suggestedName: suggestedName, takenNames: takenNames),
    );

class _NewPenDialog extends StatefulWidget {
  const _NewPenDialog({required this.suggestedName, required this.takenNames});
  final String suggestedName;
  final List<String> takenNames;

  @override
  State<_NewPenDialog> createState() => _NewPenDialogState();
}

class _NewPenDialogState extends State<_NewPenDialog> {
  late final _name = TextEditingController(text: widget.suggestedName);
  final _capacity = TextEditingController();
  final _location = TextEditingController();
  final _count = TextEditingController(text: '4');
  final _prefix = TextEditingController(text: 'Pen');
  final _start = TextEditingController();
  String _mode = 'single';
  String _error = '';

  @override
  void dispose() {
    for (final c in [_name, _capacity, _location, _count, _prefix, _start]) {
      c.dispose();
    }
    super.dispose();
  }

  int get _suggestedStart => nextStartNumber(_prefix.text, widget.takenNames);

  List<HouseRow> get _preview => _mode != 'multiple'
      ? const []
      : generateHouseRows(
          count: int.tryParse(_count.text.trim()) ?? 0,
          prefix: _prefix.text,
          startNumber: int.tryParse(_start.text.trim()) ?? _suggestedStart,
          capacity: _capacity.text,
          location: _location.text,
        );

  bool _taken(String name) => widget.takenNames.any((t) => duplicateKey(t) == duplicateKey(name));

  void _submit() {
    if (_mode == 'multiple') {
      final n = int.tryParse(_count.text.trim());
      if (n == null || n < 1) return setState(() => _error = 'Enter how many pens to add.');
      if (n > maxBulkRows) return setState(() => _error = 'Add at most $maxBulkRows pens at a time.');
      final clash = _preview.where((r) => _taken(r.houseName)).firstOrNull;
      if (clash != null) {
        return setState(
            () => _error = 'You already have a pen called "${clash.houseName}". Change the starting number or prefix.');
      }
      Navigator.of(context).pop([for (final r in _preview) (name: r.houseName, capacity: r.capacity, location: r.location)]);
      return;
    }
    final trimmed = _name.text.trim();
    if (trimmed.isEmpty) return setState(() => _error = 'Give the pen a name.');
    if (_taken(trimmed)) return setState(() => _error = 'You already have a pen called "$trimmed".');
    Navigator.of(context).pop(<NewPen>[(name: trimmed, capacity: _capacity.text.trim(), location: _location.text.trim())]);
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    void changed(_) => setState(() => _error = '');
    return AlertDialog(
      title: const Text('New house/pen'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Added to this setup and selected for this batch. Created along with everything else when you finish.',
              style: TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'single', label: Text('Add single pen')),
              ButtonSegment(value: 'multiple', label: Text('Add multiple pens')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() {
              _mode = s.first;
              _error = '';
            }),
          ),
          const SizedBox(height: 12),
          if (_mode == 'multiple') ...[
            _label('Number of pens *'),
            AppNumberInput(controller: _count, onChanged: changed),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _label('Prefix'),
                  AppInput(controller: _prefix, hintText: 'Pen', onChanged: changed),
                ]),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _label('Starting number'),
                  AppNumberInput(controller: _start, hintText: '$_suggestedStart', onChanged: changed),
                ]),
              ),
            ]),
          ] else ...[
            _label('House/Pen name *'),
            AppInput(controller: _name, hintText: 'Pen 5', onChanged: changed),
          ],
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _label('Capacity'),
                AppNumberInput(controller: _capacity, hintText: '2000', onChanged: changed),
              ]),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _label('Location'),
                AppInput(controller: _location, hintText: 'Layer House A', onChanged: changed),
              ]),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            'Leave the capacity blank if the pen has no set limit.'
            '${_mode == 'multiple' ? ' Capacity and location apply to every pen.' : ''}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          if (_mode == 'multiple' && preview.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Will add: ${preview.length <= 4 ? preview.map((r) => r.houseName).join(', ') : '${preview[0].houseName}, ${preview[1].houseName} … ${preview.last.houseName}'}'
              ' (${preview.length} pen${preview.length == 1 ? '' : 's'})',
              style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
            ),
          ],
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(_error, style: const TextStyle(fontSize: 12, color: Color(0xFFDC2626))),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: _submit,
          child: Text(_mode == 'multiple' && preview.length > 1 ? 'Add ${preview.length} pens' : 'Add pen'),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ batch size

/// "Update `batch` bird count". [onSave] throws to keep the dialog open.
Future<bool?> showBatchSizeDialog(
  BuildContext context, {
  required String batchLabel,
  required int batchBirds,
  required int previouslyAllocated,
  required int thisAllocation,
  required bool savesImmediately,
  required Future<void> Function(int numberOfBirds) onSave,
}) =>
    showDialog<bool>(
      context: context,
      builder: (_) => _BatchSizeDialog(
        batchLabel: batchLabel,
        batchBirds: batchBirds,
        previouslyAllocated: previouslyAllocated,
        thisAllocation: thisAllocation,
        savesImmediately: savesImmediately,
        onSave: onSave,
      ),
    );

class _BatchSizeDialog extends StatefulWidget {
  const _BatchSizeDialog({
    required this.batchLabel,
    required this.batchBirds,
    required this.previouslyAllocated,
    required this.thisAllocation,
    required this.savesImmediately,
    required this.onSave,
  });
  final String batchLabel;
  final int batchBirds, previouslyAllocated, thisAllocation;
  final bool savesImmediately;
  final Future<void> Function(int) onSave;

  @override
  State<_BatchSizeDialog> createState() => _BatchSizeDialogState();
}

class _BatchSizeDialogState extends State<_BatchSizeDialog> {
  late final int _accounted = widget.previouslyAllocated + widget.thisAllocation;
  late final _value = TextEditingController(text: '$_accounted');
  bool _saving = false;
  String _error = '';

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final entered = double.tryParse(_value.text.trim());
    final valid = entered != null && entered > 0;
    if (!valid) return setState(() => _error = 'Enter how many birds this batch was bought with.');
    if (entered < _accounted) {
      return setState(() =>
          _error = '${fmtInt(_accounted)} birds are already placed from this batch. It cannot be smaller than that.');
    }
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      await widget.onSave(entered.floor());
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e is StateError ? e.message : 'That could not be saved. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final entered = double.tryParse(_value.text.trim());
    final valid = entered != null && entered > 0;
    final changesStock = widget.savesImmediately && valid && entered != widget.batchBirds;
    final delta = (entered ?? 0) - widget.batchBirds;
    final abs = delta.abs().round();
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text('Update ${widget.batchLabel.isEmpty ? 'batch' : widget.batchLabel} bird count'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              widget.savesImmediately
                  ? 'This saves to the batch straight away — it is not part of the setup you are filling in.'
                  : 'This batch is being created by this setup, so the change is saved with the rest of it.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            Row(children: [
              _figure(context, 'Recorded', fmtInt(widget.batchBirds)),
              const SizedBox(width: 6),
              _figure(context, 'Already placed', fmtInt(widget.previouslyAllocated)),
              const SizedBox(width: 6),
              _figure(context, 'This setup places', fmtInt(widget.thisAllocation), color: _blue700),
            ]),
            const SizedBox(height: 12),
            _label('Birds bought (original)'),
            AppNumberInput(controller: _value, enabled: !_saving, onChanged: (_) => setState(() {})),
            const SizedBox(height: 4),
            Text('Your flocks account for ${fmtInt(_accounted)} birds from this batch.',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            if (changesStock) ...[
              const SizedBox(height: 6),
              Text(
                'This also ${delta > 0 ? 'adds' : 'removes'} ${fmtInt(abs)} bird${abs == 1 ? '' : 's'} '
                '${delta > 0 ? 'to' : 'from'} your bird stock, because the batch record is what stock is counted from. '
                'Only do this if the batch really was that size.',
                style: const TextStyle(fontSize: 12, color: _amber700),
              ),
            ],
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(_error, style: const TextStyle(fontSize: 12, color: Color(0xFFDC2626))),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: _saving ? null : _submit, child: Text(_saving ? 'Saving…' : 'Save bird count')),
        ],
      ),
    );
  }
}
