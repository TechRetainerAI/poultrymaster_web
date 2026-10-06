import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/api_client.dart';
import '../design/tokens.dart';
import '../design/web_mobile.dart';
import '../design/ui/buttons.dart';
import '../design/ui/form_section.dart';
import '../design/ui/inputs.dart';
import '../models/company.dart';
import '../models/module.dart';
import '../state/session.dart';
import '../widgets/module_sidebar.dart';
import 'export.dart';
import 'form_spec.dart';
import 'registry.dart';
import 'web_page_design.dart';
import 'list_header.dart';
import 'lookup_loader.dart';
import 'form_screen.dart';
import 'module_registry.dart';
import 'page_extras.dart';
import 'page_actions.dart';
import 'page_spec.dart';
import 'plumbing_fields.dart';
import 'record_screen.dart';

/// Renders any [PageSpec] as a searchable list of records.
///
/// Rows are cards, not table rows. The web uses tables on 172 of its pages,
/// but a table on a 400px screen means horizontal scrolling for every glance;
/// the same fields as a card read in one column. Opening a card shows the full
/// record, which is where the rest of the table's columns go.
class ListScreen extends StatefulWidget {
  const ListScreen({
    super.key,
    required this.spec,
    required this.session,
    required this.company,
  });

  final PageSpec spec;
  final Session session;
  final Company company;

  @override
  State<ListScreen> createState() => _ListScreenState();
}

class _ListScreenState extends State<ListScreen> {
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  String? _error;
  String _query = '';

  bool _extraBusy = false;

