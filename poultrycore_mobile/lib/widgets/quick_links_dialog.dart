// Customisable Quick Links (migration 318): the catalogue and resolver from
// the web's lib/nav/quick-links.ts, and the picker from
// components/dashboard/quick-links-dialog.tsx.

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/quick_links_api.dart';
import '../pages/poultry/trackers/tracker_widgets.dart' show trackerToast, TColors;
import '../pages/web_nav.dart';

/// The menus a user may pin from, in rail order. System and Tools are left
/// out, as on the web, and so are Reports.
const quickLinkMenus = ['Operations', 'Sales, Expenses & Money', 'Trackers', 'Setup'];

/// 318 enforces this too.
const maxQuickLinks = 20;

/// quickLinkCatalogue: the default Quick Links first (group "Shortcuts"),
/// then every row of the pinnable menus. The first occurrence of an href wins,
/// so a default keeps its shorter Quick Links wording.
List<({NavLink link, String group})> quickLinkCatalogue(List<NavGroup> groups) {
  final out = <({NavLink link, String group})>[];
  final seen = <String>{};
  void push(NavLink l, String group) {
    if (l.href.isEmpty || !seen.add(l.href)) return;
    out.add((link: l, group: group));
  }

  for (final g in groups.where((g) => g.title == 'Quick Links')) {
    for (final s in g.subGroups) {
      for (final l in s.links) {
        push(l, 'Shortcuts');
      }
    }
  }
  for (final menu in quickLinkMenus) {
    for (final g in groups.where((g) => g.title == menu)) {
      for (final s in g.subGroups) {
        for (final l in s.links) {
          push(l, '$menu · ${s.title}');
        }
      }
    }
  }
  return out;
}

/// The default Quick Links: the generated group.
List<NavLink> defaultQuickLinks(List<NavGroup> groups) => [
      for (final g in groups.where((g) => g.title == 'Quick Links'))
        for (final s in g.subGroups) ...s.links,
    ];

/// resolveQuickLinks: null hrefs = never customised = the defaults. An empty
/// list means the user cleared the bar and stays empty. Unknown hrefs drop.
List<NavLink> resolveQuickLinks(List<NavGroup> groups, List<String>? hrefs) {
  if (hrefs == null) return defaultQuickLinks(groups);
  final byHref = {for (final c in quickLinkCatalogue(groups)) c.link.href: c.link};
  return [for (final h in hrefs) if (byHref[h] != null) byHref[h]!];
}

/// The outcome of the picker: the new stored hrefs (null after a reset).
typedef QuickLinksResult = ({List<String>? hrefs});

/// Opens "Your Quick Links". Returns null when cancelled.
Future<QuickLinksResult?> showQuickLinksDialog(
  BuildContext context, {
  required ApiClient farmClient,
  required String userId,
  required String farmId,
  required List<NavGroup> groups,
  required List<String>? stored,
  required IconData Function(String href) iconFor,
}) =>
    showDialog<QuickLinksResult>(
      context: context,
      builder: (_) => _QuickLinksDialog(
        api: QuickLinksApi(farmClient),
        userId: userId,
        farmId: farmId,
        groups: groups,
        stored: stored,
        iconFor: iconFor,
      ),
    );

class _QuickLinksDialog extends StatefulWidget {
  const _QuickLinksDialog({
    required this.api,
    required this.userId,
    required this.farmId,
    required this.groups,
    required this.stored,
    required this.iconFor,
  });
  final QuickLinksApi api;
  final String userId, farmId;
  final List<NavGroup> groups;
  final List<String>? stored;
  final IconData Function(String href) iconFor;
  @override
  State<_QuickLinksDialog> createState() => _QuickLinksDialogState();
}

class _QuickLinksDialogState extends State<_QuickLinksDialog> {
  late final _catalogue = quickLinkCatalogue(widget.groups);
  late final Set<String> _picked = {...(widget.stored ?? [for (final l in defaultQuickLinks(widget.groups)) l.href])};
  String _search = '';
  bool _busy = false;

