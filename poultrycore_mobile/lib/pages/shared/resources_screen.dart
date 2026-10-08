// Settings → Resources (app/resources/page.tsx): "Resources & Information
// Center" — Vaccination Schedules, Medication Schedules and Feed Formulations.
// As on the web these live in the page only (seeded, add / edit / delete in
// memory, nothing sent to the server), and the "*" fields are not enforced.

import 'package:flutter/material.dart';

import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/sales/balances_widgets.dart' show CompactPager;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, sortRows, toggleSort, SortState;
import '../poultry/trackers/tracker_widgets.dart';

/// One field of a resource form: key, label, kind (text / int / decimal / notes).
typedef ResField = (String key, String label, String kind, String? hint);

class _Kind {
  const _Kind({
    required this.tab,
    required this.icon,
    required this.title,
    required this.description,
    required this.addLabel,
    required this.addTitle,
    required this.addDescription,
    required this.editTitle,
    required this.editDescription,
    required this.deleteTitle,
    required this.nameKey,
    required this.fields,
    required this.columns,
    required this.updatedToast,
    required this.deletedToast,
  });
  final String tab, title, description, addLabel, addTitle, addDescription, editTitle, editDescription, deleteTitle, nameKey;
  final IconData icon;
  final List<ResField> fields;
  final List<(String header, String? sortKey)> columns;
  final (String, String) updatedToast, deletedToast;
}

const _vaccination = _Kind(
  tab: 'Vaccination Schedules',
  icon: Icons.calendar_today_outlined,
  title: 'Vaccination Schedules',
  description: 'Track vaccination schedules for your flocks',
  addLabel: 'Add Schedule',
  addTitle: 'Add Vaccination Schedule',
  addDescription: 'Create a new vaccination schedule entry',
  editTitle: 'Edit Vaccination Schedule',
  editDescription: 'Update this vaccination schedule entry.',
  deleteTitle: 'Delete Vaccination Schedule',
  nameKey: 'vaccineName',
  fields: [
    ('vaccineName', 'Vaccine Name *', 'text', null),
    ('ageInWeeks', 'Age (Weeks)', 'int', null),
    ('ageInDays', 'Age (Days)', 'int', null),
    ('dosage', 'Dosage *', 'text', null),
    ('route', 'Route *', 'text', null),
    ('notes', 'Notes', 'notes', null),
  ],
  columns: [('Vaccine Name', 'vaccineName'), ('Age', 'ageInDays'), ('Dosage', 'dosage'), ('Route', 'route'), ('Notes', null), ('Actions', null)],
  updatedToast: ('Schedule updated', 'Vaccination schedule updated successfully.'),
  deletedToast: ('Schedule deleted', 'The vaccination schedule has been removed.'),
);

const _medication = _Kind(
  tab: 'Medication Schedules',
  icon: Icons.medication_outlined,
  title: 'Medication Schedules',
  description: 'Track medication schedules for your flocks',
  addLabel: 'Add Schedule',
  addTitle: 'Add Medication Schedule',
  addDescription: 'Create a new medication schedule entry',
  editTitle: 'Edit Medication Schedule',
  editDescription: 'Update this medication schedule entry.',
  deleteTitle: 'Delete Medication Schedule',
  nameKey: 'medicationName',
  fields: [
    ('medicationName', 'Medication Name *', 'text', null),
    ('ageInWeeks', 'Age (Weeks)', 'int', null),
    ('ageInDays', 'Age (Days)', 'int', null),
    ('dosage', 'Dosage *', 'text', null),
    ('frequency', 'Frequency *', 'text', null),
    ('duration', 'Duration *', 'text', null),
    ('notes', 'Notes', 'notes', null),
  ],
  columns: [
    ('Medication Name', 'medicationName'), ('Age', 'ageInDays'), ('Dosage', 'dosage'), ('Frequency', 'frequency'), ('Duration', 'duration'), ('Notes', null),
    ('Actions', null),
  ],
  updatedToast: ('Schedule updated', 'Medication schedule updated successfully.'),
  deletedToast: ('Schedule deleted', 'The medication schedule has been removed.'),
);

