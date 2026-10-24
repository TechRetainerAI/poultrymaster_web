// The restaurant's QR codes, as the web draws them: the ordering link a code
// carries (lib/utils/qr-order-url.ts), the printed table card
// (components/restaurant/qr-table-card.tsx), the PNG download and the print
// page (app/restaurant-qr-print/page.tsx), which here is an A4 PDF handed to
// the phone's share sheet so it can be printed or saved.
//
// The QR encoder is the `barcode` library the `pdf` package already ships
// (pdf/widgets.dart re-exports it), so no new package was added.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../config/env.dart';
import '../poultry/reports/report_export.dart' show ReportExport;
import '../poultry/trackers/tracker_logic.dart' show tStr;

const qrOrderPath = '/restaurant-order-online';

/// buildQrOrderUrl: the farm's publicBaseUrl when it has one (trailing slashes
/// trimmed, https:// added), otherwise the web portal the app talks to — the
/// app has no window.location.origin of its own.
String buildQrOrderUrl(String token, [String? overrideBase]) {
  var base = (overrideBase ?? '').trim().replaceAll(RegExp(r'/+$'), '');
  if (base.isNotEmpty && !RegExp(r'^https?://', caseSensitive: false).hasMatch(base)) base = 'https://$base';
  if (base.isEmpty) base = Env.webBase;
  return '$base$qrOrderPath?qr=${Uri.encodeComponent(token)}';
}

/// level "M", marginSize 2, as qrcode.react is called on the web.
final _qr = pw.Barcode.qrCode(errorCorrectLevel: pw.BarcodeQRCorrectionLevel.medium);

/// The dark modules of [data]'s code, in a [size] square with a two-module
/// quiet zone.
List<Rect> qrModules(String data, double size) {
  final probe = _qr.make(data, width: 100, height: 100).whereType<pw.BarcodeBar>().toList();
  if (probe.isEmpty) return const [];
  final cell = probe.map((b) => b.width).reduce((a, b) => a < b ? a : b);
  final modules = (100 / cell).round();
  final scale = size / (modules + 4);
  return [
    for (final b in probe)
      if (b.black) Rect.fromLTWH((b.left / cell + 2) * scale, (b.top / cell + 2) * scale, b.width / cell * scale, b.height / cell * scale),
  ];
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.data);
  final String data;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final p = Paint()
      ..color = Colors.black
      ..isAntiAlias = false;
    for (final r in qrModules(data, size.shortestSide)) {
      canvas.drawRect(r.inflate(.25), p);
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.data != data;
}

/// A scannable QR code.
class QrCodeView extends StatelessWidget {
  const QrCodeView({super.key, required this.data, this.size = 170});
  final String data;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: CustomPaint(painter: _QrPainter(data)));
}

/// QrTableCard: venue codes say "Order here" and the restaurant's name; table
/// codes the name, "Table" and the number. The QR and the two lines below.
class QrTableCardView extends StatelessWidget {
  const QrTableCardView({super.key, required this.token, this.tableNumber, this.codeType = 'Table', this.restaurantName, this.publicBaseUrl, this.faded = false});
  final String token;
  final String? tableNumber;
  final String codeType;
  final String? restaurantName;
  final String? publicBaseUrl;
  final bool faded;

