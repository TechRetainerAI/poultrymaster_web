// Generic → School (only for School businesses, generic-nav-config.ts):
// Classes (`app/generic-classes/page.tsx`), Academic Terms
// (`app/generic-terms/page.tsx`) and Student Attendance
// (`app/generic-student-attendance/page.tsx`).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../poultry/trackers/tracker_logic.dart' show tStr, tIntOrNull;
import '../../poultry/trackers/tracker_widgets.dart';
import '../../shared/business_dates.dart';
import '../delivery/delivery_kit.dart' show activeBadge, dField, dialogButtons;
import '../generic_kit.dart';

import 'package:poultrycore_mobile/design/tone.dart';

String _or(Object? v) => tStr(v).isEmpty ? '—' : tStr(v);

/// The web's fmtDate: "Nov 12, 2026".
String schoolDate(Object? d) {
  final t = DateTime.tryParse(tStr(d));
  return t == null ? '—' : DateFormat('MMM d, y').format(t);
}

/// The Terms dialog's checks, in the web's order; null when it may save.
String? checkTerm(String name, String start, String end) {
  if (name.trim().isEmpty) return 'Term name is required';
  if (start.isEmpty || end.isEmpty) return 'Start and end dates are required';
  if (end.compareTo(start) <= 0) return 'End date must be after start date';
  return null;
}

/// A school list page: title, Add button, a card table, edit and delete.
class _SchoolList extends StatelessWidget {
  const _SchoolList({
    required this.session,
    required this.company,
    required this.href,
    required this.title,
    required this.icon,
    this.subtitle,
    required this.addLabel,
    required this.onAdd,
    required this.loading,
    required this.empty,
    required this.columns,
    required this.rows,
    required this.onRefresh,
  });
  final Session session;
  final Company company;
  final String href, title, addLabel, empty;
  final IconData icon;
  final Widget? subtitle;
  final VoidCallback onAdd;
  final bool loading;
  final List<TCol> columns;
  final List<List<Widget>> rows;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, session, company, href: href);
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: Text(title)),
      body: RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
          Row(children: [
            Icon(icon, size: 20, color: TColors.slate900),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: TColors.slate900))),
          ]),
          ?subtitle,
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(key: const ValueKey('school-add'), onPressed: onAdd, icon: const Icon(Icons.add, size: 18), label: Text(addLabel)),
          ),
          const SizedBox(height: 12),
          TCard(
            child: loading
                ? const Padding(padding: EdgeInsets.symmetric(vertical: 36), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                : rows.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 36),
                        child: Text(empty, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: TColors.slate500)),
                      )
                    : TrackerTable(columns: columns, rows: rows),
          ),
        ]),
      ),
    );
  }
}

Widget _rowButtons(VoidCallback edit, VoidCallback del, String name) => Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(key: ValueKey('edit-$name'), visualDensity: VisualDensity.compact, onPressed: edit, icon: const Icon(Icons.edit_outlined, size: 16, color: TColors.slate600)),
      IconButton(key: ValueKey('delete-$name'), visualDensity: VisualDensity.compact, onPressed: del, icon: const Icon(Icons.delete_outline, size: 16, color: Tone.fg(0xFFEF4444))),
    ]);

Widget _switchRow(String label, bool v, ValueChanged<bool> on, Key key) => Row(children: [
      Switch(key: key, value: v, onChanged: on),
      const SizedBox(width: 6),
      Flexible(child: Text(label, style: const TextStyle(fontSize: 14, color: TColors.slate700))),
    ]);

/// Shared load / delete for Classes and Terms.
mixin _Crud<W extends StatefulWidget> on State<W> {
  Session get session;
  Company get company;
  String get path;
  String get plural;
  List<Map> rows = [];
  bool loading = true;
  String get base => '${genericBase(company)}/$path';

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final r = rowsOf(await session.farmClient.get(base));
      if (mounted) setState(() => rows = r);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load $plural', description: e.message, error: true);
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> remove(int? id, String title, String description, String done) async {
    if (!await confirmDelete(context, title: title, description: description)) return;
    try {
      await session.farmClient.delete('$base/$id');
      if (mounted) trackerToast(context, done);
      load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not delete', description: e.message, error: true);
    }
  }

  Future<void> edit(Widget dialog) async {
    if (await showDialog<bool>(context: context, builder: (_) => dialog) == true) load();
  }
}

// ----------------------------------------------------------------- Classes