const _feed = _Kind(
  tab: 'Feed Formulations',
  icon: Icons.restaurant_outlined,
  title: 'Feed Formulations',
  description: 'Manage feed composition and nutritional information',
  addLabel: 'Add Formulation',
  addTitle: 'Add Feed Formulation',
  addDescription: 'Create a new feed formulation entry',
  editTitle: 'Edit Feed Formulation',
  editDescription: 'Update this feed formulation entry.',
  deleteTitle: 'Delete Feed Formulation',
  nameKey: 'feedName',
  fields: [
    ('feedName', 'Feed Name *', 'text', null),
    ('ageRange', 'Age Range *', 'text', 'e.g., 0-4 weeks'),
    ('protein', 'Protein (%)', 'decimal', null),
    ('energy', 'Energy (kcal/kg)', 'decimal', null),
    ('ingredients', 'Ingredients *', 'notes', null),
    ('notes', 'Notes', 'notes', null),
  ],
  columns: [
    ('Feed Name', 'feedName'), ('Age Range', 'ageRange'), ('Protein (%)', 'protein'), ('Energy (kcal/kg)', 'energy'), ('Ingredients', null), ('Notes', null),
    ('Actions', null),
  ],
  updatedToast: ('Formulation updated', 'Feed formulation updated successfully.'),
  deletedToast: ('Formulation deleted', 'The feed formulation has been removed.'),
);

const _kinds = [_vaccination, _medication, _feed];

String resourceAge(Map r) {
  final w = tNum(r['ageInWeeks']), d = tNum(r['ageInDays']);
  return [if (w > 0) '${w.toInt()} weeks', if (d > 0) '${d.toInt()} days'].join(', ');
}

class ResourcesScreen extends StatefulWidget {
  const ResourcesScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;
  @override
  State<ResourcesScreen> createState() => _ResourcesScreenState();
}

class _ResourcesScreenState extends State<ResourcesScreen> {
  int _tab = 0;
  SortState _sort = (key: null, dir: null);
  final _pages = [1, 1, 1], _sizes = [10, 10, 10];
  final List<List<Map<String, Object?>>> _data = [
    [
      {'id': 1, 'vaccineName': 'Newcastle Disease', 'ageInWeeks': 0, 'ageInDays': 1, 'dosage': '0.2ml', 'route': 'Eye drop', 'notes': 'First vaccination'},
      {'id': 2, 'vaccineName': 'Infectious Bursal Disease', 'ageInWeeks': 2, 'ageInDays': 14, 'dosage': '0.2ml', 'route': 'Drinking water', 'notes': 'Second vaccination'},
    ],
    [
      {
        'id': 1, 'medicationName': 'Vitamin Supplement', 'ageInWeeks': 0, 'ageInDays': 1, 'dosage': '1ml per liter', 'frequency': 'Daily',
        'duration': 'First week', 'notes': 'Boost immunity',
      },
    ],
    [
      {
        'id': 1, 'feedName': 'Starter Feed', 'ageRange': '0-4 weeks', 'protein': 20, 'energy': 3000, 'ingredients': 'Corn, Soybean meal, Fish meal, Vitamins',
        'notes': 'For day-old to 4 weeks',
      },
      {
        'id': 2, 'feedName': 'Grower Feed', 'ageRange': '4-16 weeks', 'protein': 18, 'energy': 2900, 'ingredients': 'Corn, Soybean meal, Wheat, Vitamins',
        'notes': 'For growing birds',
      },
    ],
  ];

