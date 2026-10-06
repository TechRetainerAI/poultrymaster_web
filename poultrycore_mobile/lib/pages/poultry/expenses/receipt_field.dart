// The expense receipt photo (components/expense/expense-receipt-field.tsx and
// lib/api/receipt-upload.ts): pick from the photos or take one with the camera,
// the same type and size checks, a preview, and the upload to the web's
// `/api/receipt-upload`, which answers with the `/receipt-uploads/...` path the
// description carries.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';

import '../../../config/env.dart';
import '../../../state/session.dart';
import '../trackers/tracker_widgets.dart' show TColors;

class ReceiptImage {
  const ReceiptImage(this.bytes, this.name, this.mime);
  final Uint8List bytes;
  final String name;
  final String mime;
}

const receiptMaxBytes = 4 * 1024 * 1024;
const receiptMimeTypes = {'image/jpeg', 'image/png', 'image/webp'};

/// validateReceiptFile's words.
String? validateReceipt(ReceiptImage f) {
  if (!receiptMimeTypes.contains(f.mime)) return 'Use a JPEG, PNG, or WebP image.';
  if (f.bytes.length > receiptMaxBytes) return 'Image must be 4 MB or smaller.';
  return null;
}

String receiptMimeOf(String name, [String? reported]) {
  if (reported != null && reported.isNotEmpty) return reported;
  final n = name.toLowerCase();
  if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
  if (n.endsWith('.png')) return 'image/png';
  if (n.endsWith('.webp')) return 'image/webp';
  if (n.endsWith('.heic') || n.endsWith('.heif')) return 'image/heic';
  return 'application/octet-stream';
}

typedef ReceiptPicker = Future<ReceiptImage?> Function({required bool camera});
typedef ReceiptUploadResult = ({bool ok, String? path, String? message});
typedef ReceiptUploader = Future<ReceiptUploadResult> Function(Session session, ReceiptImage file, String farmId);

/// Swappable so widget tests can stand in for the device picker.
ReceiptPicker pickReceiptImage = _pick;

/// Swappable so widget tests can stand in for the web upload.
ReceiptUploader uploadExpenseReceipt = _upload;

Future<ReceiptImage?> _pick({required bool camera}) async {
  final x = await ImagePicker().pickImage(source: camera ? ImageSource.camera : ImageSource.gallery);
  if (x == null) return null;
  return ReceiptImage(await x.readAsBytes(), x.name, receiptMimeOf(x.name, x.mimeType));
}

Future<ReceiptUploadResult> _upload(Session session, ReceiptImage file, String farmId) async {
  final req = http.MultipartRequest('POST', Uri.parse('${Env.webBase}/api/receipt-upload'))
    ..headers['Accept'] = 'application/json'
    ..fields['farmId'] = farmId
    ..files.add(http.MultipartFile.fromBytes('file', file.bytes, filename: file.name, contentType: MediaType.parse(file.mime)));
  final token = session.tokens.accessToken;
  if (token != null && token.isNotEmpty) req.headers['Authorization'] = 'Bearer $token';
  try {
    final res = await http.Response.fromStream(await req.send());
    Map data = const {};
    try {
      final d = jsonDecode(res.body);
      if (d is Map) data = d;
    } catch (_) {}
    if (res.statusCode < 200 || res.statusCode >= 300) {
      return (ok: false, path: null, message: '${data['message'] ?? ''}'.isNotEmpty ? '${data['message']}' : 'Upload failed (${res.statusCode})');
    }
    final path = '${data['path'] ?? ''}';
    if (path.isEmpty) return (ok: false, path: null, message: 'Upload response missing path');
    return (ok: true, path: path, message: null);
  } catch (e) {
    return (ok: false, path: null, message: '$e'.isNotEmpty ? '$e' : 'Upload failed');
  }
}

/// The expense row's own stored image (GET /api/Expense/{id}/attachment).
class ReceiptDbAttachment {
  const ReceiptDbAttachment({required this.expenseId, required this.userId, required this.farmId});
  final int expenseId;
  final String userId, farmId;
}

class ExpenseReceiptField extends StatefulWidget {
  const ExpenseReceiptField({
    super.key,
    required this.session,
    required this.existingUrl,
    required this.pending,
    required this.onPending,
    this.dbAttachment,
    this.onRemoveExisting,
    this.disabled = false,
    this.label = 'Receipt photo (optional)',
    this.showCaptureOption = true,
  });
  final Session session;