class GenericClassesScreen extends StatefulWidget {
  const GenericClassesScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;
  @override
  State<GenericClassesScreen> createState() => _ClassesState();
}

class _ClassesState extends State<GenericClassesScreen> with _Crud {
  @override
  Session get session => widget.session;
  @override
  Company get company => widget.company;
  @override
  String get path => 'classes';
  @override
  String get plural => 'classes';

  @override
  void initState() {
    super.initState();
    load();
  }

  void _open([Map? c]) => edit(_ClassDialog(session: session, company: company, editing: c));

  @override
  Widget build(BuildContext context) => _SchoolList(
        session: session,
        company: company,
        href: '/generic-classes',
        title: 'Classes',
        icon: Icons.school_outlined,
        addLabel: 'Add class',
        onAdd: _open,
        loading: loading,
        onRefresh: load,
        empty: 'No classes yet. Add your first class above.',
        columns: const [
          TCol('Class', width: 130), TCol('Level', width: 70), TCol('Teacher', width: 130), TCol('Students', width: 90),
          TCol('Capacity', width: 80), TCol('Status', width: 90), TCol('Actions', right: true, width: 100),
        ],
        rows: [
          for (final c in rows)
            [
              cellText(tStr(c['className']), bold: true),
              cellText(_or(c['classLevel'])),
              cellText(_or(c['classTeacher'])),
              Align(
                alignment: Alignment.centerLeft,
                child: TBadge('👥 ${tStr(c['studentCount']).isEmpty ? '0' : tStr(c['studentCount'])}', bg: TColors.slate100, fg: TColors.slate700),
              ),
              cellText(_or(c['capacity'])),
              Align(alignment: Alignment.centerLeft, child: activeBadge(c['isActive'] == true)),
              Align(
                alignment: Alignment.centerRight,
                child: _rowButtons(
                  () => _open(c),
                  () => remove(tIntOrNull(c['genericClassId']), 'Delete class',
                      'Are you sure you want to delete "${tStr(c['className'])}"? Students in this class will not be deleted.', 'Class deleted'),
                  tStr(c['className']),
                ),
              ),
            ],
        ],
      );
}

class _ClassDialog extends StatefulWidget {
  const _ClassDialog({required this.session, required this.company, this.editing});
  final Session session;
  final Company company;
  final Map? editing;
  @override
  State<_ClassDialog> createState() => _ClassDialogState();
}

class _ClassDialogState extends State<_ClassDialog> {
  late final Map _e = widget.editing ?? const {};
  late final _name = TextEditingController(text: tStr(_e['className']));
  late final _level = TextEditingController(text: tStr(_e['classLevel']));
  late final _teacher = TextEditingController(text: tStr(_e['classTeacher']));
  late final _capacity = TextEditingController(text: tStr(_e['capacity']));
  late final _desc = TextEditingController(text: tStr(_e['description']));
  late bool _active = widget.editing == null || _e['isActive'] == true;
  bool _saving = false;

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return trackerToast(context, 'Class name is required', error: true);
    setState(() => _saving = true);
    try {
      await widget.session.farmClient.post('${genericBase(widget.company)}/classes', body: {
        'genericClassId': tIntOrNull(_e['genericClassId']) ?? 0,
        'className': _name.text.trim(),
        'classLevel': _level.text.isEmpty ? null : num.tryParse(_level.text),
        'classTeacher': _teacher.text.isEmpty ? null : _teacher.text,
        'capacity': _capacity.text.isEmpty ? null : num.tryParse(_capacity.text),
        'description': _desc.text.isEmpty ? null : _desc.text,
        'isActive': _active,
      });
      if (!mounted) return;
      trackerToast(context, widget.editing != null ? 'Class updated' : 'Class created');
      Navigator.pop(context, true);
      return;
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not save', description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  Widget _whole(TextEditingController c, String hint, Key key) => AppInput(
        key: key,
        controller: c,
        hintText: hint,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: Text(widget.editing != null ? 'Edit class' : 'Add class'),
        content: SizedBox(
          width: 512,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('Define a class or grade level for your school.', style: TextStyle(fontSize: 14, color: TColors.slate500)),
            ),
            dField('Class name *', AppInput(key: const ValueKey('class-name'), controller: _name, hintText: 'e.g. Primary 1, JSS 2',
                inputFormatters: [LengthLimitingTextInputFormatter(100)])),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: dField('Level (for sorting)', _whole(_level, 'e.g. 1, 2, 3', const ValueKey('class-level')))),
              const SizedBox(width: 12),
              Expanded(child: dField('Capacity', _whole(_capacity, 'Max students', const ValueKey('class-capacity')))),
            ]),
            dField('Class teacher', AppInput(key: const ValueKey('class-teacher'), controller: _teacher, inputFormatters: [LengthLimitingTextInputFormatter(200)])),
            dField('Description', AppInput(controller: _desc, maxLines: 2, minLines: 2)),
            _switchRow('Active', _active, (v) => setState(() => _active = v), const ValueKey('class-active')),
          ]),
        ),
        actions: dialogButtons(context,
            label: widget.editing != null ? 'Save' : 'Create', saving: _saving, onSave: _save, saveKey: const ValueKey('class-save')),
      );
}

