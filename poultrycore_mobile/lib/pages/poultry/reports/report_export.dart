// Report exports, as the web's report toolbar: CSV, PDF and "Email" (a PDF of
// the report sent through POST /Email/Report). The PDF follows
// `lib/utils/pdf-export.ts`: an emerald letterhead band with the farm and the
// title, the period / currency / scope / generated-by lines, filter chips,
// the summary cards with their accent rails, then each table with its header
// repeated per page, zebra rows and a bold totals row, and a running footer
// with "Page n of N".

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../../api/api_client.dart';

class ReportColumn {
  const ReportColumn(this.header, {this.right = false});
  final String header;
  final bool right;
}

class ReportSection {
  const ReportSection({this.heading, required this.columns, required this.rows, this.totals});
  final String? heading;
  final List<ReportColumn> columns;
  final List<List<String>> rows;
  final List<String>? totals;
}

typedef ReportCardOut = ({String label, String value, String? accent, String? note});

/// Everything a report export carries.
class ReportDocument {
  const ReportDocument({
    required this.title,
    required this.filename,
    required this.farmName,
    this.fromDate,
    this.toDate,
    this.generatedBy,
    this.currencyLabel,
    this.filters = const [],
    this.cards = const [],
    required this.sections,
    this.landscape,
    this.recordLabel,
    this.subtitle,
    this.notes = const [],
  });
  final String title;
  final String filename;
  final String farmName;
  final String? fromDate;
  final String? toDate;
  final String? generatedBy;
  final String? currencyLabel;
  final List<(String, String)> filters;
  final List<ReportCardOut> cards;
  final List<ReportSection> sections;

  /// Null = landscape when a table is wider than seven columns.
  final bool? landscape;
  final String? recordLabel;

  /// A line under the letterhead meta (the P&L's cost-recognition line).
  final String? subtitle;

  /// Printed after the tables.
  final List<String> notes;

  int get rowCount => sections.fold(0, (n, s) => n + s.rows.length);
}

/// Hands a finished file to the system share sheet. Replaced in tests.
typedef FileSharer = Future<void> Function(String filename, List<int> bytes, String mimeType, String subject);

class ReportExport {
  const ReportExport._();

  static FileSharer sharer = _shareFile;

