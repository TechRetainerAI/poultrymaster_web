import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import 'egg_packaging.dart';
import 'egg_sorting/egg_packaging_card.dart';
import 'egg_sorting/egg_sorting_widgets.dart' show EggCompactScope, PanelSection, SizesSettingsPanel;
import 'production/production_logic.dart' show eggsPerCrate;
import 'reports/report_routes.dart' show openAppHref;
import 'trackers/egg_class_ledger.dart' show cratesText, fmtCount;
import 'trackers/tracker_logic.dart' show tNum;
import 'trackers/tracker_widgets.dart';

import 'package:poultrycore_mobile/design/tone.dart';
import 'setup/setup_embed.dart';
/// Poultry → Setup → Production → **Egg Settings** (was Egg Configuration)
/// (`app/business-office/egg-pick-settings/page.tsx`, was "Egg Pick Time
/// Settings"): one place for the farm's egg settings, as four tabs --
///   - Pick times: the time each pick represents (display and reporting only;
///     records stay "1st Pick" … "6th Pick") and a switch per optional round.
///     GET then PUT `/api/FarmProductionSettings`.
///   - Egg sorting, Packaging & units, Egg sizes: the same cards as the Egg
///     Sorting Workspace's "Sizes & settings" tab (341–344, 393, 394).
/// [initialTab] is the web's `?tab=picks|sorting|packaging|sizes`.
class EggPickSettingsScreen extends StatefulWidget {
  const EggPickSettingsScreen({super.key, required this.session, required this.company, this.initialTab = 'picks'});
  final Session session;
  final Company company;
  final String initialTab;

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

/// PICKS: key, number, label, its switch (the 4th–6th), the hint under it.
const _picks = <(String, int, String, String?, String?)>[
  ('firstPickTime', 1, '1st Pick', null, null),
  ('secondPickTime', 2, '2nd Pick', null, null),
  ('thirdPickTime', 3, '3rd Pick', null, null),
  ('fourthPickTime', 4, '4th Pick', 'enableFourthPick',
      'When off, the 4th Pick input is hidden on entry forms. Records and reports still support it, so you can turn it on any time without losing data.'),
  ('fifthPickTime', 5, '5th Pick', 'enableFifthPick',
      'Sets the time and the label. Production records cannot store a 5th pick yet, so entry forms will start using it once they can.'),
  ('sixthPickTime', 6, '6th Pick', 'enableSixthPick',
      'Sets the time and the label. Production records cannot store a 6th pick yet, so entry forms will start using it once they can.'),
];

final _rows = [for (final p in _picks) (p.$1, p.$3)];
final _toggles = [for (final p in _picks) if (p.$4 != null) (p.$4!, p.$3, p.$5!)];

/// The tabs: value, label, icon.
const _tabs = <(String, String, IconData)>[
  ('picks', 'Pick times', Icons.schedule),
  ('sorting', 'Egg sorting', Icons.settings_outlined),
  ('packaging', 'Packaging & units', Icons.inventory_2_outlined),
  ('sizes', 'Egg sizes', Icons.layers_outlined),
];

const _amber50 = Tone.bg(0xFFFFFBEB);
const _amber200 = Tone.line(0xFFFDE68A);
const _amber500 = Tone.bg(0xFFF59E0B);
const _amber900 = Tone.fg(0xFF78350F);
const _emerald100 = Tone.bg(0xFFD1FAE5);
const _emerald200 = Tone.line(0xFFA7F3D0);
const _emerald500 = Tone.bg(0xFF10B981);
const _emerald600 = Tone.fg(0xFF059669);
const _emerald700 = Tone.fg(0xFF047857);
const _emerald800 = Tone.fg(0xFF065F46);

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
  /// Farm Setup asks before leaving with unsaved pick times.
  final Object _dirtyKey = Object();
  final Map<String, String> _times = Map.of(_defaults);
  final Map<String, bool> _enabled = {for (final t in _toggles) t.$1: false};
  Map<String, String> _savedTimes = Map.of(_defaults);
  Map<String, bool> _savedEnabled = {for (final t in _toggles) t.$1: false};
  bool _loading = true;
  bool _saving = false;
  late String _tab = _tabs.any((t) => t.$1 == widget.initialTab) ? widget.initialTab : 'picks';

