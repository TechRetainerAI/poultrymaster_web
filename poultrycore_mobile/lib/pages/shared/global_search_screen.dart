// The header search (components/dashboard/global-search.tsx,
// hooks/use-global-search.ts, lib/search/records.ts), as a full screen.
//
// Type a page ("cash flow", "p&l", "who owes"), an intent ("new sale"), a name
// ("Kofi") or part of a phone number ("0244"): it offers the matching pages
// and records for the ACTIVE company, filtered to what this user may open,
// typo-tolerant, and remembers what was opened (Recent).
//
// An app addition in one respect: the web shows this box only on wide screens
// (the header's `hidden lg:flex`), so its phone layout has no search. The user
// asked for it on 3 Nov 2026; it opens from a search icon on the Home header.
// Left out: the web's "Filter this page" row and keyboard keys (Ctrl+K, "/",
// arrows) -- the search is its own screen here, not a box over a list.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../poultry/reports/report_routes.dart' show openAppHref;
import '../poultry/trackers/tracker_widgets.dart' show TColors, rowsOf;
import '../registry.dart';
import '../web_nav.dart';
import 'help/help_search.dart';
import 'setup_admin_routes.dart';

/// A named thing (records.ts SearchRecord).
class SearchRecord {
  const SearchRecord({
    required this.kind,
    required this.id,
    required this.title,
    required this.href,
    this.subtitle,
    this.extra = const [],
    this.phones = const [],
    this.inactive = false,
  });
  final String kind, id, title, href;
  final String? subtitle;
  final List<String> extra;
  final List<String?> phones;
  final bool inactive;
}

const recordKindLabel = {'customer': 'Customer', 'supplier': 'Supplier', 'flock': 'Flock', 'house': 'House', 'product': 'Product', 'driver': 'Driver'};
const _kindIcon = {
  'customer': Icons.people_outline,
  'supplier': Icons.local_shipping_outlined,
  'flock': Icons.flutter_dash,
  'house': Icons.business_outlined,
  'product': Icons.inventory_2_outlined,
  'driver': Icons.person_outline,
};

/// Digits only, so "024 412" finds "+233 24 412 ...".
String phoneDigits(String? s) => (s ?? '').replaceAll(RegExp(r'\D+'), '');

/// rankRecords: a phone fragment matches on digits (a local leading 0 meets a
/// stored country code); otherwise a real hit (score 45+) on name / subtitle / extra.
List<SearchRecord> rankRecords(String text, List<SearchRecord> records, {int limit = 6}) {
  if (text.trim().isEmpty) return [];
  final qDigits = RegExp(r'^[\d\s+()-]+$').hasMatch(text.trim()) ? phoneDigits(text) : '';
  final ranked = <(SearchRecord, double)>[];
  for (final r in records) {
    if (qDigits.length >= 4) {
      final local = qDigits.replaceFirst(RegExp('^0'), '');
      final hit = r.phones.any((p) {
        final d = phoneDigits(p);
        return d.contains(qDigits) || (local.length >= 4 && d.contains(local));
      });
      if (hit) ranked.add((r, 75 - (r.inactive ? 8 : 0)));
      continue;
    }
    var score = scoreFields(text, [(r.title, 1), (r.subtitle ?? '', 0.6), for (final e in r.extra) (e, 0.6)]);
    if (score < 45) continue;
    if (r.inactive) score -= 8;
    ranked.add((r, score));
  }
  ranked.sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final x in ranked.take(limit)) x.$1];
}

/// The query asks to record something ("new sale", "record expense").
bool queryIsCreate(String raw) {
  final t = normalize(raw).replaceFirst(RegExp(r'^(go to|goto|open|show|view|find|search|see) '), '');
  return RegExp(r'^(new|add|record|create|log|enter|make) ').hasMatch(t);
}

String searchPlaceholder(CompanyType t) => switch (t) {
      CompanyType.water => 'Search pages, customers, drivers…',
      CompanyType.generic => 'Search pages, customers, products…',
      CompanyType.hotel || CompanyType.restaurant => 'Search pages and reports…',
      _ => 'Search pages, customers, flocks…',
    };

class _Recent {
  _Recent(this.href, this.title, this.meta);
  final String href, title, meta;
  Map<String, String> toJson() => {'href': href, 'title': title, 'meta': meta};
}

