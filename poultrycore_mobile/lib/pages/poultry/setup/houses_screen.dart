import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/form_dialog.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../page_extras.dart' show fetchRows;
import '../../shared/business_dates.dart' show fmtNum;
import '../bulk_house_screen.dart';
import 'setup_embed.dart';
import 'setup_views_kit.dart';

import 'package:poultrycore_mobile/design/tone.dart';

/// Setup → Houses (`/houses`) and Farm Setup → Houses & pens, as the web's
/// components/setup-views/houses.tsx: search, Cards or Table (remembered),
/// each house's occupancy from its ACTIVE flocks, the totals, 10 to a page,
/// Add House / Add Multiple Houses/Pens, edit, and delete (refused while the
/// house holds birds).
class HousesScreen extends StatefulWidget {
  const HousesScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<HousesScreen> createState() => _HousesScreenState();
}

/// house-picker.tsx `HouseOccupancy`.
class HouseOccupancy {
  const HouseOccupancy(this.capacity, this.occupied, this.free, this.flockCount, this.state);

  /// 0 = no capacity recorded.
  final int capacity;
  final int occupied;

  /// Null when capacity is unknown.
  final int? free;
  final int flockCount;

  /// empty | free | full | unknown
  final String state;
}

int _i(Object? v) => v is num ? v.toInt() : (int.tryParse('${v ?? ''}') ?? 0);

/// house-picker.tsx `houseOccupancy`: the house's active flocks.
HouseOccupancy houseOccupancy(Map house, List<Map> flocks, {int? excludeFlockId}) {
  final id = _i(house['houseId']);
  final mine = flocks.where((f) => _i(f['houseId']) == id && f['houseId'] != null && f['active'] == true && _i(f['flockId']) != excludeFlockId).toList();
  final occupied = mine.fold<int>(0, (s, f) => s + _i(f['quantity']));
  final capacity = _i(house['capacity']);
  final free = capacity > 0 ? (capacity - occupied).clamp(0, capacity) : null;
  final state = capacity <= 0
      ? (occupied == 0 ? 'empty' : 'unknown')
      : free == 0
          ? 'full'
          : occupied == 0
              ? 'empty'
              : 'free';
  return HouseOccupancy(capacity, occupied, free, mine.length, state);
}

String _houseName(Map h) => '${h['name'] ?? h['houseName'] ?? ''}';

class _HousesScreenState extends State<HousesScreen> {
  List<Map<String, dynamic>> _houses = const [];
  List<Map<String, dynamic>> _flocks = const [];
  bool _loading = true;
  SetupView _view = SetupView.cards;
  String _search = '';
  int _page = 1;
  int _pageSize = 10;

  @override
  void initState() {
    super.initState();
    loadSetupView('houses-view').then((v) {
      if (v != null && mounted) setState(() => _view = v);
    });
    _load();
  }

