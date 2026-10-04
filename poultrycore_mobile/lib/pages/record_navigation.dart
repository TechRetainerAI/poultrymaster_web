import 'package:flutter/material.dart';

import '../models/company.dart';
import '../state/session.dart';
import 'form_screen.dart';
import 'module_registry.dart';
import 'page_spec.dart';

/// Opens the form a page uses to add (row null) or edit a record — its own
/// screen when it has one, else the shared FormScreen over its form — so a
/// hub such as Farm Setup edits with exactly the form the page itself uses.
/// Completes with true when something was saved. Null when the page has no
/// form at all.
Future<bool?>? openRecordForm(
  BuildContext context, {
  required Session session,
  required Company company,
  required PageSpec spec,
  Map<String, dynamic>? row,
  String? title,
}) {
  final custom = customForms[spec.key];
  final def = custom == null ? formForSpec(spec.key) : null;
  if (custom == null && def == null) return null;
  return Navigator.of(context).push<bool>(MaterialPageRoute(
    builder: (_) =>
        custom?.call(session, company, row) ??
        FormScreen(
          def: def!,
          title: title ?? (row == null ? 'New ${spec.title.toLowerCase()}' : 'Edit ${spec.title.toLowerCase()}'),
          company: company,
          session: session,
          spec: spec,
          existing: row,
        ),
  ));
}
