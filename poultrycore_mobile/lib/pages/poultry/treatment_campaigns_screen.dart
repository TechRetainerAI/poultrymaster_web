import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../shared/business_dates.dart';
import '../shared/company_clock.dart';
import '../shared/reason_dialog.dart';
import 'poultry_links.dart';
import 'reports/report_format.dart';
import 'sales/balances_widgets.dart' show LoadingLine;
import 'trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import 'trackers/tracker_widgets.dart';
import 'treatment_campaign_logic.dart';

/// Poultry → Tools → Treatment Campaigns, as `app/poultry-treatment-campaigns/page.tsx`
/// (migration 339): one medication, vaccine or treatment given to many flocks
/// over one or more days. The web's three views — the list, ?new=1 and ?id= —
/// are three screens here.
///
/// Recording a day adds a medication line to each flock's production record for
/// that day, so stock, costing and the expense come out exactly as if each flock
/// had been edited by hand. Creating a campaign moves nothing.

const _violet100 = Color(0xFFEDE9FE);
const _violet600 = Color(0xFF7C3AED);
const _violet700 = Color(0xFF6D28D9);
const _sky700 = Color(0xFF0369A1);

/// The API (TreatmentCampaignsController). farmId in the query on reads and in
/// the body on writes, as the web sends it.
class TreatmentCampaignApi {
  TreatmentCampaignApi(this.session, this.company);
  final Session session;
  final Company company;
  ApiClient get _c => session.farmClient;
  String get farmId => company.farmId;
  static const base = '/api/Poultry/treatment-campaigns';
  Map<String, dynamic> get _q => {'farmId': farmId};

  Future<Object?> products() => _c.get('$base/products', query: _q);
  Future<Object?> flockOptions() => _c.get('$base/flock-options', query: _q);
  Future<Object?> list() => _c.get(base, query: _q);
  Future<Object?> get(int id) => _c.get('$base/$id', query: _q);
  Future<Object?> create(Map<String, dynamic> input) => _c.post(base, body: {...input, 'farmId': farmId});
  Future<Object?> complete(int id) => _c.put('$base/$id/completion', body: {'farmId': farmId});
  Future<Object?> cancel(int id, String reason) => _c.put('$base/$id/cancellation', body: {'farmId': farmId, 'reason': reason});
  Future<Object?> flocks(int id) => _c.get('$base/$id/flocks', query: _q);
  Future<Object?> dayGrid(int id, String date) => _c.get('$base/$id/day-grid', query: {..._q, 'date': date});
  Future<Object?> days(int id) => _c.get('$base/$id/days', query: _q);
  Future<Object?> dayLines(int postId) => _c.get('$base/days/$postId/lines', query: _q);
  Future<Object?> postDay(int id, Map<String, dynamic> input) => _c.post('$base/$id/days', body: {...input, 'farmId': farmId});
  Future<Object?> reverseDay(int postId, String reason) =>
      _c.post('$base/days/$postId/reversal', body: {'farmId': farmId, 'reason': reason});
}

/// 409 InsufficientStock, as the web's InsufficientMedicationError.
bool _insufficient(ApiException e) => e.statusCode == 409 && e.body is Map && (e.body as Map)['code'] == 'InsufficientStock';

String _day(Object? v) {
  final s = tStr(v);
  return s.length >= 10 ? s.substring(0, 10) : s;
}

String _plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

/// The page title: violet pill tile, title, blurb, and "All campaigns" back.
Widget _title(BuildContext context, String title, String sub, {bool back = false}) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: _violet100, borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.medication_outlined, size: 20, color: _violet700),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (back)
              InkWell(
                onTap: () => Navigator.of(context).maybePop(),
                child: const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.arrow_back, size: 14, color: TColors.slate500),
                    SizedBox(width: 4),
                    Text('All campaigns', style: TextStyle(fontSize: 12, color: TColors.slate500)),
                  ]),
                ),
              ),
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: TColors.slate900)),
            if (sub.isNotEmpty) Text(sub, style: const TextStyle(fontSize: 13, color: TColors.slate600)),
          ]),
        ),
      ],
    );

Widget campaignStatusBadge(Object? status) {
  final (border, bg, fg) = campaignStatusStyle(status);
  return TBadge(campaignStatusLabel(status), bg: bg, fg: fg, border: border);
}

Widget _stat(String label, String value, {bool bad = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, letterSpacing: .4, color: TColors.slate500)),
        Text(value, style: TextStyle(fontWeight: FontWeight.w600, color: bad ? TColors.rose700 : TColors.slate900)),
      ]),
    );

Widget _statGrid(List<Widget> tiles) => LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - 8) / 2;
      return Wrap(spacing: 8, runSpacing: 8, children: [for (final t in tiles) SizedBox(width: w, child: t)]);
    });

Widget _field(String label, Widget child, {String? hint}) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
      const SizedBox(height: 4),
      child,
      if (hint != null) ...[
        const SizedBox(height: 2),
        Text(hint, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
      ],
    ]);

Widget _whiteCard(Widget child, {EdgeInsets padding = const EdgeInsets.all(16)}) => Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: TColors.slate200),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1))],
      ),
      child: child,
    );

Widget _link(String text, VoidCallback onTap, {Color color = _sky700, double size = 12}) => InkWell(
      onTap: onTap,
      child: Text(text, style: TextStyle(fontSize: size, color: color, decoration: TextDecoration.underline)),
    );

/// The pinned bar at the foot of New campaign and Record treatment.
Widget _stickyBar(Widget message, Widget button) => Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: const BoxDecoration(color: Color(0xF2FFFFFF), border: Border(top: BorderSide(color: TColors.slate200))),
      child: SafeArea(
        top: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          message,
          const SizedBox(height: 8),
          button,
        ]),
      ),
    );

ButtonStyle get _violetButton =>
    FilledButton.styleFrom(backgroundColor: _violet600, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(46));

// =============================================================================
// List
// =============================================================================

class TreatmentCampaignsScreen extends StatefulWidget {
  const TreatmentCampaignsScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<TreatmentCampaignsScreen> createState() => _TreatmentCampaignsScreenState();
}

