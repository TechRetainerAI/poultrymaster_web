// Restaurant → Quick Links → Tills & Shifts, as `app/restaurant-tills/page.tsx`:
// open a shift on a till with a float from the cash box, cash up at the end
// (count the drawer; the difference is posted as over / short; the takings can
// be dropped to the safe or bank in the same step), and read the X-read while
// open or the Z-report once closed (migration 323).

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/reports/report_export.dart' show ReportExport;
import '../poultry/reports/report_format.dart' show FarmMoney;
import '../poultry/sales/balances_widgets.dart' show LoadingLine;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/business_dates.dart' show isoDay;
import 'restaurant_money_kit.dart' show rField, rFin, rNumberInput, rDateInput, rDialog, rCancel, rTodayIso, rRound2;
import 'restaurant_roles.dart' show restaurantRose;
import 'restaurant_widgets.dart';

/// `when`: the web's toLocaleString, or "—".
String tillWhen(Object? s) {
  final d = DateTime.tryParse(tStr(s));
  return d == null ? '—' : DateFormat('d/M/yyyy, HH:mm:ss').format(d.toLocal());
}

/// num(): blank or junk is 0, rounded to cents.
double tillNum(String s) => rRound2(double.tryParse(s.trim()) ?? 0).toDouble();

/// The open shifts first, then the period's others, without repeats.
List<Map> mergeShifts(List<Map> open, List<Map> recent) {
  final seen = {for (final s in open) tNum(s['shiftId'])};
  return [...open, for (final s in recent) if (!seen.contains(tNum(s['shiftId']))) s];
}

/// The Z-report (or X-read) as an 80 mm roll, for Print.
Future<Uint8List> zReportPdf(Map shift, List<Map> lines, FarmMoney gh) async {
  final doc = pw.Document();
  final mono = pw.Font.courier();
  final bold = pw.Font.courierBold();
  pw.Widget row(String k, String v, {bool strong = false}) => pw.Row(children: [
        pw.Expanded(child: pw.Text(k, style: pw.TextStyle(font: strong ? bold : mono, fontSize: 9))),
        pw.Text(v, style: pw.TextStyle(font: strong ? bold : mono, fontSize: 9)),
      ]);
  pw.Widget sec(String t) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 6),
        padding: const pw.EdgeInsets.only(top: 3),
        decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: .5))),
        child: pw.Text(t, style: pw.TextStyle(font: bold, fontSize: 9)),
      );
  final closed = tStr(shift['status']) == 'Closed';
  final takings = [for (final l in lines) if (tStr(l['section']) == 'Takings') l];
  doc.addPage(pw.Page(
    pageFormat: const PdfPageFormat(80 * PdfPageFormat.mm, double.infinity, marginAll: 4 * PdfPageFormat.mm),
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Text('${tStr(shift['tillName'])} - ${tStr(shift['shiftNumber'])}', textAlign: pw.TextAlign.center, style: pw.TextStyle(font: bold, fontSize: 12)),
      row('Opened', tillWhen(shift['openedAt'])),
      row('By', tStr(shift['openedBy']).isEmpty ? '-' : tStr(shift['openedBy'])),
      if (tStr(shift['closedAt']).isNotEmpty) row('Closed', tillWhen(shift['closedAt'])),
      sec('DRAWER'),
      for (final l in lines)
        if (tStr(l['section']) == 'Drawer') row('${tStr(l['label'])} (${tNum(l['txnCount']).toInt()})', gh(tNum(l['amount']))),
      sec('CASH-UP'),
      row('Opening float', gh(tNum(shift['openingFloat']))),
      if (closed) ...[
        row('Expected', gh(tNum(shift['expectedCash']))),
        row('Counted', gh(tNum(shift['countedCash']))),
        row('Over / short', gh(tNum(shift['variance'])), strong: true),
        row('Dropped', gh(tNum(shift['dropAmount']))),
        row('Left in till', gh(tNum(shift['closingBalance']))),
      ] else
        row('In drawer now', gh(tNum(shift['currentBalance']))),
      sec('TAKINGS WHILE OPEN (ALL METHODS)'),
      if (takings.isEmpty) pw.Text('None', style: pw.TextStyle(font: mono, fontSize: 9)),
      for (final l in takings) row('${tStr(l['label'])} (${tNum(l['txnCount']).toInt()})', gh(tNum(l['amount']))),
    ]),
  ));
  return doc.save();
}

