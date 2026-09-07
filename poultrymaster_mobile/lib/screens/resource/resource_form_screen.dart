import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:intl/intl.dart';

import '../../core/json.dart';
import '../../core/theme.dart';
import '../../resources/resource_spec.dart';
import '../../services/farm_service.dart';
import '../../widgets/common.dart';

/// Create/edit form generated from a [ResourceSpec]'s field list.
class ResourceFormScreen extends StatefulWidget {
  final ResourceSpec spec;
  final Map<String, dynamic>? item;
  const ResourceFormScreen({super.key, required this.spec, this.item});

  @override
  State<ResourceFormScreen> createState() => _ResourceFormScreenState();
}

class _ResourceFormScreenState extends State<ResourceFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _text = {};
  final Map<String, DateTime?> _dates = {};
  final Map<String, dynamic> _refs = {};
  final Map<String, String?> _dropdowns = {};
  final Map<String, bool> _toggles = {};
  final Map<String, List<Map<String, dynamic>>> _refOptions = {};
  bool _busy = false;

  ResourceSpec get spec => widget.spec;
  bool get isEdit => widget.item != null;
  final _dateFmt = DateFormat('d MMM yyyy');

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    for (final f in spec.fields) {
      switch (f.type) {
        case FieldType.text:
        case FieldType.multiline:
        case FieldType.integer:
        case FieldType.decimal:
          var initial = item == null ? '' : pickString(item, [f.key]);
          // Don't prefill numeric zeros — they read as junk in a fresh form.
          if ((f.type == FieldType.integer || f.type == FieldType.decimal) &&
              (initial == '0' || initial == '0.0')) {
            initial = item == null ? '' : initial;
          }
          _text[f.key] = TextEditingController(text: initial);
        case FieldType.date:
          _dates[f.key] = item == null ? DateTime.now() : pickDate(item, [f.key]) ?? DateTime.now();
        case FieldType.dropdown:
          final v = item == null ? null : pickString(item, [f.key]);
          _dropdowns[f.key] = (v != null && f.options!.contains(v)) ? v : null;
        case FieldType.reference:
          final v = item == null ? null : pick(item, [f.key]);
          _refs[f.key] = (v is num && v == 0) ? null : v;
          _loadRefOptions(f);
        case FieldType.toggle:
          _toggles[f.key] = item == null ? true : pickBool(item, [f.key], true);
      }
    }
  }

  Future<void> _loadRefOptions(FieldSpec f) async {
    try {
      final items = await FarmService.list(f.refEndpoint!);
      if (mounted) setState(() => _refOptions[f.key] = items);
    } catch (_) {
      // Dropdown stays empty; the user can still save non-required refs.
    }
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _buildBody() {
    final body = <String, dynamic>{};
    for (final f in spec.fields) {
      switch (f.type) {
        case FieldType.text:
        case FieldType.multiline:
          body[f.key] = _text[f.key]!.text.trim();
        case FieldType.integer:
          body[f.key] = int.tryParse(_text[f.key]!.text.trim()) ?? 0;
        case FieldType.decimal:
          body[f.key] = double.tryParse(_text[f.key]!.text.trim()) ?? 0;
        case FieldType.date:
          final d = _dates[f.key] ?? DateTime.now();
          body[f.key] = DateFormat('yyyy-MM-dd').format(d);
        case FieldType.dropdown:
          body[f.key] = _dropdowns[f.key] ?? '';
        case FieldType.reference:
          if (_refs[f.key] != null) body[f.key] = _refs[f.key];
        case FieldType.toggle:
          body[f.key] = _toggles[f.key] ?? false;
      }
    }
    if (spec.derive != null) body.addAll(spec.derive!(body));
    if (isEdit) {
      body[spec.idKey] = pick(widget.item, [spec.idKey]);
      if (spec.extraUpdateBody != null) body.addAll(spec.extraUpdateBody!(widget.item!));
    }
    return body;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    for (final f in spec.fields) {
      if (f.type == FieldType.reference && f.required && _refs[f.key] == null) {
        showSnack(context, 'Please select a ${f.label.toLowerCase()}', error: true);
        return;
      }
      if (f.type == FieldType.dropdown && f.required && _dropdowns[f.key] == null) {
        showSnack(context, 'Please select a ${f.label.toLowerCase()}', error: true);
        return;
      }
    }
    setState(() => _busy = true);
    try {
      final body = _buildBody();
      if (isEdit) {
        await FarmService.update(spec.endpoint, pick(widget.item, [spec.idKey]), body);
      } else {
        await FarmService.create(spec.endpoint, body);
      }
      if (!mounted) return;
      showSnack(context, '${spec.singular} ${isEdit ? 'updated' : 'created'}');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit ${spec.singular}' : 'New ${spec.singular}')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              for (final f in spec.fields) ...[
                _buildField(f),
                const SizedBox(height: 16),
              ],
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child:
                            CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : Text(isEdit ? 'Save changes' : 'Create ${spec.singular}'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(FieldSpec f) {
    switch (f.type) {
      case FieldType.text:
      case FieldType.multiline:
        return TextFormField(
          controller: _text[f.key],
          maxLines: f.type == FieldType.multiline ? 3 : 1,
          decoration: InputDecoration(labelText: f.label, hintText: f.hint),
          validator: f.required
              ? (v) => (v == null || v.trim().isEmpty) ? '${f.label} is required' : null
              : null,
        );
      case FieldType.integer:
      case FieldType.decimal:
        return TextFormField(
          controller: _text[f.key],
          keyboardType:
              TextInputType.numberWithOptions(decimal: f.type == FieldType.decimal),
          decoration: InputDecoration(labelText: f.label, hintText: f.hint),
          validator: (v) {
            if (f.required && (v == null || v.trim().isEmpty)) {
              return '${f.label} is required';
            }
            if (v != null && v.trim().isNotEmpty && num.tryParse(v.trim()) == null) {
              return 'Enter a number';
            }
            return null;
          },
        );
      case FieldType.date:
        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _dates[f.key] ?? DateTime.now(),
              firstDate: DateTime(2015),
              lastDate: DateTime.now().add(const Duration(days: 365)),
            );
            if (picked != null) setState(() => _dates[f.key] = picked);
          },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: f.label,
              suffixIcon: const Icon(Iconsax.calendar_1, size: 20),
            ),
            child: Text(_dateFmt.format(_dates[f.key] ?? DateTime.now())),
          ),
        );
      case FieldType.dropdown:
        return DropdownButtonFormField<String>(
          initialValue: _dropdowns[f.key],
          decoration: InputDecoration(labelText: f.label),
          items: [
            for (final o in f.options!) DropdownMenuItem(value: o, child: Text(o)),
          ],
          onChanged: (v) => setState(() => _dropdowns[f.key] = v),
        );
      case FieldType.reference:
        final options = _refOptions[f.key];
        final ids = options?.map((o) => pick(o, [f.refIdKey!])).toSet() ?? {};
        return DropdownButtonFormField<dynamic>(
          initialValue: ids.contains(_refs[f.key]) ? _refs[f.key] : null,
          decoration: InputDecoration(
            labelText: f.label,
            suffixIcon: options == null
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : null,
          ),
          items: [
            if (!f.required) const DropdownMenuItem(value: null, child: Text('None')),
            for (final o in options ?? [])
              DropdownMenuItem(
                value: pick(o, [f.refIdKey!]),
                child: Text(pickString(o, f.refLabelKeys!, '—'),
                    overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => setState(() => _refs[f.key] = v),
        );
      case FieldType.toggle:
        return Card(
          child: SwitchListTile(
            title: Text(f.label, style: Theme.of(context).textTheme.bodyLarge),
            value: _toggles[f.key] ?? false,
            activeTrackColor: AppColors.primary,
            onChanged: (v) => setState(() => _toggles[f.key] = v),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
        );
    }
  }
}