  /// A header extra: open its screen and reload if it changed data, or run
  /// its action and report what it did.
  Future<void> _runExtra(ListExtra x) async {
    final run = x.run;
    if (run != null) {
      if (_extraBusy) return;
      setState(() => _extraBusy = true);
      final messenger = ScaffoldMessenger.of(context);
      try {
        messenger.showSnackBar(SnackBar(content: Text(await run(widget.session, widget.company))));
        await _load();
      } on ApiException catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      } finally {
        if (mounted) setState(() => _extraBusy = false);
      }
      return;
    }
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => x.builder!(widget.session, widget.company, _rows),
    ));
    if (changed == true) _load();
  }

  /// Fills [PageSpec.resolve] fields: the name for an id, from the same
  /// lookup the form's dropdown uses. "—" when it cannot be found, as the
  /// web shows.
  Future<void> _resolve(List<Map<String, dynamic>> rows) async {
    final spec = widget.spec;
    if (spec.resolve.isEmpty || rows.isEmpty) return;
    final loader = LookupLoader(widget.session, widget.company);
    for (final MapEntry(key: field, value: (idKey, slot, label)) in spec.resolve.entries) {
      List<AppSelectItem<String>> items = const [];
      try {
        items = await (loader.optionsFor(slot, label: label) ?? Future.value(const []));
      } catch (_) {}
      final names = {for (final i in items) i.value: i.label};
      for (final r in rows) {
        r[field] = names['${r[idKey]}'] ?? '—';
      }
    }
  }

  /// The Filters panel's choices, by ListFilter key.
  Map<String, String> _filters = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final spec = widget.spec;
    try {
      await beforeLoad[spec.key]?.call(widget.session, widget.company).catchError((_) {});
      final path = spec.path.replaceAll('{farmId}', widget.company.farmId);
      final query = <String, dynamic>{...spec.query};
      if (spec.needsFarmId && !spec.path.contains('{farmId}')) {
        query[spec.farmIdParam] = widget.company.farmId;
      }
      if (spec.needsUserId) {
        query['userId'] = widget.session.tokens.userId ?? '';
      }
      if (spec.needsCompanyType) {
        query['type'] = widget.company.type.wire;
      }

      final client = spec.source == 'login'
          ? widget.session.loginClient
          : widget.session.farmClient;
      final res = await client.get(path, query: query);
      final rows = _rowsFrom(res, spec.itemsAt);
      await _resolve(rows);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        // A 404 here is nearly always "this company has not set this up yet"
        // rather than a missing route — the endpoint answers for companies
        // that have the record. "Not Found" read as if the page were broken.
        _error = switch (e.statusCode) {
          409 => 'This company type does not expose this page.',
          404 => 'Nothing set up for this company yet.',
          _ => e.message,
        };
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load ${_name.toLowerCase()}.';
        _loading = false;
      });
    }
  }

  static List<Map<String, dynamic>> _rowsFrom(dynamic res, String? at) {
    dynamic node = res;
    if (node is Map) {
      final map = Map<String, dynamic>.from(node);
      for (final key in [at, 'items', 'data', 'results', 'rows']) {
        if (key == null) continue;
        if (map[key] is List) {
          node = map[key];
          break;
        }
      }
    }
    if (node is List) {
      return node
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    // Settings-style endpoints (company, farm production settings) return the
    // record itself rather than a list of one. Showing that record beats
    // showing an empty page, which is what returning nothing did.
    if (node is Map && node.isNotEmpty) {
      final map = Map<String, dynamic>.from(node);
      final scalars =
          map.values.where((v) => v is! Map && v is! List).length;
      if (scalars > 0) return [map];
    }
    return const [];
  }

  /// Whether a numeric field holds money.
  ///
  /// Counting words win outright. Without that, `totalEggsProduced` was summed
  /// and rendered as GHC 221,331.00 — a count of eggs shown as currency, which
  /// is worse than showing nothing because it reads as a real figure.
  static bool _isMoneyField(String lk) {
    const counts = [
      'count', 'quantity', 'qty', 'egg', 'bird', 'flock', 'crate', 'piece',
      'mortality', 'death', 'number', 'staff', 'room', 'kg', 'litre', 'liter',
      'age', 'week', 'day', 'id', 'production', 'pick', 'stock',
    ];
    for (final c in counts) {
      if (lk.contains(c)) return false;
    }

    // 'total' on its own is NOT a money word. `totalProduction` is a count of
    // eggs; `totalEggs` likewise. Requiring a real money term is what stops a
    // production figure being rendered as GHC — a mistake made three times in
    // this file before the rule was tightened to this.
    const money = [
      'amount', 'revenue', 'sales', 'expense', 'profit', 'cash', 'balance',
      'cost', 'price', 'value', 'paid', 'payable', 'receivable', 'principal',
      'outstanding', 'fee', 'salary', 'wage',
    ];
    return money.any(lk.contains);
  }

  /// A short, readable card title derived from the field being summed, so the
  /// header does not truncate at two words.
  static String _moneyLabel(String key) {
    final lk = key.toLowerCase();
    if (lk.contains('revenue')) return 'Total revenue';
    if (lk.contains('expense')) return 'Total expenses';
    if (lk.contains('cost')) return 'Total cost';
    if (lk.contains('paid')) return 'Total paid';
    if (lk.contains('balance')) return 'Total balance';
    return 'Total';
  }

  /// Summary cards plus the "Recent …" heading.
  Widget _summaryBlock(int shown) {
    final cards = _summaries();
    final rowsOfCards = <Widget>[];
    for (var i = 0; i < cards.length; i += 2) {
      final a = cards[i];
      final b = i + 1 < cards.length ? cards[i + 1] : null;
      rowsOfCards.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SummaryCard(
                    title: a.label,
                    value: a.value,
                    sub: a.sub,
                    icon: a.icon,
                    valueColor: a.color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: b == null
                    ? const SizedBox.shrink()
                    : SummaryCard(
                        title: b.label,
                        value: b.value,
                        sub: b.sub,
                        icon: b.icon,
                        valueColor: b.color),
              ),
            ],
          ),
        ),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...rowsOfCards,
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text('Recent ${_name.toLowerCase()}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            Text('$shown shown',
                style: TextStyle(
                    fontSize: 12, color: context.tokens.mutedForeground)),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  /// 263208 -> 263,208. Long figures are much easier to read at a glance
  /// grouped, and every other figure on the page already is.
  static String _grouped(num v) {
    final whole = v == v.roundToDouble();
    final s = whole ? v.toInt().abs().toString() : v.abs().toStringAsFixed(1);
    final parts = s.split('.');
    final buf = StringBuffer();
    for (var i = 0; i < parts[0].length; i++) {
      if (i > 0 && (parts[0].length - i) % 3 == 0) buf.write(',');
      buf.write(parts[0][i]);
    }
    final sign = v < 0 ? '-' : '';
    return '$sign$buf${parts.length > 1 ? '.${parts[1]}' : ''}';
  }

  static IconData _headerIcon(String title) {
    final t = title.toLowerCase();
    if (t.contains('sale')) return Icons.shopping_cart_outlined;
    if (t.contains('flock') || t.contains('bird')) return Icons.pets_outlined;
    if (t.contains('expense')) return Icons.receipt_long_outlined;
    if (t.contains('loan')) return Icons.request_quote_outlined;
    if (t.contains('asset') || t.contains('investment')) {
      return Icons.precision_manufacturing_outlined;
    }
    if (t.contains('customer') || t.contains('staff')) {
      return Icons.people_outline;
    }
    if (t.contains('cash') || t.contains('money')) {
      return Icons.account_balance_wallet_outlined;
    }
    if (t.contains('stock') || t.contains('inventory') || t.contains('material')) {
      return Icons.inventory_2_outlined;
    }
    if (t.contains('production') || t.contains('record')) {
      return Icons.description_outlined;
    }
    if (t.contains('room') || t.contains('booking')) {
      return Icons.meeting_room_outlined;
    }
    if (t.contains('order') || t.contains('menu')) return Icons.receipt_outlined;
    return Icons.list_alt_outlined;
  }

  /// Rows after the search box is applied.
  List<Map<String, dynamic>> get _visible {
    final defs = listFilters[widget.spec.key] ?? const <ListFilter>[];
    final filtered = _filters.isEmpty
        ? _rows
        : _rows.where((r) {
            for (final f in defs) {
              final v = _filters[f.key];
              if (v != null && v.isNotEmpty && !f.matches(r, v)) return false;
            }
            return true;
          }).toList();
    return _searched(filtered);
  }

  List<Map<String, dynamic>> _searched(List<Map<String, dynamic>> source) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return source;
    // A generated spec names no search fields; search every short string
    // instead, which is what a person scanning the page would do.
    final keys = widget.spec.searchFields.isNotEmpty
        ? widget.spec.searchFields
        : (_rows.isEmpty
            ? const <String>[]
            : _rows.first.keys.where((k) => _rows.first[k] is String).toList());
    return _rows.where((r) {
      for (final k in keys) {
        final v = r[k];
        if (v != null && '$v'.toLowerCase().contains(q)) return true;
      }
      return false;
    }).toList();
  }

  /// The web form for this page, when one was extracted for it.
  /// The page's name as the website gives it. `spec.title` is an API action
  /// name ("Get current user"), which is not what this app should ever show.
  String get _name => headerFor(widget.spec.key, widget.spec.title).title;

  /// One record, nothing to add, nothing to search through: a report, not a
  /// list. Shown in full rather than as a card that has to be opened.
  bool _isSingleReport(List<Map<String, dynamic>> rows) {
    if (rows.length != 1 || _query.isNotEmpty) return false;
    final acts = pageActions[widget.spec.key] ?? const PageActions();
    return acts.action == null;
  }

  FormDef? get _extractedForm => formForSpec(widget.spec.key);

  /// The form to open from the primary button.
  ///
  /// Most pages have one extracted from the web's markup. The big bespoke
  /// pages (production records, sales, flocks) build their dialogs by hand
  /// without `<FormSection>`, so nothing could be extracted — for those, a
  /// form is derived from the fields the records themselves carry, which is
  /// better than having no way to enter data at all.
  /// A page the API will not accept a POST for gets no create form at all —
  /// not even a derived one. Deriving from row shape is a guess that is only
  /// ever right where creating is possible in the first place.
  FormDef? get _formDef =>
      widget.spec.readOnly ? _extractedForm : (_extractedForm ?? _derivedForm);

  FormDef? get _derivedForm {
    final spec = widget.spec;

    // Prefer the curated field list; fall back to the shape of a loaded row.
    final fields = <FormFieldDef>[];
    if (spec.fields.isNotEmpty) {
      for (final f in spec.fields) {
        fields.add(FormFieldDef(
          label: f.label,
          kind: switch (f.kind) {
            FieldKind.money => FormFieldKind.money,
            FieldKind.number => FormFieldKind.number,
            FieldKind.date => FormFieldKind.date,
            FieldKind.boolean => FormFieldKind.bool,
            _ => FormFieldKind.text,
          },
          name: f.key,
        ));
      }
    } else if (_rows.isNotEmpty) {
      for (final k in _rows.first.keys) {
        final v = _rows.first[k];
        if (v is Map || v is List) continue;
        if (isPlumbingField(k, v)) continue;
        final lk = k.toLowerCase();
        if (lk == 'id' || lk.endsWith('id')) continue;
        fields.add(FormFieldDef(
          label: _label(k),
          kind: v is bool
              ? FormFieldKind.bool
              : v is num
                  ? (_isMoneyField(lk)
                      ? FormFieldKind.money
                      : FormFieldKind.number)
                  : (lk.contains('date')
                      ? FormFieldKind.date
                      : FormFieldKind.text),
          name: k,
        ));
        if (fields.length >= 14) break;
      }
    }
    if (fields.isEmpty) return null;

    return FormDef(
      route: '',
      specKey: spec.key,
      sections: [
        FormSectionDef(
          title: spec.title,
          color: 'indigo',
          columns: 2,
          fields: fields,
        ),
      ],
    );
  }

  static String _label(String key) {
    final spaced = key.replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}');
    return spaced.isEmpty
        ? key
        : spaced[0].toUpperCase() + spaced.substring(1);
  }

  /// Totals shown above the list.
  ///
  /// A page can declare its own cards (the web does, per page); otherwise
  /// generic ones are derived from whatever numeric fields the rows carry.
  List<_Card> _summaries() {
    final rows = _visible;
    if (rows.isEmpty) return const [];

    if (widget.spec.summaries.isNotEmpty) {
      return [
        for (final d in widget.spec.summaries) _fromDef(d, rows),
      ].whereType<_Card>().toList();
    }
    return _generic(rows);
  }

  _Card _fromDef(SummaryDef d, List<Map<String, dynamic>> all) {
    final rows = d.where.isEmpty
        ? all
        : all.where((r) => d.where.entries.every((e) => r[e.key] == e.value)).toList();
    double sum(String f) {
      var t = 0.0;
      for (final r in rows) {
        final v = r[f];
        if (v is num) t += v.toDouble();
      }
      return t;
    }

    num? latest(String f) {
      for (final r in rows) {
        final v = r[f];
        if (v is num) return v;
      }
      return null;
    }

    String text;
    switch (d.op) {
      case SummaryOp.count:
        text = _grouped(rows.length);
      case SummaryOp.sum:
        final t = sum(d.field!);
        text = d.money ? ghc(t) : _grouped(t);
      case SummaryOp.average:
        final t = sum(d.field!) / rows.length;
        text = d.money ? ghc(t) : _grouped(t.roundToDouble());
      case SummaryOp.latest:
        final v = latest(d.field!);
        text = v == null ? '—' : _grouped(v);
      case SummaryOp.distinctSum:
        text = _grouped(sum(d.field!));
    }

    String? sub = d.sub;
    if (d.crates != null && d.op == SummaryOp.sum) {
      final total = sum(d.field!).round();
      final c = total ~/ d.crates!;
      final pcs = total % d.crates!;
      sub = '${_grouped(c)}c + ${pcs}p';
    }

    return _Card(d.label, text, sub, _iconForLabel(d.label), _tone(d.tone));
  }

  static Color? _tone(SummaryTone t) => switch (t) {
        SummaryTone.positive => const Color(0xFF059669), // emerald-600
        SummaryTone.negative => const Color(0xFFDC2626), // red-600
        SummaryTone.neutral => null,
      };

  static IconData _iconForLabel(String label) {
    final l = label.toLowerCase();
    if (l.contains('egg')) return Icons.egg_outlined;
    if (l.contains('feed')) return Icons.grass_outlined;
    if (l.contains('death') || l.contains('mortal')) {
      return Icons.warning_amber_outlined;
    }
    if (l.contains('bird')) return Icons.pets_outlined;
    if (l.contains('avg') || l.contains('average')) return Icons.trending_up;
    if (l.contains('record')) return Icons.list_alt;
    if (l.contains('quantity')) return Icons.inventory_2_outlined;
    return Icons.attach_money;
  }

  /// Derived cards for pages with no declared summaries.
  List<_Card> _generic(List<Map<String, dynamic>> rows) {
    String? moneyKey;
    String? qtyKey;
    for (final k in rows.first.keys) {
      if (rows.first[k] is! num) continue;
      final lk = k.toLowerCase();
      if (moneyKey == null && _isMoneyField(lk)) moneyKey = k;
      if (qtyKey == null && (lk == 'quantity' || lk == 'qty')) qtyKey = k;
    }

    final out = <_Card>[];
    if (moneyKey != null) {
      var sum = 0.0;
      for (final r in rows) {
        final v = r[moneyKey];
        if (v is num) sum += v.toDouble();
      }
      out.add(_Card(_moneyLabel(moneyKey), ghc(sum),
          '${rows.length} transactions', Icons.attach_money, null));
      out.add(_Card('Average', ghc(sum / rows.length), 'per transaction',
          Icons.trending_up, null));
    }
    if (qtyKey != null) {
      var q = 0.0;
      for (final r in rows) {
        final v = r[qtyKey];
        if (v is num) q += v.toDouble();
      }
      out.add(_Card('Total quantity', _grouped(q),
          'across ${rows.length} records', Icons.inventory_2_outlined, null));
    }
    if (out.isEmpty) {
      out.add(_Card(_name, _grouped(rows.length),
          rows.length == 1 ? 'record' : 'records', Icons.list_alt, null));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final tokens = context.tokens;
    final nav = NavTheme.forType(widget.company.type);
    final rows = _visible;
    // The web page's own heading and subtitle, when this spec is reachable
    // from one. Preferred over headerFor(), which works from the endpoint
    // name and so reads like an API action ("Get current user") rather than
    // the page's name.
    final design = PageRegistry.designFor(spec.key);
    final head = headerFor(spec.key, spec.title).withWeb(design);
    // What the web offers on this page.
    final acts = pageActions[spec.key] ?? const PageActions();
    final lead = sidebarLeading(context, widget.session, widget.company,
        specKey: spec.key);

    return Scaffold(
      appBar: AppBar(
        leading: lead.leading,
        leadingWidth: lead.width,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(head.title,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            Text(widget.company.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: tokens.mutedForeground)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListPageHeader(
                  title: head.title,
                  // Built from the page's own name, never the spec title:
                  // that is an API action name, which read as "Manage get
                  // current user for this company".
                  description: head.description.isEmpty
                      ? 'Manage ${head.title.toLowerCase()} for this company'
                      : head.description,
                  icon: _headerIcon(head.title),
                  color: head.color,
                ),
                // The button shows wherever the web has one, with the web's
                // own label. If no form could be derived yet (an empty page
                // whose field list is unknown), it says so rather than
                // vanishing — a page with no records is exactly where someone
                // reaches for "add".
                if (acts.action != null || head.action != null) ...[
                  const SizedBox(height: 14),
                  PrimaryAction(
                    color: head.color,
                    label: acts.action ??
                        head.action ??
                        'Add ${head.title.toLowerCase()}',
                    onPressed: () {
                      final custom = customForms[spec.key];
                      if (custom != null) {
                        Navigator.of(context)
                            .push<bool>(MaterialPageRoute(
                              builder: (_) => custom(
                                  widget.session, widget.company, null),
                            ))
                            .then((saved) {
                              if (saved == true) _load();
                            });
                        return;
                      }
                      final def = _formDef;
                      if (def == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'This page has no records yet, so the fields '
                                'are unknown. Add the first one on the web.'),
                          ),
                        );
                        return;
                      }
                      Navigator.of(context)
                          .push<bool>(MaterialPageRoute(
                            builder: (_) => FormScreen(
                              def: def,
                              title: acts.action ??
                                  head.action ??
                                  'New ${head.title.toLowerCase()}',
                              company: widget.company,
                              session: widget.session,
                              spec: spec,
                            ),
                          ))
                          .then((saved) {
                            // A new record changes the list and the summary
                            // tiles above it, so reload rather than patching.
                            if (saved == true) _load();
                          });
                    },
                  ),
                ],
                for (final x in listExtras[spec.key] ?? const <ListExtra>[]) ...[
                  const SizedBox(height: 8),
                  AppButton(
                    label: x.label,
                    icon: x.icon,
                    variant: AppButtonVariant.outline,
                    fullWidth: true,
                    busy: x.run != null && _extraBusy,
                    onPressed: () => _runExtra(x),
                  ),
                ],
                const SizedBox(height: 12),
                AppSearchField(
                  hintText: 'Search ${head.title.toLowerCase()}…',
                  onChanged: (v) => setState(() => _query = v),
                ),
                const SizedBox(height: 10),
                ListActionRow(
                  onFilters: () async {
                    final defs = listFilters[spec.key];
                    if (defs == null) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('This page has no filters on the web either.')));
                      return;
                    }
                    final chosen = await showListFilters(
                      context,
                      session: widget.session,
                      company: widget.company,
                      filters: defs,
                      rows: _rows,
                      current: _filters,
                    );
                    if (chosen != null && mounted) setState(() => _filters = chosen);
                  },
                  onExport: () => ListExport.share(
                    context: context,
                    spec: spec,
                    rows: rows,
                    company: widget.company,
                  ),
                  onEmail: () => ListExport.share(
                    context: context,
                    spec: spec,
                    rows: rows,
                    company: widget.company,
                    email: true,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _Message(
                          icon: Icons.cloud_off,
                          title: 'Could not load',
                          detail: _error!,
                          onRetry: _load,
                        )
                      : rows.isEmpty
                          ? _Message(
                              icon: Icons.inbox_outlined,
                              title: _query.isEmpty && _filters.isEmpty
                                  ? 'Nothing here yet'
                                  : 'No matches',
                              detail: _query.isEmpty && _filters.isEmpty
                                  ? (spec.emptyMessage ??
                                      'No ${head.title.toLowerCase()} recorded for ${widget.company.name}.')
                                  : _query.isEmpty
                                      ? 'Nothing matches the filters. Reset them to see everything.'
                                      : 'Nothing matches “$_query”.',
                            )
                          : _isSingleReport(rows)
                          // A report that answers with one record — a P&L, a
                          // period summary — is not a list. Making the reader
                          // tap a card to reach the figures, then filing them
                          // under "Other fields", hid the whole point of the
                          // page. Show it where they landed.
                          ? ListView(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 14, 16, 40),
                              children: [
                                _RecordFields(spec: spec, row: rows.first),
                              ],
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
                              itemCount: rows.length + 1,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, i) {
                                if (i == 0) return _summaryBlock(rows.length);
                                final row = rows[i - 1];
                                return _RecordCard(
                                  spec: spec,
                                  row: row,
                                  accent: nav.bar,
                                  onTap: () => Navigator.of(context)
                                      .push<bool>(MaterialPageRoute(
                                        builder: (_) => RecordScreen(
                                          spec: spec,
                                          row: row,
                                          company: widget.company,
                                          session: widget.session,
                                        ),
                                      ))
                                      .then((changed) {
                                        if (changed == true) _load();
                                      }),
                                );
                              },
                            ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({
    required this.spec,
    required this.row,
    required this.accent,
    required this.onTap,
  });

  final PageSpec spec;
  final Map<String, dynamic> row;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    final titleKey = titleFieldIn(row, spec.titleField);
    final raw = row[titleKey];
    final asDate = raw is String && raw.length >= 10
        ? DateTime.tryParse(raw)
        : null;
    final title = formatValue(
        raw, asDate != null ? FieldKind.date : FieldKind.text);

    final rawStatus = spec.statusField == null
        ? _autoStatus(row)
        : row[spec.statusField];
    // An isActive-style flag reads as the web's Active / Inactive badge.
    final status = rawStatus is bool ? (rawStatus ? 'Active' : 'Inactive') : rawStatus;
    // Order of preference: a curated field list, then the columns the WEB
    // page shows for this route, then a guess from the row's shape. The
    // middle one is what makes a row read like the web's table instead of
    // whichever three fields happened to come back first.
    final webCols = webColumnFields(
      PageRegistry.designFor(spec.key)?.columns ?? const [],
      row,
      titleKey,
    );
    final subtitles = spec.subtitleFields.isNotEmpty
        ? spec.subtitleFields
        : (webCols.isNotEmpty ? webCols : autoSubtitles(row, titleKey));

    return Material(
      color: tokens.card,
      borderRadius: BorderRadius.circular(Dim.radiusLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(Dim.radiusLg),
        onTap: onTap,
        child: Container(
          // 48dp minimum, with even padding on all four sides.
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Dim.radiusLg),
            border: Border.all(color: tokens.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // A leading visual gives the eye something to anchor on when
              // scanning a long list. Date-keyed records get a calendar-style
              // day/month block; everything else gets an initial.
              _Leading(date: asDate, label: title, accent: accent),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title.isEmpty ? 'Untitled' : title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                            ),
                          ),
                        ),
                        if (status != null && '$status'.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          _StatusChip(value: '$status'),
                        ],
                      ],
                    ),
                    if (subtitles.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 14,
                        runSpacing: 5,
                        children: [
                          for (final f in subtitles)
                            if (row[f.key] != null)
                              RichText(
                                text: TextSpan(
                                  children: [
                                    TextSpan(
                                      text: '${f.label}  ',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: tokens.mutedForeground,
                                      ),
                                    ),
                                    TextSpan(
                                      text: formatValue(row[f.key], f.kind,
                                          suffix: f.suffix),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: tokens.cardForeground,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 2),
                child: Icon(Icons.chevron_right,
                    size: 18, color: tokens.mutedForeground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Calendar-style day/month block for dated records, otherwise an initial.
class _Leading extends StatelessWidget {
  const _Leading({required this.date, required this.label, required this.accent});

  final DateTime? date;
  final String label;
  final Color accent;

  static const _months = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];

  @override
  Widget build(BuildContext context) {
    final d = date?.toLocal();
    return Container(
      height: 40,
      width: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(Dim.radiusMd),
      ),
      child: d != null
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('${d.day}',
                    style: TextStyle(
                        fontSize: 15,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        color: accent)),
                const SizedBox(height: 1),
                Text(_months[d.month - 1],
                    style: TextStyle(
                        fontSize: 8,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .3,
                        color: accent.withValues(alpha: .85))),
              ],
            )
          : Text(
              label.isEmpty ? '?' : label.characters.first.toUpperCase(),
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: accent),
            ),
    );
  }
}

