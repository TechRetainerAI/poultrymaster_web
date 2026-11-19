// System → Help Center, as rebuilt on the web (app/help/page.tsx, 27 Oct):
// a question-style search (with suggestions, "Go to page" chips and highlighted
// answers), the Feature Guide, three tabs -- Questions, Troubleshooting and an
// A-Z Glossary -- and the Contact support card.
//
// The content is lib/help/poultry-help-content.ts, generated into
// help/poultry_help_content.dart word for word. Answer links and "Go to page"
// only offer pages this user may open (the sidebar's own list).
//
// Left out on purpose: the web's "Shortcuts" card. It lists Ctrl+K, "/" and
// arrow keys for the header search, which the app does not have.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/env.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../registry.dart';
import '../poultry/egg_pick_settings_screen.dart';
import '../poultry/reports/report_routes.dart' show openAppHref;
import '../poultry/trackers/tracker_widgets.dart';
import '../poultry/poultry_features.dart';
import '../web_nav.dart';
import 'help/contact_support.dart';
import 'help/help_search.dart';
import 'help/help_types.dart';
import 'help/poultry_help_content.dart';
import 'setup_admin_routes.dart';

import 'package:poultrycore_mobile/design/tone.dart';
/// Questions people actually type, offered before they type anything.
const helpSuggestions = ['who owes me', "cash doesn't match profit", 'reverse a sale', 'eggs per crate', 'close the day', "can't see a page"];

const _kindLabel = {HelpKind.faq: 'Question', HelpKind.fix: 'Troubleshooting', HelpKind.term: 'Glossary'};

const _indigo100 = Tone.bg(0xFFE0E7FF);
const _indigo200 = Tone.line(0xFFC7D2FE);
const _indigo700 = Tone.fg(0xFF4338CA);
const _amber100 = Tone.bg(0xFFFEF3C7);