// ------------------------------------------------------------------- Terms

class GenericTermsScreen extends StatefulWidget {
  const GenericTermsScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;
  @override
  State<GenericTermsScreen> createState() => _TermsState();
}

class _TermsState extends State<GenericTermsScreen> with _Crud {
  @override
  Session get session => widget.session;
  @override
  Company get company => widget.company;
  @override
  String get path => 'academic-terms';
  @override
  String get plural => 'terms';

  @override
  void initState() {
    super.initState();
    load();
  }

  void _open([Map? t]) => edit(_TermDialog(session: session, company: company, editing: t));

  @override
  Widget build(BuildContext context) {
    final current = rows.where((t) => t['isCurrent'] == true).firstOrNull;
    return _SchoolList(
      session: session,
      company: company,
      href: '/generic-terms',
      title: 'Academic Terms',
      icon: Icons.calendar_today_outlined,
      subtitle: current == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text.rich(
                TextSpan(children: [
                  const TextSpan(text: 'Current term: '),
                  TextSpan(text: tStr(current['termName']), style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: ' (${schoolDate(current['startDate'])} — ${schoolDate(current['endDate'])})'),
                ]),
                style: const TextStyle(fontSize: 14, color: TColors.slate500),
              ),
            ),
      addLabel: 'Add term',
      onAdd: _open,
      loading: loading,
      onRefresh: load,
      empty: 'No terms yet. Add your first academic term above.',
      columns: const [TCol('Term', width: 180), TCol('Start', width: 110), TCol('End', width: 110), TCol('Status', width: 90), TCol('Actions', right: true, width: 100)],
      rows: [
        for (final t in rows)
          [
            Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
              cellText(tStr(t['termName']), bold: true),
              if (t['isCurrent'] == true) const TBadge('Current', bg: Tone.bg(0xFFE0E7FF), fg: Tone.fg(0xFF4338CA)),
            ]),
            cellText(schoolDate(t['startDate'])),
            cellText(schoolDate(t['endDate'])),
            Align(alignment: Alignment.centerLeft, child: activeBadge(t['isActive'] == true)),
            Align(
              alignment: Alignment.centerRight,
              child: _rowButtons(
                () => _open(t),
                () => remove(tIntOrNull(t['genericAcademicTermId']), 'Delete term', 'Are you sure you want to delete "${tStr(t['termName'])}"?', 'Term deleted'),
                tStr(t['termName']),
              ),
            ),
          ],
      ],
    );
  }
}

class _TermDialog extends StatefulWidget {
  const _TermDialog({required this.session, required this.company, this.editing});
  final Session session;
  final Company company;
  final Map? editing;
  @override
  State<_TermDialog> createState() => _TermDialogState();
}

class _TermDialogState extends State<_TermDialog> {
  late final Map _e = widget.editing ?? const {};
  late final _name = TextEditingController(text: tStr(_e['termName']));
  late String _start = tStr(_e['startDate']).length >= 10 ? tStr(_e['startDate']).substring(0, 10) : '';
  late String _end = tStr(_e['endDate']).length >= 10 ? tStr(_e['endDate']).substring(0, 10) : '';
  late bool _current = _e['isCurrent'] == true;
  late bool _active = widget.editing == null || _e['isActive'] == true;
  bool _saving = false;

