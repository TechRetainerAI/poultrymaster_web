import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/company.dart';
import 'list_screen.dart' show formatValue;
import 'list_header.dart';
import 'page_spec.dart';
import 'plumbing_fields.dart';

/// Export and share the rows currently on screen.
///
/// The web offers PDF and Email on every list. Generating a true PDF on device
/// would mean a layout engine and a font bundle for a file most people forward
/// straight on, so this shares CSV — which opens in Sheets or Excel, attaches
/// to mail, and keeps the numbers usable rather than flattened into a picture.
/// The buttons are labelled for what they actually do.
class ListExport {
  const ListExport._();

  static String _csvEscape(String v) {
    final needsQuotes =
        v.contains(',') || v.contains('"') || v.contains('\n');
    final escaped = v.replaceAll('"', '""');
    return needsQuotes ? '"$escaped"' : escaped;
  }

  /// Builds a CSV of the visible rows using the spec's own column order.
  static String buildCsv({
    required PageSpec spec,
    required List<Map<String, dynamic>> rows,
    required Company company,
  }) {
    if (rows.isEmpty) return '';

    // Spec fields first (they carry proper labels), then anything else.
    final ordered = <String>[];
    final labels = <String, String>{};
    void add(String key, String label) {
      if (ordered.contains(key)) return;
      ordered.add(key);
      labels[key] = label;
    }

    final titleKey = titleFieldIn(rows.first, spec.titleField);
    if (titleKey.isNotEmpty) add(titleKey, _humanise(titleKey));
    for (final f in spec.subtitleFields) {
      add(f.key, f.label);
    }
    for (final f in spec.fields) {
      add(f.key, f.label);
    }
    for (final k in rows.first.keys) {
      final v = rows.first[k];
      if (v is Map || v is List) continue;
      // A spreadsheet a client opens, or an email they forward, must not
      // carry row GUIDs, IP addresses or raw request JSON.
      if (isPlumbingField(k, v)) continue;
      add(k, _humanise(k));
    }

    final kindOf = <String, FieldKind>{};
    for (final f in [...spec.fields, ...spec.subtitleFields]) {
      kindOf[f.key] = f.kind;
    }

    final buf = StringBuffer()
      ..writeln('${company.name} — ${headerFor(spec.key, spec.title).title}')
      ..writeln('Exported ${DateTime.now().toIso8601String().split("T").first}')
      ..writeln()
      ..writeln(ordered.map((k) => _csvEscape(labels[k] ?? k)).join(','));

    for (final r in rows) {
      buf.writeln(ordered.map((k) {
        final v = r[k];
        if (v == null) return '';
        // Money and dates are written readable, not raw, so the file matches
        // what the person saw on screen.
        final kind = kindOf[k];
        if (kind != null && kind != FieldKind.text) {
          return _csvEscape(formatValue(v, kind));
        }
        return _csvEscape('$v');
      }).join(','));
    }
    return buf.toString();
  }

  static Future<File> _write(String csv, String name) async {
    final dir = await getTemporaryDirectory();
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-');
    final file = File('${dir.path}/$safe');
    return file.writeAsString(csv);
  }

  /// Share the rows as a file — the system sheet covers mail, Drive, WhatsApp.
  static Future<void> share({
    required BuildContext context,
    required PageSpec spec,
    required List<Map<String, dynamic>> rows,
    required Company company,
    bool email = false,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    if (rows.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Nothing to export yet.')),
      );
      return;
    }

    try {
      final csv = buildCsv(spec: spec, rows: rows, company: company);
      final stamp = DateTime.now().toIso8601String().split('T').first;
      final file = await _write(
          csv, '${headerFor(spec.key, spec.title).title}-$stamp.csv');

      final subject =
          '${company.name} — ${headerFor(spec.key, spec.title).title} ($stamp)';
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          subject: subject,
          text: email
              ? '$subject\n\n${rows.length} records attached as CSV.'
              : null,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not export: $e')),
      );
    }
  }

  static String _humanise(String key) {
    final spaced = key.replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}');
    return spaced.isEmpty
        ? key
        : spaced[0].toUpperCase() + spaced.substring(1);
  }
}