  Future<void> _form(int k, {Map<String, Object?>? editing}) async {
    final kind = _kinds[k];
    final values = <String, Object?>{
      for (final (key, _, type, _) in kind.fields) key: editing?[key] ?? (type == 'int' || type == 'decimal' ? 0 : ''),
    };
    final saved = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => _ResourceDialog(
        title: editing == null ? kind.addTitle : kind.editTitle,
        description: editing == null ? kind.addDescription : kind.editDescription,
        fields: kind.fields,
        values: values,
        submitLabel: editing == null ? kind.addLabel : 'Save Changes',
      ),
    );
    if (saved == null || !mounted) return;
    setState(() {
      if (editing == null) {
        _data[k].add({...saved, 'id': DateTime.now().millisecondsSinceEpoch});
      } else {
        final i = _data[k].indexWhere((r) => r['id'] == editing['id']);
        if (i >= 0) _data[k][i] = {...saved, 'id': editing['id']};
      }
    });
    if (editing != null) trackerToast(context, kind.updatedToast.$1, description: kind.updatedToast.$2);
  }

  Future<void> _delete(int k, Map r) async {
    final kind = _kinds[k];
    final ok = await confirmDelete(context, title: kind.deleteTitle, description: 'Are you sure you want to delete "${tStr(r[kind.nameKey])}"? This action cannot be undone.');
    if (ok != true || !mounted) return;
    setState(() => _data[k].removeWhere((x) => x['id'] == r['id']));
    trackerToast(context, kind.deletedToast.$1, description: kind.deletedToast.$2);
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/resources');
    final kind = _kinds[_tab];
    final rows = sortRows(_data[_tab], _sort, (r, key) => r[key] is num ? r[key] as num : tStr(r[key]));
    final pages = rows.isEmpty ? 1 : (rows.length + _sizes[_tab] - 1) ~/ _sizes[_tab];
    final page = _pages[_tab].clamp(1, pages);
    final pageRows = rows.skip((page - 1) * _sizes[_tab]).take(_sizes[_tab]).toList();
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Resources')),
      body: ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 28), children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.menu_book_outlined, size: 20, color: Color(0xFF16A34A)),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Resources & Information Center', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: TColors.slate900)),
              Text('Access vaccination schedules, medication guides, and feed formulations', style: TextStyle(color: TColors.slate600)),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: TColors.slate100, borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            for (var i = 0; i < _kinds.length; i++)
              Expanded(
                child: InkWell(
                  key: ValueKey('res-tab-$i'),
                  onTap: () => setState(() => _tab = i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    decoration: BoxDecoration(color: _tab == i ? Colors.white : null, borderRadius: BorderRadius.circular(6)),
                    child: Column(children: [
                      Icon(_kinds[i].icon, size: 16, color: _tab == i ? TColors.slate900 : TColors.slate500),
                      const SizedBox(height: 2),
                      Text(_kinds[i].tab,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: _tab == i ? TColors.slate900 : TColors.slate500)),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 16),
        TCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(kind.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: TColors.slate900)),
            Text(kind.description, style: const TextStyle(fontSize: 14, color: TColors.slate500)),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: TColors.blue600),
                onPressed: () => _form(_tab),
                icon: const Icon(Icons.add, size: 16),
                label: Text(kind.addLabel),
              ),
            ),
            const SizedBox(height: 12),
            TrackerTable(
              sort: _sort,
              onSort: (k) => setState(() => _sort = toggleSort(k, _sort)),
              columns: [for (final (h, k) in kind.columns) TCol(h, sortKey: k, width: h == 'Ingredients' ? 220 : (h == 'Actions' ? 120 : 140), right: h == 'Actions')],
              rows: [for (final r in pageRows) _cells(_tab, r)],
            ),
            CompactPager(
              total: rows.length,
              page: page,
              pageSize: _sizes[_tab],
              onPage: (p) => setState(() => _pages[_tab] = p),
              onPageSize: (s) => setState(() {
                _sizes[_tab] = s;
                _pages[_tab] = 1;
              }),
            ),
          ]),
        ),
      ]),
    );
  }

  List<Widget> _cells(int k, Map<String, Object?> r) {
    String notes() => tStr(r['notes']).isEmpty ? '-' : tStr(r['notes']);
    Widget badge(String s) => Align(alignment: Alignment.centerLeft, child: TBadge(s, bg: Colors.white, fg: TColors.slate800, border: TColors.slate200));
    final actions = Row(mainAxisAlignment: MainAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
      IconButton(visualDensity: VisualDensity.compact, tooltip: 'Edit', icon: const Icon(Icons.edit_outlined, size: 16), onPressed: () => _form(k, editing: r)),
      IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Delete',
          icon: const Icon(Icons.delete_outline, size: 16, color: TColors.red600),
          onPressed: () => _delete(k, r)),
    ]);
    return switch (k) {
      0 => [cellText(tStr(r['vaccineName']), bold: true), cellText(resourceAge(r)), cellText(tStr(r['dosage'])), badge(tStr(r['route'])), cellText(notes()), actions],
      1 => [
          cellText(tStr(r['medicationName']), bold: true), cellText(resourceAge(r)), cellText(tStr(r['dosage'])), cellText(tStr(r['frequency'])),
          cellText(tStr(r['duration'])), cellText(notes()), actions,
        ],
      _ => [
          cellText(tStr(r['feedName']), bold: true),
          badge(tStr(r['ageRange'])),
          cellText('${_n(r['protein'])}%'),
          cellText(_thousands(tNum(r['energy']))),
          Text(tStr(r['ingredients']), maxLines: 1, overflow: TextOverflow.ellipsis),
          cellText(notes()),
          actions,
        ],
    };
  }

  String _n(Object? v) {
    final n = tNum(v);
    return n == n.roundToDouble() ? '${n.toInt()}' : '$n';
  }

  String _thousands(num v) {
    final s = _n(v);
    final parts = s.split('.');
    final whole = parts[0].replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
    return parts.length > 1 ? '$whole.${parts[1]}' : whole;
  }
}