class _TreatmentCampaignsScreenState extends State<TreatmentCampaignsScreen> {
  late final _api = TreatmentCampaignApi(widget.session, widget.company);
  List<Map>? _rows;
  String _tab = 'active';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _api.list();
      if (mounted) setState(() => _rows = rowsOf(r));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _rows = []);
      trackerToast(context, 'Could not load campaigns', description: e.message, error: true);
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    _load();
  }

  void _newCampaign() => _open(NewTreatmentCampaignScreen(session: widget.session, company: widget.company));
  void _campaign(Map c) => _open(TreatmentCampaignScreen(
      session: widget.session, company: widget.company, campaignId: tIntOrNull(c['poultryTreatmentCampaignId']) ?? 0));

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-treatment-campaigns');
    final rows = _rows;
    final shown = [
      for (final c in rows ?? const <Map>[])
        if (_tab == 'all' || c['status'] == 'Scheduled' || c['status'] == 'InProgress') c,
    ];
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Treatment Campaigns')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            _title(context, 'Treatment Campaigns',
                "Give one medication or vaccine to many flocks, over one day or several. Each day you record lands on each flock's production record, exactly as if entered one by one."),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: _violet600, foregroundColor: Colors.white),
                onPressed: _newCampaign,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New campaign'),
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'active', label: Text('Scheduled & in progress')),
                ButtonSegment(value: 'all', label: Text('All')),
              ],
              selected: {_tab},
              onSelectionChanged: (s) => setState(() => _tab = s.first),
            ),
            const SizedBox(height: 12),
            _whiteCard(
              padding: EdgeInsets.zero,
              rows == null
                  ? const Padding(padding: EdgeInsets.all(16), child: LoadingLine('Loading…'))
                  : shown.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                            Text('${_tab == 'active' ? 'No campaign is scheduled or running.' : 'No treatment campaigns yet.'} ',
                                style: const TextStyle(fontSize: 13, color: TColors.slate500)),
                            _link('Start one', _newCampaign, color: _violet700, size: 13),
                            const Text('.', style: TextStyle(fontSize: 13, color: TColors.slate500)),
                          ]),
                        )
                      : TrackerTable(
                          columns: const [
                            TCol('Campaign', width: 190),
                            TCol('Product', width: 140),
                            TCol('Dates', width: 220),
                            TCol('Flocks', right: true, width: 70),
                            TCol('Days recorded', right: true, width: 110),
                            TCol('Withdrawal', width: 220),
                            TCol('Status', width: 110),
                          ],
                          rows: [
                            for (final c in shown)
                              [
                                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  InkWell(
                                    onTap: () => _campaign(c),
                                    child: Text(tStr(c['name']), style: const TextStyle(fontWeight: FontWeight.w500, color: _violet700)),
                                  ),
                                  if (tStr(c['reason']).isNotEmpty)
                                    Text(tStr(c['reason']), style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                                ]),
                                cellText(tStr(c['itemName']).isEmpty ? '—' : tStr(c['itemName'])),
                                cellText('${formatLongDate(_day(c['startDate']))}'
                                    '${tNum(c['plannedDays']) > 1 ? ' – ${formatLongDate(_day(c['endDate']))}' : ''}'),
                                Align(alignment: Alignment.centerRight, child: Text('${tNum(c['flockCount']).toInt()}')),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Text('${tNum(c['postedDays']).toInt()} of ${tNum(c['plannedDays']).toInt()}'),
                                ),
                                _withdrawalCell(c),
                                Align(alignment: Alignment.centerLeft, child: campaignStatusBadge(c['status'])),
                              ],
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _withdrawalCell(Map c) {
    final egg = tStr(c['eggWithdrawalUntil']);
    final meat = tStr(c['meatWithdrawalUntil']);
    if (egg.isEmpty && meat.isEmpty) return const Text('—', style: TextStyle(color: TColors.slate400));
    return Text(
      '${egg.isNotEmpty ? 'Eggs until ${formatLongDate(_day(egg))}' : ''}'
      '${egg.isNotEmpty && meat.isNotEmpty ? ' · ' : ''}'
      '${meat.isNotEmpty ? 'Meat until ${formatLongDate(_day(meat))}' : ''}',
      style: const TextStyle(fontSize: 12),
    );
  }
}

// =============================================================================
// New campaign
// =============================================================================

class NewTreatmentCampaignScreen extends StatefulWidget {
  const NewTreatmentCampaignScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<NewTreatmentCampaignScreen> createState() => _NewTreatmentCampaignScreenState();
}

class _NewTreatmentCampaignScreenState extends State<NewTreatmentCampaignScreen> {
  late final _api = TreatmentCampaignApi(widget.session, widget.company);
  List<Map>? _products;
  List<Map>? _flocks;
  final _name = TextEditingController();
  int? _itemId;
  final _reason = TextEditingController();
  String _start = '', _end = '';
  final _instructions = TextEditingController();
  final _dose = TextEditingController();
  String _basis = '';

  /// Whether the dose figures are the product's saved ones, untouched.
  bool _fromProduct = false;
  final _egg = TextEditingController();
  final _meat = TextEditingController();
  final _withdrawalNotes = TextEditingController();
  final _notes = TextEditingController();
  bool _saveDefault = false;
  final Map<int, bool> _picked = {};
  final Map<int, TextEditingController> _flockDose = {};
  final Map<int, TextEditingController> _flockNotes = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    companyToday(widget.session, widget.company).then((t) {
      if (mounted) {
        setState(() {
          _start = t;
          _end = t;
        });
      }
    });
    _api.products().then((p) {
      if (mounted) setState(() => _products = [for (final x in rowsOf(p)) if (x['isActive'] == true) x]);
    }, onError: (Object _) {
      if (mounted) setState(() => _products = []);
    });
    _api.flockOptions().then((f) {
      if (mounted) setState(() => _flocks = rowsOf(f));
    }, onError: (Object _) {
      if (mounted) setState(() => _flocks = []);
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _reason, _instructions, _dose, _egg, _meat, _withdrawalNotes, _notes, ..._flockDose.values, ..._flockNotes.values]) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _doseFor(int id) => _flockDose.putIfAbsent(id, TextEditingController.new);
  TextEditingController _notesFor(int id) => _flockNotes.putIfAbsent(id, TextEditingController.new);

  Map? get _product {
    for (final p in _products ?? const <Map>[]) {
      if (tIntOrNull(p['poultryRawMaterialItemId']) == _itemId) return p;
    }
    return null;
  }

  /// Choosing a product brings in the farm's OWN saved figures for it — or
  /// nothing, if none were ever saved.
  void _chooseProduct(int id) {
    setState(() {
      _itemId = id;
      final p = _product;
      _dose.text = p?['doseQuantity'] != null ? jsNumText(p!['doseQuantity']) : '';
      _basis = p != null && isDoseBasis(p['doseBasis']) ? tStr(p['doseBasis']) : '';
      _fromProduct = p?['doseQuantity'] != null;
      _egg.text = p?['eggWithdrawalDays'] != null ? jsNumText(p!['eggWithdrawalDays']) : '';
      _meat.text = p?['meatWithdrawalDays'] != null ? jsNumText(p!['meatWithdrawalDays']) : '';
      _withdrawalNotes.text = tStr(p?['withdrawalNotes']);
      _saveDefault = false;
    });
  }

