import 'package:flutter/material.dart';

import '../api/quick_links_api.dart';
import '../design/web_mobile.dart';
import '../models/company.dart';
import '../pages/registry.dart';
import '../pages/web_nav.dart';
import '../state/session.dart';
import 'module_sidebar.dart';

/// The web's "All pages" panel: a dark sheet with a search box and orange
/// uppercase section headers, each showing how many pages it holds and
/// collapsing to keep the list scannable.
///
/// Sections start collapsed, as on the web — with 37 report pages under one
/// heading, an expanded list would bury everything else.
Future<void> showAllPages(
  BuildContext context,
  Session session,
  Company company,
) {
  final groups = webNavGroups[PageRegistry.moduleOf(company.type)] ?? const [];

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AllPagesSheet(
      session: session,
      company: company,
      groups: groups,
    ),
  );
}

class _AllPagesSheet extends StatefulWidget {
  const _AllPagesSheet({
    required this.session,
    required this.company,
    required this.groups,
  });

  final Session session;
  final Company company;
  final List<NavGroup> groups;

  @override
  State<_AllPagesSheet> createState() => _AllPagesSheetState();
}

class _AllPagesSheetState extends State<_AllPagesSheet> {
  final _open = <String>{};
  String _query = '';

  /// The user's own shortcuts. Null until loaded, and stays null when the bar
  /// has never been customised or the call failed — in both cases the section
  /// is simply absent rather than guessed at.
  List<NavLink>? _quickLinks;

  @override
  void initState() {
    super.initState();
    _loadQuickLinks();
  }

  Future<void> _loadQuickLinks() async {
    final api = QuickLinksApi(widget.session.farmClient);
    final saved = await api.get(
      userId: widget.session.tokens.userId,
      farmId: widget.company.farmId,
    );
    if (!mounted || saved == null || !saved.customised) return;

    // Resolve each stored href against the nav so a shortcut opens the same
    // screen the menu would. An href the app has no link for is dropped: the
    // web can have pages this build does not know, and a chip that goes
    // nowhere is worse than one fewer chip.
    final byHref = <String, NavLink>{};
    for (final g in widget.groups) {
      for (final sub in g.subGroups) {
        for (final l in sub.links) {
          byHref.putIfAbsent(l.href, () => l);
        }
      }
    }
    final resolved = [
      for (final h in saved.hrefs)
        if (byHref[h] != null) byHref[h]!,
    ];
    if (resolved.isEmpty) return;
    setState(() => _quickLinks = resolved);
  }

  /// Same routing as the sidebar (openNavLink): a screen of its own, then
  /// the page's list, then the real web page.
  void _open_(NavLink link) {
    final nav = Navigator.of(context);
    nav.pop();
    openNavLink(nav, link, widget.session, widget.company);
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();

    // web_nav carries a hardcoded 'Quick Links' group, frozen at whatever the
    // bar held when the nav was generated. Once the user's real bar has
    // loaded, that snapshot is stale by definition, so it is dropped rather
    // than shown twice. With no saved bar it stays: an unpersonalised user
    // should still see the same default shortcuts the web gives them.
    final source = _quickLinks == null
        ? widget.groups
        : widget.groups.where((g) => g.title != 'Quick Links').toList();

    final groups = [
      for (final g in source)
        NavGroup(
          g.title,
          [
            for (final sub in g.subGroups)
              NavSubGroup(
                sub.title,
                q.isEmpty
                    ? sub.links
                    : sub.links
                        .where((l) => l.label.toLowerCase().contains(q))
                        .toList(),
              )
          ].where((sub) => sub.links.isNotEmpty).toList(),
        )
    ].where((g) => g.count > 0).toList();

    return Container(
      height: MediaQuery.sizeOf(context).height * .88,
      decoration: const BoxDecoration(
        color: WebMobile.sheet,
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 10, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'All pages',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70, size: 22),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                autofocus: false,
                style: const TextStyle(color: Colors.white, fontSize: 14.5),
                cursorColor: WebMobile.orange,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search pages…',
                  hintStyle: const TextStyle(color: Colors.white54, fontSize: 14.5),
                  prefixIcon:
                      const Icon(Icons.search, size: 19, color: Colors.white54),
                  filled: true,
                  fillColor: WebMobile.sheetField,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: const BorderSide(color: Color(0xFF334155)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: const BorderSide(color: Color(0xFF334155)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: const BorderSide(color: WebMobile.orange),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  // The user's own shortcuts first, as the web puts them at the
                  // top of its mobile More sheet. Hidden while searching, where
                  // a fixed bar would sit above results that do not match it.
                  if (_quickLinks != null && q.isEmpty) ...[
                    _SectionHeader(
                      title: 'Quick links',
                      count: _quickLinks!.length,
                      expanded: true,
                      onTap: () {},
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final l in _quickLinks!)
                            _QuickChip(label: l.label, onTap: () => _open_(l)),
                        ],
                      ),
                    ),
                  ],
                  for (final g in groups) ...[
                    _SectionHeader(
                      title: g.title,
                      count: g.count,
                      expanded: _open.contains(g.title) || q.isNotEmpty,
                      onTap: () => setState(() {
                        if (!_open.remove(g.title)) _open.add(g.title);
                      }),
                    ),
                    if (_open.contains(g.title) || q.isNotEmpty)
                      for (final sub in g.subGroups) ...[
                        if (sub.title.isNotEmpty)
                          Container(
                            width: double.infinity,
                            color: const Color(0xFF172033),
                            padding:
                                const EdgeInsets.fromLTRB(20, 12, 20, 6),
                            child: Text(
                              sub.title.toUpperCase(),
                              style: const TextStyle(
                                color: WebMobile.orange,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: .5,
                              ),
                            ),
                          ),
                        _TileGrid(
                          links: sub.links,
                          onOpen: _open_,
                        ),
                      ],
                  ],
                  if (groups.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(28),
                      child: Center(
                        child: Text('No pages match “$_query”.',
                            style: const TextStyle(color: Colors.white60)),
                      ),
                    ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    required this.expanded,
    required this.onTap,
  });