/// Most records carry a status under one of a few names; showing it is worth
/// more than a spec entry per page.
dynamic _autoStatus(Map<String, dynamic> row) {
  for (final k in ['status', 'state', 'paymentStatus', 'orderStatus']) {
    final v = row[k];
    if (v is String && v.isNotEmpty) return v;
  }
  return null;
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.value});
  final String value;

  @override
  Widget build(BuildContext context) {
    final s = statusStyle(value);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
          color: s.bg, borderRadius: BorderRadius.circular(Dim.radiusMd)),
      child: Text(value,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: s.fg)),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.detail,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return ListView(
      children: [
        const SizedBox(height: 80),
        Icon(icon, size: 44, color: tokens.mutedForeground),
        const SizedBox(height: 14),
        Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(detail,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, height: 1.45, color: tokens.mutedForeground)),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 16),
          Center(
            child: FilledButton.tonal(
                onPressed: onRetry, child: const Text('Retry')),
          ),
        ],
      ],
    );
  }
}

final _money = NumberFormat.currency(symbol: '₵', decimalDigits: 2);
final _plain = NumberFormat.decimalPattern();

/// Renders a raw API value for display.
String formatValue(dynamic v, FieldKind kind, {String? suffix}) {
  if (v == null) return '—';
  switch (kind) {
    case FieldKind.money:
      final n = v is num ? v : num.tryParse('$v');
      return n == null ? '$v' : _money.format(n);
    case FieldKind.number:
      final n = v is num ? v : num.tryParse('$v');
      final text = n == null ? '$v' : _plain.format(n);
      return suffix == null ? text : '$text $suffix';
    case FieldKind.date:
      final d = DateTime.tryParse('$v');
      return d == null ? '$v' : DateFormat('d MMM yyyy').format(d.toLocal());
    case FieldKind.boolean:
      return (v == true || '$v'.toLowerCase() == 'true') ? 'Yes' : 'No';
    case FieldKind.status:
    case FieldKind.text:
      return '$v';
  }
}