  // Egg sorting, packaging, sizes.
  Map? _settings;
  List<Map> _classes = [];
  String? _eggError;

  bool get _canEditEggs => (widget.company.role ?? '').toLowerCase() != 'staff';

  bool get _picksDirty =>
      _times.entries.any((e) => _savedTimes[e.key] != e.value) || _enabled.entries.any((e) => _savedEnabled[e.key] != e.value);

  @override
  void initState() {
    super.initState();
    _load();
    _loadEggs();
    loadEggPackaging(widget.session, widget.company).then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _loadEggs() async {
    final api = widget.session.farmClient;
    try {
      setState(() => _eggError = null);
      final s = await api.get('/api/Poultry/egg-sorting/settings', query: {'farmId': widget.company.farmId});
      final on = s is Map && s['enableEggSorting'] == true;
      final c = await api.get('/api/Poultry/egg-sorting/classes',
          query: {'farmId': widget.company.farmId, 'includeInactive': 'true', 'ensure': '$on'});
      if (mounted) {
        setState(() {
          _settings = s is Map ? s : null;
          _classes = rowsOf(c);
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _eggError = e.message.isNotEmpty ? e.message : 'Could not load egg sorting settings.');
    }
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
    _savedTimes = Map.of(_times);
    _savedEnabled = Map.of(_enabled);
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
      if (res is! Map) {
        _savedTimes = Map.of(_times);
        _savedEnabled = Map.of(_enabled);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('Save failed. ${e.message}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/business-office/egg-pick-settings');
    final enabledPicks = [for (final p in _picks) if (p.$4 == null || _enabled[p.$4] == true) p];
    final pk = eggPackagingFor(widget.company.farmId);
    final activeSizes = _classes.where((c) => c['classKind'] == 'Size' && c['isActive'] == true).length;
    final status = {
      'picks': _loading ? '…' : '${enabledPicks.length} picks a day',
      'sorting': _settings == null ? '…' : (_settings!['enableEggSorting'] == true ? 'On' : 'Off'),
      'packaging': boxSize(pk) != null ? 'Boxes of ${pk.cratesPerBox} crates' : 'Crates of $eggsPerCrate',
      'sizes': _settings == null ? '…' : '$activeSizes active',
    };
    final unsorted = _classes.where((c) => c['classKind'] == 'Unsorted').firstOrNull;
    return Scaffold(
      appBar: isSetupEmbedded(context) ? null : AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Egg Settings')),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([_load(), _loadEggs()]);
        },
        child: ListView(
          key: const ValueKey('egg-config-list'),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: isSetupEmbedded(context)
              ? _embedded(status, enabledPicks, unsorted)
              : [
            _header(),
            const SizedBox(height: 14),
            _tabGrid(status),
            const SizedBox(height: 14),
            if (_eggError != null && _tab != 'picks') ...[TrackerBanner.error(_eggError!), const SizedBox(height: 12)],
            ...switch (_tab) {
              'sorting' => [
                  SizesSettingsPanel(
                    session: widget.session,
                    company: widget.company,
                    settings: _settings,
                    classes: _classes,
                    canEdit: _canEditEggs,
                    onChanged: _loadEggs,
                    section: PanelSection.sorting,
                  ),
                  if (unsorted != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Unsorted / General eggs on hand: ${fmtCount(tNum(unsorted['onHand']))} (${cratesText(tNum(unsorted['onHand']))}). Production always adds to Unsorted.',
                      style: const TextStyle(fontSize: 12, color: TColors.slate500),
                    ),
                  ],
                ],
              'packaging' => [
                  EggPackagingCard(
                    session: widget.session,
                    company: widget.company,
                    canEdit: _canEditEggs,
                    onChanged: () => setState(() {}),
                  ),
                ],
              'sizes' => [
                  SizesSettingsPanel(
                    session: widget.session,
                    company: widget.company,
                    settings: _settings,
                    classes: _classes,
                    canEdit: _canEditEggs,
                    onChanged: _loadEggs,
                    section: PanelSection.sizes,
                  ),
                ],
              _ => _pickTimes(enabledPicks),
            },
          ],
        ),
      ),
    );
  }

  Widget _header() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_amber50, Tone.bg(0xFFFFFFFF), Tone.bg(0xFFECFDF5)]),
          border: Border.all(color: const Tone.line(0xFFFEF3C7)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: _amber500, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.egg_outlined, color: Colors.white),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Egg Settings', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: TColors.slate900)),
                Text(
                  'Everything about how this farm collects, counts, sorts and prices its eggs — pick times, egg sorting, packaging units and egg sizes.',
                  style: TextStyle(fontSize: 13, color: TColors.slate600),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const ValueKey('egg-config-open-sorting'),
            style: OutlinedButton.styleFrom(backgroundColor: Tone.button(Tone.bg(0xFFFFFFFF)), foregroundColor: TColors.slate800),
            onPressed: () => openAppHref(context, widget.session, widget.company, '/poultry-egg-sorting', label: 'Egg Sorting'),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Open Egg Sorting'),
          ),
        ]),
      );

  /// The four tabs, two per row on a phone, each with its status line.
  Widget _tabGrid(Map<String, String> status) {
    Widget tab((String, String, IconData) t) {
      final on = _tab == t.$1;
      return InkWell(
        key: ValueKey('egg-config-tab-${t.$1}'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => _tab = t.$1),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: on ? _amber50 : Colors.transparent,
            border: Border.all(color: on ? _amber200 : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(t.$3, size: 16, color: on ? _amber900 : TColors.slate700),
              const SizedBox(width: 6),
              Flexible(child: Text(t.$2, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: on ? _amber900 : TColors.slate700))),
            ]),
            const SizedBox(height: 2),
            Text(status[t.$1]!, style: const TextStyle(fontSize: 11, color: TColors.slate500)),
          ]),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Tone.bg(0xFFFFFFFF), border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        for (var i = 0; i < _tabs.length; i += 2)
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: tab(_tabs[i])),
              const SizedBox(width: 4),
              Expanded(child: tab(_tabs[i + 1])),
            ]),
          ),
      ]),
    );
  }

  /// Inside Farm Setup the four tabs are one page (setup-views/egg-pick-settings.tsx):
  /// four titled panels, each with the compact version of its settings (a
  /// 2 × 2 grid on a wide screen, one after another on a phone).
  List<Widget> _embedded(Map<String, String> status, List<(String, int, String, String?, String?)> enabledPicks, Map? unsorted) {
    reportSetupDirty(context, _dirtyKey, _picksDirty);
    return [
      SetupTaskBar(tasks: [
        SetupTask(
          id: 'sorting',
          label: 'Open Egg Sorting',
          icon: Icons.open_in_new,
          onTap: () => openAppHref(context, widget.session, widget.company, '/poultry-egg-sorting', label: 'Egg Sorting'),
        ),
      ]),
      if (_eggError != null) ...[TrackerBanner.error(_eggError!), const SizedBox(height: 12)],
      _quadrant(Icons.schedule, _QTone.emerald, 'Pick times', 'When each egg pick happens in the day', status['picks']!, _compactPicks()),
      const SizedBox(height: 16),
      _quadrant(
        Icons.settings_outlined,
        _QTone.sky,
        'Egg sorting',
        'Sort eggs into sizes and price them',
        status['sorting']!,
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          EggCompactScope(
            child: SizesSettingsPanel(
              session: widget.session,
              company: widget.company,
              settings: _settings,
              classes: _classes,
              canEdit: _canEditEggs,
              onChanged: _loadEggs,
              section: PanelSection.sorting,
            ),
          ),
          if (unsorted != null) ...[
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Unsorted on hand: '),
                TextSpan(text: fmtCount(tNum(unsorted['onHand'])), style: const TextStyle(fontWeight: FontWeight.w700, color: TColors.slate700)),
                TextSpan(text: ' (${cratesText(tNum(unsorted['onHand']))})'),
              ]),
              style: const TextStyle(fontSize: 12, color: TColors.slate500),
            ),
          ],
        ]),
      ),
      const SizedBox(height: 16),
      _quadrant(
        Icons.inventory_2_outlined,
        _QTone.amber,
        'Packaging & units',
        'Count eggs in boxes, crates and pieces',
        status['packaging']!,
        EggCompactScope(
          child: EggPackagingCard(session: widget.session, company: widget.company, canEdit: _canEditEggs, onChanged: () => setState(() {})),
        ),
      ),
      const SizedBox(height: 16),
      _quadrant(
        Icons.layers_outlined,
        _QTone.violet,
        'Egg sizes',
        "Each size's name, price and stock",
        status['sizes']!,
        EggCompactScope(
          child: SizesSettingsPanel(
            session: widget.session,
            company: widget.company,
            settings: _settings,
            classes: _classes,
            canEdit: _canEditEggs,
            onChanged: _loadEggs,
            section: PanelSection.sizes,
          ),
        ),
      ),
    ];
  }

  /// The compact pick times: a box per pick (number, name, its switch, the
  /// time), then the save row.
  Widget _compactPicks() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Row(children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 8),
          Text('Loading…', style: TextStyle(fontSize: 14, color: TColors.slate500)),
        ]),
      );
    }
    Widget box((String, int, String, String?, String?) p) {
      final (key, n, label, toggle, hint) = p;
      final enabled = toggle == null || _enabled[toggle] == true;
      final time = _times[key] ?? '';
      final tile = Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: enabled ? Tone.bg(0xFFFFFFFF) : TColors.slate50,
          border: Border.all(color: TColors.slate200),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: enabled ? const Tone.bg(0xFFD1FAE5) : const Tone.bg(0xFFE2E8F0), shape: BoxShape.circle),
              child: Text('$n', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: enabled ? const Tone.fg(0xFF047857) : TColors.slate500)),
            ),
            const SizedBox(width: 6),
            Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: TColors.slate800))),
            if (toggle != null)
              SizedBox(
                height: 24,
                child: FittedBox(
                  child: Switch(
                    key: ValueKey('egg-config-qtoggle-$n'),
                    value: _enabled[toggle] == true,
                    onChanged: _saving ? null : (v) => setState(() => _enabled[toggle] = v),
                  ),
                ),
              )
            else
              const Text('ON', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: TColors.slate400)),
          ]),
          const SizedBox(height: 6),
          Opacity(
            opacity: enabled ? 1 : .6,
            child: OutlinedButton(
              key: ValueKey('egg-config-qtime-$n'),
              onPressed: _saving ? null : () => _pick(key),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(32), alignment: Alignment.centerLeft, backgroundColor: Tone.bg(0xFFFFFFFF)),
              child: Text(time.isEmpty ? '--:--' : time),
            ),
          ),
        ]),
      );
      return hint == null ? tile : Tooltip(message: hint, child: tile);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Two per row on a phone, as the web's grid-cols-2.
      for (var i = 0; i < _picks.length; i += 2) ...[
        if (i > 0) const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: box(_picks[i])),
          const SizedBox(width: 8),
          Expanded(child: i + 1 < _picks.length ? box(_picks[i + 1]) : const SizedBox()),
        ]),
      ],
      const SizedBox(height: 12),
      const Divider(height: 1, color: TColors.slate100),
      const SizedBox(height: 10),
      Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 6, children: [
        Text(_picksDirty ? 'Unsaved changes' : 'Pick times are saved.',
            style: TextStyle(fontSize: 12, fontWeight: _picksDirty ? FontWeight.w500 : FontWeight.w400, color: _picksDirty ? const Tone.fg(0xFFB45309) : TColors.slate500)),
        Row(mainAxisSize: MainAxisSize.min, children: [
          if (_picksDirty)
            TextButton(
              onPressed: _saving
                  ? null
                  : () => setState(() {
                        _times
                          ..clear()
                          ..addAll(_savedTimes);
                        _enabled
                          ..clear()
                          ..addAll(_savedEnabled);
                      }),
              child: const Text('Discard'),
            ),
          const SizedBox(width: 6),
          FilledButton.icon(
            key: const ValueKey('egg-config-qsave'),
            onPressed: _saving || !_picksDirty ? null : _save,
            icon: _saving
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_outlined, size: 16),
            label: const Text('Save'),
          ),
        ]),
      ]),
    ]);
  }

  /// One quarter of the Farm Setup egg settings page: a titled, coloured panel.
  Widget _quadrant(IconData icon, _QTone tone, String title, String subtitle, String status, Widget child) {
    final (head, line, solid, chipBg, chipFg) = switch (tone) {
      _QTone.emerald => (const Tone.bg(0xFFECFDF5), const Tone.line(0xFFD1FAE5), const Tone.bg(0xFF10B981), const Tone.bg(0xFFD1FAE5), const Tone.fg(0xFF065F46)),
      _QTone.sky => (const Tone.bg(0xFFF0F9FF), const Tone.line(0xFFE0F2FE), const Tone.bg(0xFF0EA5E9), const Tone.bg(0xFFE0F2FE), const Tone.fg(0xFF075985)),
      _QTone.amber => (const Tone.bg(0xFFFFFBEB), const Tone.line(0xFFFEF3C7), const Tone.bg(0xFFF59E0B), const Tone.bg(0xFFFEF3C7), const Tone.fg(0xFF92400E)),
      _QTone.violet => (const Tone.bg(0xFFF5F3FF), const Tone.line(0xFFEDE9FE), const Tone.bg(0xFF8B5CF6), const Tone.bg(0xFFEDE9FE), const Tone.fg(0xFF5B21B6)),
    };
    return Container(
      key: ValueKey('egg-quadrant-$title'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: Tone.bg(0xFFFFFFFF), border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [head, Tone.bg(0xFFFFFFFF)]),
            border: Border(bottom: BorderSide(color: line)),
          ),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: solid, borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 20, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: TColors.slate900)),
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
              ]),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(color: chipBg, borderRadius: BorderRadius.circular(999)),
              child: Text(status, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: chipFg)),
            ),
          ]),
        ),
        Padding(padding: const EdgeInsets.all(16), child: child),
      ]),
    );
  }

  List<Widget> _pickTimes(List<(String, int, String, String?, String?)> enabledPicks) {
    if (_loading) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 30),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 8),
            Text('Loading…', style: TextStyle(color: TColors.slate500)),
          ]),
        ),
      ];
    }
    return [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Tone.bg(0xFFFFFFFF), border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Row(children: [
            Icon(Icons.schedule, size: 16, color: _emerald600),
            SizedBox(width: 6),
            Text('Pick times', style: TextStyle(fontWeight: FontWeight.w600, color: TColors.slate900)),
          ]),
          const SizedBox(height: 2),
          const Text(
            'The time of day each egg pick represents. Used for display and reporting; production records are labelled 1st Pick through 6th Pick.',
            style: TextStyle(fontSize: 13, color: TColors.slate600),
          ),
          const SizedBox(height: 12),
          // The day at a glance.
          Container(
            key: const ValueKey('egg-config-your-day'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: TColors.slate50, border: Border.all(color: TColors.slate100), borderRadius: BorderRadius.circular(8)),
            child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              const Text('Your day:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: TColors.slate500)),
              for (final (i, p) in enabledPicks.indexed) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: Tone.bg(0xFFFFFFFF), border: Border.all(color: _emerald200), borderRadius: BorderRadius.circular(999)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 6, height: 6, decoration: const BoxDecoration(color: _emerald500, shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                    Text('${p.$3} · ${_times[p.$1]!.isEmpty ? 'default' : formatPickTime(_times[p.$1]!)}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _emerald800)),
                  ]),
                ),
                if (i < enabledPicks.length - 1) const Text('→', style: TextStyle(color: TColors.slate300)),
              ],
            ]),
          ),
          const SizedBox(height: 12),
          for (final p in _picks) ...[_pickCard(p), const SizedBox(height: 10)],
        ]),
      ),
      const SizedBox(height: 12),
      // Save bar: amber while there are unsaved changes.
      Container(
        key: const ValueKey('egg-config-save-bar'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _picksDirty ? _amber50 : Tone.bg(0xFFFFFFFF),
          border: Border.all(color: _picksDirty ? _amber200 : TColors.slate200),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_picksDirty ? 'You have unsaved changes to the pick times.' : 'Pick times are saved.',
              style: const TextStyle(fontSize: 14, color: TColors.slate600)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(backgroundColor: Tone.button(Tone.bg(0xFFFFFFFF)), foregroundColor: TColors.slate800),
                onPressed: _saving || !_picksDirty
                    ? null
                    : () => setState(() {
                          _times
                            ..clear()
                            ..addAll(_savedTimes);
                          _enabled
                            ..clear()
                            ..addAll(_savedEnabled);
                        }),
                child: const Text('Discard'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                key: const ValueKey('egg-config-save-picks'),
                onPressed: _saving || _loading || !_picksDirty ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_outlined, size: 18),
                label: Text(_saving ? 'Saving…' : 'Save pick times'),
              ),
            ),
          ]),
        ]),
      ),
    ];
  }

  Widget _pickCard((String, int, String, String?, String?) p) {
    final (key, n, label, toggle, hint) = p;
    final enabled = toggle == null || _enabled[toggle] == true;
    final time = _times[key]!;
    return Container(
      key: ValueKey('egg-config-pick-$n'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: enabled ? Tone.bg(0xFFFFFFFF) : TColors.slate50,
        border: Border.all(color: TColors.slate200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: enabled ? _emerald100 : TColors.slate200, shape: BoxShape.circle),
            child: Text('$n', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: enabled ? _emerald700 : TColors.slate500)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: TColors.slate800))),
          if (toggle != null)
            Switch(
              key: ValueKey('egg-config-enable-$n'),
              value: _enabled[toggle]!,
              onChanged: _saving ? null : (v) => setState(() => _enabled[toggle] = v),
            )
          else
            const Text('Always on', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: TColors.slate400)),
        ]),
        const SizedBox(height: 8),
        Opacity(
          opacity: enabled ? 1 : .7,
          child: OutlinedButton.icon(
            key: ValueKey('egg-config-time-$n'),
            onPressed: _saving ? null : () => _pick(key),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44), alignment: Alignment.centerLeft, backgroundColor: Tone.bg(0xFFFFFFFF)),
            icon: const Icon(Icons.schedule, size: 18),
            label: Text(time.isEmpty ? '--:--' : time),
          ),
        ),
        const SizedBox(height: 6),
        Text(time.isEmpty ? 'Not set — falls back to the default.' : formatPickTime(time), style: const TextStyle(fontSize: 12, color: TColors.slate500)),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(hint, style: const TextStyle(fontSize: 11, height: 1.35, color: TColors.slate400)),
        ],
      ]),
    );
  }
}

/// The four panels' colours (QUADRANT_TONES).
enum _QTone { emerald, sky, amber, violet }
