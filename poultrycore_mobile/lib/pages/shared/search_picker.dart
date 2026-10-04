import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../design/ui/inputs.dart';
import 'currencies.dart';

/// A field that opens a searchable list — the web's Command popover, which
/// the currency picker uses and a 550-zone timezone list needs on a phone.
class SearchPickerField extends StatelessWidget {
  const SearchPickerField({
    super.key,
    required this.label,
    required this.items,
    required this.onPicked,
    this.placeholder = 'Pick…',
    this.searchHint = 'Search…',
    this.emptyText = 'Nothing found.',
    this.enabled = true,
  });

  /// What the field shows now; empty for the placeholder.
  final String label;
  final List<AppSelectItem<String>> items;
  final ValueChanged<String> onPicked;
  final String placeholder;
  final String searchHint;
  final String emptyText;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return OutlinedButton(
      onPressed: enabled ? () => _open(context) : null,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(44),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.isEmpty ? placeholder : label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                color: label.isEmpty ? tokens.mutedForeground : tokens.cardForeground,
              ),
            ),
          ),
          Icon(Icons.unfold_more, size: 18, color: tokens.mutedForeground),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PickerSheet(items: items, searchHint: searchHint, emptyText: emptyText),
    );
    if (picked != null) onPicked(picked);
  }
}

class _PickerSheet extends StatefulWidget {
  const _PickerSheet({required this.items, required this.searchHint, required this.emptyText});
  final List<AppSelectItem<String>> items;
  final String searchHint;
  final String emptyText;

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final shown = q.isEmpty
        ? widget.items
        : widget.items
            .where((i) => i.label.toLowerCase().contains(q) || i.value.toLowerCase().contains(q))
            .toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .8,
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: AppSearchField(hintText: widget.searchHint, onChanged: (v) => setState(() => _q = v)),
          ),
          Expanded(
            child: shown.isEmpty
                ? Center(child: Text(widget.emptyText))
                : ListView.builder(
                    itemCount: shown.length,
                    itemBuilder: (_, i) => ListTile(
                      dense: true,
                      title: Text(shown[i].label),
                      onTap: () => Navigator.of(context).pop(shown[i].value),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// The web's CurrencySelect: every currency as "GHS — Ghanaian Cedi (GH₵)",
/// searchable, Ghana and its neighbours first. A code that is not ISO (older
/// rows hold "GHC") still shows as itself.
class CurrencyPickerField extends StatelessWidget {
  const CurrencyPickerField({super.key, required this.code, required this.onChanged, this.enabled = true});
  final String code;
  final ValueChanged<CurrencyOption> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SearchPickerField(
      label: findCurrency(code)?.label ?? code,
      placeholder: 'Pick a currency',
      searchHint: 'Search currency…',
      emptyText: 'No currency found.',
      enabled: enabled,
      items: [for (final c in allCurrencies) AppSelectItem(value: c.code, label: c.label)],
      onPicked: (v) => onChanged(findCurrency(v)!),
    );
  }
}
