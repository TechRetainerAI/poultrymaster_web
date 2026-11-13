import 'package:flutter/material.dart';

import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../list_screen.dart';
import '../module_registry.dart';
import '../registry.dart';
import 'setup/company_settings_form.dart';
import 'setup/poultry_setup_tabs.dart';
import 'setup/setup_embed.dart';

import 'package:poultrycore_mobile/design/tone.dart';

/// Farm Setup (`/poultry-setup`), as the web's `app/poultry-setup/page.tsx`:
/// the one place a poultry farm sets itself up.
///
///   Farm Setup
///   ( ) Production Setup  ( ) Business Setup    the section
///   [tab] [tab] [tab] …                         its tabs
///   One-line description
///   the tab's own setup screen                  (the same screen as its page)
///   [task] [task] [⋯]                 [reload]  task bar, along the bottom
///
/// Each tab shows the page's own screen with its title and buttons taken off:
/// the buttons go on the task bar ([SetupTaskBar]). Changing tab or section
/// asks first when the open tab holds unsaved edits.
class FarmSetupScreen extends StatefulWidget {
  const FarmSetupScreen({super.key, required this.session, required this.company, this.href = setupPath});
  final Session session;
  final Company company;

  /// The link it was opened from: `?section=` / `?tab=` / an old `?step=`.
  final String href;

  @override
  State<FarmSetupScreen> createState() => _FarmSetupScreenState();
}

/// Where each tab's screen lives: its page's route, and the list it shows
/// when the app has no screen of its own for that route.
const Map<String, (String href, String? specKey)> setupTabRoutes = {
  'houses': ('/houses', 'house'),
  'flock-purchases': ('/flock-batch', null),
  'flock-groups': ('/flocks', 'flocks'),
  'products': ('/poultry-products', 'poultry-products'),
  'feed-formulas': ('/poultry-feed-formulas', 'poultry-feed-formulas'),
  'egg-settings': ('/business-office/egg-pick-settings', null),
  'inventory': ('/poultry-supply-purchases', null),
  'customers': ('/customers', 'customer'),
  'suppliers': ('/suppliers', 'supplier'),
  'financial-settings': ('/poultry-financial-settings', null),
  'cash-accounts': ('/poultry-cash-accounts', null),
  'drivers': ('/poultry-drivers', 'poultry-drivers'),
  'vehicles': ('/poultry-vehicles', 'poultry-vehicles'),
  'routes': ('/poultry-routes', 'poultry-routes'),
  'staff': ('/poultry-staff', 'poultry-staff'),
};

const _leavePrompt = 'You have unsaved changes on this tab. Leave without saving them?';
const _reloadPrompt = 'You have unsaved changes on this tab. Reload and lose them?';

class _FarmSetupScreenState extends State<FarmSetupScreen> {
  final _embed = SetupEmbedController();
  late SetupLocation _loc = resolveSetupHref(widget.href, allowed: _allowed);
  int _reloadKey = 0;
  final _tabKeys = <String, GlobalKey>{};

  /// Which tabs this user may open. The app gates Setup the way its menus
  /// do: the whole of Farm Setup is for anyone who is not an ordinary
  /// employee (the web's per-tab flags are all true for them).
  bool _allowed(String tab) => true;

