import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/tokens.dart';
import '../../design/ui/buttons.dart';
import '../../design/ui/form_section.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';

/// Poultry → Setup → Production → Egg Pick Times, as
/// `app/business-office/egg-pick-settings/page.tsx`: the time of day each of
/// the six picks represents (display and reporting only — records stay
/// "1st Pick" … "6th Pick") and a switch per optional round. A settings page,
/// not a list: GET then PUT `/api/FarmProductionSettings`.
class EggPickSettingsScreen extends StatefulWidget {
  const EggPickSettingsScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<EggPickSettingsScreen> createState() => _EggPickSettingsScreenState();
}

/// DEFAULT_PICK_SETTINGS — no default for the 5th and 6th, so a farm that
/// never collects then sees "not set" rather than an invented hour.
const _defaults = {
  'firstPickTime': '09:00',
  'secondPickTime': '12:00',
  'thirdPickTime': '16:00',
  'fourthPickTime': '18:00',
  'fifthPickTime': '',
  'sixthPickTime': '',
};

const _rows = [
  ('firstPickTime', '1st Pick Time'),
  ('secondPickTime', '2nd Pick Time'),
  ('thirdPickTime', '3rd Pick Time'),
  ('fourthPickTime', '4th Pick Time'),
  ('fifthPickTime', '5th Pick Time'),
  ('sixthPickTime', '6th Pick Time'),
];

const _toggles = [
  ('enableFourthPick', 'Enable 4th Pick',
      'When off, the 4th Pick input is hidden on entry forms. Records and reports still support it, so you can turn it on any time without losing data.'),
  ('enableFifthPick', 'Enable 5th Pick',
      'Sets the time and the label. Production records cannot store a 5th pick yet, so entry forms will start using it once they can.'),
  ('enableSixthPick', 'Enable 6th Pick',
      'Sets the time and the label. Production records cannot store a 6th pick yet, so entry forms will start using it once they can.'),
];

/// formatPickTime: "16:00" -> "4:00 PM".
String formatPickTime(String hhmm) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(hhmm.trim());
  if (m == null) return hhmm;
  var h = int.parse(m.group(1)!);
  final ampm = h >= 12 ? 'PM' : 'AM';
  h %= 12;
  if (h == 0) h = 12;
  return '$h:${m.group(2)} $ampm';
}

class _EggPickSettingsScreenState extends State<EggPickSettingsScreen> {
  final Map<String, String> _times = Map.of(_defaults);
  final Map<String, bool> _enabled = {for (final t in _toggles) t.$1: false};
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// "HH:mm" from whatever the API sends ("16:00:00" for a TimeSpan).
  static String _hhmm(Object? v) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch('${v ?? ''}');
    return m == null ? '' : '${m.group(1)!.padLeft(2, '0')}:${m.group(2)}';
  }

  Future<void> _load() async {
    try {
      final res = await widget.session.farmClient
          .get('/api/FarmProductionSettings', query: {'farmId': widget.company.farmId});
      if (res is Map) _apply(res);
    } catch (_) {
      // Keep the defaults, as the web does.
    }
    if (mounted) setState(() => _loading = false);
  }

  /// mapSettings: missing 1st–4th fall back to the defaults, missing 5th/6th
  /// stay blank.
  void _apply(Map res) {
    for (final (key, _) in _rows) {
      final v = _hhmm(res[key]);
      _times[key] = v.isNotEmpty ? v : _defaults[key]!;
    }
    for (final (key, _, _) in _toggles) {
      _enabled[key] = res[key] == true;
    }
  }

  Future<void> _pick(String key) async {
    final cur = _times[key]!;
    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(cur);
    final picked = await showTimePicker(
      context: context,
      initialTime: m == null
          ? const TimeOfDay(hour: 9, minute: 0)
          : TimeOfDay(hour: int.parse(m.group(1)!), minute: int.parse(m.group(2)!)),
    );
    if (picked == null) return;
    setState(() => _times[key] =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    String? t(String k) => _times[k]!.isEmpty ? null : _times[k];
    try {
      final res = await widget.session.farmClient.put('/api/FarmProductionSettings', body: {
        'FarmId': widget.company.farmId,
        'FirstPickTime': t('firstPickTime'),
        'SecondPickTime': t('secondPickTime'),
        'ThirdPickTime': t('thirdPickTime'),
        'FourthPickTime': t('fourthPickTime'),
        'FifthPickTime': t('fifthPickTime'),
        'SixthPickTime': t('sixthPickTime'),
        'EnableFourthPick': _enabled['enableFourthPick'],
        'EnableFifthPick': _enabled['enableFifthPick'],
        'EnableSixthPick': _enabled['enableSixthPick'],
        'UpdatedBy': widget.session.tokens.userId,
      });
      if (!mounted) return;
      setState(() {
        if (res is Map) _apply(res);
        _saving = false;
      });
      messenger.showSnackBar(const SnackBar(content: Text('Egg pick settings saved')));
    } on ApiException catch (e) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('Save failed. ${e.message}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final lead = sidebarLeading(context, widget.session, widget.company,
        href: '/business-office/egg-pick-settings');
    return Scaffold(
      appBar: AppBar(
        leading: lead.leading,
        leadingWidth: lead.width,
        title: const Text('Egg Pick Time Settings'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
              children: [
                Text(
                  'Configure the time of day each egg pick represents for this farm. These times are used '
                  'for display and reporting, while production records are labelled 1st Pick through 6th Pick.',
                  style: TextStyle(fontSize: 12.5, color: tokens.mutedForeground),
                ),
                const SizedBox(height: 12),
                FormSection(title: 'Pick times', color: SectionColor.emerald, children: [
                  for (final (key, label) in _rows)
                    AppField(
                      label: label,
                      hint: _times[key]!.isEmpty
                          ? 'Not set — falls back to the default.'
                          : formatPickTime(_times[key]!),
                      child: OutlinedButton.icon(
                        onPressed: _saving ? null : () => _pick(key),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                          alignment: Alignment.centerLeft,
                        ),
                        icon: const Icon(Icons.schedule, size: 18),
                        label: Text(_times[key]!.isEmpty ? '--:--' : _times[key]!),
                      ),
                    ),
                ]),
                const SizedBox(height: 12),
                for (final (key, label, hint) in _toggles) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: tokens.muted,
                      border: Border.all(color: tokens.border),
                      borderRadius: BorderRadius.circular(Dim.radiusMd),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Switch(
                          value: _enabled[key]!,
                          onChanged: _saving ? null : (v) => setState(() => _enabled[key] = v),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                              Text(hint, style: TextStyle(fontSize: 12, color: tokens.mutedForeground)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: 'Cancel',
                        variant: AppButtonVariant.outline,
                        size: AppButtonSize.lg,
                        fullWidth: true,
                        onPressed: _saving ? null : () => Navigator.of(context).maybePop(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppButton(
                        label: 'Save settings',
                        icon: Icons.save_outlined,
                        size: AppButtonSize.lg,
                        fullWidth: true,
                        busy: _saving,
                        onPressed: _saving ? null : _save,
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