class RestaurantTillsScreen extends StatefulWidget {
  const RestaurantTillsScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<RestaurantTillsScreen> createState() => _RestaurantTillsScreenState();
}

class _RestaurantTillsScreenState extends State<RestaurantTillsScreen> {
  bool _loading = true;
  List<Map> _accounts = [];
  List<Map> _shifts = [];
  String _from = isoDay(DateTime.now().subtract(const Duration(days: 13)));
  String _to = rTodayIso();
  FarmMoney _gh = const FarmMoney();

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _gh = m);
    });
    _load();
  }

  List<Map> _rows(Object? v) => [for (final x in (v is List ? v : const [])) if (x is Map) x];

  Future<void> _load() async {
    try {
      final r = await Future.wait<Object?>([
        _api.get(rFin('/accounts', _farmId)),
        _api.get(rFin('/shifts', _farmId, {'status': 'Open'})),
        _api.get(rFin('/shifts', _farmId, {'from': _from, 'to': _to})),
      ]);
      _accounts = _rows(r[0]);
      _shifts = mergeShifts(_rows(r[1]), _rows(r[2]));
    } catch (e) {
      if (mounted) trackerToast(context, 'Could not load tills', description: e is ApiException ? e.message : '$e', error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  List<Map> get _tills => [for (final a in _accounts) if (tStr(a['accountType']) == 'Till' && a['isActive'] != false) a];
  List<Map> get _sources => [for (final a in _accounts) if (tStr(a['accountType']) != 'Till' && a['isActive'] != false) a];
  List<Map> get _open => [for (final s in _shifts) if (tStr(s['status']) == 'Open') s];
  List<Map> get _closed => [for (final s in _shifts) if (tStr(s['status']) == 'Closed') s];

  /// The cash box: the source marked default for Cash, else the first.
  int? get _defaultBox {
    final box = _sources.where((a) => tStr(a['defaultFor']) == 'Cash').firstOrNull ?? _sources.firstOrNull;
    return box == null ? null : tNum(box['cashAccountId']).toInt();
  }

  Future<void> _newTill() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _NewTillDialog(api: _api, farmId: _farmId));
    if (ok == true) await _load();
  }

  Future<void> _openShift(Map till) async {
    final ok = await showDialog<bool>(
        context: context, builder: (_) => _OpenShiftDialog(api: _api, farmId: _farmId, till: till, sources: _sources, box: _defaultBox, gh: _gh));
    if (ok == true) await _load();
  }

  Future<void> _closeShift(Map s) async {
    final ok = await showDialog<bool>(
        context: context, builder: (_) => _CloseShiftDialog(api: _api, farmId: _farmId, shift: s, sources: _sources, box: _defaultBox, gh: _gh));
    if (ok != true) return;
    await _load();
    // The Z-report reads the refreshed row so the counted figures show.
    final fresh = _shifts.where((x) => tNum(x['shiftId']) == tNum(s['shiftId'])).firstOrNull ?? {...s, 'status': 'Closed'};
    if (mounted) _showZ(fresh);
  }

  Future<void> _showZ(Map s) async {
    List<Map> lines = [];
    try {
      lines = _rows(await _api.get(rFin('/shifts/${s['shiftId']}/z-report', _farmId)));
    } catch (e) {
      if (mounted) trackerToast(context, 'Could not load the Z-report', description: e is ApiException ? e.message : '$e', error: true);
    }
    if (!mounted) return;
    await showDialog<void>(context: context, builder: (_) => _ZReportDialog(shift: s, lines: lines, gh: _gh));
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/restaurant-tills');
    final today = rTodayIso();
    final todayVariance = _closed
        .where((s) => tStr(s['closedAt']).length >= 10 && tStr(s['closedAt']).substring(0, 10) == today)
        .fold<num>(0, (t, s) => t + tNum(s['variance']));
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Tills & Shifts')),
      body: _loading
          ? const Padding(padding: EdgeInsets.all(20), child: LoadingLine('Loading…'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
                RPageHeader(
                  icon: Icons.calculate_outlined,
                  title: 'Tills & Shifts',
                  subtitle: 'Open the drawer with a float, cash up at the end, see the Z-report',
                  actions: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                      onPressed: _newTill,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('New till'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                RStatCard(label: 'Open shifts', value: '${_open.length}', icon: Icons.meeting_room_outlined, color: 'green'),
                const SizedBox(height: 10),
                RStatCard(
                    label: 'Cash in open tills',
                    value: _gh(_open.fold<num>(0, (t, s) => t + tNum(s['currentBalance']))),
                    icon: Icons.payments_outlined,
                    color: 'blue'),
                const SizedBox(height: 10),
                RStatCard(label: 'Over / short closed today', value: _gh(todayVariance), icon: Icons.balance, color: todayVariance < 0 ? 'red' : 'amber'),
                const SizedBox(height: 14),
                if (_tills.isEmpty)
                  TCard(
                    child: REmptyState(
                      icon: Icons.calculate_outlined,
                      title: 'No tills yet',
                      description:
                          'A till is a cash drawer. Create one for each drawer at the counter; cash sales then go into whichever till has a shift open.',
                      actionLabel: 'Create a till',
                      onAction: _newTill,
                    ),
                  )
                else
                  for (final till in _tills) ...[_tillCard(till), const SizedBox(height: 12)],
                const SizedBox(height: 4),
                _history(),
              ]),
            ),
    );
  }

  Widget _figure(String label, String value) => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: const Color(0xFFF9FAFB), borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _tillCard(Map till) {
    final s = _open.where((x) => tNum(x['cashAccountId']) == tNum(till['cashAccountId'])).firstOrNull;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: s != null ? const Color(0xFF86EFAC) : TColors.slate200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tStr(till['name']), overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                  s != null
                      ? '${tStr(s['shiftNumber'])} · opened ${tillWhen(s['openedAt'])}${tStr(s['openedBy']).isEmpty ? '' : ' by ${tStr(s['openedBy'])}'}'
                      : 'No shift open',
                  style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            ]),
          ),
          s != null
              ? rBadge('Open', bg: const Color(0xFF16A34A), fg: Colors.white)
              : Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(999)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.lock_outline, size: 11, color: Color(0xFF374151)),
                    SizedBox(width: 3),
                    Text('Closed', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                  ]),
                ),
        ]),
        const SizedBox(height: 10),
        twoColumns([
          _figure('In the drawer', _gh(tNum(till['currentBalance']))),
          if (s != null) _figure('Cash sales this shift', _gh(tNum(s['cashSales']))),
          if (s != null) _figure('Opening float', _gh(tNum(s['openingFloat']))),
        ], gap: 8),
        const SizedBox(height: 10),
        if (s != null)
          Row(children: [
            Expanded(child: roseButton('Close & count', () => _closeShift(s), icon: Icons.lock_outline)),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => _showZ(s),
              icon: const Icon(Icons.description_outlined, size: 16),
              label: const Text('X-read'),
            ),
          ])
        else
          roseButton('Open shift', () => _openShift(till), icon: Icons.meeting_room_outlined, color: const Color(0xFF16A34A)),
      ]),
    );
  }

  Widget _history() {
    final closed = _closed;
    return TCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Shift history', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: rDateInput(_from, (d) => setState(() => _from = d))),
          const SizedBox(width: 8),
          Expanded(child: rDateInput(_to, (d) => setState(() => _to = d))),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: _load, child: const Text('Show')),
        ]),
        const SizedBox(height: 10),
        if (closed.isEmpty)
          const Padding(
            padding: EdgeInsets.all(18),
            child: Text('No closed shifts in this period.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: TColors.slate500)),
          )
        else
          for (final s in closed) _historyRow(s),
      ]),
    );
  }

  Widget _historyRow(Map s) {
    final v = tNum(s['variance']);
    final vColor = v < 0
        ? const Color(0xFFDC2626)
        : v > 0
            ? const Color(0xFFD97706)
            : const Color(0xFF15803D);
    Widget cell(String k, String val, {Color? color, bool bold = false}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(k, style: const TextStyle(fontSize: 11, color: TColors.slate500)),
            Text(val, style: TextStyle(fontSize: 13, color: color, fontWeight: bold ? FontWeight.w600 : null)),
          ]),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('${tStr(s['shiftNumber'])} · ${tStr(s['tillName'])}', style: const TextStyle(fontWeight: FontWeight.w600))),
          OutlinedButton(style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact), onPressed: () => _showZ(s), child: const Text('Z-report')),
        ]),
        Text('Opened ${tillWhen(s['openedAt'])}${tStr(s['openedBy']).isEmpty ? '' : ' · ${tStr(s['openedBy'])}'}',
            style: const TextStyle(fontSize: 12, color: TColors.slate500)),
        Text('Closed ${tillWhen(s['closedAt'])}${tStr(s['closedBy']).isEmpty ? '' : ' · ${tStr(s['closedBy'])}'}',
            style: const TextStyle(fontSize: 12, color: TColors.slate500)),
        const SizedBox(height: 8),
        Row(children: [
          cell('Expected', _gh(tNum(s['expectedCash']))),
          cell('Counted', _gh(tNum(s['countedCash']))),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          cell('Over / short', _gh(v), color: vColor, bold: true),
          cell('Dropped', _gh(tNum(s['dropAmount']))),
        ]),
      ]),
    );
  }
}

