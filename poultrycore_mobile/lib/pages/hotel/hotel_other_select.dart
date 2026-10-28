// components/hotel/other-select.tsx (migration 300): a Hotel dropdown whose
// "Other" choice opens a text box, and whose typed value is remembered against
// this hotel once the record holding it saves, so it is a normal option next
// time. Kept apart from RestaurantOtherSelect as the web keeps the two apart:
// each talks to its own module's custom-options endpoint.

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../poultry/trackers/tracker_widgets.dart' show trackerToast;

const _other = '__other__';
const _none = '__none__';

class HotelOtherSelect extends StatefulWidget {
  const HotelOtherSelect({
    super.key,
    required this.session,
    required this.company,
    required this.listKey,
    required this.baseOptions,
    required this.value,
    required this.onChanged,
    this.placeholder = 'Select',
    this.includeNone = false,
    this.noneLabel = 'None',
    this.otherLabel = 'Other (type your own)',
    this.typePlaceholder = 'Type your own',
  });

  final Session session;
  final Company company;

  /// Which remembered list this dropdown draws from (HotelCustomOptionListKey).
  final String listKey;
  final List<String> baseOptions;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String placeholder;

  /// Adds a row that clears the value, labelled [noneLabel].
  final bool includeNone;
  final String noneLabel;
  final String otherLabel;
  final String typePlaceholder;

  @override
  State<HotelOtherSelect> createState() => HotelOtherSelectState();
}

class HotelOtherSelectState extends State<HotelOtherSelect> {
  List<String> _custom = [];
  bool _typing = false;
  final _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCustom();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  // Remembered values. Failure is silent: the seed options still work.
  Future<void> _loadCustom() async {
    try {
      final r = await widget.session.farmClient.get(
        '/api/Hotel/custom-options',
        query: {'listKey': widget.listKey, 'farmId': widget.company.farmId},
      );
      if (!mounted) return;
      setState(
        () => _custom = [
          for (final x in (r is List ? r : const []))
            if (x is Map) '${x['value'] ?? ''}',
        ],
      );
    } catch (_) {}
  }

  /// Everything pickable, de-duplicated case-insensitively. Any seed row that
  /// reads "Other" is dropped (several seed tables ship one), and the current
  /// value is folded in unless typing, so an old value is never lost.
  List<String> get _options {
    final seen = <String>{};
    final out = <String>[];
    for (final o in [...widget.baseOptions, ..._custom, if (!_typing && (widget.value ?? '').isNotEmpty) widget.value!]) {
      final v = o.trim();
      if (v.isEmpty || v.toLowerCase() == 'other') continue;
      if (seen.add(v.toLowerCase())) out.add(v);
    }
    return out;
  }

  /// Saves what was typed under "Other" so it is an option next time. Call
  /// after the record holding it saved. A no-op unless "Other" is in use, and
  /// a failure never reads as the record failing.
  Future<void> remember() async {
    if (!_typing) return;
    final v = _text.text.trim();
    if (v.isEmpty) return;
    try {
      await widget.session.farmClient.post(
        '/api/Hotel/custom-options',
        body: {'farmId': widget.company.farmId, 'listKey': widget.listKey, 'value': v},
      );
      if (!mounted) return;
      setState(() {
        if (!_custom.any((p) => p.toLowerCase() == v.toLowerCase())) _custom = [..._custom, v];
        _typing = false;
      });
    } on ApiException catch (e) {
      if (mounted) {
        trackerToast(
          context,
          'Saved, but the value was not remembered',
          description: e.message.isEmpty ? 'It applies to this record; it just will not be in the list next time.' : e.message,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final opts = _options;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppSelect<String>(
          value: _typing ? _other : ((widget.value ?? '').isEmpty ? (widget.includeNone ? _none : null) : widget.value),
          hintText: widget.placeholder,
          items: [
            if (widget.includeNone) AppSelectItem(value: _none, label: widget.noneLabel),
            for (final o in opts) AppSelectItem(value: o, label: o),
            AppSelectItem(value: _other, label: widget.otherLabel),
          ],
          onChanged: (v) {
            if (v == _other) {
              setState(() {
                _typing = true;
                _text.clear();
              });
              widget.onChanged(null);
              return;
            }
            setState(() => _typing = false);
            widget.onChanged(v == _none ? null : v);
          },
        ),
        if (_typing) ...[
          const SizedBox(height: 6),
          AppInput(
            controller: _text,
            hintText: widget.typePlaceholder,
            autofocus: true,
            onChanged: (v) => widget.onChanged(v.isEmpty ? null : v),
          ),
        ],
      ],
    );
  }
}