  void _toast(String title, [String? detail]) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(detail == null ? title : '$title — $detail')));

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await Future.wait([
        fetchRows(widget.session, widget.company, '/api/House'),
        fetchRows(widget.session, widget.company, '/api/Flock').catchError((Object _) => <Map<String, dynamic>>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _houses = r[0];
        _flocks = r[1];
      });
    } on ApiException catch (e) {
      if (mounted) _toast('Could not load houses', e.message.isNotEmpty ? e.message : 'Failed to load houses');
    } catch (e) {
      if (mounted) _toast('Could not load houses', '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _shown {
    final term = _search.trim().toLowerCase();
    return [
      for (final h in _houses)
        if (term.isEmpty || _houseName(h).toLowerCase().contains(term) || '${h['location'] ?? ''}'.toLowerCase().contains(term)) h,
    ];
  }

  /// Birds per house from ACTIVE flocks, so an occupied pen says why it
  /// cannot be deleted. The server refuses it too.
  ({int flocks, int birds}) _held(Map h) {
    final id = _i(h['houseId']);
    var flocks = 0, birds = 0;
    for (final f in _flocks) {
      if (f['houseId'] == null || f['active'] != true || _i(f['houseId']) != id) continue;
      flocks++;
      birds += _i(f['quantity']);
    }
    return (flocks: flocks, birds: birds);
  }

  Future<void> _openForm([Map? editing]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _HouseDialog(session: widget.session, company: widget.company, editing: editing),
    );
    if (saved == true) await _load();
  }

  Future<void> _bulk() async {
    final created = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => BulkHouseScreen(
        session: widget.session,
        company: widget.company,
        existingNames: [for (final h in _houses) _houseName(h)],
        source: 'Houses page',
      ),
    ));
    if (created == true) await _load();
  }

  Future<void> _delete(Map h) async {
    final name = '${h['houseName'] ?? h['name'] ?? ''}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete House'),
        content: Text('Are you sure you want to delete "$name"? This action cannot be undone.'),
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
      await widget.session.farmClient.delete('/api/House/${h['houseId']}', query: {
        'userId': widget.session.tokens.userId ?? '',
        'farmId': widget.company.farmId,
      });
      if (!mounted) return;
      _toast('House deleted', '"$name" has been successfully deleted.');
      await _load();
    } on ApiException catch (e) {
      if (mounted) _toast('Delete failed', e.message.isNotEmpty ? e.message : 'Something went wrong. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final embedded = isSetupEmbedded(context);
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/houses');
    final shown = _shown;
    final pg = pagedSlice(shown, _page, _pageSize);
    final tasks = [
      SetupTask(id: 'add', label: 'Add House', icon: Icons.add, primary: true, onTap: () => _openForm()),
      SetupTask(id: 'bulk', label: 'Add Multiple Houses/Pens', icon: Icons.layers_outlined, onTap: _bulk),
    ];
    return Scaffold(
      appBar: embedded ? null : AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Houses')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(key: const ValueKey('houses-list'), padding: const EdgeInsets.fromLTRB(14, 12, 14, 24), children: [
          if (!embedded) ...[
            Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: const Tone.bg(0xFFDBEAFE), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.home_outlined, size: 20, color: _blue600),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Houses', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: _slate900)),
                  Text('Manage poultry houses', style: TextStyle(fontSize: 14, color: _slate600)),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
          ],
          SetupTaskBar(tasks: tasks),
          if (!embedded) const SizedBox(height: 12),
          if (!_loading && _houses.isNotEmpty) ...[
            SetupSearch(hint: 'Search by name or location', onChanged: (v) => setState(() {
              _search = v;
              _page = 1;
            })),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: Text('${shown.length} of ${_houses.length} houses', style: const TextStyle(fontSize: 13.5, color: _slate500))),
              ViewSwitch(value: _view, onChanged: (v) {
                setState(() => _view = v);
                saveSetupView('houses-view', v);
              }),
            ]),
            const SizedBox(height: 12),
          ],
          if (_loading)
            const Padding(padding: EdgeInsets.symmetric(vertical: 48), child: Center(child: Text('Loading houses...', style: TextStyle(color: _slate600))))
          else if (_houses.isEmpty)
            const SetupCard(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Column(children: [
                Icon(Icons.home_outlined, size: 48, color: Tone.fg(0xFF94A3B8)),
                SizedBox(height: 12),
                Text('No houses yet.', style: TextStyle(color: _slate600)),
              ]),
            )
          else if (shown.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 40),
              decoration: BoxDecoration(
                color: const Tone.bg(0xFFFFFFFF),
                border: Border.all(color: const Tone.line(0xFFCBD5E1)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('No house matches "$_search".', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13.5, color: _slate500)),
            )
          else if (_view == SetupView.table)
            _table(pg.items, shown)
          else
            for (final h in pg.items) ...[_card(h), const SizedBox(height: 12)],
          if (!_loading && shown.isNotEmpty)
            RecordsPager(
              total: shown.length,
              page: pg.page,
              pageSize: _pageSize,
              onPage: (p) => setState(() => _page = p),
              onPageSize: (n) => setState(() => _pageSize = n),
            ),
        ]),
      ),
    );
  }

  Widget _deleteButton(Map h, double size) {
    final held = _held(h);
    final blocked = held.flocks > 0;
    return IconButton(
      key: ValueKey('house-delete-${h['houseId']}'),
      tooltip: blocked
          ? 'Holds ${fmtNum(held.birds, 0)} bird${held.birds == 1 ? '' : 's'} in ${held.flocks} flock${held.flocks == 1 ? '' : 's'}. '
              'Move or close them before deleting this house.'
          : 'Delete this house',
      onPressed: blocked ? null : () => _delete(h),
      icon: Icon(Icons.delete_outline, size: size, color: blocked ? const Tone.fg(0xFFCBD5E1) : const Tone.fg(0xFFDC2626)),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _editButton(Map h, double size) => IconButton(
        key: ValueKey('house-edit-${h['houseId']}'),
        tooltip: 'Edit',
        onPressed: () => _openForm(h),
        icon: Icon(Icons.edit_outlined, size: size),
        visualDensity: VisualDensity.compact,
      );

  Widget _card(Map h) {
    final o = houseOccupancy(h, _flocks);
    final pct = o.capacity > 0 ? ((o.occupied / o.capacity) * 100).round().clamp(0, 100) : null;
    final location = '${h['location'] ?? ''}';
    return SetupCard(
      key: ValueKey('house-${h['houseId']}'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Header: name + location, with the row actions.
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _slate100))),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: const Tone.bg(0xFFEFF6FF), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.home_outlined, size: 16, color: _blue600),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_houseName(h), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _slate900)),
                location.isNotEmpty
                    ? Row(children: [
                        const Icon(Icons.place_outlined, size: 12, color: _slate500),
                        const SizedBox(width: 3),
                        Flexible(child: Text(location, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: _slate500))),
                      ])
                    : const Text('No location set', style: TextStyle(fontSize: 12, color: _slate400)),
              ]),
            ),
            _editButton(h, 16),
            _deleteButton(h, 16),
          ]),
        ),
        // Body: occupancy at a glance.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              HouseStatusPill(state: o.state),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${o.flockCount} active ${o.flockCount == 1 ? 'flock' : 'flocks'}',
                    textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: _slate500)),
              ),
            ]),
            const SizedBox(height: 12),
            if (o.capacity > 0 && pct != null) ...[
              UsageBar(pct: pct),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: Text('${fmtNum(o.occupied, 0)} / ${fmtNum(o.capacity, 0)} birds', style: const TextStyle(fontSize: 12, color: _slate500))),
                Text(o.free != null ? '${fmtNum(o.free, 0)} free' : '$pct%',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Tone.fg(0xFF334155))),
              ]),
            ] else
              const Text('Capacity not set', style: TextStyle(fontSize: 12, color: _slate400)),
          ]),
        ),
      ]),
    );
  }

  /// The table, sideways-scrolling on a phone, with its totals row over every
  /// house the search shows.
  Widget _table(List<Map<String, dynamic>> page, List<Map<String, dynamic>> shown) {
    var capacity = 0, birds = 0, full = 0;
    for (final h in shown) {
      final o = houseOccupancy(h, _flocks);
      capacity += o.capacity;
      birds += o.occupied;
      if (o.state == 'full') full++;
    }
    final free = (capacity - birds).clamp(0, 1 << 30);
    const head = TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _slate900);
    const num = TextStyle(fontSize: 13.5, color: _slate900);
    DataCell right(Widget w) => DataCell(Align(alignment: Alignment.centerRight, child: w));
    return SetupCard(
      child: SingleChildScrollView(
        key: const ValueKey('houses-table'),
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: const WidgetStatePropertyAll(_slate50),
          headingRowHeight: 40,
          columnSpacing: 20,
          columns: const [
            DataColumn(label: Text('House', style: head)),
            DataColumn(label: Text('Location', style: head)),
            DataColumn(label: Text('Capacity', style: head), numeric: true),
            DataColumn(label: Text('Active flocks', style: head), numeric: true),
            DataColumn(label: Text('Birds in house', style: head), numeric: true),
            DataColumn(label: Text('Used', style: head)),
            DataColumn(label: Text('Free', style: head), numeric: true),
            DataColumn(label: Text('Status', style: head)),
            DataColumn(label: Text('Actions', style: head)),
          ],
          rows: [
            for (final h in page)
              () {
                final o = houseOccupancy(h, _flocks);
                final pct = o.capacity > 0 ? ((o.occupied / o.capacity) * 100).round().clamp(0, 100) : null;
                final loc = '${h['location'] ?? ''}';
                return DataRow(cells: [
                  DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.home_outlined, size: 16, color: _blue600),
                    const SizedBox(width: 8),
                    Text(_houseName(h), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: _slate900)),
                  ])),
                  DataCell(loc.isEmpty
                      ? const Text('—', style: TextStyle(color: _slate400))
                      : Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.place_outlined, size: 14, color: _slate400),
                          const SizedBox(width: 4),
                          Text(loc, style: const TextStyle(fontSize: 13.5, color: _slate600)),
                        ])),
                  right(o.capacity > 0 ? Text(fmtNum(o.capacity, 0), style: num) : const Text('Not set', style: TextStyle(color: _slate400))),
                  right(Text('${o.flockCount}', style: num)),
                  right(Text(fmtNum(o.occupied, 0), style: num)),
                  DataCell(pct == null
                      ? const Text('—', style: TextStyle(fontSize: 12, color: _slate400))
                      : SizedBox(
                          width: 160,
                          child: Row(children: [
                            Expanded(child: UsageBar(pct: pct)),
                            SizedBox(width: 40, child: Text('$pct%', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: _slate600))),
                          ]),
                        )),
                  right(o.free != null
                      ? Text(fmtNum(o.free, 0),
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: o.state == 'full' ? const Tone.fg(0xFFDC2626) : _emerald700))
                      : const Text('—', style: TextStyle(color: _slate400))),
                  DataCell(HouseStatusPill(state: o.state)),
                  DataCell(Row(mainAxisSize: MainAxisSize.min, children: [_editButton(h, 16), _deleteButton(h, 16)])),
                ]);
              }(),
            DataRow(color: const WidgetStatePropertyAll(_slate50), cells: [
              DataCell(Text('Total, all ${shown.length} houses${full > 0 ? ' ($full full)' : ''}',
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Tone.fg(0xFF334155)))),
              const DataCell(SizedBox()),
              right(Text(fmtNum(capacity, 0), style: num.copyWith(fontWeight: FontWeight.w600))),
              const DataCell(SizedBox()),
              right(Text(fmtNum(birds, 0), style: num.copyWith(fontWeight: FontWeight.w600))),
              const DataCell(SizedBox()),
              right(Text(fmtNum(free, 0), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: _emerald700))),
              const DataCell(SizedBox()),
              const DataCell(SizedBox()),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Empty · Has space · Full · In use.