class _NewTillDialog extends StatefulWidget {
  const _NewTillDialog({required this.api, required this.farmId});
  final ApiClient api;
  final String farmId;
  @override
  State<_NewTillDialog> createState() => _NewTillDialogState();
}

class _NewTillDialogState extends State<_NewTillDialog> {
  final _name = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.api.post(rFin('/accounts', widget.farmId), body: {'name': name, 'accountType': 'Till', 'farmId': widget.farmId});
      if (!mounted) return;
      trackerToast(context, '$name created');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        trackerToast(context, 'Could not create the till', description: e is ApiException ? e.message : '$e', error: true);
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => rDialog(
        title: 'New till',
        description: 'A cash drawer at the counter, e.g. "Front Till" or "Bar Till".',
        children: [rField('Name', AppInput(controller: _name, hintText: 'Front Till', onChanged: (_) => setState(() {})))],
        actions: [
          rCancel(context, 'Cancel'),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: restaurantRose),
            onPressed: _saving || _name.text.trim().isEmpty ? null : _create,
            child: const Text('Create'),
          ),
        ],
      );
}

class _OpenShiftDialog extends StatefulWidget {
  const _OpenShiftDialog({required this.api, required this.farmId, required this.till, required this.sources, required this.box, required this.gh});
  final ApiClient api;
  final String farmId;
  final Map till;
  final List<Map> sources;
  final int? box;
  final FarmMoney gh;
  @override
  State<_OpenShiftDialog> createState() => _OpenShiftDialogState();
}