  @override
  Widget build(BuildContext context) {
    final venue = codeType == 'Restaurant';
    final name = tStr(restaurantName);
    return Opacity(
      opacity: faded ? .4 : 1,
      child: Container(
        width: 250,
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFE5E7EB)), borderRadius: BorderRadius.circular(12)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (venue) ...[
            const Text('ORDER HERE', style: TextStyle(fontSize: 11, letterSpacing: 2, color: Color(0xFF9CA3AF))),
            Text(name.isEmpty ? 'Our Menu' : name,
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
          ] else ...[
            if (name.isNotEmpty)
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
            const SizedBox(height: 4),
            const Text('TABLE', style: TextStyle(fontSize: 11, letterSpacing: 2, color: Color(0xFF9CA3AF))),
            Text(tStr(tableNumber), style: const TextStyle(fontSize: 32, height: 1, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
          ],
          const SizedBox(height: 12),
          QrCodeView(data: buildQrOrderUrl(token, publicBaseUrl)),
          const SizedBox(height: 12),
          Text(venue ? 'Skip the queue — order from your phone' : 'Scan to order from your phone',
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
          const SizedBox(height: 4),
          const Text('Point your camera here to see the menu, choose your food and order.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: Color(0xFF6B7280))),
        ]),
      ),
    );
  }
}

/// downloadQrPng: the code alone at 1024 px.
Future<Uint8List> qrPngBytes(String url, {int size = 1024}) async {
  final rec = ui.PictureRecorder();
  _QrPainter(url).paint(Canvas(rec), Size.square(size.toDouble()));
  final img = await rec.endRecording().toImage(size, size);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<void> shareQrPng(Map q, String? publicBaseUrl) async {
  final bytes = await qrPngBytes(buildQrOrderUrl(tStr(q['qrToken']), publicBaseUrl));
  final file = tStr(q['codeType']) == 'Restaurant' ? 'restaurant-qr.png' : 'table-${tStr(q['tableNumber'])}-qr.png';
  await ReportExport.sharer(file, bytes, 'image/png', file);
}

/// The print page: every active code (or just [only]) as a 70 mm card on A4.
Future<Uint8List> qrCardsPdf(List<Map> codes, {String? restaurantName, String? publicBaseUrl}) async {
  final doc = pw.Document();
  final name = tStr(restaurantName);
  pw.Widget card(Map q) {
    final venue = tStr(q['codeType']) == 'Restaurant';
    return pw.Container(
      width: 70 * PdfPageFormat.mm,
      height: 95 * PdfPageFormat.mm,
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300), borderRadius: pw.BorderRadius.circular(8)),
      child: pw.Column(children: [
        if (venue) ...[
          pw.Text('ORDER HERE', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500)),
          pw.Text(name.isEmpty ? 'Our Menu' : name, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        ] else ...[
          if (name.isNotEmpty) pw.Text(name, maxLines: 1, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
          pw.Text('TABLE', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500)),
          pw.Text(tStr(q['tableNumber']), style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold)),
        ],
        pw.SizedBox(height: 8),
        pw.BarcodeWidget(
          barcode: _qr,
          data: buildQrOrderUrl(tStr(q['qrToken']), publicBaseUrl),
          width: 45 * PdfPageFormat.mm,
          height: 45 * PdfPageFormat.mm,
          padding: const pw.EdgeInsets.all(4),
        ),
        pw.SizedBox(height: 8),
        pw.Text(venue ? 'Skip the queue - order from your phone' : 'Scan to order from your phone',
            textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 3),
        pw.Text('Point your camera here to see the menu, choose your food and order.',
            textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey600)),
      ]),
    );
  }

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4.copyWith(
        marginLeft: 10 * PdfPageFormat.mm, marginRight: 10 * PdfPageFormat.mm, marginTop: 10 * PdfPageFormat.mm, marginBottom: 10 * PdfPageFormat.mm),
    build: (_) => [pw.Wrap(spacing: 8, runSpacing: 8, alignment: pw.WrapAlignment.center, children: [for (final q in codes) card(q)])],
  ));
  return doc.save();
}

/// "Print": the active codes, or only the one with id [only].
Future<int> shareQrCards(List<Map> all, {int? only, String? restaurantName, String? publicBaseUrl}) async {
  final codes = [
    for (final q in all)
      if (q['isActive'] != false && (only == null || q['qrCodeId'] == only)) q,
  ];
  if (codes.isEmpty) return 0;
  final bytes = await qrCardsPdf(codes, restaurantName: restaurantName, publicBaseUrl: publicBaseUrl);
  await ReportExport.sharer('qr-cards.pdf', bytes, 'application/pdf', 'QR cards');
  return codes.length;
}
