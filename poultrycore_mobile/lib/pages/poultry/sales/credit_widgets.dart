// What Customer Credits and Supplier Credits share on the web: the tab strip
// (lib/ui/tab-styles.ts), the four KPI cards, the credit-event status badge, the
// "one customer's / supplier's credits" phone dialog and the reverse dialog
// with its required reason (components/ui/reason-select.tsx).

import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../shared/reason_select.dart';
import '../trackers/tracker_logic.dart' show tNum, tStr;
import '../trackers/tracker_widgets.dart';

const creditBlue700 = Color(0xFF1D4ED8);

/// A day as yyyy-MM-dd on the phone's clock (the web dialogs' `today()`).
String localToday() {
  final d = DateTime.now();
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// tabListCls / tabTriggerCls / tabCountCls: a white bordered strip, the active
/// trigger blue-600 with a white count.
class CreditTabs extends StatelessWidget {
  const CreditTabs({super.key, required this.tabs, required this.value, required this.onChanged});

  /// (value, icon, label, count); a null count shows no pill.
  final List<(String, IconData, String, int?)> tabs;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: TColors.slate200),
      borderRadius: BorderRadius.circular(12),
      boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1))],
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (i, (v, icon, label, count)) in tabs.indexed) ...[
            if (i > 0) const SizedBox(width: 4),
            Material(
              color: value == v ? TColors.blue600 : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onChanged(v),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 16, color: value == v ? Colors.white : TColors.slate600),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: value == v ? Colors.white : TColors.slate600),
                      ),
                      if (count != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: value == v ? Colors.white.withValues(alpha: .2) : TColors.slate100,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '$count',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: value == v ? Colors.white : TColors.slate600),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

/// One of the four summary cards: a small label over a large figure.
Widget creditKpi(String label, String value, {Color color = TColors.slate900}) => Container(
  padding: const EdgeInsets.all(14),
  decoration: BoxDecoration(
    color: Colors.white,
    border: Border.all(color: TColors.slate200),
    borderRadius: BorderRadius.circular(12),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
      const SizedBox(height: 2),
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: color),
      ),
    ],
  ),
);

/// STATUS_TONE: Available blue, Partly used amber, Used / Refunded grey.
Widget creditStatusBadge(Object? status) {
  final s = tStr(status);
  final (fg, border) = switch (s) {
    'Available' => (creditBlue700, TColors.blue300),
    'Partly used' => (TColors.amber700, TColors.amber300),
    _ => (TColors.slate500, TColors.slate300),
  };
  return TBadge(s, bg: Colors.white, fg: fg, border: border);
}

/// The grey "secondary" badge: Reversed, Undone.
Widget greyBadge(String text) => TBadge(text, bg: TColors.slate100, fg: TColors.slate700, border: TColors.slate200);

/// A full-width outlined action under a card (the web's `flex-1 h-10` buttons).
Widget cardAction(String label, IconData icon, VoidCallback onTap) =>
    OutlinedButton.icon(onPressed: onTap, icon: Icon(icon, size: 16), label: Text(label));

/// The phone dialog that lists one party's credit events: each with where it
/// came from, what is left and its own actions.
Future<void> showCreditEvents(
  BuildContext context, {
  required String title,
  required IconData icon,
  required Color iconColor,
  required Future<List<Map>> Function() load,
  required String Function(Map e) heading,
  required String Function(Map e) subline,
  required String Function(num n) money,
  required List<Widget> Function(Map e, VoidCallback close) actions,
}) => showDialog<void>(
  context: context,
  builder: (_) => _CreditEventsDialog(
    title: title,
    icon: icon,
    iconColor: iconColor,
    load: load,
    heading: heading,
    subline: subline,
    money: money,
    actions: actions,
  ),
);

class _CreditEventsDialog extends StatefulWidget {
  const _CreditEventsDialog({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.load,
    required this.heading,
    required this.subline,
    required this.money,
    required this.actions,
  });
  final String title;
  final IconData icon;
  final Color iconColor;
  final Future<List<Map>> Function() load;
  final String Function(Map e) heading;
  final String Function(Map e) subline;
  final String Function(num n) money;
  final List<Widget> Function(Map e, VoidCallback close) actions;
  @override
  State<_CreditEventsDialog> createState() => _CreditEventsDialogState();
}

class _CreditEventsDialogState extends State<_CreditEventsDialog> {
  List<Map>? _list;