  Future<void> _save() async {
    final problem = checkTerm(_name.text, _start, _end);
    if (problem != null) return trackerToast(context, problem, error: true);
    setState(() => _saving = true);
    try {
      await widget.session.farmClient.post('${genericBase(widget.company)}/academic-terms', body: {
        'genericAcademicTermId': tIntOrNull(_e['genericAcademicTermId']) ?? 0,
        'termName': _name.text.trim(),
        'startDate': _start,
        'endDate': _end,
        'isCurrent': _current,
        'isActive': _active,
      });
      if (!mounted) return;
      trackerToast(context, widget.editing != null ? 'Term updated' : 'Term created');
      Navigator.pop(context, true);
      return;
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not save', description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: Text(widget.editing != null ? 'Edit term' : 'Add term'),
        content: SizedBox(
          width: 512,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('Define an academic term or semester.', style: TextStyle(fontSize: 14, color: TColors.slate500)),
            ),
            dField('Term name *', AppInput(key: const ValueKey('term-name'), controller: _name, hintText: 'e.g. Term 1 2026, Semester 2',
                inputFormatters: [LengthLimitingTextInputFormatter(100)])),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: dField('Start date *', AppDateField(
                  key: const ValueKey('term-start'),
                  value: _start.isEmpty ? null : businessDateAsDateTime(_start),
                  onChanged: (v) => setState(() => _start = v == null ? '' : isoDay(v)),
                )),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: dField('End date *', AppDateField(
                  key: const ValueKey('term-end'),
                  value: _end.isEmpty ? null : businessDateAsDateTime(_end),
                  onChanged: (v) => setState(() => _end = v == null ? '' : isoDay(v)),
                )),
              ),
            ]),
            _switchRow('This is the current term', _current, (v) => setState(() => _current = v), const ValueKey('term-current')),
            _switchRow('Active', _active, (v) => setState(() => _active = v), const ValueKey('term-active')),
          ]),
        ),
        actions: dialogButtons(context,
            label: widget.editing != null ? 'Save' : 'Create', saving: _saving, onSave: _save, saveKey: const ValueKey('term-save')),
      );
}

// ------------------------------------------------------ Student attendance

const studentAttendanceStatuses = ['Present', 'Absent', 'Late', 'HalfDay', 'Excused'];

(Color, Color) _markColors(String s) => switch (s) {
      'Present' => (TColors.emerald100, TColors.emerald700),
      'Absent' => (const Tone.bg(0xFFFFE4E6), const Tone.fg(0xFFBE123C)),
      'Late' => (TColors.amber100, TColors.amber700),
      'HalfDay' => (TColors.blue100, const Tone.fg(0xFF1D4ED8)),
      _ => (TColors.slate100, TColors.slate600),
    };

/// The class list for the filter: the school's active classes, or when there
/// are none, the class names the students carry (sorted), as on the web.
List<String> attendanceClassNames(List<Map> classes, List<Map> students) => classes.isNotEmpty
    ? [for (final c in classes) tStr(c['className'])]
    : ({for (final s in students) if (tStr(s['classOrGrade']).isNotEmpty) tStr(s['classOrGrade'])}.toList()..sort());

class GenericStudentAttendanceScreen extends StatefulWidget {
  const GenericStudentAttendanceScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;
  @override
  State<GenericStudentAttendanceScreen> createState() => _AttendanceState();
}

class _AttendanceState extends State<GenericStudentAttendanceScreen> {
  bool _loading = true, _saving = false;
  List<Map> _students = [], _classes = [];
  String _date = DateTime.now().toIso8601String().substring(0, 10), _class = 'all';
  Map<int, String> _marks = {};