  @override
  void initState() {
    super.initState();
    _embed.addListener(_onTasks);
    final loc = _loc;
    if (loc is SetupRedirect) {
      // An old link to a page outside Farm Setup (Users & Permissions).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final screen = pageScreens[loc.href];
        final spec = PageRegistry.of('admin-company-employees');
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => screen != null
              ? screen(widget.session, widget.company)
              : spec != null
                  ? ListScreen(spec: spec, session: widget.session, company: widget.company)
                  : const SizedBox.shrink(),
        ));
      });
    }
  }

  void _onTasks() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _embed.removeListener(_onTasks);
    _embed.dispose();
    super.dispose();
  }

  Future<bool> _confirm(String message) async {
    if (!_embed.anyDirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
        ],
      ),
    );
    return ok == true;
  }

  /// Radios and tabs: ask first when the open view holds unsaved edits. A
  /// cancelled confirm changes nothing.
  Future<void> _go(SetupSection section, [String? tab]) async {
    final target = tab ?? setupSections[section]!.tabs.where((t) => _allowed(t.key)).firstOrNull?.key;
    if (target == null) return;
    final now = _loc;
    if (now is SetupAt && now.tab == target) return;
    if (!await _confirm(_leavePrompt) || !mounted) return;
    _embed.clear();
    setState(() => _loc = SetupAt(section, target));
    // On a phone the tab row scrolls sideways: keep the open tab in view.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _tabKeys[target]?.currentContext;
      if (ctx != null) Scrollable.ensureVisible(ctx, alignment: .5, duration: const Duration(milliseconds: 200));
    });
  }

  /// Reload remounts the open view, so it fetches its data again.
  Future<void> _reload() async {
    if (!await _confirm(_reloadPrompt) || !mounted) return;
    _embed.clear();
    setState(() => _reloadKey++);
  }

  Widget _view(String tab) {
    if (tab == 'company-settings') {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        child: CompanySettingsForm(session: widget.session, company: widget.company),
      );
    }
    final route = setupTabRoutes[tab];
    if (route == null) return const SizedBox.shrink();
    final screen = pageScreens[route.$1];
    if (screen != null) return screen(widget.session, widget.company);
    final spec = route.$2 == null ? null : PageRegistry.of(route.$2!);
    if (spec == null) return const SizedBox.shrink();
    return ListScreen(spec: spec, session: widget.session, company: widget.company);
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: setupPath);
    final loc = _loc;
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Farm Setup')),
      body: switch (loc) {
        SetupNone() => const Padding(
            padding: EdgeInsets.all(24),
            child: Text('You do not have access to any part of Farm Setup. Ask the account owner or an admin.',
                textAlign: TextAlign.center, style: TextStyle(color: _slate500)),
          ),
        SetupRedirect() => const Center(child: CircularProgressIndicator()),
        SetupAt(:final section, :final tab) => _body(section, tab),
      },
    );
  }

  Widget _body(SetupSection section, String tab) {
    final def = setupSections[section]!;
    final tabs = def.tabs.where((t) => _allowed(t.key)).toList();
    final current = def.tabs.firstWhere((t) => t.key == tab);
    final visibleSections = [
      for (final s in SetupSection.values)
        if (setupSections[s]!.tabs.any((t) => _allowed(t.key))) s,
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Section radios, under the title.
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Wrap(spacing: 16, runSpacing: 0, children: [
          for (final s in visibleSections) _radio(s, s == section),
        ]),
      ),
      Container(
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
        decoration: const BoxDecoration(
          color: Tone.bg(0xFFFFFFFF),
          border: Border(
            top: BorderSide(color: _slate200),
            left: BorderSide(color: _slate200),
            right: BorderSide(color: _slate200),
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Underlined text tabs; they scroll sideways on a phone.
          Container(
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _slate200))),
            child: SingleChildScrollView(
              key: const ValueKey('setup-tab-row'),
              scrollDirection: Axis.horizontal,
              child: Row(children: [for (final t in tabs) _tab(section, t, t.key == tab)]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
            child: Text(current.description, key: const ValueKey('setup-tab-description'), style: const TextStyle(fontSize: 13.5, color: _slate600)),
          ),
        ]),
      ),
      Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: const BoxDecoration(
            color: Tone.bg(0xFFFFFFFF),
            border: Border(left: BorderSide(color: _slate200), right: BorderSide(color: _slate200), bottom: BorderSide(color: _slate200)),
          ),
          child: SetupEmbed(
            controller: _embed,
            // A new tab, company or Reload remounts the view, so it loads fresh
            // data and no late reply from before can land in it.
            child: KeyedSubtree(key: ValueKey('${widget.company.farmId}:$tab:$_reloadKey'), child: _view(tab)),
          ),
        ),
      ),
      _taskBar(),
    ]);
  }

  Widget _radio(SetupSection s, bool on) => InkWell(
        key: ValueKey('setup-section-${s.name}'),
        onTap: on ? null : () => _go(s),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            // The web's native radio, drawn as an icon (the whole row is the tap target).
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(
                on ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                size: 18,
                color: on ? const Tone.fg(0xFFD97706) : _slate500,
              ),
            ),
            Text(setupSections[s]!.label,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: on ? const Tone.fg(0xFFB45309) : _slate800)),
          ]),
        ),
      );

  Widget _tab(SetupSection section, SetupTab t, bool on) => InkWell(
        key: _tabKeys.putIfAbsent(t.key, () => GlobalKey()),
        onTap: on ? null : () => _go(section, t.key),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: on ? const Tone.line(0xFFD97706) : const Tone.line(0x00000000), width: 2)),
          ),
          child: Text(
            t.label,
            style: TextStyle(fontSize: 14, fontWeight: on ? FontWeight.w500 : FontWeight.w400, color: on ? const Tone.fg(0xFFB45309) : _slate600),
          ),
        ),
      );

  /// The open tab's buttons, fixed along the bottom; what does not fit folds
  /// into "More". Then a divider and Reload.
  Widget _taskBar() => Container(
        key: const ValueKey('setup-task-bar'),
        padding: EdgeInsets.fromLTRB(16, 8, 8, 8 + MediaQuery.paddingOf(context).bottom),
        decoration: const BoxDecoration(
          color: Tone.bg(0xFF1E293B),
          border: Border(top: BorderSide(color: Tone.line(0xFF0F172A))),
          boxShadow: [BoxShadow(color: Tone.bg(0x1F0F172A), blurRadius: 12, offset: Offset(0, -4))],
        ),
        child: Row(children: [
          Expanded(child: TaskBarRow(tasks: _embed.tasks, dark: true, align: MainAxisAlignment.center)),
          Container(width: 1, height: 24, color: const Tone.line(0x33FFFFFF)),
          IconButton(
            key: const ValueKey('setup-reload'),
            tooltip: 'Reload this tab',
            onPressed: _reload,
            icon: const Icon(Icons.refresh, size: 18, color: Tone.fg(0xFFCBD5E1)),
          ),
        ]),
      );
}

const _slate200 = Tone.line(0xFFE2E8F0);
const _slate500 = Tone.fg(0xFF64748B);
const _slate600 = Tone.fg(0xFF475569);
const _slate800 = Tone.fg(0xFF1E293B);