class _OpenShiftDialogState extends State<_OpenShiftDialog> {
  final _float = TextEditingController();
  final _notes = TextEditingController();
  late int? _from = widget.box;
  bool _saving = false;

  @override
  void dispose() {
    _float.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final fl = tillNum(_float.text);
    if (fl > 0 && _from == null) {
      trackerToast(context, 'Choose where the float comes from', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.api.post(rFin('/shifts', widget.farmId), body: {
        'tillAccountId': widget.till['cashAccountId'],
        'openingFloat': fl,
        'floatFromAccountId': fl > 0 ? _from : null,
        'notes': _notes.text.isEmpty ? null : _notes.text,
      });
      if (!mounted) return;
      trackerToast(context, 'Shift opened on ${tStr(widget.till['name'])}');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        trackerToast(context, 'Could not open the shift', description: e is ApiException ? e.message : '$e', error: true);
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => rDialog(
        title: 'Open shift — ${tStr(widget.till['name'])}',
        description: 'The drawer already holds ${widget.gh(tNum(widget.till['currentBalance']))}. Add a float if the cashier needs change.',
        children: [
          rField('Float to add', rNumberInput(_float, hint: '0.00', onChanged: () => setState(() {}))),
          rField(
            'Taken from',
            AppSelect<int>(
              value: _from,
              hintText: 'Account',
              enabled: tillNum(_float.text) > 0,
              items: [
                for (final a in widget.sources)
                  AppSelectItem(value: tNum(a['cashAccountId']).toInt(), label: '${tStr(a['name'])} — ${widget.gh(tNum(a['currentBalance']))}'),
              ],
              onChanged: (v) => setState(() => _from = v),
            ),
          ),
          rField('Notes', AppInput(controller: _notes)),
        ],
        actions: [
          rCancel(context, 'Cancel', busy: _saving),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
            onPressed: _saving ? null : _submit,
            child: const Text('Open shift'),
          ),
        ],
      );
}

class _CloseShiftDialog extends StatefulWidget {
  const _CloseShiftDialog({required this.api, required this.farmId, required this.shift, required this.sources, required this.box, required this.gh});
  final ApiClient api;
  final String farmId;
  final Map shift;
  final List<Map> sources;
  final int? box;
  final FarmMoney gh;
  @override
  State<_CloseShiftDialog> createState() => _CloseShiftDialogState();
}

class _CloseShiftDialogState extends State<_CloseShiftDialog> {
  final _counted = TextEditingController();
  final _drop = TextEditingController();
  final _notes = TextEditingController();
  late int? _dropTo = widget.box;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_counted, _drop, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  num get _expected => tNum(widget.shift['currentBalance']);
  double get _countedNum => tillNum(_counted.text);
  num get _variance => _counted.text.isEmpty ? 0 : rRound2(_countedNum - _expected);
  double get _dropNum => tillNum(_drop.text);

  Future<void> _submit() async {
    final s = widget.shift;
    if (_counted.text.isEmpty) {
      trackerToast(context, 'Enter the cash counted', error: true);
      return;
    }
    if (_dropNum > _countedNum) {
      trackerToast(context, 'You cannot drop more than you counted', error: true);
      return;
    }
    if (_dropNum > 0 && _dropTo == null) {
      trackerToast(context, 'Choose where the drop goes', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final r = await widget.api.post(rFin('/shifts/${s['shiftId']}/close', widget.farmId), body: {
        'countedCash': _countedNum,
        'dropAmount': _dropNum,
        'dropToAccountId': _dropNum > 0 ? _dropTo : null,
        'notes': _notes.text.isEmpty ? null : _notes.text,
      });
      final m = r is Map ? r : const {};
      final v = tNum(m['variance']);
      if (!mounted) return;
      trackerToast(context, '${tStr(s['shiftNumber'])} closed',
          description: v == 0
              ? 'The drawer balanced.'
              : '${v > 0 ? 'Over' : 'Short'} by ${widget.gh(v.abs())}. ${widget.gh(tNum(m['closingBalance']))} left in the till.');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        trackerToast(context, 'Could not close the shift', description: e is ApiException ? e.message : '$e', error: true);
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final gh = widget.gh;
    final v = _variance;
    final (bg, fg) = v == 0
        ? (const Color(0xFFF0FDF4), const Color(0xFF166534))
        : v > 0
            ? (const Color(0xFFFFFBEB), const Color(0xFF92400E))
            : (const Color(0xFFFEF2F2), const Color(0xFF991B1B));
    final float = tNum(widget.shift['openingFloat']);
    return rDialog(
      title: 'Close & count — ${tStr(widget.shift['tillName'])}',
      description: 'Count every note and coin in the drawer. Any difference from what the system expects is recorded as over or short.',
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFF9FAFB), borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            const Expanded(child: Text('System expects', style: TextStyle(fontSize: 14))),
            Flexible(child: Text(gh(_expected), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
          ]),
        ),
        rField(
          'Cash counted',
          TextField(
            controller: _counted,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ),
        if (_counted.text.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
            child: Text(v == 0 ? 'The drawer balances.' : '${v > 0 ? 'Over' : 'Short'} by ${gh(v.abs())}',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: fg)),
          ),
        rField(
          'Drop to safe / bank',
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            rNumberInput(_drop, hint: '0.00', onChanged: () => setState(() {})),
            if (_counted.text.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  style: TextButton.styleFrom(foregroundColor: const Color(0xFFBE123C), padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                  onPressed: () => setState(() => _drop.text = (_countedNum - float > 0 ? _countedNum - float : 0).toStringAsFixed(2)),
                  child: Text('Leave the float (${gh(float)}) in the till', style: const TextStyle(fontSize: 12, decoration: TextDecoration.underline)),
                ),
              ),
          ]),
        ),
        rField(
          'Drop into',
          AppSelect<int>(
            value: _dropTo,
            hintText: 'Account',
            enabled: _dropNum > 0,
            items: [for (final a in widget.sources) AppSelectItem(value: tNum(a['cashAccountId']).toInt(), label: tStr(a['name']))],
            onChanged: (v) => setState(() => _dropTo = v),
          ),
        ),
        rField('Notes', AppInput(controller: _notes, hintText: v < 0 ? 'Why is it short?' : null)),
      ],
      actions: [
        rCancel(context, 'Cancel', busy: _saving),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: restaurantRose),
          onPressed: _saving || _counted.text.isEmpty ? null : _submit,
          child: const Text('Close shift'),
        ),
      ],
    );
  }
}

