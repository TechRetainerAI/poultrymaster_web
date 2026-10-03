import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../design/ui/buttons.dart';
import '../design/ui/form_section.dart';
import '../design/ui/inputs.dart';
import '../api/api_client.dart';
import '../models/company.dart';
import '../state/session.dart';
import 'form_spec.dart';
import 'lookup_loader.dart';
import 'lookup_sources.dart';
import 'page_spec.dart';
import 'record_api.dart';

/// Renders a [FormDef] using the same section bands, column counts, labels and
/// input kinds the web uses.
///
/// The controls come from the ported kit, so a money field is ₵-prefixed and
/// two-decimal clamped, a number field is digits-only, and a date field opens
/// the platform picker — matching what each `<FormField>` wraps on the site.
class FormScreen extends StatefulWidget {
  const FormScreen({
    super.key,
    required this.def,
    required this.title,
    required this.company,
    this.session,
    this.spec,
    this.existing,
  });

  final FormDef def;
  final String title;
  final Company company;

  /// Needed to actually submit. Without these the screen is layout-only.
  final Session? session;
  final PageSpec? spec;

  /// When editing, the record being changed.
  final Map<String, dynamic>? existing;

  @override
  State<FormScreen> createState() => _FormScreenState();
}

class _FormScreenState extends State<FormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{};
  final _dates = <String, DateTime?>{};
  final _bools = <String, bool>{};
  final _selects = <String, String?>{};

  /// Dropdown options per field id: absent = still loading, empty = the site
  /// has no list for it either.
  final _options = <String, List<AppSelectItem<String>>>{};
  final _optionsFailed = <String>{};

  bool _saving = false;

  /// How many rows each line editor is showing. Starts at one, as the web
  /// does, and grows with "Add line".
  final Map<String, int> _lineCounts = {};

  TextEditingController _c(String id) =>
      _controllers.putIfAbsent(id, TextEditingController.new);

  @override
  void initState() {
    super.initState();
    _loadOptions();
    final row = widget.existing;
    if (row == null) {
      _applyInitials();
      return;
    }
    // Prefill from the record being edited, matching on the field name the
    // web binds to.
    for (final s in widget.def.sections) {
      for (final f in s.fields) {
        final name = f.name;
        if (name == null) continue;
        final v = row[name] ?? row[name[0].toLowerCase() + name.substring(1)];
        if (v == null) continue;
        final id = _id(s, f);
        switch (f.kind) {
          case FormFieldKind.bool:
            _bools[id] = v == true || '$v'.toLowerCase() == 'true';
          case FormFieldKind.date:
            _dates[id] = DateTime.tryParse('$v');
          case FormFieldKind.select:
            _selects[id] = f.yesNo
                ? (v == true || '$v'.toLowerCase() == 'true' ? 'yes' : 'no')
                : '$v';
          default:
            _c(id).text = '$v';
        }
      }
    }
  }

  /// A new record starts from the web's empty form, not a blank one.
  void _applyInitials() {
    for (final s in widget.def.sections) {
      for (final f in s.fields) {
        final v = f.initial;
        if (v == null) continue;
        final id = _id(s, f);
        switch (f.kind) {
          case FormFieldKind.bool:
            _bools[id] = v == 'true';
          case FormFieldKind.select:
            _selects[id] = v;
          case FormFieldKind.date:
            _dates[id] = DateTime.tryParse(v);
          default:
            _c(id).text = v;
        }
      }
    }
  }

  /// Fetches each dropdown's options from the endpoint the web reads.
  void _loadOptions() {
    final session = widget.session;
    final spec = widget.spec;
    if (session == null || spec == null) return;
    final loader = LookupLoader(session, widget.company);

    for (final s in widget.def.sections) {
      for (final f in s.fields) {
        if (f.kind != FormFieldKind.select || f.name == null) continue;
        final id = _id(s, f);
        final future = loader.optionsFor('${spec.key}.${f.name}', label: f.optionLabel);
        if (future == null) continue;      // no list on the web either
        future.then((items) {
          if (!mounted) return;
          setState(() => _options[id] = items);
        }).catchError((_) {
          if (!mounted) return;
          setState(() => _optionsFailed.add(id));
        });
      }
    }
  }

  /// Builds the payload from the field names the web binds to.
  Map<String, dynamic> _payload() {
    final out = <String, dynamic>{};
    for (final s in widget.def.sections) {
      for (final f in s.fields) {
        final name = f.name;
        if (name == null) continue;          // unnamed fields cannot be sent
        final id = _id(s, f);
        switch (f.kind) {
          case FormFieldKind.calc:
            break;                           // derived; the server recomputes
          case FormFieldKind.bool:
            out[name] = _bools[id] ?? false;
          case FormFieldKind.date:
            final d = _dates[id];
            if (d != null) out[name] = d.toIso8601String();
          case FormFieldKind.select:
            final v = _selects[id];
            if (v != null && v.isNotEmpty) {
              // A numeric id goes as a number, as the web sends it
              // (`defaultVehicleId: Number(v)`).
              out[name] = f.yesNo
                  ? v == 'yes'
                  : (name.endsWith('Id') && RegExp(r'^\d+$').hasMatch(v) ? int.parse(v) : v);
            }
          case FormFieldKind.money:
          case FormFieldKind.number:
            final t = _controllers[id]?.text.trim() ?? '';
            if (t.isNotEmpty) out[name] = num.tryParse(t) ?? t;
          case FormFieldKind.text:
          case FormFieldKind.textarea:
            final t = _controllers[id]?.text.trim() ?? '';
            if (t.isNotEmpty) out[name] = t;
        }
      }
      // Line rows go as a list of maps under the section's line name, which
      // is the shape the web posts them in.
      final lines = s.lines;
      if (lines != null) {
        final rows = <Map<String, dynamic>>[];
        for (var i = 0; i < (_lineCounts[lines.name] ?? 1); i++) {
          final row = <String, dynamic>{};
          for (final f in lines.fields) {
            final name = f.name;
            if (name == null || f.kind == FormFieldKind.calc) continue;
            final id = '${lines.name}#$i:${f.label}';
            if (f.kind == FormFieldKind.select) {
              final v = _selects[id];
              if (v != null && v.isNotEmpty) row[name] = v;
            } else {
              final t = _controllers[id]?.text.trim() ?? '';
              if (t.isNotEmpty) {
                row[name] = f.kind == FormFieldKind.number ||
                        f.kind == FormFieldKind.money
                    ? (num.tryParse(t) ?? t)
                    : t;
              }
            }
          }
          if (row.isNotEmpty) rows.add(row);
        }
        if (rows.isNotEmpty) out[lines.name] = rows;
      }
    }
    return out;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final session = widget.session;
    final spec = widget.spec;
    if (session == null || spec == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('This form is not connected to an endpoint.')));
      return;
    }

    setState(() => _saving = true);
    final api = RecordApi(session, spec, widget.company);
    final body = _payload();
    try {
      final id =
          widget.existing == null ? null : api.idIn(widget.existing!);
      final idKey = widget.def.idKey;
      if (idKey != null) body[idKey] = id ?? 0;
      final me = session.tokens.userId ?? '';
      final stamp = id == null ? widget.def.createdByKey : widget.def.updatedByKey;
      if (stamp != null) body[stamp] = me;
      for (final k in widget.def.carry) {
        final v = widget.existing?[k];
        if (v != null) body[k] = v;
      }
      if (id == null) {
        await api.create(body);
      } else {
        await api.update(id, body);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.existing == null ? 'Created' : 'Saved')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      // Surface the API's own message: these endpoints explain what is wrong
      // (missing field, wrong company type) far better than a generic error.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _id(FormSectionDef s, FormFieldDef f) =>
      f.name ?? '${s.title}:${f.label}';

  Widget _control(FormSectionDef s, FormFieldDef f) {
    final id = _id(s, f);
    String? req(String? v) => f.required && (v == null || v.trim().isEmpty)
        ? 'Required'
        : null;

    switch (f.kind) {
      case FormFieldKind.calc:
        // The web works these out and shows them read-only; the server
        // recomputes them on save, so this never collects a value.
        return AppInput(
          controller: _c(id),
          enabled: false,
          hintText: f.placeholder ?? 'Worked out on save',
        );
      case FormFieldKind.money:
        return AppMoneyInput(controller: _c(id), validator: req);
      case FormFieldKind.number:
        return AppNumberInput(
          controller: _c(id),
          validator: req,
          allowDecimal: f.decimal,
          hintText: f.placeholder ?? '0',
        );
      case FormFieldKind.textarea:
        return AppTextarea(
          controller: _c(id),
          hintText: f.placeholder,
          validator: req,
        );
      case FormFieldKind.date:
        final today = DateTime.now();
        return AppDateField(
          value: _dates[id],
          hintText: f.placeholder ?? 'Pick a date',
          firstDate: f.dateBound == DateBound.future
              ? DateTime(today.year, today.month, today.day)
              : null,
          lastDate: f.dateBound == DateBound.past ? today : null,
          onChanged: (d) => setState(() => _dates[id] = d),
        );
      case FormFieldKind.bool:
        return AppSwitchRow(
          label: f.placeholder ?? 'Yes',
          value: _bools[id] ?? false,
          onChanged: (v) => setState(() => _bools[id] = v),
        );
      case FormFieldKind.select:
        final slot = widget.spec == null || f.name == null
            ? null
            : '${widget.spec!.key}.${f.name}';
        // A foreign key is worth ATTEMPTING even with no generated source:
        // LookupLoader can find the collection at run time, on a farm that
        // actually has rows, and proves it before using it. Declaring it
        // unknown up front is what left 142 dropdowns reading "Type it on
        // the web" when many of them are perfectly resolvable.
        final declared = slot != null &&
            (lookupSources.containsKey(slot) || staticOptions.containsKey(slot));
        final resolvable = declared || (f.name?.endsWith('Id') ?? false);
        // A list GUESSED at run time that came back empty is no list at all.
        // A declared list that is empty is real and just has nothing in it
        // yet ("No vehicles. Add one on the Vehicles page first.") — saying
        // "type it on the web" there was wrong, and read as a broken field.
        final searched = _options.containsKey(id);
        final known = declared ||
            (resolvable && !(searched && (_options[id]?.isEmpty ?? false)));
        final items = _options[id];
        final loading = known && items == null && !_optionsFailed.contains(id);

        // A selected value that is not in the list would assert in
        // DropdownButtonFormField, which happens while editing a record whose
        // option list is still loading.
        final selected = _selects[id];
        final value = items != null && items.any((i) => i.value == selected)
            ? selected
            : null;

        return AppSelect<String>(
          value: value,
          enabled: !loading,
          hintText: loading
              ? 'Loading…'
              : _optionsFailed.contains(id)
                  ? 'Could not load options'
                  : !known
                      // Honest rather than faked: the web fills this one from
                      // somewhere this build could not trace.
                      ? 'Type it on the web'
                      : (items?.isEmpty ?? true)
                          ? f.emptyHint ?? 'Nothing to choose yet'
                          : f.placeholder ?? 'Select…',
          items: items ?? const [],
          validator: req,
          onChanged: (v) => setState(() => _selects[id] = v),
        );
      case FormFieldKind.text:
        return AppInput(
          controller: _c(id),
          hintText: f.placeholder,
          validator: req,
        );
    }
  }

  /// One control of a line row. Rows are keyed by index so each keeps its
  /// own controllers as rows are added.
  Widget _lineControl(FormLineDef l, int i, FormFieldDef f) {
    final id = '${l.name}#$i:${f.label}';
    switch (f.kind) {
      case FormFieldKind.calc:
        return AppInput(
            controller: _c(id), enabled: false, hintText: '—');
      case FormFieldKind.select:
        final slot = widget.spec == null
            ? null
            : '${widget.spec!.key}.${l.name}.${f.name}';
        final items = slot == null ? null : _options[slot];
        return AppSelect<String>(
          value: _selects[id],
          hintText: (items?.isEmpty ?? true)
              ? (f.placeholder ?? 'Nothing to choose yet')
              : (f.placeholder ?? 'Select…'),
          items: items ?? const [],
          onChanged: (v) => setState(() => _selects[id] = v),
        );
      case FormFieldKind.money:
        return AppMoneyInput(controller: _c(id));
      case FormFieldKind.number:
        return AppNumberInput(controller: _c(id), hintText: '0');
      default:
        return AppInput(controller: _c(id), hintText: f.placeholder);
    }
  }

  Widget _lineEditor(FormLineDef l) {
    final count = _lineCounts[l.name] ?? 1;
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final f in l.fields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppField(
                      label: f.label,
                      required: f.required,
                      child: _lineControl(l, i, f),
                    ),
                  ),
                if (count > 1)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => setState(() {
                        // Drop the last row: the rows below would otherwise
                        // have to be shuffled between controllers.
                        _lineCounts[l.name] = count - 1;
                      }),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Remove line'),
                    ),
                  ),
                Divider(color: tokens.border, height: 18),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () =>
                setState(() => _lineCounts[l.name] = count + 1),
            icon: const Icon(Icons.add, size: 18),
            label: Text(l.addLabel),
          ),
        ),
      ],
    );
  }

  int get _unnamedCount => widget.def.sections
      .expand((s) => s.fields)
      .where((f) => f.name == null && f.kind != FormFieldKind.calc)
      .length;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            Text(widget.company.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: tokens.mutedForeground)),
          ],
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
          children: [
            for (final s in widget.def.sections) ...[
              FormSection(
                title: s.title,
                color: s.sectionColor,
                columns: s.columns,
                children: [
                  if (s.description != null)
                    AppField(label: '', full: true,
                        child: Text(s.description!,
                            style: TextStyle(
                                fontSize: 12, color: tokens.mutedForeground))),
                  if (s.lines != null)
                    AppField(label: '', full: true, child: _lineEditor(s.lines!)),
                  for (final f in s.fields)
                    AppField(
                      label: f.label,
                      required: f.required,
                      hint: f.hint,
                      full: f.full || f.kind == FormFieldKind.textarea,
                      child: _control(s, f),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 6),
            if (_unnamedCount > 0) ...[
              _FieldNotice(unnamed: _unnamedCount, total: widget.def.fieldCount),
              const SizedBox(height: 12),
            ],
            AppButton(
              label: widget.existing == null ? 'Save' : 'Update',
              fullWidth: true,
              size: AppButtonSize.lg,
              busy: _saving,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}

/// Some extracted fields have no bound name in the web markup, so they cannot
/// be sent. Saying which, rather than dropping them silently.
class _FieldNotice extends StatelessWidget {
  const _FieldNotice({required this.unnamed, required this.total});
  final int unnamed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.muted,
        borderRadius: BorderRadius.circular(Dim.radiusMd),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 17, color: tokens.mutedForeground),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '$unnamed of $total fields are not bound to a name in the web '
              'markup, so they will not be sent. The rest save normally.',
              style: TextStyle(
                  fontSize: 12.5, height: 1.4, color: tokens.mutedForeground),
            ),
          ),
        ],
      ),
    );
  }
}