/// One summary card's resolved content.
class _Card {
  const _Card(this.label, this.value, this.sub, this.icon, this.color);
  final String label;
  final String value;
  final String? sub;
  final IconData icon;
  final Color? color;
}

/// A single record shown in place, for pages that answer with one row.
///
/// Reports (profit & loss, a period summary, company settings) are not lists,
/// and the figures are the page. This renders them the way the detail screen
/// does, minus the card-then-tap that hid them.
class _RecordFields extends StatelessWidget {
  const _RecordFields({required this.spec, required this.row});

  final PageSpec spec;
  final Map<String, dynamic> row;

  static String _humanise(String key) {
    final spaced = key.replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}');
    return spaced.isEmpty
        ? key
        : spaced[0].toUpperCase() + spaced.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final named = {
      spec.titleField,
      if (spec.statusField != null) spec.statusField!,
      ...spec.fields.map((f) => f.key),
    };
    final extras = row.keys
        .where((k) => !named.contains(k))
        .where((k) => row[k] != null && row[k] is! Map && row[k] is! List)
        .where((k) => !isPlumbingField(k, row[k]))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (spec.fields.isNotEmpty)
          FormSection(
            title: 'Details',
            color: SectionColor.slate,
            columns: 2,
            children: [
              for (final f in spec.fields)
                AppField(
                  label: f.label,
                  child: _PlainValue(
                      text: formatValue(row[f.key], f.kind, suffix: f.suffix)),
                ),
            ],
          ),
        if (extras.isNotEmpty) ...[
          if (spec.fields.isNotEmpty) const SizedBox(height: 14),
          FormSection(
            title: spec.fields.isEmpty ? 'Figures' : 'Other fields',
            color: SectionColor.slate,
            columns: 2,
            children: [
              for (final k in extras)
                AppField(
                  label: _humanise(k),
                  child: _PlainValue(text: '${row[k]}'),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _PlainValue extends StatelessWidget {
  const _PlainValue({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.muted,
        borderRadius: BorderRadius.circular(Dim.radiusMd),
      ),
      child: Text(text.isEmpty ? '—' : text,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
    );
  }
}