class HelpCenterScreen extends StatefulWidget {
  const HelpCenterScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;
  @override
  State<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _HelpCenterScreenState extends State<HelpCenterScreen> {
  final _search = TextEditingController();
  final _supportKey = GlobalKey<ContactSupportState>();
  final _letterKeys = <String, GlobalKey>{};
  final _index = prepareHelpIndex(helpEntries);
  String _q = '';
  HelpKind _tab = HelpKind.faq;
  String _category = 'All';

  // Questions open by default (`_closed` holds the folded ones); fixes are a
  // list of symptoms to scan, so `_opened` holds the expanded ones.
  final _closed = <String>{};
  final _opened = <String>{};

  late final List<({String title, String href, String group})> _pages = _openablePages();
  // Paths only: a menu row can carry a query (/poultry-setup?section=business).
  late final Set<String> _openable = {for (final p in _pages) p.href.split('?').first};

  List<({String title, String href, String group})> _openablePages() {
    final out = <String, ({String title, String href, String group})>{};
    final groups = gatePoultryFeatureLinks(gateSetupLinks(webNavGroups[PageRegistry.moduleOf(widget.company.type)] ?? const [], widget.company), widget.company);
    // Quick Links last, as on the web; the first occurrence of an href wins.
    for (final g in [...groups.where((g) => g.title != 'Quick Links'), ...groups.where((g) => g.title == 'Quick Links')]) {
      for (final s in g.subGroups) {
        for (final l in s.links) {
          if (l.href.startsWith('#')) continue;
          out.putIfAbsent(l.href, () => (title: l.label, href: l.href, group: s.title));
        }
      }
    }
    return out.values.toList();
  }

  bool _canOpen(String href) => _openable.contains(href.split('?').first);

  void _open(String href, String label) {
    final uri = Uri.parse(href);
    // Egg Configuration opens on the tab the answer names (?tab=sorting).
    if (uri.path == '/business-office/egg-pick-settings' && uri.queryParameters['tab'] != null) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => EggPickSettingsScreen(session: widget.session, company: widget.company, initialTab: uri.queryParameters['tab']!),
      ));
      return;
    }
    openAppHref(context, widget.session, widget.company, uri.path, label: label);
  }

  bool _isOpen(HelpEntry e) => e.kind == HelpKind.fix ? _opened.contains(e.id) : !_closed.contains(e.id);

  void _toggle(HelpEntry e) => setState(() {
        final set = e.kind == HelpKind.fix ? _opened : _closed;
        if (!set.remove(e.id)) set.add(e.id);
      });

  void _setQuery(String v) {
    _search.value = TextEditingValue(text: v, selection: TextSelection.collapsed(offset: v.length));
    setState(() => _q = v);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/help');
    final searching = _q.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Help Center')),
      body: ListView(key: const ValueKey('help-list'), padding: const EdgeInsets.fromLTRB(14, 16, 14, 28), children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: _indigo100, borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.help_outline, size: 32, color: Tone.fg(0xFF4F46E5)),
          ),
        ),
        const SizedBox(height: 12),
        const Text('Help Center', textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Tone.fg(0xFF0F172A))),
        const SizedBox(height: 6),
        const Text('Ask in your own words. Answers, fixes for common problems, what the terms mean, and a quick way to reach us.',
            textAlign: TextAlign.center, style: TextStyle(color: Tone.fg(0xFF475569))),
        const SizedBox(height: 16),
        AppInput(
          key: const ValueKey('help-search'),
          controller: _search,
          hintText: 'e.g. how do I reverse a sale?',
          prefixIcon: const Icon(Icons.search, color: Tone.fg(0xFF7F8EA3)),
          suffixIcon: searching
              ? IconButton(
                  key: const ValueKey('help-search-clear'),
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close, size: 18, color: Tone.fg(0xFF7F8EA3)),
                  onPressed: () => _setQuery(''),
                )
              : null,
          onChanged: (v) => setState(() => _q = v),
        ),
        if (!searching) ...[
          const SizedBox(height: 8),
          Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
            for (final s in helpSuggestions)
              InkWell(
                key: ValueKey('help-suggest-$s'),
                borderRadius: BorderRadius.circular(999),
                onTap: () => _setQuery(s),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(color: Tone.bg(0xFFFFFFFF), border: Border.all(color: Tone.line(0xFFE2E8F0)), borderRadius: BorderRadius.circular(999)),
                  child: Text(s, style: const TextStyle(fontSize: 12, color: Tone.fg(0xFF475569))),
                ),
              ),
          ]),
        ],
        const SizedBox(height: 22),
        if (searching) ..._results() else ..._browse(),
        const SizedBox(height: 22),
        ContactSupport(key: _supportKey),
      ]),
    );
  }

  // ------------------------------------------------------------ results

  List<Widget> _results() {
    final q = _q.trim();
    final hits = searchHelp(_q, _index);
    final pageHits = rankPages(_q, _pages);
    return [
      if (pageHits.isNotEmpty) ...[
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Text('GO TO PAGE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .6, color: Tone.fg(0xFF7F8EA3))),
          for (final p in pageHits)
            InkWell(
              key: ValueKey('help-goto-${p.href}'),
              borderRadius: BorderRadius.circular(999),
              onTap: () => _open(p.href, p.title),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(color: Tone.bg(0xFFFFFFFF), border: Border.all(color: _indigo200), borderRadius: BorderRadius.circular(999)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(child: Text(p.title, style: const TextStyle(fontSize: 13.5, color: _indigo700))),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward, size: 13, color: _indigo700),
                ]),
              ),
            ),
        ]),
        const SizedBox(height: 14),
      ],
      Text('${hits.length} ${hits.length == 1 ? 'answer' : 'answers'} for “$q”',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate500)),
      const SizedBox(height: 10),
      if (hits.isEmpty)
        TCard(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(children: [
              Text('No answer matches “$q” yet.', textAlign: TextAlign.center, style: const TextStyle(color: TColors.slate500)),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const ValueKey('help-ask-support'),
                style: FilledButton.styleFrom(backgroundColor: Tone.button(Tone.bg(0xFF4F46E5)), foregroundColor: Colors.white),
                onPressed: () => _supportKey.currentState?.ask(q),
                icon: const Icon(Icons.chat_bubble_outline, size: 16),
                label: const Text('Ask support this question'),
              ),
            ]),
          ),
        )
      else ...[
        for (final h in hits)
          _EntryCard(
            entry: h.entry,
            open: _isOpen(h.entry),
            onToggle: () => _toggle(h.entry),
            matched: h.matched,
            showKind: true,
            links: [for (final l in h.entry.links) if (_canOpen(l.href)) l],
            onLink: (l) => _open(l.href, l.label),
          ),
        const SizedBox(height: 6),
        Center(
          child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Text('Not what you needed? ', style: TextStyle(fontSize: 14, color: TColors.slate500)),
            InkWell(
              key: const ValueKey('help-ask-support'),
              onTap: () => _supportKey.currentState?.ask(q),
              child: const Text('Ask support', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Tone.fg(0xFF4F46E5))),
            ),
          ]),
        ),
      ],
    ];
  }

  // ------------------------------------------------------------- browse

  List<Widget> _browse() {
    final faqs = [for (final e in helpEntries) if (e.kind == HelpKind.faq) e];
    final fixes = [for (final e in helpEntries) if (e.kind == HelpKind.fix) e];
    final terms = [for (final e in helpEntries) if (e.kind == HelpKind.term) e]..sort((a, b) => a.title.compareTo(b.title));
    final guides = [for (final g in featureGuides) if (_canOpen(g.path)) g];
    return [
      const Row(children: [
        Icon(Icons.menu_book_outlined, size: 20, color: Tone.fg(0xFF4F46E5)),
        SizedBox(width: 8),
        Text('Feature Guide', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Tone.fg(0xFF0F172A))),
      ]),
      const SizedBox(height: 12),
      // Two per row on a phone, as the web's grid-cols-2; the description is
      // hidden below its sm: breakpoint, so the tiles carry the title only.
      for (var i = 0; i < guides.length; i += 2)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: _guideTile(guides[i])),
              const SizedBox(width: 10),
              Expanded(child: i + 1 < guides.length ? _guideTile(guides[i + 1]) : const SizedBox()),
            ]),
          ),
        ),
      const SizedBox(height: 16),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: Tone.bg(0xFFF1F5F9), borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            _tabButton(HelpKind.faq, Icons.help_outline, 'Questions', faqs.length),
            _tabButton(HelpKind.fix, Icons.build_outlined, 'Troubleshooting', fixes.length),
            _tabButton(HelpKind.term, Icons.sort_by_alpha, 'Glossary', terms.length),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      ...switch (_tab) {
        HelpKind.faq => _questions(faqs),
        HelpKind.fix => _troubleshooting(fixes),
        HelpKind.term => _glossary(terms),
      },
    ];
  }

  Widget _guideTile(FeatureGuide g) {
    final tone = toneOfFamily(g.tone);
    return InkWell(
      key: ValueKey('help-guide-${g.path}'),
      borderRadius: BorderRadius.circular(12),
      onTap: () => _open(g.path, g.title),
      child: TCard(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: tone.tintBg, borderRadius: BorderRadius.circular(12)),
            child: Icon(g.icon, color: tone.tintFg),
          ),
          const SizedBox(height: 8),
          Text(g.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Tone.fg(0xFF0F172A))),
        ]),
      ),
    );
  }

  Widget _tabButton(HelpKind kind, IconData icon, String label, int count) {
    final on = _tab == kind;
    return InkWell(
      key: ValueKey('help-tab-${kind.name}'),
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => _tab = kind),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: on ? Tone.bg(0xFFFFFFFF) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: on ? const [BoxShadow(color: Color(0x14000000), blurRadius: 2, offset: Offset(0, 1))] : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: on ? Tone.fg(0xFF0F172A) : Tone.fg(0xFF475569)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: on ? Tone.fg(0xFF0F172A) : Tone.fg(0xFF475569))),
          const SizedBox(width: 5),
          Text('$count', style: const TextStyle(fontSize: 12, color: Tone.fg(0xFF7F8EA3))),
        ]),
      ),
    );
  }

  List<Widget> _questions(List<HelpEntry> faqs) {
    final categories = ['All', ...{for (final f in faqs) f.category}];
    final shown = _category == 'All' ? faqs : [for (final f in faqs) if (f.category == _category) f];
    final allOpen = shown.every((f) => !_closed.contains(f.id));
    return [
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final cat in categories) _chip(cat, cat == 'All' ? faqs.length : faqs.where((f) => f.category == cat).length),
      ]),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerRight,
        child: InkWell(
          key: const ValueKey('help-collapse-all'),
          onTap: () => setState(() {
            if (allOpen) {
              _closed.addAll(shown.map((f) => f.id));
            } else {
              _closed.clear();
            }
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(allOpen ? 'Collapse all' : 'Expand all', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Tone.fg(0xFF4F46E5))),
          ),
        ),
      ),
      const SizedBox(height: 8),
      for (final e in shown) _card(e),
    ];
  }

  List<Widget> _troubleshooting(List<HelpEntry> fixes) => [
        const Text('Something looks wrong? Find the symptom, open it, and work through the checks in order.',
            style: TextStyle(fontSize: 14, color: TColors.slate500)),
        const SizedBox(height: 12),
        for (final e in fixes) _card(e),
      ];

  List<Widget> _glossary(List<HelpEntry> terms) {
    final letters = <String>[];
    for (final t in terms) {
      final l = t.title[0].toUpperCase();
      if (!letters.contains(l)) letters.add(l);
    }
    return [
      Wrap(spacing: 4, runSpacing: 4, children: [
        for (final l in letters)
          InkWell(
            key: ValueKey('help-letter-$l'),
            borderRadius: BorderRadius.circular(6),
            onTap: () {
              final ctx = _letterKeys[l]?.currentContext;
              if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300));
            },
            child: Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Tone.bg(0xFFFFFFFF), border: Border.all(color: Tone.line(0xFFE2E8F0)), borderRadius: BorderRadius.circular(6)),
              child: Text(l, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Tone.fg(0xFF475569))),
            ),
          ),
      ]),
      const SizedBox(height: 12),
      Container(
        decoration: BoxDecoration(color: Tone.bg(0xFFFFFFFF), border: Border.all(color: Tone.line(0xFFE2E8F0)), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (i, t) in terms.indexed) ...[
            if (i > 0) const Divider(height: 1, color: Tone.line(0xFFF1F5F9)),
            _term(t, i == 0 || terms[i - 1].title[0].toUpperCase() != t.title[0].toUpperCase()),
          ],
        ]),
      ),
    ];
  }

  Widget _term(HelpEntry t, bool firstOfLetter) {
    final letter = t.title[0].toUpperCase();
    final links = [for (final l in t.links) if (_canOpen(l.href)) l];
    return Padding(
      key: firstOfLetter ? _letterKeys.putIfAbsent(letter, GlobalKey.new) : ValueKey('help-term-${t.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 12, crossAxisAlignment: WrapCrossAlignment.end, children: [
          Text(t.title, style: const TextStyle(fontWeight: FontWeight.w600, color: Tone.fg(0xFF0F172A))),
          Text(t.category, style: const TextStyle(fontSize: 11, color: Tone.fg(0xFF7F8EA3))),
        ]),
        const SizedBox(height: 4),
        Text(t.body, style: const TextStyle(fontSize: 14, height: 1.5, color: Tone.fg(0xFF475569))),
        if (links.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 12, runSpacing: 4, children: [
            for (final l in links)
              InkWell(
                onTap: () => _open(l.href, l.label),
                child: Text('${l.label} →', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Tone.fg(0xFF4F46E5))),
              ),
          ]),
        ],
      ]),
    );
  }

  Widget _card(HelpEntry e) => _EntryCard(
        entry: e,
        open: _isOpen(e),
        onToggle: () => _toggle(e),
        links: [for (final l in e.links) if (_canOpen(l.href)) l],
        onLink: (l) => _open(l.href, l.label),
      );

  Widget _chip(String cat, int n) {
    final tone = cat == 'All' ? fallbackHelpTone : toneFor(cat);
    final on = _category == cat;
    return InkWell(
      key: ValueKey('faq-cat-$cat'),
      borderRadius: BorderRadius.circular(999),
      onTap: () => setState(() => _category = cat),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: on ? tone.chipOn : Tone.bg(0xFFFFFFFF),
          border: Border.all(color: on ? tone.chipOn : Tone.line(0xFFE2E8F0)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: cat, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: on ? Colors.white : Tone.fg(0xFF1E293B))),
          TextSpan(text: '  $n', style: TextStyle(fontSize: 10, color: on ? Colors.white70 : Tone.fg(0xFF7F8EA3))),
        ])),
      ),
    );
  }
}

