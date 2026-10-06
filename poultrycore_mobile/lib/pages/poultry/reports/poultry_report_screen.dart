import 'dart:async';

import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/buttons.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../lookup_loader.dart';
import '../../shared/business_dates.dart';
import 'report_defs.dart';
import 'report_export.dart';
import 'report_format.dart';
import 'report_widgets.dart';
import 'reports_catalog_screen.dart';

/// Who is reading, for the export letterhead and the email default.
String? reportUser(Session s) => (s.username ?? '').isEmpty ? null : s.username;

String defaultEmailRecipient(Session s, Company c) {
  if ((c.email ?? '').contains('@')) return c.email!;
  final u = s.username ?? '';
  return u.contains('@') ? u : '';
}

/// "1/10/2026, 14:05" — when the report was generated, on the phone's clock
/// as the web's `new Date().toLocaleString()`.
String generatedNow() {
  final n = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${n.day}/${n.month}/${n.year}, ${two(n.hour)}:${two(n.minute)}';
}

/// One Advanced Poultry Report, as the web's `PoultryReportView`: the filter
/// bar, backend warnings and notes, the summary cards, the detail table (or
/// Revenue / Expenses scorecards for the P&L-by-flock report), the analysis
/// and breakdown, and CSV / Email / PDF.
class PoultryReportScreen extends StatefulWidget {
  const PoultryReportScreen({super.key, required this.session, required this.company, required this.slug});
  final Session session;
  final Company company;
  final String slug;

  @override
  State<PoultryReportScreen> createState() => _PoultryReportScreenState();
}

class _PoultryReportScreenState extends State<PoultryReportScreen> {
  late final PoultryReportDef def = poultryReportDefs[widget.slug]!;
  final ReportFilterValue _filter = ReportFilterValue.initial();
  FarmMoney _money = const FarmMoney();
  List<(int, String)> _flocks = const [];
  List<String> _customers = const [];
  final Set<String> _categories = {};
  Map<String, dynamic>? _data;
  bool _busy = true;
  String? _error;
  bool _downloading = false;
  late final String _generatedAt = generatedNow();
  Timer? _debounce;
  int _loadSeq = 0;