  /// '' → null; a whole number ≥ 0 → it; anything else → NaN.
  num? _intDays(String t) {
    if (t.trim().isEmpty) return null;
    final n = num.tryParse(t.trim());
    return n != null && n == n.roundToDouble() && n >= 0 ? n.toInt() : double.nan;
  }

  List<Map> get _selected => [for (final f in _flocks ?? const <Map>[]) if (_picked[tIntOrNull(f['flockId'])] == true) f];

  String? _problem(num? dose, int days, num? egg, num? meat) {
    final selected = _selected;
    if (_name.text.trim().isEmpty) return 'Give the campaign a name.';
    if (_itemId == null) return 'Choose the medication product.';
    if (days == 0) return 'The end date is before the start date.';
    if (days > 366) return 'A campaign can run for at most a year.';
    if ((_dose.text.trim().isNotEmpty && dose == null) || (dose != null && dose <= 0)) return 'The dose must be a number above 0.';
    if (dose == null || _basis.isEmpty) {
      return 'A dose needs both an amount and what it is per (per bird, per 1,000 birds or per flock).';
    }
    if ((egg?.isNaN ?? false) || (meat?.isNaN ?? false)) return 'Withdrawal days must be whole numbers.';
    if (selected.isEmpty) return 'Choose at least one flock.';
    if (selected.any((f) {
      final t = _doseFor(tIntOrNull(f['flockId']) ?? 0).text;
      return t.trim().isNotEmpty && (parseQty(t) ?? 0) == 0;
    })) {
      return "A flock's own dose must be a number above 0.";
    }
    return null;
  }

