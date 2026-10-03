import 'package:flutter/material.dart';

import '../../design/ui/inputs.dart';

/// The web's BreedSelect (`components/poultry/breed-select.tsx`): a grouped
/// list — breeds already used on this farm first, then the catalogue — with
/// "Other" that switches to typing. A value the list has never heard of
/// still shows and stays selected.
class BreedPicker extends StatefulWidget {
  const BreedPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.known = const [],
    this.hintText = 'Select a breed',
    this.enabled = true,
  });

  final String value;
  final ValueChanged<String> onChanged;

  /// Breeds already used on this farm.
  final List<String> known;

  /// The web's `placeholder`.
  final String hintText;
  final bool enabled;

  @override
  State<BreedPicker> createState() => _BreedPickerState();
}

/// lib/poultry/breeds.ts — BREED_CATALOG.
const breedCatalog = <(String, List<String>)>[
  ('Layers', ['Isa Brown', 'Lohmann Brown', 'Bovan Brown', 'Hy-Line Brown',
      'Shaver Brown', 'Dekalb Brown', 'Nera Black']),
  ('Broilers', ['Cobb 500', 'Ross 308', 'Arbor Acres', 'Hubbard']),
  ('Dual purpose', ['Sasso', 'Kuroiler', 'Noiler', 'Rhode Island Red',
      'Plymouth Rock', 'Light Sussex']),
  ('Local', ['Local / Indigenous']),
];

/// Not a breed anyone can type, so it cannot collide with a real value.
const _other = '__other__';

class _BreedPickerState extends State<BreedPicker> {
  bool _typing = false;
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_typing) {
      return Row(
        children: [
          Expanded(
            child: AppInput(
              controller: _text,
              hintText: 'e.g., Rhode Island Red',
              onChanged: (v) => widget.onChanged(v.trim()),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.outlined(
            tooltip: 'Choose from the list instead',
            icon: const Icon(Icons.list, size: 18),
            onPressed: () => setState(() => _typing = false),
          ),
        ],
      );
    }

    // Used on this farm (the current value first), then the catalogue,
    // each breed once regardless of case.
    final seen = <String>{};
    final farm = <String>[];
    for (final raw in [widget.value, ...([...widget.known]..sort())]) {
      final v = raw.trim();
      if (v.isNotEmpty && seen.add(v.toLowerCase())) farm.add(v);
    }
    final catalog = [
      for (final (group, breeds) in breedCatalog)
        for (final b in breeds)
          if (seen.add(b.toLowerCase())) (group, b),
    ];

    return AppSelect<String>(
      value: widget.value.trim().isEmpty ? null : widget.value.trim(),
      hintText: widget.hintText,
      items: [
        for (final k in farm) AppSelectItem(value: k, label: '$k  ·  Used on this farm'),
        for (final (group, b) in catalog) AppSelectItem(value: b, label: '$b  ·  $group'),
        const AppSelectItem(value: _other, label: 'Other (type a breed)…'),
      ],
      onChanged: !widget.enabled
          ? null
          : (v) {
        if (v == _other) {
          // Start from empty so the farm types the new breed rather than
          // editing the one that happened to be selected.
          _text.clear();
          widget.onChanged('');
          setState(() => _typing = true);
        } else {
          widget.onChanged(v ?? '');
        }
      },
    );
  }
}
