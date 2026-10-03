import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/tokens.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../lookup_loader.dart';
import 'search_picker.dart';

/// The web's CompanyTimeZoneField (`components/settings/company-timezone-field.tsx`),
/// shared by every company type's setup page: the business timezone, its own
/// Save / Confirm button (it saves on its own, not with the form), today's
/// business date, and a warning while it is still the guess made from the
/// currency (migration 298).
class CompanyTimeZoneField extends StatefulWidget {
  const CompanyTimeZoneField({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<CompanyTimeZoneField> createState() => _CompanyTimeZoneFieldState();
}

class _CompanyTimeZoneFieldState extends State<CompanyTimeZoneField> {
  Map? _ctx;
  List<AppSelectItem<String>> _zones = const [];
  String _selected = '';
  bool _saving = false;
  bool _justSaved = false;
  String? _error;

  ApiClient get _client => widget.session.farmClient;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([
        _client.get('/api/CompanyTime/context', query: {'farmId': widget.company.farmId}),
        _client.get('/api/CompanyTime/zones'),
      ]);
      if (!mounted) return;
      setState(() {
        _ctx = r[0] is Map ? r[0] as Map : null;
        _selected = '${_ctx?['timeZoneId'] ?? ''}';
        _zones = [
          for (final z in LookupLoader.rowsIn(r[1]))
            if (z is Map)
              AppSelectItem(value: '${z['timeZoneId']}', label: '${z['timeZoneId']} (${z['utcOffset']})'),
        ];
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load the company timezone.');
    }
  }

  Future<void> _save() async {
    if (_selected.isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
      _justSaved = false;
    });
    try {
      final r = await _client.put(
        '/api/CompanyTime/timezone?farmId=${Uri.encodeComponent(widget.company.farmId)}',
        body: {
          'farmId': widget.company.farmId,
          'timeZoneId': _selected,
          'updatedBy': widget.session.tokens.userId,
        },
      );
      if (!mounted) return;
      setState(() {
        if (r is Map && _ctx != null) {
          _ctx = {
            ..._ctx!,
            'timeZoneId': r['timeZoneId'],
            'timeZoneConfirmed': r['timeZoneConfirmed'],
            'businessDate': r['businessDate'],
          };
        }
        _justSaved = true;
      });
    } on ApiException catch (e) {
      // A 400 carries the server's own wording ("Use a region id such as
      // Africa/Accra…"), which beats a generic message.
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final ctx = _ctx;
    final changed = ctx != null && _selected != '${ctx['timeZoneId']}';
    final needsConfirming = ctx != null && ctx['timeZoneConfirmed'] != true;
    final zoneLabel = _zones.where((z) => z.value == _selected).firstOrNull?.label ?? _selected;
    TextStyle small(Color c) => TextStyle(fontSize: 12, color: c);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SearchPickerField(
          label: zoneLabel,
          placeholder: ctx != null ? 'Pick a timezone' : 'Loading…',
          searchHint: 'Search timezone…',
          enabled: _zones.isNotEmpty,
          items: _zones,
          onPicked: (v) => setState(() {
            _selected = v;
            _justSaved = false;
          }),
        ),
        if (ctx != null) ...[
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(style: small(tokens.mutedForeground), children: [
              const TextSpan(text: 'Today here is '),
              TextSpan(text: '${ctx['businessDate'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
              const TextSpan(
                  text: '. New records default to this date, and daily and period reports start and end by it.'),
            ]),
          ),
        ],
        if (needsConfirming && !changed) ...[
          const SizedBox(height: 6),
          Text(
            'This was guessed from your currency and has not been confirmed. '
            'If it is right, save it once to confirm.',
            style: small(const Color(0xFFB45309)), // amber-700
          ),
        ],
        if (changed) ...[
          const SizedBox(height: 6),
          Text(
            'Changing this does not alter any date already recorded — only what new entries '
            'default to and where report days start and end.',
            style: small(tokens.mutedForeground),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(_error!, style: small(Theme.of(context).colorScheme.error)),
        ],
        if (_justSaved && !changed) ...[
          const SizedBox(height: 6),
          Text('✓ Timezone confirmed.', style: small(const Color(0xFF047857))),
        ],
        if (ctx != null && (changed || needsConfirming)) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : changed ? 'Save timezone' : 'Confirm timezone'),
            ),
          ),
        ],
      ],
    );
  }
}