/// The Add / Edit dialog for one resource kind.
class _ResourceDialog extends StatefulWidget {
  const _ResourceDialog({required this.title, required this.description, required this.fields, required this.values, required this.submitLabel});
  final String title, description, submitLabel;
  final List<ResField> fields;
  final Map<String, Object?> values;
  @override
  State<_ResourceDialog> createState() => _ResourceDialogState();
}

class _ResourceDialogState extends State<_ResourceDialog> {
  late final _c = {
    for (final (key, _, type, _) in widget.fields)
      key: TextEditingController(text: type == 'int' || type == 'decimal' ? _num(widget.values[key]) : tStr(widget.values[key])),
  };

  String _num(Object? v) {
    final n = tNum(v);
    return n == n.roundToDouble() ? '${n.toInt()}' : '$n';
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, Object?> get _result => {
        for (final (key, _, type, _) in widget.fields)
          key: switch (type) {
            'int' => int.tryParse(_c[key]!.text.trim()) ?? 0,
            'decimal' => num.tryParse(_c[key]!.text.trim()) ?? 0,
            _ => _c[key]!.text,
          },
      };

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(widget.description, style: const TextStyle(fontSize: 14, color: TColors.slate500)),
              const SizedBox(height: 12),
              for (final (key, label, type, hint) in widget.fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate700)),
                    const SizedBox(height: 4),
                    AppInput(
                      controller: _c[key],
                      hintText: hint,
                      minLines: type == 'notes' ? 2 : null,
                      maxLines: type == 'notes' ? 4 : 1,
                      keyboardType: type == 'int'
                          ? TextInputType.number
                          : type == 'decimal'
                              ? const TextInputType.numberWithOptions(decimal: true)
                              : null,
                    ),
                  ]),
                ),
            ]),
          ),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: TColors.red600),
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(onPressed: () => Navigator.pop(context, _result), child: Text(widget.submitLabel)),
        ],
      );
}
