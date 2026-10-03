import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import 'business_dates.dart';

/// The web's ReasonDialog (`components/closing/daily-closing-dialogs.tsx`):
/// a required reason before a reversal, rejection or reopen. Completes with
/// the trimmed reason, or null when cancelled.
Future<String?> showReasonDialog(
  BuildContext context, {
  required String title,
  required String description,
  required String confirmLabel,
  bool destructive = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _ReasonDialog(
      title: title,
      description: description,
      confirmLabel: confirmLabel,
      destructive: destructive,
    ),
  );
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.description,
    required this.confirmLabel,
    required this.destructive,
  });
  final String title;
  final String description;
  final String confirmLabel;
  final bool destructive;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = _reason.text.trim().isNotEmpty;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.description, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          const Text.rich(TextSpan(text: 'Reason ', children: [
            TextSpan(text: '*', style: TextStyle(color: Colors.red)),
          ])),
          const SizedBox(height: 4),
          TextField(
            controller: _reason,
            autofocus: true,
            minLines: 3,
            maxLines: 3,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          style: widget.destructive
              ? FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error)
              : null,
          onPressed: ok ? () => Navigator.of(context).pop(_reason.text.trim()) : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// The company's today ("yyyy-MM-dd") from `/CompanyTime/context`, as the
/// web's useBusinessDate — never the phone's clock. Falls back to the phone's
/// date only when the server cannot be asked.
Future<String> companyToday(Session session, Company company) async {
  try {
    final c = await session.farmClient.get('/api/CompanyTime/context', query: {'farmId': company.farmId});
    final d = c is Map ? toBusinessDate(c['businessDate']) : null;
    if (d != null) return d;
  } on ApiException {
    // fall through
  }
  return isoDay(DateTime.now());
}