  void _toggle(String href) {
    setState(() {
      if (_picked.contains(href)) {
        _picked.remove(href);
      } else if (_picked.length >= maxQuickLinks) {
        trackerToast(context, 'That is $maxQuickLinks links',
            description: 'Remove one before adding another — a bar this long is not a shortcut.', error: true);
      } else {
        _picked.add(href);
      }
    });
  }

  /// Order follows the catalogue, not the order of ticking.
  List<String> get _inOrder => [for (final c in _catalogue) if (_picked.contains(c.link.href)) c.link.href];

  Future<void> _run(Future<List<String>?> Function() fn, String ok) async {
    setState(() => _busy = true);
    try {
      final hrefs = await fn();
      if (!mounted) return;
      trackerToast(context, ok);
      Navigator.pop<QuickLinksResult>(context, (hrefs: hrefs));
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'That did not save', description: e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.trim().toLowerCase();
    final groups = <String, List<NavLink>>{};
    for (final c in _catalogue) {
      if (q.isNotEmpty && !c.link.label.toLowerCase().contains(q) && !c.link.href.toLowerCase().contains(q)) continue;
      (groups[c.group] ??= []).add(c.link);
    }
    return AlertDialog(
      title: const Row(children: [
        Icon(Icons.star_border, color: Color(0xFFF59E0B)),
        SizedBox(width: 8),
        Flexible(child: Text('Your Quick Links')),
      ]),
      content: SizedBox(
        width: 560,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text(
            "Pick the pages you open most. This is yours alone, and it applies to this company — switch company and you get that one's bar.",
            style: TextStyle(fontSize: 14, color: TColors.slate500),
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search, size: 18), hintText: 'Find a page…', isDense: true),
            onChanged: (v) => setState(() => _search = v),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: Container(
              decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
              child: groups.isEmpty
                  ? Padding(padding: const EdgeInsets.all(16), child: Text('No page matches “$_search”.', style: const TextStyle(fontSize: 14, color: TColors.slate500)))
                  : ListView(shrinkWrap: true, children: [
                      for (final e in groups.entries) ...[
                        Container(
                          color: TColors.slate50,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: Text(e.key.toUpperCase(),
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .5, color: TColors.slate500)),
                        ),
                        for (final l in e.value)
                          InkWell(
                            key: ValueKey('ql-${l.href}'),
                            onTap: () => _toggle(l.href),
                            child: Container(
                              color: _picked.contains(l.href) ? const Color(0x99FFFBEB) : null,
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              child: Row(children: [
                                Checkbox(value: _picked.contains(l.href), onChanged: (_) => _toggle(l.href)),
                                Icon(widget.iconFor(l.href), size: 16, color: TColors.slate400),
                                const SizedBox(width: 10),
                                Expanded(child: Text(l.label, style: const TextStyle(fontSize: 14, color: TColors.slate900))),
                              ]),
                            ),
                          ),
                      ],
                    ]),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(alignment: WrapAlignment.spaceBetween, spacing: 8, runSpacing: 4, children: [
            Text('${_picked.length} of $maxQuickLinks chosen', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            if (_picked.isEmpty) const Text('An empty bar is allowed — the menu stays hidden.', style: TextStyle(fontSize: 12, color: TColors.slate500)),
          ]),
        ]),
      ),
      actionsOverflowDirection: VerticalDirection.up,
      actions: [
        TextButton.icon(
          onPressed: _busy
              ? null
              : () => _run(() async {
                    await widget.api.reset(userId: widget.userId, farmId: widget.farmId);
                    return null;
                  }, 'Back to the default Quick Links'),
          icon: const Icon(Icons.restart_alt, size: 16),
          label: const Text('Reset to defaults'),
        ),
        OutlinedButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _busy
              ? null
              : () => _run(() async {
                    final saved = await widget.api.save(userId: widget.userId, farmId: widget.farmId, hrefs: _inOrder);
                    return saved.hrefs;
                  }, 'Quick Links saved'),
          child: Text(_busy ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}