class HouseStatusPill extends StatelessWidget {
  const HouseStatusPill({super.key, required this.state});
  final String state;

  @override
  Widget build(BuildContext context) {
    final (text, bg, fg, line) = switch (state) {
      'empty' => ('Empty', const Tone.bg(0xFFECFDF5), _emerald700, const Tone.line(0xFFA7F3D0)),
      'free' => ('Has space', const Tone.bg(0xFFF0F9FF), const Tone.fg(0xFF0369A1), const Tone.line(0xFFBAE6FD)),
      'full' => ('Full', const Tone.bg(0xFFFEF2F2), const Tone.fg(0xFFB91C1C), const Tone.line(0xFFFECACA)),
      _ => ('In use', _slate50, _slate600, const Tone.line(0xFFE2E8F0)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, border: Border.all(color: line), borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: fg)),
    );
  }
}

/// Create New House / Edit House.
class _HouseDialog extends StatefulWidget {
  const _HouseDialog({required this.session, required this.company, this.editing});
  final Session session;
  final Company company;
  final Map? editing;

  @override
  State<_HouseDialog> createState() => _HouseDialogState();
}

class _HouseDialogState extends State<_HouseDialog> {
  late final _name = TextEditingController(text: '${widget.editing?['name'] ?? widget.editing?['houseName'] ?? ''}');
  late final _capacity = TextEditingController(text: widget.editing?['capacity'] == null ? '' : '${widget.editing!['capacity']}');
  late final _location = TextEditingController(text: '${widget.editing?['location'] ?? ''}');
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _capacity, _location]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_name.text.trim().isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Give this house a name so you can find it later in lists and reports.')));
      return;
    }
    setState(() => _saving = true);
    final body = {
      'UserId': widget.session.tokens.userId ?? '',
      'FarmId': widget.company.farmId,
      'HouseName': _name.text,
      'Capacity': _capacity.text.isEmpty ? null : int.tryParse(_capacity.text),
      'Location': _location.text.isEmpty ? null : _location.text,
    };
    try {
      final e = widget.editing;
      if (e != null) {
        await widget.session.farmClient.put('/api/House/${e['houseId']}', body: body);
      } else {
        await widget.session.farmClient.post('/api/House', body: body);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('Save failed — ${e.message.isNotEmpty ? e.message : 'Save failed'}')));
    }
  }

  Widget _label(String text, Widget child) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(text, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: Tone.fg(0xFF334155))),
        const SizedBox(height: 6),
        child,
      ]);

  @override
  Widget build(BuildContext context) {
    final editing = widget.editing != null;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(editing ? 'Edit House' : 'Create New House', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(editing ? 'Update the house information below.' : 'Add a new poultry house to your farm records.',
              style: const TextStyle(fontSize: 13.5, color: _slate500)),
        ]),
        content: SizedBox(
          width: 672,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TintedSection(title: 'House Details', color: FormColor.blue, children: [
              _label('House Name *', AppInput(key: const ValueKey('house-name'), controller: _name, hintText: 'House A')),
              _label('Capacity (birds)', AppNumberInput(key: const ValueKey('house-capacity'), controller: _capacity, hintText: '1000')),
            ]),
            const SizedBox(height: 16),
            TintedSection(title: 'Additional Information', color: FormColor.purple, children: [
              _label('Location', AppInput(key: const ValueKey('house-location'), controller: _location, hintText: 'North Wing')),
            ]),
          ]),
        ),
        actions: [
          FormDialogFooter(onCancel: () => Navigator.of(context).pop(false), cancelDisabled: _saving, children: [
            FilledButton(
              key: const ValueKey('house-save'),
              style: formPrimary(FormColor.blue),
              onPressed: _saving ? null : _submit,
              child: Text(_saving ? 'Saving...' : editing ? 'Update House' : 'Create House'),
            ),
          ]),
        ],
      ),
    );
  }
}

const _blue600 = Tone.fg(0xFF2563EB);
const _emerald700 = Tone.fg(0xFF047857);
const _slate50 = Tone.bg(0xFFF8FAFC);
const _slate100 = Tone.line(0xFFF1F5F9);
const _slate400 = Tone.fg(0xFF94A3B8);
const _slate500 = Tone.fg(0xFF64748B);
const _slate600 = Tone.fg(0xFF475569);
const _slate900 = Tone.fg(0xFF0F172A);