class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;
  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final _q = TextEditingController();
  String _query = '';
  List<SearchRecord> _records = [];
  bool _fetching = false;
  List<_Recent> _recents = [];

  late final List<({String title, String href, String group})> _pages = _openablePages();
  late final Set<String> _openable = {for (final p in _pages) p.href};

  String get _recentKey => 'globalSearch:recent:${widget.company.farmId}';
  bool get _pagesOnly => widget.company.type == CompanyType.hotel || widget.company.type == CompanyType.restaurant;

  @override
  void initState() {
    super.initState();
    _loadRecents();
    _loadRecords();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  List<({String title, String href, String group})> _openablePages() {
    final out = <String, ({String title, String href, String group})>{};
    final groups = gateSetupLinks(webNavGroups[PageRegistry.moduleOf(widget.company.type)] ?? const [], widget.company);
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

  Future<void> _loadRecents() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = jsonDecode(p.getString(_recentKey) ?? '[]');
      if (!mounted || raw is! List) return;
      setState(() => _recents = [
            for (final r in raw)
              if (r is Map) _Recent('${r['href']}', '${r['title']}', '${r['meta']}'),
          ].take(6).toList());
    } catch (_) {
      // Nothing remembered.
    }
  }

  Future<void> _remember(_Recent e) async {
    final next = [e, ..._recents.where((r) => r.href != e.href)].take(6).toList();
    setState(() => _recents = next);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_recentKey, jsonEncode([for (final r in next) r.toJson()]));
    } catch (_) {
      // This time only.
    }
  }

  Future<void> _clearRecents() async {
    setState(() => _recents = []);
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_recentKey);
    } catch (_) {}
  }

  /// loadRecords: only from pages this user may open; a record is a way INTO
  /// a page, never around its permission.
  Future<void> _loadRecords() async {
    if (_pagesOnly) return;
    setState(() => _fetching = true);
    final api = widget.session.farmClient;
    final scope = {'farmId': widget.company.farmId, 'userId': widget.session.tokens.userId ?? ''};
    Future<List<Map>> list(String href, String path) async {
      if (!_openable.contains(href)) return [];
      try {
        return rowsOf(await api.get(path, query: scope));
      } on ApiException {
        return [];
      }
    }

    String? join(List<Object?> parts) {
      final s = parts.where((p) => p != null && '$p'.trim().isNotEmpty).join(' · ');
      return s.isEmpty ? null : s;
    }

    final out = <SearchRecord>[];
    if (widget.company.type == CompanyType.water) {
      final r = await Future.wait([list('/water-customers', '/api/Water/customers'), list('/water-drivers', '/api/Water/drivers')]);
      for (final c in r[0]) {
        out.add(SearchRecord(
          kind: 'customer', id: '${c['waterCustomerId']}', title: '${c['name'] ?? ''}', href: '/water-customers',
          subtitle: join([c['contactPhone'], c['city']]), extra: ['${c['contactEmail'] ?? ''}', '${c['address'] ?? ''}'], phones: ['${c['contactPhone'] ?? ''}'],
        ));
      }
      for (final d in r[1]) {
        out.add(SearchRecord(
          kind: 'driver', id: '${d['waterDriverId']}', title: '${d['driverName'] ?? ''}', href: '/water-drivers',
          subtitle: join([d['phoneNumber']]), phones: ['${d['phoneNumber'] ?? ''}'], inactive: d['isActive'] == false,
        ));
      }
    } else if (widget.company.type == CompanyType.poultry) {
      final r = await Future.wait([
        list('/customers', '/api/Customer'),
        list('/suppliers', '/api/Supplier'),
        list('/flocks', '/api/Flock'),
        list('/houses', '/api/House'),
      ]);
      for (final c in r[0]) {
        out.add(SearchRecord(
          kind: 'customer', id: '${c['customerId']}', title: '${c['name'] ?? ''}', href: '/customers',
          subtitle: join([c['contactPhone'], c['city']]), extra: ['${c['contactEmail'] ?? ''}', '${c['address'] ?? ''}'], phones: ['${c['contactPhone'] ?? ''}'],
        ));
      }
      for (final s in r[1]) {
        out.add(SearchRecord(
          kind: 'supplier', id: '${s['supplierId']}', title: '${s['name'] ?? ''}', href: '/suppliers',
          subtitle: join([s['contactPhone'], s['city']]), extra: ['${s['contactEmail'] ?? ''}', '${s['address'] ?? ''}'], phones: ['${s['contactPhone'] ?? ''}'],
        ));
      }
      for (final f in r[2]) {
        final active = f['active'] != false;
        out.add(SearchRecord(
          kind: 'flock', id: '${f['flockId']}', title: '${f['name'] ?? ''}', href: '/flocks',
          subtitle: join([f['breed'], active ? '${f['quantity'] ?? 0} birds' : 'Closed']), inactive: !active,
        ));
      }
      for (final h in r[3]) {
        out.add(SearchRecord(
          kind: 'house', id: '${h['houseId']}', title: '${h['name'] ?? ''}', href: '/houses',
          subtitle: join([h['location'], h['capacity'] != null ? 'capacity ${h['capacity']}' : null]),
        ));
      }
    }
    if (mounted) {
      setState(() {
        _records = out;
        _fetching = false;
      });
    }
  }

  void _go(_Recent e) {
    _remember(e);
    _q.clear();
    setState(() => _query = '');
    openAppHref(context, widget.session, widget.company, e.href, label: e.title);
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim();
    final hasQuery = q.isNotEmpty;
    final pages = rankPages(_query, _pages, limit: 8);
    final text = parseQuery(_query);
    final records = text.length >= 2 ? rankRecords(text, _records) : const <SearchRecord>[];
    final visibleRecents = [for (final r in _recents) if (_openable.contains(r.href.split('?').first)) r];
    final nothing = hasQuery && pages.isEmpty && records.isEmpty && !_fetching;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: AppInput(
            key: const ValueKey('global-search'),
            controller: _q,
            autofocus: true,
            hintText: searchPlaceholder(widget.company.type),
            prefixIcon: const Icon(Icons.search, color: TColors.slate400),
            suffixIcon: hasQuery
                ? IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      _q.clear();
                      setState(() => _query = '');
                    },
                  )
                : null,
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
      ),
      body: ListView(key: const ValueKey('global-search-list'), padding: const EdgeInsets.symmetric(vertical: 6), children: [
        if (!hasQuery && visibleRecents.isNotEmpty) ...[
          _heading('Recent', trailing: TextButton(onPressed: _clearRecents, child: const Text('Clear', style: TextStyle(fontSize: 12)))),
          for (final r in visibleRecents) _row(Icons.schedule, r.title, r.meta, () => _go(r), key: ValueKey('recent-${r.href}')),
        ],
        if (!hasQuery)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Text.rich(
              TextSpan(style: const TextStyle(fontSize: 13, color: TColors.slate500), children: [
                TextSpan(text: 'Search pages and ${_pagesOnly ? 'reports' : 'records'}. Try '),
                const TextSpan(text: 'who owes', style: TextStyle(fontWeight: FontWeight.w500, color: TColors.slate700)),
                const TextSpan(text: ', '),
                const TextSpan(text: 'new sale', style: TextStyle(fontWeight: FontWeight.w500, color: TColors.slate700)),
                const TextSpan(text: ', '),
                const TextSpan(text: 'p&l', style: TextStyle(fontWeight: FontWeight.w500, color: TColors.slate700)),
                if (!_pagesOnly) const TextSpan(text: ', a customer name or a phone number'),
                const TextSpan(text: '.'),
              ]),
            ),
          ),
        if (pages.isNotEmpty) ...[
          _heading(queryIsCreate(_query) ? 'Record it on' : 'Pages'),
          for (final p in pages)
            _row(queryIsCreate(_query) ? Icons.add_circle_outline : Icons.arrow_forward, p.title, _groupOf(p.href), () => _go(_Recent(p.href, p.title, _groupOf(p.href))),
                key: ValueKey('page-${p.href}')),
        ],
        if (records.isNotEmpty) ...[
          _heading('Records'),
          for (final r in records)
            _row(_kindIcon[r.kind] ?? Icons.label_outline, r.inactive ? '${r.title} (inactive)' : r.title, recordKindLabel[r.kind] ?? '',
                () => _go(_Recent(r.href, r.title, recordKindLabel[r.kind] ?? '')),
                subtitle: r.subtitle, key: ValueKey('record-${r.kind}-${r.id}')),
        ],
        if (hasQuery && _fetching && records.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(children: [
              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 8),
              Text('Looking through records…', style: TextStyle(fontSize: 12, color: TColors.slate500)),
            ]),
          ),
        if (nothing)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
            child: Column(children: [
              Text('Nothing matches “$q”.', textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: TColors.slate500)),
              const SizedBox(height: 4),
              const Text('Check the spelling, or try a shorter word.', style: TextStyle(fontSize: 12, color: TColors.slate500)),
            ]),
          ),
      ]),
    );
  }

  String _groupOf(String href) => _pages.firstWhere((p) => p.href == href, orElse: () => (title: '', href: href, group: '')).group;

  Widget _heading(String text, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 2),
        child: Row(children: [
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: TColors.slate500))),
          ?trailing,
        ]),
      );

  Widget _row(IconData icon, String title, String meta, VoidCallback onTap, {String? subtitle, Key? key}) => InkWell(
        key: key,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Icon(icon, size: 18, color: TColors.slate500),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 14.5, color: TColors.slate900)),
                if (subtitle != null) Text(subtitle, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
              ]),
            ),
            if (meta.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(meta, style: const TextStyle(fontSize: 11.5, color: TColors.slate400)),
            ],
          ]),
        ),
      );
}