class _ZReportDialog extends StatelessWidget {
  const _ZReportDialog({required this.shift, required this.lines, required this.gh});
  final Map shift;
  final List<Map> lines;
  final FarmMoney gh;

  @override
  Widget build(BuildContext context) {
    const mono = TextStyle(fontFamily: 'monospace', fontSize: 12);
    final closed = tStr(shift['status']) == 'Closed';
    Widget row(String k, String v, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 1.5),
          child: Row(children: [
            Expanded(child: Text(k, style: mono.copyWith(fontWeight: bold ? FontWeight.w700 : null))),
            const SizedBox(width: 8),
            Flexible(child: Text(v, textAlign: TextAlign.right, style: mono.copyWith(fontWeight: bold ? FontWeight.w700 : null))),
          ]),
        );
    Widget sec(String t) => Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.only(top: 4),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.black38))),
          child: Text(t, style: mono.copyWith(fontWeight: FontWeight.w700)),
        );
    final takings = [for (final l in lines) if (tStr(l['section']) == 'Takings') l];
    return AlertDialog(
      scrollable: true,
      title: Text(closed ? 'Z-report' : 'X-read (shift still open)'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${tStr(shift['tillName'])} · ${tStr(shift['shiftNumber'])}', style: const TextStyle(fontSize: 13, color: TColors.slate500)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('${tStr(shift['tillName'])} — ${tStr(shift['shiftNumber'])}', textAlign: TextAlign.center, style: mono.copyWith(fontWeight: FontWeight.w700)),
              row('Opened', tillWhen(shift['openedAt'])),
              row('By', tStr(shift['openedBy']).isEmpty ? '—' : tStr(shift['openedBy'])),
              if (tStr(shift['closedAt']).isNotEmpty) row('Closed', tillWhen(shift['closedAt'])),
              sec('DRAWER'),
              for (final l in lines)
                if (tStr(l['section']) == 'Drawer') row('${tStr(l['label'])} (${tNum(l['txnCount']).toInt()})', gh(tNum(l['amount']))),
              sec('CASH-UP'),
              row('Opening float', gh(tNum(shift['openingFloat']))),
              if (closed) ...[
                row('Expected', gh(tNum(shift['expectedCash']))),
                row('Counted', gh(tNum(shift['countedCash']))),
                row('Over / short', gh(tNum(shift['variance'])), bold: true),
                row('Dropped', gh(tNum(shift['dropAmount']))),
                row('Left in till', gh(tNum(shift['closingBalance']))),
              ] else
                row('In drawer now', gh(tNum(shift['currentBalance']))),
              sec('TAKINGS WHILE OPEN (ALL METHODS)'),
              if (takings.isEmpty) Text('None', style: mono.copyWith(color: TColors.slate500)),
              for (final l in takings) row('${tStr(l['label'])} (${tNum(l['txnCount']).toInt()})', gh(tNum(l['amount']))),
            ]),
          ),
        ]),
      ),
      actions: [
        Wrap(alignment: WrapAlignment.end, spacing: 8, children: [
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: restaurantRose),
            onPressed: () async {
              final bytes = await zReportPdf(shift, lines, gh);
              await ReportExport.sharer('Z-report_${tStr(shift['shiftNumber'])}.pdf', bytes, 'application/pdf', 'Z-report');
            },
            icon: const Icon(Icons.print_outlined, size: 16),
            label: const Text('Print'),
          ),
        ]),
      ],
    );
  }
}