  /// The saved receipt's view path (`/api/receipt-file/...`), or null.
  final String? existingUrl;
  final ReceiptDbAttachment? dbAttachment;
  final ReceiptImage? pending;
  final ValueChanged<ReceiptImage?> onPending;
  final VoidCallback? onRemoveExisting;
  final bool disabled;
  final String label;
  final bool showCaptureOption;

  @override
  State<ExpenseReceiptField> createState() => _ExpenseReceiptFieldState();
}

class _ExpenseReceiptFieldState extends State<ExpenseReceiptField> {
  String? _fileError;

  Future<void> _choose({required bool camera}) async {
    final f = await pickReceiptImage(camera: camera);
    if (f == null || !mounted) return;
    final err = validateReceipt(f);
    setState(() => _fileError = err);
    widget.onPending(err == null ? f : null);
  }

  Widget _frame(Widget child) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: TColors.slate50,
          border: Border.all(color: TColors.slate200),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Opacity(opacity: widget.disabled ? .6 : 1, child: ConstrainedBox(constraints: const BoxConstraints(maxHeight: 224), child: child)),
      );

  @override
  Widget build(BuildContext context) {
    final pending = widget.pending;
    final db = widget.dbAttachment;
    final showLegacy = widget.existingUrl != null && pending == null && db == null;
    final showDb = db != null && pending == null;
    final hasPreview = pending != null || showLegacy || showDb;
    final showRemoveSaved = (widget.existingUrl != null || db != null) && pending == null;
    final off = widget.disabled;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(widget.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate700)),
      const SizedBox(height: 4),
      Text(
        'JPEG, PNG, or WebP, up to 4 MB.${widget.showCaptureOption ? ' Upload from your device, or take a photo with the camera (works best on phones and tablets).' : ' Saved with this record for your files.'}',
        style: const TextStyle(fontSize: 12, color: TColors.slate500),
      ),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 6, children: [
        OutlinedButton.icon(
          onPressed: off ? null : () => _choose(camera: false),
          icon: const Icon(Icons.image_outlined, size: 16),
          label: Text(hasPreview ? 'Replace image' : 'Upload image'),
        ),
        if (widget.showCaptureOption)
          OutlinedButton.icon(
            onPressed: off ? null : () => _choose(camera: true),
            icon: const Icon(Icons.photo_camera_outlined, size: 16),
            label: const Text('Take photo'),
          ),
        if (pending != null)
          TextButton.icon(
            onPressed: off
                ? null
                : () {
                    setState(() => _fileError = null);
                    widget.onPending(null);
                  },
            icon: const Icon(Icons.close, size: 16),
            label: const Text('Clear new image'),
          ),
        if (showRemoveSaved && widget.onRemoveExisting != null)
          TextButton.icon(
            onPressed: off ? null : widget.onRemoveExisting,
            icon: const Icon(Icons.close, size: 16),
            label: const Text('Remove saved receipt'),
          ),
      ]),
      if (_fileError != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(_fileError!, style: const TextStyle(fontSize: 12, color: TColors.red600)),
        ),
      if (showDb)
        _frame(Image.network(
          '${Env.farmApi}/api/Expense/${db.expenseId}/attachment?${Uri(queryParameters: {'userId': db.userId, 'farmId': db.farmId}).query}',
          headers: {'Authorization': 'Bearer ${widget.session.tokens.accessToken ?? ''}'},
          fit: BoxFit.contain,
          semanticLabel: 'Receipt preview',
          errorBuilder: (_, _, _) => const SizedBox(height: 56, width: 384),
        )),
      if (pending != null) _frame(Image.memory(pending.bytes, fit: BoxFit.contain, semanticLabel: 'Receipt preview')),
      if (showLegacy)
        Image.network(
          '${Env.webBase}${widget.existingUrl}',
          fit: BoxFit.contain,
          semanticLabel: 'Receipt preview',
          frameBuilder: (_, child, _, _) => _frame(child),
          errorBuilder: (_, _, _) => Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: TColors.amber50,
              border: Border.all(color: TColors.amber200),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'Receipt file could not be loaded (it may be missing on the server after a deploy). Re-upload a photo or remove the saved receipt.',
              style: TextStyle(fontSize: 12, color: TColors.amber700),
            ),
          ),
        ),
    ]);
  }
}