  ApiClient get _client => widget.session.farmClient;
  Map<String, String> get _scope => {'userId': widget.session.tokens.userId ?? '', 'farmId': widget.company.farmId};

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final money = FarmMoney.load(widget.session, widget.company);
    if (def.filters.flock) {
      _client.get('/api/Flock', query: _scope).then((res) {
        if (!mounted) return;
        setState(() => _flocks = [
              for (final f in LookupLoader.rowsIn(res))
                if (f is Map && f['flockId'] != null) ((f['flockId'] as num).toInt(), '${f['name'] ?? ''}'),
            ]);
      }).catchError((_) {});
    }
    if (def.filters.customer) {
      _client.get('/api/Customer', query: _scope).then((res) {
        if (!mounted) return;
        final names = {
          for (final c in LookupLoader.rowsIn(res))
            if (c is Map && '${c['name'] ?? ''}'.isNotEmpty) '${c['name']}',
        }.toList()
          ..sort();
        setState(() => _customers = names);
      }).catchError((_) {});
    }
    final m = await money;
    if (mounted) setState(() => _money = m);
    await _load();
  }

  Future<void> _load() async {
    final seq = ++_loadSeq;
    setState(() {
      _busy = true;
      _error = null;
    });
    final f = _filter;
    try {
      final res = await _client.get('/api/poultry/reports/${widget.slug}', query: {
        ..._scope,
        'startDate': f.fromDate,
        'endDate': f.toDate,
        'datePreset': rangeToPeriod(f.fromDate, f.toDate),
        if (def.filters.flock && f.flockId != null) 'flockId': '${f.flockId}',
        if (def.filters.customer && (f.customerName ?? '').isNotEmpty) 'customerName': f.customerName,
        if (def.filters.supplier && (f.supplierName ?? '').isNotEmpty) 'supplierName': f.supplierName,
        if (def.filters.category && (f.category ?? '').isNotEmpty) 'category': f.category,
        if (def.filters.includeClosedFlocks && f.includeClosedFlocks) 'includeClosedFlocks': 'true',
      });
      if (!mounted || seq != _loadSeq) return;
      final data = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      setState(() {
        _data = data;
        // Accumulated, so picking a category never leaves it the only option.
        if (def.filters.category) {
          for (final r in _rows(data)) {
            final c = '${r['category'] ?? ''}'.trim();
            if (c.isNotEmpty) _categories.add(c);
          }
        }
      });
    } on ApiException catch (e) {
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _error = e.message.isEmpty ? 'Could not load the report.' : e.message;
        _data = null;
      });
    } finally {
      if (mounted && seq == _loadSeq) setState(() => _busy = false);
    }
  }

  /// Re-fetch after a filter change, debounced a touch as the web does.
  void _changed() {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _load);
  }

  void _reset() {
    final r = defaultReportRange();
    _filter
      ..fromDate = r.from
      ..toDate = r.to
      ..flockId = null
      ..customerName = null
      ..supplierName = null
      ..category = null
      ..includeClosedFlocks = false;
    _changed();
  }

  static List<Map> _rows(Map? data) => [for (final r in (data?['rows'] is List ? data!['rows'] as List : const [])) if (r is Map) r];

  FmtCtx get _ctx => FmtCtx(_money);
  FmtCtx get _cardCtx => FmtCtx(_money, withSymbol: true);

  List<SummaryCardData> get _cards {
    final s = _data?['summary'];
    if (s is! Map) return const [];
    return [for (final c in def.cards) (label: c.label, value: c.value(s, _cardCtx), accent: c.accentFor(s), note: c.note)];
  }

  /// The selections made, in the words seen on screen.
  List<(String, String)> get _filtersUsed {
    final f = _filter;
    final preset = rangeToPeriod(f.fromDate, f.toDate);
    return [
      if (preset != 'custom') ('Period', periodLabel(preset)),
      if (def.filters.flock && f.flockId != null)
        ('Flock', _flocks.where((x) => x.$1 == f.flockId).map((x) => x.$2).firstOrNull ?? '#${f.flockId}'),
      if (def.filters.customer && f.customerName != null) ('Customer', f.customerName!),
      if (def.filters.supplier && f.supplierName != null) ('Supplier', f.supplierName!),
      if (def.filters.category && f.category != null) ('Category', f.category!),
      if (def.filters.includeClosedFlocks && f.includeClosedFlocks) ('Closed flocks', 'Included'),
    ];
  }

  ReportDocument _document() {
    final rows = _rows(_data);
    return ReportDocument(
      title: def.title,
      filename: 'poultry-${widget.slug}',
      farmName: widget.company.name,
      fromDate: _filter.fromDate,
      toDate: _filter.toDate,
      generatedBy: reportUser(widget.session),
      currencyLabel: _money.label,
      filters: _filtersUsed,
      cards: [for (final c in _cards) (label: c.label, value: c.value, accent: c.accent, note: c.note)],
      landscape: def.columns.length > 8,
      sections: [
        ReportSection(
          columns: [for (final c in def.columns) ReportColumn(c.header, right: c.right)],
          rows: [
            for (final r in rows) [for (final c in def.columns) c.cell(r, _ctx)],
          ],
          totals: reportTotalsRow(def.columns, rows, _ctx),
        ),
      ],
    );
  }

  Future<void> _export(Future<void> Function(ReportDocument) run, {bool pdf = false}) async {
    if (pdf) setState(() => _downloading = true);
    try {
      await run(_document());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed. $e')));
    } finally {
      if (mounted && pdf) setState(() => _downloading = false);
    }
  }

  void _openCatalog() => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PoultryReportsCatalogScreen(session: widget.session, company: widget.company),
      ));

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry/reports/${widget.slug}');
    final data = _data;
    final rows = _rows(data);
    final hasData = data != null && rows.isNotEmpty;
    final summary = data?['summary'] is Map ? data!['summary'] as Map : null;
    List<String> lines(String k) => [for (final x in (data?[k] is List ? data![k] as List : const [])) '$x'];

    return Scaffold(
      backgroundColor: slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: Text(def.title, overflow: TextOverflow.ellipsis)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
          children: [
            Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.spaceBetween, children: [
              AppButton(
                label: 'Poultry reports',
                icon: Icons.arrow_back,
                variant: AppButtonVariant.outline,
                size: AppButtonSize.sm,
                onPressed: _openCatalog,
              ),
              ReportExportButtons(
                onCsv: () => _export(ReportExport.shareCsv),
                onEmail: () => showReportEmailDialog(
                  context,
                  client: _client,
                  document: _document,
                  defaultRecipient: defaultEmailRecipient(widget.session, widget.company),
                ),
                onPdf: () => _export(ReportExport.sharePdf, pdf: true),
                busy: _downloading,
                disabled: _busy || !hasData,
              ),
            ]),
            const SizedBox(height: 12),
            ReportCard(children: [
              ReportLetterhead(
                farmName: widget.company.name.isEmpty ? 'Poultry farm' : widget.company.name,
                title: def.title,
                description: def.description,
                lines: [
                  ('Period', '${_filter.fromDate} → ${_filter.toDate}'),
                  ('Currency', _money.label),
                  ('Generated', _generatedAt),
                  ('Records', fmtNum(rows.length, 0)),
                ],
              ),
              ReportFilterPanel(
                value: _filter,
                onChanged: _changed,
                onReset: _reset,
                show: def.filters,
                flocks: _flocks,
                customers: _customers,
                categories: [..._categories]..sort(),
              ),
              ReportNotices(lines: lines('warnings'), warning: true),
              ReportNotices(lines: lines('notes'), warning: false),
              if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: ReportError(_error!, onRetry: _load)),
              if (_busy)
                const ReportLoading()
              else if (!hasData)
                const ReportEmpty()
              else ...[
                SummaryCards(_cards),
                if (def.tableAsCards) ..._cardRows(rows) else reportTableFor(def.columns, rows, _ctx),
                if (def.analysis != null && summary != null)
                  ReportAnalysis(title: def.analysis!.title, items: def.analysis!.items(summary, (n) => _money(n))),
                if (def.breakdown != null && summary != null && !def.tableAsCards)
                  ReportBreakdown(groups: def.breakdown!, summary: summary, ctx: _cardCtx),
              ],
            ]),
          ],
        ),
      ),
    );
  }

  /// The P&L reports' rows as a Revenue Details card and an Expenses details
  /// card each, labelled by [PoultryReportDef.cardRowLabel]'s value.
  List<Widget> _cardRows(List<Map> rows) {
    final labelHeader = def.cardRowLabel;
    bool isRevenue(String h) => h.contains('rev') || h.contains('sales');
    final cols = [for (final c in def.columns) if (c.header != labelHeader) c];
    ({({String label, String value})? headline, List<({String label, String value})> items}) pick(
        List<({String label, String value})> arr, String kw) {
      final i = arr.indexWhere((x) => x.label.toLowerCase().contains(kw));
      final idx = i == -1 ? arr.length - 1 : i;
      return (headline: arr.isEmpty ? null : arr[idx], items: [for (final (n, x) in arr.indexed) if (n != idx) x]);
    }

    return [
      for (final row in rows)
        () {
          List<({String label, String value})> build(bool Function(String) keep) => [
                for (final c in cols)
                  if (keep(c.header.toLowerCase())) (label: c.header, value: c.cell(row, _cardCtx)),
              ];
          final revenue = pick(build(isRevenue), 'total revenue');
          final expense = pick(build((h) => !isRevenue(h) && !h.contains('net profit')), 'total cost');
          final label = labelHeader == null ? null : def.columns.firstWhere((c) => c.header == labelHeader).cell(row, _cardCtx);
          Widget card(String title, ({String label, String value})? headline, List<({String label, String value})> items,
                  Color rail, Color headColor) =>
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: slate200), borderRadius: BorderRadius.circular(12)),
                clipBehavior: Clip.antiAlias,
                child: Stack(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text(title.toUpperCase(), style: const TextStyle(fontSize: 11, letterSpacing: .6, color: slate500)),
                      const SizedBox(height: 4),
                      Text(headline?.value ?? '—', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600, color: headColor)),
                      const Divider(height: 20, color: slate100),
                      for (final it in items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Row(children: [
                            Expanded(child: Text(it.label, style: const TextStyle(fontSize: 13, color: slate500))),
                            Text(it.value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: slate800)),
                          ]),
                        ),
                    ]),
                  ),
                  Positioned(left: 0, top: 0, bottom: 0, width: 4, child: ColoredBox(color: rail)),
                ]),
              );
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (label != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: slate800)),
                ),
              card('Revenue Details', revenue.headline, revenue.items, emerald500, emerald700),
              card('Expenses details', expense.headline, expense.items, rose500, slate900),
            ]),
          );
        }(),
    ];
  }
}
