import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../page_extras.dart' show fetchRows;
import '../../shared/business_dates.dart' show fmtNum;
import '../feed_formula_form_screen.dart';
import 'setup_embed.dart';
import 'setup_views_kit.dart';

import 'package:poultrycore_mobile/design/tone.dart';

/// Setup → Feed Formulas (`/poultry-feed-formulas`) and Farm Setup → Feed
/// formulas, as the web's components/setup-views/poultry-feed-formulas.tsx
/// (9 Nov pull): New Formula and Add missing defaults as tasks, a search, and
/// one card per formula: an icon tile, its name, the Default badge and its
/// finished feed, Active / Inactive, the ingredient count and % Total (amber
/// when it does not add to 100), then Edit, Delete and Copy as my own formula.
class FeedFormulasScreen extends StatefulWidget {
  const FeedFormulasScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<FeedFormulasScreen> createState() => _FeedFormulasScreenState();
}

num _n(Object? v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);

class _FeedFormulasScreenState extends State<FeedFormulasScreen> {
  List<Map<String, dynamic>> _formulas = const [];
  bool _loading = true;
  bool _restoring = false;
  bool _seeded = false;
  String _search = '';
  int _page = 1;
  int _pageSize = 10;
  final Set<Object?> _closed = {};

  /// featureAccess.canManageFeedProduction, as the app reads it: not Staff.
  bool get _canManage => (widget.company.role ?? '').toLowerCase() != 'staff';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _toast(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      if (!_seeded) {
        _seeded = true;
        // Once per farm on the server; silent if it fails (staff, or 385 not applied).
        if (_canManage) {
          try {
            await ensureDefaultFeedFormulas(widget.session, widget.company);
          } catch (_) {}
        }
      }
      final rows = await fetchRows(widget.session, widget.company, '/api/Poultry/feed-formulas');
      if (mounted) setState(() => _formulas = rows);
    } on ApiException catch (e) {
      if (mounted) _toast('Failed to load feed formulas — ${e.message}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _restoreDefaults() async {
    setState(() => _restoring = true);
    try {
      final (formulas, items) = await ensureDefaultFeedFormulas(widget.session, widget.company, force: true);
      if (!mounted) return;
      _toast(formulas + items == 0
          ? 'Nothing to add. All the default formulas and feeds are already here.'
          : 'Default formulas added. $formulas formula${formulas == 1 ? '' : 's'} and $items feed item${items == 1 ? '' : 's'} added.');
      await _load();
    } on ApiException catch (e) {
      if (mounted) _toast('Could not add the default formulas. ${e.message}');
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  Future<void> _open({Map<String, dynamic>? existing, bool asCopy = false}) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => FeedFormulaFormScreen(session: widget.session, company: widget.company, existing: existing, asCopy: asCopy),
    ));
    if (saved == true) await _load();
  }