  Future<void> _save(num? dose, num? egg, num? meat) async {
    setState(() => _saving = true);
    try {
      final r = await _api.create({
        'name': _name.text.trim(),
        'itemId': _itemId,
        'reason': _reason.text.trim().isEmpty ? null : _reason.text.trim(),
        'startDate': _start,
        'endDate': _end,
        'doseInstructions': _instructions.text.trim().isEmpty ? null : _instructions.text.trim(),
        'doseQuantity': dose,
        'doseBasis': _basis.isEmpty ? null : _basis,
        'doseSource': _fromProduct ? 'Product' : 'User',
        'eggWithdrawalDays': egg,
        'meatWithdrawalDays': meat,
        'withdrawalNotes': _withdrawalNotes.text.trim().isEmpty ? null : _withdrawalNotes.text.trim(),
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'saveAsProductDefault': _saveDefault,
        'flocks': [
          for (final f in _selected)
            {
              'flockId': tIntOrNull(f['flockId']),
              'doseQuantity': parseQty(_doseFor(tIntOrNull(f['flockId']) ?? 0).text),
              'notes': _notesFor(tIntOrNull(f['flockId']) ?? 0).text.trim().isEmpty ? null : _notesFor(tIntOrNull(f['flockId']) ?? 0).text.trim(),
            },
        ],
      });
      if (!mounted) return;
      trackerToast(context, 'Campaign created', description: "Nothing has left stock yet — record each day's treatment as it is given.");
      final id = tIntOrNull(r is Map ? r['poultryTreatmentCampaignId'] : null) ?? 0;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => TreatmentCampaignScreen(session: widget.session, company: widget.company, campaignId: id),
      ));
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Not created', description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-treatment-campaigns');
    final product = _product;
    final unit = tStr(product?['unitOfMeasure']);
    final dose = parseQty(_dose.text);
    final days = daysInclusive(_start, _end);
    final selected = _selected;
    num? sugFor(Map f) {
      final own = parseQty(_doseFor(tIntOrNull(f['flockId']) ?? 0).text);
      return suggestQuantity(own ?? dose, _basis.isEmpty ? null : _basis, f['birds']);
    }

    final perDay = selected.fold<num>(0, (s, f) => s + (sugFor(f) ?? 0));
    final anySuggestion = selected.any((f) => sugFor(f) != null);
    final planTotal = perDay * days;
    final egg = _intDays(_egg.text);
    final meat = _intDays(_meat.text);
    final problem = _problem(dose, days, egg, meat);
    final flocks = _flocks;
    final allPicked = (flocks ?? const []).isNotEmpty && flocks!.every((f) => _picked[tIntOrNull(f['flockId'])] == true);
    final available = tNum(product?['availableQuantity']);
    final products = _products;

    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('New treatment campaign')),
      body: Column(children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
            children: [
              _title(context, 'New treatment campaign',
                  'Plan a treatment for several flocks. Creating it moves no stock — each day is recorded separately, when it is given.',
                  back: true),
              const SizedBox(height: 14),
              _whiteCard(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _field('Campaign name',
                    AppInput(controller: _name, hintText: 'e.g. Coccidiosis — Houses 2 to 4', onChanged: (_) => setState(() {}))),
                const SizedBox(height: 12),
                _field(
                  'Medication / product',
                  AppSelect<int>(
                    value: _itemId,
                    hintText: products == null ? 'Loading…' : (products.isNotEmpty ? 'Choose a product' : 'No medication items in Raw Materials'),
                    items: [
                      for (final p in products ?? const <Map>[])
                        AppSelectItem(
                          value: tIntOrNull(p['poultryRawMaterialItemId']) ?? 0,
                          label: '${tStr(p['itemName'])} — ${fmtQty(tNum(p['availableQuantity']), p['unitOfMeasure'])} in stock',
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) _chooseProduct(v);
                    },
                  ),
                ),
                const SizedBox(height: 12),
                _field('Reason', AppInput(controller: _reason, hintText: 'e.g. Vet diagnosis, routine vaccination')),
                const SizedBox(height: 12),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: _field(
                      'Start date',
                      AppDateField(
                        value: DateTime.tryParse(_start),
                        onChanged: (d) {
                          if (d == null) return;
                          setState(() {
                            _start = isoDay(d);
                            if (_end.compareTo(_start) < 0) _end = _start;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _field(
                      'End date',
                      AppDateField(
                        value: DateTime.tryParse(_end),
                        firstDate: DateTime.tryParse(_start),
                        onChanged: (d) {
                          if (d != null) setState(() => _end = isoDay(d));
                        },
                      ),
                      hint: days > 0 ? _plural(days, 'day') : '—',
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                _field('Dose / usage information (as on the label or from the vet)',
                    AppTextarea(controller: _instructions, rows: 2, hintText: 'e.g. 1 ml per litre of drinking water for 5 days')),
                const SizedBox(height: 12),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: _field(
                      'Dose amount${unit.isNotEmpty ? ' ($unit)' : ''}',
                      AppNumberInput(
                        controller: _dose,
                        hintText: '',
                        allowDecimal: true,
                        onChanged: (_) => setState(() => _fromProduct = false),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _field(
                      'Per',
                      AppSelect<String>(
                        value: _basis.isEmpty ? null : _basis,
                        hintText: 'Choose',
                        items: [for (final (k, l, _) in doseBases) AppSelectItem(value: k, label: l)],
                        onChanged: (v) => setState(() {
                          _basis = isDoseBasis(v) ? v! : '';
                          _fromProduct = false;
                        }),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: _field('Egg withdrawal (days)',
                        AppNumberInput(controller: _egg, hintText: '', onChanged: (_) => setState(() {}))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _field('Meat withdrawal (days)',
                        AppNumberInput(controller: _meat, hintText: '', onChanged: (_) => setState(() {}))),
                  ),
                ]),
                const SizedBox(height: 6),
                Text(
                  product != null && _fromProduct
                      ? 'Dose and withdrawal filled from your saved settings for ${tStr(product['itemName'])}. Change them for this campaign if needed.'
                      : "Enter the dose from the product label or your vet's instructions — the system has no built-in doses or withdrawal periods.",
                  style: const TextStyle(fontSize: 12, color: TColors.slate500),
                ),
                const SizedBox(height: 12),
                _field('Withdrawal notes', AppInput(controller: _withdrawalNotes, hintText: 'e.g. Per label, eggs discarded')),
                const SizedBox(height: 12),
                _field('Notes', AppInput(controller: _notes)),
                if (product != null) ...[
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () => setState(() => _saveDefault = !_saveDefault),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Checkbox(value: _saveDefault, onChanged: (v) => setState(() => _saveDefault = v == true)),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            "Save this dose and withdrawal as ${tStr(product['itemName'])}'s default for future campaigns",
                            style: const TextStyle(fontSize: 13, color: TColors.slate700),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ],
              ])),
              const SizedBox(height: 14),
              _whiteCard(
                padding: EdgeInsets.zero,
                Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(4, 4, 12, 8),
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: TColors.slate100))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Checkbox(
                          value: allPicked,
                          onChanged: (v) => setState(() {
                            _picked.clear();
                            if (v == true) {
                              for (final f in flocks ?? const <Map>[]) {
                                _picked[tIntOrNull(f['flockId']) ?? 0] = true;
                              }
                            }
                          }),
                        ),
                        Expanded(
                          child: Text('Flocks (${selected.length} selected)',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate800)),
                        ),
                      ]),
                      const Padding(
                        padding: EdgeInsets.only(left: 12),
                        child: Text(
                          "Open flocks only. Give a flock its own dose only when it differs from the campaign's.",
                          style: TextStyle(fontSize: 12, color: TColors.slate500),
                        ),
                      ),
                    ]),
                  ),
                  if (flocks == null)
                    const Padding(padding: EdgeInsets.all(12), child: LoadingLine('Loading flocks…'))
                  else if (flocks.isEmpty)
                    const Padding(padding: EdgeInsets.all(12), child: Text('No open flocks.', style: TextStyle(color: TColors.slate500)))
                  else
                    for (final f in flocks) _flockPickRow(f, dose, unit, sugFor(f)),
                ]),
              ),
              if (product != null && anySuggestion) ...[
                const SizedBox(height: 14),
                _statGrid([
                  _stat('In stock now', fmtQty(available, unit)),
                  _stat('Suggested per day', fmtQty(perDay, unit)),
                  _stat('Suggested for ${_plural(days, 'day')}', fmtQty(planTotal, unit), bad: planTotal > available),
                  _stat('Short by', planTotal > available ? fmtQty(planTotal - available, unit) : '—', bad: planTotal > available),
                ]),
              ],
            ],
          ),
        ),
        _stickyBar(
          Text(
            problem ?? '${_plural(selected.length, 'flock')}, ${_plural(days, 'day')}. No stock moves until a day is recorded.',
            style: TextStyle(fontSize: 13, color: problem != null ? TColors.slate500 : TColors.slate600),
          ),
          FilledButton(
            style: _violetButton,
            onPressed: problem != null || _saving ? null : () => _save(dose, egg, meat),
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Create campaign'),
          ),
        ),
      ]),
    );
  }

  Widget _flockPickRow(Map f, num? dose, String unit, num? sug) {
    final id = tIntOrNull(f['flockId']) ?? 0;
    final on = _picked[id] == true;
    final muted = on ? TColors.slate900 : TColors.slate500;
    return Container(
      key: ValueKey('flock-$id'),
      padding: const EdgeInsets.fromLTRB(4, 6, 12, 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: TColors.slate100))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Checkbox(value: on, onChanged: (v) => setState(() => _picked[id] = v == true)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tStr(f['flockName']), style: TextStyle(fontWeight: FontWeight.w500, color: muted)),
              Text(
                'House/Pen: ${tStr(f['houseName']).isEmpty ? '—' : tStr(f['houseName'])} · Bird count: ${f['birds'] == null ? '—' : fmtNum(tNum(f['birds']), 0)}',
                style: const TextStyle(fontSize: 12, color: TColors.slate500),
              ),
              if (on) Text('Suggested / day: ${fmtQty(sug, unit)}', style: const TextStyle(fontSize: 12, color: TColors.slate600)),
            ]),
          ),
        ]),
        if (on)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 120,
                child: _field(
                  'Own dose${unit.isNotEmpty ? ' ($unit)' : ''}',
                  AppNumberInput(
                    key: ValueKey('own-dose-$id'),
                    controller: _doseFor(id),
                    allowDecimal: true,
                    hintText: dose != null ? jsNumText(dose) : '',
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _field('Notes', AppInput(key: ValueKey('flock-notes-$id'), controller: _notesFor(id)))),
            ]),
          ),
      ]),
    );
  }
}

/// A number as JavaScript's String(n) writes it: 2, 0.5.
String jsNumText(Object? v) {
  final n = tNum(v);
  if (n == n.roundToDouble()) return n.toInt().toString();
  return n.toString();
}

// =============================================================================
// One campaign
// =============================================================================

class TreatmentCampaignScreen extends StatefulWidget {
  const TreatmentCampaignScreen({super.key, required this.session, required this.company, required this.campaignId});
  final Session session;
  final Company company;
  final int campaignId;

  @override
  State<TreatmentCampaignScreen> createState() => _TreatmentCampaignScreenState();
}

