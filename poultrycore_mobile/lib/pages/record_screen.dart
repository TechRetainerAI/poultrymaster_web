import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../design/tokens.dart';
import '../design/ui/form_section.dart';
import '../models/company.dart';
import '../state/session.dart';
import '../widgets/module_sidebar.dart';
import '../design/ui/buttons.dart';
import 'form_screen.dart';
import 'module_registry.dart';
import 'page_extras.dart';
import 'list_screen.dart' show formatValue;
import 'form_spec.dart';
import 'page_actions.dart';
import 'list_header.dart';
import 'page_spec.dart';
import 'plumbing_fields.dart';
import 'page_verbs.dart';
import 'record_api.dart';

/// One record, shown in the same coloured sections the web uses for detail and
/// edit views.
///
/// The fields a table shows as columns are listed here instead — on a phone the
/// list card carries the two or three that matter and the rest live one tap in,
/// rather than off the right edge of a scrolling table.
class RecordScreen extends StatelessWidget {
  const RecordScreen({
    super.key,
    required this.spec,
    required this.row,
    required this.company,
    this.session,
  });

  final PageSpec spec;
  final Map<String, dynamic> row;
  final Company company;

  /// Needed for edit and delete. Without it the screen stays read-only.
  final Session? session;

  /// The page's name as the website gives it, never the API action name.
  String get _name => headerFor(spec.key, spec.title).title;

  /// The web form for this record's page, when one was extracted.
  FormDef? get _form => formForSpec(spec.key);

  /// What the API itself accepts on this endpoint.
  PageVerbs get _verbs => pageVerbs[spec.key] ?? const PageVerbs();

  /// Three things have to line up before Edit is honest: the web offers it
  /// here (reports and balances are read-only there too), the API accepts a
  /// PUT, and a form was extracted to edit with.
  bool get _canEdit =>
      (pageActions[spec.key] ?? const PageActions()).canEdit &&
      // A custom screen saves through its own endpoint (Feed Formulas
      // upserts with POST), so the PUT verb only matters for FormScreen.
      ((_verbs.put && _form != null) || customForms.containsKey(spec.key)) &&
      session != null;

  bool get _canDelete =>
      (pageActions[spec.key] ?? const PageActions()).canDelete &&
      _verbs.delete &&
      (deleteGuards[spec.key]?.call(row) ?? true) &&
      session != null &&
      RecordApi.idOf(row, hint: '${spec.key} ${spec.title}') != null;

  Future<void> _delete(BuildContext context) async {
    final label = formatValue(row[spec.titleField], FieldKind.text);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this record?'),
        content: Text(label.isEmpty
            ? 'This cannot be undone.'
            : '“$label” will be removed. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final api = RecordApi(session!, spec, company);
      await api.remove(api.idIn(row)!);
      navigator.pop(true);
      messenger.showSnackBar(const SnackBar(content: Text('Deleted')));
    } on ApiException catch (e) {
      // The API explains refusals (in use elsewhere, closed period) better
      // than any message written here could.
      messenger.showSnackBar(SnackBar(
        content: Text(e.message),
        duration: const Duration(seconds: 6),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final title = formatValue(row[spec.titleField], FieldKind.text);
    final status = spec.statusField == null ? null : row[spec.statusField];

    // Anything the spec did not name, so nothing in the record is hidden.
    final named = {
      spec.titleField,
      if (spec.statusField != null) spec.statusField!,
      ...spec.fields.map((f) => f.key),
      ...spec.subtitleFields.map((f) => f.key),
    };
    final extras = row.keys
        .where((k) => !named.contains(k))
        .where((k) => row[k] != null && row[k] is! Map && row[k] is! List)
        .where((k) => !isPlumbingField(k, row[k]))
        .toList();

    final lead = sidebarLeading(context, session, company, specKey: spec.key);
    return Scaffold(
      appBar: AppBar(
        leading: lead.leading,
        leadingWidth: lead.width,
        title: Text(_name),
        actions: [
          if (_canDelete)
            IconButton(
              tooltip: 'Delete',
              icon: Icon(Icons.delete_outline,
                  size: 20, color: Theme.of(context).colorScheme.error),
              onPressed: () => _delete(context),
            ),
          if (_canEdit)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
                onPressed: () => Navigator.of(context)
                    .push<bool>(MaterialPageRoute(
                      builder: (_) => customForms[spec.key]
                              ?.call(session!, company, row) ??
                          FormScreen(
                        def: _form!,
                        title: 'Edit ${_name.toLowerCase()}',
                        company: company,
                        session: session,
                        spec: spec,
                        existing: row,
                      ),
                    ))
                    .then((saved) {
                      // The row this screen was built from is now stale, so
                      // close back to the list and let it reload.
                      if (saved == true && context.mounted) {
                        Navigator.of(context).pop(true);
                      }
                    }),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: [
          if (session != null)
            for (final x in recordExtras[spec.key] ?? const <RecordExtra>[])
              if (x.when?.call(row) ?? true) ...[
              AppButton(
                label: x.label,
                icon: x.icon,
                variant: AppButtonVariant.outline,
                fullWidth: true,
                onPressed: () => Navigator.of(context).push<bool>(MaterialPageRoute(
                  builder: (_) => x.builder(session!, company, row),
                )),
              ),
              const SizedBox(height: 12),
            ],
          Row(
            children: [
              Expanded(
                child: Text(title.isEmpty ? 'Untitled' : title,
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.w700)),
              ),
              if (status != null && '$status'.isNotEmpty)
                Builder(builder: (context) {
                  final s = statusStyle('$status');
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                        color: s.bg,
                        borderRadius: BorderRadius.circular(Dim.radiusMd)),
                    child: Text('$status',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: s.fg)),
                  );
                }),
            ],
          ),
          const SizedBox(height: 16),
          if (spec.fields.isNotEmpty)
            FormSection(
              title: 'Details',
              color: SectionColor.slate,
              columns: 2,
              children: [
                for (final f in spec.fields)
                  AppField(
                    label: f.label,
                    child: _ReadOnly(
                        text: formatValue(row[f.key], f.kind, suffix: f.suffix)),
                  ),
              ],
            ),
          if (extras.isNotEmpty) ...[
            if (spec.fields.isNotEmpty) const SizedBox(height: 14),
            FormSection(
              // "Other fields" only makes sense next to a Details section.
              // On a generated page there is no curated field list, so these
              // ARE the record — a P&L report had its revenue and profit
              // filed under "Other fields".
              title: spec.fields.isEmpty ? 'Details' : 'Other fields',
              color: SectionColor.slate,
              columns: 2,
              children: [
                for (final k in extras)
                  AppField(
                    label: _humanise(k),
                    child: _ReadOnly(text: '${row[k]}'),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          Text(
            _canEdit
                ? 'Edit opens the same form the web uses.'
                : !_verbs.put
                    ? 'This page is read-only — the endpoint accepts no edits.'
                    : 'No edit form could be built for this page yet.',
            style: TextStyle(fontSize: 12, color: tokens.mutedForeground),
          ),
        ],
      ),
    );
  }

  static String _humanise(String key) {
    final spaced = key.replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}');
    return spaced.isEmpty
        ? key
        : spaced[0].toUpperCase() + spaced.substring(1);
  }
}

/// A value styled like a disabled input, so detail and edit views line up.
class _ReadOnly extends StatelessWidget {
  const _ReadOnly({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 40),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.muted,
        borderRadius: BorderRadius.circular(Dim.radiusMd),
        border: Border.all(color: tokens.border),
      ),
      child: Text(text, style: const TextStyle(fontSize: 14)),
    );
  }
}