  Future<void> _delete(Map f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete feed formula?'),
        content: Text('"${f['formulaName']}" will be permanently removed. This does not affect past production batches.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Tone.button(const Tone.bg(0xFFDC2626))),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.session.farmClient.delete('/api/Poultry/feed-formulas/${f['poultryFeedFormulaId']}', query: {'farmId': widget.company.farmId});
      if (!mounted) return;
      _toast('Formula deleted');
      await _load();
    } on ApiException catch (e) {
      if (mounted) _toast('Failed to delete formula — ${e.message}');
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return _formulas;
    return [
      for (final f in _formulas)
        if ('${f['formulaName'] ?? ''}'.toLowerCase().contains(q) || '${f['finishedFeedItemName'] ?? ''}'.toLowerCase().contains(q)) f,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final embedded = isSetupEmbedded(context);
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-feed-formulas');
    final filtered = _filtered;
    final pg = pagedSlice(filtered, _page, _pageSize);
    return Scaffold(
      appBar: embedded ? null : AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Feed Formulas')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(key: const ValueKey('feed-formulas-list'), padding: const EdgeInsets.fromLTRB(14, 12, 14, 24), children: [
          if (!embedded) ...[
            const Text('Feed Formulas', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: _slate900)),
            const SizedBox(height: 12),
          ],
          SetupTaskBar(tasks: [
            SetupTask(id: 'new', label: 'New Formula', icon: Icons.add, primary: true, onTap: () => _open(), disabled: _loading, hidden: !_canManage),
            SetupTask(
              id: 'defaults',
              label: _restoring ? 'Adding defaults…' : 'Add missing defaults',
              icon: Icons.auto_awesome,
              onTap: _restoreDefaults,
              disabled: _restoring || _loading,
              hidden: !_canManage,
            ),
          ]),
          if (!embedded) const SizedBox(height: 12),
          SetupSearch(hint: 'Search formula or feed', onChanged: (v) => setState(() {
            _search = v;
            _page = 1;
          })),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator()))
          else if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Column(children: [
                Icon(Icons.science_outlined, size: 40, color: Tone.fg(0xFFCBD5E1)),
                SizedBox(height: 12),
                Text('No feed formulas yet. Create one to speed up feed production.',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, color: _slate500)),
              ]),
            )
          else ...[
            for (final f in pg.items) ...[_card(f), const SizedBox(height: 12)],
            RecordsPager(
              total: filtered.length,
              page: pg.page,
              pageSize: _pageSize,
              onPage: (p) => setState(() => _page = p),
              onPageSize: (n) => setState(() => _pageSize = n),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _card(Map<String, dynamic> f) {
    final id = f['poultryFeedFormulaId'];
    final open = !_closed.contains(id);
    final total = _n(f['percentageTotal']);
    final usesPct = total > 0;
    final pctGood = !usesPct || (total - 100).abs() < 0.01;
    final (statBg, statLine, statFg) = !usesPct
        ? (_slate50, _slate200, _slate500)
        : pctGood
            ? (const Tone.bg(0xFFECFDF5), const Tone.line(0xFFA7F3D0), const Tone.fg(0xFF047857))
            : (const Tone.bg(0xFFFFFBEB), const Tone.line(0xFFFDE68A), const Tone.fg(0xFFB45309));
    final active = f['isActive'] == true;
    return SetupCard(
      key: ValueKey('formula-$id'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Header: icon tile + title + subtitle; tapping folds the card.
        InkWell(
          onTap: () => setState(() => open ? _closed.add(id) : _closed.remove(id)),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _slate100))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: const Tone.bg(0xFFFFFBEB), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.science_outlined, size: 16, color: Tone.fg(0xFFD97706)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text('${f['formulaName'] ?? ''}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _slate900)),
                    if (f['isDefault'] == true) _badge('Default', const Tone.bg(0xFFF0F9FF), const Tone.line(0xFF7DD3FC), const Tone.fg(0xFF0369A1)),
                  ]),
                  Text('${f['finishedFeedItemName'] ?? 'No finished feed'}', maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: _slate500)),
                ]),
              ),
              const SizedBox(width: 6),
              active
                  ? _badge('Active', const Tone.bg(0xFFF1F5F9), const Tone.line(0xFFF1F5F9), _slate900)
                  : _badge('Inactive', const Tone.bg(0xFFFFFFFF), _slate200, _slate900),
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: open ? .5 : 0,
                duration: const Duration(milliseconds: 150),
                child: const Icon(Icons.expand_more, size: 18, color: Tone.fg(0xFF94A3B8)),
              ),
            ]),
          ),
        ),
        // Body: key stats, then the actions while open.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: _stat('INGREDIENTS', Text('${_n(f['lineCount']).toInt()}', style: _statValue), _slate50, _slate200, _slate500)),
              const SizedBox(width: 8),
              Expanded(
                child: _stat(
                  '% TOTAL',
                  usesPct
                      ? Row(children: [
                          Icon(pctGood ? Icons.check_circle_outline : Icons.warning_amber_rounded, size: 16, color: statFg),
                          const SizedBox(width: 4),
                          Text('${fmtNum(total, 2)}%', style: _statValue.copyWith(color: statFg)),
                        ])
                      : Text('fixed', style: _statValue.copyWith(color: const Tone.fg(0xFF94A3B8))),
                  statBg,
                  statLine,
                  statFg,
                ),
              ),
            ]),
            if (open) ...[
              const SizedBox(height: 12),
              const Divider(height: 1, color: _slate100),
              const SizedBox(height: 12),
              // Two per row: labelled buttons overflow a phone card on one line.
              Row(children: [
                Expanded(child: _action('Edit', Icons.edit_outlined, () => _open(existing: f))),
                if (_canManage) ...[
                  const SizedBox(width: 8),
                  Expanded(child: _action('Delete', Icons.delete_outline, () => _delete(f), danger: true)),
                ],
              ]),
              if (_canManage) ...[
                const SizedBox(height: 8),
                _action('Copy as my own formula', Icons.copy, () => _open(existing: f, asCopy: true)),
              ],
            ],
          ]),
        ),
      ]),
    );
  }

  static const _statValue = TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _slate900);

  Widget _stat(String label, Widget value, Color bg, Color line, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: bg, border: Border.all(color: line), borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .5, color: fg)),
          value,
        ]),
      );

  Widget _badge(String text, Color bg, Color line, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        decoration: BoxDecoration(color: bg, border: Border.all(color: line), borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: fg)),
      );

  Widget _action(String label, IconData icon, VoidCallback onTap, {bool danger = false}) => SizedBox(
        height: 40,
        child: OutlinedButton.icon(
          key: ValueKey('formula-action-$label'),
          style: OutlinedButton.styleFrom(
            backgroundColor: Tone.button(const Tone.bg(0xFFFFFFFF)),
            foregroundColor: danger ? const Tone.fg(0xFFDC2626) : _slate900,
            side: BorderSide(color: danger ? const Tone.line(0xFFFECACA) : _slate200),
          ),
          onPressed: onTap,
          icon: Icon(icon, size: 16),
          label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      );
}

const _slate50 = Tone.bg(0xFFF8FAFC);
const _slate100 = Tone.line(0xFFF1F5F9);
const _slate200 = Tone.line(0xFFE2E8F0);
const _slate500 = Tone.fg(0xFF64748B);
const _slate900 = Tone.fg(0xFF0F172A);