  static Future<void> _shareFile(String filename, List<int> bytes, String mimeType, String subject) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: mimeType)], subject: subject));
  }

  static String _day() => DateTime.now().toIso8601String().substring(0, 10);

  // ------------------------------------------------------------------ CSV

  static String _esc(String v) => '"${v.replaceAll('"', '""')}"';

  /// The web's onCsv: title, farm + period, then header, rows and totals.
  /// Multiple sections follow one another under their headings.
  static String buildCsv(ReportDocument d) {
    final b = StringBuffer()
      ..writeln(_esc(d.title))
      ..writeln('${_esc('Farm: ${d.farmName}')},'
          '${_esc('Period: ${d.fromDate ?? ''} to ${d.toDate ?? ''}')}')
      ..writeln();
    for (final (i, s) in d.sections.indexed) {
      if (i > 0) b.writeln();
      if (s.heading != null) b.writeln(_esc(s.heading!));
      b.writeln(s.columns.map((c) => _esc(c.header)).join(','));
      for (final r in s.rows) {
        b.writeln(r.map(_esc).join(','));
      }
      if (s.totals != null) b.writeln(s.totals!.map(_esc).join(','));
    }
    return b.toString();
  }

  static Future<void> shareCsv(ReportDocument d) {
    // The BOM makes Excel read the file as UTF-8, as the web's download does.
    final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode(buildCsv(d))];
    final range = d.fromDate == null ? _day() : '${d.fromDate}_${d.toDate}';
    return sharer('${d.filename}-$range.csv', bytes, 'text/csv', d.title);
  }

  // ------------------------------------------------------------------ PDF

  static const _brand = PdfColor.fromInt(0xFF059669);
  static const _band = PdfColor.fromInt(0xFF047857);
  static const _zebra = PdfColor.fromInt(0xFFECFDF5);
  static const _totalsBg = PdfColor.fromInt(0xFFD1FAE5);
  static const _ink = PdfColor.fromInt(0xFF0F172A);
  static const _muted = PdfColor.fromInt(0xFF64748B);
  static const _rule = PdfColor.fromInt(0xFFE2E8F0);

  static PdfColor _accent(String? a) => switch (a) {
        'green' => const PdfColor.fromInt(0xFF047857),
        'rose' => const PdfColor.fromInt(0xFFBE123C),
        'indigo' => const PdfColor.fromInt(0xFF4338CA),
        _ => const PdfColor.fromInt(0xFFCBD5E1),
      };

  /// The built-in PDF fonts are reliable for plain ASCII only; everything the
  /// reports print outside it gets its plain equivalent, never a missing glyph.
  static String latin(String s) {
    const map = {
      '—': '-', '–': '-', '−': '-', '→': '->', '←': '<-', '‘': "'", '’': "'", '“': '"', '”': '"',
      '…': '...', '≈': '~', '₵': 'C', '•': '-', '·': '-', '×': 'x', '÷': '/', '✓': 'v', '°': ' deg',
      ' ': ' ',
    };
    final b = StringBuffer();
    for (final ch in s.runes) {
      final c = String.fromCharCode(ch);
      final m = map[c];
      if (m != null) {
        b.write(m);
      } else if (ch >= 0x20 && ch <= 0x7E) {
        b.write(c);
      } else if (ch == 0x0A) {
        b.write(' ');
      } else {
        b.write('?');
      }
    }
    return b.toString();
  }

  static String _scope(ReportDocument d) {
    final noun = (d.recordLabel ?? '').trim().isEmpty ? 'records' : d.recordLabel!.trim();
    final n = _thousands(d.rowCount);
    return d.filters.isEmpty ? 'Showing:  all $n $noun' : 'Showing:  $n $noun';
  }

  static String _thousands(int n) {
    final s = '$n';
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  static Future<Uint8List> buildPdf(ReportDocument d) async {
    final wide = d.landscape ?? d.sections.any((s) => s.columns.length > 7);
    final format = wide ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;
    final generated = DateTime.now().toString().substring(0, 16);
    final doc = pw.Document(title: latin(d.title), author: latin(d.generatedBy ?? ''));
    pw.TextStyle t(double size, {PdfColor color = _ink, bool bold = false}) =>
        pw.TextStyle(fontSize: size, color: color, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal);

    final meta = [
      if (d.fromDate != null && d.toDate != null) 'Period:  ${d.fromDate}  to  ${d.toDate}',
      if (d.currencyLabel != null) 'Currency:  ${d.currencyLabel}',
      _scope(d),
      if ((d.generatedBy ?? '').isNotEmpty) 'Generated by:  ${d.generatedBy}',
    ];

    final perRow = d.cards.isEmpty ? 1 : (d.cards.length < 4 ? d.cards.length : 4);

    doc.addPage(pw.MultiPage(
      pageFormat: format,
      margin: const pw.EdgeInsets.fromLTRB(40, 0, 40, 30),
      header: (ctx) => ctx.pageNumber == 1
          ? pw.SizedBox()
          : pw.SizedBox(height: 30),
      footer: (ctx) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 4),
        decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _rule, width: 0.3))),
        child: pw.Row(children: [
          pw.Expanded(child: pw.Text(latin('${d.farmName} - ${d.title}'), style: t(8, color: _muted), maxLines: 1)),
          pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: t(8, color: _muted)),
        ]),
      ),
      build: (ctx) => [
        // Letterhead band, edge to edge.
        pw.Container(
          margin: const pw.EdgeInsets.only(left: -40, right: -40, bottom: 18),
          padding: const pw.EdgeInsets.fromLTRB(40, 14, 40, 12),
          color: _band,
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(latin(d.farmName.isEmpty ? 'Report' : d.farmName), style: t(15, color: PdfColors.white, bold: true)),
                pw.SizedBox(height: 4),
                pw.Text(latin(d.title), style: t(11, color: PdfColors.white)),
              ]),
            ),
            pw.Text(generated, style: t(8, color: PdfColors.white)),
          ]),
        ),
        for (final line in meta) pw.Padding(padding: const pw.EdgeInsets.only(bottom: 3), child: pw.Text(latin(line), style: t(9, color: _muted))),
        if (d.filters.isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 3, bottom: 4),
            child: pw.Wrap(spacing: 5, runSpacing: 4, children: [
              for (final (label, value) in d.filters)
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: pw.BoxDecoration(
                    color: _zebra,
                    border: pw.Border.all(color: const PdfColor.fromInt(0xFFA7F3D0), width: 0.4),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Text(latin('$label: $value'), style: t(7.5, color: _band)),
                ),
            ]),
          ),
        if (d.subtitle != null)
          pw.Padding(padding: const pw.EdgeInsets.only(bottom: 4), child: pw.Text(latin(d.subtitle!), style: t(9, color: _muted))),
        if (d.cards.isNotEmpty) ...[
          pw.SizedBox(height: 6),
          for (var i = 0; i < d.cards.length; i += perRow)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                for (var j = i; j < i + perRow; j++) ...[
                  if (j > i) pw.SizedBox(width: 8),
                  pw.Expanded(child: j < d.cards.length ? _pdfCard(d.cards[j], t) : pw.SizedBox()),
                ],
              ]),
            ),
        ],
        pw.SizedBox(height: 10),
        for (final s in d.sections) ...[
          if (s.heading != null)
            pw.Padding(padding: const pw.EdgeInsets.only(top: 6, bottom: 4), child: pw.Text(latin(s.heading!), style: t(11, bold: true))),
          if (s.rows.isEmpty)
            pw.Text('No rows.', style: t(9, color: _muted))
          else
            pw.TableHelper.fromTextArray(
              headers: [for (final c in s.columns) latin(c.header)],
              data: [
                for (final r in s.rows) [for (final v in r) latin(v)],
                if (s.totals != null) [for (final v in s.totals!) latin(v)],
              ],
              headerStyle: t(8, color: PdfColors.white, bold: true),
              headerDecoration: const pw.BoxDecoration(color: _brand),
              cellStyle: t(8),
              cellPadding: const pw.EdgeInsets.all(4),
              border: pw.TableBorder.all(color: _rule, width: 0.3),
              oddRowDecoration: const pw.BoxDecoration(color: _zebra),
              cellAlignments: {
                for (final (i, c) in s.columns.indexed) i: c.right ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
              },
              headerAlignments: {
                for (final (i, c) in s.columns.indexed) i: c.right ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
              },
              // The totals row: bold on the totals fill.
              cellDecoration: s.totals == null
                  ? null
                  : (index, data, rowNum) => rowNum == s.rows.length + 1 ? const pw.BoxDecoration(color: _totalsBg) : const pw.BoxDecoration(),
              textStyleBuilder: s.totals == null
                  ? null
                  : (index, data, rowNum) => rowNum == s.rows.length + 1 ? t(8, bold: true) : t(8),
            ),
          pw.SizedBox(height: 10),
        ],
        for (final n in d.notes) pw.Padding(padding: const pw.EdgeInsets.only(top: 4), child: pw.Text(latin(n), style: t(8, color: _muted))),
      ],
    ));
    return doc.save();
  }

  static pw.Widget _pdfCard(ReportCardOut c, pw.TextStyle Function(double, {PdfColor color, bool bold}) t) => pw.Container(
        decoration: pw.BoxDecoration(border: pw.Border.all(color: _rule, width: 0.5), borderRadius: pw.BorderRadius.circular(4)),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Container(width: 3, height: c.note != null ? 44 : 34, color: _accent(c.accent)),
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(8, 5, 6, 4),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(latin(c.label.toUpperCase()), style: t(7, color: _muted), maxLines: 1),
                pw.SizedBox(height: 3),
                pw.Text(latin(c.value), style: t(11, color: c.accent == null ? _ink : _accent(c.accent), bold: true), maxLines: 1),
                if (c.note != null) pw.Text(latin(c.note!), style: t(5.5, color: _muted), maxLines: 2),
              ]),
            ),
          ),
        ]),
      );

  static String pdfFilename(ReportDocument d) => '${d.filename}-${_day()}.pdf';

  static Future<void> sharePdf(ReportDocument d) async =>
      sharer(pdfFilename(d), await buildPdf(d), 'application/pdf', d.title);

  // ---------------------------------------------------------------- email

  static final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  /// Splits "a@x.com, b@y.com" the way the web does; null when any is invalid.
  static List<String>? recipients(String raw) {
    final list = raw.split(RegExp(r'[,;\n]')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (list.isEmpty || list.any((e) => !_emailRe.hasMatch(e))) return null;
    return list;
  }

  /// emailTableAsPdf: the PDF goes to POST /Email/Report as multipart.
  static Future<void> email(ApiClient client, ReportDocument d, List<String> to) async {
    final bytes = await buildPdf(d);
    await client.postFile(
      '/api/Email/Report',
      field: 'file',
      bytes: bytes,
      filename: pdfFilename(d),
      contentType: 'application/pdf',
      fields: {
        'to': to.join(','),
        'farmName': d.farmName,
        'reportTitle': d.title,
        if ((d.generatedBy ?? '').isNotEmpty) 'senderName': d.generatedBy!,
      },
    );
  }
}