class _TreatmentCampaignScreenState extends State<TreatmentCampaignScreen> {
  late final _api = TreatmentCampaignApi(widget.session, widget.company);
  int get _id => widget.campaignId;
  Map? _c;
  String? _error;
  Map? _product;
  List<Map> _flocks = [];
  List<Map> _days = [];
  String _tab = 'record';
  String? _date;
  List<Map>? _grid;
  bool _gridLoading = false;
  final Map<int, TextEditingController> _actual = {};
  final Map<int, TextEditingController> _lineNotes = {};
  bool _posting = false;
  int? _openDay;
  final Map<int, List<Map>> _dayLines = {};
  bool _busy = false;
  FarmMoney _money = const FarmMoney();
  Duration _offset = DateTime.now().timeZoneOffset;

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _money = m);
    });
    CompanyClock.load(widget.session, widget.company).then((c) {
      if (mounted) setState(() => _offset = c.offset);
    });
    _loadCampaign();
  }

  @override
  void dispose() {
    for (final c in [..._actual.values, ..._lineNotes.values]) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _actualFor(int id) => _actual.putIfAbsent(id, TextEditingController.new);
  TextEditingController _notesFor(int id) => _lineNotes.putIfAbsent(id, TextEditingController.new);

  void _toast(String title, {String? description, bool error = false}) {
    if (mounted) trackerToast(context, title, description: description, error: error);
  }

  Future<void> _loadCampaign() async {
    try {
      final r = await Future.wait([_api.get(_id), _api.flocks(_id), _api.days(_id), _api.products()]);
      if (!mounted) return;
      final camp = r[0] is Map ? r[0] as Map : null;
      if (camp == null) throw ApiException(404, 'Could not load this campaign.');
      setState(() {
        _c = camp;
        _flocks = rowsOf(r[1]);
        _days = rowsOf(r[2]);
        final prods = rowsOf(r[3]).where((p) => tIntOrNull(p['poultryRawMaterialItemId']) == tIntOrNull(camp['poultryRawMaterialItemId']));
        _product = prods.isEmpty ? null : prods.first;
        _error = null;
      });
      _pickDefaultDate();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message.isNotEmpty ? e.message : 'Could not load this campaign.');
    }
  }

  String get _today => _day(_c?['companyToday']);
  List<String> get _recordable => _c == null ? const [] : recordableDays(_day(_c!['startDate']), _day(_c!['endDate']), _today);
  Set<String> get _postedDates => {for (final d in _days) if (d['status'] == 'Posted') _day(d['businessDate'])};

  /// Default: today when it is in the window, else the first day not yet recorded.
  void _pickDefaultDate() {
    if (_c == null || _date != null) return;
    final rec = _recordable;
    if (rec.isEmpty) return;
    final posted = _postedDates;
    final firstOpen = rec.where((d) => !posted.contains(d));
    _date = rec.contains(_today) && !posted.contains(_today) ? _today : (firstOpen.isNotEmpty ? firstOpen.first : rec.last);
    _loadGrid();
  }

  Future<void> _loadGrid() async {
    final date = _date;
    if (date == null) return;
    setState(() => _gridLoading = true);
    try {
      final g = await _api.dayGrid(_id, date);
      if (!mounted) return;
      setState(() {
        _grid = rowsOf(g);
        for (final c in _actual.values) {
          c.clear();
        }
        for (final c in _lineNotes.values) {
          c.clear();
        }
      });
    } on ApiException catch (e) {
      _toast('Could not load the flocks for this day', description: e.message, error: true);
    }
    if (mounted) setState(() => _gridLoading = false);
  }

  String get _unit {
    final u = tStr(_c?['unitOfMeasure']);
    return u.isNotEmpty ? u : tStr(_product?['unitOfMeasure']);
  }

  List<({Map r, String state, String actualText})> get _rows => [
        for (final r in _grid ?? const <Map>[])
          (r: r, state: dayRowState(r), actualText: _actualFor(tIntOrNull(r['flockId']) ?? 0).text),
      ];

  void _fillSuggestions() => setState(() {
        for (final x in _rows) {
          if (x.state == 'ok' && x.r['suggestedQuantity'] != null) {
            _actualFor(tIntOrNull(x.r['flockId']) ?? 0).text = jsNumText(x.r['suggestedQuantity']);
          }
        }
      });

  Future<void> _confirmPost(num total, List<({Map r, String state, String actualText})> toPost) async {
    final notes = await showDialog<String>(
      context: context,
      builder: (_) => _RecordDialog(
        summary:
            "${fmtQty(total, _unit)} of ${tStr(_c?['itemName'])} on ${formatLongDate(_date)}, to ${toPost.length} flock${toPost.length == 1 ? '' : 's'}. Stock is checked again when you record. Each flock's production record gets the medication as a line, and stock goes down now.",
      ),
    );
    if (notes == null) return;
    await _doPost(notes, total, toPost);
  }

  Future<void> _doPost(String notes, num total, List<({Map r, String state, String actualText})> toPost) async {
    final date = _date;
    if (date == null) return;
    setState(() => _posting = true);
    try {
      await _api.postDay(_id, {
        'businessDate': date,
        'notes': notes.isEmpty ? null : notes,
        'lines': [
          for (final x in toPost)
            {
              'flockId': tIntOrNull(x.r['flockId']),
              'actualQuantity': parseQty(x.actualText),
              'suggestedQuantity': x.r['suggestedQuantity'],
              'notes': _notesFor(tIntOrNull(x.r['flockId']) ?? 0).text.trim().isEmpty ? null : _notesFor(tIntOrNull(x.r['flockId']) ?? 0).text.trim(),
            },
        ],
      });
      _toast('Treatment recorded', description: "${fmtQty(total, _unit)} to ${toPost.length} flock${toPost.length == 1 ? '' : 's'} on ${formatLongDate(date)}.");
      await _loadCampaign();
      await _loadGrid();
    } on ApiException catch (e) {
      final short = _insufficient(e);
      _toast(short ? 'Not enough in stock' : 'Not recorded', description: e.message, error: true);
      if (short) await _loadCampaign();
    }
    if (mounted) setState(() => _posting = false);
  }

  Future<void> _toggleDay(int pid) async {
    if (_openDay == pid) return setState(() => _openDay = null);
    setState(() => _openDay = pid);
    if (_dayLines[pid] == null) {
      setState(() => _dayLines[pid] = []);
      try {
        final l = await _api.dayLines(pid);
        if (mounted) setState(() => _dayLines[pid] = rowsOf(l));
      } on ApiException {
        // Shown as empty.
      }
    }
  }

  Future<void> _run(Future<Object?> Function() fn, String ok, [VoidCallback? after]) async {
    setState(() => _busy = true);
    try {
      await fn();
      _toast(ok);
      after?.call();
      await _loadCampaign();
      await _loadGrid();
    } on ApiException catch (e) {
      _toast('Not done', description: e.message, error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _complete() async {
    final c = _c!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark this campaign completed?'),
        content: SizedBox(
          width: 420,
          child: Text(
            '${tNum(c['postedDays']).toInt()} of ${tNum(c['plannedDays']).toInt()} days are recorded. Completing stops further recording; the days already recorded stay as they are.',
          ),
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not yet')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: TColors.emerald600, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mark completed'),
          ),
        ],
      ),
    );
    if (ok == true) await _run(() => _api.complete(_id), 'Campaign completed');
  }

  Future<void> _cancel() async {
    final reason = await showReasonDialog(
      context,
      title: 'Cancel this campaign?',
      description:
          'No more treatment can be recorded on it. Days already recorded stay recorded — those birds were treated. To take a wrong day back, reverse it under Treatment days.',
      confirmLabel: 'Cancel campaign',
      destructive: true,
    );
    if (reason != null) await _run(() => _api.cancel(_id, reason), 'Campaign cancelled');
  }

  Future<void> _reverse(Map d) async {
    final reason = await showReasonDialog(
      context,
      title: 'Reverse this treatment day?',
      description:
          "The medication comes off each flock's production record for that day and goes back into stock. The day stays in the history, marked Reversed, and can be recorded again.",
      confirmLabel: 'Reverse',
      destructive: true,
    );
    if (reason == null) return;
    final pid = tIntOrNull(d['poultryTreatmentCampaignPostId']) ?? 0;
    await _run(() => _api.reverseDay(pid, reason), 'Treatment day reversed', () => _dayLines.remove(pid));
  }

  void _openHref(String href, String label) => openPoultryHref(context, widget.session, widget.company, href, label: label);

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-treatment-campaigns');
    final c = _c;
    Widget body;
    Widget? bar;
    if (_error != null) {
      body = ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
        _title(context, 'Treatment campaign', '', back: true),
        const SizedBox(height: 12),
        TrackerBanner.error(_error!),
      ]);
    } else if (c == null) {
      body = const Padding(padding: EdgeInsets.all(16), child: LoadingLine('Loading…'));
    } else {
      final isOpen = c['lifecycle'] == 'Open';
      final showRecord = _tab == 'record' && isOpen && _recordable.isNotEmpty;
      final rows = _rows;
      final totals = dayTotals(tNum(_product?['availableQuantity']), [for (final x in rows) (state: x.state, actualText: x.actualText)]);
      final alreadyPosted = _date != null && _postedDates.contains(_date);
      final blocker = dayPostBlocker((actual: totals.actual, remaining: totals.remaining),
          [for (final x in rows) (state: x.state, actualText: x.actualText)],
          alreadyPosted: alreadyPosted, campaignOpen: isOpen, inWindow: _date != null && _recordable.contains(_date));
      final nothingEntered = rows.every((x) => x.actualText.trim().isEmpty);
      final toPost = [for (final x in rows) if (x.state == 'ok' && (parseQty(x.actualText) ?? 0) > 0) x];
      body = RefreshIndicator(
        onRefresh: () async {
          await _loadCampaign();
          await _loadGrid();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
          children: [
            _title(context, tStr(c['name']), [tStr(c['itemName']), tStr(c['reason'])].where((s) => s.isNotEmpty).join(' · '), back: true),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              campaignStatusBadge(c['status']),
              if (isOpen) ...[
                OutlinedButton.icon(
                  onPressed: _busy ? null : _complete,
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: const Text('Mark completed'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: TColors.rose700),
                  onPressed: _busy ? null : _cancel,
                  icon: const Icon(Icons.cancel_outlined, size: 16),
                  label: const Text('Cancel campaign'),
                ),
              ],
            ]),
            const SizedBox(height: 12),
            _summary(c),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  const ButtonSegment(value: 'record', label: Text('Record treatment')),
                  ButtonSegment(value: 'days', label: Text('Treatment days (${_days.length})')),
                  ButtonSegment(value: 'flocks', label: Text('Flocks (${_flocks.length})')),
                ],
                selected: {_tab},
                onSelectionChanged: (s) => setState(() => _tab = s.first),
              ),
            ),
            const SizedBox(height: 14),
            if (_tab == 'record') ..._recordTab(c, isOpen, totals, alreadyPosted, rows),
            if (_tab == 'days') _daysTab(),
            if (_tab == 'flocks') _flocksTab(c),
          ],
        ),
      );
      if (showRecord) {
        final msg = alreadyPosted
            ? blocker
            : nothingEntered
                ? 'Type the quantity actually given to each flock.'
                : blocker ?? "${fmtQty(totals.actual, _unit)} to ${toPost.length} flock${toPost.length == 1 ? '' : 's'} · ${fmtQty(totals.remaining, _unit)} left";
        bar = _stickyBar(
          Text(msg ?? '', style: TextStyle(fontSize: 13, color: blocker != null && !nothingEntered ? TColors.rose700 : TColors.slate600)),
          FilledButton(
            style: _violetButton,
            onPressed: blocker != null || _posting ? null : () => _confirmPost(totals.actual, toPost),
            child: _posting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text("Record Today's Treatment"),
          ),
        );
      }
    }
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: Text(c == null ? 'Treatment campaign' : tStr(c['name']))),
      body: Column(children: [Expanded(child: body), ?bar]),
    );
  }

  Widget _summary(Map c) {
    final unit = _unit;
    final planned = tNum(c['plannedDays']).toInt();
    final dose = describeDose(c['doseQuantity'], c['doseBasis'], unit);
    final egg = c['eggWithdrawalDays'];
    final meat = c['meatWithdrawalDays'];
    String withdrawal(Object? days, Object? until) => days == null
        ? 'not set'
        : '${_plural(tNum(days).toInt(), 'day')}${tStr(until).isNotEmpty ? ' — until ${formatLongDate(_day(until))}' : ''}';
    Widget line(String label, String value, {Color? color}) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: '$label: ', style: const TextStyle(color: TColors.slate500)),
              TextSpan(text: value),
            ]),
            style: TextStyle(fontSize: 13, color: color ?? TColors.slate900),
          ),
        );
    return _whiteCard(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      line('Dates', '${formatLongDate(_day(c['startDate']))} – ${formatLongDate(_day(c['endDate']))} (${_plural(planned, 'day')})'),
      line('Days recorded', '${tNum(c['postedDays']).toInt()} of $planned'),
      line('Given so far', '${fmtQty(tNum(c['totalQuantity']), unit)}${c['totalCost'] != null ? ' · ${_money(tNum(c['totalCost']))}' : ''}'),
      line('Dose', dose != null ? '$dose${c['doseSource'] == 'Product' ? ' (product setting)' : ''}' : 'None set — quantities are typed each day'),
      line('Egg withdrawal', withdrawal(egg, c['eggWithdrawalUntil'])),
      line('Meat withdrawal', withdrawal(meat, c['meatWithdrawalUntil'])),
      if (tStr(c['doseInstructions']).isNotEmpty) line('Usage information', tStr(c['doseInstructions'])),
      if (tStr(c['withdrawalNotes']).isNotEmpty) line('Withdrawal notes', tStr(c['withdrawalNotes'])),
      if (tStr(c['notes']).isNotEmpty) line('Notes', tStr(c['notes'])),
      if (c['status'] == 'Cancelled')
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            'Cancelled by ${tStr(c['cancelledBy']).isEmpty ? 'unknown' : tStr(c['cancelledBy'])} · ${fmtInstant(c['cancelledAtUtc'], _offset)} — ${tStr(c['cancelReason'])}. Days already recorded stay recorded.',
            style: const TextStyle(fontSize: 13, color: TColors.rose700),
          ),
        ),
      if (c['status'] == 'Completed')
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            'Completed by ${tStr(c['completedBy']).isEmpty ? 'unknown' : tStr(c['completedBy'])} · ${fmtInstant(c['completedAtUtc'], _offset)}',
            style: const TextStyle(fontSize: 13, color: TColors.emerald700),
          ),
        ),
      const Text(
        'Withdrawal dates run from the last day recorded. They are your own figures — the system does not hold eggs or birds back on them.',
        style: TextStyle(fontSize: 12, color: TColors.slate500),
      ),
    ]));
  }

  // ---------------------------------------------------------------- record

  List<Widget> _recordTab(Map c, bool isOpen, ({num available, num actual, num remaining}) totals, bool alreadyPosted,
      List<({Map r, String state, String actualText})> rows) {
    const muted = TextStyle(fontSize: 13, color: TColors.slate500);
    if (!isOpen) {
      return [Text('This campaign is ${campaignStatusLabel(c['status']).toLowerCase()} — no more treatment can be recorded on it.', style: muted)];
    }
    final rec = _recordable;
    if (rec.isEmpty) {
      return [Text('This campaign starts on ${formatLongDate(_day(c['startDate']))}. Treatment can be recorded from that day.', style: muted)];
    }
    final posted = _postedDates;
    final unit = _unit;
    final recognition = _product?['costRecognitionMethod'] == 'EXPENSE_WHEN_CONSUMED'
        ? 'Expensed when consumed — recording a day books the medication cost as an expense.'
        : 'Expensed when purchased — recording a day moves stock only; the cost was expensed at purchase.';
    return [
      _whiteCard(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _field(
          'Treatment day',
          AppSelect<String>(
            value: rec.contains(_date) ? _date : null,
            hintText: 'Choose a day',
            items: [
              for (var i = 0; i < rec.length; i++)
                AppSelectItem(value: rec[i], label: 'Day ${i + 1} · ${formatLongDate(rec[i])}${posted.contains(rec[i]) ? ' — recorded' : ''}'),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _date = v);
              _loadGrid();
            },
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: alreadyPosted || !rows.any((x) => x.state == 'ok' && x.r['suggestedQuantity'] != null) ? null : _fillSuggestions,
            child: const Text('Fill Actual from suggestions'),
          ),
        ),
        const SizedBox(height: 8),
        _statGrid([
          _stat('In stock', fmtQty(totals.available, unit)),
          _stat('Giving today', fmtQty(totals.actual, unit)),
          _stat('Left after', fmtQty(totals.remaining, unit), bad: totals.remaining < 0),
        ]),
        const SizedBox(height: 8),
        Text(recognition, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
      ])),
      const SizedBox(height: 12),
      if (_gridLoading) const LoadingLine('Loading flocks…'),
      if (_grid != null && !_gridLoading)
        for (final x in rows) ...[_dayRowCard(x, unit), const SizedBox(height: 8)],
    ];
  }

  Widget _dayRowCard(({Map r, String state, String actualText}) x, String unit) {
    final r = x.r;
    final id = tIntOrNull(r['flockId']) ?? 0;
    final locked = x.state != 'ok';
    final invalid = x.actualText.trim().isNotEmpty && parseQty(x.actualText) == null;
    final thisItem = tNum(r['thisItemQuantity']);
    const small = TextStyle(fontSize: 12, color: TColors.slate500);
    return Container(
      key: ValueKey('grid-$id'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: locked ? TColors.slate50 : Colors.white,
        border: Border.all(color: TColors.slate200),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tStr(r['flockName']), style: TextStyle(fontWeight: FontWeight.w600, color: locked ? TColors.slate500 : TColors.slate900)),
        if (tStr(r['houseName']).isNotEmpty) Text(tStr(r['houseName']), style: small),
        if (thisItem > 0 && x.state == 'ok')
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.warning_amber_rounded, size: 13, color: TColors.amber700),
            const SizedBox(width: 4),
            Expanded(
              child: Text("Already ${fmtQty(thisItem, unit)} of this product on today's record",
                  style: const TextStyle(fontSize: 12, color: TColors.amber700)),
            ),
          ]),
        const SizedBox(height: 4),
        Text(
          'Bird count: ${r['birds'] == null ? '—' : fmtNum(tNum(r['birds']), 0)} · Dose: ${describeDose(r['doseQuantity'], r['doseBasis'], unit) ?? '—'}',
          style: small,
        ),
        Text('Suggested: ${locked ? '—' : fmtQty(r['suggestedQuantity'] == null ? null : tNum(r['suggestedQuantity']), unit)}', style: small),
        const SizedBox(height: 8),
        if (x.state == 'posted')
          Row(children: [
            const Icon(Icons.check_circle_outline, size: 15, color: TColors.emerald700),
            const SizedBox(width: 4),
            Text('${fmtQty(tNum(r['postedQuantity']), unit)} recorded', style: const TextStyle(fontSize: 12, color: TColors.emerald700)),
          ])
        else if (locked)
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Icon(Icons.lock_outline, size: 15, color: TColors.slate500),
            const SizedBox(width: 4),
            if (x.state == 'closed')
              const Text('Flock is closed', style: TextStyle(fontSize: 12))
            else if (x.state == 'noRecord') ...[
              const Text('No production record — ', style: TextStyle(fontSize: 12)),
              _link('record it first', () => _openHref('/production-records/new?flockId=$id&date=$_date', 'Record production')),
            ] else ...[
              Text('${tNum(r['recordCount']).toInt()} records for this day — ', style: const TextStyle(fontSize: 12)),
              _link('fix the duplicate', () => _openHref('/production-records?date=$_date', 'Production records')),
            ],
          ])
        else
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 130,
              child: _field(
                'Actual${unit.isNotEmpty ? ' ($unit)' : ''}',
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  AppNumberInput(
                    key: ValueKey('actual-$id'),
                    controller: _actualFor(id),
                    allowDecimal: true,
                    hintText: '',
                    onChanged: (_) => setState(() {}),
                  ),
                  if (invalid) const Text('Not a valid number', style: TextStyle(fontSize: 11, color: TColors.rose700)),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: _field('Notes', AppInput(key: ValueKey('line-notes-$id'), controller: _notesFor(id)))),
          ]),
      ]),
    );
  }

  // ---------------------------------------------------------------- days

  Widget _daysTab() {
    if (_days.isEmpty) {
      return _whiteCard(const Text('No treatment recorded yet.', style: TextStyle(fontSize: 13, color: TColors.slate500)));
    }
    final unit = _unit;
    const small = TextStyle(fontSize: 12, color: TColors.slate600);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final d in _days) ...[
        Builder(builder: (_) {
          final pid = tIntOrNull(d['poultryTreatmentCampaignPostId']) ?? 0;
          final open = _openDay == pid;
          final posted = d['status'] == 'Posted';
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: TColors.slate200),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              InkWell(
                onTap: () => _toggleDay(pid),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Icon(open ? Icons.expand_less : Icons.expand_more, size: 18, color: TColors.slate500),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(formatLongDate(_day(d['businessDate'])),
                            style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.slate900)),
                      ),
                      TBadge(posted ? 'Recorded' : 'Reversed',
                          bg: posted ? TColors.emerald100 : TColors.slate200, fg: posted ? TColors.emerald700 : TColors.slate600),
                    ]),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.only(left: 22),
                      child: Text(
                        'Flocks: ${tNum(d['flockCount']).toInt()} · Quantity: ${fmtQty(tNum(d['totalQuantity']), unit)} · Cost: ${d['totalCost'] != null ? _money(tNum(d['totalCost'])) : '—'}',
                        style: small,
                      ),
                    ),
                    if (posted)
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                          onPressed: _busy ? null : () => _reverse(d),
                          icon: const Icon(Icons.restart_alt, size: 14),
                          label: const Text('Reverse'),
                        ),
                      ),
                  ]),
                ),
              ),
              if (open)
                Container(
                  color: const Color(0xCCF8FAFC),
                  padding: const EdgeInsets.fromLTRB(34, 10, 12, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(
                      'Recorded by ${tStr(d['postedBy']).isEmpty ? 'unknown' : tStr(d['postedBy'])} · ${fmtInstant(d['postedAtUtc'], _offset)}'
                      '${tStr(d['notes']).isNotEmpty ? ' · “${tStr(d['notes'])}”' : ''}',
                      style: small,
                    ),
                    if (d['status'] == 'Reversed')
                      Text(
                        'Reversed by ${tStr(d['reversedBy']).isEmpty ? 'unknown' : tStr(d['reversedBy'])} · ${fmtInstant(d['reversedAtUtc'], _offset)} — ${tStr(d['reversalReason'])}',
                        style: const TextStyle(fontSize: 12, color: TColors.rose700),
                      ),
                    const SizedBox(height: 6),
                    for (final l in _dayLines[pid] ?? const <Map>[])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(tStr(l['flockName']), style: const TextStyle(fontSize: 12, color: TColors.slate800)),
                          Text(
                            '${fmtQty(tNum(l['actualQuantity']), unit)}'
                            '${l['suggestedQuantity'] != null ? ' (suggested ${fmtQty(tNum(l['suggestedQuantity']), unit)})' : ''}'
                            '${l['totalCost'] != null ? ' · ${_money(tNum(l['totalCost']))}' : ''}',
                            style: small,
                          ),
                          Wrap(children: [
                            _link('production record',
                                () => _openHref('/production-records/${tStr(l['productionRecordId'])}', 'Production record')),
                            if (tStr(l['notes']).isNotEmpty || tStr(l['reversalNote']).isNotEmpty)
                              Text(
                                ' ${tStr(l['notes'])}${tStr(l['reversalNote']).isNotEmpty ? ' · ${tStr(l['reversalNote'])}' : ''}',
                                style: small,
                              ),
                          ]),
                        ]),
                      ),
                  ]),
                ),
            ]),
          );
        }),
        const SizedBox(height: 8),
      ],
    ]);
  }

  // ---------------------------------------------------------------- flocks

  Widget _flocksTab(Map c) {
    final unit = _unit;
    return _whiteCard(
      padding: EdgeInsets.zero,
      TrackerTable(
        columns: const [
          TCol('Flock', width: 170),
          TCol('Birds at start', right: true, width: 110),
          TCol('Own dose', width: 200),
          TCol('Days given', right: true, width: 90),
          TCol('Total given', right: true, width: 110),
          TCol('Notes', width: 180),
        ],
        rows: [
          for (final f in _flocks)
            [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(children: [
                  InkWell(
                    onTap: () => _openHref('/flocks/${tStr(f['flockId'])}', 'Flock'),
                    child: Text(tStr(f['flockName']), style: const TextStyle(fontWeight: FontWeight.w500, color: _violet700)),
                  ),
                  if (f['isClosed'] == true) const Text(' (closed)', style: TextStyle(fontSize: 12, color: TColors.slate500)),
                ]),
                if (tStr(f['houseName']).isNotEmpty) Text(tStr(f['houseName']), style: const TextStyle(fontSize: 12, color: TColors.slate500)),
              ]),
              Align(
                alignment: Alignment.centerRight,
                child: Text(f['birdsAtCreation'] == null ? '—' : fmtNum(tNum(f['birdsAtCreation']), 0)),
              ),
              Text(
                f['doseQuantity'] != null ? (describeDose(f['doseQuantity'], c['doseBasis'], unit) ?? '') : 'Campaign dose',
                style: const TextStyle(fontSize: 12),
              ),
              Align(alignment: Alignment.centerRight, child: Text('${tNum(f['postedDays']).toInt()}')),
              Align(alignment: Alignment.centerRight, child: Text(fmtQty(tNum(f['totalQuantity']), unit))),
              Text(tStr(f['notes']), style: const TextStyle(fontSize: 12)),
            ],
        ],
      ),
    );
  }
}

/// "Record this treatment?" with optional notes. Completes with the trimmed
/// notes, or null when cancelled.
class _RecordDialog extends StatefulWidget {
  const _RecordDialog({required this.summary});
  final String summary;

  @override
  State<_RecordDialog> createState() => _RecordDialogState();
}

class _RecordDialogState extends State<_RecordDialog> {
  final _notes = TextEditingController();

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: const Text('Record this treatment?'),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(widget.summary, style: const TextStyle(fontSize: 13, color: TColors.slate600)),
            const SizedBox(height: 12),
            _field('Notes (optional)', AppInput(controller: _notes, hintText: 'e.g. Given in morning water')),
          ]),
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _violet600, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, _notes.text.trim()),
            child: const Text('Record'),
          ),
        ],
      );
}