/// help-entry-card.tsx: the coloured rail, the badges ABOVE the question (on a
/// phone, inline badges left the question in a two-word column), the body as
/// paragraphs / numbered steps / bullets, the page links and "Copy link".
class _EntryCard extends StatefulWidget {
  const _EntryCard({
    required this.entry,
    required this.open,
    required this.onToggle,
    required this.links,
    required this.onLink,
    this.matched = const [],
    this.showKind = false,
  });
  final HelpEntry entry;
  final bool open;
  final VoidCallback onToggle;
  final List<HelpLink> links;
  final ValueChanged<HelpLink> onLink;
  final List<String> matched;
  final bool showKind;
  @override
  State<_EntryCard> createState() => _EntryCardState();
}

class _EntryCardState extends State<_EntryCard> {
  bool _copied = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _copyLink() async {
    // The web's link, so it opens on this answer for whoever receives it.
    await Clipboard.setData(ClipboardData(text: '${Env.webBase}/help#${widget.entry.id}'));
    if (!mounted) return;
    setState(() => _copied = true);
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final tone = toneFor(e.category);
    return Container(
      key: ValueKey('help-entry-${e.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Tone.bg(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Tone.line(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(border: Border(left: BorderSide(color: tone.rail, width: 4))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            onTap: widget.onToggle,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(spacing: 4, runSpacing: 4, children: [
                      if (widget.showKind) TBadge(_kindLabel[e.kind]!, bg: Tone.bg(0xFFFFFFFF), fg: TColors.slate500, border: Tone.line(0xFFE2E8F0)),
                      TBadge(e.category, bg: tone.badgeBg, fg: tone.badgeFg, border: tone.badgeBorder),
                    ]),
                    const SizedBox(height: 6),
                    Text.rich(_highlighted(e.title, widget.matched, const TextStyle(fontWeight: FontWeight.w500, color: Tone.fg(0xFF0F172A)))),
                  ]),
                ),
                Icon(widget.open ? Icons.expand_less : Icons.expand_more, color: Tone.fg(0xFF7F8EA3)),
              ]),
            ),
          ),
          if (widget.open)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Divider(height: 1, color: Tone.line(0xFFF1F5F9)),
                const SizedBox(height: 12),
                ..._body(e.body),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  for (final l in widget.links)
                    InkWell(
                      key: ValueKey('help-link-${e.id}-${l.href}'),
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => widget.onLink(l),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: const Tone.bg(0xFFEEF2FF), border: Border.all(color: _indigo200), borderRadius: BorderRadius.circular(6)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Flexible(child: Text(l.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _indigo700))),
                          const SizedBox(width: 4),
                          const Icon(Icons.open_in_new, size: 12, color: _indigo700),
                        ]),
                      ),
                    ),
                  InkWell(
                    key: ValueKey('help-copy-${e.id}'),
                    borderRadius: BorderRadius.circular(6),
                    onTap: _copyLink,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(_copied ? Icons.check : Icons.link, size: 14, color: _copied ? const Tone.fg(0xFF059669) : TColors.slate500),
                        const SizedBox(width: 4),
                        Text(_copied ? 'Link copied' : 'Copy link', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                      ]),
                    ),
                  ),
                ]),
              ]),
            ),
        ]),
      ),
    );
  }

  static const _bodyStyle = TextStyle(fontSize: 14, height: 1.5, color: Tone.fg(0xFF475569));

  /// HelpBody: paragraphs on blank lines; "1. " lines numbered, "- " bulleted.
  List<Widget> _body(String body) {
    final out = <Widget>[];
    for (final para in body.split(RegExp(r'\n\s*\n'))) {
      final lines = [for (final l in para.split('\n')) if (l.trim().isNotEmpty) l.trim()];
      if (lines.isEmpty) continue;
      if (out.isNotEmpty) out.add(const SizedBox(height: 10));
      if (lines.every((l) => RegExp(r'^\d+\.\s').hasMatch(l))) {
        out.add(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final (j, l) in lines.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 20,
                  height: 20,
                  margin: const EdgeInsets.only(top: 1, right: 10),
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: _indigo100, shape: BoxShape.circle),
                  child: Text('${j + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _indigo700)),
                ),
                Expanded(child: Text.rich(_highlighted(l.replaceFirst(RegExp(r'^\d+\.\s'), ''), widget.matched, _bodyStyle))),
              ]),
            ),
        ]));
      } else if (lines.every((l) => l.startsWith('- '))) {
        out.add(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('•  ', style: _bodyStyle),
                Expanded(child: Text.rich(_highlighted(l.substring(2), widget.matched, _bodyStyle))),
              ]),
            ),
        ]));
      } else {
        out.add(Text.rich(_highlighted(lines.join(' '), widget.matched, _bodyStyle)));
      }
    }
    return out;
  }
}

/// Highlighted: the searched words picked out in amber.
TextSpan _highlighted(String text, List<String> matched, TextStyle style) => TextSpan(style: style, children: [
      for (final r in highlightRuns(text, matched))
        TextSpan(text: r.text, style: r.hit ? const TextStyle(backgroundColor: _amber100) : null),
    ]);