  String get _base => genericBase(widget.company);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await Future.wait([
        widget.session.farmClient.get('$_base/customers'),
        widget.session.farmClient.get('$_base/classes'),
        widget.session.farmClient.get('$_base/customer-attendance', query: {'date': _date}),
      ]);
      if (!mounted) return;
      setState(() {
        _students = rowsOf(r[0]).where((s) => s['isActive'] == true).toList();
        _classes = rowsOf(r[1]).where((c) => c['isActive'] == true).toList();
        _marks = {for (final a in rowsOf(r[2])) if (tIntOrNull(a['genericCustomerId']) != null) tIntOrNull(a['genericCustomerId'])!: tStr(a['status'])};
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  List<Map> get _shown => _class == 'all' ? _students : _students.where((s) => s['classOrGrade'] == _class).toList();
  int _id(Map s) => tIntOrNull(s['genericCustomerId']) ?? 0;

  Future<void> _saveAll() async {
    setState(() => _saving = true);
    final classId = _class == 'all' ? null : tIntOrNull(_classes.where((c) => c['className'] == _class).firstOrNull?['genericClassId']);
    final marked = _shown.where((s) => _marks[_id(s)] != null).toList();
    try {
      await Future.wait([
        for (final s in marked)
          widget.session.farmClient.post('$_base/customer-attendance', body: {
            'genericCustomerId': _id(s),
            'attendanceDate': _date,
            'status': _marks[_id(s)],
            'genericClassId': classId,
          }),
      ]);
      if (mounted) trackerToast(context, 'Attendance saved for ${marked.length} students');
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not save attendance', description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/generic-student-attendance');
    final shown = _shown;
    final marked = shown.where((s) => _marks[_id(s)] != null).length;
    final present = shown.where((s) => _marks[_id(s)] == 'Present').length;
    final absent = shown.where((s) => _marks[_id(s)] == 'Absent').length;
    final names = attendanceClassNames(_classes, _students);
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Student Attendance')),
      body: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
        const Row(children: [
          Icon(Icons.assignment_turned_in_outlined, size: 20, color: TColors.slate900),
          SizedBox(width: 8),
          Expanded(child: Text('Student Attendance', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: TColors.slate900))),
        ]),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: dField('Date', AppDateField(
              key: const ValueKey('att-date'),
              value: businessDateAsDateTime(_date),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _date = isoDay(v));
                _load();
              },
            )),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: dField('Class', AppSelect<String>(
              key: const ValueKey('att-class'),
              value: _class,
              items: [const AppSelectItem(value: 'all', label: 'All classes'), for (final n in names) AppSelectItem(value: n, label: n)],
              onChanged: (v) => setState(() => _class = v ?? 'all'),
            )),
          ),
        ]),
        Wrap(spacing: 6, children: [
          OutlinedButton(
            onPressed: () => setState(() => [for (final s in shown) _marks[_id(s)] = 'Present']),
            child: const Text('All Present'),
          ),
          OutlinedButton(
            onPressed: () => setState(() => [for (final s in shown) _marks[_id(s)] = 'Absent']),
            child: const Text('All Absent'),
          ),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, children: [
          TBadge('${shown.length} students', bg: TColors.slate100, fg: TColors.slate700),
          TBadge('$marked marked', bg: TColors.slate100, fg: TColors.slate700),
          TBadge('$present present', bg: TColors.emerald100, fg: TColors.emerald700),
          TBadge('$absent absent', bg: const Tone.bg(0xFFFFE4E6), fg: const Tone.fg(0xFFBE123C)),
        ]),
        const SizedBox(height: 12),
        TCard(
          padding: EdgeInsets.zero,
          child: _loading
              ? const Padding(padding: EdgeInsets.symmetric(vertical: 36), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
              : shown.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 36),
                      child: Text(_students.isEmpty ? 'No students found. Add students first.' : 'No students in this class.',
                          textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: TColors.slate500)),
                    )
                  : Column(children: [
                      for (final (i, s) in shown.indexed) ...[
                        if (i > 0) const Divider(height: 1, color: TColors.slate200),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(tStr(s['customerName']), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate900)),
                            Text(
                              '${tStr(s['admissionNumber']).isEmpty ? '' : '${tStr(s['admissionNumber'])} · '}${tStr(s['classOrGrade']).isEmpty ? 'No class' : tStr(s['classOrGrade'])}',
                              style: const TextStyle(fontSize: 12, color: TColors.slate500),
                            ),
                            const SizedBox(height: 6),
                            Wrap(spacing: 4, runSpacing: 4, children: [
                              for (final st in studentAttendanceStatuses)
                                _markButton(st, _marks[_id(s)] == st, () => setState(() => _marks[_id(s)] = st), ValueKey('mark-${_id(s)}-$st')),
                            ]),
                          ]),
                        ),
                      ],
                    ]),
        ),
        if (shown.isNotEmpty) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: const ValueKey('att-save'),
              onPressed: _saving || marked == 0 ? null : _saveAll,
              icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check, size: 18),
              label: Text(_saving ? 'Saving…' : 'Save attendance ($marked)'),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _markButton(String st, bool on, VoidCallback tap, Key key) {
    final c = _markColors(st);
    return InkWell(
      key: key,
      onTap: tap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: on ? c.$1 : TColors.slate50, borderRadius: BorderRadius.circular(6)),
        child: Text(st == 'HalfDay' ? 'Half' : st,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: on ? c.$2 : const Tone.fg(0xFF94A3B8))),
      ),
    );
  }
}