  @override
  void initState() {
    super.initState();
    widget
        .load()
        .then((l) {
          if (mounted) setState(() => _list = l);
        })
        .catchError((Object _) {
          if (mounted) setState(() => _list = []);
        });
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    void close() => Navigator.pop(context);
    return AlertDialog(
      scrollable: true,
      title: Row(
        children: [
          Icon(widget.icon, color: widget.iconColor),
          const SizedBox(width: 8),
          Flexible(child: Text(widget.title)),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Each credit, where it came from, and what is left of it.', style: TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 12),
            if (list == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  children: [
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text('Loading…', style: TextStyle(fontSize: 13, color: TColors.slate500)),
                  ],
                ),
              )
            else if (list.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Nothing held any more.', style: TextStyle(fontSize: 13, color: TColors.slate500)),
              )
            else
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: TColors.slate200),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  children: [
                    for (final (i, e) in list.indexed)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: i == 0 ? null : const Border(top: BorderSide(color: TColors.slate200)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.heading(e),
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: TColors.slate900),
                                      ),
                                      Text(widget.subline(e), style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      widget.money(tNum(e['available'])),
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: creditBlue700),
                                    ),
                                    Text(
                                      'of ${widget.money(tNum(e['originalAmount']))}',
                                      style: const TextStyle(fontSize: 11, color: TColors.slate500),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Applied ${widget.money(tNum(e['applied']))} · Refunded ${widget.money(tNum(e['refunded']))} · ${tStr(e['status'])}',
                              style: const TextStyle(fontSize: 12, color: TColors.slate600),
                            ),
                            if (widget.actions(e, close).isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  for (final (j, a) in widget.actions(e, close).indexed) ...[if (j > 0) const SizedBox(width: 8), Expanded(child: a)],
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [OutlinedButton(onPressed: close, child: const Text('Close'))],
    );
  }
}

/// The red reverse dialog: what reversing means, a required reason from
/// [reasons] ("Other" to type one), Cancel and [action]. [onConfirm] posts;
/// its ApiException shows in the dialog. Returns true once it succeeded.
Future<bool> showReverseWithReason(
  BuildContext context, {
  required String title,
  required String description,
  required List<Widget> body,
  required String action,
  required Future<void> Function(String reason) onConfirm,
  List<String> reasons = reversalReasons,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _ReverseDialog(title: title, description: description, body: body, action: action, onConfirm: onConfirm, reasons: reasons),
    ) ==
    true;

class _ReverseDialog extends StatefulWidget {
  const _ReverseDialog({
    required this.title,
    required this.description,
    required this.body,
    required this.action,
    required this.onConfirm,
    required this.reasons,
  });
  final String title;
  final String description;
  final List<Widget> body;
  final String action;
  final Future<void> Function(String reason) onConfirm;
  final List<String> reasons;
  @override
  State<_ReverseDialog> createState() => _ReverseDialogState();
}

class _ReverseDialogState extends State<_ReverseDialog> {
  String _reason = '';
  bool _saving = false;
  String? _error;

  Future<void> _go() async {
    if (_reason.trim().isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onConfirm(_reason.trim());
      if (mounted) Navigator.pop(context, true);
      return;
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      scrollable: true,
      title: Row(
        children: [
          const Icon(Icons.undo, color: TColors.red600),
          const SizedBox(width: 8),
          Flexible(child: Text(widget.title)),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.description, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 12),
            ...widget.body,
            const SizedBox(height: 12),
            FilterLabel('Reason *', ReasonSelect(options: widget.reasons, value: _reason, onChanged: (v) => setState(() => _reason = v))),
            if (_error != null) ...[const SizedBox(height: 10), TrackerBanner.error(_error!)],
          ],
        ),
      ),
      actions: [
        OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: TColors.red600),
          onPressed: _saving || _reason.trim().isEmpty ? null : _go,
          child: !_saving
              ? Text(widget.action)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                    const SizedBox(width: 8),
                    Flexible(child: Text(widget.action, overflow: TextOverflow.ellipsis)),
                  ],
                ),
        ),
      ],
    ),
  );
}

/// The amber "what this means" box inside a reverse dialog.
Widget warnBox(List<InlineSpan> spans) => Container(
  padding: const EdgeInsets.all(10),
  decoration: BoxDecoration(
    color: TColors.amber50,
    border: Border.all(color: TColors.amber200),
    borderRadius: BorderRadius.circular(6),
  ),
  child: Text.rich(
    TextSpan(children: spans),
    style: const TextStyle(fontSize: 13, color: TColors.amber900),
  ),
);

/// A bullet line inside a reverse dialog.
Widget bullet(String text, {Color color = TColors.slate700}) => Padding(
  padding: const EdgeInsets.only(bottom: 4),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('•  ', style: TextStyle(fontSize: 13, color: color)),
      Expanded(
        child: Text(text, style: TextStyle(fontSize: 13, color: color)),
      ),
    ],
  ),
);

const boldSpan = TextStyle(fontWeight: FontWeight.w700);

/// The selectable option card used for "Where the credit came from" / "What is it".
Widget kindOption({required bool selected, required String title, required String body, required VoidCallback onTap}) => Padding(
  padding: const EdgeInsets.only(bottom: 8),
  child: InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(6),
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: selected ? const Color(0x99EFF6FF) : null,
        border: Border.all(color: selected ? const Color(0xFF60A5FA) : TColors.slate200),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 18, color: selected ? TColors.blue600 : TColors.slate400),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: TColors.slate900),
                ),
                Text(body, style: const TextStyle(fontSize: 12, color: TColors.slate600)),
              ],
            ),
          ),
        ],
      ),
    ),
  ),
);

/// The grey summary line at the foot of a form ("X will hold …").
Widget summaryBox(List<InlineSpan> spans) => Container(
  padding: const EdgeInsets.all(10),
  decoration: BoxDecoration(color: TColors.slate50, borderRadius: BorderRadius.circular(6)),
  child: Text.rich(
    TextSpan(children: spans),
    style: const TextStyle(fontSize: 13, color: TColors.slate700),
  ),
);