  final String title;
  final int count;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFF334155))),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title.toUpperCase(),
                style: const TextStyle(
                  color: WebMobile.orange,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .4,
                ),
              ),
            ),
            Text('$count',
                style: const TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(width: 8),
            Icon(expanded ? Icons.expand_less : Icons.expand_more,
                size: 20, color: Colors.white54),
          ],
        ),
      ),
    );
  }
}

/// Items inside an expanded section are two-column tiles, as the web shows
/// them — a flat list of 17 rows under Operations would be a long scroll for
/// something meant to be scanned.
class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.links, required this.onOpen});

  final List<NavLink> links;
  final void Function(NavLink) onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF172033),
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
      child: Column(
        children: [
          for (var i = 0; i < links.length; i += 2)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              // IntrinsicHeight so both tiles in a row match the taller one.
              // A bare `CrossAxisAlignment.stretch` here gives them unbounded
              // height inside the scroll view and they collapse to nothing.
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _Tile(link: links[i], onTap: onOpen)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: i + 1 < links.length
                          ? _Tile(link: links[i + 1], onTap: onOpen)
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.link, required this.onTap});

  final NavLink link;
  final void Function(NavLink) onTap;

  static IconData _iconFor(String label) {
    final l = label.toLowerCase();
    if (l.contains('record') || l.contains('report')) return Icons.description_outlined;
    if (l.contains('egg')) return Icons.egg_outlined;
    if (l.contains('feed')) return Icons.grass_outlined;
    if (l.contains('batch') || l.contains('production')) return Icons.widgets_outlined;
    if (l.contains('inventory') || l.contains('stock')) return Icons.widgets_outlined;
    if (l.contains('suppl') || l.contains('material')) return Icons.inventory_2_outlined;
    if (l.contains('health')) return Icons.warning_amber_outlined;
    if (l.contains('loss') || l.contains('damage')) return Icons.warning_amber_outlined;
    if (l.contains('deliver') || l.contains('driver')) return Icons.local_shipping_outlined;
    if (l.contains('sale')) return Icons.shopping_cart_outlined;
    if (l.contains('expense')) return Icons.receipt_long_outlined;
    if (l.contains('cash') || l.contains('money')) return Icons.account_balance_wallet_outlined;
    if (l.contains('loan')) return Icons.request_quote_outlined;
    if (l.contains('customer') || l.contains('staff') || l.contains('people')) {
      return Icons.people_outline;
    }
    if (l.contains('setup') || l.contains('setting')) return Icons.settings_outlined;
    return Icons.insert_chart_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF223049),
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () => onTap(link),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
          child: Row(
            children: [
              Icon(_iconFor(link.label), size: 17, color: Colors.white70),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  link.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 13, height: 1.25),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One shortcut in the Quick Links bar, styled like the web's: a rounded
/// slate tile on the dark sheet, two to a row at phone width.
class _QuickChip extends StatelessWidget {
  const _QuickChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width - 24 - 8) / 2;
    return SizedBox(
      width: width,
      child: Material(
        color: WebMobile.sheetField,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            child: Row(
              children: [
                const Icon(Icons.bolt_outlined, size: 17, color: WebMobile.orange),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
